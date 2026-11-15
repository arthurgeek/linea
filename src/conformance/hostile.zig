//! Programs built to sit where the compiler's cost or its limits are decided.
//!
//! `generate.zig` writes small programs that are well typed by construction,
//! and every one of them is far from any limit the language states and from
//! any shape whose cost depends on how a type is shared. This file writes the
//! other kind, and says of each program what the compiler must answer:
//!
//!   - a generic alias chain in which each alias names the one before it
//!     twice, so a type of `2^depth` names is `depth` declarations, used once.
//!     It must be accepted, or refused once where a mistake is planted in it,
//!     within the allocation work a program of its length is allowed;
//!   - for each limit in `support/limits.zig`, a written type at exactly the
//!     limit, which must be accepted, and one past it, which must be refused
//!     under the limit's rule and under nothing else.
//!
//! Each written type sits in one of the positions `Position` names. The
//! language states its limits about the type and not about where it is
//! written, so a type refused in a `let` is refused in an `impl` head too.

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

/// Where a program writes its type.
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

    pub fn describe(self: Position) []const u8 {
        return switch (self) {
            .let_annotation => "a `let` annotation",
            .parameter => "a function parameter",
            .field => "a struct field",
            .payload => "an enum payload",
            .implementation_argument => "the trait argument of an `impl`",
            .derive_argument => "a derive argument",
            .implementation_head => "the head of an `impl`",
        };
    }

    /// Whether the position is an argument of a written trait, which is one
    /// level of the written type that names the trait.
    fn isTraitArgument(self: Position) bool {
        return self == .implementation_argument or self == .derive_argument;
    }
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

    /// A written type at `limit`, or one past it, at `position`.
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
            .limit => |l| try writer.print("{s} {s} {s} in {s}", .{
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

/// Why no written type reaches `limit`, or null where one does.
///
/// A limit is listed here until a generator part writes a program at it. The
/// switch is exhaustive, so a limit added to the table is given a shape in
/// `writeLimit` or a reason here before this file compiles.
pub fn unwritten(limit: Limit) ?[]const u8 {
    return switch (limit) {
        .tree_height,
        .tuple_components,
        .callable_head_parameters,
        .answer_links,
        .array_length,
        .type_bytes,
        => null,
        .coverage_cells => "the cells are counted over a `match`'s arms, and a written type builds none",
    };
}

/// Whether a type at `limit` is written at `position`.
pub fn writes(limit: Limit, position: Position) bool {
    if (unwritten(limit) != null) return false;
    return switch (limit) {
        .tree_height, .tuple_components, .answer_links => true,
        // An implementation's head is a named type, a tuple or a callable.
        .array_length => position != .implementation_head,
        // The limit is on a callable type that heads an implementation, and
        // a callable type of any length is accepted everywhere else.
        .callable_head_parameters => position == .implementation_head,
        // An enum adds its tag to the widest payload, so a payload exactly at
        // the limit makes an enum past it.
        .type_bytes => switch (position) {
            .payload, .derive_argument, .implementation_head => false,
            else => true,
        },
        .coverage_cells => false,
    };
}

/// Every limit, on each side of it, in each position that writes it.
pub const cells: []const Shape.AtLimit = blk: {
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

/// The shallowest and the deepest doubling chain generated. A type of two
/// to the shallowest names, spelled out once, is already more allocation
/// work than the budget allows a program of that length, so a pass that
/// walks the names and not the declarations fails at every depth. The deepest
/// keeps the type's size under [L-Size].
pub const shallowest_shared: u32 = 20;
pub const deepest_shared: u32 = 24;

/// The shape a stream of choices selects.
pub fn shapeOf(bytes: []const u8) Shape {
    var c: Choices = .{ .bytes = bytes };
    if (c.odds(4)) {
        const depth = c.between(shallowest_shared, deepest_shared);
        if (c.odds(3)) {
            const given = [_]Position{ .let_annotation, .parameter };
            return .{ .shared = .{ .depth = depth, .position = given[c.below(given.len)], .mistaken = true } };
        }
        const positions = std.enums.values(Position);
        return .{ .shared = .{ .depth = depth, .position = positions[c.below(@intCast(positions.len))] } };
    }
    return .{ .limit = cells[c.below(@intCast(cells.len))] };
}

/// The program a seed selects, from the choices the seed fills.
pub fn fromSeed(gpa: std.mem.Allocator, seed: u64) !Program {
    const bytes = try choices_mod.fromSeed(gpa, seed, 16);
    defer gpa.free(bytes);
    return write(gpa, shapeOf(bytes));
}

test "a seed selects one program" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    var shared: u32 = 0;
    var at_limits: u32 = 0;
    for (0..64) |seed| {
        const one = try fromSeed(gpa, seed);
        const again = try fromSeed(gpa, seed);
        try testing.expectEqualStrings(one.text, again.text);
        switch (one.shape) {
            .shared => shared += 1,
            .limit => at_limits += 1,
        }
    }
    try testing.expect(shared > 0);
    try testing.expect(at_limits > 0);
}

/// One type as a position writes it.
const Written = struct {
    type: []const u8,
    /// What a variant holds for a derive naming `type` to find it.
    held: []const u8,
    /// Whether the rule reports once for the file or the type, however many
    /// places write it.
    once: bool,
    /// Whether `type` is an alias. An implementation is written for a type's
    /// own declaration, so its head holds an alias as an argument.
    alias: bool = false,
};

/// Writes the declarations a type counting `n` at `limit` needs, and returns
/// how `position` spells the type.
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
            return .{ .type = text.written(), .held = text.written(), .once = true };
        },
        .tuple_components => {
            try t.writeAll("(");
            for (0..n) |i| try t.writeAll(if (i == 0) "UInt8" else ", UInt8");
            try t.writeAll(")");
            return .{ .type = text.written(), .held = text.written(), .once = false };
        },
        .callable_head_parameters => {
            try t.writeAll("fn(");
            for (0..n) |i| try t.print("{s}_p{d}: UInt8", .{ if (i == 0) "" else ", ", i });
            try t.writeAll(") -> UInt8");
            return .{ .type = text.written(), .held = text.written(), .once = true };
        },
        .answer_links => {
            // Each alias is one link, the first included.
            try w.writeAll("alias _Link0 = UInt8\n");
            for (1..n) |i| try w.print("alias _Link{d} = _Link{d}\n", .{ i, i - 1 });
            try w.writeAll("\n");
            try t.print("_Link{d}", .{n - 1});
            return .{ .type = text.written(), .held = "UInt8", .once = true, .alias = true };
        },
        .array_length => {
            // The unit type has no bytes, so the length is the only limit
            // the array reaches.
            try t.print("[(); {d}]", .{n});
            return .{ .type = text.written(), .held = text.written(), .once = false };
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
            return .{ .type = text.written(), .held = text.written(), .once = true };
        },
        .coverage_cells => unreachable,
    }
}

