const std = @import("std");
const testing = std.testing;

const source_mod = @import("../support/source.zig");
const FileId = source_mod.FileId;
const FileTable = source_mod.FileTable;
const LineCol = source_mod.LineCol;
const Source = source_mod.Source;
const SourceMap = source_mod.SourceMap;
const diagnostic = @import("diagnostic.zig");
const Diagnostic = diagnostic.Diagnostic;
const Label = diagnostic.Label;
const Severity = diagnostic.Severity;
const sink_mod = @import("sink.zig");
const Sink = sink_mod.Sink;
const Span = @import("../support/span.zig").Span;

pub const Color = enum { never, always };
pub const Options = struct { color: Color = .never };

const reset = "\x1b[0m";
const bold = "\x1b[1m";

/// The most of a source line a snippet shows.
///
/// Nothing the renderer writes may scale with the source. A snippet carries a
/// marker row of its own width, and one diagnostic per label group repeats
/// both, so an unbounded snippet would make a file's diagnostics a multiple of
/// the file -- and one write of it would meet the ceiling a host puts on a
/// single write, which is an outcome decided by how the compiler was built
/// rather than by what it was given.
///
/// The number is a reading width and not a memory limit: a snippet exists to
/// be read beside its marker row, and 120 columns is wider than any line
/// written by hand, so an ordinary diagnostic is never cut and a cut one
/// points into a line that was generated.
const max_snippet_columns: u32 = 120;

/// Written on whichever side of a snippet was cut, held off the text by a
/// space so that a line beginning or ending in a dot cannot be read as part of
/// the mark.
const cut_before = "... ";
const cut_after = " ...";

fn severityColor(s: Severity) []const u8 {
    return switch (s) {
        .err => "\x1b[31m",
        .warning => "\x1b[33m",
        .note => "\x1b[36m",
    };
}

/// Emits an escape sequence only when colour is enabled, so every call site
/// stays free of the conditional.
fn paint(w: *std.Io.Writer, opts: Options, code: []const u8) std.Io.Writer.Error!void {
    if (opts.color == .always) try w.writeAll(code);
}

fn decimalWidth(n: u32) usize {
    var width: usize = 1;
    var v = n;
    while (v >= 10) : (v /= 10) width += 1;
    return width;
}

/// How many labels are ordered before the rest are shown as they were built.
///
/// A diagnostic carries two or three. The cap is what lets the order be
/// decided without an allocator, which this pass is not handed one of.
const max_ordered = 8;

/// The order labels are shown in: the primary's file first, then source order
/// within each file.
///
/// Ordering is presentation, and this is the only place that can do it. A span
/// is a byte offset into the file that produced it, so two spans from
/// different files compare as though they named the same place -- which
/// `support/span.zig` says on the type itself. Passes that compared bare
/// offsets got an order that flips when an unrelated file grows a comment, and
/// a diagnostic's labels were sorted by the length of a file it was not about.
///
/// Emitters append labels as they build them and order nothing.
fn labelOrder(table: *const FileTable, d: *const Diagnostic, home: FileId, buf: *[max_ordered]usize) []const usize {
    const n = @min(d.labels.len, max_ordered);
    for (0..n) |i| buf[i] = i;

    // Insertion sort: with a handful of labels it is the whole of what is
    // needed, and it is stable, so labels that compare equal stay in the order
    // the pass built them.
    var i: usize = 1;
    while (i < n) : (i += 1) {
        var j = i;
        while (j > 0 and before(table, home, d.labels[buf[j]], d.labels[buf[j - 1]])) : (j -= 1) {
            std.mem.swap(usize, &buf[j], &buf[j - 1]);
        }
    }
    return buf[0..n];
}

fn before(table: *const FileTable, home: FileId, a: Label, b: Label) bool {
    // The file the diagnostic points at comes first, whatever it is called.
    // Everything else is ordered by name so the grouping does not depend on
    // the order the files happened to load.
    if ((a.file == home) != (b.file == home)) return a.file == home;
    if (a.file != b.file) {
        return std.mem.order(u8, table.get(a.file).path, table.get(b.file).path) == .lt;
    }
    const pa = table.mapOf(a.file).lineCol(a.span.start);
    const pb = table.mapOf(b.file).lineCol(b.span.start);
    if (pa.line != pb.line) return pa.line < pb.line;
    return pa.column < pb.column;
}

