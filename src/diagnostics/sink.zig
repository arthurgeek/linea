const std = @import("std");
const testing = std.testing;

const Span = @import("../support/span.zig").Span;
const diagnostic = @import("diagnostic.zig");
const Code = diagnostic.Code;
const Diagnostic = diagnostic.Diagnostic;
const Label = diagnostic.Label;
const Edit = diagnostic.Edit;
const Fix = diagnostic.Fix;
const FileId = @import("../support/source.zig").FileId;

/// The most of one text a diagnostic carries.
///
/// A snippet is cut out of the source by the renderer, so bounding it is a
/// matter of where the cut is made. A message is not: it arrives already built
/// by whichever pass raised it, and a pass quotes what it read -- `undefined
/// name `x`` names a token, so a token as long as the file is a message as
/// long as the file. The same holds for a label's message and for a note.
///
/// Wide enough that no message the compiler writes comes near it, so an
/// ordinary diagnostic reads exactly as it did. What it forbids is the one
/// shape that scales: a message carrying the file it was written about.
pub const max_text_bytes: usize = 512;

/// Written where a text was cut. A reader who cannot see the rest has to be
/// told there is a rest, or a cut message reads as a whole one.
pub const truncated = " ... (truncated)";

/// Accumulates diagnostics for one compilation.
///
/// Passes report and continue; only the driver decides to stop, and only
/// between passes.
///
/// Every text a diagnostic carries is cut to `max_text_bytes` on the way in,
/// except a fix's edits, each fix kept whole or dropped.
/// The bound sits here rather than in a renderer because a renderer is not the
/// only one: the human form and the JSON form are two writers of the same
/// text, and a bound written into one of them says nothing about the other. A
/// diagnostic reaches every consumer through this type, so cutting at the door
/// is what leaves no route around it -- including routes not written yet.
///
/// The sink does not own message strings: callers pass literals or memory from
/// the same arena, and a text short enough to keep is stored as it arrived. A
/// text over the bound is the one case that allocates, since the cut form has
/// to be somewhere.
pub const Sink = struct {
    arena: std.mem.Allocator,
    list: std.ArrayList(Diagnostic) = .empty,
    error_count: u32 = 0,
    warning_count: u32 = 0,

    pub fn init(arena: std.mem.Allocator) Sink {
        return .{ .arena = arena };
    }

    pub fn add(self: *Sink, d: Diagnostic) !void {
        switch (d.severity) {
            .err => self.error_count += 1,
            .warning => self.warning_count += 1,
            .note => {},
        }

        try self.list.append(self.arena, try self.bounded(d));
    }

    /// `d` with every text it carries within the bound.
    fn bounded(self: *Sink, d: Diagnostic) !Diagnostic {
        var within = d;
        within.message = try cut(self.arena, d.message);
        within.labels = try cutLabels(self.arena, d.labels);
        within.notes = try cutNotes(self.arena, d.notes);
        within.remarks = try cutNotes(self.arena, d.remarks);
        within.fixes = try boundFixes(self.arena, d.fixes, d.notes.len);
        return within;
    }

    /// Replaces the diagnostic at `at` with `d`, a revision of it that a
    /// pass amended with a label, a note or a fix: cut as `add` cuts, so an
    /// amendment is held to the bound too. The severity is the one it had,
    /// so the totals stand.
    pub fn revise(self: *Sink, at: usize, d: Diagnostic) !void {
        std.debug.assert(d.severity == self.list.items[at].severity);
        self.list.items[at] = try self.bounded(d);
    }

    /// Replaces every diagnostic with `kept`, counted and cut as `add`
    /// counts and cuts them. `kept` may be a slice of `items()`.
    pub fn replaceAll(self: *Sink, kept: []const Diagnostic) !void {
        const copied = try self.arena.dupe(Diagnostic, kept);
        self.list.clearRetainingCapacity();
        self.error_count = 0;
        self.warning_count = 0;
        for (copied) |d| try self.add(d);
    }

    /// One error with a single primary label, which is the common shape.
    pub fn addError(
        self: *Sink,
        code: Code,
        file: FileId,
        span: Span,
        message: []const u8,
        label: []const u8,
    ) !void {
        const labels = try self.arena.alloc(Label, 1);
        labels[0] = .{ .file = file, .span = span, .message = label, .style = .primary };
        try self.add(.{
            .severity = .err,
            .code = code,
            .message = message,
            .labels = labels,
        });
    }

    /// One note with a single label. A note counts towards neither total, so
    /// it describes a hazard without deciding whether the build stops.
    pub fn addNote(
        self: *Sink,
        code: Code,
        file: FileId,
        span: Span,
        message: []const u8,
        label: []const u8,
    ) !void {
        const labels = try self.arena.alloc(Label, 1);
        labels[0] = .{ .file = file, .span = span, .message = label, .style = .primary };
        try self.add(.{
            .severity = .note,
            .code = code,
            .message = message,
            .labels = labels,
        });
    }

    /// As `addError`, with the message formatted into the arena.
    pub fn addErrorFmt(
        self: *Sink,
        code: Code,
        file: FileId,
        span: Span,
        label: []const u8,
        comptime fmt: []const u8,
        args: anytype,
    ) !void {
        const message = try std.fmt.allocPrint(self.arena, fmt, args);
        try self.addError(code, file, span, message, label);
    }

    pub fn items(self: *const Sink) []const Diagnostic {
        return self.list.items;
    }

    pub fn hasErrors(self: *const Sink) bool {
        return self.error_count > 0;
    }
};

