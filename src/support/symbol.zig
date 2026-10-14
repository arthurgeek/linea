//! The alphabet a symbol is spelled in, and how a byte outside it is written.
//!
//! A function's symbol carries the types it was instantiated with, and a type
//! is spelled for a reader rather than for an assembler: the unit type is
//! written `()`, which no emitted format reads as part of a name. Escaping rather than
//! refusing is what makes the spelling total -- every type a program can
//! instantiate has to have a symbol, or a well-typed program is one the backend
//! cannot name.

const std = @import("std");
const testing = std.testing;

const symbol = @This();

/// The digits an escape is spelled with, lower case because a symbol is
/// compared byte for byte and one spelling of a byte is enough.
const hex_digits = "0123456789abcdef";

/// What is written before every symbol this language defines, so nothing a
/// user can declare collides with a name the runtime owns: a program with a
/// function called `linea_trap` would otherwise emit calls that link
/// against the runtime's, and a trap that does not trap is the worst shape
/// of failure.
///
/// It sits beside the alphabet rather than at the one place that writes it,
/// because how long a name may be is what an identifier has left once this
/// is written before it. Two constants, one of them elsewhere, is a bound
/// that stops holding the day the prefix grows.
pub const defined_prefix = "lin.";

/// A bound on generated names, owned by nothing downstream: the emitted
/// formats read longer names without complaint. Kept because a name is
/// built by concatenation, and a concatenation with no ceiling turns a
/// deep instantiation into an unbounded symbol nobody can read -- the
/// bound is where that defect is caught, until a truncation policy owns
/// long names properly.
///
/// Sized for a reader, not a tool: what a symbol costs past this length is
/// legibility in a debugger and a profile, and what digesting costs is the
/// structure those tools would have shown. So the ceiling sits where an
/// ordinary instantiation never meets it and only a generated tower of
/// them does.
const identifier_max = 255;

/// The longest a mangled name may be.
pub const max_len = identifier_max - defined_prefix.len;

/// What a name too long to spell says in place of the structure it dropped.
///
/// `$` introduces an escape and an escape's first digit is hexadecimal, so
/// `$h` begins no escape and appears in no spelled name. That is what keeps
/// the two kinds of name apart: a shortened one can equal a spelled one
/// nowhere, whatever the two types were.
const digest_marker = ".$h";

/// A 64-bit digest, four bits a digit.
const digest_len = 16;

/// How much of the spelled structure a shortened name keeps.
const kept_max = max_len - digest_marker.len - digest_len;

/// Whether a byte is one a spelling carries into a symbol unchanged.
///
/// `_` is carried, so an ordinary name reaches the symbol table spelled the
/// way it was written: escaping it cost three bytes for every underscore in
/// every snake_case name, and made `write_str` read as `write_5fstr`.
/// Brackets and a comma are carried for a stronger reason -- they are what
/// an instantiation and an interpolation are written with, and escaping
/// them cost three bytes per level of a structure that nests without limit.
fn isPlain(c: u8) bool {
    return switch (c) {
        'A'...'Z', 'a'...'z', '0'...'9', '.', '_', '[', ']', ',', ';' => true,
        else => false,
    };
}

/// Whether every byte is one a symbol may hold. What the backend asks of a
/// name it is handed, rather than a second place that decides one.
///
/// What the set is held against is measured rather than assumed: a symbol
/// carrying every one of these was put through the emitter, `mlir-opt`,
/// `mlir-translate`, the assembler and the linker, and called at run time,
/// on ELF x86-64 and on Mach-O arm64. The set is therefore what this
/// pipeline accepts, not the narrower intersection of every tool's rules.
///
/// `;` is the one here that is safe for a reason rather than by being
/// unremarkable: it begins a comment in one of those assembler syntaxes and
/// separates statements in the other, and what makes it work is that the
/// backend emits a label quoted wherever the name needs it. So a route that
/// bypassed the integrated assembler is the one to doubt, not the character.
/// It is spelled at all because an array reads as the source writes it,
/// `[UInt8;2]`, and a component of digits and a letter said the same thing
/// while reading like neither.
pub fn holds(name: []const u8) bool {
    for (name) |c| switch (c) {
        'A'...'Z', 'a'...'z', '0'...'9', '.', '_', '[', ']', ',', ';', '$' => {},
        else => return false,
    };
    return true;
}

/// Appends a spelling, writing any byte a symbol does not carry plainly as
/// `$` and its two hexadecimal digits.
///
/// `$` is escaped as well, which is what makes the mapping injective and so
/// keeps two instantiations two symbols: `$` introduces an escape and
/// stands for itself nowhere, so a type named `$28$29` cannot collide with
/// the escape of `()`.
///
/// `$` rather than `_`, because the introducer is the one character a name
/// pays for twice and `_` is the one a name is full of. No identifier this
/// language accepts holds a `$`, so the character is free to mean this and
/// nothing else -- and an underscore reaches the symbol table as itself.
pub fn appendEscaped(
    gpa: std.mem.Allocator,
    out: *std.ArrayList(u8),
    text: []const u8,
) std.mem.Allocator.Error!void {
    for (text) |c| {
        if (isPlain(c)) try out.append(gpa, c) else try appendByteEscape(gpa, out, c);
    }
}

