//! Where a case sits, and where its expectations sit.
//!
//! The conformance runner groups files into cases and opens a golden for each;
//! `linea fmt` has to leave alone the cases whose subject is their own byte
//! layout. Both are asking the same thing -- which case a file belongs to, and
//! therefore which stem its goldens share -- and answering it apart is how the
//! command came to reformat the input half of a case the runner exempts.
//!
//! A corpus case's goldens sit beside it. An example's sit in `tests/examples/`,
//! under the example's own name, so `examples/` holds only what a reader wants.
//!
//! Path surgery and nothing else, so the two callers that cannot see each
//! other can both see this.

const std = @import("std");
const testing = std.testing;

/// What a golden's stem has to name for anything to open the golden: a case
/// that is one file, or a case that is a directory. A command case is a
/// transcript that holds its own expected output, so nothing beside it is
/// opened.
///
/// Longest first, so `stemOf` takes the anchor that reaches furthest back:
/// `m/main.lin` is one case named `m`, not a case named `m/main` that happens
/// to live in a directory. Order says nothing to a caller that tries every
/// anchor.
pub const case_anchors = [_][]const u8{ "/main.lin", ".lin" };

/// The stem a file's case goes by, or null where the file anchors no case.
///
/// The inverse of `case_anchors`, which is what makes a golden found from a
/// case and a case found from a golden the same relation rather than two that
/// agree until a corpus is laid out the other way.
pub fn stemOf(path: []const u8) ?[]const u8 {
    for (case_anchors) |a| {
        if (std.mem.endsWith(u8, path, a)) return path[0 .. path.len - a.len];
    }
    return null;
}

test "a directory case is named by its directory" {
    // The whole of what the two callers disagreed about: `m/main.lin` is the
    // entry of a case named `m`, so its goldens sit at `m.fmt` rather than at
    // `m/main.fmt`, which nothing writes.
    try testing.expectEqualStrings("tests/m", stemOf("tests/m/main.lin").?);
    try testing.expectEqualStrings("tests/one", stemOf("tests/one.lin").?);
    try testing.expect(stemOf("tests/command.cmd") == null);
    try testing.expect(stemOf("tests/notes.md") == null);
}

/// The two trees a checkout holds cases in, each named by its top directory.
const tests_dir = "tests";
const examples_dir = "examples";

/// Where the examples' goldens sit, relative to the checkout: `examples/x.lin`
/// records its status at `tests/examples/x.exit`.
pub const examples_goldens = tests_dir ++ "/" ++ examples_dir;

/// A path split at the tree it lies in: the checkout holding that tree, and
/// the path from the tree's own name down, which is how a failure names it.
pub const Split = struct { checkout: []const u8, display: []const u8 };

/// Splits a path at the nearest ancestor named `tests` or `examples`. The
/// mirror `tests/examples` lies in `tests`: it holds goldens, not examples.
/// A path under neither is split at its own parent.
pub fn split(path: []const u8) Split {
    const trimmed = std.mem.trimEnd(u8, path, "/");
    var ancestor = trimmed;
    while (ancestor.len > 0) {
        const name = std.fs.path.basename(ancestor);
        const parent = std.fs.path.dirname(ancestor);
        const in_mirror = std.mem.eql(u8, name, examples_dir) and parent != null and
            std.mem.eql(u8, std.fs.path.basename(parent.?), tests_dir);
        if (!in_mirror and (std.mem.eql(u8, name, tests_dir) or std.mem.eql(u8, name, examples_dir))) {
            return .{
                .checkout = parent orelse ".",
                .display = trimmed[ancestor.len - name.len ..],
            };
        }
        ancestor = parent orelse break;
        if (std.mem.eql(u8, ancestor, "/")) break;
    }
    return .{
        .checkout = std.fs.path.dirname(trimmed) orelse ".",
        .display = std.fs.path.basename(trimmed),
    };
}

test "a path is split at the tree it lies in" {
    const cases = [_]struct { []const u8, []const u8, []const u8 }{
        .{ "tests/vec", ".", "tests/vec" },
        .{ "/checkout/tests/vec/", "/checkout", "tests/vec" },
        .{ "examples", ".", "examples" },
        .{ "/checkout/examples/demo", "/checkout", "examples/demo" },
        .{ "/checkout/tests/examples/demo.exit", "/checkout", "tests/examples/demo.exit" },
        .{ "tests/examples", ".", "tests/examples" },
        .{ "/elsewhere/cases", "/elsewhere", "cases" },
    };
    for (cases) |c| {
        const got = split(c[0]);
        try testing.expectEqualStrings(c[1], got.checkout);
        try testing.expectEqualStrings(c[2], got.display);
    }
}

