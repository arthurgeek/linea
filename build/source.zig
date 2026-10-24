//! What the project's own text says about itself.
//!
//! Every gate in `build.zig` is a string heuristic over a file this repository
//! keeps: which Zig file imports which, which declaration a file keeps to
//! itself, which names a `comptime` block holds, what a decision index states
//! about a record. None of it is about the build graph, and all of it decides
//! whether a build fails -- so it sits in a module `build/source_test.zig` can
//! run, rather than in a script whose own `test` blocks nothing executes.
//!
//! Text and not trees. A name reached by anything but being written is missed,
//! which is the limit every gate reading this shares: it holds today and fails
//! the moment something stops being named.

const std = @import("std");

/// One file of a source tree, read once.
pub const SourceFile = struct {
    path: []const u8,
    text: []const u8,
};

/// Every `.zig` file beneath `sub_path`, with its text, ordered by path.
///
/// One walk, because the questions asked of the result are about the same
/// corpus and reading it several times would be several chances for them to
/// disagree about what the compiler is.
///
/// `iterate` is what makes the walk legal: a directory opened without it can
/// still be iterated on some hosts and not on others.
pub fn compilerSource(
    gpa: std.mem.Allocator,
    io: std.Io,
    root: std.Io.Dir,
    sub_path: []const u8,
) []const SourceFile {
    var dir = root.openDir(io, sub_path, .{ .iterate = true }) catch
        @panic("the compiler's source is missing");
    defer dir.close(io);

    var walker = dir.walk(gpa) catch @panic("OOM");
    defer walker.deinit();

    var found: std.ArrayList(SourceFile) = .empty;
    while (walker.next(io) catch @panic("walking the compiler failed")) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.basename, ".zig")) continue;

        const text = dir.readFileAlloc(io, entry.path, gpa, .limited(1 << 22)) catch continue;
        const path = gpa.dupe(u8, entry.path) catch @panic("OOM");
        found.append(gpa, .{ .path = path, .text = text }) catch @panic("OOM");
    }
    std.mem.sort(SourceFile, found.items, {}, lessThanPath);
    return found.items;
}

fn lessThanPath(_: void, a: SourceFile, b: SourceFile) bool {
    return std.mem.lessThan(u8, a.path, b.path);
}

/// Whether the byte can be part of a Zig identifier, which is what makes a
/// count of a name a count of that name rather than of every name holding it.
fn partOfAName(c: u8) bool {
    return std.ascii.isAlphanumeric(c) or c == '_';
}

/// How many times each name appears in a text as a whole word, from one pass
/// over it. A gate asking about many names in one file reads this rather than
/// scanning the file again for each.
pub fn wordCounts(gpa: std.mem.Allocator, text: []const u8) std.StringHashMapUnmanaged(u32) {
    var counts: std.StringHashMapUnmanaged(u32) = .empty;
    var at: usize = 0;
    while (at < text.len) {
        if (!partOfAName(text[at])) {
            at += 1;
            continue;
        }
        const start = at;
        while (at < text.len and partOfAName(text[at])) at += 1;
        const entry = counts.getOrPut(gpa, text[start..at]) catch @panic("out of memory");
        entry.value_ptr.* = if (entry.found_existing) entry.value_ptr.* + 1 else 1;
    }
    return counts;
}

/// Every quoted string in `text`, in the order they are written.
///
/// A gate reading names a table spells has to read the table rather than one
/// spelling of it: a row is a struct literal whose fields may be reordered or
/// added to, so what stays true is that the names in it are the quoted strings
/// and nothing else is.
///
/// An escape is not understood, because a name that needs one is not a name any
/// of these tables holds -- an identifier the compiler looks up cannot contain a
/// quote or a backslash.
pub fn quotedIn(gpa: std.mem.Allocator, text: []const u8) []const []const u8 {
    var found: std.ArrayList([]const u8) = .empty;
    var at: usize = 0;
    while (std.mem.indexOfScalarPos(u8, text, at, '"')) |opened| {
        const closed = std.mem.indexOfScalarPos(u8, text, opened + 1, '"') orelse break;
        found.append(gpa, text[opened + 1 .. closed]) catch @panic("out of memory");
        at = closed + 1;
    }
    return found.toOwnedSlice(gpa) catch @panic("out of memory");
}

/// The first quoted string on the line holding `at`, or null where that line
/// holds none.
///
/// The line and not the rest of the file, because the question is what one call
/// was given. A call handed a variable has no name to read, and a scan running
/// past the end of its line would answer with a literal belonging to some later
/// call -- which is a wrong name rather than no name, and reads as a gate
/// working.
pub fn quotedOnLine(text: []const u8, at: usize) ?[]const u8 {
    const from = if (std.mem.lastIndexOfScalar(u8, text[0..at], '\n')) |nl| nl + 1 else 0;
    const to = std.mem.indexOfScalarPos(u8, text, at, '\n') orelse text.len;
    const line = text[from..to];

    const opened = std.mem.indexOfScalarPos(u8, line, at - from, '"') orelse return null;
    const closed = std.mem.indexOfScalarPos(u8, line, opened + 1, '"') orelse return null;
    return line[opened + 1 .. closed];
}

/// The names in the first column of the Markdown table that follows `marker`.
///
/// A row's first cell is read as one backticked name, which is how the
/// semantics document writes a name in a table. The header row and the
/// separator hold no backticked cell and are skipped, and the table ends at
/// the first line that is not a row. A marker nothing follows, or one with no
/// table after it, holds no names.
pub fn tableNamesAfter(gpa: std.mem.Allocator, text: []const u8, marker: []const u8) []const []const u8 {
    var found: std.ArrayList([]const u8) = .empty;
    const at = std.mem.indexOf(u8, text, marker) orelse return found.toOwnedSlice(gpa) catch @panic("out of memory");
    var lines = std.mem.splitScalar(u8, text[at + marker.len ..], '\n');
    var in_table = false;
    while (lines.next()) |raw| {
        const line = std.mem.trim(u8, raw, " \r");
        if (!std.mem.startsWith(u8, line, "|")) {
            if (in_table) break;
            continue;
        }
        in_table = true;
        const cell_end = std.mem.indexOfScalarPos(u8, line, 1, '|') orelse continue;
        const cell = std.mem.trim(u8, line[1..cell_end], " ");
        if (cell.len < 3 or cell[0] != '`' or cell[cell.len - 1] != '`') continue;
        found.append(gpa, cell[1 .. cell.len - 1]) catch @panic("out of memory");
    }
    return found.toOwnedSlice(gpa) catch @panic("out of memory");
}

/// The name a line declares privately, or null where it declares none.
///
/// Column zero and no `pub`, so this is a declaration the file keeps to itself
/// -- which is the only kind whose uses are all in that file, and so the only
/// kind one file can answer for.
pub fn privateDeclaration(line: []const u8) ?[]const u8 {
    for ([_][]const u8{ "fn ", "const " }) |kw| {
        if (!std.mem.startsWith(u8, line, kw)) continue;
        const rest = line[kw.len..];
        var end: usize = 0;
        while (end < rest.len and partOfAName(rest[end])) end += 1;
        if (end == 0) continue;
        return rest[0..end];
    }
    return null;
}

/// Every file of the tree an importer names with `@import`, as paths relative
/// to the tree's root, from one pass over its text. A gate asking which files
/// anything imports collects these once per file rather than asking every file
/// about every other.
pub fn importedPaths(gpa: std.mem.Allocator, importer: SourceFile) []const []const u8 {
    const dir = std.fs.path.dirname(importer.path) orelse "";
    var found: std.ArrayList([]const u8) = .empty;
    var at: usize = 0;
    while (std.mem.indexOfPos(u8, importer.text, at, "@import(\"")) |start| {
        const from = start + "@import(\"".len;
        const to = std.mem.indexOfScalarPos(u8, importer.text, from, '"') orelse break;
        at = to + 1;
        const named = importer.text[from..to];
        // A module rather than a file: `std`, and the assets a build hands
        // over by name. Those name nothing under the tree being read.
        if (!std.mem.endsWith(u8, named, ".zig")) continue;
        // `resolve` gives an absolute path; the tree is stored relative to
        // its root, so the leading separator comes off.
        const joined = std.fs.path.resolve(gpa, &.{ "/", dir, named }) catch continue;
        defer gpa.free(joined);
        found.append(gpa, gpa.dupe(u8, joined[1..]) catch @panic("out of memory")) catch @panic("out of memory");
    }
    return found.toOwnedSlice(gpa) catch @panic("out of memory");
}

/// Whether `importer` reaches `wanted` by an `@import`, resolved.
///
/// An import is written relative to the file holding it, so `sema/types.zig`
/// saying `@import("../syntax/node.zig")` and `mir/lower.zig` saying
/// `@import("mir.zig")` both name one file each, and neither string is the
/// path either file is stored under. Resolving is what makes the comparison
/// about files rather than about spellings.
pub fn importsPath(gpa: std.mem.Allocator, importer: SourceFile, wanted: []const u8) bool {
    const paths = importedPaths(gpa, importer);
    defer {
        for (paths) |path| gpa.free(path);
        gpa.free(paths);
    }
    for (paths) |path| {
        if (std.mem.eql(u8, path, wanted)) return true;
    }
    return false;
}

/// Whether a test root's first `comptime` block imports exactly the manifest
/// files named for it and no other file from the same tree.
///
/// Ordinary imports are ignored: a test block is compiled because the root
/// names its file at comptime, not because production code happens to reach it.
/// Costs one scan of the root per manifest and per file in the tree.
pub fn importsExactly(
    gpa: std.mem.Allocator,
    root: SourceFile,
    wanted: []const []const u8,
    among: []const SourceFile,
) bool {
    const manifest: SourceFile = .{ .path = root.path, .text = comptimeBlock(root.text) };

    for (wanted) |path| {
        if (!importsPath(gpa, manifest, path)) return false;
    }

    for (among) |file| {
        if (std.mem.eql(u8, file.path, root.path)) continue;
        if (!importsPath(gpa, manifest, file.path)) continue;
        for (wanted) |path| {
            if (std.mem.eql(u8, file.path, path)) break;
        } else return false;
    }
    return true;
}

/// The body of a file's first `comptime` block.
///
/// Read apart from the rest of the file because a plain `@import` at the top
/// of a root is a reference for that root's own code, and a test build never
/// analyses `main`. Naming a file inside the block is what pulls it in; naming
/// it outside says nothing.
pub fn comptimeBlock(text: []const u8) []const u8 {
    const opened = std.mem.indexOf(u8, text, "\ncomptime {\n") orelse return "";
    const body = text[opened + "\ncomptime {\n".len ..];
    const closed = std.mem.indexOf(u8, body, "\n}\n") orelse return body;
    return body[0..closed];
}

/// The containers in a Zig file that hold `test` blocks and that no
/// file-level `comptime` block names, each written as the path a reference to
/// it takes: `Outer` or `Outer.Inner`.
///
/// A test inside a struct is compiled only once something makes the compiler
/// look inside that struct. A test build analyses what its tests use, and a
/// filtered build uses only the tests it kept, so a struct's own tests were
/// compiled only when an unrelated kept test happened to reach the struct: a
/// run filtered to one of them reported nothing and passed. A file-level
/// `comptime { _ = Outer; }` makes the compiler look inside regardless, which
/// is what this holds every such container to.
///
/// Read from the parsed file rather than its text, because a Zig test quotes
/// Linea source whose braces a line-based reading would take for Zig's. A
/// container a function builds, or one written inside a function body, has no
/// name a `comptime` block could write, so a test inside one is always
/// reported, as `a container no name reaches, line N`.
pub fn unreachedNestedTests(gpa: std.mem.Allocator, text: []const u8) []const []const u8 {
    const z = gpa.dupeZ(u8, text) catch @panic("OOM");
    var tree = std.zig.Ast.parse(gpa, z, .zig) catch @panic("OOM");
    defer tree.deinit(gpa);

    var named: std.ArrayList(u8) = .empty;
    for (tree.rootDecls()) |decl| {
        if (tree.nodeTag(decl) != .@"comptime") continue;
        const first = tree.firstToken(decl);
        const last = tree.lastToken(decl);
        const start = tree.tokenStart(first);
        const end = tree.tokenStart(last) + tree.tokenSlice(last).len;
        named.appendSlice(gpa, z[start..end]) catch @panic("OOM");
        named.append(gpa, '\n') catch @panic("OOM");
    }

    var unreached: std.ArrayList([]const u8) = .empty;
    var visited: std.AutoHashMapUnmanaged(std.zig.Ast.Node.Index, void) = .empty;
    visitContainer(gpa, &tree, tree.rootDecls(), "", named.items, &unreached, &visited);

    // Every test the walk above did not meet sits in a container no path of
    // names reaches.
    for (tree.nodes.items(.tag), 0..) |tag, i| {
        if (tag != .test_decl) continue;
        const at: std.zig.Ast.Node.Index = @enumFromInt(i);
        if (visited.contains(at)) continue;
        const line = tree.tokenLocation(0, tree.nodeMainToken(at)).line + 1;
        unreached.append(gpa, std.fmt.allocPrint(gpa, "a container no name reaches, line {d}", .{line}) catch @panic("OOM")) catch @panic("OOM");
    }
    return unreached.toOwnedSlice(gpa) catch @panic("OOM");
}

