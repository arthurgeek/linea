//! Deterministic mangling of a program's whitespace, for checking that
//! formatting is a normal form.
//!
//! What may be mangled is exactly what the formatter does not preserve:
//! indentation, and the spacing between tokens on a line. Everything else it
//! keeps deliberately -- the trailing comma that decides a list's layout, the
//! line a comment sits on, whether a blank line separates two statements -- and
//! changing any of those would change the formatting legitimately, so the
//! equality would fail on a formatter that was working.
//!
//! A run of two or more blank lines is the one exception, and only because the
//! formatter collapses every such run to one: making it longer cannot change
//! what comes out.
//!
//! Deterministic, not random. A random rewrite would find more and would also
//! fail on a different case each run, which is how a suite stops being
//! believed.

const std = @import("std");
const testing = std.testing;

const Source = @import("../support/source.zig").Source;
const Sink = @import("../diagnostics/sink.zig").Sink;
const Interner = @import("../support/interner.zig").Interner;
const token = @import("../lexer/token.zig");
const tokenize = @import("../lexer/lexer.zig").tokenize;
const parse = @import("../parser/parser.zig").parse;
const fmt = @import("../fmt/fmt.zig");

/// The source with its whitespace driven as far from formatted as the grammar
/// allows, or null where there is nothing it could change.
pub fn perturb(
    gpa: std.mem.Allocator,
    text: []const u8,
) !?[]const u8 {
    const source: Source = .{ .path = "perturb.lin", .text = text };
    var sink = Sink.init(gpa);
    var interner: Interner = .empty;
    const tokens = tokenize(gpa, &source, .from(0), &sink, &interner) catch return null;
    if (sink.hasErrors()) return null;

    const tags = tokens.slice().items(.tag);
    const spans = tokens.slice().items(.span);
    if (tags.len < 2) return null;

    // Where a region ends is the formatter's rule, and this has to route around
    // exactly what the formatter copies. Asking it needs a tree, which is why
    // the text is parsed here rather than only tokenized.
    var ast = parse(gpa, &source, .from(0), tokens, &sink) catch return null;
    if (sink.hasErrors()) return null;

    // Built once: a marker asks how far its region reaches, and answering that
    // by reading the tree per marker is what made it cost the file per marker.
    var extents = fmt.Extents.build(gpa, &ast) catch return null;
    defer extents.deinit(gpa);

    var out: std.Io.Writer.Allocating = .init(gpa);
    var prev_end: u32 = 0;
    var verbatim_until: u32 = 0;

    for (tags, spans, 0..) |tag, span, i| {
        if (tag == .eof) break;

        // Text the formatter copies unchanged must be handed to it unchanged,
        // or the mangling survives into the output it is being compared with.
        if (span.start < verbatim_until) {
            try out.writer.writeAll(text[prev_end..span.end]);
            prev_end = span.end;
            continue;
        }
        if (tag == .comment and fmt.markerAt(text, span) == .off) {
            verbatim_until = fmt.regionEnd(&ast, &extents, token.TokenId.at(@intCast(i)));
            try out.writer.writeAll(text[prev_end..span.end]);
            prev_end = span.end;
            continue;
        }

        const newlines = std.mem.count(u8, text[prev_end..span.start], "\n");
        if (newlines == 0) {
            // Never nothing: two tokens written adjacently must stay two
            // tokens, and space is the only separator that cannot merge them.
            try out.writer.writeAll("   ");
        } else {
            // The line structure is kept exactly, save that a run the formatter
            // will collapse anyway is made longer.
            try out.writer.splatByteAll('\n', if (newlines > 1) newlines + 2 else 1);
            try out.writer.splatByteAll(' ', 7);
        }
        try out.writer.writeAll(span.slice(text));
        prev_end = span.end;
    }
    // Whether a file ends in a newline is the author's. Inventing one would
    // show up in a file the formatter copies verbatim, and the comparison would
    // then fail on a formatter that was right.
    if (std.mem.endsWith(u8, text, "\n")) try out.writer.writeAll("\n");
    return out.written();
}

/// Formats text, or null where it does not parse cleanly.
fn format(gpa: std.mem.Allocator, text: []const u8) !?[]const u8 {
    const source: Source = .{ .path = "perturb.lin", .text = text };
    var sink = Sink.init(gpa);
    var interner: Interner = .empty;
    const tokens = try tokenize(gpa, &source, .from(0), &sink, &interner);
    var ast = try parse(gpa, &source, .from(0), tokens, &sink);
    if (sink.hasErrors()) return null;
    return try fmt.formatAlloc(gpa, &ast);
}

/// The source, mangled and then formatted. Null where it does not parse, or
/// where there was nothing to mangle.
pub fn perturbAndFormat(
    gpa: std.mem.Allocator,
    text: []const u8,
) !?[]const u8 {
    const ugly = (try perturb(gpa, text)) orelse return null;
    return format(gpa, ugly);
}