/// `text` if it is within the bound, and a cut copy of it saying so if not.
fn cut(arena: std.mem.Allocator, text: []const u8) ![]const u8 {
    if (text.len <= max_text_bytes) return text;

    // Cut on a scalar boundary. The text quotes the source, so the byte at the
    // bound may be the middle of a character, and half a character is not
    // text -- continuation bytes are 0b10xxxxxx, so backing up over them lands
    // on the start of the character the bound fell inside.
    var end = max_text_bytes;
    while (end > 0 and text[end] & 0xC0 == 0x80) end -= 1;

    return std.mem.concat(arena, u8, &.{ text[0..end], truncated });
}

/// The fixes, without each one an edit of which is over the bound.
///
/// An edit is source a tool writes, and half a clause does not parse, so a
/// fix is kept whole or dropped rather than cut; its help is a note, and is
/// cut as any note is. The array is rebuilt only when a fix is dropped.
///
/// Every diagnostic `add` and `revise` store passes here, so this is where a
/// fix is held to what `Fix` promises: its `note` is one of the `notes`
/// count helps, and its edits never overlap. A fix breaking either is the
/// compiler's mistake, not the program's.
fn boundFixes(arena: std.mem.Allocator, fixes: []const Fix, notes: usize) ![]const Fix {
    for (fixes) |fix| assertHolds(fix, notes);
    const within = struct {
        fn check(fix: Fix) bool {
            for (fix.edits) |e| if (e.text.len > max_text_bytes) return false;
            return true;
        }
    }.check;
    var over = false;
    for (fixes) |fix| over = over or !within(fix);
    if (!over) return fixes;
    var kept: std.ArrayList(Fix) = .empty;
    for (fixes) |fix| if (within(fix)) try kept.append(arena, fix);
    return kept.items;
}

/// That `fix` writes one of `notes` helps, or its primary label's, and that
/// no two of its edits touch the same bytes of one file. Two insertions at
/// one byte overlap too: which is written first is a choice the fix did not
/// make.
///
/// **Bound:** the square of the fix's edits, a handful.
fn assertHolds(fix: Fix, notes: usize) void {
    if (fix.note) |at| std.debug.assert(at < notes);
    for (fix.edits, 0..) |a, i| for (fix.edits[i + 1 ..]) |b| {
        if (a.file != b.file) continue;
        const overlap = a.span.start == b.span.start or (a.span.start < b.span.end and b.span.start < a.span.end);
        std.debug.assert(!overlap);
    };
}

/// The labels, with every message within the bound.
///
/// The array is rebuilt only when some message is over it, so the ordinary
/// diagnostic -- every message short, which is every message the compiler
/// writes by hand -- keeps the array the caller built and allocates nothing.
/// Each label is copied whole and only its message replaced, so a field added
/// to `Label` is carried rather than dropped.
fn cutLabels(arena: std.mem.Allocator, labels: []const Label) ![]const Label {
    var over = false;
    for (labels) |l| over = over or l.message.len > max_text_bytes;
    if (!over) return labels;

    const out = try arena.alloc(Label, labels.len);
    for (out, labels) |*o, l| {
        o.* = l;
        o.message = try cut(arena, l.message);
    }
    return out;
}

/// The notes, with every one within the bound. Rebuilt only when one is over.
fn cutNotes(arena: std.mem.Allocator, notes: []const []const u8) ![]const []const u8 {
    var over = false;
    for (notes) |n| over = over or n.len > max_text_bytes;
    if (!over) return notes;

    const out = try arena.alloc([]const u8, notes.len);
    for (out, notes) |*o, n| o.* = try cut(arena, n);
    return out;
}

