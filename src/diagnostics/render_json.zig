const std = @import("std");
const testing = std.testing;

const source_mod = @import("../support/source.zig");
const FileTable = @import("../support/source.zig").FileTable;
const Source = source_mod.Source;
const diagnostic = @import("diagnostic.zig");
const Diagnostic = diagnostic.Diagnostic;
const sink_mod = @import("sink.zig");
const Sink = sink_mod.Sink;

/// One object per line, so output streams and diffs a line at a time.
///
/// The texts written here are bounded, and nothing here bounds them: a
/// diagnostic reaches this by having been added to a sink, and the sink cuts
/// every text it is given. Two renderers of the same diagnostics is exactly
/// the arrangement in which a bound written into one of them holds only for
/// that one, which is why the bound is not written into either.
fn renderOne(
    w: *std.Io.Writer,
    table: *const FileTable,
    d: *const Diagnostic,
) std.Io.Writer.Error!void {
    try w.writeAll("{\"severity\":");
    try std.json.Stringify.value(d.severity.text(), .{}, w);

    if (d.code) |c| {
        try w.writeAll(",\"code\":");
        try std.json.Stringify.value(c.ruleName(), .{}, w);
    }

    try w.writeAll(",\"message\":");
    try std.json.Stringify.value(d.message, .{}, w);

    // The file of the primary label: a diagnostic points somewhere, and that
    // is the file a reader opens. Null where the diagnostic carries no label
    // at all, because there is no such file -- naming whichever loaded first
    // is what `Label.file` exists to make impossible, and a consumer reading
    // `null` knows it has been told nothing rather than told something wrong.
    try w.writeAll(",\"file\":");
    if (d.primaryLabel()) |l| {
        try std.json.Stringify.value(table.get(l.file).path, .{}, w);
    } else {
        try w.writeAll("null");
    }

    try w.writeAll(",\"labels\":[");
    for (d.labels, 0..) |l, i| {
        if (i > 0) try w.writeByte(',');
        const pos = table.mapOf(l.file).lineCol(l.span.start);
        // Each label says which file its offsets index. A diagnostic spans
        // several files whenever it explains itself -- a mismatch points at
        // the argument and at the parameter that expected it -- so a label
        // published with offsets and no file is an offset into nothing, and a
        // consumer joining it to the diagnostic's own file opens a real and
        // plausible and wrong location. The human renderer says the same
        // thing with its `:::` line.
        try w.writeAll("{\"file\":");
        try std.json.Stringify.value(table.get(l.file).path, .{}, w);
        try w.print(
            ",\"line\":{d},\"column\":{d},\"start\":{d},\"end\":{d},\"style\":\"{s}\",\"message\":",
            .{ pos.line, pos.column, l.span.start, l.span.end, @tagName(l.style) },
        );
        try std.json.Stringify.value(l.message, .{}, w);
        try w.writeByte('}');
    }
    try w.writeAll("]");

    // Named as the human form prints them: advice is `= help:`, a fact
    // about the problem is `= note:`.
    try w.writeAll(",\"help\":[");
    for (d.notes, 0..) |n, i| {
        if (i > 0) try w.writeByte(',');
        try std.json.Stringify.value(n, .{}, w);
    }
    try w.writeAll("],\"notes\":[");
    for (d.remarks, 0..) |n, i| {
        if (i > 0) try w.writeByte(',');
        try std.json.Stringify.value(n, .{}, w);
    }

    // Each fix names the help it writes by its index in `help`, or null for
    // the primary label's, and each edit says which file its offsets index,
    // for the reason a label does. Applying a fix is writing every one of its
    // edits; they never overlap.
    try w.writeAll("],\"fixes\":[");
    for (d.fixes, 0..) |fix, i| {
        if (i > 0) try w.writeByte(',');
        try w.writeAll("{\"kind\":");
        try std.json.Stringify.value(fix.kind.text(), .{}, w);
        try w.writeAll(",\"help\":");
        if (fix.note) |at| try w.print("{d}", .{at}) else try w.writeAll("null");
        try w.writeAll(",\"edits\":[");
        for (fix.edits, 0..) |e, j| {
            if (j > 0) try w.writeByte(',');
            const pos = table.mapOf(e.file).lineCol(e.span.start);
            try w.writeAll("{\"file\":");
            try std.json.Stringify.value(table.get(e.file).path, .{}, w);
            try w.print(",\"line\":{d},\"column\":{d},\"start\":{d},\"end\":{d},\"text\":", .{ pos.line, pos.column, e.span.start, e.span.end });
            try std.json.Stringify.value(e.text, .{}, w);
            try w.writeByte('}');
        }
        try w.writeAll("]}");
    }
    try w.writeAll("]}\n");
}

