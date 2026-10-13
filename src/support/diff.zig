//! A line diff, for reporting what `linea fmt --check` would change.
//!
//! Myers admits several edit scripts of equal cost, so which one this returns
//! is part of what the module promises rather than a property of how it happens
//! to be written. Without that, hunks are stable only by accident and rewriting
//! this file would churn every golden that records a diff.
//!
//! What is promised, in order: the longest shared head and the longest shared
//! tail are kept as they are, and within what remains a deletion comes before
//! an insertion and the earliest position wins. The two trims come first
//! because they are what keep the cost linear in the ordinary case, and they do
//! change which equal-cost script is chosen -- `[A]` against `[B, A, A]` keeps
//! the second `A` rather than the first. That is a rule, not an accident, and
//! it is the one to state.

const std = @import("std");
const testing = std.testing;

pub const Edit = struct {
    tag: Tag,
    /// Borrowed from the input line slices, which borrow from their text.
    text: []const u8,

    pub const Tag = enum { keep, delete, insert };
};

/// The lines of a text, without their terminators. A trailing newline does not
/// produce a final empty line: a file ending in one has as many lines as it has
/// newlines.
pub fn splitLines(
    gpa: std.mem.Allocator,
    text: []const u8,
) std.mem.Allocator.Error![]const []const u8 {
    var out: std.ArrayList([]const u8) = .empty;
    var start: usize = 0;
    for (text, 0..) |ch, i| {
        if (ch != '\n') continue;
        try out.append(gpa, text[start..i]);
        start = i + 1;
    }
    if (start < text.len) try out.append(gpa, text[start..]);
    return out.toOwnedSlice(gpa);
}

/// How large an interior the quadratic table is allowed to cover.
///
/// The table is `(a+1)*(b+1)` cells of `u32`, so cost grows with the product
/// rather than with the difference. Two texts that share everything but a few
/// lines never reach this, because the shared head and tail are matched off
/// first. Two that genuinely differ everywhere would otherwise ask for gigabytes
/// to describe a diff nobody reads, so past this the interior is reported as one
/// replacement -- which is what it is.
const max_cells = 4 << 20;

/// The shortest edit script turning `a` into `b`.
///
/// The quadratic dynamic-programming form rather than Myers' linear-space
/// refinement: it is exact, it is obviously correct, and its cost is bounded by
/// the size of a file someone is editing. The refinement trades memory for
/// speed on inputs far larger than any source file.
pub fn diff(
    gpa: std.mem.Allocator,
    a: []const []const u8,
    b: []const []const u8,
) std.mem.Allocator.Error![]const Edit {
    // The shared head and tail are matched off before the table is sized. A
    // formatted file agrees with its source everywhere but a few lines, so
    // this is what keeps the ordinary case off the quadratic path -- and what
    // stops a change in the middle pushing everything after it past the bound.
    var head: usize = 0;
    while (head < a.len and head < b.len and std.mem.eql(u8, a[head], b[head])) head += 1;

    var tail: usize = 0;
    while (tail < a.len - head and tail < b.len - head and
        std.mem.eql(u8, a[a.len - 1 - tail], b[b.len - 1 - tail])) tail += 1;

    var out: std.ArrayList(Edit) = .empty;
    for (a[0..head]) |line| try out.append(gpa, .{ .tag = .keep, .text = line });
    try interior(gpa, &out, a[head .. a.len - tail], b[head .. b.len - tail]);
    for (a[a.len - tail ..]) |line| try out.append(gpa, .{ .tag = .keep, .text = line });
    return out.toOwnedSlice(gpa);
}

/// The part of the two texts that does not share a head or a tail.
fn interior(
    gpa: std.mem.Allocator,
    out: *std.ArrayList(Edit),
    a: []const []const u8,
    b: []const []const u8,
) std.mem.Allocator.Error!void {
    if (a.len == 0 and b.len == 0) return;
    if ((a.len + 1) * (b.len + 1) > max_cells) {
        for (a) |line| try out.append(gpa, .{ .tag = .delete, .text = line });
        for (b) |line| try out.append(gpa, .{ .tag = .insert, .text = line });
        return;
    }

    // cost[i][j] is how many edits turn a[i..] into b[j..].
    const w = b.len + 1;
    const cost = try gpa.alloc(u32, (a.len + 1) * w);
    defer gpa.free(cost);

    cost[a.len * w + b.len] = 0;
    var j = b.len;
    while (j > 0) {
        j -= 1;
        cost[a.len * w + j] = @intCast(b.len - j);
    }
    var i = a.len;
    while (i > 0) {
        i -= 1;
        cost[i * w + b.len] = @intCast(a.len - i);
        var k = b.len;
        while (k > 0) {
            k -= 1;
            cost[i * w + k] = if (std.mem.eql(u8, a[i], b[k]))
                cost[(i + 1) * w + (k + 1)]
            else
                1 + @min(cost[(i + 1) * w + k], cost[i * w + (k + 1)]);
        }
    }

    var x: usize = 0;
    var y: usize = 0;
    while (x < a.len or y < b.len) {
        if (x < a.len and y < b.len and std.mem.eql(u8, a[x], b[y])) {
            try out.append(gpa, .{ .tag = .keep, .text = a[x] });
            x += 1;
            y += 1;
            continue;
        }
        // The tie-break: a deletion is taken whenever it costs no more than the
        // insertion, so two scripts of equal length always resolve the same way.
        const delete_cost = if (x < a.len) cost[(x + 1) * w + y] else std.math.maxInt(u32);
        const insert_cost = if (y < b.len) cost[x * w + (y + 1)] else std.math.maxInt(u32);
        if (delete_cost <= insert_cost) {
            try out.append(gpa, .{ .tag = .delete, .text = a[x] });
            x += 1;
        } else {
            try out.append(gpa, .{ .tag = .insert, .text = b[y] });
            y += 1;
        }
    }
}