test "sink accumulates and counts by severity" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    var sink = Sink.init(arena.allocator());
    try sink.addError(.s_char, .from(0), .{ .start = 0, .end = 1 }, "bad byte", "not a token");
    try sink.add(.{ .severity = .warning, .message = "suspicious" });

    try testing.expectEqual(@as(usize, 2), sink.items().len);
    try testing.expectEqual(@as(u32, 1), sink.error_count);
    try testing.expectEqual(@as(u32, 1), sink.warning_count);
    try testing.expect(sink.hasErrors());
}

test "addErrorFmt formats the message into the arena" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    var sink = Sink.init(arena.allocator());
    try sink.addErrorFmt(
        .s_char,
        .from(0),
        .{ .start = 2, .end = 3 },
        "not a token",
        "unexpected character '{c}'",
        .{'#'},
    );

    try testing.expectEqualStrings("unexpected character '#'", sink.items()[0].message);
}

test "a text built from the source is cut on the way in, and says that it was" {
    // The shape this exists for: a pass quoting a token it read. `undefined
    // name `x`` is one message with one token in it, so an identifier as long
    // as the file is a message as long as the file, and a renderer cutting the
    // snippet says nothing about it -- the text arrives already built.
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const long = "Z" ** 4000;
    var sink = Sink.init(arena.allocator());
    try sink.add(.{
        .severity = .err,
        .message = long,
        .labels = &.{.{ .file = .from(0), .span = .{ .start = 0, .end = 1 }, .message = long }},
        .notes = &.{long},
        .remarks = &.{long},
    });

    // Four places one message can be written, and the sink is upstream of all
    // of them, so each is bounded before any renderer sees it.
    const d = sink.items()[0];
    for ([_][]const u8{ d.message, d.labels[0].message, d.notes[0], d.remarks[0] }) |text| {
        try testing.expectEqual(max_text_bytes + truncated.len, text.len);
        try testing.expect(std.mem.endsWith(u8, text, truncated));
    }
}

test "a text at the bound is kept whole, and one byte past it is cut" {
    // A bound is wrong at exactly one length either way, so both are named.
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    for ([_]usize{ max_text_bytes, max_text_bytes + 1 }) |len| {
        const message = try arena.allocator().alloc(u8, len);
        @memset(message, 'Z');

        var sink = Sink.init(arena.allocator());
        try sink.add(.{ .severity = .err, .message = message });

        const got = sink.items()[0].message;
        const was_cut = len > max_text_bytes;
        try testing.expectEqual(was_cut, std.mem.endsWith(u8, got, truncated));
        try testing.expectEqual(
            if (was_cut) max_text_bytes else len,
            std.mem.count(u8, got, "Z"),
        );
    }
}

test "a cut falls on a character boundary, not inside one" {
    // A message quotes the source, and the source is bytes: the bound can land
    // in the middle of a character, and half a character is not text.
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    var sink = Sink.init(arena.allocator());
    try sink.add(.{
        .severity = .err,
        .message = "Z" ** (max_text_bytes - 1) ++ "é" ++ "Z" ** 8,
    });

    // The two-byte character straddles the bound, so it is dropped whole
    // rather than half-written.
    const got = sink.items()[0].message;
    try testing.expectEqual(@as(usize, max_text_bytes - 1), std.mem.count(u8, got, "Z"));
    try testing.expect(std.mem.indexOf(u8, got, "é") == null);
    try testing.expect(std.unicode.utf8ValidateSlice(got));
}

test "a diagnostic within the bound is stored as it arrived" {
    // Cutting must cost nothing in the ordinary case, which is every message
    // the compiler writes by hand: the texts are handed on unchanged and the
    // arrays the caller built are kept rather than rebuilt.
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const labels: []const Label = &.{
        .{ .file = .from(0), .span = .{ .start = 0, .end = 1 }, .message = "here" },
    };
    const notes: []const []const u8 = &.{"try this"};

    var sink = Sink.init(arena.allocator());
    try sink.add(.{ .severity = .err, .message = "boom", .labels = labels, .notes = notes });

    const d = sink.items()[0];
    try testing.expectEqual(labels.ptr, d.labels.ptr);
    try testing.expectEqual(notes.ptr, d.notes.ptr);
    try testing.expectEqual(@as([*]const u8, "boom"), d.message.ptr);
}

