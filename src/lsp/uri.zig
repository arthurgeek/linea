const std = @import("std");
const testing = std.testing;

const Analysis = @import("analysis.zig").Analysis;
const FileId = @import("../support/source.zig").FileId;

/// How the protocol names a file, and how this machine does.
///
/// A client never sends a path: it sends a `file://` URI, percent-encoded,
/// and expects one back. Everything inside the server works in paths, so the
/// conversion happens once at the door in each direction and nowhere else --
/// a second place that stripped a prefix or decoded an escape would be a
/// second answer to what file a message is about.
const scheme = "file://";

/// The unreserved set, plus the separator a path is built from. Every other
/// byte is escaped, which is what makes the encoding total: a path this
/// cannot spell does not exist.
fn isLiteral(byte: u8) bool {
    return switch (byte) {
        'A'...'Z', 'a'...'z', '0'...'9', '-', '.', '_', '~', '/' => true,
        else => false,
    };
}

fn hexDigit(c: u8) ?u4 {
    return switch (c) {
        '0'...'9' => @intCast(c - '0'),
        'a'...'f' => @intCast(c - 'a' + 10),
        'A'...'F' => @intCast(c - 'A' + 10),
        else => null,
    };
}

/// The filesystem path a URI names.
///
/// A URI with no scheme is returned as written. That is not a second dialect
/// but the protocol's own allowance for a client that sends a path where a
/// URI belongs: refusing it would turn a client's sloppiness into a server
/// that reports nothing, and accepting it costs one comparison.
///
/// An authority is dropped when it is empty or `localhost`, which are the two
/// spellings of "this machine". Any other host names a file this process
/// cannot open, so it is left in the path and fails as a missing file rather
/// than being silently read from somewhere local.
pub fn pathOf(gpa: std.mem.Allocator, uri: []const u8) ![]u8 {
    if (!std.mem.startsWith(u8, uri, scheme)) return gpa.dupe(u8, uri);

    var rest = uri[scheme.len..];
    if (std.mem.startsWith(u8, rest, "localhost/")) rest = rest["localhost".len..];

    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    try out.ensureTotalCapacity(gpa, rest.len);

    var i: usize = 0;
    while (i < rest.len) {
        // A `%` not followed by two hex digits is not an escape, and is kept
        // as the byte it is rather than refused: a path is being named, not
        // validated.
        if (rest[i] == '%' and i + 2 < rest.len) {
            if (hexDigit(rest[i + 1])) |hi| {
                if (hexDigit(rest[i + 2])) |lo| {
                    out.appendAssumeCapacity(@as(u8, hi) << 4 | lo);
                    i += 3;
                    continue;
                }
            }
        }
        out.appendAssumeCapacity(rest[i]);
        i += 1;
    }
    return out.toOwnedSlice(gpa);
}

/// The URI naming a path, which is what a client is told a diagnostic is
/// about.
pub fn uriOf(gpa: std.mem.Allocator, path: []const u8) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    try out.appendSlice(gpa, scheme);

    for (path) |byte| {
        if (isLiteral(byte)) {
            try out.append(gpa, byte);
        } else {
            try out.print(gpa, "%{X:0>2}", .{byte});
        }
    }
    return out.toOwnedSlice(gpa);
}

/// The URI a client can open a file of the checked module at, or null where
/// there is none.
///
/// A file the editor opened is named by the absolute path its URI carried, and
/// needs nothing. The standard library is carried inside the binary and named
/// by the path it was written at -- `std/text/str.lin`, relative to
/// wherever the library's source sits -- so a URI built from it names a file
/// no client can open.
///
/// Resolved against the workspace, which is where that source is when the
/// workspace is the compiler's own checkout. Anywhere else the file is not
/// there, and answering nothing is the honest result: a location a client
/// cannot follow is worse than no location, because the failure surfaces as
/// the editor's rather than the server's.
///
/// The file found there has to be the file that was compiled, and the only
/// thing that establishes it is its text. A path is a name a workspace is free
/// to reuse -- `std/` is an ordinary directory for a project -- and the range
/// travelling beside this URI is measured in the library's own bytes, so a
/// client sent to a file holding anything else lands at a position that file
/// does not have. That is worse than the answer this exists to avoid, because
/// the editor opens the file and shows the wrong place rather than failing.
///
/// Whether a file is the library's is what the loader recorded, asked rather
/// than guessed from the shape of the path -- a rule reading the shape would
/// be answering where the library happens to live.
///
/// Asked here rather than by each capability that reports a location, because
/// two of them do and a second reading would offer a file one of them refuses.
///
/// Costs one read of the named file, and only for a library one: a file the
/// editor opened is named by the path its URI carried and is read not at all.
pub fn openable(
    gpa: std.mem.Allocator,
    io: std.Io,
    checked: *const Analysis,
    file: FileId,
    /// The directory the client opened, which the library's source sits under
    /// when the workspace is the compiler's own checkout.
    root: []const u8,
) !?[]u8 {
    const path = checked.table.get(file).path;
    if (!checked.library[file.index()]) return try uriOf(gpa, path);

    const joined = if (root.len == 0)
        try gpa.dupe(u8, path)
    else
        try std.fs.path.join(gpa, &.{ root, path });
    defer gpa.free(joined);

    const there = std.Io.Dir.cwd().readFileAlloc(io, joined, gpa, .limited(1 << 22)) catch return null;
    defer gpa.free(there);

    if (!std.mem.eql(u8, there, checked.table.get(file).text)) return null;
    return try uriOf(gpa, joined);
}

test "a URI names the path it was built from" {
    const path = "/srv/code/main.lin";
    const uri = try uriOf(testing.allocator, path);
    defer testing.allocator.free(uri);
    try testing.expectEqualStrings("file:///srv/code/main.lin", uri);

    const back = try pathOf(testing.allocator, uri);
    defer testing.allocator.free(back);
    try testing.expectEqualStrings(path, back);
}

test "a path a shell would quote survives the round trip" {
    // The bytes an editor actually sends and nothing here may mangle: a
    // space, a character outside ASCII, and the escape character itself.
    const path = "/tmp/a dir/caf\u{00E9}/100% done.lin";
    const uri = try uriOf(testing.allocator, path);
    defer testing.allocator.free(uri);
    try testing.expectEqualStrings("file:///tmp/a%20dir/caf%C3%A9/100%25%20done.lin", uri);

    const back = try pathOf(testing.allocator, uri);
    defer testing.allocator.free(back);
    try testing.expectEqualStrings(path, back);
}

test "the two spellings of this machine name the same file" {
    const plain = try pathOf(testing.allocator, "file:///src/main.lin");
    defer testing.allocator.free(plain);
    const local = try pathOf(testing.allocator, "file://localhost/src/main.lin");
    defer testing.allocator.free(local);
    try testing.expectEqualStrings(plain, local);
}

test "a path arriving where a URI belongs is the path it spells" {
    const path = try pathOf(testing.allocator, "main.lin");
    defer testing.allocator.free(path);
    try testing.expectEqualStrings("main.lin", path);
}

test "an incomplete escape is a byte, not a refusal" {
    const path = try pathOf(testing.allocator, "file:///tmp/50%.lin");
    defer testing.allocator.free(path);
    try testing.expectEqualStrings("/tmp/50%.lin", path);
}
