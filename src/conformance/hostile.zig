//! Programs built to sit where the compiler's cost or its limits are decided.
//!
//! `generate.zig` writes small programs that are well typed by construction,
//! and every one of them is far from any limit the language states and from
//! any shape whose cost depends on how a type is shared. This file writes the
//! other kind, and says of each program what the compiler must answer:
//!
//!   - a generic alias chain in which each alias names the one before it
//!     twice, so a type of `2^depth` names is `depth` declarations, used once.
//!     It must be accepted, or refused once where a mistake is planted in it;
//!   - for each limit in `support/limits.zig`, a program exactly at the limit,
//!     which must be accepted, and one past it, which must be refused under
//!     the limit's rule and under nothing else.
//!
//! A limit on a written type is written in each of the positions `Position`
//! names. A type is the same type wherever it is written, so a chain of
//! declared answers, a tuple or an array refused in a `let` is refused in an
//! `impl` head too. Two limits count something the position adds to, and the
//! generator writes that down: nesting is counted from the type's place in
//! the tree, so a trait's argument has one level fewer, and an enum is wider
//! than its payload by its tag.
//!
//! Every program is also held to a bound on the allocation work its check
//! adds, see `Work`.

const std = @import("std");
const testing = std.testing;

const slow_tests = @import("../support/slow_tests.zig");
const Limit = @import("../support/limits.zig").Limit;
const diagnostic = @import("../diagnostics/diagnostic.zig");
const Code = diagnostic.Code;
const loader = @import("../driver/loader.zig");
const test_library = @import("../driver/test_library.zig");
const choices_mod = @import("choices.zig");
const Choices = choices_mod.Choices;
const Counting = @import("counting.zig").Counting;
const generate = @import("generate.zig");

/// Where a program writes what it counts.
pub const Position = enum {
    let_annotation,
    parameter,
    field,
    payload,
    /// The argument of the trait an `impl` names: `impl Trait[T] for Target`.
    implementation_argument,
    /// The argument of a derived trait: `@derive(From[T])`.
    derive_argument,
    /// The type an `impl` is written for: `impl Trait for T`.
    implementation_head,
    /// The initialiser of a `let` in `main`, for a limit on an expression.
    value,

    pub fn describe(self: Position) []const u8 {
        return switch (self) {
            .let_annotation => "a `let` annotation",
            .parameter => "a function parameter",
            .field => "a struct field",
            .payload => "an enum payload",
            .implementation_argument => "the trait argument of an `impl`",
            .derive_argument => "a derive argument",
            .implementation_head => "the head of an `impl`",
            .value => "a `let` initialiser",
        };
    }

    /// Whether the position is an argument of a written trait, which is one
    /// level of the written type that names the trait.
    fn isTraitArgument(self: Position) bool {
        return self == .implementation_argument or self == .derive_argument;
    }

    /// Whether the position is, or needs beside it, an enum's payload.
    fn isPayload(self: Position) bool {
        return self == .payload or self == .derive_argument;
    }
};

/// The positions a type is written in.
const type_positions = [_]Position{
    .let_annotation,
    .parameter,
    .field,
    .payload,
    .implementation_argument,
    .derive_argument,
    .implementation_head,
};

pub const Shape = union(enum) {
    shared: Shared,
    limit: AtLimit,

    /// A generic alias chain `depth` aliases long above its first, each
    /// naming the one before it twice, used once at `position`.
    pub const Shared = struct {
        depth: u32,
        position: Position,
        /// Whether the program gives a `UInt8` where the chain's type is
        /// wanted, which is its one mistake.
        mistaken: bool = false,
    };

    /// A program at `limit`, or one past it, written at `position`.
    pub const AtLimit = struct {
        limit: Limit,
        past: bool,
        position: Position,
    };

    pub fn format(self: Shape, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        switch (self) {
            .shared => |s| try writer.print("a doubling alias chain {d} deep in {s}{s}", .{
                s.depth,
                s.position.describe(),
                if (s.mistaken) ", given a `UInt8`" else "",
            }),
            .limit => |l| try writer.print("{s} {s} [{s}] in {s}", .{
                if (l.past) "one past" else "exactly at",
                @tagName(l.limit),
                l.limit.rule(),
                l.position.describe(),
            }),
        }
    }
};

/// What the compiler must say of a program.
pub const Expectation = union(enum) {
    accepted,
    refused: Refusal,

    pub const Refusal = struct {
        rule: Code,
        /// How many diagnostics the program earns, all under `rule`: one for
        /// each place the mistake is written, or one where the rule reports
        /// once whatever the number of places.
        reports: u32,
    };
};

pub const Program = struct {
    shape: Shape,
    text: []const u8,
    expectation: Expectation,
};

