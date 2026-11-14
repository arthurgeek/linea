const std = @import("std");
const testing = std.testing;
const Span = @import("span.zig").Span;

/// The largest a source may be.
///
/// Half of what a span's offset can hold, and derived from that field rather
/// than written down beside it, because a cap stated in two places is a cap
/// that drifts.
///
/// Half, not all of it, because an offset is not the only thing built from
/// one. The compiler adds two of them in `u32` -- `render.zig` computes where
/// a snippet's line ends as the label's start plus that line's length -- and a
/// sum of two quantities each capped at the field's full range does not fit
/// the field. Half is the largest cap at which every such sum still does. A
/// cap the code behind it cannot honour is not a cap; it is the arithmetic
/// that binds first, so it is the arithmetic the number comes from.
///
/// It happens also to sit under the smaller number a host will accept in one
/// read -- Darwin refuses a `pread` above `INT_MAX`, Linux shortens one above
/// `0x7ffff000`. That is corroboration and not the reason: a cap taken from a
/// syscall would be a different cap per host, and, because what is asked for
/// is how far a buffer has grown rather than how large the file is, a
/// different cap per toolchain. `readWithin` asks in `io_chunk` pieces so
/// that no syscall is ever the thing that decides.
///
/// This is not a rule of the language and carries no rule name. A bound on how
/// deeply a program nests is a statement about programs, and is the same
/// number in every build; this is a statement about how the compiler records a
/// position, and a source past it is a source that cannot be read.
pub const max_bytes: u64 = std.math.maxInt(@FieldType(Span, "start")) / 2;

/// The most one syscall is asked for at a time, in either direction.
///
/// A gibibyte is under every per-call ceiling a host imposes. It is a size and
/// not a limit: no source is accepted or refused for it and no diagnostic can
/// name it, which is what lets it be a round number where `max_bytes` may not.
///
/// One number for reading and for writing because it answers one question --
/// how much a host will move in a single call -- and the ceilings that bind
/// are the same ones on both sides: Darwin refuses either above `INT_MAX`,
/// Linux either above `0x7ffff000`. Two numbers would be one question with two
/// answers, and the second would be the one nobody checked.
const io_chunk: usize = 1 << 30;

/// How much to ask a stream for before it has delivered anything, where it
/// reported no size to reserve against. Doubles from here as bytes arrive.
const first_ask: usize = 64 * 1024;

/// Reads an entire file into memory. The caller owns the returned slice.
pub fn readFileAlloc(io: std.Io, gpa: std.mem.Allocator, path: []const u8) ![]u8 {
    return readFileWithin(io, gpa, path, max_bytes);
}

/// Reads a file no larger than `limit`, refusing one that is.
///
/// The size is consulted first so a file far past the cap is refused without
/// reading any of it -- a sparse file of a hundred gigabytes costs nothing to
/// create. The size is a hint and not the decision: what a stream reports and
/// what it then delivers need not agree, so `readWithin` counts what arrives
/// and refuses on that.
fn readFileWithin(io: std.Io, gpa: std.mem.Allocator, path: []const u8, limit: u64) ![]u8 {
    const file = try std.Io.Dir.cwd().openFile(io, path, .{});
    defer file.close(io);

    const size = try file.length(io);
    if (size > limit) return error.SourceTooLarge;

    var file_reader = file.reader(io, &.{});
    return readWithin(gpa, &file_reader.interface, limit, size);
}

/// Reads a stream to its end, refusing one longer than `limit`. The caller
/// owns the returned slice.
///
/// Reading to the end unbounded is what took the process down, and it did so
/// before any size mattered: the whole remaining buffer goes to one syscall,
/// and past a ceiling the platform sets that syscall fails with a code the
/// standard library treats as impossible -- a panic in a debug build and an
/// unexplained failure in a release one, which is one input with two outcomes
/// decided by optimisation level. Asking in `io_chunk` pieces holds every
/// syscall under the ceiling, so `limit` is what decides.
///
/// At most `limit + 1` bytes are ever read: one byte past the cap settles that
/// the source is over it, and a source wildly over it should not be held in
/// memory to find out.
///
/// `reserve` is what the caller already knows is there -- a file's size, and
/// zero for a stream that reports none. It decides nothing: a source is
/// accepted or refused on what arrives. What it buys is one allocation instead
/// of a sequence of them, and near the cap that is the difference between
/// holding the source and holding it several times over while each growth
/// copies what has arrived so far.
pub fn readWithin(
    gpa: std.mem.Allocator,
    reader: *std.Io.Reader,
    limit: u64,
    reserve: u64,
) ![]u8 {
    var text: std.ArrayList(u8) = .empty;
    errdefer text.deinit(gpa);

    if (reserve > 0) try text.ensureTotalCapacityPrecise(gpa, @intCast(@min(reserve, limit) + 1));

    while (true) {
        const room = limit + 1 - text.items.len;
        var want: usize = @intCast(@min(io_chunk, room));

        // Room already reserved is asked for in preference to room that would
        // have to be made, so a stream that is the size it said it was is read
        // without ever growing the buffer.
        const spare = text.capacity - text.items.len;
        if (spare > 0) {
            want = @min(want, spare);
        } else {
            // Nothing reserved is nothing known about what is coming, and
            // `io_chunk` is the ceiling one syscall must stay under rather
            // than an amount worth holding before a byte has arrived. Asking
            // for it outright allocated a gigabyte to read an empty file --
            // and an empty file is what a golden recording "printed nothing"
            // is, so a corpus of them cost a gigabyte apiece.
            //
            // Doubling from a small first ask instead: a stream that reported
            // no size still reaches any length in a logarithmic number of
            // grows, and one that is short costs its own size.
            want = @min(want, @max(first_ask, text.items.len));
        }

        try text.ensureUnusedCapacity(gpa, want);
        const into = text.unusedCapacitySlice()[0..want];
        const got = try reader.readSliceShort(into);
        text.items.len += got;

        // Short of what was asked for is the stream ending, which is the only
        // way out of this loop that is not a refusal.
        if (got < want) break;
        if (text.items.len > limit) return error.SourceTooLarge;
    }

    return text.toOwnedSlice(gpa);
}

