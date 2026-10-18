//! What the gates read out of the project's own text, held to cases.
//!
//! The root of a test binary of its own, because a build script's `test` blocks
//! are never run by anything: `zig build` evaluates `build.zig` and runs no test
//! in it, so a heuristic living there is a heuristic nothing can fail.

const std = @import("std");
const testing = std.testing;
const source = @import("source.zig");
const test_roots = @import("test_roots.zig");
const runtime_symbols = @import("runtime_symbols");

test "runtime archive members have stable names and separate linkage" {
    const archive = @embedFile("runtime_archive");
    try testing.expect(std.mem.startsWith(u8, archive, "!<arch>\n"));
    const expected = [_][]const u8{ "linea_rt.o", "io.o", "net.o", "clock.o", "linea_float.o", "math.o" };
    var member: usize = 0;
    var offset: usize = 8;
    var long_names: []const u8 = "";
    while (offset < archive.len) {
        try testing.expect(archive.len - offset >= 60);
        const header = archive[offset..][0..60];
        try testing.expectEqualStrings("`\n", header[58..60]);
        const size = try std.fmt.parseInt(usize, std.mem.trim(u8, header[48..58], " "), 10);
        offset += 60;
        try testing.expect(size <= archive.len - offset);
        const contents = archive[offset..][0..size];
        offset += size + size % 2;
        var name = std.mem.trimEnd(u8, header[0..16], " ");
        if (std.mem.eql(u8, name, "/") or std.mem.eql(u8, name, "/SYM64/")) continue;
        if (std.mem.eql(u8, name, "//")) {
            long_names = contents;
            continue;
        }
        if (std.mem.startsWith(u8, name, "#1/")) {
            const length = try std.fmt.parseInt(usize, name[3..], 10);
            try testing.expect(length <= contents.len);
            name = std.mem.trimEnd(u8, contents[0..length], "\x00");
        } else if (std.mem.startsWith(u8, name, "/")) {
            const start = try std.fmt.parseInt(usize, name[1..], 10);
            try testing.expect(start < long_names.len);
            const end = std.mem.indexOfScalarPos(u8, long_names, start, '\n') orelse return error.InvalidArchive;
            name = std.mem.trimEnd(u8, long_names[start..end], "/");
        } else {
            name = std.mem.trimEnd(u8, name, "/");
        }
        if (std.mem.startsWith(u8, name, "__.SYMDEF")) continue;
        try testing.expect(member < expected.len);
        try testing.expectEqualStrings(expected[member], name);
        member += 1;
    }
    try testing.expectEqual(expected.len, member);
}

test "CI outcome snapshots preserve restore and save contracts" {
    const workflow = try std.Io.Dir.cwd().readFileAlloc(testing.io, ".github/workflows/ci.yml", testing.allocator, .limited(1 << 20));
    defer testing.allocator.free(workflow);
    for ([_][]const u8{ "check", "sanitize", "optimised" }) |job_name| {
        const marker = try std.fmt.allocPrint(testing.allocator, "\n  {s}:\n", .{job_name});
        defer testing.allocator.free(marker);
        const job_start = (std.mem.indexOf(u8, workflow, marker) orelse return error.MissingJob) + marker.len;
        var job_end = job_start;
        while (job_end < workflow.len) {
            const line_end = std.mem.indexOfScalarPos(u8, workflow, job_end, '\n') orelse workflow.len;
            const line = workflow[job_end..line_end];
            if (line.len > 2 and std.mem.startsWith(u8, line, "  ") and line[2] != ' ') break;
            job_end = @min(line_end + 1, workflow.len);
        }
        const job = workflow[job_start..job_end];
        const restore = outcomeStep(job, "actions/cache/restore@v4") orelse return error.MissingRestoreStep;
        const save = outcomeStep(job, "actions/cache/save@v4") orelse return error.MissingSaveStep;
        try testing.expectEqualStrings("outcomes_restore", source.between(restore, "id: ", "\n").?);
        const first_run = std.mem.indexOf(u8, job, "\n        run:") orelse return error.MissingRunStep;
        const last_run = std.mem.lastIndexOf(u8, job, "\n        run:").?;
        try testing.expect(@intFromPtr(restore.ptr) < @intFromPtr(job.ptr) + first_run);
        try testing.expect(@intFromPtr(job.ptr) + last_run < @intFromPtr(save.ptr));
        try testing.expectEqualStrings(
            "!cancelled() && steps.outcomes_restore.outcome == 'success' && steps.outcomes_restore.outputs.cache-hit != 'true'",
            source.between(save, "if: ${{ ", " }}") orelse return error.MissingSaveCondition,
        );
        const paths = source.between(restore, "          path: |\n", "          key:") orelse return error.MissingRestorePaths;
        try testing.expectEqualStrings(paths, source.between(save, "          path: |\n", "          key:").?);
        try testing.expectEqualStrings("${{ steps.outcomes_restore.outputs.cache-primary-key }}", source.between(save, "          key: ", "\n").?);

        const lane = if (std.mem.eql(u8, job_name, "sanitize")) "-${{ matrix.sanitizer }}" else "";
        const prefix = try std.mem.concat(testing.allocator, u8, &.{ "outcomes-${{ github.job }}", lane, "-${{ runner.os }}-${{ hashFiles('flake.lock') }}-" });
        defer testing.allocator.free(prefix);
        const key = try std.mem.concat(testing.allocator, u8, &.{ prefix, "${{ github.sha }}-${{ github.run_id }}-${{ github.run_attempt }}" });
        defer testing.allocator.free(key);
        try testing.expectEqualStrings(key, source.between(restore, "          key: ", "\n").?);
        const expected_prefixes = try std.mem.concat(testing.allocator, u8, &.{ prefix, "${{ github.sha }}-\n            ", prefix });
        defer testing.allocator.free(expected_prefixes);
        const prefix_marker = "          restore-keys: |\n";
        const prefix_start = (std.mem.indexOf(u8, restore, prefix_marker) orelse return error.MissingRestorePrefixes) + prefix_marker.len;
        const prefix_tail = restore[prefix_start..];
        const prefixes = prefix_tail[0 .. std.mem.indexOf(u8, prefix_tail, "\n\n") orelse prefix_tail.len];
        try testing.expectEqualStrings(expected_prefixes, std.mem.trim(u8, prefixes, " \n"));
        // `check` also walks the recompilation properties and `optimised` also
        // runs the soundness step; each keeps its recorded outcomes in a
        // directory of its own beside the corpus's.
        const extra = if (std.mem.eql(u8, job_name, "check"))
            "\n            ${{ env.LINEA_SCRATCH }}-${{ github.job }}/properties/outcomes"
        else if (std.mem.eql(u8, job_name, "optimised"))
            "\n            ${{ env.LINEA_SCRATCH }}-${{ github.job }}/soundness/outcomes"
        else
            "";
        const expected_paths = try std.mem.concat(testing.allocator, u8, &.{
            "${{ env.LINEA_SCRATCH }}-${{ github.job }}", lane, "/outcomes\n            ",
            "${{ env.LINEA_SCRATCH }}-${{ github.job }}", lane, "/examples/outcomes",
            extra,
        });
        defer testing.allocator.free(expected_paths);
        try testing.expectEqualStrings(expected_paths, std.mem.trim(u8, paths, " \n"));
    }
}

fn outcomeStep(job: []const u8, action: []const u8) ?[]const u8 {
    var steps = std.mem.splitSequence(u8, job, "\n      - ");
    while (steps.next()) |step| if (std.mem.indexOf(u8, step, action) != null) return step;
    return null;
}

test "explicit release modes preserve their requested safety and size policy" {
    const Case = struct {
        release: std.Build.ReleaseMode,
        preferred: ?bool,
        want: std.builtin.OptimizeMode,
    };
    const cases = [_]Case{
        .{ .release = .off, .preferred = null, .want = .Debug },
        .{ .release = .off, .preferred = false, .want = .Debug },
        .{ .release = .off, .preferred = true, .want = .ReleaseFast },
        .{ .release = .any, .preferred = null, .want = .ReleaseFast },
        .{ .release = .any, .preferred = false, .want = .Debug },
        .{ .release = .any, .preferred = true, .want = .ReleaseFast },
        .{ .release = .safe, .preferred = null, .want = .ReleaseSafe },
        .{ .release = .safe, .preferred = false, .want = .ReleaseSafe },
        .{ .release = .safe, .preferred = true, .want = .ReleaseSafe },
        .{ .release = .fast, .preferred = null, .want = .ReleaseFast },
        .{ .release = .fast, .preferred = false, .want = .ReleaseFast },
        .{ .release = .fast, .preferred = true, .want = .ReleaseFast },
        .{ .release = .small, .preferred = null, .want = .ReleaseSmall },
        .{ .release = .small, .preferred = false, .want = .ReleaseSmall },
        .{ .release = .small, .preferred = true, .want = .ReleaseSmall },
    };
    for (cases) |case| try testing.expectEqual(case.want, test_roots.optimizeMode(case.release, case.preferred));
}

test "the unit tests run once, in the mode the build selects" {
    for (std.enums.values(std.builtin.OptimizeMode)) |optimize| {
        for ([_]bool{ false, true }) |filtered| {
            const roots = test_roots.select(.{ .optimize = optimize, .filtered = filtered });
            try testing.expectEqual(test_roots.Root.joined, roots.selected.?);
        }
    }
}

test "test suites keep compiler coverage disjoint from instrumented and fuzz runs" {
    const Case = struct {
        suite: test_roots.Suite,
        optimize: std.builtin.OptimizeMode,
        filtered: bool = false,
        want: test_roots.Selection,
    };
    const cases = [_]Case{
        .{ .suite = .full, .optimize = .Debug, .want = .{ .selected = .joined, .source = true, .corpus = true, .examples = true, .guide = true, .editor = true } },
        .{ .suite = .full, .optimize = .ReleaseSafe, .want = .{ .selected = .joined, .source = true, .corpus = true, .examples = true, .guide = true, .editor = true } },
        .{ .suite = .full, .optimize = .Debug, .filtered = true, .want = .{ .selected = .joined, .source = true, .corpus = false, .examples = false, .guide = false, .editor = false } },
        .{ .suite = .unit, .optimize = .ReleaseFast, .want = .{ .selected = .joined, .source = true, .corpus = false, .examples = false, .guide = false, .editor = false } },
        .{ .suite = .conformance, .optimize = .ReleaseFast, .want = .{ .selected = null, .source = false, .corpus = true, .examples = true, .guide = false, .editor = false } },
        .{ .suite = .conformance, .optimize = .Debug, .want = .{ .selected = null, .source = false, .corpus = true, .examples = true, .guide = false, .editor = false } },
        .{ .suite = .fuzz, .optimize = .ReleaseSafe, .want = .{ .selected = .fuzz, .source = false, .corpus = false, .examples = false, .guide = false, .editor = false } },
    };
    for (cases) |case| {
        const got = test_roots.select(.{ .suite = case.suite, .optimize = case.optimize, .filtered = case.filtered });
        try testing.expectEqualDeep(case.want, got);
        // A named scope keeps its inclusion boundary even when another target
        // in the same invocation uses the development filter.
        if (case.suite != .full) {
            try testing.expectEqualDeep(case.want, test_roots.select(.{ .suite = case.suite, .optimize = case.optimize, .filtered = true }));
        }
    }
}

