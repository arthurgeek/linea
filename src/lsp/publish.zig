const std = @import("std");
const testing = std.testing;
const lsp = @import("lsp");

const analysis_mod = @import("analysis.zig");
const test_library = @import("../driver/test_library.zig");
const Analysis = analysis_mod.Analysis;
const uri_mod = @import("uri.zig");
const diagnostic = @import("../diagnostics/diagnostic.zig");
const Diagnostic = diagnostic.Diagnostic;
const Label = diagnostic.Label;
const Severity = diagnostic.Severity;
const positions = @import("positions.zig");
const FileId = @import("../support/source.zig").FileId;
const Program = @import("../syntax/program.zig").Program;

/// Iterates over non-library source files eligible for diagnostic publication.
/// Scans the program's modules and files once, using two indexes and no list.
pub const Files = struct {
    program: *const Program,
    module: usize = 0,
    file: usize = 0,

    pub fn next(self: *Files) ?FileId {
        while (self.module < self.program.modules.len) {
            const m = self.program.modules[self.module];
            if (m.library or self.file == m.files.len) {
                self.module += 1;
                self.file = 0;
                continue;
            }
            defer self.file += 1;
            return m.files[self.file];
        }
        return null;
    }
};

pub fn files(program: *const Program) Files {
    return .{ .program = program };
}

/// Diagnostics grouped by the source file their primary label names.
///
/// Prepared once per publication, then borrowed by every file conversion.
/// The analysis and its sink remain immutable while this value is used. The
/// message arena owns the index and every converted diagnostic; the index
/// points into the analysis rather than copying its messages or labels.
///
/// O(files + diagnostics + labels) preparation and O(files + diagnostics)
/// storage. Each file reads only its own run, in the sink's original order.
/// File identity is the label's recorded FileId, never a path-derived answer.
pub const Publication = struct {
    checked: *const Analysis,
    starts: []const usize,
    grouped: []const *const Diagnostic,

    pub fn init(gpa: std.mem.Allocator, checked: *const Analysis) !Publication {
        if (checked.sink.items().len == 0) return .{ .checked = checked, .starts = &.{}, .grouped = &.{} };
        const file_count = checked.table.count();
        const starts = try gpa.alloc(usize, file_count + 1);
        errdefer gpa.free(starts);
        @memset(starts, 0);
        for (checked.sink.items()) |*d| {
            const primary = d.primaryLabel() orelse continue;
            // Skip primary labels outside the publishable file table.
            if (primary.file.index() >= file_count) continue;
            starts[primary.file.index() + 1] += 1;
        }
        for (1..starts.len) |i| starts[i] += starts[i - 1];

        const grouped = try gpa.alloc(*const Diagnostic, starts[file_count]);
        errdefer gpa.free(grouped);
        const cursor = try gpa.dupe(usize, starts[0..file_count]);
        defer gpa.free(cursor);
        for (checked.sink.items()) |*d| {
            const primary = d.primaryLabel() orelse continue;
            const file = primary.file.index();
            if (file >= file_count) continue;
            grouped[cursor[file]] = d;
            cursor[file] += 1;
        }
        return .{ .checked = checked, .starts = starts, .grouped = grouped };
    }

    /// The compiler's diagnostics `forFile` converts for `file`, in the same
    /// order, so the two can be read side by side.
    pub fn reportedIn(self: Publication, file: FileId) []const *const Diagnostic {
        const i = file.index();
        if (self.starts.len == 0 or i >= self.starts.len - 1) return &.{};
        return self.grouped[self.starts[i]..self.starts[i + 1]];
    }

    /// Converts this file's diagnostics to LSP format in sink order, matching
    /// the order rendered by `check`. Rule names, messages, severities and
    /// spans come from the reporting pass; only their representation changes.
    ///
    /// Use the caller's message arena for the result and its nested label
    /// lists, so all publication allocations can be released together.
    pub fn forFile(
        self: Publication,
        gpa: std.mem.Allocator,
        file: FileId,
        encoding: lsp.offsets.Encoding,
    ) ![]const lsp.types.Diagnostic {
        const checked = self.checked;
        const i = file.index();
        if (self.starts.len == 0 or i >= self.starts.len - 1) return &.{};
        // Gather all primary and related-label offsets before conversion,
        // allowing one scan per referenced file instead of one per offset.
        var reported: std.ArrayList(Reported) = .empty;
        defer reported.deinit(gpa);
        var asked: std.ArrayList(Asked) = .empty;
        defer asked.deinit(gpa);

        for (self.grouped[self.starts[i]..self.starts[i + 1]]) |d| {
            const primary = d.primaryLabel().?;

            const at: u32 = @intCast(asked.items.len);
            try asked.append(gpa, .{ .file = primary.file, .offset = primary.span.start });
            try asked.append(gpa, .{ .file = primary.file, .offset = primary.span.end });

            // Preserve every related label, including the explanation of a
            // [T-Mismatch]. Each label needs a Location because it may refer
            // to another file.
            var it: Others = .{ .labels = d.labels };
            while (it.next()) |l| {
                try asked.append(gpa, .{ .file = l.file, .offset = l.span.start });
                try asked.append(gpa, .{ .file = l.file, .offset = l.span.end });
            }

            try reported.append(gpa, .{ .of = d, .at = at });
        }

        const at = try positionsOf(gpa, checked, asked.items, encoding);
        defer gpa.free(at);

        const out = try gpa.alloc(lsp.types.Diagnostic, reported.items.len);
        for (out, reported.items) |*entry, r| {
            const related = try gpa.alloc(lsp.types.Diagnostic.RelatedInformation, r.of.labels.len - 1);
            var seen: u32 = 0;
            var it: Others = .{ .labels = r.of.labels };
            while (it.next()) |l| : (seen += 1) {
                related[seen] = .{
                    .location = .{
                        .uri = try uri_mod.uriOf(gpa, checked.table.get(l.file).path),
                        .range = .{
                            .start = at[r.at + 2 + seen * 2],
                            .end = at[r.at + 3 + seen * 2],
                        },
                    },
                    .message = l.message,
                };
            }

            entry.* = .{
                .range = .{ .start = at[r.at], .end = at[r.at + 1] },
                .severity = severityOf(r.of.severity),
                .code = if (r.of.code) |c| .{ .string = c.ruleName() } else null,
                .source = "linea",
                .message = r.of.message,
                .relatedInformation = if (related.len == 0) null else related,
            };
        }

        return out;
    }
};