/// The rule a program past `limit` is refused under.
pub fn codeOf(limit: Limit) Code {
    for (std.enums.values(Code)) |c| {
        if (std.mem.eql(u8, c.ruleName(), limit.rule())) return c;
    }
    unreachable;
}

test "every limit names a rule the compiler emits" {
    for (std.enums.values(Limit)) |limit| {
        var found = false;
        for (std.enums.values(Code)) |c| {
            if (std.mem.eql(u8, c.ruleName(), limit.rule())) found = true;
        }
        try testing.expect(found);
    }
}

/// A count as the semantics document spells the small ones.
fn inWords(n: u64) []const u8 {
    const words = [_][]const u8{ "zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten" };
    return words[@intCast(n)];
}

/// The sentence of `docs/linea-semantics.md` that states `limit`, written
/// from the table's number.
fn statedAs(buffer: []u8, limit: Limit) ![]const u8 {
    const most = limit.most();
    return switch (limit) {
        .tree_height => std.fmt.bufPrint(buffer, "nests at most {d} levels deep", .{most}),
        .tuple_components => std.fmt.bufPrint(buffer, "at least {s} components and at most {s}", .{
            inWords(limit.fewest().?),
            inWords(most),
        }),
        .answer_links => std.fmt.bufPrint(buffer, "passes through at most {d} links", .{most}),
        .coverage_cells => std.fmt.bufPrint(buffer, "more than 2^{d} cells", .{std.math.log2_int(u64, most)}),
        .array_length => std.fmt.bufPrint(buffer, "The maximum length is {d}", .{most}),
        .type_bytes => std.fmt.bufPrint(buffer, "A type is at most {d} bytes", .{most}),
        .raw_literal_hashes => std.fmt.bufPrint(buffer, "A raw literal opens with at most {s} `#`", .{inWords(most)}),
        .interpolation_depth => std.fmt.bufPrint(buffer, "at most {d} interpolations open at once", .{most}),
        .format_count => std.fmt.bufPrint(buffer, "a width or precision above {d}", .{most}),
        .embedded_bytes => std.fmt.bufPrint(buffer, "more than {d} MiB", .{most >> 20}),
    };
}

test "the semantics document states every limit as the table holds it" {
    // The compiler and the generator read one table, so a wrong number in it
    // is accepted by both. The document is the third statement of each limit
    // and the only one the table is not derived from.
    const semantics = @embedFile("semantics");
    const joined = try testing.allocator.dupe(u8, semantics);
    defer testing.allocator.free(joined);
    // A sentence may break across lines anywhere.
    for (joined) |*byte| {
        if (byte.* == '\n') byte.* = ' ';
    }

    try testing.expect(std.math.isPowerOfTwo(Limit.coverage_cells.most()));
    try testing.expectEqual(@as(u64, 0), Limit.embedded_bytes.most() % (1 << 20));

    var missing: u32 = 0;
    for (std.enums.values(Limit)) |limit| {
        var buffer: [128]u8 = undefined;
        const sentence = try statedAs(&buffer, limit);
        if (std.mem.indexOf(u8, joined, sentence) == null) {
            std.debug.print("docs/linea-semantics.md does not say \"{s}\", which is `{s}` as the limit table holds it\n", .{
                sentence,
                @tagName(limit),
            });
            missing += 1;
        }
    }
    try testing.expectEqual(@as(u32, 0), missing);
}

/// Why no generated program reaches `limit`, or null where one does.
///
/// A limit is listed here until a generator part writes a program at it. The
/// switch is exhaustive, so a limit added to the table is given a shape in
/// `writeLimit` or a reason here before this file compiles.
pub fn unwritten(limit: Limit) ?[]const u8 {
    return switch (limit) {
        .tree_height,
        .tuple_components,
        .answer_links,
        .array_length,
        .type_bytes,
        .raw_literal_hashes,
        .interpolation_depth,
        .format_count,
        => null,
        .coverage_cells => "the cells are counted over a `match`'s arms, and no part writes a `match` that wide",
        .embedded_bytes => "the bytes are a file's beside the program, and a generated program is one file",
    };
}

/// Whether a program at `limit` is written at `position`.
pub fn writes(limit: Limit, position: Position) bool {
    if (unwritten(limit) != null) return false;
    return switch (limit) {
        .tree_height, .tuple_components, .answer_links => position != .value,
        // An implementation's head is a named type, a tuple or a callable,
        // and both of these are written as arrays.
        .array_length, .type_bytes => position != .value and position != .implementation_head,
        .raw_literal_hashes, .interpolation_depth, .format_count => position == .value,
        .coverage_cells, .embedded_bytes => false,
    };
}

/// The bytes a tag adds before an enum's payload, which is also what the
/// enum's size is rounded up to.
const word_bytes = 8;