/// Appends `$` and the two hexadecimal digits of `c`.
pub fn appendByteEscape(gpa: std.mem.Allocator, out: *std.ArrayList(u8), c: u8) std.mem.Allocator.Error!void {
    // Written out rather than formatted into a buffer. A byte is two digits
    // and the escape is three bytes, so there is no width to get wrong and no
    // failure to dismiss -- and no dismissal that the distributed build,
    // compiled with safety off, would turn into an append from an undefined
    // slice.
    try out.appendSlice(gpa, &.{ '$', hex_digits[c >> 4], hex_digits[c & 0xf] });
}

/// Appends a module's route: the path from the root to the module's
/// directory, `/`-separated, written with a `.` between directory names and
/// every byte of a name that an identifier does not hold written as `$` and
/// its two hexadecimal digits.
///
/// A directory whose name is not an identifier, such as `my-lib` or `a.b`, is
/// a module no import can name, and it is still part of its program: its tests
/// run and its functions need symbols. A `.` inside a name is escaped like any
/// other such byte, so `a.b` is `a$2eb` and stays apart from the two
/// directories `a/b`, which are `a.b`. `$` is escaped as well, for the reason
/// `appendEscaped` escapes it, so the route is one spelling of one path.
pub fn appendRoute(
    gpa: std.mem.Allocator,
    out: *std.ArrayList(u8),
    relative_dir: []const u8,
) std.mem.Allocator.Error!void {
    for (relative_dir) |c| switch (c) {
        'A'...'Z', 'a'...'z', '0'...'9', '_' => try out.append(gpa, c),
        '/' => try out.append(gpa, '.'),
        else => try appendByteEscape(gpa, out, c),
    };
}

test "a route keeps a directory an identifier names, and escapes one it does not" {
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(testing.allocator);

    try symbol.appendRoute(testing.allocator, &out, "app/util_2");
    try testing.expectEqualStrings("app.util_2", out.items);

    out.clearRetainingCapacity();
    try symbol.appendRoute(testing.allocator, &out, "my-lib/led;ger$");
    try testing.expectEqualStrings("my$2dlib.led$3bger$24", out.items);

    // One directory with a dot in its name, and two directories.
    out.clearRetainingCapacity();
    try symbol.appendRoute(testing.allocator, &out, "a.b");
    try testing.expectEqualStrings("a$2eb", out.items);
    out.clearRetainingCapacity();
    try symbol.appendRoute(testing.allocator, &out, "a/b");
    try testing.expectEqualStrings("a.b", out.items);
}

/// How long the escaped form of a spelling is, without writing it.
fn escapedLen(text: []const u8) usize {
    var n: usize = 0;
    for (text) |c| n += if (isPlain(c)) 1 else 3;
    return n;
}

/// Appends a spelling as a symbol: escaped, and shortened to a digest where
/// the escaped form is longer than a symbol may be.
///
/// **Bound:** `max_len` bytes, for every spelling there is and so at every
/// nesting depth. A type is named by its structure, structure nests without
/// limit, and a level costs several bytes -- so a program the checker
/// accepts reaches a spelling no assembler will take, at a depth nothing in
/// the source marks. Spelling it verbatim overflows and cutting it at the
/// first bracket makes distinct types one name; keeping a prefix and
/// digesting the whole is the scheme with neither failure.
///
/// Injective in the same sense the escape is. Two shortened names are equal
/// only where the kept prefixes and the digests both are, and the digest
/// covers the whole spelling rather than the prefix -- so two structures
/// alike as far as the prefix reaches are still two symbols. That leaves
/// only a digest collision, which the module verifier answers for with a
/// status of its own rather than letting one body stand for two.
///
/// The seed is fixed and the algorithm is named here rather than taken from
/// anything the host decides. A symbol reaches an object file a linker
/// resolves against, and the recorded outcome of a compilation is keyed on
/// the emitted IR -- a name that varied between runs would make a build
/// unreproducible and every cached answer wrong.
pub fn appendBounded(
    gpa: std.mem.Allocator,
    out: *std.ArrayList(u8),
    text: []const u8,
) std.mem.Allocator.Error!void {
    if (escapedLen(text) <= max_len) return appendEscaped(gpa, out, text);

    // Whole escapes only. A prefix cut inside one still reads as a symbol
    // and no longer reads as a spelling, which is what the marker relies on
    // to be something no spelled name can hold.
    var written: usize = 0;
    var kept: usize = 0;
    while (kept < text.len) : (kept += 1) {
        const width: usize = if (isPlain(text[kept])) 1 else 3;
        if (written + width > kept_max) break;
        written += width;
    }
    try appendEscaped(gpa, out, text[0..kept]);

    try out.appendSlice(gpa, digest_marker);
    const digest = std.hash.Wyhash.hash(0, text);
    var at: usize = digest_len;
    while (at > 0) {
        at -= 1;
        const nibble: u4 = @truncate(digest >> @intCast(4 * at));
        try out.append(gpa, hex_digits[nibble]);
    }
}