/// A diagnostic and its first index in the gathered offsets: two offsets for
/// the primary range, followed by two for each related label.
const Reported = struct {
    of: *const Diagnostic,
    at: u32,
};

/// A byte offset and its source file, retained for cross-file label conversion.
const Asked = struct {
    file: FileId,
    offset: u32,
};

/// Iterates over every label except the first primary label, whose range is
/// already published. Gathering offsets and emitting related information use
/// this same traversal so duplicate labels retain matching positions.
const Others = struct {
    labels: []const Label,
    at: usize = 0,
    gave_the_range: bool = false,

    fn next(self: *Others) ?Label {
        while (self.at < self.labels.len) {
            const l = self.labels[self.at];
            self.at += 1;
            if (!self.gave_the_range and l.style == .primary) {
                self.gave_the_range = true;
                continue;
            }
            return l;
        }
        return null;
    }
};

/// Converts byte offsets to protocol positions using the requested encoding
/// through `lsp.offsets`, preserving the input order. UTF-16 positions count
/// code units, which can differ from byte offsets and rendered columns.
///
/// Grouping by file and sorting offsets permits one scan per referenced file.
/// For k offsets, this costs O(text + k log k), where text is the combined
/// size of those files, instead of O(text * k) independent conversions.
fn positionsOf(
    gpa: std.mem.Allocator,
    checked: *const Analysis,
    asked: []const Asked,
    encoding: lsp.offsets.Encoding,
) ![]lsp.types.Position {
    const out = try gpa.alloc(lsp.types.Position, asked.len);
    errdefer gpa.free(out);

    const order = try gpa.alloc(u32, asked.len);
    defer gpa.free(order);
    for (order, 0..) |*o, i| o.* = @intCast(i);

    std.mem.sortUnstable(u32, order, asked, struct {
        fn before(all: []const Asked, a: u32, b: u32) bool {
            return all[a].file.index() < all[b].file.index();
        }
    }.before);

    var offsets: std.ArrayList(u32) = .empty;
    defer offsets.deinit(gpa);

    var from: usize = 0;
    while (from < order.len) {
        const of = asked[order[from]].file;
        var to = from;
        while (to < order.len and asked[order[to]].file == of) to += 1;

        offsets.clearRetainingCapacity();
        for (order[from..to]) |i| try offsets.append(gpa, asked[i].offset);

        const found = try positions.positionsOf(gpa, checked.table.get(of).text, offsets.items, encoding);
        defer gpa.free(found);
        for (order[from..to], found) |i, p| out[i] = p;

        from = to;
    }

    return out;
}