/// The count a program of `cell` writes.
fn countOf(cell: Shape.AtLimit) u64 {
    const most = cell.limit.most();
    if (cell.limit == .type_bytes and cell.position.isPayload()) {
        // The widest payload whose enum, a tag and the payload rounded up to
        // a word, is still within the limit.
        const widest = most - most % word_bytes - word_bytes;
        return widest + @intFromBool(cell.past);
    }
    return most + @intFromBool(cell.past);
}

/// Every limit, on each side of it, in each position that writes it.
pub const cells: []const Shape.AtLimit = blk: {
    @setEvalBranchQuota(10_000);
    var all: []const Shape.AtLimit = &.{};
    for (std.enums.values(Limit)) |limit| {
        for ([_]bool{ false, true }) |past| {
            for (std.enums.values(Position)) |position| {
                if (!writes(limit, position)) continue;
                all = all ++ [_]Shape.AtLimit{.{ .limit = limit, .past = past, .position = position }};
            }
        }
    }
    break :blk all;
};

test "a limit has a cell unless it says why it has none" {
    for (std.enums.values(Limit)) |limit| {
        var found: u32 = 0;
        for (cells) |cell| {
            if (cell.limit == limit) found += 1;
        }
        try testing.expectEqual(unwritten(limit) == null, found > 0);
        // Both sides, or the limit is only half held.
        try testing.expect(found % 2 == 0);
    }
}

/// The depths a doubling chain is generated at. A chain's check is held to
/// add at most `Work.growth` times what half the depth adds, and
/// `Work.slack` above that. A type of two to the twentieth names, spelled
/// out once at a few bytes a name, is several times the slack, so a pass
/// that walks the names and not the declarations is over its bound at every
/// depth here. The deepest keeps the type's size under [L-Size].
pub const shared_depths = [_]u32{ 20, 21, 22, 23, 24 };

/// The depths a doubling chain is generated at with a mistake planted in it.
///
/// At the shallow ones the whole name is a few kilobytes, so the check is
/// within its bound however the name is built and the one report is what
/// the program is held to.
pub const mistaken_depths = [_]u32{ 4, 8, 16, 18 };

/// Every shape a seed can select.
pub const shapes: []const Shape = blk: {
    @setEvalBranchQuota(10_000);
    var all: []const Shape = &.{};
    for (cells) |cell| all = all ++ [_]Shape{.{ .limit = cell }};
    for (shared_depths) |depth| {
        for (type_positions) |position| {
            all = all ++ [_]Shape{.{ .shared = .{ .depth = depth, .position = position } }};
        }
    }
    for (mistaken_depths) |depth| {
        for ([_]Position{ .let_annotation, .parameter }) |position| {
            all = all ++ [_]Shape{.{ .shared = .{ .depth = depth, .position = position, .mistaken = true } }};
        }
    }
    break :blk all;
};

comptime {
    // One byte of a choice stream selects a shape.
    std.debug.assert(shapes.len <= 256);
}

/// The shape a stream of choices selects.
pub fn shapeOf(bytes: []const u8) Shape {
    var c: Choices = .{ .bytes = bytes };
    return shapes[c.below(@intCast(shapes.len))];
}

/// The shape a seed selects, from the choices the seed fills.
pub fn shapeOfSeed(seed: u64) Shape {
    var bytes: [1]u8 = undefined;
    var prng = std.Random.DefaultPrng.init(seed);
    prng.random().bytes(&bytes);
    return shapeOf(&bytes);
}

test "a seed selects one shape, and the seeds reach both kinds" {
    var shared: u32 = 0;
    var at_limits: u32 = 0;
    for (0..64) |seed| {
        try testing.expect(std.meta.eql(shapeOfSeed(seed), shapeOfSeed(seed)));
        switch (shapeOfSeed(seed)) {
            .shared => shared += 1,
            .limit => at_limits += 1,
        }
    }
    try testing.expect(shared > 0);
    try testing.expect(at_limits > 0);
}

/// One thing as a position writes it.
const Written = struct {
    text: []const u8,
    /// What a variant holds for a derive naming `text` to find it.
    held: []const u8,
    /// Whether the rule reports once for the file or the type, however many
    /// places write it.
    once: bool,
    /// Whether `text` is an alias. An implementation is written for a type's
    /// own declaration, so its head holds an alias as an argument.
    alias: bool = false,
};

/// What every position writes in a program with nothing hostile in it.
const plain: Written = .{ .text = "UInt8", .held = "UInt8", .once = true };