/// Writes the declaration that holds `written` at `position` and the `main`
/// after it, and returns how many places wrote the type.
fn place(w: *std.Io.Writer, position: Position, written: Written, mistaken: bool) !u32 {
    var writings: u32 = 1;
    var body: []const u8 = "0";
    switch (position) {
        .let_annotation => {
            if (!mistaken) try w.writeAll("fn _any[T]() -> T {\n    _any()\n}\n\n");
            try w.print("fn main() -> UInt8 {{\n    let _held: {s} = {s}\n    0\n}}\n", .{
                written.type,
                if (mistaken) "3" else "_any()",
            });
            return writings;
        },
        .parameter => {
            try w.print("fn _take(_given: {s}) -> UInt8 {{\n    0\n}}\n\n", .{written.type});
            if (mistaken) body = "_take(3)";
        },
        .field => try w.print("struct _Holder {{\n    _part: {s},\n}}\n\n", .{written.type}),
        .payload => try w.print("enum _Choice {{\n    _Only({s}),\n}}\n\n", .{written.type}),
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
        , .{written.type}),
        .derive_argument => {
            try w.print("@derive(From[{s}])\nenum _Choice {{\n    _Only({s}),\n}}\n\n", .{ written.type, written.held });
            if (written.held.ptr == written.type.ptr) writings = 2;
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
            written.type,
            if (written.alias) "]" else "",
        }),
    }
    try w.print("fn main() -> UInt8 {{\n    {s}\n}}\n", .{body});
    return writings;
}