fn visitContainer(
    gpa: std.mem.Allocator,
    tree: *const std.zig.Ast,
    members: []const std.zig.Ast.Node.Index,
    path: []const u8,
    named: []const u8,
    unreached: *std.ArrayList([]const u8),
    visited: *std.AutoHashMapUnmanaged(std.zig.Ast.Node.Index, void),
) void {
    var holds_a_test = false;
    for (members) |member| {
        if (tree.nodeTag(member) == .test_decl) {
            holds_a_test = true;
            visited.put(gpa, member, {}) catch @panic("OOM");
            continue;
        }
        const variable = tree.fullVarDecl(member) orelse continue;
        const init = variable.ast.init_node.unwrap() orelse continue;
        var buffer: [2]std.zig.Ast.Node.Index = undefined;
        const container = tree.fullContainerDecl(&buffer, init) orelse continue;
        const name = tree.tokenSlice(variable.ast.mut_token + 1);
        const inner = if (path.len == 0)
            gpa.dupe(u8, name) catch @panic("OOM")
        else
            std.fmt.allocPrint(gpa, "{s}.{s}", .{ path, name }) catch @panic("OOM");
        visitContainer(gpa, tree, container.ast.members, inner, named, unreached, visited);
    }
    if (!holds_a_test or path.len == 0) return;
    const reference = std.fmt.allocPrint(gpa, "_ = {s};", .{path}) catch @panic("OOM");
    if (std.mem.indexOf(u8, named, reference) != null) return;
    unreached.append(gpa, path) catch @panic("OOM");
}

/// The text between `start` and the first `end` after it, or null where the
/// opening delimiter is not there.
///
/// The one shape every gate reading a value out of a file someone else's tool
/// owns has in common -- a sanitizer matrix in the CI workflow, a library name
/// in the toolchain, an indent width in the formatter and in the editor config.
/// Written once, so a fix to how a value is found is a fix to all of them.
///
/// Both delimiters are text, not one string and one character. Every value read
/// today is closed by a single byte, but nothing about the shape is: a comment
/// closed by `*/` and a fence closed by ``` are the same question, and a second
/// helper for them would be the same rule with two implementations.
///
/// Where nothing closes it the answer is empty rather than the rest of the
/// file: a value running off the end means the file is malformed, and half a
/// document read as a value is worse than no value at all.
pub fn between(text: []const u8, start: []const u8, end: []const u8) ?[]const u8 {
    const at = std.mem.indexOf(u8, text, start) orelse return null;
    const from = at + start.len;
    const to = std.mem.indexOfPos(u8, text, from, end) orelse from;
    return text[from..to];
}

/// The lines standing indented under the one holding `at`.
///
/// What a block is, read from the shape a formatted file already has rather
/// than by matching braces: a format string holds `{d}` and `{{`, so counting
/// braces over text means counting the ones inside string literals too, and a
/// counter that has to know what a literal is has stopped being a heuristic
/// over lines. Indentation is what `zig fmt` guarantees and what a reader uses.
///
/// A blank line belongs to the block it sits inside; the block ends at the
/// first line written no further in than the one that opened it.
pub fn indentedUnder(text: []const u8, at: usize) []const u8 {
    const opened = if (std.mem.lastIndexOfScalar(u8, text[0..at], '\n')) |nl| nl + 1 else 0;
    var outer: usize = 0;
    while (opened + outer < text.len and text[opened + outer] == ' ') outer += 1;

    const ends = std.mem.indexOfScalarPos(u8, text, at, '\n') orelse return "";
    const from = ends + 1;

    var i = from;
    while (i < text.len) {
        const stop = std.mem.indexOfScalarPos(u8, text, i, '\n') orelse text.len;
        const line = text[i..stop];
        var indent: usize = 0;
        while (indent < line.len and line[indent] == ' ') indent += 1;
        if (indent < line.len and indent <= outer) return text[from..i];
        i = if (stop == text.len) stop else stop + 1;
    }
    return text[from..];
}

/// The members an enum declares, and which of them no call counts.
pub const Accounting = struct {
    /// How many members the enum declares. None means the enum is not there
    /// under that name, which is a gate reading a file it no longer
    /// understands rather than a file with nothing wrong with it.
    declared: usize,
    /// The members no call to the counting function names.
    uncounted: []const []const u8,
};

/// Which members of `enum_name` no call to `counted_by` names.
///
/// One pass over the text per member, over the enum's own lines to find them
/// and over the calls to find what each is given.
pub fn accountingOf(
    gpa: std.mem.Allocator,
    text: []const u8,
    enum_name: []const u8,
    counted_by: []const u8,
) Accounting {
    const members = enumMembers(gpa, text, enum_name);
    var uncounted: std.ArrayList([]const u8) = .empty;
    for (members) |member| {
        if (passedTo(text, counted_by, member)) continue;
        uncounted.append(gpa, member) catch @panic("OOM");
    }
    return .{ .declared = members.len, .uncounted = uncounted.items };
}

/// The names an enum lists, in the order it lists them.
///
/// A member is a line at one indent holding a name and a comma. A doc comment,
/// a method and a switch prong inside a method are each written differently, so
/// this counts what the enum offers rather than what is written between the
/// members -- and a member spelled some other way is missed, which is the limit
/// every gate reading text has.
fn enumMembers(gpa: std.mem.Allocator, text: []const u8, name: []const u8) []const []const u8 {
    const header = std.fmt.allocPrint(gpa, "const {s} = enum {{\n", .{name}) catch @panic("OOM");
    defer gpa.free(header);

    const opened = std.mem.indexOf(u8, text, header) orelse return &.{};
    const body = text[opened + header.len ..];
    const closed = std.mem.indexOf(u8, body, "\n};") orelse body.len;

    var found: std.ArrayList([]const u8) = .empty;
    var lines = std.mem.splitScalar(u8, body[0..closed], '\n');
    while (lines.next()) |line| {
        if (!std.mem.startsWith(u8, line, "    ")) continue;
        const rest = line["    ".len..];
        if (!std.mem.endsWith(u8, rest, ",")) continue;
        const member = rest[0 .. rest.len - 1];
        if (member.len == 0) continue;

        var named = true;
        for (member) |c| {
            if (partOfAName(c)) continue;
            named = false;
            break;
        }
        if (!named) continue;
        found.append(gpa, member) catch @panic("OOM");
    }
    return found.items;
}

/// Whether some call to `called` is given `.literal` as an argument.
fn passedTo(text: []const u8, called: []const u8, literal: []const u8) bool {
    var at: usize = 0;
    while (std.mem.indexOfPos(u8, text, at, called)) |found| {
        at = found + called.len;
        // The name and not a name holding it, and a call and not a mention.
        if (found > 0 and partOfAName(text[found - 1])) continue;
        if (at >= text.len or text[at] != '(') continue;

        const given = firstLiteralIn(text, at + 1) orelse continue;
        if (std.mem.eql(u8, given, literal)) return true;
    }
    return false;
}

/// The first enum literal a call is given, reading from just inside its paren.
///
/// An argument and not a field of one: `&w.passed_over` holds a dot that begins
/// no literal, so what precedes a literal has to be the paren or the comma that
/// opens the argument. The scan reaches to the semicolon ending the statement,
/// so a literal written past one -- inside a block the call is handed -- is not
/// seen, and neither is one passed as a variable.
fn firstLiteralIn(text: []const u8, from: usize) ?[]const u8 {
    var i = from;
    while (i < text.len) : (i += 1) {
        if (text[i] == ';') return null;
        if (text[i] != '.') continue;

        var back = i;
        while (back > from and (text[back - 1] == ' ' or text[back - 1] == '\n')) back -= 1;
        if (back != from and text[back - 1] != ',') continue;

        var end = i + 1;
        while (end < text.len and partOfAName(text[end])) end += 1;
        if (end == i + 1) continue;
        return text[i + 1 .. end];
    }
    return null;
}

/// Whether every loop over `enum_name`'s values that prints `marker` also calls
/// `accounted_by` in the same block, and some loop does both.
///
/// Some loop, rather than none vacuously: a run that stopped reporting these
/// counts altogether, or an enum renamed under this, leaves nothing for the
/// first half to be true of.
pub fn reportsAndAccounts(
    gpa: std.mem.Allocator,
    text: []const u8,
    enum_name: []const u8,
    marker: []const u8,
    accounted_by: []const u8,
) bool {
    const over = std.fmt.allocPrint(gpa, "std.enums.values({s})", .{enum_name}) catch @panic("OOM");
    defer gpa.free(over);
    const call = std.fmt.allocPrint(gpa, "{s}(", .{accounted_by}) catch @panic("OOM");
    defer gpa.free(call);

    var both = false;
    var at: usize = 0;
    while (std.mem.indexOfPos(u8, text, at, over)) |found| {
        at = found + over.len;
        const body = indentedUnder(text, found);
        if (std.mem.indexOf(u8, body, marker) == null) continue;
        if (std.mem.indexOf(u8, body, call) == null) return false;
        both = true;
    }
    return both;
}

/// A relation one decision record states about another, and the relation the
/// other has to state back.
///
/// Longest first, because `refined by` contains `refine`: a scan taking the
/// shorter one would read "refined by 0051" as "refines 0051" and demand the
/// reciprocal of a relation nobody wrote.
const relations = [_]struct { says: []const u8, back: []const u8 }{
    .{ .says = "superseded by", .back = "supersedes" },
    .{ .says = "refined by", .back = "refines" },
    .{ .says = "extended by", .back = "extends" },
    .{ .says = "clarified by", .back = "clarifies" },
    .{ .says = "supersedes", .back = "superseded by" },
    .{ .says = "refines", .back = "refined by" },
    .{ .says = "extends", .back = "extended by" },
    .{ .says = "clarifies", .back = "clarified by" },
};

/// One relation found in a status, with the records it names.
pub const Relation = struct {
    says: []const u8,
    back: []const u8,
    /// Everything between the relation and the next one, which is where the
    /// records it names are written.
    targets: []const u8,
    /// Where a search for the next relation in the same status resumes.
    after: usize,
};

/// The first relation a status states at or after `from`, with the record it
/// names.
///
/// A relation reaches forward to the next relation or to the end, so the words
/// between it and its target are prose the index is free to write: "supersedes
/// the exclusivity clause of 0025" names 0025 the same way "supersedes 0025"
/// does, and which clause it was is a sentence rather than a relation.
pub fn findRelation(status: []const u8, from: usize) ?Relation {
    var best: ?usize = null;
    var which: usize = 0;
    for (relations, 0..) |r, i| {
        const at = indexOfIgnoringCase(status, r.says, from) orelse continue;
        if (best == null or at < best.?) {
            best = at;
            which = i;
        }
    }
    const at = best orelse return null;
    const r = relations[which];

    // Up to the next relation, whichever that turns out to be: the numbers in
    // between belong to this one.
    var stop = status.len;
    for (relations) |o| {
        const next = indexOfIgnoringCase(status, o.says, at + r.says.len) orelse continue;
        if (next < stop) stop = next;
    }

    return .{
        .says = r.says,
        .back = r.back,
        .targets = status[at + r.says.len .. stop],
        .after = at + r.says.len,
    };
}

/// Whether a status states this relation about this record.
pub fn statesRelation(status: []const u8, says: []const u8, number: []const u8) bool {
    var at: usize = 0;
    while (findRelation(status, at)) |found| {
        at = found.after;
        if (!std.mem.eql(u8, found.says, says)) continue;
        var targets: Numbers = .{ .rest = found.targets };
        while (targets.next()) |target| {
            if (std.mem.eql(u8, target, number)) return true;
        }
    }
    return false;
}

/// The four-digit runs in a string, which is how a record is numbered.
pub const Numbers = struct {
    rest: []const u8,

    pub fn next(self: *Numbers) ?[]const u8 {
        var run: usize = 0;
        for (self.rest, 0..) |c, i| {
            if (c < '0' or c > '9') {
                run = 0;
                continue;
            }
            run += 1;
            if (run < 4) continue;
            const found = self.rest[i - 3 .. i + 1];
            self.rest = self.rest[i + 1 ..];
            return found;
        }
        self.rest = "";
        return null;
    }
};

fn indexOfIgnoringCase(haystack: []const u8, needle: []const u8, from: usize) ?usize {
    if (from >= haystack.len) return null;
    const at = std.ascii.indexOfIgnoreCase(haystack[from..], needle) orelse return null;
    return from + at;
}

/// One row of the decision index: the record it links to and what it says
/// about that record's standing.
pub const IndexRow = struct {
    number: []const u8,
    status: []const u8,
};

/// Every row a decision index states, in the order it states them.
///
/// `| [0042](0042-....md) | Title | Status |`, and nothing else in the document
/// opens a line with a bracketed number.
pub fn indexRows(gpa: std.mem.Allocator, text: []const u8) []const IndexRow {
    var rows: std.ArrayList(IndexRow) = .empty;
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |line| {
        if (!std.mem.startsWith(u8, line, "| [")) continue;
        const number = line["| [".len..];
        if (number.len < 4) continue;

        var fields = std.mem.splitScalar(u8, line, '|');
        _ = fields.next();
        _ = fields.next();
        _ = fields.next();
        const status = fields.next() orelse continue;
        rows.append(gpa, .{
            .number = number[0..4],
            .status = std.mem.trim(u8, status, " "),
        }) catch @panic("OOM");
    }
    return rows.items;
}

/// The first number two rows both claim, or null when each names one record.
///
/// A number is how one record refers to another, so a number naming two
/// records is not a clash of filenames -- it is a reference with two referents,
/// and every gate that resolves one picks whichever row it met first. The
/// relation gate is the one that shows it: handed a duplicate, it reports a
/// disagreement between records that never named each other, which says
/// nothing about the pair it names and does not say what is actually wrong.
///
/// Keyed rather than compared pairwise: this walks the index once, so a project
/// that accumulates records does not pay for the check twice over.
pub fn numberClaimedTwice(gpa: std.mem.Allocator, rows: []const IndexRow) ?[]const u8 {
    var seen: std.StringHashMapUnmanaged(void) = .empty;
    defer seen.deinit(gpa);
    for (rows) |row| {
        const got = seen.getOrPut(gpa, row.number) catch @panic("OOM");
        if (got.found_existing) return row.number;
    }
    return null;
}

/// Where the runtime's I/O categories are numbered, and where std reads the
/// numbers back.
pub const io_category_enum = "enum linea_io_category {";
pub const io_category_match = "match linea_io_category(code) {";
pub const io_category_type = "pub enum IoCategory {";