/// Writes the declarations a program counting `n` at `limit` needs, and
/// returns how `position` spells what it counts.
fn writeLimit(
    gpa: std.mem.Allocator,
    w: *std.Io.Writer,
    limit: Limit,
    n: u64,
    position: Position,
) !Written {
    std.debug.assert(writes(limit, position));
    var text: std.Io.Writer.Allocating = .init(gpa);
    const t = &text.writer;
    switch (limit) {
        .tree_height => {
            // A trait's argument stands one level below the written type
            // that names the trait.
            const levels = if (position.isTraitArgument()) n - 1 else n;
            for (0..levels) |_| try t.writeAll("Option[");
            try t.writeAll("UInt8");
            for (0..levels) |_| try t.writeAll("]");
            return .{ .text = text.written(), .held = text.written(), .once = true };
        },
        .tuple_components => {
            try t.writeAll("(");
            for (0..n) |i| try t.writeAll(if (i == 0) "UInt8" else ", UInt8");
            try t.writeAll(")");
            return .{ .text = text.written(), .held = text.written(), .once = false };
        },
        .answer_links => {
            // Each alias is one link, the first included.
            try w.writeAll("alias _Link0 = UInt8\n");
            for (1..n) |i| try w.print("alias _Link{d} = _Link{d}\n", .{ i, i - 1 });
            try w.writeAll("\n");
            try t.print("_Link{d}", .{n - 1});
            return .{ .text = text.written(), .held = "UInt8", .once = true, .alias = true };
        },
        .array_length => {
            // The unit type has no bytes, so the length is the only limit
            // the array reaches.
            try t.print("[(); {d}]", .{n});
            return .{ .text = text.written(), .held = text.written(), .once = false };
        },
        .type_bytes => {
            // Bytes while the count is a length an array may have, and
            // two-byte elements past that.
            if (n <= Limit.array_length.most()) {
                try t.print("[UInt8; {d}]", .{n});
            } else {
                std.debug.assert(n % 2 == 0);
                try t.print("[UInt16; {d}]", .{n / 2});
            }
            return .{ .text = text.written(), .held = text.written(), .once = true };
        },
        .raw_literal_hashes => {
            try t.writeAll("r");
            for (0..n) |_| try t.writeAll("#");
            try t.writeAll("\"text\"");
            for (0..n) |_| try t.writeAll("#");
            return .{ .text = text.written(), .held = text.written(), .once = true };
        },
        .interpolation_depth => {
            for (0..n) |_| try t.writeAll("\"{");
            try t.writeAll("1");
            for (0..n) |_| try t.writeAll("}\"");
            return .{ .text = text.written(), .held = text.written(), .once = true };
        },
        .format_count => {
            try t.print("\"{{1:{d}}}\"", .{n});
            return .{ .text = text.written(), .held = text.written(), .once = true };
        },
        .coverage_cells, .embedded_bytes => unreachable,
    }
}

/// Writes the declarations of a doubling chain `depth` aliases above its
/// first, and returns the use of the last.
fn writeShared(gpa: std.mem.Allocator, w: *std.Io.Writer, depth: u32) !Written {
    try w.writeAll("struct _Pair[A, B] {\n    _left: A,\n    _right: B,\n}\n\n");
    try w.writeAll("alias _Twice0[T] = _Pair[T, T]\n");
    for (1..depth + 1) |i| {
        try w.print("alias _Twice{d}[T] = _Pair[_Twice{d}[T], _Twice{d}[T]]\n", .{ i, i - 1, i - 1 });
    }
    try w.writeAll("\n");
    const used = try std.fmt.allocPrint(gpa, "_Twice{d}[UInt8]", .{depth});
    return .{ .text = used, .held = used, .once = true, .alias = true };
}

/// Writes the declaration that holds `written` at `position` and the `main`
/// after it, and returns how many places wrote it.
fn place(w: *std.Io.Writer, position: Position, written: Written, mistaken: bool) !u32 {
    var writings: u32 = 1;
    var body: []const u8 = "0";
    switch (position) {
        .let_annotation => {
            if (!mistaken) try w.writeAll("fn _any[T]() -> T {\n    _any()\n}\n\n");
            try w.print("fn main() -> UInt8 {{\n    let _held: {s} = {s}\n    0\n}}\n", .{
                written.text,
                if (mistaken) "3" else "_any()",
            });
            return writings;
        },
        .value => {
            // A scalar's plain form is a number; every limit written here is
            // on a string literal.
            const plain_value = "\"text\"";
            try w.print("fn main() -> UInt8 {{\n    let _held = {s}\n    0\n}}\n", .{
                if (written.text.ptr == plain.text.ptr) plain_value else written.text,
            });
            return writings;
        },
        .parameter => {
            try w.print("fn _take(_given: {s}) -> UInt8 {{\n    0\n}}\n\n", .{written.text});
            if (mistaken) body = "_take(3)";
        },
        .field => try w.print("struct _Holder {{\n    _part: {s},\n}}\n\n", .{written.text}),
        .payload => try w.print("enum _Choice {{\n    _Only({s}),\n}}\n\n", .{written.text}),
        .implementation_argument => try w.print(
            \\struct _Target {{
            \\    _part: UInt8,
            \\}}
            \\
            \\trait _Reads[phantom X] {{
            \\    fn _read() -> UInt8
            \\}}
            \\
            \\impl _Reads[{s}] for _Target {{
            \\    fn _read() -> UInt8 {{
            \\        0
            \\    }}
            \\}}
            \\
            \\
        , .{written.text}),
        .derive_argument => {
            try w.print("@derive(From[{s}])\nenum _Choice {{\n    _Only({s}),\n}}\n\n", .{ written.text, written.held });
            if (written.held.ptr == written.text.ptr) writings = 2;
        },
        .implementation_head => try w.print(
            \\trait _Reads {{
            \\    fn _read() -> UInt8
            \\}}
            \\
            \\impl _Reads for {s}{s}{s} {{
            \\    fn _read() -> UInt8 {{
            \\        0
            \\    }}
            \\}}
            \\
            \\
        , .{
            if (written.alias) "Option[" else "",
            written.text,
            if (written.alias) "]" else "",
        }),
    }
    try w.print("fn main() -> UInt8 {{\n    {s}\n}}\n", .{body});
    return writings;
}

