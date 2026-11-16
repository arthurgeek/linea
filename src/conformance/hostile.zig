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
//! Every program is also held to a bound on the allocation work of its
//! check, see `Work`.

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
const Regions = @import("counting.zig").Regions;
const generate = @import("generate.zig");
const Layout = @import("../sema/types.zig").Layout;

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
    /// The same, where the count is a format's precision and not its width.
    value_precision,

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
            .value_precision => "a `let` initialiser, as a precision",
        };
    }

    /// Whether the position is an argument of a written trait, which is one
    /// level of the written type that names the trait.
    fn isTraitArgument(self: Position) bool {
        return self == .implementation_argument or self == .derive_argument;
    }

    fn isValue(self: Position) bool {
        return self == .value or self == .value_precision;
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

/// A count as the semantics document groups a long one: `16 777 216`.
fn inGroups(buffer: []u8, n: u64) ![]const u8 {
    var digits: [24]u8 = undefined;
    const plain = try std.fmt.bufPrint(&digits, "{d}", .{n});
    var w = std.Io.Writer.fixed(buffer);
    for (plain, 0..) |digit, i| {
        if (i != 0 and (plain.len - i) % 3 == 0) try w.writeByte(' ');
        try w.writeByte(digit);
    }
    return w.buffered();
}

/// The `at`th sentence of `docs/linea-semantics.md` that states `limit`,
/// written from the table's number, or null past the last one. The first is
/// the sentence under the limit's own rule.
fn statedAs(buffer: []u8, limit: Limit, at: usize) !?[]const u8 {
    const most = limit.most();
    var groups: [32]u8 = undefined;
    return switch (limit) {
        .tree_height => switch (at) {
            0 => try std.fmt.bufPrint(buffer, "nests at most {d} levels deep", .{most}),
            else => null,
        },
        .tuple_components => switch (at) {
            0 => try std.fmt.bufPrint(buffer, "at least {s} components and at most {s}", .{
                inWords(limit.fewest().?),
                inWords(most),
            }),
            1 => try std.fmt.bufPrint(buffer, "| `Tuple{d}` | a tuple of {s} components constructs this type |", .{ most, inWords(most) }),
            2 => try std.fmt.bufPrint(buffer, "and likewise through `Tuple{d}`", .{most}),
            else => null,
        },
        .answer_links => switch (at) {
            0 => try std.fmt.bufPrint(buffer, "passes through at most {d} links", .{most}),
            1 => try std.fmt.bufPrint(buffer, "chain of {d} settled references", .{most}),
            2 => try std.fmt.bufPrint(buffer, "and one of {d} is refused where the chain starts", .{most + 1}),
            3 => try std.fmt.bufPrint(buffer, "A plain chain of {d} aliases is refused as well", .{most + 1}),
            else => null,
        },
        .coverage_cells => switch (at) {
            0 => try std.fmt.bufPrint(buffer, "more than 2^{d} cells", .{std.math.log2_int(u64, most)}),
            else => null,
        },
        .array_length => switch (at) {
            0 => try std.fmt.bufPrint(buffer, "The maximum length is {d}", .{most}),
            else => null,
        },
        .type_bytes => switch (at) {
            0 => try std.fmt.bufPrint(buffer, "A type is at most {d} bytes (2^{d} - 1, just under {d} GiB)", .{
                most,
                std.math.log2_int(u64, most + 1),
                (most + 1) >> 30,
            }),
            else => null,
        },
        .raw_literal_hashes => switch (at) {
            0 => try std.fmt.bufPrint(buffer, "A raw literal opens with at most {s} `#`", .{inWords(most)}),
            1 => try std.fmt.bufPrint(buffer, "Up to {s} hashes may open one", .{inWords(most)}),
            else => null,
        },
        .interpolation_depth => switch (at) {
            0 => try std.fmt.bufPrint(buffer, "with at most {d} interpolations open at once", .{most}),
            else => null,
        },
        .format_count => switch (at) {
            0 => try std.fmt.bufPrint(buffer, "a width or precision above {d}", .{most}),
            else => null,
        },
        .embedded_bytes => switch (at) {
            0 => try std.fmt.bufPrint(buffer, "and when the file holds more than {d} MiB ({s} bytes), which is refused before the file is read", .{
                most >> 20,
                try inGroups(&groups, most),
            }),
            else => null,
        },
    };
}

test "the semantics document states every limit as the table holds it" {
    // The compiler and the generator read one table, so a wrong number in it
    // is accepted by both. The document is the third statement of each limit
    // and the only one the table is not derived from. Every sentence of it
    // that writes a limit's number is listed in `statedAs`.
    const semantics = @embedFile("semantics");
    const joined = try testing.allocator.dupe(u8, semantics);
    defer testing.allocator.free(joined);
    // A sentence may break across lines anywhere.
    for (joined) |*byte| {
        if (byte.* == '\n') byte.* = ' ';
    }

    try testing.expect(std.math.isPowerOfTwo(Limit.coverage_cells.most()));
    try testing.expect(std.math.isPowerOfTwo(Limit.type_bytes.most() + 1));
    try testing.expectEqual(@as(u64, 0), Limit.embedded_bytes.most() % (1 << 20));

    var missing: u32 = 0;
    for (std.enums.values(Limit)) |limit| {
        var at: usize = 0;
        while (true) : (at += 1) {
            var buffer: [192]u8 = undefined;
            const sentence = (try statedAs(&buffer, limit, at)) orelse break;
            if (std.mem.indexOf(u8, joined, sentence) != null) continue;
            std.debug.print("docs/linea-semantics.md does not say \"{s}\", which is `{s}` as the limit table holds it\n", .{
                sentence,
                @tagName(limit),
            });
            missing += 1;
        }
        try testing.expect(at > 0);
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
        .tree_height, .tuple_components, .answer_links => !position.isValue(),
        // An implementation's head is a named type, a tuple or a callable,
        // and both of these are written as arrays.
        .array_length, .type_bytes => !position.isValue() and position != .implementation_head,
        .raw_literal_hashes, .interpolation_depth => position == .value,
        .format_count => position.isValue(),
        .coverage_cells, .embedded_bytes => false,
    };
}

/// The count a program of `cell` writes.
fn countOf(cell: Shape.AtLimit) u64 {
    const most = cell.limit.most();
    if (cell.limit == .type_bytes and cell.position.isPayload()) {
        // The widest payload whose enum, a tag and the payload rounded up to
        // the tag's width, is still within the limit.
        const widest = most - most % Layout.tag_width - Layout.tag_width;
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

/// The depths a doubling chain is generated at. The deepest keeps the
/// type's size under [L-Size].
pub const shared_depths = [_]u32{ 20, 21, 22, 23, 24 };

/// The depths a doubling chain is generated at with a mistake planted in it.
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
    /// Whether `text` is held as the argument of an `Option` where it heads
    /// an implementation. An implementation is written for a type's own
    /// declaration, so an alias is; a reference is held as its whole is.
    alias: bool = false,
};

/// Which of a shape's two programs is written.
const Form = enum {
    /// The program the shape names.
    whole,
    /// The program the shape's work is compared with, see `Work`.
    reference,
};

/// The count a limit's reference program writes where the count is not
/// material: a number in the text, or too few parts to regroup. Null where
/// the reference regroups the same parts into two halves.
fn referenceCount(limit: Limit) ?u64 {
    return switch (limit) {
        .tree_height, .answer_links => null,
        .tuple_components => limit.fewest().?,
        .array_length, .type_bytes => 2,
        .raw_literal_hashes, .interpolation_depth, .format_count => 1,
        .coverage_cells, .embedded_bytes => unreachable,
    };
}

fn writeNested(t: *std.Io.Writer, levels: u64, leaf: []const u8) !void {
    for (0..levels) |_| try t.writeAll("Option[");
    try t.writeAll(leaf);
    for (0..levels) |_| try t.writeAll("]");
}

/// Writes the declarations a program counting `n` at `limit` needs, and
/// returns how `position` spells what it counts.
fn writeLimit(
    gpa: std.mem.Allocator,
    w: *std.Io.Writer,
    limit: Limit,
    n: u64,
    position: Position,
    form: Form,
) !Written {
    std.debug.assert(writes(limit, position));
    var text: std.Io.Writer.Allocating = .init(gpa);
    const t = &text.writer;
    const count = if (form == .reference) referenceCount(limit) orelse n else n;
    switch (limit) {
        .tree_height => {
            // A trait's argument stands one level below the written type
            // that names the trait.
            const levels = if (position.isTraitArgument()) count - 1 else count;
            switch (form) {
                .whole => try writeNested(t, levels, "UInt8"),
                // The same wrappers in two types, with leaves that keep the
                // two halves from being one type, held by a named type as
                // the whole is one.
                .reference => {
                    try w.writeAll("struct _Both[A, B] {\n    _one: A,\n    _other: B,\n}\n\n");
                    try t.writeAll("_Both[");
                    try writeNested(t, levels / 2, "UInt8");
                    try t.writeAll(", ");
                    try writeNested(t, levels - levels / 2, "Bool");
                    try t.writeAll("]");
                },
            }
            return .{ .text = text.written(), .held = text.written(), .once = true };
        },
        .tuple_components => {
            try t.writeAll("(");
            for (0..count) |i| try t.writeAll(if (i == 0) "UInt8" else ", UInt8");
            try t.writeAll(")");
            return .{ .text = text.written(), .held = text.written(), .once = false };
        },
        .answer_links => {
            // Each alias is one link, the last included. Every alias names
            // the one declared after it, so the first is settled through all
            // of them and not one at a time as each is declared. The
            // reference declares the same aliases as two chains of half the
            // length.
            const last = if (form == .reference) count / 2 - 1 else count - 1;
            for (0..count) |i| {
                if (i == last or i == count - 1) {
                    try w.print("alias _Link{d} = UInt8\n", .{i});
                } else {
                    try w.print("alias _Link{d} = _Link{d}\n", .{ i, i + 1 });
                }
            }
            try w.writeAll("\n");
            // The whole uses its one chain where the type is written. The
            // reference uses its first chain there and its second here, so
            // both of its chains are read from their first alias.
            if (form == .reference) try w.print("fn _second(_given: _Link{d}) -> UInt8 {{\n    0\n}}\n\n", .{count / 2});
            try t.writeAll("_Link0");
            return .{ .text = text.written(), .held = "UInt8", .once = true, .alias = true };
        },
        .array_length => {
            // The unit type has no bytes, so the length is the only limit
            // the array reaches.
            try t.print("[(); {d}]", .{count});
            return .{ .text = text.written(), .held = text.written(), .once = false };
        },
        .type_bytes => {
            // Bytes while the count is a length an array may have, and
            // two-byte elements past that.
            if (count <= Limit.array_length.most()) {
                try t.print("[UInt8; {d}]", .{count});
            } else {
                std.debug.assert(count % 2 == 0);
                try t.print("[UInt16; {d}]", .{count / 2});
            }
            return .{ .text = text.written(), .held = text.written(), .once = true };
        },
        .raw_literal_hashes => {
            try t.writeAll("r");
            for (0..count) |_| try t.writeAll("#");
            try t.writeAll("\"text\"");
            for (0..count) |_| try t.writeAll("#");
            return .{ .text = text.written(), .held = text.written(), .once = true };
        },
        .interpolation_depth => {
            for (0..count) |_| try t.writeAll("\"{");
            try t.writeAll("1");
            for (0..count) |_| try t.writeAll("}\"");
            return .{ .text = text.written(), .held = text.written(), .once = true };
        },
        .format_count => {
            if (position == .value_precision) {
                try t.print("\"{{1.5:.{d}}}\"", .{count});
            } else {
                try t.print("\"{{1:{d}}}\"", .{count});
            }
            return .{ .text = text.written(), .held = text.written(), .once = true };
        },
        .coverage_cells, .embedded_bytes => unreachable,
    }
}

/// Writes the declarations of a doubling chain `depth` aliases above its
/// first, and returns the use of the last. The reference declares the same
/// aliases as two chains of half the depth and uses both.
fn writeShared(gpa: std.mem.Allocator, w: *std.Io.Writer, depth: u32, form: Form) !Written {
    const restart = if (form == .reference) (depth + 1) / 2 else depth + 1;
    try w.writeAll("struct _Pair[A, B] {\n    _left: A,\n    _right: B,\n}\n\n");
    for (0..depth + 1) |i| {
        if (i == 0 or i == restart) {
            try w.print("alias _Twice{d}[T] = _Pair[T, T]\n", .{i});
        } else {
            try w.print("alias _Twice{d}[T] = _Pair[_Twice{d}[T], _Twice{d}[T]]\n", .{ i, i - 1, i - 1 });
        }
    }
    try w.writeAll("\n");
    switch (form) {
        .whole => {
            const used = try std.fmt.allocPrint(gpa, "_Twice{d}[UInt8]", .{depth});
            return .{ .text = used, .held = used, .once = true, .alias = true };
        },
        .reference => {
            const used = try std.fmt.allocPrint(gpa, "_Pair[_Twice{d}[UInt8], _Twice{d}[Bool]]", .{ restart - 1, depth });
            // Held in an `Option` where it heads an implementation, as the
            // whole's alias is.
            return .{ .text = used, .held = used, .once = true, .alias = true };
        },
    }
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
        .value, .value_precision => {
            try w.print("fn main() -> UInt8 {{\n    let _held = {s}\n    0\n}}\n", .{written.text});
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

/// The text of one of `shape`'s two programs.
fn writeForm(gpa: std.mem.Allocator, shape: Shape, form: Form) !struct { text: []const u8, writings: u32, once: bool } {
    var out: std.Io.Writer.Allocating = .init(gpa);
    const w = &out.writer;
    switch (shape) {
        .shared => |s| {
            const written = try writeShared(gpa, w, s.depth, form);
            const writings = try place(w, s.position, written, s.mistaken);
            return .{ .text = out.written(), .writings = writings, .once = true };
        },
        .limit => |l| {
            const written = try writeLimit(gpa, w, l.limit, countOf(l), l.position, form);
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
    const whole = try writeForm(gpa, shape, .whole);
    const expectation: Expectation = if (refusingRule(shape)) |rule|
        .{ .refused = .{ .rule = rule, .reports = if (whole.once) 1 else whole.writings } }
    else
        .accepted;
    return .{ .shape = shape, .text = whole.text, .expectation = expectation };
}

/// The program a seed selects.
pub fn fromSeed(gpa: std.mem.Allocator, seed: u64) !Program {
    return write(gpa, shapeOfSeed(seed));
}

/// The allocation work of a shape's program and of its reference.
///
/// Work is the sum of what a check asks its allocator for: each allocation's
/// size, and for a buffer that grows in place the bytes it adds. No clock is
/// read, and two checks of one program in one build count the same.
///
/// The reference is the same position holding the same material arranged
/// so that nothing in it is deep, shared or large:
///
///   - a chain of declared answers, a nested type and a doubling chain are
///     written as two of half the length, over the same number of
///     declarations and of written levels;
///   - an array's length, a type's bytes, a format's count and a raw
///     literal's `#` are a number or a run in one token, and the reference
///     writes a small one;
///   - a tuple's components and an interpolation's depth are too few to
///     regroup, and the reference writes the fewest.
///
/// The two programs are within a few tokens of each other, so every table
/// that grows as a file is read, tokens, nodes, declarations and names,
/// reaches the same capacity in both, with the same declarations before
/// them or none. What is left in `whole - reference` is the work the
/// arrangement itself costs.
///
/// So the bound fails a check whose work grows faster than the depth of a
/// chain or a nesting, or with the names a shared type spells out, or with
/// an array's length, once that work passes the allowance: at a thousand
/// nested levels, sixteen bytes for each pair of a level and a level around
/// it fails and four bytes passes.
///
/// It does not fail work in proportion to the material, however much: a pass
/// that wastes the same bytes for every alias or level costs the reference
/// as much. Nor work that grows with how many declarations a file holds, of
/// which both programs hold the same number.
pub const Work = struct {
    reference: usize,
    whole: usize,

    /// The share of `reference` that `whole` may exceed it by.
    ///
    /// A doubling chain costs up to 1.65 MB more than its two halves, about
    /// two thirds of this beside the prelude: the compiler spends a bounded
    /// amount naming each level of a shared type, and a chain of half the
    /// depth is too short to reach that bound. No limit's shape differs by
    /// more than 0.9 MB.
    pub const allowance_share = 50;

    /// The most one check may take, the reference's and the whole's alike.
    /// Four times what the largest library measured costs a check that
    /// writes nothing, and what a walker can hold beside its other checks.
    /// A check stopped here is not answered, and the program fails.
    pub const cap: usize = 1 << 30;

    pub fn allowance(self: Work) usize {
        return self.reference / allowance_share;
    }

    pub fn over(self: Work) bool {
        return self.whole > self.reference + self.allowance();
    }

    fn difference(self: Work) usize {
        return self.whole -| self.reference;
    }

    /// The first measurement with the second's difference, where the second
    /// shows the first was over by an arena's node: null where it does not.
    fn excusesNode(first: Work, second: Work) ?Work {
        if (first.difference() -| second.difference() < node_step) return null;
        if (second.difference() > first.allowance()) return null;
        return .{ .reference = first.reference, .whole = first.reference + second.difference() };
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
    library: *const loader.CheckedLibrary,
    text: []const u8,
    most: usize,
) !Measured {
    // A large allocation grows in place and is charged what it adds, so a
    // table costs its last capacity and not every capacity it had.
    var regions = Regions.init();
    defer regions.deinit();
    var counting: Counting = .{ .under = regions.allocator(), .charge = .added, .most = most };

    const loaded = generate.checkLoadedText(counting.allocator(), "hostile.lin", text, library) catch |err| {
        // The system refusing address space is not the check passing its
        // bound, and is not reported as one.
        if (regions.failed) return error.RegionReservationFailed;
        if (err == error.OutOfMemory and counting.refused) return .{ .took = counting.took, .stopped = true, .reports = &.{} };
        return err;
    };
    if (regions.failed) return error.RegionReservationFailed;
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

test "a second measurement excuses a node and never a program" {
    const plain: Work = .{ .reference = 100 << 20, .whole = (100 << 20) + (30 << 20) };
    try testing.expect(plain.over());

    // Thirty megabytes over, and within the allowance once declarations
    // moved the node: the node's.
    const moved: Work = .{ .reference = 140 << 20, .whole = (140 << 20) + (1 << 20) };
    try testing.expect(!Work.excusesNode(plain, moved).?.over());

    // A program three megabytes over stays over when its difference falls
    // to under the larger allowance the declarations bring, since it did
    // not fall by a node.
    const costly: Work = .{ .reference = 100 << 20, .whole = (100 << 20) + (3 << 20) };
    const behind: Work = .{ .reference = 140 << 20, .whole = (140 << 20) + (5 << 19) };
    try testing.expect(costly.over());
    try testing.expect(!behind.over());
    try testing.expectEqual(@as(?Work, null), Work.excusesNode(costly, behind));

    // A fall of a node that leaves more than the first allowance is still
    // over.
    const still: Work = .{ .reference = 140 << 20, .whole = (140 << 20) + (5 << 20) };
    try testing.expectEqual(@as(?Work, null), Work.excusesNode(plain, still));
}

test "two checks of one program count the same work" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    const program = try write(gpa, .{ .limit = .{ .limit = .tuple_components, .past = false, .position = .field } });

    const first = try measure(gpa, test_library.get(), program.text, Work.cap);
    // Allocations between the two move every address the second check is
    // given.
    _ = try gpa.alloc(u8, 12345);
    _ = try std.heap.page_allocator.alloc(u8, 3 << 20);
    const second = try measure(gpa, test_library.get(), program.text, Work.cap);
    try testing.expectEqual(first.took, second.took);
}

/// What the compiler did with one program.
pub const Observed = struct {
    /// The rule of each error, in the order reported. Empty where the check
    /// was stopped.
    reports: []const ?Code,
    work: Work,
    /// Whether a check was ended at `Work.cap`, so what the compiler says of
    /// the program is not known.
    stopped: bool,
};

/// Checks the reference and the program of `shape`, each after `before`.
fn workAfter(
    gpa: std.mem.Allocator,
    library: *const loader.CheckedLibrary,
    program: Program,
    before: []const u8,
) !Observed {
    const reference_text = try std.mem.concat(gpa, u8, &.{ before, (try writeForm(gpa, program.shape, .reference)).text });
    const whole_text = try std.mem.concat(gpa, u8, &.{ before, program.text });
    const reference = try measure(gpa, library, reference_text, Work.cap);
    const whole = try measure(gpa, library, whole_text, Work.cap);
    return .{
        .reports = whole.reports,
        .work = .{ .reference = reference.took, .whole = whole.took },
        .stopped = reference.stopped or whole.stopped,
    };
}

/// How many unrelated declarations a check over its bound is measured again
/// after.
const confirming_fillers = 2000;

/// The least a difference falls by, measured again, for the first
/// measurement to have been an arena's node and not the program. No legal
/// shape's difference moves by a megabyte with declarations before it, and
/// the nodes of an arena that holds a check's types are tens of megabytes.
const node_step: usize = 8 << 20;

/// Checks `program` and its reference. Allocates from `gpa` and frees
/// nothing it returns.
///
/// The checker allocates from arenas. An arena that fills its node asks for
/// one half again as large as the last and the request together, and that
/// node is charged whole, so where the program fills a node and its
/// reference stops just short, their difference is the node. A check over
/// its bound is therefore measured once more after unrelated declarations,
/// which move where the nodes fill. It is within its bound only if the
/// difference then falls by `node_step` or more and is within the allowance
/// of the first measurement. A difference that stays, or falls by less, is
/// the program's, and the first measurement stands: the second can excuse a
/// node and cannot raise what a program is allowed.
pub fn observe(
    gpa: std.mem.Allocator,
    library: *const loader.CheckedLibrary,
    program: Program,
) !Observed {
    const first = try workAfter(gpa, library, program, "");
    if (first.stopped or !first.work.over()) return first;
    var filler: std.Io.Writer.Allocating = .init(gpa);
    try writeFiller(&filler.writer, confirming_fillers);
    const second = try workAfter(gpa, library, program, filler.written());
    if (second.stopped) return first;
    const excused = Work.excusesNode(first.work, second.work) orelse return first;
    return .{ .reports = first.reports, .work = excused, .stopped = false };
}

/// A defect a generated program shows in the compiler, recorded so the walk
/// stays green while the defect stands and fails when it stops reproducing.
///
/// A finding records everything the compiler says of the programs it covers.
/// A program that says anything else, one more report or one under another
/// rule, fails as a program with no finding does, and so does one whose
/// check is over its bound.
pub const Finding = struct {
    /// A seed whose program shows it.
    seed: u64,
    limit: Limit,
    positions: []const Position,
    /// The rule of each error the compiler reports of the program one past
    /// the limit, in order.
    reports: []const Code,
    /// What the language requires of the program.
    requires: []const u8,

    pub fn covering(self: Finding, shape: Shape) bool {
        if (shape != .limit) return false;
        const l = shape.limit;
        if (l.limit != self.limit or !l.past) return false;
        return std.mem.indexOfScalar(Position, self.positions, l.position) != null;
    }
};

pub const known_findings = [_]Finding{
    .{
        .seed = 65,
        .limit = .raw_literal_hashes,
        .positions = &.{.value},
        .reports = &.{ .s_string, .t_mismatch },
        .requires = "[S-String] is the only report of a raw literal opened with nine `#`: the binding it " ++
            "initialises and the function around it are not reported as a consequence",
    },
    .{
        .seed = 8,
        .limit = .interpolation_depth,
        .positions = &.{.value},
        .reports = &.{ .s_string, .s_string, .s_entry, .t_mismatch },
        .requires = "[S-String] reports a literal that opens a seventeenth interpolation once, and the rest " ++
            "of the file is read as it is without it",
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

fn describe(gpa: std.mem.Allocator, reports: anytype, work: ?Work) ![]const u8 {
    var out: std.Io.Writer.Allocating = .init(gpa);
    const w = &out.writer;
    if (reports.len == 0) try w.writeAll("accepted");
    for (reports, 0..) |report, i| {
        const code: ?Code = report;
        try w.print("{s}[{s}]", .{ if (i == 0) "refused: " else ", ", if (code) |c| c.ruleName() else "no rule" });
    }
    if (work) |measured| {
        try w.print("; {s} the bound on its work ({d} bytes, {d} for its reference, {d} allowed above it)", .{
            if (measured.over()) "over" else "within",
            measured.whole,
            measured.reference,
            measured.allowance(),
        });
    } else {
        try w.writeAll("; within the bound on its work");
    }
    return out.written();
}

/// What is wrong with what `observed` says of `program`, given the findings
/// recorded: null where the program is answered as it states and nothing is
/// recorded against it, or exactly as its finding records.
pub fn judge(gpa: std.mem.Allocator, program: Program, observed: Observed) !?Disagreement {
    const stated = try statedReports(gpa, program.expectation);
    const said = if (observed.stopped)
        try std.fmt.allocPrint(gpa, "stopped after {d} bytes of allocation work, before it answered", .{Work.cap})
    else
        try describe(gpa, observed.reports, observed.work);
    const within = !observed.stopped and !observed.work.over();
    const as_stated = within and sameReports(observed.reports, stated);

    const finding = findingOf(program.shape) orelse {
        if (as_stated) return null;
        return .{
            .what = "a hostile program is not answered as it states",
            .expected = try std.fmt.allocPrint(gpa, "{s}\n{s}", .{ try describe(gpa, stated, null), excerpt(program.text) }),
            .actual = said,
        };
    };
    if (as_stated) return .{
        .what = "a recorded finding no longer reproduces, so its entry in `known_findings` is removed",
        .expected = try std.fmt.allocPrint(gpa, "{s}\n{s}", .{ try describe(gpa, finding.reports, null), finding.requires }),
        .actual = said,
    };
    if (within and sameReports(observed.reports, finding.reports)) return null;
    return .{
        .what = "a program with a recorded finding is answered another way",
        .expected = try std.fmt.allocPrint(gpa, "{s}\n{s}", .{ try describe(gpa, finding.reports, null), finding.requires }),
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

/// Declarations with nothing to do with any shape, in the three kinds a file
/// mostly holds.
fn writeFiller(w: *std.Io.Writer, count: u32) !void {
    for (0..count) |i| {
        switch (i % 3) {
            0 => try w.print("fn _pad{d}(_x: UInt8) -> UInt8 {{\n    _x\n}}\n\n", .{i}),
            1 => try w.print("struct _PadS{d} {{\n    _f: UInt8,\n}}\n\n", .{i}),
            else => try w.print("alias _PadA{d} = UInt8\n\n", .{i}),
        }
    }
}

/// The shapes the filler test checks: each limit's accepted side in its
/// first and last position, and the doubling chain at both ends of its
/// depths in two positions, with and without its mistake.
fn fillerSample(gpa: std.mem.Allocator) ![]const Shape {
    var sample: std.ArrayList(Shape) = .empty;
    for (std.enums.values(Limit)) |limit| {
        var first: ?Shape.AtLimit = null;
        var last: ?Shape.AtLimit = null;
        for (cells) |cell| {
            if (cell.limit != limit or cell.past) continue;
            if (first == null) first = cell;
            last = cell;
        }
        if (first) |cell| try sample.append(gpa, .{ .limit = cell });
        if (last) |cell| {
            if (!std.meta.eql(first, last)) try sample.append(gpa, .{ .limit = cell });
        }
    }
    for ([_]u32{ shared_depths[0], shared_depths[shared_depths.len - 1] }) |depth| {
        try sample.append(gpa, .{ .shared = .{ .depth = depth, .position = .field } });
        try sample.append(gpa, .{ .shared = .{ .depth = depth, .position = .derive_argument } });
    }
    for (mistaken_depths) |depth| {
        try sample.append(gpa, .{ .shared = .{ .depth = depth, .position = .parameter, .mistaken = true } });
    }
    return sample.items;
}

test "slow: a legal shape stays within its bound whatever is declared before it" {
    try slow_tests.skipUnlessRun();
    // A table that grows as a file is read is charged its whole new size when
    // it grows, so the same shape costs a different amount after a different
    // number of declarations. A shape's two programs differ by a few tokens,
    // so both cross the same capacities and the difference stays what it is
    // with nothing before them.
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const sample = try fillerSample(arena.allocator());

    var per_program = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer per_program.deinit();
    var over: u32 = 0;
    for ([_]u32{ 0, 500, 1500, 4000, 8000 }) |fillers| {
        var filler: std.Io.Writer.Allocating = .init(arena.allocator());
        try writeFiller(&filler.writer, fillers);
        for (sample) |shape| {
            _ = per_program.reset(.retain_capacity);
            const scratch = per_program.allocator();
            var took: [2]usize = undefined;
            for ([_]Form{ .reference, .whole }, 0..) |form, i| {
                const text = try std.mem.concat(scratch, u8, &.{ filler.written(), (try writeForm(scratch, shape, form)).text });
                const measured = try measure(scratch, test_library.get(), text, Work.cap);
                try testing.expect(!measured.stopped);
                took[i] = measured.took;
            }
            const work: Work = .{ .reference = took[0], .whole = took[1] };
            if (work.over()) {
                over += 1;
                std.debug.print("after {d} filler declaration(s), {f}: {d} bytes, {d} for its reference\n", .{
                    fillers,
                    shape,
                    work.whole,
                    work.reference,
                });
            }
        }
    }
    try testing.expectEqual(@as(u32, 0), over);
}