/// Writes one diagnostic in the form a person reads.
///
/// Reached only through `renderAll`, which is reached only with a `Sink`. That
/// is what makes the texts here already bounded: a diagnostic becomes visible
/// by being added to a sink, and the sink cuts what it is given. Taking a bare
/// `Diagnostic` publicly would be a second way in, and a way in that skips the
/// cut is a way for output to scale with the source again.
fn render(
    w: *std.Io.Writer,
    table: *const FileTable,
    d: *const Diagnostic,
    opts: Options,
) std.Io.Writer.Error!void {
    try paint(w, opts, bold);
    try paint(w, opts, severityColor(d.severity));
    try w.writeAll(d.severity.text());
    if (d.code) |c| try w.print("[{f}]", .{c});
    try paint(w, opts, reset);
    try paint(w, opts, bold);
    try w.print(": {s}", .{d.message});
    try paint(w, opts, reset);
    try w.writeByte('\n');

    // A diagnostic with no primary label has no place to point at, so the
    // header is the whole message.
    const primary = d.primaryLabel() orelse return;
    const primary_map = table.mapOf(primary.file);
    const primary_pos = primary_map.lineCol(primary.span.start);

    var max_line = primary_pos.line;
    for (d.labels) |l| {
        const line = table.mapOf(l.file).lineCol(l.span.start).line;
        if (line > max_line) max_line = line;
    }
    const gutter = decimalWidth(max_line);

    try w.splatByteAll(' ', gutter);
    try w.print("--> {s}:{d}:{d}\n", .{ table.get(primary.file).path, primary_pos.line, primary_pos.column });

    try writeGutterBar(w, gutter);
    // Labels that fall inside the snippet already shown share it: repeating
    // the source would suggest two places to look at when there is only one.
    // Labels that fall outside it get their own, because on a line too long to
    // show whole there really are two places.
    var window: Window = .none;
    var order_buf: [max_ordered]usize = undefined;
    var shown: FileId = primary.file;
    for (labelOrder(table, d, primary.file, &order_buf)) |i| {
        const l = d.labels[i];
        const l_map = table.mapOf(l.file);
        const pos = l_map.lineCol(l.span.start);

        // A label in another file says which, because two files' line 2 shown
        // one above the other is two places a reader cannot tell apart.
        if (l.file != shown) {
            shown = l.file;
            try w.splatByteAll(' ', gutter);
            try w.print("::: {s}\n", .{table.get(l.file).path});
            window = .none;
        }

        if (!window.holds(l, pos.line)) {
            window = windowFor(l_map, l, pos);
            try writeSnippet(w, window, pos.line, gutter);
        }
        try writeMarker(w, window, l, gutter, opts);
    }

    if (d.notes.len > 0) {
        try writeGutterBar(w, gutter);
        for (d.notes) |note| {
            try w.splatByteAll(' ', gutter);
            try paint(w, opts, severityColor(.note));
            try w.print(" = help: {s}", .{note});
            try paint(w, opts, reset);
            try w.writeByte('\n');
        }
    }
}

fn writeGutterBar(w: *std.Io.Writer, gutter: usize) std.Io.Writer.Error!void {
    try w.splatByteAll(' ', gutter);
    try w.writeAll(" |\n");
}

/// The part of one line a snippet shows, and where that part sits in the file.
///
/// Every marker under a snippet is placed against the window the snippet was
/// written from, so the offsets a marker is indented and clamped by are the
/// ones the reader can see. That is also what decides when a snippet is
/// repeated: a label the window does not hold has nowhere to point in it.
const Window = struct {
    file: FileId,
    line: u32,
    /// Offsets into the file of the first shown byte and of one past the last.
    begin: u32,
    end: u32,
    text: []const u8,
    left_cut: bool,
    right_cut: bool,

    /// A window over nothing, so the first label always brings its own.
    const none: Window = .{
        .file = .none,
        .line = 0,
        .begin = 0,
        .end = 0,
        .text = "",
        .left_cut = false,
        .right_cut = false,
    };

    /// Whether a marker for `l` has a place in this window. The end is
    /// inclusive because a zero-width span sits one past the text it follows.
    fn holds(self: Window, l: Label, line: u32) bool {
        return self.file == l.file and self.line == line and
            l.span.start >= self.begin and l.span.start <= self.end;
    }
};

