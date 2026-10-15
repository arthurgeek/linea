const std = @import("std");
const test_roots = @import("build/test_roots.zig");

// Copy the pinned provider unchanged: Zig forbids sharing its source files
// between the standard-library module and this integer-only entry point.
fn addDecimalProvider(b: *std.Build, module: *std.Build.Module) void {
    const lib_directory = b.graph.zig_lib_directory.path orelse @panic("Zig library directory is required");
    const files = b.addWriteFiles();
    const directory = b.pathJoin(&.{ lib_directory, "std", "fmt", "parse_float" });
    const root = files.addCopyFile(.{ .cwd_relative = b.pathJoin(&.{ directory, "convert_slow.zig" }) }, "convert_slow.zig");
    for ([_][]const u8{ "decimal.zig", "common.zig", "FloatStream.zig" }) |name| {
        _ = files.addCopyFile(.{ .cwd_relative = b.pathJoin(&.{ directory, name }) }, name);
    }
    _ = files.addCopyFile(b.path("runtime/zig-float-LICENSE"), "LICENSE");
    module.addImport("decimal_provider", b.createModule(.{
        .root_source_file = root,
        .target = module.resolved_target,
        .optimize = module.optimize,
    }));
}

/// What a test run's binaries are watched by.
///
/// A sanitizer works by instrumenting code as it is compiled -- redzones
/// around a frame, shadow memory beside it -- and the address sanitizer
/// instruments only functions carrying the `sanitize_address` attribute.
/// Clang's frontend adds that attribute while it lowers C, so
/// `runtime/linea_rt.c` is instrumented. The generated program
/// reaches `cc` as printed LLVM IR (`-x ir`), and the emitter writes no such
/// attribute, so its loads and stores are not watched: a read of freed or
/// out-of-bounds storage in generated Linea code is not caught. What a
/// sanitized run does watch is the runtime's own code, every allocation and
/// free through the intercepted allocator (a double or invalid free), leaks
/// at exit, and crashes.
///
/// `address` also answers for the language's central promise. Its leak
/// checker is the only run-time check for a leak: it runs at every clean exit
/// on Linux, and ownership claims no value is abandoned -- so a corpus
/// program that leaks is not an untidy test, it is ownership and lowering
/// disagreeing about a disposal, caught at run time from outside the compiler
/// entirely. A trapping program aborts past the leak check, which is right:
/// what a trap leaves behind is not a leak, it is a stopped program.
///
/// A `memory` sanitizer ran beside it as an experiment, sound only where every
/// store a value passes through is instrumented. In its run it found one
/// defect, and not in the runtime: the conformance runner handed a spawned
/// program a writable descriptor at 9 that the standard library's spawn path
/// had opened without close-on-exec, which two cases asserting that
/// descriptor is closed then read (fixed in 6050688e). It found nothing in
/// the runtime or in generated code over two and a half months, and it is no
/// longer offered.
///
/// Undefined-behaviour checks are not listed because they are not a choice:
/// the runtime is always compiled with them, trapping alone or reporting
/// when a selected sanitizer needs its routines reachable -- and generated
/// IR cannot take them at all, because UBSan instruments while a frontend
/// lowers source and no frontend runs over printed IR. What stands for it in
/// generated code is the language: every operation is defined or refused,
/// and the trap checks are already printed into the module.
///
/// A thread sanitizer stays absent because its scope is empty: the runtime
/// creates no thread and the language has no concurrency. A type sanitizer
/// stays absent by decision rather than omission: it checks the promises
/// TBAA metadata makes, and this compiler deliberately emits none -- proofs
/// are handed to the optimiser, never premises. The data-flow instrumentation
/// is a taint framework a program must call into, not a detector to run a
/// corpus under.
///
/// None of this works on Darwin, which is where the compiler is developed:
/// the runtime hangs before reaching `main` on a C program that does nothing
/// but return a constant, so the fault is under the toolchain rather than in
/// anything generated. It is selected here and exercised on Linux.
const Sanitize = enum {
    none,
    address,

    fn flag(self: Sanitize) ?[]const u8 {
        return switch (self) {
            .none => null,
            else => @tagName(self),
        };
    }
};