/// The CamelCase member a `LINEA_IO_UPPER_SNAKE` constant is called in std.
fn categoryMemberName(gpa: std.mem.Allocator, constant: []const u8) []const u8 {
    const prefix = "LINEA_IO_";
    const bare = if (std.mem.startsWith(u8, constant, prefix)) constant[prefix.len..] else constant;
    var name: std.ArrayList(u8) = .empty;
    var words = std.mem.tokenizeScalar(u8, bare, '_');
    while (words.next()) |word| {
        name.append(gpa, std.ascii.toUpper(word[0])) catch @panic("OOM");
        for (word[1..]) |c| name.append(gpa, std.ascii.toLower(c)) catch @panic("OOM");
    }
    return name.toOwnedSlice(gpa) catch @panic("OOM");
}

/// The lines between the first `{` of the construct at `marker` and its
/// closing line, or null where `text` does not hold the marker.
fn constructBody(text: []const u8, marker: []const u8) ?[]const u8 {
    const at = std.mem.indexOf(u8, text, marker) orelse return null;
    const from = at + marker.len;
    const closed = std.mem.indexOfAnyPos(u8, text, from, "}") orelse return null;
    return text[from..closed];
}

/// Every way the runtime's I/O category numbers and std's reading of them
/// disagree, each as a sentence; empty where they agree.
///
/// The number is the whole interface: the runtime returns it, and std's
/// `from_os` maps it back to a member by a retyped literal. Std's enum has
/// members the runtime never produces, so its ordinal cannot stand in. What
/// holds the two together is this reading both: every runtime category is
/// the arm std maps it to, number zero is the member the fallback arm names,
/// and no arm maps a number the runtime does not define.
///
/// A text that no longer holds the shape this reads is itself a
/// disagreement, never an empty pass.
pub fn ioCategoryDisagreements(gpa: std.mem.Allocator, header: []const u8, std_text: []const u8) []const []const u8 {
    var found: std.ArrayList([]const u8) = .empty;
    const say = struct {
        fn at(g: std.mem.Allocator, list: *std.ArrayList([]const u8), comptime fmt: []const u8, args: anytype) void {
            list.append(g, std.fmt.allocPrint(g, fmt, args) catch @panic("OOM")) catch @panic("OOM");
        }
    }.at;

    const enum_body = constructBody(header, io_category_enum) orelse {
        say(gpa, &found, "runtime/io.h no longer declares `{s}` where the gate reads it", .{io_category_enum});
        return found.items;
    };
    const match_body = constructBody(std_text, io_category_match) orelse {
        say(gpa, &found, "std no longer declares `{s}` where the gate reads it", .{io_category_match});
        return found.items;
    };
    const type_body = constructBody(std_text, io_category_type) orelse {
        say(gpa, &found, "std no longer declares `{s}` where the gate reads it", .{io_category_type});
        return found.items;
    };

    const Arm = struct { number: ?u32, name: []const u8 };
    var arms: std.ArrayList(Arm) = .empty;
    var arm_lines = std.mem.splitScalar(u8, match_body, '\n');
    while (arm_lines.next()) |raw| {
        const line = std.mem.trim(u8, raw, " \t\r,");
        const arrow = std.mem.indexOf(u8, line, " => .") orelse continue;
        const key = line[0..arrow];
        const name = std.mem.trim(u8, line[arrow + " => .".len ..], " \t");
        const number: ?u32 = if (std.mem.eql(u8, key, "_")) null else std.fmt.parseInt(u32, key, 10) catch {
            say(gpa, &found, "std maps `{s}`, which is not a category number", .{key});
            continue;
        };
        arms.append(gpa, .{ .number = number, .name = name }) catch @panic("OOM");
    }

    var members: std.ArrayList([]const u8) = .empty;
    var member_lines = std.mem.splitScalar(u8, type_body, '\n');
    while (member_lines.next()) |raw| {
        const line = std.mem.trim(u8, raw, " \t\r,");
        if (line.len > 0 and std.ascii.isUpper(line[0])) members.append(gpa, line) catch @panic("OOM");
    }

    var defined: std.ArrayList(u32) = .empty;
    var constants = std.mem.splitScalar(u8, enum_body, '\n');
    while (constants.next()) |raw| {
        const line = std.mem.trim(u8, raw, " \t\r,");
        const equals = std.mem.indexOf(u8, line, " = ") orelse continue;
        const name = categoryMemberName(gpa, std.mem.trim(u8, line[0..equals], " "));
        const number = std.fmt.parseInt(u32, std.mem.trim(u8, line[equals + 3 ..], " "), 10) catch continue;
        defined.append(gpa, number) catch @panic("OOM");

        var holds_member = false;
        for (members.items) |m| holds_member = holds_member or std.mem.eql(u8, m, name);
        if (!holds_member) say(gpa, &found, "the runtime's category {d} is `{s}` and std's `IoCategory` has no such member", .{ number, name });

        var mapped: ?[]const u8 = null;
        for (arms.items) |arm| {
            if (arm.number == number or (number == 0 and arm.number == null)) mapped = arm.name;
        }
        const through = mapped orelse {
            say(gpa, &found, "the runtime's category {d} (`{s}`) is mapped by no arm of `from_os`", .{ number, name });
            continue;
        };
        if (!std.mem.eql(u8, through, name)) {
            say(gpa, &found, "the runtime's category {d} is `{s}` and std reads it as `{s}`", .{ number, name, through });
        }
    }
    if (defined.items.len == 0) say(gpa, &found, "the gate read no category from runtime/io.h", .{});

    for (arms.items) |arm| {
        const number = arm.number orelse continue;
        var known = false;
        for (defined.items) |d| known = known or d == number;
        if (!known) say(gpa, &found, "std maps category {d} to `{s}` and the runtime defines no such number", .{ number, arm.name });
    }
    return found.items;
}

/// A chapter the guide's index links to: the name the index gives it, its file,
/// and, once the gate has read it, its text.
pub const GuideChapter = struct {
    name: []const u8,
    file: []const u8,
    text: []const u8 = "",
    root: ?struct { io: std.Io, dir: std.Io.Dir } = null,
};

/// Every chapter `docs/learn/README.md` links to, in the order it lists them.
///
/// A chapter is a link whose target is a numbered file, `[Errors](03-errors.md)`;
/// the index is read rather than the directory walked, so the chapters are the
/// ones the guide admits to, in its order, on every platform. A file linked
/// twice is kept once, through a set keyed by file, so the work is linear in
/// the index's length.
pub fn guideChapters(gpa: std.mem.Allocator, index: []const u8) []const GuideChapter {
    return linkedPages(gpa, index, .chapters);
}

/// Every page of the guide `docs/learn/README.md` links to: the chapters and
/// the appendices beside them, such as `patterns.md`, in the order it lists
/// them. The guide gate reads the code of all of them; the error index is
/// built from the chapters alone, since `errors.md` is that index.
pub fn guidePages(gpa: std.mem.Allocator, index: []const u8) []const GuideChapter {
    return linkedPages(gpa, index, .pages);
}

fn linkedPages(gpa: std.mem.Allocator, index: []const u8, wanted: enum { chapters, pages }) []const GuideChapter {
    var found: std.ArrayList(GuideChapter) = .empty;
    var seen: std.StringHashMapUnmanaged(void) = .empty;
    defer seen.deinit(gpa);
    var at: usize = 0;
    while (std.mem.indexOfPos(u8, index, at, "](")) |close| {
        at = close + 2;
        const end = std.mem.indexOfScalarPos(u8, index, at, ')') orelse break;
        const file = index[at..end];
        const admitted = switch (wanted) {
            .chapters => isChapterFile(file),
            .pages => isPageFile(file),
        };
        if (!admitted) continue;
        const open = std.mem.lastIndexOfScalar(u8, index[0..close], '[') orelse continue;
        const got = seen.getOrPut(gpa, file) catch @panic("out of memory");
        if (got.found_existing) continue;
        found.append(gpa, .{ .name = index[open + 1 .. close], .file = file }) catch @panic("out of memory");
    }
    return found.toOwnedSlice(gpa) catch @panic("out of memory");
}

/// Whether a link names a page in the guide's own directory: a lowercase
/// Markdown file with no directory, such as `patterns.md`.
fn isPageFile(file: []const u8) bool {
    if (file.len < 4 or !std.mem.endsWith(u8, file, ".md")) return false;
    for (file[0 .. file.len - 3]) |c| {
        if (!std.ascii.isLower(c) and !std.ascii.isDigit(c) and c != '-') return false;
    }
    return true;
}

fn isChapterFile(file: []const u8) bool {
    if (file.len < 7 or !std.mem.endsWith(u8, file, ".md")) return false;
    if (!std.ascii.isDigit(file[0]) or !std.ascii.isDigit(file[1]) or file[2] != '-') return false;
    for (file[3 .. file.len - 3]) |c| {
        if (!std.ascii.isLower(c) and !std.ascii.isDigit(c) and c != '-') return false;
    }
    return true;
}

/// A file of a program the guide pastes, at the path the guide gives it.
pub const GuideFile = struct {
    path: []const u8,
    text: []const u8,
};

/// What the gate asks the compiler to do with a pasted program: `linea run`
/// when output is pasted beside it, `linea test` when that output is a test
/// report, and `linea check` when none is.
pub const GuideCommand = enum { run, check, @"test" };

/// Where the code the gate compiles comes from.
pub const GuideSource = enum {
    /// A `linea` block with `fn main` or a `test fn`, or the files of a
    /// project its labels name.
    program,
    /// A `linea` block that is not a program, written alone as the root file
    /// of a library, which needs no `main`.
    fragment,
    /// The program above with a run of `<!-- guide: edit LINES -->` blocks
    /// applied to it.
    edit,
};

/// Code the guide pastes, as the gate compiles it, with the output the guide
/// pastes beside it, which the gate holds to what the compiler prints.
pub const GuideProgram = struct {
    chapter: []const u8,
    /// The line of the opening fence of the program, the fragment, or the
    /// first block of an edit.
    line: usize,
    files: []const GuideFile,
    /// The path handed to `linea`: the one file, or the project's directory.
    target: []const u8,
    command: GuideCommand,
    expected: ?[]const u8,
    /// The line of the opening fence of the pasted output.
    expected_line: usize = 0,
    /// How many diagnostics the pasted output shows when a `<!-- guide: first N
    /// diagnostics -->` marker says it stops there; null when it shows all.
    expected_first: ?usize = null,
    source: GuideSource = .program,
};

/// Output the guide pastes beside a block the gate does not run.
pub const GuideBlock = struct {
    chapter: []const u8,
    line: usize,
    body: []const u8,
};

/// A block the gate can neither check nor account for.
pub const GuideProblem = struct {
    chapter: []const u8,
    line: usize,
    message: []const u8,
};

/// What one chapter holds: the code to compile, the blocks checked another
/// way or excluded, and the blocks that are none of those, which are refused.
pub const GuideReading = struct {
    programs: []const GuideProgram,
    problems: []const GuideProblem,
    /// Linea blocks a `<!-- guide: excerpt PATH -->` line holds to the file it
    /// names, which the build compiles elsewhere.
    excerpts: usize,
    /// Blocks a `<!-- guide: unchecked REASON -->` line above them excludes,
    /// each with the output pasted beside it.
    excluded: usize,
    /// The output blocks of the excluded ones, which the gate holds to the
    /// diagnostics the compiler prints elsewhere.
    unrun_output: []const GuideBlock,
};

const GuideFence = struct {
    line: usize,
    info: []const u8,
    body: []const u8,
    /// The path in a `` `path.lin`: `` or `` `page.txt`: `` line directly
    /// above the fence.
    label: ?[]const u8,
    /// The `<!-- guide: ... -->` line directly above the fence.
    marker: ?Marker = null,

    fn unchecked(self: GuideFence) bool {
        const marker = self.marker orelse return false;
        return marker == .unchecked;
    }

    /// The N of a `<!-- guide: first N diagnostics -->` line directly above.
    fn first(self: GuideFence) ?usize {
        const marker = self.marker orelse return null;
        return switch (marker) {
            .first => |count| count,
            else => null,
        };
    }

    /// The path of a `<!-- guide: excerpt PATH -->` line directly above.
    fn excerpt(self: GuideFence) ?[]const u8 {
        const marker = self.marker orelse return null;
        return switch (marker) {
            .excerpt => |path| path,
            else => null,
        };
    }

    /// The lines a `<!-- guide: edit LINES -->` line directly above replaces.
    fn edit(self: GuideFence) ?Edit {
        const marker = self.marker orelse return null;
        return switch (marker) {
            .edit => |lines| lines,
            else => null,
        };
    }

    /// A block that could be a program's output. One directly after a
    /// program is its output whatever line stands above it.
    fn isOutput(self: GuideFence) bool {
        return self.info.len == 0 or std.mem.eql(u8, self.info, "text");
    }

    /// A block that is not Linea, labelled with a file that is not Linea
    /// source, and that no program before it claimed as output: a file
    /// written beside the next program, which it may `embed`.
    fn isData(self: GuideFence) bool {
        const path = self.label orelse return false;
        // A labelled manifest is a file of the project it sits in.
        if (std.mem.eql(u8, self.info, "json") and isManifestPath(path)) return false;
        return !std.mem.eql(u8, self.info, "linea") and !std.mem.endsWith(u8, path, ".lin");
    }

    /// The `.lin` file a Linea block's label names, or null. A line above a
    /// Linea block naming anything else, such as `` `str.split_once`: `` at
    /// the end of a sentence, is prose.
    fn sourceLabel(self: GuideFence) ?[]const u8 {
        const path = self.label orelse return null;
        return if (std.mem.endsWith(u8, path, ".lin")) path else null;
    }

    fn hasEntryPoint(self: GuideFence) bool {
        var lines = std.mem.splitScalar(u8, self.body, '\n');
        while (lines.next()) |line| {
            for ([_][]const u8{ "fn main", "pub fn main", "test fn ", "test trap fn " }) |opening| {
                if (std.mem.startsWith(u8, line, opening)) return true;
            }
        }
        return false;
    }

    /// A `linea` block the gate compiles as a program, rather than as a
    /// fragment, an edit or an excerpt.
    fn isProgram(self: GuideFence) bool {
        return std.mem.eql(u8, self.info, "linea") and self.marker == null and
            (self.hasEntryPoint() or self.sourceLabel() != null);
    }
};

