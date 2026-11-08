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
const slow_tests = @import("../support/slow_tests.zig");
const builtin = @import("builtin");
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
/// The most entries the directory keeps: writing one removes the least
/// recently used beyond this many, so a compiler rebuilt many times leaves
/// this many behind. An entry is one set of library modules; the corpus's
/// cases import some fifty-five sets, and an entry averages about 21 MB, so
/// the directory stays under some 1.4 GB.
const kept_entries = 64;

/// Where the cache lives, allocated in `gpa`, or null where it is turned off or
/// `HOME` is not set.
pub fn directory(gpa: std.mem.Allocator, environ: std.process.Environ) std.mem.Allocator.Error!?[]const u8 {
    if (environ.getPosix(directory_variable)) |named| return if (named.len == 0) null else try gpa.dupe(u8, named);
    const home = environ.getPosix("HOME") orelse return null;
    if (home.len == 0) return null;
    return try std.fs.path.join(gpa, &.{ home, default_directory });
}

/// The checked library for this compiler: read from the cache in `dir`, or
/// checked and written there. Null where this compiler has no key or the
/// cache cannot be written, and the command compiles as it would without a
/// cache: checking every library module only to keep nothing costs more than
/// the command saves.
///
/// `modules` are the library modules beside the prelude's closure the
/// library holds (`loader.resumableLibraryOf`), and the entry is keyed by
/// them as well as by the compiler: a program resumes only from a library
/// holding exactly the modules a fresh load of it loads.
pub fn open(gpa: std.mem.Allocator, io: std.Io, dir: []const u8, modules: []const []const u8) !?*CheckedLibrary {
    const compiler = compilerIdentity() orelse return null;
    var hasher = Sha256.init(.{});
    hasher.update(&compiler);
    for (modules) |module| {
        hasher.update(module);
        hasher.update(&.{0});
    }
    return openKeyed(gpa, io, dir, hasher.finalResult(), modules);
}

/// The checked library holding the prelude's closure and `modules`: read
/// from or written to the cache `environ` names, as a command would, or
/// checked in this process where there is no usable cache.
pub fn checkedFor(gpa: std.mem.Allocator, io: std.Io, environ: std.process.Environ, modules: []const []const u8) !*CheckedLibrary {
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    if (try directory(arena.allocator(), environ)) |dir| {
        if (try open(gpa, io, dir, modules)) |library| return library;
    }
    return CheckedLibrary.initFor(gpa, modules);
}

fn openKeyed(gpa: std.mem.Allocator, io: std.Io, dir: []const u8, key: Digest, modules: []const []const u8) !?*CheckedLibrary {
    return openWaiting(gpa, io, dir, key, modules, lock_wait_ns);
}

/// How long a command waits for another checking the same entry before it
/// checks the library itself without the cache: what a Debug compiler takes
/// to check a large set of modules, well short of a command that seems hung.
const lock_wait_ns: i96 = 60 * std.time.ns_per_s;

/// `openKeyed`, holding the entry's lock while it checks the library, so of
/// several commands missing one entry at once one checks and writes it and
/// the others wait and read it. The lock is an advisory lock on `NAME.lock`,
/// which the system releases when its holder exits, however it exits; a
/// command that waits says so once on a terminal, and after `wait_ns`
/// checks without the cache.
fn openWaiting(gpa: std.mem.Allocator, io: std.Io, dir: []const u8, key: Digest, modules: []const []const u8, wait_ns: i96) !?*CheckedLibrary {
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const scratch = arena.allocator();
    const name = try entryName(scratch, key);
    if (try readDecoded(gpa, scratch, io, dir, name, key)) |library| return library;
    // The lock is made before the library is checked, so a cache that
    // cannot be written is known before that cost.
    var cache = std.Io.Dir.cwd().createDirPathOpen(io, dir, .{ .open_options = .{ .iterate = true } }) catch return null;
    defer cache.close(io);
    const lock_name = try std.fmt.allocPrint(scratch, "{s}.lock", .{name});
    const lock = cache.createFile(io, lock_name, .{ .truncate = false }) catch return null;
    defer lock.close(io);
    if (!(lock.tryLock(io, .exclusive) catch return null)) {
        // Said to a person watching, never into captured output, where
        // whether a command waited depends on how commands raced.
        if (std.Io.File.stderr().isTty(io) catch false) std.debug.print("linea: waiting for another command to check the standard library into {s}\n", .{dir});
        const began = std.Io.Timestamp.now(io, .awake);
        while (true) {
            io.sleep(.fromMilliseconds(50), .awake) catch {};
            if (try readDecoded(gpa, scratch, io, dir, name, key)) |library| return library;
            if (lock.tryLock(io, .exclusive) catch return null) break;
            if (began.durationTo(std.Io.Timestamp.now(io, .awake)).nanoseconds > wait_ns) return null;
        }
    }
    defer lock.unlock(io);
    // The holder this command waited on may have written it just before.
    if (try readDecoded(gpa, scratch, io, dir, name, key)) |library| return library;
    const library = CheckedLibrary.initFor(gpa, modules) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return null,
    };
    errdefer library.deinit();
    const payload = try encoding.encode(scratch, library);
    // A write that fails after the check leaves the checked library this
    // command already holds.
    write(io, cache, scratch, name, key, payload) catch return library;
    evict(io, cache) catch {};
    return library;
}