/// The library's files, as a Zig source listing them.
///
/// `@embedFile` takes a path it can see at compile time, so a library that
/// grows by a directory rather than by an edit needs the list generated. The
/// sources are copied beside the generated file so that each `@embedFile` is
/// an ordinary relative path -- which is also what makes the compiler rebuild
/// when one of them changes.
fn libraryManifest(b: *std.Build) std.Build.LazyPath {
    const wf = b.addWriteFiles();

    var text: std.ArrayList(u8) = .empty;
    text.appendSlice(b.allocator,
        \\pub const File = struct { path: []const u8, text: []const u8 };
        \\
        \\pub const files = [_]File{
        \\
    ) catch @panic("OOM");

    const io = b.graph.io;
    var dir = b.build_root.handle.openDir(io, "std", .{ .iterate = true }) catch
        @panic("the standard library is missing");
    defer dir.close(io);

    var walker = dir.walk(b.allocator) catch @panic("OOM");
    defer walker.deinit();

    // Sorted, so the generated file is the same however the directory is read
    // and a build does not churn on filesystem order.
    //
    // Nothing here is freed: `b.allocator` is the build graph's arena, which
    // lives as long as the process that walks this directory once. Freeing a
    // path would return it to an allocator that is about to be discarded
    // whole.
    var found: std.ArrayList([]const u8) = .empty;
    while (walker.next(io) catch @panic("cannot read the standard library")) |entry| {
        if (entry.kind != .file) continue;
        // Every file but the library's documentation travels with the
        // sources: the manifest says this root is the library named `std`, for
        // the copy compiled in as for the directory, and any other file is one
        // a library module may `embed`, which the copy must hold to read.
        if (std.mem.endsWith(u8, entry.basename, ".md")) continue;
        found.append(b.allocator, b.dupe(entry.path)) catch @panic("OOM");
    }
    std.mem.sort([]const u8, found.items, {}, lessThanSlice);

    for (found.items) |rel| {
        // The loader reads a module out of a directory, so the path it is
        // given has to be the one the library is laid out under.
        _ = wf.addCopyFile(b.path(b.fmt("std/{s}", .{rel})), rel);

        // Escaped, because this goes into a Zig string literal and a path is
        // whatever the filesystem allows -- a quote or a backslash in one
        // would end the literal early and the generated file would not parse.
        const quoted = zigString(b, rel);
        text.appendSlice(b.allocator, b.fmt(
            "    .{{ .path = \"std/{s}\", .text = @embedFile(\"{s}\") }},\n",
            .{ quoted, quoted },
        )) catch @panic("OOM");
    }

    text.appendSlice(b.allocator, "};\n") catch @panic("OOM");
    return wf.add("manifest.zig", text.items);
}

/// A path as the body of a Zig string literal.
fn zigString(b: *std.Build, s: []const u8) []const u8 {
    var out: std.ArrayList(u8) = .empty;
    for (s) |ch| {
        switch (ch) {
            '"', '\\' => out.append(b.allocator, '\\') catch @panic("OOM"),
            else => {},
        }
        out.append(b.allocator, ch) catch @panic("OOM");
    }
    return out.items;
}

/// Every source the runtime is built from, as a Zig source listing them: its
/// C headers and files and its Zig files, without the tests. Walked rather
/// than listed, so a new runtime file is read by the test that holds the
/// runtime's signature table to it without anybody adding it here.
fn runtimeSources(b: *std.Build) std.Build.LazyPath {
    const wf = b.addWriteFiles();
    var text: std.ArrayList(u8) = .empty;
    text.appendSlice(b.allocator,
        \\pub const File = struct { path: []const u8, text: []const u8 };
        \\
        \\pub const files = [_]File{
        \\
    ) catch @panic("OOM");

    const io = b.graph.io;
    var dir = b.build_root.handle.openDir(io, "runtime", .{ .iterate = true }) catch
        @panic("the runtime is missing");
    defer dir.close(io);
    var iterator = dir.iterate();
    var found: std.ArrayList([]const u8) = .empty;
    while (iterator.next(io) catch @panic("cannot read the runtime")) |entry| {
        if (entry.kind != .file) continue;
        const readable = std.mem.endsWith(u8, entry.name, ".h") or std.mem.endsWith(u8, entry.name, ".c") or std.mem.endsWith(u8, entry.name, ".zig");
        if (!readable or std.mem.endsWith(u8, entry.name, "_test.c")) continue;
        found.append(b.allocator, b.dupe(entry.name)) catch @panic("OOM");
    }
    std.mem.sort([]const u8, found.items, {}, lessThanSlice);
    for (found.items) |name| {
        _ = wf.addCopyFile(b.path(b.fmt("runtime/{s}", .{name})), name);
        const quoted = zigString(b, name);
        text.appendSlice(b.allocator, b.fmt(
            "    .{{ .path = \"runtime/{s}\", .text = @embedFile(\"{s}\") }},\n",
            .{ quoted, quoted },
        )) catch @panic("OOM");
    }
    text.appendSlice(b.allocator, "};\n") catch @panic("OOM");
    return wf.add("runtime_sources.zig", text.items);
}

/// One runtime source compiled to the object an archive holds.
fn runtimeObject(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    name: []const u8,
    file: std.Build.LazyPath,
    flags: []const []const u8,
) *std.Build.Step.Compile {
    const module = b.createModule(.{
        .target = target,
        .optimize = .ReleaseSmall,
        .link_libc = true,
    });
    module.addSystemIncludePath(.{ .cwd_relative = b.graph.zig_lib_directory.path orelse "." });
    module.addCSourceFile(.{ .file = file, .flags = flags });
    return b.addObject(.{ .name = name, .root_module = module });
}

/// The target with the CPU model of the build machine replaced by the baseline
/// model of its architecture. A target that names its CPU is left alone.
fn baselineCpu(b: *std.Build, target: std.Build.ResolvedTarget) std.Build.ResolvedTarget {
    var query = target.query;
    if (query.isNativeCpu()) query.cpu_model = .baseline;
    return b.resolveTargetQuery(query);
}

fn lessThanSlice(_: void, a: []const u8, b: []const u8) bool {
    return std.mem.lessThan(u8, a, b);
}

/// What the gates below read out of the project's own text.
///
/// A module rather than functions here, because `zig build` runs no `test`
/// block in this file: a heuristic deciding whether a build fails is worth
/// cases, and only code outside a build script can have them.
const source = @import("build/source.zig");

/// The runtime archive and symbols an installed compiler goes looking for.
const runtime_symbols = @import("src/support/runtime_symbols.zig");
const toolchain = @import("src/driver/toolchain.zig");
const tree_sitter_dir = "editor-support/tree-sitter-linea";

/// Tracy's client, compiled from its own source rather than through a binding.
/// A binding pins the client's version, and a client whose protocol does not
/// match the installed profiler refuses the connection. Here the version is
/// this dependency's, chosen to match what the profiler on the machine is.
///
/// Every module that compiles `src/` needs it, not just the runner: the zones
/// sit in the passes themselves, so any binary that typechecks a program
/// references the client's symbols and fails to link without it.
fn linkTracyClient(b: *std.Build, m: *std.Build.Module, profiling: bool) void {
    if (!profiling) return;
    const tracy_src = b.dependency("tracy_src", .{});
    m.addCSourceFile(.{
        .file = tracy_src.path("public/TracyClient.cpp"),
        .flags = &.{"-DTRACY_ENABLE"},
    });
    m.addIncludePath(tracy_src.path("public"));
    m.link_libcpp = true;
}

/// The files the compiler embeds, given to a module that compiles it.
///
/// Every binary built from `src/` needs all five: a test reads the runtime's
/// source to check the two agree about traps, a diagnostic's code is an index
/// into the semantics, the standard library travels inside the binary, the
/// fuzz corpus is replayed on every run, and the language server's protocol
/// types enable IDE support. Every test scope receives the same compiler
/// inputs even when it selects only one part of the test universe.
fn addCompilerAssets(
    m: *std.Build.Module,
    runtime_source: std.Build.LazyPath,
    semantics: std.Build.LazyPath,
    library: std.Build.LazyPath,
    corpus: *std.Build.Module,
    lsp_kit: *std.Build.Dependency,
    options: *std.Build.Step.Options,
) void {
    m.addOptions("build_options", options);
    m.addAnonymousImport("runtime_source", .{ .root_source_file = runtime_source });
    m.addAnonymousImport("semantics", .{ .root_source_file = semantics });
    m.addAnonymousImport("library_manifest", .{ .root_source_file = library });
    m.addImport("fuzz_corpus", corpus);
    m.addImport("lsp", lsp_kit.module("lsp"));
}

/// The generated and hand-written editor descriptions conformance tests read.
fn addConformanceAssets(b: *std.Build, m: *std.Build.Module) void {
    m.addAnonymousImport("grammar_json", .{
        .root_source_file = b.path(tree_sitter_dir ++ "/src/grammar.json"),
    });
    m.addAnonymousImport("highlights_scm", .{
        .root_source_file = b.path(tree_sitter_dir ++ "/queries/highlights.scm"),
    });
    m.addAnonymousImport("sublime_syntax", .{
        .root_source_file = b.path("editor-support/sublime-linea/linea.sublime-syntax"),
    });
}

/// Whether CI runs every sanitizer this build offers.
///
/// `Sanitize` is the only executable statement of the set: `flag()` derives
/// the `-fsanitize=` name from the tag, and the tag salts the conformance
/// outcome cache. The CI workflow and the README are text beside it, and the
/// enum's own doc says these "are selected here and exercised on Linux" --
/// which is a claim about a file this one has no other reason to read.
///
/// None of them work on Darwin, where the compiler is developed, so adding a
/// sanitizer and not adding it to the workflow means it is never run anywhere
/// and nothing says so.
fn checkCiRunsEverySanitizer(b: *std.Build) void {
    const io = b.graph.io;
    const workflow = b.build_root.handle.readFileAlloc(
        io,
        ".github/workflows/ci.yml",
        b.allocator,
        .limited(1 << 20),
    ) catch @panic("the CI workflow is missing or unreadable");

    const matrix_key = "sanitizer: [";
    const matrix_start = std.mem.indexOf(u8, workflow, matrix_key) orelse
        @panic("the CI workflow names no sanitizer matrix");
    const matrix_rest = workflow[matrix_start + matrix_key.len ..];
    const matrix = matrix_rest[0 .. std.mem.indexOfScalar(u8, matrix_rest, ']') orelse
        @panic("the CI sanitizer matrix is unterminated")];

    var missing = false;
    for (std.enums.values(Sanitize)) |sanitizer| {
        // `.none` is the default and names no runtime to link, so it is not a
        // matrix entry.
        const name = sanitizer.flag() orelse continue;
        var entries = std.mem.splitSequence(u8, matrix, ", ");
        const listed = while (entries.next()) |entry| {
            if (std.mem.eql(u8, std.mem.trim(u8, entry, " "), name)) break true;
        } else false;
        if (listed) continue;
        std.debug.print("sanitize: CI does not run `{s}`\n", .{name});
        missing = true;
    }
    if (missing) @panic("a sanitizer this build offers is never run");
}

/// Whether the editor config indents by what the formatter indents by.
///
/// ADR 0038 refuses to make the width configurable, so there is one number by
/// decision -- and it was written twice, once in the formatter and once in a
/// `.helix/languages.toml` that also sets `auto-format = true` and points at
/// `linea fmt`. So the editor indents a partial line by its own number and the
/// formatter rewrites the file by the other, and the disagreement shows up as
/// the editor undoing itself while you type.
///
/// Read from the sources rather than shared between them: an editor config is
/// not a thing the compiler can import, which is the whole reason the number
/// is written twice.
fn checkTheEditorIndentsByWhatTheFormatterDoes(b: *std.Build) void {
    const io = b.graph.io;
    const fmt_source = b.build_root.handle.readFileAlloc(
        io,
        "src/fmt/fmt.zig",
        b.allocator,
        .limited(1 << 22),
    ) catch @panic("the formatter is missing");

    const spelled_width = source.between(fmt_source, "const indent_width = ", ";") orelse
        @panic("the formatter no longer states an indent width");
    const width = std.fmt.parseInt(usize, spelled_width, 10) catch
        @panic("the formatter's indent width is not a number");

    const config = b.build_root.handle.readFileAlloc(
        io,
        ".helix/languages.toml",
        b.allocator,
        .limited(1 << 20),
    ) catch return;

    const spelled = source.between(config, "unit = \"", "\"") orelse
        @panic("the editor config states no indent unit");

    if (spelled.len == width and std.mem.allEqual(u8, spelled, ' ')) return;
    std.debug.print(
        "indent: the formatter writes {d} spaces and .helix/languages.toml says \"{s}\"\n",
        .{ width, spelled },
    );
    @panic("the editor and the formatter disagree about indentation");
}

/// Whether the prelude publishes the names the compiler asks it for, and
/// nothing beyond them but the documented core vocabulary.
///
/// A name the syntax requires is one the compiler looks up by prelude
/// identity -- a literal has a type, `?` answers with one, `a[i]` is a call on
/// a trait. Every such lookup must find a published name, or a program is
/// refused for a name it never wrote.
///
/// Every other published name must be listed in the core-vocabulary table of
/// the semantics document, the one list recording which names the prelude
/// adds by decision rather than by syntax. A `pub use` added to the manifest
/// without a row there fails here, so the prelude cannot grow one convenience
/// at a time without the decision being written down. The table is held to
/// the manifest in the other direction too: a row naming nothing the prelude
/// publishes, or a name the compiler also looks up, is a table that lies.
///
/// Read out of the sources rather than shared between them. The compiler
/// cannot import the library's text -- the library is Linea and the lookup is
/// Zig -- so the three say it separately, which is exactly the shape that
/// drifts.
fn checkThePreludeIsDocumented(b: *std.Build) void {
    const io = b.graph.io;
    const gpa = b.allocator;

    const read = struct {
        fn file(bb: *std.Build, i: anytype, path: []const u8) []const u8 {
            return bb.build_root.handle.readFileAlloc(i, path, bb.allocator, .limited(1 << 22)) catch
                std.debug.panic("the prelude gate cannot read {s}", .{path});
        }
    }.file;

    // What the compiler asks the prelude for: every name a lookup is written
    // with, and every name a row of the traits it implements itself spells.
    var wanted: std.StringArrayHashMapUnmanaged(void) = .empty;
    const checker = read(b, io, "src/sema/typecheck.zig");
    var at: usize = 0;
    while (std.mem.indexOfPos(u8, checker, at, "preludeDecl(")) |found| {
        at = found + "preludeDecl(".len;
        // A call handed a variable names nothing here; what reaches it is a row
        // below, which is read as a row.
        const name = source.quotedOnLine(checker, at) orelse continue;
        wanted.put(gpa, name, {}) catch @panic("out of memory");
    }

    const resolver = read(b, io, "src/sema/resolve.zig");
    const table = "const ambient_array_traits = ";
    const opened = std.mem.indexOf(u8, resolver, table) orelse
        @panic("the resolver no longer states which traits it implements itself");
    for (source.quotedIn(gpa, source.indentedUnder(resolver, opened + table.len))) |name| {
        wanted.put(gpa, name, {}) catch @panic("out of memory");
    }

    // The declarations tuple syntax names, which the resolver finds by
    // identity and every later pass reads from it.
    const tuples = "const tuple_names = ";
    const tuples_opened = std.mem.indexOf(u8, resolver, tuples) orelse
        @panic("the resolver no longer states which declarations tuple syntax names");
    for (source.quotedIn(gpa, source.indentedUnder(resolver, tuples_opened + tuples.len))) |name| {
        wanted.put(gpa, name, {}) catch @panic("out of memory");
    }

    if (wanted.count() == 0) @panic("the prelude gate found no lookup to read");

    // What the prelude publishes. A re-export names the module it came from,
    // and the name is what a program writes.
    var published: std.StringArrayHashMapUnmanaged(void) = .empty;
    const prelude = read(b, io, "std/std.lin");
    var lines = std.mem.splitScalar(u8, prelude, '\n');
    while (lines.next()) |line| {
        if (!std.mem.startsWith(u8, line, "pub use ")) continue;
        const path = std.mem.trim(u8, line["pub use ".len..], " \r");
        const dot = std.mem.lastIndexOfScalar(u8, path, '.') orelse continue;
        published.put(gpa, path[dot + 1 ..], {}) catch @panic("out of memory");
    }

    // What the semantics document says the prelude adds beyond the syntax.
    const semantics = read(b, io, "docs/linea-semantics.md");
    const vocabulary = source.tableNamesAfter(gpa, semantics, "**The core vocabulary**");
    if (vocabulary.len == 0) @panic("the prelude gate found no core-vocabulary table in docs/linea-semantics.md");
    var documented: std.StringArrayHashMapUnmanaged(void) = .empty;
    for (vocabulary) |name| documented.put(gpa, name, {}) catch @panic("out of memory");

    var failed = false;
    for (wanted.keys()) |name| {
        if (published.contains(name)) continue;
        std.debug.print(
            "prelude: the compiler looks up `{s}` and std/std.lin does not publish it\n",
            .{name},
        );
        failed = true;
    }
    for (published.keys()) |name| {
        if (wanted.contains(name) or documented.contains(name)) continue;
        std.debug.print(
            "prelude: std/std.lin publishes `{s}`, which no syntax requires and the " ++
                "core-vocabulary table in docs/linea-semantics.md does not list\n",
            .{name},
        );
        failed = true;
    }
    for (documented.keys()) |name| {
        if (!published.contains(name)) {
            std.debug.print(
                "prelude: docs/linea-semantics.md lists `{s}` as core vocabulary and std/std.lin does not publish it\n",
                .{name},
            );
            failed = true;
        }
        if (wanted.contains(name)) {
            std.debug.print(
                "prelude: docs/linea-semantics.md lists `{s}` as core vocabulary and the compiler looks it up for syntax\n",
                .{name},
            );
            failed = true;
        }
    }
    if (failed) @panic("the prelude and its documented vocabulary disagree");
}

/// Whether the runtime's trap messages are the compiler's trap kinds.
///
/// The two sides of a trap agree on a small integer: generated code passes
/// `@intFromEnum` of a `TrapKind`, and the runtime indexes `what[]` with it.
/// The number is the whole interface, so the tables must have the same length
/// in the same order saying the same words -- and nothing checks that but
/// this, because the compiler is Zig and the runtime is C, so neither can
/// read the other's table at compile time. A kind appended on one side only
/// is a trap reporting the wrong message, or reading past the table.
///
/// The kind's message is taken from `describe`'s arms by name, then ordered
/// by the enum's own member order: the integer is the member's position, not
/// the arm's, and a switch reordered without renumbering anything would
/// otherwise read as drift.
///
/// Deliberately coupled to the declaration's shape -- bare members before the
/// first `pub fn`, one arm per line. Reshaping `TrapKind` means reshaping
/// this gate, and the gate says so: a shape it cannot read is a panic naming
/// what moved, never a silent pass.
fn checkTheRuntimeSpeaksEveryTrapKind(b: *std.Build) void {
    const io = b.graph.io;
    const gpa = b.allocator;
    const read = struct {
        fn file(bb: *std.Build, i: anytype, path: []const u8) []const u8 {
            return bb.build_root.handle.readFileAlloc(i, path, bb.allocator, .limited(1 << 22)) catch
                std.debug.panic("the trap gate cannot read {s}", .{path});
        }
    }.file;

    const mir = read(b, io, "src/mir/mir.zig");
    const opened = std.mem.indexOf(u8, mir, "pub const TrapKind = enum(u8) {") orelse
        @panic("src/mir/mir.zig no longer declares TrapKind where the trap gate reads it");
    const body = source.indentedUnder(mir, opened);

    // The members, in declaration order: a bare name ending in a comma,
    // before the first function the enum declares.
    var members: std.ArrayList([]const u8) = .empty;
    var lines = std.mem.splitScalar(u8, body, '\n');
    while (lines.next()) |line| {
        const t = std.mem.trim(u8, line, " \r");
        if (std.mem.startsWith(u8, t, "pub fn")) break;
        if (t.len < 2 or t[t.len - 1] != ',' or std.mem.startsWith(u8, t, "//")) continue;
        const name = t[0 .. t.len - 1];
        var word = name.len > 0;
        for (name) |c| {
            if (!std.ascii.isAlphanumeric(c) and c != '_') word = false;
        }
        if (!word) continue;
        members.append(gpa, name) catch @panic("out of memory");
    }
    if (members.items.len == 0) @panic("the trap gate read no TrapKind members");

    // Each member's message, found by the arm that names it.
    var failed = false;
    var messages: std.ArrayList([]const u8) = .empty;
    for (members.items) |name| {
        const arm = std.fmt.allocPrint(gpa, ".{s} => ", .{name}) catch @panic("out of memory");
        const at = std.mem.indexOf(u8, body, arm) orelse {
            std.debug.print("trap: `describe` has no arm for `{s}`\n", .{name});
            failed = true;
            continue;
        };
        const said = source.quotedOnLine(body, at + arm.len) orelse {
            std.debug.print("trap: the arm for `{s}` names no message\n", .{name});
            failed = true;
            continue;
        };
        messages.append(gpa, said) catch @panic("out of memory");
    }

    const rt = read(b, io, "runtime/linea_rt.c");
    const table = std.mem.indexOf(u8, rt, "static const char *const what[] = {") orelse
        @panic("runtime/linea_rt.c no longer declares what[] where the trap gate reads it");
    const end = std.mem.indexOfPos(u8, rt, table, "};") orelse
        @panic("the trap gate cannot find the end of what[]");
    const spoken = source.quotedIn(gpa, rt[table..end]);

    if (spoken.len != messages.items.len) {
        std.debug.print(
            "trap: the compiler numbers {d} kinds and the runtime speaks {d}\n",
            .{ messages.items.len, spoken.len },
        );
        failed = true;
    }
    for (messages.items, 0..) |said, i| {
        if (i >= spoken.len) break;
        if (std.mem.eql(u8, said, spoken[i])) continue;
        std.debug.print(
            "trap: kind {d} is \"{s}\" to the compiler and \"{s}\" to the runtime\n",
            .{ i, said, spoken[i] },
        );
        failed = true;
    }
    if (failed) @panic("the runtime does not speak the compiler's trap kinds");
}

/// Whether std reads the runtime's I/O category numbers as the runtime
/// numbers them.
///
/// `linea_io_category` returns a small integer and `IoError.from_os` maps it to
/// a member by retyped literals, with a fallback arm for every number it does
/// not know. Std's enum has members the runtime never produces, so the ordinal
/// cannot stand in, and nothing else holds the two together: a category added
/// to the runtime and mapped nowhere reads as `Other` with no diagnostic.
fn checkTheRuntimeSpeaksEveryIoCategory(b: *std.Build) void {
    const io = b.graph.io;
    const header = b.build_root.handle.readFileAlloc(io, "runtime/io.h", b.allocator, .limited(1 << 22)) catch
        @panic("the io category gate cannot read runtime/io.h");
    const std_text = b.build_root.handle.readFileAlloc(io, "std/io/core/error.lin", b.allocator, .limited(1 << 22)) catch
        @panic("the io category gate cannot read std/io/core/error.lin");
    const found = source.ioCategoryDisagreements(b.allocator, header, std_text);
    for (found) |line| std.debug.print("io category: {s}\n", .{line});
    if (found.len != 0) @panic("std and the runtime disagree about the I/O categories");
}

/// Whether `docs/learn/errors.md` indexes exactly the diagnostics the guide
/// shows.
///
/// The page restates what the chapters paste -- every code, where it first
/// appears, and the section of the semantics that defines its rule -- so the
/// two drift the moment a chapter gains or loses an error. The page is computed
/// here from the chapters the guide's index links to and from the semantics,
/// and a page that differs is refused with the page it should be, which is then
/// pasted in by hand. A code the guide shows or names that no rule defines is
/// refused on its own, since no page could link it.
fn checkTheGuideIndexesItsErrors(b: *std.Build) void {
    const io = b.graph.io;
    const gpa = b.allocator;
    const read = struct {
        fn file(bb: *std.Build, i: anytype, path: []const u8) []const u8 {
            return bb.build_root.handle.readFileAlloc(i, path, bb.allocator, .limited(1 << 22)) catch
                std.debug.panic("the guide's error-index gate cannot read {s}", .{path});
        }
    }.file;

    const listed = source.guideChapters(gpa, read(b, io, "docs/learn/README.md"));
    if (listed.len == 0) @panic("the guide's error-index gate found no chapter in docs/learn/README.md");
    const chapters = gpa.alloc(source.GuideChapter, listed.len) catch @panic("out of memory");
    for (listed, chapters) |chapter, *filled| {
        filled.* = chapter;
        filled.text = read(b, io, b.pathJoin(&.{ "docs/learn", chapter.file }));
    }
    const index = source.guideErrorIndex(gpa, chapters, read(b, io, "docs/linea-semantics.md"));
    for (index.undefined_codes) |code| {
        std.debug.print("guide: the chapters show or name `{s}`, and no rule in docs/linea-semantics.md defines it\n", .{code});
    }
    for (index.unclassified) |bare| {
        std.debug.print(
            "guide: {s} writes `{s}` bare in a heading or a table row, where it cannot be told from a word; " ++
                "write it `[{s}]` or `` `{s}` ``: {s}\n",
            .{ bare.file, bare.code, bare.code, bare.code, bare.line },
        );
    }
    if (index.undefined_codes.len > 0) @panic("the guide names a diagnostic the semantics does not define");
    if (index.unclassified.len > 0) @panic("the guide writes a rule code the gate cannot classify");

    const page = read(b, io, "docs/learn/errors.md");
    const difference = source.firstDifference(index.page, page) orelse return;
    std.debug.print(
        "guide: docs/learn/errors.md does not index the errors the chapters show. Line {d} should read\n" ++
            "  {s}\nand reads\n  {s}\nThe whole page should read:\n\n{s}\n",
        .{ difference.number, difference.expected, difference.found, index.page },
    );
    @panic("docs/learn/errors.md is stale");
}

/// Whether the decision index agrees with itself about what refines what.
///
/// The index restates a standing the record owns, so the two can drift; the
/// records are append-only and the index is edited, which decides which way
/// they drift. A record's own `Status:` line is prose and its wording is not
/// worth matching, but the relations the index states are mechanical -- and a
/// relation has a direction, so every one of them is written twice by
/// construction and the two spellings must name each other.
///
/// This is what a bare eye does not do: a row saying "refined by 0042" reads
/// exactly like a row saying "refined by 0046", and the wrong one sat in the
/// index for a milestone naming a superseded record about parser nesting.
fn checkTheDecisionIndexIsReciprocal(b: *std.Build) void {
    const io = b.graph.io;
    const text = b.build_root.handle.readFileAlloc(
        io,
        "docs/adr/README.md",
        b.allocator,
        .limited(1 << 22),
    ) catch @panic("the decision index is missing");

    const rows = source.indexRows(b.allocator, text);

    // Before a single relation is resolved. Resolution takes the first row
    // carrying a number, so under a duplicate every complaint below is about
    // whichever record sorted earlier rather than the one that stated the
    // relation -- the gate stays red and stops naming what is wrong.
    if (source.numberClaimedTwice(b.allocator, rows)) |number| {
        std.debug.print(
            "decisions: {s} names two records, so a reference to it has two referents\n",
            .{number},
        );
        @panic("a decision number names two records");
    }

    var complaints: std.ArrayList([]const u8) = .empty;
    for (rows) |row| {
        var at: usize = 0;
        while (source.findRelation(row.status, at)) |found| {
            at = found.after;

            // Every record the relation names, not the first: "extends 0029
            // and 0055" states one relation about two records, and each of
            // them has to state it back.
            var targets: source.Numbers = .{ .rest = found.targets };
            while (targets.next()) |target| {
                const other = for (rows) |r| {
                    if (std.mem.eql(u8, r.number, target)) break r;
                } else {
                    complaints.append(b.allocator, b.fmt(
                        "{s} is {s} {s}, which the index does not list",
                        .{ row.number, found.says, target },
                    )) catch @panic("OOM");
                    continue;
                };

                if (!source.statesRelation(other.status, found.back, row.number)) {
                    complaints.append(b.allocator, b.fmt(
                        "{s} says \"{s} {s}\", but {s} does not say \"{s} {s}\" -- it says \"{s}\"",
                        .{ row.number, found.says, target, target, found.back, row.number, other.status },
                    )) catch @panic("OOM");
                }
            }
        }
    }

    if (complaints.items.len == 0) return;
    std.debug.print("decisions: the index disagrees with itself\n", .{});
    for (complaints.items) |c| std.debug.print("  {s}\n", .{c});
    @panic("the decision index is not reciprocal");
}

/// Whether every property the conformance runner reports accounts for what it
/// counted.
///
/// A property that counts on its own is the defect this project makes most
/// often, and it is invisible from the outside: a check with a counter beside
/// it and a line reporting the number reads exactly like one asked of the whole
/// corpus, and the number it prints is true. What is missing is the population
/// -- so a property asked of two programs while its line says the corpus keeps
/// saying so, and every one of them was found by a reading rather than by a
/// run.
///
/// The runner's answer to that is `Property`: a member carries a population, is
/// counted through `tally` onto one of the two sides, and the loop that reports
/// the counts checks `accountsFor` -- `checked + passed_over` against the
/// population, by equality. This holds the runner to using it: a member nothing
/// tallies is counted somewhere else or not at all, and either way the printed
/// line answers to nothing.
///
/// One pass over the runner's text per member, and the runner is one file.
///
/// What this establishes is that the accounting is *called*, and not that the
/// population it is called with is the right one: a property can name a
/// population smaller than what it claims and account for it perfectly. That
/// still rests on someone reading `populationIn`. So does a count kept outside
/// the enum entirely -- a counter of its own with a `conformance:` line beside
/// it is what this gate wants a property written as instead, and it cannot tell
/// one from an informational line.
fn checkEveryPropertyAccountsForItself(b: *std.Build) void {
    const io = b.graph.io;
    const runner = b.build_root.handle.readFileAlloc(
        io,
        "src/conformance_main.zig",
        b.allocator,
        .limited(1 << 22),
    ) catch @panic("the conformance runner is missing");

    const accounting = source.accountingOf(b.allocator, runner, "Property", "tally");
    // Nothing declared is this gate reading a file it no longer understands.
    // Silence is what it exists to stop, so it does not answer with its own.
    if (accounting.declared == 0) @panic("the conformance runner declares no properties");

    var failed = false;
    for (accounting.uncounted) |property| {
        std.debug.print(
            "property: nothing tallies `{s}`, so the run accounts for nothing it counted\n",
            .{property},
        );
        failed = true;
    }
    if (!source.reportsAndAccounts(b.allocator, runner, "Property", "conformance:", "accountsFor")) {
        std.debug.print(
            "property: the run reports what each property counted and holds it to no population\n",
            .{},
        );
        failed = true;
    }
    if (failed) @panic("a property counts without accounting for what it counted");
}

/// What a directory under `src/` is, and therefore what it may import.
///
/// A pass may not import the driver: the driver imports every pass, so an
/// import back closes a cycle. A harness drives the compiler from outside and
/// may -- the conformance runner has to build a module the way the compiler
/// does, and asking the driver is the alternative to keeping a second copy of
/// its pass order.
///
/// Every directory is named. A new one is a build failure until someone says
/// which it is, because there is no safe default: calling it a pass exempts a
/// harness from nothing and calls a legitimate import a violation, while
/// calling it a harness lets a real pass import the driver unremarked -- and
/// that one is silent, which is the direction this gate exists to stop.
///
/// One import runs the other way and is not checked here: `mir/verify.zig`
/// reaches the generator in `conformance/` for its fuzz target, which needs
/// programs that are well-typed by construction. Zig has no test-only import,
/// and the target has to sit in the binary a fuzzing run keeps -- which is the
/// unit tests rather than the conformance runner's own.
const Layer = enum { pass, harness };

const layers = [_]struct { dir: []const u8, is: Layer }{
    .{ .dir = "backend", .is = .pass },
    .{ .dir = "conformance", .is = .harness },
    .{ .dir = "diagnostics", .is = .pass },
    .{ .dir = "driver", .is = .harness },
    .{ .dir = "fmt", .is = .pass },
    .{ .dir = "lexer", .is = .pass },
    .{ .dir = "lsp", .is = .harness },
    .{ .dir = "mir", .is = .pass },
    .{ .dir = "ownership", .is = .pass },
    .{ .dir = "parser", .is = .pass },
    .{ .dir = "sema", .is = .pass },
    .{ .dir = "support", .is = .pass },
    .{ .dir = "syntax", .is = .pass },
};

/// A tree of Zig source these gates read, and what a root of it is.
///
/// Two of them: the compiler under `src/`, and under `build/` the analysis the
/// gates themselves are written in. The second is held to the same rules for
/// the reason it exists -- it was extracted so a heuristic deciding whether a
/// build fails could be run against cases, and a dead declaration in the file
/// that reports dead declarations is the same defect as one anywhere else.
///
/// The layering rule is `src/`'s alone, and not by exemption: it says which
/// directory under a tree is a pass and which is a harness, and `build/` holds
/// neither. It is read by `build.zig` before a compiler exists.
const Tree = struct {
    dir: []const u8,
    /// The files a test build is rooted at. Each names, in a `comptime` block,
    /// every file whose tests it wants compiled.
    roots: []const []const u8,
    /// A file outside the tree that imports into it, or null where none does.
    /// The build script is what names `build/`'s module and is part of no tree
    /// it reads.
    imported_by: ?[]const u8 = null,
    /// Whether this tree's directories are passes and harnesses.
    layered: bool,
    /// The manifests whose direct `comptime` imports make test-bearing files
    /// part of the tree's test universe.
    test_manifests: []const []const u8,
    /// One test root joining several manifests into one Zig module.
    joined: ?struct { root: []const u8, manifests: []const []const u8 } = null,
};

const trees = [_]Tree{
    .{
        .dir = "src",
        .roots = &.{ "main.zig", "conformance_main.zig", "test_main.zig" },
        .layered = true,
        .test_manifests = &.{ "main.zig", "conformance_main.zig" },
        .joined = .{ .root = "test_main.zig", .manifests = &.{ "main.zig", "conformance_main.zig" } },
    },
    .{
        .dir = "build",
        .roots = &.{ "source_test.zig", "guide_gate.zig" },
        .imported_by = "build.zig",
        .layered = false,
        .test_manifests = &.{"source_test.zig"},
    },
    .{
        .dir = "runtime",
        .roots = &.{"float.zig"},
        .layered = false,
        .test_manifests = &.{"float.zig"},
    },
};

/// Four things the project's own source is held to, from one reading of each
/// tree.
///
/// Each exists because nothing else can catch it. Zig reports an unused local
/// and says nothing about a declaration nobody names, or a file nobody imports;
/// and a cycle in the module graph is a compile error while a pass importing the
/// driver is not.
fn checkTheCompilerIsTidy(b: *std.Build) void {
    var failed = false;
    for (trees) |tree| checkTreeIsTidy(b, tree, &failed);
    if (failed) @panic("the compiler's source is not tidy");
}

fn checkTreeIsTidy(b: *std.Build, tree: Tree, failed: *bool) void {
    const files = source.compilerSource(b.allocator, b.graph.io, b.build_root.handle, tree.dir);

    if (tree.joined) |joined| {
        const root = for (files) |file| {
            if (std.mem.eql(u8, file.path, joined.root)) break file;
        } else {
            std.debug.print("test root: {s}/{s} is missing\n", .{ tree.dir, joined.root });
            failed.* = true;
            return;
        };
        if (!source.importsExactly(b.allocator, root, joined.manifests, files)) {
            std.debug.print("test root: {s}/{s} does not import exactly its test manifests\n", .{ tree.dir, joined.root });
            failed.* = true;
        }
    }

    // A pass may not import the driver.
    //
    // Every other layering constraint is a compile error, because a cycle in
    // the graph is one. This is the shape Zig permits between separate files,
    // so the rule survives only as long as someone remembers it -- and it did
    // not: two files reached through the driver for renderers sitting in it.
    // The driver composes and does not decide, so a pass with a question for it
    // is a pass asking about a decision that should not live there.
    if (tree.layered) for (files) |f| {
        // The entry point and the conformance runner drive the compiler rather
        // than being part of it, and asking the driver what its command line
        // offers is a question only it can answer.
        const cut = std.mem.indexOfScalar(u8, f.path, '/') orelse continue;

        const layer = for (layers) |l| {
            if (std.mem.eql(u8, l.dir, f.path[0..cut])) break l.is;
        } else {
            std.debug.print("layering: {s}/{s}/ is neither a pass nor a harness\n", .{ tree.dir, f.path[0..cut] });
            failed.* = true;
            continue;
        };
        if (layer == .harness) continue;

        // Every file of the driver, rather than its entry point alone: the
        // loader and the toolchain close the same cycle, and a gate naming one
        // file reads as a gate on the directory while being a gate on a
        // filename.
        if (std.mem.indexOf(u8, f.text, "driver/") == null) continue;
        std.debug.print("layering: a pass may not import the driver -- {s}/{s}\n", .{ tree.dir, f.path });
        failed.* = true;
    };

    // A file nothing imports is a file nothing runs.
    //
    // The two roots are named in this file as root source files rather than
    // imported, which is what makes them roots.
    //
    // Matched on the path an `@import` resolves to, not on the basename it
    // ends with. `src/` holds three `dump.zig`: under a basename match, any
    // one of them being imported answered for all three, so a dead one was
    // reported live by a live sibling it has nothing to do with. The loop
    // already excluded itself by path, so the two identities in one comparison
    // were the whole defect.
    // A file outside the tree that imports into it, read once. Its imports name
    // the tree by the path the build root holds it under, which is what the
    // comparison below is against.
    const outside: ?source.SourceFile = if (tree.imported_by) |path| .{
        .path = path,
        .text = b.build_root.handle.readFileAlloc(b.graph.io, path, b.allocator, .limited(1 << 22)) catch
            @panic("the file that imports this tree is missing"),
    } else null;

    // Every path some other file imports, collected in one pass over each
    // file rather than by asking every file about every other.
    var imported_paths: std.StringHashMapUnmanaged(void) = .empty;
    for (files) |other| {
        for (source.importedPaths(b.allocator, other)) |path| {
            if (std.mem.eql(u8, path, other.path)) continue;
            imported_paths.put(b.allocator, path, {}) catch @panic("out of memory");
        }
    }
    const outside_paths: []const []const u8 = if (outside) |script| source.importedPaths(b.allocator, script) else &.{};

    for (files) |f| {
        const root = for (tree.roots) |name| {
            if (std.mem.eql(u8, f.path, name)) break true;
        } else false;
        if (root) continue;

        var imported = imported_paths.contains(f.path);
        if (!imported) {
            const from_outside = b.fmt("{s}/{s}", .{ tree.dir, f.path });
            for (outside_paths) |path| {
                if (std.mem.eql(u8, path, from_outside)) imported = true;
            }
        }
        if (imported) continue;
        std.debug.print("dead file: nothing imports {s}/{s}\n", .{ tree.dir, f.path });
        failed.* = true;
    }

    // A file holding tests that no root's `comptime` block names.
    //
    // Zig analyses a file only where something in it is used, and a test build
    // never analyses `main` -- so a module reached solely from another module's
    // code is a module whose `test` blocks compile to nothing at all. The
    // roots name every such file in a `comptime` block for exactly that
    // reason, and nothing held them to it: a file added under `src/lsp/` with
    // a deliberately failing test in it compiled to nothing, `zig build test`
    // reported `All 0 tests passed`, and the build stayed green.
    //
    // The check above cannot stand in for this one. It is satisfied by any
    // importer at all, and being imported is what the unnamed file already
    // was.
    for (files) |f| {
        if (std.mem.indexOf(u8, f.text, "\ntest ") == null) continue;

        var named = false;
        for (tree.test_manifests) |name| {
            if (std.mem.eql(u8, f.path, name)) {
                named = true;
                break;
            }
            const root = for (files) |r| {
                if (std.mem.eql(u8, r.path, name)) break r;
            } else continue;
            if (source.importsPath(b.allocator, .{ .path = root.path, .text = source.comptimeBlock(root.text) }, f.path)) {
                named = true;
                break;
            }
        }
        if (named) continue;
        std.debug.print("untested file: no root names {s}/{s}, so its tests never compile\n", .{ tree.dir, f.path });
        failed.* = true;
    }

    // A container holding tests that no file-level `comptime` block names.
    //
    // A test inside a struct compiles only once something makes the compiler
    // look inside that struct, and a filtered build keeps nothing that would:
    // a run filtered to such a test reported nothing and passed. A test in a
    // container a function builds or holds has no name to write there, so it
    // is refused outright.
    for (files) |f| {
        if (std.mem.indexOf(u8, f.text, "    test ") == null) continue;
        for (source.unreachedNestedTests(b.allocator, f.text)) |path| {
            std.debug.print("unreached tests: {s}/{s} holds tests in `{s}`, which no `comptime {{ _ = {s}; }}` names\n", .{ tree.dir, f.path, path, path });
            failed.* = true;
        }
    }

    // A declaration nobody names.
    //
    // [N-Unused] makes this an error in the language this compiler implements,
    // and the compiler was exempt from its own rule: Zig reports an unused
    // local and accepts a private function nothing calls, forever. Private
    // declarations only, because those are the ones whose every use is in the
    // file that declares them.
    //
    // One pass over the text rather than over a tree, so a name reached by
    // anything but being written is missed. That is the same heuristic and the
    // same limit the reserved-word gates have, and it is worth what it costs:
    // it holds today and fails the moment something stops being named.
    for (files) |f| {
        const counts = source.wordCounts(b.allocator, f.text);
        var lines = std.mem.splitScalar(u8, f.text, '\n');
        while (lines.next()) |line| {
            const name = source.privateDeclaration(line) orelse continue;
            if ((counts.get(name) orelse 0) > 1) continue;
            std.debug.print("dead declaration: nothing names `{s}` in {s}/{s}\n", .{ name, tree.dir, f.path });
            failed.* = true;
        }
    }
}

/// The gates that hold the documentation to the compiler and to itself: the
/// decision index, the guide's index of errors, and the prelude's
/// documentation. Each prints what it found and stops the build.
fn checkTheDocumentation(step: *std.Build.Step, options: std.Build.Step.MakeOptions) anyerror!void {
    _ = options;
    const b = step.owner;
    checkTheDecisionIndexIsReciprocal(b);
    checkTheGuideIndexesItsErrors(b);
    checkThePreludeIsDocumented(b);
}

/// Every heavy step a suite runs, made by one routine each.
///
/// The suites share one of each. A sequential run (`-Dsequential`) asks for
/// copies of its own and chains them, so the order it adds is held by steps
/// only that run reaches: another top-level step gains nothing from it. A copy
/// of a compile is the same compilation, so it reuses the cached result.
const HeavySteps = struct {
    b: *std.Build,
    compiler_module: *std.Build.Module,
    runner_module: *std.Build.Module,
    unit_module: *std.Build.Module,
    /// The runtime archives a compiler links, which must exist before it is
    /// built.
    runtime_steps: [2]*std.Build.Step,
    /// The runtime archives installed beside the compiler, where an installed
    /// compiler looks for them.
    runtime_installs: [2]*std.Build.Step,
    generate_grammar: *std.Build.Step,
    guide_gate: *std.Build.Step.Compile,
    checked_runtime_archive: std.Build.LazyPath,
    test_filters: []const []const u8,
    scratch: []const u8,
    walkers: ?u32,
    sanitize: Sanitize,
    programs: u32,
    seed: u64,
    update: bool,
    opt_levels: bool,

    fn compiler(self: *const HeavySteps) *std.Build.Step.Compile {
        const exe = self.b.addExecutable(.{ .name = "linea", .root_module = self.compiler_module });
        // A build cannot run before the libraries it links exist.
        for (self.runtime_steps) |step| exe.step.dependOn(step);
        return exe;
    }

    fn runner(self: *const HeavySteps) *std.Build.Step.Compile {
        return self.b.addExecutable(.{ .name = "conformance", .root_module = self.runner_module });
    }

    fn unitTests(self: *const HeavySteps) *std.Build.Step.Compile {
        const tests = self.b.addTest(.{ .root_module = self.unit_module, .filters = self.test_filters });
        tests.step.dependOn(self.generate_grammar);
        return tests;
    }

    fn unitRun(self: *const HeavySteps, tests: *std.Build.Step.Compile) *std.Build.Step.Run {
        return self.b.addRunArtifact(tests);
    }

    fn corpus(self: *const HeavySteps, runner_step: *std.Build.Step.Compile, compiler_step: *std.Build.Step.Compile) *std.Build.Step.Run {
        const b = self.b;
        const run = b.addRunArtifact(runner_step);
        run.addArg(b.pathFromRoot("tests"));
        // The runner builds and runs generated programs, so it is told where the
        // runtime is and where to put intermediates. It does not run from an
        // install tree and cannot find either on its own.
        run.addArg("--compiler");
        run.addFileArg(compiler_step.getEmittedBin());
        run.addArg("--runtime");
        run.addFileArg(self.checked_runtime_archive);
        run.addArg("--scratch");
        // Deliberately outside the build cache. A recorded outcome is keyed on the
        // emitted IR, the runtime, the commands a build assembles and a stamp of
        // each tool it runs them with -- where the tool resolved on `PATH`, and the
        // size and modification time of the file there, rather than its bytes. That
        // identifies a toolchain on one machine and not across machines, where the
        // same size and time can name different bytes, so the outcomes must not
        // travel the way a cached build directory does.
        run.addArg(self.scratch);
        if (self.walkers) |n| {
            run.addArg("--walkers");
            run.addArg(b.fmt("{d}", .{n}));
        }
        run.addArg("--sanitize");
        run.addArg(@tagName(self.sanitize));
        // A sanitized run watches what runs: the cases that record an exit
        // status, the examples, and the transcripts that build or run a program.
        // The generated code is not instrumented (see `Sanitize`), so what it
        // watches is the runtime, every allocation and free, and a leak check at
        // each clean exit. The runner leaves every other case, and the
        // corpus-wide frontend and editor properties, to the unsanitized walk.
        // Generated programs are held to the metamorphic properties beside the
        // corpus. The seeds are consecutive from zero, so a run generates the same
        // programs as the last one and their outcomes stay cached -- the cost is
        // paid once rather than on every build. A sanitized run generates none.
        // Only a run over the whole corpus can be held to what each rewrite must
        // reach, and a sanitized run is not one. Held to the floors anyway it
        // would report that a rule nobody narrowed away had stopped being covered.
        if (self.sanitize == .none) run.addArg("--floors");
        run.addArg("--programs");
        run.addArg(b.fmt("{d}", .{if (self.sanitize == .none) self.programs else 0}));
        run.addArg("--seed");
        run.addArg(b.fmt("{d}", .{self.seed}));
        if (self.update) run.addArg("--update");
        // A run over the whole corpus must have found something for every
        // metamorphic property. The examples run below is a smaller set on purpose
        // and is not held to it, and neither is a sanitized run, for the same
        // reason: a property finding nothing there is a statement about what was
        // built, not about the property.
        if (self.sanitize == .none) run.addArg("--every-property");
        if (self.opt_levels) run.addArg("--levels");
        // Golden files change on disk between runs, so the result is never cacheable.
        run.has_side_effects = true;
        return run;
    }

    fn properties(self: *const HeavySteps, runner_step: *std.Build.Step.Compile, compiler_step: *std.Build.Step.Compile) *std.Build.Step.Run {
        const b = self.b;
        const run = b.addRunArtifact(runner_step);
        run.addArg(b.pathFromRoot("tests"));
        run.addArgs(&.{ "--properties", "--property-cases", b.pathFromRoot("build/property-cases.txt"), "--every-property" });
        run.addArg("--compiler");
        run.addFileArg(compiler_step.getEmittedBin());
        run.addArg("--runtime");
        run.addFileArg(self.checked_runtime_archive);
        run.addArgs(&.{ "--scratch", b.pathJoin(&.{ self.scratch, "properties" }), "--sanitize", @tagName(self.sanitize) });
        if (self.walkers) |n| run.addArgs(&.{ "--walkers", b.fmt("{d}", .{n}) });
        run.has_side_effects = true;
        return run;
    }

    /// The examples are held to the same standard as the corpus: they are
    /// built and run, so one cannot quietly stop compiling as the language
    /// moves. Their goldens sit in `tests/examples/`, which the corpus walk
    /// leaves to this one.
    fn examples(self: *const HeavySteps, runner_step: *std.Build.Step.Compile) *std.Build.Step.Run {
        const b = self.b;
        const run = b.addRunArtifact(runner_step);
        run.addArg(b.pathFromRoot("examples"));
        run.addArg("--runtime");
        run.addFileArg(self.checked_runtime_archive);
        run.addArg("--scratch");
        // Both corpus processes number their LSP fixtures from zero and clear
        // that directory on startup, so concurrent walks need separate roots.
        run.addArg(b.pathJoin(&.{ self.scratch, "examples" }));
        run.addArg("--sanitize");
        run.addArg(@tagName(self.sanitize));
        if (self.update) run.addArg("--update");
        run.has_side_effects = true;
        return run;
    }

    /// Every complete program the guide pastes is compiled, and the output
    /// pasted beside it is held to what the compiler prints. The guide shows
    /// real errors and real output, so a compiler change that moves one makes
    /// the page false without any test noticing. It stands beside the
    /// error-index check but runs the compiler, so it is a step of the suites
    /// that build the compiler, and `zig build` alone never pays for it.
    ///
    /// `installed` puts the compiler and its runtime where the gate runs it.
    fn guide(self: *const HeavySteps, installed: *std.Build.Step) *std.Build.Step.Run {
        const b = self.b;
        const run = b.addRunArtifact(self.guide_gate);
        run.addArg(b.pathFromRoot("docs/learn"));
        // The installed compiler finds the runtime beside itself.
        run.addArg(b.getInstallPath(.bin, "linea"));
        run.step.dependOn(installed);
        // The installed runtime is the sanitized one, so the compiler it runs
        // has to be told which sanitizer the link must name.
        if (toolchain.sanitizeVariable(self.sanitize.flag())) |variable| run.setEnvironmentVariable(variable.name, variable.value);
        run.addArg(b.pathJoin(&.{ self.scratch, "guide" }));
        run.addArg(b.pathFromRoot("tests"));
        if (self.walkers) |n| run.addArg(b.fmt("{d}", .{n}));
        run.has_side_effects = true;
        return run;
    }

    /// Fresh copies of the heavy steps `order` names, each waiting for the
    /// one before it; returns the last, or null when there are none.
    fn sequence(self: *const HeavySteps, order: []const test_roots.Heavy) ?*std.Build.Step {
        var compiler_copy: ?*std.Build.Step.Compile = null;
        var runner_copy: ?*std.Build.Step.Compile = null;
        var unit_copy: ?*std.Build.Step.Compile = null;
        var earlier: ?*std.Build.Step = null;
        for (order) |heavy| {
            const this: *std.Build.Step = switch (heavy) {
                .compile_compiler => step: {
                    compiler_copy = self.compiler();
                    break :step &compiler_copy.?.step;
                },
                .compile_runner => step: {
                    runner_copy = self.runner();
                    break :step &runner_copy.?.step;
                },
                .compile_unit_tests => step: {
                    unit_copy = self.unitTests();
                    break :step &unit_copy.?.step;
                },
                .unit_tests => &self.unitRun(unit_copy.?).step,
                .corpus => &self.corpus(runner_copy.?, compiler_copy.?).step,
                .properties => &self.properties(runner_copy.?, compiler_copy.?).step,
                .examples => &self.examples(runner_copy.?).step,
                .guide => step: {
                    const install = self.b.addInstallArtifact(compiler_copy.?, .{});
                    for (self.runtime_installs) |runtime_install| install.step.dependOn(runtime_install);
                    break :step &self.guide(&install.step).step;
                },
            };
            if (earlier) |before| this.dependOn(before);
            earlier = this;
        }
        return earlier;
    }
};

pub fn build(b: *std.Build) void {
    checkTheCompilerIsTidy(b);
    checkEveryPropertyAccountsForItself(b);
    checkTheEditorIndentsByWhatTheFormatterDoes(b);
    checkCiRunsEverySanitizer(b);
    checkTheRuntimeSpeaksEveryTrapKind(b);
    checkTheRuntimeSpeaksEveryIoCategory(b);
    const target = b.standardTargetOptions(.{});
    // `zig build` stays a debug build for the edit-compile loop, and
    // `zig build -Drelease` is the distributed one. The unit tests run in the
    // mode the build selects: Debug here, ReleaseFast in the optimised CI lane.
    const optimize = test_roots.optimizeMode(b.release_mode, b.option(bool, "release", "optimize for end users"));

    // Where recorded outcomes and build intermediates go.
    //
    // Overridable because `actions/checkout` runs `git clean -ffdx`, which
    // deletes anything under the workspace between runs. On a persistent
    // machine that throws away the one cache that makes a second run cheap --
    // and a persistent machine is exactly where the cache is *valid*, since a
    // recorded outcome is keyed on a stamp of each tool as that machine sees
    // it. Pointed outside the workspace, the outcomes survive the clean while
    // the checkout stays honest.
    // Tracy, off unless asked for.
    //
    // The suite's own timers answer how long a phase took, summed over a run.
    // They cannot answer why a thread was not running, because a thread that
    // is blocked is inside the phase that blocked it and looks the same as one
    // doing work. That question came up with a 42-second hole no amount of
    // bracketing would localise, and a timeline per thread is the instrument
    // for it.
    //
    // Off by default and absent from the binary when off: this is for
    // answering a question, not a thing the suite carries.
    const profiling = b.option(bool, "tracy", "Build with Tracy zones") orelse false;
    const tracy_options = b.addOptions();
    tracy_options.addOption(bool, "tracy", profiling);

    // How many walkers the corpus is divided between. Defaults to one per core.
    //
    // Worth naming because this box is not the only consumer: CI runs several
    // jobs on one machine, so a run that takes every core makes the other jobs
    // wait for it. It is also the only way to measure what the parallelism is
    // actually buying, by asking for one.
    const walkers = b.option(u32, "walkers", "How many workers walk the corpus (default: one per core)");

    const scratch = b.option(
        []const u8,
        "scratch",
        "Where recorded outcomes and build intermediates go (default: .zig-cache/conformance-scratch)",
    ) orelse b.pathFromRoot(".zig-cache/conformance-scratch");

    const sanitize = b.option(
        Sanitize,
        "sanitize",
        "Build the runtime library with a sanitizer and link every program with it; generated code is not instrumented",
    ) orelse .none;

    const update_goldens = b.option(
        bool,
        "update",
        "Rewrite conformance expectations instead of failing",
    ) orelse false;

    // Narrows the Zig test binaries to tests whose name contains a substring.
    // Integration gates without named tests are excluded; pointing the
    // conformance executable at a narrower directory is how one corpus case is
    // isolated.
    const test_filter = b.option(
        []const u8,
        "test-filter",
        "Run only unit tests whose name contains this substring",
    );
    const test_filters: []const []const u8 =
        if (test_filter) |f| &.{f} else &.{};
    const fuzz_filter = b.option(
        []const u8,
        "fuzz-filter",
        "Run only fuzz targets whose name contains this text",
    );
    const sweep_filter = b.option(
        []const u8,
        "sweep-filter",
        "Run only release sweep dimensions whose names contain this text",
    );
    // How many programs the generator supplies to the metamorphic properties.
    // Enough by default that a regression is caught, and raised for a run that
    // is looking rather than checking.
    const programs = b.option(
        u32,
        "programs",
        "How many generated programs to check against the metamorphic properties",
    ) orelse 32;

    // Where the seed sequence starts. Zero by default, so an ordinary run
    // generates the programs the last one did and their outcomes stay cached.
    // A run that is looking rather than checking moves the window: seeds are
    // consecutive from here, so a failure still names one number that
    // reproduces it, and nightly ground nobody has walked costs only the cache
    // it gives up.
    const seed = b.option(
        u64,
        "seed",
        "The first seed the generator uses, for a run that wants new programs",
    ) orelse 0;

    // How many generated storage programs the soundness step checks, each
    // with its mutants. Seeds start at `-Dseed` as the generated programs'
    // do, so an ordinary run checks the same programs as the last one and
    // serves them from the outcome cache.
    const storage_programs = b.option(
        u32,
        "storage-programs",
        "How many generated storage programs, with their mutants, the soundness step checks",
    ) orelse 16;

    // Whether the soundness step checks the matrix as well as the generated
    // programs. A search over new seeds leaves it out: its cells are the same
    // whatever the seed.
    const soundness_matrix = b.option(
        bool,
        "soundness-matrix",
        "Check the soundness matrix as well as the generated storage programs (default: true)",
    ) orelse true;

    // The conformance runner compiles and rewrites generated programs in
    // process; the generated-program phase of a Debug runner takes several
    // times as long as a ReleaseSafe one's. The compiler under test and the
    // unit tests keep the optimisation level the build selects.
    const safe_runner = b.option(
        bool,
        "safe-runner",
        "Build the conformance runner with ReleaseSafe when the build would otherwise be Debug",
    ) orelse false;

    // Each heavy step of a suite holds several gigabytes -- a compile of the
    // compiler, of the conformance runner or of the unit tests, the unit
    // tests, the corpus walk and the walks beside it -- and a machine of
    // seven, such as a hosted CI runner, cannot hold two at once. `-j1` does
    // not stop them overlapping, so this orders them one after another, in
    // whichever of the test suites is asked for (`test`, `test-corpus`,
    // `test-support`, `test-unit`, `conformance`). The build runner's
    // `--maxrss` would too, but on Zig 0.16 a step it holds back is started
    // without counting against the limit.
    const sequential = b.option(
        bool,
        "sequential",
        "Run a test suite's heavy steps one after another, for a machine with little memory",
    ) orelse false;

    // The guide compiles and runs about two hundred programs with the Debug
    // compiler. A pull request's `check` run leaves it to the `optimised` lane,
    // which runs before the pull request merges, and passes `-Dguide=false`;
    // everywhere else `test` runs it.
    const guide_in_test = b.option(
        bool,
        "guide",
        "Run the guide gate as part of `test` (default: true)",
    ) orelse true;

    // Every case that runs, built again at every other optimisation level and
    // held to answering alike. Off by default because it builds each case six
    // times rather than once; no CI lane sets it.
    const opt_levels = b.option(
        bool,
        "opt-levels",
        "Build every corpus case that runs at every optimisation level and hold it to answering alike",
    ) orelse false;

    // Install the runtime beside the compiler so generated programs can link
    // it without a source checkout. Ordinary builds trap on sanitizer failures;
    // instrumented builds link the reporting runtime selected below.
    var runtime_flags: std.ArrayList([]const u8) = .empty;
    runtime_flags.appendSlice(b.allocator, &.{
        "-std=c99",
        "-Wall",
        "-Wextra",
        "-Werror",
        "-pedantic",
        "-fsanitize=undefined",
        "-fsanitize=integer",
        "-fsanitize=implicit-conversion",
        "-fsanitize=local-bounds",
        "-fsanitize=nullability",
        // Platform constants differ in signedness between targets, and the
        // implicit-conversion trap above only fires on the target that
        // spells one unsigned. Warning here turns that into a build error on
        // every target the runtime is compiled for.
        "-Wconversion",
        "-Wsign-conversion",
    }) catch @panic("OOM");

    if (sanitize.flag()) |name| {
        // A sanitizer that reports has to be able to reach its reporting
        // routine, so trapping is off wherever one is selected. A trap would
        // abort with no account of what it found.
        runtime_flags.append(
            b.allocator,
            b.fmt("-fsanitize={s}", .{name}),
        ) catch @panic("OOM");
    } else {
        runtime_flags.append(b.allocator, "-fsanitize-trap=all") catch @panic("OOM");
    }

    var math_flags: std.ArrayList([]const u8) = .empty;
    math_flags.appendSlice(b.allocator, runtime_flags.items) catch @panic("OOM");
    math_flags.appendSlice(b.allocator, &.{
        "-std=c11",        "-fno-fast-math",        "-ffp-contract=off", "-frounding-math",
        "-ftrapping-math", "-fno-finite-math-only", "-fhonor-nans",      "-fno-math-errno",
    }) catch @panic("OOM");
    const native_math_step = b.step("test-native-math", "Check strict binary64 runtime operations against independent reference vectors");
    const native_math_module = b.createModule(.{ .target = target, .optimize = optimize, .link_libc = true });
    native_math_module.addCSourceFile(.{ .file = b.path("runtime/math.c"), .flags = math_flags.items });
    native_math_module.addIncludePath(b.path("runtime"));
    native_math_module.addCSourceFile(.{ .file = b.path("tests/native/math_test.c"), .flags = math_flags.items });
    if (target.result.os.tag == .linux) native_math_module.linkSystemLibrary("m", .{});
    const native_math_tests = b.addExecutable(.{ .name = "native-math-tests", .root_module = native_math_module });
    const run_native_math = b.addRunArtifact(native_math_tests);
    native_math_step.dependOn(&run_native_math.step);

    const native_io_step = b.step("test-native-io", "Check native byte transport and filesystem operations");
    inline for (.{ false, true }) |faults| {
        const native_io_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });
        var transport_flags: std.ArrayList([]const u8) = .empty;
        transport_flags.appendSlice(b.allocator, runtime_flags.items) catch @panic("OOM");
        if (faults) transport_flags.appendSlice(b.allocator, &.{
            "-Dread=linea_test_read",
            "-Dwrite=linea_test_write",
            "-Dclose=linea_test_close",
            "-Dgetentropy=linea_test_getentropy",
        }) catch @panic("OOM");
        native_io_module.addCSourceFile(.{
            .file = b.path("runtime/io.c"),
            .flags = transport_flags.items,
        });
        native_io_module.addCSourceFile(.{
            .file = b.path(if (faults) "runtime/io_fault_test.c" else "runtime/io_test.c"),
            .flags = runtime_flags.items,
        });
        // The fault tests stand in for the allocator to see what I/O reports
        // to it; the others link the allocator itself.
        if (!faults) native_io_module.addCSourceFile(.{ .file = b.path("runtime/linea_rt.c"), .flags = runtime_flags.items });
        const native_io_tests = b.addExecutable(.{
            .name = if (faults) "native-io-fault-tests" else "native-io-tests",
            .root_module = native_io_module,
        });
        const run_native_io = b.addRunArtifact(native_io_tests);
        native_io_step.dependOn(&run_native_io.step);
    }
    const native_net_step = b.step("test-native-net", "Check native socket listen, accept, connect and address operations");
    inline for (.{ false, true }) |faults| {
        const native_net_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });
        var socket_flags: std.ArrayList([]const u8) = .empty;
        socket_flags.appendSlice(b.allocator, runtime_flags.items) catch @panic("OOM");
        if (faults) socket_flags.appendSlice(b.allocator, &.{
            "-Dsocket=linea_test_socket",
            "-Dsetsockopt=linea_test_setsockopt",
            "-Dbind=linea_test_bind",
            "-Dlisten=linea_test_listen",
            "-Dfcntl=linea_test_fcntl",
            "-Daccept=linea_test_accept",
            "-Dconnect=linea_test_connect",
            "-Dgetpeername=linea_test_getpeername",
            "-Dgetsockname=linea_test_getsockname",
        }) catch @panic("OOM");
        native_net_module.addCSourceFile(.{
            .file = b.path("runtime/net.c"),
            .flags = socket_flags.items,
        });
        native_net_module.addCSourceFile(.{
            .file = b.path("runtime/io.c"),
            .flags = runtime_flags.items,
        });
        native_net_module.addCSourceFile(.{
            .file = b.path("runtime/linea_rt.c"),
            .flags = runtime_flags.items,
        });
        native_net_module.addCSourceFile(.{
            .file = b.path(if (faults) "runtime/net_fault_test.c" else "runtime/net_test.c"),
            .flags = runtime_flags.items,
        });
        const native_net_tests = b.addExecutable(.{
            .name = if (faults) "native-net-fault-tests" else "native-net-tests",
            .root_module = native_net_module,
        });
        const run_native_net = b.addRunArtifact(native_net_tests);
        native_net_step.dependOn(&run_native_net.step);
    }
    const native_clock_step = b.step("test-native-clock", "Check native clock reads and the monotonic sleep");
    inline for (.{ false, true }) |faults| {
        const native_clock_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });
        var clock_flags: std.ArrayList([]const u8) = .empty;
        clock_flags.appendSlice(b.allocator, runtime_flags.items) catch @panic("OOM");
        if (faults) clock_flags.appendSlice(b.allocator, &.{
            "-Dclock_gettime=linea_test_clock_gettime",
            "-Dnanosleep=linea_test_nanosleep",
        }) catch @panic("OOM");
        native_clock_module.addCSourceFile(.{
            .file = b.path("runtime/clock.c"),
            .flags = clock_flags.items,
        });
        native_clock_module.addCSourceFile(.{
            .file = b.path(if (faults) "runtime/clock_fault_test.c" else "runtime/clock_test.c"),
            .flags = runtime_flags.items,
        });
        const native_clock_tests = b.addExecutable(.{
            .name = if (faults) "native-clock-fault-tests" else "native-clock-tests",
            .root_module = native_clock_module,
        });
        const run_native_clock = b.addRunArtifact(native_clock_tests);
        native_clock_step.dependOn(&run_native_clock.step);
    }
    // A sanitized runtime leaves storage checking to the sanitizer, whose
    // shadow memory cannot see pages the checking allocator maps itself, so
    // the checking allocator is compiled only where no sanitizer is selected.
    var checked_flags: std.ArrayList([]const u8) = .empty;
    checked_flags.appendSlice(b.allocator, runtime_flags.items) catch @panic("OOM");
    if (sanitize == .none) checked_flags.append(b.allocator, "-DLINEA_CHECK_STORAGE=1") catch @panic("OOM");

    const native_runtime_step = b.step("test-native-runtime", "Check the generated-code runtime's allocation, arguments, environment and aborts");
    inline for (.{ false, true }) |checked| {
        const flags = if (checked) checked_flags.items else runtime_flags.items;
        const native_runtime_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });
        native_runtime_module.addCSourceFile(.{
            .file = b.path("runtime/linea_rt.c"),
            .flags = flags,
        });
        native_runtime_module.addCSourceFile(.{
            .file = b.path("runtime/linea_rt_test.c"),
            .flags = flags,
        });
        const native_runtime_tests = b.addExecutable(.{
            .name = if (checked) "native-checked-runtime-tests" else "native-runtime-tests",
            .root_module = native_runtime_module,
        });
        const run_native_runtime = b.addRunArtifact(native_runtime_tests);
        native_runtime_step.dependOn(&run_native_runtime.step);
    }

    // The runtime is compiled for Linux as well as for the host, so a platform
    // constant that is signed on one and unsigned on the other is a build
    // error on a macOS checkout and not a trap on the first Linux run.
    const linux_target = b.resolveTargetQuery(.{ .cpu_arch = .x86_64, .os_tag = .linux, .abi = .gnu });
    for ([_]struct { name: []const u8, file: []const u8, flags: []const []const u8 }{
        .{ .name = "linea_rt_linux", .file = "runtime/linea_rt.c", .flags = checked_flags.items },
        .{ .name = "io_linux", .file = "runtime/io.c", .flags = runtime_flags.items },
        .{ .name = "net_linux", .file = "runtime/net.c", .flags = runtime_flags.items },
        .{ .name = "clock_linux", .file = "runtime/clock.c", .flags = runtime_flags.items },
    }) |input| {
        native_runtime_step.dependOn(&runtimeObject(b, linux_target, input.name, b.path(input.file), input.flags).step);
    }

    // The runtime objects are compiled for the baseline CPU of the target
    // rather than the CPU of the machine building them. The outcome cache
    // hashes the archive's bytes, and the same source built for two CPU models
    // is two different archives, so a runner whose CPU model changed between
    // runs would discard every recorded outcome.
    const runtime_target = baselineCpu(b, target);

    // Compile Zig's Ryu formatter through C so ASan and MSan instrument its
    // memory accesses too. Passing Zig LLVM IR to Clang would not add the
    // function attributes that enable those checks.
    var float_target_query = runtime_target.query;
    float_target_query.ofmt = .c;
    const float_source = b.addObject(.{
        .name = "linea_float",
        .root_module = b.createModule(.{
            .root_source_file = b.path("runtime/float.zig"),
            .target = b.resolveTargetQuery(float_target_query),
            .optimize = .ReleaseSmall,
        }),
    });
    addDecimalProvider(b, float_source.root_module);
    var float_flags: std.ArrayList([]const u8) = .empty;
    float_flags.appendSlice(b.allocator, runtime_flags.items) catch @panic("OOM");
    float_flags.appendSlice(b.allocator, &.{
        "-std=c11",
        // Zig emits unused target metadata and implements wrapping operations
        // with defined unsigned C arithmetic. Keep all other runtime checks.
        "-Wno-unused-const-variable",
        "-Wno-conversion",
        "-Wno-sign-conversion",
        "-fno-sanitize=unsigned-integer-overflow",
    }) catch @panic("OOM");
    // Archive basenames in source order. Compiler-generated archives include
    // cache paths, which change outcome-cache keys without changing code.
    //
    // Two archives share every object but the one holding the allocator:
    // `linea test` and the conformance runner link the checking one, and
    // `linea build` and `linea run` the other unless asked to check.
    const runtime = b.addSystemCommand(&.{ b.graph.zig_exe, "ar", "rcsD" });
    const runtime_archive = runtime.addOutputFileArg(runtime_symbols.archive_name);
    const checked_runtime = b.addSystemCommand(&.{ b.graph.zig_exe, "ar", "rcsD" });
    const checked_runtime_archive = checked_runtime.addOutputFileArg(runtime_symbols.checked_archive_name);
    for ([_]struct { name: []const u8, file: std.Build.LazyPath, flags: []const []const u8, checked_flags: ?[]const []const u8 = null }{
        .{ .name = "linea_rt", .file = b.path("runtime/linea_rt.c"), .flags = runtime_flags.items, .checked_flags = checked_flags.items },
        .{ .name = "io", .file = b.path("runtime/io.c"), .flags = runtime_flags.items },
        .{ .name = "net", .file = b.path("runtime/net.c"), .flags = runtime_flags.items },
        .{ .name = "clock", .file = b.path("runtime/clock.c"), .flags = runtime_flags.items },
        .{ .name = "linea_float", .file = float_source.getEmittedBin(), .flags = float_flags.items },
        .{ .name = "math", .file = b.path("runtime/math.c"), .flags = math_flags.items },
    }) |input| {
        const object = runtimeObject(b, runtime_target, input.name, input.file, input.flags);
        runtime.addArtifactArg(object);
        checked_runtime.addArtifactArg(if (input.checked_flags) |flags| runtimeObject(b, runtime_target, input.name, input.file, flags) else object);
    }
    const runtime_installs = [_]*std.Build.Step{
        &b.addInstallLibFile(runtime_archive, runtime_symbols.archive_name).step,
        &b.addInstallLibFile(checked_runtime_archive, runtime_symbols.checked_archive_name).step,
    };
    for (runtime_installs) |install| b.getInstallStep().dependOn(install);
    b.getInstallStep().dependOn(&b.addInstallFile(b.path("runtime/zig-float-LICENSE"), "share/licenses/linea/Zig-MIT").step);

    // The compiler reads the runtime's source to check that the two agree on
    // what each trap kind means. Naming it here is what lets a test embed a
    // file from outside `src/`.
    const runtime_source = b.path("runtime/linea_rt.c");

    // A diagnostic's code is an index into the semantics, so a test reads the
    // document to check that every rule it can emit is actually written there.
    const semantics = b.path("docs/linea-semantics.md");

    // The standard library travels in the binary for the reason the semantics
    // does: what `std` names cannot depend on what sits beside the program.
    // Which files it is made of is read from the directory, so adding a module
    // is adding a directory and nothing else.
    const library = libraryManifest(b);

    // Every input the fuzzer has ever found, replayed by every run after it.
    // A list rather than a directory walk: the list is where a reader learns
    // what each input broke, which a filename cannot carry.
    const corpus = b.createModule(.{ .root_source_file = b.path("tests/fuzz/corpus.zig") });

    // The language server's protocol types. Named here rather than imported by
    // path, because it is a package rather than a file of this compiler.
    const lsp_kit = b.dependency("lsp_kit", .{ .target = target, .optimize = optimize });

    const compiler_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    addCompilerAssets(compiler_module, runtime_source, semantics, library, corpus, lsp_kit, tracy_options);
    linkTracyClient(b, compiler_module, profiling);
    // Filled in as each part it builds from is made; every heavy step below,
    // and each copy a sequential run orders, comes from it.
    var heavy: HeavySteps = .{
        .b = b,
        .compiler_module = compiler_module,
        .runtime_steps = .{ &runtime.step, &checked_runtime.step },
        .runtime_installs = runtime_installs,
        .checked_runtime_archive = checked_runtime_archive,
        .scratch = scratch,
        .walkers = walkers,
        .sanitize = sanitize,
        .programs = programs,
        .seed = seed,
        .update = update_goldens,
        .opt_levels = opt_levels,
        .test_filters = test_filters,
        .runner_module = undefined,
        .unit_module = undefined,
        .generate_grammar = undefined,
        .guide_gate = undefined,
    };
    const exe = heavy.compiler();
    b.installArtifact(exe);

    const run_step = b.step("run", "Run the compiler");
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);
    run_step.dependOn(&run_cmd.step);

    // The editor grammar is generated rather than committed, so the gates read
    // real output and no stale artefact can exist. `grammar.js` is the only
    // source of it in the tree.
    const ts_dir = tree_sitter_dir;

    // The CLI finds grammars through a per-user configuration, and what it
    // does without one depends on its version: some fall back to the grammar
    // in the working directory, and some parse nothing and exit 0 -- the
    // vacuous pass the refused chain below exists to catch, which it did, on
    // a runner whose home directory had never been configured. The build
    // writes its own configuration and points every invocation at it, so
    // the gates read the same grammar on every machine and no host's
    // dotfiles are part of the answer.
    const ts_config_dir = b.pathFromRoot(".zig-cache/tree-sitter");
    {
        const io = b.graph.io;
        b.build_root.handle.createDirPath(io, ".zig-cache/tree-sitter") catch {};
        b.build_root.handle.writeFile(io, .{
            .sub_path = ".zig-cache/tree-sitter/config.json",
            .data = b.fmt("{{\"parser-directories\": [\"{s}\"]}}", .{b.pathFromRoot("editor-support")}),
        }) catch {};
    }

    const generate_grammar = b.addSystemCommand(&.{ "tree-sitter", "generate", "-o", "src" });
    generate_grammar.setCwd(b.path(ts_dir));
    generate_grammar.setEnvironmentVariable("TREE_SITTER_DIR", ts_config_dir);
    // Declared so the step reruns when the source changes rather than never.
    generate_grammar.addFileInput(b.path(ts_dir ++ "/grammar.js"));
    generate_grammar.has_side_effects = true;

    // The conformance suite drives the real pipeline through a real binary,
    // so the goldens record what a user would see.
    const conformance_module = b.createModule(.{
        .root_source_file = b.path("src/conformance_main.zig"),
        .target = target,
        .optimize = if (safe_runner and optimize == .Debug) .ReleaseSafe else optimize,
    });
    addCompilerAssets(conformance_module, runtime_source, semantics, library, corpus, lsp_kit, tracy_options);
    linkTracyClient(b, conformance_module, profiling);

    heavy.runner_module = conformance_module;
    heavy.generate_grammar = &generate_grammar.step;
    const conformance = heavy.runner();
    const conformance_runner = b.step("conformance-runner", "Build the conformance runner for narrowed corpus checks");
    conformance_runner.dependOn(&b.addInstallArtifact(conformance, .{}).step);
    // Relative imports from `test_main` make shared compiler files one module
    // instance. The unit-only scope runs this same universe without integrations.
    const debug_test_module = joined: {
        const module = b.createModule(.{
            .root_source_file = b.path("src/test_main.zig"),
            .target = target,
            .optimize = optimize,
        });
        addCompilerAssets(module, runtime_source, semantics, library, corpus, lsp_kit, tracy_options);
        addConformanceAssets(b, module);
        linkTracyClient(b, module, profiling);
        break :joined module;
    };
    heavy.unit_module = debug_test_module;
    const debug_tests = heavy.unitTests();
    const run_debug_tests = heavy.unitRun(debug_tests);
    // Cache hashing reads declared inputs even when their tests are filtered
    // out. The same manifest reaches every fuzzer without editor assets.
    const fuzz_module = b.createModule(.{
        .root_source_file = debug_test_module.root_source_file,
        .target = target,
        .optimize = optimize,
    });
    addCompilerAssets(fuzz_module, runtime_source, semantics, library, corpus, lsp_kit, tracy_options);
    linkTracyClient(b, fuzz_module, profiling);
    // Every fuzz target by default. A target whose one input compiles whole
    // programs is named `fuzz-slow:` so it can be searched apart with a run
    // count of its own; `-Dfuzz-filter=fuzz:` or `-Dfuzz-filter=fuzz-slow:`
    // selects one group. CI searches only `fuzz:`, weekly.
    const fuzz_filters: []const []const u8 =
        if (fuzz_filter) |f| &.{f} else &.{ "fuzz:", "fuzz-slow:" };
    const fuzz_tests = b.addTest(.{ .root_module = fuzz_module, .filters = fuzz_filters });
    const run_fuzz_tests = b.addRunArtifact(fuzz_tests);

    const run_conformance = heavy.corpus(conformance, exe);

    // The soundness matrix, and generated programs over heap storage with
    // their mutants toward unsoundness. A live matrix program or a mutant must
    // be refused by the invalidation rule; acceptance is the failure, decided
    // before anything runs. An ended matrix program and a generated program
    // must be accepted, built, run clean and compute what they mean; each
    // generated program is also built at every optimisation level and held to
    // answering alike. Outcomes are cached by module, level and toolchain, so
    // a run over unchanged programs builds nothing. A selected sanitizer
    // watches the runtime, the allocator and crashes, not the generated code
    // (see `Sanitize`).
    //
    // Programs link the checking runtime, so a use of freed storage, a second
    // disposal or a store outside an allocation in an accepted program aborts
    // instead of passing.
    //
    // Programs are compiled in process against the checked library; only
    // what is accepted reaches the toolchain. A program that declares a
    // closure checks the library again, which is most of the cost: about a
    // minute with an optimised runner and six with a debug one, even with
    // every outcome cached. So it is a step of its own, run by the optimised
    // CI lane. `-Dsoundness-matrix=false` leaves the matrix out of a search
    // over new seeds, since the matrix does not depend on the seed.
    const run_soundness = b.addRunArtifact(conformance);
    run_soundness.addArg(b.pathFromRoot("tests"));
    run_soundness.addArgs(&.{ "--soundness", "--storage-programs", b.fmt("{d}", .{storage_programs}), "--seed", b.fmt("{d}", .{seed}) });
    if (!soundness_matrix) run_soundness.addArg("--skip-matrix");
    run_soundness.addArg("--runtime");
    run_soundness.addFileArg(checked_runtime_archive);
    run_soundness.addArgs(&.{ "--scratch", b.pathJoin(&.{ scratch, "soundness" }), "--sanitize", @tagName(sanitize) });
    if (walkers) |n| run_soundness.addArgs(&.{ "--walkers", b.fmt("{d}", .{n}) });
    run_soundness.has_side_effects = true;
    const soundness_step = b.step("soundness", "Check the soundness matrix and generated storage programs with their mutants");
    soundness_step.dependOn(&run_soundness.step);

    const run_properties = heavy.properties(conformance, exe);
    const property_tests = b.step("test-properties", "Run recompilation properties over selected corpus cases (skipped with test-filter)");
    if (test_filter == null) property_tests.dependOn(&run_properties.step);

    // What each input dimension costs, and how that cost grows.
    //
    // Its own step rather than part of `test`, because it is the one gate that
    // reads a clock. `test` asserts what a compilation asked for, which is
    // counted and so is the same number on every machine; a walk inside a walk
    // allocates nothing and runs straight past it. Catching that shape means
    // timing something, and a timing gate inside the suite would fail on a
    // busy machine and teach everyone to re-run the suite.
    //
    // So it stands alone: cheap to run, cheap to re-run, and a failure names a
    // dimension rather than a case.
    const run_sweep = b.addRunArtifact(conformance);
    run_sweep.addArg(b.pathFromRoot("tests"));
    run_sweep.addArg("--sweep");
    if (sweep_filter) |filter| {
        run_sweep.addArg("--sweep-filter");
        run_sweep.addArg(filter);
    }
    // A slowdown emits the same bytes, so a cached answer is exactly what a
    // regression would produce.
    run_sweep.has_side_effects = true;
    const sweep_step = b.step("sweep", "Report what each input dimension costs, and refuse a dimension that grows faster than its input");
    sweep_step.dependOn(&run_sweep.step);

    const run_examples = heavy.examples(conformance);

    // `zig build conformance -- <path>` walks that directory, case or
    // transcript alone, as the runner does when pointed at it: its cases,
    // goldens and transcripts, with no coverage floors, generated programs or
    // examples, since a part of the corpus cannot answer for what the whole
    // must reach. Naming `examples/` or one example walks it against its
    // goldens in `tests/examples/`.
    const narrowed_conformance: ?*std.Build.Step = if (test_roots.walkOf(b.args)) |walk| switch (walk) {
        .whole => null,
        .narrowed => |directory| narrowed: {
            const run_narrowed = b.addRunArtifact(conformance);
            run_narrowed.addArg(b.pathFromRoot(directory));
            run_narrowed.addArg("--compiler");
            run_narrowed.addFileArg(exe.getEmittedBin());
            run_narrowed.addArg("--runtime");
            run_narrowed.addFileArg(checked_runtime_archive);
            run_narrowed.addArg("--scratch");
            run_narrowed.addArg(b.pathJoin(&.{ scratch, "narrowed" }));
            if (walkers) |n| run_narrowed.addArgs(&.{ "--walkers", b.fmt("{d}", .{n}) });
            run_narrowed.addArg("--sanitize");
            run_narrowed.addArg(@tagName(sanitize));
            if (update_goldens) run_narrowed.addArg("--update");
            run_narrowed.has_side_effects = true;
            break :narrowed &run_narrowed.step;
        },
    } else |_| &b.addFail("zig build conformance walks one directory: name at most one after `--`").step;

    heavy.guide_gate = b.addExecutable(.{
        .name = "guide-gate",
        .root_module = b.createModule(.{
            .root_source_file = b.path("build/guide_gate.zig"),
            .target = b.graph.host,
            .optimize = .Debug,
        }),
    });
    heavy.guide_gate.root_module.addAnonymousImport("process", .{ .root_source_file = b.path("src/conformance/process.zig") });
    const run_guide = heavy.guide(b.getInstallStep());
    const guide_step = b.step("guide", "Compile the guide's programs and hold their pasted output to what the compiler prints");
    guide_step.dependOn(&run_guide.step);

    // Fidelity, as a checked claim rather than an impression. Reserved-word
    // parity only reaches the surface: a grammar can mangle impl blocks or
    // match arms entirely while every keyword is present and every other gate
    // is green.
    //
    // One invocation rather than one per file -- the CLI takes many paths, and
    // a process spawn per corpus file would be the slowest thing in the suite.
    // Its exit status covers a MISSING node as well as an ERROR one, which
    // matters: an unterminated block makes tree-sitter insert a token rather
    // than give up, and a check blind to that passes on a grammar hallucinating
    // its own delimiters.
    // Compile the generated parser before anything parses with it.
    //
    // The CLI builds the library as a side effect of the first `parse`, and
    // that invocation answers about no file: it exits 0 having parsed nothing.
    // For the sweep, which expects 0, that is an invisible pass over the whole
    // corpus; for a `refused` step, which expects 1, it is a failure with no
    // cause a reader can see. Chaining the steps orders them but does not help,
    // because whichever runs first still pays for the build -- and `generate`
    // rewrites `src/parser.c` on every build, so the library is stale again
    // every time and the first parse is always the one that suffers.
    //
    // An explicit build makes the compile a step with its own name, one that
    // fails as itself rather than as whichever parse drew the short straw.
    const build_grammar = b.addSystemCommand(&.{"tree-sitter"});
    build_grammar.addArg("build");
    // Into the cache the build owns, not beside the grammar. Without this the
    // CLI writes the compiled library into the source tree, where it is a
    // hundred kilobytes of build output waiting for someone's `git add -A`.
    build_grammar.addArg("-o");
    build_grammar.addArg(b.pathFromRoot(".zig-cache/tree-sitter/linea.dylib"));
    build_grammar.setCwd(b.path(ts_dir));
    build_grammar.setEnvironmentVariable("TREE_SITTER_LIBDIR", b.pathFromRoot(".zig-cache/tree-sitter"));
    build_grammar.setEnvironmentVariable("TREE_SITTER_DIR", ts_config_dir);
    build_grammar.step.dependOn(&generate_grammar.step);
    // The library lands beside the checkout while the manifest that records
    // this step lives in the cache, and the cache is shared between checkouts.
    // So one workspace's run can satisfy another's, which leaves the second
    // holding a verdict of "already built" and no library -- and every parse
    // after it reports that no parser directory is configured. Always running
    // it costs a second and makes the two agree.
    build_grammar.has_side_effects = true;

    // The CLI writes the file it failed on to standard output, which the build
    // shows only for a check rather than a failed exit; the files it refused
    // are repeated on standard error, so a failure names them.
    const sweep = b.addSystemCommand(&.{
        "sh",
        "-c",
        \\out=$(tree-sitter parse --quiet --stat "$@"); status=$?
        \\printf '%s\n' "$out"
        \\printf '%s\n' "$out" | grep -E '\((ERROR|MISSING)' >&2
        \\exit $status
        ,
        "tree-sitter-parse",
    });
    sweep.setCwd(b.path(ts_dir));
    // The CLI compiles the generated parser into a cache of its own and decides
    // from that cache whether to rebuild. A cache in the user's home outlives
    // any one checkout, so a parser built for a different grammar can answer
    // here -- which reports ERROR nodes on source this grammar accepts, and
    // would as readily accept source it rejects. Pointed at a directory the
    // build owns, the gate depends on nothing outside the build.
    sweep.setEnvironmentVariable("TREE_SITTER_LIBDIR", b.pathFromRoot(".zig-cache/tree-sitter"));
    sweep.setEnvironmentVariable("TREE_SITTER_DIR", ts_config_dir);
    sweep.step.dependOn(&build_grammar.step);
    // On a host with no parser configuration the CLI can parse *nothing* and
    // exit 0, which turns every gate in this file into a check that cannot
    // fail: the sweep passes over a corpus it never read, and only the refused
    // chain below notices, by expecting a refusal and getting the vacuous
    // success. The stat line is printed per file actually parsed, so requiring
    // it makes an empty run fail as itself.
    sweep.addCheck(.{ .expect_stdout_match = "successful parses:" });
    sweep.expectExitCode(0);
    addCorpusPaths(b, sweep);

    // The other direction: every file the sweep above leaves out is a file the
    // grammar has to actually refuse. An exclusion list is a restatement of
    // the parser's verdict, and an entry that stopped being one -- because the
    // grammar learned the form, or because the case changed -- silently shrinks
    // what the sweep covers and reads as an audited exemption. One invocation
    // per file, because the CLI reports failure for the batch and the question
    // is about each.
    // Chained rather than fanned out. The CLI compiles the generated parser
    // into `TREE_SITTER_LIBDIR` on first use, so several of these running at
    // once race on building it -- and one that starts before the library is
    // ready parses nothing and exits 0, which reads here as a file the grammar
    // accepts. Each waits for the one before it.
    var previous: *std.Build.Step = &build_grammar.step;
    for (rejected_by_the_compiler) |path| {
        const refused = b.addSystemCommand(&.{ "tree-sitter", "parse", "--quiet" });
        refused.setCwd(b.path(ts_dir));
        refused.setEnvironmentVariable("TREE_SITTER_LIBDIR", b.pathFromRoot(".zig-cache/tree-sitter"));
        refused.setEnvironmentVariable("TREE_SITTER_DIR", ts_config_dir);
        refused.step.dependOn(previous);
        refused.addArg(b.pathJoin(&.{ "..", "..", path }));
        refused.expectExitCode(1);
        previous = &refused.step;
    }
    sweep.step.dependOn(previous);

    // What the highlighter actually paints, rather than what the query file
    // says somewhere. A query is matched in order and the last pattern to
    // capture a node is the one that colours it, so a narrower rule written
    // above the general one it refines matches and is then overwritten --
    // which is a file that reads correctly, passes every gate that greps it,
    // and highlights nothing. `tree-sitter test` runs the assertions beside
    // the fixture and reports the capture each token actually received.
    //
    // The output is checked because the CLI answers a missing fixture with
    // exit 0 and silence, which is the same verdict a passing run gives.
    const highlights_test = b.addSystemCommand(&.{ "tree-sitter", "test" });
    highlights_test.setCwd(b.path(ts_dir));
    highlights_test.setEnvironmentVariable("TREE_SITTER_LIBDIR", b.pathFromRoot(".zig-cache/tree-sitter"));
    highlights_test.setEnvironmentVariable("TREE_SITTER_DIR", ts_config_dir);
    highlights_test.step.dependOn(&build_grammar.step);
    highlights_test.addFileInput(b.path(ts_dir ++ "/queries/highlights.scm"));
    highlights_test.addCheck(.{ .expect_stdout_match = "syntax highlighting:" });
    highlights_test.addCheck(.{ .expect_stdout_match = "assertions" });
    highlights_test.expectExitCode(0);
    // After the parses, for the reason they are chained to each other: the
    // library they share is built on first use.
    highlights_test.step.dependOn(&sweep.step);

    // The editor gates alone, which CI runs ahead of the suite: they take a
    // few seconds, and a grammar that stopped parsing a file is otherwise
    // reported after everything else has run.
    const editor_step = b.step("editor", "Check the editor grammar parses the corpus and highlights what its queries say");
    editor_step.dependOn(&sweep.step);
    editor_step.dependOn(&highlights_test.step);

    // What the gates read out of the project's own text, run as ordinary code
    // against ordinary cases. `zig build` evaluates this file and runs no test
    // in it, so a heuristic that stays here is a heuristic nothing can fail --
    // which is why the analysis lives in a module and the module has a test
    // binary of its own.
    const source_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("build/source_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
        .filters = test_filters,
    });
    source_tests.root_module.addAnonymousImport("runtime_archive", .{ .root_source_file = runtime_archive });
    // The runtime's signature table and every source it describes, so a test
    // holds the one to the other.
    source_tests.root_module.addAnonymousImport("runtime_symbols", .{ .root_source_file = b.path("src/support/runtime_symbols.zig") });
    source_tests.root_module.addAnonymousImport("runtime_sources", .{ .root_source_file = runtimeSources(b) });
    const run_source_tests = b.addRunArtifact(source_tests);
    const runtime_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("runtime/float.zig"),
            .target = target,
            .optimize = optimize,
        }),
        .filters = test_filters,
    });
    addDecimalProvider(b, runtime_tests.root_module);
    runtime_tests.root_module.link_libc = true;
    if (target.result.os.tag == .linux) runtime_tests.root_module.linkSystemLibrary("m", .{});
    const run_runtime_tests = b.addRunArtifact(runtime_tests);

    // The documentation gates read Markdown rather than source, so they run
    // as a step of the suites instead of on every evaluation of this file: a
    // `zig build` that only compiles does not pay for reading the decision
    // index, the guide and the library's documentation.
    const documentation_gates = b.allocator.create(std.Build.Step) catch @panic("OOM");
    documentation_gates.* = .init(.{
        .id = .custom,
        .name = "documentation gates",
        .owner = b,
        .makeFn = checkTheDocumentation,
    });

    const suites = .{
        .{ test_roots.Suite.full, "test", "Run unit tests and the conformance suite" },
        .{ test_roots.Suite.corpus, "test-corpus", "Run the complete corpus and generated programs with coverage floors (skipped with test-filter)" },
        .{ test_roots.Suite.support, "test-support", "Run full test coverage except the corpus: units, examples, and editor checks" },
        .{ test_roots.Suite.unit, "test-unit", "Run compiler and build machinery unit tests without integrations" },
        .{ test_roots.Suite.conformance, "conformance", "Run the corpus and examples with the selected runtime, or only the directory, case or transcript named after --" },
        .{ test_roots.Suite.fuzz, "fuzz", "Run only the compiler's fuzz entry points" },
    };
    inline for (suites) |suite| {
        const selected = test_roots.select(.{ .suite = suite[0], .optimize = optimize, .filtered = test_filter != null });
        const step = b.step(suite[1], suite[2]);
        if (selected.source) {
            step.dependOn(documentation_gates);
            step.dependOn(&run_source_tests.step);
            step.dependOn(&run_runtime_tests.step);
            if (test_filter == null) {
                step.dependOn(native_io_step);
                step.dependOn(native_net_step);
                step.dependOn(native_clock_step);
                step.dependOn(native_math_step);
                step.dependOn(native_runtime_step);
            }
        }
        const narrowed = suite[0] == .conformance and narrowed_conformance != null;
        const properties = selected.corpus and (suite[0] == .full or suite[0] == .corpus) and test_filter == null;
        if (selected.selected == .fuzz) step.dependOn(&run_fuzz_tests.step);
        if (narrowed) step.dependOn(narrowed_conformance.?);
        if (sequential and !narrowed) {
            const order = test_roots.heavyOrder(selected, .{ .properties = properties, .guide = guide_in_test });
            if (heavy.sequence(order.slice())) |last| step.dependOn(last);
        } else {
            if (selected.selected == .joined) step.dependOn(&run_debug_tests.step);
            if (!narrowed) {
                if (selected.examples) step.dependOn(&run_examples.step);
                if (selected.guide and guide_in_test) step.dependOn(&run_guide.step);
                if (selected.corpus) step.dependOn(&run_conformance.step);
            }
            if (properties) step.dependOn(property_tests);
        }
        if (selected.editor) {
            step.dependOn(&sweep.step);
            step.dependOn(&highlights_test.step);
        }
    }
}