fn positionOf(shape: Shape) Position {
    return switch (shape) {
        .shared => |s| s.position,
        .limit => |l| l.position,
    };
}

/// The count `shape` grows with: a chain's depth or a limit's count.
fn sizeOf(shape: Shape) u64 {
    return switch (shape) {
        .shared => |s| s.depth,
        .limit => |l| countOf(l),
    };
}

/// The text of `shape` written at `size` in place of its own.
fn writeSized(gpa: std.mem.Allocator, shape: Shape, size: u64) !struct { text: []const u8, writings: u32, once: bool } {
    var out: std.Io.Writer.Allocating = .init(gpa);
    const w = &out.writer;
    switch (shape) {
        .shared => |s| {
            const written = try writeShared(gpa, w, @intCast(size));
            const writings = try place(w, s.position, written, s.mistaken);
            return .{ .text = out.written(), .writings = writings, .once = true };
        },
        .limit => |l| {
            const written = try writeLimit(gpa, w, l.limit, size, l.position);
            const writings = try place(w, l.position, written, false);
            return .{ .text = out.written(), .writings = writings, .once = written.once };
        },
    }
}

/// The rule the program of `shape` is refused under, or null where it is
/// accepted.
pub fn refusingRule(shape: Shape) ?Code {
    return switch (shape) {
        .shared => |s| if (s.mistaken) .t_mismatch else null,
        .limit => |l| if (l.past) codeOf(l.limit) else null,
    };
}

/// The program of `shape`, and what the compiler must say of it.
pub fn write(gpa: std.mem.Allocator, shape: Shape) !Program {
    const sized = try writeSized(gpa, shape, sizeOf(shape));
    const expectation: Expectation = if (refusingRule(shape)) |rule|
        .{ .refused = .{ .rule = rule, .reports = if (sized.once) 1 else sized.writings } }
    else
        .accepted;
    return .{ .shape = shape, .text = sized.text, .expectation = expectation };
}

/// The program a seed selects.
pub fn fromSeed(gpa: std.mem.Allocator, seed: u64) !Program {
    return write(gpa, shapeOfSeed(seed));
}

/// `shape` at half its size, which is within every limit.
fn writeHalf(gpa: std.mem.Allocator, shape: Shape) ![]const u8 {
    const least: u64 = switch (shape) {
        .shared => 1,
        .limit => |l| l.limit.fewest() orelse 1,
    };
    return (try writeSized(gpa, shape, @max(least, sizeOf(shape) / 2))).text;
}

/// The declarations and the `main` of `shape` with `UInt8`, or a plain
/// string, where the hostile thing is written, and nothing else.
fn writePlain(gpa: std.mem.Allocator, shape: Shape) ![]const u8 {
    var out: std.Io.Writer.Allocating = .init(gpa);
    _ = try place(&out.writer, positionOf(shape), plain, false);
    return out.written();
}

