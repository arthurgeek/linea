//! What a golden records of a location inside the standard library.
//!
//! A line or column in `std/` moves whenever the library file above it
//! changes, so a golden that records one fails on an edit that changed no
//! behaviour. `normalise` replaces those numbers with placeholders, both for
//! what a golden is written from and for what it is compared against. A
//! location in a user file is recorded exactly.
//!
//! Four shapes carry a standard-library location:
//!
//!   * `std/mem/buffer.lin:230:9`, and the quoted `"std/mem/buffer.lin":230:9`
//!     an MLIR `loc(...)` prints, become `:L:C`.
//!   * The snippet under a `::: std/...` or `--> std/...` header keeps its
//!     text and masks the line number in its gutter.
//!   * The gutter is as wide as the longest line number in the diagnostic,
//!     standard-library lines included, so a diagnostic naming a `std/` file is
//!     re-rendered at the width its own files' lines need.
//!   * The backend hands the runtime a trap's or panic's line and column as the
//!     constants `%tl<n>` and `%tc<n>`. When such a constant carries a
//!     library `loc(...)`, its value is that library line or column and
//!     becomes `L` or `C`. The trap kind `%tk<n>` and every other constant
//!     are code and stay exact.
//! The compiler and runtime print a location only as `path:line:column`
//! (`--> path:L:C`, `loc("path":L:C)`, `at path:L:C`), so no other spelling
//! (a range, `(line,col)`, a bare line) is masked. A program that prints
//! `std/x.lin:1:2` as data, or one with a `std/` directory of its own, is
//! masked like the library: only the line and column are lost.

const std = @import("std");
const mlir_backend = @import("../backend/mlir.zig");

const line_placeholder = "L";
const column_placeholder = "C";
const library_prefix = "std/";

/// Returns `text` with every standard-library location masked. The caller owns
/// the result.
pub fn normalise(gpa: std.mem.Allocator, text: []const u8) std.mem.Allocator.Error![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    try out.ensureTotalCapacity(gpa, text.len);

    var block_start: usize = 0;
    var at: usize = 0;
    while (at < text.len) {
        const line_end = std.mem.indexOfScalarPos(u8, text, at, '\n') orelse text.len;
        if (at > block_start and isHeader(text[at..line_end])) {
            try block(gpa, &out, text[block_start..at]);
            block_start = at;
        }
        at = @min(line_end + 1, text.len);
    }
    try block(gpa, &out, text[block_start..]);
    const located = try out.toOwnedSlice(gpa);
    defer gpa.free(located);
    return positionConstants(gpa, located);
}

/// Copies `text`, masking the value of each `%tl<n>`/`%tc<n>` constant whose
/// `loc` is already masked as a library location: the value is that source
/// line or column.
fn positionConstants(gpa: std.mem.Allocator, text: []const u8) std.mem.Allocator.Error![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    try out.ensureTotalCapacity(gpa, text.len);
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |line| {
        if (positionConstant(line)) |value| {
            try out.appendSlice(gpa, line[0..value.start]);
            try out.appendSlice(gpa, value.placeholder);
            try out.appendSlice(gpa, line[value.end..]);
        } else {
            try out.appendSlice(gpa, line);
        }
        if (lines.index != null) try out.append(gpa, '\n');
    }
    return out.toOwnedSlice(gpa);
}

const PositionValue = struct { start: usize, end: usize, placeholder: []const u8 };

/// Where the value sits in `    %tl3 = arith.constant 141 : i32 loc("std/...":L:C)`,
/// or null when `line` is not a library trap line or column constant.
fn positionConstant(line: []const u8) ?PositionValue {
    const indent = std.mem.indexOfNone(u8, line, " ") orelse return null;
    const line_name = "%" ++ mlir_backend.trap_line_name;
    const column_name = "%" ++ mlir_backend.trap_col_name;
    var at = indent;
    var placeholder: []const u8 = undefined;
    if (std.mem.startsWith(u8, line[at..], line_name)) {
        at += line_name.len;
        placeholder = line_placeholder;
    } else if (std.mem.startsWith(u8, line[at..], column_name)) {
        at += column_name.len;
        placeholder = column_placeholder;
    } else return null;
    const digits = std.mem.indexOfNonePos(u8, line, at, "0123456789") orelse return null;
    if (digits == at) return null;
    const head = " = arith.constant ";
    if (!std.mem.startsWith(u8, line[digits..], head)) return null;
    const start = digits + head.len;
    const end = std.mem.indexOfNonePos(u8, line, start, "0123456789LC") orelse return null;
    if (end == start or !std.mem.startsWith(u8, line[end..], " : i32 loc(\"" ++ library_prefix)) return null;
    return .{ .start = start, .end = end, .placeholder = placeholder };
}