test "conformance walks the directory it is given, or the whole corpus" {
    try testing.expectEqualDeep(test_roots.Walk.whole, try test_roots.walkOf(null));
    try testing.expectEqualDeep(test_roots.Walk.whole, try test_roots.walkOf(&.{}));
    try testing.expectEqualDeep(test_roots.Walk{ .narrowed = "tests/cmd/http_json_echo" }, try test_roots.walkOf(&.{"tests/cmd/http_json_echo"}));
    try testing.expectError(error.SeveralDirectories, test_roots.walkOf(&.{ "tests/decl", "tests/cmd" }));
}

test "test suites partition the full graph without omitting or repeating roots" {
    for (std.enums.values(std.builtin.OptimizeMode)) |optimize| {
        for ([_]bool{ false, true }) |filtered| {
            const full = test_roots.select(.{ .suite = .full, .optimize = optimize, .filtered = filtered });
            const corpus = test_roots.select(.{ .suite = .corpus, .optimize = optimize, .filtered = filtered });
            const support = test_roots.select(.{ .suite = .support, .optimize = optimize, .filtered = filtered });
            try testing.expectEqual(test_roots.Selection{
                .selected = null,
                .source = false,
                .corpus = !filtered,
                .examples = false,
                .guide = false,
                .editor = false,
            }, corpus);
            try testing.expect(!support.corpus);
            try testing.expectEqual(full.selected, support.selected);
            inline for (@typeInfo(test_roots.Selection).@"struct".fields) |field| {
                if (field.type == bool) {
                    const owners = @as(u8, @intFromBool(@field(corpus, field.name))) + @intFromBool(@field(support, field.name));
                    try testing.expectEqual(@as(u8, @intFromBool(@field(full, field.name))), owners);
                }
            }
        }
    }
}

test "test suites retain each CI compiler mode and runtime instrumentation once" {
    const Lane = struct {
        suite: test_roots.Suite,
        optimize: std.builtin.OptimizeMode,
        instrumentation: enum { none, address } = .none,
    };
    const lanes = [_]Lane{
        .{ .suite = .corpus, .optimize = .Debug },
        .{ .suite = .support, .optimize = .Debug },
        .{ .suite = .unit, .optimize = .ReleaseFast },
        .{ .suite = .conformance, .optimize = .ReleaseFast },
        .{ .suite = .conformance, .optimize = .ReleaseSafe, .instrumentation = .address },
        .{ .suite = .fuzz, .optimize = .ReleaseSafe },
    };
    var joined: [4]u8 = @splat(0);
    var build_source: [4]u8 = @splat(0);
    var corpus: [2][4]u8 = @splat(@splat(0));
    var examples: [2][4]u8 = @splat(@splat(0));
    var editor: u8 = 0;
    var fuzz: u8 = 0;
    for (lanes) |lane| {
        const selected = test_roots.select(.{ .suite = lane.suite, .optimize = lane.optimize, .filtered = false });
        const mode = @intFromEnum(lane.optimize);
        if (selected.selected) |root| switch (root) {
            .joined => joined[mode] += 1,
            .fuzz => fuzz += 1,
        };
        if (selected.source) build_source[mode] += 1;
        if (selected.corpus) corpus[@intFromEnum(lane.instrumentation)][mode] += 1;
        if (selected.examples) examples[@intFromEnum(lane.instrumentation)][mode] += 1;
        if (selected.editor) editor += 1;
    }
    try testing.expectEqualSlices(u8, &.{ 1, 0, 1, 0 }, &joined);
    try testing.expectEqualSlices(u8, &.{ 1, 0, 1, 0 }, &build_source);
    const runtimes = [2][4]u8{ .{ 1, 0, 1, 0 }, .{ 0, 1, 0, 0 } };
    try testing.expectEqualDeep(runtimes, corpus);
    try testing.expectEqualDeep(runtimes, examples);
    try testing.expectEqual(@as(u8, 1), editor);
    try testing.expectEqual(@as(u8, 1), fuzz);
}

test "a name is counted where it stands alone" {
    // A count of a name and not of every name holding it: the gate reading this
    // decides whether a declaration is dead, and `foo` inside `foobar` is a
    // different declaration entirely.
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const counts = source.wordCounts(arena.allocator(), "foo foobar barfoo _foo foo_ aa aa");
    try testing.expectEqual(@as(?u32, 1), counts.get("foo"));
    try testing.expectEqual(@as(?u32, 2), counts.get("aa"));
    try testing.expectEqual(@as(?u32, null), counts.get("bar"));
    try testing.expectEqual(@as(?u32, 1), source.wordCounts(arena.allocator(), "foo").get("foo"));
}

test "a private declaration is one at column zero without pub" {
    try testing.expectEqualStrings("thing", source.privateDeclaration("fn thing(a: u8) void {").?);
    try testing.expectEqualStrings("x", source.privateDeclaration("const x = 1;").?);
    try testing.expectEqualStrings("Numbers", source.privateDeclaration("const Numbers = struct {").?);

    // A `pub` declaration is reachable from outside the file, so the file
    // cannot answer for whether anything names it.
    try testing.expectEqual(@as(?[]const u8, null), source.privateDeclaration("pub fn thing() void {"));
    try testing.expectEqual(@as(?[]const u8, null), source.privateDeclaration("    fn nested() void {"));
    try testing.expectEqual(@as(?[]const u8, null), source.privateDeclaration("fn ("));
    try testing.expectEqual(@as(?[]const u8, null), source.privateDeclaration("constant = 5"));
    try testing.expectEqual(@as(?[]const u8, null), source.privateDeclaration(""));
}

test "a comptime block is the first one, and only a whole line opens it" {
    const named =
        \\const std = @import("std");
        \\
        \\comptime {
        \\    _ = @import("a.zig");
        \\}
        \\
        \\pub fn main() void {}
        \\
    ;
    try testing.expectEqualStrings("    _ = @import(\"a.zig\");", source.comptimeBlock(named));

    try testing.expectEqualStrings("", source.comptimeBlock("const a = 1;\n"));

    // The opener carries its own newline, so a file whose very first bytes are
    // the block has none in front of it and states nothing.
    try testing.expectEqualStrings("", source.comptimeBlock("comptime {\n    _ = @import(\"a.zig\");\n}\n"));

    // Unterminated, which is what a truncated file looks like: what is there is
    // read rather than nothing, so a name inside it still counts as named.
    try testing.expectEqualStrings("    _ = x;\n", source.comptimeBlock("\ncomptime {\n    _ = x;\n"));
}

test "a container holding tests is reached only where a comptime block names it" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const text =
        \\const std = @import("std");
        \\
        \\pub const Named = struct {
        \\    x: u8,
        \\    test "reached" {}
        \\};
        \\
        \\const Outer = struct {
        \\    const Inner = union(enum) {
        \\        a,
        \\        test "unreached, nested twice" {}
        \\    };
        \\};
        \\
        \\const Quiet = struct {
        \\    const source = "{ test \"not a test\" {} }";
        \\};
        \\
        \\const Loud = enum {
        \\    a,
        \\    test "unreached" {}
        \\};
        \\
        \\test "at file level" {}
        \\
        \\fn Built(comptime T: type) type {
        \\    return struct {
        \\        value: T,
        \\        test "unreached, no name reaches it" {}
        \\    };
        \\}
        \\
        \\comptime {
        \\    _ = Named;
        \\}
        \\
    ;
    const unreached = source.unreachedNestedTests(gpa, text);
    try testing.expectEqual(@as(usize, 3), unreached.len);
    try testing.expectEqualStrings("Outer.Inner", unreached[0]);
    try testing.expectEqualStrings("Loud", unreached[1]);
    try testing.expectEqualStrings("a container no name reaches, line 29", unreached[2]);

    const all_named = text ++
        \\comptime {
        \\    _ = Outer.Inner;
        \\    _ = Loud;
        \\}
        \\
    ;
    const still = source.unreachedNestedTests(gpa, all_named);
    try testing.expectEqual(@as(usize, 1), still.len);
    try testing.expectEqualStrings("a container no name reaches, line 29", still[0]);
}

test "an import is resolved against the file that writes it" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const up: source.SourceFile = .{
        .path = "sema/types.zig",
        .text = "const node = @import(\"../syntax/node.zig\");\n",
    };
    try testing.expect(source.importsPath(gpa, up, "syntax/node.zig"));
    try testing.expect(!source.importsPath(gpa, up, "sema/node.zig"));

    const beside: source.SourceFile = .{
        .path = "mir/lower.zig",
        .text = "const mir = @import(\"mir.zig\");\n",
    };
    try testing.expect(source.importsPath(gpa, beside, "mir/mir.zig"));

    const root: source.SourceFile = .{
        .path = "main.zig",
        .text = "const driver = @import(\"driver/driver.zig\");\n",
    };
    try testing.expect(source.importsPath(gpa, root, "driver/driver.zig"));

    // `src/` holds three `dump.zig`, so the answer is about a path and never
    // about the name a file ends with.
    const ambiguous: source.SourceFile = .{
        .path = "mir/lower.zig",
        .text = "const dump = @import(\"dump.zig\");\n",
    };
    try testing.expect(source.importsPath(gpa, ambiguous, "mir/dump.zig"));
    try testing.expect(!source.importsPath(gpa, ambiguous, "syntax/dump.zig"));

    // A package rather than a file of this compiler, which names nothing here.
    const package: source.SourceFile = .{
        .path = "lsp/server.zig",
        .text = "const std = @import(\"std\");\nconst lsp = @import(\"lsp\");\n",
    };
    try testing.expect(!source.importsPath(gpa, package, "std"));
    try testing.expect(!source.importsPath(gpa, package, "lsp"));

    const truncated: source.SourceFile = .{
        .path = "a.zig",
        .text = "const b = @import(\"b.zig",
    };
    try testing.expect(!source.importsPath(gpa, truncated, "b.zig"));
}

test "a joined test root imports exactly its manifests" {
    const files = [_]source.SourceFile{
        .{
            .path = "test_main.zig",
            .text =
            \\const ignored = @import("extra.zig");
            \\
            \\comptime {
            \\    _ = @import("main.zig");
            \\    _ = @import("conformance_main.zig");
            \\}
            ,
        },
        .{ .path = "main.zig", .text = "" },
        .{ .path = "conformance_main.zig", .text = "" },
        .{ .path = "extra.zig", .text = "" },
    };
    const wanted = [_][]const u8{ "main.zig", "conformance_main.zig" };
    try testing.expect(source.importsExactly(testing.allocator, files[0], &wanted, &files));

    const missing = source.SourceFile{
        .path = "test_main.zig",
        .text =
        \\comptime {
        \\    _ = @import("main.zig");
        \\}
        ,
    };
    try testing.expect(!source.importsExactly(testing.allocator, missing, &wanted, &files));

    const extra = source.SourceFile{
        .path = "test_main.zig",
        .text =
        \\comptime {
        \\    _ = @import("main.zig");
        \\    _ = @import("conformance_main.zig");
        \\    _ = @import("extra.zig");
        \\}
        ,
    };
    try testing.expect(!source.importsExactly(testing.allocator, extra, &wanted, &files));
}