test "a spelling an assembler cannot read is escaped, and distinctly" {
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(testing.allocator);

    // The spelling that reaches a symbol from `Opt[()]`, and the identifier a
    // program could write that would otherwise mangle to the same bytes.
    try symbol.appendEscaped(testing.allocator, &out, "Opt.()");
    try testing.expectEqualStrings("Opt.$28$29", out.items);
    try testing.expect(symbol.holds(out.items));

    out.clearRetainingCapacity();
    try symbol.appendEscaped(testing.allocator, &out, "Opt.$28$29");
    try testing.expectEqualStrings("Opt.$2428$2429", out.items);
    try testing.expect(symbol.holds(out.items));

    // What the introducer moved for: an underscore is carried, so an ordinary
    // name is spelled in the symbol table the way it was written.
    out.clearRetainingCapacity();
    try symbol.appendEscaped(testing.allocator, &out, "write_str");
    try testing.expectEqualStrings("write_str", out.items);
    try testing.expect(symbol.holds(out.items));

    // And what a structure is written with is carried too, so a level of
    // nesting costs one byte per delimiter rather than three.
    out.clearRetainingCapacity();
    try symbol.appendEscaped(testing.allocator, &out, "Opt[Pair[Str,Int64]]");
    try testing.expectEqualStrings("Opt[Pair[Str,Int64]]", out.items);
    try testing.expect(symbol.holds(out.items));
}

test "a spelling longer than a symbol may be keeps a prefix and a digest of the whole" {
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(testing.allocator);

    // Two structures alike as far as any prefix reaches, differing only past
    // where one stops. A scheme keeping the prefix alone spells one symbol for
    // both, which is two definitions of one name.
    //
    // Nested the way an instantiation nests, because that is the spelling that
    // reaches this bound: a level costs a bracket and a name, and nothing in
    // the source marks the depth at which the total stops fitting.
    // Deep enough to overflow whatever the bound is, worked out from the
    // bound rather than written as a count: a depth that merely cleared the
    // ceiling of the day broke the moment the ceiling moved, without saying
    // which of the two was wrong.
    const depth = symbol.max_len / "Envelope[".len + 1;
    const opened = "Envelope[" ** depth;
    const closed = "]" ** depth;
    try symbol.appendBounded(testing.allocator, &out, opened ++ "UInt8" ++ closed);
    const one = try testing.allocator.dupe(u8, out.items);
    defer testing.allocator.free(one);

    out.clearRetainingCapacity();
    try symbol.appendBounded(testing.allocator, &out, opened ++ "Bool" ++ closed);

    try testing.expect(one.len <= symbol.max_len);
    try testing.expect(out.items.len <= symbol.max_len);
    try testing.expect(symbol.holds(one));
    try testing.expect(symbol.holds(out.items));
    try testing.expect(!std.mem.eql(u8, one, out.items));
    // The prefix is the whole of what they share, so the digest is the whole of
    // what tells them apart.
    try testing.expectEqualStrings(one[0..symbol.kept_max], out.items[0..symbol.kept_max]);
}

test "a spelling a symbol has room for is spelled" {
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(testing.allocator);

    // Whatever the bound is, a name under it is the escape and nothing else --
    // a shortened name is what a spelling that does not fit says instead.
    const fits = "Cell.1.Opt.1.UInt8";
    try symbol.appendBounded(testing.allocator, &out, fits);
    try testing.expectEqualStrings(fits, out.items);

    out.clearRetainingCapacity();
    try symbol.appendBounded(testing.allocator, &out, "Opt.()");
    try testing.expectEqualStrings("Opt.$28$29", out.items);
}

test "a shortened name is a name no spelling produces" {
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(testing.allocator);

    // Sized from the bound, for the reason the digest test's depth is.
    const layers = "Layer.1." ** (symbol.max_len / "Layer.1.".len + 1);
    try symbol.appendBounded(testing.allocator, &out, layers ++ "UInt8");
    const shortened = try testing.allocator.dupe(u8, out.items);
    defer testing.allocator.free(shortened);

    // The marker is `_` and a byte that begins no escape, so a spelling of the
    // shortened name escapes the `_` and the two are two names. Which is what
    // says a program naming a type after one cannot take its symbol.
    out.clearRetainingCapacity();
    try symbol.appendBounded(testing.allocator, &out, shortened);
    try testing.expect(!std.mem.eql(u8, shortened, out.items));
    try testing.expect(std.mem.indexOf(u8, shortened, symbol.digest_marker) != null);
}

test "a symbol and what is written before it fit an identifier" {
    try testing.expect(symbol.defined_prefix.len + symbol.max_len <= symbol.identifier_max);
    try testing.expect(symbol.kept_max > 0);
}

test "a name an assembler can read is not a symbol byte away from one it cannot" {
    try testing.expect(symbol.holds("lin.ident.u8"));
    try testing.expect(symbol.holds("a_name_with_underscores"));
    try testing.expect(!symbol.holds("ident.()"));
    try testing.expect(!symbol.holds("ident.<unknown>"));
}