/// A writer that asks no single call of the one beneath it for more than
/// `io_chunk`.
///
/// The mirror of the read, and the same fault: a writer hands its drain
/// whatever slice it was given, so one `writeAll` of a whole text is one
/// `writev` of that many bytes, and past the ceiling the platform sets it
/// fails with `EINVAL` -- a code the standard library treats as impossible, so
/// a panic in a debug build and a `WriteFailed` in a release one. That is one
/// input with two outcomes decided by optimisation level.
///
/// The bound is on the writer and not on the write, because the write is not
/// one place. Cutting a call cuts the one call it is written at: the formatted
/// text was cut where it is written out, and the unified diff `fmt --check`
/// prints was the place nobody cut -- a diff writes a line, and a file without
/// newlines is one line as long as the file. A writer that cannot ask for more
/// than the host will move leaves no such place: what is bounded is what a
/// consumer was handed, so a consumer written later is bounded without knowing
/// this exists.
///
/// The cap on a source does not cover this. Formatting is not length
/// preserving: it indents, and it ends a file with a newline that was not
/// there, so a source at the cap becomes an output past it. The size that has
/// to be held under the ceiling is the one being written, not the one that was
/// read.
///
/// This is where the buffering belongs, so the writer beneath is given none:
/// bytes waiting in two places is two places a flush has to reach, and the
/// bytes still in the lower one are the ones a partial write leaves behind.
pub const Piecewise = struct {
    writer: std.Io.Writer,
    out: *std.Io.Writer,
    piece: usize,

    pub fn init(out: *std.Io.Writer, buffer: []u8) Piecewise {
        return initPiece(out, buffer, io_chunk);
    }

    /// `init` with the piece size supplied, so a case can reach the seam
    /// without moving a gibibyte to do it.
    fn initPiece(out: *std.Io.Writer, buffer: []u8, piece: usize) Piecewise {
        return .{
            .writer = .{
                .vtable = &.{ .drain = drain, .flush = flush },
                .buffer = buffer,
            },
            .out = out,
            .piece = piece,
        };
    }

    fn drain(w: *std.Io.Writer, data: []const []const u8, splat: usize) std.Io.Writer.Error!usize {
        const self: *Piecewise = @alignCast(@fieldParentPtr("writer", w));

        // What is buffered was written first, so it goes out first.
        try writeInPieces(self.out, w.buffer[0..w.end], self.piece);
        w.end = 0;

        const slices = data[0 .. data.len - 1];
        const pattern = data[slices.len];

        var written: usize = 0;
        for (slices) |bytes| {
            try writeInPieces(self.out, bytes, self.piece);
            written += bytes.len;
        }
        // Counted a repetition at a time rather than as a product: the sum is
        // bytes that were written, so it cannot overflow what was written.
        for (0..splat) |_| {
            try writeInPieces(self.out, pattern, self.piece);
            written += pattern.len;
        }
        return written;
    }

    fn flush(w: *std.Io.Writer) std.Io.Writer.Error!void {
        const self: *Piecewise = @alignCast(@fieldParentPtr("writer", w));
        _ = try drain(w, &.{""}, 1);
        return self.out.flush();
    }
};

fn writeInPieces(w: *std.Io.Writer, bytes: []const u8, piece: usize) std.Io.Writer.Error!void {
    var at: usize = 0;
    while (at < bytes.len) {
        const n = @min(piece, bytes.len - at);
        try w.writeAll(bytes[at..][0..n]);
        at += n;
    }
}