test "a marker names the text up to what closes it" {
    try testing.expectEqualStrings(
        "address, thread, memory",
        source.between("        sanitizer: [address, thread, memory]\n", "sanitizer: [", "]").?,
    );
    try testing.expectEqualStrings(
        "4",
        source.between("const indent_width = 4;\n", "const indent_width = ", ";").?,
    );
    try testing.expectEqual(
        @as(?[]const u8, null),
        source.between("nothing here\n", "sanitizer: [", "]"),
    );

    // Nothing closes it, which is a malformed file. Empty rather than the rest
    // of it: half a document read as a value is worse than no value.
    try testing.expectEqualStrings("", source.between("const indent_width = 4\n", "const indent_width = ", ";").?);
}

test "a value is closed by whatever spells the end of it, however long" {
    try testing.expectEqualStrings(
        " 4 ",
        source.between("width = /* 4 */ 8\n", "/*", "*/").?,
    );

    // The end is sought after the whole of the start, so a document whose
    // delimiters share bytes reads the value between them rather than an
    // overlap of the two.
    try testing.expectEqualStrings(
        "linea",
        source.between("<<name>>linea<<name>>\n", "<<name>>", "<<name>>").?,
    );

    try testing.expectEqualStrings("", source.between("/* 4\n", "/*", "*/").?);
}

test "the longer relation wins over the one spelled inside it" {
    // `refined by` holds `refine`: taking the shorter reads "refined by 0051"
    // as "refines 0051" and demands the reciprocal of a relation nobody wrote.
    const found = source.findRelation("Refined by 0051", 0).?;
    try testing.expectEqualStrings("refined by", found.says);
    try testing.expectEqualStrings("refines", found.back);

    const other = source.findRelation("Superseded by 0042", 0).?;
    try testing.expectEqualStrings("superseded by", other.says);
    try testing.expectEqualStrings("supersedes", other.back);

    try testing.expectEqual(@as(?source.Relation, null), source.findRelation("Accepted", 0));
}

test "a relation reaches to the next one, and the prose between is not a relation" {
    const found = source.findRelation("Superseded by the exclusivity clause of 0025", 0).?;
    var targets: source.Numbers = .{ .rest = found.targets };
    try testing.expectEqualStrings("0025", targets.next().?);
    try testing.expectEqual(@as(?[]const u8, null), targets.next());

    // Two relations in one status: each owns the numbers before the next.
    const status = "Supersedes 0010, refined by 0020";
    const first = source.findRelation(status, 0).?;
    try testing.expectEqualStrings("supersedes", first.says);
    var mine: source.Numbers = .{ .rest = first.targets };
    try testing.expectEqualStrings("0010", mine.next().?);
    try testing.expectEqual(@as(?[]const u8, null), mine.next());

    const second = source.findRelation(status, first.after).?;
    try testing.expectEqualStrings("refined by", second.says);
    var theirs: source.Numbers = .{ .rest = second.targets };
    try testing.expectEqualStrings("0020", theirs.next().?);
}

test "a relation is stated about every record it names" {
    try testing.expect(source.statesRelation("Extends 0029 and 0055", "extends", "0029"));
    try testing.expect(source.statesRelation("Extends 0029 and 0055", "extends", "0055"));
    try testing.expect(!source.statesRelation("Extends 0029 and 0055", "extends", "0030"));
    try testing.expect(!source.statesRelation("Extends 0029", "refines", "0029"));
    try testing.expect(!source.statesRelation("Accepted", "extends", "0029"));
}

test "a four-digit run is a record number" {
    var two: source.Numbers = .{ .rest = "0029 and 0055" };
    try testing.expectEqualStrings("0029", two.next().?);
    try testing.expectEqualStrings("0055", two.next().?);
    try testing.expectEqual(@as(?[]const u8, null), two.next());

    var none: source.Numbers = .{ .rest = "no records here" };
    try testing.expectEqual(@as(?[]const u8, null), none.next());

    var short: source.Numbers = .{ .rest = "123" };
    try testing.expectEqual(@as(?[]const u8, null), short.next());
}

test "an index row is a bracketed number and the standing beside it" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const text =
        \\# Decisions
        \\
        \\| Number | Title | Status |
        \\| --- | --- | --- |
        \\| [0025](0025-a.md) | A | Superseded by 0042 |
        \\| [0042](0042-b.md) | B | Supersedes 0025 |
        \\
        \\Prose that is not a row.
        \\
    ;
    const rows = source.indexRows(gpa, text);
    try testing.expectEqual(@as(usize, 2), rows.len);
    try testing.expectEqualStrings("0025", rows[0].number);
    try testing.expectEqualStrings("Superseded by 0042", rows[0].status);
    try testing.expectEqualStrings("0042", rows[1].number);
    try testing.expectEqualStrings("Supersedes 0025", rows[1].status);
}

test "a number two records claim is named, and a number one record claims is not" {
    // A duplicate is not a cosmetic clash. Every gate resolving a number takes
    // the first row carrying it, so the second row answers for a record that
    // never claimed the relation -- and the relation gate then reports a
    // disagreement between two records that do not refer to each other at all,
    // which names neither the duplicate nor the record that lost.
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const claimed_twice =
        \\| [0009](0009-a.md) | A | Accepted |
        \\| [0097](0097-b.md) | B | Accepted; extends 0009 |
        \\| [0097](0097-c.md) | C | Accepted; extends 0009 |
        \\
    ;
    try testing.expectEqualStrings(
        "0097",
        source.numberClaimedTwice(gpa, source.indexRows(gpa, claimed_twice)).?,
    );

    const each_its_own =
        \\| [0009](0009-a.md) | A | Accepted |
        \\| [0097](0097-b.md) | B | Accepted; extends 0009 |
        \\| [0100](0100-c.md) | C | Accepted; extends 0009 |
        \\
    ;
    try testing.expectEqual(
        @as(?[]const u8, null),
        source.numberClaimedTwice(gpa, source.indexRows(gpa, each_its_own)),
    );
}

/// A conformance runner in miniature: an enum of properties, a call that counts
/// each one, and the loop that reports them and checks them against the corpus.
///
/// Written out rather than read from the runner, because a case that reads the
/// file the gate reads passes for whatever that file happens to say and can
/// never state the failing shape at all.
const accounting_runner =
    \\const Property = enum {
    \\    formatting,
    \\    /// A name reaches a binding the scope makes visible.
    \\    names_in_scope,
    \\
    \\    fn floor(self: Property) u32 {
    \\        return switch (self) {
    \\            .formatting => 350,
    \\            .names_in_scope => 300,
    \\        };
    \\    }
    \\};
    \\
    \\fn run() void {
    \\    tally(&w.properties, &w.passed_over, .formatting, true);
    \\    tally(properties, passed_over, .names_in_scope, false);
    \\
    \\    for (std.enums.values(Property)) |q| {
    \\        std.debug.print("conformance: {d} checked that {s}\n", .{ reached, q.why() });
    \\        if (!q.accountsFor(corpus, reached, declined)) fail();
    \\    }
    \\}
    \\
;

test "a property is accounted for where a call counts it" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const accounted = source.accountingOf(gpa, accounting_runner, "Property", "tally");
    try testing.expectEqual(@as(usize, 2), accounted.declared);
    try testing.expectEqual(@as(usize, 0), accounted.uncounted.len);
    try testing.expect(source.reportsAndAccounts(gpa, accounting_runner, "Property", "conformance:", "accountsFor"));
}

test "a property counted by a variable of its own is accounted for by nothing" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    // The shape every one of these defects had: a check with a counter beside
    // it and a line reporting the number, and no population the number is
    // compared against.
    const counting =
        \\const Property = enum {
        \\    formatting,
        \\    trait_members,
        \\};
        \\
        \\fn run() void {
        \\    tally(&w.properties, &w.passed_over, .formatting, true);
        \\    if (checkTraitMembers()) traits_asked += 1;
        \\    std.debug.print("conformance: {d} trait(s) checked\n", .{traits_asked});
        \\
        \\    for (std.enums.values(Property)) |q| {
        \\        std.debug.print("conformance: {d} checked that {s}\n", .{ reached, q.why() });
        \\        if (!q.accountsFor(corpus, reached, declined)) fail();
        \\    }
        \\}
        \\
    ;

    const accounted = source.accountingOf(gpa, counting, "Property", "tally");
    try testing.expectEqual(@as(usize, 2), accounted.declared);
    try testing.expectEqual(@as(usize, 1), accounted.uncounted.len);
    try testing.expectEqualStrings("trait_members", accounted.uncounted[0]);
}

test "a run that reports a property and checks it against nothing accounts for none" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    // The counts still printed, and the equality gone. Every property is
    // tallied, so the names alone say nothing is wrong.
    const unchecked =
        \\const Property = enum {
        \\    formatting,
        \\};
        \\
        \\fn run() void {
        \\    tally(&w.properties, &w.passed_over, .formatting, true);
        \\
        \\    for (std.enums.values(Property)) |q| {
        \\        std.debug.print("conformance: {d} checked that {s}\n", .{ reached, q.why() });
        \\    }
        \\}
        \\
    ;
    try testing.expectEqual(@as(usize, 0), source.accountingOf(gpa, unchecked, "Property", "tally").uncounted.len);
    try testing.expect(!source.reportsAndAccounts(gpa, unchecked, "Property", "conformance:", "accountsFor"));

    // Nothing reports the properties at all, which is the same silence read
    // from the other end: an enum renamed, or a loop deleted, leaves a gate
    // that passes over a file it no longer understands.
    try testing.expect(!source.reportsAndAccounts(gpa, "fn run() void {}\n", "Property", "conformance:", "accountsFor"));
}

test "an enum declares the names it lists, and nothing else written between them" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    // A doc comment, a method and the prongs of a switch inside it are all
    // written differently from a member, which is what makes the count a count
    // of what the enum offers.
    const accounted = source.accountingOf(gpa, accounting_runner, "Property", "tally");
    try testing.expectEqual(@as(usize, 2), accounted.declared);

    // An enum the file does not declare. Nothing declared is what the gate
    // reads as the runner having been renamed under it.
    try testing.expectEqual(@as(usize, 0), source.accountingOf(gpa, accounting_runner, "Mutation", "tally").declared);
}

test "a call names a literal where the literal is an argument of it" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    // A dot inside `&w.passed_over` begins no literal, and the one this call
    // names is written after the arguments that carry the counts.
    const spread =
        \\const Property = enum {
        \\    parameter_hints,
        \\};
        \\
        \\fn run() void {
        \\    tally(
        \\        &w.properties,
        \\        &w.passed_over,
        \\        .parameter_hints,
        \\        true,
        \\    );
        \\}
        \\
    ;
    try testing.expectEqual(@as(usize, 0), source.accountingOf(gpa, spread, "Property", "tally").uncounted.len);

    // A call whose statement ends before any literal is written, and a name
    // this one only begins with: neither counts the property.
    const neither =
        \\const Property = enum {
        \\    parameter_hints,
        \\};
        \\
        \\fn run() void {
        \\    tally(counts, declined, q, true);
        \\    tallyTwice(&w.properties, &w.passed_over, .parameter_hints, true);
        \\}
        \\
    ;
    try testing.expectEqual(@as(usize, 1), source.accountingOf(gpa, neither, "Property", "tally").uncounted.len);
}