const marker_open = "<!-- guide:";
const marker_close = "-->";
const marker_help = "the guide markers are `<!-- guide: unchecked REASON -->`, `<!-- guide: first N diagnostics -->`, `<!-- guide: excerpt PATH -->` and `<!-- guide: edit [PATH] N | N-M | after N -->`, and each is complete";

const Marker = union(enum) {
    unchecked,
    first: usize,
    excerpt: []const u8,
    edit: Edit,
};

/// The lines of the program above that an edit replaces with its block:
/// `count` lines from the 0-based line `start`, so an insertion after line N
/// is `start = N` and `count = 0`.
const Edit = struct {
    /// The file of the program the edit changes, when the program has more
    /// than one Linea file.
    path: ?[]const u8,
    start: usize,
    count: usize,
};

/// The marker a `<!-- guide: ... -->` line holds, or null when it is none of
/// the four kinds or is incomplete.
fn guideMarker(bare: []const u8) ?Marker {
    if (!std.mem.endsWith(u8, bare, marker_close)) return null;
    const inner = std.mem.trim(u8, bare[marker_open.len .. bare.len - marker_close.len], " \t");
    var words = std.mem.tokenizeAny(u8, inner, " \t");
    const kind = words.next() orelse return null;
    if (std.mem.eql(u8, kind, "unchecked")) return if (words.next() != null) .unchecked else null;
    if (std.mem.eql(u8, kind, "excerpt")) {
        const path = words.next() orelse return null;
        if (words.next() != null or path.len == 0 or path[0] == '/') return null;
        return .{ .excerpt = path };
    }
    if (std.mem.eql(u8, kind, "edit")) return if (editMarker(&words)) |lines| .{ .edit = lines } else null;
    if (!std.mem.eql(u8, kind, "first")) return null;
    const count = std.fmt.parseInt(usize, words.next() orelse return null, 10) catch return null;
    const noun = words.next() orelse return null;
    if (count == 0 or words.next() != null) return null;
    if (!std.mem.eql(u8, noun, "diagnostics") and !(count == 1 and std.mem.eql(u8, noun, "diagnostic"))) return null;
    return .{ .first = count };
}

/// The words after `edit`: an optional relative path, then `N`, `N-M` or
/// `after N`, with lines counted from 1.
fn editMarker(words: *std.mem.TokenIterator(u8, .any)) ?Edit {
    var word = words.next() orelse return null;
    var path: ?[]const u8 = null;
    if (std.mem.endsWith(u8, word, ".lin")) {
        if (word[0] == '/') return null;
        path = word;
        word = words.next() orelse return null;
    }
    var lines: Edit = undefined;
    if (std.mem.eql(u8, word, "after")) {
        const after = std.fmt.parseInt(usize, words.next() orelse return null, 10) catch return null;
        lines = .{ .path = path, .start = after, .count = 0 };
    } else {
        const dash = std.mem.indexOfScalar(u8, word, '-');
        const from = std.fmt.parseInt(usize, word[0 .. dash orelse word.len], 10) catch return null;
        const to = if (dash) |at| std.fmt.parseInt(usize, word[at + 1 ..], 10) catch return null else from;
        if (from == 0 or to < from) return null;
        lines = .{ .path = path, .start = from - 1, .count = to - from + 1 };
    }
    if (words.next() != null) return null;
    return lines;
}

/// The path a `` `path.lin`: `` or `` `path/linea.json`: `` line labels, or a
/// data file's such as `` `usage.txt`: ``, or null for any other line. A data
/// file's name carries an extension, so a line naming a word, `` `defer`: ``,
/// labels nothing.
fn guideLabel(line: []const u8) ?[]const u8 {
    const bare = std.mem.trim(u8, line, " \t");
    if (bare.len < 4 or bare[0] != '`' or !std.mem.endsWith(u8, bare, "`:")) return null;
    const path = bare[1 .. bare.len - 2];
    if (std.mem.indexOfScalar(u8, std.fs.path.basename(path), '.') == null) return null;
    for (path) |c| {
        if (!std.ascii.isAlphanumeric(c) and c != '_' and c != '/' and c != '.' and c != '-') return null;
    }
    return path;
}

/// Every fenced block of a chapter in order, with the label and the marker
/// above it. A marker that is not directly above a fence, or gives no reason,
/// is a problem rather than being ignored.
fn guideFences(
    gpa: std.mem.Allocator,
    chapter: GuideChapter,
    problems: *std.ArrayList(GuideProblem),
) []const GuideFence {
    var fences: std.ArrayList(GuideFence) = .empty;
    var lines = std.mem.splitScalar(u8, chapter.text, '\n');
    var number: usize = 0;
    var label: ?[]const u8 = null;
    var pending: ?struct { line: usize, marker: Marker } = null;
    while (lines.next()) |raw| {
        number += 1;
        const line = std.mem.trimEnd(u8, raw, "\r");
        const bare = std.mem.trim(u8, line, " \t");
        const run = fenceRun(bare);
        if (run.len >= 3) {
            const indent = line.len - std.mem.trimStart(u8, line, " \t").len;
            const opening = number;
            var body: std.ArrayList(u8) = .empty;
            while (lines.next()) |inner_raw| {
                number += 1;
                const inner = std.mem.trimEnd(u8, inner_raw, "\r");
                const closing = std.mem.trim(u8, inner, " \t");
                const closing_run = fenceRun(closing);
                if (closing_run.char == run.char and closing_run.len >= run.len and closing_run.len == closing.len) break;
                if (body.items.len > 0) body.append(gpa, '\n') catch @panic("out of memory");
                body.appendSlice(gpa, inner[@min(indent, inner.len - std.mem.trimStart(u8, inner, " \t").len)..]) catch @panic("out of memory");
            }
            fences.append(gpa, .{
                .line = opening,
                .info = std.mem.trim(u8, bare[run.len..], " \t"),
                .body = body.items,
                .label = label,
                .marker = if (pending) |p| p.marker else null,
            }) catch @panic("out of memory");
            label = null;
            pending = null;
            continue;
        }
        if (bare.len == 0) continue;
        if (pending) |at| {
            problems.append(gpa, .{
                .chapter = chapter.file,
                .line = at.line,
                .message = "a `<!-- guide: ... -->` line must sit directly above the block it excludes",
            }) catch @panic("out of memory");
            pending = null;
        }
        label = guideLabel(line);
        if (std.mem.startsWith(u8, bare, marker_open)) {
            if (guideMarker(bare)) |marker| {
                pending = .{ .line = number, .marker = marker };
            } else problems.append(gpa, .{
                .chapter = chapter.file,
                .line = number,
                .message = marker_help,
            }) catch @panic("out of memory");
        }
    }
    if (pending) |at| problems.append(gpa, .{
        .chapter = chapter.file,
        .line = at.line,
        .message = "a `<!-- guide: ... -->` line must sit directly above the block it excludes",
    }) catch @panic("out of memory");
    return fences.toOwnedSlice(gpa) catch @panic("out of memory");
}

/// The `linea` command a shell block shows: its subcommand and path, or null
/// when the block shows anything else.
fn guideCommand(body: []const u8) ?struct { command: GuideCommand, path: []const u8 } {
    var words = std.mem.tokenizeAny(u8, std.mem.trim(u8, body, " \t\r\n"), " \t");
    if (!std.mem.eql(u8, words.next() orelse return null, "linea")) return null;
    const verb = words.next() orelse return null;
    const command = std.meta.stringToEnum(GuideCommand, verb) orelse return null;
    const path = words.next() orelse return null;
    if (words.next() != null) return null;
    return .{ .command = command, .path = path };
}

/// Whether a line is the closing line of a `linea test` report, such as
/// `3 passed, 0 failed`.
fn isTestSummary(line: []const u8) bool {
    var words = std.mem.tokenizeScalar(u8, std.mem.trim(u8, line, " \t\r"), ' ');
    const passed = words.next() orelse return false;
    const passed_word = words.next() orelse return false;
    const failed = words.next() orelse return false;
    const failed_word = words.next() orelse return false;
    if (words.next() != null) return false;
    _ = std.fmt.parseInt(u64, passed, 10) catch return false;
    _ = std.fmt.parseInt(u64, failed, 10) catch return false;
    return std.mem.eql(u8, passed_word, "passed,") and std.mem.eql(u8, failed_word, "failed");
}

/// Whether a label names a manifest, which a project carries beside its
/// sources.
fn isManifestPath(path: []const u8) bool {
    return std.mem.eql(u8, std.fs.path.basename(path), "linea.json");
}

/// The file a pasted diagnostic or trap names, such as `pace_lent.lin` in
/// `--> pace_lent.lin:10:21`. The standard library's own files are not it.
fn guideNamedFile(output: []const u8) ?[]const u8 {
    var at: usize = 0;
    while (std.mem.indexOfPos(u8, output, at, ".lin:")) |end| {
        at = end + 5;
        var start = end;
        while (start > 0) {
            const c = output[start - 1];
            if (!std.ascii.isAlphanumeric(c) and c != '_' and c != '/' and c != '.' and c != '-') break;
            start -= 1;
        }
        const path = output[start .. end + 4];
        if (path.len > 4 and !std.mem.startsWith(u8, path, "std/")) return path;
    }
    return null;
}

/// The output a block claims: the first block that follows without a `linea`
/// or an output block between, bare or `text`, after an optional `sh` block
/// holding the `linea` command that produced it.
const Claim = struct {
    shown: ?struct { command: GuideCommand, path: []const u8 } = null,
    expected: ?[]const u8 = null,
    expected_line: usize = 0,
    expected_first: ?usize = null,

    /// `linea run` when output is pasted, `linea test` when it ends with a
    /// test report, and `linea check` when none is, unless a shell block
    /// shows the command.
    fn command(self: Claim) GuideCommand {
        if (self.shown) |shown| return shown.command;
        const text = self.expected orelse return .check;
        var last: []const u8 = "";
        var lines = std.mem.splitScalar(u8, text, '\n');
        while (lines.next()) |line| {
            if (std.mem.trim(u8, line, " \t\r").len > 0) last = line;
        }
        return if (isTestSummary(last)) .@"test" else .run;
    }

    /// The file the shell block runs or the pasted output names, if either
    /// does.
    fn named(self: Claim) ?[]const u8 {
        if (self.shown) |shown| return shown.path;
        return guideNamedFile(self.expected orelse return null);
    }
};

/// Takes the output after the block before `i.*`, advancing past it.
fn claimOutput(
    gpa: std.mem.Allocator,
    chapter: GuideChapter,
    fences: []const GuideFence,
    i: *usize,
    problems: *std.ArrayList(GuideProblem),
) Claim {
    var claim: Claim = .{};
    if (i.* < fences.len and std.mem.eql(u8, fences[i.*].info, "sh")) {
        if (guideCommand(fences[i.*].body)) |shown| {
            claim.shown = .{ .command = shown.command, .path = shown.path };
            i.* += 1;
        } else if (std.mem.startsWith(u8, std.mem.trimStart(u8, fences[i.*].body, " \t\r\n"), "linea ")) {
            problems.append(gpa, .{
                .chapter = chapter.file,
                .line = fences[i.*].line,
                .message = "the gate reads `linea run|check|test PATH` and nothing longer; write `<!-- guide: unchecked REASON -->` above the program",
            }) catch @panic("out of memory");
            i.* += 1;
        }
    }
    if (i.* < fences.len and fences[i.*].isOutput() and !fences[i.*].unchecked()) {
        claim.expected = fences[i.*].body;
        claim.expected_line = fences[i.*].line;
        claim.expected_first = fences[i.*].first();
        i.* += 1;
    }
    return claim;
}