/// The program of `shape`, and what the compiler must say of it.
pub fn write(gpa: std.mem.Allocator, shape: Shape) !Program {
    var out: std.Io.Writer.Allocating = .init(gpa);
    const w = &out.writer;
    switch (shape) {
        .shared => |s| {
            try w.writeAll("struct _Pair[A, B] {\n    _left: A,\n    _right: B,\n}\n\n");
            try w.writeAll("alias _Twice0[T] = _Pair[T, T]\n");
            for (1..s.depth + 1) |i| {
                try w.print("alias _Twice{d}[T] = _Pair[_Twice{d}[T], _Twice{d}[T]]\n", .{ i, i - 1, i - 1 });
            }
            try w.writeAll("\n");
            const used = try std.fmt.allocPrint(gpa, "_Twice{d}[UInt8]", .{s.depth});
            _ = try place(w, s.position, .{ .type = used, .held = used, .once = true, .alias = true }, s.mistaken);
            return .{
                .shape = shape,
                .text = out.written(),
                .expectation = if (s.mistaken) .{ .refused = .{ .rule = .t_mismatch, .reports = 1 } } else .accepted,
            };
        },
        .limit => |l| {
            const n = l.limit.most() + @intFromBool(l.past);
            const written = try writeLimit(gpa, w, l.limit, n, l.position);
            const writings = try place(w, l.position, written, false);
            return .{
                .shape = shape,
                .text = out.written(),
                .expectation = if (l.past)
                    .{ .refused = .{ .rule = codeOf(l.limit), .reports = if (written.once) 1 else writings } }
                else
                    .accepted,
            };
        },
    }
}

/// The allocation work checking a program may take.
///
/// Counted as the sweep counts it, so it is the same number on every machine
/// and reads no clock. Linear in the program's text: twice what checking the
/// smallest program beside the library takes, and for each byte of source
/// many times what the widest program here takes. A pass whose work follows
/// the names a shared type spells out, and not the declarations that write
/// it, passes any bound of this form at the shallowest chain generated.
pub const Budget = struct {
    /// What checking `smallest` takes.
    empty: usize,

    const smallest = "fn main() -> UInt8 {\n    0\n}\n";
    const per_byte: usize = 16 << 10;

    pub fn measure(gpa: std.mem.Allocator, library: *const loader.CheckedLibrary) !Budget {
        var counting: Counting = .{ .under = gpa, .allow_growth = false };
        var arena = std.heap.ArenaAllocator.init(counting.allocator());
        defer arena.deinit();
        _ = try generate.checkLoadedText(arena.allocator(), "hostile.lin", smallest, library);
        return .{ .empty = counting.took };
    }

    pub fn of(self: Budget, length: usize) usize {
        return 2 * self.empty + per_byte * length;
    }
};

/// How a program's check disagreed with what the program states.
pub const How = enum {
    refused_an_accepted_program,
    accepted_a_refused_program,
    /// Refused, with no diagnostic under the rule the program names.
    refused_under_another_rule,
    /// Refused under the rule, with a different number of reports under it
    /// or with a report under another rule beside it.
    reported_otherwise,
    over_budget,

    pub fn describe(self: How) []const u8 {
        return switch (self) {
            .refused_an_accepted_program => "a program at the limit, or of a shared type, was refused",
            .accepted_a_refused_program => "a program the language refuses was accepted",
            .refused_under_another_rule => "a refused program was not refused under its rule",
            .reported_otherwise => "one mistake was not reported once, under its rule alone",
            .over_budget => "checking took more allocation work than a program of this length may",
        };
    }
};

pub const Outcome = union(enum) {
    held,
    broke: Broke,

    pub const Broke = struct {
        how: How,
        /// What the compiler said: its diagnostics, or the work it asked for.
        said: []const u8,
    };
};