test "a block is what stands indented under the line that opens it" {
    const text =
        \\fn run() void {
        \\    for (values) |q| {
        \\        one();
        \\
        \\        two();
        \\    }
        \\    after();
        \\}
        \\
    ;
    const at = std.mem.indexOf(u8, text, "for (values)").?;
    const body = source.indentedUnder(text, at);
    try testing.expect(std.mem.indexOf(u8, body, "one();") != null);
    try testing.expect(std.mem.indexOf(u8, body, "two();") != null);
    try testing.expect(std.mem.indexOf(u8, body, "after();") == null);

    // A blank line is part of the block it sits in rather than the end of it,
    // and a line that opens nothing has nothing under it.
    const last = std.mem.indexOf(u8, text, "after();").?;
    try testing.expectEqualStrings("", source.indentedUnder(text, last));
}

test "the source of a tree is every zig file beneath it, in one order" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const io = testing.io;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.createDirPath(io, "src/sema");
    try tmp.dir.writeFile(io, .{ .sub_path = "src/main.zig", .data = "const a = 1;\n" });
    try tmp.dir.writeFile(io, .{ .sub_path = "src/sema/types.zig", .data = "const b = 2;\n" });
    try tmp.dir.writeFile(io, .{ .sub_path = "src/notes.txt", .data = "not source\n" });

    const files = source.compilerSource(gpa, io, tmp.dir, "src");
    try testing.expectEqual(@as(usize, 2), files.len);
    try testing.expectEqualStrings("main.zig", files[0].path);
    try testing.expectEqualStrings("const a = 1;\n", files[0].text);
    try testing.expectEqualStrings("sema/types.zig", files[1].path);
    try testing.expectEqualStrings("const b = 2;\n", files[1].text);
}

test "example roots: every example and every nested manifest is a root" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const found = source.exampleRoots(gpa, &.{
        .{ .path = "README.md", .directory = false },
        .{ .path = "hello.lin", .directory = false },
        .{ .path = "discounts", .directory = true },
        .{ .path = "discounts/linea.json", .directory = false },
        .{ .path = "discounts/main.lin", .directory = false },
        .{ .path = "discounts/mail", .directory = true },
        .{ .path = "discounts/mail/send.lin", .directory = false },
        .{ .path = "guest-book", .directory = true },
        .{ .path = "guest-book/linea.json", .directory = false },
        .{ .path = "guest-book/sqlite", .directory = true },
        .{ .path = "guest-book/sqlite/linea.json", .directory = false },
        .{ .path = "guest-book/sqlite/deep", .directory = true },
        .{ .path = "loose", .directory = true },
        .{ .path = "loose/main.lin", .directory = false },
    });
    try testing.expectEqual(@as(usize, 5), found.len);
    try testing.expectEqualStrings("discounts", found[0]);
    try testing.expectEqualStrings("guest-book", found[1]);
    try testing.expectEqualStrings("guest-book/sqlite", found[2]);
    try testing.expectEqualStrings("hello.lin", found[3]);
    try testing.expectEqualStrings("loose", found[4]);
}

test "example roots: a symlink under examples is refused by name" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const io = testing.io;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.createDirPath(io, "elsewhere");
    try tmp.dir.createDirPath(io, "examples");
    try tmp.dir.writeFile(io, .{ .sub_path = "elsewhere/main.lin", .data = "fn main() {}\n" });
    try tmp.dir.symLink(io, "../elsewhere", "examples/linked", .{ .is_directory = true });

    const layout = try source.exampleLayout(gpa, io, tmp.dir, "examples");
    try testing.expectEqualStrings("linked", layout.symlink);
}

test "example roots: the walk lists nested directories and files and nothing else" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const io = testing.io;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.createDirPath(io, "examples/guest-book/sqlite");
    try tmp.dir.writeFile(io, .{ .sub_path = "examples/hello.lin", .data = "fn main() {}\n" });
    try tmp.dir.writeFile(io, .{ .sub_path = "examples/guest-book/sqlite/linea.json", .data = "{}" });

    const layout = try source.exampleLayout(gpa, io, tmp.dir, "examples");
    const roots = source.exampleRoots(gpa, layout.entries);
    try testing.expectEqual(@as(usize, 3), roots.len);
    try testing.expectEqualStrings("guest-book", roots[0]);
    try testing.expectEqualStrings("guest-book/sqlite", roots[1]);
    try testing.expectEqualStrings("hello.lin", roots[2]);
}

test "example roots: a source no root reaches belongs to no example root" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    // The same manifest text and directories as the loader's test "a manifest's
    // source key narrows the files a root reaches", which must agree.
    const entries = [_]source.ExampleEntry{
        .{ .path = "hello.lin", .directory = false },
        .{ .path = "app", .directory = true },
        .{ .path = "app/linea.json", .directory = false, .text = "{\"source\": \"./src/\"}" },
        .{ .path = "app/src/main.lin", .directory = false },
        .{ .path = "app/src/deep/part.lin", .directory = false },
        .{ .path = "app/stray.lin", .directory = false },
        .{ .path = "app/lib", .directory = true },
        .{ .path = "app/lib/linea.json", .directory = false, .text = "{}" },
        .{ .path = "app/lib/main.lin", .directory = false },
        .{ .path = "flat", .directory = true },
        .{ .path = "flat/main.lin", .directory = false },
        .{ .path = "flat/mail/send.lin", .directory = false },
    };
    const roots = source.exampleRoots(gpa, &entries);
    const stray = source.unreachedSources(gpa, &entries, roots);
    try testing.expectEqual(@as(usize, 0), stray.problems.len);
    try testing.expectEqual(@as(usize, 1), stray.files.len);
    try testing.expectEqualStrings("app/stray.lin", stray.files[0]);
}

test "example roots: a file named like a manifest is not the manifest" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const entries = [_]source.ExampleEntry{
        .{ .path = "app", .directory = true },
        .{ .path = "app/alinea.json", .directory = false },
        .{ .path = "app/linea.json", .directory = false, .text = "{\"source\": \"src\"}" },
        .{ .path = "app/src/main.lin", .directory = false },
        .{ .path = "app/stray.lin", .directory = false },
    };
    const roots = source.exampleRoots(gpa, &entries);
    const stray = source.unreachedSources(gpa, &entries, roots);
    try testing.expectEqual(@as(usize, 0), stray.problems.len);
    try testing.expectEqual(@as(usize, 1), stray.files.len);
    try testing.expectEqualStrings("app/stray.lin", stray.files[0]);
}

test "example roots: a source that leaves its root, and a manifest that is not JSON, are named" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    // The spellings of the loader's test "a manifest's source stays inside the
    // directory holding it".
    const entries = [_]source.ExampleEntry{
        .{ .path = "up", .directory = true },
        .{ .path = "up/linea.json", .directory = false, .text = "{\"source\": \"../d\"}" },
        .{ .path = "up/main.lin", .directory = false },
        .{ .path = "climbs", .directory = true },
        .{ .path = "climbs/linea.json", .directory = false, .text = "{\"source\": \"src/../../x\"}" },
        .{ .path = "absolute", .directory = true },
        .{ .path = "absolute/linea.json", .directory = false, .text = "{\"source\": \"/tmp\"}" },
        .{ .path = "inside", .directory = true },
        .{ .path = "inside/linea.json", .directory = false, .text = "{\"source\": \"src/../lib\"}" },
        .{ .path = "inside/lib/main.lin", .directory = false },
        .{ .path = "broken", .directory = true },
        .{ .path = "broken/linea.json", .directory = false, .text = "{\"source\": " },
        .{ .path = "broken/main.lin", .directory = false },
    };
    const roots = source.exampleRoots(gpa, &entries);
    const found = source.unreachedSources(gpa, &entries, roots);
    try testing.expectEqual(@as(usize, 0), found.files.len);
    try testing.expectEqual(@as(usize, 4), found.problems.len);
    try testing.expectEqualStrings("absolute/linea.json names a source, \"/tmp\", outside its directory", found.problems[0]);
    try testing.expectEqualStrings("broken/linea.json is not valid JSON", found.problems[1]);
    try testing.expectEqualStrings("climbs/linea.json names a source, \"src/../../x\", outside its directory", found.problems[2]);
    try testing.expectEqualStrings("up/linea.json names a source, \"../d\", outside its directory", found.problems[3]);
}

test "example roots: the tests a run reported are read from its closing line" {
    try testing.expectEqual(@as(?usize, 3), source.testsReported("ok    a\n\n3 passed, 0 failed\n"));
    try testing.expectEqual(@as(?usize, 0), source.testsReported("0 passed, 0 failed\n"));
    try testing.expectEqual(@as(?usize, 5), source.testsReported("x\n4 passed, 1 failed"));
    try testing.expectEqual(@as(?usize, null), source.testsReported("error[N-Undefined]: no such name\n"));
    try testing.expectEqual(@as(?usize, null), source.testsReported(""));
}

test "the quoted strings of a text are read in order" {
    const gpa = testing.allocator;
    const rows =
        \\    .{ .name = "Index", .args = &.{.{ .primitive = .u64 }} },
        \\    .{ .name = "Index", .args = &.{.{ .prelude = "FromEnd" }} },
    ;
    const found = source.quotedIn(gpa, rows);
    defer gpa.free(found);

    try testing.expectEqual(@as(usize, 3), found.len);
    try testing.expectEqualStrings("Index", found[0]);
    try testing.expectEqualStrings("Index", found[1]);
    try testing.expectEqualStrings("FromEnd", found[2]);
}

test "a text with nothing quoted holds no names" {
    const gpa = testing.allocator;

    // An opening quote nothing closes is not half a name: a file that ends
    // mid-literal is malformed, and the tail of it read as one is worse than
    // reading none.
    for ([_][]const u8{ "", "no quotes here", "\"unclosed" }) |text| {
        const found = source.quotedIn(gpa, text);
        defer gpa.free(found);
        try testing.expectEqual(@as(usize, 0), found.len);
    }
}

test "the names a table lists are read from its first column after the marker" {
    const gpa = testing.allocator;
    const text =
        \\| `Str` | not this table |
        \\
        \\**The core vocabulary** is the second group:
        \\
        \\| Name | Declared in |
        \\| --- | --- |
        \\| `Release` | `std.release` |
        \\| `Vec` | `std.mem` |
        \\
        \\| `After` | a later table |
    ;
    const found = source.tableNamesAfter(gpa, text, "**The core vocabulary**");
    defer gpa.free(found);

    try testing.expectEqual(@as(usize, 2), found.len);
    try testing.expectEqualStrings("Release", found[0]);
    try testing.expectEqualStrings("Vec", found[1]);
}

test "a marker with no table after it lists no names" {
    const gpa = testing.allocator;
    for ([_][]const u8{ "", "**The core vocabulary** and no table", "no marker\n| `Str` | x |" }) |text| {
        const found = source.tableNamesAfter(gpa, text, "**The core vocabulary**");
        defer gpa.free(found);
        try testing.expectEqual(@as(usize, 0), found.len);
    }
}