fn windowFor(map: *const SourceMap, l: Label, pos: LineCol) Window {
    const text = map.lineText(pos.line);
    const len: u32 = @intCast(text.len);

    // Where the line ends, as the label's start plus what of the line follows
    // it. `max_bytes` is halved so that this sum holds in a span's own field.
    const line_end = l.span.start + len - (pos.column - 1);
    const line_begin = line_end - len;

    // A label inside the first `max_snippet_columns` columns is shown with the
    // line's own beginning, which is the context a reader wants. One past them
    // is centred instead, so a cut line still shows what led up to the label.
    //
    // A span may sit past the text of the line it belongs to -- at end of
    // input, or on a line whose terminator the snippet drops -- so where it
    // sits is clamped to what the snippet can be cut out of.
    const at = @min(pos.column - 1, len);
    const from: u32 = if (at < max_snippet_columns) 0 else at - max_snippet_columns / 2;
    const to: u32 = @min(len, from + max_snippet_columns);

    return .{
        .file = l.file,
        .line = pos.line,
        .begin = line_begin + from,
        .end = line_begin + to,
        .text = text[from..to],
        .left_cut = from > 0,
        .right_cut = to < len,
    };
}

fn writeSnippet(
    w: *std.Io.Writer,
    window: Window,
    line: u32,
    gutter: usize,
) std.Io.Writer.Error!void {
    try w.print("{d}", .{line});
    try w.splatByteAll(' ', gutter - decimalWidth(line));
    try w.writeAll(" | ");
    if (window.left_cut) try w.writeAll(cut_before);
    try w.writeAll(window.text);
    if (window.right_cut) try w.writeAll(cut_after);
    try w.writeByte('\n');
}

fn writeMarker(
    w: *std.Io.Writer,
    window: Window,
    l: Label,
    gutter: usize,
    opts: Options,
) std.Io.Writer.Error!void {
    try w.splatByteAll(' ', gutter);
    try w.writeAll(" | ");
    if (window.left_cut) try w.splatByteAll(' ', cut_before.len);
    try w.splatByteAll(' ', l.span.start - window.begin);

    const marker: u8 = if (l.style == .primary) '^' else '-';
    // Clamp to what the snippet shows, so that a span crossing a newline or
    // running past the cut does not carry a marker off the end of it. A
    // zero-width span at end of input sits past the last character of the line
    // it belongs to, so the lower bound matters as much as the upper one.
    const end = @max(l.span.start, @min(l.span.end, window.end));
    const width = @max(@as(u32, 1), end - l.span.start);

    try paint(w, opts, severityColor(if (l.style == .primary) .err else .note));
    try w.splatByteAll(marker, width);
    if (l.message.len > 0) try w.print(" {s}", .{l.message});
    try paint(w, opts, reset);
    try w.writeByte('\n');
}

pub fn renderAll(
    w: *std.Io.Writer,
    table: *const FileTable,
    sink: *const Sink,
    opts: Options,
) std.Io.Writer.Error!void {
    for (sink.items()) |*d| try render(w, table, d, opts);
}

fn renderToString(gpa: std.mem.Allocator, text: []const u8, d: Diagnostic) ![]u8 {
    const src: Source = .{ .path = "t.lin", .text = text };
    var table: FileTable = .empty;
    defer table.deinit(gpa);
    _ = try table.add(gpa, src);
    try table.buildMaps(gpa);

    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    try render(&out.writer, &table, &d, .{ .color = .never });
    return out.toOwnedSlice();
}

/// The 1-based rows of a rendering, so a case can name the snippet and the
/// marker under it rather than search the whole output for a substring.
fn rowsOf(gpa: std.mem.Allocator, got: []const u8) ![][]const u8 {
    var rows: std.ArrayList([]const u8) = .empty;
    var it = std.mem.splitScalar(u8, got, '\n');
    while (it.next()) |line| try rows.append(gpa, line);
    return rows.toOwnedSlice(gpa);
}