/// The library the entry `name` holds, or null where it is missing or
/// damaged. An entry read is touched, so the entries kept are the ones used.
fn readDecoded(gpa: std.mem.Allocator, scratch: std.mem.Allocator, io: std.Io, dir: []const u8, name: []const u8, key: Digest) !?*CheckedLibrary {
    const payload = read(scratch, io, dir, name, key) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return null,
    };
    const library = encoding.decode(gpa, payload) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.Corrupt => return null,
    };
    touch: {
        var cache = std.Io.Dir.cwd().openDir(io, dir, .{}) catch break :touch;
        defer cache.close(io);
        const file = cache.openFile(io, name, .{ .mode = .read_write }) catch break :touch;
        defer file.close(io);
        file.setTimestampsNow(io) catch {};
    }
    return library;
}

fn currentProcess() std.posix.pid_t {
    return if (builtin.os.tag == .linux and !builtin.link_libc) std.os.linux.getpid() else std.c.getpid();
}

fn entryName(gpa: std.mem.Allocator, key: Digest) std.mem.Allocator.Error![]const u8 {
    return std.fmt.allocPrint(gpa, "{s}{x}", .{ entry_prefix, key });
}

/// The SHA-256 of the running compiler's own read-only image as it is mapped
/// in memory: its code and constant data, the standard library it carries
/// included. Read from the process rather than from the file at its path,
/// which another compiler may have replaced since this one started. Null on a
/// platform this does not read, where the cache is not used.
fn compilerIdentity() ?Digest {
    var hasher = Sha256.init(.{});
    switch (builtin.os.tag) {
        .macos => {
            const header: *const std.macho.mach_header_64 = @ptrCast(@alignCast(std.c._dyld_get_image_header(0) orelse return null));
            const slide = std.c._dyld_get_image_vmaddr_slide(0);
            var command: [*]const u8 = @ptrCast(header);
            command += @sizeOf(std.macho.mach_header_64);
            var hashed = false;
            for (0..header.ncmds) |_| {
                const load: *align(1) const std.macho.load_command = @ptrCast(command);
                if (load.cmd == .SEGMENT_64) {
                    const segment: std.macho.segment_command_64 = @as(*align(1) const std.macho.segment_command_64, @ptrCast(command)).*;
                    // The writable segments hold pointers the loader fixes up
                    // for wherever the image was placed, and `__LINKEDIT`
                    // holds symbols and the signature's bytes. Re-signing
                    // still changes the key: the load commands at the start
                    // of `__TEXT` record the signature's size.
                    if (!segment.initprot.WRITE and segment.filesize != 0 and !std.mem.eql(u8, segment.segName(), "__LINKEDIT")) {
                        const start: [*]const u8 = @ptrFromInt(segment.vmaddr + slide);
                        hasher.update(start[0..segment.filesize]);
                        hashed = true;
                    }
                }
                command += load.cmdsize;
            }
            if (!hashed) return null;
        },
        .linux => {
            const Image = struct {
                hasher: *Sha256,
                hashed: bool = false,
                fn segments(info: *std.posix.dl_phdr_info, _: usize, image: *@This()) error{Done}!void {
                    // The first object is the executable itself.
                    for (info.phdr[0..info.phnum]) |phdr| {
                        if (phdr.type != .LOAD or phdr.flags.W or phdr.filesz == 0) continue;
                        const start: [*]const u8 = @ptrFromInt(info.addr + phdr.vaddr);
                        image.hasher.update(start[0..phdr.filesz]);
                        image.hashed = true;
                    }
                    return error.Done;
                }
            };
            var image: Image = .{ .hasher = &hasher };
            std.posix.dl_iterate_phdr(&image, error{Done}, Image.segments) catch {};
            if (!image.hashed) return null;
        },
        else => return null,
    }
    return hasher.finalResult();
}