/// Whether `line` opens a diagnostic: severities are the only text printed at
/// the left margin.
fn isHeader(line: []const u8) bool {
    return std.mem.startsWith(u8, line, "error") or
        std.mem.startsWith(u8, line, "warning") or
        std.mem.startsWith(u8, line, "note");
}

/// The path after a `--> ` or `::: ` marker, or null when `line` is neither
/// preceded by `gutter` spaces nor carries one.
fn headerPath(line: []const u8, gutter: usize) ?[]const u8 {
    if (line.len < gutter + 4) return null;
    for (line[0..gutter]) |c| if (c != ' ') return null;
    const rest = line[gutter..];
    if (!std.mem.startsWith(u8, rest, "--> ") and !std.mem.startsWith(u8, rest, "::: ")) return null;
    return rest[4..];
}

/// The width of the gutter a diagnostic was rendered with, read off its
/// `-->` line.
fn gutterWidth(lines_text: []const u8) ?usize {
    var lines = std.mem.splitScalar(u8, lines_text, '\n');
    while (lines.next()) |line| {
        const spaces = std.mem.indexOfNone(u8, line, " ") orelse continue;
        if (std.mem.startsWith(u8, line[spaces..], "--> ")) return spaces;
    }
    return null;
}

/// The digits of a snippet line `N<padding> | text` rendered at `gutter`
/// width, or null when `line` is not one.
fn snippetDigits(line: []const u8, gutter: usize) ?usize {
    // The masked line number is as much a number as the one it replaces, so
    // normalising masked text finds the same snippets.
    const digits = if (std.mem.startsWith(u8, line, line_placeholder))
        line_placeholder.len
    else
        std.mem.indexOfNone(u8, line, "0123456789") orelse line.len;
    if (digits == 0 or digits > gutter or line.len < gutter + 3) return null;
    for (line[digits..gutter]) |c| if (c != ' ') return null;
    if (!std.mem.startsWith(u8, line[gutter..], " | ")) return null;
    return digits;
}

/// A line made only of the gutter and a bar: the blank bar, an underline, or
/// a label. Returns what follows the gutter's spaces.
fn barRest(line: []const u8, gutter: usize) ?[]const u8 {
    if (line.len < gutter + 2) return null;
    for (line[0 .. gutter + 1]) |c| if (c != ' ') return null;
    if (line[gutter + 1] != '|') return null;
    return line[gutter + 1 ..];
}

fn helpRest(line: []const u8, gutter: usize) ?[]const u8 {
    if (line.len < gutter) return null;
    for (line[0..gutter]) |c| if (c != ' ') return null;
    if (!std.mem.startsWith(u8, line[gutter..], " = ")) return null;
    return line[gutter..];
}

fn isLibrary(path: []const u8) bool {
    return std.mem.startsWith(u8, path, library_prefix);
}

/// How many bytes of `text` the diagnostic rendered at `gutter` occupies: its
/// header, `-->`/`:::` lines, snippets, bars and help lines. Anything after
/// them is not part of the diagnostic and keeps its text.
fn diagnosticLength(text: []const u8, gutter: usize) usize {
    var at: usize = 0;
    var first = true;
    while (at < text.len) {
        const line_end = std.mem.indexOfScalarPos(u8, text, at, '\n') orelse text.len;
        const line = text[at..line_end];
        const part = first or headerPath(line, gutter) != null or snippetDigits(line, gutter) != null or
            barRest(line, gutter) != null or helpRest(line, gutter) != null;
        if (!part) return at;
        first = false;
        at = @min(line_end + 1, text.len);
    }
    return text.len;
}

fn block(gpa: std.mem.Allocator, out: *std.ArrayList(u8), whole: []const u8) !void {
    const gutter = gutterWidth(whole) orelse return inlineLocations(gpa, out, whole);
    const length = diagnosticLength(whole, gutter);
    try diagnostic(gpa, out, whole[0..length], gutter);
    try inlineLocations(gpa, out, whole[length..]);
}