test "a rendered row is bounded, whichever text the diagnostic carries" {
    // The header, a marker and a note are three places one message is written.
    // The texts are bounded before they arrive -- a sink cuts what it is given
    // -- and this is the other half of that: nothing on a row grows with the
    // text either, so a bounded text makes a bounded row.
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const long = "Z" ** 4000;
    var sink = Sink.init(arena.allocator());
    try sink.add(.{
        .severity = .err,
        .message = long,
        .labels = &.{.{ .file = .from(0), .span = .{ .start = 0, .end = 1 }, .message = long }},
        .notes = &.{long},
    });

    const src: Source = .{ .path = "t.lin", .text = "x\n" };
    var table: FileTable = .empty;
    defer table.deinit(testing.allocator);
    _ = try table.add(testing.allocator, src);
    try table.buildMaps(testing.allocator);

    var out: std.Io.Writer.Allocating = .init(testing.allocator);
    defer out.deinit();
    try renderAll(&out.writer, &table, &sink, .{ .color = .never });

    // Nothing precedes a text on its row but a fixed prefix, of which
    // ` = help: ` past a one-digit gutter is the widest.
    const prefix = " = help: ".len + 1;
    const widest = prefix + sink_mod.max_text_bytes + sink_mod.truncated.len;
    var rows = std.mem.splitScalar(u8, out.written(), '\n');
    while (rows.next()) |row| try testing.expect(row.len <= widest);

    // Three cuts, and each says so: a cut message that does not is read as a
    // whole one, which is worse than the length it was cut for.
    const got = out.written();
    try testing.expectEqual(@as(usize, 3), std.mem.count(u8, got, sink_mod.truncated));
}

test "a line longer than the bound is cut, and its marker stops at the cut" {
    var text: [400]u8 = @splat('a');
    text[399] = '\n';

    const got = try renderToString(testing.allocator, &text, .{
        .severity = .err,
        .message = "long",
        .labels = &.{.{ .file = .from(0), .span = .{ .start = 0, .end = 399 }, .message = "here" }},
    });
    defer testing.allocator.free(got);

    const rows = try rowsOf(testing.allocator, got);
    defer testing.allocator.free(rows);

    // The label sits inside the first `max_snippet_columns` columns, so the
    // line is shown from its own beginning and only the far end is cut.
    try testing.expectEqual(@as(usize, max_snippet_columns), std.mem.count(u8, rows[3], "a"));
    try testing.expect(std.mem.endsWith(u8, rows[3], cut_after));

    // A span reaching past the cut is clamped to it, exactly as one reaching
    // past the end of a line is.
    try testing.expectEqual(@as(usize, max_snippet_columns), std.mem.count(u8, rows[4], "^"));
}

test "a label past the bound brings the part of the line around it" {
    var text: [400]u8 = @splat('a');
    text[300] = 'z';
    text[399] = '\n';

    const got = try renderToString(testing.allocator, &text, .{
        .severity = .err,
        .message = "far",
        .labels = &.{.{ .file = .from(0), .span = .{ .start = 300, .end = 301 }, .message = "here" }},
    });
    defer testing.allocator.free(got);

    const rows = try rowsOf(testing.allocator, got);
    defer testing.allocator.free(rows);

    // Cutting the snippet does not move the location: the header names the
    // column in the file, which the snippet no longer starts at.
    try testing.expectEqualStrings(" --> t.lin:1:301", rows[1]);

    // Cut on both sides, since the label sits in the middle of the line.
    try testing.expect(std.mem.indexOf(u8, rows[3], cut_before) != null);
    try testing.expect(std.mem.endsWith(u8, rows[3], cut_after));

    // The caret is under the character the label names, which is what the cut
    // has to preserve to be worth showing at all.
    try testing.expectEqual(
        std.mem.indexOfScalar(u8, rows[3], 'z'),
        std.mem.indexOfScalar(u8, rows[4], '^'),
    );
}