/// A writer that counts what the largest single call was asked to move, and
/// keeps everything it was handed.
///
/// It buffers nothing, which is how a file writer under a `Piecewise` is
/// opened: a drain hands the host its buffer and its data in one call, so a
/// sink that held any back would be measuring less than the host is asked for.
const Metering = struct {
    writer: std.Io.Writer,
    widest: usize = 0,
    seen: std.ArrayList(u8) = .empty,
    gpa: std.mem.Allocator,

    fn init(gpa: std.mem.Allocator) Metering {
        return .{
            .gpa = gpa,
            .writer = .{ .vtable = &.{ .drain = drain }, .buffer = &.{} },
        };
    }

    fn deinit(self: *Metering) void {
        self.seen.deinit(self.gpa);
    }

    fn drain(w: *std.Io.Writer, data: []const []const u8, splat: usize) std.Io.Writer.Error!usize {
        const self: *Metering = @alignCast(@fieldParentPtr("writer", w));

        const slice = data[0 .. data.len - 1];
        const pattern = data[slice.len];

        var written: usize = 0;
        for (slice) |bytes| {
            self.seen.appendSlice(self.gpa, bytes) catch return error.WriteFailed;
            written += bytes.len;
        }
        for (0..splat) |_| {
            self.seen.appendSlice(self.gpa, pattern) catch return error.WriteFailed;
            written += pattern.len;
        }

        self.widest = @max(self.widest, written);
        return written;
    }
};

test "a piecewise writer asks for no more than a piece, and drops none of it" {
    // The fault being held off is a single call asking for more than the host
    // will move, which needs two gigabytes to reach with the real piece size.
    // The seam is the same at any size, so the case supplies a small one and
    // asserts the two things that matter: no call is asked for more than a
    // piece, and cutting the write into pieces does not reorder or drop any of
    // it.
    var text: [1000]u8 = undefined;
    for (&text, 0..) |*b, i| b.* = @truncate(i);

    for ([_]usize{ 1, 7, 64, text.len - 1, text.len, text.len + 1 }) |piece| {
        var metering: Metering = .init(testing.allocator);
        defer metering.deinit();

        var buffer: [16]u8 = undefined;
        var out: Piecewise = .initPiece(&metering.writer, &buffer, piece);

        try out.writer.writeAll(&text);
        try out.writer.flush();

        try testing.expect(metering.widest <= piece);
        try testing.expectEqualSlices(u8, &text, metering.seen.items);
    }
}

test "the bound holds however the writer is asked, not only through writeAll" {
    // A consumer is handed a `std.Io.Writer` and uses whichever of its methods
    // suits it -- the unified diff writes a byte, then a line, then a byte.
    // Each reaches the sink by a different route, and a bound that only one of
    // them respects is one the next consumer walks around.
    const long = "Z" ** 300;
    const piece = 8;

    var metering: Metering = .init(testing.allocator);
    defer metering.deinit();

    var buffer: [16]u8 = undefined;
    var out: Piecewise = .initPiece(&metering.writer, &buffer, piece);

    try out.writer.writeByte('-');
    try out.writer.writeAll(long);
    try out.writer.print(" {d} {s}\n", .{ 42, long });
    try out.writer.splatBytesAll(long, 3);
    try out.writer.flush();

    try testing.expect(metering.widest <= piece);
    try testing.expectEqualStrings(
        "-" ++ long ++ " 42 " ++ long ++ "\n" ++ long ** 3,
        metering.seen.items,
    );
}

test "nothing is asked of a writer for an empty text" {
    var metering: Metering = .init(testing.allocator);
    defer metering.deinit();

    var buffer: [16]u8 = undefined;
    var out: Piecewise = .init(&metering.writer, &buffer);

    try out.writer.writeAll("");
    try out.writer.flush();
    try testing.expectEqual(@as(usize, 0), metering.widest);
}

test "a file over the cap is refused from its size, before any of it is read" {
    // Reading it is what died, so a guard that waited for the text would never
    // run. The limit is supplied here so the case costs a few bytes rather
    // than two gigabytes; what it pins is that the size decides, and that it
    // decides first.
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    {
        const file = try tmp.dir.createFile(testing.io, "big.lin", .{});
        defer file.close(testing.io);
        try file.writeStreamingAll(testing.io, "fn main() -> UInt8 { 1 }\n");
    }

    const path = try std.fmt.allocPrint(
        testing.allocator,
        ".zig-cache/tmp/{s}/big.lin",
        .{tmp.sub_path},
    );
    defer testing.allocator.free(path);

    try testing.expectError(
        error.SourceTooLarge,
        readFileWithin(testing.io, testing.allocator, path, 8),
    );

    const text = try readFileWithin(testing.io, testing.allocator, path, 64);
    defer testing.allocator.free(text);
    try testing.expectEqualStrings("fn main() -> UInt8 { 1 }\n", text);
}