test "every text a diagnostic carries is one the sink cuts" {
    // The bound is on adding, not on the passes that build messages, so it
    // holds only while every text a diagnostic can carry is cut by `add`.
    // These are the fields that carry one; a field added to either type is a
    // text nobody bounded, and this is what stops it landing quietly.
    //
    // A file's path is not among them and is deliberately not cut: it is
    // bounded by what the filesystem will open, never by the source, and a cut
    // one would leave a diagnostic naming a place that cannot be found.
    const expected_diagnostic = [_][]const u8{ "severity", "code", "message", "labels", "notes", "remarks", "fixes" };
    const expected_label = [_][]const u8{ "file", "span", "message", "style" };
    const expected_fix = [_][]const u8{ "kind", "note", "edits" };
    const expected_edit = [_][]const u8{ "file", "span", "text" };

    const d_fields = @typeInfo(Diagnostic).@"struct".fields;
    const l_fields = @typeInfo(Label).@"struct".fields;
    const f_fields = @typeInfo(Fix).@"struct".fields;
    const e_fields = @typeInfo(Edit).@"struct".fields;

    try testing.expectEqual(expected_diagnostic.len, d_fields.len);
    try testing.expectEqual(expected_label.len, l_fields.len);
    try testing.expectEqual(expected_fix.len, f_fields.len);
    try testing.expectEqual(expected_edit.len, e_fields.len);
    inline for (d_fields, expected_diagnostic) |f, name| try testing.expectEqualStrings(name, f.name);
    inline for (l_fields, expected_label) |f, name| try testing.expectEqualStrings(name, f.name);
    inline for (f_fields, expected_fix) |f, name| try testing.expectEqualStrings(name, f.name);
    inline for (e_fields, expected_edit) |f, name| try testing.expectEqualStrings(name, f.name);
}

test "a fix with an edit over the bound is dropped whole, and its help kept" {
    // A cut edit would write half a clause into the source, so a fix is
    // carried whole or not at all; the help's prose is cut like any note.
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const span: Span = .{ .start = 0, .end = 0 };
    const long = try a.alloc(u8, max_text_bytes + 1);
    @memset(long, 'a');
    const short = "a" ** max_text_bytes;
    const kept: []const Edit = &.{.{ .file = .from(0), .span = span, .text = short }};
    const over: []const Edit = &.{ .{ .file = .from(0), .span = span, .text = short }, .{ .file = .from(0), .span = .{ .start = 1, .end = 1 }, .text = long } };

    var sink = Sink.init(a);
    try sink.add(.{
        .severity = .err,
        .message = "boom",
        .notes = &.{ "write the clause", "write the other clause" },
        .fixes = &.{ .{ .kind = .where_clause, .note = 0, .edits = kept }, .{ .kind = .where_clause, .note = 1, .edits = over } },
    });

    const d = sink.items()[0];
    try testing.expectEqual(@as(usize, 1), d.fixes.len);
    try testing.expectEqual(@as(?u32, 0), d.fixes[0].note);
    try testing.expectEqual(@as(usize, 2), d.notes.len);
}

test "a revised diagnostic is cut as an added one is, and keeps the totals" {
    // A pass that adds a label or a note to a report it already made writes
    // text quoting the source, which the bound holds to as it holds `add`.
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    var sink = Sink.init(arena.allocator());
    try sink.add(.{ .severity = .err, .message = "boom" });
    var revised = sink.items()[0];
    revised.notes = &.{"Z" ** (max_text_bytes + 1)};
    try sink.revise(0, revised);

    try testing.expectEqual(max_text_bytes + truncated.len, sink.items()[0].notes[0].len);
    try testing.expectEqual(@as(u32, 1), sink.error_count);
}

test "replacing every diagnostic recounts and cuts them" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    var sink = Sink.init(arena.allocator());
    try sink.add(.{ .severity = .err, .message = "one" });
    try sink.add(.{ .severity = .warning, .message = "two" });
    try sink.add(.{ .severity = .err, .message = "three" });
    try sink.replaceAll(&.{ .{ .severity = .err, .message = "Z" ** (max_text_bytes + 1) }, sink.items()[1] });

    try testing.expectEqual(@as(usize, 2), sink.items().len);
    try testing.expectEqual(@as(u32, 1), sink.error_count);
    try testing.expectEqual(@as(u32, 1), sink.warning_count);
    try testing.expectEqual(max_text_bytes + truncated.len, sink.items()[0].message.len);
}

test "empty sink has no errors" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    var sink = Sink.init(arena.allocator());
    try testing.expect(!sink.hasErrors());
    try testing.expectEqual(@as(usize, 0), sink.items().len);
}