pub const Options = struct { color: bool = false };

const red = "\x1b[31m";
const green = "\x1b[32m";
const reset = "\x1b[0m";

/// A unified diff with three lines of context around the changes.
///
/// Writes nothing at all when the two texts agree, so a caller can render every
/// file it checked and only the differing ones produce output.
pub fn writeUnified(
    w: *std.Io.Writer,
    path: []const u8,
    edits: []const Edit,
    opts: Options,
) std.Io.Writer.Error!void {
    const context = 3;

    var first_change: ?usize = null;
    var last_change: usize = 0;
    for (edits, 0..) |e, i| {
        if (e.tag == .keep) continue;
        if (first_change == null) first_change = i;
        last_change = i;
    }
    const first = first_change orelse return;

    const lo = first -| context;
    const hi = @min(edits.len, last_change + context + 1);

    // Line numbers are one-based and count each side separately, so a deletion
    // advances the old file's count and an insertion the new one's.
    var old_start: usize = 1;
    var new_start: usize = 1;
    for (edits[0..lo]) |e| switch (e.tag) {
        .keep => {
            old_start += 1;
            new_start += 1;
        },
        .delete => old_start += 1,
        .insert => new_start += 1,
    };

    var old_len: usize = 0;
    var new_len: usize = 0;
    for (edits[lo..hi]) |e| switch (e.tag) {
        .keep => {
            old_len += 1;
            new_len += 1;
        },
        .delete => old_len += 1,
        .insert => new_len += 1,
    };

    try w.print("--- {s}\n+++ {s}\n", .{ path, path });
    try w.print("@@ -{d},{d} +{d},{d} @@\n", .{ old_start, old_len, new_start, new_len });
    for (edits[lo..hi]) |e| {
        if (opts.color) switch (e.tag) {
            .delete => try w.writeAll(red),
            .insert => try w.writeAll(green),
            .keep => {},
        };
        try w.writeByte(switch (e.tag) {
            .keep => ' ',
            .delete => '-',
            .insert => '+',
        });
        try w.writeAll(e.text);
        if (opts.color and e.tag != .keep) try w.writeAll(reset);
        try w.writeByte('\n');
    }
}

/// Applying a diff to the text it was computed from yields the other text.
/// Stated as a property because it is the only thing a diff must do, and it
/// holds for inputs no example would think to write.
fn apply(gpa: std.mem.Allocator, edits: []const Edit) std.mem.Allocator.Error![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    for (edits) |e| switch (e.tag) {
        .delete => {},
        .keep, .insert => {
            try out.appendSlice(gpa, e.text);
            try out.append(gpa, '\n');
        },
    };
    return out.toOwnedSlice(gpa);
}

fn joined(gpa: std.mem.Allocator, lines: []const []const u8) std.mem.Allocator.Error![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    for (lines) |line| {
        try out.appendSlice(gpa, line);
        try out.append(gpa, '\n');
    }
    return out.toOwnedSlice(gpa);
}

test "a diff of identical texts keeps every line" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const a = try splitLines(gpa, "one\ntwo\n");
    const edits = try diff(gpa, a, a);
    for (edits) |e| try testing.expectEqual(Edit.Tag.keep, e.tag);
    try testing.expectEqual(@as(usize, 2), edits.len);
}

test "a changed line becomes a delete and an insert, in that order" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const a = try splitLines(gpa, "one\ntwo\nthree\n");
    const b = try splitLines(gpa, "one\nTWO\nthree\n");
    const edits = try diff(gpa, a, b);

    try testing.expectEqual(@as(usize, 4), edits.len);
    try testing.expectEqual(Edit.Tag.keep, edits[0].tag);
    // The tie-break, asserted rather than assumed: both orderings cost the
    // same, so only the rule decides which comes out.
    try testing.expectEqual(Edit.Tag.delete, edits[1].tag);
    try testing.expectEqual(Edit.Tag.insert, edits[2].tag);
    try testing.expectEqual(Edit.Tag.keep, edits[3].tag);
}

test "a file with no trailing newline has no final empty line" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    try testing.expectEqual(@as(usize, 2), (try splitLines(gpa, "a\nb")).len);
    try testing.expectEqual(@as(usize, 2), (try splitLines(gpa, "a\nb\n")).len);
    try testing.expectEqual(@as(usize, 0), (try splitLines(gpa, "")).len);
}