/// Formatting is a normal form: two sources differing only in what the
/// formatter does not preserve format to the same bytes.
///
/// Strictly stronger than idempotence. Idempotence says formatting settles;
/// this says it settles in the same place however the input was spaced, and a
/// formatter can be perfectly idempotent while still leaking its input's
/// spacing into its output.
/// Returns whether the property was actually asked, so a run can tell a
/// property that agreed from one that stopped applying. Answering "yes" from a
/// path that compares nothing is how a check comes to be counted and unable to
/// fail.
pub fn checkNormalForm(
    gpa: std.mem.Allocator,
    text: []const u8,
    formatted: []const u8,
) !bool {
    // Nothing to mangle leaves only one spelling, so there is no normal-form
    // comparison to make. The supplied canonical text already proves the
    // original parses and formats cleanly.
    const ugly = (try perturb(gpa, text)) orelse return false;
    try compareNormalForm(gpa, formatted, ugly);
    return true;
}

/// The property proper, with canonical and mangled spellings supplied.
///
/// Split out so a test can hand it a mangling of its own. The thing this must
/// be able to fail for is the mangler being wrong, and a mangler that is wrong
/// is not going to report itself.
fn compareNormalForm(gpa: std.mem.Allocator, formatted: []const u8, ugly: []const u8) !void {
    // The mangling touches only whitespace the formatter ignores, so text it
    // produces that does not parse is the mangler being wrong. Reading that as
    // "nothing to compare" is what left this property unable to fail for its
    // own fault -- and every corpus file went quiet rather than red.
    const roundabout = (try format(gpa, ugly)) orelse return error.PerturbationDidNotParse;
    // Compared without `expectEqualStrings`, which prints a diff before it
    // returns. The runner reports the error's name and its own expected/actual
    // pair, so the print adds nothing there -- and a test asserting the
    // comparison fails would emit what reads as a failure in a passing run.
    if (!std.mem.eql(u8, formatted, roundabout)) return error.NotANormalForm;
}

test "a mangling that does not parse is a failure, not a pass" {
    // The perturbation only ever touches whitespace the formatter ignores, so
    // it cannot legitimately produce something unparseable. Treating that as
    // "nothing to compare" is what made this property unable to fail for the
    // one fault it exists to catch: the mangler itself being wrong.
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const text = "fn main() -> UInt8 {\n    0\n}\n";
    try testing.expectError(
        error.PerturbationDidNotParse,
        compareNormalForm(gpa, text, "( this does not parse"),
    );
}

test "a mangling that parses is compared, not skipped" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const text = "fn main() -> UInt8 {\n    0\n}\n";
    try compareNormalForm(gpa, text, "fn main()->UInt8{0}");

    // Asserted without `expectEqualStrings`, which prints its diff before
    // returning the error -- so a passing run would emit what reads as a
    // failure, in the tail of the output where real failures live.
    try testing.expectError(
        error.NotANormalForm,
        compareNormalForm(gpa, text, "fn main() -> UInt8 {\n    1\n}\n"),
    );
}

fn expectNormalForm(text: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const ugly = (try perturb(gpa, text)).?;
    // A rewrite that changed nothing would make the property vacuous, and the
    // whole reason it perturbs first is that it must always have work to do.
    try testing.expect(!std.mem.eql(u8, text, ugly));
    const formatted = switch (try fmt.checkProperties(gpa, text)) {
        .not_applicable => return error.ExpectedCheckedFormatting,
        .checked => |checked| checked.formatted,
    };
    _ = try checkNormalForm(gpa, text, formatted);
}

test "formatting is a normal form over indentation and spacing" {
    try expectNormalForm(
        \\fn main() -> UInt8 {
        \\    let x = 1;
        \\    let y = 2;
        \\    x + y
        \\}
        \\
    );
}

test "a blank line the author left survives being made longer" {
    try expectNormalForm(
        \\fn main() -> UInt8 {
        \\    let x = 1;
        \\
        \\    let y = 2;
        \\    x + y
        \\}
        \\
    );
}

test "a comment keeps the line it was written on" {
    try expectNormalForm(
        \\// above
        \\fn main() -> UInt8 {
        \\    let x = 1; // trailing
        \\    x
        \\}
        \\
    );
}

test "a trailing comma still decides the layout after mangling" {
    try expectNormalForm(
        \\enum Flat { A, B }
        \\
        \\enum Broken {
        \\    A,
        \\    B,
        \\}
        \\
        \\fn main() -> UInt8 { 1 }
        \\
    );
}

test "lambda pipes and invocation modes survive whitespace mangling" {
    try expectNormalForm(
        \\fn main() -> UInt8 {
        \\    let empty = || 1
        \\    let reader = read [] |value: UInt8| { value }
        \\    empty() + reader(2)
        \\}
        \\
    );
}

test "an off region is handed to the formatter unchanged" {
    try expectNormalForm(
        \\fn main() -> UInt8 {
        \\    // linea fmt: off
        \\    let   x   =   1;
        \\    // linea fmt: on
        \\    x
        \\}
        \\
    );
}

test "a program of every construct survives" {
    try expectNormalForm(
        \\enum Step { Half, Whole, Exactly(UInt8) }
        \\
        \\struct Plan {
        \\    remaining: UInt8,
        \\    step: Step,
        \\}
        \\
        \\fn amount(s: Step) -> UInt8 {
        \\    match read s {
        \\        Half => 5,
        \\        Whole => { let a: UInt8 = 10; a },
        \\        Exactly(n) => n,
        \\    }
        \\}
        \\
        \\fn main() -> UInt8 {
        \\    let plan: Plan = .{ remaining = 3, step = .Half };
        \\    let Plan { remaining, step } = plan;
        \\    amount(step) + remaining
        \\}
        \\
    );
}