test "the compiler is keyed by its own image, alike every time it is read" {
    const first = compilerIdentity() orelse return error.SkipZigTest;
    try testing.expectEqualSlices(u8, &first, &compilerIdentity().?);
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

/// Writes the entry `name` through `NAME.PID.tmp`, renamed over it, so a
/// reader sees a whole entry or none.
fn write(io: std.Io, cache: std.Io.Dir, scratch: std.mem.Allocator, name: []const u8, key: Digest, payload: []const u8) !void {
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
    const temporary = try std.fmt.allocPrint(scratch, "{s}.{d}.tmp", .{ name, currentProcess() });
    errdefer cache.deleteFile(io, temporary) catch {};
    {
        const file = try cache.createFile(io, temporary, .{});
        defer file.close(io);
        try file.writeStreamingAll(io, &header);
        try file.writeStreamingAll(io, payload);
    }
    try std.Io.Dir.rename(cache, temporary, cache, name, io);
}

/// Removes the oldest entries beyond `kept_entries`, and files an interrupted
/// write left behind.
fn evict(io: std.Io, cache: std.Io.Dir) !void {
    const Entry = struct { name: [entry_prefix.len + 2 * Sha256.digest_length]u8, modified: i96 };
    var entries: [kept_entries + 1]Entry = undefined;
    var count: usize = 0;
    const now = std.Io.Timestamp.now(io, .real).nanoseconds;
    var it = cache.iterate();
    while (try it.next(io)) |entry| {
        // What a command stopped while writing an entry left behind, an
        // hour on, and the lock of an entry that is gone, where no command
        // holds it.
        if (entry.kind == .file and std.mem.startsWith(u8, entry.name, entry_prefix)) {
            if (std.mem.endsWith(u8, entry.name, ".tmp")) {
                const stat = cache.statFile(io, entry.name, .{}) catch continue;
                if (now - stat.mtime.nanoseconds > std.time.ns_per_hour) cache.deleteFile(io, entry.name) catch {};
                continue;
            }
            if (std.mem.endsWith(u8, entry.name, ".lock")) {
                const of = entry.name[0 .. entry.name.len - ".lock".len];
                if (cache.statFile(io, of, .{})) |_| continue else |_| {}
                const lock = cache.openFile(io, entry.name, .{ .mode = .read_write }) catch continue;
                defer lock.close(io);
                if (lock.tryLock(io, .exclusive) catch false) {
                    defer lock.unlock(io);
                    cache.deleteFile(io, entry.name) catch {};
                }
                continue;
            }
        }
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

test "slow: checked library cache: a missing, damaged or foreign entry is checked again and rewritten" {
    try slow_tests.skipUnlessRun();
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    const dir = try std.fmt.allocPrint(testing.allocator, ".zig-cache/tmp/{s}", .{tmp.sub_path});
    defer testing.allocator.free(dir);
    const key: Digest = @splat(7);
    const name = try entryName(testing.allocator, key);
    defer testing.allocator.free(name);

    // Missing: checked and written.
    const first = (try openKeyed(testing.allocator, testing.io, dir, key, &.{})).?;
    const expected = try encoding.encode(testing.allocator, first);
    defer testing.allocator.free(expected);
    first.deinit();
    const written = try tmp.dir.readFileAlloc(testing.io, name, testing.allocator, .unlimited);
    defer testing.allocator.free(written);
    try testing.expectEqualSlices(u8, expected, payloadOf(written, key).?);

    // Present: read back, and the same library.
    const second = (try openKeyed(testing.allocator, testing.io, dir, key, &.{})).?;
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
        const library = (try openKeyed(testing.allocator, testing.io, dir, key, &.{})).?;
        library.deinit();
        const rewritten = try tmp.dir.readFileAlloc(testing.io, name, testing.allocator, .unlimited);
        defer testing.allocator.free(rewritten);
        try testing.expectEqualSlices(u8, written, rewritten);
    }
}

test "checked library cache: a held lock is waited on, a released one taken, and one left behind holds nothing" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    const dir = try std.fmt.allocPrint(testing.allocator, ".zig-cache/tmp/{s}", .{tmp.sub_path});
    defer testing.allocator.free(dir);
    const key: Digest = @splat(9);
    const name = try entryName(testing.allocator, key);
    defer testing.allocator.free(name);
    const lock_name = try std.fmt.allocPrint(testing.allocator, "{s}.lock", .{name});
    defer testing.allocator.free(lock_name);

    // A lock file another command left behind, naming anything, holds no
    // command: only a held lock does.
    try tmp.dir.writeFile(testing.io, .{ .sub_path = lock_name, .data = "1" });
    const first = (try openWaiting(testing.allocator, testing.io, dir, key, &.{}, lock_wait_ns)).?;
    first.deinit();

    // Held by another: the command waits, then checks without the cache.
    try tmp.dir.deleteFile(testing.io, name);
    const held = try tmp.dir.openFile(testing.io, lock_name, .{ .mode = .read_write });
    defer held.close(testing.io);
    try testing.expect(try held.tryLock(testing.io, .exclusive));
    try testing.expect(try openWaiting(testing.allocator, testing.io, dir, key, &.{}, 100 * std.time.ns_per_ms) == null);
    try testing.expectError(error.FileNotFound, tmp.dir.statFile(testing.io, name, .{}));

    // Released: the command takes it and writes the entry.
    held.unlock(testing.io);
    const second = (try openWaiting(testing.allocator, testing.io, dir, key, &.{}, lock_wait_ns)).?;
    second.deinit();
    _ = try tmp.dir.statFile(testing.io, name, .{});
}

test "checked library cache: of commands missing one entry at once, one writes it and the others read it" {
    var tmp = testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    const dir = try std.fmt.allocPrint(testing.allocator, ".zig-cache/tmp/{s}", .{tmp.sub_path});
    defer testing.allocator.free(dir);
    const Opener = struct {
        dir: []const u8,
        result: ?*CheckedLibrary = null,
        fn run(self: *@This()) void {
            self.result = openKeyed(testing.allocator, testing.io, self.dir, @splat(5), &.{}) catch null;
        }
    };
    var openers: [3]Opener = .{ .{ .dir = dir }, .{ .dir = dir }, .{ .dir = dir } };
    var threads: [3]std.Thread = undefined;
    for (&threads, &openers) |*thread, *opener| thread.* = try std.Thread.spawn(.{}, Opener.run, .{opener});
    for (threads) |thread| thread.join();
    var encodings: [3][]u8 = undefined;
    for (&openers, &encodings) |opener, *bytes| {
        const library = opener.result.?;
        bytes.* = try encoding.encode(testing.allocator, library);
        library.deinit();
    }
    defer for (encodings) |bytes| testing.allocator.free(bytes);
    for (encodings[1..]) |bytes| try testing.expectEqualSlices(u8, encodings[0], bytes);
    // The entry and its lock, and no temporary file left behind.
    var count: usize = 0;
    var it = tmp.dir.iterate();
    while (try it.next(testing.io)) |entry| {
        try testing.expect(!std.mem.endsWith(u8, entry.name, ".tmp"));
        count += 1;
    }
    try testing.expectEqual(@as(usize, 2), count);
}

test "checked library cache: a cache that cannot be written is not used, and the library is not checked for it" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    // A file where the directory should be.
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "cache", .data = "" });
    const dir = try std.fmt.allocPrint(testing.allocator, ".zig-cache/tmp/{s}/cache", .{tmp.sub_path});
    defer testing.allocator.free(dir);
    try testing.expect(try openKeyed(testing.allocator, testing.io, dir, @splat(7), &.{}) == null);
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