/// Maps the reporting pass's severity to the corresponding LSP enumeration.
fn severityOf(severity: Severity) lsp.types.Diagnostic.Severity {
    return switch (severity) {
        .err => .Error,
        .warning => .Warning,
        .note => .Information,
    };
}

test "a diagnostic is published as the rule, the range and the labels it carries" {
    const gpa = testing.allocator;
    var messages = std.heap.ArenaAllocator.init(gpa);
    defer messages.deinit();

    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{
        .{ .path = "main.lin", .text = "fn main() -> UInt8 {\n    let x: UInt8 = true\n    x\n}\n" },
    }, "main.lin");
    defer checked.deinit();

    const publication = try Publication.init(messages.allocator(), &checked);
    const published = try publication.forFile(messages.allocator(), checked.fileNamed("main.lin").?, .@"utf-16");

    try testing.expect(published.len > 0);
    const first = published[0];
    try testing.expectEqualStrings("T-Mismatch", first.code.?.string);
    try testing.expectEqual(lsp.types.Diagnostic.Severity.Error, first.severity.?);

    // `true` sits on the second line, nineteen UTF-16 code units in.
    try testing.expectEqual(@as(u32, 1), first.range.start.line);
    try testing.expectEqual(@as(u32, 19), first.range.start.character);
    try testing.expectEqual(@as(u32, 23), first.range.end.character);
}

test "a position counts UTF-16 code units, not bytes" {
    const gpa = testing.allocator;
    var messages = std.heap.ArenaAllocator.init(gpa);
    defer messages.deinit();

    // An earlier source line contains an em-dash: three bytes, one UTF-16 unit.
    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{
        .{ .path = "main.lin", .text = "fn main() -> UInt8 {\n    // — \n    nope\n}\n" },
    }, "main.lin");
    defer checked.deinit();

    const publication = try Publication.init(messages.allocator(), &checked);
    const published = try publication.forFile(messages.allocator(), checked.fileNamed("main.lin").?, .@"utf-16");

    try testing.expectEqual(@as(usize, 1), published.len);
    try testing.expectEqualStrings("N-Undefined", published[0].code.?.string);
    try testing.expectEqual(@as(u32, 2), published[0].range.start.line);
    try testing.expectEqual(@as(u32, 4), published[0].range.start.character);
}

test "a file with nothing wrong publishes an empty list" {
    const gpa = testing.allocator;
    var messages = std.heap.ArenaAllocator.init(gpa);
    defer messages.deinit();

    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{
        .{ .path = "main.lin", .text = "fn main() -> UInt8 {\n    0\n}\n" },
    }, "main.lin");
    defer checked.deinit();

    const publication = try Publication.init(messages.allocator(), &checked);
    const published = try publication.forFile(messages.allocator(), checked.fileNamed("main.lin").?, .@"utf-16");

    try testing.expectEqual(@as(usize, 0), published.len);
}