test "a stream is refused on what arrives, since it reports no size to check" {
    // A file is refused from the size it reports; a pipe reports none, so
    // counting what arrives is the whole of the guard there. `linea fmt
    // --stdin` is the route that has no size, and it is the one an editor
    // uses.
    const text = "fn main() -> UInt8 { 1 }\n";

    for ([_]u64{ 0, 1, text.len - 1 }) |limit| {
        var reader: std.Io.Reader = .fixed(text);
        try testing.expectError(
            error.SourceTooLarge,
            readWithin(testing.allocator, &reader, limit, 0),
        );
    }

    // Exactly at the cap is accepted: a source of `limit` bytes ends at offset
    // `limit`, which is a position a span still holds.
    var reader: std.Io.Reader = .fixed(text);
    const read = try readWithin(testing.allocator, &reader, text.len, 0);
    defer testing.allocator.free(read);
    try testing.expectEqualStrings(text, read);

    // An empty stream is a source, not a refusal, whatever the cap.
    var empty: std.Io.Reader = .fixed("");
    const none = try readWithin(testing.allocator, &empty, 0, 0);
    defer testing.allocator.free(none);
    try testing.expectEqualStrings("", none);
}

test "what a stream claimed decides nothing about whether it is refused" {
    // `reserve` sizes the buffer and must not be mistaken for the guard: a
    // stream that under-reports is still refused on what arrives, and one that
    // over-reports is still read whole.
    const text = "fn main() -> UInt8 { 1 }\n";

    var lying: std.Io.Reader = .fixed(text);
    try testing.expectError(
        error.SourceTooLarge,
        readWithin(testing.allocator, &lying, text.len - 1, 1),
    );

    var short: std.Io.Reader = .fixed(text);
    const read = try readWithin(testing.allocator, &short, max_bytes, 4096);
    defer testing.allocator.free(read);
    try testing.expectEqualStrings(text, read);
}

test "a stream comes back byte for byte, in order" {
    // The read is issued in pieces now, so the risk the whole-file read did
    // not have is a piece landing at the wrong offset or a loop mistaking a
    // short read for the end and returning a prefix as the file. Every byte is
    // distinguishable from its neighbours, so either shows up as a mismatch.
    var text: [8192]u8 = undefined;
    for (&text, 0..) |*b, i| b.* = @truncate(i);

    var reader: std.Io.Reader = .fixed(&text);
    const read = try readWithin(testing.allocator, &reader, max_bytes, text.len);
    defer testing.allocator.free(read);
    try testing.expectEqualSlices(u8, &text, read);
}

test "the size a source is capped at is one two positions can be added at" {
    // A cap the code does not check is a cap that drifts, which is what left
    // 4 GiB documented as the limit and unreachable only by luck. What pins
    // the number is the arithmetic behind it: a start plus a length, both
    // bounded by the cap, is computed in the span's own field, so twice the
    // cap has to fit that field. This is the assertion that would fail if the
    // cap were widened back to the field's full range.
    const offset = @FieldType(Span, "start");
    try testing.expectEqual(@as(u64, std.math.maxInt(i32)), max_bytes);
    try testing.expect(max_bytes * 2 <= std.math.maxInt(offset));
    try testing.expect((max_bytes + 1) * 2 > std.math.maxInt(offset));

    // Both ends of a span answer to it, since either can name the last byte.
    try testing.expectEqual(
        @as(u64, std.math.maxInt(@FieldType(Span, "end"))),
        @as(u64, std.math.maxInt(offset)),
    );

    // A chunk is not a second cap. Every byte up to the cap is reachable in
    // pieces this size, and a piece is under the ceiling a syscall sets --
    // Darwin's `INT_MAX` being the lower of the two that bind.
    try testing.expect(io_chunk < std.math.maxInt(i32));
    try testing.expect(io_chunk < max_bytes);
}

/// A source file held entirely in memory. Owns its text.
pub const Source = struct {
    path: []const u8,
    text: []const u8,

    pub fn load(io: std.Io, gpa: std.mem.Allocator, path: []const u8) !Source {
        return .{ .path = path, .text = try readFileAlloc(io, gpa, path) };
    }
};

/// Which file a span is an offset into.
///
/// A `Span` deliberately does not carry one: spans are stored column-wise for
/// every token in the program, and a file is constant across all of them. The
/// identity rides on the things that outnumber files rather than tokens — a
/// syntax tree, and a diagnostic's label.
pub const FileId = enum(u32) {
    /// No file. For a `Loc` that records the absence of a position, never for
    /// a label -- a diagnostic that points nowhere has nothing to render.
    none = std.math.maxInt(u32),
    _,

    pub fn from(i: usize) FileId {
        return @enumFromInt(i);
    }

    pub fn index(self: FileId) usize {
        return @intFromEnum(self);
    }
};