test "two labels too far apart on one line each bring their own snippet" {
    var text: [400]u8 = @splat('a');
    text[399] = '\n';

    const got = try renderToString(testing.allocator, &text, .{
        .severity = .err,
        .message = "two",
        .labels = &.{
            .{ .file = .from(0), .span = .{ .start = 0, .end = 1 }, .message = "first", .style = .secondary },
            .{ .file = .from(0), .span = .{ .start = 350, .end = 351 }, .message = "second", .style = .primary },
        },
    });
    defer testing.allocator.free(got);

    // On a line shown whole these would share one snippet. Here the second
    // label has nowhere to point in the first snippet, so the line is shown
    // twice -- there really are two places to look.
    try testing.expectEqual(@as(usize, 2), std.mem.count(u8, got, "1 | "));
    try testing.expect(std.mem.indexOf(u8, got, "- first") != null);
    try testing.expect(std.mem.indexOf(u8, got, "^ second") != null);
}

test "renders header, location, snippet and caret" {
    const got = try renderToString(testing.allocator, "let x = 1;\nlet y = #;\n", .{
        .severity = .err,
        .code = .s_char,
        .message = "unexpected character '#'",
        .labels = &.{.{ .file = .from(0), .span = .{ .start = 19, .end = 20 }, .message = "not a token" }},
        .notes = &.{"remove it"},
    });
    defer testing.allocator.free(got);

    try testing.expectEqualStrings(
        \\error[S-Char]: unexpected character '#'
        \\ --> t.lin:2:9
        \\  |
        \\2 | let y = #;
        \\  |         ^ not a token
        \\  |
        \\  = help: remove it
        \\
    , got);
}

test "caret width matches the span length" {
    const got = try renderToString(testing.allocator, "let ident = 1;\n", .{
        .severity = .err,
        .message = "bad name",
        .labels = &.{.{ .file = .from(0), .span = .{ .start = 4, .end = 9 }, .message = "here" }},
    });
    defer testing.allocator.free(got);

    try testing.expect(std.mem.indexOf(u8, got, "^^^^^ here") != null);
}

test "diagnostic without a code omits the bracket" {
    const got = try renderToString(testing.allocator, "x\n", .{
        .severity = .warning,
        .message = "plain",
        .labels = &.{.{ .file = .from(0), .span = .{ .start = 0, .end = 1 }, .message = "l" }},
    });
    defer testing.allocator.free(got);

    try testing.expect(std.mem.startsWith(u8, got, "warning: plain\n"));
}

/// Rendering takes a source and spans into it, and a span is as adversarial as
/// a byte: it may be empty, sit at the end of input, cross a newline, or reach
/// past the file. Both faults this renderer has had were of that shape -- a
/// final line reported with its terminator, and a zero-width span at end of
/// input underflowing a width -- and neither was found by a written case.
fn fuzzSpans(_: void, smith: *std.testing.Smith) anyerror!void {
    // Longer than the bound a sink cuts a text to, so a message quoting the
    // whole source is past it rather than short of it: the cut is reached
    // here, not assumed.
    var buf: [1024]u8 = undefined;
    const len = smith.slice(&buf);
    const text = buf[0..len];

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const src: Source = .{ .path = "fuzz.lin", .text = text };
    var table: FileTable = .empty;
    _ = try table.add(gpa, src);
    try table.buildMaps(gpa);
    const map = table.mapOf(.from(0));

    // Offsets are unconstrained on purpose: a caller that computes one wrongly
    // is exactly what this has to survive.
    const a = smith.value(u16) % @max(1, text.len + 1);
    const b = smith.value(u16) % @max(1, text.len + 1);
    const span: Span = .{ .start = @intCast(@min(a, b)), .end = @intCast(@max(a, b)) };

    // Every offset names a line and column, and the line it names contains it.
    const at = map.lineCol(span.start);
    try std.testing.expect(at.line >= 1);
    try std.testing.expect(at.column >= 1);
    try std.testing.expect(at.line <= map.lineCount());

    // A line never carries its own terminator.
    const line = map.lineText(at.line);
    try std.testing.expect(std.mem.indexOfScalar(u8, line, '\n') == null);

    var out: std.Io.Writer.Allocating = .init(gpa);
    var sink = Sink.init(gpa);
    // Every text carries the source, which is what a pass quoting a token it
    // read produces. A message built anywhere in the compiler reaches the
    // renderer through a sink, and the sink is what cuts it.
    try sink.add(.{
        .severity = .err,
        .code = .s_char,
        .message = text,
        .labels = &.{.{ .file = .from(0), .span = span, .message = text, .style = .primary }},
        .notes = &.{text},
    });
    try renderAll(&out.writer, &table, &sink, .{ .color = .never });

    // Nothing the renderer writes scales with the source. A snippet is cut to
    // `max_snippet_columns`, a marker is indented and clamped inside the
    // window it was cut to, and every text a diagnostic carries was cut by the
    // sink -- so a rendered row is bounded whatever line it points into and
    // whatever was written about it. That is what holds one write of a
    // diagnostic under the ceiling a host puts on a single write.
    const gutter = decimalWidth(map.lineCount());
    const widest = gutter + " | ".len + cut_before.len + max_snippet_columns +
        cut_after.len + " ".len + sink_mod.max_text_bytes + sink_mod.truncated.len;
    var rows = std.mem.splitScalar(u8, out.written(), '\n');
    while (rows.next()) |row| try std.testing.expect(row.len <= widest);
}

