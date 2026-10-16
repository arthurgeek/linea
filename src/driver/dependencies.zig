//! What a manifest writes under `dependencies`, read with the byte spans an
//! entry is written at, so a refused dependency is reported on the line that
//! names it.
//!
//! ```json
//! { "dependencies": { "sqlite": { "path": "../sqlite", "extern": true } } }
//! ```
//!
//! The rest of the manifest is read by `loader.Written`; this reads the one key
//! whose problems are reported against the manifest's text.
const std = @import("std");
const testing = std.testing;
const Span = @import("../support/span.zig").Span;

/// One entry of a manifest's `dependencies` object.
pub const Entry = struct {
    /// The key: the name every import of the library starts with.
    name: []const u8,
    /// Where the key is written, quotes included.
    key: Span,
    /// The directory holding the library's manifest, relative to the manifest
    /// that writes it, or null where the entry writes none.
    path: ?[]const u8 = null,
    /// Where the `path` value is written, or the key where there is none.
    path_at: Span,
    /// Whether the manifest consents to the library declaring `extern`
    /// functions.
    consents_to_extern: bool = false,
    /// Why the entry cannot be read, where it cannot.
    problem: ?Problem = null,
};

/// Why a value cannot be read, with where it is written and what to write
/// instead.
pub const Problem = struct {
    at: Span,
    message: []const u8,
    label: []const u8 = "write `{ \"name\": { \"path\": \"directory\" } }`",
};

pub const Written = struct {
    entries: []const Entry = &.{},
    /// A `dependencies` key whose value is not an object.
    problem: ?Problem = null,
};

/// The `dependencies` a manifest writes, or null where the text is not a JSON
/// object (a manifest that will not parse is reported by the reader that read
/// it as one).
///
/// Strings are borrowed from `text` where they hold no escape and allocated in
/// `arena` where they do.
pub fn read(arena: std.mem.Allocator, text: []const u8) std.mem.Allocator.Error!?Written {
    var scanner = std.json.Scanner.initCompleteInput(arena, text);
    defer scanner.deinit();
    return readFrom(arena, text, &scanner) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return null,
    };
}

const ReadError = std.mem.Allocator.Error || std.json.Scanner.NextError || std.json.Scanner.SkipError || std.json.Scanner.AllocError || std.json.Scanner.PeekError || error{NotAnObject};

fn readFrom(arena: std.mem.Allocator, text: []const u8, scanner: *std.json.Scanner) ReadError!Written {
    if (try scanner.next() != .object_begin) return error.NotAnObject;
    var written: Written = .{};
    while (true) {
        const key = try scanner.nextAlloc(arena, .alloc_if_needed);
        const name = switch (key) {
            .object_end => break,
            .string, .allocated_string => |s| s,
            else => return error.NotAnObject,
        };
        if (!std.mem.eql(u8, name, "dependencies")) {
            try scanner.skipValue();
            continue;
        }
        const value_start = scanner.cursor;
        if (try scanner.peekNextTokenType() != .object_begin) {
            try scanner.skipValue();
            written.problem = .{
                .at = trimmed(text, value_start, scanner.cursor),
                .message = "`dependencies` is an object from each library's name to where it is",
            };
            continue;
        }
        written.entries = try readEntries(arena, text, scanner);
    }
    return written;
}