/// Every source in one compilation, and the line indexes built to render
/// diagnostics against them.
///
/// Maps are built for the files a consumer needs. Initialized maps survive
/// later source additions; diagnostics can prepare every remaining map.
pub const FileTable = struct {
    sources: std.ArrayList(Source) = .empty,
    maps: std.ArrayList(?SourceMap) = .empty,
    mapped_count: usize = 0,

    pub const empty: FileTable = .{};

    pub fn deinit(self: *FileTable, gpa: std.mem.Allocator) void {
        for (self.maps.items) |*slot| {
            if (slot.*) |*map| map.deinit();
        }
        self.maps.deinit(gpa);
        self.sources.deinit(gpa);
        self.* = undefined;
    }

    pub fn add(self: *FileTable, gpa: std.mem.Allocator, source: Source) !FileId {
        try self.sources.append(gpa, source);
        return .from(self.sources.items.len - 1);
    }

    pub fn get(self: *const FileTable, file: FileId) *const Source {
        return &self.sources.items[file.index()];
    }

    pub fn count(self: *const FileTable) usize {
        return self.sources.items.len;
    }

    /// Build every remaining index so diagnostic rendering needs no allocator.
    pub fn buildMaps(self: *FileTable, gpa: std.mem.Allocator) !void {
        if (self.mapped_count == self.sources.items.len) return;
        for (0..self.sources.items.len) |i| _ = try self.buildMap(gpa, .from(i));
    }

    /// Prepare one file's index without scanning or indexing other sources.
    pub fn buildMap(self: *FileTable, gpa: std.mem.Allocator, file: FileId) !*const SourceMap {
        if (file.index() < self.maps.items.len) {
            if (self.maps.items[file.index()]) |*map| return map;
        }
        if (self.maps.items.len < self.sources.items.len) {
            const first = self.maps.items.len;
            try self.maps.resize(gpa, self.sources.items.len);
            @memset(self.maps.items[first..], null);
        }
        self.maps.items[file.index()] = try SourceMap.init(gpa, self.get(file));
        self.mapped_count += 1;
        return &self.maps.items[file.index()].?;
    }

    /// An index already prepared by this file's consumer.
    pub fn mapOf(self: *const FileTable, file: FileId) *const SourceMap {
        return &self.maps.items[file.index()].?;
    }
};

test "a file table hands back what it was given" {
    var table: FileTable = .empty;
    defer table.deinit(testing.allocator);

    const a = try table.add(testing.allocator, .{ .path = "a.lin", .text = "let x = 1;" });
    const b = try table.add(testing.allocator, .{ .path = "b.lin", .text = "let y = 2;" });

    try testing.expect(a != b);
    try testing.expectEqualStrings("a.lin", table.get(a).path);
    try testing.expectEqualStrings("b.lin", table.get(b).path);
    try testing.expectEqual(@as(usize, 2), table.count());
}

test "a source map answers coordinates for the file a label names" {
    // The failure this exists for: one map built from the first source and
    // reused for every label renders line numbers from the wrong file, which
    // reads as an off-by-N in the lexer rather than as a missing lookup.
    var table: FileTable = .empty;
    defer table.deinit(testing.allocator);

    _ = try table.add(testing.allocator, .{ .path = "a.lin", .text = "one\ntwo\n" });
    const b = try table.add(testing.allocator, .{ .path = "b.lin", .text = "\n\n\nfour\n" });

    try table.buildMaps(testing.allocator);
    const map = table.mapOf(b);

    // "four" begins at offset 3 of b.lin, which is line 4 there and line 1 in
    // the file a shared map would have indexed.
    try testing.expectEqual(@as(u32, 4), map.lineCol(3).line);
    try testing.expectEqualStrings("four", map.lineText(4));
}

test "source maps are reused when more files are added" {
    var table: FileTable = .empty;
    defer table.deinit(testing.allocator);

    const a = try table.add(testing.allocator, .{ .path = "a.lin", .text = "one\ntwo\n" });
    try table.buildMaps(testing.allocator);
    const first = table.mapOf(a).line_starts.ptr;
    var no_alloc = testing.FailingAllocator.init(testing.allocator, .{ .fail_index = 0 });
    try table.buildMaps(no_alloc.allocator());
    try testing.expectEqual(first, table.mapOf(a).line_starts.ptr);

    const b = try table.add(testing.allocator, .{ .path = "b.lin", .text = "\n\nthree" });
    try table.buildMaps(testing.allocator);
    try testing.expectEqual(first, table.mapOf(a).line_starts.ptr);
    try testing.expectEqualStrings("two", table.mapOf(a).lineText(2));
    try testing.expectEqualStrings("three", table.mapOf(b).lineText(3));
}

