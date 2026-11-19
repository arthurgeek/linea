//! Lists every symbol the runtime's objects call without defining, for every
//! target the runtime is built for: `runtime_imports OUT OBJECT...` writes the
//! union, one name per line, sorted. Each object is ELF or Mach-O, and a name
//! is written as C spells it: without the `_` Mach-O puts before every C
//! symbol, and without an ELF symbol version such as `@GLIBC_2.2.5`. So an
//! export the compiler refuses for colliding with a runtime import is refused
//! on every target alike.

const std = @import("std");

pub fn main(init: std.process.Init) !void {
    // Everything lives until the process ends, so the arena frees it.
    const gpa = init.arena.allocator();
    const io = init.io;
    const args = try init.minimal.args.toSlice(gpa);
    if (args.len < 2) return error.MissingOutput;
    const out_path = args[1];

    var names: std.StringArrayHashMapUnmanaged(void) = .empty;
    for (args[2..]) |path| {
        const bytes = try std.Io.Dir.cwd().readFileAlloc(io, path, gpa, .limited(256 << 20));
        try collect(gpa, bytes, &names);
    }

    const sorted = try gpa.dupe([]const u8, names.keys());
    std.mem.sort([]const u8, sorted, {}, lessThan);
    var listing: std.ArrayList(u8) = .empty;
    for (sorted) |name| {
        try listing.appendSlice(gpa, name);
        try listing.append(gpa, '\n');
    }
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = out_path, .data = listing.items });
}

fn lessThan(_: void, a: []const u8, b: []const u8) bool {
    return std.mem.lessThan(u8, a, b);
}

/// Adds to `names` every undefined external symbol of the object `bytes`.
fn collect(gpa: std.mem.Allocator, bytes: []const u8, names: *std.StringArrayHashMapUnmanaged(void)) !void {
    if (bytes.len >= 4 and std.mem.eql(u8, bytes[0..4], "\x7fELF")) return collectElf(gpa, bytes, names);
    if (bytes.len >= 4 and std.mem.readInt(u32, bytes[0..4], .little) == 0xfeedfacf) return collectMachO(gpa, bytes, names);
    return error.UnknownObjectFormat;
}

fn add(gpa: std.mem.Allocator, names: *std.StringArrayHashMapUnmanaged(void), spelled: []const u8) !void {
    if (spelled.len == 0) return;
    if (names.contains(spelled)) return;
    try names.put(gpa, try gpa.dupe(u8, spelled), {});
}

/// The name C spells for an ELF symbol: the symbol without its version.
fn elfName(symbol: []const u8) []const u8 {
    return symbol[0 .. std.mem.indexOfScalar(u8, symbol, '@') orelse symbol.len];
}

/// The name C spells for a Mach-O symbol: the symbol without the `_` Mach-O
/// writes before every C name.
fn machOName(symbol: []const u8) []const u8 {
    return if (std.mem.startsWith(u8, symbol, "_")) symbol[1..] else symbol;
}

test "a symbol is named as C spells it" {
    try std.testing.expectEqualStrings("read", elfName("read@GLIBC_2.2.5"));
    try std.testing.expectEqualStrings("free", elfName("free"));
    try std.testing.expectEqualStrings("free", machOName("_free"));
    try std.testing.expectEqualStrings("_error", machOName("__error"));
}

fn cString(bytes: []const u8, at: usize) ![]const u8 {
    if (at >= bytes.len) return error.MalformedObject;
    const end = std.mem.indexOfScalarPos(u8, bytes, at, 0) orelse return error.MalformedObject;
    return bytes[at..end];
}

fn slice(bytes: []const u8, at: u64, len: u64) ![]const u8 {
    if (at > bytes.len or len > bytes.len - at) return error.MalformedObject;
    return bytes[@intCast(at)..][0..@intCast(len)];
}