/// Checks `program` beside the library, under its budget, against what it
/// states. Allocates from `gpa` and frees nothing it returns.
pub fn check(
    gpa: std.mem.Allocator,
    library: *const loader.CheckedLibrary,
    budget: Budget,
    program: Program,
) !Outcome {
    // Growth in place is refused, as the sweep's accounting refuses it: an
    // arena otherwise grows its last node by what each allocation needs, and
    // every growth is charged its full size.
    var counting: Counting = .{ .under = gpa, .allow_growth = false, .most = budget.of(program.text.len) };
    var arena = std.heap.ArenaAllocator.init(counting.allocator());
    defer arena.deinit();

    const over_budget: Outcome = .{ .broke = .{
        .how = .over_budget,
        .said = try std.fmt.allocPrint(gpa, "more than {d} bytes for {d} bytes of source", .{
            counting.most,
            program.text.len,
        }),
    } };
    const loaded = generate.checkLoadedText(arena.allocator(), "hostile.lin", program.text, library) catch |err| {
        if (err == error.OutOfMemory and counting.refused) return over_budget;
        return err;
    };
    // A refused allocation does not always end the check: a report whose
    // text could not be built is dropped, and what is left says nothing
    // about the program.
    if (counting.refused) return over_budget;

    var under_rule: u32 = 0;
    var errors: u32 = 0;
    for (loaded.sink.items()) |d| {
        if (d.severity != .err) continue;
        errors += 1;
        switch (program.expectation) {
            .accepted => {},
            .refused => |r| under_rule += @intFromBool(d.code == r.rule),
        }
    }

    const how: How = switch (program.expectation) {
        .accepted => if (errors == 0) return .held else .refused_an_accepted_program,
        .refused => |r| if (errors == 0)
            .accepted_a_refused_program
        else if (under_rule == 0)
            .refused_under_another_rule
        else if (under_rule != r.reports or errors != under_rule)
            .reported_otherwise
        else
            return .held,
    };

    var said: std.Io.Writer.Allocating = .init(gpa);
    try said.writer.print("{d} error(s), {d} under the rule\n", .{ errors, under_rule });
    for (loaded.sink.items(), 0..) |d, shown| {
        if (d.severity != .err) continue;
        if (shown == 6) break;
        const message = d.message[0..@min(d.message.len, 160)];
        try said.writer.print("error[{s}]: {s}\n", .{ if (d.code) |c| c.ruleName() else "-", message });
    }
    return .{ .broke = .{ .how = how, .said = said.written() } };
}

/// A defect a generated program shows in the compiler, recorded so the walk
/// stays green while the defect stands and fails when it stops reproducing.
pub const Finding = struct {
    /// A seed whose program shows it.
    seed: u64,
    how: How,
    covers: Covers,
    /// What the compiler does, and what the language says it should.
    shows: []const u8,

    pub const Covers = union(enum) {
        limit: struct { limit: Limit, past: bool, positions: []const Position },
        /// Every doubling chain with a planted mistake.
        mistaken_shared,
    };

    pub fn covering(self: Finding, shape: Shape) bool {
        switch (self.covers) {
            .limit => |c| {
                if (shape != .limit) return false;
                const l = shape.limit;
                if (l.limit != c.limit or l.past != c.past) return false;
                return std.mem.indexOfScalar(Position, c.positions, l.position) != null;
            },
            .mistaken_shared => return shape == .shared and shape.shared.mistaken,
        }
    }
};

pub const known_findings = [_]Finding{
    .{
        .seed = 3,
        .how = .accepted_a_refused_program,
        .covers = .{ .limit = .{
            .limit = .answer_links,
            .past = true,
            .positions = &.{ .implementation_argument, .derive_argument, .implementation_head },
        } },
        .shows = "a chain of 1001 aliases is refused under [T-AnswerDepth] in a `let`, a parameter, a field and a payload, " ++
            "and accepted as the trait argument of an `impl`, as a derive argument and inside the head of an `impl`",
    },
    .{
        .seed = 18,
        .how = .reported_otherwise,
        .covers = .{ .limit = .{
            .limit = .tree_height,
            .past = true,
            .positions = std.enums.values(Position),
        } },
        .shows = "a written type nested 1001 levels is reported under [S-Nesting] and then again as a consequence: " ++
            "[T-Bound] says the `Option` at the cut was given no argument, and a derive naming the type says under " ++
            "[T-Derive] that no variant wraps it. [S-Nesting] says nothing past the limit is reported again",
    },
    .{
        .seed = 302,
        .how = .reported_otherwise,
        .covers = .{ .limit = .{ .limit = .tuple_components, .past = true, .positions = &.{.derive_argument} } },
        .shows = "a tuple of nine components written as a derive argument is reported under [S-Tuple] twice, " ++
            "once at the tuple and once at the trait the derive names",
    },
    .{
        .seed = 4,
        .how = .reported_otherwise,
        .covers = .{ .limit = .{ .limit = .array_length, .past = true, .positions = &.{.derive_argument} } },
        .shows = "an array type one element too long written as a derive argument is reported under [T-ArraySize] " ++
            "twice, once at the length and once at the trait the derive names",
    },
    .{
        .seed = 11,
        .how = .over_budget,
        .covers = .mistaken_shared,
        .shows = "a `UInt8` given where a doubling alias chain's type is wanted is refused under [T-Mismatch] " ++
            "with allocation work that doubles with each alias: the message cuts the type's name short after " ++
            "the whole name has been built. Where that allocation is refused the report is dropped and the " ++
            "program reads as accepted",
    },
};