test "selected source maps leave other files unindexed and survive bulk preparation" {
    const gpa = testing.allocator;
    var table: FileTable = .empty;
    defer table.deinit(gpa);
    const a = try table.add(gpa, .{ .path = "a.lin", .text = "one\ntwo" });
    const b = try table.add(gpa, .{ .path = "b.lin", .text = "three\nfour" });
    const c = try table.add(gpa, .{ .path = "c.lin", .text = "five\nsix" });
    const selected = try table.buildMap(gpa, c);
    const retained = selected.line_starts.ptr;
    try testing.expectEqualStrings("six", selected.lineText(2));
    try testing.expect(table.maps.items[a.index()] == null);
    try testing.expect(table.maps.items[b.index()] == null);
    var no_alloc = testing.FailingAllocator.init(gpa, .{ .fail_index = 0 });
    try testing.expectEqual(retained, (try table.buildMap(no_alloc.allocator(), c)).line_starts.ptr);
    try table.buildMaps(gpa);
    try testing.expectEqual(retained, table.mapOf(c).line_starts.ptr);
    try testing.expectEqualStrings("two", table.mapOf(a).lineText(2));
    try testing.expectEqualStrings("four", table.mapOf(b).lineText(2));
}

test "selected source maps preserve another index on allocation failure" {
    try testing.checkAllAllocationFailures(testing.allocator, struct {
        fn run(gpa: std.mem.Allocator) !void {
            var table: FileTable = .empty;
            defer table.deinit(gpa);
            const a = try table.add(gpa, .{ .path = "a.lin", .text = "one\ntwo" });
            const b = try table.add(gpa, .{ .path = "b.lin", .text = "three\nfour" });
            const retained = (try table.buildMap(gpa, b)).line_starts.ptr;
            _ = table.buildMap(gpa, a) catch |err| {
                try testing.expectEqual(retained, table.mapOf(b).line_starts.ptr);
                try testing.expectEqualStrings("four", table.mapOf(b).lineText(2));
                return err;
            };
            try testing.expectEqualStrings("two", table.mapOf(a).lineText(2));
        }
    }.run, .{});
}

test "adding sources builds no maps" {
    var table: FileTable = .empty;
    defer table.deinit(testing.allocator);

    _ = try table.add(testing.allocator, .{ .path = "a.lin", .text = "one\ntwo\n" });
    try testing.expectEqual(@as(usize, 0), table.maps.items.len);
}

test "source maps preserve initialized files on allocation failure" {
    try testing.checkAllAllocationFailures(testing.allocator, struct {
        fn run(gpa: std.mem.Allocator) !void {
            var table: FileTable = .empty;
            defer table.deinit(gpa);
            const a = try table.add(gpa, .{ .path = "a.lin", .text = "one\ntwo\n" });
            try table.buildMaps(gpa);
            const first = table.mapOf(a).line_starts.ptr;
            const b = try table.add(gpa, .{ .path = "b.lin", .text = "\n\nthree" });
            table.buildMaps(gpa) catch |err| {
                try testing.expectEqual(first, table.mapOf(a).line_starts.ptr);
                try testing.expectEqualStrings("two", table.mapOf(a).lineText(2));
                return err;
            };
            try testing.expectEqualStrings("three", table.mapOf(b).lineText(3));
        }
    }.run, .{});
}

/// A 1-based line and column. Columns count Unicode scalar values, not bytes
/// and not grapheme clusters; wide and combining characters will misalign
/// carets, which is a known and deferred limitation.
pub const LineCol = struct {
    line: u32,
    column: u32,
};