test "what a call was given is read from that call's own line" {
    const calls =
        \\    const a = preludeDecl(ast, res, "Option");
        \\    const b = preludeDecl(ast, res, name) orelse return null;
        \\    const c = preludeDecl(ast, res, "Str");
    ;
    const first = std.mem.indexOf(u8, calls, "preludeDecl(").?;
    try testing.expectEqualStrings("Option", source.quotedOnLine(calls, first).?);

    // A call handed a variable names nothing, and the answer is nothing rather
    // than the literal some later call was given -- a wrong name reads as a
    // gate that works.
    const second = std.mem.indexOfPos(u8, calls, first + 1, "preludeDecl(").?;
    try testing.expectEqual(@as(?[]const u8, null), source.quotedOnLine(calls, second));

    const third = std.mem.indexOfPos(u8, calls, second + 1, "preludeDecl(").?;
    try testing.expectEqualStrings("Str", source.quotedOnLine(calls, third).?);
}

const io_header =
    \\enum linea_io_category {
    \\    LINEA_IO_OTHER = 0,
    \\    LINEA_IO_NOT_FOUND = 1,
    \\    LINEA_IO_TIMED_OUT = 2
    \\};
;
const io_std =
    \\pub enum IoCategory {
    \\    Other,
    \\    NotFound,
    \\    NoProgress,
    \\    TimedOut,
    \\}
    \\let category: IoCategory = match linea_io_category(code) {
    \\    1 => .NotFound,
    \\    2 => .TimedOut,
    \\    _ => .Other,
    \\}
;

test "io categories the runtime numbers and std reads agree" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const found = source.ioCategoryDisagreements(arena.allocator(), io_header, io_std);
    try testing.expectEqual(@as(usize, 0), found.len);
}

test "an io category numbered differently on the two sides is reported" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    // The runtime renumbers a category.
    const renumbered = std.mem.replaceOwned(u8, gpa, io_header, "TIMED_OUT = 2", "TIMED_OUT = 3") catch unreachable;
    try testing.expect(source.ioCategoryDisagreements(gpa, renumbered, io_std).len > 0);

    // The runtime gains a category std never maps: it would read as Other.
    const grown = std.mem.replaceOwned(u8, gpa, io_header, "TIMED_OUT = 2", "TIMED_OUT = 2,\n    LINEA_IO_NO_SPACE = 3") catch unreachable;
    try testing.expect(source.ioCategoryDisagreements(gpa, grown, io_std).len > 0);

    // Std swaps two arms.
    const swapped = std.mem.replaceOwned(u8, gpa, io_std, "1 => .NotFound", "1 => .TimedOut") catch unreachable;
    try testing.expect(source.ioCategoryDisagreements(gpa, io_header, swapped).len > 0);

    // Std keeps an arm for a number the runtime dropped.
    const stale = std.mem.replaceOwned(u8, gpa, io_std, "_ => .Other", "7 => .Other,\n    _ => .Other") catch unreachable;
    try testing.expect(source.ioCategoryDisagreements(gpa, io_header, stale).len > 0);

    // Std drops the member a category maps to.
    const dropped = std.mem.replaceOwned(u8, gpa, io_std, "    TimedOut,\n}\nlet", "}\nlet") catch unreachable;
    try testing.expect(source.ioCategoryDisagreements(gpa, io_header, dropped).len > 0);

    // A text without the shape the gate reads is a disagreement, not a pass.
    try testing.expect(source.ioCategoryDisagreements(gpa, "", io_std).len > 0);
    try testing.expect(source.ioCategoryDisagreements(gpa, io_header, "").len > 0);
}

/// A runtime function as its source declares it.
const Declared = struct {
    symbol: []const u8,
    parameters: []const runtime_symbols.Parameter,
    result: runtime_symbols.Scalar,
};

/// The scalar a C or Zig type spells, and whether it is passed through a
/// pointer the callee writes. Null for a spelling the table has no scalar for.
fn scalarOf(written: []const u8) ?runtime_symbols.Parameter {
    const t = std.mem.trim(u8, written, " \t\n");
    const Spelling = struct { []const u8, runtime_symbols.Parameter };
    const spellings = [_]Spelling{
        .{ "uint8_t", .{ .scalar = .u8 } },
        .{ "int", .{ .scalar = .i32 } },
        .{ "long", .{ .scalar = .i64 } },
        .{ "unsigned long", .{ .scalar = .u64 } },
        .{ "double", .{ .scalar = .f64 } },
        .{ "const char *", .{ .scalar = .ptr } },
        .{ "char **", .{ .scalar = .ptr } },
        .{ "void", .{ .scalar = .unit } },
        .{ "u8", .{ .scalar = .u8 } },
        .{ "i32", .{ .scalar = .i32 } },
        .{ "i64", .{ .scalar = .i64 } },
        .{ "u64", .{ .scalar = .u64 } },
        .{ "f64", .{ .scalar = .f64 } },
        .{ "*u64", .{ .scalar = .u64, .passing = .inout } },
        .{ "*i64", .{ .scalar = .i64, .passing = .inout } },
        .{ "unsigned long *", .{ .scalar = .u64, .passing = .inout } },
        .{ "long *", .{ .scalar = .i64, .passing = .inout } },
    };
    for (spellings) |s| if (std.mem.eql(u8, s[0], t)) return s[1];
    return null;
}

/// Why a runtime source could not be read as declarations, naming the symbol.
const Unread = struct { symbol: []const u8, why: []const u8 };

/// Every `linea_` function a runtime source defines or declares: C
/// prototypes and definitions and Zig `export fn`s, written at the start of a
/// line. A `static` C function is private to its file and is not one. A
/// declaration of a function the compiler owns is read like any other and
/// held to `owned_functions`. Any `linea_` name at the start of
/// a declaration whose shape or types this cannot read is returned as
/// unread rather than skipped: a runtime function the table cannot be held to
/// is a failure, not an omission.
fn declaredIn(gpa: std.mem.Allocator, text: []const u8, out: *std.ArrayList(Declared), unread: *std.ArrayList(Unread)) !void {
    var at: usize = 0;
    while (std.mem.indexOfPos(u8, text, at, "linea_")) |found| {
        at = found + 1;
        const line_start = if (std.mem.lastIndexOfScalar(u8, text[0..found], '\n')) |n| n + 1 else 0;
        const head = text[line_start..found];
        // Indented, or inside a comment: a use or a description, not a
        // declaration.
        if (head.len > 0 and (head[0] == ' ' or head[0] == '\t' or head[0] == '/' or head[0] == '*' or head[0] == '#')) continue;
        if (found > 0 and (std.ascii.isAlphanumeric(text[found - 1]) or text[found - 1] == '_')) continue;
        var end = found;
        while (end < text.len and (std.ascii.isAlphanumeric(text[end]) or text[end] == '_')) end += 1;
        const symbol = text[found..end];
        if (end >= text.len or text[end] != '(') continue;
        if (std.mem.startsWith(u8, head, "static")) continue;
        const close = std.mem.indexOfScalarPos(u8, text, end, ')') orelse {
            try unread.append(gpa, .{ .symbol = symbol, .why = "its parameter list does not close" });
            continue;
        };
        const zig = std.mem.startsWith(u8, head, "export fn ") or std.mem.startsWith(u8, head, "pub export fn ");
        const result_spelling = if (zig) zig: {
            const after = text[close + 1 ..];
            const brace = std.mem.indexOfScalar(u8, after, '{') orelse {
                try unread.append(gpa, .{ .symbol = symbol, .why = "its result is not followed by a body" });
                continue;
            };
            var tail = std.mem.trim(u8, after[0..brace], " ");
            if (std.mem.startsWith(u8, tail, "callconv(.c)")) tail = std.mem.trim(u8, tail["callconv(.c)".len..], " ");
            break :zig tail;
        } else head;
        const result = scalarOf(result_spelling) orelse {
            try unread.append(gpa, .{ .symbol = symbol, .why = "its result type is not one the table spells" });
            continue;
        };
        var parameters: std.ArrayList(runtime_symbols.Parameter) = .empty;
        var readable = true;
        const inner = std.mem.trim(u8, text[end + 1 .. close], " \n");
        if (inner.len > 0 and !std.mem.eql(u8, inner, "void")) {
            var pieces = std.mem.splitScalar(u8, inner, ',');
            while (pieces.next()) |piece| {
                const trimmed = std.mem.trim(u8, piece, " \t\n");
                // A C parameter is its type then its name; a Zig one is its
                // name, a colon, then its type.
                const spelled = if (std.mem.indexOfScalar(u8, trimmed, ':')) |colon|
                    trimmed[colon + 1 ..]
                else if (std.mem.lastIndexOfAny(u8, trimmed, " *")) |cut|
                    (if (trimmed[cut] == '*') trimmed[0 .. cut + 1] else trimmed[0..cut])
                else
                    trimmed;
                const parameter = scalarOf(spelled) orelse {
                    readable = false;
                    break;
                };
                try parameters.append(gpa, parameter);
            }
        }
        if (!readable) {
            try unread.append(gpa, .{ .symbol = symbol, .why = "a parameter type is not one the table spells" });
            continue;
        }
        try out.append(gpa, .{ .symbol = symbol, .parameters = try parameters.toOwnedSlice(gpa), .result = result.scalar });
    }
}

test "a runtime declaration the table cannot read is reported, not skipped" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    var declared: std.ArrayList(Declared) = .empty;
    var unread: std.ArrayList(Unread) = .empty;
    try declaredIn(gpa,
        \\long linea_close(int fd);
        \\size_t linea_measure(int fd);
        \\long linea_split(int fd,
        \\                 size_t length);
        \\static long linea_private(int fd) { return fd; }
        \\void linea_trap(int kind, const char *file, int line, int col) {
        \\    linea_close(1);
        \\/* linea_commented(int) */
        \\export fn linea_float64_parse(address: u64, length: u64, bits: *u64, offset: *u64) callconv(.c) u64 {
    , &declared, &unread);
    try testing.expectEqual(@as(usize, 3), declared.items.len);
    try testing.expectEqualStrings("linea_close", declared.items[0].symbol);
    // A symbol the compiler owns is read like any other, so its widths are
    // compared.
    try testing.expectEqualStrings("linea_trap", declared.items[1].symbol);
    try testing.expectEqual(runtime_symbols.Scalar.ptr, declared.items[1].parameters[1].scalar);
    try testing.expectEqualStrings("linea_float64_parse", declared.items[2].symbol);
    try testing.expectEqual(runtime_symbols.Passing.inout, declared.items[2].parameters[2].passing);
    try testing.expectEqual(@as(usize, 2), unread.items.len);
    try testing.expectEqualStrings("linea_measure", unread.items[0].symbol);
    try testing.expectEqualStrings("linea_split", unread.items[1].symbol);
}

test "the runtime signature table is the runtime's own sources" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    var declared: std.ArrayList(Declared) = .empty;
    var unread: std.ArrayList(Unread) = .empty;
    const sources = @import("runtime_sources").files;
    try testing.expect(sources.len > 0);
    for (sources) |file| try declaredIn(gpa, file.text, &declared, &unread);

    // Every declaration reads, so nothing the runtime provides escapes the
    // comparison below.
    for (unread.items) |u| std.debug.print("{s}: {s}\n", .{ u.symbol, u.why });
    try testing.expectEqual(@as(usize, 0), unread.items.len);

    // Every function the runtime provides is in a table, with the same
    // signature wherever the runtime declares it, and every function a table
    // says the runtime provides is in the runtime.
    for (runtime_symbols.runtime_functions ++ runtime_symbols.owned_functions) |expected| {
        if (expected.provider != .runtime) continue;
        var found = false;
        for (declared.items) |d| {
            if (!std.mem.eql(u8, d.symbol, expected.symbol)) continue;
            found = true;
            try testing.expectEqual(expected.result, d.result);
            try testing.expectEqualSlices(runtime_symbols.Parameter, expected.parameters, d.parameters);
        }
        if (!found) std.debug.print("the runtime does not define {s}\n", .{expected.symbol});
        try testing.expect(found);
    }
    for (declared.items) |d| {
        const listed = runtime_symbols.signatureOf(d.symbol) != null or for (runtime_symbols.owned_functions) |owned| {
            if (std.mem.eql(u8, owned.symbol, d.symbol)) break true;
        } else false;
        if (!listed) std.debug.print("{s} is not in a runtime signature table\n", .{d.symbol});
        try testing.expect(listed);
    }
}