/// Copies one diagnostic, re-rendering its gutter when it shows a library file.
fn diagnostic(gpa: std.mem.Allocator, out: *std.ArrayList(u8), text: []const u8, gutter: usize) !void {
    var names_library = false;
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |line| {
        if (headerPath(line, gutter)) |path| {
            if (isLibrary(path)) names_library = true;
        }
    }
    if (!names_library) return inlineLocations(gpa, out, text);

    // The width the user's own lines need: the library's line numbers are
    // masked, so they must not decide it.
    var width: usize = 1;
    var in_library = false;
    lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |line| {
        if (headerPath(line, gutter)) |path| {
            in_library = isLibrary(path);
        } else if (!in_library) {
            if (snippetDigits(line, gutter)) |digits| width = @max(width, digits);
        }
    }

    in_library = false;
    lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |line| {
        const last = lines.index == null;
        var rendered: std.ArrayList(u8) = .empty;
        defer rendered.deinit(gpa);
        if (headerPath(line, gutter)) |path| {
            in_library = isLibrary(path);
            try rendered.appendNTimes(gpa, ' ', width);
            try rendered.appendSlice(gpa, line[gutter..]);
        } else if (snippetDigits(line, gutter)) |digits| {
            if (in_library) {
                try rendered.appendSlice(gpa, line_placeholder);
                try rendered.appendNTimes(gpa, ' ', width - line_placeholder.len);
            } else {
                try rendered.appendSlice(gpa, line[0..digits]);
                try rendered.appendNTimes(gpa, ' ', width - digits);
            }
            try rendered.appendSlice(gpa, line[gutter..]);
        } else if (barRest(line, gutter)) |rest| {
            try rendered.appendNTimes(gpa, ' ', width + 1);
            try rendered.appendSlice(gpa, rest);
        } else if (helpRest(line, gutter)) |rest| {
            try rendered.appendNTimes(gpa, ' ', width);
            try rendered.appendSlice(gpa, rest);
        } else {
            try rendered.appendSlice(gpa, line);
        }
        try inlineLocations(gpa, out, rendered.items);
        if (!last) try out.append(gpa, '\n');
    }
}

fn isPathByte(c: u8) bool {
    return std.ascii.isAlphanumeric(c) or c == '_' or c == '/' or c == '-';
}

/// Copies `text`, masking the line and column after each `std/...lin` path.
fn inlineLocations(gpa: std.mem.Allocator, out: *std.ArrayList(u8), text: []const u8) !void {
    var copied: usize = 0;
    var at: usize = 0;
    while (std.mem.indexOfPos(u8, text, at, library_prefix)) |start| {
        at = start + library_prefix.len;
        // `examples/std/x.lin`, `mystd/x.lin` and `$ROOT/std/x.lin` name some
        // other file.
        if (start > 0 and (isPathByte(text[start - 1]) or text[start - 1] == '.')) continue;
        var end = at;
        while (end < text.len and isPathByte(text[end])) end += 1;
        if (!std.mem.startsWith(u8, text[end..], ".lin")) continue;
        end += ".lin".len;
        if (end < text.len and text[end] == '"') end += 1;
        if (end >= text.len or text[end] != ':') continue;
        var line_end = end + 1;
        while (line_end < text.len and std.ascii.isDigit(text[line_end])) line_end += 1;
        if (line_end == end + 1) continue;
        if (line_end + 1 >= text.len or text[line_end] != ':' or !std.ascii.isDigit(text[line_end + 1])) continue;
        var location_end = line_end + 1;
        while (location_end < text.len and std.ascii.isDigit(text[location_end])) location_end += 1;

        try out.appendSlice(gpa, text[copied..end]);
        try out.appendSlice(gpa, ":" ++ line_placeholder ++ ":" ++ column_placeholder);
        copied = location_end;
        at = location_end;
    }
    try out.appendSlice(gpa, text[copied..]);
}

fn expectNormalised(expected: []const u8, input: []const u8) !void {
    const got = try normalise(std.testing.allocator, input);
    defer std.testing.allocator.free(got);
    try std.testing.expectEqualStrings(expected, got);
    // Masking what is already masked changes nothing.
    const again = try normalise(std.testing.allocator, got);
    defer std.testing.allocator.free(again);
    try std.testing.expectEqualStrings(expected, again);
}

test "a trap location in the library loses its line and column" {
    try expectNormalised(
        "linea: index out of bounds at std/mem/buffer.lin:L:C\n",
        "linea: index out of bounds at std/mem/buffer.lin:230:9\n",
    );
}

test "a quoted MLIR location in the library loses its line and column" {
    try expectNormalised(
        "%v1 = arith.constant 1 : i64 loc(\"std/mem/buffer.lin\":L:C)\n",
        "%v1 = arith.constant 1 : i64 loc(\"std/mem/buffer.lin\":231:9)\n",
    );
}