/// Byte-offset to line/column mapping for diagnostics and emitted locations.
pub const SourceMap = struct {
    gpa: std.mem.Allocator,
    /// The bytes the offsets index.
    ///
    /// The text rather than the `Source` holding it: a `Source` lives in the
    /// table's list, which reallocates whenever a file is added, so a map
    /// built before the last `add` pointed into freed memory. The bytes are
    /// allocated apart from that list and do not move.
    ///
    /// A slice rather than a `FileId` and a lookup, because this is the thing
    /// the map is a map of -- every method wants it, and threading the table
    /// through each would put "which file is this" at every call site of a
    /// type whose whole job is to answer about one.
    text: []const u8,
    /// Byte offset at which each line begins. Always holds at least one entry,
    /// since line 1 begins at offset 0.
    line_starts: []u32,
    /// The line containing each 256-byte boundary. A lookup searches at most
    /// 257 line starts instead of the whole file. Costs one u32 per 256 bytes.
    line_buckets: []u32,
    /// Whether each line holds only single-byte scalars, in step with
    /// `line_starts`.
    ///
    /// A column counts scalar values, so it is a walk from the line's start
    /// unless every byte on the line is its own scalar -- and then it is the
    /// byte offset. Rendering one diagnostic asks three times, and a file whose
    /// diagnostics sit on one long line asked for the whole prefix each time.
    ascii_only: []bool,

    pub fn init(gpa: std.mem.Allocator, source: *const Source) !SourceMap {
        var starts: std.ArrayList(u32) = .empty;
        errdefer starts.deinit(gpa);

        var ascii: std.ArrayList(bool) = .empty;
        errdefer ascii.deinit(gpa);

        try starts.append(gpa, 0);
        var plain = true;
        for (source.text, 0..) |ch, i| {
            if (ch == '\n') {
                try ascii.append(gpa, plain);
                plain = true;
                try starts.append(gpa, @intCast(i + 1));
                continue;
            }
            if (ch >= 0x80) plain = false;
        }
        // The last line ends at the end of the text rather than at a newline,
        // so it is closed here. Without this a file not ending in one has a
        // line with no bit, and asking about it reads past the end.
        try ascii.append(gpa, plain);

        // A trailing newline would otherwise open a final line that has no
        // content and no position any diagnostic can refer to. Both arrays
        // give it up, because they are one line's worth of answer each.
        if (starts.items.len > 1 and starts.items[starts.items.len - 1] == source.text.len) {
            _ = starts.pop();
            _ = ascii.pop();
        }

        const line_starts = try starts.toOwnedSlice(gpa);
        errdefer gpa.free(line_starts);

        const line_buckets = try gpa.alloc(u32, source.text.len / 256 + 1);
        errdefer gpa.free(line_buckets);
        var line: usize = 0;
        for (line_buckets, 0..) |*bucket, i| {
            while (line + 1 < line_starts.len and line_starts[line + 1] <= i * 256) : (line += 1) {}
            bucket.* = @intCast(line);
        }

        return .{
            .gpa = gpa,
            .text = source.text,
            .line_starts = line_starts,
            .line_buckets = line_buckets,
            .ascii_only = try ascii.toOwnedSlice(gpa),
        };
    }

    pub fn deinit(self: *SourceMap) void {
        self.gpa.free(self.line_starts);
        self.gpa.free(self.line_buckets);
        self.gpa.free(self.ascii_only);
        self.* = undefined;
    }

    pub fn lineCount(self: *const SourceMap) u32 {
        return @intCast(self.line_starts.len);
    }

    /// The 1-based line containing `offset`: the last line whose start is at or
    /// before it.
    fn lineOf(self: *const SourceMap, offset: u32) u32 {
        const bucket = @min(offset, self.text.len) / 256;
        var lo: usize = self.line_buckets[bucket];
        var hi: usize = if (bucket + 1 < self.line_buckets.len) self.line_buckets[bucket + 1] + 1 else self.line_starts.len;
        while (lo < hi) {
            const mid = lo + (hi - lo) / 2;
            if (self.line_starts[mid] <= offset) lo = mid + 1 else hi = mid;
        }
        // `lo` is the count of line starts at or before `offset`, which is the
        // 1-based line number. Line 1 starts at 0, so it is never zero.
        return @intCast(lo);
    }

    pub fn lineCol(self: *const SourceMap, offset: u32) LineCol {
        const line = self.lineOf(offset);
        const start = self.line_starts[line - 1];

        // Every byte on the line is its own scalar, so the count of them is the
        // distance -- the same answer the walk below reaches, without the walk.
        if (self.ascii_only[line - 1]) {
            const at = @min(offset, @as(u32, @intCast(self.text.len)));
            return .{ .line = line, .column = at - start + 1 };
        }

        // Continuation bytes are 0b10xxxxxx, so counting everything else counts
        // scalar values rather than bytes.
        var scalars: u32 = 0;
        var i = start;
        while (i < offset and i < self.text.len) : (i += 1) {
            if (self.text[i] & 0xC0 != 0x80) scalars += 1;
        }

        return .{ .line = line, .column = scalars + 1 };
    }

    /// The text of a 1-based line, excluding its terminator.
    pub fn lineText(self: *const SourceMap, line: u32) []const u8 {
        const start = self.line_starts[line - 1];
        const end = if (line < self.lineCount())
            self.line_starts[line] - 1
        else
            @as(u32, @intCast(self.text.len));

        var text = self.text[start..end];
        // The final line reaches the end of the input, which still carries its
        // newline when the file ends with one.
        if (text.len > 0 and text[text.len - 1] == '\n') text = text[0 .. text.len - 1];
        if (text.len > 0 and text[text.len - 1] == '\r') text = text[0 .. text.len - 1];
        return text;
    }
};

test "lineCol maps offsets to 1-based line and column" {
    const src: Source = .{ .path = "t.lin", .text = "let x = 1;\nlet y = 2;\n" };
    var map = try SourceMap.init(testing.allocator, &src);
    defer map.deinit();

    try testing.expectEqual(LineCol{ .line = 1, .column = 1 }, map.lineCol(0));
    try testing.expectEqual(LineCol{ .line = 1, .column = 5 }, map.lineCol(4));
    try testing.expectEqual(LineCol{ .line = 2, .column = 1 }, map.lineCol(11));
    try testing.expectEqual(LineCol{ .line = 2, .column = 5 }, map.lineCol(15));
}