test "fuzz: rendering any span into any source terminates" {
    // Every input this property has ever failed on, replayed before any
    // new one is tried -- so a crash the fuzzer found once cannot come
    // back unnoticed, and a search starts where the last one got to.
    try std.testing.fuzz({}, fuzzSpans, .{ .corpus = @import("fuzz_corpus").render });
}

test "every input the fuzzer found for this still passes" {
    // Replayed here as well as handed to the fuzzer, because the two run at
    // different times: a search runs nightly and on a push, and this runs
    // whenever anyone builds. A regression that only fails in CI is one
    // somebody finds after they have moved on.
    for (@import("fuzz_corpus").render) |input| {
        var smith: std.testing.Smith = .{ .in = input };
        try fuzzSpans({}, &smith);
    }
}

test "two labels on one line share the source snippet" {
    const src: Source = .{ .path = "t.lin", .text = "let x: UInt8 = 300;\n" };
    var table: FileTable = .empty;
    defer table.deinit(testing.allocator);
    _ = try table.add(testing.allocator, src);
    try table.buildMaps(testing.allocator);

    var out: std.Io.Writer.Allocating = .init(testing.allocator);
    defer out.deinit();

    try render(&out.writer, &table, &.{
        .severity = .err,
        .message = "out of range",
        .labels = &.{
            .{ .file = .from(0), .span = .{ .start = 7, .end = 9 }, .message = "from here", .style = .secondary },
            .{ .file = .from(0), .span = .{ .start = 12, .end = 15 }, .message = "here", .style = .primary },
        },
    }, .{ .color = .never });

    // The line appears once, with a marker row for each label.
    try testing.expectEqual(@as(usize, 1), std.mem.count(u8, out.written(), "let x: UInt8 = 300;"));
    try testing.expect(std.mem.indexOf(u8, out.written(), "-- from here") != null);
    try testing.expect(std.mem.indexOf(u8, out.written(), "^^^ here") != null);
}

test "three labels on one line share it, whatever their columns" {
    const src: Source = .{ .path = "t.lin", .text = "let x: UInt8 = 300;\n" };
    var table: FileTable = .empty;
    defer table.deinit(testing.allocator);
    _ = try table.add(testing.allocator, src);
    try table.buildMaps(testing.allocator);

    var out: std.Io.Writer.Allocating = .init(testing.allocator);
    defer out.deinit();

    try render(&out.writer, &table, &.{
        .severity = .err,
        .message = "three",
        .labels = &.{
            .{ .file = .from(0), .span = .{ .start = 4, .end = 5 }, .message = "a", .style = .secondary },
            // Two at the same column: the snippet is still printed once.
            .{ .file = .from(0), .span = .{ .start = 7, .end = 9 }, .message = "b", .style = .secondary },
            .{ .file = .from(0), .span = .{ .start = 7, .end = 9 }, .message = "c", .style = .primary },
        },
    }, .{ .color = .never });

    try testing.expectEqual(@as(usize, 1), std.mem.count(u8, out.written(), "let x: UInt8 = 300;"));
    for ([_][]const u8{ "- a", "-- b", "^^ c" }) |marker| {
        try testing.expect(std.mem.indexOf(u8, out.written(), marker) != null);
    }
}