test "the guide's chapters are the numbered files its index links to, in its order" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const index =
        \\1. [Linea in an hour](01-linea-in-an-hour.md) — the first chapter.
        \\2. [Errors](03-errors.md) — listed out of number order.
        \\The appendix, [Errors the guide shows](errors.md), is not a chapter,
        \\and neither is the [language definition](../linea-semantics.md).
        \\[Linea in an hour](01-linea-in-an-hour.md) is listed once.
        \\
    ;
    const chapters = source.guideChapters(gpa, index);
    try testing.expectEqual(@as(usize, 2), chapters.len);
    try testing.expectEqualStrings("Linea in an hour", chapters[0].name);
    try testing.expectEqualStrings("01-linea-in-an-hour.md", chapters[0].file);
    try testing.expectEqualStrings("Errors", chapters[1].name);
    try testing.expectEqualStrings("03-errors.md", chapters[1].file);
}

test "a heading's anchor is the one GitHub gives it" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    try testing.expectEqualStrings("39-opaque-types", source.headingSlug(gpa, "§3.9 Opaque types"));
    try testing.expectEqualStrings("-marks-a-receiver-the-call-will-change", source.headingSlug(gpa, "`&` marks a receiver the call will change"));
    try testing.expectEqualStrings("borrows--my-result-points-into-what-you-gave-me", source.headingSlug(gpa, "`borrows` — my result points into what you gave me"));
    try testing.expectEqualStrings("let--else-bind-the-value", source.headingSlug(gpa, "`let … else`: bind the value"));
    try testing.expectEqualStrings("a-names-case", source.headingSlug(gpa, "A name's case"));
    try testing.expectEqualStrings("olá-mundo", source.headingSlug(gpa, "Olá mundo"));
}

test "a walk tells headings, pasted output and prose apart, and numbers a repeated heading" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const text =
        \\# Title
        \\Prose names [O-Leak].
        \\```linea
        \\# not a heading inside source
        \\```
        \\## Repeated
        \\```
        \\error[O-Move]: moved
        \\```
        \\## Repeated
        \\- a list item holds a block:
        \\
        \\  ```text
        \\  note[S-Continuation]: indented
        \\  ```
        \\
    ;
    var walk = source.MarkdownWalk.init(gpa, text);
    var headings: std.ArrayList([]const u8) = .empty;
    var output: std.ArrayList([]const u8) = .empty;
    while (walk.next()) |line| switch (line) {
        .heading => |h| try headings.append(gpa, h.anchor),
        .fenced => |o| if (source.diagnosticOpening(o) != null) try output.append(gpa, o),
        .prose => {},
    };
    try testing.expectEqual(@as(usize, 3), headings.items.len);
    try testing.expectEqualStrings("title", headings.items[0]);
    try testing.expectEqualStrings("repeated", headings.items[1]);
    try testing.expectEqualStrings("repeated-1", headings.items[2]);
    try testing.expectEqual(@as(usize, 2), output.items.len);
    try testing.expectEqualStrings("error[O-Move]: moved", output.items[0]);
    try testing.expectEqualStrings("  note[S-Continuation]: indented", output.items[1]);
}

test "an output line opens with a diagnostic only when it names a rule" {
    const shown = source.diagnosticOpening("  warning[N-Shadowed]: `Coffee` declares `cents`").?;
    try testing.expectEqualStrings("warning", shown.kind);
    try testing.expectEqualStrings("N-Shadowed", shown.code);
    try testing.expectEqual(@as(?source.Diagnostic, null), source.diagnosticOpening("   = help: settle it first"));
    try testing.expectEqual(@as(?source.Diagnostic, null), source.diagnosticOpening("error[not a code]: text"));
    try testing.expectEqual(@as(?source.Diagnostic, null), source.diagnosticOpening("linea: panic: called Result.unwrap"));
}

test "a line names a rule in brackets or backticks, and writes one bare otherwise" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const codes = source.codesOnLine(gpa, "| `O-Move` | ambiguous (`[N-Ambiguous]`); see [Errors](03-errors.md), [T-Impl] and O-Leak |");
    try testing.expectEqual(@as(usize, 3), codes.named.len);
    try testing.expectEqualStrings("O-Move", codes.named[0]);
    try testing.expectEqualStrings("N-Ambiguous", codes.named[1]);
    try testing.expectEqualStrings("T-Impl", codes.named[2]);
    try testing.expectEqual(@as(usize, 1), codes.bare.len);
    try testing.expectEqualStrings("O-Leak", codes.bare[0]);
}

test "a rule code is a capital, a dash and a capitalised word" {
    try testing.expect(source.isRuleCode("O-Leak"));
    try testing.expect(source.isRuleCode("T-TryAnswer"));
    try testing.expect(!source.isRuleCode("A-Z"));
    try testing.expect(!source.isRuleCode("UTF-8"));
    try testing.expect(!source.isRuleCode("O-leak"));
    try testing.expect(!source.isRuleCode("OL-Leak"));
}

test "the first differing line of a stale page is named with both versions" {
    const d = source.firstDifference("a\nb\nc\n", "a\nB\nc\n").?;
    try testing.expectEqual(@as(usize, 2), d.number);
    try testing.expectEqualStrings("b", d.expected);
    try testing.expectEqualStrings("B", d.found);
    const short = source.firstDifference("a\nb", "a").?;
    try testing.expectEqual(@as(usize, 2), short.number);
    try testing.expectEqualStrings("(the end of the page)", short.found);
    try testing.expectEqual(@as(?source.FirstDifference, null), source.firstDifference("same\n", "same\n"));
}

test "an error pasted under any fence is shown, however the fence is written" {
    // A `console` fence, an info string after a space, a four-backtick fence
    // holding a three-backtick line, and a tilde fence each paste one error.
    // Prose after each names a code, so a fence read as still open would lose
    // that prose.
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const chapters = [_]source.GuideChapter{
        .{ .name = "Fences", .file = "01-fences.md", .text =
        \\# Fences
        \\```console
        \\error[O-Move]: under console
        \\```
        \\``` text
        \\error[O-Leak]: after a space
        \\```
        \\````
        \\```
        \\error[O-Merge]: inside four backticks
        \\```
        \\````
        \\~~~
        \\error[O-Copy]: under tildes
        \\~~~
        \\Prose after every fence names [N-Ambiguous].
        \\
        },
    };
    const semantics =
        \\## §3 Names
        \\**[N-Ambiguous]** Two traits declare it.
        \\## §5 Ownership
        \\**[O-Copy]** Copy.
        \\**[O-Leak]** Leak.
        \\**[O-Merge]** Merge.
        \\**[O-Move]** Move.
        \\
    ;
    const index = source.guideErrorIndex(gpa, &chapters, semantics);
    try testing.expectEqual(@as(usize, 0), index.undefined_codes.len);
    inline for (.{ "O-Move", "O-Leak", "O-Merge", "O-Copy" }) |code| {
        try testing.expect(std.mem.indexOf(u8, index.page, "| `" ++ code ++ "` | error |") != null);
    }
    try testing.expect(std.mem.indexOf(u8, index.page, "| `N-Ambiguous` | Fences:") != null);
}

test "a misspelt code in a heading or a table cell is refused, and a bare one is unclassified" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const chapters = [_]source.GuideChapter{
        .{ .name = "Tables", .file = "01-tables.md", .text =
        \\# Tables
        \\## What [X-Bogus] means
        \\| Error | Meaning |
        \\| --- | --- |
        \\| `O-Moev` | a misspelt code in a cell |
        \\| O-Move | a code written bare in a cell |
        \\### The O-Leak heading
        \\
        },
    };
    const semantics =
        \\## §5 Ownership
        \\**[O-Leak]** Leak.
        \\**[O-Move]** Move.
        \\
    ;
    const index = source.guideErrorIndex(gpa, &chapters, semantics);
    try testing.expectEqual(@as(usize, 2), index.undefined_codes.len);
    try testing.expectEqualStrings("O-Moev", index.undefined_codes[0]);
    try testing.expectEqualStrings("X-Bogus", index.undefined_codes[1]);
    try testing.expectEqual(@as(usize, 2), index.unclassified.len);
    try testing.expectEqualStrings("O-Move", index.unclassified[0].code);
    try testing.expectEqualStrings("O-Leak", index.unclassified[1].code);
    try testing.expectEqualStrings("01-tables.md", index.unclassified[1].file);
}

test "a rule is found in the section whose paragraph opens with its bold name" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const semantics =
        \\## §3 Names
        \\
        \\**[N-Case]** A declared name starts in the case its kind requires.
        \\A later mention of [N-Case] defines nothing.
        \\
        \\### §3.8 Visibility
        \\
        \\**[M-Vis]** A private name is reached only from its module.
        \\```
        \\**[S-Fake]** inside a block defines nothing
        \\```
        \\
    ;
    var rules = source.ruleSections(gpa, semantics);
    try testing.expectEqual(@as(usize, 2), rules.count());
    try testing.expectEqualStrings("3-names", rules.get("N-Case").?.anchor);
    try testing.expectEqualStrings("§3.8 Visibility", rules.get("M-Vis").?.title);
    try testing.expectEqualStrings("38-visibility", rules.get("M-Vis").?.anchor);
}

test "the error index lists each shown code once, names the unshown ones apart, and refuses an undefined one" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const chapters = [_]source.GuideChapter{
        .{ .name = "Basics", .file = "01-basics.md", .text =
        \\# Basics
        \\## Moving
        \\```
        \\error[O-Move]: `gift` has already been moved
        \\```
        \\## Again
        \\```
        \\error[O-Move]: shown a second time
        \\error[X-Nowhere]: no rule defines this
        \\```
        \\Two traits make the call ambiguous, `[N-Ambiguous]`, and [O-Move] is named too.
        \\
        },
    };
    const semantics =
        \\## §3 Names
        \\**[N-Ambiguous]** Two traits declare it.
        \\## §5 Ownership
        \\**[O-Move]** A value is taken once.
        \\
    ;
    const index = source.guideErrorIndex(gpa, &chapters, semantics);
    try testing.expectEqual(@as(usize, 1), index.undefined_codes.len);
    try testing.expectEqualStrings("X-Nowhere", index.undefined_codes[0]);
    try testing.expect(std.mem.indexOf(
        u8,
        index.page,
        "| `O-Move` | error | Basics: [Moving](01-basics.md#moving) | [§5 Ownership](../linea-semantics.md#5-ownership), at `[O-Move]` |",
    ) != null);
    try testing.expectEqual(@as(usize, 1), std.mem.count(u8, index.page, "| `O-Move` |"));
    try testing.expect(std.mem.indexOf(
        u8,
        index.page,
        "| `N-Ambiguous` | Basics: [Again](01-basics.md#again) | [§3 Names](../linea-semantics.md#3-names), at `[N-Ambiguous]` |",
    ) != null);
}