/// Every complete program a chapter pastes, every fragment, and an account
/// of the rest.
///
/// A `linea` block is a program when it has `fn main` or a `test fn`, or
/// when it is one of the files a `` `path.lin`: `` line labels, which together
/// make a project once `main.lin` arrives. Its output is the block `Claim`
/// describes. Any other `linea` block is a fragment, and every fragment is
/// checked one way:
///
/// - `<!-- guide: edit [PATH] LINES -->` above it applies it to the last
///   program above, or with PATH to the file PATH of the last program above
///   that has one, replacing line N, lines N-M, or inserting after line N,
///   counted in that file as pasted. Consecutive edit blocks apply together,
///   and the output after the last is what the edited program prints.
/// - `<!-- guide: excerpt PATH -->` holds it to consecutive lines of a file
///   the build compiles, or of a program a guide page compiles.
/// - `<!-- guide: unchecked REASON -->` excludes it, for a sketch or a
///   signature that cannot stand alone.
/// - Otherwise it is checked alone, as the root file of a library.
///
/// Output that no block claims is refused, so a pasted error cannot sit
/// beside code nothing compiles.
pub fn readGuideChapter(gpa: std.mem.Allocator, chapter: GuideChapter) GuideReading {
    var problems: std.ArrayList(GuideProblem) = .empty;
    const fences = guideFences(gpa, chapter, &problems);
    var programs: std.ArrayList(GuideProgram) = .empty;
    var project: std.ArrayList(GuideFile) = .empty;
    // Files written beside the next program, which it may embed, and the line
    // of the first of them.
    var data: std.ArrayList(GuideFile) = .empty;
    var data_line: usize = 0;
    var excerpts: usize = 0;
    var excluded: usize = 0;
    var unrun_output: std.ArrayList(GuideBlock) = .empty;
    // The index in `programs` of the last program built from program blocks,
    // which an edit changes, and of the last with a file at each path, which
    // an edit naming that path changes.
    var above: ?usize = null;
    var by_file: std.StringHashMapUnmanaged(usize) = .empty;
    var i: usize = 0;
    while (i < fences.len) {
        const fence = fences[i];
        i += 1;
        const is_linea = std.mem.eql(u8, fence.info, "linea");
        // A data block belongs to the program directly after it, past other
        // data blocks and the files of a labelled project; anything else
        // strands it, and a fragment does below.
        const is_manifest = std.mem.eql(u8, fence.info, "json") and if (fence.label) |path| isManifestPath(path) else false;
        const continues_data = fence.isData() or is_manifest or (is_linea and fence.excerpt() == null and fence.edit() == null);
        if (!continues_data) strandData(gpa, chapter, &problems, &data, data_line);
        if (fence.first() != null and !fence.isOutput()) {
            problems.append(gpa, .{
                .chapter = chapter.file,
                .line = fence.line,
                .message = "`<!-- guide: first N diagnostics -->` belongs directly above the output block it describes",
            }) catch @panic("out of memory");
        }
        if ((fence.excerpt() != null or fence.edit() != null) and !is_linea) {
            problems.append(gpa, .{
                .chapter = chapter.file,
                .line = fence.line,
                .message = "`<!-- guide: excerpt PATH -->` and `<!-- guide: edit LINES -->` belong directly above a `linea` block",
            }) catch @panic("out of memory");
            continue;
        }
        if (fence.excerpt()) |path| {
            excerpts += 1;
            if (checkExcerpt(gpa, chapter, path, fence.body)) |message| {
                problems.append(gpa, .{
                    .chapter = chapter.file,
                    .line = fence.line,
                    .message = message,
                }) catch @panic("out of memory");
            }
            continue;
        }
        if (fence.unchecked()) {
            excluded += 1;
            // An excluded program takes the data above it with it.
            if (is_linea) data.clearRetainingCapacity();
            if (fence.isOutput()) {
                unrun_output.append(gpa, .{ .chapter = chapter.file, .line = fence.line, .body = fence.body }) catch @panic("out of memory");
            }
            if (i < fences.len and fences[i].isOutput()) {
                unrun_output.append(gpa, .{ .chapter = chapter.file, .line = fences[i].line, .body = fences[i].body }) catch @panic("out of memory");
                i += 1;
            }
            continue;
        }
        if (fence.isData()) {
            if (data.items.len == 0) data_line = fence.line;
            data.append(gpa, .{ .path = fence.label.?, .text = fence.body }) catch @panic("out of memory");
            continue;
        }
        if (fence.isOutput()) {
            problems.append(gpa, .{
                .chapter = chapter.file,
                .line = fence.line,
                .message = "output pasted beside no complete program; give the program above it, or write `<!-- guide: unchecked REASON -->` above the block",
            }) catch @panic("out of memory");
            continue;
        }
        // A labelled manifest joins the project as any labelled file does:
        // it says what its directory's root is and which libraries it
        // depends on.
        if (std.mem.eql(u8, fence.info, "json")) {
            if (fence.label) |path| if (isManifestPath(path)) {
                project.append(gpa, .{ .path = path, .text = fence.body }) catch @panic("out of memory");
            };
            continue;
        }
        if (!is_linea) continue;

        if (fence.edit() != null) {
            // The run is this block and the edit blocks directly after it.
            const run_start = i - 1;
            while (i < fences.len and std.mem.eql(u8, fences[i].info, "linea") and fences[i].edit() != null) i += 1;
            const run = fences[run_start..i];
            const claim = claimOutput(gpa, chapter, fences, &i, &problems);
            const named = for (run) |edit_fence| {
                if (edit_fence.edit().?.path) |path| break path;
            } else null;
            const base_at = if (named) |path| by_file.get(path) else above;
            const base = if (base_at) |at| programs.items[at] else {
                problems.append(gpa, .{
                    .chapter = chapter.file,
                    .line = fence.line,
                    .message = if (named) |path|
                        std.fmt.allocPrint(gpa, "an edit naming `{s}` changes the last program above with that file, and none comes before it in this page", .{path}) catch @panic("out of memory")
                    else
                        "an edit changes the program above it, and no program comes before it in this page",
                }) catch @panic("out of memory");
                continue;
            };
            const files = applyEdits(gpa, chapter, base, run, &problems) orelse continue;
            var target = base.target;
            // A program of one file is written to the file its output names.
            if (base.files.len > 0 and std.mem.eql(u8, base.target, base.files[0].path)) {
                if (claim.named()) |name| {
                    files[0].path = name;
                    target = name;
                }
            }
            programs.append(gpa, .{
                .chapter = chapter.file,
                .line = fence.line,
                .files = files,
                .target = target,
                .command = claim.command(),
                .expected = claim.expected,
                .expected_line = claim.expected_line,
                .expected_first = claim.expected_first,
                .source = .edit,
            }) catch @panic("out of memory");
            continue;
        }

        const label = fence.sourceLabel();
        if (label == null) project.clearRetainingCapacity();
        const has_entry = fence.hasEntryPoint();
        if (label) |path| project.append(gpa, .{ .path = path, .text = fence.body }) catch @panic("out of memory");
        const is_main_file = if (label) |path| std.mem.eql(u8, std.fs.path.basename(path), "main.lin") else false;
        var sources: usize = 0;
        for (project.items) |file| sources += @intFromBool(std.mem.endsWith(u8, file.path, ".lin"));
        const alone = label != null and sources == 1 and has_entry;
        if (label != null and !is_main_file and !alone) continue;

        if (label == null and !has_entry) {
            strandData(gpa, chapter, &problems, &data, data_line);
            const claim = claimOutput(gpa, chapter, fences, &i, &problems);
            const files = fragmentLibrary(gpa, claim.named() orelse "fragment.lin", fence.body);
            programs.append(gpa, .{
                .chapter = chapter.file,
                .line = fence.line,
                .files = files,
                .target = files[0].path,
                .command = if (claim.shown) |shown| shown.command else .check,
                .expected = claim.expected,
                .expected_line = claim.expected_line,
                .expected_first = claim.expected_first,
                .source = .fragment,
            }) catch @panic("out of memory");
            continue;
        }

        const claim = claimOutput(gpa, chapter, fences, &i, &problems);
        if (label != null) {
            var root: []const u8 = ".";
            if (is_main_file) {
                const dir = std.fs.path.dirname(label.?) orelse "";
                if (dir.len > 0) root = dir;
            } else root = label.?;
            project.appendSlice(gpa, data.items) catch @panic("out of memory");
            data.clearRetainingCapacity();
            programs.append(gpa, .{
                .chapter = chapter.file,
                .line = fence.line,
                .files = gpa.dupe(GuideFile, project.items) catch @panic("out of memory"),
                .target = root,
                .command = claim.command(),
                .expected = claim.expected,
                .expected_line = claim.expected_line,
                .expected_first = claim.expected_first,
            }) catch @panic("out of memory");
            above = programs.items.len - 1;
            for (programs.items[above.?].files) |file| by_file.put(gpa, file.path, above.?) catch @panic("out of memory");
            project.clearRetainingCapacity();
            continue;
        }
        const name = claim.named() orelse "main.lin";
        const files = gpa.alloc(GuideFile, 1 + data.items.len) catch @panic("out of memory");
        files[0] = .{ .path = name, .text = fence.body };
        @memcpy(files[1..], data.items);
        data.clearRetainingCapacity();
        programs.append(gpa, .{
            .chapter = chapter.file,
            .line = fence.line,
            .files = files,
            .target = name,
            .command = claim.command(),
            .expected = claim.expected,
            .expected_line = claim.expected_line,
            .expected_first = claim.expected_first,
        }) catch @panic("out of memory");
        above = programs.items.len - 1;
        by_file.put(gpa, name, above.?) catch @panic("out of memory");
    }
    strandData(gpa, chapter, &problems, &data, data_line);
    return .{
        .programs = programs.toOwnedSlice(gpa) catch @panic("out of memory"),
        .problems = problems.toOwnedSlice(gpa) catch @panic("out of memory"),
        .excerpts = excerpts,
        .excluded = excluded,
        .unrun_output = unrun_output.toOwnedSlice(gpa) catch @panic("out of memory"),
    };
}

/// A fragment written as the root file of a library at `path`, with the
/// manifest beside it, so a fragment of declarations needs no `main`. A
/// library's root file is named after the library, so a name that is not an
/// identifier is replaced by `fragment`.
fn fragmentLibrary(gpa: std.mem.Allocator, path: []const u8, body: []const u8) []GuideFile {
    const dir = std.fs.path.dirname(path) orelse "";
    const stem = std.fs.path.stem(path);
    const name = if (isLibraryName(stem)) stem else "fragment";
    const files = gpa.alloc(GuideFile, 2) catch @panic("out of memory");
    files[0] = .{
        .path = std.fs.path.join(gpa, &.{ dir, std.mem.concat(gpa, u8, &.{ name, ".lin" }) catch @panic("out of memory") }) catch @panic("out of memory"),
        .text = body,
    };
    files[1] = .{
        .path = std.fs.path.join(gpa, &.{ dir, "linea.json" }) catch @panic("out of memory"),
        .text = std.fmt.allocPrint(gpa, "{{ \"kind\": \"library\", \"name\": \"{s}\" }}", .{name}) catch @panic("out of memory"),
    };
    return files;
}

fn isLibraryName(name: []const u8) bool {
    if (name.len == 0 or std.ascii.isDigit(name[0])) return false;
    for (name) |c| {
        if (!std.ascii.isLower(c) and !std.ascii.isDigit(c) and c != '_') return false;
    }
    return true;
}

/// The files of `base` with a run of edit blocks applied, or null after
/// reporting why the run cannot apply. Every edit counts lines in `base` as
/// pasted, so the edits of one run must not overlap; each is compared with
/// the others of its run, and a run is the few blocks between two outputs.
fn applyEdits(
    gpa: std.mem.Allocator,
    chapter: GuideChapter,
    base: GuideProgram,
    run: []const GuideFence,
    problems: *std.ArrayList(GuideProblem),
) ?[]GuideFile {
    const Placed = struct { file: usize, edit: Edit, body: []const u8, order: usize };
    var placed: std.ArrayList(Placed) = .empty;
    var linea_files: usize = 0;
    var only: usize = 0;
    for (base.files, 0..) |file, at| if (std.mem.endsWith(u8, file.path, ".lin")) {
        linea_files += 1;
        only = at;
    };
    var failed = false;
    for (run, 0..) |fence, order| {
        const edit = fence.edit().?;
        const file: usize = if (edit.path) |path| found: {
            for (base.files, 0..) |candidate, at| if (std.mem.eql(u8, candidate.path, path)) break :found at;
            problems.append(gpa, .{
                .chapter = chapter.file,
                .line = fence.line,
                .message = std.fmt.allocPrint(gpa, "the edit names `{s}`, which is not a file of the program above", .{path}) catch @panic("out of memory"),
            }) catch @panic("out of memory");
            failed = true;
            continue;
        } else if (linea_files == 1) only else {
            problems.append(gpa, .{
                .chapter = chapter.file,
                .line = fence.line,
                .message = "the program above has several Linea files; name the one this block changes, `<!-- guide: edit PATH LINES -->`",
            }) catch @panic("out of memory");
            failed = true;
            continue;
        };
        const length = std.mem.count(u8, base.files[file].text, "\n") + 1;
        if (edit.start + edit.count > length) {
            problems.append(gpa, .{
                .chapter = chapter.file,
                .line = fence.line,
                .message = std.fmt.allocPrint(gpa, "the edit reaches past the end of `{s}`, which has {d} lines", .{ base.files[file].path, length }) catch @panic("out of memory"),
            }) catch @panic("out of memory");
            failed = true;
            continue;
        }
        for (placed.items) |earlier| {
            if (earlier.file != file) continue;
            const apart = edit.start + edit.count <= earlier.edit.start or earlier.edit.start + earlier.edit.count <= edit.start;
            // Two insertions at one line, or an insertion at the edge of a
            // replacement, are apart; an insertion inside one is not.
            const inside = (edit.count == 0 and edit.start > earlier.edit.start and edit.start < earlier.edit.start + earlier.edit.count) or
                (earlier.edit.count == 0 and earlier.edit.start > edit.start and earlier.edit.start < edit.start + edit.count);
            if (apart and !inside) continue;
            problems.append(gpa, .{
                .chapter = chapter.file,
                .line = fence.line,
                .message = "this edit changes lines an earlier edit of the same run already changes",
            }) catch @panic("out of memory");
            failed = true;
            break;
        }
        placed.append(gpa, .{ .file = file, .edit = edit, .body = fence.body, .order = order }) catch @panic("out of memory");
    }
    if (failed) return null;

    std.mem.sort(Placed, placed.items, {}, struct {
        fn lessThan(_: void, a: Placed, b: Placed) bool {
            if (a.file != b.file) return a.file < b.file;
            if (a.edit.start != b.edit.start) return a.edit.start < b.edit.start;
            // An insertion goes before a replacement that starts on its line.
            if ((a.edit.count == 0) != (b.edit.count == 0)) return a.edit.count == 0;
            return a.order < b.order;
        }
    }.lessThan);
    const files = gpa.dupe(GuideFile, base.files) catch @panic("out of memory");
    var next: usize = 0;
    for (files, 0..) |*file, at| {
        const first = next;
        while (next < placed.items.len and placed.items[next].file == at) next += 1;
        if (first == next) continue;
        var lines: std.ArrayList([]const u8) = .empty;
        var split = std.mem.splitScalar(u8, file.text, '\n');
        while (split.next()) |line| lines.append(gpa, line) catch @panic("out of memory");
        var out: std.ArrayList(u8) = .empty;
        var line: usize = 0;
        for (placed.items[first..next]) |edit| {
            for (lines.items[line..edit.edit.start]) |kept| {
                out.appendSlice(gpa, kept) catch @panic("out of memory");
                out.append(gpa, '\n') catch @panic("out of memory");
            }
            out.appendSlice(gpa, edit.body) catch @panic("out of memory");
            out.append(gpa, '\n') catch @panic("out of memory");
            line = edit.edit.start + edit.edit.count;
        }
        for (lines.items[line..]) |kept| {
            out.appendSlice(gpa, kept) catch @panic("out of memory");
            out.append(gpa, '\n') catch @panic("out of memory");
        }
        file.text = out.items[0 .. out.items.len - 1];
    }
    return files;
}

