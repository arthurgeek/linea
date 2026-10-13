const std = @import("std");

/// The indefinite article a name is read with in a report: "an" before
/// `Int64`, `Option[T]` and `iter.Filter`, "a" before `UInt8`, `Unit` and
/// `String`.
///
/// The article follows the sound the name starts with, read from its first
/// letter; a bracket or other punctuation in front of it is not read aloud.
/// A leading `U` sounds like "you" in `UInt8`, `Unit` and `Utf8`, so it takes
/// "a" there and "an" elsewhere, as in `Unknown`. A name that is one letter
/// is read as that letter: "an `F`", "a `T`". The rule reads spelling, not
/// sound, so a name whose first letter is pronounced otherwise -- `Euro`,
/// `One`, `Hour`, an initialism such as `URL` or `HTTP` -- takes the article
/// its spelling suggests.
pub fn before(name: []const u8) []const u8 {
    const at = for (name, 0..) |c, i| {
        if (std.ascii.isAlphabetic(c)) break i;
    } else return "a";
    const first = std.ascii.toLower(name[at]);
    const rest = name[at + 1 ..];
    if (rest.len == 0 or !std.ascii.isAlphanumeric(rest[0])) {
        return if (std.mem.indexOfScalar(u8, "aefhilmnorsx", first) != null) "an" else "a";
    }
    return switch (first) {
        'a', 'e', 'i', 'o' => "an",
        'u' => if (soundsLikeYou(rest)) "a" else "an",
        else => "a",
    };
}

test "a name starting with a vowel sound takes an" {
    try std.testing.expectEqualStrings("an", before("Int64"));
    try std.testing.expectEqualStrings("an", before("Option[UInt8]"));
    try std.testing.expectEqualStrings("an", before("iter.Filter[Protocol, <closure>]"));
    try std.testing.expectEqualStrings("an", before("enum"));
    try std.testing.expectEqualStrings("an", before("Unknown"));
}

test "a name starting with a consonant sound takes a" {
    try std.testing.expectEqualStrings("a", before("UInt8"));
    try std.testing.expectEqualStrings("a", before("Unit"));
    try std.testing.expectEqualStrings("a", before("Utf8"));
    try std.testing.expectEqualStrings("a", before("String"));
    try std.testing.expectEqualStrings("a", before("mem.Slice[Str]"));
    try std.testing.expectEqualStrings("a", before("struct"));
}

test "punctuation in front of a name is not read" {
    try std.testing.expectEqualStrings("an", before("[Int64; 3]"));
    try std.testing.expectEqualStrings("a", before("(UInt8, Bool)"));
    try std.testing.expectEqualStrings("an", before("<unknown>"));
    try std.testing.expectEqualStrings("a", before(""));
}

test "a one-letter name is read as its letter" {
    try std.testing.expectEqualStrings("an", before("F"));
    try std.testing.expectEqualStrings("an", before("S"));
    try std.testing.expectEqualStrings("a", before("T"));
    try std.testing.expectEqualStrings("a", before("U"));
    try std.testing.expectEqualStrings("an", before("A"));
}

/// Whether a name starting with `u` and continuing with `rest` starts with
/// the sound "you": `UInt`, `Unit`, `Universe`, `Use`, `Utf8`.
fn soundsLikeYou(rest: []const u8) bool {
    const prefixes = [_][]const u8{ "in", "ni", "se", "sa", "su", "ti", "tf" };
    for (prefixes) |prefix| {
        if (rest.len >= prefix.len and std.ascii.eqlIgnoreCase(rest[0..prefix.len], prefix)) return true;
    }
    return false;
}