test "source positions cross byte buckets and keep the final line" {
    const text = "x\n" ** 513;
    const src: Source = .{ .path = "t.lin", .text = text };
    var map = try SourceMap.init(testing.allocator, &src);
    defer map.deinit();
    for (0..text.len + 1) |offset| {
        const line: u32 = @intCast(@min(offset / 2 + 1, 513));
        const column: u32 = @intCast(offset - (line - 1) * 2 + 1);
        try testing.expectEqual(LineCol{ .line = line, .column = column }, map.lineCol(@intCast(offset)));
    }
    const unicode: Source = .{ .path = "unicode.lin", .text = "é" ** 130 ++ "\n界x" };
    var wide = try SourceMap.init(testing.allocator, &unicode);
    defer wide.deinit();
    try testing.expectEqual(LineCol{ .line = 1, .column = 129 }, wide.lineCol(256));
    try testing.expectEqual(LineCol{ .line = 2, .column = 2 }, wide.lineCol(264));
}

test "source maps release partial indexes on allocation failure" {
    try testing.checkAllAllocationFailures(testing.allocator, struct {
        fn run(gpa: std.mem.Allocator) !void {
            const src: Source = .{ .path = "t.lin", .text = "x\n" ** 513 };
            var map = try SourceMap.init(gpa, &src);
            defer map.deinit();
        }
    }.run, .{});
}

test "columns count Unicode scalars, not bytes" {
    // "é" is two bytes; the character after it is column 3, not column 4.
    const src: Source = .{ .path = "t.lin", .text = "aéb" };
    var map = try SourceMap.init(testing.allocator, &src);
    defer map.deinit();

    try testing.expectEqual(@as(u32, 1), map.lineCol(0).column); // 'a'
    try testing.expectEqual(@as(u32, 2), map.lineCol(1).column); // 'é'
    try testing.expectEqual(@as(u32, 3), map.lineCol(3).column); // 'b'
}

test "lineText excludes the terminator and handles CRLF" {
    const src: Source = .{ .path = "t.lin", .text = "one\r\ntwo\nthree" };
    var map = try SourceMap.init(testing.allocator, &src);
    defer map.deinit();

    try testing.expectEqual(@as(u32, 3), map.lineCount());
    try testing.expectEqualStrings("one", map.lineText(1));
    try testing.expectEqualStrings("two", map.lineText(2));
    try testing.expectEqualStrings("three", map.lineText(3));
}

test "lineText excludes the terminator on a trailing-newline final line" {
    const src: Source = .{ .path = "t.lin", .text = "one\ntwo\n" };
    var map = try SourceMap.init(testing.allocator, &src);
    defer map.deinit();

    try testing.expectEqual(@as(u32, 2), map.lineCount());
    try testing.expectEqualStrings("one", map.lineText(1));
    try testing.expectEqualStrings("two", map.lineText(2));
}

test "offset at end of input is valid" {
    const src: Source = .{ .path = "t.lin", .text = "ab" };
    var map = try SourceMap.init(testing.allocator, &src);
    defer map.deinit();

    try testing.expectEqual(LineCol{ .line = 1, .column = 3 }, map.lineCol(2));
}

test "a line of single-byte scalars is counted as the walk would count it" {
    // The fast answer and the walk it stands for, over inputs shaped to hit
    // the places the two could part: a file with no trailing newline, whose
    // last line has no terminator to close it; a multi-byte scalar, which is
    // what makes a column differ from a byte offset; an empty line; and an
    // offset at the very end of the text.
    const alphabet = [_][]const u8{ "a", " ", "\n", "\u{e9}", "\u{4e2d}", "\u{1f600}", "\r" };

    var prng = std.Random.DefaultPrng.init(0x5eed);
    const rand = prng.random();

    var text: std.ArrayList(u8) = .empty;
    defer text.deinit(testing.allocator);

    for (0..400) |_| {
        text.clearRetainingCapacity();
        const len = rand.uintLessThan(usize, 120);
        for (0..len) |_| {
            try text.appendSlice(testing.allocator, alphabet[rand.uintLessThan(usize, alphabet.len)]);
        }

        const src: Source = .{ .path = "t.lin", .text = text.items };
        var map = try SourceMap.init(testing.allocator, &src);
        defer map.deinit();

        for (0..text.items.len + 1) |offset| {
            const at: u32 = @intCast(offset);
            const line = map.lineOf(at);
            const start = map.line_starts[line - 1];

            var scalars: u32 = 0;
            var i = start;
            while (i < at and i < text.items.len) : (i += 1) {
                if (text.items[i] & 0xC0 != 0x80) scalars += 1;
            }

            try testing.expectEqual(
                LineCol{ .line = line, .column = scalars + 1 },
                map.lineCol(at),
            );
        }
    }
}