/// Whether a path lies in the examples' goldens, which no walk of `tests`
/// treats as cases of its own.
pub fn inExamplesGoldens(path: []const u8) bool {
    const display = split(path).display;
    return std.mem.eql(u8, display, examples_goldens) or
        (std.mem.startsWith(u8, display, examples_goldens) and display[examples_goldens.len] == '/');
}

test "the examples' goldens are told apart from the corpus" {
    try testing.expect(inExamplesGoldens("/checkout/tests/examples"));
    try testing.expect(inExamplesGoldens("tests/examples/hello.exit"));
    try testing.expect(!inExamplesGoldens("tests/examples_of_rules/x.exit"));
    try testing.expect(!inExamplesGoldens("tests/vec/x.exit"));
    try testing.expect(!inExamplesGoldens("examples/hello.lin"));
}

/// Where the examples' goldens lie under a walked root, relative to it, or null
/// where the root does not hold them. A walk of `tests` finds them at
/// `examples`, and leaves them to the walk of the examples they belong to.
pub fn examplesGoldensWithin(root: []const u8) ?[]const u8 {
    const display = split(root).display;
    if (!std.mem.startsWith(u8, examples_goldens, display)) return null;
    if (examples_goldens.len == display.len or examples_goldens[display.len] != '/') return null;
    return examples_goldens[display.len + 1 ..];
}

test "a walk of tests finds the examples' goldens beneath it" {
    try testing.expectEqualStrings("examples", examplesGoldensWithin("/checkout/tests/").?);
    try testing.expectEqualStrings("examples", examplesGoldensWithin("tests").?);
    try testing.expect(examplesGoldensWithin("tests/vec") == null);
    try testing.expect(examplesGoldensWithin("tests/examples") == null);
    try testing.expect(examplesGoldensWithin("examples") == null);
    try testing.expect(examplesGoldensWithin("/elsewhere/cases") == null);
}

/// Where the goldens under `path` are read and written: the path itself, or,
/// for a path in `examples/`, the same name under `tests/examples/`.
///
/// The one mapping between an example and its expectations. A case's stem, a
/// walked root's goldens and `linea fmt`'s exemption all go through it, so the
/// runner that compares a golden and the check that finds it orphaned read
/// the same file. The caller owns the result.
pub fn goldenPath(gpa: std.mem.Allocator, path: []const u8) ![]const u8 {
    const at = split(path);
    const is_example = std.mem.eql(u8, at.display, examples_dir) or
        std.mem.startsWith(u8, at.display, examples_dir ++ "/");
    if (!is_example) return gpa.dupe(u8, std.mem.trimEnd(u8, path, "/"));
    if (std.mem.eql(u8, at.checkout, ".")) return std.fs.path.join(gpa, &.{ tests_dir, at.display });
    return std.fs.path.join(gpa, &.{ at.checkout, tests_dir, at.display });
}

test "an example's goldens sit under tests/examples, and a corpus case's beside it" {
    const gpa = testing.allocator;
    const cases = [_]struct { []const u8, []const u8 }{
        .{ "examples", "tests/examples" },
        .{ "examples/tcp_echo", "tests/examples/tcp_echo" },
        .{ "/checkout/examples/http-json-echo/", "/checkout/tests/examples/http-json-echo" },
        .{ "/checkout/tests/vec/push", "/checkout/tests/vec/push" },
        .{ "tests/examples/hello", "tests/examples/hello" },
    };
    for (cases) |c| {
        const got = try goldenPath(gpa, c[0]);
        defer gpa.free(got);
        try testing.expectEqualStrings(c[1], got);
    }
}

/// The stem the goldens of the case `path` anchors are opened under, or null
/// where the path anchors no case. The caller owns the result.
pub fn goldenStemOf(gpa: std.mem.Allocator, path: []const u8) !?[]const u8 {
    return try goldenPath(gpa, stemOf(path) orelse return null);
}

test "a case's goldens are named by its stem, wherever they sit" {
    const gpa = testing.allocator;
    const cases = [_]struct { []const u8, ?[]const u8 }{
        .{ "examples/hello.lin", "tests/examples/hello" },
        .{ "/checkout/examples/accounts/main.lin", "/checkout/tests/examples/accounts" },
        .{ "tests/m/main.lin", "tests/m" },
        .{ "tests/cmd/usage.cmd", null },
    };
    for (cases) |c| {
        const got = try goldenStemOf(gpa, c[0]);
        defer if (got) |g| gpa.free(g);
        if (c[1]) |want| try testing.expectEqualStrings(want, got.?) else try testing.expect(got == null);
    }
}