pub fn renderAllJson(
    w: *std.Io.Writer,
    table: *const FileTable,
    sink: *const Sink,
) std.Io.Writer.Error!void {
    for (sink.items()) |*d| try renderOne(w, table, d);
}

test "emits one JSON object per diagnostic" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const src: Source = .{ .path = "t.lin", .text = "let y = #;\n" };
    var table: FileTable = .empty;
    defer table.deinit(testing.allocator);
    _ = try table.add(testing.allocator, src);
    try table.buildMaps(testing.allocator);

    var sink = Sink.init(arena.allocator());
    const message = "unexpected character '\"'\n\\\t\x08\x0c";
    try sink.addError(.s_char, .from(0), .{ .start = 8, .end = 9 }, message, "not a token");

    var out: std.Io.Writer.Allocating = .init(testing.allocator);
    defer out.deinit();
    try renderAllJson(&out.writer, &table, &sink);

    const got = out.written();
    try testing.expect(std.mem.endsWith(u8, got, "\n"));
    try testing.expectEqual(@as(usize, 1), std.mem.count(u8, got, "\n"));
    const parsed = try std.json.parseFromSlice(std.json.Value, testing.allocator, got, .{});
    defer parsed.deinit();
    const object = parsed.value.object;
    try testing.expectEqualStrings("S-Char", object.get("code").?.string);
    try testing.expectEqualStrings("error", object.get("severity").?.string);
    try testing.expectEqualStrings(message, object.get("message").?.string);
    const labels = object.get("labels").?.array.items;
    try testing.expectEqual(@as(usize, 1), labels.len);
    try testing.expectEqual(@as(i64, 1), labels[0].object.get("line").?.integer);
    try testing.expectEqual(@as(i64, 9), labels[0].object.get("column").?.integer);
}

test "advice is written under help and a fact under notes, as the human form prints them" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const src: Source = .{ .path = "t.lin", .text = "x\n" };
    var table: FileTable = .empty;
    defer table.deinit(testing.allocator);
    _ = try table.add(testing.allocator, src);
    try table.buildMaps(testing.allocator);

    var sink = Sink.init(arena.allocator());
    try sink.add(.{
        .severity = .err,
        .code = .m_embed_text,
        .message = "not text",
        .labels = &.{.{ .file = .from(0), .span = .{ .start = 0, .end = 1 }, .message = "here" }},
        .notes = &.{"embed it as bytes"},
        .remarks = &.{"at line 1"},
    });
    try sink.addError(.s_char, .from(0), .{ .start = 0, .end = 1 }, "plain", "here");

    var out: std.Io.Writer.Allocating = .init(testing.allocator);
    defer out.deinit();
    try renderAllJson(&out.writer, &table, &sink);

    var lines = std.mem.splitScalar(u8, out.written(), '\n');
    const first = try std.json.parseFromSlice(std.json.Value, testing.allocator, lines.next().?, .{});
    defer first.deinit();
    try testing.expectEqualStrings("embed it as bytes", first.value.object.get("help").?.array.items[0].string);
    try testing.expectEqualStrings("at line 1", first.value.object.get("notes").?.array.items[0].string);
    // Every object has both keys, so a reader needs no case for a missing one.
    const second = try std.json.parseFromSlice(std.json.Value, testing.allocator, lines.next().?, .{});
    defer second.deinit();
    try testing.expectEqual(@as(usize, 0), second.value.object.get("help").?.array.items.len);
    try testing.expectEqual(@as(usize, 0), second.value.object.get("notes").?.array.items.len);
    try testing.expectEqual(@as(usize, 0), second.value.object.get("fixes").?.array.items.len);
}