/// Why `fragment` is not a run of consecutive lines of `path` under
/// `chapter.root`, or null when it is. A guide page's lines are those of the
/// programs it compiles, so an excerpt of a page quotes code the gate built.
fn checkExcerpt(gpa: std.mem.Allocator, chapter: GuideChapter, path: []const u8, fragment: []const u8) ?[]const u8 {
    const root = chapter.root orelse return std.fmt.allocPrint(gpa, "the excerpt file `{s}` could not be read", .{path}) catch @panic("out of memory");
    const file_text = root.dir.readFileAlloc(root.io, path, gpa, .limited(1 << 22)) catch {
        return std.fmt.allocPrint(gpa, "the excerpt file `{s}` could not be read", .{path}) catch @panic("out of memory");
    };
    if (!std.mem.endsWith(u8, path, ".md")) {
        if (isExcerptOf(gpa, fragment, file_text)) return null;
        return std.fmt.allocPrint(gpa, "the excerpt does not match consecutive lines of `{s}`", .{path}) catch @panic("out of memory");
    }
    var ignored: std.ArrayList(GuideProblem) = .empty;
    for (guideFences(gpa, .{ .name = path, .file = path, .text = file_text }, &ignored)) |fence| {
        if (fence.isProgram() and isExcerptOf(gpa, fragment, fence.body)) return null;
    }
    return std.fmt.allocPrint(gpa, "the excerpt does not match consecutive lines of a program `{s}` compiles", .{path}) catch @panic("out of memory");
}

/// Whether every line of `fragment` is a consecutive line of `file_text`, with
/// one indentation that all the matched lines share taken off.
fn isExcerptOf(gpa: std.mem.Allocator, fragment: []const u8, file_text: []const u8) bool {
    var wanted: std.ArrayList([]const u8) = .empty;
    var frag_iter = std.mem.splitScalar(u8, fragment, '\n');
    while (frag_iter.next()) |raw| {
        wanted.append(gpa, std.mem.trimEnd(u8, raw, " \t\r")) catch @panic("out of memory");
    }
    if (wanted.items.len == 0) return false;
    // The first line with text decides the indentation the match takes off.
    var anchor: usize = 0;
    while (anchor < wanted.items.len and wanted.items[anchor].len == 0) anchor += 1;
    if (anchor == wanted.items.len) return false;

    var lines: std.ArrayList([]const u8) = .empty;
    var file_iter = std.mem.splitScalar(u8, file_text, '\n');
    while (file_iter.next()) |raw| {
        lines.append(gpa, std.mem.trimEnd(u8, raw, " \t\r")) catch @panic("out of memory");
    }
    if (wanted.items.len > lines.items.len) return false;
    const limit = lines.items.len - wanted.items.len + 1;
    outer: for (0..limit) |start| {
        const at_anchor = lines.items[start + anchor];
        if (!std.mem.endsWith(u8, at_anchor, wanted.items[anchor])) continue;
        const indent = at_anchor[0 .. at_anchor.len - wanted.items[anchor].len];
        if (std.mem.trim(u8, indent, " \t").len != 0) continue;
        for (wanted.items, 0..) |line, offset| {
            const have = lines.items[start + offset];
            if (line.len == 0) {
                if (have.len != 0) continue :outer;
                continue;
            }
            if (!std.mem.startsWith(u8, have, indent) or !std.mem.eql(u8, have[indent.len..], line)) continue :outer;
        }
        return true;
    }
    return false;
}

/// Reports data blocks no program took, and forgets them: a file written beside
/// nothing that runs is a block the gate never checked.
fn strandData(
    gpa: std.mem.Allocator,
    chapter: GuideChapter,
    problems: *std.ArrayList(GuideProblem),
    data: *std.ArrayList(GuideFile),
    line: usize,
) void {
    if (data.items.len == 0) return;
    problems.append(gpa, .{
        .chapter = chapter.file,
        .line = line,
        .message = "a labelled data block is written beside the program directly after it, and none follows; put the program after it, or write `<!-- guide: unchecked REASON -->` above the block",
    }) catch @panic("out of memory");
    data.clearRetainingCapacity();
}

/// Why what the compiler printed is not what the guide pasted, or null when it
/// is. Trailing whitespace is not compared. A block marked `<!-- guide: first N
/// diagnostics -->` must be exactly the first N diagnostics of the output, with
/// at least one more diagnostic after them; any other block is all of it. A
/// program with no pasted output must simply pass `linea check`.
pub fn judgeGuideProgram(gpa: std.mem.Allocator, program: GuideProgram, actual: []const u8, succeeded: bool) ?[]const u8 {
    const shown = maskStandardLocations(gpa, std.mem.trimEnd(u8, actual, " \t\r\n"));
    const pasted = maskStandardLocations(gpa, std.mem.trimEnd(u8, program.expected orelse {
        if (succeeded) return null;
        if (program.source == .fragment and onlyUnusedDeclarations(actual, program.files[0].text)) return null;
        const what: []const u8 = switch (program.source) {
            .program => "the program is complete and pasted without output, and `linea check` refused it",
            .fragment => "this fragment is pasted without output, and `linea check` refused it alone, as the root file of a library",
            .edit => "the program above with this edit is pasted without output, and `linea check` refused it",
        };
        const next: []const u8 = switch (program.source) {
            .program => "",
            .fragment => "Correct the fragment if it is wrong. Otherwise say where it belongs: `<!-- guide: edit LINES -->` " ++
                "above it applies it to the program above (`N`, `N-M` or `after N`), `<!-- guide: excerpt PATH -->` holds it " ++
                "to lines of a file the build compiles or of a program a guide page compiles, and " ++
                "`<!-- guide: unchecked REASON -->` excludes a sketch or a signature that cannot stand alone.\n",
            .edit => "Correct the edit or the lines its `<!-- guide: edit LINES -->` names, which count lines of the program above as pasted, " ++
                "or paste the output the edited program prints after it.\n",
        };
        return std.fmt.allocPrint(gpa, "{s}:{d}: {s}:\n{s}\n{s}", .{ program.chapter, program.line, what, shown, next }) catch @panic("out of memory");
    }, " \t\r\n"));
    if (program.expected_first) |count| {
        if (std.mem.eql(u8, pasted, shown)) {
            return std.fmt.allocPrint(
                gpa,
                "{s}:{d}: the output pasted at line {d} is all of what `linea {s} {s}` prints; remove its `<!-- guide: first {d} diagnostics -->` line\n",
                .{ program.chapter, program.line, program.expected_line, @tagName(program.command), program.target, count },
            ) catch @panic("out of memory");
        }
        if (isDiagnosticPrefix(pasted, shown, count)) return null;
    } else if (std.mem.eql(u8, pasted, shown)) return null;
    const marker_note: []const u8 = if (program.expected_first != null)
        "The marker promises the first diagnostics and nothing else: the pasted block must be exactly the first N, followed in the output by another diagnostic.\n"
    else
        "A block that shows only the first diagnostics says so with `<!-- guide: first N diagnostics -->` above it.\n";
    const difference = firstDifference(pasted, shown) orelse FirstDifference{
        .number = std.mem.count(u8, pasted, "\n") + 1,
        .expected = "(the end of the pasted block)",
        .found = "(more output)",
    };
    return std.fmt.allocPrint(
        gpa,
        "{s}:{d}: the output pasted at line {d} is not what `linea {s} {s}` prints.\n" ++
            "  first difference at line {d} of the pasted block:\n    pasted: {s}\n    actual: {s}\n{s}" ++
            "The compiler printed:\n{s}\n",
        .{
            program.chapter,           program.line,     program.expected_line,
            @tagName(program.command), program.target,   difference.number,
            difference.expected,       difference.found, marker_note,
            shown,
        },
    ) catch @panic("out of memory");
}

/// Whether every diagnostic in `output` is `[N-Unused]` reported at a line of
/// `body` that opens a declaration at the top of the file. A fragment shows
/// declarations without the code that calls them, so its own declarations
/// going unused says nothing about the fragment; an unused local, or any
/// other error, does.
fn onlyUnusedDeclarations(output: []const u8, body: []const u8) bool {
    var lines = std.mem.splitScalar(u8, output, '\n');
    var diagnostics: usize = 0;
    var awaiting_location = false;
    while (lines.next()) |raw| {
        const line = std.mem.trimEnd(u8, raw, " \t\r");
        if (line.len > 0 and line[0] != ' ') {
            const opening = diagnosticOpening(line) orelse continue;
            if (!std.mem.eql(u8, opening.kind, "error") or !std.mem.eql(u8, opening.code, "N-Unused")) return false;
            if (awaiting_location) return false;
            diagnostics += 1;
            awaiting_location = true;
            continue;
        }
        if (!awaiting_location) continue;
        const arrow = std.mem.indexOf(u8, line, "--> ") orelse continue;
        awaiting_location = false;
        // `path:LINE:COLUMN`, read from the right so a path may hold colons.
        const location = line[arrow + 4 ..];
        const column_colon = std.mem.lastIndexOfScalar(u8, location, ':') orelse return false;
        const line_colon = std.mem.lastIndexOfScalar(u8, location[0..column_colon], ':') orelse return false;
        const number = std.fmt.parseInt(usize, location[line_colon + 1 .. column_colon], 10) catch return false;
        var body_lines = std.mem.splitScalar(u8, body, '\n');
        var at: usize = 1;
        const reported = while (body_lines.next()) |body_line| : (at += 1) {
            if (at == number) break body_line;
        } else return false;
        if (reported.len == 0 or reported[0] == ' ' or reported[0] == '\t') return false;
    }
    return diagnostics > 0 and !awaiting_location;
}

/// `text` with the line and column of every location inside the standard
/// library, such as `std/result/result.lin:394:23`, replaced by `_`. Those
/// numbers move whenever a library file changes above the line and say nothing
/// about the guide's program, so only the file is compared.
fn maskStandardLocations(gpa: std.mem.Allocator, text: []const u8) []const u8 {
    var out: std.ArrayList(u8) = .empty;
    var at: usize = 0;
    while (std.mem.indexOfPos(u8, text, at, "std/")) |start| {
        var end = start;
        while (end < text.len and (std.ascii.isAlphanumeric(text[end]) or text[end] == '_' or text[end] == '/' or text[end] == '.' or text[end] == '-')) end += 1;
        const path = text[start..end];
        out.appendSlice(gpa, text[at..end]) catch @panic("out of memory");
        at = end;
        if (!std.mem.endsWith(u8, path, ".lin")) continue;
        var cursor = end;
        var numbers: usize = 0;
        while (numbers < 2 and cursor < text.len and text[cursor] == ':') {
            const digits = std.mem.indexOfNonePos(u8, text, cursor + 1, "0123456789") orelse text.len;
            if (digits == cursor + 1) break;
            cursor = digits;
            numbers += 1;
        }
        if (numbers == 0) continue;
        out.appendSlice(gpa, if (numbers == 2) ":_:_" else ":_") catch @panic("out of memory");
        at = cursor;
    }
    out.appendSlice(gpa, text[at..]) catch @panic("out of memory");
    return out.items;
}

/// Whether `pasted` is exactly the first `count` diagnostics of `shown`, with
/// another diagnostic directly after them.
fn isDiagnosticPrefix(pasted: []const u8, shown: []const u8, count: usize) bool {
    if (!std.mem.startsWith(u8, shown, pasted) or shown.len <= pasted.len or shown[pasted.len] != '\n') return false;
    if (countDiagnostics(pasted) != count) return false;
    const rest = shown[pasted.len + 1 ..];
    return diagnosticOpening(rest[0 .. std.mem.indexOfScalar(u8, rest, '\n') orelse rest.len]) != null and rest[0] != ' ';
}

/// How many diagnostics start in `text`: lines at column 0 that open an error,
/// a warning or a note.
fn countDiagnostics(text: []const u8) usize {
    var count: usize = 0;
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |line| {
        if (line.len > 0 and line[0] != ' ' and diagnosticOpening(line) != null) count += 1;
    }
    return count;
}

/// The wording of diagnostics the compiler really prints: the header of each
/// diagnostic, each `help:` and `note:` line, and the label beside each
/// underline, with the names between backticks and the digits masked. The
/// guide pastes errors for programs it does not run, such as an edit of the
/// program above, and holds each of those lines to being one the compiler
/// prints for some program. The set is built once from the compiler's real
/// output, so a check costs a lookup per pasted line, never a scan of the
/// output. Spans, source lines and the line numbers in them are not compared.
pub const DiagnosticWording = struct {
    seen: std.StringHashMapUnmanaged(void) = .empty,

    /// Records every diagnostic line in `text`, the output of one compiler run.
    pub fn addOutput(self: *DiagnosticWording, gpa: std.mem.Allocator, text: []const u8) void {
        var key: std.ArrayList(u8) = .empty;
        defer key.deinit(gpa);
        var lines = std.mem.splitScalar(u8, text, '\n');
        while (lines.next()) |line| {
            if (!wordingKey(gpa, &key, line)) continue;
            if (self.seen.contains(key.items)) continue;
            self.seen.put(gpa, gpa.dupe(u8, key.items) catch @panic("out of memory"), {}) catch @panic("out of memory");
        }
    }

    /// Why a pasted block states wording the compiler never prints, or null.
    pub fn judge(self: DiagnosticWording, gpa: std.mem.Allocator, block: GuideBlock) ?[]const u8 {
        var key: std.ArrayList(u8) = .empty;
        defer key.deinit(gpa);
        var found: std.ArrayList(u8) = .empty;
        var lines = std.mem.splitScalar(u8, block.body, '\n');
        var number: usize = 0;
        while (lines.next()) |line| {
            number += 1;
            if (!wordingKey(gpa, &key, line)) continue;
            if (self.seen.contains(key.items)) continue;
            found.print(gpa, "{s}:{d}: the guide pastes `{s}`, and no diagnostic the compiler prints reads that way\n", .{
                block.chapter, block.line + number, std.mem.trim(u8, line, " \t\r"),
            }) catch @panic("out of memory");
        }
        return if (found.items.len == 0) null else found.items;
    }
};