fn readEntries(arena: std.mem.Allocator, text: []const u8, scanner: *std.json.Scanner) ReadError![]const Entry {
    _ = try scanner.next();
    var entries: std.ArrayList(Entry) = .empty;
    while (true) {
        const key = try scanner.nextAlloc(arena, .alloc_if_needed);
        const name = switch (key) {
            .object_end => break,
            .string, .allocated_string => |s| s,
            else => return error.NotAnObject,
        };
        const key_at = stringSpan(text, scanner.cursor);
        var entry: Entry = .{ .name = name, .key = key_at, .path_at = key_at };
        if (try scanner.peekNextTokenType() != .object_begin) {
            const start = scanner.cursor;
            try scanner.skipValue();
            entry.problem = .{
                .at = trimmed(text, start, scanner.cursor),
                .message = "an entry is an object naming the library's `path`",
                .label = "write `{ \"path\": \"directory\" }`",
            };
            try entries.append(arena, entry);
            continue;
        }
        _ = try scanner.next();
        while (true) {
            const field = try scanner.nextAlloc(arena, .alloc_if_needed);
            const field_name = switch (field) {
                .object_end => break,
                .string, .allocated_string => |s| s,
                else => return error.NotAnObject,
            };
            // A value of the wrong kind is skipped whole, nested values
            // included, so the entries after it are read where they are.
            const start = scanner.cursor;
            const kind = try scanner.peekNextTokenType();
            if (std.mem.eql(u8, field_name, "path")) {
                if (kind == .string) {
                    switch (try scanner.nextAlloc(arena, .alloc_if_needed)) {
                        .string, .allocated_string => |s| {
                            entry.path = s;
                            entry.path_at = stringSpan(text, scanner.cursor);
                        },
                        else => unreachable,
                    }
                } else {
                    try scanner.skipValue();
                    if (entry.problem == null) entry.problem = .{
                        .at = trimmed(text, start, scanner.cursor),
                        .message = "`path` is a string naming the directory that holds the library",
                        .label = "write the directory as a string",
                    };
                }
            } else if (std.mem.eql(u8, field_name, "extern")) {
                switch (kind) {
                    .true => {
                        _ = try scanner.next();
                        entry.consents_to_extern = true;
                    },
                    .false => {
                        _ = try scanner.next();
                        entry.consents_to_extern = false;
                    },
                    else => {
                        try scanner.skipValue();
                        if (entry.problem == null) entry.problem = .{
                            .at = trimmed(text, start, scanner.cursor),
                            .message = "`extern` is `true` or `false`",
                            .label = "write `true` to consent to the library's `extern` functions",
                        };
                    },
                }
            } else {
                // Keys this compiler does not read are ignored, as the
                // manifest's own unknown keys are, so a manifest may carry
                // what a later version reads.
                try scanner.skipValue();
            }
        }
        if (entry.path == null and entry.problem == null) entry.problem = .{
            .at = key_at,
            .message = "an entry names the directory that holds the library with `path`",
            .label = "write `{ \"path\": \"directory\" }`",
        };
        try entries.append(arena, entry);
    }
    return entries.toOwnedSlice(arena);
}

/// The span of the string token that ends just before `end`, quotes included.
fn stringSpan(text: []const u8, end: usize) Span {
    var start = end -| 1;
    while (start > 0) {
        start -= 1;
        if (text[start] == '"' and (start == 0 or text[start - 1] != '\\')) break;
    }
    return .{ .start = @intCast(start), .end = @intCast(end) };
}

/// The span from `start` to `end` with the separators before the value left
/// out.
fn trimmed(text: []const u8, start: usize, end: usize) Span {
    var from = start;
    while (from < end and (std.ascii.isWhitespace(text[from]) or text[from] == ':' or text[from] == ',')) from += 1;
    return .{ .start = @intCast(from), .end = @intCast(end) };
}

test "a manifest's dependencies are read with where each is written" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const text =
        \\{ "kind": "program", "dependencies": {
        \\    "sqlite": { "path": "../sqlite", "extern": true, "version": "3" },
        \\    "shout": { "path": "libs/shout" },
        \\    "broken": "libs/broken",
        \\    "pathless": {}
        \\} }
    ;
    const written = (try read(arena.allocator(), text)).?;
    try testing.expectEqual(@as(usize, 4), written.entries.len);
    const sqlite = written.entries[0];
    try testing.expectEqualStrings("sqlite", sqlite.name);
    try testing.expectEqualStrings("\"sqlite\"", text[sqlite.key.start..sqlite.key.end]);
    try testing.expectEqualStrings("../sqlite", sqlite.path.?);
    try testing.expectEqualStrings("\"../sqlite\"", text[sqlite.path_at.start..sqlite.path_at.end]);
    try testing.expect(sqlite.consents_to_extern);
    try testing.expect(sqlite.problem == null);
    try testing.expect(!written.entries[1].consents_to_extern);
    try testing.expect(written.entries[2].problem != null);
    try testing.expect(written.entries[3].problem != null);
}

test "a value of the wrong kind is skipped whole, and the entries after it are read" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const text =
        \\{ "dependencies": {
        \\    "nested": { "path": "lib", "extern": { "path": "../nowhere" } },
        \\    "other": { "path": "other" }
        \\} }
    ;
    const written = (try read(arena.allocator(), text)).?;
    try testing.expectEqual(@as(usize, 2), written.entries.len);
    try testing.expectEqualStrings("lib", written.entries[0].path.?);
    const problem = written.entries[0].problem.?;
    try testing.expectEqualStrings("{ \"path\": \"../nowhere\" }", text[problem.at.start..problem.at.end]);
    try testing.expectEqualStrings("other", written.entries[1].path.?);
}

test "a manifest without dependencies writes none, and one that is not JSON is not read" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    try testing.expectEqual(@as(usize, 0), (try read(arena.allocator(), "{ \"kind\": \"library\" }")).?.entries.len);
    try testing.expect((try read(arena.allocator(), "{ not json")) == null);
    const wrong = (try read(arena.allocator(), "{ \"dependencies\": [\"a\"] }")).?;
    try testing.expect(wrong.problem != null);
}