/// The corpus files the grammar is not asked to derive.
///
/// Files the compiler does not parse either, so the grammar is not asked to do
/// what the language does not. Named rather than inferred from what goldens a
/// case carries, because a list is easier to audit than a rule -- but a list
/// is also a restatement of the parser's verdict, so `sweepRejects` below
/// holds every entry to actually being one the grammar refuses. It found the
/// first line of this list, which the grammar parsed perfectly well: excluding
/// it hid nothing and quietly shrank the sweep by a file.
const rejected_by_the_compiler = [_][]const u8{
    "tests/traits/a_grouped_type_is_not_a_derive_target.lin",
    "tests/traits/a_grouped_tuple_head_is_reported_once.lin",
    "tests/tuples/a_pattern_refused_by_the_parser_is_reported_once.lin",
    "tests/tuples/a_refused_tuple_arm_does_not_make_the_next_arm_unreachable.lin",
    "tests/structs/named_literals/a_named_literal_requires_its_closing_brace.lin",
    "tests/struct_update/the_base_comes_last.lin",
    "tests/struct_update/a_base_needs_an_expression.lin",
    "tests/struct_update/a_second_base_is_still_read.lin",
    "tests/structs/a_literal_value_without_a_field_name_is_one_mistake.lin",
    "tests/closure_captures/invocation_mode_requires_capture_list.lin",
    "tests/decl/a_lambda_parameter_list_is_closed.lin",
    "tests/ranges/a_chain_in_a_pattern_is_one_mistake.lin",
    "tests/decl/impl_takes_no_modifier.lin",
    "tests/decl/an_impl_is_not_a_test.lin",
    "tests/diag/invalid_run.lin",
    "tests/decl/a_destructure_is_introduced_by_let.lin",
    "tests/derive_from/a_derive_entry_missing_its_closing_bracket_is_reported_once.lin",
    "tests/derive_from/a_derive_entry_with_trailing_garbage_is_reported_once.lin",
    "tests/derive_from/a_derive_entry_without_a_source_is_reported_once.lin",
    "tests/derive_from/a_derive_request_missing_its_closing_parenthesis_is_reported_once.lin",
    "tests/traits/an_unnamed_callable_parameter_in_two_implementations_is_refused_by_the_parser.lin",
    "tests/defer_let/a_defer_let_binds_one_name.lin",
    "tests/defer_let/a_defer_let_read_binds_nothing_to_release.lin",
    "tests/tuples/a_tuple_pattern_does_not_nest_in_a_payload.lin",
    "tests/tuples/var_does_not_take_a_tuple_apart.lin",
    "tests/tuples/a_declaration_parameter_is_a_name_not_a_pattern.lin",
    "tests/traits/a_grouped_type_is_not_an_implementation_head.lin",
    "tests/decl/borrowed_lets/a_borrowed_pattern_is_not_a_var_declaration.lin",
    "tests/decl/borrowed_lets/nested_patterns_are_not_introduced_by_read.lin",
    "tests/decl/borrowed_lets/read_requires_an_irrefutable_pattern.lin",
    "tests/ownership/a_catch_all_is_the_bare_underscore/main.lin",
    "tests/traits/a_trait_projection_has_no_body.lin",
    "tests/traits/a_settling_with_nothing_after_it_says_what_is_missing.lin",
    "tests/traits/a_settled_reference_the_parser_could_not_finish_is_one_report.lin",
    "tests/text/an_extern_declares_no_body.lin",
    "tests/traits/a_trait_is_never_closed.lin",
    "tests/lsp/a_call_that_was_never_closed_still_says_what_is_in_scope/main.lin",
    "tests/lsp/a_dot_on_a_type_being_written_offers_its_trait_operations/main.lin",
    "tests/arrays/a_bracket_says_where_it_closes.lin",
    "tests/arrays/an_array_type_missing_its_semicolon_poisons_its_binding.lin",
    "tests/unit_value/the_unit_value_is_not_a_pattern.lin",
    "tests/diag/unexpected_character.lin",
    "tests/diag/unterminated_string.lin",
    "tests/raw_strings/an_unterminated_raw_literal.lin",
    "tests/raw_strings/a_raw_literal_is_one_token.lin",
    "tests/raw_strings/a_raw_literal_opens_with_at_most_eight_hashes.lin",
    "tests/multiline_strings/a_line_cannot_begin_inside_an_interpolation.lin",
    "tests/multiline_strings/an_arm_after_a_multiline_literal_needs_its_comma.lin",
    "tests/diag/an_interpolation_format_spec_is_written_in_order.lin",
    "tests/diag/an_unclosed_interpolation_ends_at_its_line.lin",
    "tests/lexer/delimiters.lin",
    "tests/newtypes/a_proven_value_has_nothing_to_decline.lin",
    "tests/newtypes/a_clause_the_file_ends_inside_is_refused.lin",
    "tests/modules/a_dangling_dot_off_a_qualified_type_is_one_mistake/main.lin",
    "tests/iter/a_for_names_what_it_walks.lin",
    "tests/arrays/inferred_length/missing_bracket_recovers.lin",
    "tests/arrays/inferred_length/missing_initializer_recovers.lin",
    "tests/decl/a_constant_takes_no_modifier.lin",
    "tests/decl/a_function_takes_no_modifier.lin",
    "tests/borrows/contracts/a_carrier_mark_belongs_to_a_struct_or_an_enum.lin",
    "tests/decl/attributes/a_bare_carrier_is_refused.lin",
    "tests/decl/attributes/a_bare_carrier_after_a_visibility_is_refused.lin",
    "tests/decl/attributes/a_lone_carrier_is_refused.lin",
    "tests/decl/attributes/a_group_closes_before_its_declaration.lin",
    "tests/decl/attributes/a_group_separates_its_items.lin",
    "tests/decl/attributes/a_malformed_attribute_preserves_the_following_declaration.lin",
    "tests/decl/attributes/an_attribute_group_is_not_empty.lin",
    "tests/decl/attributes/an_attribute_requires_a_following_declaration.lin",
    "tests/decl/attributes/attribute_names_are_closed.lin",
    "tests/decl/attributes/attributes_do_not_attach_to_constants.lin",
    "tests/decl/attributes/attributes_do_not_attach_to_fields.lin",
    "tests/decl/attributes/attributes_do_not_attach_to_functions.lin",
    "tests/decl/attributes/attributes_do_not_attach_to_implementations.lin",
    "tests/decl/attributes/attributes_do_not_attach_to_imports/main.lin",
    "tests/decl/attributes/attributes_do_not_attach_to_statements.lin",
    "tests/decl/attributes/attributes_do_not_attach_to_traits.lin",
    "tests/decl/attributes/attributes_do_not_disappear_on_implementations.lin",
    "tests/decl/attributes/derive_attributes_do_not_attach_to_implementations.lin",
    "tests/decl/attributes/the_bare_copyable_prefix_is_removed.lin",
    "tests/decl/attributes/the_bare_linear_prefix_is_removed.lin",
    "tests/decl/attributes/the_bare_opaque_prefix_is_removed.lin",
    "tests/decl/borrowed_lets/a_borrowed_name_is_refused_without_moving_its_place.lin",
    "tests/decl/borrowed_lets/read_marks_the_pattern_not_the_place.lin",
    "tests/modules/a_reexport_takes_no_modifier/mid/mid.lin",
    "tests/traits/a_trait_takes_no_modifier.lin",
    "tests/construction_derive/malformed_argument_keeps_parser_diagnostic.lin",
    "tests/structs/a_field_pattern_binds_a_name_and_compares_nothing.lin",
    "tests/structs/a_field_pattern_read_binds_a_name.lin",
    "tests/structs/a_destructure_binds_a_name_for_each_field.lin",
    "tests/structs/a_field_pattern_is_no_range.lin",
    "tests/decl/a_unit_result_is_not_written/main.lin",
    "tests/testing_signatures/a_written_unit_result_says_what_a_test_and_main_answer.lin",
};

/// Every corpus file the grammar is asked to derive.
fn addCorpusPaths(b: *std.Build, run: *std.Build.Step.Run) void {
    const io = b.graph.io;
    // The library too. Its files are Linea, they are compiled into every
    // binary the compiler produces, and leaving them out meant the grammar was
    // never asked to parse the code every program depends on.
    for ([_][]const u8{ "examples", "tests", "std" }) |root| {
        var dir = b.build_root.handle.openDir(io, root, .{ .iterate = true }) catch continue;
        defer dir.close(io);
        var walker = dir.walk(b.allocator) catch @panic("OOM");
        defer walker.deinit();
        while (walker.next(io) catch @panic("walking the corpus failed")) |entry| {
            if (entry.kind != .file) continue;
            if (!std.mem.endsWith(u8, entry.basename, ".lin")) continue;

            const path = b.pathJoin(&.{ root, entry.path });
            if (std.mem.indexOf(u8, path, "recovery") != null) continue;
            var skip = false;
            for (rejected_by_the_compiler) |r| {
                if (std.mem.eql(u8, path, r)) skip = true;
            }
            if (skip) continue;

            // Relative to the grammar directory the sweep runs in.
            run.addArg(b.pathJoin(&.{ "..", "..", path }));
        }
    }
}