/// The allocation work of three checks, from which a program's bound is
/// taken.
///
/// Work is the sum of what a check asks its allocator for, counted above a
/// fresh arena over whole pages with growth in place refused. No clock is
/// read, and two checks of one program in one build count the same.
///
/// `plain` is the program's position with nothing hostile written in it, so
/// `whole - plain` is the work the hostile thing adds beside the library.
/// `half` is the same shape at half its size. A check whose work is linear
/// in what is written adds about twice at the whole size what it adds at
/// half; one that is quadratic adds four times, and one that follows the
/// names of a doubling chain adds two to the half depth times. The bound
/// allows three times, and `slack` above that.
pub const Work = struct {
    plain: usize,
    half: usize,
    whole: usize,

    /// How many times the work the half size adds the whole size may add.
    pub const growth = 3;

    /// The share of `plain` every program is allowed above `growth`.
    ///
    /// A check appends to tables that already hold the library, and a table
    /// that grows is charged its whole new size. Which of the three programs
    /// crosses a table's capacity is an accident of the library's size, so
    /// their differences carry an error that grows with `plain`: a few tenths
    /// of a percent of it over the libraries measured. The allowance is a
    /// share of `plain` for that reason, so a larger library widens it by
    /// what it widens the error. Added work under it is not held to `growth`
    /// at all, which is also what a size that does not lengthen the program
    /// needs: an array's length adds the same few allocations at half.
    pub const slack_share = 64;

    /// How far past its bound a check runs before it is stopped. The reports
    /// of a program over its bound are still read, so a check is ended only
    /// where finishing it would take memory the walk does not have.
    pub const room: usize = 1 << 30;

    pub fn slack(self: Work) usize {
        return self.plain / slack_share;
    }

    /// The most the whole program's check may take.
    pub fn bound(self: Work) usize {
        return self.plain + self.slack() + growth * (self.half -| self.plain);
    }

    pub fn over(self: Work) bool {
        return self.whole > self.bound();
    }
};

/// What a check of one program took and said.
const Measured = struct {
    took: usize,
    /// Whether an allocation was refused at `most`.
    stopped: bool,
    /// The rule of each error, in the order reported.
    reports: []const ?Code,
};

/// Checks `text` beside the library and counts the work. `reports` is
/// allocated from `gpa`; everything else the check held is released.
fn measure(
    gpa: std.mem.Allocator,
    library: ?*const loader.CheckedLibrary,
    text: []const u8,
    most: usize,
) !Measured {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    // Growth in place is refused. An arena inside the check otherwise grows
    // its last node by what each allocation needs, and every growth is
    // charged its full size, so the count would follow how often a node
    // happened to have room after it.
    var counting: Counting = .{ .under = arena.allocator(), .allow_growth = false, .most = most };

    const loaded = generate.checkLoadedText(counting.allocator(), "hostile.lin", text, library) catch |err| {
        if (err == error.OutOfMemory and counting.refused) return .{ .took = counting.took, .stopped = true, .reports = &.{} };
        return err;
    };
    // A refused allocation does not always end the check: a report whose
    // text could not be built is dropped, so what is left is not what the
    // compiler says of the program.
    if (counting.refused) return .{ .took = counting.took, .stopped = true, .reports = &.{} };

    var reports: std.ArrayList(?Code) = .empty;
    for (loaded.sink.items()) |d| {
        if (d.severity == .err) try reports.append(gpa, d.code);
    }
    return .{ .took = counting.took, .stopped = false, .reports = reports.items };
}

test "two checks of one program count the same work" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    const program = try write(gpa, .{ .limit = .{ .limit = .tuple_components, .past = false, .position = .field } });

    const first = try measure(gpa, test_library.get(), program.text, std.math.maxInt(usize));
    // Allocations between the two move every address the second check is
    // given.
    _ = try gpa.alloc(u8, 12345);
    _ = try std.heap.page_allocator.alloc(u8, 3 << 20);
    const second = try measure(gpa, test_library.get(), program.text, std.math.maxInt(usize));
    try testing.expectEqual(first.took, second.took);
}

/// What the compiler did with one program.
pub const Observed = struct {
    /// The rule of each error, in the order reported. Empty where the check
    /// was stopped.
    reports: []const ?Code,
    work: Work,
    /// Whether the check was ended `Work.room` past its bound, so what the
    /// compiler says of the program is not known.
    stopped: bool,
};

/// Checks the program of `shape` and the two programs its bound is taken
/// from. Allocates from `gpa` and frees nothing it returns.
pub fn observe(
    gpa: std.mem.Allocator,
    library: ?*const loader.CheckedLibrary,
    program: Program,
) !Observed {
    const unbounded = std.math.maxInt(usize);
    const plain_work = try measure(gpa, library, try writePlain(gpa, program.shape), unbounded);
    const half_work = try measure(gpa, library, try writeHalf(gpa, program.shape), unbounded);
    var work: Work = .{ .plain = plain_work.took, .half = half_work.took, .whole = 0 };
    const whole = try measure(gpa, library, program.text, work.bound() + Work.room);
    work.whole = whole.took;
    return .{ .reports = whole.reports, .work = work, .stopped = whole.stopped };
}