test "identical texts render no diff at all" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const a = try splitLines(gpa, "one\ntwo\n");
    var out: std.Io.Writer.Allocating = .init(gpa);
    try writeUnified(&out.writer, "x.lin", try diff(gpa, a, a), .{});
    try testing.expectEqualStrings("", out.written());
}

test "a hunk header counts each side separately" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const a = try splitLines(gpa, "one\ntwo\n");
    const b = try splitLines(gpa, "one\ntwo\nthree\n");
    var out: std.Io.Writer.Allocating = .init(gpa);
    try writeUnified(&out.writer, "x.lin", try diff(gpa, a, b), .{});

    try testing.expectEqualStrings(
        \\--- x.lin
        \\+++ x.lin
        \\@@ -1,2 +1,3 @@
        \\ one
        \\ two
        \\+three
        \\
    , out.written());
}

test "colour wraps only the changed lines" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const a = try splitLines(gpa, "one\n");
    const b = try splitLines(gpa, "two\n");
    var out: std.Io.Writer.Allocating = .init(gpa);
    try writeUnified(&out.writer, "x.lin", try diff(gpa, a, b), .{ .color = true });

    try testing.expect(std.mem.indexOf(u8, out.written(), red ++ "-one" ++ reset) != null);
    try testing.expect(std.mem.indexOf(u8, out.written(), green ++ "+two" ++ reset) != null);
}

test "the shared tail is kept, which decides between equal-cost scripts" {
    // `[A]` against `[B, A, A]` admits two scripts of cost 2. The tail trim
    // keeps the *second* `A`, so the answer is insert, insert, keep. Pinned
    // because it is the case where the trim is observable, and a diff whose
    // choice moves churns every golden that records one.
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const edits = try diff(gpa, &.{"A"}, &.{ "B", "A", "A" });
    try testing.expectEqual(@as(usize, 3), edits.len);
    try testing.expectEqual(Edit.Tag.insert, edits[0].tag);
    try testing.expectEqual(Edit.Tag.insert, edits[1].tag);
    try testing.expectEqual(Edit.Tag.keep, edits[2].tag);
}

test "a shared head and tail are matched off before the table is sized" {
    // The table is the product of the two lengths, so a diff of two long texts
    // that agree everywhere but one line must never build one that large. This
    // asserts the shape rather than the timing: every line but the changed one
    // is kept, which is only reachable if the head and tail were trimmed.
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const n = 20_000;
    var a: std.ArrayList([]const u8) = .empty;
    var b: std.ArrayList([]const u8) = .empty;
    for (0..n) |i| {
        const line = try std.fmt.allocPrint(gpa, "line {d}", .{i});
        try a.append(gpa, line);
        try b.append(gpa, if (i == n / 2) "changed" else line);
    }

    const edits = try diff(gpa, a.items, b.items);
    var kept: usize = 0;
    for (edits) |e| {
        if (e.tag == .keep) kept += 1;
    }
    try testing.expectEqual(n - 1, kept);
    try testing.expectEqual(n + 1, edits.len);
}

test "an interior too large for the table is reported as one replacement" {
    // Past the bound the answer is still an answer: applying the edits has to
    // reproduce the second text, which is the whole contract.
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const n = 4_000;
    var a: std.ArrayList([]const u8) = .empty;
    var b: std.ArrayList([]const u8) = .empty;
    for (0..n) |i| {
        try a.append(gpa, try std.fmt.allocPrint(gpa, "a{d}", .{i}));
        try b.append(gpa, try std.fmt.allocPrint(gpa, "b{d}", .{i}));
    }

    const edits = try diff(gpa, a.items, b.items);
    try testing.expectEqualStrings(try joined(gpa, b.items), try apply(gpa, edits));
}

fn fuzzRoundTrip(_: void, smith: *std.testing.Smith) anyerror!void {
    var buf: [256]u8 = undefined;
    const len = smith.slice(&buf);
    const split = len / 2;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const a = try splitLines(gpa, buf[0..split]);
    const b = try splitLines(gpa, buf[split..len]);

    const rebuilt = try apply(gpa, try diff(gpa, a, b));
    try testing.expectEqualStrings(try joined(gpa, b), rebuilt);
}

test "fuzz: applying a diff reproduces the second text" {
    // Every input this property has ever failed on, replayed before any new one
    // is tried, so a crash the fuzzer found once cannot come back unnoticed.
    try std.testing.fuzz({}, fuzzRoundTrip, .{ .corpus = @import("fuzz_corpus").diff });
}

test "every input the fuzzer found for the diff still passes" {
    // Replayed here as well as handed to the fuzzer, because the two run at
    // different times: a search runs nightly and on a push, and this runs
    // whenever anyone builds.
    for (@import("fuzz_corpus").diff) |input| {
        var smith: std.testing.Smith = .{ .in = input };
        try fuzzRoundTrip({}, &smith);
    }
}