/// An ELF64 little-endian object's symbol table: a symbol whose section is
/// `SHN_UNDEF` with a global or weak binding is one the object calls.
fn collectElf(gpa: std.mem.Allocator, bytes: []const u8, names: *std.StringArrayHashMapUnmanaged(void)) !void {
    if (bytes.len < 64 or bytes[4] != 2 or bytes[5] != 1) return error.UnsupportedElf;
    const shoff = std.mem.readInt(u64, bytes[0x28..][0..8], .little);
    const shentsize = std.mem.readInt(u16, bytes[0x3a..][0..2], .little);
    const shnum = std.mem.readInt(u16, bytes[0x3c..][0..2], .little);
    for (0..shnum) |i| {
        const header = try slice(bytes, shoff + i * shentsize, 64);
        const sh_type = std.mem.readInt(u32, header[4..8], .little);
        if (sh_type != 2) continue; // SHT_SYMTAB
        const offset = std.mem.readInt(u64, header[0x18..][0..8], .little);
        const size = std.mem.readInt(u64, header[0x20..][0..8], .little);
        const link = std.mem.readInt(u32, header[0x28..][0..4], .little);
        const entsize = std.mem.readInt(u64, header[0x38..][0..8], .little);
        if (entsize < 24) return error.MalformedObject;
        const strings_header = try slice(bytes, shoff + @as(u64, link) * shentsize, 64);
        const strings_offset = std.mem.readInt(u64, strings_header[0x18..][0..8], .little);
        const strings_size = std.mem.readInt(u64, strings_header[0x20..][0..8], .little);
        const strings = try slice(bytes, strings_offset, strings_size);
        const table = try slice(bytes, offset, size);
        var at: usize = 0;
        while (at + 24 <= table.len) : (at += @intCast(entsize)) {
            const symbol = table[at..][0..24];
            const name = std.mem.readInt(u32, symbol[0..4], .little);
            const binding = symbol[4] >> 4;
            const section = std.mem.readInt(u16, symbol[6..8], .little);
            if (section != 0 or (binding != 1 and binding != 2)) continue;
            try add(gpa, names, elfName(try cString(strings, name)));
        }
    }
}

/// A 64-bit Mach-O object's `LC_SYMTAB`: an external symbol of type
/// `N_UNDF` with no value is one the object calls (a value would make it a
/// common symbol, which the object defines).
fn collectMachO(gpa: std.mem.Allocator, bytes: []const u8, names: *std.StringArrayHashMapUnmanaged(void)) !void {
    if (bytes.len < 32) return error.MalformedObject;
    const ncmds = std.mem.readInt(u32, bytes[16..20], .little);
    var at: usize = 32;
    for (0..ncmds) |_| {
        const command = try slice(bytes, at, 8);
        const cmd = std.mem.readInt(u32, command[0..4], .little);
        const cmdsize = std.mem.readInt(u32, command[4..8], .little);
        if (cmdsize < 8) return error.MalformedObject;
        if (cmd == 0x2) { // LC_SYMTAB
            const symtab = try slice(bytes, at, 24);
            const symoff = std.mem.readInt(u32, symtab[8..12], .little);
            const nsyms = std.mem.readInt(u32, symtab[12..16], .little);
            const stroff = std.mem.readInt(u32, symtab[16..20], .little);
            const strsize = std.mem.readInt(u32, symtab[20..24], .little);
            const strings = try slice(bytes, stroff, strsize);
            const table = try slice(bytes, symoff, @as(u64, nsyms) * 16);
            for (0..nsyms) |i| {
                const symbol = table[i * 16 ..][0..16];
                const strx = std.mem.readInt(u32, symbol[0..4], .little);
                const n_type = symbol[4];
                const value = std.mem.readInt(u64, symbol[8..16], .little);
                const stab = n_type & 0xe0 != 0;
                const external = n_type & 0x01 != 0;
                const undefined_symbol = n_type & 0x0e == 0;
                if (stab or !external or !undefined_symbol or value != 0) continue;
                try add(gpa, names, machOName(try cString(strings, strx)));
            }
        }
        at += cmdsize;
    }
}