/// A defect a generated program shows in the compiler, recorded so the walk
/// stays green while the defect stands and fails when it stops reproducing.
///
/// A finding records everything the compiler says of the programs it covers.
/// A program that says anything else, one more report or one under another
/// rule, fails as a program with no finding does.
pub const Finding = struct {
    /// A seed whose program shows it.
    seed: u64,
    covers: Covers,
    /// The rule of each error the compiler reports, in order.
    reports: []const Code,
    /// Whether the check takes more work than its bound.
    over: bool = false,
    /// What the language requires of the program.
    requires: []const u8,

    pub const Covers = union(enum) {
        limit: struct { limit: Limit, past: bool, positions: []const Position },
        /// A doubling chain with a planted mistake, at these depths.
        mistaken: []const u32,
    };

    pub fn covering(self: Finding, shape: Shape) bool {
        switch (self.covers) {
            .limit => |c| {
                if (shape != .limit) return false;
                const l = shape.limit;
                if (l.limit != c.limit or l.past != c.past) return false;
                return std.mem.indexOfScalar(Position, c.positions, l.position) != null;
            },
            .mistaken => |depths| {
                if (shape != .shared or !shape.shared.mistaken) return false;
                return std.mem.indexOfScalar(u32, depths, shape.shared.depth) != null;
            },
        }
    }
};

pub const known_findings = [_]Finding{
    .{
        .seed = 2,
        .covers = .{ .limit = .{
            .limit = .answer_links,
            .past = true,
            .positions = &.{ .implementation_argument, .derive_argument, .implementation_head },
        } },
        .reports = &.{},
        .requires = "[T-AnswerDepth] refuses a chain of 1001 aliases wherever its last alias is written, " ++
            "as it does in a `let`, a parameter, a field and a payload",
    },
    .{
        .seed = 11,
        .covers = .{ .limit = .{
            .limit = .tree_height,
            .past = true,
            .positions = &.{ .let_annotation, .parameter, .field, .payload, .implementation_argument, .implementation_head },
        } },
        .reports = &.{ .s_nesting, .t_bound },
        .requires = "[S-Nesting] is the only report of a type nested 1001 levels: what stands past the limit " ++
            "is stepped over, so the `Option` at the cut is not reported as given no argument",
    },
    .{
        .seed = 217,
        .covers = .{ .limit = .{ .limit = .tree_height, .past = true, .positions = &.{.derive_argument} } },
        .reports = &.{ .s_nesting, .t_derive },
        .requires = "[S-Nesting] is the only report of a type nested 1001 levels: a derive naming the type " ++
            "does not also say that no variant wraps it",
    },
    .{
        .seed = 61,
        .covers = .{ .limit = .{ .limit = .tuple_components, .past = true, .positions = &.{.derive_argument} } },
        .reports = &.{ .s_tuple, .s_tuple, .s_tuple },
        .requires = "a tuple of nine components written twice, as a derive's argument and as the payload " ++
            "the derive finds, earns two reports under [S-Tuple]",
    },
    .{
        .seed = 81,
        .covers = .{ .limit = .{ .limit = .array_length, .past = true, .positions = &.{.derive_argument} } },
        .reports = &.{ .t_array_size, .t_array_size, .t_array_size },
        .requires = "an array type one element too long written twice, as a derive's argument and as the " ++
            "payload the derive finds, earns two reports under [T-ArraySize]",
    },
    .{
        .seed = 8,
        .covers = .{ .limit = .{ .limit = .raw_literal_hashes, .past = true, .positions = &.{.value} } },
        .reports = &.{ .s_string, .t_mismatch },
        .requires = "[S-String] is the only report of a raw literal opened with nine `#`: the binding it " ++
            "initialises and the function around it are not reported as a consequence",
    },
    .{
        .seed = 54,
        .covers = .{ .limit = .{ .limit = .interpolation_depth, .past = true, .positions = &.{.value} } },
        .reports = &.{ .s_string, .s_string, .s_entry, .t_mismatch },
        .requires = "[S-String] reports a literal that opens a seventeenth interpolation once, and the rest " ++
            "of the file is read as it is without it",
    },
    .{
        .seed = 32,
        .covers = .{ .mistaken = &.{ 16, 18 } },
        .reports = &.{.t_mismatch},
        .over = true,
        .requires = "a `UInt8` given where a doubling alias chain's type is wanted is refused under " ++
            "[T-Mismatch] with work that grows with the chain's declarations, not with the names the " ++
            "type spells out",
    },
};

pub fn findingOf(shape: Shape) ?*const Finding {
    for (&known_findings) |*finding| {
        if (finding.covering(shape)) return finding;
    }
    return null;
}

/// Whether some shape states a refusal under `rule` that its check is
/// compared against: a shape no finding covers, or one whose finding still
/// records a report under the rule.
pub fn reaches(rule: Code) bool {
    for (shapes) |shape| {
        if (refusingRule(shape) != rule) continue;
        const finding = findingOf(shape) orelse return true;
        if (std.mem.indexOfScalar(Code, finding.reports, rule) != null) return true;
    }
    return false;
}