test "publication preserves per-file sink order and cross-file related labels" {
    const gpa = testing.allocator;
    var messages = std.heap.ArenaAllocator.init(gpa);
    defer messages.deinit();
    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{
        .{ .path = "app/a.lin", .text = "fn main() -> UInt8 { 0 }\n" },
        .{ .path = "app/b.lin", .text = "// éb\n" },
        .{ .path = "app/c.lin", .text = "// clean\n" },
    }, "app");
    defer checked.deinit();
    try testing.expectEqual(@as(usize, 0), checked.sink.items().len);
    checked.sink = .init(checked.arena.allocator());

    const first: FileId = checked.fileNamed("app/a.lin").?;
    const second: FileId = checked.fileNamed("app/b.lin").?;
    try testing.expectEqualStrings("app/a.lin", checked.table.get(first).path);
    try testing.expectEqualStrings("app/b.lin", checked.table.get(second).path);
    try checked.sink.addError(.n_undefined, second, .{ .start = 3, .end = 6 }, "first in b", "b");
    try checked.sink.add(.{
        .severity = .err,
        .code = .t_mismatch,
        .message = "first in a",
        .labels = &.{
            .{ .file = second, .span = .{ .start = 3, .end = 6 }, .message = "see sibling", .style = .secondary },
            .{ .file = first, .span = .{ .start = 0, .end = 2 }, .message = "a" },
            .{ .file = first, .span = .{ .start = 0, .end = 2 }, .message = "a" },
        },
    });
    try checked.sink.addError(.n_undefined, second, .{ .start = 3, .end = 6 }, "second in b", "b");
    try checked.sink.addError(.n_undefined, first, .{ .start = 0, .end = 2 }, "second in a", "a");
    try checked.sink.add(.{ .severity = .note, .message = "no source label" });
    try checked.sink.add(.{
        .severity = .note,
        .message = "only a secondary label",
        .labels = &.{.{ .file = first, .span = .{ .start = 0, .end = 2 }, .message = "context", .style = .secondary }},
    });
    const outside = try checked.sink.arena.alloc(Label, 1);
    outside[0] = .{
        .file = .from(checked.table.count()),
        .span = .{ .start = 0, .end = 2 },
        .message = "outside the loaded files",
    };
    try checked.sink.add(.{ .severity = .note, .message = "no publishable primary", .labels = outside });

    const publication = try Publication.init(messages.allocator(), &checked);
    const a = try publication.forFile(messages.allocator(), first, .@"utf-16");
    const b = try publication.forFile(messages.allocator(), second, .@"utf-16");
    const c = try publication.forFile(messages.allocator(), .from(2), .@"utf-16");
    try testing.expectEqual(@as(usize, 2), a.len);
    try testing.expectEqual(@as(usize, 2), b.len);
    try testing.expectEqual(@as(usize, 0), c.len);
    try testing.expectEqualStrings("first in a", a[0].message);
    try testing.expectEqualStrings("second in a", a[1].message);
    try testing.expectEqualStrings("first in b", b[0].message);
    try testing.expectEqualStrings("second in b", b[1].message);
    const related = a[0].relatedInformation.?;
    try testing.expectEqual(@as(usize, 2), related.len);
    try testing.expect(std.mem.endsWith(u8, related[0].location.uri, "app/b.lin"));
    try testing.expectEqualStrings("see sibling", related[0].message);
    try testing.expectEqual(@as(u32, 3), related[0].location.range.start.character);
    try testing.expectEqual(@as(u32, 5), related[0].location.range.end.character);
    try testing.expect(std.mem.endsWith(u8, related[1].location.uri, "app/a.lin"));
    try testing.expectEqualStrings("a", related[1].message);
    try testing.expectEqual(@as(u32, 0), related[1].location.range.start.character);
    try testing.expectEqual(@as(u32, 2), related[1].location.range.end.character);
}

test "publication keeps every label except the first primary as related information" {
    const gpa = testing.allocator;
    var checked = try analysis_mod.of(gpa, gpa, test_library.get(), &.{
        .{ .path = "main.lin", .text = "fn main() -> UInt8 { 0 }\n" },
    }, "main.lin");
    defer checked.deinit();
    try testing.expect(!checked.sink.hasErrors());

    const primary: Label = .{ .file = checked.fileNamed("main.lin").?, .span = .{ .start = 3, .end = 7 }, .message = "primary" };
    checked.sink = .init(checked.arena.allocator());
    try checked.sink.add(.{
        .severity = .note,
        .message = "labels",
        .labels = &.{
            .{ .file = checked.fileNamed("main.lin").?, .span = .{ .start = 20, .end = 21 }, .message = "secondary", .style = .secondary },
            primary,
            primary,
        },
    });
    const publication = try Publication.init(checked.arena.allocator(), &checked);
    const published = try publication.forFile(checked.arena.allocator(), checked.fileNamed("main.lin").?, .@"utf-16");
    try testing.expectEqual(@as(usize, 1), published.len);
    const report = published[0];
    try testing.expectEqual(@as(u32, 3), report.range.start.character);
    try testing.expectEqual(@as(u32, 7), report.range.end.character);
    const related = report.relatedInformation.?;
    try testing.expectEqual(@as(usize, 2), related.len);
    try testing.expectEqualStrings("secondary", related[0].message);
    try testing.expectEqual(@as(u32, 20), related[0].location.range.start.character);
    try testing.expectEqualStrings("primary", related[1].message);
    try testing.expectEqual(report.range, related[1].location.range);
}