test "a trap's library line and column constants are masked, its kind is not" {
    try expectNormalised(
        "    %tk1 = arith.constant 6 : i32 loc(\"std/text/str.lin\":L:C)\n" ++
            "    %tl1 = arith.constant L : i32 loc(\"std/text/str.lin\":L:C)\n" ++
            "    %tc1 = arith.constant C : i32 loc(\"std/text/str.lin\":L:C)\n",
        "    %tk1 = arith.constant 6 : i32 loc(\"std/text/str.lin\":141:19)\n" ++
            "    %tl1 = arith.constant 141 : i32 loc(\"std/text/str.lin\":141:19)\n" ++
            "    %tc1 = arith.constant 19 : i32 loc(\"std/text/str.lin\":141:19)\n",
    );
}

test "a trap's line and column constants in a user file are recorded exactly" {
    const text =
        "    %tl1 = arith.constant 12 : i32 loc(\"main.lin\":12:9)\n" ++
        "    %tc1 = arith.constant 9 : i32 loc(\"main.lin\":12:9)\n";
    try expectNormalised(text, text);
}

test "a constant that is not a trap position is left alone in the library" {
    const text =
        "    %v1 = arith.constant 141 : i32 loc(\"std/text/str.lin\":L:C)\n" ++
        "    %tlx = arith.constant 141 : i32 loc(\"std/text/str.lin\":L:C)\n" ++
        "    %tl2 = arith.constant 141 : i64 loc(\"std/text/str.lin\":L:C)\n";
    try expectNormalised(text, text);
}

test "a library file name without a location is left alone" {
    try expectNormalised(
        "global @linea_file0(\"std/testing/testing.lin\\00\") : !llvm.array<24 x i8>\n",
        "global @linea_file0(\"std/testing/testing.lin\\00\") : !llvm.array<24 x i8>\n",
    );
}

test "a location in a user file is recorded exactly" {
    try expectNormalised(
        "linea: panic at tests/x/main.lin:12:5\n",
        "linea: panic at tests/x/main.lin:12:5\n",
    );
    try expectNormalised(
        "loc(\"main.lin\":3:4)\n",
        "loc(\"main.lin\":3:4)\n",
    );
}

test "a path that merely contains std is not the library" {
    try expectNormalised("at examples/std/x.lin:3:4\n", "at examples/std/x.lin:3:4\n");
    try expectNormalised("at mystd/x.lin:3:4\n", "at mystd/x.lin:3:4\n");
    try expectNormalised("at app/std/extra/extra.lin:3:4\n", "at app/std/extra/extra.lin:3:4\n");
    try expectNormalised("at $ROOT/std/x.lin:3:4\n", "at $ROOT/std/x.lin:3:4\n");
    try expectNormalised("at ./std/x.lin:3:4\n", "at ./std/x.lin:3:4\n");
}

test "only a path:line:column location is masked" {
    try expectNormalised("at std/a/b.lin:12\n", "at std/a/b.lin:12\n");
    try expectNormalised("at std/a/b.lin:L:C-12:9\n", "at std/a/b.lin:12:3-12:9\n");
    try expectNormalised("at std/notes.txt:3:4\n", "at std/notes.txt:3:4\n");
    try expectNormalised("at a.std/x.lin:3:4\n", "at a.std/x.lin:3:4\n");
}