test "a fix is written with its kind, the help it writes and every edit" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const src: Source = .{ .path = "t.lin", .text = "fn f() {\n}\n" };
    var table: FileTable = .empty;
    defer table.deinit(testing.allocator);
    _ = try table.add(testing.allocator, src);
    try table.buildMaps(testing.allocator);

    var sink = Sink.init(arena.allocator());
    try sink.add(.{
        .severity = .err,
        .code = .t_try_answer,
        .message = "no answer",
        .labels = &.{.{ .file = .from(0), .span = .{ .start = 3, .end = 4 }, .message = "here" }},
        .notes = &.{"make it answer"},
        .fixes = &.{.{ .kind = .answer_type, .note = 0, .edits = &.{
            .{ .file = .from(0), .span = .{ .start = 6, .end = 6 }, .text = " -> UInt8" },
            .{ .file = .from(0), .span = .{ .start = 9, .end = 9 }, .text = "0" },
        } }},
    });

    var out: std.Io.Writer.Allocating = .init(testing.allocator);
    defer out.deinit();
    try renderAllJson(&out.writer, &table, &sink);

    const parsed = try std.json.parseFromSlice(std.json.Value, testing.allocator, out.written(), .{});
    defer parsed.deinit();
    const fixes = parsed.value.object.get("fixes").?.array.items;
    try testing.expectEqual(@as(usize, 1), fixes.len);
    try testing.expectEqualStrings("answer_type", fixes[0].object.get("kind").?.string);
    try testing.expectEqual(@as(i64, 0), fixes[0].object.get("help").?.integer);
    const edits = fixes[0].object.get("edits").?.array.items;
    try testing.expectEqual(@as(usize, 2), edits.len);
    try testing.expectEqualStrings("t.lin", edits[0].object.get("file").?.string);
    try testing.expectEqual(@as(i64, 6), edits[0].object.get("start").?.integer);
    try testing.expectEqualStrings(" -> UInt8", edits[0].object.get("text").?.string);
    try testing.expectEqual(@as(i64, 2), edits[1].object.get("line").?.integer);
    try testing.expectEqual(@as(i64, 1), edits[1].object.get("column").?.integer);
}

test "a message quoting the source does not scale the object it is written in" {
    // The machine-readable form is the second writer of the same texts, and it
    // was the one that stayed unbounded when the human form was cut: an editor
    // asking for JSON got the whole file back inside one object. Nothing is
    // asserted about a bound of its own -- what is asserted is that the sink's
    // bound reaches here, because there is no other way in.
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const long = "Z" ** 8000;
    // One text made of control bytes, because JSON is the form that escapes
    // and a byte can leave here six bytes wide. Escaping multiplies a bound
    // rather than removing one, but a bound asserted only against bytes that
    // pass through unchanged would not have said so.
    const long_control = "\x01" ** 8000;

    const src: Source = .{ .path = "t.lin", .text = "x\n" };
    var table: FileTable = .empty;
    defer table.deinit(testing.allocator);
    _ = try table.add(testing.allocator, src);
    try table.buildMaps(testing.allocator);

    var sink = Sink.init(arena.allocator());
    try sink.add(.{
        .severity = .err,
        .code = .s_char,
        .message = long,
        .labels = &.{.{ .file = .from(0), .span = .{ .start = 0, .end = 1 }, .message = long }},
        .notes = &.{long_control},
    });

    var out: std.Io.Writer.Allocating = .init(testing.allocator);
    defer out.deinit();
    try renderAllJson(&out.writer, &table, &sink);

    const got = out.written();
    try testing.expectEqual(@as(usize, 3), std.mem.count(u8, got, sink_mod.truncated));
    try testing.expectEqual(@as(usize, 2 * sink_mod.max_text_bytes), std.mem.count(u8, got, "Z"));
    try testing.expectEqual(@as(usize, sink_mod.max_text_bytes), std.mem.count(u8, got, "\\u0001"));

    // One object is one line, so the line is what a reader's parser is handed
    // in one piece. Everything else on it -- the code, the path, four numbers,
    // a style and the punctuation between them -- is fixed or bounded by the
    // filesystem, so three bounded texts make a bounded object.
    const skeleton = 256;
    const escaped = 6 * (sink_mod.max_text_bytes + sink_mod.truncated.len);
    const widest = skeleton + src.path.len + 3 * escaped;
    try testing.expect(got.len <= widest);
}