/// Writes the comparison key of a diagnostic line into `key` and returns true,
/// or returns false for a line that is not part of a diagnostic's wording.
fn wordingKey(gpa: std.mem.Allocator, key: *std.ArrayList(u8), raw: []const u8) bool {
    const line = std.mem.trimEnd(u8, raw, " \t\r");
    key.clearRetainingCapacity();
    var text: []const u8 = undefined;
    if (line.len > 0 and line[0] != ' ' and diagnosticOpening(line) != null) {
        text = line;
    } else {
        const bare = std.mem.trimStart(u8, line, " \t");
        if (std.mem.startsWith(u8, bare, "= help:") or std.mem.startsWith(u8, bare, "= note:")) {
            text = bare;
        } else {
            const bar = std.mem.indexOfScalar(u8, line, '|') orelse return false;
            if (std.mem.trim(u8, line[0..bar], " ").len != 0) return false;
            const after = std.mem.trim(u8, line[bar + 1 ..], " \t");
            if (after.len == 0 or (after[0] != '^' and after[0] != '-')) return false;
            const run = std.mem.indexOfNone(u8, after, &.{after[0]}) orelse return false;
            text = std.mem.trimStart(u8, after[run..], " \t");
            if (text.len == 0) return false;
            key.appendSlice(gpa, "| ") catch @panic("out of memory");
        }
    }
    var in_code = false;
    for (text) |c| {
        if (c == '`') {
            in_code = !in_code;
            key.append(gpa, c) catch @panic("out of memory");
            if (in_code) key.append(gpa, '_') catch @panic("out of memory");
        } else if (!in_code) {
            const masked: u8 = if (std.ascii.isDigit(c)) '#' else c;
            if (masked == '#' and key.items.len > 0 and key.items[key.items.len - 1] == '#') continue;
            key.append(gpa, masked) catch @panic("out of memory");
        }
    }
    return true;
}

/// The anchor GitHub gives a heading: lowercased, spaces made hyphens, and
/// every character dropped that is neither a letter, a digit, `-` nor `_`.
///
/// A letter outside ASCII is kept, as GitHub keeps `á`; the punctuation the
/// documents use outside ASCII -- `§`, `—`, `…` -- is dropped. Only Latin
/// letters are recognised above ASCII, which is every letter these documents
/// write in a heading.
pub fn headingSlug(gpa: std.mem.Allocator, title: []const u8) []const u8 {
    var out: std.ArrayList(u8) = .empty;
    const trimmed = std.mem.trim(u8, title, " \t\r");
    var i: usize = 0;
    while (i < trimmed.len) {
        const c = trimmed[i];
        if (c < 0x80) {
            if (std.ascii.isAlphanumeric(c) or c == '_' or c == '-') {
                out.append(gpa, std.ascii.toLower(c)) catch @panic("out of memory");
            } else if (c == ' ') {
                out.append(gpa, '-') catch @panic("out of memory");
            }
            i += 1;
            continue;
        }
        const len = std.unicode.utf8ByteSequenceLength(c) catch 1;
        const end = @min(i + len, trimmed.len);
        const point = std.unicode.utf8Decode(trimmed[i..end]) catch 0;
        // Latin-1 Supplement and Latin Extended-A and -B letters, without the
        // two signs that sit among them.
        if (point >= 0xC0 and point <= 0x24F and point != 0xD7 and point != 0xF7) {
            out.appendSlice(gpa, trimmed[i..end]) catch @panic("out of memory");
        }
        i = end;
    }
    return out.toOwnedSlice(gpa) catch @panic("out of memory");
}

/// A heading and the anchor a link reaches it by.
pub const Heading = struct {
    title: []const u8,
    anchor: []const u8,
};

/// One line of a Markdown document as the guide's gate reads it.
pub const MarkdownLine = union(enum) {
    heading: Heading,
    /// A line inside a fenced block, whatever its info string. Output is
    /// pasted under a bare fence, `text`, `console` or anything else, and no
    /// line of source opens with `error[X-Name]: `, so every fenced line is
    /// read for a diagnostic rather than guessing which fences hold output.
    fenced: []const u8,
    prose: []const u8,
};

/// A walk over a Markdown document's lines, telling headings, fenced lines and
/// prose apart. A repeated heading gets the anchor GitHub gives it, with `-1`,
/// `-2` and so on after the first.
///
/// A fence is a run of three or more backticks or tildes, indented or not, and
/// only a run of the same character at least as long closes it, as CommonMark
/// says: a four-backtick fence holds a three-backtick line as text.
pub const MarkdownWalk = struct {
    gpa: std.mem.Allocator,
    lines: std.mem.SplitIterator(u8, .scalar),
    seen: std.StringHashMapUnmanaged(usize) = .empty,
    fence: ?Fence = null,

    const Fence = struct { char: u8, len: usize };

    pub fn init(gpa: std.mem.Allocator, text: []const u8) MarkdownWalk {
        return .{ .gpa = gpa, .lines = std.mem.splitScalar(u8, text, '\n') };
    }

    pub fn next(self: *MarkdownWalk) ?MarkdownLine {
        while (self.lines.next()) |raw| {
            const line = std.mem.trimEnd(u8, raw, "\r");
            const bare = std.mem.trim(u8, line, " \t");
            if (self.fence) |open| {
                const run = fenceRun(bare);
                if (run.len >= open.len and run.char == open.char and run.len == bare.len) {
                    self.fence = null;
                    continue;
                }
                return .{ .fenced = line };
            }
            const run = fenceRun(bare);
            if (run.len >= 3) {
                self.fence = .{ .char = run.char, .len = run.len };
                continue;
            }
            if (headingTitle(line)) |title| {
                const base = headingSlug(self.gpa, title);
                const got = self.seen.getOrPut(self.gpa, base) catch @panic("out of memory");
                const count = if (got.found_existing) got.value_ptr.* else 0;
                got.value_ptr.* = count + 1;
                const anchor = if (count == 0) base else std.fmt.allocPrint(self.gpa, "{s}-{d}", .{ base, count }) catch @panic("out of memory");
                return .{ .heading = .{ .title = title, .anchor = anchor } };
            }
            return .{ .prose = line };
        }
        return null;
    }
};

const FenceRun = struct { char: u8 = 0, len: usize = 0 };

/// The run of backticks or tildes a trimmed line opens with.
fn fenceRun(bare: []const u8) FenceRun {
    if (bare.len == 0 or (bare[0] != '`' and bare[0] != '~')) return .{};
    var len: usize = 0;
    while (len < bare.len and bare[len] == bare[0]) len += 1;
    return .{ .char = bare[0], .len = len };
}

fn headingTitle(line: []const u8) ?[]const u8 {
    var hashes: usize = 0;
    while (hashes < line.len and line[hashes] == '#') hashes += 1;
    if (hashes == 0 or hashes > 6 or hashes >= line.len or line[hashes] != ' ') return null;
    return line[hashes + 1 ..];
}

/// A diagnostic a line of pasted output opens with: its kind and its code.
pub const Diagnostic = struct {
    kind: []const u8,
    code: []const u8,
};

/// The diagnostic an output line opens with, such as `error[O-Leak]: …`, or
/// null for any other line.
pub fn diagnosticOpening(line: []const u8) ?Diagnostic {
    const bare = std.mem.trimStart(u8, line, " \t");
    inline for (.{ "error", "warning", "note" }) |kind| {
        if (std.mem.startsWith(u8, bare, kind ++ "[")) {
            const rest = bare[kind.len + 1 ..];
            const close = std.mem.indexOfScalar(u8, rest, ']') orelse return null;
            const code = rest[0..close];
            if (!isRuleCode(code) or !std.mem.startsWith(u8, rest[close..], "]: ")) return null;
            return .{ .kind = kind, .code = code };
        }
    }
    return null;
}

/// Whether `code` has the shape of a rule's name: a capital naming the pass,
/// `-`, then a capitalised word such as `Leak` or `TryAnswer`. The lowercase
/// letter it requires is what tells `O-Leak` from a character class such as
/// `A-Z`.
pub fn isRuleCode(code: []const u8) bool {
    if (code.len < 4 or !std.ascii.isUpper(code[0]) or code[1] != '-' or !std.ascii.isUpper(code[2])) return false;
    var lower = false;
    for (code[3..]) |c| {
        if (!std.ascii.isAlphabetic(c)) return false;
        if (std.ascii.isLower(c)) lower = true;
    }
    return lower;
}

/// How a line names rule codes: the ones it names in a form the gate reads,
/// `[T-Impl]` or `` `T-Impl` ``, and the ones it writes bare, which the gate
/// cannot tell from ordinary words.
pub const CodesOnLine = struct {
    named: []const []const u8,
    bare: []const []const u8,
};

/// Every rule code a line of prose, a heading or a table cell names.
pub fn codesOnLine(gpa: std.mem.Allocator, line: []const u8) CodesOnLine {
    var named: std.ArrayList([]const u8) = .empty;
    var bare: std.ArrayList([]const u8) = .empty;
    var i: usize = 0;
    while (i < line.len) {
        if (!std.ascii.isUpper(line[i]) or (i > 0 and isWordByte(line[i - 1]))) {
            i += 1;
            continue;
        }
        var end = i;
        while (end < line.len and (isWordByte(line[end]) or line[end] == '-')) end += 1;
        const word = line[i..end];
        if (isRuleCode(word)) {
            const before: u8 = if (i > 0) line[i - 1] else ' ';
            const after: u8 = if (end < line.len) line[end] else ' ';
            const wrapped = (before == '[' and after == ']') or (before == '`' and after == '`');
            (if (wrapped) &named else &bare).append(gpa, word) catch @panic("out of memory");
        }
        i = @max(end, i + 1);
    }
    return .{
        .named = named.toOwnedSlice(gpa) catch @panic("out of memory"),
        .bare = bare.toOwnedSlice(gpa) catch @panic("out of memory"),
    };
}

fn isWordByte(c: u8) bool {
    return std.ascii.isAlphanumeric(c) or c == '_';
}

/// Where the semantics document defines each rule: the section holding the
/// paragraph that opens `**[CODE]**`.
pub fn ruleSections(gpa: std.mem.Allocator, semantics: []const u8) std.StringArrayHashMapUnmanaged(Heading) {
    var rules: std.StringArrayHashMapUnmanaged(Heading) = .empty;
    var walk = MarkdownWalk.init(gpa, semantics);
    var section: Heading = .{ .title = "", .anchor = "" };
    while (walk.next()) |line| switch (line) {
        .heading => |h| section = h,
        .fenced => {},
        .prose => |text| {
            if (!std.mem.startsWith(u8, text, "**[")) continue;
            const close = std.mem.indexOfPos(u8, text, 3, "]**") orelse continue;
            const code = text[3..close];
            if (!isRuleCode(code)) continue;
            const got = rules.getOrPut(gpa, code) catch @panic("out of memory");
            if (!got.found_existing) got.value_ptr.* = section;
        },
    };
    return rules;
}

/// Where the guide first mentions a code: the chapter, the section, and the
/// kind of diagnostic when the guide shows one.
const Mention = struct {
    chapter: GuideChapter,
    section: Heading,
    kind: []const u8,
};

/// A code written bare in a heading or a table row, where the gate cannot tell
/// whether it names a rule.
pub const Unclassified = struct {
    code: []const u8,
    file: []const u8,
    line: []const u8,
};

/// The page `docs/learn/errors.md` must hold, every code the guide shows or
/// names that no rule of the semantics defines, and every code it writes where
/// the gate cannot classify it.
pub const GuideErrorIndex = struct {
    page: []const u8,
    undefined_codes: []const []const u8,
    unclassified: []const Unclassified,
};