/// How a program's check differs from what is expected of it.
pub const Disagreement = struct {
    what: []const u8,
    expected: []const u8,
    actual: []const u8,
};

fn sameReports(actual: []const ?Code, expected: []const Code) bool {
    if (actual.len != expected.len) return false;
    for (actual, expected) |a, e| {
        if (a != e) return false;
    }
    return true;
}

fn statedReports(gpa: std.mem.Allocator, expectation: Expectation) ![]const Code {
    return switch (expectation) {
        .accepted => &.{},
        .refused => |r| blk: {
            const all = try gpa.alloc(Code, r.reports);
            @memset(all, r.rule);
            break :blk all;
        },
    };
}

fn describe(gpa: std.mem.Allocator, reports: anytype, over: bool, work: ?Work) ![]const u8 {
    var out: std.Io.Writer.Allocating = .init(gpa);
    const w = &out.writer;
    if (reports.len == 0) try w.writeAll("accepted");
    for (reports, 0..) |report, i| {
        const code: ?Code = report;
        try w.print("{s}[{s}]", .{ if (i == 0) "refused: " else ", ", if (code) |c| c.ruleName() else "no rule" });
    }
    try w.print("; {s} the bound on its work", .{if (over) "over" else "within"});
    if (work) |measured| {
        try w.print(" (adds {d} bytes to {d}, {d} at half its size, bound {d})", .{
            measured.whole -| measured.plain,
            measured.plain,
            measured.half -| measured.plain,
            measured.bound() - measured.plain,
        });
    }
    return out.written();
}

/// What is wrong with what `observed` says of `program`, given the findings
/// recorded: null where the program is answered as it states and nothing is
/// recorded against it, or exactly as its finding records.
pub fn judge(gpa: std.mem.Allocator, program: Program, observed: Observed) !?Disagreement {
    const stated = try statedReports(gpa, program.expectation);
    const said = if (observed.stopped)
        try std.fmt.allocPrint(gpa, "stopped {d} bytes past the bound on its work, before it answered", .{Work.room})
    else
        try describe(gpa, observed.reports, observed.work.over(), observed.work);
    const as_stated = !observed.stopped and !observed.work.over() and sameReports(observed.reports, stated);

    const finding = findingOf(program.shape) orelse {
        if (as_stated) return null;
        return .{
            .what = "a hostile program is not answered as it states",
            .expected = try std.fmt.allocPrint(gpa, "{s}\n{s}", .{ try describe(gpa, stated, false, null), excerpt(program.text) }),
            .actual = said,
        };
    };
    if (as_stated) return .{
        .what = "a recorded finding no longer reproduces, so its entry in `known_findings` is removed",
        .expected = try std.fmt.allocPrint(gpa, "{s}\n{s}", .{ try describe(gpa, finding.reports, finding.over, null), finding.requires }),
        .actual = said,
    };
    if (!observed.stopped and observed.work.over() == finding.over and sameReports(observed.reports, finding.reports)) return null;
    return .{
        .what = "a program with a recorded finding is answered another way",
        .expected = try std.fmt.allocPrint(gpa, "{s}\n{s}", .{ try describe(gpa, finding.reports, finding.over, null), finding.requires }),
        .actual = said,
    };
}

/// The end of a program, where its use of what it counts is written. The
/// declarations above it are a thousand lines of one pattern.
fn excerpt(text: []const u8) []const u8 {
    const most = 240;
    if (text.len <= most) return text;
    return text[text.len - most ..];
}

test "a finding's seed selects a program the finding covers" {
    for (known_findings) |finding| {
        try testing.expect(finding.covering(shapeOfSeed(finding.seed)));
    }
}

test "no shape is covered by two findings, and every finding covers one" {
    for (shapes) |shape| {
        var covering: u32 = 0;
        for (known_findings) |finding| covering += @intFromBool(finding.covering(shape));
        try testing.expect(covering <= 1);
    }
    for (known_findings) |finding| {
        var covered: u32 = 0;
        for (shapes) |shape| covered += @intFromBool(finding.covering(shape));
        try testing.expect(covered > 0);
    }
}

test "slow: every hostile shape is answered as it states, or as a finding records" {
    try slow_tests.skipUnlessRun();
    var per_program = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer per_program.deinit();

    var disagreed: u32 = 0;
    for (shapes) |shape| {
        _ = per_program.reset(.retain_capacity);
        const scratch = per_program.allocator();
        const program = try write(scratch, shape);
        const observed = try observe(scratch, test_library.get(), program);
        if (try judge(scratch, program, observed)) |d| {
            disagreed += 1;
            std.debug.print("\n{f}: {s}\n--- expected\n{s}\n--- actual\n{s}\n", .{ shape, d.what, d.expected, d.actual });
        }
    }
    try testing.expectEqual(@as(u32, 0), disagreed);
}