const guide_chapter: source.GuideChapter = .{ .name = "Fixture", .file = "01-fixture.md" };

fn readFixture(gpa: std.mem.Allocator, text: []const u8) source.GuideReading {
    var chapter = guide_chapter;
    chapter.text = text;
    return source.readGuideChapter(gpa, chapter);
}

test "the guide gate: a program whose pasted output matches what it prints passes" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const reading = readFixture(gpa,
        \\# Fixture
        \\
        \\```linea
        \\import std.io
        \\
        \\fn main() -> Result[UInt8, io.IoError] {
        \\    io.println("hi")?
        \\    .Ok(0)
        \\}
        \\```
        \\
        \\```
        \\hi
        \\```
        \\
    );
    try testing.expectEqual(@as(usize, 0), reading.problems.len);
    try testing.expectEqual(@as(usize, 1), reading.programs.len);
    const program = reading.programs[0];
    try testing.expectEqual(@as(usize, 3), program.line);
    try testing.expectEqual(source.GuideCommand.run, program.command);
    try testing.expectEqualStrings("main.lin", program.files[0].path);
    try testing.expect(source.judgeGuideProgram(gpa, program, "hi\n", true) == null);
}

test "the guide gate: a program whose pasted output differs from what it prints fails with the line" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const reading = readFixture(gpa,
        \\```linea
        \\fn main() -> UInt8 {
        \\    0
        \\}
        \\```
        \\
        \\```
        \\hello
        \\world
        \\```
        \\
    );
    try testing.expectEqual(@as(usize, 1), reading.programs.len);
    const failure = source.judgeGuideProgram(gpa, reading.programs[0], "hello\nthere\n", true).?;
    try testing.expect(std.mem.indexOf(u8, failure, "01-fixture.md:1") != null);
    try testing.expect(std.mem.indexOf(u8, failure, "line 2") != null);
    try testing.expect(std.mem.indexOf(u8, failure, "world") != null);
    try testing.expect(std.mem.indexOf(u8, failure, "there") != null);
}

test "the guide gate: pasted output is all of the output unless a marker says how many diagnostics it stops after" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const unmarked = readFixture(gpa,
        \\```linea
        \\fn main() -> UInt8 {
        \\    0
        \\}
        \\```
        \\
        \\```
        \\error[T-Mismatch]: first
        \\ --> main.lin:2:5
        \\```
        \\
    ).programs[0];
    const first = "error[T-Mismatch]: first\n --> main.lin:2:5\n";
    const second = "error[N-Undefined]: second\n --> main.lin:3:5\n";
    try testing.expect(source.judgeGuideProgram(gpa, unmarked, first, true) == null);
    try testing.expect(source.judgeGuideProgram(gpa, unmarked, first ++ second, true) != null);

    const marked = readFixture(gpa,
        \\```linea
        \\fn main() -> UInt8 {
        \\    0
        \\}
        \\```
        \\
        \\<!-- guide: first 1 diagnostic -->
        \\```
        \\error[T-Mismatch]: first
        \\ --> main.lin:2:5
        \\```
        \\
    );
    try testing.expectEqual(@as(usize, 0), marked.problems.len);
    const program = marked.programs[0];
    try testing.expectEqual(@as(?usize, 1), program.expected_first);
    try testing.expect(source.judgeGuideProgram(gpa, program, first ++ second, true) == null);
    try testing.expect(source.judgeGuideProgram(gpa, program, first, true) != null);
    try testing.expect(source.judgeGuideProgram(gpa, program, "error[T-Mismatch]: first\n --> main.lin:2:5\n   | more of the first\n", true) != null);
    try testing.expect(source.judgeGuideProgram(gpa, program, first ++ "the program's own output\n", true) != null);
    try testing.expect(source.judgeGuideProgram(gpa, program, first ++ " " ++ second, true) != null);
}

test "the guide gate: a location inside the standard library compares by file, and any other location compares whole" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const program = readFixture(gpa,
        \\```linea
        \\fn main() -> UInt8 {
        \\    0
        \\}
        \\```
        \\
        \\```
        \\linea: panic: called Result.unwrap on Err at std/result/result.lin:394:23
        \\```
        \\
    ).programs[0];
    try testing.expect(source.judgeGuideProgram(gpa, program, "linea: panic: called Result.unwrap on Err at std/result/result.lin:401:9\n", true) == null);
    try testing.expect(source.judgeGuideProgram(gpa, program, "linea: panic: called Result.unwrap on Err at std/option/option.lin:401:9\n", true) != null);
    try testing.expect(source.judgeGuideProgram(gpa, program, "linea: panic: called Result.unwrap on Err at main.lin:401:9\n", true) != null);
}

test "the guide gate: a first-N marker counts the diagnostics it shows and sits above an output block" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const two = readFixture(gpa,
        \\```linea
        \\fn main() -> UInt8 {
        \\    0
        \\}
        \\```
        \\
        \\<!-- guide: first 2 diagnostics -->
        \\```
        \\error[T-Mismatch]: first
        \\```
        \\
    ).programs[0];
    try testing.expect(source.judgeGuideProgram(gpa, two, "error[T-Mismatch]: first\nerror[N-Undefined]: second\n", true) != null);

    for ([_][]const u8{ "first 0 diagnostics", "first two diagnostics", "first 2", "first 1 diagnostics" }) |text| {
        const reading = readFixture(gpa, std.fmt.allocPrint(gpa, "<!-- guide: {s} -->\n```\nout\n```\n", .{text}) catch unreachable);
        var refused: usize = 0;
        for (reading.problems) |problem| refused += @intFromBool(std.mem.indexOf(u8, problem.message, "guide markers are") != null);
        try testing.expectEqual(@as(usize, if (std.mem.eql(u8, text, "first 1 diagnostics")) 0 else 1), refused);
    }

    const misplaced = readFixture(gpa,
        \\<!-- guide: first 1 diagnostic -->
        \\```linea
        \\fn main() -> UInt8 {
        \\    0
        \\}
        \\```
        \\
    );
    try testing.expectEqual(@as(usize, 1), misplaced.problems.len);
}

test "the guide gate: pasted errors beside an unrun program must read as diagnostics the compiler prints" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const reading = readFixture(gpa,
        \\<!-- guide: unchecked the error an edit of the program above produces -->
        \\```
        \\error[O-Move]: `distance` is lent, and this takes it
        \\  --> pace_lent.lin:10:21
        \\   |
        \\10 |     let Meters(m) = distance
        \\   |                     ^^^^^^^^ `copy` it, or declare the parameter `sink` to take it
        \\   = help: settle it first with `distance.release()`
        \\```
        \\
    );
    try testing.expectEqual(@as(usize, 1), reading.unrun_output.len);

    var wording: source.DiagnosticWording = .{};
    wording.addOutput(gpa,
        \\error[O-Move]: `pace` is lent, and this takes it
        \\ --> other.lin:3:9
        \\  |
        \\3 |     let Meters(m) = pace
        \\  |                     ^^^^ `copy` it, or declare the parameter `sink` to take it
        \\  = help: settle it first with `pace.release()`
    );
    try testing.expect(wording.judge(gpa, reading.unrun_output[0]) == null);

    const altered = readFixture(gpa,
        \\<!-- guide: unchecked the error an edit of the program above produces -->
        \\```
        \\error[O-Move]: `distance` is MUTATED, and this takes it
        \\  --> pace_lent.lin:10:21
        \\   |
        \\   |                     ^^^^^^^^ MUTATED WRONG HINT
        \\   = help: settle it first with `distance.release()`
        \\```
        \\
    );
    const failure = wording.judge(gpa, altered.unrun_output[0]).?;
    try testing.expect(std.mem.indexOf(u8, failure, "is MUTATED") != null);
    try testing.expect(std.mem.indexOf(u8, failure, "MUTATED WRONG HINT") != null);
    try testing.expect(std.mem.indexOf(u8, failure, "01-fixture.md:3") != null);
    try testing.expect(std.mem.indexOf(u8, failure, "settle it first") == null);
}

test "the guide gate: a pasted diagnostic names the file the program is written to" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const reading = readFixture(gpa,
        \\```linea
        \\fn main() -> UInt8 {
        \\    0
        \\}
        \\```
        \\
        \\```
        \\error[T-Mismatch]: first
        \\ --> pace_lent.lin:2:5
        \\```
        \\
    );
    try testing.expectEqualStrings("pace_lent.lin", reading.programs[0].files[0].path);
    try testing.expectEqualStrings("pace_lent.lin", reading.programs[0].target);
}

test "the guide gate: a run command between a program and its output chooses the command and the file" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const reading = readFixture(gpa,
        \\```linea
        \\test fn works() {
        \\}
        \\```
        \\
        \\```sh
        \\linea test tiles.lin
        \\```
        \\
        \\```
        \\ok    works
        \\
        \\1 passed, 0 failed
        \\```
        \\
    );
    try testing.expectEqual(@as(usize, 0), reading.problems.len);
    try testing.expectEqual(source.GuideCommand.@"test", reading.programs[0].command);
    try testing.expectEqualStrings("tiles.lin", reading.programs[0].target);
}

test "the guide gate: labelled files make one project that runs from its main file" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const reading = readFixture(gpa,
        \\`shop/menu/menu.lin`:
        \\
        \\```linea
        \\pub fn price() -> UInt64 {
        \\    3
        \\}
        \\```
        \\
        \\`shop/main.lin`:
        \\
        \\```linea
        \\import menu
        \\
        \\fn main() -> UInt8 {
        \\    0
        \\}
        \\```
        \\
        \\```
        \\done
        \\```
        \\
    );
    try testing.expectEqual(@as(usize, 0), reading.problems.len);
    try testing.expectEqual(@as(usize, 1), reading.programs.len);
    try testing.expectEqual(@as(usize, 2), reading.programs[0].files.len);
    try testing.expectEqualStrings("shop/menu/menu.lin", reading.programs[0].files[0].path);
    try testing.expectEqualStrings("shop", reading.programs[0].target);
}

test "the guide gate: a labelled manifest joins the project it sits in" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const reading = readFixture(gpa,
        \\`garden/plants/linea.json`:
        \\
        \\```json
        \\{ "kind": "library", "name": "plants" }
        \\```
        \\
        \\`garden/plants/plants.lin`:
        \\
        \\```linea
        \\pub fn days() -> UInt8 {
        \\    3
        \\}
        \\```
        \\
        \\`garden/linea.json`:
        \\
        \\```json
        \\{ "dependencies": { "plants": { "path": "plants" } } }
        \\```
        \\
        \\`garden/main.lin`:
        \\
        \\```linea
        \\import plants
        \\
        \\fn main() -> UInt8 {
        \\    plants.days()
        \\}
        \\```
        \\
        \\```json
        \\{ "an": "unlabelled block, which is prose" }
        \\```
        \\
    );
    try testing.expectEqual(@as(usize, 0), reading.problems.len);
    try testing.expectEqual(@as(usize, 1), reading.programs.len);
    try testing.expectEqual(@as(usize, 4), reading.programs[0].files.len);
    try testing.expectEqualStrings("garden/plants/linea.json", reading.programs[0].files[0].path);
    try testing.expectEqualStrings("garden", reading.programs[0].target);
}