/// The index of the diagnostics the guide shows, as `docs/learn/errors.md`
/// holds it.
///
/// A code is shown where a fenced block pastes an error, warning or note that
/// opens with it, and the row links to the first such section. A code named in
/// prose, a heading or a table cell, as `[T-Impl]` or `` `T-Impl` ``, and shown
/// nowhere is listed apart, linking to where it is first named, so a reader who
/// meets it can still find its rule. A code written bare in a heading or a
/// table row is reported rather than guessed at.
pub fn guideErrorIndex(gpa: std.mem.Allocator, chapters: []const GuideChapter, semantics: []const u8) GuideErrorIndex {
    var shown: std.StringArrayHashMapUnmanaged(Mention) = .empty;
    var named: std.StringArrayHashMapUnmanaged(Mention) = .empty;
    var unclassified: std.ArrayList(Unclassified) = .empty;
    for (chapters) |chapter| {
        var walk = MarkdownWalk.init(gpa, chapter.text);
        var section: Heading = .{ .title = "", .anchor = "" };
        while (walk.next()) |line| {
            const text = switch (line) {
                .heading => |h| blk: {
                    section = h;
                    break :blk h.title;
                },
                .fenced => |text| {
                    const d = diagnosticOpening(text) orelse continue;
                    const got = shown.getOrPut(gpa, d.code) catch @panic("out of memory");
                    if (!got.found_existing) got.value_ptr.* = .{ .chapter = chapter, .section = section, .kind = d.kind };
                    continue;
                },
                .prose => |text| text,
            };
            const codes = codesOnLine(gpa, text);
            for (codes.named) |code| {
                const got = named.getOrPut(gpa, code) catch @panic("out of memory");
                if (!got.found_existing) got.value_ptr.* = .{ .chapter = chapter, .section = section, .kind = "" };
            }
            const structural = line == .heading or std.mem.startsWith(u8, std.mem.trimStart(u8, text, " "), "|");
            if (structural) for (codes.bare) |code| {
                unclassified.append(gpa, .{ .code = code, .file = chapter.file, .line = text }) catch @panic("out of memory");
            };
        }
    }
    const rules = ruleSections(gpa, semantics);

    var undefined_codes: std.ArrayList([]const u8) = .empty;
    var out: std.ArrayList(u8) = .empty;
    const w = struct {
        fn line(o: *std.ArrayList(u8), a: std.mem.Allocator, comptime fmt: []const u8, args: anytype) void {
            const s = std.fmt.allocPrint(a, fmt ++ "\n", args) catch @panic("out of memory");
            o.appendSlice(a, s) catch @panic("out of memory");
        }
    }.line;

    w(&out, gpa, "# Errors the guide shows", .{});
    w(&out, gpa, "", .{});
    w(&out, gpa, "Every diagnostic the compiler prints names the rule it enforces, such as", .{});
    w(&out, gpa, "`error[O-Leak]`. This page lists each code the guide shows a real error, warning", .{});
    w(&out, gpa, "or note for, where the guide first shows it, and the section of the [language", .{});
    w(&out, gpa, "definition](../linea-semantics.md) that defines its rule. Search that section", .{});
    w(&out, gpa, "for the code in brackets to reach the rule itself.", .{});
    w(&out, gpa, "", .{});
    w(&out, gpa, "| Code | Kind | First shown in | Rule |", .{});
    w(&out, gpa, "| --- | --- | --- | --- |", .{});
    for (sortedKeys(gpa, shown.keys())) |code| {
        const m = shown.get(code).?;
        const rule = rules.get(code) orelse {
            undefined_codes.append(gpa, code) catch @panic("out of memory");
            continue;
        };
        w(&out, gpa, "| `{s}` | {s} | {s}: [{s}]({s}#{s}) | [{s}](../linea-semantics.md#{s}), at `[{s}]` |", .{
            code, m.kind, m.chapter.name, m.section.title, m.chapter.file, m.section.anchor, rule.title, rule.anchor, code,
        });
    }

    var unshown: std.ArrayList([]const u8) = .empty;
    for (sortedKeys(gpa, named.keys())) |code| {
        if (!shown.contains(code)) unshown.append(gpa, code) catch @panic("out of memory");
    }
    if (unshown.items.len > 0) {
        w(&out, gpa, "", .{});
        w(&out, gpa, "## Named but not shown", .{});
        w(&out, gpa, "", .{});
        w(&out, gpa, "The chapters name these codes without pasting an error for them.", .{});
        w(&out, gpa, "", .{});
        w(&out, gpa, "| Code | Named in | Rule |", .{});
        w(&out, gpa, "| --- | --- | --- |", .{});
        for (unshown.items) |code| {
            const m = named.get(code).?;
            const rule = rules.get(code) orelse {
                undefined_codes.append(gpa, code) catch @panic("out of memory");
                continue;
            };
            w(&out, gpa, "| `{s}` | {s}: [{s}]({s}#{s}) | [{s}](../linea-semantics.md#{s}), at `[{s}]` |", .{
                code, m.chapter.name, m.section.title, m.chapter.file, m.section.anchor, rule.title, rule.anchor, code,
            });
        }
    }
    w(&out, gpa, "", .{});
    w(&out, gpa, "`zig build` checks this page against the chapters, and refuses to configure", .{});
    w(&out, gpa, "while a code is missing from it or a row has gone stale. It then prints the", .{});
    w(&out, gpa, "page as it should read.", .{});
    return .{
        .page = out.toOwnedSlice(gpa) catch @panic("out of memory"),
        .undefined_codes = undefined_codes.toOwnedSlice(gpa) catch @panic("out of memory"),
        .unclassified = unclassified.toOwnedSlice(gpa) catch @panic("out of memory"),
    };
}

/// The first line on which two texts differ, counted from 1, and each text's
/// version of it; null when they are equal.
pub const FirstDifference = struct {
    number: usize,
    expected: []const u8,
    found: []const u8,
};

pub fn firstDifference(expected: []const u8, found: []const u8) ?FirstDifference {
    if (std.mem.eql(u8, expected, found)) return null;
    var e = std.mem.splitScalar(u8, expected, '\n');
    var f = std.mem.splitScalar(u8, found, '\n');
    var number: usize = 1;
    while (true) : (number += 1) {
        const a = e.next();
        const b = f.next();
        if (a == null and b == null) return null;
        const x = a orelse "(the end of the page)";
        const y = b orelse "(the end of the page)";
        if (a == null or b == null or !std.mem.eql(u8, x, y)) return .{ .number = number, .expected = x, .found = y };
    }
}

fn sortedKeys(gpa: std.mem.Allocator, keys: []const []const u8) []const []const u8 {
    const copy = gpa.dupe([]const u8, keys) catch @panic("out of memory");
    std.mem.sort([]const u8, copy, {}, struct {
        fn less(_: void, a: []const u8, b: []const u8) bool {
            return std.mem.lessThan(u8, a, b);
        }
    }.less);
    return copy;
}

/// One file or directory beneath `examples/`, by path relative to it.
pub const ExampleEntry = struct {
    path: []const u8,
    directory: bool,
    /// A manifest's text; empty for everything else.
    text: []const u8 = "",
};

pub const ExampleLayout = union(enum) {
    entries: []const ExampleEntry,
    /// A symlink, by path. `linea` does not follow one inside a root, so
    /// whether a linked directory is a root is a question the walk cannot
    /// settle, and the gate refuses to guess.
    symlink: []const u8,
};

/// Every file and directory beneath `sub_path`, ordered by path.
///
/// `iterate` is what makes the walk legal: a directory opened without it can
/// still be iterated on some hosts and not on others.
pub fn exampleLayout(
    gpa: std.mem.Allocator,
    io: std.Io,
    root: std.Io.Dir,
    sub_path: []const u8,
) !ExampleLayout {
    var dir = try root.openDir(io, sub_path, .{ .iterate = true });
    defer dir.close(io);

    var walker = try dir.walk(gpa);
    defer walker.deinit();

    var found: std.ArrayList(ExampleEntry) = .empty;
    while (try walker.next(io)) |entry| {
        const path = try gpa.dupe(u8, entry.path);
        switch (entry.kind) {
            .sym_link => return .{ .symlink = path },
            .directory => try found.append(gpa, .{ .path = path, .directory = true }),
            .file => {
                const text: []const u8 = if (std.mem.eql(u8, entry.basename, manifest_name))
                    try dir.readFileAlloc(io, entry.path, gpa, .limited(1 << 20))
                else
                    "";
                try found.append(gpa, .{ .path = path, .directory = false, .text = text });
            },
            else => {},
        }
    }
    std.mem.sort(ExampleEntry, found.items, {}, struct {
        fn less(_: void, a: ExampleEntry, b: ExampleEntry) bool {
            return std.mem.lessThan(u8, a.path, b.path);
        }
    }.less);
    return .{ .entries = found.items };
}

const manifest_name = "linea.json";

/// Which paths to hand to `linea test`, relative to `examples/`: each `.lin`
/// file directly in it, each directory directly in it (an example is a root
/// with or without a manifest), and each deeper directory holding a
/// `linea.json`, which is a library or application of its own.
///
/// `linea test` runs only the tests of the root it names (ADR 0229), so a
/// nested library needs its own run. Which files a root reaches, and which of
/// them declare tests, is the loader's answer and is read from the run.
pub fn exampleRoots(gpa: std.mem.Allocator, entries: []const ExampleEntry) []const []const u8 {
    var roots: std.StringArrayHashMapUnmanaged(void) = .empty;
    for (entries) |entry| {
        const nested = std.mem.indexOfScalar(u8, entry.path, '/') != null;
        if (entry.directory) {
            if (!nested) roots.put(gpa, entry.path, {}) catch @panic("out of memory");
            continue;
        }
        if (!nested) {
            if (std.mem.endsWith(u8, entry.path, ".lin")) roots.put(gpa, entry.path, {}) catch @panic("out of memory");
            continue;
        }
        const directory = std.fs.path.dirnamePosix(entry.path).?;
        if (std.mem.eql(u8, std.fs.path.basenamePosix(entry.path), manifest_name)) {
            roots.put(gpa, directory, {}) catch @panic("out of memory");
        }
    }
    return sortedKeys(gpa, roots.keys());
}

/// How many tests a `linea test` run reported, from its closing
/// `N passed, M failed` line; null when the output ends otherwise.
pub fn testsReported(output: []const u8) ?usize {
    const trimmed = std.mem.trimEnd(u8, output, "\n");
    const line = trimmed[(std.mem.lastIndexOfScalar(u8, trimmed, '\n') orelse 0)..];
    var words = std.mem.tokenizeAny(u8, line, " ,\n");
    const passed = std.fmt.parseInt(usize, words.next() orelse return null, 10) catch return null;
    if (!std.mem.eql(u8, words.next() orelse return null, "passed")) return null;
    const failed = std.fmt.parseInt(usize, words.next() orelse return null, 10) catch return null;
    if (!std.mem.eql(u8, words.next() orelse return null, "failed")) return null;
    return passed + failed;
}

/// What `unreachedSources` found wrong beneath `examples/`.
pub const Unreached = struct {
    /// `.lin` files no root's run would load.
    files: []const []const u8,
    /// Manifests whose `source` cannot be applied, each as a sentence naming it.
    problems: []const []const u8,
};

/// Whether a manifest's `source` names a directory inside the one holding the
/// manifest: not absolute, and not climbing past it once `.` and `..` are
/// resolved. The rule is `sourceStaysInside` in `src/driver/loader.zig`, which
/// build/ cannot import; its test "a manifest's source stays inside the
/// directory holding it" and the case "a source that leaves its root, and a
/// manifest that is not JSON, are named" in `build/source_test.zig` use the
/// same spellings.
fn staysInside(gpa: std.mem.Allocator, named: []const u8) bool {
    if (named.len > 0 and named[0] == '/') return false;
    const resolved = std.fs.path.resolvePosix(gpa, &.{named}) catch @panic("out of memory");
    return !(std.mem.eql(u8, resolved, "..") or std.mem.startsWith(u8, resolved, "../"));
}

/// The directory, relative to `examples/`, whose files `root` reaches: the
/// root itself, or its manifest's `source` directory. A manifest that cannot
/// be read, or whose `source` leaves the root, is a problem and has no reach.
///
/// This is the rule `sourceRootOf` in `src/driver/loader.zig` applies to a
/// manifest, spelled by joining and removing `.` segments. The compiler cannot
/// be imported here, so the loader's test "a manifest's source key narrows the
/// files a root reaches" and the case "a source no root reaches belongs to no
/// example root" in `build/source_test.zig` use the same manifest text and fail
/// when the two disagree.
fn reachOf(gpa: std.mem.Allocator, root: []const u8, entries: []const ExampleEntry, problems: *std.ArrayList([]const u8)) ?[]const u8 {
    const manifest = for (entries) |entry| {
        if (entry.directory or !std.mem.eql(u8, std.fs.path.basenamePosix(entry.path), manifest_name)) continue;
        const directory = std.fs.path.dirnamePosix(entry.path) orelse continue;
        if (std.mem.eql(u8, directory, root)) break entry;
    } else null;
    var named: []const u8 = ".";
    if (manifest) |found| {
        const Written = struct { source: ?[]const u8 = null };
        const parsed = std.json.parseFromSliceLeaky(Written, gpa, found.text, .{ .ignore_unknown_fields = true }) catch {
            problems.append(gpa, std.fmt.allocPrint(gpa, "{s} is not valid JSON", .{found.path}) catch @panic("out of memory")) catch @panic("out of memory");
            return null;
        };
        if (parsed.source) |source| if (source.len > 0) {
            if (!staysInside(gpa, source)) {
                problems.append(gpa, std.fmt.allocPrint(gpa, "{s} names a source, \"{s}\", outside its directory", .{ found.path, source }) catch @panic("out of memory")) catch @panic("out of memory");
                return null;
            }
            named = source;
        };
    }
    const resolved = std.fs.path.resolvePosix(gpa, &.{ "/", root, named }) catch @panic("out of memory");
    return resolved[1..];
}

/// The `.lin` files beneath `examples/` that no root reaches, so that no run of
/// `linea test` would load them, and the manifests whose `source` cannot be
/// applied. A file belongs to the deepest root enclosing it, and is reached
/// when it lies inside that root's source directory.
pub fn unreachedSources(gpa: std.mem.Allocator, entries: []const ExampleEntry, roots: []const []const u8) Unreached {
    var problems: std.ArrayList([]const u8) = .empty;
    const reaches = gpa.alloc(?[]const u8, roots.len) catch @panic("out of memory");
    for (roots, reaches) |root, *reach| {
        reach.* = if (std.mem.endsWith(u8, root, ".lin")) root else reachOf(gpa, root, entries, &problems);
    }
    var unreached: std.ArrayList([]const u8) = .empty;
    for (entries) |entry| {
        if (entry.directory or !std.mem.endsWith(u8, entry.path, ".lin")) continue;
        var owner: ?usize = null;
        for (roots, 0..) |root, at| {
            const encloses = std.mem.eql(u8, entry.path, root) or
                (entry.path.len > root.len and entry.path[root.len] == '/' and std.mem.startsWith(u8, entry.path, root));
            if (encloses and (owner == null or root.len > roots[owner.?].len)) owner = at;
        }
        const at = owner orelse {
            unreached.append(gpa, entry.path) catch @panic("out of memory");
            continue;
        };
        if (std.mem.eql(u8, entry.path, roots[at])) continue;
        // A root whose manifest is refused reports that, not its files.
        const reach = reaches[at] orelse continue;
        const inside = reach.len == 0 or
            (entry.path.len > reach.len and entry.path[reach.len] == '/' and std.mem.startsWith(u8, entry.path, reach));
        if (!inside) unreached.append(gpa, entry.path) catch @panic("out of memory");
    }
    return .{ .files = unreached.items, .problems = problems.items };
}