test "a library snippet masks its line number and keeps its text" {
    try expectNormalised(
        \\error[T-Bound]: needs `Discardable`
        \\  --> tests/iter/find.lin:20:18
        \\   |
        \\20 |     match tokens.find(|item| item) {
        \\   |                  ^^^^ `find` may dispose
        \\  ::: std/iter/iter.lin
        \\L  |         Self.Iter.Item: Discardable,
        \\   |         -------------- required by this `where` clause
        \\
    ,
        \\error[T-Bound]: needs `Discardable`
        \\   --> tests/iter/find.lin:20:18
        \\    |
        \\20  |     match tokens.find(|item| item) {
        \\    |                  ^^^^ `find` may dispose
        \\   ::: std/iter/iter.lin
        \\258 |         Self.Iter.Item: Discardable,
        \\    |         -------------- required by this `where` clause
        \\
    );
}

test "a library snippet reads the same however many digits its line has" {
    const short =
        \\error[T-Bound]: needs `Discardable`
        \\  --> a.lin:2:1
        \\   |
        \\2  |     use()
        \\   |     ^^^ here
        \\  ::: std/iter/iter.lin
        \\82 |     Self.Item: Discardable
        \\   |     ---- required
        \\
    ;
    const long =
        \\error[T-Bound]: needs `Discardable`
        \\   --> a.lin:2:1
        \\    |
        \\2   |     use()
        \\    |     ^^^ here
        \\   ::: std/iter/iter.lin
        \\100 |     Self.Item: Discardable
        \\    |     ---- required
        \\
    ;
    const a = try normalise(std.testing.allocator, short);
    defer std.testing.allocator.free(a);
    const b = try normalise(std.testing.allocator, long);
    defer std.testing.allocator.free(b);
    try std.testing.expectEqualStrings(a, b);
}

test "a change to the text of a library line still shows" {
    const before = try normalise(std.testing.allocator, "error[X]: m\n --> a.lin:1:1\n  |\n1 | f()\n  | ^ x\n ::: std/a.lin\n9 | let a\n  | - y\n");
    defer std.testing.allocator.free(before);
    const after = try normalise(std.testing.allocator, "error[X]: m\n --> a.lin:1:1\n  |\n1 | f()\n  | ^ x\n ::: std/a.lin\n9 | let b\n  | - y\n");
    defer std.testing.allocator.free(after);
    try std.testing.expect(!std.mem.eql(u8, before, after));
}

test "a diagnostic that names no library file is untouched" {
    const text =
        \\error[T-Mismatch]: expected `Int`
        \\    --> a.lin:100:3
        \\     |
        \\100  |     x
        \\     |     ^ here
        \\     = help: try it
        \\
    ;
    try expectNormalised(text, text);
}

test "help lines follow the re-rendered gutter" {
    try expectNormalised(
        \\error[X]: m
        \\ --> a.lin:1:1
        \\  |
        \\1 | f()
        \\  | ^ x
        \\ ::: std/a.lin
        \\L | let a
        \\  | - y
        \\  |
        \\  = help: do it
        \\
    ,
        \\error[X]: m
        \\   --> a.lin:1:1
        \\    |
        \\1   | f()
        \\    | ^ x
        \\   ::: std/a.lin
        \\100 | let a
        \\    | - y
        \\    |
        \\    = help: do it
        \\
    );
}

test "text with no trailing newline and empty text survive" {
    try expectNormalised("", "");
    try expectNormalised("at std/a.lin:L:C", "at std/a.lin:3:4");
}

test "a line after a library excerpt that looks like a gutter row is not masked" {
    const text =
        \\error[X]: m
        \\ --> a.lin:1:1
        \\  |
        \\1 | f()
        \\  | ^ x
        \\ ::: std/a.lin
        \\L | let a
        \\  | - y
        \\12 | row
        \\
    ;
    try expectNormalised(text, text);
}

test "a user excerpt after a library excerpt keeps its numbers" {
    try expectNormalised(
        \\error[X]: m
        \\  --> a.lin:1:1
        \\   |
        \\1  | f()
        \\   | ^ x
        \\  ::: std/a.lin
        \\L  | let a
        \\   | - y
        \\  ::: tests/b.lin
        \\98 | g()
        \\   | - z
        \\
    ,
        \\error[X]: m
        \\    --> a.lin:1:1
        \\     |
        \\1    | f()
        \\     | ^ x
        \\    ::: std/a.lin
        \\1000 | let a
        \\     | - y
        \\    ::: tests/b.lin
        \\98   | g()
        \\     | - z
        \\
    );
}

test "each diagnostic is re-rendered at the width of its own lines" {
    try expectNormalised(
        \\error[X]: m
        \\ --> a.lin:1:1
        \\  |
        \\1 | f()
        \\  | ^ x
        \\ ::: std/a.lin
        \\L | let a
        \\  | - y
        \\error[X]: n
        \\  --> b.lin:20:1
        \\   |
        \\20 | f()
        \\   | ^ x
        \\  ::: std/a.lin
        \\L  | let a
        \\   | - y
        \\
    ,
        \\error[X]: m
        \\  --> a.lin:1:1
        \\   |
        \\1  | f()
        \\   | ^ x
        \\  ::: std/a.lin
        \\10 | let a
        \\   | - y
        \\error[X]: n
        \\   --> b.lin:20:1
        \\    |
        \\20  | f()
        \\    | ^ x
        \\   ::: std/a.lin
        \\300 | let a
        \\    | - y
        \\
    );
}