test "the guide gate: a library's file with tests completes a project beside its manifest" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const reading = readFixture(gpa,
        \\`plants/linea.json`:
        \\
        \\```json
        \\{ "kind": "library", "name": "plants" }
        \\```
        \\
        \\`plants/plants.lin`:
        \\
        \\```linea
        \\pub fn days() -> UInt8 {
        \\    3
        \\}
        \\
        \\test fn three_days() {
        \\}
        \\```
        \\
    );
    try testing.expectEqual(@as(usize, 0), reading.problems.len);
    try testing.expectEqual(@as(usize, 1), reading.programs.len);
    try testing.expectEqual(@as(usize, 2), reading.programs[0].files.len);
    try testing.expectEqualStrings("plants/plants.lin", reading.programs[0].target);
}

test "the guide gate: a labelled data block is a file beside the next program, not its output" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const reading = readFixture(gpa,
        \\`usage.txt`:
        \\
        \\```text
        \\usage: forecast CITY
        \\```
        \\
        \\```linea
        \\fn main() -> UInt8 {
        \\    UInt8(embed("usage.txt").length())
        \\}
        \\```
        \\
        \\```linea
        \\fn main() -> UInt8 {
        \\    0
        \\}
        \\```
        \\
        \\```text
        \\done
        \\```
        \\
    );
    try testing.expectEqual(@as(usize, 0), reading.problems.len);
    try testing.expectEqual(@as(usize, 2), reading.programs.len);
    try testing.expectEqual(@as(usize, 2), reading.programs[0].files.len);
    try testing.expectEqualStrings("main.lin", reading.programs[0].files[0].path);
    try testing.expectEqualStrings("usage.txt", reading.programs[0].files[1].path);
    try testing.expectEqualStrings("usage: forecast CITY", reading.programs[0].files[1].text);
    // A data block joins the program after it and no other.
    try testing.expectEqual(@as(usize, 1), reading.programs[1].files.len);
    try testing.expectEqualStrings("done", reading.programs[1].expected.?);
}

test "the guide gate: a data block with no program after it is reported" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const at_end = readFixture(gpa,
        \\`orphan.txt`:
        \\
        \\```text
        \\nobody embeds this
        \\```
        \\
    );
    try testing.expectEqual(@as(usize, 1), at_end.problems.len);
    try testing.expectEqual(@as(usize, 3), at_end.problems[0].line);

    const before_a_fragment = readFixture(gpa,
        \\`orphan.txt`:
        \\
        \\```text
        \\nobody embeds this
        \\```
        \\
        \\```linea
        \\let x = 1
        \\```
        \\
    );
    try testing.expectEqual(@as(usize, 1), before_a_fragment.problems.len);
    try testing.expectEqual(@as(usize, 0), before_a_fragment.programs.len);
}

test "the guide gate: a line naming something other than a .lin file above a Linea block is prose, and the block is compiled" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const reading = readFixture(gpa,
        \\The whole of it fits in one call to
        \\`str.split_once`:
        \\
        \\```linea
        \\fn main() -> UInt8 { 0 }
        \\```
        \\
    );
    try testing.expectEqual(@as(usize, 0), reading.problems.len);
    try testing.expectEqual(@as(usize, 1), reading.programs.len);
    try testing.expectEqual(@as(usize, 1), reading.programs[0].files.len);
    try testing.expectEqualStrings("main.lin", reading.programs[0].files[0].path);
}

test "the guide gate: a labelled block directly after a program is its output, not data" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const reading = readFixture(gpa,
        \\```linea
        \\fn main() -> UInt8 { 0 }
        \\```
        \\
        \\It prints what `io.print` was given, which ends
        \\`report.txt`:
        \\
        \\```
        \\done
        \\```
        \\
    );
    try testing.expectEqual(@as(usize, 0), reading.problems.len);
    try testing.expectEqual(@as(usize, 1), reading.programs.len);
    try testing.expectEqualStrings("done", reading.programs[0].expected.?);
}

test "the guide gate: an unchecked program takes the data above it" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const then_another = readFixture(gpa,
        \\`page.txt`:
        \\
        \\```text
        \\hello
        \\```
        \\
        \\<!-- guide: unchecked the file is shown elsewhere -->
        \\```linea
        \\fn main() -> UInt8 { UInt8(embed("page.txt").length()) }
        \\```
        \\
        \\```
        \\error[M-Embed]: something
        \\```
        \\
        \\```linea
        \\fn main() -> UInt8 { 0 }
        \\```
        \\
    );
    try testing.expectEqual(@as(usize, 0), then_another.problems.len);
    try testing.expectEqual(@as(usize, 1), then_another.programs.len);
    try testing.expectEqual(@as(usize, 1), then_another.programs[0].files.len);

    const at_end = readFixture(gpa,
        \\`page.txt`:
        \\
        \\```text
        \\hello
        \\```
        \\
        \\<!-- guide: unchecked reason -->
        \\```linea
        \\fn main() -> UInt8 { UInt8(embed("page.txt").length()) }
        \\```
        \\
    );
    try testing.expectEqual(@as(usize, 0), at_end.problems.len);
    try testing.expectEqual(@as(usize, 0), at_end.programs.len);
}

test "the guide gate: a labelled manifest and C source join the project" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const reading = readFixture(gpa,
        \\`tally/linea.json`:
        \\
        \\```json
        \\{ "extern": ["counter"], "native": ["counter/counter.c"] }
        \\```
        \\
        \\`tally/counter/counter.c`:
        \\
        \\```c
        \\int counter_double(int value) { return value * 2; }
        \\```
        \\
        \\`tally/counter/counter.lin`:
        \\
        \\```linea
        \\extern fn counter_double(value: Int32) -> Int32
        \\
        \\pub fn double(value: Int32) -> Int32 {
        \\    counter_double(value)
        \\}
        \\```
        \\
        \\`tally/main.lin`:
        \\
        \\```linea
        \\import counter
        \\
        \\fn main() -> UInt8 {
        \\    UInt8(counter.double(2))
        \\}
        \\```
        \\
    );
    try testing.expectEqual(@as(usize, 0), reading.problems.len);
    try testing.expectEqual(@as(usize, 1), reading.programs.len);
    try testing.expectEqual(@as(usize, 4), reading.programs[0].files.len);
    try testing.expectEqualStrings("tally/linea.json", reading.programs[0].files[0].path);
    // A labelled C source is a data file of the program after it, written
    // beside the project's sources wherever it sits among them.
    const carries_c = for (reading.programs[0].files) |file| {
        if (std.mem.eql(u8, file.path, "tally/counter/counter.c")) break true;
    } else false;
    try testing.expect(carries_c);
    try testing.expectEqualStrings("tally", reading.programs[0].target);
}

test "the guide gate: a fragment passes uncounted as a program, and a fragment with output is refused" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const bare = readFixture(gpa,
        \\```linea
        \\let x = 1
        \\```
        \\
    );
    try testing.expectEqual(@as(usize, 0), bare.problems.len);
    try testing.expectEqual(@as(usize, 0), bare.programs.len);
    try testing.expectEqual(@as(usize, 1), bare.fragments);

    const refused = readFixture(gpa,
        \\```linea
        \\let x = 1
        \\```
        \\
        \\```
        \\error[T-Mismatch]: pasted beside an edit nothing compiles
        \\```
        \\
    );
    try testing.expectEqual(@as(usize, 1), refused.problems.len);
    try testing.expectEqual(@as(usize, 5), refused.problems[0].line);
}

test "the guide gate: an explicit marker excludes a block and the output beside it, and needs a reason" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const marked = readFixture(gpa,
        \\<!-- guide: unchecked the program is an edit of the one above -->
        \\```linea
        \\fn main() -> UInt8 {
        \\    1
        \\}
        \\```
        \\
        \\```
        \\whatever it printed
        \\```
        \\
    );
    try testing.expectEqual(@as(usize, 0), marked.problems.len);
    try testing.expectEqual(@as(usize, 0), marked.programs.len);
    try testing.expectEqual(@as(usize, 1), marked.excluded);

    const bare_marker = readFixture(gpa,
        \\<!-- guide: unchecked -->
        \\```
        \\output
        \\```
        \\
    );
    try testing.expect(bare_marker.problems.len > 0);
    try testing.expectEqual(@as(usize, 1), bare_marker.problems[0].line);
}

test "the guide gate: a program without pasted output is only checked, and output after no program is refused" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const checked = readFixture(gpa,
        \\```linea
        \\fn main() -> UInt8 {
        \\    0
        \\}
        \\```
        \\
    );
    try testing.expectEqual(@as(usize, 1), checked.programs.len);
    try testing.expectEqual(source.GuideCommand.check, checked.programs[0].command);
    try testing.expect(checked.programs[0].expected == null);
    try testing.expectEqual(@as(usize, 0), checked.problems.len);

    const loose = readFixture(gpa,
        \\Prose.
        \\
        \\```
        \\output that follows no program
        \\```
        \\
    );
    try testing.expectEqual(@as(usize, 1), loose.problems.len);
    try testing.expectEqual(@as(usize, 3), loose.problems[0].line);
}

test "a sequential run orders exactly the heavy steps its suite selects" {
    // The unit tests come first: they fail most often, and a failure stops
    // every step ordered after it.
    const full = test_roots.select(.{ .optimize = .Debug, .filtered = false });
    const all = test_roots.heavyOrder(full, .{ .properties = true, .guide = true });
    try testing.expectEqualSlices(test_roots.Heavy, &.{
        .compile_unit_tests, .unit_tests, .compile_compiler, .compile_runner,
        .corpus,             .properties, .examples,         .guide,
    }, all.slice());

    // A step the suite leaves out is not ordered, so ordering adds none.
    const without_guide = test_roots.heavyOrder(full, .{ .properties = true, .guide = false });
    for (without_guide.slice()) |heavy| try testing.expect(heavy != .guide);
    const filtered = test_roots.heavyOrder(test_roots.select(.{ .optimize = .Debug, .filtered = true }), .{ .properties = false, .guide = true });
    try testing.expectEqualSlices(test_roots.Heavy, &.{ .compile_unit_tests, .unit_tests }, filtered.slice());
    const unit = test_roots.heavyOrder(test_roots.select(.{ .suite = .unit, .optimize = .ReleaseFast, .filtered = false }), .{ .properties = false, .guide = true });
    try testing.expectEqualSlices(test_roots.Heavy, &.{ .compile_unit_tests, .unit_tests }, unit.slice());
    const conformance = test_roots.heavyOrder(test_roots.select(.{ .suite = .conformance, .optimize = .ReleaseFast, .filtered = false }), .{ .properties = false, .guide = true });
    try testing.expectEqualSlices(test_roots.Heavy, &.{ .compile_compiler, .compile_runner, .corpus, .examples }, conformance.slice());
}