test "labels on different lines each carry their source" {
    const src: Source = .{ .path = "t.lin", .text = "fn main() -> UInt8 {\n    x\n}\n" };
    var table: FileTable = .empty;
    defer table.deinit(testing.allocator);
    _ = try table.add(testing.allocator, src);
    try table.buildMaps(testing.allocator);

    var out: std.Io.Writer.Allocating = .init(testing.allocator);
    defer out.deinit();

    try render(&out.writer, &table, &.{
        .severity = .err,
        .message = "mismatch",
        .labels = &.{
            .{ .file = .from(0), .span = .{ .start = 13, .end = 15 }, .message = "expected", .style = .secondary },
            .{ .file = .from(0), .span = .{ .start = 22, .end = 23 }, .message = "found", .style = .primary },
        },
    }, .{ .color = .never });

    try testing.expect(std.mem.indexOf(u8, out.written(), "fn main() -> UInt8 {") != null);
    try testing.expect(std.mem.indexOf(u8, out.written(), "    x") != null);
}

test "diagnostic without labels renders only the header" {
    const got = try renderToString(testing.allocator, "x\n", .{
        .severity = .err,
        .message = "no location",
    });
    defer testing.allocator.free(got);

    try testing.expectEqualStrings("error: no location\n", got);
}

test "a zero-width span at end of input renders" {
    // The position sits past the last character of the line it belongs to,
    // which must not be read as a negative width.
    const got = try renderToString(testing.allocator, "(1 + \n", .{
        .severity = .err,
        .message = "expected an expression",
        .labels = &.{.{ .file = .from(0), .span = .{ .start = 6, .end = 6 }, .message = "here" }},
    });
    defer testing.allocator.free(got);

    try testing.expect(std.mem.indexOf(u8, got, "^ here") != null);
}

test "colour mode emits ANSI codes" {
    const src: Source = .{ .path = "t.lin", .text = "x\n" };
    var table: FileTable = .empty;
    defer table.deinit(testing.allocator);
    _ = try table.add(testing.allocator, src);
    try table.buildMaps(testing.allocator);

    var out: std.Io.Writer.Allocating = .init(testing.allocator);
    defer out.deinit();
    try render(&out.writer, &table, &.{ .severity = .err, .message = "m" }, .{ .color = .always });

    try testing.expect(std.mem.indexOf(u8, out.written(), "\x1b[") != null);
}

test "the order of two labels does not depend on how long another file is" {
    // A span is an offset into its own file, so comparing two from different
    // files orders a diagnostic by a number that means nothing across them.
    // Rendered twice with the second file grown, the order has to hold: what
    // it is about did not change.
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    for ([_][]const u8{ "pub fn f()\n", "// " ++ ("x" ** 200) ++ "\npub fn f()\n" }) |other| {
        var sink = Sink.init(arena.allocator());
        try sink.add(.{
            .severity = .err,
            .message = "m",
            .labels = &.{
                // Built the way a pass builds them: the primary first, and the
                // one saying what required it after.
                .{ .file = .from(0), .span = .{ .start = 5, .end = 6 }, .message = "here", .style = .primary },
                .{ .file = .from(1), .span = .{ .start = @intCast(other.len - 4), .end = @intCast(other.len - 3) }, .message = "there", .style = .secondary },
            },
        });

        var table: FileTable = .empty;
        defer table.deinit(testing.allocator);
        _ = try table.add(testing.allocator, .{ .path = "a.lin", .text = "fn main()\n" });
        _ = try table.add(testing.allocator, .{ .path = "b.lin", .text = other });
        try table.buildMaps(testing.allocator);

        var out: std.Io.Writer.Allocating = .init(arena.allocator());
        try renderAll(&out.writer, &table, &sink, .{ .color = .never });
        const text = out.written();

        // The file the diagnostic points at comes first, and the other is
        // named rather than stacked under it.
        const here = std.mem.indexOf(u8, text, "here").?;
        const there = std.mem.indexOf(u8, text, "there").?;
        try testing.expect(here < there);
        try testing.expect(std.mem.indexOf(u8, text, "::: b.lin") != null);
    }
}