pub fn findingOf(shape: Shape) ?*const Finding {
    for (&known_findings) |*finding| {
        if (finding.covering(shape)) return finding;
    }
    return null;
}

/// What is wrong with how a program's check came out, given the findings
/// recorded: null where the program held and nothing is recorded against it,
/// or broke exactly as a finding records.
pub const Disagreement = struct {
    what: []const u8,
    expected: []const u8,
    actual: []const u8,
};

pub fn judge(gpa: std.mem.Allocator, budget: Budget, program: Program, outcome: Outcome) !?Disagreement {
    const finding = findingOf(program.shape);
    const stated: []const u8 = switch (program.expectation) {
        .accepted => try std.fmt.allocPrint(gpa, "accepted within {d} bytes of allocation work\n{s}", .{
            budget.of(program.text.len),
            excerpt(program.text),
        }),
        .refused => |r| try std.fmt.allocPrint(gpa, "{d} report(s), all under [{s}], within {d} bytes of allocation work\n{s}", .{
            r.reports,
            r.rule.ruleName(),
            budget.of(program.text.len),
            excerpt(program.text),
        }),
    };
    switch (outcome) {
        .held => {
            const known = finding orelse return null;
            return .{
                .what = "a recorded finding no longer reproduces, so its entry in `known_findings` is removed",
                .expected = try std.fmt.allocPrint(gpa, "{s}: {s}", .{ known.how.describe(), known.shows }),
                .actual = stated,
            };
        },
        .broke => |b| {
            if (finding) |known| {
                if (known.how == b.how) return null;
                return .{
                    .what = "a program with a recorded finding broke another way",
                    .expected = try std.fmt.allocPrint(gpa, "{s}: {s}", .{ known.how.describe(), known.shows }),
                    .actual = try std.fmt.allocPrint(gpa, "{s}\n{s}", .{ b.how.describe(), b.said }),
                };
            }
            return .{
                .what = b.how.describe(),
                .expected = stated,
                .actual = b.said,
            };
        },
    }
}

/// The end of a program, where its use of the type is written. The
/// declarations above it are a thousand lines of one pattern.
fn excerpt(text: []const u8) []const u8 {
    const most = 240;
    if (text.len <= most) return text;
    return text[text.len - most ..];
}

test "a finding's seed selects a program the finding covers" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    for (known_findings) |finding| {
        const program = try fromSeed(arena.allocator(), finding.seed);
        try testing.expect(finding.covering(program.shape));
    }
}

test "no shape is covered by two findings" {
    for (cells) |cell| {
        var covering: u32 = 0;
        for (known_findings) |finding| covering += @intFromBool(finding.covering(.{ .limit = cell }));
        try testing.expect(covering <= 1);
    }
}

/// Every shape the generator can select at the limits, and the doubling
/// chain at its two ends in every position.
fn everyShape(gpa: std.mem.Allocator) ![]const Shape {
    var all: std.ArrayList(Shape) = .empty;
    for (cells) |cell| try all.append(gpa, .{ .limit = cell });
    for (shallowest_shared..deepest_shared + 1) |at| {
        const depth: u32 = @intCast(at);
        for (std.enums.values(Position)) |position| {
            try all.append(gpa, .{ .shared = .{ .depth = depth, .position = position } });
        }
        for ([_]Position{ .let_annotation, .parameter }) |position| {
            try all.append(gpa, .{ .shared = .{ .depth = depth, .position = position, .mistaken = true } });
        }
    }
    return all.items;
}

test "slow: every hostile shape is answered as it states, or as a finding records" {
    try slow_tests.skipUnlessRun();
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    var per_program = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer per_program.deinit();

    const budget = try Budget.measure(gpa, test_library.get());
    var disagreed: u32 = 0;
    for (try everyShape(gpa)) |shape| {
        _ = per_program.reset(.retain_capacity);
        const scratch = per_program.allocator();
        const program = try write(scratch, shape);
        const outcome = try check(scratch, test_library.get(), budget, program);
        if (try judge(scratch, budget, program, outcome)) |d| {
            disagreed += 1;
            std.debug.print("\n{f}: {s}\n--- expected\n{s}\n--- actual\n{s}\n", .{ shape, d.what, d.expected, d.actual });
        }
    }
    try testing.expectEqual(@as(u32, 0), disagreed);
}
