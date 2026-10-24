const std = @import("std");
const builtin = @import("builtin");
const tracy = @import("support/tracy.zig");
const compiler_stack = @import("support/stack.zig");
const testing = std.testing;
const std_locations = @import("conformance/std_locations.zig");

const source_mod = @import("support/source.zig");
const name_case = @import("support/name_case.zig");
const FileTable = source_mod.FileTable;
const Source = source_mod.Source;
const readFileAlloc = source_mod.readFileAlloc;
const Sink = @import("diagnostics/sink.zig").Sink;
const diagnostic = @import("diagnostics/diagnostic.zig");
const Diagnostic = diagnostic.Diagnostic;
const Interner = @import("support/interner.zig").Interner;
const StringId = @import("support/interner.zig").StringId;
const render = @import("diagnostics/render.zig");
const token = @import("lexer/token.zig");
const tokenize = @import("lexer/lexer.zig").tokenize;
const isIdentifier = @import("lexer/lexer.zig").isIdentifier;
const parse = @import("parser/parser.zig").parse;
const dumpAst = @import("syntax/dump.zig").dumpAst;
const resolve_mod = @import("sema/resolve.zig");
const resolveTree = resolve_mod.resolveTree;
const Resolution = resolve_mod.Resolution;
const BindingId = resolve_mod.BindingId;
const constfold = @import("sema/constfold.zig");
const typecheck_mod = @import("sema/typecheck.zig");
const typecheckTree = @import("sema/typecheck.zig").typecheckTree;
const postfixSelection = @import("sema/typecheck.zig").postfixSelection;
const node_mod = @import("syntax/node.zig");
const ExprId = node_mod.ExprId;
const driver = @import("driver/driver.zig");
const lexer_dump = @import("lexer/dump.zig");
const annotated = @import("fmt/annotated.zig");
const loader = @import("driver/loader.zig");
const library = @import("driver/library.zig");
const InMemoryFile = loader.InMemoryFile;
const loadFromMemory = loader.loadFromMemory;
const checkProgram = loader.checkProgram;
const lower = @import("mir/lower.zig").lowerProgram;
const dumpMirModule = @import("mir/dump.zig").dumpModule;
const checkOwnershipTree = @import("ownership/check.zig").checkTree;
const DisposalPlan = @import("ownership/cfg.zig").DisposalPlan;
const buildOwnershipCfg = @import("ownership/build.zig").build;
const lowerTree = @import("mir/lower.zig").lowerTree;
const mlir_backend = @import("backend/mlir.zig");
const emitMlir = mlir_backend.emit;
const toolchain = @import("driver/toolchain.zig");
const edges = @import("mir/edges.zig");
const storage_mod = @import("mir/storage.zig");
const Inst = @import("mir/mir.zig").Inst;
const MirModule = @import("mir/mir.zig").Module;
const transform_mod = @import("conformance/transform.zig");
const walk_loops = @import("conformance/walk_loops.zig");
const Transform = transform_mod.Transform;
const TransformSemantics = transform_mod.Semantics;
const mutate = @import("conformance/mutate.zig");
const Mutation = mutate.Mutation;
const Damage = @import("conformance/damage.zig").Damage;
const Program = @import("syntax/program.zig").Program;
const ProgramKind = @import("syntax/program.zig").Kind;
const ExpandedProgram = @import("syntax/expanded_program.zig").ExpandedProgram;
const ModuleId = @import("syntax/program.zig").ModuleId;
const GeneratedImplementationId = @import("syntax/expanded_program.zig").GeneratedImplementationId;
const sema_types = @import("sema/types.zig");
const Typing = sema_types.Typing;
const corpus_layout = @import("support/corpus.zig");
const runtime_symbols = @import("support/runtime_symbols.zig");
const case_anchors = corpus_layout.case_anchors;
const generate = @import("conformance/generate.zig");
const matrix = @import("conformance/matrix.zig");
const storage_gen = @import("conformance/storage.zig");
const regions = @import("conformance/regions.zig");
const layout_oracle = @import("conformance/layout.zig");
const fmt = @import("fmt/fmt.zig");
const hermeticRun = @import("conformance/process.zig").run;
const transcripts = @import("conformance/transcript.zig");
const perturb = @import("conformance/perturb.zig");
const session = @import("lsp/session.zig");
const lsp = @import("lsp");
const test_library = @import("driver/test_library.zig");
const lsp_analysis = @import("lsp/analysis.zig");
const lsp_references = @import("lsp/references.zig");
const lsp_publish = @import("lsp/publish.zig");
const lsp_hints = @import("lsp/hints.zig");
const lsp_rename = @import("lsp/rename.zig");
const lsp_uri = @import("lsp/uri.zig");
const lsp_positions = @import("lsp/positions.zig");
const lsp_workspace = @import("lsp/workspace.zig");
const lsp_fix = @import("lsp/fix.zig");
const lsp_exports = @import("lsp/exports.zig");
const lsp_completion = @import("lsp/completion.zig");
const Documents = @import("lsp/documents.zig").Documents;
const ast_mod = @import("syntax/ast.zig");
const Ast = ast_mod.Ast;
const TokenId = @import("lexer/token.zig").TokenId;
const FileId = source_mod.FileId;

comptime {
    _ = @import("conformance/std_locations.zig");
    _ = @import("conformance/transform.zig");
    _ = @import("conformance/walk_loops.zig");
    _ = @import("conformance/mutate.zig");
    _ = @import("conformance/damage.zig");
    _ = @import("conformance/coverage.zig");
    _ = @import("conformance/layout.zig");
    _ = @import("conformance/generate.zig");
    _ = @import("conformance/matrix.zig");
    _ = @import("conformance/storage.zig");
    _ = @import("conformance/regions.zig");
    _ = @import("conformance/perturb.zig");
    _ = @import("conformance/grammars.zig");
    _ = @import("conformance/process.zig");
    _ = @import("conformance/transcript.zig");
    _ = @import("support/corpus.zig");
    // The session harness. Named here rather than left to the `@import` above
    // it, because a test build never analyses `main` and so never reaches a
    // file only a function body refers to -- which is a file whose tests have
    // never been compiled, let alone run.
    _ = @import("lsp/session.zig");
    _ = @import("lsp/completion.zig");
}

/// A file's canonical formatting, or null where it does not parse cleanly.
fn formattedText(gpa: std.mem.Allocator, text: []const u8) !?[]const u8 {
    const source: Source = .{ .path = "gate.lin", .text = text };
    var sink = Sink.init(gpa);
    var interner: Interner = .empty;
    const tokens = try tokenize(gpa, &source, .from(0), &sink, &interner);
    var ast = try parse(gpa, &source, .from(0), tokens, &sink);
    if (sink.hasErrors()) return null;
    return try fmt.formatAlloc(gpa, &ast);
}

/// One case: a `.lin` file, or a directory holding a file named `main.lin`.
///
/// A module is a directory, so a program of several files is a directory of
/// them. What makes a directory a case rather than a grouping is that entry
/// point: `tests/enums/` holds a hundred unrelated single-file programs and no
/// `main.lin`, and a directory-only rule would make one module of them all.
const Case = struct {
    /// What a failure names.
    display_path: []const u8,
    /// The path every golden of the case is named by: the case's own path
    /// without `.lin`, or for a directory the directory's, and for an example
    /// the same name under `tests/examples/`.
    stem: []const u8,
    /// What the loader is pointed at: the file, or the directory.
    entry: []const u8,
    /// Every `.lin` file the case can reach, which for a directory is
    /// everything beneath it. Which of them belong to which module is the
    /// loader's question, and it answers it from the imports.
    files: []const InMemoryFile,
    /// The manifest marking the case's root, where it has one.
    ///
    /// Beside the source rather than among it. It says which kind of root the
    /// case is, so the loader has to see it -- and it is not a document, so
    /// every property that walks the files asking a server about each of them
    /// must not. Keeping it out of `files` is what makes both true without a
    /// rule every one of those walks has to remember.
    manifest: ?InMemoryFile = null,
    /// The manifests of the libraries a case holds below its root, which its
    /// own manifest may name as dependencies. Kept out of `files` for the
    /// reason the root's manifest is.
    libraries: []const InMemoryFile = &.{},
    /// The C driver linked against this case's object, where it has one.
    ///
    /// Kept out of `files` for the reason the manifest is: it is not Linea
    /// source, so nothing that walks a case's documents should be handed it.
    /// A case carrying one is a library asked the only question that matters
    /// about a library -- whether something outside can call it -- and the
    /// answer is what the program prints.
    driver: ?InMemoryFile = null,
    /// Every other regular file beneath a directory case: the files its
    /// program may embed with `embed` or `embed_bytes`.
    ///
    /// Kept out of `files` for the reason the manifest is: they are not Linea
    /// source, and a walk over a case's documents must not be handed a
    /// template or an image. The loader reads them only through an embed.
    data: []const InMemoryFile = &.{},
    /// The C the case's manifest names under `native` and `link`, and every C
    /// source and header beside the case's source, so an include resolves.
    /// Kept out of `files` for the reason the driver is.
    native: Native = .{},

    /// The C outside the case's module that building it needs: the sources
    /// and libraries the loader gathered from every manifest of the program,
    /// its dependencies' included, built from the case's C files.
    fn foreign(self: Case, program: *const Program) Foreign {
        return .{
            .driver = if (self.driver) |d| d.text else null,
            .native = .{ .files = self.native.files, .compile = program.native, .link = program.link },
        };
    }
};

/// The C a program is built with: the sources its manifest names under
/// `native`, with every C file of the case beside them, and the libraries it
/// names under `link`.
const Native = struct {
    /// Every `.c` and `.h` file of the case but its driver, by its path.
    files: []const InMemoryFile = &.{},
    /// The paths among `files` the build compiles.
    compile: []const []const u8 = &.{},
    link: []const []const u8 = &.{},
};

/// The C a case's build links beside its module: a driver that calls into a
/// library, and the C a program's manifest builds and links.
const Foreign = struct {
    driver: ?[]const u8 = null,
    native: Native = .{},
};

/// Every C file of the case, which the program's manifests name what to
/// build from.
fn nativeOf(c_files: []const InMemoryFile) Native {
    return .{ .files = c_files };
}

/// What the loader reads beside a case's source: the manifest marking its
/// root, where it has one, the manifests of the libraries it holds, and the
/// files its program may embed. Every recompilation of a case, rewritten or
/// not, is given these, so it is the same root holding the same files. The
/// caller owns the result.
fn besideOf(gpa: std.mem.Allocator, case: Case) ![]const InMemoryFile {
    const marking = case.manifest orelse return case.data;
    const all = try gpa.alloc(InMemoryFile, 1 + case.libraries.len + case.data.len);
    all[0] = marking;
    @memcpy(all[1..][0..case.libraries.len], case.libraries);
    @memcpy(all[1 + case.libraries.len ..], case.data);
    return all;
}

/// A case's source followed by what the loader reads beside it. The caller
/// owns the result.
fn inputsOf(gpa: std.mem.Allocator, case: Case) ![]const InMemoryFile {
    const beside = try besideOf(gpa, case);
    if (beside.len == 0) return case.files;
    return std.mem.concat(gpa, InMemoryFile, &.{ case.files, beside });
}

fn lessByPath(_: void, a: []const u8, b: []const u8) bool {
    return std.mem.lessThan(u8, a, b);
}

/// Every file under `root`, relative to it, in a fixed order.
///
/// Sorted before anything is grouped, so a filesystem's listing order cannot
/// decide which file of a module is numbered first -- and so a failure
/// reported by name reproduces.
///
/// Everything, not only the programs: what a corpus holds beside its programs
/// is the other half of what a run has to account for, and a walk that saw
/// only `.lin` could not notice a golden with nothing to compare.
fn collectPaths(gpa: std.mem.Allocator, io: std.Io, root: []const u8) ![]const []const u8 {
    var dir = try std.Io.Dir.cwd().openDir(io, root, .{ .iterate = true });
    defer dir.close(io);

    var walker = try dir.walk(gpa);
    defer walker.deinit();

    var paths: std.ArrayList([]const u8) = .empty;
    while (try walker.next(io)) |entry| {
        if (entry.kind != .file) continue;
        try paths.append(gpa, try gpa.dupe(u8, entry.path));
    }
    std.mem.sort([]const u8, paths.items, {}, lessByPath);
    return paths.toOwnedSlice(gpa);
}

/// A root that is one case rather than a tree of them: a `.lin` file, a `.cmd`
/// transcript, or a directory holding a `main.lin`. It is walked from the
/// directory holding it with only its own paths selected -- exactly what
/// naming it as a focused property case selects -- so a golden with its stem
/// is found wherever the walk of that directory finds it.
const NarrowedCase = struct {
    /// The directory the case sits in, walked as the corpus root.
    parent: []const u8,
    /// The case's name under `parent`, as a property-case manifest writes it.
    name: []const u8,

    fn deinit(self: NarrowedCase, gpa: std.mem.Allocator) void {
        gpa.free(self.parent);
        gpa.free(self.name);
    }
};

fn narrowedCase(gpa: std.mem.Allocator, io: std.Io, root: []const u8) !?NarrowedCase {
    const trimmed = std.mem.trimEnd(u8, root, "/");
    if (trimmed.len == 0) return null;
    const is_case = if (std.mem.endsWith(u8, trimmed, ".lin") or isCommandPath(trimmed))
        true
    else holds: {
        const entry = try std.fs.path.join(gpa, &.{ trimmed, "main.lin" });
        defer gpa.free(entry);
        std.Io.Dir.cwd().access(io, entry, .{}) catch break :holds false;
        break :holds true;
    };
    if (!is_case) return null;
    const parent = try gpa.dupe(u8, std.fs.path.dirname(trimmed) orelse ".");
    errdefer gpa.free(parent);
    return .{ .parent = parent, .name = try gpa.dupe(u8, std.fs.path.basename(trimmed)) };
}

test "a root that is itself one case or one transcript is walked from its parent, selecting only it" {
    const gpa = testing.allocator;
    const io = testing.io;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDirPath(io, "tree/module_case");
    try tmp.dir.writeFile(io, .{ .sub_path = "tree/module_case/main.lin", .data = "fn main() -> UInt8 { 0 }\n" });
    try tmp.dir.writeFile(io, .{ .sub_path = "tree/file_case.lin", .data = "fn main() -> UInt8 { 0 }\n" });
    const root = try tmp.dir.realPathFileAlloc(io, ".", gpa);
    defer gpa.free(root);

    const module = try std.fs.path.join(gpa, &.{ root, "tree/module_case/" });
    defer gpa.free(module);
    const module_case = (try narrowedCase(gpa, io, module)).?;
    defer module_case.deinit(gpa);
    try testing.expect(std.mem.endsWith(u8, module_case.parent, "/tree"));
    try testing.expectEqualStrings("module_case", module_case.name);

    const file = try std.fs.path.join(gpa, &.{ root, "tree/file_case.lin" });
    defer gpa.free(file);
    const file_case = (try narrowedCase(gpa, io, file)).?;
    defer file_case.deinit(gpa);
    try testing.expect(std.mem.endsWith(u8, file_case.parent, "/tree"));
    try testing.expectEqualStrings("file_case.lin", file_case.name);

    const transcript = try std.fs.path.join(gpa, &.{ root, "tree/usage.cmd" });
    defer gpa.free(transcript);
    const transcript_case = (try narrowedCase(gpa, io, transcript)).?;
    defer transcript_case.deinit(gpa);
    try testing.expectEqualStrings("usage.cmd", transcript_case.name);

    const tree = try std.fs.path.join(gpa, &.{ root, "tree" });
    defer gpa.free(tree);
    try testing.expect((try narrowedCase(gpa, io, tree)) == null);
    try testing.expect((try narrowedCase(gpa, io, "module_case")) == null);
}

/// What a case records beside itself, each compared against something a pass
/// produced for the case whose stem it shares.
/// What a language-server session case records, beside the script that drove
/// it. Named once, because the gate that asks whether a case records anything
/// and the runner that compares what it recorded must mean the same file.
const session_golden = "session.golden";

/// What a session case records where the file beside its script is not the
/// text the script opens that file with.
const session_disk = "session.disk";

fn isSessionPath(path: []const u8) bool {
    return std.mem.endsWith(u8, path, "/session.jsonl");
}

/// Whether a corpus path is a transcript case.
fn isCommandPath(path: []const u8) bool {
    return std.mem.endsWith(u8, path, ".cmd");
}

/// The transcripts among a corpus root's paths, in the order walked. Every
/// `.cmd` beneath the root is one, so a root narrowed to a directory of
/// transcripts runs them as the whole corpus would.
fn commandPaths(gpa: std.mem.Allocator, paths: []const []const u8) ![]const []const u8 {
    var found: std.ArrayList([]const u8) = .empty;
    errdefer found.deinit(gpa);
    for (paths) |p| if (isCommandPath(p)) try found.append(gpa, p);
    return found.toOwnedSlice(gpa);
}

test "a transcript is found wherever it sits beneath the root" {
    // A root narrowed to one directory of transcripts holds no `cmd/` of its
    // own, and a transcript there is as much a case as one under `cmd/`.
    const paths = [_][]const u8{ "a.lin", "cmd/README.md", "cmd/usage.cmd", "echoes_a_document.cmd", "nested/answers.cmd" };
    const found = try commandPaths(testing.allocator, &paths);
    defer testing.allocator.free(found);
    try testing.expectEqual(@as(usize, 3), found.len);
    try testing.expectEqualStrings("cmd/usage.cmd", found[0]);
    try testing.expectEqualStrings("echoes_a_document.cmd", found[1]);
    try testing.expectEqualStrings("nested/answers.cmd", found[2]);
}

/// The paths not under `under`, a directory relative to the same root.
fn pathsOutside(gpa: std.mem.Allocator, paths: []const []const u8, under: []const u8) ![]const []const u8 {
    var kept: std.ArrayList([]const u8) = .empty;
    errdefer kept.deinit(gpa);
    for (paths) |p| {
        if (std.mem.startsWith(u8, p, under) and p.len > under.len and p[under.len] == '/') continue;
        try kept.append(gpa, p);
    }
    return kept.toOwnedSlice(gpa);
}

test "a walk of the corpus leaves the examples' goldens out" {
    const paths = [_][]const u8{ "examples/hello.exit", "examples_of_rules.lin", "vec/push.exit", "vec/push.lin" };
    const kept = try pathsOutside(testing.allocator, &paths, "examples");
    defer testing.allocator.free(kept);
    try testing.expectEqual(@as(usize, 3), kept.len);
    try testing.expectEqualStrings("examples_of_rules.lin", kept[0]);
}

/// One thing a program that ran left behind, and the golden recording it.
///
/// Named once because six places have to mean the same set: what a command
/// case compares, what a walked case compares, which goldens a case that never
/// ran cannot have, which say a case enters the runtime, and which of them a
/// golden's stem is looked for by. A stream taught to one of those and not the
/// rest is a golden that is written and never read, which is a check counted in
/// a review while being unable to fail.
const Stream = struct {
    ext: []const u8,
    /// What the program left on it.
    of: *const fn (Ran) []const u8,
    /// Whether recording this one is what asks for the case to be built and
    /// run. Nothing else is compared without it: the other streams exist only
    /// once a program has run.
    asks_for_a_run: bool = false,
    /// Whether producing nothing here is the observation. A program that says
    /// nothing on a stream is a result and no other golden holds it, while a
    /// status is a byte every program that finished produced.
    empty_is_an_answer: bool = true,
};

const streams = [_]Stream{
    .{ .ext = ".exit", .of = exitTextOf, .asks_for_a_run = true, .empty_is_an_answer = false },
    .{ .ext = ".out", .of = printedBy },
    .{ .ext = ".err", .of = saidBy },
};

/// Where in `streams` one extension sits, so a rule about a single stream names
/// it and fails to compile if the table stops carrying it.
fn streamIndex(comptime ext: []const u8) comptime_int {
    for (streams, 0..) |s, i| {
        if (std.mem.eql(u8, s.ext, ext)) return i;
    }
    @compileError("no stream records " ++ ext);
}

fn exitTextOf(ran: Ran) []const u8 {
    return ran.text;
}

fn printedBy(ran: Ran) []const u8 {
    return ran.output;
}

fn saidBy(ran: Ran) []const u8 {
    return saidOf(ran.text, ran.errors);
}

/// What a case records that a run does not produce: the dumps a pass wrote and
/// the diagnostics it rendered.
const dump_extensions = [_][]const u8{
    ".tokens", ".ast", ".inferred", ".mono", ".mir", ".fmt", ".mlir", ".stderr",
};

/// What every stream is recorded under.
const stream_extensions = blk: {
    var exts: [streams.len][]const u8 = undefined;
    for (streams, 0..) |s, i| exts[i] = s.ext;
    break :blk exts;
};

/// Every golden that names its case by stem, which is every one of both kinds.
const golden_extensions = dump_extensions ++ stream_extensions;

/// Every golden a case only gets to record by being built and run: each stream,
/// and the dumps written from a program that got past the diagnostics.
const produced_by_a_run = stream_extensions ++ [_][]const u8{ ".inferred", ".mono", ".mir", ".mlir" };

/// Whether the corpus holds a path.
///
/// A search rather than a walk, which `collectPaths` order allows: the corpus
/// is every file under the root, so asking it about each golden read all of
/// them once per golden.
fn holdsPath(paths: []const []const u8, want: []const u8) bool {
    var lo: usize = 0;
    var hi: usize = paths.len;
    while (lo < hi) {
        const mid = lo + (hi - lo) / 2;
        if (lessByPath({}, paths[mid], want)) lo = mid + 1 else hi = mid;
    }
    return lo < paths.len and std.mem.eql(u8, paths[lo], want);
}

/// The goldens among `goldens` whose stem names no case among `cases`.
///
/// Both are in `collectPaths` order, relative to the roots they were walked
/// from: a corpus root is walked once and passed as both, while the examples'
/// goldens are walked from their mirror, where each is named as its example is.
///
/// Every golden is reached from its case, so one whose case is gone is never
/// opened -- and an expectation nothing opens is a check that is counted in a
/// directory listing and in a review while being unable to fail. The corpus
/// held one for four milestones after the case was deleted, which is how long
/// it takes to notice by eye.
fn orphanGoldens(gpa: std.mem.Allocator, goldens: []const []const u8, cases: []const []const u8) ![]const []const u8 {
    var out: std.ArrayList([]const u8) = .empty;
    for (goldens) |p| {
        const ext = for (golden_extensions) |e| {
            if (std.mem.endsWith(u8, p, e)) break e;
        } else continue;
        const stem = p[0 .. p.len - ext.len];

        var anchored = false;
        for (case_anchors) |a| {
            const wanted = try std.mem.concat(gpa, u8, &.{ stem, a });
            defer gpa.free(wanted);
            if (holdsPath(cases, wanted)) {
                anchored = true;
                break;
            }
        }
        if (!anchored) try out.append(gpa, p);
    }
    return out.toOwnedSlice(gpa);
}

/// What names a case as another case's twin.
///
/// A case named `X_twin` states a relation to the case named `X`: the two
/// spell one thing two ways and are otherwise one program, so what reaches the
/// backend is one module. The suffix is the whole of how a pair says so --
/// there is nothing else in a corpus of files to say it with, and a pair that
/// named each other in a comment would be a relation nothing runs.
const twin_suffix = "_twin";

/// The twin case's own stem -- the path with its case shape stripped and the
/// `_twin` suffix still on it -- or null for a path that is no twin. The
/// sibling's stem is this minus the suffix, and the caller derives it; what
/// this answers is the name the twin's own goldens hang off. A case is a file
/// or a directory holding a `main.lin`, and a directory's goldens sit beside
/// the directory under its own name, so both shapes answer the same stem.
fn twinCaseStemOf(path: []const u8) ?[]const u8 {
    const stem = if (std.mem.endsWith(u8, path, twin_suffix ++ ".lin"))
        path[0 .. path.len - ".lin".len]
    else if (std.mem.endsWith(u8, path, twin_suffix ++ "/main.lin"))
        path[0 .. path.len - "/main.lin".len]
    else
        return null;
    // A case named bare `_twin` states a relation with nobody: the suffix
    // needs a case's name on the other side of it.
    const sibling = stem[0 .. stem.len - twin_suffix.len];
    if (sibling.len == 0 or sibling[sibling.len - 1] == '/') return null;
    return stem;
}

test "a twin case is named by its suffix, in both shapes a case takes" {
    try testing.expectEqualStrings("a/b_twin", twinCaseStemOf("a/b_twin.lin").?);
    try testing.expectEqualStrings("a/b_twin", twinCaseStemOf("a/b_twin/main.lin").?);
    // The relation composes: `X_twin` is the twin of `X`, whatever `X` ends
    // in -- so a twin of a twin names its own sibling, not the grandparent.
    try testing.expectEqualStrings("c_twin_twin", twinCaseStemOf("c_twin_twin.lin").?);
    // A name merely containing the suffix states no relation, and neither
    // does a file inside a twin-named directory that is not the module entry.
    try testing.expect(twinCaseStemOf("a_twin_thing.lin") == null);
    try testing.expect(twinCaseStemOf("a_twin/other.lin") == null);
    try testing.expect(twinCaseStemOf("b_twin.mlir") == null);
    // The degenerate name: a bare `_twin` has nobody on the other side of
    // its suffix, in either shape, at the root or under a directory.
    try testing.expect(twinCaseStemOf("_twin.lin") == null);
    try testing.expect(twinCaseStemOf("d/_twin.lin") == null);
    try testing.expect(twinCaseStemOf("_twin/main.lin") == null);
}

test "two records differing only in the file each was compiled from are one record" {
    // A twin is compiled from another path, so its record differs in the
    // provenance blob and in every operation's location, and in nothing else.
    // The comparison is `sameCode`, the one implementation of "position is
    // not code" -- a second comparator here would be the same rule twice.
    const one =
        "  llvm.mlir.global internal constant @linea_file0(\"tests/a.lin\\00\") : !llvm.array<12 x i8>\n" ++
        "    %v0 = arith.constant 0 : i64 loc(\"tests/a.lin\":1:1)";
    const other =
        "  llvm.mlir.global internal constant @linea_file0(\"tests/a_twin.lin\\00\") : !llvm.array<17 x i8>\n" ++
        "    %v0 = arith.constant 0 : i64 loc(\"tests/a_twin.lin\":1:1)";
    const moved =
        "  llvm.mlir.global internal constant @linea_file0(\"tests/a_twin.lin\\00\") : !llvm.array<17 x i8>\n" ++
        "    %v0 = arith.constant 1 : i64 loc(\"tests/a_twin.lin\":1:1)";
    const shorter =
        "  llvm.mlir.global internal constant @linea_file0(\"tests/a_twin.lin\\00\") : !llvm.array<17 x i8>";

    try testing.expect(sameCode(one, other));
    try testing.expect(!sameCode(one, moved));
    try testing.expect(!sameCode(one, shorter));
}

/// A twin's record of what the backend receives, held against its sibling's.
///
/// Each `.mlir` golden on its own says only what its own case produced, and
/// `-Dupdate` rewrites both -- so a pair that drifted apart would be accepted
/// together, and the relation the pair exists for would be enforced nowhere.
/// This is the one thing that reads the two side by side.
///
/// Asked after the walk, so the goldens are the ones this run settled rather
/// than the ones it was about to rewrite. That also makes the answer
/// independent of which of the pair a walker reached first.
///
/// **Bound:** one pass over the corpus's paths, and one read of each file of
/// each pair.
fn checkTwins(
    gpa: std.mem.Allocator,
    io: std.Io,
    failures: *std.ArrayList(Failure),
    root: []const u8,
    golden_root: []const u8,
    paths: []const []const u8,
) !void {
    // Walked by case rather than by golden, so a twin that records no
    // module is a failure instead of a pair whose relation nothing enforces:
    // a loop over goldens cannot notice the golden that is not there.
    for (paths) |p| {
        const stem = twinCaseStemOf(p) orelse continue;
        const golden = try std.mem.concat(gpa, u8, &.{ stem, ".mlir" });
        const sibling = try std.mem.concat(gpa, u8, &.{ stem[0 .. stem.len - twin_suffix.len], ".mlir" });

        const twin_text = try readIfExists(io, gpa, try std.fs.path.join(gpa, &.{ golden_root, golden })) orelse {
            try failures.append(gpa, .{
                .path = try displayPath(gpa, root, p),
                .what = "is a twin that records no module",
                .expected = try displayPath(gpa, golden_root, golden),
                .actual = "nothing to hold the pair to",
            });
            continue;
        };
        const sibling_text = try readIfExists(io, gpa, try std.fs.path.join(gpa, &.{ golden_root, sibling })) orelse {
            try failures.append(gpa, .{
                .path = try displayPath(gpa, root, p),
                .what = "is a twin of a case that records no module",
                .expected = try displayPath(gpa, golden_root, sibling),
                .actual = "nothing with that stem",
            });
            continue;
        };

        if (sameCode(twin_text, sibling_text)) continue;
        try failures.append(gpa, .{
            .path = try displayPath(gpa, root, p),
            .what = "emits a different module from the case it is a twin of",
            .expected = sibling_text,
            .actual = twin_text,
        });
    }
}

/// The cases under a corpus root that record nothing.
///
/// `stems` is every case's, relative to the root; `paths` is in `collectPaths`
/// order.
///
/// The mirror of `orphanGoldens`, and the same argument turned round. A golden
/// nothing opens cannot fail; neither can a case that opens none. Such a case
/// is not nothing -- it is walked, and the properties that read a tree run over
/// it -- but what the compiler *did* with it is compared against nothing, which
/// is the half a reader assumes is there.
///
/// Nothing else notices. `-Dupdate` fills goldens rather than creating them, so
/// the file has to exist before it can be written to; and the walk counts the
/// case either way. Six cases written for a construct the compiler did not have
/// yet were counted and reported OK on the day they were written, and went on
/// being counted while it was built.
///
/// It does not extend to an empty golden: a corpus case whose golden and
/// output are both empty is already refused, because a case can produce
/// nothing by doing nothing.
fn unpinnedStems(
    gpa: std.mem.Allocator,
    stems: []const []const u8,
    paths: []const []const u8,
) ![]const []const u8 {
    var out: std.ArrayList([]const u8) = .empty;
    for (stems) |stem| {
        var records = false;
        for (golden_extensions) |e| {
            const wanted = try std.mem.concat(gpa, u8, &.{ stem, e });
            defer gpa.free(wanted);
            if (holdsPath(paths, wanted)) {
                records = true;
                break;
            }
        }
        // A session's golden sits inside the case rather than beside it,
        // because a script and what it was answered are one case's two halves
        // and neither names the other. It pins what the case does exactly as a
        // stem-named golden pins what a program does.
        if (!records) {
            const inside = try std.mem.concat(gpa, u8, &.{ stem, "/", session_golden });
            defer gpa.free(inside);
            records = holdsPath(paths, inside);
        }
        if (!records) try out.append(gpa, stem);
    }
    return out.toOwnedSlice(gpa);
}

test "a case that records nothing is unpinned" {
    const gpa = testing.allocator;

    // One file case with a golden, one directory case with a golden, and one
    // file case with none. Which golden it is does not matter: a case that
    // records any of them has something that can disagree.
    const paths = [_][]const u8{
        "modules/pair.exit",
        "modules/pair/main.lin",
        "recovery/kept.ast",
        "recovery/kept.lin",
        "recovery/silent.lin",
    };
    const stems = [_][]const u8{ "modules/pair", "recovery/kept", "recovery/silent" };

    const found = try unpinnedStems(gpa, &stems, &paths);
    defer gpa.free(found);

    try testing.expectEqual(@as(usize, 1), found.len);
    try testing.expectEqualStrings("recovery/silent", found[0]);
}

test "a golden of any kind pins a case" {
    const gpa = testing.allocator;

    // Every extension, one case each, so that adding one to
    // `golden_extensions` without teaching this rule about it fails here.
    var paths: std.ArrayList([]const u8) = .empty;
    defer paths.deinit(gpa);
    var stems: std.ArrayList([]const u8) = .empty;
    defer stems.deinit(gpa);
    var owned: std.ArrayList([]const u8) = .empty;
    defer {
        for (owned.items) |o| gpa.free(o);
        owned.deinit(gpa);
    }

    for (golden_extensions, 0..) |e, i| {
        const stem = try std.fmt.allocPrint(gpa, "c{d}", .{i});
        try owned.append(gpa, stem);
        const golden = try std.mem.concat(gpa, u8, &.{ stem, e });
        try owned.append(gpa, golden);
        try stems.append(gpa, stem);
        try paths.append(gpa, golden);
    }
    std.mem.sort([]const u8, paths.items, {}, lessByPath);

    const found = try unpinnedStems(gpa, stems.items, paths.items);
    defer gpa.free(found);
    try testing.expectEqual(@as(usize, 0), found.len);
}

test "a golden whose stem names no case is an orphan" {
    const gpa = testing.allocator;

    // A case that is one file and a case that is a directory each anchor their
    // own goldens. A transcript is its own golden, so a stream golden beside
    // one is opened by nothing, like the `.ast` whose case is gone.
    const paths = [_][]const u8{
        "cmd/usage.cmd",
        "cmd/usage.exit",
        "modules/pair.exit",
        "modules/pair/main.lin",
        "modules/pair/other.lin",
        "recovery/gone.ast",
        "recovery/kept.ast",
        "recovery/kept.lin",
    };

    const found = try orphanGoldens(gpa, &paths, &paths);
    defer gpa.free(found);

    try testing.expectEqual(@as(usize, 2), found.len);
    try testing.expectEqualStrings("cmd/usage.exit", found[0]);
    try testing.expectEqualStrings("recovery/gone.ast", found[1]);
}

test "a file that records nothing is not a golden" {
    const gpa = testing.allocator;

    // A corpus holds fixtures and prose beside its cases. Neither is compared
    // against anything, so neither can be orphaned -- a rule that flagged
    // every unrecognised file would be a rule nobody could keep.
    const paths = [_][]const u8{
        "cmd/README.md",
        "cmd/fixtures/a_marker_that_does_not_close.fixture",
        "fuzz/corpus.zig",
    };

    const found = try orphanGoldens(gpa, &paths, &paths);
    defer gpa.free(found);

    try testing.expectEqual(@as(usize, 0), found.len);
}

test "a golden walked apart from the cases is anchored by the case of its name" {
    const gpa = testing.allocator;
    const cases = [_][]const u8{ "accounts/main.lin", "hello.lin" };
    const goldens = [_][]const u8{ "accounts.exit", "gone.out", "hello.exit" };
    const found = try orphanGoldens(gpa, &goldens, &cases);
    defer gpa.free(found);
    try testing.expectEqual(@as(usize, 1), found.len);
    try testing.expectEqualStrings("gone.out", found[0]);

    // With no case to anchor them, every golden is reported.
    const beside = try orphanGoldens(gpa, &goldens, &.{});
    defer gpa.free(beside);
    try testing.expectEqual(goldens.len, beside.len);
}

/// What a case's C driver is called, where it has one.
///
/// One spelling, beside the manifest's, because both are read by matching a
/// basename and a second spelling would be a second rule about what a case may
/// hold.
const driver_name = "driver.c";

/// Finds every case among the paths of a corpus root.
fn collectCases(gpa: std.mem.Allocator, io: std.Io, root: []const u8, all: []const []const u8) ![]Case {
    var paths: std.ArrayList([]const u8) = .empty;
    for (all) |p| {
        if (!std.mem.endsWith(u8, p, ".lin")) continue;
        try paths.append(gpa, p);
    }

    // Which directories hold a `main.lin`, and are therefore the root of a
    // case. A `main.lin` beneath another one is a file of the outer case, not
    // a case of its own: imports only ever name a directory below, so the
    // outermost entry point is the one that can reach everything.
    var roots: std.ArrayList([]const u8) = .empty;
    for (paths.items) |p| {
        if (!std.mem.eql(u8, std.fs.path.basename(p), "main.lin")) continue;
        const d = std.fs.path.dirname(p) orelse continue;
        if (ownerOf(roots.items, d) != null) continue;
        try roots.append(gpa, d);
    }

    // Sorted paths put a case's files together only when they sit directly in
    // its directory, so grouping is by owner rather than by position: an
    // imported module is a subdirectory, and its files sort before the entry.
    var files_of = try gpa.alloc(std.ArrayList(InMemoryFile), roots.items.len);
    @memset(files_of, .empty);

    var cases: std.ArrayList(Case) = .empty;
    for (paths.items) |p| {
        if (ownerOf(roots.items, p)) |owner| {
            try files_of[owner].append(gpa, try readCase(gpa, io, root, p));
            continue;
        }

        const files = try gpa.alloc(InMemoryFile, 1);
        files[0] = try readCase(gpa, io, root, p);
        try cases.append(gpa, .{
            .display_path = files[0].path,
            .stem = try goldenStemOfCase(gpa, root, p),
            .entry = files[0].path,
            .files = files,
        });
    }

    // A case's manifest is read beside its source: it is what says which kind
    // of root the case is, and a case loaded from its `.lin` files alone is
    // loaded as a program whatever it says it is -- a library refused for
    // declaring no `main`, here and nowhere a person running the compiler would
    // ever see.
    //
    // The shallowest manifest marks the case's root; one deeper marks a
    // library the case holds, which its root may name as a dependency.
    const manifests = try gpa.alloc(?InMemoryFile, roots.items.len);
    @memset(manifests, null);
    const libraries = try gpa.alloc(std.ArrayList(InMemoryFile), roots.items.len);
    @memset(libraries, .empty);
    for (all) |p| {
        if (!std.mem.eql(u8, std.fs.path.basename(p), loader.manifest_name)) continue;
        const owner = ownerOf(roots.items, p) orelse continue;
        const read = try readCase(gpa, io, root, p);
        if (manifests[owner]) |held| {
            if (std.mem.count(u8, held.path, "/") <= std.mem.count(u8, p, "/")) {
                try libraries[owner].append(gpa, read);
                continue;
            }
            try libraries[owner].append(gpa, held);
        }
        manifests[owner] = read;
    }

    // A driver is read beside the source the same way, and for the same
    // reason: it is not Linea source, and a library that publishes something
    // is only shown to publish it by something outside calling it.
    const drivers = try gpa.alloc(?InMemoryFile, roots.items.len);
    @memset(drivers, null);
    for (all) |p| {
        if (!std.mem.eql(u8, std.fs.path.basename(p), driver_name)) continue;
        const owner = ownerOf(roots.items, p) orelse continue;
        drivers[owner] = try readCase(gpa, io, root, p);
    }

    // Every other file beneath a directory case is one its program may embed.
    // A golden is the case's record rather than its input, so one beneath the
    // directory is left to the orphan check, which reports it.
    const data_of = try gpa.alloc(std.ArrayList(InMemoryFile), roots.items.len);
    @memset(data_of, .empty);
    for (all) |p| {
        if (!isCaseData(p)) continue;
        const owner = ownerOf(roots.items, p) orelse continue;
        try data_of[owner].append(gpa, try readCase(gpa, io, root, p));
    }

    // C sources and headers a program's manifest may build, read beside the
    // source for the reason the driver is.
    const c_files = try gpa.alloc(std.ArrayList(InMemoryFile), roots.items.len);
    @memset(c_files, .empty);
    for (all) |p| {
        if (!std.mem.endsWith(u8, p, ".c") and !std.mem.endsWith(u8, p, ".h")) continue;
        if (std.mem.eql(u8, std.fs.path.basename(p), driver_name)) continue;
        const owner = ownerOf(roots.items, p) orelse continue;
        try c_files[owner].append(gpa, try readCase(gpa, io, root, p));
    }

    for (roots.items, 0..) |d, i| {
        const entry = try displayPath(gpa, root, d);
        try cases.append(gpa, .{
            .display_path = entry,
            .stem = try goldenStemOfCase(gpa, root, try std.fs.path.join(gpa, &.{ d, "main.lin" })),
            .entry = entry,
            .files = try files_of[i].toOwnedSlice(gpa),
            .manifest = manifests[i],
            .libraries = try libraries[i].toOwnedSlice(gpa),
            .driver = drivers[i],
            .data = try data_of[i].toOwnedSlice(gpa),
            .native = nativeOf(try c_files[i].toOwnedSlice(gpa)),
        });
    }

    return cases.toOwnedSlice(gpa);
}

/// Whether a file beneath a directory case is a file the case's program may
/// embed: anything but its source, its manifest, its driver and a golden.
fn isCaseData(path: []const u8) bool {
    const base = std.fs.path.basename(path);
    if (std.mem.endsWith(u8, base, ".lin")) return false;
    if (std.mem.eql(u8, base, loader.manifest_name) or std.mem.eql(u8, base, driver_name)) return false;
    for (golden_extensions) |ext| if (std.mem.endsWith(u8, base, ext)) return false;
    return true;
}

test "a directory case carries every other file beneath it as data its program may embed" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    const io = testing.io;
    var tmp = testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    try tmp.dir.createDirPath(io, "tree/site/nested");
    try tmp.dir.createDirPath(io, "tree/site/templates");
    for ([_][]const u8{ "tree/site/main.lin", "tree/site/linea.json", "tree/site/page.txt", "tree/site/nested/x.sql", "tree/site/templates/card.html", "tree/site/stale.out", "tree/alone.lin" }) |path| {
        try tmp.dir.writeFile(io, .{ .sub_path = path, .data = "fn main() -> UInt8 { 0 }\n" });
    }
    const root = try tmp.dir.realPathFileAlloc(io, "tree", gpa);
    const cases = try collectCases(gpa, io, root, try collectPaths(gpa, io, root));

    try testing.expectEqual(@as(usize, 2), cases.len);
    const alone, const site = if (std.mem.endsWith(u8, cases[0].entry, "alone.lin")) .{ cases[0], cases[1] } else .{ cases[1], cases[0] };
    try testing.expectEqual(@as(usize, 0), alone.data.len);
    try testing.expectEqual(@as(usize, 3), site.data.len);
    var names: [3][]const u8 = undefined;
    for (site.data, &names) |d, *n| n.* = std.fs.path.basename(d.path);
    std.mem.sort([]const u8, &names, {}, lessByPath);
    try testing.expectEqualStrings("card.html", names[0]);
    try testing.expectEqualStrings("page.txt", names[1]);
    try testing.expectEqualStrings("x.sql", names[2]);
    // The manifest goes first, then the data, and the source keeps its place.
    const inputs = try inputsOf(gpa, site);
    try testing.expectEqual(site.files.len + 4, inputs.len);
    try testing.expectEqualStrings("linea.json", std.fs.path.basename(inputs[site.files.len].path));
}

/// The stem every golden of the case anchored at `rel` is opened under.
///
/// Asked of `corpus`, which is where the relation between a case and the stem
/// its goldens sit at is decided -- and which the driver already reads to know
/// which files not to reformat. This is the site that *assigns* the stem every
/// golden is opened under, so it is the one that most needs to agree.
fn goldenStemOfCase(gpa: std.mem.Allocator, root: []const u8, rel: []const u8) ![]const u8 {
    return (try corpus_layout.goldenStemOf(gpa, try std.fs.path.join(gpa, &.{ root, rel }))).?;
}

/// Which case root a path lies under, if any. A path lies under a root when
/// the root is one of its ancestor directories.
fn ownerOf(roots: []const []const u8, path: []const u8) ?usize {
    for (roots, 0..) |r, i| {
        if (path.len <= r.len) continue;
        if (!std.mem.startsWith(u8, path, r)) continue;
        if (path[r.len] != '/') continue;
        return i;
    }
    return null;
}

/// Diagnostics quote the path they were given, so the corpus is read through
/// the path the runner was handed and reported through a checkout-relative
/// one. Otherwise every rendered golden would record the absolute location of
/// the machine that generated it.
fn displayPath(gpa: std.mem.Allocator, root: []const u8, rel: []const u8) ![]const u8 {
    return std.fs.path.join(gpa, &.{ corpus_layout.split(root).display, rel });
}

test "narrowed corpus roots preserve diagnostic paths and witness locations" {
    const gpa = testing.allocator;
    const roots = [_][]const u8{ "tests/vec", "/checkout/tests/vec/", "examples", "/checkout/examples/demo" };
    const displays = [_][]const u8{ "tests/vec/case.lin", "tests/vec/case.lin", "examples/case.lin", "examples/demo/case.lin" };
    for (roots, displays) |root, expected| {
        const path = try displayPath(gpa, root, "case.lin");
        defer gpa.free(path);
        try testing.expectEqualStrings(expected, path);
    }
}

fn readCase(gpa: std.mem.Allocator, io: std.Io, root: []const u8, rel: []const u8) !InMemoryFile {
    return .{
        .path = try displayPath(gpa, root, rel),
        .text = try readFileAlloc(io, gpa, try std.fs.path.join(gpa, &.{ root, rel })),
    };
}

/// A command case: a transcript of shell commands with their expected output
/// inline, so the file is its own golden.
///
/// The compiler is driven in-process everywhere else in this runner, which is
/// faster and gives better failure messages. It cannot answer questions about
/// the command line itself, though -- exit codes, which stream a message went
/// to, how a usage error reads -- and those are the parts a user meets first.
const CommandCase = struct {
    text: []const u8,
    stem: []const u8,
    display_path: []const u8,
};

/// Runs one transcript case and compares its rendering, with the outputs that
/// ran, against the file. `--update` rewrites the file in place.
///
/// Never consults the outcome cache: a transcript runs a shell and tools the
/// cache does not stamp, so a cached pass could hide a change in any of them.
fn checkTranscript(
    gpa: std.mem.Allocator,
    io: std.Io,
    failures: *std.ArrayList(Failure),
    compiler: []const u8,
    environ: std.process.Environ,
    runtime: ?[]const u8,
    sanitize: ?[]const u8,
    root: []const u8,
    scratch: []const u8,
    case: CommandCase,
    update: bool,
) !void {
    const text = case.text;
    var parsed = try transcripts.parse(gpa, text);
    defer parsed.deinit(gpa);

    const name = try scratchName(gpa, case.display_path);
    const relative = try std.fmt.allocPrint(gpa, "{s}/{s}.transcript", .{ scratch, name });
    std.Io.Dir.cwd().deleteTree(io, relative) catch {};
    try std.Io.Dir.cwd().createDirPath(io, relative);
    // A case that hangs keeps its directory, so files its commands wrote,
    // such as a server's log, can be read after the run.
    var keep = false;
    defer if (!keep) std.Io.Dir.cwd().deleteTree(io, relative) catch {};
    const directory = try std.Io.Dir.cwd().realPathFileAlloc(io, relative, gpa);

    const ran = transcripts.run(gpa, io, .{
        .linea = compiler,
        .root = root,
        .directory = directory,
        .environ = environ,
        .runtime = runtime,
        .sanitize = sanitize,
    }, parsed) catch |e| {
        try failures.append(gpa, .{
            .path = case.display_path,
            .what = "running the transcript",
            .expected = "every command runs",
            .actual = @errorName(e),
        });
        return;
    };
    defer ran.deinit(gpa);

    const rendered = try transcripts.render(gpa, parsed, ran.steps);
    if (ran.timed_out) {
        keep = true;
        try failures.append(gpa, .{
            .path = case.display_path,
            .what = "running the transcript",
            .expected = try std.fmt.allocPrint(gpa, "every command finishes within {d} seconds", .{transcripts.default_timeout_seconds}),
            .actual = try std.fmt.allocPrint(gpa, "timed out; what ran before the deadline, with its files in {s}:\n{s}", .{ directory, rendered }),
        });
        return;
    }

    const golden = try std.mem.concat(gpa, u8, &.{ case.stem, ".cmd" });
    if (try compare(gpa, io, failures, case.display_path, "transcript", golden, text, rendered, update, false)) {
        std.debug.print("updated {s}\n", .{golden});
    }
}

/// What `compiler help` prints: the commands that binary offers. A help this
/// cannot read stops the walk rather than passing transcripts over.
fn compilerHelp(gpa: std.mem.Allocator, io: std.Io, compiler: []const u8) ![]const u8 {
    const ran = try hermeticRun(gpa, io, .{ .argv = &.{ compiler, "help" } });
    defer gpa.free(ran.stderr);
    const exited = switch (ran.term) {
        .exited => |code| code == 0,
        else => false,
    };
    if (!exited or !transcripts.isUsage(ran.stdout)) {
        std.debug.print("conformance: `{s} help` printed no usage this runner can read:\n{s}{s}\n", .{ compiler, ran.stdout, ran.stderr });
        return error.UnreadableCompilerHelp;
    }
    return ran.stdout;
}

/// Exercises the command-line handoff to the external compiler. The recorder
/// refuses after printing its optimisation arguments, so the real frontend and
/// MLIR conversion run without depending on an optimiser's choice of code.
fn checkCommandOptimisation(
    gpa: std.mem.Allocator,
    io: std.Io,
    failures: *std.ArrayList(Failure),
    compiler: []const u8,
    environ: std.process.Environ,
    runtime: ?[]const u8,
    scratch: []const u8,
) !void {
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const a = arena.allocator();
    const directory = try std.fmt.allocPrint(a, "{s}/command-optimisation-{d}", .{
        scratch, std.Io.Clock.awake.now(io).nanoseconds,
    });
    try std.Io.Dir.cwd().createDirPath(io, directory);
    defer std.Io.Dir.cwd().deleteTree(io, directory) catch {};
    const root = try std.Io.Dir.cwd().realPathFileAlloc(io, directory, a);
    const bin = try std.fs.path.join(a, &.{ root, "bin" });
    try std.Io.Dir.cwd().createDirPath(io, bin);
    try std.Io.Dir.cwd().writeFile(io, .{
        .sub_path = try std.fs.path.join(a, &.{ bin, "cc" }),
        .flags = .{ .permissions = .executable_file },
        .data =
        \\#!/bin/sh
        \\for argument do
        \\    case "$argument" in -O*) printf '%s\n' "$argument" >&2 ;; esac
        \\done
        \\exit 1
        \\
        ,
    });
    const source = try std.fs.path.join(a, &.{ root, "main.lin" });
    try std.Io.Dir.cwd().writeFile(io, .{
        .sub_path = source,
        .data =
        \\fn main() -> UInt8 { 0 }
        \\
        ,
    });
    var child_environ = try environ.createMap(a);
    defer child_environ.deinit();
    try child_environ.put("PATH", try std.fmt.allocPrint(a, "{s}:{s}", .{
        bin, environ.getPosix("PATH") orelse "",
    }));
    if (runtime) |rt| try child_environ.put(toolchain.runtime_override, rt);

    var levels: [toolchain.levels.len + 1]?[]const u8 = .{null} ** (toolchain.levels.len + 1);
    for (toolchain.levels, levels[1..]) |level, *slot| slot.* = level;
    for ([_][]const u8{ "build", "run" }) |command| {
        for (levels) |level| {
            var argv: std.ArrayList([]const u8) = .empty;
            try argv.appendSlice(a, &.{ compiler, command, source });
            if (level) |chosen| try argv.appendSlice(a, &.{ "-O", chosen });
            if (std.mem.eql(u8, command, "build")) {
                try argv.appendSlice(a, &.{ "-o", try std.fs.path.join(a, &.{ root, "program" }) });
            }
            const result = try hermeticRun(a, io, .{
                .argv = argv.items,
                .environ_map = &child_environ,
            });
            const status: u8 = switch (result.term) {
                .exited => |code| code,
                else => 255,
            };
            const expected = try std.fmt.allocPrint(a, "error: cc failed\n-O{s}\n", .{level orelse toolchain.default_level});
            if (status != 74 or result.stdout.len != 0 or !std.mem.eql(u8, expected, result.stderr)) {
                try failures.append(gpa, .{
                    .path = "command optimisation",
                    .what = try std.fmt.allocPrint(gpa, "{s} forwards {s} to cc", .{ command, level orelse "the default" }),
                    .expected = try std.fmt.allocPrint(gpa, "exit 74, empty stdout, stderr:\n{s}", .{expected}),
                    .actual = try std.fmt.allocPrint(gpa, "exit {d}, stdout:\n{s}stderr:\n{s}", .{ status, result.stdout, result.stderr }),
                });
            }
        }
    }
    std.debug.print("conformance: 14 command optimisation handoffs checked\n", .{});
}

/// What there was to check, counted from the walk rather than from a run.
///
/// A floor says a property was asked about at least so many files. This says
/// how many files there were to ask about, which is the other side of the same
/// number and comes from the corpus's own contents rather than from a counter
/// a check increments. A tally above it was fed by something that is not the
/// corpus -- the generated programs being the only such thing here, and how
/// many of those there are is a flag.
const Corpus = struct {
    /// Every file the cases are made of.
    files: u32,
    /// Cases of more than one file, which are the only ones whose files have
    /// an order to give in the other direction.
    modules: u32,
    /// Command lines, which are cases of a kind of their own.
    commands: u32,
    /// Every case, whatever it is made of -- what a property asked once per
    /// case is entitled to be asked.
    cases: u32,
    /// Cases of exactly one file. A property reading spans against one text
    /// can be asked about no other kind, so this is its whole population and
    /// not a subset of a larger one it silently declines.
    files_alone: u32,
    /// Scripts of protocol messages, which are cases of a kind of their own.
    sessions: u32,
    /// Programs, which are the directories holding a manifest. A property
    /// about what a program exports can be asked about no other kind.
    programs: u32,
    /// The functions the cases declare, the library's excluded: the library is
    /// loaded again for every case, so counting it would report how many cases
    /// there are rather than how much code the corpus holds.
    ///
    /// Filled from each case's tree as it is parsed rather than by the walk
    /// that finds the cases, because which declarations are functions is the
    /// parser's answer and the walk has not read a byte of them. Filled from
    /// the tree and not from the property that reads it, so a property that
    /// quietly stops at the first function of a case does not also shrink what
    /// it is measured against.
    functions: u32,
    /// The settled references the cases write -- `Self.Item` and everything
    /// else spelled as a name, a dot and a name -- the library's excluded for
    /// the reason the functions are.
    ///
    /// Counted from the tree's own tables rather than by the walk the property
    /// makes over the positions a type may be written in: an argument's settled
    /// reference sits in the flat table of arguments whatever it was written
    /// under, so a walk that stopped descending into `Option[Self.Item]`
    /// disagrees with this number instead of shrinking along with it.
    settled_refs: u32,

    fn of(cases: []const Case, paths: []const []const u8) Corpus {
        var counted: Corpus = .{
            .files = 0,
            .modules = 0,
            .commands = 0,
            .cases = 0,
            .files_alone = 0,
            .sessions = 0,
            .programs = 0,
            .functions = 0,
            .settled_refs = 0,
        };
        for (cases) |case| {
            counted.files += @intCast(case.files.len);
            counted.cases += 1;
            if (case.files.len > 1) counted.modules += 1;
            if (case.files.len == 1) counted.files_alone += 1;
        }
        for (paths) |p| {
            if (isCommandPath(p)) counted.commands += 1;
            if (isSessionPath(p)) counted.sessions += 1;
            if (std.mem.eql(u8, std.fs.path.basename(p), loader.manifest_name)) counted.programs += 1;
        }
        return counted;
    }
};

/// A property a run asserts that is not a rewrite or a mutation.
///
/// Here so that one which stops running fails the run rather than going quiet.
/// The rewrites and mutations already had that; a property asserted inline had
/// nothing, so it could stop being asked and the run would report the silence
/// as success.
///
/// Every property a run makes is a member. That is the whole of what the enum
/// is for: a member carries a floor and a population, so a check that stops
/// running fails the floor and a chance the corpus gives that nothing takes
/// fails the accounting -- and neither is visible for a property that is only
/// a block of code in the case loop.
const Property = enum {
    formatting,
    normal_form,
    file_order,
    /// Emitting each token's gap and then its text reproduces the file. The
    /// guarantee every formatting tool depends on.
    losslessness,
    /// Tokenising terminates and leaves a well-formed stream, which each file
    /// ends its own.
    token_stream,
    /// Parsing yields a tree with no hole in it: every body is a block and the
    /// whole of it renders. The executable form of the parser having no error
    /// path.
    complete_tree,
    /// No use reaches a binding from outside the region that declares it.
    regions,
    /// An expression is poison only where something was reported, so no pass
    /// swallowed an error.
    poison_free,
    /// No two extents the tree records cross: the premise the position index
    /// sweeps the tokens with a stack on, held over the programs error recovery
    /// built rather than assumed of them.
    nested_extents,
    /// What a language server publishes about a program is what `check`
    /// reports about it.
    published_diagnostics,
    /// A name reaches a binding the scope tree makes visible where it is
    /// written.
    ///
    /// The tree is recorded by the walk that binds names, so this is what says
    /// it is that walk's answer and not a second one. It is also the only
    /// thing that can say it: the tree has no consumer.
    names_in_scope,
    /// A parameter hint names the parameter the call reaches, and shows that
    /// parameter's own convention.
    ///
    /// The one answer an editor gives that a reader acts on without checking:
    /// a hint saying `read` where the pass took the value is worse than no
    /// hint. Two answers to one question is the defect this whole design is
    /// organised against, and a call site is where it would appear.
    parameter_hints,
    /// A rename applied to a case's own source leaves a program that still
    /// compiles. The one answer a client writes back into the file, so the
    /// only thing that says it is right is checking the result.
    renamed,
    /// A server driven through the protocol over any program finishes, and
    /// answers rather than failing. The frontend's guarantee that no input is
    /// refused, asked of the thing an editor actually talks to.
    survives,
    /// One script answered twice in one process gives the same bytes twice.
    ///
    /// Not because correctness depends on the order of a list, but because
    /// nothing else catches the nondeterminism a server accumulates -- a map
    /// iterated for diagnostics, a set of edits emitted in whatever order it
    /// held them. This compiler has already shipped one: dead schedules were
    /// reported in hash order until a case with six of them said so.
    deterministic,
    /// A session case holds its program once.
    ///
    /// A `didOpen` carries its source inline and that inline copy is what the
    /// server answers from, while the file of the same name beside the script
    /// is what `check` runs over and every corpus property reads. One program
    /// under one name in two places, and a field added to the file changes
    /// nothing any golden can show unless the two are compared.
    ///
    /// Counted per session, not per document: how many documents a script
    /// opens is what the check itself reads out of the script, so a population
    /// taken from there would account for the check by construction. The
    /// sessions are the corpus's own number, and every one of them is either
    /// asked or passed over.
    held_once,
    /// What a user meets first: the exit status, the stream a message went to,
    /// and how a usage error reads.
    ///
    /// Held to a floor for the reason the rewrites are. These cases are the
    /// only ones that drive the real binary, and they are reached through a
    /// directory that is opened with `catch null` and walked for a suffix --
    /// so deleting `tests/cmd`, renaming it, or renaming the suffix left a run
    /// that reported zero commands checked and exited 0.
    command,
    /// The symbol index offers nothing the program cannot import.
    ///
    /// `import` resolves relative to a module's own directory, so a module in
    /// one program cannot be reached from another, and a name offered across
    /// that line is an import nobody can write. The add-import quick fix
    /// takes the offer literally, so an offer that cannot be imported is a
    /// fix that breaks the program.
    ///
    /// Asked over the corpus rather than over a workspace made for it: the
    /// corpus is a directory of a hundred and fifty unrelated programs, which
    /// is the shape the rule exists for and one nobody would think to build.
    importable,

    /// Every name a completion offers is one the resolver would bind at that
    /// point, and it offers no fewer than that point has.
    ///
    /// The one thing that keeps completion a reading of what the compiler
    /// decided rather than a second opinion about what a name means, and the
    /// only thing that can say so: nothing else reads the scope chain from a
    /// point rather than from a name.
    completion_offers,

    /// Accepting what the server offers leaves a program that checks.
    ///
    /// An offer that does not compile is worse than none: a reader takes it,
    /// the squiggle stays or a new one appears, and now the file holds text
    /// nobody wrote. Nothing about the shape of an action or of a completion
    /// item would say so, which is why this applies the edits and checks the
    /// program again.
    ///
    /// Both things a client writes back from this server: a quick fix, and a
    /// completion item carrying the import that would reach the name it
    /// offers.
    ///
    /// Asked of every program that holds a module an import of it would name,
    /// by writing the undefined name and the cursor into the program rather
    /// than by waiting for the corpus to hold one: a corpus of programs that
    /// compile offers no fix, and a property asked only where an offer happens
    /// to be made speaks for the cases written for it and for nothing else.
    accepted_offers,

    /// A completion answers from whatever the parser recovered.
    ///
    /// A completion is asked from broken text far more often than from whole
    /// text, so the set that matters is the shapes the parser's recovery
    /// leaves rather than the half-written constructs somebody thought to
    /// write a case for. Asked once per shape per program, over the shapes
    /// read off the parser's own recovery sites.
    completion_recovers,

    /// A settled reference recorded inside an implementation names the type
    /// that implementation wrote.
    ///
    /// **Not every settled reference**, and the counts say which: one written
    /// in a trait's own signature is answered per call and recorded against no
    /// token, so it is passed over here and checked by nothing anywhere. That
    /// half is counted apart from the refusals and printed on its own line,
    /// because a single "passed over" reads as coverage declined and this is
    /// coverage missing.
    ///
    /// `Self.Item` is whatever an implementation settled `Item` to, and the
    /// checker answers it by reading the pairing it recorded when it settled
    /// them. A property comparing that answer against that record would be the
    /// same read twice and could not fail, so this one crosses the seam: it
    /// finds the implementation from the source -- the type after `for`, the
    /// trait before it, the arguments the trait was given -- takes the type
    /// that impl's own `type Item = ...` line writes, and holds the checker's
    /// answer to what that line says. Which is what a reader of the program
    /// believes, and the only thing the recorded pairing can drift from.
    ///
    /// What that catches: a settled reference resolved through the wrong
    /// implementation, which is one keyed lookup away whenever a type
    /// implements one trait twice at different arguments; a substitution that
    /// dropped an argument; a run of names read from the wrong end.
    settled_refs,

    /// Every float literal a case spells reaches the backend as the double it
    /// means: the emitted constant's spelling parses back to the same bits
    /// the literal's own text does.
    ///
    /// The constant crosses the pipeline as text twice -- the literal in, the
    /// spelling out -- and each crossing is a parse someone can get wrong. A
    /// spelling that is close rather than exact would pass every eval case
    /// whose comparisons tolerate it, so this reads the bits.
    float_round_trip,

    /// A consuming walk hands each element over as a value, and hands it over
    /// once.
    ///
    /// Both halves, and each is a mutation of the case's own source held to the
    /// compiler's answer rather than to a reading of the loop. Emptying the
    /// body leaves an element nothing takes, which is [O-Leak]: the walk owes
    /// what it handed over, so it handed over at least one. Taking the binder
    /// at the top of the body leaves the body's own use naming what is gone,
    /// which is [O-Move]: what the walk handed over is one value, so the body
    /// cannot have it twice.
    ///
    /// Asked where the element is Linear, and nowhere else. A discardable element owes
    /// nothing, so an empty body is a program and neither mutation says
    /// anything -- which is why the corpus's own walks over numbers are passed
    /// over here rather than checked into a number that means nothing.
    ///
    /// **What it does not say:** how many times the loop ran. That every
    /// position of an array is reached exactly once is what the recorded exit
    /// statuses of the walks over one say, and what this reads is the
    /// obligation each iteration carries.
    walk_consumes,

    /// A lending walk leaves what it walks live, and a consuming walk does not.
    ///
    /// The pair rather than either half. A second lending walk written after
    /// the first must be a program -- the sequence was lent and not taken, so
    /// it is still there to lend again -- and that on its own would also pass
    /// under a compiler that had stopped modelling the head at all. So the same
    /// second walk is written after the *consuming* form of the first, where
    /// it must be [O-Move]: the head is gone, and the only thing that could
    /// have taken it is the loop.
    ///
    /// The second half asks the head to be an array, because that is the one
    /// head both forms walk: a consuming walk over anything else needs the
    /// `Sequence` a lending one never asked for, and the refusal would be about
    /// the missing implementation rather than about what the loop took. How
    /// many walks each half reached is reported beside the property.
    walk_lends,

    /// A walk that cannot abandon what it holds is refused at the walk.
    ///
    /// [O-LinearWalk] and [O-LinearTail] are the two rules about a walk holding
    /// something at an exit, and the iterator they are about is a value no
    /// reader wrote: it is built by the desugar, or it is the positions a `trav`
    /// names. So the message has to point at something the reader did write,
    /// which is the walk's own head or the traversal's positions -- and nothing
    /// but this compares where the diagnostic points against where those are.
    ///
    /// Read from the tree, not from the checker's memory of where it reported:
    /// the spans are looked up among the walks and traversals the case wrote,
    /// so a diagnostic anchored at the body, at the binder or at a hidden
    /// binding fails here whatever the checker believed it was pointing at.
    walk_named,

    /// Every walk answers as the loop it stands for: refused by the same
    /// rules, or accepted and running to the same answer.
    ///
    /// Asked of every case of one file on the ordinary walk, refused cases
    /// included, rather than of the focused population: the defect it exists
    /// for is a walk the ownership pass accepts while its loop is refused, and
    /// that shape is found in programs nobody wrote a property case for.
    /// `checkWalkLoops` asserts it; a case is counted where it claimed one.
    walk_loops,

    /// A help that names an edit concrete enough to write fixes what it was
    /// written for.
    ///
    /// A help a reader follows verbatim and is told the same thing again is
    /// worse than none, and nothing in the help's wording says whether it
    /// works. So each edit a diagnostic carries, the machine-readable form of
    /// one of its helps, is applied to the case and the case is checked again
    /// as `linea check` checks it: the error the help answered must be gone
    /// from where it was reported, and the edit must add no error of its own
    /// -- none loading reports that it did not before, and none pointing at a
    /// line the edit wrote. A different error elsewhere is the program's next
    /// mistake and is allowed. Then the fixes are followed in turn, a bounded
    /// number of times, so two helps that each undo the other are reported
    /// rather than chased.
    ///
    /// There is no golden: the case is its own expectation, and `-Dupdate`
    /// has nothing to accept. Counted per case of one file; a case is
    /// checked where at least one of its diagnostics carried an edit, and
    /// the cases are counted again by the kind of fix they carried, so a
    /// kind of help that stops writing its fix is seen.
    help_edits,

    /// A range pattern's exhaustiveness is the type's own bounds.
    ///
    /// Held by the mutation that narrows a covering arm by one value, which is
    /// the whole of the claim: an arm reaching the type's top is what covers
    /// it, and moving that bound by one must leave a program the checker
    /// refuses for the gap. Counted here for the reason above, and asserted
    /// there rather than a second time.
    range_exhaustive,

    /// The fewest files this property must be asked about. See
    /// `Transform.floor`.
    ///
    /// Counted over the corpus alone, which is why the run keeps a second
    /// tally for the generated programs rather than one sum: how many of those
    /// there are is a flag, and a floor reading a count they contributed to
    /// would be measuring the flag. At `-Dprograms=200` the corpus could fall
    /// to a third of what it reaches and clear every number below.
    fn floor(self: Property) u32 {
        return switch (self) {
            .file_order,
            .regions,
            .published_diagnostics,
            .renamed,
            .survives,
            .importable,
            .accepted_offers,
            .completion_recovers,
            .walk_consumes,
            .walk_lends,
            .range_exhaustive,
            => 1,
            .formatting, .normal_form, .losslessness, .token_stream => 350,
            .complete_tree, .poison_free, .nested_extents, .names_in_scope, .parameter_hints => 300,
            .deterministic => 6,
            .held_once => 50,
            .command => 12,
            .completion_offers => 900,
            .settled_refs => 111,
            .float_round_trip => 6,
            .walk_named => 5,
            .walk_loops => 50,
            .help_edits => 50,
        };
    }

    /// How many chances the corpus gives this property: the part of it the
    /// property is asked about, counted from the walk.
    ///
    /// The floor above is a lower bound and cannot see a tally the generated
    /// programs fed: those only ever raise a number, and a raised number
    /// clears a floor. This is the other side of it, and it comes from the
    /// corpus's own contents rather than from a counter a check increments.
    fn populationIn(self: Property, corpus: Corpus) u32 {
        return switch (self) {
            .formatting, .normal_form, .losslessness, .token_stream, .survives => corpus.files,
            .file_order => corpus.modules,
            .complete_tree,
            .poison_free,
            .nested_extents,
            .names_in_scope,
            .published_diagnostics,
            .parameter_hints,
            .renamed,
            => corpus.cases,
            .regions => corpus.files_alone,
            .command => corpus.commands,
            .deterministic, .held_once => corpus.sessions,
            .importable, .accepted_offers => corpus.programs,
            .completion_offers => corpus.functions,
            .completion_recovers => corpus.programs * @as(u32, recovery_shapes.len),
            .settled_refs => corpus.settled_refs,
            .float_round_trip,
            .walk_consumes,
            .walk_lends,
            .walk_named,
            .walk_loops,
            .range_exhaustive,
            .help_edits,
            => corpus.cases,
        };
    }

    /// Whether the run's two corpus tallies account for every chance the
    /// corpus gave.
    ///
    /// Each chance is counted once, on one side or the other: checked where
    /// the property held, passed over where it did not apply -- a file that
    /// does not parse has no formatting to compare, and a command naming a
    /// debugging aid a release build hides is never run. So the two sum to the
    /// population exactly.
    ///
    /// Exactly, rather than at most it. An upper bound alone leaves slack the
    /// size of what the property declines, and a tally the generated programs
    /// fed hides inside that slack until it has climbed past it -- so how large
    /// a leak had to be before anything caught it was decided by how much of
    /// the corpus this property cannot speak for, and that is not a number
    /// anyone chose. An equality has no slack: one generated program on the
    /// corpus's counter is one too many. It also catches the opposite, which no
    /// upper bound could -- a chance the corpus gave that neither counter saw.
    fn focused(self: Property) bool {
        return switch (self) {
            .file_order,
            .regions,
            .published_diagnostics,
            .renamed,
            .survives,
            .importable,
            .accepted_offers,
            .completion_recovers,
            .walk_consumes,
            .walk_lends,
            .range_exhaustive,
            => true,
            else => false,
        };
    }

    fn accountingPopulation(self: Property, corpus: Corpus, enabled: bool) Corpus {
        return if (self.focused() and !enabled) std.mem.zeroes(Corpus) else corpus;
    }

    fn accountsFor(self: Property, corpus: Corpus, checked: u32, passed_over: u32) bool {
        return checked + passed_over == self.populationIn(corpus);
    }

    /// What one of this property's counts is a count of. A module is not a
    /// file and neither is a command line, and a number is comparable against
    /// the corpus only if it says which of them it counts.
    fn subject(self: Property) []const u8 {
        return switch (self) {
            .formatting, .normal_form, .losslessness, .token_stream, .survives => "file",
            .file_order => "module",
            .complete_tree,
            .regions,
            .poison_free,
            .nested_extents,
            .names_in_scope,
            .published_diagnostics,
            .parameter_hints,
            .renamed,
            .walk_consumes,
            .walk_lends,
            .walk_named,
            .walk_loops,
            .range_exhaustive,
            .help_edits,
            => "case",
            .command => "command",
            .deterministic, .held_once => "session",
            .importable, .accepted_offers => "program",
            .completion_offers => "function",
            .completion_recovers => "program and shape",
            .settled_refs => "settled reference",
            .float_round_trip => "case",
        };
    }

    fn why(self: Property) []const u8 {
        return switch (self) {
            .formatting => "formatting preserves, settles and re-parses",
            .normal_form => "formatting is a normal form",
            .file_order => "a module's files may be given in either order",
            .losslessness => "the token stream reconstructs the file it came from",
            .token_stream => "a file's tokens end with its own eof",
            .complete_tree => "parsing yields a tree with no hole in it",
            .regions => "no use reaches a binding from outside its region",
            .poison_free => "an expression is poison only where something was reported",
            .nested_extents => "no extent the tree records crosses another",
            .names_in_scope => "a name reaches a binding the scope it sits in makes visible, and that scope makes nothing else visible",
            .published_diagnostics => "a server publishes the diagnostics `check` reports",
            .parameter_hints => "a parameter hint names the parameter the call reaches",
            .renamed => "a rename applied leaves a program that still compiles",
            .survives => "a server answers a session over any program and finishes",
            .command => "a transcript's commands print what they printed and exit as they did",
            .deterministic => "one script answered twice gives the same bytes twice",
            .held_once => "a session case holds its program once",
            .importable => "the index offers nothing the program cannot import",
            .accepted_offers => "accepting what the server offers leaves a program that checks",
            .completion_offers => "a completion offers what the point can reach and nothing else",
            .completion_recovers => "a completion answers from whatever the parser recovered",
            .settled_refs => "one recorded inside an implementation names what that implementation settled, and one read through a bound names the bound that declares it",
            .float_round_trip => "a float constant reaches the backend as the float its literal spelled",
            .walk_consumes => "a consuming walk owes each element it hands over, and owes it once",
            .walk_lends => "a lending walk leaves what it walks live, and a consuming one takes it",
            .walk_named => "a walk that cannot abandon what it holds is refused at the walk",
            .walk_loops => "every walk answers as the loop it stands for",
            .range_exhaustive => "a range pattern's exhaustiveness is the type's own bounds",
            .help_edits => "a help's edit, applied, removes the error it was written for",
        };
    }
};

test "a property's population is the part of the corpus it applies to" {
    const one: InMemoryFile = .{ .path = "a.lin", .text = "" };

    // Two cases of one file, one module of three, and two transcripts. A
    // population that answered the same number for every property would be
    // measuring the corpus rather than what each property is asked about, and
    // would put the command cases under a bound six times their number.
    const cases = [_]Case{
        .{ .display_path = "a.lin", .stem = "a", .entry = "a.lin", .files = &.{one} },
        .{ .display_path = "b.lin", .stem = "b", .entry = "b.lin", .files = &.{one} },
        .{ .display_path = "m", .stem = "m", .entry = "m", .files = &.{ one, one, one } },
    };
    const paths = [_][]const u8{
        "a.lin",       "b.lin",       "m/main.lin",
        "cmd/one.cmd", "cmd/two.cmd", "lsp/one/session.jsonl",
    };

    const corpus: Corpus = .of(&cases, &paths);
    try testing.expectEqual(@as(u32, 5), Property.formatting.populationIn(corpus));
    try testing.expectEqual(@as(u32, 5), Property.normal_form.populationIn(corpus));
    try testing.expectEqual(@as(u32, 1), Property.file_order.populationIn(corpus));
    try testing.expectEqual(@as(u32, 2), Property.command.populationIn(corpus));

    // Both session properties are asked of every script and of nothing else:
    // one script is one chance at each, whatever it opens.
    try testing.expectEqual(@as(u32, 1), Property.deterministic.populationIn(corpus));
    try testing.expectEqual(@as(u32, 1), Property.held_once.populationIn(corpus));
}

test "the two corpus tallies account for the corpus exactly" {
    const one: InMemoryFile = .{ .path = "a.lin", .text = "" };
    const cases = [_]Case{
        .{ .display_path = "a.lin", .stem = "a", .entry = "a.lin", .files = &.{one} },
        .{ .display_path = "b.lin", .stem = "b", .entry = "b.lin", .files = &.{one} },
        .{ .display_path = "m", .stem = "m", .entry = "m", .files = &.{ one, one, one } },
    };
    const corpus: Corpus = .of(&cases, &.{});
    const q: Property = .formatting;

    // Every file checked, and every file split between the two counters: both
    // are the corpus accounted for, and a property that declines four fifths of
    // what it is offered is ordinary.
    try testing.expect(q.accountsFor(corpus, 5, 0));
    try testing.expect(q.accountsFor(corpus, 1, 4));

    // One more file checked than the corpus holds. This is the shape a
    // generated program makes when it reaches the corpus's counter, and it is
    // caught at the first one rather than after enough of them to cover what
    // the property declines.
    try testing.expect(!q.accountsFor(corpus, 6, 0));
    try testing.expect(!q.accountsFor(corpus, 1, 5));

    // A file the run neither checked nor passed over -- a counter that stopped
    // incrementing, or a walk that skipped a case. An upper bound reads this
    // as coverage to spare.
    try testing.expect(!q.accountsFor(corpus, 4, 0));
}

/// One chance the corpus gave a property, recorded on the side that describes
/// it: checked where the property applied, passed over where it did not.
///
/// Both sides through one call, so a chance cannot be recorded on neither --
/// which is the only way the two can stop accounting for the corpus without
/// the corpus itself having changed.
/// Property: every float literal the case spells reaches the backend as the
/// double it means. The literal's own text and the emitted `d_` spelling are
/// parsed by one routine and compared as bits, so a spelling that is merely
/// close -- rounded through too few digits -- fails here even where every
/// eval comparison happens to tolerate it.
///
/// Answers whether the case gave the property anything to read: a case with
/// no float literal is the caller's to pass over.
///
/// Only the case's own files. The tree carries the library beside them, and
/// a library literal reaches the backend only where something instantiates
/// the function holding it -- so a literal in an unused `std` body would
/// fail every case that imports the prelude and calls nothing over floats.
///
/// And only what an ordinary build emits. A `test fn` body is checked and left
/// out of the artefact, so a float literal inside one reaches no backend and
/// has no constant to be found -- the same reason as above, arrived at from the
/// other side. Without this the property reads a case declaring a test over
/// floats as a compiler that stopped emitting them.
fn checkFloatRoundTrip(
    gpa: std.mem.Allocator,
    failures: *std.ArrayList(Failure),
    display_path: []const u8,
    ast: *const Ast,
    table: *const FileTable,
    case: *const Case,
    ir_text: []const u8,
) !bool {
    // What a test declares, which an ordinary build does not emit.
    //
    // **Bound:** the declarations of one case, walked once, and the tests among
    // them held against each literal. A case declares a handful of each and
    // neither grows with the program being compiled.
    var untested: std.ArrayList(token.TokenRange) = .empty;
    defer untested.deinit(gpa);
    for (0..ast.declCount()) |d| {
        const id = node_mod.DeclId.at(@intCast(d));
        if (!ast.declIsTest(id)) continue;
        try untested.append(gpa, ast.declTokens(id));
    }

    var any = false;
    const tags = ast.tokens.items(.tag);
    for (ast.parts) |part| {
        const path = table.get(part.file).path;
        const own = for (case.files) |cf| {
            if (std.mem.eql(u8, cf.path, path)) break true;
        } else false;
        if (!own) continue;

        for (part.token_start..part.token_end) |i| {
            if (tags[i] != .float_literal) continue;
            if (spelledInATest(untested.items, i)) continue;
            const text = ast.tokenText(TokenId.at(@intCast(i)));
            // An unfinished literal's bytes parse to nothing; its case is
            // rejected and never reaches this property.
            // The property reads tokens, not types, so a literal is held to a
            // constant of either float width that rounds it once.
            const wide = std.fmt.parseFloat(f64, text) catch continue;
            const narrow = std.fmt.parseFloat(f32, text) catch continue;
            any = true;
            if (!irHoldsFloat(ir_text, @bitCast(wide), "f64") and !irHoldsFloat(ir_text, @as(u32, @bitCast(narrow)), "f32")) {
                try failures.append(gpa, .{
                    .path = display_path,
                    .what = "a float literal's constant reaches the backend changed",
                    .expected = try std.fmt.allocPrint(gpa, "an `f64` or `f32` constant holding the bits of `{s}`", .{text}),
                    .actual = "no emitted constant holds those bits",
                });
            }
        }
    }
    return any;
}

/// Whether a token sits inside one of the declarations a build leaves out.
fn spelledInATest(tests: []const token.TokenRange, at: usize) bool {
    for (tests) |r| {
        if (at >= r.start.index() and at < r.end.index()) return true;
    }
    return false;
}

/// Whether any constant of MLIR float type `float_type` in the emitted text
/// has exactly the bits `want_bits`.
fn irHoldsFloat(ir_text: []const u8, want_bits: u64, float_type: []const u8) bool {
    // A float constant is spelled as its bits in hex, typed by its width, so
    // the comparison is bit equality with no parsing of a rounded decimal.
    // Only lines defining a value are read: a string literal passes user bytes
    // into a `@linea_str` blob verbatim, so a spelling found anywhere else in
    // the text is a spelling a program can forge.
    var lines = std.mem.splitScalar(u8, ir_text, '\n');
    while (lines.next()) |line| {
        const op = std.mem.trimStart(u8, line, " ");
        if (!std.mem.startsWith(u8, op, "%")) continue;
        const at = std.mem.indexOf(u8, op, " = arith.constant 0x") orelse continue;
        const start = at + " = arith.constant 0x".len;
        var end = start;
        while (end < op.len and std.ascii.isHex(op[end])) end += 1;
        const typed = op[end..];
        if (!std.mem.startsWith(u8, typed, " : ") or !std.mem.startsWith(u8, typed[3..], float_type)) continue;
        const bits = std.fmt.parseInt(u64, op[start..end], 16) catch continue;
        if (bits == want_bits) return true;
    }
    return false;
}

/// Whether a node was written in the text a property is holding.
///
/// The tree is the program's, so it carries the library beside the case: a
/// construct written in `std/` is not one the case answers for, and its span
/// indexes another file's bytes. Asked of the source the token came from rather
/// than of a path, because that is the same question the offsets are about.
fn writtenIn(ast: *const Ast, id: ExprId, text: []const u8) bool {
    return ast.partOf(ast.exprTokens(id).start).source.ptr == text.ptr;
}

/// Compiles a program built to be wrong and holds the refusal to one rule.
///
/// The compiler is the oracle, and it is asked through the routine the
/// mutations ask through: a property with a checker of its own would be a
/// second reading of the same rule, and the two would drift.
fn mustRefuse(
    gpa: std.mem.Allocator,
    failures: *std.ArrayList(Failure),
    display_path: []const u8,
    rule: []const u8,
    what: []const u8,
    broken: []const u8,
    kind: ProgramKind,
) !void {
    const verdict = try mutate.verdictOf(gpa, broken, kind);
    if (verdict.rejected and mutate.cites(verdict.text, rule)) return;
    try failures.append(gpa, .{
        .path = display_path,
        .what = what,
        .expected = try std.fmt.allocPrint(gpa, "[{s}], and this program:\n{s}", .{ rule, broken }),
        .actual = if (verdict.rejected) verdict.text else "accepted",
    });
}

/// Compiles a program that must still be one, and says so where it is not.
fn mustCompile(
    gpa: std.mem.Allocator,
    failures: *std.ArrayList(Failure),
    display_path: []const u8,
    what: []const u8,
    made: []const u8,
    kind: ProgramKind,
) !void {
    const verdict = try mutate.verdictOf(gpa, made, kind);
    if (!verdict.rejected) return;
    try failures.append(gpa, .{
        .path = display_path,
        .what = what,
        .expected = try std.fmt.allocPrint(gpa, "a program, and this is one:\n{s}", .{made}),
        .actual = verdict.text,
    });
}

/// Property: a consuming walk owes every element it hands over, and owes it
/// once.
///
/// Two mutations of the case's own source, each answered by the compiler rather
/// than by a reading of the loop. The body emptied leaves the element with
/// nothing to take it, which is [O-Leak] and says the walk handed over
/// something owed. The binder taken at the top of the body leaves the body's
/// own use naming what is gone, which is [O-Move] and says it handed over one
/// value rather than one per reader.
///
/// Asked where the element is Linear and passed over everywhere else: a discardable
/// element owes nothing, so an empty body is an ordinary program and neither
/// mutation is evidence about anything.
///
/// Whether an element is owed is asked within the declaration whose body
/// holds the walk, as the ownership pass asks it: it builds one graph per
/// declaration body, and a closure's under the declaration it is written in,
/// so that declaration's bounds decide. A type parameter's item is
/// Discardable where they say so, and owed nowhere else. The pass keeps no
/// table of that owner once it finishes, so it is found here the way the pass
/// finds it: declaration bodies do not overlap, and the one holding the walk
/// is the body that begins last at or before it.
///
/// **Bound:** the expressions and declarations of one case, walked once each,
/// the case file's declaration bodies sorted once and searched once per walk,
/// and two compilations per walk with a Linear element. The corpus holds two
/// such walks.
fn checkWalkConsumes(
    gpa: std.mem.Allocator,
    failures: *std.ArrayList(Failure),
    display_path: []const u8,
    ast: *const Ast,
    typing: *const Typing,
    text: []const u8,
    kind: ProgramKind,
) !bool {
    const Body = struct { at: @import("support/span.zig").Span, decl: node_mod.DeclId };
    var bodies: std.ArrayList(Body) = .empty;
    defer bodies.deinit(gpa);
    for (0..ast.declCount()) |i| {
        const d = node_mod.DeclId.at(@intCast(i));
        const body = ast.declBody(d);
        if (body == ExprId.none or !writtenIn(ast, body, text)) continue;
        try bodies.append(gpa, .{ .at = ast.exprExtent(body), .decl = d });
    }
    std.mem.sort(Body, bodies.items, {}, struct {
        fn before(_: void, a: Body, b: Body) bool {
            return a.at.start < b.at.start;
        }
    }.before);

    var any = false;
    for (0..ast.exprCount()) |i| {
        const id = ExprId.at(@intCast(i));
        if (ast.exprTag(id) != .for_) continue;
        if (!writtenIn(ast, id, text)) continue;

        const f = ast.call(id);
        const element = typing.exprType(f.args[0]);
        if (element == .poison) continue;

        const at = ast.exprExtent(id);
        const after = std.sort.upperBound(Body, bodies.items, at.start, struct {
            fn order(key: u32, b: Body) std.math.Order {
                return std.math.order(key, b.at.start);
            }
        }.order);
        const owner: node_mod.DeclId = if (after > 0 and bodies.items[after - 1].at.end >= at.end)
            bodies.items[after - 1].decl
        else
            .none;
        if (!typing.mustConsumeWithin(owner, element)) continue;

        // By the extent rather than the span: a comment written after the
        // closing brace sits inside the body's range, and cutting there
        // deletes it from the text that follows.
        const body = ast.exprExtent(f.args[1]);
        if (body.end > text.len) continue;
        any = true;

        try mustRefuse(gpa, failures, display_path, "O-Leak", "a walk hands over an element that is owed", try std.mem.concat(gpa, u8, &.{
            text[0..body.start],
            "{}",
            text[body.end..],
        }), kind);

        // Inside the braces the body opens with, so every use the body makes
        // of the binder comes after it.
        try mustRefuse(gpa, failures, display_path, "O-Move", "a walk hands over one element per iteration", try std.mem.concat(gpa, u8, &.{
            text[0 .. body.start + 1],
            "\nlet _linea_taken = ",
            ast.exprExtent(f.args[0]).slice(text),
            "\n",
            text[body.start + 1 ..],
        }), kind);
    }
    return any;
}

/// Property: a lending walk leaves what it walks live, and a consuming walk
/// does not.
///
/// One pair of programs per walk, differing only in the first probe's lending
/// keyword. Each places two empty walks before the case's original walk. The
/// first copies its head and respells its binder; the second lends the same
/// value. The original body remains so every declaration it uses stays used.
/// Lending, that second walk is a program: the value was lent and not taken,
/// so it is still there to lend. Consuming, it is [O-Move], and the only thing
/// that could have taken the value is the first probe.
///
/// Both halves, because the first alone would pass under a compiler that had
/// stopped modelling the head at all -- a walk that took nothing and left
/// nothing would let every use after it stand.
///
/// The second half asks the head to be an array, and `also` says how many walks
/// it reached: a consuming walk over anything else asks for the `Sequence` a
/// lending walk never needed, and would be refused for the implementation it
/// cannot find rather than for the value the loop took.
///
/// **Bound:** the expressions and statements of one case, and two compilations
/// per lending walk over a named place.
fn checkWalkLends(
    gpa: std.mem.Allocator,
    failures: *std.ArrayList(Failure),
    display_path: []const u8,
    ast: *const Ast,
    typing: *const Typing,
    text: []const u8,
    also: *u32,
    kind: ProgramKind,
) !bool {
    var any = false;
    for (0..ast.stmtCount()) |i| {
        const s = node_mod.StmtId.at(@intCast(i));
        // The whole of a statement, so there is a place after it to write
        // another one. A walk bound to a name carries what its `break` sites
        // settled, and nothing follows it inside the initialiser.
        if (ast.stmtTag(s) != .expr_stmt) continue;
        const id = ast.stmtData(s).init;
        if (id == ExprId.none) continue;
        const lends = switch (ast.exprTag(id)) {
            .for_read, .for_inout => true,
            else => false,
        };
        if (!lends) continue;
        if (!writtenIn(ast, id, text)) continue;

        const f = ast.call(id);
        // A name, so the second walk reaches the same value rather than
        // building another one: what is being asked is whether *this* value is
        // still there, and a head that runs something answers a different
        // question every time it is written.
        if (ast.exprTag(f.callee) != .name_ref) continue;

        const at = ast.exprExtent(id);
        if (at.end > text.len) continue;
        const binder = ast.exprExtent(f.args[0]);
        const body = ast.exprExtent(f.args[1]);
        const head = ast.exprExtent(f.callee).slice(text);

        // The binder respelled, because a body that binds nothing leaves the
        // name unread and [N-Unused] would answer for the mutation instead of
        // the rule it is about. Keep the original walk after the probes so its
        // body's uses and control flow remain intact.
        const kept = try std.mem.concat(gpa, u8, &.{
            text[0..binder.start],
            "_linea_lent",
            text[binder.end..body.start],
            "{}",
            "\nfor read _linea_again in ",
            head,
            " {}\n",
            text[at.start..],
        });
        any = true;
        try mustCompile(gpa, failures, display_path, "a lending walk leaves what it walks live", kept, kind);

        if (typing.get(typing.exprType(f.callee)) != .array) continue;
        also.* += 1;

        // The same program with the lend struck out, which is the one edit
        // between them. The word after `for` is what says how the binder is
        // bound, and this walk has one because it is a lending walk.
        const form = ast.tokenSpan(TokenId.at(ast.exprTokens(id).start.index() + 1));
        try mustRefuse(gpa, failures, display_path, "O-Move", "a consuming walk takes what it walks", try std.mem.concat(gpa, u8, &.{
            kept[0..form.start],
            kept[form.end..],
        }), kind);
    }
    return any;
}

test "lending walk probes preserve names used only by the original body" {
    const walks = [_]struct { convention: []const u8, body: []const u8 }{
        .{ .convention = "read", .body = "total += value + bonus" },
        .{ .convention = "inout", .body = "value += bonus\ntotal += value" },
    };
    for (walks) |walk| {
        var arena = std.heap.ArenaAllocator.init(testing.allocator);
        defer arena.deinit();
        const gpa = arena.allocator();
        const text = try std.fmt.allocPrint(gpa,
            \\fn main() -> UInt8 {{
            \\    var values: [UInt8; 2] = [1, 2]
            \\    let bonus: UInt8 = 3
            \\    var total: UInt8 = 0
            \\    for {s} value in values {{ {s} }}
            \\    total
            \\}}
            \\
        , .{ walk.convention, walk.body });
        var table: FileTable = .empty;
        var sink = Sink.init(gpa);
        var interner: Interner = .empty;
        const files = [_]InMemoryFile{.{ .path = "main.lin", .text = text }};
        const program = try loadFromMemory(gpa, &table, &sink, &interner, "main.lin", &files, .program, true, .borrow);
        const settled = try checkProgram(gpa, testing.allocator, &program, &interner, &sink, .program);
        try testing.expect(!sink.hasErrors());
        var failures: std.ArrayList(Failure) = .empty;
        var consuming: u32 = 0;
        try testing.expect(try checkWalkLends(
            gpa,
            &failures,
            "main.lin",
            &settled.expanded.ast,
            &settled.typing,
            text,
            &consuming,
            .program,
        ));
        try testing.expectEqual(@as(u32, 1), consuming);
        for (failures.items) |failure| {
            std.debug.print("{s}: {s}\n", .{ failure.what, failure.actual });
        }
        try testing.expectEqual(@as(usize, 0), failures.items.len);
    }
}

/// Property: a walk that cannot abandon what it holds is refused at the walk.
///
/// [O-LinearWalk] and [O-LinearTail] are about a value no reader wrote: the
/// iterator a `Sequence` vends, or the positions a `trav` is bound to. So the
/// message has to point at something the reader did write, and what that is is
/// the walk's own head or the traversal's positions.
///
/// Held against the tree rather than against the checker's memory of where it
/// reported: the span is looked for among the heads and the positions the case
/// wrote, so a diagnostic anchored at the body, at the binder or at the hidden
/// binding fails here whatever the pass believed it was pointing at.
///
/// **Bound:** the diagnostics of one case, each held against the walks and
/// traversals of one case.
fn checkWalkNamed(
    gpa: std.mem.Allocator,
    failures: *std.ArrayList(Failure),
    display_path: []const u8,
    ast: *const Ast,
    sink: *const Sink,
) !bool {
    var any = false;
    for (sink.list.items) |d| {
        if (d.severity != .err) continue;
        const code = d.code orelse continue;
        switch (code) {
            .o_linear_walk, .o_linear_tail => {},
            else => continue,
        }
        const label = d.primaryLabel() orelse continue;
        any = true;

        var named = false;
        for (0..ast.exprCount()) |i| {
            const id = ExprId.at(@intCast(i));
            switch (ast.exprTag(id)) {
                .for_, .for_read, .for_inout => {},
                else => continue,
            }
            const head = ast.call(id).callee;
            if (ast.fileOfExpr(head) != label.file) continue;
            const span = ast.exprSpan(head);
            if (span.start == label.span.start and span.end == label.span.end) named = true;
        }
        for (0..ast.declCount()) |i| {
            const d2 = node_mod.DeclId.at(@intCast(i));
            if (ast.declTag(d2) != .traversal_) continue;
            const positions = ast.declInit(d2);
            if (positions == ExprId.none) continue;
            if (ast.fileOfExpr(positions) != label.file) continue;
            const span = ast.exprSpan(positions);
            if (span.start == label.span.start and span.end == label.span.end) named = true;
        }

        if (!named) {
            try failures.append(gpa, .{
                .path = display_path,
                .what = "a walk that cannot abandon what it holds is refused somewhere else",
                .expected = "the span of a walk's head or of a traversal's positions",
                .actual = try std.fmt.allocPrint(gpa, "[{s}] at {d}..{d}", .{
                    code.ruleName(),
                    label.span.start,
                    label.span.end,
                }),
            });
        }
    }
    return any;
}

fn tally(
    checked: *std.EnumMap(Property, u32),
    passed_over: *std.EnumMap(Property, u32),
    q: Property,
    applied: bool,
) void {
    const side = if (applied) checked else passed_over;
    side.put(q, (side.get(q) orelse 0) + 1);
}

const Failure = struct {
    path: []const u8,
    what: []const u8,
    expected: []const u8,
    actual: []const u8,
    // Discovery records precede the case's own checks.
    case_ordinal: usize = 0,
    case_order: usize = 0,
};

fn failureLess(_: void, a: Failure, b: Failure) bool {
    return switch (std.mem.order(u8, a.path, b.path)) {
        .lt => true,
        .gt => false,
        .eq => if (a.case_ordinal == b.case_ordinal)
            a.case_order < b.case_order
        else
            a.case_ordinal < b.case_ordinal,
    };
}

/// Measured compiler work for one sweep sample, including any fixed batch.
const Cost = struct {
    /// The cumulative resulting size of every successful backing allocation or
    /// growth, counted rather than read off the process. It is a proxy for
    /// allocation work under the sampling policy, not physical heap traffic.
    ///
    /// It is not peak or live bytes: shrink and free cost nothing, and growing
    /// a backing allocation charges its full resulting size. File-based costs
    /// use a separate accounting invocation with backing growth disabled:
    /// nested arenas otherwise choose capacities from allocator placement.
    took: usize,
    nanos: u64,
    /// CPU consumed during the same interval, excluding time descheduled.
    cpu_nanos: u64 = 0,
};

const CostTimer = struct {
    wall: std.Io.Timestamp,
    cpu: std.Io.Timestamp,

    fn start(io: std.Io) CostTimer {
        const cpu = std.Io.Timestamp.now(io, .cpu_process);
        return .{ .wall = std.Io.Timestamp.now(io, .awake), .cpu = cpu };
    }

    fn finish(self: CostTimer, io: std.Io, took: usize) Cost {
        const wall = std.Io.Timestamp.now(io, .awake);
        const cpu = std.Io.Timestamp.now(io, .cpu_process);
        return .{
            .took = took,
            .nanos = @intCast(self.wall.durationTo(wall).nanoseconds),
            .cpu_nanos = @intCast(self.cpu.durationTo(cpu).nanoseconds),
        };
    }
};

/// An allocator that sums successful backing allocation and growth sizes.
/// Ordinary timing forwards the backing allocator's policy. Separate accounting
/// can refuse growth so nested arenas choose their fallback capacities.
///
/// A growing resize or remap charges its full resulting size because failure
/// followed by allocate-copy-free is the same logical growth. Outcome-equivalent
/// growth must contribute the same cost; failed growth, shrink, and free add
/// nothing.
const Counting = struct {
    under: std.mem.Allocator,
    took: usize = 0,
    allow_growth: bool = true,

    fn allocator(self: *Counting) std.mem.Allocator {
        return .{ .ptr = self, .vtable = &.{
            .alloc = alloc,
            .resize = resize,
            .remap = remap,
            .free = free,
        } };
    }

    fn alloc(ctx: *anyopaque, n: usize, a: std.mem.Alignment, ra: usize) ?[*]u8 {
        const self: *Counting = @ptrCast(@alignCast(ctx));
        const got = self.under.rawAlloc(n, a, ra) orelse return null;
        self.took += n;
        return got;
    }

    fn resize(ctx: *anyopaque, buf: []u8, a: std.mem.Alignment, n: usize, ra: usize) bool {
        const self: *Counting = @ptrCast(@alignCast(ctx));
        if (!self.allow_growth and n > buf.len) return false;
        if (!self.under.rawResize(buf, a, n, ra)) return false;
        if (n > buf.len) self.took += n;
        return true;
    }

    fn remap(ctx: *anyopaque, buf: []u8, a: std.mem.Alignment, n: usize, ra: usize) ?[*]u8 {
        const self: *Counting = @ptrCast(@alignCast(ctx));
        if (!self.allow_growth and n > buf.len) return null;
        const got = self.under.rawRemap(buf, a, n, ra) orelse return null;
        if (n > buf.len) self.took += n;
        return got;
    }

    fn free(ctx: *anyopaque, buf: []u8, a: std.mem.Alignment, ra: usize) void {
        const self: *Counting = @ptrCast(@alignCast(ctx));
        self.under.rawFree(buf, a, ra);
    }
};

test "allocation growth costs the same after remap success or fallback" {
    var remap_storage: [64]u8 = undefined;
    var remap_backing = std.heap.FixedBufferAllocator.init(&remap_storage);
    var remap_counting: Counting = .{ .under = remap_backing.allocator() };
    var remapped: std.Io.Writer.Allocating = .init(remap_counting.allocator());
    defer remapped.deinit();
    try remapped.ensureTotalCapacityPrecise(8);
    try remapped.ensureTotalCapacityPrecise(16);

    var fallback_storage: [64]u8 = undefined;
    var fallback_backing = std.heap.FixedBufferAllocator.init(&fallback_storage);
    var fallback_counting: Counting = .{ .under = fallback_backing.allocator() };
    var allocated: std.Io.Writer.Allocating = .init(fallback_counting.allocator());
    defer allocated.deinit();
    try allocated.ensureTotalCapacityPrecise(8);
    _ = try fallback_backing.allocator().alloc(u8, 1);
    try allocated.ensureTotalCapacityPrecise(16);

    try testing.expectEqual(remap_counting.took, fallback_counting.took);
    try testing.expectEqual(@as(usize, 24), remap_counting.took);
}

test "nested arena allocation work is independent of backing growth" {
    const Scenario = struct {
        fn cost(block_growth: bool) !usize {
            var storage: [4096]u8 align(64) = undefined;
            var backing = std.heap.FixedBufferAllocator.init(&storage);
            var counting: Counting = .{ .under = backing.allocator(), .allow_growth = false };
            var arena = std.heap.ArenaAllocator.init(counting.allocator());
            defer arena.deinit();

            const first = try arena.allocator().alloc(u8, 128);
            @memset(first, 17);
            // A separate backing allocation prevents resizing the arena's
            // first node without changing the requests made through it.
            if (block_growth) _ = try backing.allocator().alloc(u8, 1);
            const second = try arena.allocator().alloc(u8, 128);
            @memset(second, 29);
            for (first) |byte| try testing.expectEqual(@as(u8, 17), byte);
            for (second) |byte| try testing.expectEqual(@as(u8, 29), byte);
            return counting.took;
        }
    };

    try testing.expectEqual(try Scenario.cost(false), try Scenario.cost(true));
}

/// A module of `n` functions, each calling the next, so none is unused.
///
/// Wide rather than deep: a table sized by the program while it is held per
/// function only shows itself where there are many functions, and that is the
/// shape this property exists to refuse.
fn wideModule(gpa: std.mem.Allocator, n: u32) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    const w = &out.writer;

    for (0..n) |i| {
        if (i + 1 < n) {
            try w.print(
                "fn f{d}(a: UInt8) -> UInt8 {{\n    let t: UInt8 = f{d}(a)\n    t + 1\n}}\n\n",
                .{ i, i + 1 },
            );
        } else {
            try w.print("fn f{d}(a: UInt8) -> UInt8 {{\n    a + 1\n}}\n\n", .{i});
        }
    }
    try w.print("fn main() -> UInt8 {{\n    let x: UInt8 = 3\n    f0(x)\n}}\n", .{});
    return out.toOwnedSlice();
}

/// `n` types implementing one trait: the shape a search over implementations
/// grows on.
fn implModule(gpa: std.mem.Allocator, n: u32) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    const w = &out.writer;

    try w.print("pub trait Tr {{\n    fn of(x: Self) -> UInt8\n}}\n\n", .{});
    for (0..n) |i| {
        try w.print("pub struct S{d} {{\n    a: UInt8,\n}}\n\n", .{i});
        try w.print(
            "impl Tr for S{d} {{\n    fn of(x: Self) -> UInt8 {{\n        x.a\n    }}\n}}\n\n",
            .{i},
        );
    }
    try w.print("fn main() -> UInt8 {{\n    0\n}}\n", .{});
    return out.toOwnedSlice();
}

/// One trait implemented for four callable shapes, and `n` functions of those
/// shapes each handed to a bound the trait answers.
///
/// A callable head is found through the chain its shape keys, so the lookup a
/// function costs is that shape's one implementation. Read through one chain
/// for every callable, each of the `n` lookups would walk every
/// implementation of the trait, and the shapes are what keep it from doing so.
fn callableHeadsModule(gpa: std.mem.Allocator, n: u32) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    const w = &out.writer;

    try w.print("pub trait Tr[S] {{\n    fn of(self: Self, inout state: S) -> UInt8\n}}\n\n", .{});
    try w.print("impl[S] Tr[S] for fn(inout state: S) -> UInt8 {{\n    fn of(self: Self, inout state: S) -> UInt8 {{\n        self(&state)\n    }}\n}}\n\n", .{});
    try w.print("impl[S] Tr[S] for fn(a: UInt8) -> UInt8 {{\n    fn of(self: Self, inout _state: S) -> UInt8 {{\n        self(1)\n    }}\n}}\n\n", .{});
    try w.print("impl[S] Tr[S] for fn(inout state: S, a: UInt8) -> UInt8 {{\n    fn of(self: Self, inout state: S) -> UInt8 {{\n        self(&state, 1)\n    }}\n}}\n\n", .{});
    try w.print("impl[S] Tr[S] for fn(a: UInt8, b: UInt8) -> UInt8 {{\n    fn of(self: Self, inout _state: S) -> UInt8 {{\n        self(1, 2)\n    }}\n}}\n\n", .{});
    try w.print("fn run[S, H: Tr[S]](inout state: S, handler: H) -> UInt8 {{\n    handler.of(&state)\n}}\n\n", .{});
    for (0..n) |i| {
        switch (i % 4) {
            0 => try w.print("fn f{d}(inout _state: ()) -> UInt8 {{\n    0\n}}\n\n", .{i}),
            1 => try w.print("fn f{d}(a: UInt8) -> UInt8 {{\n    a\n}}\n\n", .{i}),
            2 => try w.print("fn f{d}(inout _state: (), a: UInt8) -> UInt8 {{\n    a\n}}\n\n", .{i}),
            else => try w.print("fn f{d}(_a: UInt8, b: UInt8) -> UInt8 {{\n    b\n}}\n\n", .{i}),
        }
    }
    try w.print("fn main() -> UInt8 {{\n    var state = ()\n", .{});
    for (0..n) |i| try w.print("    let _r{d} = run(&state, f{d})\n", .{ i, i });
    try w.print("    0\n}}\n", .{});
    return out.toOwnedSlice();
}

/// `n` types, each declaring one operation of its own, and `n` functions each
/// making one postfix call to it.
///
/// A postfix call asks which traits the module can see declare its name, and
/// the type names a module can see grow with the program's types. Read as a
/// scan, every call costs every type, and a module of many types each called
/// once is where that meets itself. With `distinct` the operations are named
/// apart, so what a call costs is the lookup of its own name; sharing one
/// name instead costs whatever marks or gathers every member of that name.
fn postfixCallsModule(gpa: std.mem.Allocator, n: u32, names: enum { distinct, shared }) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    const w = &out.writer;

    for (0..n) |i| {
        try w.print("pub struct S{d} {{\n    a: UInt8,\n}}\n\n", .{i});
        switch (names) {
            .distinct => try w.print(
                "impl S{d} {{\n    pub fn get{d}(self: Self) -> UInt8 {{\n        self.a\n    }}\n}}\n\n" ++
                    "pub fn f{d}(s: S{d}) -> UInt8 {{\n    s.get{d}()\n}}\n\n",
                .{ i, i, i, i, i },
            ),
            .shared => try w.print(
                "impl S{d} {{\n    pub fn get(self: Self) -> UInt8 {{\n        self.a\n    }}\n}}\n\n" ++
                    "pub fn f{d}(s: S{d}) -> UInt8 {{\n    s.get()\n}}\n\n",
                .{ i, i, i },
            ),
        }
    }
    try w.print("fn main() -> UInt8 {{\n    let s: S0 = .{{ a = 1 }}\n    f0(s)\n}}\n", .{});
    return out.toOwnedSlice();
}

fn distinctPostfixCallsModule(gpa: std.mem.Allocator, n: u32) ![]u8 {
    return postfixCallsModule(gpa, n, .distinct);
}

fn sharedPostfixCallsModule(gpa: std.mem.Allocator, n: u32) ![]u8 {
    return postfixCallsModule(gpa, n, .shared);
}

/// `n` traits, `n` types and `n` functions each making one postfix call to a
/// name nothing declares, so every call is refused as a field the type lacks.
///
/// The report asks whether a trait the module cannot see declares the name,
/// which is a question about the program's traits: read as a walk, every
/// refused call costs every trait, and a module of many traits mid-edit is
/// where that meets itself. Read from the index by name, it costs the traits
/// declaring that name, which here is none.
fn failedPostfixCallsModule(gpa: std.mem.Allocator, n: u32) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    const w = &out.writer;

    for (0..n) |i| {
        try w.print("pub trait Tr{d} {{\n    fn of{d}(x: Self) -> UInt8\n}}\n\n", .{ i, i });
        try w.print("pub struct S{d} {{\n    a: UInt8,\n}}\n\n", .{i});
        try w.print("pub fn f{d}(s: S{d}) -> UInt8 {{\n    s.nothing{d}()\n}}\n\n", .{ i, i, i });
    }
    try w.print("fn main() -> UInt8 {{\n    let s: S0 = .{{ a = 1 }}\n    f0(s)\n}}\n", .{});
    return out.toOwnedSlice();
}

test "the failed postfix call sweep is refused once per call and for nothing else" {
    for ([_]u32{ 3, 6 }) |n| {
        const text = try failedPostfixCallsModule(testing.allocator, n);
        defer testing.allocator.free(text);
        _ = try treeCost(testing.allocator, testing.io, text, .{ .refused = .t_unknown_operation });
    }
}

/// Each function makes one call refused for its bound and one accepted, and
/// asks both results for an operation whose implementation demands the same
/// bound: the refused one's report is what the refusal already said, so the
/// module costs the refusal, its recorded demand, and the lookup that finds
/// the demand explains the missing implementation, once per function.
fn refusedBoundedCallsModule(gpa: std.mem.Allocator, n: u32) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    const w = &out.writer;

    try w.writeAll("pub trait Shout {\n    fn shout(_self: Self) -> UInt8\n}\n\n");
    try w.writeAll("pub struct Pair {\n    left: UInt8,\n}\n\n");
    try w.writeAll("pub struct Box[T] {\n    item: T,\n}\n\n");
    try w.writeAll("impl[T: Copyable] Shout for Box[T] {\n    fn shout(_self: Self) -> UInt8 {\n        1\n    }\n}\n\n");
    try w.writeAll("pub fn keep[T: Copyable](sink value: T) -> Box[T] where carries(value) {\n    .{ item = value }\n}\n\n");
    for (0..n) |i| {
        try w.print("pub fn f{d}() -> UInt8 {{\n    let p: Pair = .{{ left = 1 }}\n    keep(p).shout() + keep(UInt8(2)).shout()\n}}\n\n", .{i});
    }
    try w.writeAll("fn main() -> UInt8 {\n    f0()\n}\n");
    return out.toOwnedSlice();
}

test "the refused bounded call sweep is refused once per call and for nothing else" {
    for ([_]u32{ 3, 6 }) |n| {
        const text = try refusedBoundedCallsModule(testing.allocator, n);
        defer testing.allocator.free(text);
        _ = try treeCost(testing.allocator, testing.io, text, .{ .refused = .t_bound });
    }
}

/// Independent array wrappers exercise field settlement and projection lookup
/// without making any individual projection chain longer.
fn delegatedWrappersModule(gpa: std.mem.Allocator, n: u32) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    const w = &out.writer;
    for (0..n) |i| {
        try w.print("pub struct Board{d} {{ values: [UInt8; 2] }}\n", .{i});
        try w.print("impl Index[UInt64] for Board{d} via values\n", .{i});
        try w.print("pub fn score{d}(inout board: Board{d}, i: UInt64) -> UInt8 {{ board[i] += 1; board[i] }}\n", .{ i, i });
    }
    try w.writeAll("fn main() -> UInt8 { 0 }\n");
    return out.toOwnedSlice();
}

test "delegated wrapper sweep checks independent indexed reads and writes" {
    for ([_]u32{ 8, 16 }) |n| {
        const source = try delegatedWrappersModule(testing.allocator, n);
        defer testing.allocator.free(source);
        const files = [_]loader.InMemoryFile{
            .{ .path = "p/linea.json", .text = "{}\n" },
            .{ .path = "p/main.lin", .text = source },
        };
        _ = try costOfFiles(testing.allocator, testing.io, "p/main.lin", &files, .accounting);
    }
}

/// Every payload field carries a callable signature checked during MIR verification.
fn callableEnumModule(gpa: std.mem.Allocator, n: u32) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    const w = &out.writer;
    try w.writeAll("enum Callbacks { Held(");
    for (0..n) |i| {
        if (i != 0) try w.writeAll(", ");
        try w.writeAll("fn(read value: UInt8) -> UInt8");
    }
    try w.writeAll(") }\nfn increment(value: UInt8) -> UInt8 { value + 1 }\nfn main() -> UInt8 {\n    let callbacks: Callbacks = .Held(");
    for (0..n) |i| {
        if (i != 0) try w.writeAll(", ");
        try w.writeAll("increment");
    }
    try w.writeAll(")\n    let _ = callbacks\n    0\n}\n");
    return out.toOwnedSlice();
}

/// One `match` with n arms, each naming a key and a variant inside a struct
/// pattern, then `_`. A row naming a constructor joins that constructor's
/// branch alone, so coverage copies each arm once and grows with n.
fn matchArmsModule(gpa: std.mem.Allocator, n: u32) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    const w = &out.writer;
    try w.writeAll("enum Choice { Yes(UInt8), No }\nstruct Row { key: UInt64, choice: Choice }\nfn pick(sink row: Row) -> UInt64 {\n    match row {\n");
    for (0..n) |i| try w.print("        Row {{ key: {d}, choice: No }} => {d},\n", .{ i, i });
    try w.writeAll("        _ => 0,\n    }\n}\nfn main() -> UInt8 {\n    UInt8(pick(Row { key = 1, choice = .No }))\n}\n");
    return out.toOwnedSlice();
}

/// One `match` over a pair of n-variant enums with an arm per variant naming
/// it in both columns: the first column splits into n branches, and the
/// second column is split again inside each of them.
fn twoWideColumnsModule(gpa: std.mem.Allocator, n: u32) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    const w = &out.writer;
    try w.writeAll("enum Wide {\n");
    for (0..n) |i| try w.print("    V{d},\n", .{i});
    try w.writeAll("}\nstruct Pair { a: Wide, b: Wide }\nfn same(sink pair: Pair) -> UInt8 {\n    match pair {\n");
    for (0..n) |i| try w.print("        Pair {{ a: V{d}, b: V{d} }} => 1,\n", .{ i, i });
    try w.writeAll("        _ => 0,\n    }\n}\nfn main() -> UInt8 {\n    same(Pair { a = .V0, b = .V1 })\n}\n");
    return out.toOwnedSlice();
}

/// One `match` of n arms, each binding a name: the arms' paths meet at the
/// join after the `match`, each holding a binding the others never had.
fn bindingArmsModule(gpa: std.mem.Allocator, n: u32) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    const w = &out.writer;
    try w.writeAll("enum Found { Pair(UInt64, UInt8), Missing }\nfn pick(sink found: Found) -> UInt8 {\n    match found {\n");
    for (0..n) |i| try w.print("        Pair({d}, value) => value,\n", .{i});
    try w.writeAll("        _ => 0,\n    }\n}\nfn main() -> UInt8 {\n    pick(.Missing)\n}\n");
    return out.toOwnedSlice();
}

/// One enum of n variants, each carrying a number, and one `match` taking
/// every variant's number in an arm of its own: the enum's width meets
/// coverage, the arms' tag tests and every payload read the verifier places.
fn wideEnumModule(gpa: std.mem.Allocator, n: u32) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    const w = &out.writer;
    try w.writeAll("enum Wide {\n");
    for (0..n) |i| try w.print("    V{d}(UInt8),\n", .{i});
    try w.writeAll("}\nfn number(sink w: Wide) -> UInt8 {\n    match w {\n");
    for (0..n) |i| try w.print("        V{d}(value) => value,\n", .{i});
    try w.writeAll("    }\n}\nfn main() -> UInt8 {\n    number(.V0(0))\n}\n");
    return out.toOwnedSlice();
}

/// A pattern n variants deep, over n enums each carrying the one before it,
/// so resolving, checking, coverage and ownership each walk a pattern of
/// depth n. Checked rather than emitted: every tag test reads at an offset
/// into the outermost value, and the MIR verifier finds which part an access
/// lands on by descending the type from there, which is the type's depth per
/// access whatever wrote it.
fn patternDepthModule(gpa: std.mem.Allocator, n: u32) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    const w = &out.writer;
    try w.writeAll("enum Level0 { Held(UInt8), Empty }\n");
    for (1..n + 1) |i| try w.print("enum Level{d} {{ Held(Level{d}), Empty }}\n", .{ i, i - 1 });
    try w.print("fn open(sink value: Level{d}) -> UInt8 {{\n    match value {{\n        ", .{n});
    for (0..n + 1) |_| try w.writeAll("Held(");
    try w.writeAll("inner");
    for (0..n + 1) |_| try w.writeAll(")");
    try w.writeAll(" => inner,\n        _ => 0,\n    }\n}\nfn main() -> UInt8 {\n    open(.Empty)\n}\n");
    return out.toOwnedSlice();
}

/// n generic function values named without a type in one body, each settled
/// by a call through it, so the body's open values and open types grow with n.
fn openFunctionValuesModule(gpa: std.mem.Allocator, n: u32) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    const w = &out.writer;
    try w.writeAll("fn identity[T: Copyable](value: T) -> T {\n    copy(value)\n}\nfn main() -> UInt8 {\n    var total: UInt8 = 0\n");
    for (0..n) |i| try w.print("    let same{d} = identity\n    total = same{d}(total)\n", .{ i, i });
    try w.writeAll("    total\n}\n");
    return out.toOwnedSlice();
}

/// n functions, each naming a generic function without a type and settling it
/// by a call, so a table a body holds that were sized by the program would
/// grow with n squared.
fn functionValueBodiesModule(gpa: std.mem.Allocator, n: u32) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    const w = &out.writer;
    try w.writeAll("fn identity[T: Copyable](value: T) -> T {\n    copy(value)\n}\n");
    for (0..n) |i| try w.print("fn step{d}(value: UInt8) -> UInt8 {{\n    let same = identity\n    same(value)\n}}\n", .{i});
    try w.writeAll("fn main() -> UInt8 {\n    var total: UInt8 = 0\n");
    for (0..n) |i| try w.print("    total = step{d}(total)\n", .{i});
    try w.writeAll("    total\n}\n");
    return out.toOwnedSlice();
}

/// One n-field payload and n constructor conversions with constant-size
/// contracts. Only one field carries dependencies, so coverage must count the
/// payload's children once rather than scanning all fields per conversion.
fn constructorPayloadFieldsModule(gpa: std.mem.Allocator, n: u32) ![]u8 {
    std.debug.assert(n > 0);
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    const w = &out.writer;
    try w.writeAll("struct Payload {\n    observation: borrow UInt64,\n");
    for (1..n) |i| try w.print("    field{d}: UInt8,\n", .{i});
    try w.writeAll("}\nenum Wrapped { Value(Payload) }\nfn main() -> UInt8 {\n");
    for (0..n) |i| try w.print(
        "    let _make{d}: fn(sink payload: Payload) -> Wrapped where carries(.Value.observation: payload) = Wrapped.Value\n",
        .{i},
    );
    try w.writeAll("    0\n}\n");
    return out.toOwnedSlice();
}

/// Distinct record defaults share one leaf and array, with aliases and reordered
/// fields requiring the same callable identity. Each runtime value has fixed
/// size, so emitted constants and generic instantiations grow with `n`.
fn aggregateConstantsModule(gpa: std.mem.Allocator, n: u32) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    const w = &out.writer;
    try w.writeAll(
        "@copyable\nstruct Leaf { amount: UInt64, enabled: Bool }\n" ++
            "@copyable\nstruct Config { tag: UInt64, children: [Leaf; 2] }\n" ++
            "let shared: Leaf = .{ amount = 7, enabled = true }\n" ++
            "let shared_alias = shared\n",
    );
    for (0..n) |i| {
        try w.print(
            "let value{d}: Config = .{{ tag = {d}, children = [shared, shared_alias] }}\n" ++
                "let alias{d} = value{d}\n" ++
                "fn read{d}(options: Config = alias{d}) -> UInt64 {{\n" ++
                "    if options.children[0].enabled {{ options.tag + options.children[1].amount }} else {{ 0 }}\n" ++
                "}}\n" ++
                "fn invoke{d}[F: fn(read options: Config = .{{ children = [shared_alias, shared], tag = {d} }}) -> UInt64](callback: F) -> UInt64 {{\n" ++
                "    callback()\n" ++
                "}}\n",
            .{ i, i, i, i, i, i, i, i },
        );
    }
    try w.writeAll("fn main() -> UInt8 {\n");
    for (0..n) |i| {
        try w.print(
            "    if invoke{d}(read{d}) != {d} || read{d}(options: value{d}) != {d} {{ return 1 }}\n",
            .{ i, i, i + 7, i, i, i + 7 },
        );
    }
    try w.writeAll("    0\n}\n");
    return out.toOwnedSlice();
}

/// One growing Record-to-Leaf edge crosses n generic helpers. Trait selection
/// at the final helper must not invent an edge back to the Record factory.
fn genericHelperDepthModule(gpa: std.mem.Allocator, n: u32) ![]u8 {
    return genericHelperModule(gpa, n, false);
}

/// Unrelated suppliers share a trait, while the reachable helper has an exact
/// receiver. Increasing the supplier count must not expand that call's body set.
fn genericHelperSuppliersModule(gpa: std.mem.Allocator, n: u32) ![]u8 {
    return genericHelperModule(gpa, n, true);
}

fn genericHelperModule(gpa: std.mem.Allocator, n: u32, suppliers: bool) ![]u8 {
    std.debug.assert(n > 0);
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    const w = &out.writer;
    try w.writeAll(
        "trait Make[A: Copyable] { fn make(input: A) -> Self where carries(input) }\n" ++
            "struct Leaf[A: Copyable] { value: A }\n" ++
            "impl[A: Copyable] Make[A] for Leaf[A] { fn make(input: A) -> Self where carries(input) { .{ value = copy(input) } } }\n",
    );
    if (suppliers) for (0..n) |i| {
        try w.print("struct Other{d}[A: Copyable] {{ value: A }}\n", .{i});
        try w.print("impl[A: Copyable] Make[A] for Other{d}[A] {{ fn make(input: A) -> Self where carries(input) {{ .{{ value = copy(input) }} }} }}\n", .{i});
    };
    const helpers = if (suppliers) 1 else n;
    for (0..helpers) |i| {
        try w.print("fn build{d}[A: Copyable, T: Make[A]](input: A) -> T where carries(input) {{ ", .{i});
        if (i + 1 == helpers) try w.writeAll("Make.make(input)") else try w.print("build{d}(input)", .{i + 1});
        try w.writeAll(" }\n");
    }
    try w.writeAll(
        "struct Record[A: Copyable] { child: Leaf[A] }\n" ++
            "impl[A: Copyable] Make[A] for Record[A] { fn make(input: A) -> Self where carries(input) { let child: Leaf[A] = build0(input); return .{ child } } }\n" ++
            "fn main() -> UInt8 { let record: Record[UInt8] = Make.make(UInt8(7)); if record.child.value == 7 { 0 } else { 1 } }\n",
    );
    return out.toOwnedSlice();
}

/// A single helper carries n independent type parameters into a Leaf factory.
/// This varies frame width while the reachable declaration count stays fixed.
fn genericHelperWidthModule(gpa: std.mem.Allocator, n: u32) ![]u8 {
    std.debug.assert(n > 0);
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    const w = &out.writer;
    var binders: std.Io.Writer.Allocating = .init(gpa);
    defer binders.deinit();
    var arguments: std.Io.Writer.Allocating = .init(gpa);
    defer arguments.deinit();
    var parameters: std.Io.Writer.Allocating = .init(gpa);
    defer parameters.deinit();
    var inputs: std.Io.Writer.Allocating = .init(gpa);
    defer inputs.deinit();
    for (0..n) |i| {
        if (i != 0) {
            try binders.writer.writeAll(", ");
            try arguments.writer.writeAll(", ");
            try parameters.writer.writeAll(", ");
            try inputs.writer.writeAll(", ");
        }
        try binders.writer.print("A{d}: Copyable", .{i});
        try arguments.writer.print("A{d}", .{i});
        try parameters.writer.print("input{d}: A{d}", .{ i, i });
        try inputs.writer.print("input{d}", .{i});
    }
    const bs = binders.written();
    const as = arguments.written();
    const ps = parameters.written();
    const ins = inputs.written();
    try w.print("trait Make[{s}] {{ fn make({s}) -> Self where carries({s}) }}\nstruct Leaf[{s}] {{\n", .{ bs, ps, ins, bs });
    for (0..n) |i| try w.print("value{d}: A{d},\n", .{ i, i });
    try w.print("}}\nimpl[{s}] Make[{s}] for Leaf[{s}] {{ fn make({s}) -> Self where carries({s}) {{ .{{ ", .{ bs, as, as, ps, ins });
    for (0..n) |i| {
        if (i != 0) try w.writeAll(", ");
        try w.print("value{d} = copy(input{d})", .{ i, i });
    }
    try w.print(" }} }} }}\nfn build[{s}, T: Make[{s}]]({s}) -> T where carries({s}) {{ Make.make({s}) }}\n", .{ bs, as, ps, ins, ins });
    try w.print("struct Record[{s}] {{ child: Leaf[{s}] }}\nimpl[{s}] Make[{s}] for Record[{s}] {{ fn make({s}) -> Self where carries({s}) {{ let child: Leaf[{s}] = build({s}); return .{{ child }} }} }}\n", .{ bs, as, bs, as, as, ps, ins, as, ins });
    try w.writeAll("fn main() -> UInt8 { let record: Record[");
    for (0..n) |i| {
        if (i != 0) try w.writeAll(", ");
        try w.writeAll("UInt8");
    }
    try w.writeAll("] = Make.make(");
    for (0..n) |i| {
        if (i != 0) try w.writeAll(", ");
        try w.writeAll("UInt8(7)");
    }
    try w.writeAll("); if record.child.value0 == 7 { 0 } else { 1 } }\n");
    return out.toOwnedSlice();
}

/// A trait-only binder lies beneath n injective key constructors.
fn genericOriginDepthModule(gpa: std.mem.Allocator, n: u32) ![]u8 {
    std.debug.assert(n > 0);
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    const w = &out.writer;
    var key: std.Io.Writer.Allocating = .init(gpa);
    defer key.deinit();
    for (0..n) |_| try key.writer.writeAll("Layer[");
    try key.writer.writeAll("A");
    for (0..n) |_| try key.writer.writeAll("]");
    try w.writeAll(
        "@copyable\nstruct Layer[A: Copyable] { value: A }\n" ++
            "trait Make[A: Copyable] { fn make(input: A) -> Self where carries(input) }\n" ++
            "struct Leaf {}\n",
    );
    try w.print("impl[A: Copyable] Make[{s}] for Leaf {{ fn make(_input: {s}) -> Self where carries(_input) {{ .{{}} }} }}\n", .{ key.written(), key.written() });
    try w.writeAll(
        "fn build[A: Copyable, T: Make[A]](input: A) -> T where carries(input) { Make.make(input) }\n" ++
            "struct Record[A: Copyable] { value: A }\n" ++
            "impl[A: Copyable] Make[A] for Record[A] { fn make(input: A) -> Self where carries(input) {\n",
    );
    try w.print("let wrapped: {s} = ", .{key.written()});
    for (0..n) |_| try w.writeAll(".{ value = ");
    try w.writeAll("copy(input)");
    for (0..n) |_| try w.writeAll(" }");
    try w.writeAll(
        "\nlet _leaf: Leaf = build(wrapped)\n.{ value = copy(input) }\n} }\n" ++
            "fn main() -> UInt8 { let record: Record[UInt8] = Make.make(UInt8(7)); record.value - 7 }\n",
    );
    return out.toOwnedSlice();
}

/// Repeated Pair[T,T] transfers share type DAG children across n helpers.
fn genericSharedDagModule(gpa: std.mem.Allocator, n: u32) ![]u8 {
    return genericSharedDagProgram(gpa, n, false);
}

/// A possible trait supplier closes the call graph, while the known Pair
/// receiver selects a terminating supplier during recurrence checks.
fn genericTraitSelectedSharedDagModule(gpa: std.mem.Allocator, n: u32) ![]u8 {
    return genericSharedDagProgram(gpa, n, true);
}

fn genericSharedDagProgram(gpa: std.mem.Allocator, n: u32, weighted: bool) ![]u8 {
    std.debug.assert(n > 0);
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    const w = &out.writer;
    try w.writeAll("@copyable\nstruct Pair[phantom A, phantom B] {}\n");
    if (weighted) try w.writeAll(
        "trait Finish { fn finish(self: Self) -> UInt8 }\n" ++
            "impl[A, B] Finish for Pair[A, B] { fn finish(_self: Self) -> UInt8 { 0 } }\n" ++
            "struct Again[T] { value: T }\n" ++
            "impl[T] Finish for Again[T] { fn finish(self: Self) -> UInt8 { step0(self.value) } }\n",
    );
    for (0..n) |i| {
        try w.print("fn step{d}[T](_input: T) -> UInt8 {{ let next: Pair[T, T] = .{{}}; ", .{i});
        if (i + 1 == n) {
            try w.writeAll(if (weighted) "Finish.finish(next)" else "let _done = next; 0");
        } else try w.print("step{d}(next)", .{i + 1});
        try w.writeAll(" }\n");
    }
    try w.writeAll("fn main() -> UInt8 { step0(UInt8(7)) }\n");
    return out.toOwnedSlice();
}

/// One growing edge closes a cycle through n distinct receiver families.
fn genericPositiveCycleModule(gpa: std.mem.Allocator, n: u32) ![]u8 {
    std.debug.assert(n > 0);
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    const w = &out.writer;
    try w.writeAll(
        "trait Run { fn run(self: Self) -> UInt8 }\n" ++
            "@copyable\nstruct Wrap[T: Copyable] { value: T }\n",
    );
    for (0..n) |i| try w.print("@copyable\nstruct Node{d}[T: Copyable] {{ value: T }}\n", .{i});
    for (0..n) |i| {
        try w.print("impl[T: Copyable] Run for Node{d}[T] {{ fn run(self: Self) -> UInt8 {{ ", .{i});
        if (i + 1 == n) {
            try w.writeAll("let next: Node0[Wrap[T]] = .{ value = .{ value = copy(self.value) } }; ");
        } else try w.print("let next: Node{d}[T] = .{{ value = copy(self.value) }}; ", .{i + 1});
        try w.writeAll("Run.run(next) } }\n");
    }
    try w.writeAll("fn main() -> UInt8 { let first: Node0[UInt8] = .{ value = 7 }; Run.run(first) }\n");
    return out.toOwnedSlice();
}

test "generic graph sweeps check shared DAGs and reject positive cycles" {
    for ([_]u32{ 3, 6 }) |n| {
        const shared = try genericSharedDagModule(testing.allocator, n);
        defer testing.allocator.free(shared);
        _ = try treeCost(testing.allocator, testing.io, shared, .check);
        const growing = try genericPositiveCycleModule(testing.allocator, n);
        defer testing.allocator.free(growing);
        _ = try treeCost(testing.allocator, testing.io, growing, .{ .refused = .t_poly_rec });
    }
}

test "generic trait-selected shared DAG sweep selects its terminating supplier" {
    for ([_]u32{ 3, 6 }) |n| {
        const shared = try genericTraitSelectedSharedDagModule(testing.allocator, n);
        defer testing.allocator.free(shared);
        _ = try treeCost(testing.allocator, testing.io, shared, .check);
    }
}

test "generic helper sweeps preserve finite trait factory composition" {
    inline for (.{ genericHelperDepthModule, genericHelperWidthModule, genericHelperSuppliersModule, genericOriginDepthModule }) |make| {
        for ([_]u32{ 3, 6 }) |n| {
            const source = try make(testing.allocator, n);
            defer testing.allocator.free(source);
            _ = try costOf(testing.allocator, testing.io, source);
        }
    }
}

/// One lookup table precedes all its leaves, so dependency scheduling must
/// resume after each completed leaf instead of rescanning the table prefix.
/// Constants each borrowed through a field and an element, and the borrows
/// returned from functions that take nothing, so every constant is laid out
/// as a static and every borrow is rooted at one.
fn borrowedConstantsModule(gpa: std.mem.Allocator, n: u32) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    const w = &out.writer;
    try w.writeAll(
        "struct Reading { value: borrow UInt64 }\n" ++
            "fn reading(value: UInt64) -> Reading where borrows(.value: value) { .{ value = borrow value } }\n" ++
            "@copyable\nstruct Config { limit: UInt64, sizes: [UInt64; 2] }\n",
    );
    for (0..n) |i| {
        try w.print(
            "let config{d}: Config = .{{ limit = {d}, sizes = [{d}, 1] }}\n" ++
                "fn limit{d}() -> Reading where carries() {{ reading(config{d}.limit) }}\n" ++
                "fn size{d}() -> borrow UInt64 where carries() {{ borrow config{d}.sizes[0] }}\n",
            .{ i, i, i, i, i, i, i },
        );
    }
    try w.writeAll("fn main() -> UInt8 {\n");
    for (0..n) |i| {
        try w.print("    if *limit{d}().value != {d} || *size{d}() != {d} {{ return 1 }}\n", .{ i, i, i, i });
    }
    try w.writeAll("    0\n}\n");
    return out.toOwnedSlice();
}

test "borrowed constant sweep returns borrows of constants" {
    for ([_]u32{ 3, 6 }) |n| {
        const source = try borrowedConstantsModule(testing.allocator, n);
        defer testing.allocator.free(source);
        _ = try costOf(testing.allocator, testing.io, source);
    }
}

fn forwardAggregateTableModule(gpa: std.mem.Allocator, n: u32) ![]u8 {
    std.debug.assert(n > 0);
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    const w = &out.writer;
    try w.print("let table: [UInt64; {d}] = [", .{n});
    for (0..n) |i| {
        if (i != 0) try w.writeAll(", ");
        try w.print("item{d}", .{i});
    }
    try w.writeAll("]\n");
    for (0..n) |i| try w.print("let item{d}: UInt64 = {d}\n", .{ i, i });
    try w.print("fn main() -> UInt8 {{ if table[0] == 0 && table[{d}] == {d} {{ 0 }} else {{ 1 }} }}\n", .{ n - 1, n - 1 });
    return out.toOwnedSlice();
}

test "aggregate constant sweep checks a forward lookup table" {
    for ([_]u32{ 3, 6 }) |n| {
        const source = try forwardAggregateTableModule(testing.allocator, n);
        defer testing.allocator.free(source);
        _ = try costOf(testing.allocator, testing.io, source);
    }
}

test "aggregate constant sweep checks shared defaults and callable identity" {
    for ([_]u32{ 3, 6 }) |n| {
        const source = try aggregateConstantsModule(testing.allocator, n);
        defer testing.allocator.free(source);
        _ = try costOf(testing.allocator, testing.io, source);
    }
}

test "constructor payload field sweep retains sparse contracts across conversions" {
    for ([_]u32{ 8, 16 }) |n| {
        var arena = std.heap.ArenaAllocator.init(testing.allocator);
        defer arena.deinit();
        const gpa = arena.allocator();
        const text = try constructorPayloadFieldsModule(gpa, n);
        const source: Source = .{ .path = "constructor-payload-fields.lin", .text = text };
        var sink = Sink.init(gpa);
        var interner: Interner = .empty;
        const tokens = try tokenize(gpa, &source, .from(0), &sink, &interner);
        var ast = try parse(gpa, &source, .from(0), tokens, &sink);
        var resolved = try resolveTree(gpa, &ast, &sink);
        const typing = try typecheckTree(gpa, &resolved, &sink);
        try testing.expectEqual(@as(u32, 0), sink.error_count);
        try testing.expectEqual(@as(usize, n), typing.function_values.len);
        for (typing.function_values) |value| {
            try testing.expect(value.target == .constructor);
            const signature = typing.get(value.signature).callable;
            try testing.expectEqual(n, typing.fieldCount(typing.callableParams(signature)[0].ty));
            try testing.expectEqual(@as(usize, 1), signature.contracts.len);
            try testing.expectEqual(@as(usize, 2), signature.contracts[0].target.len);
        }
        _ = try costOf(gpa, testing.io, text);
    }
}

/// `n` traits, each declaring one signature: the shape a walk for "which
/// signatures does this trait declare" grows on.
fn traitModule(gpa: std.mem.Allocator, n: u32) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    const w = &out.writer;

    for (0..n) |i| {
        try w.print("pub trait Tr{d} {{\n    fn of{d}(x: Self) -> UInt8\n}}\n\n", .{ i, i });
    }
    try w.print("fn main() -> UInt8 {{\n    0\n}}\n", .{});
    return out.toOwnedSlice();
}

/// One type with `n` members, each called once: the shape a search over
/// members grows on.
fn memberModule(gpa: std.mem.Allocator, n: u32) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    const w = &out.writer;

    try w.print("pub struct T {{\n    a: UInt8,\n}}\n\nimpl T {{\n", .{});
    for (0..n) |i| {
        try w.print("    pub fn m{d}(s: Self) -> UInt8 {{\n        s.a\n    }}\n", .{i});
    }
    try w.print("}}\n\nfn main() -> UInt8 {{\n    let t: T = .{{ a = 1 }}\n", .{});
    for (0..n) |i| try w.print("    let _ = T.m{d}(t)\n", .{i});
    try w.print("    let _ = t\n    0\n}}\n", .{});
    return out.toOwnedSlice();
}

/// Distinct bound shapes with a shared first bound and a selective second one.
/// Every witness also has an implementation of the shared trait, so selecting
/// candidates must retain rows for other traits under the same receiver head.
fn distinctBoundShapesModule(gpa: std.mem.Allocator, n: u32) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    const w = &out.writer;
    try w.writeAll("trait Common {}\n");
    for (0..n) |i| {
        try w.print("trait M{d} {{ fn of(self: Self) -> UInt8 }}\n", .{i});
        try w.print("struct S{d} {{ value: UInt8, }}\n", .{i});
        try w.print("impl Common for S{d} {{}}\n", .{i});
        try w.print("impl M{d} for S{d} {{ fn of(self: Self) -> UInt8 {{ self.value }} }}\n", .{ i, i });
        try w.print("fn g{d}[T: Common + M{d}](value: T) -> UInt8 {{ M{d}.of(value) }}\n", .{ i, i, i });
    }
    try w.writeAll("fn main() -> UInt8 {\n");
    for (0..n) |i| {
        try w.print("    let value{d}: S{d} = .{{ value = 7 }}\n    let _ = g{d}(value{d})\n", .{ i, i, i, i });
    }
    try w.writeAll("    7\n}\n");
    return out.toOwnedSlice();
}

/// One parameter bounded at `n` distinct arguments of one trait, and a name
/// written after it that exactly one other bound declares: reading that name
/// pairs every bound with the ones before it.
fn boundsOnOneParameterModule(gpa: std.mem.Allocator, n: u32) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    const w = &out.writer;
    try w.writeAll("trait Tail { type Elem }\n");
    try w.writeAll("trait Lookup[I] { fn at(self: Self, i: I) -> UInt8 where carries(self, i) }\n");
    try w.writeAll("fn _pass[C: Tail");
    for (0..n) |i| try w.print(" + Lookup[[UInt8; {d}]]", .{i + 1});
    try w.writeAll("](sink value: C.Elem) -> C.Elem {\n    value\n}\n");
    try w.writeAll("fn main() -> UInt8 {\n    0\n}\n");
    return out.toOwnedSlice();
}

/// Aliases nested `n` deep, each naming the one below it twice, so the type
/// the last stands for is a tree of 2^n leaves written in n lines. Two equal
/// implementations of one trait for it are one duplicate.
fn nestedAliasImplementationsModule(gpa: std.mem.Allocator, n: u32) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    const w = &out.writer;
    try w.writeAll("@copyable\nstruct Pair[phantom A, phantom B] {}\nalias A0 = Pair[UInt8, UInt8]\n");
    for (1..n + 1) |i| try w.print("alias A{d} = Pair[A{d}, A{d}]\n", .{ i, i - 1, i - 1 });
    try w.writeAll("trait Give[T] { fn give(_self: Self, _x: T) -> UInt8 }\nstruct Holder { value: UInt8 }\n");
    for (0..2) |_| try w.print("impl Give[A{d}] for Holder {{ fn give(_self: Self, _x: A{d}) -> UInt8 {{ 0 }} }}\n", .{ n, n });
    try w.writeAll("fn main() -> UInt8 {\n    0\n}\n");
    return out.toOwnedSlice();
}

/// The same aliases read by bounds: two equal bounds on one parameter are one
/// bound, and the associated type is read through it.
fn nestedAliasBoundsModule(gpa: std.mem.Allocator, n: u32) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    const w = &out.writer;
    try w.writeAll("@copyable\nstruct Pair[phantom A, phantom B] {}\nalias A0 = Pair[UInt8, UInt8]\n");
    for (1..n + 1) |i| try w.print("alias A{d} = Pair[A{d}, A{d}]\n", .{ i, i - 1, i - 1 });
    try w.writeAll("trait Tail { type Elem }\ntrait Lookup[I] { fn at(self: Self, i: I) -> UInt8 where carries(self, i) }\n");
    try w.print("fn _pass[C: Tail + Lookup[A{d}] + Lookup[A{d}]](sink value: C.Elem) -> C.Elem {{\n    value\n}}\n", .{ n, n });
    try w.writeAll("fn main() -> UInt8 {\n    0\n}\n");
    return out.toOwnedSlice();
}

/// Many calls through one generic alias, each settling the alias's parameter
/// from its own annotation: the alias is read once and every path head matches
/// it against that call's result.
fn genericAliasHeadsModule(gpa: std.mem.Allocator, n: u32) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    const w = &out.writer;
    try w.writeAll("struct Cell[T] {\n    value: T,\n}\n\nimpl[T] Cell[T] {\n    fn wrap(sink value: T) -> Cell[T] {\n        .{ value = value }\n    }\n}\n\nalias Slot[T] = Cell[T]\n");
    for (0..n) |i| try w.print("fn _held{d}() -> UInt8 {{\n    let cell: Slot[UInt8] = Slot.wrap(1)\n    let Cell {{ value }} = cell\n    value\n}}\n", .{i});
    try w.writeAll("fn main() -> UInt8 {\n    0\n}\n");
    return out.toOwnedSlice();
}

test "generic alias path heads sweep is accepted" {
    for ([_]u32{ 3, 6 }) |n| {
        var arena = std.heap.ArenaAllocator.init(testing.allocator);
        defer arena.deinit();
        const gpa = arena.allocator();
        const text = try genericAliasHeadsModule(gpa, n);
        _ = try treeCost(gpa, testing.io, text, .check);
    }
}

test "nested alias sweeps are accepted or refused as the one duplicate" {
    for ([_]u32{ 3, 6 }) |n| {
        var arena = std.heap.ArenaAllocator.init(testing.allocator);
        defer arena.deinit();
        const gpa = arena.allocator();
        const bounds = try nestedAliasBoundsModule(gpa, n);
        _ = try treeCost(gpa, testing.io, bounds, .check);
        const duplicates = try nestedAliasImplementationsModule(gpa, n);
        _ = try treeCost(gpa, testing.io, duplicates, .{ .refused = .n_duplicate });
    }
}

test "bounds on one parameter sweep reads the name through the one bound declaring it" {
    for ([_]u32{ 3, 6 }) |n| {
        var arena = std.heap.ArenaAllocator.init(testing.allocator);
        defer arena.deinit();
        const gpa = arena.allocator();
        const text = try boundsOnOneParameterModule(gpa, n);
        const source: Source = .{ .path = "bounds-on-one-parameter.lin", .text = text };
        var sink = Sink.init(gpa);
        var interner: Interner = .empty;
        const tokens = try tokenize(gpa, &source, .from(0), &sink, &interner);
        var ast = try parse(gpa, &source, .from(0), tokens, &sink);
        var resolved = try resolveTree(gpa, &ast, &sink);
        _ = try typecheckTree(gpa, &resolved, &sink);
        try testing.expectEqual(@as(u32, 0), sink.error_count);
        _ = try costOf(gpa, testing.io, text);
    }
}

test "distinct bound sweep retains a shared and a selective requirement" {
    for ([_]u32{ 3, 6 }) |n| {
        var arena = std.heap.ArenaAllocator.init(testing.allocator);
        defer arena.deinit();
        const gpa = arena.allocator();
        const text = try distinctBoundShapesModule(gpa, n);
        const source: Source = .{ .path = "distinct-bounds.lin", .text = text };
        var sink = Sink.init(gpa);
        var interner: Interner = .empty;
        const tokens = try tokenize(gpa, &source, .from(0), &sink, &interner);
        var ast = try parse(gpa, &source, .from(0), tokens, &sink);
        var resolved = try resolveTree(gpa, &ast, &sink);
        const typing = try typecheckTree(gpa, &resolved, &sink);
        try testing.expectEqual(@as(u32, 0), sink.error_count);
        try testing.expectEqual(@as(usize, n * 2), typing.implementations.len);
        var parameters: usize = 0;
        for (0..ast.declCount()) |i| {
            const declaration = node_mod.DeclId.at(@intCast(i));
            for (ast.declTypeParams(declaration)) |parameter| {
                parameters += 1;
                try testing.expectEqual(@as(usize, 2), ast.boundsOf(parameter).len);
            }
        }
        try testing.expectEqual(@as(usize, n), parameters);
        _ = try costOf(gpa, testing.io, text);
    }
}

/// One trait requiring `n` members and one implementation supplying them all.
fn traitMemberPairingModule(gpa: std.mem.Allocator, n: u32) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    const w = &out.writer;

    try w.writeAll("pub trait Many {\n");
    for (0..n) |i| try w.print("    fn m{d}(x: Self) -> UInt8\n", .{i});
    try w.writeAll("}\n\npub struct T {\n    a: UInt8,\n}\n\nimpl Many for T {\n");
    for (0..n) |i| {
        try w.print("    fn m{d}(x: Self) -> UInt8 {{\n        x.a\n    }}\n", .{i});
    }
    try w.writeAll("}\n\nfn main() -> UInt8 {\n    0\n}\n");
    return out.toOwnedSlice();
}

/// Disjoint trait arguments sharing one receiver constructor. Open arguments
/// exercise overlap checking; settled arguments also exercise resolver keys.
fn coherenceModule(gpa: std.mem.Allocator, n: u32, comptime open: bool, comptime later_argument: bool) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    const w = &out.writer;
    try w.writeAll("struct Holder[T] { value: T }\n");
    try w.writeAll(if (later_argument)
        "trait Route[phantom Fixed, A] { fn route(_self: Self, _item: A) -> UInt8 }\n"
    else
        "trait Route[A] { fn route(_self: Self, _item: A) -> UInt8 }\n");
    const fixed = if (later_argument) "UInt8, " else "";
    for (0..n) |i| {
        try w.print("struct Tag{d}[T] {{ value: T }}\n", .{i});
        if (open) {
            try w.print("impl[T] Route[{s}Tag{d}[T]] for Holder[T] {{\n" ++
                "    fn route(_self: Self, _item: Tag{d}[T]) -> UInt8 {{ 0 }}\n}}\n", .{ fixed, i, i });
        } else {
            try w.print("impl Route[{s}Tag{d}[UInt8]] for Holder[UInt8] {{\n" ++
                "    fn route(_self: Self, _item: Tag{d}[UInt8]) -> UInt8 {{ 0 }}\n}}\n", .{ fixed, i, i });
        }
    }
    try w.writeAll("fn main() -> UInt8 { 0 }\n");
    return out.toOwnedSlice();
}

fn openCoherenceModule(gpa: std.mem.Allocator, n: u32) ![]u8 {
    return coherenceModule(gpa, n, true, false);
}

fn groundCoherenceModule(gpa: std.mem.Allocator, n: u32) ![]u8 {
    return coherenceModule(gpa, n, false, false);
}

fn openLaterCoherenceModule(gpa: std.mem.Allocator, n: u32) ![]u8 {
    return coherenceModule(gpa, n, true, true);
}

fn groundLaterCoherenceModule(gpa: std.mem.Allocator, n: u32) ![]u8 {
    return coherenceModule(gpa, n, false, true);
}

test "coherence sweeps retain disjoint same-head implementations" {
    inline for (.{ true, false }) |open| {
        inline for (.{ false, true }) |later_argument| {
            for ([_]u32{ 3, 6, 12 }) |n| {
                var arena = std.heap.ArenaAllocator.init(testing.allocator);
                defer arena.deinit();
                const gpa = arena.allocator();
                const text = try coherenceModule(gpa, n, open, later_argument);
                const source: Source = .{ .path = "coherence-sweep.lin", .text = text };
                var sink = Sink.init(gpa);
                var interner: Interner = .empty;
                const tokens = try tokenize(gpa, &source, .from(0), &sink, &interner);
                var ast = try parse(gpa, &source, .from(0), tokens, &sink);
                var res = try resolveTree(gpa, &ast, &sink);
                const typing = try typecheckTree(gpa, &res, &sink);
                try testing.expectEqual(@as(u32, 0), sink.error_count);
                try testing.expectEqual(@as(usize, n), typing.supply_index.by_sig.len);
                _ = try costOf(gpa, testing.io, text);
            }
        }
    }
}

/// Parameter families meet only same-trait constructor heads. The two shapes
/// vary unrelated trait chains and one family's nominal receiver candidates.
fn parameterCoherenceModule(gpa: std.mem.Allocator, n: u32, comptime separate_traits: bool) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    const w = &out.writer;
    for (0..n) |i| {
        const trait_index = if (separate_traits) i else 0;
        if (separate_traits or i == 0) {
            try w.print("trait Route{d}[phantom Target] {{ fn route(_self: Self) -> UInt8 }}\n" ++
                "impl[T] Route{d}[UInt8] for T {{ fn route(_self: T) -> UInt8 {{ 1 }} }}\n", .{ trait_index, trait_index });
        }
        try w.print("struct Receiver{d} {{}}\n" ++
            "impl Route{d}[Bool] for Receiver{d} {{ fn route(_self: Self) -> UInt8 {{ 2 }} }}\n", .{ i, trait_index, i });
    }
    try w.writeAll("fn main() -> UInt8 { 0 }\n");
    return out.toOwnedSlice();
}

fn separateParameterCoherenceModule(gpa: std.mem.Allocator, n: u32) ![]u8 {
    return parameterCoherenceModule(gpa, n, true);
}

fn nominalParameterCoherenceModule(gpa: std.mem.Allocator, n: u32) ![]u8 {
    return parameterCoherenceModule(gpa, n, false);
}

test "parameter head coherence sweeps retain disjoint cross-head implementations" {
    inline for (.{ true, false }) |separate_traits| {
        for ([_]u32{ 3, 6, 12 }) |n| {
            var arena = std.heap.ArenaAllocator.init(testing.allocator);
            defer arena.deinit();
            const gpa = arena.allocator();
            const text = try parameterCoherenceModule(gpa, n, separate_traits);
            const source: Source = .{ .path = "parameter-coherence.lin", .text = text };
            var sink = Sink.init(gpa);
            var interner: Interner = .empty;
            const tokens = try tokenize(gpa, &source, .from(0), &sink, &interner);
            var ast = try parse(gpa, &source, .from(0), tokens, &sink);
            var res = try resolveTree(gpa, &ast, &sink);
            const typing = try typecheckTree(gpa, &res, &sink);
            try testing.expectEqual(@as(u32, 0), sink.error_count);
            try testing.expectEqual(@as(usize, if (separate_traits) n * 2 else n + 1), typing.implementations.len);
            _ = try costOf(gpa, testing.io, text);
        }
    }
}

test "coherence lookup preparation grows with written receivers" {
    inline for (.{ false, true }) |later_argument| {
        const small = try coherenceModule(testing.allocator, 64, true, later_argument);
        defer testing.allocator.free(small);
        const large = try coherenceModule(testing.allocator, 128, true, later_argument);
        defer testing.allocator.free(large);
        const before = try costOf(testing.allocator, testing.io, small);
        const after = try costOf(testing.allocator, testing.io, large);
        // A doubling admits the sweep's allocation margin without allowing
        // every receiver to manufacture every implementation's argument types.
        try testing.expect(@as(f64, @floatFromInt(after.took)) <=
            @as(f64, @floatFromInt(before.took)) * sweep_allocation_work_bound);
    }
}

test "trait member pairing sweep supplies every required signature" {
    for ([_]u32{ 3, 6 }) |n| {
        var arena = std.heap.ArenaAllocator.init(testing.allocator);
        defer arena.deinit();
        const gpa = arena.allocator();
        const text = try traitMemberPairingModule(gpa, n);
        const source: Source = .{ .path = "trait-member-pairing-sweep.lin", .text = text };
        var sink = Sink.init(gpa);
        var interner: Interner = .empty;
        const tokens = try tokenize(gpa, &source, .from(0), &sink, &interner);
        var ast = try parse(gpa, &source, .from(0), tokens, &sink);
        var res = try resolveTree(gpa, &ast, &sink);
        const typing = try typecheckTree(gpa, &res, &sink);

        try testing.expectEqual(@as(u32, 0), sink.error_count);
        try testing.expectEqual(@as(usize, n), typing.supply_index.by_sig.len);
        _ = try costOf(gpa, testing.io, text);
    }
}

/// `n` locals in one body, each named once: the shape a walk over a function's
/// own bindings grows on, which is a different curve from many functions.
fn deepModule(gpa: std.mem.Allocator, n: u32) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    const w = &out.writer;

    try w.print("fn main() -> UInt8 {{\n", .{});
    for (0..n) |i| try w.print("    let x{d}: UInt8 = {d}\n", .{ i, i % 7 });
    for (0..n) |i| try w.print("    let _ = x{d}\n", .{i});
    try w.print("    0\n}}\n", .{});
    return out.toOwnedSlice();
}

/// One loop exit reached from progressively deeper conditional breaks.
fn conditionalLoopExitsModule(gpa: std.mem.Allocator, n: u32) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    try out.writer.writeAll(
        "fn work(flag: Bool) -> UInt8 {\n" ++
            "    var again: Bool = true\n" ++
            "    while again {\n" ++
            "        again = false\n",
    );
    for (0..n) |_| try out.writer.writeAll("        if flag { break }\n");
    try out.writer.writeAll("    }\n    0\n}\nfn main() -> UInt8 { work(false) }\n");
    return out.toOwnedSlice();
}

test "conditional loop exits keep a shared exit and a backedge" {
    for ([_]u32{ 16, 32 }) |n| {
        var arena = std.heap.ArenaAllocator.init(testing.allocator);
        defer arena.deinit();
        const gpa = arena.allocator();
        const text = try conditionalLoopExitsModule(gpa, n);
        const source: Source = .{ .path = "conditional-exits.lin", .text = text };
        var sink = Sink.init(gpa);
        var interner: Interner = .empty;
        const tokens = try tokenize(gpa, &source, .from(0), &sink, &interner);
        var ast = try parse(gpa, &source, .from(0), tokens, &sink);
        var resolved = try resolveTree(gpa, &ast, &sink);
        var typing = try typecheckTree(gpa, &resolved, &sink);
        var cfg = try buildOwnershipCfg(gpa, &resolved.expanded, &resolved.resolution, &typing);
        defer cfg.deinit(gpa);
        var plan = try checkOwnershipTree(gpa, &resolved, &typing, &sink);
        defer plan.deinit(gpa);
        try testing.expectEqual(@as(u32, 0), sink.error_count);
        try testing.expect(hasBackwardEdge(&cfg));
        const incoming = try gpa.alloc(u32, cfg.blocks.len);
        @memset(incoming, 0);
        for (cfg.blocks) |block| for (cfg.edgesOf(block)) |target| {
            incoming[target.index()] += 1;
        };
        try testing.expectEqual(n + 1, std.mem.max(u32, incoming));
    }
}

/// Repeated generic reads cross joins while only two source bindings stay live.
fn dependencyReadsModule(gpa: std.mem.Allocator, n: u32) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    try out.writer.writeAll(
        "struct Cell { value: UInt64 }\n" ++
            "fn measure[T](_value: T) -> UInt64 { 1 }\n" ++
            "fn accumulate[T](left: T, right: T, flag: Bool) -> UInt64 {\n" ++
            "    var total: UInt64 = 0\n",
    );
    for (0..n) |_| try out.writer.writeAll(
        "    if flag { total = total + measure(left) }\n" ++
            "    else { total = total + measure(right) }\n" ++
            "    while true {\n" ++
            "        total = total + measure(left) + measure(right)\n" ++
            "        break\n" ++
            "    }\n",
    );
    try out.writer.writeAll(
        "    total\n}\n" ++
            "fn main() -> UInt8 {\n" ++
            "    let left: Cell = .{ value = 1 }\n" ++
            "    let right: Cell = .{ value = 2 }\n" ++
            "    let _total = accumulate(left, right, true)\n" ++
            "    0\n}\n",
    );
    return out.toOwnedSlice();
}

/// One loop containing `n` branches whose arms mint and consume one value.
fn smallOwnershipDeltasModule(gpa: std.mem.Allocator, n: u32) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    const w = &out.writer;

    try w.writeAll(
        "@linear enum Key { Forged(UInt8) }\n\n" ++
            "fn release(sink key: Key) {\n" ++
            "    match key { Forged(_) => {} }\n" ++
            "}\n\n" ++
            "fn main() -> UInt8 {\n" ++
            "    var x: UInt8 = 0\n" ++
            "    while x < 2 {\n",
    );
    for (0..n) |i| try w.print(
        "        if x == {d} {{\n" ++
            "            let yes{d}: Key = .Forged(0)\n" ++
            "            release(yes{d})\n" ++
            "        }} else {{\n" ++
            "            let no{d}: Key = .Forged(0)\n" ++
            "            release(no{d})\n" ++
            "        }}\n",
        .{ i % 2, i, i, i, i },
    );
    try w.writeAll("        x = x + 1\n    }\n    x\n}\n");
    return out.toOwnedSlice();
}

/// Either path through one loop branch mints and consumes `n` values together.
fn heavyOwnershipDeltasModule(gpa: std.mem.Allocator, n: u32) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    const w = &out.writer;

    try w.writeAll(
        "@linear enum Key { Forged(UInt8) }\n\n" ++
            "fn release(sink key: Key) {\n" ++
            "    match key { Forged(_) => {} }\n" ++
            "}\n\n" ++
            "fn main() -> UInt8 {\n" ++
            "    var turn: UInt8 = 0\n" ++
            "    while turn < 2 {\n" ++
            "        if turn == 0 {\n",
    );
    for (0..n) |i| try w.print("            let yes{d}: Key = .Forged(0)\n", .{i});
    for (0..n) |i| try w.print("            release(yes{d})\n", .{i});
    try w.writeAll("        } else {\n");
    for (0..n) |i| try w.print("            let no{d}: Key = .Forged(0)\n", .{i});
    for (0..n) |i| try w.print("            release(no{d})\n", .{i});
    try w.writeAll("        }\n");
    for (0..n) |i| try w.print(
        "        if turn == {d} {{\n" ++
            "            let path_yes{d}: Key = .Forged(0)\n" ++
            "            release(path_yes{d})\n" ++
            "        }} else {{\n" ++
            "            let path_no{d}: Key = .Forged(0)\n" ++
            "            release(path_no{d})\n" ++
            "        }}\n",
        .{ i % 2, i, i, i, i },
    );
    try w.writeAll("        turn = turn + 1\n    }\n");
    try w.writeAll("    turn\n}\n");
    return out.toOwnedSlice();
}

/// One body deferring `n` values at its top and then branching `n` times, so
/// every join sits before every schedule and the function holds `n` deferred
/// bindings over about `2n` blocks.
fn deferredBindingsAcrossJoinsModule(gpa: std.mem.Allocator, n: u32) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    const w = &out.writer;

    try w.writeAll(deferredKeyPrelude);
    for (0..n) |i| try w.print("    let k{d}: Key = .{{ n = 1 }}\n    defer lock(k{d})\n", .{ i, i });
    for (0..n) |_| try w.writeAll("    if turns == 0 {\n        turns = turns + 1\n    }\n");
    try w.writeAll(deferredKeyEnd);
    return out.toOwnedSlice();
}

/// Sixteen values deferred at the top of a body that then nests `n` loops, so
/// the schedules at the body's end are awaited across `n` back edges.
fn deferredBindingsUnderNestedLoopsModule(gpa: std.mem.Allocator, n: u32) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    const w = &out.writer;

    try w.writeAll(deferredKeyPrelude);
    for (0..16) |i| try w.print("    let k{d}: Key = .{{ n = 1 }}\n    defer lock(k{d})\n", .{ i, i });
    for (0..n) |_| try w.writeAll("    while turns < 1 {\n");
    for (0..n) |_| try w.writeAll("    turns = turns + 1\n    }\n");
    try w.writeAll(deferredKeyEnd);
    return out.toOwnedSlice();
}

const deferredKeyPrelude =
    "struct Key { n: UInt8 }\n\n" ++
    "fn lock(sink k: Key) {\n" ++
    "    let Key { n: _n } = k\n" ++
    "}\n\n" ++
    "fn work() -> UInt8 {\n" ++
    "    var turns: UInt8 = 0\n";

const deferredKeyEnd = "    turns\n}\n\nfn main() -> UInt8 { work() }\n";

test "deferred binding modules are accepted" {
    inline for (.{ deferredBindingsAcrossJoinsModule, deferredBindingsUnderNestedLoopsModule }) |make| {
        var arena = std.heap.ArenaAllocator.init(testing.allocator);
        defer arena.deinit();
        const gpa = arena.allocator();
        const text = try make(gpa, 16);
        const source: Source = .{ .path = "deferred-bindings.lin", .text = text };
        var sink = Sink.init(gpa);
        var interner: Interner = .empty;
        const tokens = try tokenize(gpa, &source, .from(0), &sink, &interner);
        var ast = try parse(gpa, &source, .from(0), tokens, &sink);
        var resolved = try resolveTree(gpa, &ast, &sink);
        var typing = try typecheckTree(gpa, &resolved, &sink);
        var plan = try checkOwnershipTree(gpa, &resolved, &typing, &sink);
        defer plan.deinit(gpa);
        try testing.expectEqual(@as(u32, 0), sink.error_count);
    }
}

/// Distinct observations remain live across writes to unrelated owners.
fn independentObservationsModule(gpa: std.mem.Allocator, n: u32) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    const w = &out.writer;
    try w.writeAll("fn main() -> UInt8 {\n");
    for (0..n) |i| {
        try w.print("    let owner{d}: UInt64 = 1\n    let view{d} = borrow owner{d}\n    var other{d}: UInt64 = 0\n", .{ i, i, i, i });
    }
    for (0..n) |i| try w.print("    other{d} = other{d} + 1\n", .{ i, i });
    try w.writeAll("    var total: UInt64 = 0\n");
    for (0..n) |i| try w.print("    total = total + *view{d} + other{d}\n", .{ i, i });
    try w.print("    if total == {d} {{ 0 }} else {{ 1 }}\n}}\n", .{@as(u64, n) * 2});
    return out.toOwnedSlice();
}

/// One body of `n` closures, each lent its own field of one record `inout`
/// and kept live across `n` reads of another field of that record. A read
/// must inspect only the lends its path can overlap, not every lend of the
/// record.
fn inoutFieldLendsModule(gpa: std.mem.Allocator, n: u32) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    const w = &out.writer;
    try w.writeAll("struct Tally {\n");
    for (0..n) |i| try w.print("    f{d}: UInt64,\n", .{i});
    try w.writeAll("    other: UInt64,\n}\nfn main() -> UInt8 {\n    var tally = Tally { other = 1");
    for (0..n) |i| try w.print(", f{d} = 0", .{i});
    try w.writeAll(" }\n");
    for (0..n) |i| try w.print("    var tick{d} = inout [inout count = tally.f{d}] || {{ count += 1 }}\n", .{ i, i });
    try w.writeAll("    var seen: UInt64 = 0\n");
    for (0..n) |_| try w.writeAll("    seen = seen + tally.other\n");
    for (0..n) |i| try w.print("    &tick{d}()\n", .{i});
    try w.writeAll("    var total: UInt64 = seen\n");
    for (0..n) |i| try w.print("    total = total + tally.f{d}\n", .{i});
    try w.print("    if total == {d} {{ 0 }} else {{ 1 }}\n}}\n", .{@as(u64, n) * 2});
    return out.toOwnedSlice();
}

/// One body of `n` closures, each lent its own place `inout` and kept live
/// across `n` reads of an unlent place, then each place read after its
/// closure's last call. A read must inspect only the lends of the place it
/// reads, so the reads cost nothing for the lends of the others.
fn inoutLendsModule(gpa: std.mem.Allocator, n: u32) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    const w = &out.writer;
    try w.writeAll("fn main() -> UInt8 {\n");
    for (0..n) |i| {
        try w.print("    var count{d}: UInt64 = 0\n    var tick{d} = inout [inout count{d}] || {{ count{d} += 1 }}\n", .{ i, i, i, i });
    }
    try w.writeAll("    var other: UInt64 = 0\n");
    for (0..n) |_| try w.writeAll("    other = other + 1\n");
    for (0..n) |i| try w.print("    &tick{d}()\n", .{i});
    try w.writeAll("    var total: UInt64 = other\n");
    for (0..n) |i| try w.print("    total = total + count{d}\n", .{i});
    try w.print("    if total == {d} {{ 0 }} else {{ 1 }}\n}}\n", .{@as(u64, n) * 2});
    return out.toOwnedSlice();
}

/// One body of `n` observations of places kept live to its end, and `n`
/// statements between them that each borrow a temporary. Ending a statement's
/// temporaries must read only what that statement made, whatever else is live.
fn borrowedTemporariesModule(gpa: std.mem.Allocator, n: u32) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    const w = &out.writer;
    try w.writeAll(
        \\struct Reading { value: borrow UInt64 }
        \\fn reading(value: UInt64) -> Reading where borrows(.value: value) { .{ value = borrow value } }
        \\fn sum(entry: Reading) -> UInt64 { *entry.value }
        \\fn main() -> UInt8 {
        \\    var total: UInt64 = 0
        \\
    );
    for (0..n) |i| try w.print("    let owner{d}: UInt64 = {d}\n    let view{d} = reading(owner{d})\n", .{ i, i, i, i });
    for (0..n) |i| try w.print("    total = total + sum(reading(total + {d}))\n", .{i});
    for (0..n) |i| try w.print("    total = total + sum(view{d})\n", .{i});
    try w.writeAll("    if total == 0 { 1 } else { 0 }\n}\n");
    return out.toOwnedSlice();
}

test "borrow sweep keeps independent observations live across unrelated writes" {
    const shapes = [_]*const fn (std.mem.Allocator, u32) anyerror![]u8{ independentObservationsModule, carrierFieldBindingsModule, borrowedTemporariesModule, inoutLendsModule, inoutFieldLendsModule };
    for (shapes) |make| for ([_]u32{ 8, 16 }) |n| {
        const source = try make(testing.allocator, n);
        defer testing.allocator.free(source);
        _ = try costOf(testing.allocator, testing.io, source);
    };
}

fn hasBackwardEdge(cfg: *const @import("ownership/cfg.zig").Cfg) bool {
    for (cfg.blocks, 0..) |block, from| {
        for (cfg.edgesOf(block)) |to| {
            if (to.index() <= from) return true;
        }
    }
    return false;
}

const LinearStateChurn = struct {
    total: usize = 0,
    max_per_block: usize = 0,
};

fn linearStateChurn(
    cfg: *const @import("ownership/cfg.zig").Cfg,
    typing: *const Typing,
) LinearStateChurn {
    var churn: LinearStateChurn = .{};
    for (cfg.blocks) |block| {
        var in_block: usize = 0;
        var ops = cfg.opsOf(block);
        while (ops.next()) |op| switch (cfg.opTag(op)) {
            .init, .consume => {
                const root = cfg.opPlace(op).root;
                if (root != .none and typing.mustConsume(typing.bindingType(root))) {
                    in_block += 1;
                }
            },
            .dies => {
                const run = cfg.opRun(op);
                var scope = run.top;
                while (scope != .none and cfg.scopes[scope.index()].depth > run.mark) {
                    const root = cfg.scopes[scope.index()].binding;
                    if (typing.mustConsume(typing.bindingType(root))) in_block += 1;
                    scope = cfg.scopes[scope.index()].outer;
                }
            },
            else => {},
        };
        churn.total += in_block;
        churn.max_per_block = @max(churn.max_per_block, in_block);
    }
    return churn;
}

test "ownership deltas have linear source and growing cyclic CFGs" {
    const DeltaShape = struct {
        make: *const fn (std.mem.Allocator, u32) anyerror![]u8,
        heavy: bool,
    };
    const shapes = [_]DeltaShape{
        .{ .make = smallOwnershipDeltasModule, .heavy = false },
        .{ .make = heavyOwnershipDeltasModule, .heavy = true },
    };
    for (shapes) |shape| {
        var arena = std.heap.ArenaAllocator.init(testing.allocator);
        defer arena.deinit();
        const gpa = arena.allocator();

        const text = try shape.make(gpa, 16);
        const doubled = try shape.make(gpa, 32);
        try testing.expect(doubled.len <= text.len * 2 + 512);

        const source: Source = .{ .path = "ownership-deltas.lin", .text = text };
        var sink = Sink.init(gpa);
        var interner: Interner = .empty;
        const tokens = try tokenize(gpa, &source, .from(0), &sink, &interner);
        var ast = try parse(gpa, &source, .from(0), tokens, &sink);
        var res = try resolveTree(gpa, &ast, &sink);
        var typing = try typecheckTree(gpa, &res, &sink);
        var cfg = try buildOwnershipCfg(testing.allocator, &res.expanded, &res.resolution, &typing);
        defer cfg.deinit(testing.allocator);
        var disposals = try checkOwnershipTree(gpa, &res, &typing, &sink);
        defer disposals.deinit(gpa);

        const doubled_source: Source = .{ .path = "ownership-deltas-doubled.lin", .text = doubled };
        var doubled_sink = Sink.init(gpa);
        var doubled_interner: Interner = .empty;
        const doubled_tokens = try tokenize(gpa, &doubled_source, .from(0), &doubled_sink, &doubled_interner);
        var doubled_ast = try parse(gpa, &doubled_source, .from(0), doubled_tokens, &doubled_sink);
        var doubled_res = try resolveTree(gpa, &doubled_ast, &doubled_sink);
        var doubled_typing = try typecheckTree(gpa, &doubled_res, &doubled_sink);
        var doubled_cfg = try buildOwnershipCfg(testing.allocator, &doubled_res.expanded, &doubled_res.resolution, &doubled_typing);
        defer doubled_cfg.deinit(testing.allocator);
        var doubled_disposals = try checkOwnershipTree(gpa, &doubled_res, &doubled_typing, &doubled_sink);
        defer doubled_disposals.deinit(gpa);

        try testing.expectEqual(@as(u32, 0), sink.error_count);
        try testing.expectEqual(@as(u32, 0), doubled_sink.error_count);
        try testing.expect(doubled_cfg.blocks.len > cfg.blocks.len);
        try testing.expect(doubled_cfg.ops.len > cfg.ops.len);
        try testing.expect(hasBackwardEdge(&cfg));

        const churn = linearStateChurn(&cfg, &typing);
        const doubled_churn = linearStateChurn(&doubled_cfg, &doubled_typing);
        try testing.expect(churn.total > 0);
        try testing.expect(doubled_churn.total > churn.total);
        if (shape.heavy) {
            try testing.expect(doubled_churn.max_per_block > churn.max_per_block);
        } else {
            try testing.expect(churn.max_per_block <= 4);
            try testing.expectEqual(churn.max_per_block, doubled_churn.max_per_block);
        }
    }
}

/// `n` lending binders in one body, each observed by one copy.
///
/// The item type, functions, read parameter, and accumulator stay fixed. Each
/// unit of growth adds only one `match read` binder and the operation that
/// reads its true lend bit.
fn lendingBindersModule(gpa: std.mem.Allocator, n: u32) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    const w = &out.writer;

    try w.writeAll(
        "enum Item { Held(UInt8) }\n\n" ++
            "fn observe(sink value: UInt8) -> UInt8 { value }\n\n" ++
            "fn measure(item: Item) -> UInt8 {\n" ++
            "    var total: UInt8 = 0\n",
    );
    for (0..n) |i| {
        try w.print(
            "    total += match read item {{ Held(lend{d}) => observe(lend{d}) }}\n",
            .{ i, i },
        );
    }
    try w.writeAll(
        "    total\n" ++
            "}\n\n" ++
            "fn main() -> UInt8 {\n" ++
            "    measure(.Held(1))\n" ++
            "}\n",
    );
    return out.toOwnedSlice();
}

test "lending binder modules scale only true match-read binders" {
    const sizes = [_]u32{ 3, 6, 12 };
    for (sizes) |n| {
        var arena = std.heap.ArenaAllocator.init(testing.allocator);
        defer arena.deinit();
        const gpa = arena.allocator();

        const text = try lendingBindersModule(gpa, n);
        const source: Source = .{ .path = "lending-binders.lin", .text = text };
        var sink = Sink.init(gpa);
        var interner: Interner = .empty;
        const tokens = try tokenize(gpa, &source, .from(0), &sink, &interner);
        var ast = try parse(gpa, &source, .from(0), tokens, &sink);
        var res = try resolveTree(gpa, &ast, &sink);
        var typing = try typecheckTree(gpa, &res, &sink);

        try testing.expectEqual(@as(u32, 0), sink.error_count);
        try testing.expectEqual(@as(u32, 4), ast.declCount());
        var functions: u32 = 0;
        var types: u32 = 0;
        for (0..ast.declCount()) |i| {
            switch (ast.declTag(node_mod.DeclId.at(@intCast(i)))) {
                .function => functions += 1,
                .enum_, .struct_, .newtype => types += 1,
                else => {},
            }
        }
        try testing.expectEqual(@as(u32, 3), functions);
        try testing.expectEqual(@as(u32, 1), types);
        try testing.expectEqual(@as(u32, sema_types.TypeId.primitives.len + 7) + n, res.resolution.bindingCount());

        var cfg = try buildOwnershipCfg(testing.allocator, &res.expanded, &res.resolution, &typing);
        defer cfg.deinit(testing.allocator);

        var true_lends: u32 = 0;
        var read_parameter = BindingId.none;
        for (0..res.resolution.bindingCount()) |i| {
            const binding = BindingId.at(@intCast(i));
            const declared = res.resolution.declaringToken(binding);
            if (declared != .none and std.mem.eql(u8, ast.tokenText(declared), "item")) {
                read_parameter = binding;
            }
            if (!cfg.isLend(binding)) continue;
            true_lends += 1;
            try testing.expect(declared != .none);
            try testing.expect(std.mem.startsWith(u8, ast.tokenText(declared), "lend"));
        }
        try testing.expectEqual(n, true_lends);
        try testing.expect(read_parameter != .none);
        try testing.expect(!cfg.isLend(read_parameter));
        _ = try costOf(gpa, testing.io, text);
    }
}

/// One generic *function* instantiated at `n` distinct types.
///
/// A function rather than a type, and that is the point: discovery walks a
/// body per instantiation, and what it reaches there is invisible to passes
/// that only checked the generic body. A generic type instantiated as often
/// may create types and no function instances, so it does not reach the same
/// code.
fn instanceModule(gpa: std.mem.Allocator, n: u32) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    const w = &out.writer;

    for (0..n) |i| try w.print("struct S{d} {{\n    v: UInt8,\n}}\n\n", .{i});
    try w.print("fn wrap[T: Discardable](sink _x: T) -> UInt8 {{\n    0\n}}\n\n", .{});
    try w.print("fn main() -> UInt8 {{\n", .{});
    for (0..n) |i| {
        try w.print("    let _b{d}: S{d} = .{{ v = 0 }}\n", .{ i, i });
        try w.print("    let _r{d} = wrap(_b{d})\n", .{ i, i });
    }
    try w.print("    0\n}}\n", .{});
    return out.toOwnedSlice();
}

/// One structure of `n` fields, built by a literal that gives all of them.
///
/// The dimension a walk over an aggregate's parts grows on, which is a
/// different curve from many structures: verification asks what an access
/// names once per access, and layout asks where a field sits once per field.
fn fieldModule(gpa: std.mem.Allocator, n: u32) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    const w = &out.writer;

    try w.print("struct Big {{\n", .{});
    for (0..n) |i| try w.print("    f{d}: UInt8,\n", .{i});
    try w.print("}}\n\nfn main() -> UInt8 {{\n    let b: Big = .{{ ", .{});
    for (0..n) |i| {
        if (i > 0) try w.print(", ", .{});
        try w.print("f{d} = 1", .{i});
    }
    try w.print(" }}\n    b.f0\n}}\n", .{});
    return out.toOwnedSlice();
}

/// One reflected template expanded over `n` components. The source and the
/// generated implementation both grow by one constant-size field operation.
fn reflectionComponentsModule(gpa: std.mem.Allocator, n: u32) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    const w = &out.writer;

    try w.writeAll(
        "trait Visit { fn visit(sink self: Self) }\n\n" ++
            "template impl Visit {\n" ++
            "    fn visit(sink _self: Self) {\n" ++
            "        match _self { reflect.case => {\n" ++
            "            for component in reflect.components {\n" ++
            "                let _ = component.of(_self)\n" ++
            "            }\n" ++
            "        } }\n" ++
            "    }\n" ++
            "}\n\n" ++
            "struct Big {\n",
    );
    for (0..n) |i| try w.print("    f{d}: UInt8,\n", .{i});
    try w.writeAll("}\n\nderive Visit for Big\n\nfn main() -> UInt8 {\n    let value: Big = .{ ");
    for (0..n) |i| {
        if (i > 0) try w.writeAll(", ");
        try w.print("f{d} = 1", .{i});
    }
    try w.writeAll(" }\n    Visit.visit(value)\n    0\n}\n");
    return out.toOwnedSlice();
}

const constructionSweepPrelude =
    \\trait Seed[A: Copyable] {
    \\    fn seed(input: A) -> Self where carries(input)
    \\}
    \\impl[A: Copyable] Seed[A] for UInt8 {
    \\    fn seed(input: A) -> UInt8 where carries(input) {
    \\        let _input = copy(input)
    \\        7
    \\    }
    \\}
    \\trait Construct[A: Copyable] {
    \\    fn construct(input: A) -> Self where carries(input)
    \\}
    \\template impl[A: Copyable] Construct[A] where
    \\    reflect.target: struct,
    \\    reflect.components: Seed[A],
    \\{
    \\    fn construct(input: A) -> Self where carries(input) {
    \\        reflect.construct(
    \\            reflect.product,
    \\            |component| {
    \\                let field: component.Type = Seed.seed(input)
    \\                field
    \\            },
    \\            {},
    \\        )
    \\    }
    \\}
    \\
;

/// One flat construction recipe expands once per field, with one applied
/// component requirement and a trait-only parameter on the generated impl.
fn constructionProductModule(gpa: std.mem.Allocator, n: u32) ![]u8 {
    std.debug.assert(n > 0);
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    const w = &out.writer;
    try w.writeAll(constructionSweepPrelude);
    try w.writeAll("struct Product {\n");
    for (0..n) |i| try w.print("    f{d}: UInt8,\n", .{i});
    try w.writeAll(
        "}\n" ++
            "derive[A: Copyable] Construct[A] for Product\n" ++
            "fn main() -> UInt8 {\n" ++
            "    let product: Product = Construct.construct(true)\n" ++
            "    product.f0\n" ++
            "}\n",
    );
    return out.toOwnedSlice();
}

/// Repeated small products hold recipe width fixed while growing derive
/// planning, parameter substitution and ordinary generated implementations.
fn constructionDerivesModule(gpa: std.mem.Allocator, n: u32) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    const w = &out.writer;
    try w.writeAll(constructionSweepPrelude);
    for (0..n) |i| {
        try w.print("struct Product{d} {{ first: UInt8, second: UInt8 }}\n", .{i});
        try w.print("derive[A: Copyable] Construct[A] for Product{d}\n", .{i});
    }
    try w.writeAll("fn main() -> UInt8 {\n");
    for (0..n) |i| try w.print("    let _product{d}: Product{d} = Construct.construct(true)\n", .{ i, i });
    try w.writeAll("    0\n}\n");
    return out.toOwnedSlice();
}

/// One enum with `n` reflected cases. A fixed wide body makes the bounded
/// 16/32/64 case ladder measurable without changing another source dimension.
fn reflectedEnumCasesModule(gpa: std.mem.Allocator, n: u32) ![]u8 {
    std.debug.assert(n > 0 and n <= 64);
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    const w = &out.writer;

    try w.writeAll(
        "trait CaseOrdinal { fn ordinal(self: Self) -> UInt64 }\n\n" ++
            "template impl CaseOrdinal {\n" ++
            "    fn ordinal(self: Self) -> UInt64 {\n" ++
            "        match read self { reflect.case => {\n" ++
            "            var total: UInt64 = 0\n",
    );
    for (0..2000) |_| try w.writeAll("            total += 0\n");
    try w.writeAll(
        "            total + reflect.case.ordinal\n" ++
            "        } }\n" ++
            "    }\n" ++
            "}\n\n" ++
            "enum Cases {\n",
    );
    for (0..n) |i| try w.print("    Case{d},\n", .{i});
    try w.writeAll(
        "}\n\n" ++
            "derive CaseOrdinal for Cases\n\n" ++
            "fn main() -> UInt8 {\n" ++
            "    let _case: Cases = .Case0\n" ++
            "    0\n" ++
            "}\n",
    );
    return out.toOwnedSlice();
}

/// One enum variant carrying `n` payloads, all visited by one reflected loop.
fn reflectedEnumPayloadsModule(gpa: std.mem.Allocator, n: u32) ![]u8 {
    std.debug.assert(n > 0);
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    const w = &out.writer;

    try w.writeAll(
        "trait VisitPayloads { fn visit(sink self: Self) }\n\n" ++
            "template impl VisitPayloads {\n" ++
            "    fn visit(sink self: Self) {\n" ++
            "        match self { reflect.case => {\n" ++
            "            for component in reflect.components {\n" ++
            "                let _ordinal: UInt64 = component.ordinal\n" ++
            "            }\n" ++
            "        } }\n" ++
            "    }\n" ++
            "}\n\n" ++
            "enum Payloads { Value(",
    );
    for (0..n) |i| {
        if (i != 0) try w.writeAll(", ");
        try w.writeAll("UInt8");
    }
    try w.writeAll(") }\n\nderive VisitPayloads for Payloads\n\nfn main() -> UInt8 {\n    let value = Payloads.Value(");
    for (0..n) |i| {
        if (i != 0) try w.writeAll(", ");
        try w.writeAll("0");
    }
    try w.writeAll(")\n    VisitPayloads.visit(value)\n    0\n}\n");
    return out.toOwnedSlice();
}

/// One template member with `n` independent ordinal observations over a fixed
/// two-case enum, so each occurrence contributes one constant-size match.
fn reflectedOrdinalOperationsModule(gpa: std.mem.Allocator, n: u32) ![]u8 {
    std.debug.assert(n > 0);
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    const w = &out.writer;

    try w.writeAll(
        "trait ObserveOrdinals { fn observe(self: Self) -> UInt64 }\n\n" ++
            "template impl ObserveOrdinals {\n" ++
            "    fn observe(self: Self) -> UInt64 {\n",
    );
    for (0..n) |i| try w.print("        let _ordinal{d} = reflect.ordinal_of(self)\n", .{i});
    try w.writeAll(
        "        UInt64(0)\n" ++
            "    }\n" ++
            "}\n\n" ++
            "enum Observed { First, Second }\n\n" ++
            "derive ObserveOrdinals for Observed\n\n" ++
            "fn main() -> UInt8 {\n" ++
            "    let value: Observed = .First\n" ++
            "    let _answer = ObserveOrdinals.observe(value)\n" ++
            "    0\n" ++
            "}\n",
    );
    return out.toOwnedSlice();
}

/// One grouped derive expanded into `n` implementations. Every template has
/// one requirement over the same one-field target, so every entry also asks
/// the ordinary implementation index to discharge one row.
fn deriveGroupEntriesModule(gpa: std.mem.Allocator, n: u32) ![]u8 {
    std.debug.assert(n > 0);
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    const w = &out.writer;

    try w.writeAll("trait Required {}\n\nimpl Required for UInt8 {}\n\n");
    for (0..n) |i| {
        try w.print(
            "trait Group{d} {{}}\n\ntemplate impl Group{d} where reflect.components: Required {{}}\n\n",
            .{ i, i },
        );
    }
    try w.writeAll("struct GroupTarget { value: UInt8 }\n\nderive (\n");
    for (0..n) |i| try w.print("    Group{d},\n", .{i});
    try w.writeAll(
        ") for GroupTarget\n\n" ++
            "fn main() -> UInt8 {\n" ++
            "    let _value: GroupTarget = .{ value = 0 }\n" ++
            "    0\n" ++
            "}\n",
    );
    return out.toOwnedSlice();
}

/// One dependent derive requiring `n` direct supertrait derives at the same
/// normalized head. Every lookup is indexed and every prerequisite is checked
/// once under the dependent environment.
fn structuralSupertraitConstraintsModule(gpa: std.mem.Allocator, n: u32) ![]u8 {
    std.debug.assert(n > 0);
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    const w = &out.writer;

    for (0..n) |i| {
        try w.print("trait Base{d} {{}}\n\ntemplate impl Base{d} {{}}\n\n", .{ i, i });
    }
    const dependent_count = 8;
    for (0..dependent_count) |dependent| {
        try w.print("trait Law{d}: ", .{dependent});
        for (0..n) |i| {
            if (i != 0) try w.writeAll(" + ");
            try w.print("Base{d}", .{i});
        }
        try w.print(
            " {{}}\n\ntemplate impl Law{d} where reflect.supertraits: derived {{}}\n\n",
            .{dependent},
        );
    }
    try w.writeAll("struct Item {}\n\nderive (\n");
    for (0..n) |i| try w.print("    Base{d},\n", .{i});
    for (0..dependent_count) |dependent| try w.print("    Law{d},\n", .{dependent});
    try w.writeAll(
        ") for Item\n\n" ++
            "fn main() -> UInt8 {\n" ++
            "    let _item: Item = .{}\n" ++
            "    0\n" ++
            "}\n",
    );
    return out.toOwnedSlice();
}

/// One generic derive with `n` written predicates. Its sole component
/// requirement is the first predicate, so checking the generated descriptor
/// has to read the explicit environment rather than infer a bound.
fn genericDerivePredicatesModule(gpa: std.mem.Allocator, n: u32) ![]u8 {
    std.debug.assert(n > 0);
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    const w = &out.writer;

    try w.writeAll(
        "trait Predicate {}\n\n" ++
            "trait PredicateTarget {}\n\n" ++
            "template impl PredicateTarget where reflect.components: Predicate {}\n\n" ++
            "struct GenericTarget[T] { value: T }\n\n" ++
            "derive[T] PredicateTarget for GenericTarget[T] where\n",
    );
    for (0..n) |_| try w.writeAll("    T: Predicate,\n");
    try w.writeAll(
        "\nfn _hold[T](_value: GenericTarget[T]) {}\n\n" ++
            "fn main() -> UInt8 { 0 }\n",
    );
    return out.toOwnedSlice();
}

/// One generated implementation with `n` components and one requirement.
fn componentRequirementComponentsModule(gpa: std.mem.Allocator, n: u32) ![]u8 {
    std.debug.assert(n > 0);
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    const w = &out.writer;

    try w.writeAll(
        "trait ComponentBound {}\n\n" ++
            "impl ComponentBound for UInt8 {}\n\n" ++
            "trait ComponentsTarget {}\n\n" ++
            "template impl ComponentsTarget where reflect.components: ComponentBound {}\n\n" ++
            "struct ManyComponents {\n",
    );
    for (0..n) |i| try w.print("    f{d}: UInt8,\n", .{i});
    try w.writeAll("}\n\nderive ComponentsTarget for ManyComponents\n\nfn main() -> UInt8 {\n    let _value: ManyComponents = .{ ");
    for (0..n) |i| {
        if (i != 0) try w.writeAll(", ");
        try w.print("f{d} = 0", .{i});
    }
    try w.writeAll(" }\n    0\n}\n");
    return out.toOwnedSlice();
}

/// One component checked against `n` distinct template bounds.
fn componentRequirementsModule(gpa: std.mem.Allocator, n: u32) ![]u8 {
    std.debug.assert(n > 0);
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    const w = &out.writer;

    for (0..n) |i| {
        try w.print("trait Requirement{d} {{}}\n\nimpl Requirement{d} for UInt8 {{}}\n\n", .{ i, i });
    }
    try w.writeAll("trait RequirementsTarget {}\n\ntemplate impl RequirementsTarget where reflect.components: ");
    for (0..n) |i| {
        if (i != 0) try w.writeAll(" + ");
        try w.print("Requirement{d}", .{i});
    }
    try w.writeAll(
        " {}\n\n" ++
            "struct OneComponent { value: UInt8 }\n\n" ++
            "derive RequirementsTarget for OneComponent\n\n" ++
            "fn main() -> UInt8 {\n" ++
            "    let _value: OneComponent = .{ value = 0 }\n" ++
            "    0\n" ++
            "}\n",
    );
    return out.toOwnedSlice();
}

/// Approximately `sqrt(n)` components by `ceil(n / sqrt(n))` requirements,
/// producing at least `n` rows while neither side of the product dominates.
fn componentRequirementRowsModule(gpa: std.mem.Allocator, n: u32) ![]u8 {
    std.debug.assert(n > 0);
    var components: u32 = 1;
    while (components + 1 <= n / (components + 1)) components += 1;
    const requirements = std.math.divCeil(u32, n, components) catch unreachable;

    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    const w = &out.writer;
    for (0..requirements) |i| {
        try w.print("trait RowBound{d} {{}}\n\nimpl RowBound{d} for UInt8 {{}}\n\n", .{ i, i });
    }
    try w.writeAll("trait RowsTarget {}\n\ntemplate impl RowsTarget where reflect.components: ");
    for (0..requirements) |i| {
        if (i != 0) try w.writeAll(" + ");
        try w.print("RowBound{d}", .{i});
    }
    try w.writeAll(" {}\n\nstruct RowComponents {\n");
    for (0..components) |i| try w.print("    f{d}: UInt8,\n", .{i});
    try w.writeAll("}\n\nderive RowsTarget for RowComponents\n\nfn main() -> UInt8 {\n    let _value: RowComponents = .{ ");
    for (0..components) |i| {
        if (i != 0) try w.writeAll(", ");
        try w.print("f{d} = 0", .{i});
    }
    try w.writeAll(" }\n    0\n}\n");
    return out.toOwnedSlice();
}

/// One structural template member with `n` generic parameters. Every
/// parameter carries one applied bound and appears in one ordinary parameter,
/// so member compatibility reads one constant-size row per parameter.
fn templateMemberParametersModule(gpa: std.mem.Allocator, n: u32) ![]u8 {
    std.debug.assert(n > 0);
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    const w = &out.writer;

    try w.writeAll(
        "trait MemberBound[phantom I] {}\n\n" ++
            "trait Structural {\n    fn value[",
    );
    for (0..n) |i| {
        if (i != 0) try w.writeAll(", ");
        try w.print("A{d}: MemberBound[A{d}]", .{ i, i });
    }
    try w.writeAll("](self: Self");
    for (0..n) |i| try w.print(", item{d}: A{d}", .{ i, i });
    try w.writeAll(") -> UInt8\n}\n\ntemplate impl Structural {\n    fn value[");
    for (0..n) |i| {
        if (i != 0) try w.writeAll(", ");
        try w.print("X{d}: MemberBound[X{d}]", .{ i, i });
    }
    try w.writeAll("](_self: Self");
    for (0..n) |i| try w.print(", _item{d}: X{d}", .{ i, i });
    try w.writeAll(
        ") -> UInt8 { 0 }\n" ++
            "}\n\n" ++
            "struct Target {}\n\n" ++
            "derive Structural for Target\n\n" ++
            "fn main() -> UInt8 {\n" ++
            "    let _value: Target = .{}\n" ++
            "    0\n" ++
            "}\n",
    );
    return out.toOwnedSlice();
}

fn expectRequirementSweepModule(
    make: *const fn (std.mem.Allocator, u32) anyerror![]u8,
    n: u32,
    implementations: u32,
    rows: usize,
) !void {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    const text = try make(gpa, n);
    const source: Source = .{ .path = "requirement-sweep.lin", .text = text };
    var sink = Sink.init(gpa);
    var interner: Interner = .empty;
    const tokens = try tokenize(gpa, &source, .from(0), &sink, &interner);
    var ast = try parse(gpa, &source, .from(0), tokens, &sink);
    var res = try resolveTree(gpa, &ast, &sink);
    var typing = try typecheckTree(gpa, &res, &sink);
    var disposals = try checkOwnershipTree(gpa, &res, &typing, &sink);
    _ = &disposals;

    try testing.expectEqual(@as(u32, 0), sink.error_count);
    try testing.expectEqual(implementations, res.expanded.generatedImplementationCount());
    var requirement_rows: usize = 0;
    for (0..implementations) |i| {
        requirement_rows += res.expanded.componentRequirements(GeneratedImplementationId.at(@intCast(i))).len;
    }
    try testing.expectEqual(rows, requirement_rows);
    _ = try costOf(gpa, testing.io, text);
}

test "component requirement sweep modules expand and discharge every planned row" {
    try expectRequirementSweepModule(deriveGroupEntriesModule, 3, 3, 3);
    try expectRequirementSweepModule(genericDerivePredicatesModule, 3, 1, 1);
    try expectRequirementSweepModule(componentRequirementComponentsModule, 3, 1, 3);
    try expectRequirementSweepModule(componentRequirementsModule, 3, 1, 3);
    try expectRequirementSweepModule(componentRequirementRowsModule, 5, 1, 6);
}

test "construction sweep modules expand products and discharge parameterized requirements" {
    try expectRequirementSweepModule(constructionProductModule, 4, 1, 4);
    try expectRequirementSweepModule(constructionDerivesModule, 3, 3, 6);
}

test "enum reflection sweep modules exercise cases payloads and ordinals" {
    for ([_]*const fn (std.mem.Allocator, u32) anyerror![]u8{
        reflectedEnumCasesModule,
        reflectedEnumPayloadsModule,
        reflectedOrdinalOperationsModule,
    }) |make| {
        var arena = std.heap.ArenaAllocator.init(testing.allocator);
        defer arena.deinit();
        const gpa = arena.allocator();
        const text = try make(gpa, 3);
        _ = try costOf(gpa, testing.io, text);
    }
}

test "structural supertrait sweep modules select every prerequisite derive" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    const text = try structuralSupertraitConstraintsModule(gpa, 3);
    _ = try costOf(gpa, testing.io, text);
}

test "template member sweep modules match every generic parameter row" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    const text = try templateMemberParametersModule(gpa, 3);
    const source: Source = .{ .path = "template-member-sweep.lin", .text = text };
    var sink = Sink.init(gpa);
    var interner: Interner = .empty;
    const tokens = try tokenize(gpa, &source, .from(0), &sink, &interner);
    var ast = try parse(gpa, &source, .from(0), tokens, &sink);
    var res = try resolveTree(gpa, &ast, &sink);
    var typing = try typecheckTree(gpa, &res, &sink);
    var cancelled = try checkOwnershipTree(gpa, &res, &typing, &sink);
    _ = &cancelled;

    try testing.expectEqual(@as(u32, 0), sink.error_count);
    try testing.expectEqual(@as(u32, 1), res.expanded.generatedImplementationCount());
    _ = try costOf(gpa, testing.io, text);
}

/// A chain of `n` nominal types, each represented by the one before it.
///
/// Every declaration is deliberately unused by the program but used by the
/// next declaration. Representation still has to settle every row in the
/// sealed pool, and following the whole prefix once per row is quadratic.
fn newtypeChainModule(gpa: std.mem.Allocator, n: u32) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    const w = &out.writer;

    if (n > 0) try w.writeAll("type _T0 = UInt8\n");
    for (1..n) |i| try w.print("type _T{d} = _T{d}\n", .{ i, i - 1 });
    try w.writeAll("\nfn main() -> UInt8 {\n    0\n}\n");
    return out.toOwnedSlice();
}

/// A borrowed carrier with `n` field paths, moved through `n` bindings.
/// The literal, type and binding chain each contain O(n) source text.
fn carrierFieldBindingsModule(gpa: std.mem.Allocator, n: u32) ![]u8 {
    std.debug.assert(n > 0);
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    const w = &out.writer;

    try w.writeAll(
        "@copyable enum Failure { Failed }\n" ++
            "@copyable enum Result[T, E] { Ok(T), Err(E) }\n" ++
            "fn observe(value: UInt8) -> Result[borrow UInt8, Failure] where borrows(.Ok: value) { .Ok(borrow value) }\n" ++
            "struct Big {\n",
    );
    for (0..n) |i| try w.print("    f{d}: Result[borrow UInt8, Failure],\n", .{i});
    try w.writeAll("}\nfn consume(sink _value: Big) -> UInt8 { 0 }\nfn main() -> UInt8 {\n    let owner: UInt8 = 0\n    let view = observe(owner)\n    let b0: Big = .{ ");
    for (0..n) |i| {
        if (i != 0) try w.writeAll(", ");
        try w.print("f{d} = copy(view)", .{i});
    }
    try w.writeAll(" }\n");
    for (1..n) |i| try w.print("    let b{d} = b{d}\n", .{ i, i - 1 });
    try w.print("    let answer = consume(b{d})\n", .{n - 1});
    try w.writeAll("    match view { Ok(_value) => {}, Err(_error) => {} }\n    answer\n}\n");
    return out.toOwnedSlice();
}

/// Repeated owners compress to dependency ranges; known writes split those
/// ranges. Conditional writes also exercise ambient-fact joins.
fn arrayReplacementModule(gpa: std.mem.Allocator, n: u32, conditional: bool) ![]u8 {
    std.debug.assert(n > 0);
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    const w = &out.writer;
    if (conditional) {
        try w.print("fn replace(old: [borrow UInt8; {d}], owner: UInt8, choose: Bool) -> UInt8 {{\nvar slots = copy(old)\n", .{n});
        for (0..n) |i| try w.print("if choose {{ slots[{d}] = borrow owner }}\n", .{i});
        try w.writeAll("let result = copy(slots[0])\n*result\n}\n");
    }
    try w.writeAll("fn main() -> UInt8 {\nlet old: UInt8 = 1\nlet owner: UInt8 = 0\n");
    try w.writeAll(if (conditional) "let slots = [" else "var slots = [");
    for (0..n) |i| {
        if (i != 0) try w.writeAll(", ");
        try w.writeAll("borrow old");
    }
    try w.writeAll("]\n");
    if (conditional) {
        try w.writeAll("replace(slots, owner, true)\n}\n");
    } else {
        for (0..n) |i| try w.print("slots[{d}] = borrow owner\n", .{i});
        try w.writeAll("let result = copy(slots[0])\n*result\n}\n");
    }
    return out.toOwnedSlice();
}

fn knownArrayReplacementModule(gpa: std.mem.Allocator, n: u32) ![]u8 {
    return arrayReplacementModule(gpa, n, false);
}

fn conditionalArrayReplacementModule(gpa: std.mem.Allocator, n: u32) ![]u8 {
    return arrayReplacementModule(gpa, n, true);
}

/// A program of `n` modules, each exporting one function the root calls.
///
/// The dimension nothing else here builds: every other shape is one file in
/// one module, so a question asked of the modules a program has, or of the
/// declarations another module holds, is asked of one. A module is a
/// directory, so this grows with the source tree rather than with any file.
///
/// The caller owns the list and every path and body in it.
fn moduleProgram(gpa: std.mem.Allocator, n: u32) ![]loader.InMemoryFile {
    var files: std.ArrayList(loader.InMemoryFile) = .empty;
    errdefer {
        for (files.items) |f| {
            gpa.free(f.path);
            gpa.free(f.text);
        }
        files.deinit(gpa);
    }

    try files.append(gpa, .{
        .path = try gpa.dupe(u8, "p/linea.json"),
        .text = try gpa.dupe(u8, "{}\n"),
    });

    var root: std.Io.Writer.Allocating = .init(gpa);
    errdefer root.deinit();
    const w = &root.writer;
    for (0..n) |i| try w.print("import m{d}\n", .{i});
    try w.print("\nfn main() -> UInt8 {{\n", .{});
    for (0..n) |i| try w.print("    let _v{d} = m{d}.v{d}()\n", .{ i, i, i });
    try w.print("    0\n}}\n", .{});

    try files.append(gpa, .{
        .path = try gpa.dupe(u8, "p/main.lin"),
        .text = try root.toOwnedSlice(),
    });

    for (0..n) |i| {
        try files.append(gpa, .{
            .path = try std.fmt.allocPrint(gpa, "p/m{d}/m{d}.lin", .{ i, i }),
            .text = try std.fmt.allocPrint(
                gpa,
                "pub fn v{d}() -> UInt8 {{\n    {d}\n}}\n",
                .{ i, i % 7 },
            ),
        });
    }

    return files.toOwnedSlice(gpa);
}

/// Runs the whole pipeline over a program of several files and says what it
/// cost. What `costOf` does for one module, through the loader, because a
/// program of several is what the loader is for.
fn costOfFiles(
    backing: std.mem.Allocator,
    io: std.Io,
    entry: []const u8,
    files: []const loader.InMemoryFile,
    mode: enum { accounting, timing },
) !Cost {
    var compilation = std.heap.ArenaAllocator.init(backing);
    defer compilation.deinit();
    const gpa = compilation.allocator();
    var counting: Counting = .{ .under = gpa, .allow_growth = mode == .timing };
    const a = counting.allocator();

    const timer = CostTimer.start(io);
    {
        var arena = std.heap.ArenaAllocator.init(a);
        defer arena.deinit();
        var sink = Sink.init(arena.allocator());
        var interner: Interner = .empty;
        defer interner.deinit(a);

        var table: FileTable = .empty;
        defer table.deinit(a);

        var program = try loadFromMemory(a, &table, &sink, &interner, entry, files, .program, true, .borrow);
        defer program.deinit(a);
        if (sink.hasErrors()) return error.CostModuleRejected;

        var semantics = try checkProgram(a, a, &program, &interner, &sink, .program);
        defer semantics.deinit(a);
        if (sink.hasErrors()) return error.CostModuleRejected;

        var lowered = (try lower(a, &semantics.expanded, &semantics.res, &semantics.typing, &semantics.disposals, &sink, .program)) orelse return error.CostModuleRejected;
        defer lowered.deinit(a);

        // Match the driver's 4 KiB output buffer without including file I/O.
        // Retaining unread MLIR would add output-sized growth and copying.
        var output_buffer: [4096]u8 = undefined;
        var ir: std.Io.Writer.Discarding = .init(&output_buffer);
        if (!try emitMlir(a, &ir.writer, &lowered, &table, &sink)) {
            return error.CostModuleRejected;
        }
    }
    return timer.finish(io, counting.took);
}

/// The fastest of `runs` runs over a program of several files.
fn fastestOfFiles(
    backing: std.mem.Allocator,
    io: std.Io,
    entry: []const u8,
    files: []const loader.InMemoryFile,
    runs: usize,
) !Cost {
    // One extra compilation fixes backing growth for the allocation metric.
    // Its arena is released before timing starts; only the allocation total
    // survives. Timing retains ordinary allocator policy.
    const accounting = try costOfFiles(backing, io, entry, files, .accounting);
    var best = try costOfFiles(backing, io, entry, files, .timing);
    best.took = accounting.took;
    for (1..@max(runs, 1)) |_| {
        const again = try costOfFiles(backing, io, entry, files, .timing);
        if (again.nanos < best.nanos) {
            best.nanos = again.nanos;
            best.cpu_nanos = again.cpu_nanos;
        }
    }
    return best;
}

/// `n` copies in one body, each of the same source.
///
/// Whether a copy did anything is the one question this compiler asks
/// backwards, and it is asked once per copy against the operations of the
/// body holding it -- so a body of many copies is where that meets itself.
fn copyModule(gpa: std.mem.Allocator, n: u32) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    const w = &out.writer;

    try w.print("@copyable struct P {{\n    v: UInt8,\n}}\n\nfn main() -> UInt8 {{\n", .{});
    try w.print("    let p: P = .{{ v = 1 }}\n", .{});
    for (0..n) |i| {
        try w.print("    let c{d}: P = copy(p)\n", .{i});
        try w.print("    let _u{d} = c{d}.v\n", .{ i, i });
        try w.print("    let _k{d} = c{d}\n", .{ i, i });
    }
    try w.print("    let _l = p\n    0\n}}\n", .{});
    return out.toOwnedSlice();
}

/// `n` uses of `?` in one body, with every earlier local still live at each.
///
/// The failing edge of a `?` leaves every scope it is inside, and a scope's
/// end names a stretch of the live stack rather than each binding in it -- so
/// the graph is the exits and not the exits times the locals. Held to the same
/// bound as every other dimension since it became able to meet it.
fn exitModule(gpa: std.mem.Allocator, n: u32) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    const w = &out.writer;

    try w.print("fn some() -> Option[UInt8] {{\n    Option.Some(1)\n}}\n\n", .{});
    try w.print("fn go() -> Option[UInt8] {{\n", .{});
    for (0..n) |i| try w.print("    let x{d} = some()?\n", .{i});
    for (0..n) |i| try w.print("    let _u{d} = x{d}\n", .{ i, i });
    try w.print("    Option.Some(0)\n}}\n\n", .{});
    try w.print(
        "fn main() -> UInt8 {{\n    match go() {{\n        Some(v) => v,\n" ++
            "        None => 0,\n    }}\n}}\n",
        .{},
    );
    return out.toOwnedSlice();
}

/// Runs the front end over one module and says what it cost.
fn costOf(gpa: std.mem.Allocator, io: std.Io, text: []const u8) !Cost {
    return treeCost(gpa, io, text, .emit);
}

/// How far a sweep compiles one text, and what it accepts of the outcome.
/// `refused` names the one diagnostic the program is written to provoke, so
/// a dimension of rejected programs measures the report path and nothing
/// else: any other diagnostic, or none, fails the sample.
const TreeCostMode = union(enum) { emit, check, refused: diagnostic.Code };

fn treeCost(gpa: std.mem.Allocator, io: std.Io, text: []const u8, mode: TreeCostMode) !Cost {
    return treeCostGrowing(gpa, io, text, mode, true);
}

/// `treeCost`, with backing growth refused where `growth` is false. An arena
/// grows its last node in place by just what each allocation needs when the
/// backing allows it, and every such growth is charged its full size, so with
/// growth allowed the allocation metric reads where the backing happened to
/// place the arena rather than what the compilation asked for.
fn treeCostGrowing(gpa: std.mem.Allocator, io: std.Io, text: []const u8, mode: TreeCostMode, growth: bool) !Cost {
    var counting: Counting = .{ .under = gpa, .allow_growth = growth };
    const a = counting.allocator();

    const timer = CostTimer.start(io);
    checking: {
        const source: Source = .{ .path = "cost.lin", .text = text };
        // The sink keeps what it is told in an arena its owner frees, and
        // that arena is counted too: what a compilation holds includes what it
        // holds to report.
        var arena = std.heap.ArenaAllocator.init(a);
        defer arena.deinit();
        var sink = Sink.init(arena.allocator());
        var interner: Interner = .empty;
        defer interner.deinit(a);

        var table: FileTable = .empty;
        defer table.deinit(a);
        const file = try table.add(a, source);

        const tokens = try tokenize(a, &source, file, &sink, &interner);
        var ast = try parse(a, &source, file, tokens, &sink);
        defer ast.deinit(a);
        var res = try resolveTree(a, &ast, &sink);
        defer res.deinit(a);
        var typing = try typecheckTree(a, &res, &sink);
        defer typing.deinit(a);
        if (mode == .refused) {
            var refusals: usize = 0;
            for (sink.items()) |diagnostic_| {
                if (diagnostic_.code != mode.refused) return error.UnexpectedSweepDiagnostic;
                refusals += 1;
            }
            if (refusals == 0) return error.ExpectedSweepRefusal;
            break :checking;
        }
        var disposals = try checkOwnershipTree(a, &res, &typing, &sink);
        defer disposals.deinit(a);

        if (sink.hasErrors()) return error.CostModuleRejected;
        if (mode == .check) break :checking;

        // Past the front end, because a pass below it costs what it costs and
        // nothing above was measuring it. Monomorphisation happens here and
        // the module is verified inside emission, so this is where a table
        // sized by the program but held per function shows itself.
        //
        // Emit every byte through a bounded sink. Producing the IR is measured;
        // retaining it and running external tools are not.
        var lowered = (try lowerTree(a, &res, &typing, &disposals, &sink, .program)) orelse return error.CostModuleRejected;
        defer lowered.deinit(a);

        // Match the driver's 4 KiB output buffer without including file I/O.
        // Retaining unread MLIR would add output-sized growth and copying.
        var output_buffer: [4096]u8 = undefined;
        var ir: std.Io.Writer.Discarding = .init(&output_buffer);
        if (!try emitMlir(a, &ir.writer, &lowered, &table, &sink)) {
            return error.CostModuleRejected;
        }
    }
    return timer.finish(io, counting.took);
}

/// One input dimension, and how big a module of it to build.
/// How many balanced curve samples a dimension receives, rung by rung, while
/// its reading is in doubt.
///
/// One sample measures all sizes forward and backward and keeps the faster
/// reading of each size. Every size then occupies both ends of a run, so
/// frequency drift cannot steepen one side of a doubling. Doubt buys more
/// complete samples, which are reduced per size by the same minimum.
///
/// The minimum is the statistic because scheduler preemption, interrupts and
/// cache pollution only add time: a reading is the true cost plus a
/// non-negative disturbance, so the smallest of several is the nearest to the
/// true cost and a disturbance cannot shorten it. A mean or a median of the
/// same readings keeps part of the disturbance, which compresses the small
/// sizes of a doubling unevenly and reads as slope.
const sweep_ladder = [_]usize{ 1, 3, 9 };

const Dimension = struct {
    name: []const u8,
    n: u32,
    /// Whether calibration may grow `n`. False where `n` is a nesting depth or
    /// a count the language caps rather than a quantity of repeated items,
    /// so growing it measures a different cost or is refused outright.
    grows: bool = true,
    /// What one size of this dimension costs, as the fastest of `runs`.
    ///
    /// A function rather than the program itself, because the dimensions are
    /// not built alike: most are one text the tree path compiles, and two are
    /// a set of files the loader reads. What the sweep does with a dimension
    /// is the same for all of them, so the difference sits here and nowhere
    /// above it.
    /// The first allocator owns endpoint inputs. The second backs independent
    /// compilation regions, so accounting cannot retain storage into timing.
    /// Zero runs compiles the program at least once and measures as little
    /// as the dimension allows, which is how a test checks its generator.
    cost: *const fn (std.mem.Allocator, std.mem.Allocator, std.Io, u32, usize) anyerror!Cost,
};

/// A dimension whose program is one text, compiled through the tree.
fn throughTheTree(
    comptime make: fn (std.mem.Allocator, u32) anyerror![]u8,
) *const fn (std.mem.Allocator, std.mem.Allocator, std.Io, u32, usize) anyerror!Cost {
    return &struct {
        fn cost(gpa: std.mem.Allocator, backing: std.mem.Allocator, io: std.Io, n: u32, runs: usize) anyerror!Cost {
            _ = backing;
            const text = try make(gpa, n);
            defer gpa.free(text);
            return fastestOf(gpa, io, text, runs);
        }
    }.cost;
}

/// Sum complete independent compilations to make short dimensions measurable.
/// The batch count is fixed across input sizes. Allocation work, wall time and
/// CPU time are totals, preserving the per-compilation growth ratios. Choose
/// the fastest complete batch, rather than mixing its fastest operations.
fn throughTreeBatch(
    comptime make: fn (std.mem.Allocator, u32) anyerror![]u8,
    comptime mode: TreeCostMode,
    comptime batch: usize,
) *const fn (std.mem.Allocator, std.mem.Allocator, std.Io, u32, usize) anyerror!Cost {
    std.debug.assert(batch > 0);
    return &struct {
        fn cost(gpa: std.mem.Allocator, backing: std.mem.Allocator, io: std.Io, n: u32, runs: usize) anyerror!Cost {
            const text = try make(gpa, n);
            defer gpa.free(text);
            var best: Cost = .{ .took = 0, .nanos = std.math.maxInt(u64) };
            // No runs asks for the program to be compiled once, unmeasured.
            for (0..@max(runs, 1)) |_| {
                var measured: Cost = .{ .took = 0, .nanos = 0 };
                for (0..if (runs == 0) 1 else batch) |_| {
                    const operation = try treeCost(backing, io, text, mode);
                    measured.nanos += operation.nanos;
                    measured.cpu_nanos += operation.cpu_nanos;
                }
                if (measured.nanos < best.nanos) best = measured;
            }
            // The allocation metric is fixed with backing growth refused, as
            // `fastestOf` fixes it.
            const accounting = try treeCostGrowing(backing, io, text, mode, false);
            best.took = accounting.took * (if (runs == 0) 1 else batch);
            return best;
        }
    }.cost;
}

/// How much allocation work may grow for one doubling. Counted rather than
/// measured, so it is the same number on every machine and can be asserted per
/// doubling: about two is linear, and the fixed cost every compilation pays is
/// what leaves room above it.
const sweep_allocation_work_bound = 2.5;

/// How much steeper than the run's own baseline a dimension may grow.
///
/// Read as an exponent: a dimension costing `n^k` for an input of `n`, and
/// this is how far above the baseline `k` may sit. Not a ceiling on a
/// duration and not one on a ratio of durations either. A ratio carries the
/// machine in it -- the same tree reads 2.22x per doubling here and 2.69x on
/// a slower box -- and it moves the wrong way besides: taking constant work
/// out of a superlinear pass makes it faster and raises its ratio. So the
/// baseline is measured rather than assumed, from the median of the
/// dimensions swept beside it: whatever the machine, its cache and its load
/// make a linear doubling cost, they make it cost for every dimension at
/// once, and the median is what a dimension with no term of its own reads.
///
/// The bound is 0.15 because it has to sit between what the readings scatter
/// by and what a term that grows with the input reads. On an idle machine the
/// dimensions read at most 0.07 above their run's median; on the shared hosted
/// runners, over the same tree, the widest gap was 0.10 to 0.14 on every one of
/// five runs, each time on a different dimension, while the two sabotages that
/// put a lookup back to a walk read 0.17 and 0.25 above the median. The bound
/// sits above the scatter and below the signal.
///
/// A dimension added is a reason to measure both again rather than to trust
/// the number: sweep every dimension a handful of times on an idle machine and
/// take the widest gap between a slope and its run's median, which is the
/// scatter; then put one lookup already known to be linear back to a walk and
/// sweep the dimension it serves, which is the signal. The bound belongs
/// between them, and a scatter that has reached it says the readings, not the
/// bound, are what needs fixing.
const sweep_steepness_bound = 0.15;

/// The steepest a dimension may read, whatever the rest of the run reads.
///
/// The gate above is relative, and what it holds a dimension against is the
/// median of the others. That answers a regression confined to a minority of
/// the dimensions, and only that: one shared by fewer than half of them is
/// caught with the whole tolerance to spare, while one shared by more than
/// half carries the median with it, and the gate reads a uniformly slower
/// compiler as a uniformly ordinary run. A rule with one implementation that
/// every pass goes through is exactly the shape that moves every dimension at
/// once, and it is the bug class this compiler is on record as having.
///
/// So the slope is held to a second bound that nothing in the run can move.
/// 1.20 because no dimension reads above n^1.18 on a hosted runner, while the
/// two sabotages that put a lookup back to a walk read n^1.20 and n^1.31 on a
/// quiet machine. It sits above every reading with no term in it and not above
/// the one that has the smallest.
///
/// A backstop rather than the working gate, and the reason it can be a fixed
/// number at all is that this step runs on an idle machine: work beside it
/// steepens every slope at once, which the relative gate divides out and this
/// one cannot.
const sweep_steepest = 1.20;

/// Under this the clock is not saying anything about the compiler, so the
/// reading is neither asserted nor counted towards the baseline. A debug
/// build is slower than the release one these sizes were chosen against, so
/// this only bites if a dimension gets much faster -- and then the sizes want
/// raising, which is what the message asks for.
const sweep_enough = 15 * std.time.ns_per_ms;

/// How many of the dimensions swept have to be long enough to time.
///
/// One guard drops a dimension too quick to time from its own assertion and
/// from the median at once, so a sweep can quietly shrink to a handful of
/// dimensions and go on printing a baseline. What that baseline hides is
/// arithmetic over how many dimensions it was taken over -- a regression
/// shared by half of a smaller sample is a regression the median follows --
/// so the sample has a floor and the sweep fails under it.
///
/// Four fifths of what was swept, rounded up, so a dimension added raises the
/// floor rather than buying room to lose one.
fn leastTimed(swept: usize) usize {
    return (swept * 4 + 4) / 5;
}

test "a sweep filter selects matching dimensions only" {
    try testing.expect(sweepSelected("locals in one body", "locals"));
    try testing.expect(!sweepSelected("newtype chain", "locals"));
    try testing.expect(sweepSelected("newtype chain", null));
}

test "a sweep filter that matches nothing is empty" {
    try testing.expectEqual(@as(usize, 0), selectedSweepCount("does-not-exist"));
}

test "a filter naming a kind of dimension selects at least one" {
    // A filter that selects nothing runs nothing, so a filter someone uses to
    // reach a kind of dimension is held to reaching at least one, whatever
    // else the table holds.
    for ([_][]const u8{ "body", "lending binders", "functions" }) |filter| {
        try testing.expect(selectedSweepCount(filter) >= 1);
    }
}

/// How a dimension's declared size is grown until its largest run is long
/// enough for the clock to say something about the compiler.
///
/// A run of a few tens of milliseconds is dominated by scheduler jitter on a
/// shared machine, which moves the slope by 0.1 or more with identical
/// allocation work. The declared `n` is therefore a minimum: it doubles until
/// the largest size (4n) takes `target_nanos`, and stops early where growth
/// would exceed `growth_cap` times the declared size or where the largest run
/// would allocate more than `allocation_cap` bytes, so the dimensions that are
/// already large are measured as declared. Calibration timing is taken from
/// the samples measured on the way and never enters a dimension's reading.
const Calibration = struct {
    target_nanos: u64,
    growth_cap: u32,
    allocation_cap: u64,
};

/// The target puts every dimension's largest run well above scheduler noise
/// while the whole sweep stays within a few minutes of its uncalibrated cost.
/// The allocation cap is 256 MiB of total allocation at the largest size, so a
/// grown dimension keeps a working set small enough to stay out of the cache
/// regime in which time grows faster than allocation. Dimensions already above
/// it are measured as declared.
const sweep_calibration: Calibration = .{
    .target_nanos = 120 * std.time.ns_per_ms,
    .growth_cap = 64,
    .allocation_cap = 256 << 20,
};

/// The size to measure next, given what the largest size cost at `n`.
///
/// `n` itself means calibration is finished: the largest run is long enough,
/// or doubling would pass a cap. Never less than `declared` and never more
/// than doubling `n`.
fn calibratedBase(calibration: Calibration, declared: u32, n: u32, top: Cost) u32 {
    if (n < declared) return declared;
    if (top.nanos >= calibration.target_nanos) return n;
    const doubled = @as(u64, n) * 2;
    if (doubled > @as(u64, declared) * calibration.growth_cap) return n;
    if (doubled * 4 > std.math.maxInt(u32)) return n;
    if (@as(u64, top.took) * 2 > calibration.allocation_cap) return n;
    return @intCast(doubled);
}

/// One balanced sample of `shape` at the size calibration settles on, which is
/// stored in `shape.n`. The last calibration sample is the returned sample,
/// so a dimension already long enough costs exactly one.
fn calibratedSample(
    gpa: std.mem.Allocator,
    io: std.Io,
    source: anytype,
    ordinal: usize,
    shape: *Dimension,
) !Curve {
    const declared = shape.n;
    var curve = try sampledCurve(gpa, io, source, ordinal, shape.*, sweep_ladder[0]);
    while (true) {
        const next = calibratedBase(sweep_calibration, declared, shape.n, curve[2]);
        if (!shape.grows or next == shape.n) return curve;
        shape.n = next;
        curve = try sampledCurve(gpa, io, source, ordinal, shape.*, sweep_ladder[0]);
    }
}

test "sweep calibration doubles a size whose largest run is below the target" {
    const c: Calibration = .{ .target_nanos = 100, .growth_cap = 64, .allocation_cap = 1 << 20 };
    try testing.expectEqual(@as(u32, 200), calibratedBase(c, 100, 100, .{ .took = 10, .nanos = 99 }));
    try testing.expectEqual(@as(u32, 800), calibratedBase(c, 100, 400, .{ .took = 10, .nanos = 1 }));
}

test "sweep calibration stops once the largest run reaches the target" {
    const c: Calibration = .{ .target_nanos = 100, .growth_cap = 64, .allocation_cap = 1 << 20 };
    try testing.expectEqual(@as(u32, 100), calibratedBase(c, 100, 100, .{ .took = 10, .nanos = 100 }));
    try testing.expectEqual(@as(u32, 400), calibratedBase(c, 100, 400, .{ .took = 10, .nanos = 5000 }));
}

test "sweep calibration respects the growth and allocation caps" {
    const c: Calibration = .{ .target_nanos = 100, .growth_cap = 8, .allocation_cap = 1000 };
    try testing.expectEqual(@as(u32, 800), calibratedBase(c, 100, 400, .{ .took = 10, .nanos = 1 }));
    try testing.expectEqual(@as(u32, 800), calibratedBase(c, 100, 800, .{ .took = 10, .nanos = 1 }));
    try testing.expectEqual(@as(u32, 100), calibratedBase(c, 100, 100, .{ .took = 501, .nanos = 1 }));
    try testing.expectEqual(@as(u32, 200), calibratedBase(c, 100, 100, .{ .took = 500, .nanos = 1 }));
    const wide: Calibration = .{ .target_nanos = 100, .growth_cap = 1 << 30, .allocation_cap = std.math.maxInt(u64) };
    try testing.expectEqual(@as(u32, 1 << 30), calibratedBase(wide, 1 << 30, 1 << 30, .{ .took = 1, .nanos = 1 }));
}

test "sweep calibration never returns less than the declared size and never shrinks" {
    const c: Calibration = .{ .target_nanos = 100, .growth_cap = 64, .allocation_cap = 1 << 20 };
    try testing.expectEqual(@as(u32, 100), calibratedBase(c, 100, 50, .{ .took = 1, .nanos = 1 }));
    var n: u32 = 7;
    var nanos: u64 = 1;
    while (nanos < 400) : (nanos *= 3) {
        const next = calibratedBase(c, 7, n, .{ .took = 1, .nanos = nanos });
        try testing.expect(next >= n and next <= n * 2);
        n = next;
    }
    // A longer run never asks for a larger size than a shorter one.
    var previous: u32 = std.math.maxInt(u32);
    var t: u64 = 0;
    while (t < 300) : (t += 17) {
        const next = calibratedBase(c, 10, 40, .{ .took = 1, .nanos = t });
        try testing.expect(next <= previous);
        previous = next;
    }
}

test "sweep calibration grows a dimension until its largest run reaches the target" {
    const Linear = struct {
        fn cost(_: std.mem.Allocator, _: std.mem.Allocator, _: std.Io, n: u32, _: usize) anyerror!Cost {
            return .{ .took = n * 100, .nanos = @as(u64, n) * 1000, .cpu_nanos = @as(u64, n) * 1000 };
        }
    };
    var source: DirectSweepSamples = .{};
    var shape: Dimension = .{ .name = "linear", .n = 1000, .cost = Linear.cost };
    const curve = try calibratedSample(testing.allocator, testing.io, &source, 0, &shape);
    // The largest run at 1000 takes 4ms and doubles until it reaches the
    // 120ms target at 32000 with 128ms, inside the 64x growth cap.
    try testing.expectEqual(@as(u32, 32000), shape.n);
    try testing.expectEqual(@as(u64, 4 * 32000 * 1000), curve[2].nanos);
}

test "sweep calibration leaves a bounded dimension at its declared size" {
    const Linear = struct {
        fn cost(_: std.mem.Allocator, _: std.mem.Allocator, _: std.Io, n: u32, _: usize) anyerror!Cost {
            return .{ .took = n, .nanos = n, .cpu_nanos = n };
        }
    };
    var source: DirectSweepSamples = .{};
    var shape: Dimension = .{ .name = "bounded", .n = 16, .grows = false, .cost = Linear.cost };
    _ = try calibratedSample(testing.allocator, testing.io, &source, 0, &shape);
    try testing.expectEqual(@as(u32, 16), shape.n);
}

/// Three sizes of one dimension, each twice the last.
const Curve = [3]Cost;

const sweep_sample_version = "linea-sweep-sample-v2";

fn writeSweepSample(writer: *std.Io.Writer, curve: Curve) !void {
    try writer.print("{s}", .{sweep_sample_version});
    for (curve) |cost| try writer.print(" {d} {d} {d}", .{ cost.took, cost.nanos, cost.cpu_nanos });
    try writer.writeByte('\n');
}

fn parseSweepSample(text: []const u8) !Curve {
    if (text.len == 0 or text[text.len - 1] != '\n') return error.InvalidSweepSample;
    var fields = std.mem.tokenizeScalar(u8, text[0 .. text.len - 1], ' ');
    if (!std.mem.eql(u8, fields.next() orelse return error.InvalidSweepSample, sweep_sample_version)) {
        return error.InvalidSweepSample;
    }

    var curve: Curve = undefined;
    for (&curve) |*cost| {
        cost.took = std.fmt.parseInt(usize, fields.next() orelse return error.InvalidSweepSample, 10) catch
            return error.InvalidSweepSample;
        cost.nanos = std.fmt.parseInt(u64, fields.next() orelse return error.InvalidSweepSample, 10) catch
            return error.InvalidSweepSample;
        cost.cpu_nanos = std.fmt.parseInt(u64, fields.next() orelse return error.InvalidSweepSample, 10) catch
            return error.InvalidSweepSample;
    }
    if (fields.next() != null) return error.InvalidSweepSample;
    return curve;
}

fn sampleFromRunResult(result: std.process.RunResult) !Curve {
    const exited = switch (result.term) {
        .exited => |code| code == 0,
        else => false,
    };
    if (!exited or result.stderr.len != 0) return error.SweepSampleFailed;
    return parseSweepSample(result.stdout);
}

fn writeSweepChildFailure(
    writer: *std.Io.Writer,
    dimension: []const u8,
    result: std.process.RunResult,
    err: anyerror,
) std.Io.Writer.Error!void {
    try writer.print("sweep: child for {s} returned {s}", .{ dimension, @errorName(err) });
    switch (result.term) {
        .exited => |code| if (code != 0) try writer.print(" after exit {d}", .{code}),
        .signal => |signal| try writer.print(" after signal {s}", .{@tagName(signal)}),
        .stopped => |signal| try writer.print(" after stop signal {s}", .{@tagName(signal)}),
        .unknown => |code| try writer.print(" after unknown termination {d}", .{code}),
    }
    if (result.stderr.len != 0) {
        try writer.print(": {s}", .{result.stderr});
    } else if (err == error.InvalidSweepSample and result.stdout.len != 0) {
        try writer.print(": {s}", .{result.stdout});
    }
    try writer.writeByte('\n');
}

fn printSweepChildFailure(
    dimension: []const u8,
    result: std.process.RunResult,
    err: anyerror,
) void {
    var buffer: [5 << 10]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    writeSweepChildFailure(&writer, dimension, result, err) catch {
        std.debug.print("sweep: child for {s} returned {s}\n", .{ dimension, @errorName(err) });
        return;
    };
    std.debug.print("{s}", .{writer.buffered()});
}

fn writeSweepAllocationFailure(writer: *std.Io.Writer, dimension: []const u8) std.Io.Writer.Error!void {
    try writer.print("sweep: {s} changed allocation work between samples\n", .{dimension});
}

fn printSweepAllocationFailure(dimension: []const u8) void {
    var buffer: [128]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    writeSweepAllocationFailure(&writer, dimension) catch {
        std.debug.print("sweep: a dimension changed allocation work between samples\n", .{});
        return;
    };
    std.debug.print("{s}", .{writer.buffered()});
}

fn ratio(after: u64, before: u64) f64 {
    return @as(f64, @floatFromInt(after)) / @as(f64, @floatFromInt(before));
}

/// The faster of two readings of one size, with the CPU time of that same run.
fn faster(a: Cost, b: Cost) Cost {
    if (a.cpu_nanos > 0 and b.cpu_nanos > 0) {
        return if (b.cpu_nanos < a.cpu_nanos) b else a;
    }
    return if (b.nanos < a.nanos) b else a;
}

fn requireSameAllocations(a: Curve, b: Curve) !void {
    for (a, b) |one, other| {
        if (one.took != other.took) return error.InconsistentSweepAllocation;
    }
}

fn balancedCurve(forward: Curve, reverse: Curve) !Curve {
    try requireSameAllocations(forward, reverse);
    var balanced: Curve = undefined;
    for (&balanced, forward, reverse) |*out, earlier, later| {
        out.* = faster(earlier, later);
    }
    return balanced;
}

fn curveSteepness(curve: Curve) f64 {
    const after = if (curve[2].cpu_nanos > 0) curve[2].cpu_nanos else curve[2].nanos;
    const before = if (curve[1].cpu_nanos > 0) curve[1].cpu_nanos else curve[1].nanos;
    return @log2(ratio(after, before));
}

/// The fastest reading of each size across `samples`, which allocate alike.
fn minimumCurve(samples: []const Curve) Curve {
    std.debug.assert(samples.len != 0);
    var best = samples[0];
    for (samples[1..]) |sample| {
        for (&best, sample) |*cost, other| cost.* = faster(cost.*, other);
    }
    return best;
}

/// What one input dimension cost at each of three sizes.
const Measured = struct {
    name: []const u8,
    n: u32,
    at: Curve,

    /// How many times the cost doubles per doubling of the input.
    ///
    /// Read off the later doubling rather than across both. A term the
    /// dimension carries is at least as visible at the larger size as at the
    /// smaller one -- a table sized by the program costs more of what the
    /// program is worth the more of it there is -- so nothing this gate looks
    /// for is quieter there.
    ///
    /// What is quieter there is everything else. The smallest of three readings
    /// is the one nearest the timer's floor and the one a fixed cost is the
    /// largest share of, and it is the one a cache knee sits under: a working
    /// set that fits a per-core cache at one size and not at its double reads
    /// that transition as a steep first doubling with a clean one behind it.
    /// Anchoring on it made a constant factor paid once look like a term paid
    /// per element.
    ///
    /// A machine's speed is a constant factor on both readings and cancels.
    /// What this costs is the averaging that three points bought, and the runs
    /// a doubted reading is measured again with are what pay for it.
    fn steepness(self: Measured) f64 {
        return curveSteepness(self.at);
    }

    /// Whether the smaller of the two readings it is judged on is long enough
    /// to divide.
    fn timed(self: Measured) bool {
        const t1 = if (self.at[1].cpu_nanos > 0) self.at[1].cpu_nanos else self.at[1].nanos;
        return t1 >= sweep_enough;
    }

    fn allocationWork(self: Measured) [2]f64 {
        return .{ ratio(self.at[1].took, self.at[0].took), ratio(self.at[2].took, self.at[1].took) };
    }

    fn time(self: Measured) [2]f64 {
        const t0 = if (self.at[0].cpu_nanos > 0) self.at[0].cpu_nanos else self.at[0].nanos;
        const t1 = if (self.at[1].cpu_nanos > 0) self.at[1].cpu_nanos else self.at[1].nanos;
        const t2 = if (self.at[2].cpu_nanos > 0) self.at[2].cpu_nanos else self.at[2].nanos;
        return .{ ratio(t1, t0), ratio(t2, t1) };
    }
};

/// What a linear doubling costs on the machine this run is on, and how much of
/// the run said so.
const Baseline = struct {
    /// The median of what the dimensions measured, which is the reading a
    /// dimension carrying no term of its own gives. A median rather than a
    /// mean so that the dimensions that do carry one -- which is what this
    /// sweep is looking for -- move it by nothing.
    steepness: f64,
    /// How many dimensions were long enough to time, which is how many the
    /// median was taken over and how many are held to it. A run that timed
    /// fewer is a run whose median speaks for less.
    timed: usize,
};

/// How steep a dimension may read before the run refuses it.
///
/// The tighter of the two bounds, because they answer different regressions:
/// one dimension that grew steeper than the rest of the run, and every
/// dimension growing steeper together.
fn allowedSteepness(baseline: Baseline) f64 {
    return @min(baseline.steepness + sweep_steepness_bound, sweep_steepest);
}

/// Whether this dimension read steeper than the run allows.
///
/// One statement of the question, because two things ask it: the report that
/// refuses a dimension, and the pass that measures one again before it is
/// reported. A second copy could select a dimension the report then passed, or
/// pass one the report then refused, and either reads as the clock.
fn overAllowed(m: Measured, baseline: Baseline) bool {
    return m.timed() and m.steepness() > allowedSteepness(baseline);
}

fn baselineOf(gpa: std.mem.Allocator, measured: []const Measured) !Baseline {
    const steep = try gpa.alloc(f64, measured.len);
    defer gpa.free(steep);
    var n: usize = 0;
    for (measured) |m| {
        if (!m.timed()) continue;
        steep[n] = m.steepness();
        n += 1;
    }
    if (n == 0) return .{ .steepness = 1.0, .timed = 0 };

    std.mem.sort(f64, steep[0..n], {}, std.sort.asc(f64));
    const middle = if (n % 2 == 1) steep[n / 2] else (steep[n / 2 - 1] + steep[n / 2]) / 2.0;
    return .{ .steepness = middle, .timed = n };
}

test "sweep baseline: every timed dimension contributes regardless of order" {
    var measured: [41]Measured = undefined;
    for (measured[0..20]) |*m| m.* = dimensionAt("lower", 0.8);
    for (measured[20..40]) |*m| m.* = dimensionAt("higher", 1.2);
    measured[40] = quickerThanTheClock("too quick");

    const baseline = try baselineOf(testing.allocator, &measured);
    try testing.expectEqual(@as(usize, 40), baseline.timed);
    try testing.expectApproxEqAbs(@as(f64, 1.0), baseline.steepness, 0.0001);

    std.mem.reverse(Measured, &measured);
    try testing.expectEqual(baseline, try baselineOf(testing.allocator, &measured));
}

test "sweep baseline: a large fully timed set meets the timing floor" {
    var measured: [41]Measured = undefined;
    for (&measured) |*m| m.* = dimensionAt("linear", 1.0);
    var failures: std.ArrayList(Failure) = .empty;
    defer failures.deinit(testing.allocator);
    try holdToBounds(testing.allocator, &failures, &measured);
    defer for (failures.items) |failure| {
        testing.allocator.free(failure.expected);
        testing.allocator.free(failure.actual);
    };
    try testing.expectEqual(@as(usize, 0), failures.items.len);
}

test "file sweep reclaims compilation storage before starting another compilation" {
    const Backing = struct {
        freed: bool = false,
        allocated_after_free: bool = false,

        fn allocator(self: *@This()) std.mem.Allocator {
            return .{ .ptr = self, .vtable = &.{ .alloc = alloc, .resize = resize, .remap = remap, .free = free } };
        }

        fn alloc(ctx: *anyopaque, len: usize, alignment: std.mem.Alignment, ra: usize) ?[*]u8 {
            const self: *@This() = @ptrCast(@alignCast(ctx));
            const memory = testing.allocator.rawAlloc(len, alignment, ra) orelse return null;
            self.allocated_after_free = self.allocated_after_free or self.freed;
            return memory;
        }

        fn resize(_: *anyopaque, memory: []u8, alignment: std.mem.Alignment, len: usize, ra: usize) bool {
            return testing.allocator.rawResize(memory, alignment, len, ra);
        }

        fn remap(_: *anyopaque, memory: []u8, alignment: std.mem.Alignment, len: usize, ra: usize) ?[*]u8 {
            return testing.allocator.rawRemap(memory, alignment, len, ra);
        }

        fn free(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, ra: usize) void {
            const self: *@This() = @ptrCast(@alignCast(ctx));
            testing.allocator.rawFree(memory, alignment, ra);
            self.freed = true;
        }
    };
    inline for (.{ modulesCost, earlyExitsCost }) |cost| {
        var backing: Backing = .{};
        _ = try sweepEndpoint(backing.allocator(), testing.io, .{
            .name = "file compilation lifetime",
            .n = 1,
            .cost = cost,
        }, 0);
        try testing.expect(backing.allocated_after_free);
    }
}

test "file sweep preserves accounting totals across timed compilations" {
    const files = [_]loader.InMemoryFile{
        .{ .path = "p/linea.json", .text = "{}\n" },
        .{ .path = "p/main.lin", .text = "fn main() -> UInt8 { 0 }\n" },
    };
    const accounting = try costOfFiles(testing.allocator, testing.io, "p/main.lin", &files, .accounting);
    const measured = try fastestOfFiles(testing.allocator, testing.io, "p/main.lin", &files, 2);
    try testing.expect(accounting.took > 0);
    try testing.expectEqual(accounting.took, measured.took);
}

test "file sweep rejected compilation releases backing storage" {
    inline for (.{ .accounting, .timing }) |mode| {
        var backing = testing.FailingAllocator.init(testing.allocator, .{});
        try testing.expectError(error.CostModuleRejected, costOfFiles(backing.allocator(), testing.io, "p/main.lin", &.{
            .{ .path = "p/linea.json", .text = "{}\n" },
            .{ .path = "p/main.lin", .text = "fn main() -> UInt8 { missing }\n" },
        }, mode));
        try testing.expect(backing.allocated_bytes > 0);
        try testing.expectEqual(backing.allocated_bytes, backing.freed_bytes);
    }
}

test "sweep endpoints reclaim scratch before measuring the next size" {
    const ScratchCost = struct {
        fn cost(a: std.mem.Allocator, _: std.mem.Allocator, _: std.Io, n: u32, _: usize) anyerror!Cost {
            // Each endpoint owns scratch that has no meaning after it returns.
            const scratch = try a.alloc(u8, 4096);
            @memset(scratch, 1);
            return .{ .took = n, .nanos = n, .cpu_nanos = n };
        }
    };
    // Enough backing for one endpoint, but not all six retained together.
    // Alignment keeps fixed-buffer padding out of the retained-byte assertion.
    var storage: [8192]u8 align(@alignOf(usize)) = undefined;
    var backing = std.heap.FixedBufferAllocator.init(&storage);
    const curve = try balancedSample(backing.allocator(), testing.io, .{
        .name = "scratch lifetime",
        .n = 1,
        .cost = ScratchCost.cost,
    });
    try testing.expectEqual(@as(usize, 0), backing.end_index);
    try testing.expectEqual(@as(u64, 4), curve[2].nanos);
}

test "sweep endpoints reclaim scratch when measurement fails" {
    const ScratchCost = struct {
        fn cost(a: std.mem.Allocator, _: std.mem.Allocator, _: std.Io, _: u32, _: usize) anyerror!Cost {
            _ = try a.alloc(u8, 4096);
            return error.CostModuleRejected;
        }
    };
    var storage: [8192]u8 align(@alignOf(usize)) = undefined;
    var backing = std.heap.FixedBufferAllocator.init(&storage);
    try testing.expectError(error.CostModuleRejected, balancedSample(backing.allocator(), testing.io, .{
        .name = "failed scratch lifetime",
        .n = 1,
        .cost = ScratchCost.cost,
    }));
    try testing.expectEqual(@as(usize, 0), backing.end_index);
}

test "a balanced curve keeps the faster reading of each size with its CPU time" {
    const forward: Curve = .{
        .{ .took = 100, .nanos = 50, .cpu_nanos = 40 },
        .{ .took = 200, .nanos = 150, .cpu_nanos = 120 },
        .{ .took = 400, .nanos = 500, .cpu_nanos = 480 },
    };
    const reverse: Curve = .{
        .{ .took = 100, .nanos = 175, .cpu_nanos = 160 },
        .{ .took = 200, .nanos = 100, .cpu_nanos = 90 },
        .{ .took = 400, .nanos = 400, .cpu_nanos = 320 },
    };

    const balanced = try balancedCurve(forward, reverse);
    try testing.expectEqual(@as(u64, 50), balanced[0].nanos);
    try testing.expectEqual(@as(u64, 100), balanced[1].nanos);
    try testing.expectEqual(@as(u64, 400), balanced[2].nanos);
    try testing.expectEqual(@as(u64, 40), balanced[0].cpu_nanos);
    try testing.expectEqual(@as(u64, 90), balanced[1].cpu_nanos);
    try testing.expectEqual(@as(u64, 320), balanced[2].cpu_nanos);
    try testing.expectError(error.InconsistentSweepAllocation, balancedCurve(forward, .{
        reverse[0], reverse[1], .{ .took = 401, .nanos = 1 },
    }));
}

test "a balanced curve preserves superlinear growth" {
    const forward: Curve = .{
        .{ .took = 100, .nanos = 50 },
        .{ .took = 200, .nanos = 150 },
        .{ .took = 400, .nanos = 520 },
    };
    const reverse: Curve = .{
        .{ .took = 100, .nanos = 175 },
        .{ .took = 200, .nanos = 300 },
        .{ .took = 400, .nanos = 650 },
    };

    const balanced = try balancedCurve(forward, reverse);
    const measured: Measured = .{ .name = "growing", .n = 100, .at = balanced };
    try testing.expect(measured.steepness() > sweep_steepest);
}

/// A curve of `base * size^exponent` with `disturbance` added to each size.
fn disturbedCurve(exponent: f64, disturbance: [3]u64) Curve {
    var curve: Curve = undefined;
    for (&curve, disturbance, 0..) |*cost, extra, i| {
        const size: f64 = @floatFromInt(@as(u64, 1) << @intCast(i));
        const true_nanos: u64 = @intFromFloat(25.0 * std.time.ns_per_ms * std.math.pow(f64, size, exponent));
        cost.* = .{ .took = @as(u64, 100) << @intCast(i), .nanos = true_nanos + extra };
    }
    return curve;
}

test "a minimum curve recovers the true cost from disturbed samples" {
    const quiet = disturbedCurve(1.0, .{ 0, 0, 0 });
    const samples = [_]Curve{
        disturbedCurve(1.0, .{ 30 * std.time.ns_per_ms, 0, 12 * std.time.ns_per_ms }),
        disturbedCurve(1.0, .{ 0, 25 * std.time.ns_per_ms, 40 * std.time.ns_per_ms }),
        disturbedCurve(1.0, .{ 9 * std.time.ns_per_ms, 7 * std.time.ns_per_ms, 0 }),
    };
    const reduced = minimumCurve(&samples);
    try testing.expectEqual(quiet, reduced);
    const measured: Measured = .{ .name = "linear", .n = 100, .at = reduced };
    try testing.expectApproxEqAbs(@as(f64, 1.0), measured.steepness(), 0.0001);
}

test "a minimum curve still reads a quadratic as quadratic under disturbance" {
    const samples = [_]Curve{
        disturbedCurve(2.0, .{ 14 * std.time.ns_per_ms, 3 * std.time.ns_per_ms, 22 * std.time.ns_per_ms }),
        disturbedCurve(2.0, .{ 0, 28 * std.time.ns_per_ms, 6 * std.time.ns_per_ms }),
        disturbedCurve(2.0, .{ 5 * std.time.ns_per_ms, 9 * std.time.ns_per_ms, 0 }),
    };
    const measured: Measured = .{ .name = "quadratic", .n = 100, .at = minimumCurve(&samples) };
    try testing.expect(measured.steepness() > 1.9 and measured.steepness() < 2.1);
    try testing.expect(measured.steepness() > sweep_steepest);
}

test "a minimum curve keeps the CPU time of the run it chose" {
    const samples = [_]Curve{
        .{
            .{ .took = 1, .nanos = 20, .cpu_nanos = 19 },
            .{ .took = 2, .nanos = 30, .cpu_nanos = 29 },
            .{ .took = 4, .nanos = 40, .cpu_nanos = 39 },
        },
        .{
            .{ .took = 1, .nanos = 10, .cpu_nanos = 9 },
            .{ .took = 2, .nanos = 50, .cpu_nanos = 49 },
            .{ .took = 4, .nanos = 60, .cpu_nanos = 59 },
        },
    };
    const reduced = minimumCurve(&samples);
    try testing.expectEqual(@as(u64, 9), reduced[0].cpu_nanos);
    try testing.expectEqual(@as(u64, 29), reduced[1].cpu_nanos);
    try testing.expectEqual(@as(u64, 39), reduced[2].cpu_nanos);
}

test "a sweep sample record round trips exactly" {
    const expected: Curve = .{
        .{ .took = 11, .nanos = 12, .cpu_nanos = 10 },
        .{ .took = 21, .nanos = 22, .cpu_nanos = 20 },
        .{ .took = 31, .nanos = 32, .cpu_nanos = 30 },
    };
    var out: std.Io.Writer.Allocating = .init(testing.allocator);
    defer out.deinit();
    try writeSweepSample(&out.writer, expected);
    try testing.expectEqualStrings(
        "linea-sweep-sample-v2 11 12 10 21 22 20 31 32 30\n",
        out.written(),
    );
    try testing.expectEqual(expected, try parseSweepSample(out.written()));
}

test "a sweep sample record rejects every malformed shape" {
    const malformed = [_][]const u8{
        "",
        "linea-sweep-sample-v1 1 2 3 4 5 6\n",
        "linea-sweep-sample-v2 1 2 1 3 4 3 5 6\n",
        "linea-sweep-sample-v2 1 2 1 3 4 3 5 6 5 7\n",
        "linea-sweep-sample-v2 1 2 1 3 4 3 5 6 five\n",
        "linea-sweep-sample-v2 1 2 1 3 4 3 5 6 18446744073709551616\n",
        "linea-sweep-sample-v2 1 2 1 3 4 3 5 6 5",
        "linea-sweep-sample-v2 1 2 1 3 4 3 5 6 5\ntrailing",
    };
    for (malformed) |record| {
        try testing.expectError(error.InvalidSweepSample, parseSweepSample(record));
    }
}

test "a successful quiet sweep child supplies one sample" {
    var stdout = "linea-sweep-sample-v2 11 12 10 21 22 20 31 32 30\n".*;
    var stderr: [0]u8 = .{};
    const got = try sampleFromRunResult(.{
        .term = .{ .exited = 0 },
        .stdout = &stdout,
        .stderr = &stderr,
    });
    try testing.expectEqual(@as(usize, 11), got[0].took);
    try testing.expectEqual(@as(u64, 32), got[2].nanos);
}

test "a sweep child must exit quietly with one valid sample" {
    var valid = "linea-sweep-sample-v2 1 2 1 3 4 3 5 6 5\n".*;
    var empty: [0]u8 = .{};
    var refused = "refused".*;
    var unexpected = "unexpected".*;
    var bad = "bad\n".*;

    try testing.expectError(error.SweepSampleFailed, sampleFromRunResult(.{
        .term = .{ .exited = 1 },
        .stdout = &valid,
        .stderr = &refused,
    }));
    try testing.expectError(error.SweepSampleFailed, sampleFromRunResult(.{
        .term = .{ .signal = .KILL },
        .stdout = &empty,
        .stderr = &empty,
    }));
    try testing.expectError(error.SweepSampleFailed, sampleFromRunResult(.{
        .term = .{ .exited = 0 },
        .stdout = &valid,
        .stderr = &unexpected,
    }));
    try testing.expectError(error.InvalidSweepSample, sampleFromRunResult(.{
        .term = .{ .exited = 0 },
        .stdout = &bad,
        .stderr = &empty,
    }));
}

test "a sweep child failure names its termination" {
    var empty: [0]u8 = .{};
    var refused = "refused".*;

    var exited: std.Io.Writer.Allocating = .init(testing.allocator);
    defer exited.deinit();
    try writeSweepChildFailure(&exited.writer, "functions", .{
        .term = .{ .exited = 42 },
        .stdout = &empty,
        .stderr = &refused,
    }, error.SweepSampleFailed);
    try testing.expectEqualStrings(
        "sweep: child for functions returned SweepSampleFailed after exit 42: refused\n",
        exited.written(),
    );

    var signalled: std.Io.Writer.Allocating = .init(testing.allocator);
    defer signalled.deinit();
    try writeSweepChildFailure(&signalled.writer, "modules", .{
        .term = .{ .signal = .KILL },
        .stdout = &empty,
        .stderr = &empty,
    }, error.SweepSampleFailed);
    try testing.expectEqualStrings(
        "sweep: child for modules returned SweepSampleFailed after signal KILL\n",
        signalled.written(),
    );

    var unknown: std.Io.Writer.Allocating = .init(testing.allocator);
    defer unknown.deinit();
    try writeSweepChildFailure(&unknown.writer, "traits", .{
        .term = .{ .unknown = 17 },
        .stdout = &empty,
        .stderr = &empty,
    }, error.SweepSampleFailed);
    try testing.expectEqualStrings(
        "sweep: child for traits returned SweepSampleFailed after unknown termination 17\n",
        unknown.written(),
    );
}

test "a sweep allocation disagreement names its dimension" {
    var out: std.Io.Writer.Allocating = .init(testing.allocator);
    defer out.deinit();
    try writeSweepAllocationFailure(&out.writer, "members");
    try testing.expectEqualStrings(
        "sweep: members changed allocation work between samples\n",
        out.written(),
    );
}

/// Says what every dimension cost, and holds each to the bounds.
///
/// Allocation work is asserted per doubling because it is counted and so reads
/// the same on every machine. The clock is asserted only through steepness and
/// printed at all three sizes so a person reading a run sees what the ratios
/// were taken over.
fn reportGrowth(
    gpa: std.mem.Allocator,
    failures: *std.ArrayList(Failure),
    measured: []const Measured,
) !void {
    const baseline = try baselineOf(gpa, measured);
    std.debug.print(
        "sweep: a linear doubling on this machine reads n^{d:.2}," ++
            " the median of the {d} of {d} dimensions long enough to time\n",
        .{ baseline.steepness, baseline.timed, measured.len },
    );

    for (measured) |m| {
        const allocation_work = m.allocationWork();
        const time = m.time();
        const steepness = m.steepness();

        std.debug.print(
            "sweep: {s: <18} {d: >6} -> {d: >6} -> {d: >6}   allocation work {d:.2}x {d:.2}x" ++
                "   totals {d} -> {d} -> {d} bytes" ++
                "   time {d:.2}x {d:.2}x   n^{d:.2}{s}   ({d}ms -> {d}ms -> {d}ms)\n",
            .{
                m.name,
                m.n,
                m.n * 2,
                m.n * 4,
                allocation_work[0],
                allocation_work[1],
                m.at[0].took,
                m.at[1].took,
                m.at[2].took,
                time[0],
                time[1],
                steepness,
                if (m.timed()) "" else " (too quick to hold to, raise its size or the calibration target)",
                @divTrunc(m.at[0].nanos, std.time.ns_per_ms),
                @divTrunc(m.at[1].nanos, std.time.ns_per_ms),
                @divTrunc(m.at[2].nanos, std.time.ns_per_ms),
            },
        );
    }

    try holdToBounds(gpa, failures, measured);
}

/// Every bound the sweep asserts, over readings already taken.
///
/// Apart from the report above so that what a set of readings is refused for
/// is a question with an answer, rather than something only a machine and
/// forty seconds can be asked.
fn holdToBounds(
    gpa: std.mem.Allocator,
    failures: *std.ArrayList(Failure),
    measured: []const Measured,
) !void {
    const baseline = try baselineOf(gpa, measured);

    if (baseline.timed < leastTimed(measured.len)) {
        try failures.append(gpa, .{
            .path = "the sweep",
            .what = "times enough of its dimensions to read a baseline from",
            .expected = try std.fmt.allocPrint(
                gpa,
                "at least {d} of {d} dimensions taking over {d}ms at their middle size",
                .{ leastTimed(measured.len), measured.len, sweep_enough / std.time.ns_per_ms },
            ),
            .actual = try std.fmt.allocPrint(
                gpa,
                "{d} of {d}.\nA dimension under that reads the timer and the process rather" ++
                    " than the compiler, so it is held to nothing and counts towards no" ++
                    " median -- and how much a median hides depends on how many dimensions" ++
                    " it was taken over.\nRaise the size of every dimension the report marks" ++
                    " too quick until its middle run takes longer than that.",
                .{ baseline.timed, measured.len },
            ),
        });
    }

    for (measured) |m| {
        const allocation_work = m.allocationWork();
        const time = m.time();
        const steepness = m.steepness();

        for (allocation_work, 0..) |grew_by, i| {
            if (grew_by <= sweep_allocation_work_bound) continue;
            try failures.append(gpa, .{
                .path = try std.fmt.allocPrint(gpa, "the front end, over {s}", .{m.name}),
                .what = "does no more allocation work than twice the program is worth",
                .expected = try std.fmt.allocPrint(
                    gpa,
                    "at most {d:.2}x allocation work",
                    .{sweep_allocation_work_bound},
                ),
                .actual = try std.fmt.allocPrint(
                    gpa,
                    "{d:.2}x allocation work from {d} to {d}",
                    .{ grew_by, m.n * (@as(u32, 1) << @intCast(i)), m.n * (@as(u32, 2) << @intCast(i)) },
                ),
            });
        }

        const allowed = allowedSteepness(baseline);
        if (!overAllowed(m, baseline)) continue;
        try failures.append(gpa, .{
            .path = try std.fmt.allocPrint(gpa, "the front end, over {s}", .{m.name}),
            .what = "costs one doubling per doubling of its input",
            .expected = try std.fmt.allocPrint(
                gpa,
                "n^{d:.2} at most.\nThe {d} dimensions this run timed read n^{d:.2} between" ++
                    " them, which is what one doubling costs on this machine, and a" ++
                    " dimension carrying no term of its own reads that plus at most" ++
                    " {d:.2}.\nAbove n^{d:.2} a dimension is refused whatever the rest of the" ++
                    " run reads, because a slowdown they all share moves that median with" ++
                    " it.",
                .{
                    allowed,
                    baseline.timed,
                    baseline.steepness,
                    sweep_steepness_bound,
                    sweep_steepest,
                },
            ),
            .actual = try std.fmt.allocPrint(
                gpa,
                "n^{d:.2} -- {d:.2}x then {d:.2}x per doubling, from the fastest" ++
                    " reading of each size over {d} balanced forward/reverse curve samples.\nThe measured slope" ++
                    " exceeds the bound. Inspect the dimension's compiler work and" ++
                    " measurement conditions to establish the cause.",
                .{ steepness, time[0], time[1], sweep_ladder[sweep_ladder.len - 1] },
            ),
        });
    }
}

/// A dimension that read `steepness`, at sizes long enough to time and doing
/// exactly twice the allocation work per doubling -- so the slope is the only
/// thing a bound can be reading.
fn dimensionAt(name: []const u8, steepness: f64) Measured {
    const smallest: f64 = @floatFromInt(sweep_enough * 2);
    var at: Curve = undefined;
    for (&at, 0..) |*cost, i| {
        const doublings: f64 = @floatFromInt(i);
        cost.* = .{
            .took = @as(usize, 1000) << @intCast(i),
            .nanos = @intFromFloat(smallest * std.math.pow(f64, 2.0, steepness * doublings)),
        };
    }
    return .{ .name = name, .n = 1000, .at = at };
}

/// The same dimension, too quick at its smallest size for the clock to say
/// anything about it.
fn quickerThanTheClock(name: []const u8) Measured {
    var m = dimensionAt(name, 1.0);
    for (&m.at) |*cost| cost.nanos = @divTrunc(cost.nanos, 100);
    return m;
}

test "a slowdown every dimension shares is still a slowdown" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    // What one shared routine getting slower looks like: every dimension
    // carries the same term, so the median carries it too and no dimension
    // sits above its own run.
    var measured: [10]Measured = undefined;
    for (&measured) |*m| m.* = dimensionAt("shared", sweep_steepest + 0.15);

    var failures: std.ArrayList(Failure) = .empty;
    try holdToBounds(gpa, &failures, &measured);
    try testing.expectEqual(@as(usize, 10), failures.items.len);
}

test "a dimension steeper than its siblings is refused under the ceiling" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    var measured: [10]Measured = undefined;
    for (&measured) |*m| m.* = dimensionAt("linear", 0.98);
    // Below the ceiling and above what the rest of the run reads, which is the
    // regression the median is there to see and the ceiling is not.
    measured[3] = dimensionAt("steeper", sweep_steepest - 0.03);

    var failures: std.ArrayList(Failure) = .empty;
    try holdToBounds(gpa, &failures, &measured);
    try testing.expectEqual(@as(usize, 1), failures.items.len);
    try testing.expect(std.mem.indexOf(u8, failures.items[0].path, "steeper") != null);
}

/// A dimension that reads exactly linear however many times it is run.
fn cleanlyLinear(gpa: std.mem.Allocator, backing: std.mem.Allocator, io: std.Io, n: u32, runs: usize) anyerror!Cost {
    _ = backing;
    _ = gpa;
    _ = io;
    _ = runs;
    const doublings = n / 1000;
    return .{ .took = 1000 * doublings, .nanos = sweep_enough * 2 * doublings };
}

const ScriptedSweepSamples = struct {
    curves: []const Curve,
    at: usize = 0,
    ordinals: [32]usize = undefined,

    fn one(
        self: *@This(),
        gpa: std.mem.Allocator,
        io: std.Io,
        ordinal: usize,
        dimension: Dimension,
    ) !Curve {
        _ = gpa;
        _ = io;
        _ = dimension;
        const at = self.at;
        self.ordinals[at] = ordinal;
        self.at += 1;
        if (at >= self.curves.len) return error.ScriptedSweepExhausted;
        return self.curves[at];
    }

    fn allocationFailure(self: *@This(), dimension: []const u8) void {
        _ = self;
        _ = dimension;
    }
};

test "sampled curves ask their source once per complete balanced sample" {
    const first = dimensionAt("first", 1.20).at;
    const second = dimensionAt("second", 1.00).at;
    const third = dimensionAt("third", 1.05).at;
    var source: ScriptedSweepSamples = .{ .curves = &.{ first, second, third } };
    const dimension: Dimension = .{ .name = "scripted", .n = 1000, .cost = cleanlyLinear };

    const got = try sampledCurve(testing.allocator, undefined, &source, 7, dimension, 3);
    try testing.expectEqual(@as(usize, 3), source.at);
    try testing.expectEqualSlices(usize, &.{ 7, 7, 7 }, source.ordinals[0..3]);
    try testing.expectEqual(second, got);
}

test "a filtered sweep asks its source in table order" {
    // Long enough at its largest size that calibration keeps the declared size.
    var linear = dimensionAt("linear", 1.00).at;
    for (&linear) |*cost| cost.nanos *= 4;
    var source: ScriptedSweepSamples = .{ .curves = &.{linear} };
    var failures: std.ArrayList(Failure) = .empty;
    defer failures.deinit(testing.allocator);

    try testing.expectError(
        error.ScriptedSweepExhausted,
        sweepShapesWith(
            testing.allocator,
            undefined,
            &failures,
            "body",
            &source,
        ),
    );
    // Two of the dimensions "body" selects were asked for before the script
    // ran out, each one the filter names, and in the order the table holds
    // them.
    try testing.expectEqual(@as(usize, 2), source.at);
    for (source.ordinals[0..2]) |ordinal| {
        try testing.expect(sweepSelected(sweep_dimensions[ordinal].name, "body"));
    }
    try testing.expect(source.ordinals[0] < source.ordinals[1]);
    try testing.expectEqual(@as(usize, 0), failures.items.len);
}

test "source-backed settling requests every three- and nine-sample retry and a final revisit" {
    const steep = dimensionAt("steep", 1.20);
    var curves: [21]Curve = undefined;
    for (&curves) |*curve| curve.* = steep.at;
    var source: ScriptedSweepSamples = .{ .curves = &curves };
    var measured = [_]Measured{steep};
    const dims = [_]Dimension{.{ .name = "steep", .n = 1000, .cost = cleanlyLinear }};
    const ordinals = [_]usize{7};

    try settleWith(
        testing.allocator,
        undefined,
        &source,
        &dims,
        &ordinals,
        &measured,
        sweep_ladder[1..],
    );
    try testing.expectEqual(@as(usize, 21), source.at);
    for (source.ordinals[0..21]) |ordinal| {
        try testing.expectEqual(@as(usize, 7), ordinal);
    }
    try testing.expectApproxEqAbs(@as(f64, 1.20), measured[0].steepness(), 0.0001);
}

test "a dimension that reads over its bound at every rung and under it at the final revisit passes" {
    const steep = dimensionAt("steep", 1.20);
    const linear = dimensionAt("linear", 1.00).at;
    var curves: [21]Curve = undefined;
    for (curves[0..12]) |*curve| curve.* = steep.at;
    for (curves[12..]) |*curve| curve.* = linear;
    var source: ScriptedSweepSamples = .{ .curves = &curves };
    var measured = [_]Measured{steep};
    const dims = [_]Dimension{.{ .name = "steep", .n = 1000, .cost = cleanlyLinear }};
    const ordinals = [_]usize{7};

    try settleWith(testing.allocator, undefined, &source, &dims, &ordinals, &measured, sweep_ladder[1..]);

    try testing.expectEqual(@as(usize, 21), source.at);
    try testing.expectApproxEqAbs(@as(f64, 1.0), measured[0].steepness(), 0.0001);
}

test "a final revisit that reads steeper than the rung before it does not replace it" {
    const rung = dimensionAt("rung", 1.17);
    const worse = dimensionAt("worse", 1.30).at;
    var curves: [21]Curve = undefined;
    for (curves[0..12]) |*curve| curve.* = rung.at;
    for (curves[12..]) |*curve| curve.* = worse;
    var source: ScriptedSweepSamples = .{ .curves = &curves };
    var measured = [_]Measured{rung};
    const dims = [_]Dimension{.{ .name = "rung", .n = 1000, .cost = cleanlyLinear }};
    const ordinals = [_]usize{7};

    try settleWith(testing.allocator, undefined, &source, &dims, &ordinals, &measured, sweep_ladder[1..]);

    try testing.expectApproxEqAbs(@as(f64, 1.17), measured[0].steepness(), 0.0001);
}

test "direct and source-backed settlement agree on a doubtful dimension" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    var measured: [10]Measured = undefined;
    for (&measured) |*m| m.* = dimensionAt("linear", 1.00);
    // One reading the clock spoiled: over what the rest of the run allows, and
    // linear when it is taken again.
    measured[3] = dimensionAt("contended", sweep_steepest + 0.05);

    var dims: [10]Dimension = undefined;
    for (&dims) |*d| d.* = .{ .name = "linear", .n = 1000, .cost = cleanlyLinear };

    var direct = measured;
    try settle(gpa, undefined, &dims, &direct, sweep_ladder[1..]);

    const linear = dimensionAt("linear", 1.00).at;
    var source: ScriptedSweepSamples = .{ .curves = &.{ linear, linear, linear } };
    const ordinals = [_]usize{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9 };
    try settleWith(gpa, undefined, &source, &dims, &ordinals, &measured, sweep_ladder[1..]);
    try testing.expectEqualSlices(Measured, &direct, &measured);
    try testing.expectEqualSlices(usize, &.{ 3, 3, 3 }, source.ordinals[0..3]);

    var failures: std.ArrayList(Failure) = .empty;
    try holdToBounds(gpa, &failures, &direct);
    try testing.expectEqual(@as(usize, 0), failures.items.len);
}

test "a dimension that reads the same again is refused" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    var measured: [10]Measured = undefined;
    for (&measured) |*m| m.* = dimensionAt("linear", 1.00);
    measured[3] = dimensionAt("steeper", sweep_steepest + 0.05);

    // What settling cannot do is make a dimension linear: this one costs what
    // it costs however many runs it is given, and the second reading is what
    // refuses it rather than what excuses it.
    var dims: [10]Dimension = undefined;
    for (&dims) |*d| d.* = .{ .name = "linear", .n = 1000, .cost = cleanlyLinear };
    dims[3] = .{ .name = "steeper", .n = 1000, .cost = steeplyGrowing };

    try settle(gpa, undefined, &dims, &measured, sweep_ladder[1..]);

    var failures: std.ArrayList(Failure) = .empty;
    try holdToBounds(gpa, &failures, &measured);
    try testing.expectEqual(@as(usize, 1), failures.items.len);
    try testing.expect(std.mem.indexOf(u8, failures.items[0].path, "steeper") != null);
}

test "settling closes over a baseline shift at the final rung" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    var measured: [10]Measured = undefined;
    for (measured[0..4]) |*m| m.* = dimensionAt("linear", 1.00);
    for (measured[4..8]) |*m| m.* = dimensionAt("warmer", 1.08);
    measured[8] = dimensionAt("revealed", 1.195);
    measured[9] = dimensionAt("first", 1.25);

    var dims: [10]Dimension = undefined;
    for (&dims) |*d| d.* = .{ .name = "linear", .n = 1000, .cost = cleanlyLinear };
    var curves: [18]Curve = undefined;
    const linear = dimensionAt("linear", 1.00).at;
    for (&curves) |*curve| curve.* = linear;
    var source: ScriptedSweepSamples = .{ .curves = &curves };
    const ordinals = [_]usize{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9 };

    try settleWith(gpa, undefined, &source, &dims, &ordinals, &measured, sweep_ladder[2..]);

    try testing.expectEqual(@as(usize, 18), source.at);
    try testing.expectEqualSlices(usize, &.{ 9, 9, 9, 9, 9, 9, 9, 9, 9 }, source.ordinals[0..9]);
    try testing.expectEqualSlices(usize, &.{ 8, 8, 8, 8, 8, 8, 8, 8, 8 }, source.ordinals[9..18]);
    try testing.expectApproxEqAbs(@as(f64, 1.0), measured[8].steepness(), 0.0001);
    try testing.expectApproxEqAbs(@as(f64, 1.0), measured[9].steepness(), 0.0001);
}

test "settling refuses allocation-work changes between retry rungs" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    var measured: [10]Measured = undefined;
    for (&measured) |*m| m.* = dimensionAt("linear", 1.00);
    measured[3] = dimensionAt("steeper", 1.20);
    measured[3].at[0].took += 1;

    var dims: [10]Dimension = undefined;
    for (&dims) |*d| d.* = .{ .name = "linear", .n = 1000, .cost = cleanlyLinear };

    try testing.expectError(
        error.InconsistentSweepAllocation,
        settle(gpa, undefined, &dims, &measured, sweep_ladder[2..]),
    );
}

/// A dimension that reads steeper than any run allows, however many times it
/// is run.
fn steeplyGrowing(gpa: std.mem.Allocator, backing: std.mem.Allocator, io: std.Io, n: u32, runs: usize) anyerror!Cost {
    _ = backing;
    _ = gpa;
    _ = io;
    _ = runs;
    const doublings: f64 = @floatFromInt(n / 1000);
    const smallest: f64 = @floatFromInt(sweep_enough * 2);
    return .{
        .took = 1000 * (n / 1000),
        .nanos = @intFromFloat(smallest * std.math.pow(f64, doublings, sweep_steepest + 0.05)),
    };
}

/// A dimension whose cost steps once between two sizes and grows cleanly after.
///
/// The ratios `copies in one body` has read on a shared runner: a first
/// doubling of 2.79 with a clean 2.06 behind it.
fn steppedOnce(name: []const u8) Measured {
    var m = dimensionAt(name, 1.00);
    const smallest: f64 = @floatFromInt(m.at[0].nanos);
    m.at[1].nanos = @intFromFloat(smallest * 2.79);
    m.at[2].nanos = @intFromFloat(smallest * 2.79 * 2.06);
    return m;
}

test "a step between two sizes is not a term the dimension carries" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    var measured: [10]Measured = undefined;
    for (&measured) |*m| m.* = dimensionAt("linear", 1.00);
    // A working set that fits a cache at one size and not at its double is a
    // constant factor between two points, and a constant factor is not a term:
    // it is paid once and never again, which is what the doubling behind it
    // says.
    measured[3] = steppedOnce("stepped");

    var failures: std.ArrayList(Failure) = .empty;
    try holdToBounds(gpa, &failures, &measured);
    try testing.expectEqual(@as(usize, 0), failures.items.len);
}

test "a term that only shows at the larger size is refused" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    var measured: [10]Measured = undefined;
    for (&measured) |*m| m.* = dimensionAt("linear", 1.00);

    // The shape a table sized by the program has: linear while the program is
    // small enough that the table is not what it costs, and steeper once it is.
    // What a step and this have in common is one doubling that reads clean, and
    // which one it is is the whole difference.
    var growing = dimensionAt("growing", 1.00);
    const smallest: f64 = @floatFromInt(growing.at[0].nanos);
    growing.at[1].nanos = @intFromFloat(smallest * 2.0);
    growing.at[2].nanos = @intFromFloat(smallest * 2.0 * 2.6);
    measured[3] = growing;

    var failures: std.ArrayList(Failure) = .empty;
    try holdToBounds(gpa, &failures, &measured);
    try testing.expectEqual(@as(usize, 1), failures.items.len);
    try testing.expect(std.mem.indexOf(u8, failures.items[0].path, "growing") != null);
}

test "the allocation bound names the work it measures" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    var measured = [_]Measured{dimensionAt("allocation", 1.00)};
    measured[0].at[1].took = measured[0].at[0].took * 3;

    var failures: std.ArrayList(Failure) = .empty;
    try holdToBounds(gpa, &failures, &measured);
    try testing.expectEqual(@as(usize, 1), failures.items.len);
    try testing.expectEqualStrings(
        "does no more allocation work than twice the program is worth",
        failures.items[0].what,
    );
}

test "a median taken over too few dimensions speaks for too little" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    var measured: [10]Measured = undefined;
    for (&measured) |*m| m.* = dimensionAt("linear", 1.00);
    for (measured[0..3]) |*m| m.* = quickerThanTheClock("too quick");

    var failures: std.ArrayList(Failure) = .empty;
    try holdToBounds(gpa, &failures, &measured);
    try testing.expectEqual(@as(usize, 1), failures.items.len);
    try testing.expectEqualStrings("the sweep", failures.items[0].path);
}

/// What the front end costs per dimension, and how that cost grows.
///
/// The property below asserts allocation work, which is the same number on
/// every machine and is why it can be asserted at all. What it cannot see is a
/// walk inside a walk: quadratic in time, linear in allocation work, allocating
/// nothing as it goes. That shape has been the real defect nine times, and every
/// one of them ran past a green suite.
///
/// So this sweeps the clock as well, at three sizes rather than two, and what
/// it asserts is the doubling between the largest two rather than any duration.
/// A duration carries the machine in it: the same tree reads 2.22x per doubling
/// on one box and 2.69x on a slower one. What the doubling is held against is
/// therefore measured beside it, from the median of every dimension in the same
/// run -- a machine that makes one doubling dear makes all of them dear, and the
/// median is what a dimension with no term of its own reads.
///
/// Three sizes and not two, though only two are divided: the smallest is what
/// says whether the two above it are past the fixed costs and past the knee a
/// cache puts between one size and its double, and a dimension is sized by what
/// it reads there.
///
/// The clock is still the clock, so a reading in doubt is bought with more
/// complete curve samples than one that is not. Each sample runs sizes in both
/// directions to balance frequency drift, and the fastest reading of each size
/// over several samples rejects an interruption, which only ever adds time. This
/// is a step of its own and not part of `zig build test` for the same reason --
/// a gate that fails on a busy machine teaches everyone to re-run it, and the
/// suite is the wrong place to learn that habit.
///
/// One shape is a floor and not a net. Many small functions and one enormous
/// function are different curves, and a table sized by the program only shows
/// up on the first; a search over implementations only shows up where there
/// are many. Every dimension here is one a real defect was found on.
const sweep_dimensions = [_]Dimension{
    .{ .name = "functions", .n = 8000, .cost = throughTheTree(wideModule) },
    .{ .name = "implementations", .n = 6000, .cost = throughTheTree(implModule) },
    .{ .name = "postfix calls across types", .n = 4000, .cost = throughTheTree(distinctPostfixCallsModule) },
    .{ .name = "postfix calls sharing a name", .n = 4000, .cost = throughTheTree(sharedPostfixCallsModule) },
    .{ .name = "failed postfix calls across traits", .n = 2000, .cost = throughTreeBatch(failedPostfixCallsModule, .{ .refused = .t_unknown_operation }, 1) },
    .{ .name = "refused bounded calls", .n = 16000, .cost = throughTreeBatch(refusedBoundedCallsModule, .{ .refused = .t_bound }, 1) },
    .{ .name = "traits", .n = 6000, .cost = throughTheTree(traitModule) },
    .{ .name = "members", .n = 6000, .cost = throughTheTree(memberModule) },
    .{ .name = "trait member pairing", .n = 8000, .cost = throughTheTree(traitMemberPairingModule) },
    .{ .name = "distinct bound shapes", .n = 2000, .cost = throughTheTree(distinctBoundShapesModule) },
    .{ .name = "bounds on one parameter", .n = 4000, .cost = throughTheTree(boundsOnOneParameterModule) },
    .{ .name = "nested alias implementations", .n = 400, .cost = throughTreeBatch(nestedAliasImplementationsModule, .{ .refused = .n_duplicate }, 16) },
    .{ .name = "nested alias bounds", .n = 400, .cost = throughTreeBatch(nestedAliasBoundsModule, .check, 8) },
    .{ .name = "generic alias path heads", .n = 4000, .cost = throughTheTree(genericAliasHeadsModule) },
    .{ .name = "callable head implementations", .n = 2000, .cost = throughTheTree(callableHeadsModule) },
    .{ .name = "coherence open arguments", .n = 1000, .cost = throughTheTree(openCoherenceModule) },
    .{ .name = "coherence ground arguments", .n = 1000, .cost = throughTheTree(groundCoherenceModule) },
    .{ .name = "coherence open later argument", .n = 1000, .cost = throughTheTree(openLaterCoherenceModule) },
    .{ .name = "coherence ground later argument", .n = 1000, .cost = throughTheTree(groundLaterCoherenceModule) },
    .{ .name = "parameter coherence separate traits", .n = 1000, .cost = throughTheTree(separateParameterCoherenceModule) },
    .{ .name = "parameter coherence nominal receivers", .n = 4000, .cost = throughTheTree(nominalParameterCoherenceModule) },
    .{ .name = "editor reference families", .n = 8000, .cost = referenceFamilyCost },
    .{ .name = "editor diagnostic publication", .n = 1000, .cost = diagnosticPublicationCost },
    .{ .name = "editor qualified completion", .n = 500, .cost = qualifiedCompletionCost },
    .{ .name = "callable enum payloads", .n = 4000, .cost = throughTheTree(callableEnumModule) },
    .{ .name = "match arms", .n = 4000, .cost = throughTheTree(matchArmsModule) },
    .{ .name = "variants in one enum", .n = 1000, .cost = throughTheTree(wideEnumModule) },
    .{ .name = "arms that each bind", .n = 2000, .cost = throughTheTree(bindingArmsModule) },
    .{ .name = "two wide columns", .n = 1000, .cost = throughTheTree(twoWideColumnsModule) },
    .{ .name = "pattern depth", .n = 400, .cost = throughTreeBatch(patternDepthModule, .check, 1) },
    .{ .name = "function values settled in one function", .n = 4000, .cost = throughTheTree(openFunctionValuesModule) },
    .{ .name = "function values settled across functions", .n = 4000, .cost = throughTheTree(functionValueBodiesModule) },
    .{ .name = "constructor payload fields", .n = 2000, .cost = throughTheTree(constructorPayloadFieldsModule) },
    .{ .name = "aggregate constant defaults", .n = 1000, .cost = throughTheTree(aggregateConstantsModule) },
    .{ .name = "aggregate constant forward table", .n = 5000, .cost = throughTheTree(forwardAggregateTableModule) },
    .{ .name = "borrowed constants", .n = 2000, .cost = throughTheTree(borrowedConstantsModule) },
    .{ .name = "generic helper depth", .n = 1000, .cost = throughTheTree(genericHelperDepthModule) },
    .{ .name = "generic helper width", .n = 500, .cost = throughTheTree(genericHelperWidthModule) },
    .{ .name = "generic helper suppliers", .n = 2000, .cost = throughTheTree(genericHelperSuppliersModule) },
    .{ .name = "generic parameter origin depth", .n = 8, .grows = false, .cost = throughTreeBatch(genericOriginDepthModule, .emit, 128) },
    .{ .name = "generic shared DAG checking", .n = 8, .cost = throughTreeBatch(genericSharedDagModule, .check, 128) },
    .{ .name = "generic trait-selected shared DAG checking", .n = 8, .cost = throughTreeBatch(genericTraitSelectedSharedDagModule, .check, 128) },
    .{ .name = "generic positive cycle checking", .n = 500, .cost = throughTreeBatch(genericPositiveCycleModule, .{ .refused = .t_poly_rec }, 1) },
    .{ .name = "locals in one body", .n = 16000, .cost = throughTheTree(deepModule) },
    .{ .name = "conditional loop exits", .n = 8000, .cost = throughTheTree(conditionalLoopExitsModule) },
    .{ .name = "small ownership deltas", .n = 2000, .cost = throughTheTree(smallOwnershipDeltasModule) },
    .{ .name = "heavy ownership deltas", .n = 2000, .cost = throughTheTree(heavyOwnershipDeltasModule) },
    .{ .name = "deferred bindings across joins", .n = 2000, .cost = throughTheTree(deferredBindingsAcrossJoinsModule) },
    .{ .name = "deferred bindings under nested loops", .n = 200, .grows = false, .cost = throughTreeBatch(deferredBindingsUnderNestedLoopsModule, .check, 128) },
    .{ .name = "lending binders", .n = 1100, .cost = throughTheTree(lendingBindersModule) },
    .{ .name = "views taken and lent in one body", .n = 3000, .cost = throughTheTree(storage_mod.viewsProgram) },
    .{ .name = "views held in one struct and ended in turn", .n = 2000, .cost = throughTheTree(storage_mod.wideViewsProgram) },
    .{ .name = "views held in one struct and ended last first", .n = 4000, .cost = throughTheTree(storage_mod.wideViewsEndedLastFirstProgram) },
    .{ .name = "instantiations", .n = 8000, .cost = throughTheTree(instanceModule) },
    .{ .name = "newtype chain", .n = 16000, .cost = throughTheTree(newtypeChainModule) },
    .{ .name = "fields in one type", .n = 16000, .cost = throughTheTree(fieldModule) },
    .{ .name = "reflected components", .n = 4000, .cost = throughTheTree(reflectionComponentsModule) },
    .{ .name = "construction product width", .n = 2000, .cost = throughTheTree(constructionProductModule) },
    .{ .name = "construction repeated derives", .n = 1000, .cost = throughTheTree(constructionDerivesModule) },
    .{ .name = "derive group entries", .n = 4000, .cost = throughTheTree(deriveGroupEntriesModule) },
    .{ .name = "generic derive predicates", .n = 20000, .cost = throughTheTree(genericDerivePredicatesModule) },
    .{ .name = "component requirement components", .n = 8000, .cost = throughTheTree(componentRequirementComponentsModule) },
    .{ .name = "component requirements", .n = 8000, .cost = throughTheTree(componentRequirementsModule) },
    .{ .name = "component requirement rows", .n = 160000, .cost = throughTheTree(componentRequirementRowsModule) },
    .{ .name = "template member parameters", .n = 6000, .cost = throughTheTree(templateMemberParametersModule) },
    .{ .name = "copies in one body", .n = 6000, .cost = throughTheTree(copyModule) },
    .{ .name = "array slot replacements", .n = 4000, .cost = throughTheTree(knownArrayReplacementModule) },
    .{ .name = "conditional array replacements", .n = 4000, .cost = throughTheTree(conditionalArrayReplacementModule) },
    // The 1500/3000/6000 curve crosses the x86 runners' cache knee at its
    // last point (two independent runners read 2.70x and 2.72x there).
    // Start beyond it, as every other cache-sensitive shape above does.
    .{ .name = "carrier fields x bindings", .n = 8000, .cost = throughTheTree(carrierFieldBindingsModule) },
    // Sized past the cache knee, for the reason the table states above.
    .{ .name = "modules", .n = 8000, .cost = modulesCost },
    .{ .name = "early exits", .n = 6000, .cost = earlyExitsCost },
    .{ .name = "erased closures", .n = 2000, .cost = erasedClosuresCost },
    .{ .name = "reflected enum cases", .n = 16, .grows = false, .cost = throughTheTree(reflectedEnumCasesModule) },
    .{ .name = "reflected enum payloads", .n = 4000, .cost = throughTheTree(reflectedEnumPayloadsModule) },
    .{ .name = "reflected ordinal operations", .n = 2000, .cost = throughTheTree(reflectedOrdinalOperationsModule) },
    .{ .name = "structural supertrait constraints", .n = 1000, .cost = throughTheTree(structuralSupertraitConstraintsModule) },
    .{ .name = "dependency reads across joins", .n = 512, .cost = throughTheTree(dependencyReadsModule) },
    .{ .name = "independent observation owners", .n = 4000, .cost = throughTheTree(independentObservationsModule) },
    .{ .name = "places lent inout across reads", .n = 2000, .cost = throughTheTree(inoutLendsModule) },
    .{ .name = "fields of one place lent inout across reads", .n = 1000, .cost = throughTheTree(inoutFieldLendsModule) },
    .{ .name = "borrowed temporaries across statements", .n = 2000, .cost = throughTheTree(borrowedTemporariesModule) },
    .{ .name = "delegated array wrappers", .n = 4000, .cost = throughTheLoader(delegatedWrappersModule) },
    .{ .name = "tuple destructures in one body", .n = 16000, .cost = throughTheLoader(tupleDestructuresModule) },
    .{ .name = "tuple instantiations", .n = 8000, .cost = throughTheLoader(tupleInstanceModule) },
    .{ .name = "derived structs", .n = 3000, .cost = throughTheLoader(derivedStructsModule) },
    .{ .name = "derived structs compared", .n = 1800, .cost = throughTheLoader(derivedStructsComparedModule) },
};

fn sweepSelected(name: []const u8, filter: ?[]const u8) bool {
    const wanted = filter orelse return true;
    return std.mem.indexOf(u8, name, wanted) != null;
}

test "every sweep dimension compiles at a small size" {
    // The sweep runs in its own CI lane, after a pull request is otherwise
    // ready, and a generator the language has moved away from fails there
    // as a timing gate. Each one is compiled here at a size small enough to
    // cost nothing, so it fails beside the change that broke it.
    for (sweep_dimensions) |dimension| {
        const n = @min(dimension.n, 4);
        _ = dimension.cost(testing.allocator, testing.allocator, testing.io, n, 0) catch |err| {
            std.debug.print("sweep dimension \"{s}\" at n={d}: {s}\n", .{ dimension.name, n, @errorName(err) });
            return err;
        };
    }
}

fn selectedSweepCount(filter: ?[]const u8) usize {
    var count: usize = 0;
    for (sweep_dimensions) |dimension| {
        if (sweepSelected(dimension.name, filter)) count += 1;
    }
    return count;
}

fn selectSweepDimensions(
    shapes: []Dimension,
    ordinals: []usize,
    filter: ?[]const u8,
) usize {
    std.debug.assert(shapes.len == ordinals.len);
    var selected: usize = 0;
    for (sweep_dimensions, 0..) |dimension, ordinal| {
        if (!sweepSelected(dimension.name, filter)) continue;
        shapes[selected] = dimension;
        ordinals[selected] = ordinal;
        selected += 1;
    }
    return selected;
}

fn sweepShapesWith(
    gpa: std.mem.Allocator,
    io: std.Io,
    failures: *std.ArrayList(Failure),
    filter: ?[]const u8,
    source: anytype,
) !void {
    // Each declared size is a minimum, grown by `calibratedSample` until the
    // largest of its three takes the calibration target. Sized so the smallest
    // of each three takes tens of milliseconds, for two reasons with the same fix. Below tens of
    // milliseconds the reading is the timer and the process, not the
    // compiler. And every point of a dimension must sit on the same side of
    // the machine's cache knee: a base whose working set fits one machine's
    // per-core cache while its double does not reads that constant-factor
    // transition as a superlinear first doubling -- observed at a base of
    // 4000 on dedicated x86 cores, where the first ratio read 2.5-2.6 with a
    // clean 2.0 behind it, while a machine with larger caches read the same
    // tree clean at every point.
    const shapes = try gpa.alloc(Dimension, selectedSweepCount(filter));
    defer gpa.free(shapes);
    const ordinals = try gpa.alloc(usize, shapes.len);
    defer gpa.free(ordinals);
    const selected = selectSweepDimensions(shapes, ordinals, filter);
    std.debug.assert(selected == shapes.len);

    // Every dimension is measured before any is judged: what a linear
    // doubling costs is read off the run rather than assumed, so the readings
    // have to be in hand together.
    const measured = try gpa.alloc(Measured, shapes.len);
    defer gpa.free(measured);
    for (shapes, measured, ordinals) |*shape, *m, ordinal| {
        const at = try calibratedSample(gpa, io, source, ordinal, shape);
        m.* = .{ .name = shape.name, .n = shape.n, .at = at };
    }

    try settleWith(gpa, io, source, shapes, ordinals, measured, sweep_ladder[1..]);
    try reportGrowth(gpa, failures, measured);
}

/// Held editor requests grow with the unrelated workspace, while each answer
/// remains one importable function. Loading and index preparation are outside
/// the interval; each request has its own message allocation lifetime.
const QualifiedCompletionFixture = struct {
    const text = "fn main() -> UInt8 {\n    catalog.needle()\n}\n";

    directory: []const u8,
    root: [:0]const u8,
    checked: lsp_analysis.Analysis,
    index: lsp_workspace.Index,

    fn init(gpa: std.mem.Allocator, io: std.Io, checked_library: *const loader.CheckedLibrary, n: u32) !QualifiedCompletionFixture {
        const directory = try std.fmt.allocPrint(gpa, ".zig-cache/tmp/qualified-completion-{d}-{d}", .{
            n, std.Io.Clock.awake.now(io).nanoseconds,
        });
        errdefer gpa.free(directory);
        try std.Io.Dir.cwd().createDirPath(io, directory);
        errdefer std.Io.Dir.cwd().deleteTree(io, directory) catch {};
        const dir = try std.Io.Dir.cwd().openDir(io, directory, .{});
        defer dir.close(io);
        try dir.writeFile(io, .{ .sub_path = "linea.json", .data = "{}\n" });
        try dir.writeFile(io, .{ .sub_path = "main.lin", .data = text });
        try dir.createDirPath(io, "catalog");
        try dir.writeFile(io, .{ .sub_path = "catalog/item.lin", .data = "pub fn needle() -> UInt8 { 1 }\n" });
        for (0..n) |i| {
            const module = try std.fmt.allocPrint(gpa, "other{d:0>6}", .{i});
            defer gpa.free(module);
            try dir.createDirPath(io, module);
            const file = try std.fs.path.join(gpa, &.{ module, "item.lin" });
            defer gpa.free(file);
            try dir.writeFile(io, .{ .sub_path = file, .data = "pub fn unrelated() -> UInt8 { 0 }\n" });
        }
        const root = try std.Io.Dir.cwd().realPathFileAlloc(io, directory, gpa);
        errdefer gpa.free(root);
        const main_path = try std.fs.path.join(gpa, &.{ root, "main.lin" });
        defer gpa.free(main_path);
        var checked = try lsp_analysis.of(gpa, gpa, checked_library, &.{.{ .path = main_path, .text = text }}, root);
        errdefer checked.deinit();
        const index = try lsp_workspace.Index.build(gpa, io, root);
        return .{ .directory = directory, .root = root, .checked = checked, .index = index };
    }

    fn deinit(self: *QualifiedCompletionFixture, gpa: std.mem.Allocator, io: std.Io) void {
        self.index.deinit();
        self.checked.deinit();
        std.Io.Dir.cwd().deleteTree(io, self.directory) catch {};
        gpa.free(self.root);
        gpa.free(self.directory);
    }

    fn answer(self: *const QualifiedCompletionFixture, gpa: std.mem.Allocator, query: lsp_workspace.Query) !void {
        const position = lsp.offsets.indexToPosition(text, std.mem.indexOf(u8, text, "needle").? + 2, .@"utf-16");
        const result = try lsp_completion.forPosition(gpa, &self.checked, self.checked.program.primaryFile(), position, .@"utf-16", query, self.root, .unsupported) orelse
            return error.CostModuleRejected;
        const items = result.completion_list.items;
        if (items.len != 1 or !std.mem.eql(u8, items[0].label, "needle")) return error.CostModuleRejected;
        const detail = items[0].detail orelse return error.CostModuleRejected;
        if (!std.mem.eql(u8, detail, "pub fn needle() -> UInt8")) return error.CostModuleRejected;
        const edits = items[0].additionalTextEdits orelse return error.CostModuleRejected;
        if (edits.len != 1 or !std.mem.startsWith(u8, edits[0].newText, "import catalog\n"))
            return error.CostModuleRejected;
    }
};

fn qualifiedCompletionCost(gpa: std.mem.Allocator, backing: std.mem.Allocator, io: std.Io, n: u32, runs: usize) !Cost {
    _ = backing;
    const checked_library = try loader.CheckedLibrary.init(gpa);
    defer checked_library.deinit();
    var fixture = try QualifiedCompletionFixture.init(gpa, io, checked_library, n);
    defer fixture.deinit(gpa, io);
    const query = try fixture.index.query();
    if (fixture.index.entries.items.len != @as(usize, n) + 1) return error.CostModuleRejected;

    // Batch held requests so the interval is measurable with a small workspace.
    const requests = @as(usize, n) * 128;
    var best: Cost = .{ .took = 0, .nanos = std.math.maxInt(u64) };
    for (0..runs) |_| {
        var counting: Counting = .{ .under = gpa };
        const timer = CostTimer.start(io);
        for (0..requests) |_| {
            var message = std.heap.ArenaAllocator.init(gpa);
            defer message.deinit();
            counting.under = message.allocator();
            try fixture.answer(counting.allocator(), query);
        }
        const cost = timer.finish(io, counting.took);
        if (best.nanos != std.math.maxInt(u64) and best.took != counting.took)
            return error.InconsistentSweepAllocation;
        if (cost.nanos < best.nanos) best = cost;
    }
    return best;
}

test "qualified completion sweep holds one answer across unrelated modules" {
    var fixture = try QualifiedCompletionFixture.init(testing.allocator, testing.io, test_library.get(), 3);
    defer fixture.deinit(testing.allocator, testing.io);
    const query = try fixture.index.query();
    try testing.expectEqual(@as(usize, 4), fixture.index.entries.items.len);
    try testing.expectEqual(@as(usize, 1), fixture.checked.sink.items().len);
    try testing.expectEqual(diagnostic.Code.n_undefined, fixture.checked.sink.items()[0].code);
    try testing.expectEqual(@as(usize, 1), query.modulesNamed(fixture.root, "catalog").len);
    var message = std.heap.ArenaAllocator.init(testing.allocator);
    defer message.deinit();
    try fixture.answer(message.allocator(), query);
}

/// Family queries over held analysis, excluding compilation and cursor lookup.
fn referenceFamilyCost(gpa: std.mem.Allocator, backing: std.mem.Allocator, io: std.Io, n: u32, runs: usize) !Cost {
    _ = backing;
    const text = try implModule(gpa, n);
    defer gpa.free(text);
    const checked_library = try loader.CheckedLibrary.init(gpa);
    defer checked_library.deinit();
    var checked = try lsp_analysis.of(gpa, gpa, checked_library, &.{.{ .path = "main.lin", .text = text }}, "main.lin");
    defer checked.deinit();
    if (checked.sink.hasErrors()) return error.CostModuleRejected;
    const offset = std.mem.indexOf(u8, text, "fn of").? + 3;
    const position = lsp.offsets.indexToPosition(text, offset, .@"utf-16");
    const named = lsp_references.namedAt(&checked, checked.fileNamed("main.lin").?, position, .@"utf-16");
    if (named == .none) return error.CostModuleRejected;

    var best: Cost = .{ .took = 0, .nanos = std.math.maxInt(u64) };
    for (0..runs) |_| {
        var counting: Counting = .{ .under = gpa };
        const timer = CostTimer.start(io);
        // Each editor request owns an arena. Releasing it between queries
        // keeps temporary buffers out of later requests' working sets.
        // Batch held queries so the middle size exceeds the timing floor.
        for (0..2048) |_| {
            var message = std.heap.ArenaAllocator.init(gpa);
            defer message.deinit();
            counting.under = message.allocator();
            const family = try lsp_references.spelledAlike(counting.allocator(), &checked, named);
            defer counting.allocator().free(family);
            if (family.len != @as(usize, n) + 1) return error.CostModuleRejected;
        }
        const cost = timer.finish(io, counting.took);
        if (best.nanos != std.math.maxInt(u64) and best.took != counting.took) return error.InconsistentSweepAllocation;
        if (cost.nanos < best.nanos) best = cost;
    }
    return best;
}

fn diagnosticPublicationFiles(gpa: std.mem.Allocator, n: u32) ![]loader.InMemoryFile {
    var files: std.ArrayList(loader.InMemoryFile) = .empty;
    errdefer {
        for (files.items) |file| {
            gpa.free(file.path);
            gpa.free(file.text);
        }
        files.deinit(gpa);
    }
    var entry_text: std.Io.Writer.Allocating = .init(gpa);
    defer entry_text.deinit();
    for (0..n) |i| try entry_text.writer.print("import m{d}\n", .{i});
    try entry_text.writer.writeAll("fn main() -> UInt8 {\n");
    for (0..n) |i| try entry_text.writer.print("    let _ = m{d}.value()\n", .{i});
    try entry_text.writer.writeAll("    missing_main\n}\n");

    {
        const path = try gpa.dupe(u8, "p/main.lin");
        errdefer gpa.free(path);
        const text = try entry_text.toOwnedSlice();
        errdefer gpa.free(text);
        try files.append(gpa, .{ .path = path, .text = text });
    }
    for (0..n) |i| {
        const path = try std.fmt.allocPrint(gpa, "p/m{d}/body.lin", .{i});
        errdefer gpa.free(path);
        const text = try gpa.dupe(u8, "pub fn value() -> UInt8 { missing_value }\n");
        errdefer gpa.free(text);
        try files.append(gpa, .{ .path = path, .text = text });
    }
    return files.toOwnedSlice(gpa);
}

fn diagnosticPublicationCost(gpa: std.mem.Allocator, backing: std.mem.Allocator, io: std.Io, n: u32, runs: usize) !Cost {
    _ = backing;
    const files = try diagnosticPublicationFiles(gpa, n);
    defer {
        for (files) |file| {
            gpa.free(file.path);
            gpa.free(file.text);
        }
        gpa.free(files);
    }
    const checked_library = try loader.CheckedLibrary.init(gpa);
    defer checked_library.deinit();
    var checked = try lsp_analysis.of(gpa, gpa, checked_library, files, "p");
    defer checked.deinit();
    const expected: usize = @as(usize, n) + 1;
    const per_file = try gpa.alloc(u32, checked.table.count());
    defer gpa.free(per_file);
    @memset(per_file, 0);
    if (checked.sink.items().len != expected) return error.CostModuleRejected;
    for (checked.sink.items()) |*d| {
        if (d.code != .n_undefined) return error.CostModuleRejected;
        const primary = d.primaryLabel() orelse return error.CostModuleRejected;
        per_file[primary.file.index()] += 1;
    }
    var validated: usize = 0;
    var validate_files = lsp_publish.files(&checked.program);
    while (validate_files.next()) |file| {
        if (per_file[file.index()] != 1) return error.CostModuleRejected;
        validated += 1;
    }
    if (validated != expected) return error.CostModuleRejected;

    var best: Cost = .{ .took = 0, .nanos = std.math.maxInt(u64) };
    for (0..runs) |_| {
        var counting: Counting = .{ .under = gpa };
        const timer = CostTimer.start(io);
        // Keep the middle interval above the sweep timing floor without enlarging the workspace.
        for (0..64) |_| {
            var message = std.heap.ArenaAllocator.init(gpa);
            defer message.deinit();
            // Charge publication's logical requests, not repeated exact
            // growth of the arena's already allocated backing buffer.
            counting.under = message.allocator();
            const a = counting.allocator();
            const publication = try lsp_publish.Publication.init(a, &checked);
            var published: usize = 0;
            var it = lsp_publish.files(&checked.program);
            while (it.next()) |file| {
                const diagnostics = try publication.forFile(a, file, .@"utf-16");
                if (diagnostics.len != 1 or diagnostics[0].code == null or
                    !std.mem.eql(u8, diagnostics[0].code.?.string, "N-Undefined"))
                    return error.CostModuleRejected;
                published += 1;
            }
            if (published != expected) return error.CostModuleRejected;
        }
        const cost = timer.finish(io, counting.took);
        if (best.nanos != std.math.maxInt(u64) and best.took != counting.took)
            return error.InconsistentSweepAllocation;
        if (cost.nanos < best.nanos) best = cost;
    }
    return best;
}

test "diagnostic publication sweep reports one error from every imported module" {
    const files = try diagnosticPublicationFiles(testing.allocator, 3);
    defer {
        for (files) |file| {
            testing.allocator.free(file.path);
            testing.allocator.free(file.text);
        }
        testing.allocator.free(files);
    }
    var checked = try lsp_analysis.of(testing.allocator, testing.allocator, test_library.get(), files, "p");
    defer checked.deinit();
    try testing.expectEqual(@as(usize, 4), checked.sink.items().len);
    var message = std.heap.ArenaAllocator.init(testing.allocator);
    defer message.deinit();
    const publication = try lsp_publish.Publication.init(message.allocator(), &checked);
    var it = lsp_publish.files(&checked.program);
    var count: usize = 0;
    while (it.next()) |file| {
        const diagnostics = try publication.forFile(message.allocator(), file, .@"utf-16");
        try testing.expectEqual(@as(usize, 1), diagnostics.len);
        try testing.expectEqualStrings("N-Undefined", diagnostics[0].code.?.string);
        count += 1;
    }
    try testing.expectEqual(@as(usize, 4), count);
}

fn modulesCost(gpa: std.mem.Allocator, backing: std.mem.Allocator, io: std.Io, n: u32, runs: usize) anyerror!Cost {
    const files = try moduleProgram(gpa, n);
    defer {
        for (files) |f| {
            gpa.free(f.path);
            gpa.free(f.text);
        }
        gpa.free(files);
    }
    return fastestOfFiles(backing, io, "p/main.lin", files, runs);
}

/// What a program of many early exits costs at one size.
///
/// Through the loader, because `?` is written against `Option` and that comes
/// from the standard library, which the tree path does not load.
fn earlyExitsCost(gpa: std.mem.Allocator, backing: std.mem.Allocator, io: std.Io, n: u32, runs: usize) anyerror!Cost {
    const text = try exitModule(gpa, n);
    defer gpa.free(text);
    const files = [_]loader.InMemoryFile{
        .{ .path = "p/linea.json", .text = "{}\n" },
        .{ .path = "p/main.lin", .text = text },
    };
    return fastestOfFiles(backing, io, "p/main.lin", &files, runs);
}

/// What a program keeping `n` distinct closures in `mem.Closure` costs.
///
/// Through the loader, because `mem.Closure` is the standard library's. Each
/// closure has a type of its own, so each opens its own instantiation of
/// `Closure.open` and needs its own generated entry and release: discovery
/// and lowering must spend a constant amount per closure, not per program.
fn erasedClosuresCost(gpa: std.mem.Allocator, backing: std.mem.Allocator, io: std.Io, n: u32, runs: usize) anyerror!Cost {
    const text = try erasedClosuresModule(gpa, n);
    defer gpa.free(text);
    const files = [_]loader.InMemoryFile{
        .{ .path = "p/linea.json", .text = "{}\n" },
        .{ .path = "p/main.lin", .text = text },
    };
    return fastestOfFiles(backing, io, "p/main.lin", &files, runs);
}

/// `n` functions, each keeping a closure with its own capture in a
/// `mem.Closure`, calling it, and releasing it.
fn erasedClosuresModule(gpa: std.mem.Allocator, n: u32) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    const w = &out.writer;
    try w.writeAll("import std.mem\nimport std.release\n\nuse release.Release\n\n");
    for (0..n) |i| try w.print(
        "fn step{d}(seed: UInt64) -> UInt64 {{\n" ++
            "    let bump: UInt64 = {d}\n" ++
            "    let kept = mem.Closure.open([sink bump] |value: UInt64| -> UInt64 {{ value + bump }}).unwrap()\n" ++
            "    let answer = kept(seed)\n" ++
            "    kept.release()\n" ++
            "    answer\n" ++
            "}}\n\n",
        .{ i, i },
    );
    try w.writeAll("fn main() -> UInt8 {\n");
    for (0..n) |i| try w.print("    let _answer{d} = step{d}(0)\n", .{ i, i });
    try w.writeAll("    0\n}\n");
    return out.toOwnedSlice();
}

test "the erased closure sweep module compiles" {
    const text = try erasedClosuresModule(testing.allocator, 3);
    defer testing.allocator.free(text);
    const files = [_]loader.InMemoryFile{
        .{ .path = "p/linea.json", .text = "{}\n" },
        .{ .path = "p/main.lin", .text = text },
    };
    const cost = try costOfFiles(testing.allocator, testing.io, "p/main.lin", &files, .accounting);
    try testing.expect(cost.took > 0);
}

test "the tuple sweep modules compile" {
    for ([_]*const fn (std.mem.Allocator, u32) anyerror![]u8{ &tupleDestructuresModule, &tupleInstanceModule }) |make| {
        const text = try make(testing.allocator, 3);
        defer testing.allocator.free(text);
        const files = [_]loader.InMemoryFile{
            .{ .path = "p/linea.json", .text = "{}\n" },
            .{ .path = "p/main.lin", .text = text },
        };
        const cost = try costOfFiles(testing.allocator, testing.io, "p/main.lin", &files, .accounting);
        try testing.expect(cost.took > 0);
    }
}

test "the sweep holds both tuple dimensions" {
    try testing.expectEqual(@as(usize, 2), selectedSweepCount("tuple"));
}

/// What one module costs through the loader, which supplies the standard
/// library beside it. A tuple's type is declared there and the tree path loads
/// none, so a tuple on that path is refused as `[T-Literal]`.
fn throughTheLoader(
    comptime make: fn (std.mem.Allocator, u32) anyerror![]u8,
) *const fn (std.mem.Allocator, std.mem.Allocator, std.Io, u32, usize) anyerror!Cost {
    return &struct {
        fn cost(gpa: std.mem.Allocator, backing: std.mem.Allocator, io: std.Io, n: u32, runs: usize) anyerror!Cost {
            const text = try make(gpa, n);
            defer gpa.free(text);
            const files = [_]loader.InMemoryFile{
                .{ .path = "p/linea.json", .text = "{}\n" },
                .{ .path = "p/main.lin", .text = text },
            };
            return fastestOfFiles(backing, io, "p/main.lin", &files, runs);
        }
    }.cost;
}

/// `n` tuple literals taken apart in one body, each by its own pattern.
///
/// A pattern's binders each ask the tuple's declaration for the component they
/// name, once per binder, so a body of many patterns is where a lookup that
/// scans the declaration's fields or the body's bindings would show.
fn tupleDestructuresModule(gpa: std.mem.Allocator, n: u32) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    const w = &out.writer;

    try w.writeAll("fn main() -> UInt8 {\n");
    for (0..n) |i| try w.print("    let (a{d}, b{d}) = (UInt8({d}), true)\n", .{ i, i, i % 7 });
    for (0..n) |i| try w.print("    let _ = a{d}\n    let _ = b{d}\n", .{ i, i });
    try w.writeAll("    0\n}\n");
    return out.toOwnedSlice();
}

/// `n` distinct pair types, each returned from a function and bound.
///
/// Every `(UInt8, S{k})` is its own instance of `Tuple2`, so discovery and
/// lowering must spend a constant amount per instance and not per program. No
/// structure derives a trait: each derived implementation is one more supplier
/// of that trait's members for every call dispatched through it, which is a
/// cost of its own that a pair type should not be measured against.
fn tupleInstanceModule(gpa: std.mem.Allocator, n: u32) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    const w = &out.writer;

    for (0..n) |k| try w.print(
        "struct S{d} {{\n    v: UInt8,\n}}\n\n" ++
            "fn f{d}() -> (UInt8, S{d}) {{\n    (1, S{d} {{ v = 0 }})\n}}\n\n",
        .{ k, k, k, k },
    );
    try w.writeAll("fn main() -> UInt8 {\n");
    for (0..n) |k| try w.print("    let _pair{d} = f{d}()\n", .{ k, k });
    try w.writeAll("    0\n}\n");
    return out.toOwnedSlice();
}

/// `n` structures that each derive `Equatable`, none of them compared.
///
/// Every derived implementation is one more supplier of the trait's members,
/// so a pass that visits every supplier for each generic body it reaches pays
/// for the program once per structure.
fn derivedStructsModule(gpa: std.mem.Allocator, n: u32) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    const w = &out.writer;

    for (0..n) |k| try w.print("@derive(Equatable)\nstruct S{d} {{\n    v: UInt8,\n}}\n\n", .{k});
    try w.writeAll("fn main() -> UInt8 {\n    0\n}\n");
    return out.toOwnedSlice();
}

/// `n` structures that each derive `Equatable`, each compared once with `==`.
fn derivedStructsComparedModule(gpa: std.mem.Allocator, n: u32) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    const w = &out.writer;

    for (0..n) |k| try w.print(
        "@derive(Equatable)\nstruct S{d} {{\n    v: UInt8,\n}}\n\n" ++
            "fn same{d}(a: S{d}, b: S{d}) -> Bool {{\n    a == b\n}}\n\n",
        .{ k, k, k, k },
    );
    try w.writeAll("fn main() -> UInt8 {\n");
    for (0..n) |k| try w.print("    let _same{d} = same{d}(S{d} {{ v = 0 }}, S{d} {{ v = 1 }})\n", .{ k, k, k, k });
    try w.writeAll("    0\n}\n");
    return out.toOwnedSlice();
}

test "the sweep holds both derived-structure dimensions" {
    try testing.expectEqual(@as(usize, 2), selectedSweepCount("derived structs"));
    for ([_]u32{ 4, 8 }) |n| {
        inline for (.{ derivedStructsModule, derivedStructsComparedModule }) |make| {
            const source = try make(testing.allocator, n);
            defer testing.allocator.free(source);
            const files = [_]loader.InMemoryFile{
                .{ .path = "p/linea.json", .text = "{}\n" },
                .{ .path = "p/main.lin", .text = source },
            };
            _ = try costOfFiles(testing.allocator, testing.io, "p/main.lin", &files, .accounting);
        }
    }
}

/// One balanced sample of what a dimension costs at each of its three sizes.
///
/// The sizes run forward and backward. Every endpoint then occupies
/// complementary positions in the run, so frequency drift over a hot machine
/// scales both sides of a doubling instead of steepening one side.
fn balancedSample(gpa: std.mem.Allocator, io: std.Io, dim: Dimension) !Curve {
    var forward: Curve = undefined;
    for (&forward, 0..) |*cost, i| {
        cost.* = try sweepEndpoint(gpa, io, dim, i);
    }

    var reverse: Curve = undefined;
    var i: usize = reverse.len;
    while (i != 0) {
        i -= 1;
        reverse[i] = try sweepEndpoint(gpa, io, dim, i);
    }
    return balancedCurve(forward, reverse);
}

// Match a compiler invocation's arena lifetime. A completed endpoint must not
// leave its compiler data resident while the next input size is measured.
fn sweepEndpoint(backing: std.mem.Allocator, io: std.Io, dim: Dimension, index: usize) !Cost {
    var scratch = std.heap.ArenaAllocator.init(backing);
    defer scratch.deinit();
    return dim.cost(scratch.allocator(), backing, io, dim.n * (@as(u32, 1) << @intCast(index)), 1);
}

const DirectSweepSamples = struct {
    fn one(
        self: *@This(),
        gpa: std.mem.Allocator,
        io: std.Io,
        ordinal: usize,
        dimension: Dimension,
    ) !Curve {
        _ = self;
        _ = ordinal;
        return balancedSample(gpa, io, dimension);
    }

    fn allocationFailure(self: *@This(), dimension: []const u8) void {
        _ = self;
        _ = dimension;
    }
};

const ProcessSweepSamples = struct {
    executable: []const u8,
    tests_dir: []const u8,

    fn one(
        self: *@This(),
        gpa: std.mem.Allocator,
        io: std.Io,
        ordinal: usize,
        dimension: Dimension,
    ) !Curve {
        const named = try std.fmt.allocPrint(gpa, "{d}", .{ordinal});
        defer gpa.free(named);
        const base = try std.fmt.allocPrint(gpa, "{d}", .{dimension.n});
        defer gpa.free(base);
        const result = std.process.run(gpa, io, .{
            .argv = &.{ self.executable, self.tests_dir, "--sweep-sample", named, "--sweep-base", base },
            .stdout_limit = .limited(4 << 10),
            .stderr_limit = .limited(4 << 10),
        }) catch |err| {
            std.debug.print("sweep: could not run child for {s}: {s}\n", .{ dimension.name, @errorName(err) });
            return err;
        };
        defer {
            gpa.free(result.stdout);
            gpa.free(result.stderr);
        }
        const sample = sampleFromRunResult(result) catch |err| {
            printSweepChildFailure(dimension.name, result, err);
            return err;
        };
        // Report outside the measured child intervals, retaining every retry's evidence.
        std.debug.print("sweep sample: {s} wall_ns={d},{d},{d} cpu_ns={d},{d},{d}\n", .{
            dimension.name,
            sample[0].nanos,
            sample[1].nanos,
            sample[2].nanos,
            sample[0].cpu_nanos,
            sample[1].cpu_nanos,
            sample[2].cpu_nanos,
        });
        return sample;
    }

    fn allocationFailure(self: *@This(), dimension: []const u8) void {
        _ = self;
        printSweepAllocationFailure(dimension);
    }
};

/// What a dimension costs, as the fastest reading of each size over complete
/// balanced samples.
fn sampledCurve(
    gpa: std.mem.Allocator,
    io: std.Io,
    source: anytype,
    ordinal: usize,
    dimension: Dimension,
    samples: usize,
) !Curve {
    const curves = try gpa.alloc(Curve, samples);
    defer gpa.free(curves);

    for (curves, 0..) |*curve, sample| {
        curve.* = try source.one(gpa, io, ordinal, dimension);
        if (sample != 0) requireSameAllocations(curves[0], curve.*) catch |err| {
            source.allocationFailure(dimension.name);
            return err;
        };
    }
    return minimumCurve(curves);
}

/// Measures again every dimension the readings in hand would refuse.
///
/// The clock is the one thing here a second reading can disagree with, and a
/// dimension over its bound is the one place the disagreement decides
/// anything -- so that is where the runs are spent, and a run that refuses
/// nothing pays for none of them.
fn settleWith(
    gpa: std.mem.Allocator,
    io: std.Io,
    source: anytype,
    dims: []const Dimension,
    ordinals: ?[]const usize,
    measured: []Measured,
    ladder: []const usize,
) !void {
    if (ordinals) |held| std.debug.assert(held.len == dims.len);
    const retried = try gpa.alloc(bool, measured.len);
    defer gpa.free(retried);

    for (ladder) |runs| {
        @memset(retried, false);
        while (true) {
            // A replacement can lower the median and reveal another doubtful
            // dimension, so close over the baseline before moving up a rung.
            const baseline = try baselineOf(gpa, measured);
            var measured_again = false;
            for (dims, measured, retried, 0..) |dim, *m, *was_retried, at| {
                if (was_retried.* or !overAllowed(m.*, baseline)) continue;
                const ordinal = if (ordinals) |held| held[at] else at;
                const again = try sampledCurve(gpa, io, source, ordinal, dim, runs);
                requireSameAllocations(m.at, again) catch |err| {
                    source.allocationFailure(dim.name);
                    return err;
                };
                m.at = again;
                was_retried.* = true;
                measured_again = true;
            }
            if (!measured_again) break;
        }

        const baseline = try baselineOf(gpa, measured);
        var anything_doubted = false;
        for (measured) |m| {
            if (overAllowed(m, baseline)) anything_doubted = true;
        }
        if (!anything_doubted) break;
    }

    if (ladder.len != 0) try revisitWith(gpa, io, source, dims, ordinals, measured, ladder[ladder.len - 1]);
}

/// Reads once more, after every other dimension has been read again, each
/// dimension the readings in hand still refuse, and keeps the less steep of
/// the two curves.
///
/// The rungs above measure a doubtful dimension again straight away, so a
/// slow stretch on a shared machine -- another tenant's cache or memory
/// traffic -- lasts through all of them and the fastest of nine back-to-back
/// samples agrees with itself while being wrong. A reading taken after the
/// rest of the run has gone by does not share that stretch. The lower curve is
/// the one that lost the least to the machine, which is why `fastestOf` keeps
/// the smallest run as well; a dimension that really costs more than its bound
/// reads over it every time, so it is still refused.
fn revisitWith(
    gpa: std.mem.Allocator,
    io: std.Io,
    source: anytype,
    dims: []const Dimension,
    ordinals: ?[]const usize,
    measured: []Measured,
    runs: usize,
) !void {
    const baseline = try baselineOf(gpa, measured);
    for (dims, measured, 0..) |dim, *m, at| {
        if (!overAllowed(m.*, baseline)) continue;
        const ordinal = if (ordinals) |held| held[at] else at;
        const again = try sampledCurve(gpa, io, source, ordinal, dim, runs);
        requireSameAllocations(m.at, again) catch |err| {
            source.allocationFailure(dim.name);
            return err;
        };
        var candidate = m.*;
        candidate.at = again;
        if (candidate.steepness() < m.steepness()) m.* = candidate;
    }
}

fn settle(
    gpa: std.mem.Allocator,
    io: std.Io,
    dims: []const Dimension,
    measured: []Measured,
    ladder: []const usize,
) !void {
    var source: DirectSweepSamples = .{};
    return settleWith(gpa, io, &source, dims, null, measured, ladder);
}

/// The fastest of `runs` runs over one module.
///
/// Allocation work is counted and is the same every time; elapsed time is
/// measured, and the smallest reading is the run that lost the least to
/// whatever else the machine was doing.
fn fastestOf(gpa: std.mem.Allocator, io: std.Io, text: []const u8, runs: usize) !Cost {
    // One compilation with backing growth refused fixes the allocation metric,
    // as a file-based cost's accounting run does; timing keeps ordinary
    // allocator policy.
    const accounting = try treeCostGrowing(gpa, io, text, .emit, false);
    var best = try costOf(gpa, io, text);
    best.took = accounting.took;
    for (1..@max(runs, 1)) |_| {
        const again = try costOf(gpa, io, text);
        if (again.nanos < best.nanos) {
            best.nanos = again.nanos;
            best.cpu_nanos = again.cpu_nanos;
        }
    }
    return best;
}

/// The front end does allocation work proportional to its input, and no more.
///
/// Twice the program takes about twice the allocation work. A table a pass
/// holds per function but sizes by the whole program breaks that, and it is
/// invisible to every case in the corpus, which averages 450 bytes -- at that
/// size a quadratic and a linear are the same number.
///
/// A ratio and not a ceiling. A ceiling loose enough not to fail on a slow
/// machine only catches what is already a disaster; a ratio is self-normalising,
/// so it can be tight enough to catch the step from linear to quadratic before
/// it becomes one. What the ratio is taken over is counted rather than measured,
/// so it is the same number on every machine.
///
/// The wall clock is reported and not asserted. It read 5.83x against a 4.0x
/// bound on a loaded machine and passed on the next run against an identical
/// tree, and a gate that fails on a busy machine teaches everyone to re-run it
/// -- which is how the next real regression gets re-run too.
///
/// So this is a floor rather than a net, and what it does not catch is a pass
/// quadratic in time and linear in allocation work: the walk inside a walk,
/// which is how "which declarations does this `impl` hold" was once answered.
/// `sweepShapes` below is what covers that shape -- three sizes per input
/// dimension, and the doubling between the largest two held against what the
/// run's other dimensions read -- and a change to what a pass costs is held to
/// that rather than to this.
///
/// Not a case under `tests/`: a case says what the language means, and this
/// says what the compiler costs. It is also outside the outcome cache
/// deliberately -- a pass that gets slower emits the same IR, so a cached
/// answer is exactly what a regression would produce.
/// Holds this process's own peak to a ceiling, once, at the end of a run.
///
/// The allocation-work questions here are asked about the compiler; this memory
/// question is about the asker. The runner reached the whole of a CI machine's
/// memory with every check green, because a floor exists for every property and
/// no ceiling existed for the process -- a climb with no assertion over it is
/// invisible until the kernel ends it, and the kernel names no cause.
///
/// The ceiling is five times the peak a full run measures today, so platform
/// variance and honest growth never trip it: what it catches is the class
/// where the run costs the sum of the corpus rather than its largest member,
/// which lands at thirty gigabytes and not at eight.
fn runnerPeakBytes() u64 {
    const ru = std.posix.getrusage(std.posix.rusage.SELF);
    // What `maxrss` counts differs by kernel: Linux reports kilobytes, the
    // BSDs and macOS report bytes.
    return switch (builtin.os.tag) {
        .linux => @as(u64, @intCast(ru.maxrss)) * 1024,
        else => @intCast(ru.maxrss),
    };
}

/// The most a whole run may hold: more than any walk has a reason to.
const runner_peak_limit: u64 = 8 << 30;

fn checkPeak(gpa: std.mem.Allocator, failures: *std.ArrayList(Failure)) !void {
    const peak = runnerPeakBytes();

    const ceiling = runner_peak_limit;
    std.debug.print("conformance: the runner itself peaked at {d} MB\n", .{peak >> 20});
    if (peak <= ceiling) return;

    try failures.append(gpa, .{
        .path = "the runner",
        .what = "holds more memory than a run has any reason to",
        .expected = try std.fmt.allocPrint(gpa, "a peak under {d} MB", .{ceiling >> 20}),
        .actual = try std.fmt.allocPrint(gpa, "{d} MB resident at its highest", .{peak >> 20}),
    });
}

fn checkCost(
    gpa: std.mem.Allocator,
    io: std.Io,
    failures: *std.ArrayList(Failure),
) !void {
    // Large enough that the passes dominate what one process costs to start,
    // and small enough that a linear compiler runs both in well under a second.
    const n: u32 = 2000;

    const small = try wideModule(gpa, n);
    defer gpa.free(small);
    const large = try wideModule(gpa, n * 2);
    defer gpa.free(large);

    const a = try costOf(gpa, io, small);
    const b = try costOf(gpa, io, large);

    // Twice the input, and the fixed cost every compilation pays is what keeps
    // the counted ratio under two rather than at it.
    const allocation_work_bound = 2.5;

    const grew_by = @as(f64, @floatFromInt(b.took)) / @as(f64, @floatFromInt(a.took));
    const slowed_by = @as(f64, @floatFromInt(b.nanos)) / @as(f64, @floatFromInt(a.nanos));

    // Printed beside the number that is asserted, so a person reading a run
    // sees the shape the clock is in without a build turning on the load
    // average.
    std.debug.print(
        "cost: the front end grew {d:.2}x in allocation work and took {d:.2}x the time" ++
            " for twice the program -- {d} allocation-work bytes and {d}ms at {d} functions," ++
            " {d} and {d}ms at {d}\n",
        .{
            grew_by,
            slowed_by,
            a.took,
            @divTrunc(a.nanos, std.time.ns_per_ms),
            n,
            b.took,
            @divTrunc(b.nanos, std.time.ns_per_ms),
            n * 2,
        },
    );

    if (grew_by > allocation_work_bound) {
        try failures.append(gpa, .{
            .path = "the front end",
            .what = "does no more allocation work than its input is worth",
            .expected = try std.fmt.allocPrint(
                gpa,
                "at most {d:.1}x the allocation work for twice the program",
                .{allocation_work_bound},
            ),
            .actual = try std.fmt.allocPrint(
                gpa,
                "{d:.2}x allocation work -- {d} bytes at {d} functions, {d} at {d}",
                .{ grew_by, a.took, n, b.took, n * 2 },
            ),
        });
    }
}

/// The diagnostics a language server publishes are the ones `check` reports.
///
/// The one property this whole design is organised against. An editor and a
/// command line asking what is wrong with a program is one question, and a
/// server that answered it a second way would agree on everything anyone tried
/// and disagree on the program nobody wrote.
///
/// Two runs of the pipeline rather than one read twice: the server loads and
/// checks a module of its own from the same files, and what it publishes is
/// compared per file against what this run's sink holds -- the same rules, the
/// same number of them, in the same order. A range agrees when it converts
/// back to the byte offsets the sink recorded, which asks the protocol's own
/// inverse rather than spelling the conversion a second time here.
///
/// Costs one more check of the case, which is what a second answer costs to
/// compare against, plus one pass over each file's diagnostics.
fn checkPublished(
    gpa: std.mem.Allocator,
    failures: *std.ArrayList(Failure),
    display_path: []const u8,
    checked: *const lsp_analysis.Analysis,
    program: *const Program,
    table: *const FileTable,
    sink: *const Sink,
) !void {
    // Which of this run's files the library wrote. A server publishes for the
    // program's own modules, since a file the programmer cannot open is a file
    // no editor has a tab for -- so the library's diagnostics, if it ever had
    // one, are not what is missing when a count comes up short.
    const from_library = try gpa.alloc(bool, table.count());
    defer gpa.free(from_library);
    @memset(from_library, false);
    for (program.modules) |m| {
        if (!m.library) continue;
        for (m.files) |f| from_library[f.index()] = true;
    }

    var wanted: u32 = 0;
    for (sink.items()) |*d| {
        const primary = d.primaryLabel() orelse continue;
        if (from_library[primary.file.index()]) continue;
        wanted += 1;
    }

    const publication = try lsp_publish.Publication.init(gpa, checked);
    var compared: u32 = 0;
    var it = lsp_publish.files(&checked.program);
    while (it.next()) |file| {
        const path = checked.table.get(file).path;
        const text = checked.table.get(file).text;

        const published = try publication.forFile(gpa, file, .@"utf-16");

        var reported: std.ArrayList(*const diagnostic.Diagnostic) = .empty;
        defer reported.deinit(gpa);
        for (sink.items()) |*d| {
            const primary = d.primaryLabel() orelse continue;
            if (!std.mem.eql(u8, table.get(primary.file).path, path)) continue;
            try reported.append(gpa, d);
        }
        compared += @intCast(reported.items.len);

        if (reported.items.len != published.len) {
            try failures.append(gpa, .{
                .path = display_path,
                .what = "a server publishes what `check` reports",
                .expected = try std.fmt.allocPrint(gpa, "{d} diagnostic(s) in {s}", .{ reported.items.len, path }),
                .actual = try std.fmt.allocPrint(gpa, "{d} published", .{published.len}),
            });
            continue;
        }

        for (reported.items, published) |d, got| {
            const rule = if (d.code) |c| c.ruleName() else "";
            const said = if (got.code) |c| c.string else "";
            if (!std.mem.eql(u8, rule, said)) {
                try failures.append(gpa, .{
                    .path = display_path,
                    .what = "a server publishes the rule `check` named",
                    .expected = try gpa.dupe(u8, rule),
                    .actual = try gpa.dupe(u8, said),
                });
                continue;
            }

            // A position is a line and a count of UTF-16 units, which a file
            // that is not UTF-8 has none of. The corpus holds one on purpose --
            // it is what provokes [S-Encoding] -- and the rule it provokes is
            // compared above, which is the part that means anything here.
            if (!std.unicode.utf8ValidateSlice(text)) continue;

            const span = d.primaryLabel().?.span;
            const start = lsp.offsets.positionToIndex(text, got.range.start, .@"utf-16");
            const end = lsp.offsets.positionToIndex(text, got.range.end, .@"utf-16");
            if (start != span.start or end != span.end) {
                try failures.append(gpa, .{
                    .path = display_path,
                    .what = try std.fmt.allocPrint(gpa, "a server publishes where [{s}] was reported", .{rule}),
                    .expected = try std.fmt.allocPrint(gpa, "{d}..{d} in {s}", .{ span.start, span.end, path }),
                    .actual = try std.fmt.allocPrint(gpa, "{d}..{d}", .{ start, end }),
                });
            }
        }
    }

    // A file the server never published for is a file whose diagnostics
    // nothing above compared, and the per-file counts cannot see it.
    if (compared != wanted) {
        try failures.append(gpa, .{
            .path = display_path,
            .what = "a server publishes for every file `check` reports about",
            .expected = try std.fmt.allocPrint(gpa, "{d} diagnostic(s) accounted for", .{wanted}),
            .actual = try std.fmt.allocPrint(gpa, "{d}", .{compared}),
        });
    }
}

/// What a rename in this property changes a name to.
///
/// A name no case writes, checked against the case's own bytes rather than
/// assumed. A collision would make the second check report on the language --
/// a duplicate name, a shadowed one -- instead of on the rename.
///
/// Spelled in the case the renamed name already has: [N-Case] holds a type, a
/// trait, a variant and a type parameter to a capital first letter and every
/// other name to a lowercase one, so a rename that changed the case would be
/// refused for that alone.
const fresh_name = "renamed_by_this_property";
const fresh_capitalised_name = "RenamedByThisProperty";

/// The fresh name a rename of `was` writes.
fn freshNameFor(was: []const u8) []const u8 {
    return if (name_case.of(was) == .capital) fresh_capitalised_name else fresh_name;
}

test "a rename property keeps the case of the name it renames" {
    try testing.expectEqualStrings(fresh_capitalised_name, freshNameFor("Box"));
    try testing.expectEqualStrings(fresh_capitalised_name, freshNameFor("_T"));
    try testing.expectEqualStrings(fresh_name, freshNameFor("value"));
    try testing.expectEqualStrings(fresh_name, freshNameFor("_"));
}

/// What a rename is asked about, one binding of each per case.
///
/// The resolver's kind, except that `.function` holds three names a rename
/// treats differently: an ordinary function, the signature a trait declares, and
/// the `impl` member supplying one. The last two are several declarations one
/// rename has to keep spelled alike, and asking about the first `.function` a
/// case declares asks about whichever of the three it happened to write first --
/// so a property named for every rename would check the one kind of rename that
/// is a single declaration.
const RenameSubject = enum {
    local,
    parameter,
    function,
    signature,
    impl_member,
    constant,
    declared_type,
    builtin_type,
    trait,
    module,
    binder,
    capture,
    associated_type,
    type_parameter,
    type_alias,
};

/// Which subject a binding is, written over every kind rather than as a list of
/// the ones that split, so a kind added later has to say which subject it is.
fn subjectOf(ast: *const Ast, kind: resolve_mod.Kind, d: node_mod.DeclId) RenameSubject {
    return switch (kind) {
        .local => .local,
        .parameter => .parameter,
        .constant => .constant,
        .declared_type => .declared_type,
        .builtin_type => .builtin_type,
        .trait => .trait,
        .module => .module,
        .binder => .binder,
        .capture => .capture,
        // One subject for both sides. What a rename of either has to reach is
        // the pair the checker recorded, so asking about the side a case wrote
        // first asks about the same relation from whichever end.
        .associated_type => .associated_type,
        .type_parameter => .type_parameter,
        .type_alias => .type_alias,
        .function => blk: {
            if (d == node_mod.DeclId.none) break :blk .function;
            if (ast.declIsSignature(d)) break :blk .signature;
            // A member of an `impl` that names a trait. An inherent `impl`'s
            // member names none and is the whole of what its name means.
            if (ast.declTrait(d) != TokenId.none) break :blk .impl_member;
            break :blk .function;
        },
    };
}

/// Property: accepting what the server offers leaves a program that checks.
///
/// The one thing that says an answer a client writes back into the file is
/// right. Every other check an offer gets here is a shape -- a title, an edit
/// carrying a range, a label -- and an import written at the wrong offset, an
/// import naming a directory from the wrong side of the module it is written
/// in, and a name offered under a spelling no import can make work all have
/// exactly that shape and leave a program that reports more than it did.
///
/// Two offers, because two things a server sends are accepted into the source.
///
/// **A quick fix.** The program is checked, every action the server would
/// offer for what it reports is applied, and the program is checked again. Two
/// things have to hold: one fewer name is undefined, and no rule appeared that
/// was not there before -- an import that resolves but is never used is
/// [M-Unused], which is exactly what a fix that answers the wrong kind of name
/// would leave behind.
///
/// Every action, not the first: where two modules share a leaf both are
/// offered and either is what the reader meant, so a fix that resolves only
/// one of them is half a fix.
///
/// **A completion carrying an import.** A name from a module nobody imported
/// is offered qualified, and the module beside it, each with the import that
/// binds the qualifier. Accepting one writes the label at the cursor and the
/// import at the top, and the result has to report nothing the program did not
/// report without the probe at all -- which is what catches a bare `size`
/// offered where only `ledger.size` can be written, and an import spelled so
/// the lexer will not read it.
///
/// **Asked of every program, and not only of the ones that happen to name a
/// module they have not imported.** A corpus of programs that compile is a
/// corpus that offers no fix, and a property whose subject is the cases written
/// for it records those cases rather than the rule. So each program is given
/// the undefined name itself, in a file of the program's own entry module, in
/// each of the two shapes an undefined name takes: the qualifier of a qualified
/// access, which is what an import binds, and a name written alone, which is
/// what a reader has typed before typing the rest and which no import binds.
/// Both are checked the same way, because "the diagnostic goes away" is the
/// whole claim in both -- the second is answered by offering nothing at all.
/// The completion half is asked the same way, from a probe holding the slot a
/// reader's cursor would be in.
///
/// Asked about the files of the program's own entry module, which are the
/// files the analysis reads from memory -- an edit to a submodule's file would
/// be re-checked against what is still on disk, which is not what was applied.
///
/// **Bound:** one check of the program per probe written, and one further check
/// per offer accepted. The fix probes are two files, each holding one line per
/// module of the program the index says an import would name; the completion
/// probes are one file plus one per such module. So what the probes cost is
/// sized by the program they are written into.
fn checkAcceptedOffers(
    gpa: std.mem.Allocator,
    backing: std.mem.Allocator,
    checked_library: *const loader.CheckedLibrary,
    io: std.Io,
    failures: *std.ArrayList(Failure),
    display_path: []const u8,
    query: lsp_workspace.Query,
    program: []const u8,
    taken: *Taken,
) !bool {
    var docs: Documents = .{ .gpa = gpa };
    defer docs.deinit();
    const files = filesOfProgram(gpa, io, &docs, program) catch return false;

    var asked = try offersFix(gpa, backing, checked_library, failures, display_path, query, program, files);

    for ([_]Shape{ .qualified, .alone }) |shape| {
        const written = try probeWriting(gpa, query, program, shape) orelse continue;

        const probed = try gpa.alloc(InMemoryFile, files.len + 1);
        @memcpy(probed[0..files.len], files);
        probed[files.len] = written;

        if (try offersFix(gpa, backing, checked_library, failures, display_path, query, program, probed)) asked = true;
    }

    if (try acceptsCompletions(gpa, backing, checked_library, failures, display_path, query, program, files, taken)) asked = true;
    return asked;
}

/// How many offers a run accepted and how many it declined, so a property that
/// stopped reaching one of the two shapes says so out loud.
const Taken = struct {
    /// Completion items accepted into a probe and re-checked.
    applied: u32 = 0,
    /// Of those, the ones that replaced a range of their own rather than
    /// being written in at the cursor.
    rewritten: u32 = 0,
    /// Items carrying an import that no probe here can accept: a type, a trait
    /// and a re-export name something a value slot does not hold, and the slot
    /// a type name goes in is not the slot this probe writes.
    declined: u32 = 0,
    /// Of the accepted, the ones whose text carried a tab stop and so was
    /// reduced before it was written. A snippet is the one shape here that is
    /// not the text a compiler reads, and a run that stopped reaching one
    /// would look exactly like a run that reached it.
    stopped: u32 = 0,
};

/// What one workspace manifest contributes, kept apart until every worker has
/// finished so scheduling cannot decide accounting or report order.
const WorkspaceResult = struct {
    failures: []const Failure = &.{},
    properties: std.EnumMap(Property, u32) = .{},
    passed_over: std.EnumMap(Property, u32) = .{},
    offered: usize = 0,
    taken: Taken = .{},
    looked_for: u32 = 0,
    err: ?anyerror = null,
};

const SessionResult = struct {
    failures: []const Failure = &.{},
    deterministic: bool = false,
    held_once: bool = false,
    opened_and_beside: u32 = 0,
    opened_differing: u32 = 0,
    opened_alone: u32 = 0,
    updated: []const []const u8 = &.{},
    logs: []const u8 = "",
    err: ?anyerror = null,
};

/// What one generated seed contributes, kept apart so scheduling cannot decide
/// accounting or report order.
const GeneratedResult = struct {
    failures: []const Failure = &.{},
    diagnostics: []const u8 = "",
    generated: bool = false,
    properties: std.EnumMap(Property, u32) = .{},
    rewrites: std.EnumMap(Transform, u32) = .{},
    mutations: std.EnumMap(Mutation, u32) = .{},
    damages: std.EnumMap(Damage, u32) = .{},
    passed_over: std.EnumMap(Property, u32) = .{},
    declined_settled_refs: PassedSettledRefs = .{},
    err: ?anyerror = null,
};

fn mergeWorkspaceResults(
    gpa: std.mem.Allocator,
    results: []const WorkspaceResult,
    failures: *std.ArrayList(Failure),
    properties: *std.EnumMap(Property, u32),
    passed_over: *std.EnumMap(Property, u32),
    taken: *Taken,
    offered: *usize,
    looked_for: *u32,
) !void {
    for (results) |result| {
        if (result.err) |err| return err;
        try failures.appendSlice(gpa, result.failures);
        for (std.enums.values(Property)) |property| {
            if (result.properties.get(property)) |n| {
                properties.put(property, (properties.get(property) orelse 0) + n);
            }
            if (result.passed_over.get(property)) |n| {
                passed_over.put(property, (passed_over.get(property) orelse 0) + n);
            }
        }
        offered.* += result.offered;
        looked_for.* += result.looked_for;
        taken.applied += result.taken.applied;
        taken.rewritten += result.taken.rewritten;
        taken.declined += result.taken.declined;
        taken.stopped += result.taken.stopped;
    }
}

fn mergeSessionResults(
    gpa: std.mem.Allocator,
    results: []const SessionResult,
    failures: *std.ArrayList(Failure),
    properties: *std.EnumMap(Property, u32),
    passed_over: *std.EnumMap(Property, u32),
    opened_and_beside: *u32,
    opened_differing: *u32,
    opened_alone: *u32,
    output: ?*std.Io.Writer,
) !void {
    for (results) |result| {
        if (result.logs.len != 0) {
            if (output) |writer| try writer.writeAll(result.logs) else std.debug.print("{s}", .{result.logs});
        }
        for (result.updated) |path| {
            if (output) |writer| {
                try writer.print("updated {s}\n", .{path});
            } else std.debug.print("updated {s}\n", .{path});
        }
        if (result.err) |err| return err;

        try failures.appendSlice(gpa, result.failures);
        tally(properties, passed_over, .deterministic, result.deterministic);
        tally(properties, passed_over, .held_once, result.held_once);
        opened_and_beside.* += result.opened_and_beside;
        opened_differing.* += result.opened_differing;
        opened_alone.* += result.opened_alone;
    }
}

fn mergeGeneratedResults(
    gpa: std.mem.Allocator,
    results: []const GeneratedResult,
    failures: *std.ArrayList(Failure),
    generated: *u32,
    properties: *std.EnumMap(Property, u32),
    rewrites: *std.EnumMap(Transform, u32),
    mutations: *std.EnumMap(Mutation, u32),
    damages: *std.EnumMap(Damage, u32),
    diagnostics: ?*std.Io.Writer,
) !void {
    for (results) |result| {
        if (result.diagnostics.len != 0) {
            if (diagnostics) |writer| {
                try writer.writeAll(result.diagnostics);
            } else {
                std.debug.print("{s}", .{result.diagnostics});
            }
        }
        if (result.err) |err| return err;
        try failures.appendSlice(gpa, result.failures);
        generated.* += @intFromBool(result.generated);
        for (std.enums.values(Property)) |property| {
            if (result.properties.get(property)) |n| {
                properties.put(property, (properties.get(property) orelse 0) + n);
            }
        }
        for (std.enums.values(Transform)) |transform| {
            if (result.rewrites.get(transform)) |n| {
                rewrites.put(transform, (rewrites.get(transform) orelse 0) + n);
            }
        }
        for (std.enums.values(Mutation)) |mutation| {
            if (result.mutations.get(mutation)) |n| {
                mutations.put(mutation, (mutations.get(mutation) orelse 0) + n);
            }
        }
        for (std.enums.values(Damage)) |damage| {
            if (result.damages.get(damage)) |n| {
                damages.put(damage, (damages.get(damage) orelse 0) + n);
            }
        }
    }
}

fn retainFailures(
    keep: std.mem.Allocator,
    failures: []const Failure,
) ![]const Failure {
    const retained = try keep.alloc(Failure, failures.len);
    for (retained, failures) |*out, failure| {
        out.* = .{
            .path = try keep.dupe(u8, failure.path),
            .what = try keep.dupe(u8, failure.what),
            .expected = try keep.dupe(u8, failure.expected),
            .actual = try keep.dupe(u8, failure.actual),
            .case_ordinal = failure.case_ordinal,
            .case_order = failure.case_order,
        };
    }
    return retained;
}

fn retainStrings(keep: std.mem.Allocator, strings: []const []const u8) ![]const []const u8 {
    const retained = try keep.alloc([]const u8, strings.len);
    for (retained, strings) |*out, string| out.* = try keep.dupe(u8, string);
    return retained;
}

const GeneratedSettings = struct {
    /// The checked library a generated program resumes from.
    library: *const loader.CheckedLibrary,
    cache: *const OutcomeCache,
    env: Env,
};

fn checkGeneratedProgram(
    scratch: std.mem.Allocator,
    keep: std.mem.Allocator,
    io: std.Io,
    settings: GeneratedSettings,
    at_seed: u64,
) !GeneratedResult {
    var result: GeneratedResult = .{};
    var failures: std.ArrayList(Failure) = .empty;
    var diagnostics: std.Io.Writer.Allocating = .init(scratch);
    const env: Env = .{
        .scratch = settings.env.scratch,
        .runtime = settings.env.runtime,
        .sanitize = settings.env.sanitize,
        .diagnostics = &diagnostics.writer,
    };

    generated: {
        const gen_zone = tracy.beginZone(@src(), "generated");
        defer gen_zone.end();
        gen_zone.setValue(at_seed);

        const source_zone = tracy.beginZone(@src(), "generated.source");
        const bytes = try generate.choicesFromSeed(scratch, at_seed, 64);
        const text = try generate.generate(scratch, bytes, .{});
        source_zone.end();

        const display_path = try std.fmt.allocPrint(scratch, "generated/{d}.lin", .{at_seed});
        gen_zone.setText(display_path);
        const source: Source = .{ .path = display_path, .text = text };

        // Loaded beside the library and checked as the command line checks a
        // program, because a tuple's type is the library's. The tree of the
        // text alone is what the properties that slice that text read.
        const frontend_zone = tracy.beginZone(@src(), "generated.frontend");
        const loaded = try generate.checkLoadedText(scratch, display_path, text, settings.library);
        const table = &loaded.table;
        const sink = &loaded.sink;
        const program = &loaded.program;
        const semantics = &loaded.semantics;
        var alone = try Standalone.of(scratch, &source);
        defer alone.deinit(scratch);
        frontend_zone.end();

        if (sink.hasErrors()) {
            var why: std.Io.Writer.Allocating = .init(scratch);
            try render.renderAll(&why.writer, table, sink, .{ .color = .never });
            try failures.append(scratch, .{
                .path = display_path,
                .what = "a generated program was rejected",
                .expected = text,
                .actual = why.written(),
            });
            break :generated;
        }

        {
            const in_library = try libraryFiles(scratch, program);
            try checkSettledRefs(
                scratch,
                &failures,
                &result.properties,
                &result.passed_over,
                &result.declined_settled_refs,
                display_path,
                program,
                &semantics.res,
                &semantics.typing,
                in_library,
            );
        }

        if (try regions.firstEscape(scratch, &alone.ast, &alone.resolved.resolution, source.text)) |e| {
            try failures.append(scratch, .{
                .path = display_path,
                .what = "a use reaches a binding from outside its region",
                .expected = try std.fmt.allocPrint(scratch, "`{s}` within {d}..{d}\n{s}", .{
                    e.name,
                    e.extent.start,
                    e.extent.end,
                    text,
                }),
                .actual = try std.fmt.allocPrint(scratch, "used at {d}..{d}", .{
                    e.use.start,
                    e.use.end,
                }),
            });
        }

        const mir = (try lower(scratch, &semantics.expanded, &semantics.res, &semantics.typing, &semantics.disposals, sink, .program)) orelse return error.GeneratedProgramRejected;
        var ir: std.Io.Writer.Allocating = .init(scratch);
        if (!try emitOrRecord(scratch, &failures, &ir, &mir, table, sink, display_path)) {
            break :generated;
        }

        const name = try std.fmt.allocPrint(scratch, "generated{d}", .{at_seed});
        const outcome_zone = tracy.beginZone(@src(), "generated.outcome");
        const ran = outcomeOf(scratch, io, settings.cache, env.buildRunOptions(name, ir.written(), .{})) catch |err| {
            outcome_zone.end();
            result.err = err;
            break :generated;
        };
        outcome_zone.end();
        if (ran.timed_out) {
            try failures.append(scratch, .{
                .path = display_path,
                .what = "did not finish",
                .expected = "a program that stops",
                .actual = ran.text,
            });
            break :generated;
        }
        if (ran.tool_failed) {
            if (!ran.tool_missing) {
                try failures.append(scratch, .{
                    .path = display_path,
                    .what = "the toolchain refused a generated program",
                    .expected = "a module the toolchain takes",
                    .actual = ran.text,
                });
            }
            break :generated;
        }
        result.generated = true;

        const properties_zone = tracy.beginZone(@src(), "generated.properties");
        defer properties_zone.end();
        var formatted: ?[]const u8 = null;
        const formatting = fmt.checkPropertiesReporting(scratch, text, &diagnostics.writer) catch |e| blk: {
            try failures.append(scratch, .{
                .path = display_path,
                .what = "formatting properties",
                .expected = "preserved, idempotent, re-parsing",
                .actual = @errorName(e),
            });
            formatted = try formattedText(scratch, text);
            break :blk null;
        };
        if (formatting) |property| switch (property) {
            .not_applicable => {},
            .checked => |checked| {
                formatted = checked.formatted;
                result.properties.put(.formatting, (result.properties.get(.formatting) orelse 0) + 1);
            },
        };

        if (formatted) |canonical| {
            if (perturb.checkNormalForm(scratch, text, canonical) catch |e| blk: {
                try failures.append(scratch, .{
                    .path = display_path,
                    .what = "formatting is a normal form",
                    .expected = "the same bytes however it was spaced",
                    .actual = @errorName(e),
                });
                break :blk false;
            }) result.properties.put(.normal_form, (result.properties.get(.normal_form) orelse 0) + 1);
        }

        checkMutations(scratch, &failures, &result.mutations, display_path, &alone.ast, &alone.resolved.resolution, &alone.typing, text, .program) catch |err| {
            result.err = err;
            break :generated;
        };
        var selector = lsp_analysis.of(std.heap.page_allocator, std.heap.page_allocator, settings.library, &.{.{
            .path = source.path,
            .text = source.text,
        }}, source.path) catch |err| {
            result.err = err;
            break :generated;
        };
        defer selector.deinit();
        _ = checkRewrites(scratch, io, settings.cache, env, &failures, &result.rewrites, .{
            .display_path = display_path,
            .name = name,
            .source = &source,
            .ast = &alone.ast,
            .res = &alone.resolved.resolution,
            .typing = &alone.typing,
            .semantics = .{
                .ast = &selector.semantics.expanded.ast,
                .program = &selector.program,
                .res = &selector.semantics.res,
                .typing = &selector.semantics.typing,
                .file = selector.fileNamed(source.path).?,
            },
            .answer = ran.text,
            .output = ran.output,
            .errors = ran.errors,
            .ir = ir.written(),
        }) catch |err| {
            result.err = err;
            break :generated;
        };
        const walked = checkWalkLoops(scratch, io, settings.cache, settings.library, &failures, .{
            .display_path = display_path,
            .entry = source.path,
            .files = &.{.{ .path = source.path, .text = source.text }},
            .file_ids = &.{selector.fileNamed(source.path).?},
            .semantics = .{
                .ast = &selector.semantics.expanded.ast,
                .program = &selector.program,
                .res = &selector.semantics.res,
                .typing = &selector.semantics.typing,
                .file = selector.fileNamed(source.path).?,
            },
            .rules = "",
            .ran = .{ .env = env, .answered = .{
                .display_path = display_path,
                .name = name,
                .answer = ran.text,
                .output = ran.output,
                .errors = ran.errors,
            } },
        }) catch |err| {
            result.err = err;
            break :generated;
        };
        if (walked) result.properties.put(.walk_loops, (result.properties.get(.walk_loops) orelse 0) + 1);
        checkDamage(
            scratch,
            io,
            settings.cache,
            env,
            &failures,
            &result.damages,
            table,
            &semantics.expanded,
            &semantics.res,
            &semantics.typing,
            &semantics.disposals,
            .{
                .display_path = display_path,
                .name = name,
                .answer = ran.text,
                .errors = ran.errors,
            },
        ) catch |err| {
            result.err = err;
            break :generated;
        };
    }

    result.failures = try retainFailures(keep, failures.items);
    result.diagnostics = try keep.dupe(u8, diagnostics.written());
    return result;
}

const GeneratedWalk = struct {
    fn run(
        io: std.Io,
        settings: GeneratedSettings,
        first_seed: u64,
        results: []GeneratedResult,
        keep: *std.heap.ArenaAllocator,
        next: *std.atomic.Value(usize),
    ) void {
        tracy.setThreadName("generated");
        var per_seed = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer per_seed.deinit();

        while (true) {
            const at = next.fetchAdd(1, .monotonic);
            if (at >= results.len) break;
            _ = per_seed.reset(.{ .retain_with_limit = 4 << 20 });
            results[at] = checkGeneratedProgram(
                per_seed.allocator(),
                keep.allocator(),
                io,
                settings,
                first_seed + @as(u64, @intCast(at)),
            ) catch |err| .{ .err = err };
        }
    }
};

fn runGeneratedPrograms(
    gpa: std.mem.Allocator,
    io: std.Io,
    settings: GeneratedSettings,
    first_seed: u64,
    programs: u32,
    workers_wanted: usize,
    keep_arenas: []std.heap.ArenaAllocator,
) ![]GeneratedResult {
    const results = try gpa.alloc(GeneratedResult, programs);
    errdefer gpa.free(results);
    if (programs == 0) return results;

    const workers = @min(@max(1, workers_wanted), programs);
    std.debug.assert(keep_arenas.len >= workers);
    var next: std.atomic.Value(usize) = .init(0);

    if (workers == 1) {
        GeneratedWalk.run(io, settings, first_seed, results, &keep_arenas[0], &next);
        return results;
    }

    const threads = try gpa.alloc(std.Thread, workers);
    defer gpa.free(threads);
    var spawned: usize = 0;
    errdefer for (threads[0..spawned]) |thread| thread.join();
    for (threads, 0..) |*thread, i| {
        thread.* = try std.Thread.spawn(compiler_stack.spawn_config, GeneratedWalk.run, .{
            io,
            settings,
            first_seed,
            results,
            &keep_arenas[i],
            &next,
        });
        spawned += 1;
    }
    for (threads) |thread| thread.join();
    return results;
}

/// What a program compiled against the checked library came to.
const LibraryVerdict = union(enum) {
    /// A program some rule refused: the rendered report, and the rules it
    /// names, one per line.
    refused: struct { report: []const u8, rules: []const u8 },
    /// The module an accepted program emitted.
    accepted: []const u8,
    /// Lowering or emission failed on an accepted program, and a failure says
    /// so already.
    broken,
};

/// Compiles one file against the checked library, as a program.
fn compileWithLibrary(
    scratch: std.mem.Allocator,
    failures: *std.ArrayList(Failure),
    prefix: *const loader.CheckedLibrary,
    display_path: []const u8,
    text: []const u8,
) !LibraryVerdict {
    var table: FileTable = .empty;
    var sink = Sink.init(scratch);
    var interner: Interner = .empty;
    const files = [_]InMemoryFile{.{ .path = "main.lin", .text = text }};
    var loaded = try prefix.loadFromMemory(scratch, &table, &sink, &interner, "main.lin", &files, .program, .borrow);
    try table.buildMaps(scratch);
    // The job's own arena serves as the checker's scratch as well: everything
    // here is released with the job, and the page allocator, taking a system
    // call per request, serialises the walkers on the kernel.
    var settled = try prefix.checkProgram(scratch, scratch, &loaded, &interner, &sink, .program);
    defer settled.deinit(scratch);
    const lowered = if (sink.hasErrors())
        null
    else
        try lower(scratch, &settled.expanded, &settled.res, &settled.typing, &settled.disposals, &sink, .program);
    const module = lowered orelse {
        var report: std.Io.Writer.Allocating = .init(scratch);
        try render.renderAll(&report.writer, &table, &sink, .{ .color = .never });
        return .{ .refused = .{ .report = report.written(), .rules = try rulesNamedBy(scratch, &sink) } };
    };
    var ir: std.Io.Writer.Allocating = .init(scratch);
    if (!try emitOrRecord(scratch, failures, &ir, &module, &table, &sink, display_path)) return .broken;
    return .{ .accepted = ir.written() };
}

/// Whether a sanitizer reported a fault on standard error.
///
/// The address and leak sanitizers each name themselves in the first
/// line of a report, and the undefined-behaviour checks the runtime is built
/// with say `runtime error:` when they report rather than trap.
fn sanitizerReported(errors: []const u8) bool {
    return std.mem.indexOf(u8, errors, "Sanitizer") != null or
        std.mem.indexOf(u8, errors, "runtime error:") != null;
}

test "a sanitizer report is found wherever it sits on standard error" {
    try testing.expect(sanitizerReported("==12==ERROR: AddressSanitizer: heap-use-after-free on address"));
    try testing.expect(sanitizerReported("printed first\n==12==ERROR: LeakSanitizer: detected memory leaks"));
    try testing.expect(sanitizerReported("linea_rt.c:40:3: runtime error: signed integer overflow"));
    try testing.expect(!sanitizerReported("linea: index out of bounds at main.lin:4:9\n"));
    try testing.expect(!sanitizerReported(""));
}

/// Why a program that ran did not run clean, or null where it did.
///
/// A defined trap is the runtime's own abort, which writes `linea: ` and what
/// stopped the program; a program that stops on any other signal crashed. A
/// sanitizer that finds a fault reports on standard error and ends the program
/// with a status of its own, so its report is looked for rather than its status.
fn uncleanRun(ran: Ran) ?[]const u8 {
    if (ran.timed_out) return "did not finish";
    if (sanitizerReported(ran.errors)) return "a sanitizer reported a fault";
    if (std.mem.startsWith(u8, ran.text, trap_answer) and std.mem.indexOf(u8, ran.errors, "linea: ") == null) return "crashed";
    return null;
}

test "a defined trap runs clean and a crash or a sanitizer report does not" {
    try testing.expectEqual(@as(?[]const u8, null), uncleanRun(.{ .text = "exit 3\n", .tool_failed = false }));
    const trapped: Ran = .{ .text = "trap\nlinea: index out of bounds at main.lin:4:9\n", .errors = "linea: index out of bounds at main.lin:4:9\n", .tool_failed = false };
    try testing.expectEqual(@as(?[]const u8, null), uncleanRun(trapped));
    try testing.expectEqualStrings("crashed", uncleanRun(.{ .text = "trap\n", .tool_failed = false }).?);
    try testing.expectEqualStrings("a sanitizer reported a fault", uncleanRun(.{
        .text = "exit 1\n",
        .errors = "==9==ERROR: AddressSanitizer: heap-use-after-free\n",
        .tool_failed = false,
    }).?);
}

const SoundnessSettings = struct {
    cache: *const OutcomeCache,
    env: Env,
    library: *const loader.CheckedLibrary,
};

/// What one matrix cell, or one generated program and its mutants, came to.
const SoundnessResult = struct {
    failures: []const Failure = &.{},
    /// Live matrix programs the compiler refused.
    refused_live: u32 = 0,
    /// Programs accepted with an observation live across an owner operation:
    /// live matrix programs and mutants. Each is a failure.
    accepted_live: u32 = 0,
    /// Ended matrix programs that were accepted and ran clean.
    ended: u32 = 0,
    /// Generated storage programs accepted and run against their model.
    generated: u32 = 0,
    mutants: u32 = 0,
    mutants_refused: u32 = 0,
    /// Programs whose exit and output were compared at every level.
    levels_agreed: u32 = 0,
    /// Programs not built because a tool was not on `PATH`.
    unbuilt: u32 = 0,
    /// The rule each refused live cell or mutant was first refused by.
    refusal_rules: []const []const u8 = &.{},
    err: ?anyerror = null,
};

/// The rule that refuses an operation while an observation of its owner is
/// still to be used.
const invalidation_rule = "O-Borrow";

/// Holds a refusal of a program whose only change from an accepted one is an
/// owner operation moved or inserted across a live observation to being the
/// invalidation rule's, and records the first rule it names.
///
/// Any other rule -- a type error, a name that does not resolve, a move in a
/// loop, a pointless copy -- means the template or the mutation wrote
/// something broken, and its refusal would say nothing about the observation
/// while reading as though it did.
fn refusedByInvalidation(
    scratch: std.mem.Allocator,
    failures: *std.ArrayList(Failure),
    first_rules: *std.ArrayList([]const u8),
    display_path: []const u8,
    rules: []const u8,
    report: []const u8,
    text: []const u8,
) !void {
    var lines = std.mem.tokenizeScalar(u8, rules, '\n');
    var first: ?[]const u8 = null;
    while (lines.next()) |rule| {
        if (first == null) first = rule;
        if (std.mem.eql(u8, rule, invalidation_rule)) continue;
        try failures.append(scratch, .{
            .path = display_path,
            .what = "refused by a rule other than the invalidation rule",
            .expected = "a refusal by [" ++ invalidation_rule ++ "] alone, since only an owner operation moved",
            .actual = try std.fmt.allocPrint(scratch, "{s}--- program ---\n{s}", .{ report, text }),
        });
        return;
    }
    if (first) |rule| try first_rules.append(scratch, rule);
}

const SoundnessJob = union(enum) {
    cell: matrix.Cell,
    /// A generated storage program and the seed its choices came from.
    program: struct { seed: u64, choices: []const u8 },
};

/// Runs one program the compiler accepted, and records why it did not run
/// clean where it did not. Answers what it ran, or null where it recorded a
/// failure or no toolchain was there to build it.
fn runAccepted(
    scratch: std.mem.Allocator,
    io: std.Io,
    settings: SoundnessSettings,
    failures: *std.ArrayList(Failure),
    result: *SoundnessResult,
    display_path: []const u8,
    name: []const u8,
    ir: []const u8,
    text: []const u8,
) !?Ran {
    const ran = try outcomeOf(scratch, io, settings.cache, settings.env.buildRunOptions(name, ir, .{}));
    if (ran.tool_failed and !ran.timed_out) {
        if (ran.tool_missing) {
            result.unbuilt += 1;
        } else {
            try failures.append(scratch, .{
                .path = display_path,
                .what = "the toolchain refused an accepted program",
                .expected = "a module the toolchain takes",
                .actual = try std.fmt.allocPrint(scratch, "{s}\n--- program ---\n{s}", .{ ran.text, text }),
            });
        }
        return null;
    }
    if (uncleanRun(ran)) |why| {
        try failures.append(scratch, .{
            .path = display_path,
            .what = why,
            .expected = "a program the compiler accepted runs clean",
            .actual = try std.fmt.allocPrint(scratch, "{s}{s}\n--- program ---\n{s}", .{ ran.text, ran.errors, text }),
        });
        return null;
    }
    return ran;
}

/// Checks both programs of one matrix cell.
fn checkMatrixCell(
    scratch: std.mem.Allocator,
    keep: std.mem.Allocator,
    io: std.Io,
    settings: SoundnessSettings,
    ordinal: usize,
    cell: matrix.Cell,
) !SoundnessResult {
    var result: SoundnessResult = .{};
    var failures: std.ArrayList(Failure) = .empty;
    var refusal_rules: std.ArrayList([]const u8) = .empty;
    for (std.enums.values(matrix.Liveness)) |liveness| {
        const text = try matrix.render(scratch, cell, liveness);
        const display_path = try std.fmt.allocPrint(scratch, "soundness/{f}/{s}", .{ cell, @tagName(liveness) });
        const name = try std.fmt.allocPrint(scratch, "soundness{d}{s}", .{ ordinal, @tagName(liveness) });
        switch (try compileWithLibrary(scratch, &failures, settings.library, display_path, text)) {
            .broken => {},
            .refused => |refusal| switch (liveness) {
                .live => {
                    result.refused_live += 1;
                    try refusedByInvalidation(scratch, &failures, &refusal_rules, display_path, refusal.rules, refusal.report, text);
                },
                // The ended program uses the observation before the
                // operation, so a refusal is the template failing and the
                // cell's live refusal says nothing.
                .ended => try failures.append(scratch, .{
                    .path = display_path,
                    .what = "a program whose observation ends before the operation is refused",
                    .expected = "accepted, so the live program's refusal is about the observation",
                    .actual = try std.fmt.allocPrint(scratch, "{s}--- program ---\n{s}", .{ refusal.report, text }),
                }),
            },
            .accepted => |ir| {
                if (liveness == .live) {
                    result.accepted_live += 1;
                    try failures.append(scratch, acceptedAcrossAnOperation(display_path, text));
                    continue;
                }
                const ran = (try runAccepted(scratch, io, settings, &failures, &result, display_path, name, ir, text)) orelse continue;
                if (!std.mem.eql(u8, ran.text, "exit 0\n")) {
                    try failures.append(scratch, .{
                        .path = display_path,
                        .what = "read more than the storage ever held",
                        .expected = "exit 0\n",
                        .actual = try std.fmt.allocPrint(scratch, "{s}\n--- program ---\n{s}", .{ ran.text, text }),
                    });
                    continue;
                }
                if (liveness == .ended) result.ended += 1;
            },
        }
    }
    result.failures = try retainFailures(keep, failures.items);
    result.refusal_rules = try retainStrings(keep, refusal_rules.items);
    return result;
}

/// The failure of a program that uses an observation after an operation that
/// may move, grow or free the storage it observes, and was accepted.
///
/// Acceptance alone is the failure: the language refuses every such program,
/// and running it proves nothing, since a stale read of storage the operation
/// left allocated is invisible to every sanitizer and reads plausible values.
fn acceptedAcrossAnOperation(display_path: []const u8, text: []const u8) Failure {
    return .{
        .path = display_path,
        .what = "accepted an observation used after an operation that may move, grow or free its storage",
        .expected = "refused by [" ++ invalidation_rule ++ "]",
        .actual = text,
    };
}

const SoundnessWalk = struct {
    fn run(
        io: std.Io,
        settings: SoundnessSettings,
        jobs: []const SoundnessJob,
        results: []SoundnessResult,
        keep: *std.heap.ArenaAllocator,
        next: *std.atomic.Value(usize),
    ) void {
        tracy.setThreadName("soundness");
        // A job whose program declares a closure checks the whole library
        // again, which asks for far more than a small arena retains. Backed by
        // the page allocator, every job would map and unmap that much afresh,
        // and the walkers would spend the run waiting on the kernel.
        var per_job = std.heap.ArenaAllocator.init(std.heap.smp_allocator);
        defer per_job.deinit();

        while (true) {
            const at = next.fetchAdd(1, .monotonic);
            if (at >= jobs.len) break;
            _ = per_job.reset(.{ .retain_with_limit = 64 << 20 });
            results[at] = switch (jobs[at]) {
                .cell => |cell| checkMatrixCell(per_job.allocator(), keep.allocator(), io, settings, at, cell),
                .program => |program| checkStorageProgram(per_job.allocator(), keep.allocator(), io, settings, program.seed, program.choices),
            } catch |err| .{ .err = err };
        }
    }
};

/// What a soundness run was asked to check, and what it checked.
const SoundnessCounts = struct {
    /// Matrix cells the run held, zero where the matrix was left out.
    cells: usize,
    refused_live: u32,
    accepted_cells: u32,
    /// Ended matrix programs built, run, and found clean.
    ended: u32,
    /// Generated programs the run was given: its seed window and the
    /// replayed inputs.
    programs: usize,
    /// Generated programs built, run, and found to compute their model.
    generated: u32,
    mutants: u32,
    /// Programs not built because a tool was not on `PATH`.
    unbuilt: u32,
};

/// Holds a soundness run to having checked everything it was given.
///
/// Each half of the step passes by doing nothing when its programs cannot be
/// built, so every count is asserted rather than printed: every live cell
/// decided, every ended program and every generated program built and run,
/// and mutants written wherever programs were. A missing tool is a failure
/// of its own, because it is what makes the counts fall short.
fn checkSoundnessCounts(gpa: std.mem.Allocator, failures: *std.ArrayList(Failure), c: SoundnessCounts) !void {
    const short = struct {
        fn add(g: std.mem.Allocator, list: *std.ArrayList(Failure), what: []const u8, expected: usize, actual: usize) !void {
            try list.append(g, .{
                .path = "soundness",
                .what = what,
                .expected = try std.fmt.allocPrint(g, "{d}", .{expected}),
                .actual = try std.fmt.allocPrint(g, "{d}", .{actual}),
            });
        }
    };
    if (c.unbuilt != 0) try failures.append(gpa, .{
        .path = "soundness",
        .what = "built nothing for programs that need a tool not on PATH; run it inside `nix develop`",
        .expected = "every accepted program built and run",
        .actual = try std.fmt.allocPrint(gpa, "{d} program(s) not built", .{c.unbuilt}),
    });
    if (c.cells == 0 and c.programs == 0) try failures.append(gpa, .{
        .path = "soundness",
        .what = "was given nothing to check",
        .expected = "the matrix, generated programs, or both",
        .actual = "neither",
    });
    if (c.cells != 0) {
        if (c.refused_live + c.accepted_cells != c.cells) try short.add(gpa, failures, "decided fewer live matrix programs than it holds", c.cells, c.refused_live + c.accepted_cells);
        if (c.ended != c.cells) try short.add(gpa, failures, "built and ran fewer ended matrix programs than it holds", c.cells, c.ended);
    }
    if (c.programs != 0) {
        if (c.generated != c.programs) try short.add(gpa, failures, "built and ran fewer generated programs than it was given", c.programs, c.generated);
        if (c.mutants == 0) try short.add(gpa, failures, "wrote no mutant of any generated program", 1, 0);
    }
}

test "a soundness run that built nothing fails" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    // Every count met.
    var clean: std.ArrayList(Failure) = .empty;
    try checkSoundnessCounts(gpa, &clean, .{ .cells = 3, .refused_live = 3, .accepted_cells = 0, .ended = 3, .programs = 2, .generated = 2, .mutants = 8, .unbuilt = 0 });
    try testing.expectEqual(@as(usize, 0), clean.items.len);

    // What a run without `mlir-opt` reports: every live cell decided in
    // process, and nothing built.
    var toolless: std.ArrayList(Failure) = .empty;
    try checkSoundnessCounts(gpa, &toolless, .{ .cells = 3, .refused_live = 3, .accepted_cells = 0, .ended = 0, .programs = 2, .generated = 0, .mutants = 8, .unbuilt = 5 });
    try testing.expectEqual(@as(usize, 3), toolless.items.len);

    // A seed window whose programs had no site for a mutant.
    var unmutated: std.ArrayList(Failure) = .empty;
    try checkSoundnessCounts(gpa, &unmutated, .{ .cells = 0, .refused_live = 0, .accepted_cells = 0, .ended = 0, .programs = 2, .generated = 2, .mutants = 0, .unbuilt = 0 });
    try testing.expectEqual(@as(usize, 1), unmutated.items.len);

    var empty: std.ArrayList(Failure) = .empty;
    try checkSoundnessCounts(gpa, &empty, .{ .cells = 0, .refused_live = 0, .accepted_cells = 0, .ended = 0, .programs = 0, .generated = 0, .mutants = 0, .unbuilt = 0 });
    try testing.expectEqual(@as(usize, 1), empty.items.len);
}

/// The seed a program replayed from the fuzz corpus reports, which names no
/// position in a seed window.
const replayed_seed = std.math.maxInt(u64);

/// Checks one generated storage program, then each of its mutants.
///
/// The program must be accepted, run clean, answer its model's total, and
/// answer alike at every optimisation level. A mutant uses an observation
/// after an operation on its owner, so it must be refused by the invalidation
/// rule.
fn checkStorageProgram(
    scratch: std.mem.Allocator,
    keep: std.mem.Allocator,
    io: std.Io,
    settings: SoundnessSettings,
    seed: u64,
    choices: []const u8,
) !SoundnessResult {
    var result: SoundnessResult = .{};
    var failures: std.ArrayList(Failure) = .empty;
    var refusal_rules: std.ArrayList([]const u8) = .empty;
    const generated = try storage_gen.generate(scratch, choices);
    const label = if (seed == replayed_seed)
        try std.fmt.allocPrint(scratch, "replayed-{x}", .{std.hash.Wyhash.hash(0, choices)})
    else
        try std.fmt.allocPrint(scratch, "{d}", .{seed});
    const display_path = try std.fmt.allocPrint(scratch, "storage/{s}.lin", .{label});
    const name = try std.fmt.allocPrint(scratch, "storage{s}", .{label});

    switch (try compileWithLibrary(scratch, &failures, settings.library, display_path, generated.text)) {
        .broken => {},
        .refused => |refusal| try failures.append(scratch, .{
            .path = display_path,
            .what = "a generated storage program was refused",
            .expected = generated.text,
            .actual = refusal.report,
        }),
        .accepted => |ir| if (try runAccepted(scratch, io, settings, &failures, &result, display_path, name, ir, generated.text)) |ran| {
            if (!std.mem.eql(u8, ran.text, "exit 0\n")) {
                try failures.append(scratch, .{
                    .path = display_path,
                    .what = "computed another total than its model",
                    .expected = try std.fmt.allocPrint(scratch, "exit 0, having computed {d}", .{generated.expected}),
                    .actual = try std.fmt.allocPrint(scratch, "{s}{s}\n--- program ---\n{s}", .{ ran.text, ran.errors, generated.text }),
                });
            } else {
                result.generated += 1;
                switch (try levelsAgree(scratch, io, settings.cache, &failures, settings.env.buildRunOptions(name, ir, .{}), ran, display_path, generated.text)) {
                    .agreed => result.levels_agreed += 1,
                    .disagreed => {},
                    .unbuilt => result.unbuilt += 1,
                }
            }
        },
    }

    for (0..storage_gen.mutants_per_program) |k| {
        const m = (try storage_gen.mutant(scratch, generated, choices, @intCast(k))) orelse break;
        result.mutants += 1;
        const mutant_path = try std.fmt.allocPrint(scratch, "storage/{s}.mutant{d}.lin", .{ label, k });
        switch (try compileWithLibrary(scratch, &failures, settings.library, mutant_path, m.text)) {
            .broken => {},
            .refused => |refusal| {
                result.mutants_refused += 1;
                try refusedByInvalidation(scratch, &failures, &refusal_rules, mutant_path, refusal.rules, refusal.report, m.text);
            },
            .accepted => {
                result.accepted_live += 1;
                try failures.append(scratch, acceptedAcrossAnOperation(
                    try std.fmt.allocPrint(scratch, "{s} ({s} at an observation of {s})", .{ mutant_path, @tagName(m.operation), @tagName(m.site.target) }),
                    m.text,
                ));
            },
        }
    }

    result.failures = try retainFailures(keep, failures.items);
    result.refusal_rules = try retainStrings(keep, refusal_rules.items);
    return result;
}

/// What building a program at every other optimisation level came to.
const LevelVerdict = enum { agreed, disagreed, unbuilt };

/// Whether a program answers at every other optimisation level what it
/// answered at the default one: the same exit, the same output.
///
/// Linea has no undefined behaviour, so no level may give an optimiser a
/// premise that changes what a program does. Each level is an outcome of its
/// own in the cache, keyed by the module, the driver and the level, so an
/// unchanged module and toolchain are not built again -- which is sound, since
/// the outcome is a function of exactly what the key holds.
///
/// It assumes the program's output is deterministic: one that printed a
/// clock or an address would disagree with itself at random, and the cache
/// would then keep whichever answer it saw first.
///
/// `program` is the source a failure shows, where the caller has one text.
fn levelsAgree(
    scratch: std.mem.Allocator,
    io: std.Io,
    cache: *const OutcomeCache,
    failures: *std.ArrayList(Failure),
    at_default_options: BuildRunOptions,
    at_default: Ran,
    display_path: []const u8,
    program: ?[]const u8,
) !LevelVerdict {
    var verdict: LevelVerdict = .agreed;
    for (toolchain.levels) |level| {
        if (std.mem.eql(u8, level, at_default_options.opt)) continue;
        var options = at_default_options;
        options.opt = level;
        options.name = try std.fmt.allocPrint(scratch, "{s}O{s}", .{ at_default_options.name, level });
        const ran = try outcomeOf(scratch, io, cache, options);
        if (ran.tool_failed and ran.tool_missing) return .unbuilt;
        if (std.mem.eql(u8, ran.text, at_default.text) and std.mem.eql(u8, ran.output, at_default.output)) continue;
        verdict = .disagreed;
        try failures.append(scratch, .{
            .path = display_path,
            .what = try std.fmt.allocPrint(scratch, "answers differently at -O{s}", .{level}),
            .expected = try std.fmt.allocPrint(scratch, "at -O{s}:\n{s}--- output ---\n{s}", .{ at_default_options.opt, at_default.text, at_default.output }),
            .actual = try std.fmt.allocPrint(scratch, "at -O{s}:\n{s}--- output ---\n{s}{s}{s}", .{
                level,
                ran.text,
                ran.output,
                if (program == null) "" else "\n--- program ---\n",
                program orelse "",
            }),
        });
    }
    return verdict;
}

/// Checks the soundness matrix and the generated storage programs, with their
/// mutants, and reports what they came to.
///
/// Apart from the corpus walk: nothing here reads the corpus, and the lanes
/// that run it choose their own sanitizer and seed window.
fn runSoundness(
    gpa: std.mem.Allocator,
    scratch_backing: std.mem.Allocator,
    io: std.Io,
    options: RunnerOptions,
    environ: std.process.Environ,
) !u8 {
    const runtime_path = options.runtime_path orelse {
        std.debug.print("soundness: --soundness builds what it checks and needs --runtime\n", .{});
        return 64;
    };
    const scratch_dir = options.scratch_dir;
    std.Io.Dir.cwd().createDirPath(io, scratch_dir) catch {};
    const began = std.Io.Timestamp.now(io, .awake);

    var outcome_stats: OutcomeStats = .{};
    var cache = try OutcomeCache.init(gpa, io, environ.getPosix("PATH"), scratch_dir, runtime_path, options.sanitize);
    cache.stats = &outcome_stats;
    const prefix = try loader.CheckedLibrary.init(scratch_backing);
    defer prefix.deinit();
    const settings: SoundnessSettings = .{
        .cache = &cache,
        .env = .{ .scratch = scratch_dir, .runtime = runtime_path, .sanitize = options.sanitize },
        .library = prefix,
    };

    var jobs: std.ArrayList(SoundnessJob) = .empty;
    defer jobs.deinit(gpa);
    const all_cells = try matrix.cells(gpa);
    defer gpa.free(all_cells);
    if (!options.skip_matrix) for (all_cells) |cell| try jobs.append(gpa, .{ .cell = cell });
    for (0..options.storage_programs) |k| {
        const seed = options.seed + k;
        try jobs.append(gpa, .{ .program = .{ .seed = seed, .choices = try storage_gen.choicesFromSeed(gpa, seed) } });
    }
    // Every program a search has found, replayed by every run after it.
    for (@import("fuzz_corpus").storage) |choices| {
        try jobs.append(gpa, .{ .program = .{ .seed = replayed_seed, .choices = choices } });
    }

    const walkers = @min(jobs.items.len, @max(1, options.walkers_wanted orelse std.Thread.getCpuCount() catch 1));
    const results = try gpa.alloc(SoundnessResult, jobs.items.len);
    defer gpa.free(results);
    const arenas = try gpa.alloc(std.heap.ArenaAllocator, walkers);
    defer gpa.free(arenas);
    for (arenas) |*it| it.* = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer for (arenas) |*it| it.deinit();
    var next: std.atomic.Value(usize) = .init(0);
    const threads = try gpa.alloc(std.Thread, walkers);
    defer gpa.free(threads);
    var spawned: usize = 0;
    errdefer for (threads[0..spawned]) |thread| thread.join();
    for (threads, arenas) |*thread, *arena| {
        thread.* = try std.Thread.spawn(compiler_stack.spawn_config, SoundnessWalk.run, .{ io, settings, jobs.items, results, arena, &next });
        spawned += 1;
    }
    for (threads) |thread| thread.join();

    var failures: std.ArrayList(Failure) = .empty;
    defer failures.deinit(gpa);
    var total: SoundnessResult = .{};
    var accepted_cells: u32 = 0;
    var accepted_mutants: u32 = 0;
    var refused_by: std.StringArrayHashMapUnmanaged(u32) = .empty;
    defer refused_by.deinit(gpa);
    for (results, jobs.items) |result, job| {
        switch (job) {
            .cell => accepted_cells += result.accepted_live,
            .program => accepted_mutants += result.accepted_live,
        }
        for (result.refusal_rules) |rule| {
            const slot = try refused_by.getOrPut(gpa, rule);
            if (!slot.found_existing) slot.value_ptr.* = 0;
            slot.value_ptr.* += 1;
        }
        if (result.err) |err| return err;
        try failures.appendSlice(gpa, result.failures);
        total.refused_live += result.refused_live;
        total.ended += result.ended;
        total.generated += result.generated;
        total.mutants += result.mutants;
        total.mutants_refused += result.mutants_refused;
        total.levels_agreed += result.levels_agreed;
        total.unbuilt += result.unbuilt;
    }
    try checkSoundnessCounts(gpa, &failures, .{
        .cells = if (options.skip_matrix) 0 else all_cells.len,
        .refused_live = total.refused_live,
        .accepted_cells = accepted_cells,
        .ended = total.ended,
        .programs = options.storage_programs + @import("fuzz_corpus").storage.len,
        .generated = total.generated,
        .mutants = total.mutants,
        .unbuilt = total.unbuilt,
    });
    std.mem.sort(Failure, failures.items, {}, failureLess);

    if (!options.skip_matrix) std.debug.print("soundness: {d} matrix cell(s): {d} live program(s) refused, {d} accepted; {d} ended program(s) accepted and run clean\n", .{
        all_cells.len, total.refused_live, accepted_cells, total.ended,
    });
    std.debug.print("soundness: {d} generated storage program(s) from seeds {d}..{d} and {d} replayed; {d} mutant(s), {d} refused, {d} accepted\n", .{
        total.generated,
        options.seed,
        options.seed + options.storage_programs,
        @import("fuzz_corpus").storage.len,
        total.mutants,
        total.mutants_refused,
        accepted_mutants,
    });
    for (refused_by.keys(), refused_by.values()) |rule, n| std.debug.print("soundness: {d} refusal(s) first by [{s}]\n", .{ n, rule });
    std.debug.print("soundness: {d} program(s) answered alike at all {d} optimisation levels\n", .{ total.levels_agreed, toolchain.levels.len });
    if (total.unbuilt != 0) std.debug.print("soundness: {d} program(s) not built: a tool is not on PATH\n", .{total.unbuilt});
    outcome_stats.report("soundness", "complete");

    const seconds = @divTrunc(began.durationTo(std.Io.Timestamp.now(io, .awake)).nanoseconds, std.time.ns_per_s);
    if (failures.items.len == 0) {
        std.debug.print("soundness: OK in {d}s\n", .{seconds});
        return 0;
    }
    for (failures.items) |f| {
        std.debug.print("\nFAIL {s} ({s})\n", .{ f.path, f.what });
        std.debug.print("--- expected ---\n{s}\n--- actual ---\n{s}\n", .{ f.expected, f.actual });
    }
    std.debug.print("\nsoundness: {d} failure(s) in {d}s\n", .{ failures.items.len, seconds });
    return 1;
}

fn checkWorkspaceProgram(
    scratch: std.mem.Allocator,
    backing: std.mem.Allocator,
    checked_library: *const loader.CheckedLibrary,
    keep: std.mem.Allocator,
    io: std.Io,
    tests_dir_path: []const u8,
    manifest: []const u8,
    query: lsp_workspace.Query,
) !WorkspaceResult {
    var result: WorkspaceResult = .{};
    var failures: std.ArrayList(Failure) = .empty;

    const holding = if (std.fs.path.dirname(manifest)) |under|
        try std.fs.path.join(scratch, &.{ tests_dir_path, under })
    else
        tests_dir_path;

    // A manifest that will not parse marks no program the loader resolves, so
    // there is nothing to ask about.
    const program = loader.entryOf(scratch, io, holding, .as_named, tests_dir_path) catch {
        tally(&result.properties, &result.passed_over, .importable, false);
        tally(&result.properties, &result.passed_over, .accepted_offers, false);
        for (0..recovery_shapes.len) |_| {
            tally(&result.properties, &result.passed_over, .completion_recovers, false);
        }
        return result;
    };

    const offered = query.offers(program, "");
    result.offered = offered.len;

    const display = try displayPath(scratch, tests_dir_path, manifest);
    const program_zone = tracy.beginZone(@src(), "lsp.program");
    defer program_zone.end();
    program_zone.setText(display);

    // Beneath where the program's own source begins is necessary but not
    // sufficient for importability. This path check catches cross-program
    // leakage; the compiler-backed check below catches unspellable descendants.
    for (offered) |entry| {
        const within = std.mem.eql(u8, entry.module, program) or
            (std.mem.startsWith(u8, entry.module, program) and
                entry.module.len > program.len and entry.module[program.len] == '/');
        if (within) continue;
        try failures.append(scratch, .{
            .path = display,
            .what = "the index offers nothing the program cannot import",
            .expected = try std.fmt.allocPrint(scratch, "a module of {s}", .{program}),
            .actual = try std.fmt.allocPrint(scratch, "`{s}` from {s}", .{ entry.name, entry.module }),
        });
    }

    try checkImportable(scratch, backing, checked_library, io, &failures, display, query, program);
    tally(&result.properties, &result.passed_over, .importable, true);

    const fixed = try checkAcceptedOffers(scratch, backing, checked_library, io, &failures, display, query, program, &result.taken);
    tally(&result.properties, &result.passed_over, .accepted_offers, fixed);

    const recovered = try checkRecoveredCompletions(
        scratch,
        backing,
        checked_library,
        io,
        &failures,
        display,
        query,
        program,
        &result.looked_for,
    );
    for (0..recovery_shapes.len) |i| {
        tally(&result.properties, &result.passed_over, .completion_recovers, i < @as(usize, recovered));
    }

    result.failures = try retainFailures(keep, failures.items);
    return result;
}

const WorkspaceWalk = struct {
    fn run(
        io: std.Io,
        checked_library: *const loader.CheckedLibrary,
        tests_dir_path: []const u8,
        manifests: []const []const u8,
        query: lsp_workspace.Query,
        results: []WorkspaceResult,
        keep: *std.heap.ArenaAllocator,
        next: *std.atomic.Value(usize),
    ) void {
        tracy.setThreadName("workspace");
        var per_program = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer per_program.deinit();

        while (true) {
            const at = next.fetchAdd(1, .monotonic);
            if (at >= manifests.len) break;
            _ = per_program.reset(.{ .retain_with_limit = 4 << 20 });
            results[at] = checkWorkspaceProgram(
                per_program.allocator(),
                per_program.child_allocator,
                checked_library,
                keep.allocator(),
                io,
                tests_dir_path,
                manifests[at],
                query,
            ) catch |err| .{ .err = err };
        }
    }
};

fn runWorkspacePrograms(
    gpa: std.mem.Allocator,
    io: std.Io,
    checked_library: *const loader.CheckedLibrary,
    tests_dir_path: []const u8,
    manifests: []const []const u8,
    query: lsp_workspace.Query,
    workers_wanted: usize,
    keep_arenas: []std.heap.ArenaAllocator,
) ![]WorkspaceResult {
    const results = try gpa.alloc(WorkspaceResult, manifests.len);
    errdefer gpa.free(results);
    if (manifests.len == 0) return results;

    const workers = @min(@max(1, workers_wanted), manifests.len);
    std.debug.assert(keep_arenas.len >= workers);
    var next: std.atomic.Value(usize) = .init(0);

    if (workers == 1) {
        WorkspaceWalk.run(io, checked_library, tests_dir_path, manifests, query, results, &keep_arenas[0], &next);
        return results;
    }

    const threads = try gpa.alloc(std.Thread, workers);
    defer gpa.free(threads);
    var spawned: usize = 0;
    errdefer for (threads[0..spawned]) |thread| thread.join();
    for (threads, 0..) |*thread, i| {
        thread.* = try std.Thread.spawn(compiler_stack.spawn_config, WorkspaceWalk.run, .{
            io,
            checked_library,
            tests_dir_path,
            manifests,
            query,
            results,
            &keep_arenas[i],
            &next,
        });
        spawned += 1;
    }
    for (threads) |thread| thread.join();
    return results;
}

test "workspace results merge in manifest order" {
    var first: WorkspaceResult = .{
        .failures = &.{.{
            .path = "a/linea.json",
            .what = "first",
            .expected = "one",
            .actual = "two",
        }},
        .offered = 3,
        .taken = .{ .applied = 2, .rewritten = 1 },
        .looked_for = 5,
    };
    first.properties.put(.importable, 1);
    first.passed_over.put(.accepted_offers, 1);

    var second: WorkspaceResult = .{
        .failures = &.{.{
            .path = "b/linea.json",
            .what = "second",
            .expected = "three",
            .actual = "four",
        }},
        .offered = 7,
        .taken = .{ .applied = 4, .declined = 3, .stopped = 2 },
        .looked_for = 11,
    };
    second.properties.put(.importable, 2);
    second.passed_over.put(.completion_recovers, 3);

    var failures: std.ArrayList(Failure) = .empty;
    defer failures.deinit(testing.allocator);
    var properties: std.EnumMap(Property, u32) = .{};
    var passed_over: std.EnumMap(Property, u32) = .{};
    var taken: Taken = .{};
    var offered: usize = 0;
    var looked_for: u32 = 0;

    try mergeWorkspaceResults(
        testing.allocator,
        &.{ first, second },
        &failures,
        &properties,
        &passed_over,
        &taken,
        &offered,
        &looked_for,
    );

    try testing.expectEqual(@as(usize, 2), failures.items.len);
    try testing.expectEqualStrings("a/linea.json", failures.items[0].path);
    try testing.expectEqualStrings("b/linea.json", failures.items[1].path);
    try testing.expectEqual(@as(u32, 3), properties.get(.importable).?);
    try testing.expectEqual(@as(u32, 1), passed_over.get(.accepted_offers).?);
    try testing.expectEqual(@as(u32, 3), passed_over.get(.completion_recovers).?);
    try testing.expectEqual(@as(usize, 10), offered);
    try testing.expectEqual(@as(u32, 16), looked_for);
    try testing.expectEqual(@as(u32, 6), taken.applied);
    try testing.expectEqual(@as(u32, 1), taken.rewritten);
    try testing.expectEqual(@as(u32, 3), taken.declined);
    try testing.expectEqual(@as(u32, 2), taken.stopped);
}

test "session results merge in script path order" {
    const results = [_]SessionResult{
        .{
            .failures = &.{.{
                .path = "a/session.jsonl",
                .what = "first",
                .expected = "one",
                .actual = "two",
            }},
            .deterministic = true,
            .held_once = false,
            .opened_and_beside = 2,
            .opened_differing = 1,
            .updated = &.{ "a/session.golden", "a/session.disk" },
            .logs = "error: first\n",
        },
        .{
            .failures = &.{.{
                .path = "b/session.jsonl",
                .what = "second",
                .expected = "three",
                .actual = "four",
            }},
            .deterministic = false,
            .held_once = true,
            .opened_and_beside = 3,
            .opened_alone = 4,
            .updated = &.{"b/session.golden"},
            .logs = "error: second\n",
        },
    };
    var failures: std.ArrayList(Failure) = .empty;
    defer failures.deinit(testing.allocator);
    var properties: std.EnumMap(Property, u32) = .{};
    var passed_over: std.EnumMap(Property, u32) = .{};
    var beside: u32 = 0;
    var differing: u32 = 0;
    var alone: u32 = 0;
    var stderr: std.Io.Writer.Allocating = .init(testing.allocator);
    defer stderr.deinit();

    try mergeSessionResults(
        testing.allocator,
        &results,
        &failures,
        &properties,
        &passed_over,
        &beside,
        &differing,
        &alone,
        &stderr.writer,
    );

    try testing.expectEqualStrings("a/session.jsonl", failures.items[0].path);
    try testing.expectEqualStrings("b/session.jsonl", failures.items[1].path);
    try testing.expectEqual(@as(u32, 1), properties.get(.deterministic).?);
    try testing.expectEqual(@as(u32, 1), passed_over.get(.deterministic).?);
    try testing.expectEqual(@as(u32, 1), properties.get(.held_once).?);
    try testing.expectEqual(@as(u32, 1), passed_over.get(.held_once).?);
    try testing.expectEqual(@as(u32, 5), beside);
    try testing.expectEqual(@as(u32, 1), differing);
    try testing.expectEqual(@as(u32, 4), alone);
    try testing.expectEqualStrings(
        "error: first\nupdated a/session.golden\nupdated a/session.disk\n" ++
            "error: second\nupdated b/session.golden\n",
        stderr.written(),
    );
}

test "session result merge returns the first script error" {
    const results = [_]SessionResult{
        .{ .logs = "first\n", .err = error.FirstScript },
        .{ .logs = "second\n", .err = error.SecondScript },
    };
    var failures: std.ArrayList(Failure) = .empty;
    defer failures.deinit(testing.allocator);
    var properties: std.EnumMap(Property, u32) = .{};
    var passed_over: std.EnumMap(Property, u32) = .{};
    var beside: u32 = 0;
    var differing: u32 = 0;
    var alone: u32 = 0;
    var stderr: std.Io.Writer.Allocating = .init(testing.allocator);
    defer stderr.deinit();

    try testing.expectError(error.FirstScript, mergeSessionResults(
        testing.allocator,
        &results,
        &failures,
        &properties,
        &passed_over,
        &beside,
        &differing,
        &alone,
        &stderr.writer,
    ));
    try testing.expectEqualStrings("first\n", stderr.written());
}

fn expectSessionResultsEqual(expected: []const SessionResult, actual: []const SessionResult) !void {
    try testing.expectEqual(expected.len, actual.len);
    for (expected, actual) |a, b| {
        try expectFailuresEqual(a.failures, b.failures);
        try testing.expectEqual(a.deterministic, b.deterministic);
        try testing.expectEqual(a.held_once, b.held_once);
        try testing.expectEqual(a.opened_and_beside, b.opened_and_beside);
        try testing.expectEqual(a.opened_differing, b.opened_differing);
        try testing.expectEqual(a.opened_alone, b.opened_alone);
        try testing.expectEqual(a.updated.len, b.updated.len);
        for (a.updated, b.updated) |x, y| try testing.expectEqualStrings(x, y);
        try testing.expectEqualStrings(a.logs, b.logs);
        try testing.expectEqual(a.err != null, b.err != null);
        if (a.err) |x| try testing.expectEqualStrings(@errorName(x), @errorName(b.err.?));
    }
}

test "session workers preserve serial results" {
    var tmp = testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    const matching = "fn main() -> UInt8 { 0 }\n";
    const scripts = [_]struct { dir: []const u8, malformed: []const u8, id: u8, uri: []const u8, text: []const u8 }{
        .{ .dir = "a", .malformed = "{", .id = 11, .uri = "main.lin", .text = matching },
        .{ .dir = "b", .malformed = "x", .id = 22, .uri = "missing.lin", .text = matching },
    };
    for (scripts) |script| {
        try tmp.dir.createDirPath(testing.io, script.dir);
        const requests = try std.fmt.allocPrint(
            testing.allocator,
            "{s}\n" ++
                "{{\"jsonrpc\":\"2.0\",\"id\":{d},\"method\":\"initialize\",\"params\":{{\"capabilities\":{{}}}}}}\n" ++
                "{{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didOpen\",\"params\":{{\"textDocument\":{{\"uri\":\"{s}\",\"languageId\":\"linea\",\"version\":1,\"text\":{f}}}}}}}\n" ++
                "{{\"jsonrpc\":\"2.0\",\"id\":{d},\"method\":\"shutdown\"}}\n" ++
                "{{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}}\n",
            .{ script.malformed, script.id, script.uri, std.json.fmt(script.text, .{}), script.id + 1 },
        );
        defer testing.allocator.free(requests);
        const session_path = try std.fmt.allocPrint(testing.allocator, "{s}/session.jsonl", .{script.dir});
        defer testing.allocator.free(session_path);
        try tmp.dir.writeFile(testing.io, .{
            .sub_path = session_path,
            .data = requests,
        });
        const golden_path = try std.fmt.allocPrint(testing.allocator, "{s}/session.golden", .{script.dir});
        defer testing.allocator.free(golden_path);
        try tmp.dir.writeFile(testing.io, .{ .sub_path = golden_path, .data = "wrong\n" });
    }
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "a/main.lin", .data = matching });

    const root = try std.fmt.allocPrint(testing.allocator, ".zig-cache/tmp/{s}", .{tmp.sub_path});
    defer testing.allocator.free(root);
    const paths = [_][]const u8{ "a/session.jsonl", "b/session.jsonl" };
    var serial_arenas = [_]std.heap.ArenaAllocator{std.heap.ArenaAllocator.init(std.heap.page_allocator)};
    defer for (&serial_arenas) |*arena| arena.deinit();
    const serial = try runSessions(testing.allocator, testing.io, test_library.get(), root, &paths, false, 1, &serial_arenas);
    defer testing.allocator.free(serial);
    var parallel_arenas = [_]std.heap.ArenaAllocator{
        std.heap.ArenaAllocator.init(std.heap.page_allocator),
        std.heap.ArenaAllocator.init(std.heap.page_allocator),
    };
    defer for (&parallel_arenas) |*arena| arena.deinit();
    const parallel = try runSessions(testing.allocator, testing.io, test_library.get(), root, &paths, false, 2, &parallel_arenas);
    defer testing.allocator.free(parallel);

    try expectSessionResultsEqual(serial, parallel);
    try testing.expectEqualStrings(
        "error: Failed to handle message: error.UnexpectedEndOfInput\n" ** 2,
        serial[0].logs,
    );
    try testing.expectEqualStrings(
        "error: Failed to handle message: error.SyntaxError\n" ** 2,
        serial[1].logs,
    );
}

test "parallel session updates stay within their session directories" {
    var tmp = testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    const disk_a = "fn main() -> UInt8 { 0 }\n";
    const opened_a = "fn main() -> UInt8 { 1 }\n";
    const scripts = [_]struct { dir: []const u8, id: u8, uri: []const u8, text: []const u8 }{
        .{ .dir = "a", .id = 31, .uri = "main.lin", .text = opened_a },
        .{ .dir = "b", .id = 41, .uri = "missing.lin", .text = disk_a },
    };
    for (scripts) |script| {
        try tmp.dir.createDirPath(testing.io, script.dir);
        const requests = try std.fmt.allocPrint(
            testing.allocator,
            "{{\"jsonrpc\":\"2.0\",\"id\":{d},\"method\":\"initialize\",\"params\":{{\"capabilities\":{{}}}}}}\n" ++
                "{{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didOpen\",\"params\":{{\"textDocument\":{{\"uri\":\"{s}\",\"languageId\":\"linea\",\"version\":1,\"text\":{f}}}}}}}\n" ++
                "{{\"jsonrpc\":\"2.0\",\"id\":{d},\"method\":\"shutdown\"}}\n" ++
                "{{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}}\n",
            .{ script.id, script.uri, std.json.fmt(script.text, .{}), script.id + 1 },
        );
        defer testing.allocator.free(requests);
        const session_path = try std.fmt.allocPrint(testing.allocator, "{s}/session.jsonl", .{script.dir});
        defer testing.allocator.free(session_path);
        try tmp.dir.writeFile(testing.io, .{ .sub_path = session_path, .data = requests });
        const golden_path = try std.fmt.allocPrint(testing.allocator, "{s}/session.golden", .{script.dir});
        defer testing.allocator.free(golden_path);
        try tmp.dir.writeFile(testing.io, .{ .sub_path = golden_path, .data = "wrong\n" });
    }
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "a/main.lin", .data = disk_a });
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "a/session.disk", .data = "wrong\n" });

    const root = try std.fmt.allocPrint(testing.allocator, ".zig-cache/tmp/{s}", .{tmp.sub_path});
    defer testing.allocator.free(root);
    const paths = [_][]const u8{ "a/session.jsonl", "b/session.jsonl" };
    var arenas = [_]std.heap.ArenaAllocator{
        std.heap.ArenaAllocator.init(std.heap.page_allocator),
        std.heap.ArenaAllocator.init(std.heap.page_allocator),
    };
    defer for (&arenas) |*arena| arena.deinit();
    const results = try runSessions(testing.allocator, testing.io, test_library.get(), root, &paths, true, 2, &arenas);
    defer testing.allocator.free(results);

    const golden_a = try tmp.dir.readFileAlloc(testing.io, "a/session.golden", testing.allocator, .unlimited);
    defer testing.allocator.free(golden_a);
    const golden_b = try tmp.dir.readFileAlloc(testing.io, "b/session.golden", testing.allocator, .unlimited);
    defer testing.allocator.free(golden_b);
    try testing.expect(std.mem.indexOf(u8, golden_a, "\"id\":31") != null);
    try testing.expect(std.mem.indexOf(u8, golden_a, "\"id\":41") == null);
    try testing.expect(std.mem.indexOf(u8, golden_b, "\"id\":41") != null);
    try testing.expect(std.mem.indexOf(u8, golden_b, "\"id\":31") == null);
    const disk = try tmp.dir.readFileAlloc(testing.io, "a/session.disk", testing.allocator, .unlimited);
    defer testing.allocator.free(disk);
    try testing.expect(std.mem.indexOf(u8, disk, opened_a) != null);
    try testing.expect(std.mem.indexOf(u8, disk, disk_a) != null);
    try testing.expectError(error.FileNotFound, tmp.dir.access(testing.io, "b/session.disk", .{}));

    var failures: std.ArrayList(Failure) = .empty;
    defer failures.deinit(testing.allocator);
    var properties: std.EnumMap(Property, u32) = .{};
    var passed_over: std.EnumMap(Property, u32) = .{};
    var beside: u32 = 0;
    var differing: u32 = 0;
    var alone: u32 = 0;
    var output: std.Io.Writer.Allocating = .init(testing.allocator);
    defer output.deinit();
    try mergeSessionResults(
        testing.allocator,
        results,
        &failures,
        &properties,
        &passed_over,
        &beside,
        &differing,
        &alone,
        &output.writer,
    );
    const expected = try std.fmt.allocPrint(
        testing.allocator,
        "updated {s}/a/session.golden\nupdated {s}/a/session.disk\nupdated {s}/b/session.golden\n",
        .{ root, root, root },
    );
    defer testing.allocator.free(expected);
    try testing.expectEqualStrings(expected, output.written());
}

test "session errors retain earlier logs and updates" {
    var tmp = testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    const requests =
        \\{
        \\{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"capabilities":{}}}
        \\{"jsonrpc":"2.0","id":2,"method":"shutdown"}
        \\{"jsonrpc":"2.0","method":"exit"}
        \\
    ;
    try tmp.dir.createDirPath(testing.io, "a");
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "a/session.jsonl", .data = requests });
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "a/session.golden", .data = "wrong\n" });
    try tmp.dir.createDirPath(testing.io, "a/session.disk");
    const root = try std.fmt.allocPrint(testing.allocator, ".zig-cache/tmp/{s}", .{tmp.sub_path});
    defer testing.allocator.free(root);
    var scratch = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer scratch.deinit();
    var keep = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer keep.deinit();

    const result = try checkSession(
        scratch.allocator(),
        keep.allocator(),
        testing.io,
        test_library.get(),
        root,
        "a/session.jsonl",
        true,
    );
    try testing.expect(result.err != null);
    try testing.expectEqual(@as(usize, 1), result.updated.len);

    var failures: std.ArrayList(Failure) = .empty;
    defer failures.deinit(testing.allocator);
    var properties: std.EnumMap(Property, u32) = .{};
    var passed_over: std.EnumMap(Property, u32) = .{};
    var beside: u32 = 0;
    var differing: u32 = 0;
    var alone: u32 = 0;
    var output: std.Io.Writer.Allocating = .init(testing.allocator);
    defer output.deinit();
    try testing.expectError(result.err.?, mergeSessionResults(
        testing.allocator,
        &.{result},
        &failures,
        &properties,
        &passed_over,
        &beside,
        &differing,
        &alone,
        &output.writer,
    ));
    const expected = try std.fmt.allocPrint(
        testing.allocator,
        "error: Failed to handle message: error.UnexpectedEndOfInput\n" ++
            "error: Failed to handle message: error.UnexpectedEndOfInput\n" ++
            "updated {s}/a/session.golden\n",
        .{root},
    );
    defer testing.allocator.free(expected);
    try testing.expectEqualStrings(expected, output.written());
}

test "workspace workers preserve serial results" {
    var tmp = testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    const files = [_]struct { path: []const u8, text: []const u8 }{
        .{ .path = "a/linea.json", .text = "{}" },
        .{ .path = "a/main.lin", .text = "fn main() -> UInt8 { 0 }\n" },
        .{ .path = "a/ledger/l.lin", .text = "pub fn alpha() -> UInt8 { 1 }\n" },
        .{ .path = "b/linea.json", .text = "{}" },
        .{ .path = "b/main.lin", .text = "fn main() -> UInt8 { 0 }\n" },
        .{ .path = "b/ledger/l.lin", .text = "pub fn beta() -> UInt8 { 2 }\n" },
    };
    for (files) |file| {
        if (std.fs.path.dirname(file.path)) |parent| {
            try tmp.dir.createDirPath(testing.io, parent);
        }
        try tmp.dir.writeFile(testing.io, .{ .sub_path = file.path, .data = file.text });
    }

    const root = try std.fmt.allocPrint(testing.allocator, ".zig-cache/tmp/{s}", .{tmp.sub_path});
    defer testing.allocator.free(root);
    var index = try lsp_workspace.Index.build(testing.allocator, testing.io, root);
    defer index.deinit();
    const query = try index.query();
    const manifests = [_][]const u8{ "a/linea.json", "b/linea.json" };

    var serial_arenas = [_]std.heap.ArenaAllocator{
        std.heap.ArenaAllocator.init(std.heap.page_allocator),
    };
    defer for (&serial_arenas) |*arena| arena.deinit();
    const serial = try runWorkspacePrograms(
        testing.allocator,
        testing.io,
        test_library.get(),
        root,
        &manifests,
        query,
        1,
        &serial_arenas,
    );
    defer testing.allocator.free(serial);

    var parallel_arenas = [_]std.heap.ArenaAllocator{
        std.heap.ArenaAllocator.init(std.heap.page_allocator),
        std.heap.ArenaAllocator.init(std.heap.page_allocator),
    };
    defer for (&parallel_arenas) |*arena| arena.deinit();
    const parallel = try runWorkspacePrograms(
        testing.allocator,
        testing.io,
        test_library.get(),
        root,
        &manifests,
        query,
        2,
        &parallel_arenas,
    );
    defer testing.allocator.free(parallel);

    try testing.expectEqual(serial.len, parallel.len);
    for (serial, parallel) |expected, actual| {
        try testing.expectEqual(expected.failures.len, actual.failures.len);
        for (expected.failures, actual.failures) |a, b| {
            try testing.expectEqualStrings(a.path, b.path);
            try testing.expectEqualStrings(a.what, b.what);
            try testing.expectEqualStrings(a.expected, b.expected);
            try testing.expectEqualStrings(a.actual, b.actual);
        }
        try testing.expect(std.meta.eql(expected.properties, actual.properties));
        try testing.expect(std.meta.eql(expected.passed_over, actual.passed_over));
        try testing.expectEqual(expected.offered, actual.offered);
        try testing.expect(std.meta.eql(expected.taken, actual.taken));
        try testing.expectEqual(expected.looked_for, actual.looked_for);
        try testing.expectEqual(expected.err, actual.err);
    }
}

test "generated results merge in seed order" {
    var first: GeneratedResult = .{
        .failures = &.{.{
            .path = "generated/7.lin",
            .what = "first",
            .expected = "one",
            .actual = "two",
        }},
        .generated = true,
        .diagnostics = "first diagnostic\n",
    };
    first.properties.put(.formatting, 1);
    first.rewrites.put(.renamed_bindings, 2);
    first.mutations.put(.unknown_variant, 3);
    first.damages.put(.field_offset, 4);

    var second: GeneratedResult = .{
        .failures = &.{.{
            .path = "generated/8.lin",
            .what = "second",
            .expected = "three",
            .actual = "four",
        }},
        .diagnostics = "second diagnostic\n",
    };
    second.properties.put(.normal_form, 5);

    var failures: std.ArrayList(Failure) = .empty;
    defer failures.deinit(testing.allocator);
    var generated: u32 = 0;
    var properties: std.EnumMap(Property, u32) = .{};
    var rewrites: std.EnumMap(Transform, u32) = .{};
    var mutations: std.EnumMap(Mutation, u32) = .{};
    var damages: std.EnumMap(Damage, u32) = .{};
    var diagnostics: std.Io.Writer.Allocating = .init(testing.allocator);
    defer diagnostics.deinit();

    try mergeGeneratedResults(
        testing.allocator,
        &.{ first, second },
        &failures,
        &generated,
        &properties,
        &rewrites,
        &mutations,
        &damages,
        &diagnostics.writer,
    );

    try testing.expectEqual(@as(usize, 2), failures.items.len);
    try testing.expectEqualStrings("generated/7.lin", failures.items[0].path);
    try testing.expectEqualStrings("generated/8.lin", failures.items[1].path);
    try testing.expectEqual(@as(u32, 1), generated);
    try testing.expectEqual(@as(u32, 1), properties.get(.formatting).?);
    try testing.expectEqual(@as(u32, 5), properties.get(.normal_form).?);
    try testing.expectEqual(@as(u32, 2), rewrites.get(.renamed_bindings).?);
    try testing.expectEqual(@as(u32, 3), mutations.get(.unknown_variant).?);
    try testing.expectEqual(@as(u32, 4), damages.get(.field_offset).?);
    try testing.expectEqualStrings(
        "first diagnostic\nsecond diagnostic\n",
        diagnostics.written(),
    );

    var error_diagnostics: std.Io.Writer.Allocating = .init(testing.allocator);
    defer error_diagnostics.deinit();

    try testing.expectError(
        error.FirstGeneratedError,
        mergeGeneratedResults(
            testing.allocator,
            &.{
                .{ .diagnostics = "first error\n", .err = error.FirstGeneratedError },
                .{ .diagnostics = "second error\n", .err = error.SecondGeneratedError },
            },
            &failures,
            &generated,
            &properties,
            &rewrites,
            &mutations,
            &damages,
            &error_diagnostics.writer,
        ),
    );
    try testing.expectEqualStrings("first error\n", error_diagnostics.written());
}

test "a generated result retains failures past its seed scratch" {
    var tmp = testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    const root = try std.fmt.allocPrint(testing.allocator, ".zig-cache/tmp/{s}", .{tmp.sub_path});
    defer testing.allocator.free(root);
    const runtime = try std.fs.path.join(testing.allocator, &.{ root, "missing-runtime.a" });
    defer testing.allocator.free(runtime);
    const cache = try OutcomeCache.init(testing.allocator, testing.io, null, root, runtime, null);
    defer testing.allocator.free(cache.dir);

    var scratch = std.heap.ArenaAllocator.init(testing.allocator);
    defer scratch.deinit();
    var keep = std.heap.ArenaAllocator.init(testing.allocator);
    defer keep.deinit();

    const result = try checkGeneratedProgram(
        scratch.allocator(),
        keep.allocator(),
        testing.io,
        .{ .library = test_library.get(), .cache = &cache, .env = .{
            .scratch = root,
            .runtime = runtime,
            .sanitize = null,
        } },
        0,
    );
    try testing.expect(result.failures.len > 0);
    _ = scratch.reset(.free_all);
    try testing.expectEqualStrings("generated/0.lin", result.failures[0].path);
    try testing.expect(result.failures[0].what.len > 0);
    try testing.expect(result.failures[0].expected.len > 0);
    try testing.expect(result.failures[0].actual.len > 0);
}

fn expectFailuresEqual(expected: []const Failure, actual: []const Failure) !void {
    try testing.expectEqual(expected.len, actual.len);
    for (expected, actual) |a, b| {
        try testing.expectEqualStrings(a.path, b.path);
        try testing.expectEqualStrings(a.what, b.what);
        try testing.expectEqualStrings(a.expected, b.expected);
        try testing.expectEqualStrings(a.actual, b.actual);
        try testing.expectEqual(a.case_ordinal, b.case_ordinal);
        try testing.expectEqual(a.case_order, b.case_order);
    }
}

test "generated workers preserve serial results" {
    var tmp = testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    const root = try std.fmt.allocPrint(testing.allocator, ".zig-cache/tmp/{s}", .{tmp.sub_path});
    defer testing.allocator.free(root);
    const runtime = try std.fs.path.join(testing.allocator, &.{ root, "missing-runtime.a" });
    defer testing.allocator.free(runtime);
    const cache = try OutcomeCache.init(testing.allocator, testing.io, null, root, runtime, null);
    defer testing.allocator.free(cache.dir);
    const settings: GeneratedSettings = .{ .library = test_library.get(), .cache = &cache, .env = .{
        .scratch = root,
        .runtime = runtime,
        .sanitize = null,
    } };

    var serial_arenas = [_]std.heap.ArenaAllocator{
        std.heap.ArenaAllocator.init(std.heap.page_allocator),
    };
    defer for (&serial_arenas) |*arena| arena.deinit();
    const serial = try runGeneratedPrograms(
        testing.allocator,
        testing.io,
        settings,
        0,
        2,
        1,
        &serial_arenas,
    );
    defer testing.allocator.free(serial);

    var parallel_arenas = [_]std.heap.ArenaAllocator{
        std.heap.ArenaAllocator.init(std.heap.page_allocator),
        std.heap.ArenaAllocator.init(std.heap.page_allocator),
    };
    defer for (&parallel_arenas) |*arena| arena.deinit();
    const parallel = try runGeneratedPrograms(
        testing.allocator,
        testing.io,
        settings,
        0,
        2,
        2,
        &parallel_arenas,
    );
    defer testing.allocator.free(parallel);

    try testing.expectEqual(serial.len, parallel.len);
    for (serial, parallel) |expected, actual| {
        try expectFailuresEqual(expected.failures, actual.failures);
        try testing.expectEqual(expected.generated, actual.generated);
        try testing.expectEqualStrings(expected.diagnostics, actual.diagnostics);
        try testing.expect(std.meta.eql(expected.properties, actual.properties));
        try testing.expect(std.meta.eql(expected.rewrites, actual.rewrites));
        try testing.expect(std.meta.eql(expected.mutations, actual.mutations));
        try testing.expect(std.meta.eql(expected.damages, actual.damages));
        try testing.expect(std.meta.eql(expected.passed_over, actual.passed_over));
        try testing.expect(std.meta.eql(expected.declined_settled_refs, actual.declined_settled_refs));
        try testing.expectEqual(expected.err, actual.err);
    }
}

/// What a client leaves in the buffer after accepting a snippet and tabbing
/// through it, and how many placeholders that was.
///
/// **The protocol's own semantics, simulated.** `${1:a}` is a stop holding the
/// text `a`, `$0` is where the cursor finishes, and a client that has tabbed
/// to the end has left every placeholder standing as its own text with the
/// syntax around it gone. `add(${1:a}, ${2:b})$0` is `add(a, b)`, which is
/// what the compiler is then asked about -- the snippet itself parses as
/// nothing, so applying it verbatim would fail every item for the same reason
/// and say nothing about any of them.
///
/// Written once, here, because it is the one thing in this run that is a
/// reading of the protocol rather than of the compiler: nothing in `src/lsp`
/// interprets a stop, and a second reading of the syntax would be a second
/// opinion about what a client does.
///
/// **Anything that is not a stop is copied as it stands**, which is what makes
/// this catch a malformed one: text the grammar does not describe survives
/// into the file, and the file is what gets checked.
const Reduced = struct {
    text: []const u8,
    stops: u32,
};

fn asAClientWouldLeave(
    gpa: std.mem.Allocator,
    written: []const u8,
    format: ?lsp.types.InsertTextFormat,
) !Reduced {
    if (format != .Snippet) return .{ .text = written, .stops = 0 };

    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(gpa);

    var stops: u32 = 0;
    var i: usize = 0;
    while (i < written.len) {
        if (written[i] == '\\' and i + 1 < written.len and written[i + 1] == '$') {
            // An escaped dollar is a dollar, and nothing else escapes here.
            try out.append(gpa, '$');
            i += 2;
            continue;
        }
        if (written[i] != '$') {
            try out.append(gpa, written[i]);
            i += 1;
            continue;
        }

        // `${n:text}`, a placeholder: the text is what is left standing.
        if (i + 1 < written.len and written[i + 1] == '{') {
            var k = i + 2;
            while (k < written.len and std.ascii.isDigit(written[k])) k += 1;
            if (k > i + 2 and k < written.len and written[k] == ':') {
                if (std.mem.indexOfScalarPos(u8, written, k, '}')) |end| {
                    try out.appendSlice(gpa, written[k + 1 .. end]);
                    stops += 1;
                    i = end + 1;
                    continue;
                }
            }
        } else {
            // `$n`, a stop holding nothing: the cursor rests there and no text
            // is left behind.
            var k = i + 1;
            while (k < written.len and std.ascii.isDigit(written[k])) k += 1;
            if (k > i + 1) {
                i = k;
                continue;
            }
        }

        try out.append(gpa, written[i]);
        i += 1;
    }
    return .{ .text = try out.toOwnedSlice(gpa), .stops = stops };
}

/// Accepting what a completion offers, over one program.
///
/// Three probes, because the three shapes are accepted into different text. A
/// name is inserted where an expression goes and stands alone there, so one
/// probe with an empty slot answers for every name a module exports. A module
/// is inserted before the member a reader is reaching for -- accepting
/// `ledger` and stopping leaves text mid-edit by design -- so each module gets
/// a probe whose slot is followed by a member of that module. And an operation
/// two traits declare is not inserted at all: it replaces the postfix call the
/// reader started, so the third probe holds one of those.
///
/// The result is judged against what the program reports **without** any probe.
/// A probe holding an unfinished `let` reports a rule of its own, and comparing
/// against that would let an accepted offer introduce the same rule and pass.
///
/// A leaf two modules of the program share is left out of the module probe:
/// both are offered under one label, the member written belongs to one of them,
/// and which the reader meant is not a question the property can settle. It is
/// the same exclusion the qualified fix probe makes and for the same reason.
///
/// A fourth probe holds the call. A function is offered as the call it takes,
/// and a call carrying a stop is the one thing a server sends that is not text
/// a compiler reads -- so every probe here is asked of a client that reads a
/// stop, and an offer carrying one is reduced the way a client would leave it
/// wherever it turns up.
///
/// **Bound:** one check per probe and one per item accepted. The probes are two
/// files plus one per module of the program the index says an import would
/// name.
fn acceptsCompletions(
    gpa: std.mem.Allocator,
    backing: std.mem.Allocator,
    checked_library: *const loader.CheckedLibrary,
    failures: *std.ArrayList(Failure),
    display_path: []const u8,
    query: lsp_workspace.Query,
    program: []const u8,
    files: []const InMemoryFile,
    taken: *Taken,
) !bool {
    var base = lsp_analysis.of(backing, backing, checked_library, files, program) catch return false;
    defer base.deinit();
    const before = try rulesReported(gpa, &base);

    var asked = false;
    if (try acceptOffered(
        gpa,
        backing,
        checked_library,
        failures,
        display_path,
        query,
        program,
        files,
        before,
        try completionProbe(gpa, program, ""),
        .names,
        taken,
    ) > 0) asked = true;

    if (try acceptOffered(
        gpa,
        backing,
        checked_library,
        failures,
        display_path,
        query,
        program,
        files,
        before,
        try dotProbe(gpa, program),
        .rewrites,
        taken,
    ) > 0) asked = true;

    if (try acceptOffered(
        gpa,
        backing,
        checked_library,
        failures,
        display_path,
        query,
        program,
        files,
        before,
        try callProbe(gpa, program),
        .calls,
        taken,
    ) > 0) asked = true;

    const modules = try modulesOffered(gpa, query, program);
    defer gpa.free(modules);

    for (modules, 0..) |m, i| {
        if (m.value.len == 0) continue;
        if (i > 0 and std.mem.eql(u8, m.leaf, modules[i - 1].leaf)) continue;
        if (i + 1 < modules.len and std.mem.eql(u8, m.leaf, modules[i + 1].leaf)) continue;

        const slot = try std.fmt.allocPrint(gpa, ".{s}", .{m.value});
        if (try acceptOffered(
            gpa,
            backing,
            checked_library,
            failures,
            display_path,
            query,
            program,
            files,
            before,
            try completionProbe(gpa, program, slot),
            .{ .module = m.leaf },
            taken,
        ) > 0) asked = true;
    }
    return asked;
}

/// Where a probe's breakage sits relative to the cursor.
const Broken = enum {
    /// Written where a statement goes, with the cursor at its end. That is
    /// where a reader typing the breakage would be, and it puts the cursor
    /// inside whatever the recovery left.
    at_a_statement,
    /// Written as a declaration before a whole function, with the cursor in
    /// that function's body. A declaration-level recovery has no statement to
    /// sit at, and this is the state it leaves a reader in: one declaration
    /// half-written, and a body being typed below it.
    before_a_function,
};

/// One shape the parser's recovery leaves behind, and text that reaches it.
const Recovery = struct {
    where: Broken,
    /// The rule the recovery site reports.
    ///
    /// Checked, because a probe that stopped reaching its site still parses,
    /// still answers, and still passes: the property would go on reporting a
    /// number while asking about text the parser never had to recover from.
    reports: []const u8,
    /// What is written.
    written: []const u8,
};

/// Every shape the parser can be left in, read off the parser's own recovery
/// sites rather than off what somebody thought to write.
///
/// There are four kinds of site, and each is here:
///
/// **`errExpr`** -- a region given up on, ended at the nearest of `;`, `)`,
/// `}` and eof. Reached from a token that starts no expression, from a body
/// whose `{` is missing, from a `copy` with no `(`, from a comparison chained
/// against another, from an arm with no pattern, and from a leading `.` naming
/// no variant. `tooDeeplyNested` leaves the same node from the descent limit.
///
/// **A delimiter left open** -- a call, a group, a block. Nothing is given up
/// on: the parser reports and reads on, and what it leaves is a node whose
/// extent runs to the enclosing terminator. `add(` is this one.
///
/// **The statement skip** in `endStatement` -- a statement no separator ended,
/// skipped forward to the next thing that may begin one.
///
/// **The declaration recoveries** -- a function with no body, a function
/// writing `-> ()`, `stepOverTypeIntruders` for a type whose braces held a
/// member, and the skip to the next declaration for a token that begins none.
///
/// The sites reached only by a trailing dot are not here. After a dot the
/// enclosing scope is deliberately not offered -- `c.` cannot be followed by a
/// local -- so what those shapes must answer is the receiver's members, which
/// is what the dot cases record.
const recovery_shapes = [_]Recovery{
    // A call the parser never closed, which is the shape the design names.
    .{ .where = .at_a_statement, .reports = "S-Paren", .written = "_recovery_probe(" },
    .{ .where = .at_a_statement, .reports = "S-Paren", .written = "(" },
    .{ .where = .at_a_statement, .reports = "S-Brace", .written = "{" },
    // A construct whose body is missing: `parseBraced` reports and gives up.
    .{ .where = .at_a_statement, .reports = "S-Brace", .written = "if true" },
    // A token that starts no expression, which is `parsePrimary`'s last arm.
    .{ .where = .at_a_statement, .reports = "S-Expr", .written = "+" },
    .{ .where = .at_a_statement, .reports = "S-Paren", .written = "copy" },
    .{ .where = .at_a_statement, .reports = "S-Chain", .written = "_held < 1 < 2" },
    .{ .where = .at_a_statement, .reports = "S-Match", .written = "match _held { => 0 }" },
    // A binding with no name, and one with no initialiser.
    .{ .where = .at_a_statement, .reports = "S-Name", .written = "let" },
    .{ .where = .at_a_statement, .reports = "S-Equals", .written = "let _next" },
    // Two statements on one line, which `endStatement` skips out of.
    .{ .where = .at_a_statement, .reports = "S-Separator", .written = "_held 1" },
    // A function with no body, and one writing the `-> ()` it should leave out.
    .{ .where = .before_a_function, .reports = "S-Brace", .written = "fn _headless() -> UInt8\n\n" },
    .{ .where = .before_a_function, .reports = "S-UnitResult", .written = "fn _unit() -> () {}\n\n" },
    // A type whose braces held what an `impl` holds, which
    // `stepOverTypeIntruders` skips through the member's own braces.
    .{
        .where = .before_a_function,
        .reports = "S-Struct",
        .written = "struct _Held {\n    fn _does() -> UInt8 {\n        0\n    }\n}\n\n",
    },
    // A token that begins no declaration, skipped to the next one that does.
    .{ .where = .before_a_function, .reports = "S-Entry", .written = "1\n\n" },
};

/// The function a recovery probe asks inside, and what its body declares: a
/// parameter and a local, so the enclosing scope holds names of both kinds
/// whatever the program around it holds. Every name begins with `_`, which
/// marks a declaration deliberately unused, so the probe adds no rule beyond
/// the one its breakage is about.
const recovery_head = "fn _recovery_probe(_given: UInt8) -> UInt8 {\n    let _held: UInt8 = 1\n    ";
const recovery_tail = "\n    0\n}\n";

/// A probe holding one breakage, with the cursor where a reader's would be.
/// The empty breakage is the whole-text probe: the same function, the same
/// cursor, and nothing for the parser to recover from.
fn recoveryProbe(
    gpa: std.mem.Allocator,
    program: []const u8,
    where: Broken,
    written: []const u8,
) !Probe {
    const text, const offset = switch (where) {
        .at_a_statement => .{
            try std.mem.concat(gpa, u8, &.{ recovery_head, written, recovery_tail }),
            recovery_head.len + written.len,
        },
        .before_a_function => .{
            try std.mem.concat(gpa, u8, &.{ written, recovery_head, recovery_tail }),
            written.len + recovery_head.len,
        },
    };
    return .{
        .file = .{
            .path = try std.fs.path.join(gpa, &.{ loader.dirOfEntry(program), "_recovery_probe.lin" }),
            .text = text,
        },
        .at = lsp.offsets.indexToPosition(text, offset, .@"utf-16"),
    };
}

/// What a probe is offered, by label, and what checking it reported.
const Answered = struct {
    labels: []const []const u8,
    rules: []const []const u8,
};

/// Asks one probe, over the program's own files.
///
/// The labels are duped because they are read after the analysis they came
/// from is released, and a label is a slice of what the checker held.
fn answerFor(
    gpa: std.mem.Allocator,
    backing: std.mem.Allocator,
    checked_library: *const loader.CheckedLibrary,
    query: lsp_workspace.Query,
    program: []const u8,
    files: []const InMemoryFile,
    probe: Probe,
) !?Answered {
    const with = try gpa.alloc(InMemoryFile, files.len + 1);
    @memcpy(with[0..files.len], files);
    with[files.len] = probe.file;

    var checked = lsp_analysis.of(backing, backing, checked_library, with, program) catch return null;
    defer checked.deinit();

    const asked = checked.fileNamed(probe.file.path) orelse return null;
    const answer = try lsp_completion.forPosition(
        gpa,
        &checked,
        asked,
        probe.at,
        .@"utf-16",
        query,
        program,
        .unsupported,
    ) orelse return null;

    var labels: std.ArrayList([]const u8) = .empty;
    for (answer.completion_list.items) |item| {
        try labels.append(gpa, try gpa.dupe(u8, item.label));
    }
    const reported = try rulesReported(gpa, &checked);

    var rules: std.ArrayList([]const u8) = .empty;
    for (reported.rules) |r| try rules.append(gpa, try gpa.dupe(u8, r));

    return .{
        .labels = try labels.toOwnedSlice(gpa),
        .rules = try rules.toOwnedSlice(gpa),
    };
}

/// Property: a completion answers from whatever the parser recovered.
///
/// Completion is asked from broken text far more often than from whole text,
/// so what it must answer over is the set of shapes the parser leaves --
/// `recovery_shapes`, which is read off the parser's recovery sites rather
/// than off the half-written constructs somebody thought to write a case for.
///
/// Two things per shape, because either alone passes on an answer that is
/// plainly wrong.
///
/// **The shape was reached.** The rule its site reports has to appear. A probe
/// that stopped reaching its site -- because the grammar took the text a
/// different way, or because the recovery moved -- parses, answers, and passes,
/// and the property would go on reporting its number for text the parser never
/// recovered from.
///
/// **Nothing the scope holds is missing.** Every label the same probe is
/// offered with its breakage taken out is offered with the breakage there. The
/// breakage only ever adds text, so the enclosing scope declares everything it
/// declared without it, and one fewer name offered is the cursor lookup having
/// given up rather than walked outward. What the scope holds is not enumerated
/// here: it is whatever the whole-text probe was answered, which is a second
/// answer from the same server rather than a list this property keeps.
///
/// Asked of every program the corpus holds, once per shape, so the two tallies
/// sum to the programs times the shapes.
///
/// **Bound:** one check of the program per shape, plus one for the whole-text
/// answer. Each probe is one file whose size is the shape's own text.
fn checkRecoveredCompletions(
    gpa: std.mem.Allocator,
    backing: std.mem.Allocator,
    checked_library: *const loader.CheckedLibrary,
    io: std.Io,
    failures: *std.ArrayList(Failure),
    display_path: []const u8,
    query: lsp_workspace.Query,
    program: []const u8,
    looked_for: *u32,
) !u32 {
    var docs: Documents = .{ .gpa = gpa };
    defer docs.deinit();
    const files = filesOfProgram(gpa, io, &docs, program) catch return 0;

    const whole = try recoveryProbe(gpa, program, .at_a_statement, "");
    const unbroken = try answerFor(gpa, backing, checked_library, query, program, files, whole) orelse return 0;

    // A whole-text answer of no names would make the second half of every
    // shape vacuous while the counter went on reporting the population. There
    // is nothing to look for, so the program is passed over rather than
    // counted as asked.
    if (unbroken.labels.len == 0) return 0;

    var asked: u32 = 0;
    for (recovery_shapes) |shape| {
        const probe = try recoveryProbe(gpa, program, shape.where, shape.written);
        const answered = try answerFor(gpa, backing, checked_library, query, program, files, probe) orelse continue;
        asked += 1;

        if (indexOfRule(answered.rules, shape.reports) == null) {
            try failures.append(gpa, .{
                .path = display_path,
                .what = "a probe reaches the recovery it was written for",
                .expected = try std.fmt.allocPrint(
                    gpa,
                    "[{s}] from `{s}`",
                    .{ shape.reports, shape.written },
                ),
                .actual = try std.fmt.allocPrint(gpa, "{d} rule(s), and none of them that", .{answered.rules.len}),
            });
            continue;
        }

        for (unbroken.labels) |label| {
            looked_for.* += 1;
            const found = for (answered.labels) |offered| {
                if (std.mem.eql(u8, offered, label)) break true;
            } else false;
            if (found) continue;

            try failures.append(gpa, .{
                .path = display_path,
                .what = "a completion answers from whatever the parser recovered",
                .expected = try std.fmt.allocPrint(
                    gpa,
                    "`{s}`, which the same point is offered without `{s}`",
                    .{ label, shape.written },
                ),
                .actual = try std.fmt.allocPrint(gpa, "{d} name(s), and none of them that", .{answered.labels.len}),
            });
            break;
        }
    }
    return asked;
}

/// Which items of a completion a probe is written to accept.
const Accepts = union(enum) {
    /// Every name a module nobody imported exports whose insertion is an
    /// expression. A function and a constant are values whatever their type,
    /// so the slot holds them; a type, a trait and a re-export are declined.
    names,
    /// One module, by the name an import of it binds. The slot's next
    /// characters are a member of that module, so accepting it leaves the
    /// qualified access a reader was reaching for.
    module: []const u8,
    /// Every item after a dot that carries an edit of its own and names the
    /// operation the probe itself declares.
    ///
    /// A postfix call two traits declare the operation for is [N-Ambiguous],
    /// and what the item writes is the written-out form over the range that
    /// call occupies. A range off by a byte leaves text that does not parse,
    /// which is the only way an edit of this shape goes wrong and the only way
    /// to see it is to apply it. Held to the probe's own operation for the
    /// reason `calls` is: every item after the dot is written over the same
    /// range, and an operation the prelude's traits offer for every type,
    /// such as `into`, would make this a property about whether the probe's
    /// type happens to implement `From`.
    rewrites,
    /// Every item naming a function the probe itself declares.
    ///
    /// A function is offered as the call it takes, with a stop holding each
    /// parameter's declared name, and what a client leaves after tabbing
    /// through it is text the compiler has to read. Held to the probe's own
    /// declarations rather than to every function in scope: what the server
    /// writes has the same shape for all of them, and the corpus's own
    /// parameter names would make this a property about whether they happen to
    /// be in scope at the call site.
    calls,
};

/// One file written to hold a cursor, and where in it the completion is asked.
const Probe = struct {
    file: InMemoryFile,
    at: lsp.types.Position,
};

/// A probe whose slot holds `written`, with the cursor before it.
///
/// The declarations are named with a leading `_`, which marks a name
/// deliberately unused, so the probe adds no rule of its own to the ones an
/// accepted offer is being judged by.
fn completionProbe(gpa: std.mem.Allocator, program: []const u8, written: []const u8) !Probe {
    const head = "fn _completion_probe() -> UInt8 {\n    let _held = ";
    const text = try std.fmt.allocPrint(gpa, "{s}{s}\n    0\n}}\n", .{ head, written });
    return .{
        .file = .{
            .path = try std.fs.path.join(gpa, &.{ loader.dirOfEntry(program), "_completion_probe.lin" }),
            .text = text,
        },
        .at = lsp.offsets.indexToPosition(text, head.len, .@"utf-16"),
    };
}

/// A probe declaring functions of a known arity, with the cursor in an empty
/// value slot.
///
/// Two of them, because the two arities are different offers: a function
/// taking nothing is written as an empty call and carries no snippet syntax at
/// all, and one taking arguments is written with a stop apiece. Written into
/// every program rather than looked for, so that what the property asks does
/// not depend on what the corpus happens to declare.
///
/// The parameters are named for what they are and prefixed with `_`, which
/// marks a declaration deliberately unused: the probe adds no rule of its own,
/// so every rule the accepted offer leaves behind is the offer's. Their names
/// are declared in a body nothing else can see, which is what makes the
/// undefined name each stop leaves the thing this property is entitled to
/// expect.
fn callProbe(gpa: std.mem.Allocator, program: []const u8) !Probe {
    const head =
        "fn _probe_takes_none() -> UInt8 {\n    0\n}\n\n" ++
        "fn _probe_takes_two(_first: UInt8, _second: UInt8) -> UInt8 {\n" ++
        "    _first + _second\n}\n\n" ++
        "fn _probe_calls() -> UInt8 {\n    let _held = ";
    const text = try std.fmt.allocPrint(gpa, "{s}\n    0\n}}\n", .{head});
    return .{
        .file = .{
            .path = try std.fs.path.join(gpa, &.{ loader.dirOfEntry(program), "_completion_call_probe.lin" }),
            .text = text,
        },
        .at = lsp.offsets.indexToPosition(text, head.len, .@"utf-16"),
    };
}

/// A probe holding a call the postfix form cannot settle, with the cursor
/// after its dot.
///
/// Written into every program rather than looked for in the ones that happen
/// to declare one operation in two traits: a corpus of programs that compile
/// holds no ambiguous call, and a property whose subject is the cases written
/// for it records those cases rather than the rule.
///
/// Every name in it begins with `_`, which marks a declaration deliberately
/// unused, so the only rule the probe adds is the [N-Ambiguous] it is about --
/// and taking that rule away is what accepting the offer has to do. Judged
/// against the program with no probe at all, like every other offer here.
fn dotProbe(gpa: std.mem.Allocator, program: []const u8) !Probe {
    const head =
        \\trait _ProbeOne {
        \\    fn _probed(self: Self) -> UInt8
        \\}
        \\
        \\trait _ProbeTwo {
        \\    fn _probed(self: Self) -> UInt8
        \\}
        \\
        \\struct _ProbeHeld {
        \\    n: UInt8,
        \\}
        \\
        \\impl _ProbeOne for _ProbeHeld {
        \\    fn _probed(self: Self) -> UInt8 {
        \\        self.n
        \\    }
        \\}
        \\
        \\impl _ProbeTwo for _ProbeHeld {
        \\    fn _probed(self: Self) -> UInt8 {
        \\        self.n
        \\    }
        \\}
        \\
        \\fn _probe_dot() -> UInt8 {
        \\    let _sits: _ProbeHeld = .{ n = 1 }
        \\    _sits.
    ;
    const text = try std.fmt.allocPrint(gpa, "{s}_probed()\n}}\n", .{head});
    return .{
        .file = .{
            .path = try std.fs.path.join(gpa, &.{ loader.dirOfEntry(program), "_completion_dot_probe.lin" }),
            .text = text,
        },
        .at = lsp.offsets.indexToPosition(text, head.len, .@"utf-16"),
    };
}

/// Applies every offer a probe was written to accept and says how many.
///
/// An item carries no edit for its own insertion, so what a client does with
/// it is written here: what the item says to insert goes in at the position
/// the request named, as a replacement of nothing. That is `insertText` where
/// the item carries one and the label otherwise, which is the protocol's own
/// rule -- an item offered under its own name inserts the qualified form, and
/// a property that wrote the label would be writing a spelling the server
/// never claimed would work. That plus the edits the item carries is the whole
/// of what accepting it writes.
///
/// **A snippet is applied as a client would apply it**, which is
/// `asAClientWouldLeave`: the placeholders standing as their own text and the
/// `${n:…}` around them gone. The snippet itself parses as nothing, so writing
/// it verbatim would fail every item of that shape for one reason and say
/// nothing about any of them.
///
/// **What that result is held to.** A placeholder is a parameter's declared
/// name, which is a name of the callee's body and not one the call site can
/// see, so the reduction is expected to leave exactly the undefined names it
/// wrote: one rule, `N-Undefined`, once per stop. Nothing else may appear.
/// Every way of writing a snippet wrong -- a bracket short, a stop left open,
/// a separator inside one -- is a syntax rule, and a syntax rule is not an
/// undefined name.
fn acceptOffered(
    gpa: std.mem.Allocator,
    backing: std.mem.Allocator,
    checked_library: *const loader.CheckedLibrary,
    failures: *std.ArrayList(Failure),
    display_path: []const u8,
    query: lsp_workspace.Query,
    program: []const u8,
    files: []const InMemoryFile,
    before: Reported,
    probe: Probe,
    accepts: Accepts,
    taken: *Taken,
) !u32 {
    const with = try gpa.alloc(InMemoryFile, files.len + 1);
    @memcpy(with[0..files.len], files);
    with[files.len] = probe.file;

    var checked = lsp_analysis.of(backing, backing, checked_library, with, program) catch return 0;
    defer checked.deinit();

    const file = indexOfFile(with, probe.file.path) orelse return 0;
    const asked = checked.fileNamed(probe.file.path) orelse return 0;

    const answer = try lsp_completion.forPosition(
        gpa,
        &checked,
        asked,
        probe.at,
        .@"utf-16",
        query,
        program,
        // Every probe is asked of a client that reads a stop, so an offer
        // carrying one is reduced and re-checked wherever it turns up rather
        // than only where a probe was written for it.
        .supported,
    ) orelse return 0;

    var applied: u32 = 0;
    for (answer.completion_list.items) |item| {
        switch (accepts) {
            // An item whose acceptance writes an import: the rest are names
            // already in scope, and inserting one of those is the question the
            // property about the scope chain puts rather than this one.
            .names => {
                if (item.additionalTextEdits == null) continue;
                if (!isAnExpression(item.kind)) {
                    taken.declined += 1;
                    continue;
                }
            },
            .module => |leaf| {
                if (item.additionalTextEdits == null) continue;
                if (item.kind != .Module) continue;
                if (!std.mem.eql(u8, item.label, leaf)) continue;
            },
            .rewrites => if (item.textEdit == null or !std.mem.startsWith(u8, item.label, "_probed")) continue,
            .calls => if (!std.mem.startsWith(u8, item.label, "_probe_takes_")) continue,
        }
        const carried = item.additionalTextEdits orelse &.{};

        const written = item.insertText orelse item.label;

        // What the item says to write, and where. An item carrying an edit of
        // its own replaces a range the server chose; one carrying none is
        // written in at the cursor, as a replacement of nothing.
        var own: lsp.types.TextEdit = .{
            .range = .{ .start = probe.at, .end = probe.at },
            .newText = written,
        };
        if (item.textEdit) |e| own = switch (e) {
            .text_edit => |t| t,
            .insert_replace_edit => |t| .{ .range = t.replace, .newText = t.newText },
        };

        // The insertion format governs the item's own text, whether it arrived
        // as `insertText` or as an edit, and nothing the item carries beside
        // it: an `additionalTextEdits` is plain text by the protocol's rule.
        const leaves = try asAClientWouldLeave(gpa, own.newText, item.insertTextFormat);
        own.newText = leaves.text;

        const edits = try gpa.alloc(lsp.types.TextEdit, carried.len + 1);
        @memcpy(edits[0..carried.len], carried);
        edits[carried.len] = own;
        // In order, because an applier walks them backwards so that no
        // replacement moves a range it has not used yet.
        std.mem.sort(lsp.types.TextEdit, edits, {}, beforeEdit);

        const after_files = try gpa.dupe(InMemoryFile, with);
        after_files[file] = .{
            .path = probe.file.path,
            .text = try lsp_rename.applyTo(gpa, probe.file.text, edits, .@"utf-16"),
        };

        var again = try lsp_analysis.of(backing, backing, checked_library, after_files, program);
        defer again.deinit();
        const after = try rulesReported(gpa, &again);

        applied += 1;
        taken.applied += 1;
        if (item.textEdit != null) taken.rewritten += 1;
        if (leaves.stops > 0) taken.stopped += 1;

        for (after.rules) |rule| {
            if (indexOfRule(before.rules, rule) != null) continue;
            // The undefined name a placeholder leaves is the one rule a
            // reduction is entitled to add, and it is added only where a stop
            // was written.
            if (leaves.stops > 0 and std.mem.eql(u8, rule, "N-Undefined")) continue;
            try failures.append(gpa, .{
                .path = display_path,
                .what = "accepting what the server offers leaves a program that checks",
                .expected = try std.fmt.allocPrint(
                    gpa,
                    "no rule `{s}` from accepting `{s}`",
                    .{ rule, own.newText },
                ),
                .actual = try std.fmt.allocPrint(gpa, "`{s}` after:\n{s}", .{ rule, after_files[file].text }),
            });
        }

        // And exactly one of them per stop. A reduction that dropped a
        // placeholder, doubled one, or left a name the call site can already
        // see would satisfy the rule above and change what was written.
        if (leaves.stops > 0 and after.reportsOf("N-Undefined") != before.reportsOf("N-Undefined") + leaves.stops) {
            try failures.append(gpa, .{
                .path = display_path,
                .what = "a stop leaves the name it was written with, and nothing else",
                .expected = try std.fmt.allocPrint(
                    gpa,
                    "{d} undefined name(s) from accepting `{s}`",
                    .{ leaves.stops, own.newText },
                ),
                .actual = try std.fmt.allocPrint(
                    gpa,
                    "{d} after:\n{s}",
                    .{
                        @as(i64, @intCast(after.reportsOf("N-Undefined"))) - @as(i64, @intCast(before.reportsOf("N-Undefined"))),
                        after_files[file].text,
                    },
                ),
            });
        }
    }
    return applied;
}

/// Whether an item of this kind names something a value slot holds.
///
/// A constant does, whatever its type. A function is a value only once its
/// uses settle every type parameter it has, and a probe binding one uses it
/// nowhere, so a generic function's probe would fail over the probe rather
/// than over the offer. A type, a trait and a re-export are not values, and
/// the slot a type name goes in is a different one.
fn isAnExpression(kind: ?lsp.types.completion.Item.Kind) bool {
    return switch (kind orelse return false) {
        .Constant => true,
        else => false,
    };
}

/// By where the edit starts, which is the order an applier reads.
fn beforeEdit(_: void, a: lsp.types.TextEdit, b: lsp.types.TextEdit) bool {
    if (a.range.start.line != b.range.start.line) return a.range.start.line < b.range.start.line;
    return a.range.start.character < b.range.start.character;
}

/// The file of a checked program a path names.
/// How a probe writes the name nothing has bound.
const Shape = enum {
    /// `ledger.size`, where the undefined name is what a member is reached
    /// through. This is the one an import answers.
    qualified,
    /// `ledger`, alone. An import binds a module and [M-Vis] makes qualified
    /// access the only way a module's name is reached, so nothing an import
    /// binds is reached here and the answer is to offer nothing.
    alone,
};

/// Applies every action the server offers over one program's files and says
/// whether it offered any.
fn offersFix(
    gpa: std.mem.Allocator,
    backing: std.mem.Allocator,
    checked_library: *const loader.CheckedLibrary,
    failures: *std.ArrayList(Failure),
    display_path: []const u8,
    query: lsp_workspace.Query,
    program: []const u8,
    files: []const InMemoryFile,
) !bool {
    var checked = lsp_analysis.of(backing, backing, checked_library, files, program) catch return false;
    defer checked.deinit();
    if (!checked.sink.hasErrors()) return false;

    const before = try rulesReported(gpa, &checked);

    const publication = try lsp_publish.Publication.init(gpa, &checked);
    var asked = false;
    var it = lsp_publish.files(&checked.program);
    while (it.next()) |file| {
        const path = checked.table.get(file).path;
        const which = indexOfFile(files, path) orelse continue;

        const diagnostics = try publication.forFile(gpa, file, .@"utf-16");
        const offered = try lsp_fix.forFile(
            gpa,
            &checked,
            file,
            path,
            diagnostics,
            .@"utf-16",
        );

        for (offered) |action| {
            asked = true;

            const after_files = try gpa.dupe(InMemoryFile, files);
            after_files[which] = .{
                .path = files[which].path,
                .text = try lsp_rename.applyTo(
                    gpa,
                    files[which].text,
                    action.code_action.edit.?.changes.?.map.get(path).?,
                    .@"utf-16",
                ),
            };

            var again = try lsp_analysis.of(backing, backing, checked_library, after_files, program);
            defer again.deinit();
            const after = try rulesReported(gpa, &again);

            // What an offer has to be worth is fewer of the mistake it was
            // offered for. Counting one rule -- the undefined name an import
            // answers -- held only while one fix existed: a `use` answers a
            // name reached through a trait nothing imported, which leaves the
            // undefined names where they were and would read as an offer that
            // achieved nothing.
            const answers = ruleAnswered(action) orelse "N-Undefined";
            const was = before.reportsOf(answers);
            if (after.reportsOf(answers) >= was) {
                try failures.append(gpa, .{
                    .path = display_path,
                    .what = "accepting what the server offers leaves a program that checks",
                    .expected = try std.fmt.allocPrint(
                        gpa,
                        "fewer than {d} {s} report(s) after `{s}`",
                        .{ was, answers, action.code_action.title },
                    ),
                    .actual = try std.fmt.allocPrint(gpa, "{d}", .{after.reportsOf(answers)}),
                });
            }

            for (after.rules) |rule| {
                if (indexOfRule(before.rules, rule) != null) continue;
                try failures.append(gpa, .{
                    .path = display_path,
                    .what = "accepting what the server offers leaves a program that checks",
                    .expected = try std.fmt.allocPrint(
                        gpa,
                        "no rule `{s}` reported before `{s}`",
                        .{ rule, action.code_action.title },
                    ),
                    .actual = try std.fmt.allocPrint(gpa, "`{s}` after it", .{rule}),
                });
            }
        }
    }
    return asked;
}

/// One module of a program, and a name it exports to reach through it.
const Reachable = struct {
    module: []const u8,
    /// The last element of the module's directory, which is what an import
    /// binds and therefore what a use of it writes.
    leaf: []const u8,
    /// A name it exports that is a value whatever its type, or empty where it
    /// exports none.
    value: []const u8,
};

/// The distinct modules of a program the index offers a name from, ordered by
/// the name an import would bind.
///
/// The entry module is left out: it is the program, so its names need no
/// import and there is nothing to ask about. Ordered by leaf so that the
/// modules an import would bind under one name sit together, which makes
/// "several modules answer to this name" the neighbour beside it rather than a
/// scan of the rest.
///
/// The one derivation of what modules a program holds that the properties
/// below read, so the two of them cannot come to disagree about it.
///
/// **Bound:** one pass over the program's entries and two sorts of them.
/// Sized by what the program exports.
fn modulesOffered(
    gpa: std.mem.Allocator,
    query: lsp_workspace.Query,
    program: []const u8,
) ![]Reachable {
    const entry = loader.dirOfEntry(program);

    var found: std.ArrayList(Reachable) = .empty;
    defer found.deinit(gpa);
    for (query.offers(program, "")) |e| {
        if (std.mem.eql(u8, e.module, entry)) continue;
        try found.append(gpa, .{
            .module = e.module,
            .leaf = std.fs.path.basename(e.module),
            .value = if (isAValue(e.kind)) e.name else "",
        });
    }
    std.mem.sort(Reachable, found.items, {}, byModule);

    var distinct: std.ArrayList(Reachable) = .empty;
    errdefer distinct.deinit(gpa);
    for (found.items, 0..) |r, i| {
        if (i > 0 and std.mem.eql(u8, r.module, found.items[i - 1].module)) continue;
        try distinct.append(gpa, r);
    }
    std.mem.sort(Reachable, distinct.items, {}, byLeaf);

    return distinct.toOwnedSlice(gpa);
}

/// Property: the index offers nothing the program cannot import.
///
/// Sitting under the program's source root is necessary and not sufficient. An
/// element the lexer does not read as an identifier, and a first element
/// naming the standard library, are each a directory no import reaches, and
/// both sit under the root -- so the check has to be the one the claim makes,
/// which is that the program can write an import naming the module. It is
/// settled by writing those imports and checking the program.
///
/// One file holding one import per module the index offers a name from, each
/// under an alias, so that two modules sharing a leaf are two bindings rather
/// than one [N-Duplicate]. Nothing names them, so [M-Unused] is what an import
/// that resolves reports and is the one rule passed over here; a path that
/// does not parse, or that names no directory, reports something else.
///
/// **Bound:** one check of the program and one of it with the file added, over
/// a file holding one line per module the program holds.
fn checkImportable(
    gpa: std.mem.Allocator,
    backing: std.mem.Allocator,
    checked_library: *const loader.CheckedLibrary,
    io: std.Io,
    failures: *std.ArrayList(Failure),
    display_path: []const u8,
    query: lsp_workspace.Query,
    program: []const u8,
) !void {
    const modules = try modulesOffered(gpa, query, program);
    defer gpa.free(modules);
    if (modules.len == 0) return;

    const entry = loader.dirOfEntry(program);

    var written: std.ArrayList(u8) = .empty;
    defer written.deinit(gpa);
    for (modules, 0..) |m, i| {
        const path = try lsp_workspace.importOf(gpa, entry, m.module) orelse {
            try failures.append(gpa, .{
                .path = display_path,
                .what = "the index offers nothing the program cannot import",
                .expected = try std.fmt.allocPrint(gpa, "an import naming {s}", .{m.module}),
                .actual = try gpa.dupe(u8, "no import written in this program names it"),
            });
            continue;
        };
        try written.print(gpa, "import {s} as _m{d}\n", .{ path, i });
    }
    if (written.items.len == 0) return;

    var docs: Documents = .{ .gpa = gpa };
    defer docs.deinit();
    const files = filesOfProgram(gpa, io, &docs, program) catch return;

    var checked = lsp_analysis.of(backing, backing, checked_library, files, program) catch return;
    defer checked.deinit();
    const before = try rulesReported(gpa, &checked);

    const with = try gpa.alloc(InMemoryFile, files.len + 1);
    @memcpy(with[0..files.len], files);
    with[files.len] = .{
        .path = try std.fs.path.join(gpa, &.{ entry, "_importable_probe.lin" }),
        .text = written.items,
    };

    var again = lsp_analysis.of(backing, backing, checked_library, with, program) catch return;
    defer again.deinit();
    const after = try rulesReported(gpa, &again);

    for (after.rules) |rule| {
        // An import nothing names is what every one of these is, which is the
        // observation rather than a failure of it.
        if (std.mem.eql(u8, rule, "M-Unused")) continue;
        if (indexOfRule(before.rules, rule) != null) continue;
        try failures.append(gpa, .{
            .path = display_path,
            .what = "the index offers nothing the program cannot import",
            .expected = try std.fmt.allocPrint(
                gpa,
                "no rule `{s}` from importing every module offered",
                .{rule},
            ),
            .actual = try std.fmt.allocPrint(gpa, "`{s}` after:\n{s}", .{ rule, written.items }),
        });
    }
}

/// The file a probe writes into a program's entry module, or null where the
/// program holds no module an import of it would name.
///
/// One line per such module, so a program of several is asked about all of
/// them at once rather than checked once each. The declaration is named with a
/// leading `_`, which is what marks a name deliberately unused, so the probe
/// adds no rule of its own to the ones the fix is being judged by.
///
/// What a member is reached through is a name the index says the module
/// exports, and a value one -- a constant, since a function is not a value and
/// naming one would be refused for that rather than for the missing import.
/// So the import alone decides what the probe reports.
///
/// A leaf two modules of the program share is left out of the qualified shape:
/// both are offered, either is what a reader meant, and the member written
/// belongs to one of them -- which would fail the property over an ambiguity
/// the fix is right to answer twice. It is written once in the shape that
/// names no member, because one name undefined once is one question.
///
/// **Bound:** one pass over the modules the program holds, which is what
/// `modulesOffered` costs and no more.
fn probeWriting(
    gpa: std.mem.Allocator,
    query: lsp_workspace.Query,
    program: []const u8,
    shape: Shape,
) !?InMemoryFile {
    const modules = try modulesOffered(gpa, query, program);
    defer gpa.free(modules);

    var written: std.ArrayList(u8) = .empty;
    errdefer written.deinit(gpa);
    try written.appendSlice(gpa, "fn _import_probe() -> UInt8 {\n");

    var lines: usize = 0;
    for (modules, 0..) |m, i| {
        // A leaf the lexer does not read as an identifier is one a probe
        // cannot write as a name. What is wrong with a module like that is
        // the question `checkImportable` puts.
        if (!try isIdentifier(gpa, m.leaf)) continue;

        const shared_before = i > 0 and std.mem.eql(u8, m.leaf, modules[i - 1].leaf);
        const shared_after = i + 1 < modules.len and std.mem.eql(u8, m.leaf, modules[i + 1].leaf);

        switch (shape) {
            .qualified => {
                if (shared_before or shared_after) continue;
                if (m.value.len == 0) continue;
                try written.print(gpa, "    let _held_{d} = {s}.{s}\n", .{ lines, m.leaf, m.value });
            },
            .alone => {
                if (shared_before) continue;
                try written.print(gpa, "    let _held_{d} = {s}\n", .{ lines, m.leaf });
            },
        }
        lines += 1;
    }
    if (lines == 0) {
        written.deinit(gpa);
        return null;
    }
    try written.appendSlice(gpa, "    0\n}\n");

    return .{
        .path = try std.fs.path.join(gpa, &.{ loader.dirOfEntry(program), "_import_probe.lin" }),
        .text = try written.toOwnedSlice(gpa),
    };
}

/// Whether a name of this kind is a value, which is what a probe can bind to a
/// local whatever its type.
///
/// A constant is one. A function is one only once its uses settle every type
/// parameter it has, so `let _held = m.helper` over a generic `helper` is
/// refused for what its uses leave open rather than for the import it is
/// missing, which is the opposite of what a probe is written to isolate.
fn isAValue(kind: lsp_exports.Kind) bool {
    return switch (kind) {
        .constant => true,
        .function, .enum_, .struct_, .trait_, .re_export, .newtype, .alias => false,
    };
}

/// By module, so one module's entries are one run, and then by whether the
/// name is a value and by the name itself -- so the member a probe reaches
/// through is the first of the run and is the same one on two runs over one
/// index.
fn byModule(_: void, a: Reachable, b: Reachable) bool {
    switch (std.mem.order(u8, a.module, b.module)) {
        .lt => return true,
        .gt => return false,
        .eq => {},
    }
    if ((a.value.len == 0) != (b.value.len == 0)) return a.value.len != 0;
    return std.mem.lessThan(u8, a.value, b.value);
}

/// By the name an import binds, so the modules that share one sit together.
/// The directory settles the rest, because two runs over one index would
/// otherwise write two different probes.
fn byLeaf(_: void, a: Reachable, b: Reachable) bool {
    switch (std.mem.order(u8, a.leaf, b.leaf)) {
        .lt => return true,
        .gt => return false,
        .eq => {},
    }
    return std.mem.lessThan(u8, a.module, b.module);
}

/// What a check reported, as the rules it named and how many of them were an
/// undefined name.
const Reported = struct {
    rules: []const []const u8,
    /// How many reports each rule drew, which is what says an offer was worth
    /// accepting: the rule it answers has to be reported less often after.
    reports: []const Count,

    const Count = struct {
        rule: []const u8,
        n: usize,
    };

    fn reportsOf(self: Reported, rule: []const u8) usize {
        for (self.reports) |held| {
            if (std.mem.eql(u8, held.rule, rule)) return held.n;
        }
        return 0;
    }
};

/// Read off what the server publishes rather than off the sink, so what the
/// property compares is what a reader is shown.
fn rulesReported(gpa: std.mem.Allocator, checked: *const lsp_analysis.Analysis) !Reported {
    const publication = try lsp_publish.Publication.init(gpa, checked);
    var rules: std.ArrayList([]const u8) = .empty;
    var reports: std.ArrayList(Reported.Count) = .empty;

    var it = lsp_publish.files(&checked.program);
    while (it.next()) |file| {
        for (try publication.forFile(gpa, file, .@"utf-16")) |d| {
            const code = d.code orelse continue;
            const rule = switch (code) {
                .string => |s| s,
                .number => continue,
            };
            if (indexOfRule(rules.items, rule) == null) try rules.append(gpa, rule);

            for (reports.items) |*held| {
                if (std.mem.eql(u8, held.rule, rule)) {
                    held.n += 1;
                    break;
                }
            } else try reports.append(gpa, .{ .rule = rule, .n = 1 });
        }
    }
    return .{ .rules = try rules.toOwnedSlice(gpa), .reports = try reports.toOwnedSlice(gpa) };
}

/// The rule an action was offered against, or null where it was offered
/// against none.
///
/// A quick fix carries the reports it answers, which is what the protocol has
/// it carry and what a client shows the action beside. So what an action is
/// for is read from the action rather than guessed from its title.
fn ruleAnswered(action: lsp.types.CodeAction.Result) ?[]const u8 {
    const held = action.code_action.diagnostics orelse return null;
    for (held) |d| {
        const code = d.code orelse continue;
        switch (code) {
            .string => |s| return s,
            .number => continue,
        }
    }
    return null;
}

fn indexOfRule(among: []const []const u8, rule: []const u8) ?usize {
    for (among, 0..) |seen, i| {
        if (std.mem.eql(u8, seen, rule)) return i;
    }
    return null;
}

fn indexOfFile(among: []const InMemoryFile, path: []const u8) ?usize {
    for (among, 0..) |f, i| {
        if (std.mem.eql(u8, f.path, path)) return i;
    }
    return null;
}

/// Property: a rename applied leaves a program that reports what it reported.
///
/// A rename is the one capability whose answer a client writes back into the
/// source, so the only thing that says it is right is compiling the result.
/// Every other check a server's answer gets here is a shape: a location
/// carrying a uri, a hint carrying a label. An edit list missing one of a
/// name's uses has exactly that shape and leaves a program that no longer
/// compiles, and nothing else in this run would notice.
///
/// One binding of every subject the case declares, not one local. A local is
/// the one subject whose every site is an expression; a type, a trait, a
/// function and a pattern's binder are written in places no expression covers,
/// and those are where an answer pointing at the wrong token or carrying a site
/// twice survives. Which of those subjects a rename will take is the server's
/// own answer -- a refusal is read here as one, and the cases beside each
/// refusal are what say it is the right one.
///
/// The first binding of each subject, for the reason the first local was chosen:
/// a property that searched for a binding the rename handles would be choosing
/// what it checks. A name beginning with `_` is passed over: the prefix says
/// the value is deliberately unused, so renaming away from it changes what the
/// program means rather than only what it is called.
///
/// Asked only where the case compiles. A program with a hole in it has names
/// that reach nothing, and what a rename of one should report is not a question
/// this asks.
///
/// **Bound:** one pass over the case's bindings to choose them, and then one
/// rename and one further check of the module per subject -- a fixed number of
/// each, since the subjects are a fixed set and only the first binding of each
/// is asked about.
fn checkRenameApplies(
    gpa: std.mem.Allocator,
    backing: std.mem.Allocator,
    io: std.Io,
    failures: *std.ArrayList(Failure),
    display_path: []const u8,
    case: Case,
    checked: *const lsp_analysis.Analysis,
) !bool {
    for (case.files) |f| {
        if (std.mem.indexOf(u8, f.text, fresh_name) != null) return false;
        if (std.mem.indexOf(u8, f.text, fresh_capitalised_name) != null) return false;
    }

    if (checked.sink.hasErrors()) return false;

    const ast = &checked.program.ast;
    const res = &checked.semantics.res;

    // Keyed by subject rather than gathered into a list of the subjects worth
    // asking about, so a subject added later is asked about instead of being
    // left out of a list nobody revisits.
    var first: std.EnumArray(RenameSubject, resolve_mod.BindingId) = .initFill(.none);
    for (0..res.bindingCount()) |i| {
        const b = resolve_mod.BindingId.at(@intCast(i));
        const at = res.declaringToken(b);
        if (at == TokenId.none) continue;
        if (at.index() >= ast.tokenCount()) continue;
        if (checked.semantics.expanded.isTemplateInterfaceToken(at)) continue;
        if (checked.library[ast.fileOf(at).index()]) continue;
        if (std.mem.startsWith(u8, ast.tokenText(at), "_")) continue;
        const slot = first.getPtr(subjectOf(ast, res.kindOf(b), res.declIfDeclared(b)));
        if (slot.* == resolve_mod.BindingId.none) slot.* = b;
    }

    var asked = false;
    var it = first.iterator();
    while (it.next()) |entry| {
        if (entry.value.* == resolve_mod.BindingId.none) continue;
        if (try renameHolds(gpa, backing, io, failures, display_path, case, checked, entry.value.*)) {
            asked = true;
        }
    }
    return asked;
}

test "rename validation allocation does not grow with borrowed source bytes" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    const padding = 64 * 1024;
    var editor_cost: [2]usize = undefined;
    var validation_cost: [2]usize = undefined;
    for ([_]usize{ 0, padding }, 0..) |comment_bytes, index| {
        const comment = try gpa.alloc(u8, comment_bytes);
        @memset(comment, 'x');
        const text = try std.fmt.allocPrint(gpa, "// {s}\nfn main() -> UInt8 {{\n    let value: UInt8 = 1\n    value\n}}\n", .{comment});
        const case: Case = .{
            .display_path = "main.lin",
            .stem = "main",
            .entry = "main.lin",
            .files = &.{.{ .path = "main.lin", .text = text }},
        };
        var editor_backing: Counting = .{ .under = testing.allocator, .allow_growth = false };
        var checked = try lsp_analysis.of(editor_backing.allocator(), editor_backing.allocator(), test_library.get(), case.files, case.entry);
        defer checked.deinit();
        try testing.expect(!checked.sink.hasErrors());
        const source_file = checked.fileNamed("main.lin").?;
        var target: resolve_mod.BindingId = .none;
        for (0..checked.semantics.res.bindingCount()) |i| {
            const binding = resolve_mod.BindingId.at(@intCast(i));
            if (checked.semantics.res.kindOf(binding) != .local) continue;
            const token_id = checked.semantics.res.declaringToken(binding);
            if (token_id != .none and token_id.index() < checked.program.ast.tokenCount() and
                checked.program.ast.fileOf(token_id) == source_file and
                std.mem.eql(u8, checked.program.ast.tokenText(token_id), "value"))
            {
                target = binding;
                break;
            }
        }
        try testing.expect(target != .none);
        var renamed_backing: Counting = .{ .under = testing.allocator, .allow_growth = false };
        var failures: std.ArrayList(Failure) = .empty;
        try testing.expect(try renameHolds(gpa, renamed_backing.allocator(), testing.io, &failures, case.display_path, case, &checked, target));
        try testing.expectEqual(@as(usize, 0), failures.items.len);
        editor_cost[index] = editor_backing.took;
        validation_cost[index] = renamed_backing.took;
    }
    // Compare source growth separately from semantic arenas and editor indexes.
    try testing.expectEqual(validation_cost[0], validation_cost[1]);
    try testing.expect(editor_cost[1] >= editor_cost[0] + padding);
}

test "case LSP properties share one analysis independent of the compiler" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    const text =
        \\fn main() -> UInt8 {
        \\    let value: UInt8 = 1
        \\    value
        \\}
    ;
    const case: Case = .{
        .display_path = "main.lin",
        .stem = "main",
        .entry = "main.lin",
        .files = &.{.{ .path = "main.lin", .text = text }},
    };

    var table: FileTable = .empty;
    var sink = Sink.init(gpa);
    var interner: Interner = .empty;
    const program = try loadFromMemory(gpa, &table, &sink, &interner, case.entry, case.files, .program, true, .borrow);
    try table.buildMaps(gpa);
    var settled = try checkProgram(gpa, testing.allocator, &program, &interner, &sink, .program);
    defer settled.deinit(gpa);
    try testing.expect(!sink.hasErrors());

    var checked = try lsp_analysis.of(gpa, gpa, test_library.get(), case.files, case.entry);
    defer checked.deinit();
    try testing.expect(&program.ast != &checked.program.ast);

    var failures: std.ArrayList(Failure) = .empty;
    defer failures.deinit(gpa);
    try checkPublished(gpa, &failures, case.display_path, &checked, &program, &table, &sink);
    try testing.expect(try checkRenameApplies(gpa, testing.allocator, testing.io, &failures, case.display_path, case, &checked));
    try testing.expectEqual(@as(usize, 0), failures.items.len);
}

test "rename validation preserves compiler diagnostics and manifest semantics" {
    const body = "fn main() -> UInt8 {\n    let value: UInt8 = 1\n    value + probe()\n}\n";
    const valid_probe = "fn probe() -> UInt8 { 0 }\n";
    for (0..5) |fixture| {
        var arena = std.heap.ArenaAllocator.init(testing.allocator);
        defer arena.deinit();
        const gpa = arena.allocator();
        const prefix = if (fixture == 4) try std.mem.replaceOwned(u8, gpa, body, "fn main", "export fn answer") else body;
        const baseline = try std.mem.concat(gpa, u8, &.{ prefix, valid_probe });
        const manifest: InMemoryFile = .{ .path = "linea.json", .text = "{\"kind\":\"library\"}" };
        const originals = [_]InMemoryFile{ .{ .path = "main.lin", .text = baseline }, manifest };
        var checked = try lsp_analysis.of(gpa, testing.allocator, test_library.get(), originals[0..if (fixture == 4) @as(usize, 2) else 1], "main.lin");
        defer checked.deinit();
        try testing.expect(!checked.sink.hasErrors());
        const source_file = checked.fileNamed("main.lin").?;
        var target: resolve_mod.BindingId = .none;
        for (0..checked.semantics.res.bindingCount()) |i| {
            const binding = resolve_mod.BindingId.at(@intCast(i));
            if (checked.semantics.res.kindOf(binding) != .local) continue;
            const token_id = checked.semantics.res.declaringToken(binding);
            if (token_id != .none and token_id.index() < checked.program.ast.tokenCount() and
                checked.program.ast.fileOf(token_id) == source_file and
                std.mem.eql(u8, checked.program.ast.tokenText(token_id), "value"))
            {
                target = binding;
                break;
            }
        }
        try testing.expect(target != .none);
        const probe = switch (fixture) {
            0, 4 => valid_probe,
            1 => "fn probe() -> UInt8 { missing }\n",
            2 => "struct Token { id: UInt8 }\nfn consume(sink x: Token) -> UInt8 { x.id }\nfn probe() -> UInt8 {\n    let x: Token = .{ id = 1 }\n    consume(x) + consume(x)\n}\n",
            3 => try std.mem.replaceOwned(u8, gpa, try readFileAlloc(testing.io, gpa, "tests/generics/a_width_reached_only_inside_a_body_is_held_to_the_limit.lin"), "fn main()", "fn probe()"),
            else => unreachable,
        };
        const input = try std.mem.concat(gpa, u8, &.{ prefix, probe });
        const case: Case = .{
            .display_path = "main.lin",
            .stem = "main",
            .entry = "main.lin",
            .files = &.{.{ .path = "main.lin", .text = input }},
            .manifest = if (fixture == 4) manifest else null,
        };
        const renamed = try std.mem.concat(gpa, u8, &.{ try std.mem.replaceOwned(u8, gpa, prefix, "value", fresh_name), probe });
        const expected_files = [_]InMemoryFile{ .{ .path = "main.lin", .text = renamed }, manifest };
        const expected_inputs = expected_files[0..if (fixture == 4) @as(usize, 2) else 1];
        var expected = try lsp_analysis.of(gpa, testing.allocator, test_library.get(), expected_inputs, case.entry);
        defer expected.deinit();
        try testing.expectEqual(fixture > 0 and fixture < 4, expected.sink.hasErrors());
        if (fixture == 3) {
            var table: FileTable = .empty;
            var sink = Sink.init(gpa);
            var interner: Interner = .empty;
            const program = try loadFromMemory(gpa, &table, &sink, &interner, case.entry, expected_inputs, .program, true, .borrow);
            var semantics = try checkProgram(gpa, testing.allocator, &program, &interner, &sink, .program);
            defer semantics.deinit(gpa);
            // This fixture must reach instantiation before it is rejected.
            try testing.expect(!sink.hasErrors());
        }
        var failures: std.ArrayList(Failure) = .empty;
        try testing.expect(try renameHolds(gpa, testing.allocator, testing.io, &failures, case.display_path, case, &checked, target));
        if (expected.sink.hasErrors()) {
            try testing.expectEqual(@as(usize, 1), failures.items.len);
            try expected.table.buildMaps(expected.arena.allocator());
            var rendered: std.Io.Writer.Allocating = .init(gpa);
            try render.renderAll(&rendered.writer, &expected.table, &expected.sink, .{ .color = .never });
            try testing.expectEqualStrings(rendered.written(), failures.items[0].actual);
        } else try testing.expectEqual(@as(usize, 0), failures.items.len);
    }
}

/// One binding renamed, written into every file the answer edits, and the
/// result checked. Whether the rename was applied at all, which is what makes
/// the case count towards this property.
///
/// A refusal is not a failure: it is the server saying the name is not the
/// programmer's to change, and which names those are is settled by the cases
/// written beside each refusal rather than decided a second time here.
///
/// The answer is held to at least one edit, which is what a rename returning
/// nothing at all would fail -- that answer leaves the program exactly as it
/// was, so the check below would pass it. An answer that rewrote the
/// declaration and dropped a use leaves the program naming something that is
/// not there, and the check below is what catches that.
fn renameHolds(
    gpa: std.mem.Allocator,
    backing: std.mem.Allocator,
    io: std.Io,
    failures: *std.ArrayList(Failure),
    display_path: []const u8,
    case: Case,
    checked: *const lsp_analysis.Analysis,
    target: resolve_mod.BindingId,
) !bool {
    const ast = &checked.program.ast;
    const res = &checked.semantics.res;

    const at = res.declaringToken(target);
    const file = ast.fileOf(at);
    const part = ast.partOfFile(file).?;
    const position = lsp.offsets.indexToPosition(part.source, ast.tokenSpan(at).start, .@"utf-16");
    const named = @tagName(subjectOf(ast, res.kindOf(target), res.declIfDeclared(target)));
    const renamed_to = freshNameFor(ast.tokenText(at));

    const answered = lsp_rename.forPosition(
        gpa,
        io,
        checked,
        file,
        position,
        .@"utf-16",
        "",
        renamed_to,
    ) catch |err| switch (err) {
        // Running out of memory is this run's failure and says nothing about
        // the server.
        error.OutOfMemory => return err,
        // Everything else the answer can be is a refusal.
        else => return false,
    };
    const edit = answered orelse {
        try failures.append(gpa, .{
            .path = display_path,
            .what = "the token a name is declared at names that name",
            .expected = try std.fmt.allocPrint(gpa, "an edit for the {s} `{s}`", .{ named, ast.tokenText(at) }),
            .actual = "null",
        });
        return true;
    };
    defer lsp_rename.free(gpa, edit);

    const changes = edit.changes.?;
    var written: usize = 0;
    for (changes.map.values()) |e| written += e.len;
    if (written == 0) {
        try failures.append(gpa, .{
            .path = display_path,
            .what = "a rename changes the declaration and every use of it",
            .expected = try std.fmt.allocPrint(
                gpa,
                "at least one edit for the {s} `{s}`",
                .{ named, ast.tokenText(at) },
            ),
            .actual = try std.fmt.allocPrint(gpa, "{d} file(s), 0 edit(s)", .{changes.map.count()}),
        });
        return true;
    }

    // The source and what the loader reads beside it: a renamed program is the
    // same root as the one it was renamed from, holding the same files, and
    // reloading it without what marks that root reads a library as a program.
    const after = try gpa.dupe(InMemoryFile, try inputsOf(gpa, case));
    defer gpa.free(after);

    var rewritten: std.ArrayList([]u8) = .empty;
    defer {
        for (rewritten.items) |text| gpa.free(text);
        rewritten.deinit(gpa);
    }

    // Every file the answer names, not the one the declaration sits in: a
    // `pub` name is declared in one file of a module and used in the others,
    // and applying one file's edits alone leaves the rest naming what is no
    // longer there.
    var it = changes.map.iterator();
    while (it.next()) |entry| {
        const path = try lsp_uri.pathOf(gpa, entry.key_ptr.*);
        defer gpa.free(path);
        for (after[0..case.files.len], case.files) |*a, f| {
            if (!std.mem.eql(u8, f.path, path)) continue;
            const text = try lsp_rename.applyTo(gpa, f.text, entry.value_ptr.*, .@"utf-16");
            try rewritten.append(gpa, text);
            a.* = .{ .path = f.path, .text = text };
        }
    }

    // The edits remain alive until this check ends. Only compiler diagnostics
    // are consumed; no editor indexes or owned source copy are needed.
    var arena = std.heap.ArenaAllocator.init(backing);
    defer arena.deinit();
    const a = arena.allocator();
    var table: FileTable = .empty;
    var sink = Sink.init(a);
    var interner: Interner = .empty;
    const program = try loadFromMemory(a, &table, &sink, &interner, case.entry, after, .program, true, .borrow);
    _ = try loader.checkWhole(a, backing, &program, &interner, &sink, .program);

    if (sink.hasErrors()) {
        try table.buildMaps(a);
        var why: std.Io.Writer.Allocating = .init(gpa);
        try render.renderAll(&why.writer, &table, &sink, .{ .color = .never });
        try failures.append(gpa, .{
            .path = display_path,
            .what = "a program with a rename applied still compiles",
            .expected = try std.fmt.allocPrint(
                gpa,
                "no error, as before the {s} `{s}` became `{s}`",
                .{ named, ast.tokenText(at), renamed_to },
            ),
            .actual = why.written(),
        });
    }
    return true;
}

/// Property: every name reaches a binding the scope tree makes visible where
/// that name was written, and the tree makes nothing else visible there.
///
/// Membership alone says only half of it. A chain that puts a binding *higher*
/// than the scope that declared it still contains every name's own target, so
/// asking whether the target is visible passes on a tree that makes far too
/// much visible -- the parameter scope can be deleted outright, dropping every
/// function's parameters into the module scope they share, and every name
/// still reaches what it reached.
///
/// The other half is asked of parameter scopes, because a parameter is the one
/// binding the resolver tags with an owner as it walks declarations, and that
/// tag is settled without consulting the scope stack. So the two records are
/// independent, and comparing them is not the chain answering about itself.
/// Callable bodies may nest: a lambda body sees its own parameter scope and the
/// enclosing callable scopes so capture can be diagnosed. What must not happen
/// is one scope declaring parameters owned by two bodies. That is the shape
/// produced by dropping a parameter scope, and it makes sibling bodies see one
/// another's parameters.
///
/// Asked of `name_ref` and of nothing else, because the chain is what answers
/// one: a selection reaches into a namespace the chain does not hold, and
/// `a.f` is asked about through its own base, which is a name.
///
/// Costs the names of the program times what is visible at each -- the same
/// bound the membership half already had, since it scans that answer too.
fn checkNamesInScope(
    gpa: std.mem.Allocator,
    failures: *std.ArrayList(Failure),
    display_path: []const u8,
    ast: *const Ast,
    res: *const Resolution,
) !void {
    var visible: std.ArrayList(resolve_mod.BindingId) = .empty;
    defer visible.deinit(gpa);
    var visible_scope = resolve_mod.ScopeId.none;

    for (0..res.scopes.len) |i| {
        const sc = resolve_mod.ScopeId.at(@intCast(i));
        var owner: ?resolve_mod.ParameterOwner = null;
        for (res.declaredIn(sc)) |b| {
            if (res.kindOf(b) != .parameter) continue;
            const of = res.parameterOwner(b);
            if (owner == null) {
                owner = of;
                continue;
            }
            if (std.meta.eql(of, owner.?)) continue;
            try failures.append(gpa, .{
                .path = display_path,
                .what = "one parameter scope belongs to one callable body",
                .expected = try std.fmt.allocPrint(gpa, "every parameter declared in scope {d} has one owner", .{sc.index()}),
                .actual = try std.fmt.allocPrint(gpa, "binding {d} belongs to another callable body", .{b.index()}),
            });
            break;
        }
    }

    for (0..ast.exprCount()) |i| {
        const e: ExprId = .at(@intCast(i));
        if (ast.exprTag(e) != .name_ref) continue;

        const target = res.targetOf(e);
        if (target == resolve_mod.BindingId.none) continue;

        const spelling = ast.tokenText(res.spelledAt(e));
        const sc = res.scopeOfExpr(e);
        if (sc == .none) {
            try failures.append(gpa, .{
                .path = display_path,
                .what = "a name that reached a binding was resolved in a scope",
                .expected = try std.fmt.allocPrint(gpa, "a scope for `{s}`", .{spelling}),
                .actual = try gpa.dupe(u8, "none recorded"),
            });
            continue;
        }

        // Consecutive names often share a scope. Its immutable visibility list
        // stays valid until the next name belongs to a different scope.
        if (sc != visible_scope) {
            try res.visibleIn(gpa, sc, &visible);
            visible_scope = sc;
        }
        if (std.mem.indexOfScalar(resolve_mod.BindingId, visible.items, target) == null) {
            try failures.append(gpa, .{
                .path = display_path,
                .what = "a name reaches a binding the scope it sits in makes visible",
                .expected = try std.fmt.allocPrint(gpa, "`{s}` reaches binding {d}", .{ spelling, target.index() }),
                .actual = try std.fmt.allocPrint(gpa, "scope {d} makes {d} bindings visible, and that is not one", .{
                    sc.index(),
                    visible.items.len,
                }),
            });
        }
    }
}

test "scope membership checks every reference and preserves failure order" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    const source: Source = .{ .path = "scope.lin", .text =
        \\fn first(left: UInt8) -> UInt8 { left }
        \\fn second(right: UInt8) -> UInt8 { right }
        \\fn main() -> UInt8 { first(second(0)) }
    };
    var sink = Sink.init(gpa);
    var interner: Interner = .empty;
    const tokens = try tokenize(gpa, &source, .from(0), &sink, &interner);
    var ast = try parse(gpa, &source, .from(0), tokens, &sink);
    var resolved = try resolveTree(gpa, &ast, &sink);
    try testing.expect(!sink.hasErrors());
    var failures: std.ArrayList(Failure) = .empty;
    try checkNamesInScope(gpa, &failures, source.path, &ast, &resolved.resolution);
    try testing.expectEqual(@as(usize, 0), failures.items.len);

    const targets = try gpa.dupe(resolve_mod.BindingId, resolved.resolution.targets);
    var left: ExprId = .none;
    var right: ExprId = .none;
    for (0..ast.exprCount()) |i| {
        const e = ExprId.at(@intCast(i));
        if (ast.exprTag(e) != .name_ref) continue;
        const name = ast.tokenText(ast.exprMain(e));
        if (std.mem.eql(u8, name, "left")) left = e;
        if (std.mem.eql(u8, name, "right")) right = e;
    }
    try testing.expect(left != .none and right != .none);
    targets[left.index()] = resolved.resolution.targetOf(right);
    targets[right.index()] = resolved.resolution.targetOf(left);
    var wrong = resolved.resolution;
    wrong.targets = targets;
    try checkNamesInScope(gpa, &failures, source.path, &ast, &wrong);
    try testing.expectEqual(@as(usize, 2), failures.items.len);
    try testing.expect(std.mem.startsWith(u8, failures.items[0].expected, "`left`"));
    try testing.expect(std.mem.startsWith(u8, failures.items[1].expected, "`right`"));
}

/// Which parameter each of a call's arguments fills, worked out from the tree
/// and the callee's declaration.
///
/// A second implementation of the pairing on purpose. The hints this is
/// compared against are built from what the checker recorded, so a property
/// that read the same record back would be comparing an answer with itself and
/// asserting nothing at all -- the one shape of check this compiler keeps
/// finding. The rule is short enough to state twice, and stating it twice is
/// what makes the comparison a comparison.
///
/// Three rules and no more: a positional argument fills the parameter at its
/// own position counting from the first; an argument that names a parameter
/// fills the one it names, wherever that sits; and the receiver of a postfix
/// call fills the first, because `a.of()` is `Measure.of(a)`.
///
/// False where no such pairing exists -- a name no parameter carries, a
/// parameter filled twice, a positional argument after a named one, more
/// arguments than parameters, a parameter neither filled nor left to a
/// default. Those are the calls the language refuses, and a refused call has
/// no pairing for a hint to sit against.
fn pairArguments(
    gpa: std.mem.Allocator,
    ast: *const Ast,
    call: ExprId,
    /// Whether the call was written with a dot, which is what puts an argument
    /// in front of the ones inside the parentheses.
    postfix: bool,
    params: []const node_mod.Param,
    /// Filled with one entry per parameter -- the expression that fills it, or
    /// `.none` where the call left it to its default. The caller's, so the
    /// space is the widest call's arity rather than an allocation per hint.
    slots: *std.ArrayList(ExprId),
) !bool {
    const args = ast.call(call).args;
    const names = ast.callNames(call);
    if (names.len != args.len) return false;

    try slots.resize(gpa, params.len);
    @memset(slots.items, ExprId.none);

    // Where the next positional argument lands.
    var next: usize = 0;

    if (postfix) {
        if (params.len == 0) return false;
        // The receiver is what was written before the dot, with any
        // parentheses around it dropped: the argument the call takes is the
        // expression inside them.
        const callee = postfixSelection(ast, ast.call(call).callee);
        if (callee == ExprId.none) return false;
        const receiver = ast.withoutGroups(ast.unaryOperand(callee));
        if (receiver == ExprId.none) return false;
        slots.items[0] = receiver;
        next = 1;
    }

    var named_one = false;
    for (args, names) |a, name| {
        if (name == TokenId.none) {
            // Position is what says which parameter a positional argument
            // fills, and it says nothing once a name has been written.
            if (named_one or next >= params.len) return false;
            if (slots.items[next] != ExprId.none) return false;
            slots.items[next] = a;
            next += 1;
            continue;
        }
        named_one = true;

        // The parameter the name spells, found by scanning the callee's own
        // parameters -- a list as long as the call is wide.
        const wanted = ast.tokenName(name);
        const at = for (params, 0..) |p, k| {
            if (ast.tokenName(p.name) == wanted) break k;
        } else return false;

        if (slots.items[at] != ExprId.none) return false;
        slots.items[at] = a;
    }

    for (slots.items, params) |s, p| {
        if (s == ExprId.none and p.default == ExprId.none) return false;
    }
    return true;
}

fn checkParameterHints(
    gpa: std.mem.Allocator,
    failures: *std.ArrayList(Failure),
    display_path: []const u8,
    ast: *const Ast,
    typing: *const Typing,
) !void {
    // The property reads the index frozen alongside the checked records.
    const calls = &typing.call_index;

    // One call's parameters, refilled per hint. Sized by the arity of the call
    // being asked about rather than by anything the program holds.
    var slots: std.ArrayList(ExprId) = .empty;
    defer slots.deinit(gpa);

    for (ast.parts) |*part| {
        const found = try lsp_hints.parametersInFile(gpa, ast, typing, calls, part);
        defer {
            for (found) |h| gpa.free(h.label);
            gpa.free(found);
        }

        for (found) |h| {
            const normal = calls.callOf(typing, h.call);
            const recovered = calls.recoveredArgsOf(typing, h.call);
            const signature = if (normal) |call| switch (call.target) {
                .declared => |decl| decl,
                .closure_recovery, .array_view, .array_length, .closure, .indirect, .generic_callable, .erased => node_mod.DeclId.none,
            } else if (recovered.len > 0) recovered[0].target else node_mod.DeclId.none;
            const params = if (signature == node_mod.DeclId.none) &[_]node_mod.Param{} else ast.declParams(signature);

            if (h.param >= params.len) {
                try failures.append(gpa, .{
                    .path = display_path,
                    .what = "a hint names a parameter the call reaches",
                    .expected = try std.fmt.allocPrint(gpa, "position {d} of {d}", .{ h.param, params.len }),
                    .actual = try gpa.dupe(u8, h.label),
                });
                continue;
            }

            // Accepted calls are checked independently against their syntax.
            // Rejected calls have no complete pairing to reconstruct, so their
            // hint is held directly to the checker's recoverable relation.
            if (normal != null and try pairArguments(gpa, ast, h.call, calls.postfixOf(typing, h.call) != null, params, &slots)) {
                if (slots.items[h.param] != h.argument) {
                    try failures.append(gpa, .{
                        .path = display_path,
                        .what = "a hint sits against the argument its parameter takes",
                        .expected = try std.fmt.allocPrint(gpa, "expression {d}", .{slots.items[h.param].index()}),
                        .actual = try std.fmt.allocPrint(gpa, "{s} against {d}", .{ h.label, h.argument.index() }),
                    });
                    continue;
                }
            } else if (normal == null) {
                const paired = for (recovered) |argument| {
                    if (argument.parameter == h.param and argument.argument == h.argument) break true;
                } else false;
                if (!paired) {
                    try failures.append(gpa, .{
                        .path = display_path,
                        .what = "a recovered hint sits against the argument its parameter takes",
                        .expected = try std.fmt.allocPrint(gpa, "parameter {d} with expression {d}", .{ h.param, h.argument.index() }),
                        .actual = try std.fmt.allocPrint(gpa, "{s} against {d}", .{ h.label, h.argument.index() }),
                    });
                    continue;
                }
            }

            const param = params[h.param];
            const declared: ?node_mod.Convention = if (ast.paramSpellsConvention(param)) param.convention else null;
            if (conventionShown(h.label) != declared) {
                try failures.append(gpa, .{
                    .path = display_path,
                    .what = "a hint shows the convention its parameter declares",
                    .expected = try gpa.dupe(u8, if (declared) |c| @tagName(c) else "none"),
                    .actual = try gpa.dupe(u8, h.label),
                });
                continue;
            }

            // The expression ownership decides an argument's position with. A
            // hint shows `sink` exactly where that says the call takes the
            // value, which is the sentence a reader acts on.
            const takes = param.convention == .sink;
            if ((conventionShown(h.label) == .sink) != takes) {
                try failures.append(gpa, .{
                    .path = display_path,
                    .what = "a hint says `sink` where the call takes the value",
                    .expected = try gpa.dupe(u8, if (takes) "taken" else "lent"),
                    .actual = try gpa.dupe(u8, h.label),
                });
            }
        }
    }
}

test "recovered parameter hints distinguish duplicate arguments" {
    const gpa = testing.allocator;
    const path = "main.lin";
    var checked = try lsp_analysis.of(gpa, gpa, test_library.get(), &.{.{ .path = path, .text =
        \\fn add(a: UInt8, b: UInt8) -> UInt8 { a + b }
        \\fn main() -> UInt8 {
        \\    let _twice = add(a: 1, a: 2, b: 3)
        \\    add(1, 2, a: 3)
        \\}
        \\
    }}, path);
    defer checked.deinit();
    try testing.expectEqual(@as(u32, 2), checked.sink.error_count);

    var failures: std.ArrayList(Failure) = .empty;
    try checkParameterHints(gpa, &failures, path, &checked.program.ast, &checked.semantics.typing);
    try testing.expectEqual(@as(usize, 0), failures.items.len);
}

/// No two extents the tree records cross: one holds the other, or they are
/// apart.
///
/// The position index sweeps the tokens with a stack, which is sound only if
/// that is true of every tree. It is a property of the parser rather than of
/// the index -- an extent is where a rule began and where it had reached, and
/// the cursor only moves forward -- so the place to hold it is over the corpus,
/// which is mostly programs the parser recovered in. A crossing pair would not
/// show up as a wrong node under a cursor; it shows up as a node handed out as
/// the parent of something it does not contain, which is what a cursor on a
/// callee reads to reach its call.
///
/// **Bound:** one index build for the case -- one pass over its tokens and one
/// sort of its nodes -- and one pass over the entries.
fn checkExtentsNest(
    gpa: std.mem.Allocator,
    failures: *std.ArrayList(Failure),
    display_path: []const u8,
    ast: *const Ast,
) !void {
    var index = try lsp_positions.Index.build(gpa, ast);
    defer index.deinit(gpa);

    const found = try index.crossing(gpa) orelse return;
    try failures.append(gpa, .{
        .path = display_path,
        .what = "no extent the tree records crosses another",
        .expected = try std.fmt.allocPrint(gpa, "tokens {d}..{d} held or apart", .{
            found.inner.start,
            found.inner.end,
        }),
        .actual = try std.fmt.allocPrint(gpa, "tokens {d}..{d} ends inside it", .{
            found.outer.start,
            found.outer.end,
        }),
    });
}

/// Which function was written over a token, or null where none was.
///
/// A binary search over the functions in token order, which is what keeps this
/// linear over the program: a scan per name would read every function for every
/// name written, and both grow with the module. Functions do not nest, so the
/// last one beginning at or before a token is the only candidate.
fn functionHolding(ast: *const Ast, functions: []const node_mod.DeclId, at: TokenId) ?usize {
    var lo: usize = 0;
    var hi = functions.len;
    while (lo < hi) {
        const mid = lo + (hi - lo) / 2;
        if (ast.declTokens(functions[mid]).start.index() <= at.index()) lo = mid + 1 else hi = mid;
    }
    if (lo == 0) return null;
    if (at.index() >= ast.declTokens(functions[lo - 1]).end.index()) return null;
    return lo - 1;
}

/// Property: every name a completion offers is one the point could reach, and
/// it offers no fewer than that point has -- asked at both points a completion
/// is asked at, a name being typed and a dot just written.
///
/// **Two populations, because a dot is answered by different code.** A cursor
/// after a name is answered from the scope chain; a cursor after a dot is
/// answered from what the receiver opens, and the two share nothing but the
/// entry point. A property asked at one of them says nothing about the other,
/// and the answer after a dot is where a type's name was read as a value of
/// that type.
///
/// Asked at the byte after every name the program writes, which is where a
/// cursor sits while a name is being typed and so is the point completion is
/// actually asked about. That byte is between two tokens, so what the tree
/// covers it with is not the name -- it is whatever was still open there, which
/// in half-written text is a call with no closing bracket or a region the parser
/// gave up on. Answering from it at all is the walk outward this checks.
///
/// And at the first byte of every name written after a dot, which is where a
/// cursor sits having typed the dot and nothing more.
///
/// Two halves at each, because either alone passes on an answer that is plainly
/// wrong.
///
/// **No name offered that the point cannot reach.** The scope the resolver
/// recorded when it bound the name is the ground truth, and it is a record this
/// walk did not compute. A completion that landed in a sibling function's scope
/// offers that function's locals, and this is what says so.
///
/// **No name missing that the point must reach.** Every parameter of the
/// function the point sits in is offered. Membership alone cannot say this: the
/// module's own run is inside every chain, so a walk that gave up and answered
/// with it satisfies the first half completely while having dropped every local
/// and every parameter. A parameter is the binding the resolver tags with an
/// owner as it walks declarations, without consulting the scope stack, so what
/// this compares are two independent records.
///
/// **After a dot on a namespace, exactly what that namespace holds.** A type's
/// name, a trait's or a primitive's opens a namespace, and `selectableUnder` is
/// what settles a name written under it. Held both ways: a label that namespace
/// does not hold is a name the compiler would refuse -- a field is reached
/// through a value and a trait's operation through its trait, so neither may be
/// written after the type -- and a name it holds that is not offered is a name
/// the reader is told does not exist. An enum's variants and a trait's
/// operations are only ever written this way.
///
/// **The name the program actually wrote after the dot is offered.** Where the
/// resolver settled a qualified name -- through a module an import bound, or
/// under a namespace -- that name is one this point can reach, and it is a
/// record this walk did not compute: `selection` looked it up as it bound the
/// program. It is what holds the module-qualified answer, whose labels the
/// scope-chain half above skips.
///
/// Asked of every function the corpus holds, rejected cases included: a
/// half-written file is what an editor asks about, and the resolver binds what
/// it can whatever else is wrong. A function whose body writes neither a name
/// nor a dot has no point to ask about and is passed over, which is the other
/// side of the tally.
///
/// **Bound:** one index build for the case, one binary search per name and per
/// dot over the functions, and one answer at each -- each of which costs the
/// chain or the namespace at that point. Nothing here is sized by the program
/// per point.
fn checkCompletionOffers(
    gpa: std.mem.Allocator,
    failures: *std.ArrayList(Failure),
    properties: *std.EnumMap(Property, u32),
    passed_over: *std.EnumMap(Property, u32),
    display_path: []const u8,
    program: *const Program,
    res: *const Resolution,
    typing: *const Typing,
    dots: *u32,
) !void {
    const ast = &program.ast;

    var functions: std.ArrayList(node_mod.DeclId) = .empty;
    defer functions.deinit(gpa);
    for (program.modules) |m| {
        if (m.library) continue;
        for (m.decls.start..m.decls.end) |i| {
            const d = node_mod.DeclId.at(@intCast(i));
            if (ast.declTag(d) == .function) try functions.append(gpa, d);
        }
    }
    std.mem.sort(node_mod.DeclId, functions.items, ast, struct {
        fn before(tree: *const Ast, a: node_mod.DeclId, b: node_mod.DeclId) bool {
            return tree.declTokens(a).start.index() < tree.declTokens(b).start.index();
        }
    }.before);

    const asked = try gpa.alloc(bool, functions.items.len);
    defer gpa.free(asked);
    @memset(asked, false);

    var index = try lsp_positions.Index.build(gpa, ast);
    defer index.deinit(gpa);

    var visible: std.ArrayList(resolve_mod.BindingId) = .empty;
    defer visible.deinit(gpa);
    var reachable: std.StringHashMapUnmanaged(void) = .empty;
    defer reachable.deinit(gpa);

    for (0..ast.exprCount()) |i| {
        const e: ExprId = .at(@intCast(i));
        if (ast.exprTag(e) != .name_ref) continue;
        const sc = res.scopeOfExpr(e);
        if (sc == .none) continue;

        const at = ast.exprMain(e);
        const holder = functionHolding(ast, functions.items, at) orelse continue;
        asked[holder] = true;

        // What the resolver's own record makes visible where this name was
        // bound, by name rather than by binding: a completion offers text, and
        // two bindings of one name are one offer.
        try res.visibleIn(gpa, sc, &visible);
        reachable.clearRetainingCapacity();
        for (visible.items) |b| {
            const name = lsp_completion.nameOf(ast, res, b) orelse continue;
            try reachable.put(gpa, name, {});
        }

        const file = ast.fileOfExpr(e);
        const offered = try lsp_completion.atOffset(
            gpa,
            program,
            res,
            typing,
            &index,
            file,
            ast.tokenSpan(at).end,
            .@"utf-16",
            // What the workspace holds is not what this property is about: it
            // asks whether an offer agrees with the chain, and a name from a
            // module nobody imported is not in one.
            null,
            // Nor is what accepting one writes. This reads labels, and a label
            // is what an item is called whatever a client does with its text.
            .unsupported,
        );
        defer lsp_completion.free(gpa, offered);

        for (offered) |item| {
            // A qualified name reaches into another module, which is not what
            // this chain holds; the module it names is offered beside it and is
            // checked as the name it is.
            if (std.mem.indexOfScalar(u8, item.label, '.') != null) continue;
            if (reachable.contains(item.label)) continue;

            try failures.append(gpa, .{
                .path = display_path,
                .what = "a completion offers only what the point can reach",
                .expected = try std.fmt.allocPrint(
                    gpa,
                    "a name scope {d} makes visible after `{s}`",
                    .{ sc.index(), ast.tokenText(at) },
                ),
                .actual = try std.fmt.allocPrint(gpa, "`{s}`", .{item.label}),
            });
            break;
        }

        for (visible.items) |p| {
            if (res.kindOf(p) != .parameter) continue;
            const name = lsp_completion.nameOf(ast, res, p) orelse continue;
            const found = for (offered) |item| {
                if (std.mem.eql(u8, item.label, name)) break true;
            } else false;
            if (found) continue;

            try failures.append(gpa, .{
                .path = display_path,
                .what = "a completion offers every parameter visible at the point",
                .expected = try std.fmt.allocPrint(
                    gpa,
                    "the visible parameter `{s}` after `{s}`",
                    .{ name, ast.tokenText(at) },
                ),
                .actual = try std.fmt.allocPrint(gpa, "{d} name(s), and none of them that", .{offered.len}),
            });
            break;
        }
    }

    var holds: std.ArrayList(resolve_mod.Selectable) = .empty;
    defer holds.deinit(gpa);

    for (0..ast.exprCount()) |i| {
        const e: ExprId = .at(@intCast(i));
        if (ast.exprTag(e) != .field) continue;

        // A dot with nothing after it writes no name, so there is no first byte
        // of one to ask at and nothing the program wrote to look for.
        const at = ast.exprMain(e);
        if (ast.tokenTag(at) != .identifier) continue;

        const receiver = ast.withoutGroups(ast.unaryOperand(e));
        if (receiver == ExprId.none) continue;

        const holder = functionHolding(ast, functions.items, at) orelse continue;
        asked[holder] = true;
        dots.* += 1;

        const file = ast.fileOfExpr(e);
        const offered = try lsp_completion.atOffset(
            gpa,
            program,
            res,
            typing,
            &index,
            file,
            ast.tokenSpan(at).start,
            .@"utf-16",
            // The same reason as above: what a module nobody imported holds is
            // not what this asks about, and neither is what accepting writes.
            null,
            .unsupported,
        );
        defer lsp_completion.free(gpa, offered);

        const qualifier = res.targetOf(receiver);
        if (qualifier != resolve_mod.BindingId.none and
            resolve_mod.namesANamespace(res.kindOf(qualifier)))
        {
            try resolve_mod.selectableUnder(
                gpa,
                ast,
                program,
                res,
                res.moduleOfFile(file),
                qualifier,
                &holds,
            );

            reachable.clearRetainingCapacity();
            for (holds.items) |written| switch (written) {
                .member => |m| {
                    // What may stand here, which is not everything the
                    // namespace holds: this dot is in an expression, and a
                    // type a trait declares is not a value. The same predicate
                    // the server offers by, so this holds it to a rule rather
                    // than to a second reading of one.
                    if (!resolve_mod.standsWhereAValueBelongs(res.kindOf(m))) continue;
                    const name = lsp_completion.nameOf(ast, res, m) orelse continue;
                    try reachable.put(gpa, name, {});
                },
                .variant => |v| try reachable.put(gpa, ast.tokenText(v), {}),
            };

            const integer_namespace = if (res.builtinOf(qualifier)) |primitive|
                primitive.integerInfo() != null
            else
                res.kindOf(qualifier) == .type_parameter and
                    typing.isIntegerWithin(functions.items[holder], typing.exprType(receiver));
            if (integer_namespace) {
                // Intrinsic endpoints have no source binding. The expected
                // names come from the language rule, not the offered labels.
                try reachable.put(gpa, "min", {});
                try reachable.put(gpa, "max", {});
            }
            // A type's name also reaches the operations of the traits in scope
            // it implements, where its own namespace does not hold the name
            // and one trait alone answers: the checker's `Reach.namespaced`,
            // read through `keepReached` as the checker reads it.
            if (res.kindOf(qualifier) != .trait) {
                var through: std.ArrayList(typecheck_mod.Applicable) = .empty;
                defer through.deinit(gpa);
                try typecheck_mod.reachIn(ast, program, res, typing, res.moduleOfFile(file), functions.items[holder])
                    .namespaced(gpa, typing.exprType(receiver), null, true, &through, null);
                try typecheck_mod.keepReached(gpa, ast, &through);
                for (through.items) |a| try reachable.put(gpa, ast.tokenText(ast.declName(a.sig)), {});
            }
            try checkNamespaceOffers(gpa, failures, display_path, ast.tokenText(ast.exprMain(receiver)), &reachable, offered);
        }

        // Settled only where the name was reached through a module or under a
        // namespace, which is where the resolver has an answer of its own to
        // hold this to. A field of a value is the checker's, and the half above
        // is what asks about a namespace.
        if (res.targetOf(e) == resolve_mod.BindingId.none) continue;

        // And only where what the program wrote may stand where it wrote it. A
        // program may name a thing that is not a value in an expression, and
        // that program is refused for it -- offering the reader the text the
        // compiler is about to refuse is the opposite of what this asks for.
        if (!resolve_mod.standsWhereAValueBelongs(res.kindOf(res.targetOf(e)))) continue;

        const written = ast.tokenText(at);
        const found = for (offered) |item| {
            if (std.mem.eql(u8, item.label, written)) break true;
        } else false;
        if (found) continue;

        try failures.append(gpa, .{
            .path = display_path,
            .what = "a dot offers the name the program wrote after it",
            .expected = try std.fmt.allocPrint(
                gpa,
                "`{s}` after `{s}.`",
                .{ written, ast.tokenText(ast.exprMain(receiver)) },
            ),
            .actual = try std.fmt.allocPrint(gpa, "{d} name(s), and none of them that", .{offered.len}),
        });
    }

    for (asked) |was| tally(properties, passed_over, .completion_offers, was);
}

fn checkNamespaceOffers(
    gpa: std.mem.Allocator,
    failures: *std.ArrayList(Failure),
    display_path: []const u8,
    qualifier: []const u8,
    reachable: *const std.StringHashMapUnmanaged(void),
    offered: []const lsp.types.completion.Item,
) !void {
    for (offered) |item| {
        if (reachable.contains(item.label)) continue;
        try failures.append(gpa, .{
            .path = display_path,
            .what = "a dot on a namespace offers only what that namespace holds",
            .expected = try std.fmt.allocPrint(
                gpa,
                "a name under `{s}`",
                .{qualifier},
            ),
            .actual = try std.fmt.allocPrint(gpa, "`{s}`", .{item.label}),
        });
        break;
    }

    var wanted = reachable.keyIterator();
    while (wanted.next()) |name| {
        const found = for (offered) |item| {
            if (std.mem.eql(u8, item.label, name.*)) break true;
        } else false;
        if (found) continue;

        try failures.append(gpa, .{
            .path = display_path,
            .what = "a dot on a namespace offers every name that namespace holds",
            .expected = try std.fmt.allocPrint(
                gpa,
                "`{s}` after `{s}`",
                .{ name.*, qualifier },
            ),
            .actual = try std.fmt.allocPrint(gpa, "{d} name(s), and none of them that", .{offered.len}),
        });
        break;
    }
}

test "integer property completion oracle checks intrinsic and declared namespaces" {
    const cases = [_]struct { source: []const u8, valid: bool, dots: u32 }{
        .{ .source = "fn limit[T: Integer](_value: T) -> T { T.max }\nfn main() -> UInt8 { limit(UInt8.min) }\n", .valid = true, .dots = 2 },
        .{ .source = "fn limit[T](_value: T) -> T where T: Integer { T.min }\nfn main() -> UInt8 { limit(UInt8.max) }\n", .valid = true, .dots = 2 },
        .{ .source = "fn main() -> UInt8 { Bool.min }\n", .valid = false, .dots = 1 },
        .{ .source = "fn main() -> UInt8 { Float64.max }\n", .valid = false, .dots = 1 },
        .{ .source = "type Distance = UInt8\nfn main() -> UInt8 { Distance.min }\n", .valid = false, .dots = 1 },
        .{ .source = "fn limit[T](_value: T) -> T { T.max }\nfn main() -> UInt8 { 0 }\n", .valid = false, .dots = 1 },
        .{ .source = "trait Integer {}\nfn limit[T: Integer](_value: T) -> T { T.max }\nfn main() -> UInt8 { 0 }\n", .valid = false, .dots = 1 },
        .{ .source = "type Distance = UInt8\nimpl Distance { pub let max = UInt8(3) }\nfn main() -> UInt8 { Distance.max }\n", .valid = true, .dots = 1 },
    };
    for (cases) |case| {
        var arena = std.heap.ArenaAllocator.init(testing.allocator);
        defer arena.deinit();
        const gpa = arena.allocator();
        var checked = try lsp_analysis.of(gpa, gpa, test_library.get(), &.{.{ .path = "main.lin", .text = case.source }}, "main.lin");
        defer checked.deinit();
        try testing.expectEqual(case.valid, !checked.sink.hasErrors());
        var failures: std.ArrayList(Failure) = .empty;
        var properties: std.EnumMap(Property, u32) = .{};
        var passed_over: std.EnumMap(Property, u32) = .{};
        var dots: u32 = 0;
        try checkCompletionOffers(gpa, &failures, &properties, &passed_over, "main.lin", &checked.program, &checked.semantics.res, &checked.semantics.typing, &dots);
        try testing.expectEqual(case.dots, dots);
        try testing.expectEqual(@as(usize, 0), failures.items.len);
    }
}

test "integer property completion oracle rejects missing and unsolicited endpoints" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    var reachable: std.StringHashMapUnmanaged(void) = .empty;
    try reachable.put(gpa, "min", {});
    try reachable.put(gpa, "max", {});
    var failures: std.ArrayList(Failure) = .empty;
    try checkNamespaceOffers(gpa, &failures, "main.lin", "UInt8", &reachable, &.{.{ .label = "min" }});
    try testing.expectEqual(@as(usize, 1), failures.items.len);
    try testing.expectEqualStrings("a dot on a namespace offers every name that namespace holds", failures.items[0].what);
    failures.clearRetainingCapacity();
    reachable.clearRetainingCapacity();
    try checkNamespaceOffers(gpa, &failures, "main.lin", "Bool", &reachable, &.{.{ .label = "min" }});
    try testing.expectEqual(@as(usize, 1), failures.items.len);
    try testing.expectEqualStrings("a dot on a namespace offers only what that namespace holds", failures.items[0].what);
}

/// Whether each file of a program is the standard library's rather than the
/// program's own, keyed by the file.
///
/// The library is loaded again for every case that imports it, so what it
/// writes belongs to no case and is left out of both a population and the
/// property measured against it. Which module a file belongs to says so; a
/// path does not.
fn libraryFiles(gpa: std.mem.Allocator, program: *const Program) ![]bool {
    var most: usize = 0;
    for (program.modules) |m| {
        for (m.files) |f| {
            if (f.index() + 1 > most) most = f.index() + 1;
        }
    }
    const out = try gpa.alloc(bool, most);
    @memset(out, false);
    for (program.modules) |m| {
        if (!m.library) continue;
        for (m.files) |f| out[f.index()] = true;
    }
    return out;
}

/// Whether a written type is a settled reference the case itself wrote.
fn ownSettledRef(ast: *const Ast, in_library: []const bool, ref: node_mod.TypeRef) bool {
    if (ref.kind != .selection) return false;
    if (ref.name == TokenId.none) return false;
    const file = ast.fileOf(ref.name).index();
    return file < in_library.len and !in_library[file];
}

/// How many settled references a case writes: the population `settled_refs` is
/// asked once per.
///
/// Counted from the tree's flat tables. Every argument a written type was
/// given sits in one array whatever it was written under, so the arguments are
/// read straight out of it rather than by descending through the positions
/// that hold them -- which is the half of the count the property's own walk
/// could get wrong without this noticing.
///
/// **Bound:** one pass over written types, declarations, statements and
/// expressions, visiting each lambda parameter once. Library rows are excluded
/// by their file metadata. Work is linear in the loaded source.
fn settledRefsWritten(ast: *const Ast, program: *const Program, in_library: []const bool) u32 {
    var n: u32 = 0;

    // Every argument of every written type, at whatever depth: an argument is a
    // written type in its own right and they share one table.
    for (ast.type_refs) |r| {
        if (ownSettledRef(ast, in_library, r)) n += 1;
    }

    // And the written types nothing gave to anything, which are the ones a
    // declaration holds directly. Their arguments are above, so each is counted
    // by its head alone.
    for (program.modules) |m| {
        if (m.library) continue;
        for (m.decls.start..m.decls.end) |i| {
            const d = node_mod.DeclId.at(@intCast(i));
            for (ast.declParams(d)) |p| {
                if (ownSettledRef(ast, in_library, p.written)) n += 1;
            }
            for (ast.declFields(d)) |f| {
                if (ownSettledRef(ast, in_library, f.written)) n += 1;
            }
            for (ast.declVariants(d)) |v| {
                for (ast.variantFields(v)) |f| {
                    if (ownSettledRef(ast, in_library, f.written)) n += 1;
                }
            }
            if (ownSettledRef(ast, in_library, ast.declReturnRef(d))) n += 1;
        }
    }

    // A `let`'s annotation, which is written inside a body rather than on a
    // declaration and is reached from the statements for that reason.
    for (0..ast.stmtCount()) |i| {
        const s = node_mod.StmtId.at(@intCast(i));
        switch (ast.stmtTag(s)) {
            .let_decl, .let_destructure, .let_read_destructure => {
                if (ownSettledRef(ast, in_library, ast.stmtData(s).annotation)) n += 1;
            },
            else => {},
        }
    }

    // Lambda parameter roots are held in the parameter table; their nested
    // components and the result annotation already occur in type_refs.
    for (ast.exprs.items(.tag), 0..) |tag, i| {
        if (tag != .lambda) continue;
        for (ast.lambda(ExprId.at(@intCast(i))).params) |param| {
            if (ownSettledRef(ast, in_library, param.written)) n += 1;
        }
    }

    return n;
}

/// What an implementation settles one declared type to, as its own text says.
const Settled = struct {
    /// The written type after the `=`.
    written: node_mod.TypeRef,
    /// The type the implementation is for, which is what `Self` spells there.
    of: TokenId,
    /// Whether more than one implementation answers this key.
    ///
    /// The key holds the module that wrote it, so two of them is coherence
    /// broken inside one module -- which the compiler refuses, and the case is
    /// about the refusal. Keyed on the spelling alone it was also two modules
    /// each declaring a type of one name and each implementing one trait of
    /// one name for it, which is a program the compiler accepts and this
    /// answered nothing about: both implementations degraded to passed over,
    /// so the property went quiet on exactly the program that has two of
    /// everything.
    twice: bool = false,
};

const WrittenTypePurpose = enum { display, identity };

/// The name the source gives a written type, spelled as the type pool spells
/// one.
///
/// Re-derived from the text on purpose. The compiler answers this once and
/// records it; the point of the property this serves is to compare that record
/// against the program, so here the program is read again and independently.
///
/// Null where the text alone does not say which type is meant: an array, whose
/// name the pool builds from a length the source writes as an expression, and a
/// settled reference, which is what a settled type may not be and the checker
/// refuses.
///
/// **Owned by the caller, always.** A name with no arguments is a slice of the
/// source and one with arguments is built, and returning whichever it happened
/// to be left every caller unable to say whether freeing it was right -- so
/// none of them did, and the built ones leaked.
///
/// This spells a written type the way the pool spells a settled one, which is
/// what `Typing.nameOf` does from the other end. The two are deliberately not
/// one routine: the whole of what this property compares is a spelling derived
/// from the source against a spelling derived from the types, so a shared
/// speller would make the comparison read one answer twice. Identity keys use
/// exact default encodings; displayed names may abbreviate large defaults.
fn writtenTypeName(
    gpa: std.mem.Allocator,
    ast: *const Ast,
    res: *const Resolution,
    memo: *constfold.Memo,
    ref: node_mod.TypeRef,
    self_is: []const u8,
    purpose: WrittenTypePurpose,
) !?[]const u8 {
    if (ref.kind == .callable) {
        const callable = ast.callableType(ref);
        var out: std.ArrayList(u8) = .empty;
        errdefer out.deinit(gpa);
        try out.appendSlice(gpa, "fn(");
        for (ast.params[callable.params.start..callable.params.end], 0..) |param, i| {
            if (i > 0) try out.appendSlice(gpa, ", ");
            // A parameter's name is not part of the type it spells.
            try out.appendSlice(gpa, @tagName(param.convention));
            try out.append(gpa, ' ');
            const ty = try writtenTypeName(gpa, ast, res, memo, param.written, self_is, purpose) orelse {
                out.deinit(gpa);
                return null;
            };
            defer gpa.free(ty);
            try out.appendSlice(gpa, ty);
            if (param.default != ExprId.none) {
                const folded = try constfold.foldConstant(gpa, ast, res.nameSites(), memo, param.default);
                const value = folded.checked() orelse {
                    out.deinit(gpa);
                    return null;
                };
                const text = switch (purpose) {
                    .display => try value.text(gpa, &memo.pool),
                    .identity => try value.encoding(gpa, &memo.pool),
                };
                defer gpa.free(text);
                try out.appendSlice(gpa, " = ");
                try out.appendSlice(gpa, text);
            }
        }
        try out.append(gpa, ')');
        // A callable type writing no result returns `()`, and is named
        // without one as the checker names it.
        if (!callable.result.wasWritten()) return try out.toOwnedSlice(gpa);
        try out.appendSlice(gpa, " -> ");
        const result = try writtenTypeName(gpa, ast, res, memo, callable.result, self_is, purpose) orelse {
            out.deinit(gpa);
            return null;
        };
        defer gpa.free(result);
        try out.appendSlice(gpa, result);
        return try out.toOwnedSlice(gpa);
    }
    if (ref.kind != .named) return null;
    if (ref.name == TokenId.none) return null;

    const spelled = ast.tokenText(ref.name);
    // `Self` is an ordinary identifier, so the spelling is what tells it from a
    // declared type -- and inside an implementation it stands for the type that
    // implementation is for.
    const head = if (std.mem.eql(u8, spelled, "Self")) self_is else spelled;

    const args = ast.typeArgs(ref.args);
    if (args.len == 0) return try gpa.dupe(u8, head);

    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    try out.appendSlice(gpa, head);
    try out.append(gpa, '[');
    for (args, 0..) |a, i| {
        if (i > 0) try out.appendSlice(gpa, ", ");
        const name = try writtenTypeName(gpa, ast, res, memo, a, self_is, purpose) orelse {
            out.deinit(gpa);
            return null;
        };
        defer gpa.free(name);
        try out.appendSlice(gpa, name);
    }
    try out.append(gpa, ']');
    return try out.toOwnedSlice(gpa);
}

/// Which implementation settles a declared type, by the type and the trait
/// alone: what a name selected from a name is settled by.
///
/// No module in it, because the reference does not say one and no path leads
/// there: `Self.Mid.Item` is settled by whatever implements `Inner` for what
/// `Mid` settled to, wherever that was written. Two implementations answering
/// one key is what the caller's `twice` declines.
///
/// Spellings and nothing else, because the lookup has a type it derived as text
/// and the index has the tokens an `impl` header wrote. A trait named through
/// another spelling at one of the two ends is a key that misses, which is a
/// reference this property passes over rather than one it answers wrongly.
fn settlingKey(
    gpa: std.mem.Allocator,
    of: []const u8,
    trait: []const u8,
    member: []const u8,
) ![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    try out.appendSlice(gpa, of);
    try out.append(gpa, 0);
    try out.appendSlice(gpa, trait);
    try out.append(gpa, 0);
    try out.appendSlice(gpa, member);
    return try out.toOwnedSlice(gpa);
}

/// Which implementation a member belongs to, as the source spells it: the type
/// it is for, the trait it answers, and the arguments that trait was given.
///
/// The arguments are part of it because one type may implement one trait twice
/// at different arguments, and each of those settles a declared type its own
/// way. A key of the type and the trait alone finds whichever was written
/// first, which is exactly the wrong answer this property exists to catch.
fn implKey(
    gpa: std.mem.Allocator,
    ast: *const Ast,
    res: *const Resolution,
    memo: *constfold.Memo,
    program: *const Program,
    d: node_mod.DeclId,
    member: []const u8,
) !?[]const u8 {
    const of = ast.declOwner(d);
    const trait = ast.declTrait(d);
    if (of == TokenId.none or trait == TokenId.none) return null;

    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    // Which module wrote it, because a spelling is a spelling within one. Two
    // modules each declaring a `Counter` and each implementing a `Measure` for
    // it write one key between them, and one key answering for two
    // implementations is a key that answers for neither: both are passed over,
    // and the property goes quiet on exactly the program that has two of
    // everything.
    const wrote_it: u32 = @intFromEnum(program.moduleOf(d));
    try out.appendSlice(gpa, std.mem.asBytes(&wrote_it));
    try out.appendSlice(gpa, ast.tokenText(of));
    try out.append(gpa, 0);
    try out.appendSlice(gpa, ast.tokenText(trait));
    for (ast.typeArgs(ast.declTraitArgs(d))) |a| {
        try out.append(gpa, 0);
        const name = try writtenTypeName(gpa, ast, res, memo, a, ast.tokenText(of), .identity) orelse {
            out.deinit(gpa);
            return null;
        };
        defer gpa.free(name);
        try out.appendSlice(gpa, name);
    }
    try out.append(gpa, 0);
    try out.appendSlice(gpa, member);
    return try out.toOwnedSlice(gpa);
}

/// Property: every settled reference the checker resolved names the type the
/// implementation that settles it wrote.
///
/// **Why it is not a tautology.** Inside the compiler a settled reference is
/// answered by reading the pairing recorded when the implementations were
/// settled, which is what stops the question having two answers. So a check
/// comparing the resolution against that pairing reads one table twice and
/// cannot fail. This reads the source instead: which implementation encloses
/// the settled reference, and what that implementation's own `type Item = ...`
/// line writes. The oracle is a second derivation on purpose -- a test may
/// re-derive what the compiler records, and re-deriving is the only way to
/// notice the record drifting from the program.
///
/// **Checked** where the checker recorded an answer and the source names one: a
/// settled reference inside an implementation of a trait that settles the name
/// it writes. **Passed over** otherwise, and the two reasons are counted apart
/// because they are unlike -- see `Held`. One is a settled reference written in
/// a trait's own signature, which is answered per call, recorded against no
/// token by design, and so checked by nothing here or anywhere: coverage
/// missing. The other is everything else -- a settled reference the checker
/// refused and reported, an implementation that settles nothing for the name, a
/// settling the text alone does not spell: coverage declined.
///
/// **Bound:** one index over the case's own declarations, one pass over the
/// statements of the compilation, and per settled reference one hash lookup and
/// one binary search over those declarations. Nothing here is sized by the
/// corpus, and nothing per settled reference is sized by the case.
fn checkSettledRefs(
    gpa: std.mem.Allocator,
    failures: *std.ArrayList(Failure),
    properties: *std.EnumMap(Property, u32),
    passed_over: *std.EnumMap(Property, u32),
    declined: *PassedSettledRefs,
    display_path: []const u8,
    program: *const Program,
    res: *const Resolution,
    typing: *const Typing,
    in_library: []const bool,
) !void {
    const ast = &program.ast;
    var source_folds: constfold.Memo = .empty;
    defer source_folds.deinit(gpa);

    // What each implementation settles each declared type to, keyed as the
    // source keys it. Built once for the case, because a scan per settled
    // reference would read every declaration for every settled reference
    // written.
    var settles: std.StringHashMapUnmanaged(Settled) = .empty;
    defer settles.deinit(gpa);

    // The same, keyed without the module that wrote it. A name selected from a
    // name is settled by an implementation the reference does not name and no
    // module path leads to -- `Self.Mid.Item` is settled by whatever implements
    // `Inner` for what `Mid` settled to -- so the oracle finds it by the type
    // and the trait alone. Two modules writing one such pair is a key that
    // answers for neither, which is what `twice` says.
    var settles_anywhere: std.StringHashMapUnmanaged(Settled) = .empty;
    defer settles_anywhere.deinit(gpa);

    // What the program's traits declare, for the reference read through a
    // bound: a bound is a name, and which trait that name reaches and what
    // that trait declares are what the source says about it. Built once for
    // the case for the reason above.
    var traits: TraitsWritten = .{};
    defer traits.deinit(gpa);
    try traits.build(gpa, ast, program);

    // What the imports bind and what each module exports, for the reference
    // whose head names a module: which module a name reaches and which type
    // that module declares are what the source says about it. Built once for
    // the case for the reason above.
    var modules: ModulesWritten = .{};
    defer modules.deinit(gpa);
    try modules.build(gpa, ast, program);

    var work: SettledRefWork = .{
        .failures = failures,
        .properties = properties,
        .passed_over = passed_over,
        .declined = declined,
        .display_path = display_path,
        .settles = &settles,
        .settles_anywhere = &settles_anywhere,
        .traits = &traits,
        .modules = &modules,
        .res = res,
        .source_folds = &source_folds,
    };

    // The declarations in token order, for the settled reference written inside
    // a body rather than on a declaration: the innermost declaration over a
    // token is the last one beginning at or before it.
    var holders: std.ArrayList(node_mod.DeclId) = .empty;
    defer holders.deinit(gpa);

    for (program.modules) |m| {
        if (m.library) continue;
        for (m.decls.start..m.decls.end) |i| {
            const d = node_mod.DeclId.at(@intCast(i));
            try holders.append(gpa, d);
            if (ast.declTag(d) != .associated_type) continue;
            const written = ast.declReturnRef(d);
            if (!written.wasWritten()) continue;
            const key = try implKey(gpa, ast, res, &source_folds, program, d, ast.tokenText(ast.declName(d))) orelse continue;
            const found = try settles.getOrPut(gpa, key);
            if (found.found_existing) {
                found.value_ptr.twice = true;
                continue;
            }
            found.value_ptr.* = .{ .written = written, .of = ast.declOwner(d) };

            // A trait taking type parameters is one no settled reference is
            // read through, so a key naming it without them would answer for
            // a reference no program can write. Asked of the trait rather
            // than of what this `impl` supplied, which is the same sentence
            // the walk that reads these keys holds the compiler to: a
            // reference answered through such a bound is a failure there
            // rather than a key that quietly misses here.
            if (ast.declTrait(d) == TokenId.none) continue;
            const answers = traits.named(ast.tokenText(ast.declTrait(d))) orelse continue;
            if (ast.declTypeParams(answers).len != 0) continue;
            const anywhere = try settlingKey(
                gpa,
                ast.tokenText(ast.declOwner(d)),
                ast.tokenText(ast.declTrait(d)),
                ast.tokenText(ast.declName(d)),
            );
            const also = try settles_anywhere.getOrPut(gpa, anywhere);
            if (also.found_existing) {
                also.value_ptr.twice = true;
                continue;
            }
            also.value_ptr.* = .{ .written = written, .of = ast.declOwner(d) };
        }
    }

    std.mem.sort(node_mod.DeclId, holders.items, ast, struct {
        fn before(tree: *const Ast, a: node_mod.DeclId, b: node_mod.DeclId) bool {
            return tree.declTokens(a).start.index() < tree.declTokens(b).start.index();
        }
    }.before);

    // Every settled reference the case wrote, reached through the positions a
    // written type stands in. Each is tallied on one side or the other, and the
    // sum is held to what the case's own tables say it wrote.
    for (program.modules) |m| {
        if (m.library) continue;
        for (m.decls.start..m.decls.end) |i| {
            const d = node_mod.DeclId.at(@intCast(i));
            for (ast.declParams(d)) |p| {
                try heldToWhatSettles(gpa, &work, ast, program, typing, in_library, d, p.written);
            }
            for (ast.declFields(d)) |f| {
                try heldToWhatSettles(gpa, &work, ast, program, typing, in_library, d, f.written);
            }
            for (ast.declVariants(d)) |v| {
                for (ast.variantFields(v)) |f| {
                    try heldToWhatSettles(gpa, &work, ast, program, typing, in_library, d, f.written);
                }
            }
            // What an `impl` gave its trait, read at the `impl` and not at its
            // members: every member records the same range, so reading it at
            // each would visit one written type as many times as the block
            // holds declarations.
            if (ast.declTag(d) == .impl_) {
                for (ast.typeArgs(ast.declTraitArgs(d))) |a| {
                    try heldToWhatSettles(gpa, &work, ast, program, typing, in_library, d, a);
                }
                // What its head applies the constructor to, which a type's
                // own implementation may fix to a settled reference, as
                // `impl[P] Pair[P, mem.SystemAllocator]` does.
                for (ast.typeArgs(ast.declHead(d).args)) |a| {
                    try heldToWhatSettles(gpa, &work, ast, program, typing, in_library, d, a);
                }
            }
            for (ast.deriveTraits(d)) |entry| {
                for (ast.typeArgs(entry.ref.args)) |argument| {
                    try heldToWhatSettles(gpa, &work, ast, program, typing, in_library, d, argument);
                }
            }
            try heldToWhatSettles(gpa, &work, ast, program, typing, in_library, d, ast.declReturnRef(d));
            // What a bound gives its trait, on a type parameter or in a
            // `where` clause: `H: http.Handler[mem.SystemAllocator, ()]`
            // writes a settled reference as an argument, and the argument
            // table the population counts from holds it.
            for (ast.declTypeParams(d)) |parameter| {
                try heldBoundArguments(gpa, &work, ast, program, typing, in_library, d, ast.boundsOf(parameter));
            }
            // A predicate's subject is no argument of anything, so the
            // population counts what is written inside it -- the base a
            // selection reads through, `S.Iter` in `S.Iter.Item`, and its
            // arguments -- and not the subject itself.
            for (ast.declWherePredicates(d)) |predicate| {
                if (predicate.subject.kind == .selection) {
                    try heldToWhatSettles(gpa, &work, ast, program, typing, in_library, d, ast.selectionBase(predicate.subject));
                }
                for (ast.typeArgs(predicate.subject.args)) |a| {
                    try heldToWhatSettles(gpa, &work, ast, program, typing, in_library, d, a);
                }
                try heldBoundArguments(gpa, &work, ast, program, typing, in_library, d, ast.boundsIn(predicate.bounds));
            }
        }
    }

    for (0..ast.stmtCount()) |i| {
        const s = node_mod.StmtId.at(@intCast(i));
        switch (ast.stmtTag(s)) {
            .let_decl, .let_destructure, .let_read_destructure => {},
            else => continue,
        }
        try heldBodyAnnotation(gpa, &work, ast, program, typing, in_library, holders.items, ast.stmtData(s).annotation);
    }
    for (ast.exprs.items(.tag), 0..) |tag, i| {
        const expression = ExprId.at(@intCast(i));
        if (ast.structLiteralHead(expression)) |head| {
            try heldBodyAnnotation(gpa, &work, ast, program, typing, in_library, holders.items, head);
        }
        if (tag == .lambda) {
            const lambda = ast.lambda(expression);
            for (lambda.params) |param| {
                try heldBodyAnnotation(gpa, &work, ast, program, typing, in_library, holders.items, param.written);
            }
            try heldBodyAnnotation(gpa, &work, ast, program, typing, in_library, holders.items, lambda.result);
        }
        // The type arguments a call names in brackets, as
        // `request.extract[http.Json[Order]]()` does. The parser keeps a type
        // reading of every bracket that parses as one, and the population
        // counts it from the shared argument table, so it is held here too.
        if (tag == .index) {
            if (ast.bracketTypes(expression)) |arguments| {
                for (ast.typeArgs(arguments)) |a| {
                    try heldBodyAnnotation(gpa, &work, ast, program, typing, in_library, holders.items, a);
                }
            }
        }
    }
}

/// The arguments each named bound gives its trait, held to what settles them.
fn heldBoundArguments(
    gpa: std.mem.Allocator,
    work: *SettledRefWork,
    ast: *const Ast,
    program: *const Program,
    typing: *const Typing,
    in_library: []const bool,
    owner: node_mod.DeclId,
    bounds: []const node_mod.TraitBound,
) !void {
    for (bounds) |bound| {
        if (bound.kind != .named) continue;
        for (ast.typeArgs(bound.named.args)) |a| {
            try heldToWhatSettles(gpa, work, ast, program, typing, in_library, owner, a);
        }
    }
}

fn heldBodyAnnotation(
    gpa: std.mem.Allocator,
    work: *SettledRefWork,
    ast: *const Ast,
    program: *const Program,
    typing: *const Typing,
    in_library: []const bool,
    holders: []const node_mod.DeclId,
    annotation: node_mod.TypeRef,
) !void {
    // Composite annotations name no token themselves; their opening token
    // identifies the file and enclosing declaration for every nested reference.
    if (!annotation.wasWritten() or annotation.at == TokenId.none) return;
    const file = ast.fileOf(annotation.at).index();
    if (file < in_library.len and in_library[file]) return;
    const holder = functionHolding(ast, holders, annotation.at);
    try heldToWhatSettles(gpa, work, ast, program, typing, in_library, if (holder) |at| holders[at] else null, annotation);
}

/// One written type, and everything written inside it, held to what settles it.
///
/// Recursive over the arguments because a settled reference stands wherever a
/// type stands: `Option[Self.Item]` is a settled reference one level in, and a
/// reader that looked at the head alone would find the constructor and stop.
fn heldToWhatSettles(
    gpa: std.mem.Allocator,
    work: *SettledRefWork,
    ast: *const Ast,
    program: *const Program,
    typing: *const Typing,
    in_library: []const bool,
    owner: ?node_mod.DeclId,
    ref: node_mod.TypeRef,
) !void {
    if (ref.kind == .selection) {
        try heldToWhatSettles(gpa, work, ast, program, typing, in_library, owner, ast.selectionBase(ref));
    }
    for (ast.typeArgs(ref.args)) |a| {
        try heldToWhatSettles(gpa, work, ast, program, typing, in_library, owner, a);
    }
    if (!ownSettledRef(ast, in_library, ref)) return;

    const held = try namesWhatSettlesIt(gpa, work, ast, program, typing, owner, ref);
    tally(work.properties, work.passed_over, .settled_refs, held.wasChecked());
    switch (held) {
        .checked => {},
        .through_a_bound => work.declined.through_a_bound += 1,
        .through_a_module => work.declined.through_a_module += 1,
        .in_a_signature => work.declined.in_a_signature += 1,
        .no_bound_the_source_names => work.declined.no_bound_the_source_names += 1,
        .unrecorded => work.declined.unrecorded += 1,
    }
}

/// What the settled reference property accumulates as it walks, and where it
/// says a failure was found.
///
/// One struct because they move together and two of them are the same type:
/// `properties` and `passed_over` stood side by side in a parameter list at
/// every call site, so a pair swapped by hand compiles and tallies each into
/// the other.
const SettledRefWork = struct {
    failures: *std.ArrayList(Failure),
    properties: *std.EnumMap(Property, u32),
    passed_over: *std.EnumMap(Property, u32),
    declined: *PassedSettledRefs,
    display_path: []const u8,
    /// What each implementation settles each declared type to.
    settles: *const std.StringHashMapUnmanaged(Settled),
    /// The same, found by the type and the trait alone, for a name selected
    /// from a name: what settles it is an implementation the reference does
    /// not name.
    settles_anywhere: *const std.StringHashMapUnmanaged(Settled),
    /// What each trait declares, for a reference read through a bound.
    traits: *const TraitsWritten,
    /// Which module each import binds, and what each module exports as a type,
    /// for a reference whose head names one.
    modules: *const ModulesWritten,
    res: *const Resolution,
    source_folds: *constfold.Memo,
};

/// What one settled reference was to this property.
///
/// Six and not two, because the parts of what is checked and of what is
/// passed over are unlike and one number hides the difference. The six are
/// held to summing to the settled references the case wrote, so what the
/// accounting catches is one tallied into the wrong bucket or into none -- a
/// settled reference neither this walk nor the tally beside it reaches is
/// invisible to both, and the walk being whole is what answers for that. A
/// refusal is a settled reference with a diagnostic against it; a signature's
/// settled reference is one the checker resolves per call and records against
/// no token by design, so nothing checks it at all -- and a run reporting a
/// single "passed over" would read the second as coverage declined rather than
/// as coverage missing.
const Held = enum {
    /// Compared against what the implementation's own text settles it to.
    checked,
    /// Read through a bound, and compared against the bound the source says
    /// declares the name. Checked, and of a different question: what a
    /// reference off a bounded parameter names is settled at each
    /// instantiation rather than where it is written, so what the checker
    /// records against the token is the key -- the trait the bound named, the
    /// member, and the parameter standing for the type -- and that key is what
    /// this holds to the source. Which type each instantiation settles it to
    /// is recorded per call by nothing, so that half is checked here by
    /// nothing.
    through_a_bound,
    /// Headed by a module, and compared against the type the source says that
    /// module declares under the name after the dot. Checked, and of a third
    /// question: this one is not read through an implementation or a bound at
    /// all -- it names a declaration, and what is held is that the checker
    /// landed on the one the import and the module's own text lead to, that it
    /// is exported, and that it is a type.
    through_a_module,
    /// Written in a declaration carrying no body, which is what a trait's
    /// signature is. What it names is whatever the call settled `Self` to, so
    /// it is recorded against no token and there is nothing here to compare.
    /// **Checked by nothing.**
    in_a_signature,
    /// Read through a bound the source does not resolve: a head no type
    /// parameter of the enclosing declaration names and no import binds, a
    /// bound naming a trait no module the case reads declares, or a name two of
    /// them declare -- so the oracle has no one trait to hold the key to.
    /// **Checked by nothing**, and counted apart from the refusals because it
    /// is a reference the compiler answered and this walk could not follow.
    no_bound_the_source_names,
    /// Passed over for anything else. Either the checker recorded no answer
    /// where it records one -- so it refused the settled reference and
    /// reported, which the poison property holds it to -- or it recorded one
    /// and the source alone does not say what settles it: an implementation
    /// that settles nothing for the name, a settling written as an array or as
    /// another settled reference, two implementations of one spelling.
    unrecorded,

    /// Whether the property spoke for this one. Three of the six are checks
    /// and they are checks of different questions, which is what the counts
    /// say.
    fn wasChecked(self: Held) bool {
        return switch (self) {
            .checked, .through_a_bound, .through_a_module => true,
            .in_a_signature, .no_bound_the_source_names, .unrecorded => false,
        };
    }
};

/// The settled references split by which of the unlike reasons applies, the
/// bound-headed and module-headed checks counted beside them.
///
/// Per walker and summed at the join, for the reason every other grain here is:
/// the walkers run at once and a shared counter would report the scheduler.
const PassedSettledRefs = struct {
    /// Checked, and counted here as well so the checked number can be said as
    /// the three questions it holds.
    through_a_bound: u32 = 0,
    /// The same, for the head that names a module. Counted apart because it is
    /// a check of a third question, and because a run that stopped reaching
    /// module-headed references would leave every other number where it is.
    through_a_module: u32 = 0,
    in_a_signature: u32 = 0,
    no_bound_the_source_names: u32 = 0,
    unrecorded: u32 = 0,
};

/// Source-only name path for the independent bound/namespace oracle.
/// Concrete structural bases are passed over; native and source-materialization
/// properties cover their selection semantics.
const WrittenSelection = struct {
    tokens: []TokenId,
    head: TokenId,
    last: TokenId,

    fn init(gpa: std.mem.Allocator, ast: *const Ast, ref: node_mod.TypeRef) !WrittenSelection {
        var tokens: std.ArrayList(TokenId) = .empty;
        errdefer tokens.deinit(gpa);
        var base = ast.withoutTypeGroups(ref);
        while (base.kind == .selection) {
            try tokens.append(gpa, base.name);
            base = ast.withoutTypeGroups(ast.selectionBase(base));
        }
        const head = if (base.kind == .named) base.name else TokenId.none;
        try tokens.append(gpa, head);
        std.mem.reverse(TokenId, tokens.items);
        return .{ .tokens = try tokens.toOwnedSlice(gpa), .head = head, .last = ref.name };
    }

    fn names(self: WrittenSelection) Names {
        return .{ .tokens = self.tokens };
    }

    const Names = struct {
        tokens: []const TokenId,
        at: usize = 0,

        fn next(self: *Names) ?TokenId {
            if (self.at == self.tokens.len) return null;
            defer self.at += 1;
            return self.tokens[self.at];
        }
    };
};

/// Which of the five this one settled reference was, and the failure where it
/// was checked and disagreed.
fn namesWhatSettlesIt(
    gpa: std.mem.Allocator,
    work: *SettledRefWork,
    ast: *const Ast,
    program: *const Program,
    typing: *const Typing,
    owner: ?node_mod.DeclId,
    ref: node_mod.TypeRef,
) !Held {
    const failures = work.failures;
    const display_path = work.display_path;
    const settles = work.settles;

    const written = try WrittenSelection.init(gpa, ast, ref);
    defer gpa.free(written.tokens);
    if (written.last == .none or written.head == .none) return .unrecorded;

    // No declaration covers where this was written, so there is no
    // implementation to read it through and nothing to compare against.
    const held_by = owner orelse return .unrecorded;

    // Which of the two questions this is, which is what the head says. A
    // reference off a bounded parameter is read through the bound and settled
    // by each instantiation's own argument, so the enclosing implementation
    // settles nothing for it -- comparing the two is comparing answers to two
    // different questions, and a member generic on its own account inside an
    // implementation is where they meet.
    if (!resolve_mod.namesSelf(ast, written.head)) {
        return namesTheBoundThatDeclaresIt(gpa, work, ast, program, typing, held_by, ref, written);
    }

    // What the checker resolved, keyed by the name after the last dot. Absent
    // where it recorded none, which is a signature's settled reference wherever
    // the declaration has no body and a refused one everywhere else.
    const resolved = typing.writtenType(@intCast(written.last.index())) orelse {
        return if (ast.declIsSignature(held_by)) .in_a_signature else .unrecorded;
    };

    var names = written.names();
    // `Self`, which the implementation below is the one written around.
    _ = names.next();
    var at = names.next() orelse return .unrecorded;

    // The first name, which this implementation settles itself.
    const key = try implKey(
        gpa,
        ast,
        work.res,
        work.source_folds,
        program,
        held_by,
        ast.tokenText(at),
    ) orelse return .unrecorded;
    defer gpa.free(key);
    const settled = settles.get(key) orelse return .unrecorded;
    if (settled.twice) return .unrecorded;

    // What the run has reached, as the source spells it. Each further name is
    // selected from it, and the last is what the checker's answer is held to.
    var wrote = try writtenTypeName(
        gpa,
        ast,
        work.res,
        work.source_folds,
        settled.written,
        ast.tokenText(settled.of),
        .display,
    ) orelse return .unrecorded;
    defer gpa.free(wrote);

    // Which member of which trait the run has reached, because the bounds
    // written on it are what the next name is read through. The trait is the
    // one this implementation answers, and a member of that name is what the
    // reference reached.
    //
    // Asked where a further name asks it, and not before: a run of one name is
    // settled by this implementation alone, and a trait the source cannot
    // resolve would otherwise decline a reference nothing needed it for.
    var declared: ?node_mod.DeclId = null;

    while (names.next()) |next| {
        const from = declared orelse reached: {
            const answers = work.traits.named(ast.tokenText(ast.declTrait(held_by))) orelse
                return .unrecorded;
            break :reached work.traits.declares(ast, answers, ast.tokenName(at)) orelse
                return .unrecorded;
        };
        switch (try whichBoundDeclares(
            gpa,
            ast,
            work.res,
            work.source_folds,
            work.traits,
            ast.declBounds(from),
            ast.tokenName(next),
        )) {
            .one => |found| {
                // Whatever implements that trait for what the run reached,
                // which is an implementation this reference does not name: the
                // bound says it exists and the type is what finds it.
                const anywhere = try settlingKey(
                    gpa,
                    wrote,
                    ast.tokenText(ast.declName(found.trait)),
                    ast.tokenText(next),
                );
                defer gpa.free(anywhere);

                const also = work.settles_anywhere.get(anywhere) orelse return .unrecorded;
                if (also.twice) return .unrecorded;

                const to = try writtenTypeName(
                    gpa,
                    ast,
                    work.res,
                    work.source_folds,
                    also.written,
                    ast.tokenText(also.of),
                    .display,
                ) orelse
                    return .unrecorded;
                gpa.free(wrote);
                wrote = to;
                declared = found.member;
                at = next;
            },
            // The checker recorded an answer where the source says the type it
            // was selected from declares the name in other than one of its
            // bounds, so the two have come apart.
            .other => |count| {
                try failures.append(gpa, .{
                    .path = display_path,
                    .what = try std.fmt.allocPrint(
                        gpa,
                        "`{s}` was selected through a bound where the source declares it in other than one",
                        .{ast.tokenText(next)},
                    ),
                    .expected = try gpa.dupe(u8, "one bound declaring it"),
                    .actual = try std.fmt.allocPrint(gpa, "{d} of the bounds on `{s}`", .{
                        count,
                        ast.tokenText(at),
                    }),
                });
                return .checked;
            },
            .unresolved => return .unrecorded,
        }
    }

    const spelled = typing.nameOf(resolved);
    if (std.mem.eql(u8, spelled, wrote)) return .checked;

    try failures.append(gpa, .{
        .path = display_path,
        .what = try std.fmt.allocPrint(
            gpa,
            "`{s}` resolved to other than what the implementation settles it to",
            .{ast.tokenText(written.last)},
        ),
        .expected = try gpa.dupe(u8, wrote),
        .actual = try gpa.dupe(u8, spelled),
    });
    return .checked;
}

/// Which of a run of bounds declares the name, as the source reads them.
///
/// One reader for both heads. A settled reference is read through a bound
/// wherever it is not read through the implementation enclosing it, and the two
/// walks that ask -- the parameter-headed key and the name selected from a name
/// -- would otherwise each count bounds their own way.
fn whichBoundDeclares(
    gpa: std.mem.Allocator,
    ast: *const Ast,
    res: *const Resolution,
    memo: *constfold.Memo,
    traits: *const TraitsWritten,
    bounds: []const node_mod.TraitBound,
    wanted: StringId,
) std.mem.Allocator.Error!Declares {
    var count: u32 = 0;
    var found: Declares = .{ .other = 0 };

    for (bounds, 0..) |b, k| {
        if (b.kind == .callable) continue;
        const named = traits.named(ast.tokenText(b.named.name)) orelse {
            // A capability or integer-family bound declares no trait members. Any
            // other name this walk cannot resolve is a bound it cannot count,
            // and a count it cannot complete says nothing about which bound the
            // reference was read through.
            switch (resolve_mod.boundNames(ast, b.named.name, null)) {
                .capability, .integer, .owned => continue,
                .trait, .unknown => return .unresolved,
            }
        };
        // The pair and not the trait alone, because one type may implement a
        // trait once per argument: `Lookup[UInt64]` and `Lookup[Tail]` are two
        // bounds this counts, however alike their trait, and only the same
        // trait at the same written arguments is the repetition a program
        // means as one declaration to reach.
        if (try namedBefore(gpa, ast, res, memo, traits, bounds[0..k], b, named)) continue;
        const member = traits.declares(ast, named, wanted) orelse continue;
        count += 1;
        if (count == 1) found = .{ .one = .{ .trait = named, .member = member } };
    }

    return if (count == 1) found else .{ .other = count };
}

/// What the source says about a name written after a bounded one.
const Declares = union(enum) {
    /// Exactly one bound declares it, and this is what it declares.
    one: struct { trait: node_mod.DeclId, member: node_mod.DeclId },
    /// How many do, where that is not one -- none, or the ambiguity that is
    /// refused.
    other: u32,
    /// A bound this walk cannot resolve, so the count cannot be completed and
    /// says nothing about which bound the reference was read through.
    unresolved,
};

/// A settled reference read through a bound, held to the bound the source says
/// declares the name.
///
/// **Why it is not a tautology, and what it is not.** A reference off a bounded
/// parameter is not settled where it is written: the body stands for every type
/// the bound admits, and each instantiation settles the name its own way. What
/// the checker records against the token is therefore the key that will name it
/// -- the trait a bound named, the member of that trait, and the parameter
/// standing for the type -- and this derives that key from the source instead:
/// the parameter the head names, the bounds written on it, and which of those
/// bounds names a trait declaring a member of that name. Two derivations of one
/// answer, so the recorded one can be caught drifting.
///
/// A name after the first is derived the same way, from the bounds the declared
/// type the name before it reached carries -- so the oracle walks the run as the
/// checker does and holds the last step's key to what the source says. What it
/// selected from is spelled out as it goes, which is what the recorded key names
/// its own head.
///
/// What it catches: a reference read through the wrong bound, which is what a
/// parameter carrying several would give if the bound were picked by position
/// rather than by what it declares; a key built on the wrong parameter, which
/// is what would make one body's `W.Item` and another's the same type; a member
/// keyed by spelling where two traits spell one name; and a run whose steps the
/// checker took in another order than the names were written in.
///
/// **What no one checks**: which type an instantiation settles that key to.
/// That is answered per call and recorded nowhere, so the property says what it
/// can rather than reading the compiler's own answer back to it.
///
/// **Bound:** per name of the run, the bounds on the one thing carrying them and
/// per bound two keyed lookups into tables the case built once.
fn namesTheBoundThatDeclaresIt(
    gpa: std.mem.Allocator,
    work: *SettledRefWork,
    ast: *const Ast,
    program: *const Program,
    typing: *const Typing,
    held_by: node_mod.DeclId,
    ref: node_mod.TypeRef,
    written: WrittenSelection,
) !Held {
    // Absent where the checker recorded none, which here is a reference it
    // refused and reported -- what the poison property holds it to.
    const resolved = typing.writtenType(@intCast(written.last.index())) orelse return .unrecorded;

    // A head is read in one order and this is the source's own reading of it:
    // `Self` was answered by the caller, a type parameter of the declaration
    // writing the reference answers here, and a module is the furthest of the
    // three. A parameter of the trait whose signature this is stands in the
    // same place as the declaration's own, so it is asked for before an import
    // is -- otherwise a module sharing a trait parameter's name would be read
    // as the head, which is the reading the compiler refuses.
    const head = typeParamNamed(ast, held_by, written.head) orelse {
        if (traitParamNamed(ast, work.traits, held_by, written.head) != null) {
            return .no_bound_the_source_names;
        }
        return namesTheTypeTheModuleDeclares(gpa, work, ast, program, typing, ref, written);
    };

    var names = written.names();
    // The head, which the bounds of the first step are written on.
    _ = names.next();
    var at = names.next() orelse return .unrecorded;

    // What the run has reached, spelled as the pool spells it: the head, and a
    // name for every step already taken. The recorded key holds the type the
    // last name was selected from, and this is the source's own spelling of it.
    var from: std.ArrayList(u8) = .empty;
    defer from.deinit(gpa);
    try from.appendSlice(gpa, ast.tokenText(written.head));

    // The head's bounds are those written inline and those a trailing `where`
    // predicate writes on the bare parameter name; both constrain it equally.
    var head_bounds: std.ArrayList(node_mod.TraitBound) = .empty;
    defer head_bounds.deinit(gpa);
    try head_bounds.appendSlice(gpa, ast.boundsOf(head));
    for (ast.declWherePredicates(held_by)) |predicate| {
        const subject = predicate.subject;
        if (subject.kind != .named or subject.args.len() != 0 or subject.base != .none) continue;
        if (ast.tokenName(subject.name) != ast.tokenName(head.name)) continue;
        try head_bounds.appendSlice(gpa, ast.boundsIn(predicate.bounds));
    }
    var bounds: []const node_mod.TraitBound = head_bounds.items;
    var trait: node_mod.DeclId = node_mod.DeclId.none;
    var member: node_mod.DeclId = node_mod.DeclId.none;

    while (true) {
        switch (try whichBoundDeclares(
            gpa,
            ast,
            work.res,
            work.source_folds,
            work.traits,
            bounds,
            ast.tokenName(at),
        )) {
            .one => |found| {
                trait = found.trait;
                member = found.member;
            },
            // One bound declares it or the reference names nothing: two is the
            // ambiguity that is refused, and none is a name no bound holds.
            // Either way the checker recorded an answer where the source says
            // there is none, so the two have come apart.
            .other => |count| {
                try work.failures.append(gpa, .{
                    .path = work.display_path,
                    .what = try std.fmt.allocPrint(
                        gpa,
                        "`{s}` was read through a bound where the source declares it in other than one",
                        .{ast.tokenText(at)},
                    ),
                    .expected = try gpa.dupe(u8, "one bound declaring it"),
                    .actual = try std.fmt.allocPrint(gpa, "{d} of the bounds on `{s}`", .{
                        count,
                        from.items,
                    }),
                });
                return .through_a_bound;
            },
            .unresolved => return .no_bound_the_source_names,
        }

        const next = names.next() orelse break;
        // The next name is selected from what this one reached, so the bounds
        // the trait wrote on that declared type are what it is read through.
        try from.append(gpa, '.');
        try from.appendSlice(gpa, ast.tokenText(at));
        bounds = ast.declBounds(member);
        at = next;
    }

    // An implementation headed by a bare parameter defines the member for
    // what this reference was selected from, `I.Iter` as `I`, and the
    // reference reads as that definition -- which may itself be a key of
    // another trait awaiting an instantiation, `I.Item` for `I.Out`.
    if (readAsHeadDefinition(ast, typing, written.last)) return .through_a_bound;
    const key = typing.standinOf(resolved) orelse {
        try work.failures.append(gpa, .{
            .path = work.display_path,
            .what = try std.fmt.allocPrint(
                gpa,
                "`{s}` was read through a bound and recorded no key to settle at an instantiation",
                .{ast.tokenText(written.last)},
            ),
            .expected = try std.fmt.allocPrint(gpa, "the key `{s}`.`{s}` names", .{
                from.items,
                ast.tokenText(written.last),
            }),
            .actual = try gpa.dupe(u8, typing.nameOf(resolved)),
        });
        return .through_a_bound;
    };

    const reads = try std.fmt.allocPrint(gpa, "{s}.{s} off `{s}`", .{
        ast.tokenText(ast.declName(trait)),
        ast.tokenText(ast.declName(member)),
        from.items,
    });
    defer gpa.free(reads);

    const recorded = try std.fmt.allocPrint(gpa, "{s}.{s} off `{s}`", .{
        ast.tokenText(ast.declName(node_mod.DeclId.at(key.trait))),
        ast.tokenText(ast.declName(key.member)),
        typing.nameOf(key.held),
    });
    defer gpa.free(recorded);

    if (std.mem.eql(u8, reads, recorded)) return .through_a_bound;

    try work.failures.append(gpa, .{
        .path = work.display_path,
        .what = try std.fmt.allocPrint(
            gpa,
            "`{s}` was read through other than the bound that declares it",
            .{ast.tokenText(written.last)},
        ),
        .expected = try gpa.dupe(u8, reads),
        .actual = try gpa.dupe(u8, recorded),
    });
    return .through_a_bound;
}

/// Whether the checker settled the reference ending at `last` to the
/// definition an implementation headed by a bare parameter gives its member,
/// as it recorded on the selection the `.` before `last` makes.
fn readAsHeadDefinition(ast: *const Ast, typing: *const Typing, last: TokenId) bool {
    var at = last.index();
    while (at > 0) {
        at -= 1;
        switch (ast.tokenTag(TokenId.at(at))) {
            .comment => continue,
            .dot => return (typing.typeSelection(TokenId.at(at)) orelse return false).head_definition,
            else => return false,
        }
    }
    return false;
}

/// Whether one of the bounds already read names the same trait at the same
/// written arguments as `current`.
fn namedBefore(
    gpa: std.mem.Allocator,
    ast: *const Ast,
    res: *const Resolution,
    memo: *constfold.Memo,
    traits: *const TraitsWritten,
    earlier: []const node_mod.TraitBound,
    current: node_mod.TraitBound,
    trait: node_mod.DeclId,
) std.mem.Allocator.Error!bool {
    for (earlier) |b| {
        if (b.kind == .callable) continue;
        const named = traits.named(ast.tokenText(b.named.name)) orelse continue;
        if (named != trait) continue;
        if (try sameSourceBoundArgs(gpa, ast, res, memo, b.named.args, current.named.args)) return true;
    }
    return false;
}

/// Whether two source-derived bound argument lists denote the same exact
/// written types, with every array length and callable default read as the
/// value it folds to and, where a side does not fold, as it is spelled, and
/// every alias read as the type it names.
///
/// Written out here rather than called from the compiler: this is the oracle
/// the compiler's one comparison is held against. It rewrites each list to a
/// canonical text, substituting an alias's arguments for its parameters as it
/// goes, and compares the two texts; the compiler walks the two lists side by
/// side.
fn sameSourceBoundArgs(
    gpa: std.mem.Allocator,
    ast: *const Ast,
    res: *const Resolution,
    memo: *constfold.Memo,
    a: node_mod.TypeRefRange,
    b: node_mod.TypeRefRange,
) std.mem.Allocator.Error!bool {
    if (a.len() != b.len()) return false;
    var left: std.ArrayList(u8) = .empty;
    defer left.deinit(gpa);
    var right: std.ArrayList(u8) = .empty;
    defer right.deinit(gpa);
    for (ast.typeArgs(a), ast.typeArgs(b)) |x, y| {
        try writeSourceType(gpa, ast, res, memo, &left, x, null, 0);
        try writeSourceType(gpa, ast, res, memo, &right, y, null, 0);
    }
    return std.mem.eql(u8, left.items, right.items);
}

/// The alias a type is being read through and what it was applied to.
const SourceReading = struct {
    alias: node_mod.DeclId,
    args: []const node_mod.TypeRef,
    outer: ?*const SourceReading,
};

/// The deepest alias nesting the oracle reads; a program nesting more is one
/// the oracle cannot canonicalise, and its text says so.
const source_alias_depth: u32 = 64;

fn writeSourceType(
    gpa: std.mem.Allocator,
    ast: *const Ast,
    res: *const Resolution,
    memo: *constfold.Memo,
    out: *std.ArrayList(u8),
    ref: node_mod.TypeRef,
    reading: ?*const SourceReading,
    depth: u32,
) std.mem.Allocator.Error!void {
    const x = ast.withoutTypeGroups(ref);
    if (depth > source_alias_depth) return out.appendSlice(gpa, "(too deep)");
    if (reading) |read| {
        if (x.kind == .named and x.args.len() == 0 and ast.tokenTag(x.name) == .identifier) {
            for (ast.declTypeParams(read.alias), 0..) |param, i| {
                if (ast.tokenName(param.name) != ast.tokenName(x.name) or i >= read.args.len) continue;
                return writeSourceType(gpa, ast, res, memo, out, read.args[i], read.outer, depth + 1);
            }
        }
    }
    if ((x.kind == .named or x.kind == .selection) and x.name != TokenId.none) {
        if (res.aliasReachedBy(x.name)) |alias| {
            const through: SourceReading = .{ .alias = alias, .args = ast.typeArgs(x.args), .outer = reading };
            return writeSourceType(gpa, ast, res, memo, out, ast.declReturnRef(alias), &through, depth + 1);
        }
    }
    switch (x.kind) {
        .named, .selection => {
            // A type is the declaration a name reached, however it was
            // written: bare, or qualified by the module that declares it or
            // by one that re-exports it.
            const reached = res.writtenAt(x.name);
            if (reached != .none and res.kindOf(reached) == .declared_type) {
                try out.print(gpa, "named(decl{d}", .{@intFromEnum(res.declaredBy(reached))});
            } else if (reached != .none and res.kindOf(reached) == .builtin_type) {
                try out.print(gpa, "named(primitive{d}", .{@intFromEnum(res.builtinOf(reached).?)});
            } else {
                try out.print(gpa, "{s}(", .{@tagName(x.kind)});
                if (x.kind == .selection) try writeSourceType(gpa, ast, res, memo, out, ast.selectionBase(x), reading, depth + 1);
                try out.print(gpa, "spelled{d}.{d}", .{ @intFromEnum(ast.tokenTag(x.name)), @intFromEnum(ast.tokenName(x.name)) });
            }
        },
        .array => {
            try out.appendSlice(gpa, "array(");
            if (x.inferred_length != TokenId.none) {
                try out.appendSlice(gpa, "inferred");
            } else {
                try writeSourceConstant(gpa, ast, res, memo, out, x.length);
            }
        },
        .callable => {
            const callable = ast.callableType(x);
            try out.print(gpa, "callable({d}", .{@intFromEnum(callable.invocation)});
            for (ast.params[callable.params.start..callable.params.end]) |param| {
                try out.print(gpa, ",{d}:{d}:", .{ @intFromEnum(param.convention), @intFromEnum(ast.tokenName(param.name)) });
                try writeSourceType(gpa, ast, res, memo, out, param.written, reading, depth + 1);
                if (param.default != ExprId.none) {
                    try out.appendSlice(gpa, "=");
                    try writeSourceConstant(gpa, ast, res, memo, out, param.default);
                }
            }
            try out.appendSlice(gpa, "->");
            // An omitted result is `()`, which no other result is written as.
            if (callable.result.wasWritten()) try writeSourceType(gpa, ast, res, memo, out, callable.result, reading, depth + 1) else try out.appendSlice(gpa, "()");
            for (ast.contracts[callable.contracts.start..callable.contracts.end]) |contract| {
                try out.print(gpa, "+contract{d}{}", .{ @intFromEnum(contract.kind), contract.borrows_source });
                for ([_]node_mod.ContractPath{ contract.source, contract.destination, contract.target }) |path| {
                    try out.appendSlice(gpa, "/");
                    if (path.root != TokenId.none) try out.print(gpa, "{d}", .{@intFromEnum(ast.tokenName(path.root))});
                    for (ast.contractSteps(path)) |step| switch (step) {
                        .field => |name| try out.print(gpa, ".{d}", .{@intFromEnum(ast.tokenName(name))}),
                        .dereference => try out.appendSlice(gpa, ".*"),
                    };
                }
            }
            return out.appendSlice(gpa, ")");
        },
        .borrow, .grouped => try out.print(gpa, "{s}(", .{@tagName(x.kind)}),
        // A tuple is the prelude's declaration of its arity, which is what the
        // long form of its name reaches; the components follow in order.
        .tuple => if (res.tupleDecl(x.args.len())) |decl| {
            try out.print(gpa, "named(decl{d}", .{@intFromEnum(decl)});
        } else {
            try out.appendSlice(gpa, "tuple(");
        },
    }
    for (ast.typeArgs(x.args)) |argument| {
        try writeSourceType(gpa, ast, res, memo, out, argument, reading, depth + 1);
        try out.appendSlice(gpa, ",");
    }
    try out.appendSlice(gpa, ")");
}

fn writeSourceConstant(
    gpa: std.mem.Allocator,
    ast: *const Ast,
    res: *const Resolution,
    memo: *constfold.Memo,
    out: *std.ArrayList(u8),
    id: ExprId,
) std.mem.Allocator.Error!void {
    const folded = (try constfold.foldConstant(gpa, ast, res.nameSites(), memo, id)).checked() orelse {
        return out.print(gpa, "text[{s}]", .{ast.exprText(id)});
    };
    switch (folded) {
        .integer => |n| try out.print(gpa, "int[{d}]", .{n}),
        .truth => |t| try out.print(gpa, "truth[{}]", .{t}),
        .string => |bytes| try out.print(gpa, "string[{s}]", .{bytes}),
        .aggregate => |constant| try out.print(gpa, "aggregate[{d}]", .{@intFromEnum(constant)}),
    }
}

test "source implementation keys distinguish defaults beyond diagnostic display limits" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    var text: std.ArrayList(u8) = .empty;
    try text.appendSlice(gpa, "@copyable\nstruct Config {\n");
    for (0..140) |i| try text.print(gpa, "field{d:0>3}: UInt8,\n", .{i});
    try text.appendSlice(gpa, "z: UInt8,\n}\ntrait Selected[phantom F] { type Item }\nstruct Holder {}\n");
    for (1..3) |last| {
        try text.appendSlice(gpa, "impl Selected[fn(read config: Config = .{ ");
        for (0..140) |i| try text.print(gpa, "field{d:0>3} = 0, ", .{i});
        try text.print(gpa, "z = {d} }}) -> UInt8] for Holder {{ type Item = UInt8 }}\n", .{last});
    }
    try text.appendSlice(gpa, "fn main() -> UInt8 { let _holder: Holder = .{}\n0 }\n");
    const source: Source = .{ .path = "source-aggregate-default-keys.lin", .text = text.items };
    var sink = Sink.init(gpa);
    var interner: Interner = .empty;
    const tokens = try tokenize(gpa, &source, .from(0), &sink, &interner);
    var ast = try parse(gpa, &source, .from(0), tokens, &sink);
    const res = try resolveTree(gpa, &ast, &sink);
    try testing.expectEqual(@as(u32, 0), sink.error_count);
    var memo: constfold.Memo = .empty;
    defer memo.deinit(gpa);
    var keys: std.ArrayList([]const u8) = .empty;
    for (0..ast.declCount()) |i| {
        const d = node_mod.DeclId.at(@intCast(i));
        if (ast.declTag(d) != .associated_type) continue;
        if (try implKey(gpa, &ast, &res.resolution, &memo, res.source, d, "Item")) |key|
            try keys.append(gpa, key);
    }
    try testing.expectEqual(@as(usize, 2), keys.items.len);
    try testing.expect(!std.mem.eql(u8, keys.items[0], keys.items[1]));
}

test "source bound identity folds callable defaults" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    const source: Source = .{
        .path = "source-bound-callable-defaults.lin",
        .text =
        \\trait Give[phantom T] {}
        \\fn main() -> UInt8 { 0 }
        \\fn _probe[
        \\    A: Give[fn(read value: UInt8 = 1 + 1) -> UInt8],
        \\    B: Give[fn(read value: UInt8 = 2) -> UInt8],
        \\    C: Give[fn(read value: UInt8 = 3) -> UInt8],
        \\](_a: A, _b: B, _c: C) {}
        ,
    };
    var sink = Sink.init(gpa);
    var interner: Interner = .empty;
    const tokens = try tokenize(gpa, &source, .from(0), &sink, &interner);
    var ast = try parse(gpa, &source, .from(0), tokens, &sink);
    const res = try resolveTree(gpa, &ast, &sink);
    try testing.expectEqual(@as(u32, 0), sink.error_count);

    const probe = node_mod.DeclId.at(@intCast(ast.declCount() - 1));
    const params = ast.declTypeParams(probe);
    try testing.expectEqual(@as(usize, 3), params.len);
    const a = ast.boundsOf(params[0])[0].named.args;
    const b = ast.boundsOf(params[1])[0].named.args;
    const c = ast.boundsOf(params[2])[0].named.args;
    var memo: constfold.Memo = .empty;
    defer memo.deinit(gpa);

    try testing.expect(try sameSourceBoundArgs(gpa, &ast, &res.resolution, &memo, a, b));
    try testing.expect(!try sameSourceBoundArgs(gpa, &ast, &res.resolution, &memo, a, c));
}

/// `pct.Thing`: the reference whose head names a module, held to the type that
/// module declares.
///
/// A second derivation, like the rest of this property. The compiler answers
/// this by recording what the head reached and reading that record back; the
/// source says it by the import that binds the head in the file it was written
/// in, and by the module's own `pub` declaration of the name after the dot. So
/// what is held is that the checker landed on the declaration the text leads
/// to -- not merely on one spelled the same, and not on one the module keeps
/// private.
///
/// Passed over where the source does not say: no import here binds the head,
/// or the module declares no exported type of that name or two of them. Each
/// is a reference the compiler answered and this walk cannot follow, which is
/// the bucket beside it.
///
/// **Bound:** two keyed lookups and one walk of the run's own names.
fn namesTheTypeTheModuleDeclares(
    gpa: std.mem.Allocator,
    work: *SettledRefWork,
    ast: *const Ast,
    program: *const Program,
    typing: *const Typing,
    _: node_mod.TypeRef,
    written: WrittenSelection,
) !Held {
    const m = work.modules.moduleNamed(ast, written.head) orelse return .no_bound_the_source_names;

    var names = written.names();
    // The head, which is the module.
    _ = names.next();
    const at = names.next() orelse return .unrecorded;

    // This oracle checks namespace identity only through the exported type.
    // Further selection uses concrete implementation evidence, covered by
    // native and source-materialization properties rather than this oracle.
    if (at != written.last) return .no_bound_the_source_names;

    const declared = work.modules.typeExported(m, ast.tokenName(at)) orelse
        return .no_bound_the_source_names;
    const declared_at = ast.declName(declared);

    const resolved = typing.writtenType(@intCast(at.index())) orelse {
        try work.failures.append(gpa, .{
            .path = work.display_path,
            .what = try std.fmt.allocPrint(
                gpa,
                "`{s}`.`{s}` names a type that module declares and the checker recorded none",
                .{ ast.tokenText(written.head), ast.tokenText(at) },
            ),
            .expected = try std.fmt.allocPrint(gpa, "the type `{s}` declares as `{s}`", .{
                program.get(m).name,
                ast.tokenText(at),
            }),
            .actual = try gpa.dupe(u8, "nothing recorded against the name"),
        });
        return .through_a_module;
    };

    // The declaration itself, which tells one module's `Thing` from another's
    // where a spelling cannot, and which an instantiation answers for through
    // the template it was made from -- `pct.Pair[UInt8]` reaches `Pair`.
    if (typing.declOfType(resolved)) |reached| {
        if (reached == declared) return .through_a_module;

        try work.failures.append(gpa, .{
            .path = work.display_path,
            .what = try std.fmt.allocPrint(
                gpa,
                "`{s}`.`{s}` was read through other than the module the head names",
                .{ ast.tokenText(written.head), ast.tokenText(at) },
            ),
            .expected = try std.fmt.allocPrint(gpa, "`{s}` declared in `{s}`", .{
                ast.tokenText(declared_at),
                program.get(m).name,
            }),
            .actual = try std.fmt.allocPrint(gpa, "`{s}` declared in `{s}`", .{
                ast.tokenText(ast.declName(reached)),
                program.get(program.moduleOf(reached)).name,
            }),
        });
        return .through_a_module;
    }

    // A newtype registers no template, so it has no declaration to be compared
    // by and its spelling is what is left. Weaker on purpose and not silently:
    // two modules declaring one newtype name would pass this, and the module
    // the export was found in is what stands between them.
    if (std.mem.eql(u8, typing.nameOf(resolved), ast.tokenText(declared_at))) {
        return .through_a_module;
    }

    try work.failures.append(gpa, .{
        .path = work.display_path,
        .what = try std.fmt.allocPrint(
            gpa,
            "`{s}`.`{s}` was read as a type of another name",
            .{ ast.tokenText(written.head), ast.tokenText(at) },
        ),
        .expected = try std.fmt.allocPrint(gpa, "`{s}` declared in `{s}`", .{
            ast.tokenText(declared_at),
            program.get(m).name,
        }),
        .actual = try gpa.dupe(u8, typing.nameOf(resolved)),
    });
    return .through_a_module;
}

/// The type parameter of the trait a declaration's signature belongs to,
/// written with that name, or null where there is no such trait or it writes
/// none. A trait's parameters stand in its signatures beside the signature's
/// own.
fn traitParamNamed(
    ast: *const Ast,
    traits: *const TraitsWritten,
    d: node_mod.DeclId,
    name: TokenId,
) ?node_mod.TypeParam {
    const of = ast.declTrait(d);
    if (of == TokenId.none) return null;
    const trait = traits.named(ast.tokenText(of)) orelse return null;
    return typeParamNamed(ast, trait, name);
}

/// The type parameter of a declaration written with that name, or null where it
/// writes none.
fn typeParamNamed(ast: *const Ast, d: node_mod.DeclId, name: TokenId) ?node_mod.TypeParam {
    if (name == TokenId.none) return null;
    const wanted = ast.tokenName(name);
    for (ast.declTypeParams(d)) |p| {
        if (ast.tokenName(p.name) == wanted) return p;
    }
    return null;
}

/// What the traits a program writes are called and what each declares, as the
/// source spells them.
///
/// The oracle's own reading of the declarations, which is the point: the
/// property compares what the checker recorded against what a reader of the
/// program would answer, and a reader answers from the text. Every module,
/// the library's included, because a bound may name a trait the program did not
/// write and a reference through one is still a reference this can speak for.
///
/// **Bound:** one pass over the declarations per case, and one keyed lookup per
/// question afterwards.
const TraitsWritten = struct {
    /// The trait each name reaches, and whether one name reaches two.
    by_name: std.StringHashMapUnmanaged(Named) = .empty,
    /// The member each trait declares under each name, keyed by the token the
    /// trait's name is and the name interned. The token rather than the
    /// spelling, because an implementation's members are owned by the type's
    /// name and a type may be spelled as a trait is.
    members: std.AutoHashMapUnmanaged(Member, node_mod.DeclId) = .empty,

    const Named = struct { decl: node_mod.DeclId, twice: bool = false };
    const Member = struct { owner: u32, name: u32 };

    fn build(
        self: *TraitsWritten,
        gpa: std.mem.Allocator,
        ast: *const Ast,
        program: *const Program,
    ) !void {
        for (program.modules) |m| {
            for (m.decls.start..m.decls.end) |i| {
                const d = node_mod.DeclId.at(@intCast(i));
                const owner = ast.declOwner(d);
                if (owner != TokenId.none) {
                    try self.members.put(gpa, .{
                        .owner = @intFromEnum(owner),
                        .name = @intFromEnum(ast.tokenName(ast.declName(d))),
                    }, d);
                }
                if (ast.declTag(d) != .trait_) continue;
                const found = try self.by_name.getOrPut(gpa, ast.tokenText(ast.declName(d)));
                if (found.found_existing) {
                    found.value_ptr.twice = true;
                    continue;
                }
                found.value_ptr.* = .{ .decl = d };
            }
        }
    }

    fn deinit(self: *TraitsWritten, gpa: std.mem.Allocator) void {
        self.by_name.deinit(gpa);
        self.members.deinit(gpa);
    }

    /// The trait a bound's spelling reaches, or null where the source does not
    /// say: a name no trait here carries, or one two of them do.
    fn named(self: *const TraitsWritten, spelling: []const u8) ?node_mod.DeclId {
        const found = self.by_name.get(spelling) orelse return null;
        return if (found.twice) null else found.decl;
    }

    /// The member a trait declares under that name, or null where it declares
    /// none.
    fn declares(
        self: *const TraitsWritten,
        ast: *const Ast,
        trait: node_mod.DeclId,
        name: StringId,
    ) ?node_mod.DeclId {
        return self.members.get(.{
            .owner = @intFromEnum(ast.declName(trait)),
            .name = @intFromEnum(name),
        });
    }
};

/// What the imports the case wrote bind, and what each module exports as a
/// type, read out of the source.
///
/// Two keyed tables built once for the case, because the alternative is a walk
/// over every import for every reference and a walk over a module's
/// declarations inside it.
const ModulesWritten = struct {
    /// The module each `import` binds, keyed by the file that wrote it and the
    /// name it binds. The file, because an import binds a name there and
    /// nowhere else; the name it binds rather than the path it names, because
    /// `import a.b as c` is written `c` where it is used.
    bound: std.AutoHashMapUnmanaged(Bound, ModuleId) = .empty,
    /// The type each module declares under each name, and whether it declares
    /// two of that name. Only what a module exports, because reaching one from
    /// outside is what a qualified name does.
    exported: std.AutoHashMapUnmanaged(Exported, Named) = .empty,

    const Bound = struct { file: u32, name: u32 };
    const Exported = struct { module: u32, name: u32 };
    const Named = struct { decl: node_mod.DeclId, twice: bool = false };

    fn build(
        self: *ModulesWritten,
        gpa: std.mem.Allocator,
        ast: *const Ast,
        program: *const Program,
    ) !void {
        for (program.modules, 0..) |m, i| {
            const here = ModuleId.from(i);
            for (m.decls.start..m.decls.end) |j| {
                const d = node_mod.DeclId.at(@intCast(j));
                const at = ast.declName(d);
                if (at == TokenId.none) continue;
                const name = @intFromEnum(ast.tokenName(at));

                if (ast.declTag(d) == .import_) {
                    const reached = m.importedBy(d);
                    if (reached == .none) continue;
                    try self.bound.put(gpa, .{
                        .file = @intFromEnum(ast.fileOf(at)),
                        .name = name,
                    }, reached);
                    continue;
                }

                // A member is reached under the type or trait owning it rather
                // than under the module, so it is not what a name after a
                // module's dot can reach.
                if (ast.declOwner(d) != TokenId.none) continue;
                if (!declaresAType(ast.declTag(d))) continue;
                if (ast.declVisibility(d) == .private) continue;

                const found = try self.exported.getOrPut(gpa, .{
                    .module = @intFromEnum(here),
                    .name = name,
                });
                if (found.found_existing) {
                    found.value_ptr.twice = true;
                    continue;
                }
                found.value_ptr.* = .{ .decl = d };
            }
        }
    }

    fn deinit(self: *ModulesWritten, gpa: std.mem.Allocator) void {
        self.bound.deinit(gpa);
        self.exported.deinit(gpa);
    }

    /// The module a name reaches in the file that wrote it, or null where no
    /// import there binds it.
    fn moduleNamed(self: *const ModulesWritten, ast: *const Ast, at: TokenId) ?ModuleId {
        if (at == TokenId.none) return null;
        if (ast.tokenTag(at) != .identifier) return null;
        return self.bound.get(.{
            .file = @intFromEnum(ast.fileOf(at)),
            .name = @intFromEnum(ast.tokenName(at)),
        });
    }

    /// The type a module exports under that name, or null where it exports
    /// none, or two of that name so neither answers.
    fn typeExported(
        self: *const ModulesWritten,
        m: ModuleId,
        name: StringId,
    ) ?node_mod.DeclId {
        const found = self.exported.get(.{
            .module = @intFromEnum(m),
            .name = @intFromEnum(name),
        }) orelse return null;
        return if (found.twice) null else found.decl;
    }
};

/// Whether a declaration's tag is one that declares a type nameable from
/// another module.
fn declaresAType(tag: node_mod.Decl.Tag) bool {
    return switch (tag) {
        .struct_, .enum_, .newtype => true,
        else => false,
    };
}

/// The convention a hint's label shows, read back out of it.
///
/// A word boundary rather than a prefix: a parameter named `reading` shows
/// `reading:`, and a reader that stopped at four characters would call that a
/// lend the declaration never wrote.
fn conventionShown(label: []const u8) ?node_mod.Convention {
    var rest = label;
    if (std.mem.startsWith(u8, rest, lsp_hints.open_hint)) rest = rest[lsp_hints.open_hint.len..];
    for ([_]struct { []const u8, node_mod.Convention }{
        .{ "read", .read },
        .{ "inout", .inout },
        .{ "sink", .sink },
    }) |spelling| {
        const word, const convention = spelling;
        if (!std.mem.startsWith(u8, rest, word)) continue;
        const after = rest[word.len..];
        if (after.len == 0 or after[0] == ' ' or std.mem.eql(u8, after, lsp_hints.close_hint)) {
            return convention;
        }
    }
    return null;
}

/// What a case's file is called inside the case, which is the name a client
/// would open it under.
fn withinCase(case: Case, path: []const u8) []const u8 {
    if (path.len > case.entry.len and
        std.mem.startsWith(u8, path, case.entry) and
        path[case.entry.len] == '/') return path[case.entry.len + 1 ..];
    return std.fs.path.basename(path);
}

/// Lays a case out on disk as a program of its own, and says where.
///
/// A copy rather than the corpus's own directory. A server resolves an opened
/// file to a program by looking at the filesystem around it, and the corpus
/// keeps hundreds of unrelated single-file cases in one directory -- so a case
/// opened where it lives would drag in every sibling beside it, and the corpus
/// would cost the square of one case. A directory holding exactly this case's
/// files costs the case.
///
/// The manifest is what makes it a program rather than a loose directory, so
/// the server resolves every file of the case to the same entry the runner
/// hands the loader.
///
/// Costs the case's own bytes, once.
fn layOutCase(gpa: std.mem.Allocator, io: std.Io, dir: []const u8, case: Case) !void {
    try std.Io.Dir.cwd().createDirPath(io, dir);
    try writeFile(io, try std.fs.path.join(gpa, &.{ dir, "linea.json" }), "{}\n");

    for (case.files) |f| {
        const path = try std.fs.path.join(gpa, &.{ dir, withinCase(case, f.path) });
        if (std.fs.path.dirname(path)) |parent| try std.Io.Dir.cwd().createDirPath(io, parent);
        try writeFile(io, path, f.text);
    }
}

/// One request a script sent, so the transcript can be held to what was asked
/// rather than to how many bytes came back.
const Asked = struct {
    id: usize,
    method: []const u8,
    /// The document the request was about, as the script named it. Empty
    /// where the request was about the session rather than about a document.
    named: []const u8 = "",
    /// Whether `null` is an answer rather than a gap. True for a request about
    /// a position: whether anything is written under a cursor is what the
    /// question asks, and most bytes of most documents have nothing under them.
    may_be_null: bool = false,
    /// Whether an empty list is an answer rather than a gap.
    ///
    /// False where the script aimed the request at something the tree says is
    /// there, so a list with nothing in it is the capability having found
    /// nothing where there is something. A capability answering `[]` everywhere
    /// passes every check that only asks whether an answer arrived, which is the
    /// same shape as one answering `null` everywhere.
    may_be_empty: bool = true,
};

/// What a request about a position asks, apart from where it points.
///
/// One record rather than a parameter each, because the three questions -- may
/// this be null, may it be empty, does the method take a context -- are asked
/// per method and answered once, beside the method's name.
const About = struct {
    method: []const u8,
    may_be_null: bool = false,
    may_be_empty: bool = true,
    /// Whether the request carries the `context` member `references` requires.
    /// A `references` request without one is not a request the protocol
    /// describes, and the server refuses it before reaching the capability.
    context: bool = false,
};

/// A script, what it asked, and the request it sent after telling the server
/// to go.
const Session = struct {
    text: []const u8,
    asked: []const Asked,
    /// The id of the request written after `exit`. A server that ended where
    /// it was told to never reads it, so an answer carrying this id is the
    /// notification having been ignored.
    after_exit: usize,
};

/// Writes one request about a position, and records what it asked.
fn askAt(
    gpa: std.mem.Allocator,
    w: *std.Io.Writer,
    asked: *std.ArrayList(Asked),
    id: *usize,
    about: About,
    named: []const u8,
    position: lsp.types.Position,
) !void {
    try w.print(
        \\{{"jsonrpc":"2.0","id":{d},"method":"{s}","params":{{"textDocument":{{"uri":
    , .{ id.*, about.method });
    try std.json.Stringify.encodeJsonString(named, .{}, w);
    if (about.context) try w.writeAll("},\"context\":{\"includeDeclaration\":true");
    try w.print(
        \\}},"position":{{"line":{d},"character":{d}}}}}}}
        \\
    , .{ position.line, position.character });
    try asked.append(gpa, .{
        .id = id.*,
        .method = about.method,
        .named = named,
        .may_be_null = about.may_be_null,
        .may_be_empty = about.may_be_empty,
    });
    id.* += 1;
}

const StructuralTemplateExtents = struct {
    items: []token.TokenRange,

    fn init(gpa: std.mem.Allocator, ast: *const Ast) !StructuralTemplateExtents {
        var count: usize = 0;
        for (0..ast.declCount()) |i| {
            if (ast.declTag(node_mod.DeclId.at(@intCast(i))) == .template_impl) count += 1;
        }
        const items = try gpa.alloc(token.TokenRange, count);
        var at: usize = 0;
        for (0..ast.declCount()) |i| {
            const declaration = node_mod.DeclId.at(@intCast(i));
            if (ast.declTag(declaration) != .template_impl) continue;
            items[at] = ast.declTokens(declaration);
            at += 1;
        }
        std.mem.sortUnstable(token.TokenRange, items, {}, struct {
            fn before(_: void, lhs: token.TokenRange, rhs: token.TokenRange) bool {
                return lhs.start.index() < rhs.start.index();
            }
        }.before);
        return .{ .items = items };
    }

    fn deinit(self: *StructuralTemplateExtents, gpa: std.mem.Allocator) void {
        gpa.free(self.items);
        self.* = undefined;
    }

    fn contains(self: *const StructuralTemplateExtents, token_id: TokenId) bool {
        var lo: usize = 0;
        var hi = self.items.len;
        while (lo < hi) {
            const mid = lo + (hi - lo) / 2;
            if (self.items[mid].start.index() <= token_id.index()) lo = mid + 1 else hi = mid;
        }
        if (lo == 0) return false;
        const extent = self.items[lo - 1];
        return token_id.index() < extent.end.index();
    }
};

/// The byte the file's first literal begins at, or null where the file writes
/// none.
///
/// A literal and not merely the first expression, because this is the position
/// hover is held to an answer at and a literal is the one expression whose
/// having a type follows from the tree alone. A name can reach a module or a
/// trait, which are namespaces rather than values and which the checker settles
/// no type for; picking the position by asking what the checker settled would
/// be the property deciding what it is checking.
///
/// The first with tokens of its own: an expression the parser gave up on
/// occupies none, so no byte of the document is inside it and no cursor can
/// reach it.
fn firstWritten(ast: *const Ast, part: *const ast_mod.FilePart, templates: *const StructuralTemplateExtents) ?u32 {
    for (part.expr_start..part.expr_end) |i| {
        const id = node_mod.ExprId.at(@intCast(i));
        switch (ast.exprTag(id)) {
            .int_literal, .bool_literal => {},
            else => continue,
        }
        const tokens = ast.exprTokens(id);
        if (tokens.len() == 0) continue;
        if (templates.contains(tokens.start)) continue;
        return ast.tokenSpan(tokens.start).start;
    }
    return null;
}

/// The byte the name of the file's first function begins at, or null where the
/// file declares none.
///
/// A function and not merely the first declaration, because this is the
/// position `references` is held to an answer at and a function's own name is
/// the one token whose being a binding follows from the tree: `impl` names a
/// type declared elsewhere, and picking the position by asking which tokens
/// declare something would be the property deciding what it is checking.
fn firstFunction(ast: *const Ast, part: *const ast_mod.FilePart) ?u32 {
    for (part.decl_start..part.decl_end) |i| {
        const id = node_mod.DeclId.at(@intCast(i));
        if (ast.declTag(id) != .function) continue;
        const name = ast.declName(id);
        if (name == TokenId.none) continue;
        return ast.tokenSpan(name).start;
    }
    return null;
}

/// A script that opens every file of a case, asks about each, edits one and
/// closes them all.
///
/// Written as JSON here rather than assembled from the protocol's types
/// because a script is what a client sends: the point of the property is that
/// whatever arrives over the wire is answered, and building the message from
/// the same types that parse it would test neither the parsing nor the
/// dispatch.
///
/// What was asked is returned beside the bytes. The transcript is a list of
/// answers with nothing in it saying which question each belongs to, so a
/// reader that did not carry the questions could only count -- and a
/// capability answering `null` to every one of them writes exactly as many
/// responses as a capability that worked.
///
/// A capability about a position is asked twice per document: once at the
/// first byte, which every document has and most documents have nothing under,
/// and once where the tree says an expression begins. The program is a
/// parameter for that second one alone: where something is written is the
/// tree's answer, and a script that guessed at a position would be asking a
/// question of its own.
fn sessionOver(
    gpa: std.mem.Allocator,
    case: Case,
    program: *const Program,
    table: *const FileTable,
    accepted: bool,
) !Session {
    var out: std.Io.Writer.Allocating = .init(gpa);
    const w = &out.writer;
    var asked: std.ArrayList(Asked) = .empty;
    var template_extents = try StructuralTemplateExtents.init(gpa, &program.ast);
    defer template_extents.deinit(gpa);

    try w.writeAll(
        \\{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"capabilities":{}}}
        \\{"jsonrpc":"2.0","method":"initialized","params":{}}
        \\
    );
    try asked.append(gpa, .{ .id = 1, .method = "initialize" });

    for (case.files) |f| {
        try w.writeAll(
            \\{"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":
        );
        try std.json.Stringify.encodeJsonString(withinCase(case, f.path), .{}, w);
        try w.writeAll(",\"languageId\":\"linea\",\"version\":1,\"text\":");
        try std.json.Stringify.encodeJsonString(f.text, .{}, w);
        try w.writeAll("}}}\n");
    }

    // Every request the server advertises, asked of every document. A
    // capability answered only over the file its own case holds is a
    // capability nothing has run over a program with a hole in it -- and a
    // hole is what most of this corpus is about.
    var id: usize = 2;
    for (case.files) |f| {
        const named = withinCase(case, f.path);
        for ([_][]const u8{
            "textDocument/semanticTokens/full",
            "textDocument/documentSymbol",
            "textDocument/foldingRange",
        }) |method| {
            try w.print(
                \\{{"jsonrpc":"2.0","id":{d},"method":"{s}","params":{{"textDocument":{{"uri":
            , .{ id, method });
            try std.json.Stringify.encodeJsonString(named, .{}, w);
            try w.writeAll("}}}\n");
            try asked.append(gpa, .{ .id = id, .method = method, .named = named });
            id += 1;
        }

        // A range covering anything a file can be, since what is asked for is
        // whether every binding in it can be answered about.
        try w.print(
            \\{{"jsonrpc":"2.0","id":{d},"method":"textDocument/inlayHint","params":{{"textDocument":{{"uri":
        , .{id});
        try std.json.Stringify.encodeJsonString(named, .{}, w);
        try w.print(
            \\}},"range":{{"start":{{"line":0,"character":0}},"end":{{"line":{d},"character":0}}}}}}}}
            \\
        , .{std.math.maxInt(u32)});
        try asked.append(gpa, .{ .id = id, .method = "textDocument/inlayHint", .named = named });
        id += 1;

        try w.print(
            \\{{"jsonrpc":"2.0","id":{d},"method":"textDocument/formatting","params":{{"textDocument":{{"uri":
        , .{id});
        try std.json.Stringify.encodeJsonString(named, .{}, w);
        try w.writeAll("},\"options\":{\"tabSize\":4,\"insertSpaces\":true}}}\n");
        try asked.append(gpa, .{ .id = id, .method = "textDocument/formatting", .named = named });
        id += 1;

        // The first byte of the document, which is a position in every file
        // there is -- including one that does not parse and one the program
        // does not reach. Nothing need be written there, so `null` is an
        // answer; what is asked is that a cursor anywhere is survivable.
        for ([_]About{
            .{ .method = "textDocument/definition", .may_be_null = true },
            .{ .method = "textDocument/hover", .may_be_null = true },
            .{ .method = "textDocument/references", .may_be_null = true, .context = true },
            .{ .method = "textDocument/documentHighlight", .may_be_null = true },
        }) |about| {
            try askAt(gpa, w, &asked, &id, about, named, .{ .line = 0, .character = 0 });
        }
    }

    // And once more where the tree says something is written: the first
    // literal of each file the program holds. A capability answering `null`
    // everywhere writes one response per request exactly as a working one
    // does, so somewhere it has to be held to an answer -- and a literal is
    // where the checker settled a type whatever else the program does.
    //
    // In a program the compiler accepted. A rejected one has expressions the
    // checker could not settle a type for, and hover reports what the compiler
    // decided rather than the placeholder standing in for a decision it never
    // made -- so `null` there is the answer and not a gap.
    var files = lsp_publish.files(program);
    while (files.next()) |file| {
        const part = program.ast.partOfFile(file) orelse continue;
        const wrote = firstWritten(&program.ast, part, &template_extents) orelse continue;
        const named = withinCase(case, table.get(file).path);
        const position = lsp.offsets.indexToPosition(part.source, wrote, .@"utf-16");

        try askAt(gpa, w, &asked, &id, .{
            .method = "textDocument/hover",
            .may_be_null = !accepted,
        }, named, position);
        // Whether the name there reaches a declaration is the program's
        // business, and a corpus of programs with holes in them is mostly
        // names that reach nothing.
        try askAt(gpa, w, &asked, &id, .{
            .method = "textDocument/definition",
            .may_be_null = true,
        }, named, position);
    }

    // And once more at the name of the first function each file declares. A
    // function's own name is a binding wherever the program was accepted --
    // an unused declaration is not accepted -- so all three of these have
    // something to say there: at least the declaration itself, since the
    // script asks for it to be included, and for `definition` the token that
    // declaration was written at, which is the token the cursor is on. `null`
    // and `[]` are the two ways a capability says nothing, and a capability
    // saying nothing everywhere writes one response per request exactly as a
    // working one does.
    files = lsp_publish.files(program);
    while (files.next()) |file| {
        const part = program.ast.partOfFile(file) orelse continue;
        const wrote = firstFunction(&program.ast, part) orelse continue;
        const named = withinCase(case, table.get(file).path);
        const position = lsp.offsets.indexToPosition(part.source, wrote, .@"utf-16");

        try askAt(gpa, w, &asked, &id, .{
            .method = "textDocument/references",
            .may_be_null = !accepted,
            .may_be_empty = !accepted,
            .context = true,
        }, named, position);
        try askAt(gpa, w, &asked, &id, .{
            .method = "textDocument/documentHighlight",
            .may_be_null = !accepted,
            .may_be_empty = !accepted,
        }, named, position);
        try askAt(gpa, w, &asked, &id, .{
            .method = "textDocument/definition",
            .may_be_null = !accepted,
        }, named, position);
    }

    // One edit, which is the notification an editor sends on every keystroke
    // and the only one that arrives against a document the server already
    // holds.
    const edited = withinCase(case, case.files[0].path);
    try w.writeAll(
        \\{"jsonrpc":"2.0","method":"textDocument/didChange","params":{"textDocument":{"uri":
    );
    try std.json.Stringify.encodeJsonString(edited, .{}, w);
    try w.writeAll(",\"version\":2},\"contentChanges\":[{\"text\":");
    try std.json.Stringify.encodeJsonString(case.files[0].text, .{}, w);
    try w.writeAll("}]}}\n");

    for (case.files) |f| {
        try w.writeAll(
            \\{"jsonrpc":"2.0","method":"textDocument/didClose","params":{"textDocument":{"uri":
        );
        try std.json.Stringify.encodeJsonString(withinCase(case, f.path), .{}, w);
        try w.writeAll("}}}\n");
    }

    // The handshake the protocol describes, and then one more request. A
    // server that read the notification and stopped never sees the request
    // below it, so the answer that does not come is what says `exit` was
    // acted on rather than dispatched to nothing.
    try w.print(
        \\{{"jsonrpc":"2.0","id":{d},"method":"shutdown"}}
        \\{{"jsonrpc":"2.0","method":"exit"}}
        \\{{"jsonrpc":"2.0","id":{d},"method":"shutdown"}}
        \\
    , .{ id, id + 1 });
    try asked.append(gpa, .{ .id = id, .method = "shutdown" });

    return .{
        .text = out.written(),
        .asked = try asked.toOwnedSlice(gpa),
        .after_exit = id + 1,
    };
}

/// A member of a JSON object, where the value is one at all.
fn memberOf(value: std.json.Value, name: []const u8) ?std.json.Value {
    return switch (value) {
        .object => |o| o.get(name),
        else => null,
    };
}

/// Whether every element of an array carries every named member.
fn everyElementCarries(value: std.json.Value, names: []const []const u8) bool {
    const items = switch (value) {
        .array => |a| a.items,
        else => return false,
    };
    for (items) |item| {
        for (names) |name| {
            if (memberOf(item, name) == null) return false;
        }
    }
    return true;
}

/// What a request's answer has to be, where the answer it got is not.
///
/// The protocol's own shape per method, checked against the bytes the client
/// receives rather than against the type the server returned: a handler
/// answering the wrong union arm compiles, and what an editor reads is the
/// JSON.
fn shapeWanted(method: []const u8, result: std.json.Value) ?[]const u8 {
    if (std.mem.eql(u8, method, "initialize")) {
        if (memberOf(result, "capabilities") == null) return "an object carrying `capabilities`";
        return null;
    }
    if (std.mem.eql(u8, method, "textDocument/semanticTokens/full")) {
        const data = memberOf(result, "data") orelse return "an object carrying `data`";
        if (data != .array) return "an object carrying `data`";
        return null;
    }
    if (std.mem.eql(u8, method, "textDocument/documentSymbol")) {
        const names: []const []const u8 = &.{ "name", "kind", "range", "selectionRange" };
        if (!everyElementCarries(result, names)) return "symbols carrying a name, a kind and their ranges";
        return null;
    }
    if (std.mem.eql(u8, method, "textDocument/foldingRange")) {
        if (!everyElementCarries(result, &.{ "startLine", "endLine" })) return "folds carrying the lines they span";
        return null;
    }
    if (std.mem.eql(u8, method, "textDocument/inlayHint")) {
        if (!everyElementCarries(result, &.{ "position", "label" })) return "hints carrying a position and a label";
        return null;
    }
    if (std.mem.eql(u8, method, "textDocument/formatting")) {
        if (!everyElementCarries(result, &.{ "range", "newText" })) return "edits carrying a range and a text";
        return null;
    }
    if (std.mem.eql(u8, method, "textDocument/definition")) {
        if (memberOf(result, "uri") == null or memberOf(result, "range") == null) {
            return "a location carrying a uri and a range";
        }
        return null;
    }
    if (std.mem.eql(u8, method, "textDocument/references")) {
        if (!everyElementCarries(result, &.{ "uri", "range" })) {
            return "locations carrying a uri and a range";
        }
        return null;
    }
    if (std.mem.eql(u8, method, "textDocument/documentHighlight")) {
        if (!everyElementCarries(result, &.{"range"})) return "highlights carrying a range";
        return null;
    }
    if (std.mem.eql(u8, method, "textDocument/hover")) {
        const contents = memberOf(result, "contents") orelse return "an object carrying `contents`";
        if (memberOf(contents, "value") == null) return "contents carrying a value";
        return null;
    }
    return null;
}

/// A server driven over any program finishes, and answers.
///
/// The guarantee the frontend already makes -- no input is refused, every
/// malformed thing is a diagnostic rather than a stop -- asked of the layer an
/// editor actually talks to. It is the part of the server no golden reaches:
/// a golden says what one session answered, and this says that every program
/// in the corpus is a session that ends.
///
/// Finishing is necessary and not sufficient, because the loop swallows what a
/// notification handler returns: a server whose every `didOpen` failed would
/// finish in silence. So the transcript is read too, message by message and
/// against the requests the script sent. Every request is answered, no answer
/// is an error, each is the shape the protocol gives that method, and a
/// capability answers something about every document its program holds --
/// since a capability answering `null` everywhere writes one response per
/// request exactly as a working one does, and a tally of messages cannot tell
/// them apart.
///
/// `null` is an answer in three places and a gap everywhere else: about a
/// document no module of the program reaches, since the server read nothing to
/// answer from; about a document that does not lay out again, which is what
/// `formatSource` decides here as it decides it for the server; and about a
/// position, where whether anything is written under the cursor is the question
/// being asked. The last is why two requests per file are aimed at bytes the
/// tree says hold something -- the first literal, and the first function's own
/// name -- and, where the compiler accepted the program, are held to an answer
/// there.
///
/// An empty list is the other way to say nothing, and at those two positions it
/// is a gap too: a capability answering `[]` everywhere writes one response per
/// request exactly as `null` everywhere does. Both positions are read off the
/// tree rather than off what a pass decided, so the property does not get to
/// choose what it is checking.
///
/// At least one `publishDiagnostics` per file opened, since that is the
/// sentence a `didOpen` is supposed to begin. And no answer to the request the
/// script sends after `exit`, since a session that ended where it was told to
/// never reads it.
///
/// Costs one check of the case per document opened, plus one for the edit --
/// which is what a keystroke costs, times the files an editor could have open
/// -- and one pass over the transcript. What is held is one entry per request
/// the script sent and one per file of the case, never one per message.
fn checkSurvives(
    gpa: std.mem.Allocator,
    io: std.Io,
    checked_library: *const loader.CheckedLibrary,
    failures: *std.ArrayList(Failure),
    scratch: []const u8,
    case: Case,
    ordinal: usize,
    program: *const Program,
    table: *const FileTable,
    accepted: bool,
) !void {
    const dir = try std.fs.path.join(gpa, &.{
        scratch,
        "lsp",
        try std.fmt.allocPrint(gpa, "{d}", .{ordinal}),
    });
    {
        const zone = tracy.beginZone(@src(), "layout");
        defer zone.end();
        try layOutCase(gpa, io, dir, case);
    }

    const script = try sessionOver(gpa, case, program, table, accepted);

    var out: std.Io.Writer.Allocating = .init(gpa);
    const status = replayed: {
        const replay_zone = tracy.beginZone(@src(), "replay");
        defer replay_zone.end();
        break :replayed session.replay(gpa, io, checked_library, dir, script.text, &out.writer, null) catch |err| {
            try failures.append(gpa, .{
                .path = case.display_path,
                .what = "a server finishes a session over any program",
                .expected = "a session that ends",
                .actual = @errorName(err),
            });
            return;
        };
    };
    const transcript = out.written();

    // The script asks for a shutdown before it says to go, which is the ending
    // both sides agreed on.
    if (status != 0) {
        try failures.append(gpa, .{
            .path = case.display_path,
            .what = "a server that was shut down leaves saying so",
            .expected = "0",
            .actual = try std.fmt.allocPrint(gpa, "{d}", .{status}),
        });
    }

    // Read once into a scratch arena: the transcript's values are looked at
    // here and nothing below this call holds one, so what a case costs the run
    // is its failures and not its answers.
    var reading = std.heap.ArenaAllocator.init(gpa);
    defer reading.deinit();
    const scratch_gpa = reading.allocator();

    var answered: std.AutoHashMapUnmanaged(usize, std.json.Value) = .empty;
    var refused: std.AutoHashMapUnmanaged(usize, void) = .empty;
    var published: usize = 0;

    var lines = std.mem.splitScalar(u8, transcript, '\n');
    while (lines.next()) |line| {
        if (std.mem.trim(u8, line, " \r\t").len == 0) continue;
        const message = std.json.parseFromSliceLeaky(std.json.Value, scratch_gpa, line, .{}) catch {
            try failures.append(gpa, .{
                .path = case.display_path,
                .what = "a server writes JSON-RPC",
                .expected = "a message a client can parse",
                .actual = try gpa.dupe(u8, line),
            });
            return;
        };

        if (memberOf(message, "method")) |method| {
            if (method == .string and
                std.mem.eql(u8, method.string, "textDocument/publishDiagnostics")) published += 1;
            continue;
        }

        const id = switch (memberOf(message, "id") orelse continue) {
            .integer => |i| std.math.cast(usize, i) orelse continue,
            else => continue,
        };
        if (memberOf(message, "error") != null) {
            try refused.put(scratch_gpa, id, {});
            continue;
        }
        try answered.put(scratch_gpa, id, memberOf(message, "result") orelse .null);
    }

    if (published < case.files.len) {
        try failures.append(gpa, .{
            .path = case.display_path,
            .what = "a server publishes for a document it was told about",
            .expected = try std.fmt.allocPrint(gpa, "at least {d} notification(s)", .{case.files.len}),
            .actual = try std.fmt.allocPrint(gpa, "{d}", .{published}),
        });
    }

    // Which documents the program holds. A directory can hold a `.lin` no
    // module reaches -- a submodule nothing imports, a name the library
    // already owns -- and an editor can open it; the server has read nothing
    // to answer about it, and saying so is the answer rather than a gap.
    var held: std.StringHashMapUnmanaged(void) = .empty;
    var files = lsp_publish.files(program);
    while (files.next()) |file| try held.put(scratch_gpa, withinCase(case, table.get(file).path), {});

    // Whether a document has a layout to be given back, asked of the routine
    // the server asks. A file that does not parse has no faithful printing, so
    // `null` is what formatting answers about it -- and a second reading here
    // would agree about every file anyone wrote and disagree about one the
    // parser recovered from.
    var lays_out: std.StringHashMapUnmanaged(void) = .empty;
    for (case.files) |f| {
        var sink = Sink.init(scratch_gpa);
        const source: Source = .{ .path = f.path, .text = f.text };
        const formatting = try fmt.formatSource(scratch_gpa, &source, .from(0), &sink);
        if (formatting.text != null) try lays_out.put(scratch_gpa, withinCase(case, f.path), {});
    }

    for (script.asked) |ask| {
        if (refused.contains(ask.id)) {
            try failures.append(gpa, .{
                .path = case.display_path,
                .what = try std.fmt.allocPrint(gpa, "a server answers `{s}`", .{ask.method}),
                .expected = "an answer",
                .actual = "an error response",
            });
            continue;
        }

        const result = answered.get(ask.id) orelse {
            try failures.append(gpa, .{
                .path = case.display_path,
                .what = try std.fmt.allocPrint(gpa, "a server answers `{s}`", .{ask.method}),
                .expected = "a response carrying the request's id",
                .actual = "no response",
            });
            continue;
        };

        if (result == .null) {
            const answerable = if (ask.may_be_null)
                false
            else if (std.mem.eql(u8, ask.method, "shutdown"))
                false
            else if (std.mem.eql(u8, ask.method, "textDocument/formatting"))
                lays_out.contains(ask.named)
            else if (ask.named.len > 0)
                held.contains(ask.named)
            else
                true;
            if (!answerable) continue;
            try failures.append(gpa, .{
                .path = case.display_path,
                .what = try std.fmt.allocPrint(
                    gpa,
                    "a server answers `{s}` about a document it holds",
                    .{ask.method},
                ),
                .expected = try std.fmt.allocPrint(gpa, "an answer about {s}", .{ask.named}),
                .actual = "null",
            });
            continue;
        }

        const empty = switch (result) {
            .array => |a| a.items.len == 0,
            else => false,
        };
        if (empty and !ask.may_be_empty) {
            try failures.append(gpa, .{
                .path = case.display_path,
                .what = try std.fmt.allocPrint(
                    gpa,
                    "a server answers `{s}` about a name the tree holds",
                    .{ask.method},
                ),
                .expected = try std.fmt.allocPrint(gpa, "at least one site in {s}", .{ask.named}),
                .actual = "[]",
            });
            continue;
        }

        if (shapeWanted(ask.method, result)) |wanted| {
            try failures.append(gpa, .{
                .path = case.display_path,
                .what = try std.fmt.allocPrint(gpa, "a server answers `{s}` in shape", .{ask.method}),
                .expected = wanted,
                .actual = try gpa.dupe(u8, transcript),
            });
        }
    }

    if (answered.contains(script.after_exit) or refused.contains(script.after_exit)) {
        try failures.append(gpa, .{
            .path = case.display_path,
            .what = "a session ends where the client said to",
            .expected = "nothing read after `exit`",
            .actual = "a request sent after `exit` was answered",
        });
    }
}

/// What a session case's two copies of one program say, where they disagree.
///
/// A `didOpen` carries its source inline, and that inline copy is the buffer
/// the server answers from. A file of the same name beside the script is the
/// case's own program: `check` runs over it, its exit status is recorded, and
/// every corpus property reads it. So a session case holds one program under
/// one name in two places, and only one of them drives the session -- a field
/// added to the file changes nothing any golden can show.
///
/// This renders every disagreement, in the order the script opens the files,
/// so a case whose two copies agree renders nothing. What a case may do with a
/// disagreement is the caller's rule, not this function's.
///
/// Bound: one pass over the script's lines, and one read of each file a
/// `didOpen` names.
const HeldTwice = struct {
    /// Every `didOpen` naming a file that sits beside the script.
    compared: u32 = 0,
    /// Every `didOpen` naming one that does not, which has no second copy to
    /// disagree with.
    alone: u32 = 0,
    /// How many of `compared` disagree.
    apart: u32 = 0,
    /// The copies that disagree, both sides of each.
    differing: []const u8 = "",
};

fn heldTwice(
    gpa: std.mem.Allocator,
    io: std.Io,
    dir: []const u8,
    script: []const u8,
) !HeldTwice {
    var found: HeldTwice = .{};

    var out: std.Io.Writer.Allocating = .init(gpa);
    var reading = std.heap.ArenaAllocator.init(gpa);
    defer reading.deinit();
    const scratch_gpa = reading.allocator();

    var lines = std.mem.splitScalar(u8, script, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \r\t");
        if (trimmed.len == 0) continue;

        // A script is what a client sends, and one case sends a line no client
        // would. What is not a JSON-RPC message names no document.
        const message = std.json.parseFromSliceLeaky(std.json.Value, scratch_gpa, trimmed, .{}) catch continue;
        const method = memberOf(message, "method") orelse continue;
        if (method != .string or !std.mem.eql(u8, method.string, "textDocument/didOpen")) continue;

        const params = memberOf(message, "params") orelse continue;
        const document = memberOf(params, "textDocument") orelse continue;
        const named = memberOf(document, "uri") orelse continue;
        const opened = memberOf(document, "text") orelse continue;
        if (named != .string or opened != .string) continue;

        // A script names a file the way the case does: relative to the case's
        // own directory. Anything else names no file beside the script, which
        // is the state `alone` counts rather than the state this compares.
        if (std.fs.path.isAbsolute(named.string) or
            std.mem.indexOf(u8, named.string, "://") != null)
        {
            found.alone += 1;
            continue;
        }

        const path = try std.fs.path.join(scratch_gpa, &.{ dir, named.string });
        const beside = try readIfExists(io, scratch_gpa, path) orelse {
            found.alone += 1;
            continue;
        };
        found.compared += 1;
        if (std.mem.eql(u8, beside, opened.string)) continue;
        found.apart += 1;

        try out.writer.print("{s}, as the script opens it:\n", .{named.string});
        try writeAsLines(&out.writer, opened.string);
        try out.writer.print("{s}, as it sits beside the script:\n", .{named.string});
        try writeAsLines(&out.writer, beside);
    }

    found.differing = out.written();
    return found;
}

fn checkSessionWork(
    scratch: std.mem.Allocator,
    io: std.Io,
    checked_library: *const loader.CheckedLibrary,
    tests_dir_path: []const u8,
    session_path: []const u8,
    update: bool,
    failures: *std.ArrayList(Failure),
    updated: *std.ArrayList([]const u8),
    logs: *std.Io.Writer.Allocating,
    result: *SessionResult,
) !void {
    const rel_dir = std.fs.path.dirname(session_path) orelse return error.SessionHasNoDirectory;
    const full_dir = try std.fs.path.join(scratch, &.{ tests_dir_path, rel_dir });
    const requests = try readFileAlloc(
        io,
        scratch,
        try std.fs.path.join(scratch, &.{ tests_dir_path, session_path }),
    );
    const display = try displayPath(scratch, tests_dir_path, rel_dir);
    const session_zone = tracy.beginZone(@src(), "lsp.session");
    defer session_zone.end();
    session_zone.setText(display);

    var out: std.Io.Writer.Allocating = .init(scratch);
    _ = try session.replay(scratch, io, checked_library, full_dir, requests, &out.writer, &logs.writer);

    var again: std.Io.Writer.Allocating = .init(scratch);
    _ = try session.replay(scratch, io, checked_library, full_dir, requests, &again.writer, &logs.writer);
    const stable = std.mem.eql(u8, out.written(), again.written());
    if (!stable) {
        try failures.append(scratch, .{
            .path = display,
            .what = "a server answers one script the same way twice",
            .expected = out.written(),
            .actual = again.written(),
        });
    }

    const golden = try std.fs.path.join(scratch, &.{ full_dir, session_golden });
    if (try readIfExists(io, scratch, golden)) |expected| {
        if (try compare(
            scratch,
            io,
            failures,
            display,
            "session",
            golden,
            expected,
            out.written(),
            update,
            false,
        )) try updated.append(scratch, golden);
    }

    const held = try heldTwice(scratch, io, full_dir, requests);
    result.deterministic = stable;
    result.held_once = held.compared > 0;
    result.opened_and_beside = held.compared;
    result.opened_differing = held.apart;
    result.opened_alone = held.alone;
    const recorded_path = try std.fs.path.join(scratch, &.{ full_dir, session_disk });
    if (try readIfExists(io, scratch, recorded_path)) |recorded| {
        if (try compare(
            scratch,
            io,
            failures,
            display,
            "the file beside the script",
            recorded_path,
            recorded,
            held.differing,
            update,
            false,
        )) try updated.append(scratch, recorded_path);
    } else if (held.differing.len != 0) {
        try failures.append(scratch, .{
            .path = display,
            .what = "a session case holds its program once",
            .expected = "the script opens the bytes of the file beside it",
            .actual = held.differing,
        });
    }
}

fn checkSession(
    scratch: std.mem.Allocator,
    keep: std.mem.Allocator,
    io: std.Io,
    checked_library: *const loader.CheckedLibrary,
    tests_dir_path: []const u8,
    session_path: []const u8,
    update: bool,
) !SessionResult {
    var failures: std.ArrayList(Failure) = .empty;
    var updated: std.ArrayList([]const u8) = .empty;
    var logs: std.Io.Writer.Allocating = .init(scratch);
    var result: SessionResult = .{};
    checkSessionWork(
        scratch,
        io,
        checked_library,
        tests_dir_path,
        session_path,
        update,
        &failures,
        &updated,
        &logs,
        &result,
    ) catch |err| {
        result.err = err;
    };
    result.failures = try retainFailures(keep, failures.items);
    result.updated = try retainStrings(keep, updated.items);
    result.logs = try keep.dupe(u8, logs.written());
    return result;
}

const SessionWalk = struct {
    fn run(
        io: std.Io,
        checked_library: *const loader.CheckedLibrary,
        tests_dir_path: []const u8,
        paths: []const []const u8,
        update: bool,
        results: []SessionResult,
        keep: *std.heap.ArenaAllocator,
        next: *std.atomic.Value(usize),
    ) void {
        tracy.setThreadName("session");
        var per_session = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer per_session.deinit();

        while (true) {
            const at = next.fetchAdd(1, .monotonic);
            if (at >= paths.len) break;
            _ = per_session.reset(.{ .retain_with_limit = 4 << 20 });
            results[at] = checkSession(
                per_session.allocator(),
                keep.allocator(),
                io,
                checked_library,
                tests_dir_path,
                paths[at],
                update,
            ) catch |err| .{ .err = err };
        }
    }
};

fn runSessions(
    gpa: std.mem.Allocator,
    io: std.Io,
    checked_library: *const loader.CheckedLibrary,
    tests_dir_path: []const u8,
    paths: []const []const u8,
    update: bool,
    workers_wanted: usize,
    keep_arenas: []std.heap.ArenaAllocator,
) ![]SessionResult {
    const results = try gpa.alloc(SessionResult, paths.len);
    errdefer gpa.free(results);
    if (paths.len == 0) return results;

    const workers = @min(@max(1, workers_wanted), paths.len);
    std.debug.assert(keep_arenas.len >= workers);
    var next: std.atomic.Value(usize) = .init(0);
    if (workers == 1) {
        SessionWalk.run(io, checked_library, tests_dir_path, paths, update, results, &keep_arenas[0], &next);
        return results;
    }

    const threads = try gpa.alloc(std.Thread, workers);
    defer gpa.free(threads);
    var spawned: usize = 0;
    errdefer for (threads[0..spawned]) |thread| thread.join();
    for (threads, 0..) |*thread, i| {
        thread.* = try std.Thread.spawn(compiler_stack.spawn_config, SessionWalk.run, .{
            io,
            checked_library,
            tests_dir_path,
            paths,
            update,
            results,
            &keep_arenas[i],
            &next,
        });
        spawned += 1;
    }
    for (threads) |thread| thread.join();
    return results;
}

/// A file's text, ending where a line ends, so what follows it in a golden
/// starts at a column a reader can see.
fn writeAsLines(w: *std.Io.Writer, text: []const u8) !void {
    try w.writeAll(text);
    if (text.len == 0 or text[text.len - 1] != '\n') try w.writeByte('\n');
}

const LayoutJob = struct {
    display_path: []const u8,
    text: []const u8,
    case_ordinal: usize = 0,
    case_order: usize = std.math.maxInt(usize),
};

/// Renumber only the oracle's generated type names, including their diagnostic
/// labels. First occurrence assigns identity; later references reuse it. Every
/// declaration and expected measurement remains part of the comparison key.
fn layoutComparisonKey(gpa: std.mem.Allocator, text: []const u8) ![]const u8 {
    var names: std.StringHashMapUnmanaged(usize) = .empty;
    defer names.deinit(gpa);
    var out: std.Io.Writer.Allocating = .init(gpa);
    defer out.deinit();

    var at: usize = 0;
    while (at < text.len) {
        const start = at;
        if (!std.ascii.isAlphanumeric(text[at]) and text[at] != '_') {
            at += 1;
            try out.writer.writeByte(text[start]);
            continue;
        }
        while (at < text.len and (std.ascii.isAlphanumeric(text[at]) or text[at] == '_')) : (at += 1) {}
        const word = text[start..at];
        if (!isLayoutTypeName(word)) {
            try out.writer.writeAll(word);
            continue;
        }
        const next = names.count();
        const entry = try names.getOrPut(gpa, word);
        if (!entry.found_existing) entry.value_ptr.* = next;
        try out.writer.print("o0_t{d}", .{entry.value_ptr.*});
    }
    return gpa.dupe(u8, out.written());
}

fn isLayoutTypeName(word: []const u8) bool {
    if (word.len < 5 or word[0] != 'o') return false;
    var at: usize = 1;
    while (at < word.len and std.ascii.isDigit(word[at])) : (at += 1) {}
    if (at == 1 or !std.mem.startsWith(u8, word[at..], "_t")) return false;
    at += 2;
    const digits = at;
    while (at < word.len and std.ascii.isDigit(word[at])) : (at += 1) {}
    return at > digits and at == word.len;
}

fn layoutBatchText(gpa: std.mem.Allocator, jobs: []const LayoutJob) ![]const u8 {
    var out: std.Io.Writer.Allocating = .init(gpa);
    defer out.deinit();
    var seen: std.StringHashMapUnmanaged(void) = .empty;
    defer {
        var keys = seen.keyIterator();
        while (keys.next()) |key| gpa.free(key.*);
        seen.deinit(gpa);
    }
    for (jobs) |job| {
        const key = try layoutComparisonKey(gpa, job.text);
        const entry = seen.getOrPut(gpa, key) catch |err| {
            gpa.free(key);
            return err;
        };
        if (entry.found_existing) {
            gpa.free(key);
            continue;
        }
        // Hash matches still compare the complete key. Keep the original text
        // and jobs so a failed batch can report every affected source case.
        try out.writer.writeAll(job.text);
        try out.writer.writeByte('\n');
    }
    return gpa.dupe(u8, out.written());
}

test "layout oracle jobs share one translation unit in case order" {
    const text = try layoutBatchText(testing.allocator, &.{
        .{ .display_path = "a.lin", .text = "struct o1_t1 { uint8_t m0; };\n" },
        .{ .display_path = "b.lin", .text = "struct o2_t1 { uint64_t m0; };\n" },
    });
    defer testing.allocator.free(text);
    try testing.expectEqualStrings("struct o1_t1 { uint8_t m0; };\n\nstruct o2_t1 { uint64_t m0; };\n\n", text);
}

test "layout oracle deduplication shares identical checks across case and type identities" {
    const first =
        \\struct o7_t12 { uint8_t m0; };
        \\_Static_assert(sizeof(struct o7_t12) == 1, "size of o7_t12");
        \\_Static_assert(_Alignof(struct o7_t12) == 1, "alignment of o7_t12");
        \\_Static_assert(offsetof(struct o7_t12, m0) == 0, "offset 0 of o7_t12");
        \\struct o7_t99 { struct o7_t12 m0; struct o7_t12 m1; };
        \\_Static_assert(sizeof(struct o7_t99) == 2, "size of o7_t99");
    ;
    const same =
        \\struct o28_t450 { uint8_t m0; };
        \\_Static_assert(sizeof(struct o28_t450) == 1, "size of o28_t450");
        \\_Static_assert(_Alignof(struct o28_t450) == 1, "alignment of o28_t450");
        \\_Static_assert(offsetof(struct o28_t450, m0) == 0, "offset 0 of o28_t450");
        \\struct o28_t3 { struct o28_t450 m0; struct o28_t450 m1; };
        \\_Static_assert(sizeof(struct o28_t3) == 2, "size of o28_t3");
    ;
    const jobs = [_]LayoutJob{
        .{ .display_path = "first.lin", .text = first, .case_ordinal = 8, .case_order = 3 },
        .{ .display_path = "same.lin", .text = same, .case_ordinal = 29, .case_order = 5 },
    };
    const text = try layoutBatchText(testing.allocator, &jobs);
    defer testing.allocator.free(text);
    try testing.expectEqualStrings(first ++ "\n", text);
    try testing.expectEqualStrings(same, jobs[1].text);
    try testing.expectEqual(@as(usize, 29), jobs[1].case_ordinal);
    try testing.expectEqual(@as(usize, 5), jobs[1].case_order);
}

test "layout oracle deduplication retains different measurements and member shapes" {
    const original =
        \\struct o1_t7 { uint64_t m0; };
        \\_Static_assert(sizeof(struct o1_t7) == 8, "size of o1_t7");
        \\_Static_assert(_Alignof(struct o1_t7) == 8, "alignment of o1_t7");
        \\_Static_assert(offsetof(struct o1_t7, m0) == 0, "offset 0 of o1_t7");
    ;
    for ([_][]const u8{
        \\struct o2_t19 { uint64_t m0; };
        \\_Static_assert(sizeof(struct o2_t19) == 16, "size of o2_t19");
        \\_Static_assert(_Alignof(struct o2_t19) == 8, "alignment of o2_t19");
        \\_Static_assert(offsetof(struct o2_t19, m0) == 0, "offset 0 of o2_t19");
        ,
        \\struct o2_t19 { uint64_t m0; };
        \\_Static_assert(sizeof(struct o2_t19) == 8, "size of o2_t19");
        \\_Static_assert(_Alignof(struct o2_t19) == 4, "alignment of o2_t19");
        \\_Static_assert(offsetof(struct o2_t19, m0) == 0, "offset 0 of o2_t19");
        ,
        \\struct o2_t19 { uint64_t m0; };
        \\_Static_assert(sizeof(struct o2_t19) == 8, "size of o2_t19");
        \\_Static_assert(_Alignof(struct o2_t19) == 8, "alignment of o2_t19");
        \\_Static_assert(offsetof(struct o2_t19, m0) == 4, "offset 0 of o2_t19");
        ,
        \\struct o2_t19 { double m0; };
        \\_Static_assert(sizeof(struct o2_t19) == 8, "size of o2_t19");
        \\_Static_assert(_Alignof(struct o2_t19) == 8, "alignment of o2_t19");
        \\_Static_assert(offsetof(struct o2_t19, m0) == 0, "offset 0 of o2_t19");
        ,
    }) |different| {
        const text = try layoutBatchText(testing.allocator, &.{
            .{ .display_path = "first.lin", .text = original },
            .{ .display_path = "different.lin", .text = different },
        });
        defer testing.allocator.free(text);
        const expected = try std.mem.concat(testing.allocator, u8, &.{ original, "\n", different, "\n" });
        defer testing.allocator.free(expected);
        try testing.expectEqualStrings(expected, text);
    }
}

test "layout oracle deduplication preserves distinct type references and complete identifiers" {
    for ([_][2][]const u8{
        .{
            "struct o1_t2 { uint8_t m0; };\nstruct o1_t3 { uint8_t m0; };\nstruct o1_t4 { struct o1_t2 m0; struct o1_t3 m1; };",
            "struct o9_t8 { uint8_t m0; };\nstruct o9_t7 { uint8_t m0; };\nstruct o9_t6 { struct o9_t8 m0; struct o9_t8 m1; };",
        },
        .{ "struct prefix_o1_t2 { uint8_t m0; };", "struct prefix_o9_t8 { uint8_t m0; };" },
        .{ "struct o1_t2_suffix { uint8_t m0; };", "struct o9_t8_suffix { uint8_t m0; };" },
        .{ "struct o1_t2x { uint8_t m0; };", "struct o9_t8x { uint8_t m0; };" },
    }) |pair| {
        const text = try layoutBatchText(testing.allocator, &.{
            .{ .display_path = "first.lin", .text = pair[0] },
            .{ .display_path = "different.lin", .text = pair[1] },
        });
        defer testing.allocator.free(text);
        const expected = try std.mem.concat(testing.allocator, u8, &.{ pair[0], "\n", pair[1], "\n" });
        defer testing.allocator.free(expected);
        try testing.expectEqualStrings(expected, text);
    }
}

test "layout oracle deduplication releases allocations on failure" {
    const AllocationCase = struct {
        fn run(gpa: std.mem.Allocator) !void {
            const first = "struct o1_t1 { uint8_t m0; };";
            const different = "struct o3_t7 { uint64_t m0; };";
            const text = layoutBatchText(gpa, &.{
                .{ .display_path = "first.lin", .text = first },
                .{ .display_path = "same.lin", .text = "struct o2_t4 { uint8_t m0; };" },
                .{ .display_path = "different.lin", .text = different },
            }) catch |err| switch (err) {
                // Allocating writers report allocation failures as WriteFailed.
                error.WriteFailed => return error.OutOfMemory,
                else => return err,
            };
            defer gpa.free(text);
            try testing.expectEqualStrings(first ++ "\n" ++ different ++ "\n", text);
        }
    };
    try testing.checkAllAllocationFailures(testing.allocator, AllocationCase.run, .{});
}

test "a delayed layout failure keeps its place among case failures" {
    var failures = [_]Failure{
        .{ .path = "a.lin", .what = "discovery", .expected = "", .actual = "" },
        .{ .path = "a.lin", .what = "next case", .expected = "", .actual = "", .case_ordinal = 2, .case_order = 2 },
        .{ .path = "a.lin", .what = "before", .expected = "", .actual = "", .case_ordinal = 1, .case_order = 2 },
        .{ .path = "a.lin", .what = "after", .expected = "", .actual = "", .case_ordinal = 1, .case_order = 4 },
        .{ .path = "a.lin", .what = "layout", .expected = "", .actual = "", .case_ordinal = 1, .case_order = 3 },
    };
    std.mem.sort(Failure, &failures, {}, failureLess);
    try testing.expectEqualStrings("discovery", failures[0].what);
    try testing.expectEqualStrings("before", failures[1].what);
    try testing.expectEqualStrings("layout", failures[2].what);
    try testing.expectEqualStrings("after", failures[3].what);
    try testing.expectEqualStrings("next case", failures[4].what);
}

/// Hands one module's layout oracle to `cc`, answering with what it said where
/// the two readings disagree.
///
/// `-fsyntax-only` because nothing is to be produced: every comparison is a
/// `_Static_assert`, so `cc` performs the diff and a disagreement is a
/// diagnostic naming the type and the member. Nothing here reads an answer
/// back -- the oracle decides nothing about any program, and can only refuse to
/// agree.
fn disagreesAboutLayout(
    gpa: std.mem.Allocator,
    io: std.Io,
    env: Settings,
    display_path: []const u8,
    text: []const u8,
) !?[]const u8 {
    const dir = env.scratch_dir;
    const name = try scratchName(gpa, display_path);
    defer gpa.free(name);
    const path = try std.fmt.allocPrint(gpa, "{s}/{s}.layout.c", .{ dir, name });
    defer gpa.free(path);

    try writeFile(io, path, text);

    const failure = (try toolchain.checkC(gpa, io, path)) orelse return null;
    // A host without a C compiler has already failed every case that needs a
    // backend, so nothing is learned by failing this one too.
    if (failure.missing) return null;
    return failure.output;
}

const layout_batch_size = 64;

test "layout oracle deduplication reports every rejected original case" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    const scratch = try tmp.dir.realPathFileAlloc(testing.io, ".", gpa);
    const cache: OutcomeCache = .{ .dir = scratch, .salt = 0 };
    const settings: Settings = .{
        .library = test_library.get(),
        .cache = &cache,
        .update = false,
        .sanitize = null,
        .runtime_path = null,
        .scratch_dir = scratch,
    };
    var failures: std.ArrayList(Failure) = .empty;
    try checkLayoutJobs(gpa, testing.io, settings, &.{
        .{ .display_path = "first.lin", .case_ordinal = 1, .case_order = 3, .text = "struct o1_t0 { char m0; };\n_Static_assert(sizeof(struct o1_t0) == 0, \"wrong size of o1_t0\");\n" },
        .{ .display_path = "second.lin", .case_ordinal = 2, .case_order = 7, .text = "struct o2_t9 { char m0; };\n_Static_assert(sizeof(struct o2_t9) == 0, \"wrong size of o2_t9\");\n" },
    }, &failures);
    try testing.expectEqual(@as(usize, 2), failures.items.len);
    try testing.expectEqualStrings("first.lin", failures.items[0].path);
    try testing.expectEqualStrings("second.lin", failures.items[1].path);
    try testing.expectEqual(@as(usize, 1), failures.items[0].case_ordinal);
    try testing.expectEqual(@as(usize, 7), failures.items[1].case_order);
}

fn checkLayoutJobs(
    gpa: std.mem.Allocator,
    io: std.Io,
    env: Settings,
    jobs: []const LayoutJob,
    failures: *std.ArrayList(Failure),
) !void {
    const dir = env.scratch_dir;
    var start: usize = 0;
    while (start < jobs.len) : (start += layout_batch_size) {
        const batch = jobs[start..@min(start + layout_batch_size, jobs.len)];
        const text = try layoutBatchText(gpa, batch);
        defer gpa.free(text);
        const path = try std.fmt.allocPrint(gpa, "{s}/layout-batch-{d}.c", .{ dir, start / layout_batch_size });
        defer gpa.free(path);
        try writeFile(io, path, text);

        const failed = (try toolchain.checkC(gpa, io, path)) orelse continue;
        if (failed.missing) return;

        // A failed batch is split only for attribution. Each fragment is still
        // the same independent C oracle; no diagnostic text is parsed to decide
        // which case disagreed.
        var attributed = false;
        for (batch) |job| {
            const said = try disagreesAboutLayout(gpa, io, env, job.display_path, job.text) orelse continue;
            attributed = true;
            try failures.append(gpa, .{
                .path = job.display_path,
                .what = "the layout table and `cc` disagree about a type",
                .expected = "one arrangement, read two ways",
                .actual = said,
                .case_ordinal = job.case_ordinal,
                .case_order = job.case_order,
            });
        }
        if (!attributed) {
            try failures.append(gpa, .{
                .path = "the layout oracle",
                .what = "namespaced fragments compose into one C translation unit",
                .expected = "a batch accepted when each fragment is accepted alone",
                .actual = failed.output,
            });
        }
    }
}

fn emitOrRecord(
    gpa: std.mem.Allocator,
    failures: *std.ArrayList(Failure),
    ir: *std.Io.Writer.Allocating,
    module: *const MirModule,
    table: *FileTable,
    sink: *Sink,
    display_path: []const u8,
) !bool {
    // Whether the program was accepted is settled after the composed step,
    // not before it: discovery reports [L-Size] about concrete types the
    // checker never saw. A caller that emitted without checking the sink would
    // run a program the compiler had rejected and read its exit status as the
    // language's.
    //
    // Asked here because this is the one place both such callers pass through,
    // and the sink is already in hand.
    if (sink.hasErrors()) {
        var refused: std.Io.Writer.Allocating = .init(gpa);
        try render.renderAll(&refused.writer, table, sink, .{ .color = .never });
        try failures.append(gpa, .{
            .path = display_path,
            .what = "lowering rejected a program the passes before it accepted",
            .expected = "a verdict settled once, after the pass that can still refuse",
            .actual = refused.written(),
        });
        return false;
    }

    if (try emitMlir(gpa, &ir.writer, module, table, sink)) return true;

    var why: std.Io.Writer.Allocating = .init(gpa);
    try render.renderAll(&why.writer, table, sink, .{ .color = .never });
    try failures.append(gpa, .{
        .path = display_path,
        .what = "the backend refused to emit the module it was handed",
        .expected = "code for a program every rule accepted",
        .actual = why.written(),
    });
    return false;
}

test "canonical call index covers generated expressions" {
    const gpa = testing.allocator;
    var checked = try lsp_analysis.of(gpa, gpa, test_library.get(), &.{.{ .path = "main.lin", .text =
        \\struct Mark {}
        \\trait Literal { fn value(self: Self) -> UInt8 }
        \\impl Literal for UInt8 {
        \\    fn value(self: UInt8) -> UInt8 { self }
        \\}
        \\trait Structural { fn result(self: Self) -> UInt8 }
        \\template impl Structural {
        \\    fn result(_self: Self) -> UInt8 {
        \\        let n: UInt8 = 7
        \\        n.value()
        \\    }
        \\}
        \\derive Structural for Mark
        \\fn main() -> UInt8 {
        \\    let mark: Mark = .{}
        \\    Structural.result(mark)
        \\}
    }}, "main.lin");
    defer checked.deinit();
    try testing.expect(!checked.sink.hasErrors());
    const expanded = &checked.semantics.expanded;
    const typing = &checked.semantics.typing;
    const source_count = checked.program.ast.exprCount();
    try testing.expect(expanded.ast.exprCount() > source_count);
    var generated_calls: usize = 0;
    for (typing.calls) |call| {
        if (call.at.index() < source_count) continue;
        try testing.expect(typing.call_index.callOf(typing, call.at) != null);
        const part = expanded.ast.partOfFile(expanded.ast.fileOfExpr(call.at)).?;
        try testing.expect(part.decl_start < part.decl_end);
        const module = expanded.moduleOf(node_mod.DeclId.at(part.decl_start));
        // The prelude can contribute generated calls too; this fixture
        // must contribute its own call beyond the source domain.
        if (!expanded.get(module).library) generated_calls += 1;
    }
    try testing.expect(generated_calls > 0);
}

/// Where recorded outcomes and build intermediates go when `--scratch` is absent.
const default_scratch_dir = ".zig-cache/conformance-scratch";

const RunnerOptions = struct {
    update: bool = false,
    every_property: bool = false,
    properties: bool = false,
    property_cases: ?[]const u8 = null,
    walkers_wanted: ?usize = null,
    runtime_path: ?[]const u8 = null,
    scratch_dir: []const u8 = default_scratch_dir,
    sanitize: ?[]const u8 = null,
    compiler_path: ?[]const u8 = null,
    enforce_floors: bool = false,
    programs: u32 = 0,
    seed: u64 = 0,
    sweep: bool = false,
    sweep_sample: ?usize = null,
    sweep_base: ?u32 = null,
    sweep_filter: ?[]const u8 = null,
    /// Check the soundness matrix and the generated storage programs instead
    /// of the corpus.
    soundness: bool = false,
    /// How many generated storage programs a soundness run checks.
    storage_programs: u32 = 0,
    /// Leave the matrix out of a soundness run, for a run that searches new
    /// seeds: the matrix does not depend on the seed.
    skip_matrix: bool = false,
    /// Build every case that runs at every optimisation level, and hold it to
    /// answering alike at all of them.
    levels: bool = false,
};

test "focused properties are explicit and have a separate population" {
    const ordinary = try parseRunnerOptions(&.{ "runner", "tests" });
    const focused = try parseRunnerOptions(&.{ "runner", "small", "--properties" });
    try testing.expect(!ordinary.properties);
    try testing.expect(focused.properties);
    try testing.expect(!focused.enforce_floors);
    try testing.expect(Property.renamed.focused());
    try testing.expect(Property.walk_consumes.focused());
    try testing.expect(Property.regions.focused());
    try testing.expect(!Property.poison_free.focused());
    try testing.expect(!Property.command.focused());
    var corpus = std.mem.zeroes(Corpus);
    corpus.cases = 3;
    try testing.expectEqual(@as(u32, 0), Property.renamed.populationIn(Property.renamed.accountingPopulation(corpus, false)));
    try testing.expectEqual(@as(u32, 3), Property.renamed.populationIn(Property.renamed.accountingPopulation(corpus, true)));
    try testing.expectEqual(@as(u32, 3), Property.poison_free.populationIn(Property.poison_free.accountingPopulation(corpus, false)));
    try testing.expect(!Property.renamed.accountsFor(Property.renamed.accountingPopulation(corpus, false), 0, 3));
}

fn optionValue(args: []const []const u8, at: *usize) ![]const u8 {
    if (at.* + 1 >= args.len) return error.InvalidOptionValue;
    at.* += 1;
    const value = args[at.*];
    if (value.len == 0 or std.mem.startsWith(u8, value, "--")) return error.InvalidOptionValue;
    return value;
}

fn propertyPathMatches(path: []const u8, selected: []const u8) bool {
    if (std.mem.eql(u8, path, selected)) return true;
    if (std.mem.startsWith(u8, path, selected) and path.len > selected.len and path[selected.len] == '/') return true;
    // A transcript holds its own expected output, so only a `.lin` case has
    // goldens beside it to select.
    const stem = if (std.mem.endsWith(u8, selected, ".lin")) selected[0 .. selected.len - ".lin".len] else selected;
    if (!std.mem.startsWith(u8, path, stem) or path.len <= stem.len or path[stem.len] != '.') return false;
    for (golden_extensions) |extension| {
        if (std.mem.eql(u8, path[stem.len..], extension)) return true;
    }
    return false;
}

fn selectPropertyPaths(gpa: std.mem.Allocator, paths: []const []const u8, manifest: []const u8) ![]const []const u8 {
    const entries = try propertyEntries(gpa, paths, manifest);
    defer gpa.free(entries);
    return selectPaths(gpa, paths, entries);
}

/// The cases a manifest names, each checked against the paths it selects from.
fn propertyEntries(gpa: std.mem.Allocator, paths: []const []const u8, manifest: []const u8) ![]const []const u8 {
    var entries: std.ArrayList([]const u8) = .empty;
    errdefer entries.deinit(gpa);
    var lines = std.mem.splitScalar(u8, manifest, '\n');
    while (lines.next()) |line| {
        const entry = std.mem.trim(u8, line, " \t\r");
        if (entry.len == 0 or entry[0] == '#') continue;
        if (std.fs.path.isAbsolute(entry) or std.mem.indexOf(u8, entry, "..") != null or entry[entry.len - 1] == '/') return error.InvalidPropertyCase;
        for (entries.items) |previous| {
            if (propertyPathMatches(previous, entry) or propertyPathMatches(entry, previous)) return error.DuplicatePropertyCase;
        }
        // A module is selected whole: selecting one of its files would omit
        // its manifest, imports, or driver and change the program being checked.
        for (paths) |path| {
            if (!std.mem.endsWith(u8, path, "/main.lin")) continue;
            const module = path[0 .. path.len - "/main.lin".len];
            if (std.mem.startsWith(u8, entry, module) and entry.len > module.len and entry[module.len] == '/') return error.InvalidPropertyCase;
        }
        var found = false;
        for (paths) |path| {
            if ((std.mem.eql(u8, path, entry) and (std.mem.endsWith(u8, entry, ".lin") or std.mem.endsWith(u8, entry, ".cmd"))) or
                (std.mem.startsWith(u8, path, entry) and path.len > entry.len and path[entry.len] == '/')) found = true;
        }
        if (!found) return error.MissingPropertyCase;
        try entries.append(gpa, entry);
    }
    if (entries.items.len == 0) return error.EmptyPropertyCases;
    return entries.toOwnedSlice(gpa);
}

/// The paths a selected case owns: its files, and every golden named by its
/// stem. Goldens walked apart from their cases are selected by the same names.
fn selectPaths(gpa: std.mem.Allocator, paths: []const []const u8, entries: []const []const u8) ![]const []const u8 {
    var selected: std.ArrayList([]const u8) = .empty;
    errdefer selected.deinit(gpa);
    for (paths) |path| {
        for (entries) |entry| {
            if (propertyPathMatches(path, entry)) {
                try selected.append(gpa, path);
                break;
            }
        }
    }
    return selected.toOwnedSlice(gpa);
}

test "focused properties select only named cases and their goldens" {
    const paths = [_][]const u8{ "one.lin", "one.stderr", "one.exit", "one.more.lin", "two/main.lin", "two/linea.json", "two.stderr", "other.lin", "cmd/check.cmd" };
    const selected = try selectPropertyPaths(testing.allocator, &paths, "# corpus witnesses\none.lin\ntwo\ncmd/check.cmd\n");
    defer testing.allocator.free(selected);
    try testing.expectEqual(@as(usize, 7), selected.len);
    for (selected) |path| {
        try testing.expect(!std.mem.eql(u8, path, "one.more.lin"));
        try testing.expect(!std.mem.eql(u8, path, "other.lin"));
    }
    try testing.expectError(error.MissingPropertyCase, selectPropertyPaths(testing.allocator, &paths, "missing.lin"));
    try testing.expectError(error.DuplicatePropertyCase, selectPropertyPaths(testing.allocator, &paths, "two\ntwo/main.lin"));
    try testing.expectError(error.EmptyPropertyCases, selectPropertyPaths(testing.allocator, &paths, "# empty"));
    try testing.expectError(error.InvalidPropertyCase, selectPropertyPaths(testing.allocator, &paths, "two/main.lin"));
    try testing.expectError(error.InvalidOptionValue, parseRunnerOptions(&.{ "runner", "tests", "--property-cases", "cases.txt" }));
}

fn parseRunnerOptions(args: []const []const u8) !RunnerOptions {
    var options: RunnerOptions = .{};
    var non_one_walker_seen = false;
    var non_none_sanitizer_seen = false;

    var ai: usize = 2;
    while (ai < args.len) : (ai += 1) {
        if (std.mem.eql(u8, args[ai], "--update")) {
            options.update = true;
        } else if (std.mem.eql(u8, args[ai], "--properties")) {
            options.properties = true;
        } else if (std.mem.eql(u8, args[ai], "--property-cases")) {
            options.property_cases = try optionValue(args, &ai);
        } else if (std.mem.eql(u8, args[ai], "--every-property")) {
            options.every_property = true;
        } else if (std.mem.eql(u8, args[ai], "--walkers")) {
            const value = try optionValue(args, &ai);
            options.walkers_wanted = std.fmt.parseInt(usize, value, 10) catch
                return error.InvalidOptionValue;
            non_one_walker_seen = non_one_walker_seen or options.walkers_wanted.? != 1;
        } else if (std.mem.eql(u8, args[ai], "--runtime")) {
            options.runtime_path = try optionValue(args, &ai);
        } else if (std.mem.eql(u8, args[ai], "--scratch")) {
            options.scratch_dir = try optionValue(args, &ai);
        } else if (std.mem.eql(u8, args[ai], "--sweep")) {
            options.sweep = true;
        } else if (std.mem.eql(u8, args[ai], "--sweep-sample")) {
            const value = try optionValue(args, &ai);
            options.sweep_sample = std.fmt.parseInt(usize, value, 10) catch
                return error.InvalidOptionValue;
            if (options.sweep_sample.? >= sweep_dimensions.len) return error.InvalidSweepDimension;
        } else if (std.mem.eql(u8, args[ai], "--sweep-base")) {
            const value = try optionValue(args, &ai);
            const base = std.fmt.parseInt(u32, value, 10) catch return error.InvalidOptionValue;
            // The largest point in a balanced sample is four times its base.
            if (base == 0 or base > std.math.maxInt(u32) / 4) return error.InvalidOptionValue;
            options.sweep_base = base;
        } else if (std.mem.eql(u8, args[ai], "--sweep-filter")) {
            options.sweep_filter = try optionValue(args, &ai);
        } else if (std.mem.eql(u8, args[ai], "--floors")) {
            options.enforce_floors = true;
        } else if (std.mem.eql(u8, args[ai], "--programs")) {
            const value = try optionValue(args, &ai);
            options.programs = std.fmt.parseInt(u32, value, 10) catch
                return error.InvalidOptionValue;
        } else if (std.mem.eql(u8, args[ai], "--seed")) {
            const value = try optionValue(args, &ai);
            options.seed = std.fmt.parseInt(u64, value, 10) catch
                return error.InvalidOptionValue;
        } else if (std.mem.eql(u8, args[ai], "--compiler")) {
            options.compiler_path = try optionValue(args, &ai);
        } else if (std.mem.eql(u8, args[ai], "--levels")) {
            options.levels = true;
        } else if (std.mem.eql(u8, args[ai], "--skip-matrix")) {
            options.skip_matrix = true;
        } else if (std.mem.eql(u8, args[ai], "--soundness")) {
            options.soundness = true;
        } else if (std.mem.eql(u8, args[ai], "--storage-programs")) {
            options.storage_programs = std.fmt.parseInt(u32, try optionValue(args, &ai), 10) catch
                return error.InvalidOptionValue;
        } else if (std.mem.eql(u8, args[ai], "--sanitize")) {
            const value = try optionValue(args, &ai);
            const none = std.mem.eql(u8, value, "none");
            options.sanitize = if (none) null else value;
            non_none_sanitizer_seen = non_none_sanitizer_seen or !none;
        } else {
            // A misspelled option such as `--runtime=path` would otherwise
            // drop the setting it names and change what the run checks.
            return error.UnknownOption;
        }
    }

    if (options.sweep_base != null and options.sweep_sample == null) return error.IncompatibleSweepSampleOption;
    if (options.sweep_sample != null and
        (options.sweep or
            options.sweep_filter != null or
            options.update or
            non_none_sanitizer_seen or
            non_one_walker_seen))
    {
        return error.IncompatibleSweepSampleOption;
    }
    if (options.sweep_filter != null and !options.sweep) return error.SweepFilterWithoutSweep;
    if (options.property_cases != null and !options.properties) return error.InvalidOptionValue;
    return options;
}

test "runner options refuse an argument they do not know" {
    for ([_][]const u8{ "--runtime=rt.a", "--updat", "extra" }) |unknown| {
        try testing.expectError(error.UnknownOption, parseRunnerOptions(&.{ "conformance", "tests", unknown }));
    }
}

test "sweep sample base rejects zero overflow and nonnumeric sizes" {
    for ([_][]const u8{ "0", "1073741824", "-1", "nope" }) |base| {
        try testing.expectError(error.InvalidOptionValue, parseRunnerOptions(&.{
            "conformance", "tests", "--sweep-sample", "0", "--sweep-base", base,
        }));
    }
}

test "sweep sample base applies only to diagnostic samples" {
    const options = try parseRunnerOptions(&.{ "conformance", "tests", "--sweep-sample", "0", "--sweep-base", "8192" });
    try testing.expectEqual(@as(?u32, 8192), options.sweep_base);
    try testing.expectError(error.IncompatibleSweepSampleOption, parseRunnerOptions(&.{
        "conformance", "tests", "--sweep", "--sweep-base", "8192",
    }));
    try testing.expectError(error.IncompatibleSweepSampleOption, parseRunnerOptions(&.{
        "conformance", "tests", "--sweep-base", "8192",
    }));
}

test "sweep sample mode requires one valid dimension ordinal" {
    try testing.expectError(
        error.InvalidOptionValue,
        parseRunnerOptions(&.{ "conformance", "tests", "--sweep-sample" }),
    );
    try testing.expectError(
        error.InvalidOptionValue,
        parseRunnerOptions(&.{ "conformance", "tests", "--sweep-sample", "nope" }),
    );
    try testing.expectError(
        error.InvalidSweepDimension,
        parseRunnerOptions(&.{ "conformance", "tests", "--sweep-sample", "999" }),
    );
    const options = try parseRunnerOptions(&.{ "conformance", "tests", "--sweep-sample", "0" });
    try testing.expectEqual(@as(?usize, 0), options.sweep_sample);
}

test "sweep sample mode rejects every incompatible runner mode" {
    const cases = [_][]const []const u8{
        &.{ "conformance", "tests", "--sweep-sample", "0", "--sweep" },
        &.{ "conformance", "tests", "--sweep-sample", "0", "--sweep-filter", "functions" },
        &.{ "conformance", "tests", "--sweep-sample", "0", "--update" },
        &.{ "conformance", "tests", "--sweep-sample", "0", "--sanitize", "address" },
        &.{ "conformance", "tests", "--sweep-sample", "0", "--walkers", "2" },
    };
    for (cases) |args| {
        try testing.expectError(error.IncompatibleSweepSampleOption, parseRunnerOptions(args));
    }
}

test "a narrowed corpus checks its cases without requiring whole-corpus coverage" {
    var directory = testing.tmpDir(.{});
    defer directory.cleanup();
    try directory.dir.createDirPath(testing.io, "cases");
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    const text = "fn main() -> UInt8 {\n    0\n}\n";
    const formatted = try fmt.checkProperties(gpa, text);
    try testing.expectEqualStrings(text, formatted.checked.formatted);
    try directory.dir.writeFile(testing.io, .{ .sub_path = "cases/value.lin", .data = text });
    try directory.dir.writeFile(testing.io, .{ .sub_path = "cases/value.fmt", .data = formatted.checked.formatted });
    const root = try std.fs.path.join(gpa, &.{ ".zig-cache", "tmp", &directory.sub_path });
    const cases = try std.fs.path.join(gpa, &.{ root, "cases" });
    const scratch = try std.fs.path.join(gpa, &.{ root, "scratch" });
    const absent_compiler = try std.fs.path.join(gpa, &.{ root, "absent-compiler" });
    try testing.expectEqual(@as(u8, 0), try runConformance(gpa, testing.allocator, testing.io, &.{
        "conformance", cases, "--walkers", "1", "--scratch", scratch, "--compiler", absent_compiler,
    }, .empty));
    try testing.expectEqual(@as(u8, 1), try runConformance(gpa, testing.allocator, testing.io, &.{
        "conformance", cases, "--walkers", "1", "--scratch", scratch, "--floors",
    }, .empty));
    try testing.expectEqual(@as(u8, 1), try runConformance(gpa, testing.allocator, testing.io, &.{
        "conformance", cases, "--walkers", "1", "--scratch", scratch, "--every-property",
    }, .empty));
    try directory.dir.deleteFile(testing.io, "cases/value.fmt");
    try testing.expectEqual(@as(u8, 1), try runConformance(gpa, testing.allocator, testing.io, &.{
        "conformance", cases, "--walkers", "1", "--scratch", scratch,
    }, .empty));
}

/// A checkout laid out under a temporary directory, with one formatted
/// program to place as an example or a corpus case.
const LayoutFixture = struct {
    directory: std.testing.TmpDir,
    arena: std.heap.ArenaAllocator,
    root: []const u8,
    text: []const u8,

    fn init() !LayoutFixture {
        var self: LayoutFixture = .{
            .directory = testing.tmpDir(.{}),
            .arena = std.heap.ArenaAllocator.init(testing.allocator),
            .root = undefined,
            .text = "fn main() -> UInt8 {\n    0\n}\n",
        };
        self.root = try std.fs.path.join(self.arena.allocator(), &.{ ".zig-cache", "tmp", &self.directory.sub_path });
        return self;
    }

    fn deinit(self: *LayoutFixture) void {
        self.arena.deinit();
        self.directory.cleanup();
    }

    fn write(self: *LayoutFixture, path: []const u8, text: []const u8) !void {
        if (std.fs.path.dirname(path)) |parent| try self.directory.dir.createDirPath(testing.io, parent);
        try self.directory.dir.writeFile(testing.io, .{ .sub_path = path, .data = text });
    }

    /// Runs the conformance runner over `under`, a path below the checkout.
    fn run(self: *LayoutFixture, under: []const u8, extra: []const []const u8) !u8 {
        const gpa = self.arena.allocator();
        var args: std.ArrayList([]const u8) = .empty;
        try args.appendSlice(gpa, &.{ "conformance", try std.fs.path.join(gpa, &.{ self.root, under }), "--walkers", "1", "--scratch", try std.fs.path.join(gpa, &.{ self.root, "scratch" }) });
        try args.appendSlice(gpa, extra);
        return runConformance(gpa, testing.allocator, testing.io, args.items, .empty);
    }
};

test "an example's goldens are read from tests/examples under its own name" {
    var fixture: LayoutFixture = try .init();
    defer fixture.deinit();
    try fixture.write("examples/value.lin", fixture.text);
    try fixture.write("examples/pair/main.lin", fixture.text);
    try fixture.write("tests/examples/value.fmt", fixture.text);
    try fixture.write("tests/examples/pair.fmt", fixture.text);
    try testing.expectEqual(@as(u8, 0), try fixture.run("examples", &.{}));
    // Narrowed to one example, file or directory, it still finds its goldens.
    try testing.expectEqual(@as(u8, 0), try fixture.run("examples/value.lin", &.{}));
    try testing.expectEqual(@as(u8, 0), try fixture.run("examples/pair", &.{}));
    // The golden is compared, not merely found.
    try fixture.write("tests/examples/value.fmt", "fn main() -> UInt8 { 1 }\n");
    try testing.expectEqual(@as(u8, 1), try fixture.run("examples", &.{}));
    try testing.expectEqual(@as(u8, 1), try fixture.run("examples/value.lin", &.{}));
    // Accepting writes the mirror, and nothing beside the example.
    try testing.expectEqual(@as(u8, 0), try fixture.run("examples/value.lin", &.{"--update"}));
    const accepted = try fixture.directory.dir.readFileAlloc(testing.io, "tests/examples/value.fmt", fixture.arena.allocator(), .unlimited);
    try testing.expectEqualStrings(fixture.text, accepted);
    try testing.expectError(error.FileNotFound, fixture.directory.dir.access(testing.io, "examples/value.fmt", .{}));
}

test "a case recording a storage report is not run against a runtime without the checking allocator" {
    var fixture: LayoutFixture = try .init();
    defer fixture.deinit();
    const recorded = "trap\nlinea: storage was freed twice\n";
    try fixture.write("tests/storage/freed_twice.lin", fixture.text);
    try fixture.write("tests/storage/freed_twice.exit", recorded);
    // An archive that does not name the checking allocator's marker.
    try fixture.write("liblinea_rt.a", "!<arch>\n_linea_alloc _linea_free\n");
    const runtime = try std.fs.path.join(fixture.arena.allocator(), &.{ fixture.root, "liblinea_rt.a" });
    // Neither a failure nor, with `--update`, a golden rewritten to what an
    // unchecked runtime does.
    try testing.expectEqual(@as(u8, 0), try fixture.run("tests/storage", &.{ "--runtime", runtime }));
    try testing.expectEqual(@as(u8, 0), try fixture.run("tests/storage", &.{ "--runtime", runtime, "--update" }));
    const kept = try fixture.directory.dir.readFileAlloc(testing.io, "tests/storage/freed_twice.exit", fixture.arena.allocator(), .unlimited);
    try testing.expectEqualStrings(recorded, kept);
}

test "a golden beside an example is refused" {
    var fixture: LayoutFixture = try .init();
    defer fixture.deinit();
    try fixture.write("examples/value.lin", fixture.text);
    try fixture.write("examples/value.fmt", fixture.text);
    try fixture.write("tests/examples/value.fmt", fixture.text);
    try testing.expectEqual(@as(u8, 1), try fixture.run("examples", &.{}));
    try testing.expectEqual(@as(u8, 1), try fixture.run("examples/value.lin", &.{}));
}

test "an example's golden with no example is an orphan, and no case of the corpus" {
    var fixture: LayoutFixture = try .init();
    defer fixture.deinit();
    try fixture.write("examples/value.lin", fixture.text);
    try fixture.write("tests/examples/value.fmt", fixture.text);
    try fixture.write("tests/cases/value.lin", fixture.text);
    try fixture.write("tests/cases/value.fmt", fixture.text);
    // The corpus walk leaves the examples' goldens to the examples walk.
    try testing.expectEqual(@as(u8, 0), try fixture.run("tests", &.{}));
    try fixture.write("tests/examples/gone.fmt", fixture.text);
    try testing.expectEqual(@as(u8, 1), try fixture.run("examples", &.{}));
    try testing.expectEqual(@as(u8, 0), try fixture.run("tests", &.{}));
    // An example with no golden in the mirror records nothing.
    try fixture.write("examples/silent.lin", fixture.text);
    try testing.expectEqual(@as(u8, 1), try fixture.run("examples/silent.lin", &.{}));
}

test "a walk that selects nothing, or cannot run its transcripts, fails" {
    var fixture: LayoutFixture = try .init();
    defer fixture.deinit();
    try fixture.write("tests/prose/README.md", "Nothing to run.\n");
    try testing.expectEqual(@as(u8, 1), try fixture.run("tests/prose", &.{}));

    try fixture.write("tests/cmd/echo/greets.cmd", "Greets.\n\n  $ echo hello\n  hello\n");
    try fixture.write("tests/cmd/echo/differs.cmd", "Differs.\n\n  $ echo hello\n  goodbye\n");
    try testing.expectEqual(@as(u8, 1), try fixture.run("tests/cmd/echo", &.{}));
    try testing.expectEqual(@as(u8, 1), try fixture.run("tests/cmd/echo/greets.cmd", &.{}));

    // Given something to run, a directory of transcripts and one transcript
    // are each run, and a transcript that disagrees fails. The stand-in for a
    // compiler answers `help` with the command every build offers.
    try fixture.directory.dir.writeFile(testing.io, .{
        .sub_path = "compiler",
        .flags = .{ .permissions = .executable_file },
        .data = "#!/bin/sh\nprintf '  check <path>        report diagnostics\\n'\n",
    });
    const compiler = try std.Io.Dir.cwd().realPathFileAlloc(testing.io, try std.fs.path.join(fixture.arena.allocator(), &.{ fixture.root, "compiler" }), fixture.arena.allocator());
    const runnable: []const []const u8 = &.{ "--compiler", compiler };
    try testing.expectEqual(@as(u8, 0), try fixture.run("tests/cmd/echo/greets.cmd", runnable));
    try testing.expectEqual(@as(u8, 1), try fixture.run("tests/cmd/echo/differs.cmd", runnable));
    try testing.expectEqual(@as(u8, 1), try fixture.run("tests/cmd/echo", runnable));

    // A compiler whose `help` this cannot read stops the walk rather than
    // passing its transcripts over.
    try testing.expectError(error.UnreadableCompilerHelp, fixture.run("tests/cmd/echo/greets.cmd", &.{ "--compiler", "/bin/sh" }));
}

pub fn main(init: std.process.Init) !u8 {
    return compiler_stack.run(runInit, .{init});
}

fn runInit(init: std.process.Init) !u8 {
    const gpa = init.arena.allocator();
    const args = try init.minimal.args.toSlice(gpa);
    return runConformance(gpa, init.gpa, init.io, args, init.minimal.environ);
}

/// Wall duration of checkCase calls, accumulated privately by each walker.
/// Overlapping walkers contribute separate durations, not run throughput.
const CaseTiming = struct {
    count: u64 = 0,
    total_ns: u128 = 0,
    maximum_ns: u64 = 0,
    at_most_200_ms: u64 = 0,
    at_most_500_ms: u64 = 0,
    reused: u64 = 0,

    fn record(self: *CaseTiming, duration_ns: u64, reused: bool) void {
        self.count += 1;
        self.total_ns += duration_ns;
        self.maximum_ns = @max(self.maximum_ns, duration_ns);
        self.at_most_200_ms += @intFromBool(duration_ns <= 200 * std.time.ns_per_ms);
        self.at_most_500_ms += @intFromBool(duration_ns <= 500 * std.time.ns_per_ms);
        self.reused += @intFromBool(reused);
    }

    fn merge(self: *CaseTiming, other: CaseTiming) void {
        self.count += other.count;
        self.total_ns += other.total_ns;
        self.maximum_ns = @max(self.maximum_ns, other.maximum_ns);
        self.at_most_200_ms += other.at_most_200_ms;
        self.at_most_500_ms += other.at_most_500_ms;
        self.reused += other.reused;
    }

    fn meanNs(self: CaseTiming) u128 {
        return if (self.count == 0) 0 else self.total_ns / self.count;
    }

    fn report(self: CaseTiming, root: []const u8, focused: bool) void {
        std.debug.print("conformance: {s} wall [{s}]: count={d} mean={d:.3}ms max={d:.3}ms <=200ms={d} <=500ms={d} reused={d} fallback={d}\n", .{
            if (focused) "focused properties" else "ordinary cases",
            root,
            self.count,
            @as(f64, @floatFromInt(self.meanNs())) / std.time.ns_per_ms,
            @as(f64, @floatFromInt(self.maximum_ns)) / std.time.ns_per_ms,
            self.at_most_200_ms,
            self.at_most_500_ms,
            self.reused,
            self.count - self.reused,
        });
    }
};

test "case timing merges worker measurements and inclusive duration buckets" {
    var first: CaseTiming = .{};
    first.record(200 * std.time.ns_per_ms, true);
    first.record(201 * std.time.ns_per_ms, false);
    var second: CaseTiming = .{};
    second.record(500 * std.time.ns_per_ms, true);
    second.record(501 * std.time.ns_per_ms, false);
    first.merge(second);
    first.merge(.{});
    try testing.expectEqual(@as(u64, 4), first.count);
    try testing.expectEqual(@as(u128, 1402 * std.time.ns_per_ms), first.total_ns);
    try testing.expectEqual(@as(u64, 501 * std.time.ns_per_ms), first.maximum_ns);
    try testing.expectEqual(@as(u64, 1), first.at_most_200_ms);
    try testing.expectEqual(@as(u64, 3), first.at_most_500_ms);
    try testing.expectEqual(@as(u64, 2), first.reused);
    try testing.expectEqual(@as(u128, 350_500_000), first.meanNs());
    try testing.expectEqual(@as(u128, 0), (CaseTiming{}).meanNs());
}

const CaseProgress = struct {
    completed: std.atomic.Value(u32) = .init(0),
    reported_at: std.atomic.Value(u64) = .init(0),
    const interval_ns = 15 * std.time.ns_per_s;

    fn complete(self: *CaseProgress, elapsed_ns: u64) ?u32 {
        const done = self.completed.fetchAdd(1, .monotonic) + 1;
        var reported = self.reported_at.load(.monotonic);
        while (elapsed_ns >= reported and elapsed_ns - reported >= interval_ns) {
            if (self.reported_at.cmpxchgWeak(reported, elapsed_ns, .monotonic, .monotonic)) |claimed| {
                reported = claimed;
            } else return done;
        }
        return null;
    }
};

test "case progress reports elapsed intervals after many quick cases" {
    var progress: CaseProgress = .{};
    for (1..15_000) |millis| {
        try testing.expectEqual(@as(?u32, null), progress.complete(millis * std.time.ns_per_ms));
    }
    try testing.expectEqual(@as(?u32, 15_000), progress.complete(15 * std.time.ns_per_s));
    try testing.expectEqual(@as(u32, 15_000), progress.completed.load(.monotonic));
}

test "case progress shares one report claim between walkers" {
    const Worker = struct {
        fn complete(progress: *CaseProgress, reports: *std.atomic.Value(u32)) void {
            if (progress.complete(15 * std.time.ns_per_s) != null) {
                _ = reports.fetchAdd(1, .monotonic);
            }
        }
    };
    var progress: CaseProgress = .{};
    var reports: std.atomic.Value(u32) = .init(0);
    var threads: [4]std.Thread = undefined;
    {
        var started: usize = 0;
        defer for (threads[0..started]) |thread| thread.join();
        for (&threads) |*thread| {
            thread.* = try std.Thread.spawn(.{}, Worker.complete, .{ &progress, &reports });
            started += 1;
        }
    }
    try testing.expectEqual(@as(u32, 1), reports.load(.monotonic));
    try testing.expectEqual(@as(u32, 4), progress.completed.load(.monotonic));
}

test "case progress claims each interval once and skips missed intervals" {
    var progress: CaseProgress = .{};
    try testing.expectEqual(@as(?u32, 1), progress.complete(15 * std.time.ns_per_s));
    try testing.expectEqual(@as(?u32, null), progress.complete(15 * std.time.ns_per_s));
    try testing.expectEqual(@as(?u32, 3), progress.complete(76 * std.time.ns_per_s));
    try testing.expectEqual(@as(?u32, null), progress.complete(76 * std.time.ns_per_s));
    try testing.expectEqual(@as(?u32, null), progress.complete(75 * std.time.ns_per_s));
    try testing.expectEqual(@as(?u32, null), progress.complete(90 * std.time.ns_per_s));
    try testing.expectEqual(@as(?u32, 7), progress.complete(91 * std.time.ns_per_s));
    try testing.expectEqual(@as(u32, 7), progress.completed.load(.monotonic));
}

fn runConformance(gpa: std.mem.Allocator, scratch_backing: std.mem.Allocator, io: std.Io, args: []const []const u8, environ: std.process.Environ) !u8 {
    tracy.setThreadName("conformance");
    const run_zone = tracy.beginZone(@src(), "conformance");
    defer run_zone.end();

    if (args.len < 2) {
        std.debug.print("usage: conformance <tests-dir> [--runtime <path>] [--scratch <dir>] [--compiler <path>] [--update]\n", .{});
        return 64;
    }

    // A root that is one case is walked from the directory its goldens sit
    // in, selecting that case alone.
    const narrowed = try narrowedCase(gpa, io, args[1]);
    const tests_dir_path = if (narrowed) |one| one.parent else args[1];
    const options = parseRunnerOptions(args) catch |err| {
        switch (err) {
            error.InvalidSweepDimension => std.debug.print("--sweep-sample names no sweep dimension\n", .{}),
            error.IncompatibleSweepSampleOption => std.debug.print("sweep sampling options require a plain one-walker --sweep-sample run\n", .{}),
            error.SweepFilterWithoutSweep => std.debug.print("--sweep-filter requires --sweep\n", .{}),
            error.InvalidOptionValue => std.debug.print("a conformance option has a missing or invalid value\n", .{}),
            error.UnknownOption => std.debug.print("a conformance option is not one the runner knows\n", .{}),
        }
        return 64;
    };
    const update = options.update;
    const every_property = options.every_property;
    const focused_floors = options.properties and (options.enforce_floors or options.every_property);
    const walkers_wanted = options.walkers_wanted;
    const runtime_path = options.runtime_path;
    const scratch_dir = options.scratch_dir;
    const sanitize = options.sanitize;
    const compiler_path = options.compiler_path;
    const enforce_floors = options.enforce_floors;
    const programs = options.programs;
    const seed = options.seed;
    const sweep = options.sweep;
    const sweep_sample = options.sweep_sample;
    const sweep_filter = options.sweep_filter;

    if (sweep_sample) |ordinal| {
        var dimension = sweep_dimensions[ordinal];
        dimension.n = options.sweep_base orelse dimension.n;
        const sample = try balancedSample(scratch_backing, io, dimension);
        var buffer: [256]u8 = undefined;
        var stdout = std.Io.File.stdout().writer(io, &buffer);
        try writeSweepSample(&stdout.interface, sample);
        try stdout.interface.flush();
        return 0;
    }

    if (sweep_filter) |filter| {
        if (selectedSweepCount(filter) == 0) {
            std.debug.print("no sweep dimension matches '{s}'\n", .{filter});
            return 64;
        }
    }

    if (options.soundness) return runSoundness(gpa, scratch_backing, io, options, environ);

    // Before anything the corpus needs: the sweep compiles modules of its own
    // and answers about the compiler rather than about a case, so it neither
    // reads the corpus nor wants the outcome cache.
    if (sweep) {
        var swept: std.ArrayList(Failure) = .empty;
        defer swept.deinit(gpa);
        var source: ProcessSweepSamples = .{
            .executable = args[0],
            .tests_dir = tests_dir_path,
        };
        try sweepShapesWith(gpa, io, &swept, sweep_filter, &source);
        if (swept.items.len == 0) {
            std.debug.print("sweep: every dimension grew with its input\n", .{});
            return 0;
        }
        for (swept.items) |f| {
            std.debug.print("\nFAIL {s} ({s})\n", .{ f.path, f.what });
            std.debug.print("--- expected ---\n{s}\n--- actual ---\n{s}\n", .{ f.expected, f.actual });
        }
        std.debug.print(
            "\nsweep: {d} dimension(s) grew faster than their input\n",
            .{swept.items.len},
        );
        return 1;
    }

    const discovery_zone = tracy.beginZone(@src(), "discovery");

    std.Io.Dir.cwd().createDirPath(io, scratch_dir) catch {};

    // The survival property lays each case out under here as a program of its
    // own, numbered by where the case sits in the walk. A case renamed or
    // removed shifts every number after it, so what a previous run left behind
    // would become a file of whatever case now holds that number -- and the
    // server would be handed a module the corpus does not contain.
    std.Io.Dir.cwd().deleteTree(io, try std.fs.path.join(gpa, &.{
        scratch_dir,
        "lsp",
    })) catch {};

    var outcome_stats: OutcomeStats = .{};
    var cache = try OutcomeCache.init(
        gpa,
        io,
        environ.getPosix("PATH"),
        scratch_dir,
        runtime_path,
        sanitize,
    );
    cache.stats = &outcome_stats;

    var failures: std.ArrayList(Failure) = .empty;
    var checked: u32 = 0;

    // A run that stalls and a run that is merely slow look identical in a log
    // that says nothing until the end, and telling them apart afterwards costs
    // far more than saying so as it goes. Progress is reported against the
    // clock rather than every case, so a fast run stays quiet and a slow one
    // says where it slowed.
    const began = std.Io.Timestamp.now(io, .awake);

    // How many programs each metamorphic property actually ran on. A property
    // that stops applying to the whole corpus is otherwise indistinguishable
    // from one that applies and agrees, and both are green.
    // Counted apart from the generated programs. The floors below say what the
    // corpus must reach, and a count including generated programs would be
    // measuring `-Dprograms`: at 200 the corpus could contribute nothing and
    // still clear every floor, and at 0 a sound corpus reports itself broken.
    var rewrites: std.EnumMap(Transform, u32) = .{};
    var mutations: std.EnumMap(Mutation, u32) = .{};
    var fix_kinds: FixKinds = .{};
    var damages: std.EnumMap(Damage, u32) = .{};
    var layouts_compared: u32 = 0;
    var levels_agreed: u32 = 0;
    var materialized_derives: u32 = 0;
    var made_rewrites: std.EnumMap(Transform, u32) = .{};
    var made_mutations: std.EnumMap(Mutation, u32) = .{};
    var made_damages: std.EnumMap(Damage, u32) = .{};
    var generated: u32 = 0;
    // The same question for the properties that are not rewrites: how many
    // files each was actually asked about. A property is counted only where it
    // compared something, so one that returns early everywhere reads as zero
    // rather than as agreement. Every count of these lives here, so a number
    // the run prints is this map read rather than a counter beside it that
    // nothing bounds.
    //
    // Split from the generated programs for the reason the rewrites are: the
    // floors say what the corpus must reach, and a count both halves fed would
    // rise and fall with `-Dprograms` while the corpus's own coverage went
    // anywhere at all.
    var properties: std.EnumMap(Property, u32) = .{};
    var made_properties: std.EnumMap(Property, u32) = .{};
    // The other side of each corpus tally: what the property was offered and
    // did not apply to. Together with the tally above it accounts for the
    // corpus exactly, which is what makes a leak from the generated programs
    // visible at the first one rather than once there are enough of them to
    // cover what the property declines.
    var passed_over: std.EnumMap(Property, u32) = .{};

    // Which rules the corpus actually reached. A rule the compiler can emit
    // and no case provokes is a rule whose prose and whose code have never
    // been compared -- the gate in `diagnostics/diagnostic.zig` proves each is
    // written down, which a rule that has never fired satisfies too.
    var rules_reached: std.EnumMap(diagnostic.Code, void) = .{};
    var terminator_witnesses: TerminatorWitnesses = .initFill(false);

    // The examples' goldens hold no case of their own: they are compared when
    // the examples they belong to are walked.
    if (corpus_layout.inExamplesGoldens(tests_dir_path)) {
        std.debug.print("conformance: '{s}' holds the examples' goldens; name the example to check it\n", .{args[1]});
        return 64;
    }
    const walked_paths = collectPaths(gpa, io, tests_dir_path) catch |err| {
        std.debug.print("conformance: cannot read '{s}': {s}\n", .{ tests_dir_path, @errorName(err) });
        return 74;
    };
    const all_paths = if (corpus_layout.examplesGoldensWithin(tests_dir_path)) |mirror|
        try pathsOutside(gpa, walked_paths, mirror)
    else
        walked_paths;
    const selected: ?[]const []const u8 = if (options.property_cases) |manifest|
        try propertyEntries(gpa, all_paths, try readFileAlloc(io, gpa, manifest))
    else if (narrowed) |one|
        try propertyEntries(gpa, all_paths, one.name)
    else
        null;
    const paths = if (selected) |entries| try selectPaths(gpa, all_paths, entries) else all_paths;

    // Where the goldens of the cases walked here sit. A corpus case's sit
    // beside it, so they are among `paths`; an example's sit in the mirror,
    // named as the example is, and are walked from there.
    const golden_root = try corpus_layout.goldenPath(gpa, tests_dir_path);
    const goldens_apart = !std.mem.eql(u8, golden_root, std.mem.trimEnd(u8, tests_dir_path, "/"));
    const goldens = if (!goldens_apart) paths else mirrored: {
        const all_goldens = collectPaths(gpa, io, golden_root) catch |err| switch (err) {
            error.FileNotFound => &.{},
            else => {
                std.debug.print("conformance: cannot read '{s}': {s}\n", .{ golden_root, @errorName(err) });
                return 74;
            },
        };
        break :mirrored if (selected) |entries| try selectPaths(gpa, all_goldens, entries) else all_goldens;
    };

    const cases = try collectCases(gpa, io, tests_dir_path, paths);
    var corpus: Corpus = .of(cases, paths);

    // A walk that selects nothing checks nothing, which reads exactly like a
    // walk whose checks all passed.
    if (corpus.cases + corpus.commands + corpus.sessions == 0) {
        try failures.append(gpa, .{
            .path = try displayPath(gpa, tests_dir_path, ""),
            .what = "selects nothing to check",
            .expected = "a case, a transcript or a session",
            .actual = "none beneath this root",
        });
    }
    // A transcript runs the compiler binary, so without one it would be
    // passed over and the walk reported as though it had run.
    if (corpus.commands != 0 and compiler_path == null) {
        try failures.append(gpa, .{
            .path = try displayPath(gpa, tests_dir_path, ""),
            .what = "holds transcripts and was given no compiler to run them with",
            .expected = "--compiler <path>",
            .actual = try std.fmt.allocPrint(gpa, "{d} transcript(s) not run", .{corpus.commands}),
        });
    }

    for (try orphanGoldens(gpa, goldens, paths)) |orphan| {
        try failures.append(gpa, .{
            .path = try displayPath(gpa, golden_root, orphan),
            .what = "records what no case produces",
            .expected = "a case with its stem",
            .actual = "nothing with this stem",
        });
    }
    // Beside an example nothing reads a golden, since the example's own sit
    // in the mirror; one left there would pass while recording nothing.
    if (goldens_apart) {
        for (try orphanGoldens(gpa, paths, &.{})) |stray| {
            try failures.append(gpa, .{
                .path = try displayPath(gpa, tests_dir_path, stray),
                .what = "is a golden beside an example",
                .expected = try std.fmt.allocPrint(gpa, "its goldens under {s}/", .{corpus_layout.examples_goldens}),
                .actual = "a golden nothing reads",
            });
        }
    }

    {
        // A case's stem is rooted where its goldens sit and `goldens` are
        // relative to that root, so the two are put in the same terms before
        // either is asked about the other.
        var stems: std.ArrayList([]const u8) = .empty;
        defer stems.deinit(gpa);
        for (cases) |case| {
            var rel = case.stem;
            if (std.mem.startsWith(u8, rel, golden_root)) rel = rel[golden_root.len..];
            while (rel.len > 0 and rel[0] == std.fs.path.sep) rel = rel[1..];
            try stems.append(gpa, rel);
        }
        for (try unpinnedStems(gpa, stems.items, goldens)) |stem| {
            try failures.append(gpa, .{
                .path = try displayPath(gpa, tests_dir_path, stem),
                .what = "records nothing, so nothing it does is compared",
                .expected = try std.fmt.allocPrint(gpa, "a golden named {s}.<kind>", .{try displayPath(gpa, golden_root, stem)}),
                .actual = "no golden with this stem",
            });
        }

        // A driver is only linked where the case records what running it did,
        // so one beside a case that records no status is a file nothing reads:
        // the case still passes, and what the driver claims about the library
        // is never asked. The same reason a case with no golden at all is
        // refused, extended to the one other file a case can carry.
        for (cases, stems.items) |case, stem| {
            if (case.driver == null) continue;
            const exit_golden = try std.mem.concat(gpa, u8, &.{ case.stem, ".exit" });
            defer gpa.free(exit_golden);
            if (readIfExists(io, gpa, exit_golden) catch null) |text| {
                gpa.free(text);
                continue;
            }
            try failures.append(gpa, .{
                .path = try displayPath(gpa, tests_dir_path, stem),
                .what = "carries a driver nothing runs",
                .expected = "an `.exit` golden with its stem, which is what makes the driver run",
                .actual = "a `driver.c` and no status recorded",
            });
        }
    }

    const checked_library = initialized: {
        const started = std.Io.Timestamp.now(io, .awake);
        const prefix = try loader.CheckedLibrary.init(scratch_backing);
        const elapsed = started.durationTo(std.Io.Timestamp.now(io, .awake));
        std.debug.print("conformance: checked library init wall: {d:.3}ms\n", .{
            @as(f64, @floatFromInt(elapsed.nanoseconds)) / std.time.ns_per_ms,
        });
        break :initialized prefix;
    };
    defer checked_library.deinit();
    const checks_storage = if (runtime_path) |rt| checks: {
        const bytes = readIfExists(io, gpa, rt) catch null orelse break :checks false;
        defer gpa.free(bytes);
        break :checks runtime_symbols.holdsStorageChecks(bytes);
    } else false;
    if (runtime_path) |rt| if (!checks_storage) std.debug.print(
        "conformance: the runtime {s} holds no checking allocator, so storage is not checked; {s} holds one\n",
        .{ rt, runtime_symbols.checked_archive_name },
    );
    var unchecked_skips: std.atomic.Value(u32) = .init(0);
    const settings: Settings = .{
        .library = checked_library,
        .properties = options.properties,
        .corpus_properties = sanitize == null,
        .levels = options.levels,
        .cache = &cache,
        .update = update,
        .sanitize = sanitize,
        .runtime_path = runtime_path,
        .scratch_dir = scratch_dir,
        .checks_storage = checks_storage,
        .unchecked_skips = &unchecked_skips,
    };
    discovery_zone.end();

    // One walker per core by default, claiming cases from a shared queue.
    // Each walker allocates from an arena of its own. The process arena every
    // other part of this program uses is not safe to share, and giving each
    // walker its own is not merely a way around that -- it bounds what a walker
    // holds to the cases it walked, where one shared arena grows for the whole
    // corpus and is freed at exit.
    const walkers = walkers_wanted orelse @max(1, std.Thread.getCpuCount() catch 1);
    var work = try gpa.alloc(Work, walkers);
    for (work) |*w| w.* = .{};
    const case_timings = try gpa.alloc(CaseTiming, walkers);
    defer gpa.free(case_timings);
    @memset(case_timings, .{});

    // One per walker, held here so that what a walker recorded is still there
    // to be merged. Released together once the totals have been taken.
    const arenas = try gpa.alloc(std.heap.ArenaAllocator, walkers);
    for (arenas) |*it| it.* = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer for (arenas) |*it| it.deinit();

    // The commands' arenas, beside the walkers' and for the same reason: a
    // `Failure` is allocated from one and read when the run is reported, which
    // is after every block below has closed. An arena that did not live this
    // long would be freed before the report that reads it, and a failed command
    // could not say what went wrong -- the one moment it exists for.
    //
    // Sized by the walker count because the command workers are capped at it.
    const cmd_arenas = try gpa.alloc(std.heap.ArenaAllocator, walkers);
    for (cmd_arenas) |*it| it.* = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer for (cmd_arenas) |*it| it.deinit();

    var counted: CaseProgress = .{};
    var next_case: std.atomic.Value(usize) = .init(0);

    const Walk = struct {
        fn run(
            io_: std.Io,
            settings_: Settings,
            cases_: []const Case,
            w: *Work,
            timing: *CaseTiming,
            arena: *std.heap.ArenaAllocator,
            next: *std.atomic.Value(usize),
            counter: *CaseProgress,
            began_: std.Io.Timestamp,
        ) void {
            tracy.setThreadName("walker");

            // The caller's arena outlives this walker on purpose: what a case
            // recorded is read after the walk, so a `Failure` and the list
            // holding it are copied into here and stay.
            const keep = arena.allocator();

            // Everything else a case allocates -- its tokens, its tree, its
            // types, its MIR, every rewrite it was run under -- belongs to the
            // case and is released when the case ends.
            //
            // All of it used to go into the arena above, so the runner held
            // every case it had walked: 11.5MB each, which over a corpus of 724
            // is 10.4GB, and two runs at once is more memory than the machine
            // that runs them has. Nothing needed it -- a case is answered
            // before the next one starts, and only its record is read later.
            var per_case = std.heap.ArenaAllocator.init(std.heap.page_allocator);
            defer per_case.deinit();
            const a = per_case.allocator();

            // Each walker takes the next case nobody has claimed, rather than
            // every nth. Striping divides the *count* evenly and the cost
            // unevenly: a trace puts the slowest case at 3.9 seconds against a
            // mean of 0.29, so a walker dealt two of those finishes long after
            // the rest and everyone waits on it. Claiming one at a time needs
            // no guess about what a case will cost -- a walker that finishes a
            // cheap one immediately takes another, and the only idleness left
            // is the tail of whichever case is still running at the end.
            while (true) {
                const at = next.fetchAdd(1, .monotonic);
                if (at >= cases_.len) break;
                // A case that cannot be checked at all is a failure of the
                // runner rather than of the case, and there is nowhere to
                // return it to from here.
                const zone = tracy.beginZone(@src(), "case");
                defer zone.end();
                zone.setText(cases_[at].display_path);
                zone.setValue(at);
                const started = std.Io.Timestamp.now(io_, .awake);
                const reused = checkCase(a, per_case.child_allocator, io_, settings_, w, cases_[at], at) catch |err| {
                    std.debug.print("conformance: {s}: {s}\n", .{ cases_[at].display_path, @errorName(err) });
                    std.process.exit(1);
                };

                timing.record(@intCast(started.durationTo(std.Io.Timestamp.now(io_, .awake)).nanoseconds), reused);

                // Taken out before the arena goes, and the arena goes before
                // the next case is claimed.
                w.retain(keep, at) catch |err| {
                    std.debug.print("conformance: {s}: {s}\n", .{ cases_[at].display_path, @errorName(err) });
                    std.process.exit(1);
                };
                // Held down to one case's worth rather than retained: keeping
                // the capacity keeps the high-water mark, which is the whole
                // of what this is for.
                _ = per_case.reset(.{ .retain_with_limit = 4 << 20 });

                // Reported by whichever walker crosses the interval. The count
                // is exact; which case it names is whatever that walker had in
                // hand, which is what a progress line is for.
                const now = std.Io.Timestamp.now(io_, .awake);
                const elapsed_ns: u64 = @intCast(began_.durationTo(now).nanoseconds);
                if (counter.complete(elapsed_ns)) |done| {
                    std.debug.print("conformance: {s}: {d} case(s) after {d}s, at {s}\n", .{
                        if (settings_.properties) "focused properties" else "ordinary cases",
                        done,
                        elapsed_ns / std.time.ns_per_s,
                        cases_[at].display_path,
                    });
                }
            }
        }
    };

    {
        const walk_zone = tracy.beginZone(@src(), "corpus.walk");
        defer walk_zone.end();
        walk_zone.setValue(cases.len);

        if (walkers == 1) {
            Walk.run(io, settings, cases, &work[0], &case_timings[0], &arenas[0], &next_case, &counted, began);
        } else {
            const threads = try gpa.alloc(std.Thread, walkers);
            for (threads, 0..) |*t, me| {
                t.* = try std.Thread.spawn(compiler_stack.spawn_config, Walk.run, .{
                    io, settings, cases, &work[me], &case_timings[me], &arenas[me], &next_case, &counted, began,
                });
            }
            for (threads) |t| t.join();
        }
        checked = counted.completed.load(.monotonic);
        var timing: CaseTiming = .{};
        for (case_timings) |one| timing.merge(one);
        timing.report(tests_dir_path, options.properties);
    }
    outcome_stats.report(tests_dir_path, "corpus joined");

    const merge_zone = tracy.beginZone(@src(), "corpus.merge");

    // One walk today and several later, so the totals are *added* rather than
    // read where they were written. Addition is the whole reason the corpus can
    // be walked by more than one thread: no field here is consulted while the
    // walk runs, so two walks each keeping their own and summing afterwards
    // reach the number one walk would have.

    // What the dot half of the completion property reached, at the grain it
    // reached it: the tally beside that property counts functions, and a
    // function holding one dot and one holding forty are one apiece there.
    var dots_asked: u32 = 0;

    // The parts of what the settled reference property passed over, kept apart
    // because they are unlike: one is coverage declined and another is coverage
    // missing, and the checks are counted beside them by which check.
    var declined_settled_refs: PassedSettledRefs = .{};

    // How many lending walks were also held to the consuming form, which only
    // a walk over an array has: the property counts cases, and one number for
    // both halves would read as though every walk had been held to both.
    var walks_also: u32 = 0;
    var layout_jobs: std.ArrayList(LayoutJob) = .empty;
    defer layout_jobs.deinit(gpa);

    for (work) |*one| {
        try failures.appendSlice(gpa, one.kept.items);
        try layout_jobs.appendSlice(gpa, one.kept_layout_jobs.items);
        corpus.functions += one.functions;
        corpus.settled_refs += one.settled_refs;
        dots_asked += one.dots;
        walks_also += one.walks_also;
        declined_settled_refs.through_a_bound += one.declined_settled_refs.through_a_bound;
        declined_settled_refs.through_a_module += one.declined_settled_refs.through_a_module;
        declined_settled_refs.in_a_signature += one.declined_settled_refs.in_a_signature;
        declined_settled_refs.no_bound_the_source_names += one.declined_settled_refs.no_bound_the_source_names;
        declined_settled_refs.unrecorded += one.declined_settled_refs.unrecorded;
        for (std.enums.values(Property)) |k| {
            if (one.properties.get(k)) |n| properties.put(k, (properties.get(k) orelse 0) + n);
            if (one.passed_over.get(k)) |n| passed_over.put(k, (passed_over.get(k) orelse 0) + n);
        }
        for (std.enums.values(Transform)) |k| {
            if (one.rewrites.get(k)) |n| rewrites.put(k, (rewrites.get(k) orelse 0) + n);
        }
        for (std.enums.values(Damage)) |k| {
            if (one.damages.get(k)) |n| damages.put(k, (damages.get(k) orelse 0) + n);
        }
        layouts_compared += one.layouts_compared;
        levels_agreed += one.levels_agreed;
        materialized_derives += one.materialized_derives;
        for (std.enums.values(Mutation)) |k| {
            if (one.mutations.get(k)) |n| mutations.put(k, (mutations.get(k) orelse 0) + n);
        }
        for (std.enums.values(diagnostic.FixKind)) |k| {
            if (one.fix_kinds.get(k)) |n| fix_kinds.put(k, (fix_kinds.get(k) orelse 0) + n);
        }
        for (std.enums.values(diagnostic.Code)) |c| {
            if (one.rules_reached.contains(c)) rules_reached.put(c, {});
        }
        for (std.enums.values(Inst.Tag)) |tag| {
            if (one.terminator_witnesses.get(tag)) terminator_witnesses.set(tag, true);
        }
    }

    std.mem.sort(LayoutJob, layout_jobs.items, {}, struct {
        fn less(_: void, a: LayoutJob, b: LayoutJob) bool {
            return std.mem.order(u8, a.display_path, b.display_path) == .lt;
        }
    }.less);
    try checkLayoutJobs(gpa, io, settings, layout_jobs.items, &failures);

    // Sorted, because the walkers finish in whatever order the scheduler gave
    // them and a run's output should not depend on that. By the case's path,
    // which is the order a single walker would have reported them in.
    std.mem.sort(Failure, failures.items, {}, failureLess);

    try checkLibrary(gpa, io, &failures);
    // Asked of the corpus only, like the coverage floors: the examples are
    // programs that work, so every rule is unreached there and should be.
    if (enforce_floors) try checkEveryRuleIsReached(gpa, &failures, &rules_reached);
    merge_zone.end();

    // The corpus supplies programs someone chose to write, which is a supply
    // that grows at the pace people write them. A generator supplies programs
    // nobody has read, in shapes nobody thought to combine, and the rewrites
    // hold them to the same property -- which is what makes them worth
    // compiling without a recorded answer to compare against.
    const generated_zone = tracy.beginZone(@src(), "generated-programs");
    generated_zone.setValue(programs);

    if (programs > 0) {
        if (runtime_path) |rt| {
            const generated_settings: GeneratedSettings = .{
                .library = checked_library,
                .cache = &cache,
                .env = .{
                    .scratch = scratch_dir,
                    .runtime = rt,
                    .sanitize = sanitize,
                },
            };
            const results = try runGeneratedPrograms(
                gpa,
                io,
                generated_settings,
                seed,
                programs,
                walkers,
                arenas,
            );
            defer gpa.free(results);
            try mergeGeneratedResults(
                gpa,
                results,
                &failures,
                &generated,
                &made_properties,
                &made_rewrites,
                &made_mutations,
                &made_damages,
                null,
            );
        }
    }
    generated_zone.end();
    outcome_stats.report(tests_dir_path, "native outcomes complete");

    const coverage_zone = tracy.beginZone(@src(), "coverage-accounting");

    // Each named witness must emit its terminator during the ordinary walk.
    if (enforce_floors) {
        for (std.enums.values(Inst.Tag)) |tag| {
            if (!tag.isTerminator() or terminator_witnesses.get(tag)) continue;
            try failures.append(gpa, .{
                .path = edges.witnessOf(tag),
                .what = "named as the witness for an edge it does not produce",
                .expected = @tagName(tag),
                .actual = "not emitted by this case",
            });
        }
    }

    if (generated > 0) {
        std.debug.print("conformance: {d} generated program(s), seeds {d}..{d}\n", .{
            generated,
            seed,
            seed + programs - 1,
        });
    }
    // The two counts apart rather than their sum. The floor is on the corpus
    // alone, so a total that folded in the generated programs was a number
    // nobody could compare against the floor beside it -- and one that grew
    // with `-Dprograms` while the corpus's own coverage fell.
    for (std.enums.values(Transform)) |t| {
        const n = rewrites.get(t) orelse 0;
        std.debug.print("conformance: {d} program(s) checked with {s}, and {d} generated\n", .{
            n,
            t.why(),
            made_rewrites.get(t) orelse 0,
        });
        if (focused_floors and (rewrites.get(t) orelse 0) < 1) {
            try failures.append(gpa, .{
                .path = "the corpus",
                .what = try std.fmt.allocPrint(gpa, "reaches too few programs with {s}", .{t.why()}),
                .expected = try std.fmt.allocPrint(gpa, "at least {d}", .{@as(u32, 1)}),
                .actual = try std.fmt.allocPrint(gpa, "{d} from the corpus", .{rewrites.get(t) orelse 0}),
            });
        }
    }
    std.debug.print(
        "conformance: {d} program(s) checked with derives replaced by ordinary source\n",
        .{materialized_derives},
    );
    if (focused_floors and materialized_derives < 1) {
        try failures.append(gpa, .{
            .path = "the corpus",
            .what = "reaches too few programs with derives replaced by ordinary source",
            .expected = "at least 1",
            .actual = try std.fmt.allocPrint(gpa, "{d} from the corpus", .{materialized_derives}),
        });
    }

    // The layout table is the one input to code generation with no second
    // opinion, so a run that compared none of it proved nothing about the
    // thing every other check is relative to -- and reads exactly like a run
    // that proved everything.
    std.debug.print(
        "conformance: {d} aggregate type(s) measured a second time, by `cc`\n",
        .{layouts_compared},
    );
    if (enforce_floors and layouts_compared < layout_floor) {
        try failures.append(gpa, .{
            .path = "the corpus",
            .what = "measures too few types against a second reading of the layout rule",
            .expected = try std.fmt.allocPrint(gpa, "at least {d}", .{layout_floor}),
            .actual = try std.fmt.allocPrint(gpa, "{d} from the corpus", .{layouts_compared}),
        });
    }

    // A run asked to build every level that compared no case proved nothing,
    // and reads exactly like one that compared them all.
    if (options.levels) {
        std.debug.print("conformance: {d} case(s) answered alike at all {d} optimisation levels\n", .{
            levels_agreed,
            toolchain.levels.len,
        });
        if (levels_agreed == 0 and checked != 0) try failures.append(gpa, .{
            .path = "the corpus",
            .what = "was asked to compare every optimisation level and compared no case",
            .expected = "at least one case that runs",
            .actual = "none",
        });
    }

    for (std.enums.values(Mutation)) |m| {
        const n = mutations.get(m) orelse 0;
        std.debug.print("conformance: {d} program(s) checked that {s}, and {d} generated\n", .{
            n,
            m.why(),
            made_mutations.get(m) orelse 0,
        });
        if (focused_floors and (mutations.get(m) orelse 0) < 1) {
            try failures.append(gpa, .{
                .path = "the corpus",
                .what = try std.fmt.allocPrint(gpa, "reaches too few programs checking that {s}", .{m.why()}),
                .expected = try std.fmt.allocPrint(gpa, "at least {d}", .{@as(u32, 1)}),
                .actual = try std.fmt.allocPrint(gpa, "{d} from the corpus", .{mutations.get(m) orelse 0}),
            });
        }
        // The generated half, as a share of how many there are. A count would
        // be a reading of `-Dprograms`; a share is a reading of how much of
        // what the generator writes a mutation can be aimed at, which is the
        // number that fell silently when a disposal moved behind a `defer`.
        const made = made_mutations.get(m) orelse 0;
        if (enforce_floors and programs > 0 and made * 100 < m.generatedFloor() * programs) {
            try failures.append(gpa, .{
                .path = "the generated programs",
                .what = try std.fmt.allocPrint(gpa, "reaches too few checking that {s}", .{m.why()}),
                .expected = try std.fmt.allocPrint(gpa, "at least {d}% of {d}", .{ m.generatedFloor(), programs }),
                .actual = try std.fmt.allocPrint(gpa, "{d}", .{made}),
            });
        }
    }
    // A help's fix counted by kind as well as by case: one kind of fix the
    // corpus carries plenty of would clear a floor over all of them while
    // another kind had stopped being written at all.
    for (std.enums.values(diagnostic.FixKind)) |k| {
        const n = fix_kinds.get(k) orelse 0;
        std.debug.print("conformance: {d} case(s) carried a fix of kind {s}\n", .{ n, k.text() });
        if (every_property and !options.properties and n < 1) {
            try failures.append(gpa, .{
                .path = "the corpus",
                .what = try std.fmt.allocPrint(gpa, "reaches too few cases whose helps carry a fix of kind {s}", .{k.text()}),
                .expected = try std.fmt.allocPrint(gpa, "at least {d}", .{@as(u32, 1)}),
                .actual = try std.fmt.allocPrint(gpa, "{d} from the corpus", .{n}),
            });
        }
    }
    for (std.enums.values(Damage)) |d| {
        const n = damages.get(d) orelse 0;
        std.debug.print("conformance: {d} module(s) checked that {s}, and {d} generated\n", .{
            n,
            d.why(),
            made_damages.get(d) orelse 0,
        });
        if (focused_floors and n < 1) {
            try failures.append(gpa, .{
                .path = "the corpus",
                .what = try std.fmt.allocPrint(gpa, "reaches too few modules checking that {s}", .{d.why()}),
                .expected = try std.fmt.allocPrint(gpa, "at least {d}", .{@as(u32, 1)}),
                .actual = try std.fmt.allocPrint(gpa, "{d} from the corpus", .{n}),
            });
        }
    }
    coverage_zone.end();

    // Command cases, if the runner was told where the binary is. They record
    // what a user sees rather than what a pass computes: which stream a message
    // went to, what the exit code was, how a usage error reads.
    const commands_zone = tracy.beginZone(@src(), "commands");
    if (compiler_path) |compiler| {
        if (enforce_floors)
            try checkCommandOptimisation(gpa, io, &failures, compiler, environ, runtime_path, scratch_dir);
        // `paths` is already narrowed to the selected cases when properties
        // are focused, so every transcript it holds is one to run.
        {
            var commands: std.ArrayList(CommandCase) = .empty;
            defer commands.deinit(gpa);
            // What the compiler under test offers, from its own usage text:
            // a ReleaseSafe runner may be driving a Debug compiler. Asked once,
            // and only of a walk that holds a transcript.
            var help: ?[]const u8 = null;

            for (try commandPaths(gpa, paths)) |relative_path| {
                const full = try std.fs.path.join(gpa, &.{ tests_dir_path, relative_path });
                const text = try readFileAlloc(io, gpa, full);
                const display = try displayPath(gpa, tests_dir_path, relative_path);
                const stem = full[0 .. full.len - ".cmd".len];

                if (!transcripts.isTranscript(text)) {
                    try failures.append(gpa, .{
                        .path = display,
                        .what = "reading the command case",
                        .expected = "a command case is a transcript: a line beginning `  $ ` runs a command",
                        .actual = "no command line",
                    });
                    tally(&properties, &passed_over, .command, true);
                    continue;
                }
                var parsed = try transcripts.parse(gpa, text);
                defer parsed.deinit(gpa);
                if (help == null) help = try compilerHelp(gpa, io, compiler);
                if (transcripts.hiddenCommand(parsed, help.?, driver.isDebuggingAid)) |named| {
                    std.debug.print(
                        "conformance: {s} not checked -- this build does not offer '{s}'\n",
                        .{ display, named },
                    );
                    tally(&properties, &passed_over, .command, false);
                    continue;
                }
                // A sanitizer watches a program running, so under one a
                // transcript that runs none is left to the unsanitized walk.
                if (sanitize != null and !transcripts.runsAProgram(parsed)) {
                    tally(&properties, &passed_over, .command, false);
                    continue;
                }
                try commands.append(gpa, .{
                    .text = text,
                    .stem = stem,
                    .display_path = display,
                });
            }

            // Each command spawns the compiler and waits for it, and nothing
            // one of them does is visible to another -- so they were twenty-
            // eight processes run one at a time, which a trace put at
            // thirty-five of the thirty-seven seconds after the walk.
            //
            // Striped across the same number of workers as the corpus, for the
            // same reason: a command that has to build something costs orders
            // of magnitude more than one that reports a parse error, and the
            // list is not sorted by cost.
            // The same count the corpus is walked with, rather than one per
            // core regardless. A command builds a program and holds what it
            // built, so the count is what multiplies the largest one -- and a
            // run told to use one walker was still starting eight of these,
            // which is why asking for fewer walkers moved nothing.
            const cmd_workers = @min(commands.items.len, walkers);
            if (cmd_workers > 0) {
                // A transcript names the checkout as `LINEA_ROOT`; the runner
                // runs from the checkout root.
                const checkout_root = try std.Io.Dir.cwd().realPathFileAlloc(io, ".", gpa);
                const cmd_scratch = scratch_dir;
                const cmd_work = try gpa.alloc(Work, cmd_workers);
                for (cmd_work) |*w| w.* = .{};

                // Held by the caller for the reason the walkers' are: a
                // `Failure` is allocated from one.
                const Commands = struct {
                    fn run(
                        io_: std.Io,
                        compiler_: []const u8,
                        environ_: std.process.Environ,
                        runtime_: ?[]const u8,
                        sanitize_: ?[]const u8,
                        root_: []const u8,
                        scratch_: []const u8,
                        items: []const CommandCase,
                        w: *Work,
                        arena: *std.heap.ArenaAllocator,
                        me: usize,
                        of: usize,
                        update_: bool,
                    ) void {
                        tracy.setThreadName("command");

                        const keep = arena.allocator();

                        // A command builds a program and holds what it built,
                        // and only what it answered is read afterwards. Kept,
                        // it was the largest thing this runner did: twenty-odd
                        // commands for seven gigabytes.
                        var per_command = std.heap.ArenaAllocator.init(std.heap.page_allocator);
                        defer per_command.deinit();

                        var at = me;
                        while (at < items.len) : (at += of) {
                            const zone = tracy.beginZone(@src(), "command");
                            defer zone.end();
                            zone.setText(items[at].display_path);
                            zone.setValue(at);
                            checkTranscript(per_command.allocator(), io_, &w.failures, compiler_, environ_, runtime_, sanitize_, root_, scratch_, items[at], update_) catch |err| {
                                std.debug.print("conformance: {s}: {s}\n", .{ items[at].display_path, @errorName(err) });
                                std.process.exit(1);
                            };
                            w.retain(keep, at) catch |err| {
                                std.debug.print("conformance: {s}: {s}\n", .{ items[at].display_path, @errorName(err) });
                                std.process.exit(1);
                            };
                            _ = per_command.reset(.{ .retain_with_limit = 4 << 20 });
                            tally(&w.properties, &w.passed_over, .command, true);
                        }
                    }
                };

                if (cmd_workers == 1) {
                    Commands.run(io, compiler, environ, runtime_path, sanitize, checkout_root, cmd_scratch, commands.items, &cmd_work[0], &cmd_arenas[0], 0, 1, update);
                } else {
                    const threads = try gpa.alloc(std.Thread, cmd_workers);
                    for (threads, 0..) |*t, me| {
                        t.* = try std.Thread.spawn(compiler_stack.spawn_config, Commands.run, .{
                            io, compiler, environ, runtime_path, sanitize, checkout_root, cmd_scratch, commands.items, &cmd_work[me], &cmd_arenas[me], me, cmd_workers, update,
                        });
                    }
                    for (threads) |t| t.join();
                }

                for (cmd_work) |*one| {
                    try failures.appendSlice(gpa, one.kept.items);
                    for (std.enums.values(Property)) |k| {
                        if (one.properties.get(k)) |n| properties.put(k, (properties.get(k) orelse 0) + n);
                        if (one.passed_over.get(k)) |n| passed_over.put(k, (passed_over.get(k) orelse 0) + n);
                    }
                }
            }
        }
    } else {
        // A run given no binary can check none of them, and says so on the
        // counter rather than by leaving the corpus unaccounted for. The floor
        // is what holds a run that should have had one to having had it.
        for (0..corpus.commands) |_| tally(&properties, &passed_over, .command, false);
    }
    commands_zone.end();

    // LSP session cases: a directory holding `session.jsonl` is a script of
    // JSON-RPC requests, replayed in-process against a server rooted at that
    // directory. Every session is replayed, whether or not it has a golden --
    // the same shape a command case checks its exit status in even where an
    // individual stream's golden is absent. What the server answered is
    // compared against `session.golden`, sitting beside the script, through
    // the same acceptance flow every other golden goes through.
    //
    // How many scripts that was is not counted here. Every one of them tallies
    // `deterministic` and `held_once`, whose reported counts sum to the
    // sessions the corpus holds -- a counter beside them would be a third
    // answer to the one question, and the first session kind one loop reached
    // and another did not would be where the three stopped agreeing.

    // A server, its documents and everything it analysed, released when the
    // session that built them is answered. Two servers are stood up per
    // session and nothing either of them holds is read once the bytes have
    // been compared, so keeping them was keeping every server the corpus ever
    // started.
    const sessions_zone = tracy.beginZone(@src(), "lsp.sessions");

    var opened_and_beside: u32 = 0;
    var opened_alone: u32 = 0;
    var opened_differing: u32 = 0;

    var session_paths: std.ArrayList([]const u8) = .empty;
    defer session_paths.deinit(gpa);
    for (paths) |path| if (isSessionPath(path)) try session_paths.append(gpa, path);
    const session_results = try runSessions(
        gpa,
        io,
        checked_library,
        tests_dir_path,
        session_paths.items,
        update,
        walkers,
        arenas,
    );
    defer gpa.free(session_results);
    try mergeSessionResults(
        gpa,
        session_results,
        &failures,
        &properties,
        &passed_over,
        &opened_and_beside,
        &opened_differing,
        &opened_alone,
        null,
    );
    // Informational, and not a property: the sub-grain of `held_once`, whose
    // tally counts sessions, so a script opening one document and one opening
    // forty are one apiece there. This grain has no population the corpus can
    // give -- what a script opens is read out of the script by the check --
    // which is why the property above it is asked per session and this line
    // only says how far it reached.
    std.debug.print(
        "conformance: {d} document(s) a session opens compared against the file beside the script, {d} of them differing, {d} naming no file there\n",
        .{ opened_and_beside, opened_differing, opened_alone },
    );
    sessions_zone.end();

    // One index over the whole corpus, which is a workspace of a hundred and
    // fifty unrelated programs -- exactly the shape the cross-program rule
    // exists for. Asked once per program: everything a query for it returns
    // has to name a module that program can reach, because an offer it cannot
    // reach is an import the add-import fix would write and the compiler would
    // refuse.
    if (options.properties) {
        const workspace_zone = tracy.beginZone(@src(), "lsp.workspace");
        defer workspace_zone.end();
        var index = try lsp_workspace.Index.build(gpa, io, tests_dir_path);
        defer index.deinit();
        const query = try index.query();

        var offered_in_all: usize = 0;
        var taken: Taken = .{};
        var looked_for: u32 = 0;

        var manifests: std.ArrayList([]const u8) = .empty;
        defer manifests.deinit(gpa);
        for (paths) |path| {
            if (std.mem.eql(u8, std.fs.path.basename(path), loader.manifest_name)) {
                try manifests.append(gpa, path);
            }
        }

        const results = try runWorkspacePrograms(
            gpa,
            io,
            checked_library,
            tests_dir_path,
            manifests.items,
            query,
            walkers,
            arenas,
        );
        defer gpa.free(results);
        try mergeWorkspaceResults(
            gpa,
            results,
            &failures,
            &properties,
            &passed_over,
            &taken,
            &offered_in_all,
            &looked_for,
        );

        // Informational, and not a property: the sub-grain of
        // `accepted_offers`, whose tally counts programs, so a run that
        // accepted one item of a hundred would look exactly like one that
        // accepted all of them. This grain has no population the corpus can
        // give -- what a server offers is the server's answer, not a number
        // the walk can count -- so it is held to floors of its own below for
        // what the property above cannot see.
        std.debug.print(
            "conformance: {d} completion item(s) accepted and re-checked, {d} of them a rewrite, " ++
                "{d} of them reduced from a snippet, {d} declined as naming no value\n",
            .{ taken.applied, taken.rewritten, taken.stopped, taken.declined },
        );

        // Informational, and not a property: the sub-grain of
        // `completion_recovers`, whose tally counts a program and a shape, so
        // a shape whose whole-text answer held one name would look exactly
        // like one whose answer held forty. This grain has no population the
        // corpus can give -- the names come from the server's own whole-text
        // answer -- so it is held to a floor of its own below.
        std.debug.print(
            "conformance: {d} name(s) a whole-text answer held looked for in what a recovered one offers\n",
            .{looked_for},
        );
        // What the property above cannot see: every shape could go on being
        // asked while the answer each is compared against shrank to one name,
        // and the per-shape count would not move.
        if (focused_floors and looked_for < 1) {
            try failures.append(gpa, .{
                .path = "the corpus",
                .what = "a completion answers from whatever the parser recovered",
                .expected = try gpa.dupe(u8, "at least 1 name(s) looked for"),
                .actual = try std.fmt.allocPrint(gpa, "{d}", .{looked_for}),
            });
        }
        if (focused_floors and taken.applied < 1) {
            try failures.append(gpa, .{
                .path = "the corpus",
                .what = "accepting what the server offers leaves a program that checks",
                .expected = try gpa.dupe(u8, "at least 1 completion item(s) accepted"),
                .actual = try std.fmt.allocPrint(gpa, "{d}", .{taken.applied}),
            });
        }
        // A floor of its own, because a rewrite is a different shape of edit
        // and the count above would not notice it going to zero.
        if (focused_floors and taken.rewritten < 1) {
            try failures.append(gpa, .{
                .path = "the corpus",
                .what = "accepting what the server offers leaves a program that checks",
                .expected = try gpa.dupe(u8, "at least 1 rewrite(s) accepted"),
                .actual = try std.fmt.allocPrint(gpa, "{d}", .{taken.rewritten}),
            });
        }
        // And one for the snippet, which is the shape whose text a compiler
        // never sees as it was sent. A server that stopped writing a stop
        // would leave every other count where it is.
        if (focused_floors and taken.stopped < 1) {
            try failures.append(gpa, .{
                .path = "the corpus",
                .what = "accepting what the server offers leaves a program that checks",
                .expected = try gpa.dupe(u8, "at least 1 snippet(s) accepted"),
                .actual = try std.fmt.allocPrint(gpa, "{d}", .{taken.stopped}),
            });
        }

        // An index that held nothing would satisfy every program above and say
        // nothing about any of them.
        if (focused_floors and offered_in_all == 0) {
            try failures.append(gpa, .{
                .path = "the corpus",
                .what = "the index offers nothing the program cannot import",
                .expected = try gpa.dupe(u8, "at least one name offered across the corpus"),
                .actual = try gpa.dupe(u8, "none"),
            });
        }
    }

    const accounting_zone = tracy.beginZone(@src(), "final-accounting");

    // Informational, and not a property: the sub-grain of
    // `completion_offers`, whose tally counts functions, so a function holding
    // one dot and one holding forty are one apiece there. This grain has no
    // population the corpus can give -- how many dots a file writes is the
    // parse's answer, and counting them a second time here would be a second
    // implementation of the question -- so it is held to a floor of its own
    // below.
    //
    // Last, because the counts are complete only here.
    std.debug.print(
        "conformance: {d} point(s) after a dot held to what the resolver settles there\n",
        .{dots_asked},
    );

    // The other half of the lending property, at the grain it reached: the
    // tally counts cases, and only a walk over an array has a consuming form
    // over the same value -- so a case checked there may have been held to one
    // half of the pair or to both, and one number cannot say which.
    //
    // Last, for the reason above.
    std.debug.print(
        "conformance: {d} lending walk(s) also held to what the consuming form takes\n",
        .{walks_also},
    );

    // And the floor the tally beside it cannot carry: the half could stop
    // being reached altogether -- a walk over an array ceasing to be one this
    // finds -- while every case it belongs to went on being checked by the
    // first half and counted once.
    if (focused_floors and walks_also < 1) {
        try failures.append(gpa, .{
            .path = "the corpus",
            .what = "a lending walk leaves what it walks live, and a consuming one takes it",
            .expected = try gpa.dupe(u8, "at least 1 walk(s) held to both forms"),
            .actual = try std.fmt.allocPrint(gpa, "{d}", .{walks_also}),
        });
    }

    // What the property above cannot see: a dot half that stopped asking
    // altogether would leave the function count where it is, and the property
    // would go on reporting the same population while checking one of its two
    // points.
    if (enforce_floors and dots_asked < 400) {
        try failures.append(gpa, .{
            .path = "the corpus",
            .what = "a completion offers what the point can reach and nothing else",
            .expected = try gpa.dupe(u8, "at least 400 point(s) asked after a dot"),
            .actual = try std.fmt.allocPrint(gpa, "{d}", .{dots_asked}),
        });
    }

    // A property that ran on nothing is counted and cannot fail, which is
    // worse than not having it: the number is printed either way, and nobody
    // reads a number that does not fail. Every loop above reaches its subject
    // through `orelse continue` or through a directory opened with `catch
    // null`, so a property that stops applying looks exactly like one that
    // applies and agrees.
    for (std.enums.values(Property)) |q| {
        const reached = properties.get(q) orelse 0;
        const declined = passed_over.get(q) orelse 0;
        // The counts apart rather than their sum, as the rewrites are printed:
        // the floor speaks for the corpus, so the number beside it has to be
        // the corpus's own. Printed whether or not the floors are enforced, for
        // the reason every other count is: a floor is a number someone has to
        // be able to compare against what the run reached, and these were the
        // counts the run never said out loud. The one printed line is the whole
        // of what the run knows about this property.
        std.debug.print("conformance: {d} {s}(s) checked that {s}, {d} passed over, and {d} generated\n", .{
            reached,
            q.subject(),
            q.why(),
            declined,
            made_properties.get(q) orelse 0,
        });
        // Whatever the run was asked for: a corpus count that does not
        // account for the corpus is wrong in a run over three cases exactly
        // as it is in a run over all of them, and reaching past the
        // population is the shape the generated programs make when they feed
        // a tally the floors read.
        //
        // A sanitized walk checks only what runs and leaves the rest of the
        // corpus to the unsanitized one, so it accounts for none of it.
        const population = q.accountingPopulation(corpus, options.properties);
        if (q.focused()) std.debug.print("conformance: focused population for {s}: {d} {s}(s)\n", .{ @tagName(q), q.populationIn(population), q.subject() });
        if (sanitize == null and !q.accountsFor(population, reached, declined)) {
            try failures.append(gpa, .{
                .path = "the corpus",
                .what = try std.fmt.allocPrint(gpa, "checked that {s} on other than what it holds", .{q.why()}),
                .expected = try std.fmt.allocPrint(gpa, "{d} {s}(s)", .{ q.populationIn(population), q.subject() }),
                .actual = try std.fmt.allocPrint(gpa, "{d} checked and {d} passed over", .{ reached, declined }),
            });
        }
        if (!every_property) continue;
        if (q.focused() and !options.properties) continue;
        if (options.properties and !q.focused()) continue;
        const floor = q.floor();
        if (reached >= floor) continue;
        try failures.append(gpa, .{
            .path = "the corpus",
            .what = try std.fmt.allocPrint(gpa, "too few {s}(s) checked that {s}", .{ q.subject(), q.why() }),
            .expected = try std.fmt.allocPrint(gpa, "at least {d}", .{floor}),
            .actual = try std.fmt.allocPrint(gpa, "{d} from the corpus", .{reached}),
        });
    }

    // What the settled reference property passed over, split into the two
    // unlike things the one number above holds. A refusal is a settled
    // reference with a diagnostic against it and is coverage this property
    // declines; a signature's settled reference is one the checker resolves per
    // call and records against no token, so it is coverage nothing has -- and
    // the second is a hole rather than a decision, which one number cannot say.
    //
    // Printed last, because the counts are complete only here.
    {
        const settled = properties.get(.settled_refs) orelse 0;
        std.debug.print(
            "conformance: {d} of those read through the bound that declares the name, which each instantiation settles its own way, and {d} through the module the head names\n",
            .{ declined_settled_refs.through_a_bound, declined_settled_refs.through_a_module },
        );
        std.debug.print(
            "conformance: {d} settled reference(s) written in a signature, which the checker answers per call and records against no token, {d} read through a bound the source does not resolve, and {d} it recorded nothing else for\n",
            .{
                declined_settled_refs.in_a_signature,
                declined_settled_refs.no_bound_the_source_names,
                declined_settled_refs.unrecorded,
            },
        );

        // The split against the population, rather than the two counts the
        // property is accounted by. The sum is the same number either way, so
        // this says the split itself accounts for what was split: a settled
        // reference counted on neither side of it would leave the two-way
        // accounting holding and this failing. The bound-headed and
        // module-headed checks are inside `settled` and are not added again --
        // each is a checked one counted twice on purpose, once as a check and
        // once as which check.
        const split = settled +
            declined_settled_refs.in_a_signature +
            declined_settled_refs.no_bound_the_source_names +
            declined_settled_refs.unrecorded;
        if (split != Property.settled_refs.populationIn(corpus)) {
            try failures.append(gpa, .{
                .path = "the corpus",
                .what = try gpa.dupe(u8, "split what it passed over into other than what it passed over"),
                .expected = try std.fmt.allocPrint(gpa, "{d} settled reference(s)", .{
                    Property.settled_refs.populationIn(corpus),
                }),
                .actual = try std.fmt.allocPrint(gpa, "{d} checked ({d} through a bound, {d} through a module), {d} in a signature, {d} through a bound the source does not resolve and {d} unrecorded", .{
                    settled,
                    declined_settled_refs.through_a_bound,
                    declined_settled_refs.through_a_module,
                    declined_settled_refs.in_a_signature,
                    declined_settled_refs.no_bound_the_source_names,
                    declined_settled_refs.unrecorded,
                }),
            });
        }
    }

    // After the walk, so what is read is what this run settled.
    try checkTwins(gpa, io, &failures, tests_dir_path, golden_root, paths);
    accounting_zone.end();

    // Whole-corpus runs also check the compiler's allocation growth, using
    // two generated modules independently of the selected source cases.
    if (enforce_floors) {
        const cost_zone = tracy.beginZone(@src(), "cost");
        defer cost_zone.end();
        try checkCost(gpa, io, &failures);
    }

    // Asked of the whole run, so it is asked after everything that allocates.
    {
        const peak_zone = tracy.beginZone(@src(), "peak");
        defer peak_zone.end();
        try checkPeak(gpa, &failures);
    }

    const report_zone = tracy.beginZone(@src(), "report");
    defer report_zone.end();
    const skipped_unchecked = unchecked_skips.load(.monotonic);
    if (skipped_unchecked != 0) std.debug.print(
        "conformance: {d} case(s) record a report of the checking allocator and were not run; run them with {s}\n",
        .{ skipped_unchecked, runtime_symbols.checked_archive_name },
    );
    if (failures.items.len == 0) {
        std.debug.print("conformance: {d} case(s) and {d} transcript(s) OK in {d}s\n", .{
            checked,
            properties.get(.command) orelse 0,
            @divTrunc(began.durationTo(std.Io.Timestamp.now(io, .awake)).nanoseconds, std.time.ns_per_s),
        });
        return 0;
    }

    for (failures.items) |f| {
        std.debug.print("\nFAIL {s} ({s})\n", .{ f.path, f.what });
        std.debug.print("--- expected ---\n{s}\n--- actual ---\n{s}\n", .{ f.expected, f.actual });
    }
    std.debug.print("\nconformance: {d} failure(s) of {d} case(s) and {d} transcript(s)\n", .{ failures.items.len, checked, properties.get(.command) orelse 0 });
    std.debug.print("rerun this conformance command with --update to accept, after reading the diffs above\n", .{});
    return 1;
}

const OutcomeStats = struct {
    hits: std.atomic.Value(u64) = .init(0),
    misses: std.atomic.Value(u64) = .init(0),
    native_nanoseconds: std.atomic.Value(u64) = .init(0),

    fn report(self: *const OutcomeStats, root: []const u8, boundary: []const u8) void {
        std.debug.print("conformance: native outcomes [{s}; {s}]: {d} cache hits, {d} cache misses; {d}ms cumulative build/run time (workers overlap)\n", .{
            root,
            boundary,
            self.hits.load(.monotonic),
            self.misses.load(.monotonic),
            self.native_nanoseconds.load(.monotonic) / std.time.ns_per_ms,
        });
    }
};

/// What a case's program did, keyed by everything that decides it.
///
/// The emitted IR, the runtime, the commands a build assembles and the tools
/// it runs them with are the entire input to building and running a case, so a
/// run whose inputs are unchanged cannot produce a different outcome. Skipping
/// one avoids a link and a process launch, which between them are nearly the
/// whole cost of the suite -- our own code generation is a few milliseconds of
/// it.
const OutcomeCache = struct {
    dir: []const u8,
    /// Owned by one runner invocation and shared by its workers. Counts cover
    /// outcomeOf; command fixtures launch the compiler independently.
    stats: ?*OutcomeStats = null,
    /// Mixed into every key: what a build reads that the program does not
    /// supply. Any of it changing invalidates every entry, which is what it
    /// should do.
    ///
    /// The runtime and the build commands go in by their bytes; the tools go in
    /// by a stamp, so this identifies them rather than reading them.
    salt: u64,

    /// How one of the programs a build runs is identified.
    ///
    /// Where it resolved to on `PATH`, and what the file there is. Not its
    /// bytes: a C compiler is a hundred megabytes, hashing it would cost more
    /// than the runs the cache saves, and the three fields below move whenever
    /// the binary does -- a store path changes under Nix, and a size or a
    /// modification time changes under an in-place upgrade.
    const ToolStamp = struct {
        name: []const u8,
        path: ?[]const u8,
        size: u64,
        mtime: i96,
    };

    /// Everything a case's outcome depends on beyond the emitted IR.
    const Inputs = struct {
        /// The runtime archive's bytes.
        runtime: ?[]const u8,
        sanitize: ?[]const u8,
        /// The source of the module that assembles the build commands.
        ///
        /// The file itself rather than a copy of the argv it builds: a copy
        /// would be a second place answering "what does a build run", and the
        /// two would agree only until someone edited one of them.
        commands: []const u8,
        tools: []const ToolStamp,
    };

    /// The key every outcome is filed under, beside the program's own IR.
    ///
    /// A pure function of what a build reads, so what it covers can be
    /// asserted without a toolchain to sabotage.
    /// Mixed into every key. Changing it retires every recorded outcome, for
    /// when entries a runner already wrote can no longer be trusted: entries
    /// from runners that built concurrent cases under one shared path may
    /// hold another program's result.
    const generation = "outcomes-2";

    fn saltOf(in: Inputs) u64 {
        var salt: u64 = std.hash.Wyhash.hash(4, generation);
        if (in.runtime) |bytes| salt ^= std.hash.Wyhash.hash(0, bytes);
        if (in.sanitize) |name| salt ^= std.hash.Wyhash.hash(1, name);
        salt ^= std.hash.Wyhash.hash(2, in.commands);

        for (in.tools) |t| {
            var h: std.hash.Wyhash = .init(3);
            h.update(t.name);
            h.update(t.path orelse "not on PATH");
            h.update(std.mem.asBytes(&t.size));
            // Widened first. A modification time is 96 bits in a 128-bit slot,
            // so its own bytes carry four the value does not reach, and a key
            // reading those is a function of the memory a stamp was built in as
            // well as of the toolchain. One call per process hides that; two in
            // one process disagree about a toolchain neither of them touched.
            const mtime: i128 = t.mtime;
            h.update(std.mem.asBytes(&mtime));
            salt ^= h.final();
        }
        return salt;
    }

    /// The search path rather than the whole environment: the tools are the
    /// only thing the cache asks it about, and taking the answer means a test
    /// can hand this one a directory it just filled.
    fn init(
        gpa: std.mem.Allocator,
        io: std.Io,
        search_path: ?[]const u8,
        scratch: []const u8,
        runtime: ?[]const u8,
        sanitize: ?[]const u8,
    ) !OutcomeCache {
        var runtime_bytes: ?[]const u8 = null;
        if (runtime) |rt| {
            if (readIfExists(io, gpa, rt)) |maybe| runtime_bytes = maybe else |_| {}
        }
        defer if (runtime_bytes) |b| gpa.free(b);

        // Read into the salt and then dropped, paths included. The driver hands
        // this an arena and would never notice, but the cache is not the arena's
        // reason to exist and a test holding it to an allocator that counts is.
        var stamps: std.ArrayList(ToolStamp) = .empty;
        defer {
            for (stamps.items) |s| if (s.path) |p| gpa.free(p);
            stamps.deinit(gpa);
        }
        for (std.enums.values(toolchain.Tool)) |tool| {
            try stamps.append(gpa, try stampOf(gpa, io, search_path, tool.command()));
        }

        const salt = saltOf(.{
            .runtime = runtime_bytes,
            .sanitize = sanitize,
            .commands = @embedFile("driver/toolchain.zig"),
            .tools = stamps.items,
        });

        std.debug.print("conformance: outcome cache [{s}]: salt {x}\n", .{ scratch, salt });
        if (runtime_bytes) |bytes| {
            var digest: [std.crypto.hash.sha2.Sha256.digest_length]u8 = undefined;
            std.crypto.hash.sha2.Sha256.hash(bytes, &digest, .{});
            std.debug.print("conformance: runtime archive: {d} bytes, sha256 {x}\n", .{ bytes.len, digest });
        }
        for (stamps.items) |stamp| {
            std.debug.print("conformance: tool {s}: {s}, {d} bytes, mtime {d}\n", .{
                stamp.name, stamp.path orelse "not on PATH", stamp.size, stamp.mtime,
            });
        }

        const dir = try std.fs.path.join(gpa, &.{ scratch, "outcomes" });
        std.Io.Dir.cwd().createDirPath(io, dir) catch |err| {
            std.debug.print("conformance: cannot create '{s}': {s}\n", .{ dir, @errorName(err) });
            return err;
        };
        return .{ .dir = dir, .salt = salt };
    }

    /// Finds a program the way the build will find it, and describes it.
    ///
    /// Both tools are run by bare name, so what answers is whatever `PATH`
    /// says here and now -- which is why an outcome recorded outside the
    /// development shell must not answer a question asked inside it.
    fn stampOf(
        gpa: std.mem.Allocator,
        io: std.Io,
        search_path: ?[]const u8,
        name: []const u8,
    ) !ToolStamp {
        var it = std.mem.tokenizeScalar(u8, search_path orelse "", ':');
        while (it.next()) |dir| {
            const path = try std.fs.path.join(gpa, &.{ dir, name });
            const stat = std.Io.Dir.cwd().statFile(io, path, .{}) catch {
                gpa.free(path);
                continue;
            };
            if (stat.kind != .file) {
                gpa.free(path);
                continue;
            }
            return .{
                .name = name,
                .path = path,
                .size = stat.size,
                .mtime = stat.mtime.nanoseconds,
            };
        }
        return .{ .name = name, .path = null, .size = 0, .mtime = 0 };
    }

    /// Where one case's outcome is filed.
    ///
    /// The driver joins the emitted IR rather than the salt. The salt is what
    /// every case's build reads; a driver is read for one case, and it decides
    /// that case's outcome exactly as the IR does -- which symbol is
    /// referenced, what is passed, how the ABI is declared, what the program
    /// exits with. Hashing it into the salt would make every entry in the
    /// corpus depend on every driver in it. The optimisation level joins it
    /// for the same reason: one module is built at several levels, and each
    /// build is an outcome of its own.
    fn pathFor(
        self: *const OutcomeCache,
        gpa: std.mem.Allocator,
        key: OutcomeKey,
    ) ![]u8 {
        var h: std.hash.Wyhash = .init(self.salt);
        h.update(key.ir);
        if (key.foreign.driver) |bytes| h.update(bytes);
        for (key.foreign.native.files) |file| {
            h.update(file.path);
            h.update(file.text);
        }
        for (key.foreign.native.compile) |path| h.update(path);
        for (key.foreign.native.link) |name| h.update(name);
        h.update(key.opt);
        const filed = h.final();
        const name = try std.fmt.allocPrint(gpa, "{x}", .{filed});
        defer gpa.free(name);
        return std.fs.path.join(gpa, &.{ self.dir, name });
    }

    fn get(self: *const OutcomeCache, gpa: std.mem.Allocator, io: std.Io, key: OutcomeKey) !?[]u8 {
        const path = try self.pathFor(gpa, key);
        defer gpa.free(path);
        return readIfExists(io, gpa, path);
    }

    fn lookup(self: *const OutcomeCache, gpa: std.mem.Allocator, io: std.Io, key: OutcomeKey) !?Ran {
        if (try self.get(gpa, io, key)) |recorded| {
            if (recordedOutcome(recorded)) |split| {
                if (self.stats) |stats| _ = stats.hits.fetchAdd(1, .monotonic);
                return .{ .text = split.text, .output = split.output, .errors = split.errors, .tool_failed = false };
            }
        }
        if (self.stats) |stats| _ = stats.misses.fetchAdd(1, .monotonic);
        return null;
    }

    /// Records an outcome, failing the run if it cannot.
    ///
    /// A cache that quietly stops recording is indistinguishable from one that
    /// records and saves nothing, since correctness never suffers either way.
    /// Refusing to continue is what keeps the difference visible.
    fn put(
        self: *const OutcomeCache,
        gpa: std.mem.Allocator,
        io: std.Io,
        key: OutcomeKey,
        text: []const u8,
        diagnostics: ?*std.Io.Writer,
    ) !void {
        const path = try self.pathFor(gpa, key);
        defer gpa.free(path);

        // Written beside the entry and renamed onto it, because a reader may be
        // another case running at the same time. Two writers of one key write
        // identical bytes -- the key is a hash of what produced them -- so the
        // content is never in doubt; what a direct write risks is a reader
        // seeing half of it. A rename within a directory is atomic, so an entry
        // either is not there or is complete.
        //
        // The temporary is named for the entry it becomes plus the writer's
        // thread, so two writers of the same key do not share a scratch file
        // and neither sees the other's partial write.
        const staged = try std.fmt.allocPrint(gpa, "{s}.{d}.writing", .{ path, std.Thread.getCurrentId() });
        defer gpa.free(staged);

        {
            const file = std.Io.Dir.cwd().createFile(io, staged, .{}) catch |err| {
                if (diagnostics) |writer| {
                    try writer.print("conformance: cannot write '{s}': {s}\n", .{ path, @errorName(err) });
                } else {
                    std.debug.print("conformance: cannot write '{s}': {s}\n", .{ staged, @errorName(err) });
                }
                return err;
            };
            defer file.close(io);

            var buf: [4096]u8 = undefined;
            var w = file.writer(io, &buf);
            try w.interface.writeAll(text);
            try w.interface.flush();
        }

        try std.Io.Dir.cwd().rename(staged, std.Io.Dir.cwd(), path, io);
    }
};

test "the recorded outcome of a program is keyed on the toolchain that built it" {
    const base: OutcomeCache.Inputs = .{
        .runtime = "archive bytes",
        .sanitize = null,
        .commands = "mlir-opt in.mlir; mlir-translate; cc -o out out.ll rt.a",
        .tools = &.{
            .{ .name = "mlir-opt", .path = "/nix/store/aaa/bin/mlir-opt", .size = 400, .mtime = 1 },
            .{ .name = "cc", .path = "/nix/store/bbb/bin/cc", .size = 900, .mtime = 2 },
        },
    };
    const was = OutcomeCache.saltOf(base);

    // Reading the same inputs twice has to answer the same, or nothing is ever
    // served and the cache is a directory that only grows.
    try testing.expectEqual(was, OutcomeCache.saltOf(base));

    // The three inputs a build reads that the emitted IR does not describe: an
    // assembler swapped underneath, a linker swapped underneath, and an edit
    // to the flags the two are handed. Each is a way for the same program to
    // become a different binary, and a key blind to any of them answers a
    // question about a binary that no longer exists.
    var other_tool = base;
    other_tool.tools = &.{
        .{ .name = "mlir-opt", .path = "/nix/store/ccc/bin/mlir-opt", .size = 400, .mtime = 1 },
        .{ .name = "cc", .path = "/nix/store/bbb/bin/cc", .size = 900, .mtime = 2 },
    };
    try testing.expect(OutcomeCache.saltOf(other_tool) != was);

    var upgraded_cc = base;
    upgraded_cc.tools = &.{
        .{ .name = "mlir-opt", .path = "/nix/store/aaa/bin/mlir-opt", .size = 400, .mtime = 1 },
        .{ .name = "cc", .path = "/nix/store/bbb/bin/cc", .size = 901, .mtime = 7 },
    };
    try testing.expect(OutcomeCache.saltOf(upgraded_cc) != was);

    var other_flags = base;
    other_flags.commands = "mlir-opt in.mlir; mlir-translate; cc -O2 -o out out.ll rt.a";
    try testing.expect(OutcomeCache.saltOf(other_flags) != was);

    // And a tool that is not there at all, which is the shape a run outside
    // the development shell has: it must not be served what a run inside it
    // recorded, or a corpus whose IR has not moved reports itself green
    // without an assembler present.
    var absent = base;
    absent.tools = &.{
        .{ .name = "mlir-opt", .path = null, .size = 0, .mtime = 0 },
        .{ .name = "cc", .path = "/nix/store/bbb/bin/cc", .size = 900, .mtime = 2 },
    };
    try testing.expect(OutcomeCache.saltOf(absent) != was);
}

test "the runtime and the sanitizer still decide the key" {
    const base: OutcomeCache.Inputs = .{
        .runtime = "archive bytes",
        .sanitize = null,
        .commands = "cc -o out out.s rt.a",
        .tools = &.{},
    };
    const was = OutcomeCache.saltOf(base);

    var rebuilt_runtime = base;
    rebuilt_runtime.runtime = "other archive bytes";
    try testing.expect(OutcomeCache.saltOf(rebuilt_runtime) != was);

    var watched = base;
    watched.sanitize = "address";
    try testing.expect(OutcomeCache.saltOf(watched) != was);
}

test "a tool is stamped from the file the search path leads to" {
    const gpa = testing.allocator;

    var holding = testing.tmpDir(.{});
    defer holding.cleanup();
    try holding.dir.writeFile(testing.io, .{ .sub_path = "mlir-opt", .data = "a pretend lowering" });
    const dir = try std.fs.path.join(gpa, &.{ ".zig-cache", "tmp", &holding.sub_path });
    defer gpa.free(dir);

    // Found by the name the build runs, at the first directory on the path
    // holding it -- and described by the file rather than by the name, so two
    // toolchains cannot stamp alike.
    const found = try OutcomeCache.stampOf(gpa, testing.io, dir, "mlir-opt");
    defer if (found.path) |p| gpa.free(p);
    try testing.expect(found.path != null);
    try testing.expectEqual(@as(u64, "a pretend lowering".len), found.size);

    // A name no directory on the path holds. This is the shape a run outside
    // the development shell has, and it must not stamp the same as a run
    // inside it.
    const missing = try OutcomeCache.stampOf(gpa, testing.io, dir, "cc");
    defer if (missing.path) |p| gpa.free(p);
    try testing.expect(missing.path == null);

    // An empty path is not the same as no path: both find nothing, and neither
    // may reach past the search it was given to whatever the process inherited.
    const nowhere = try OutcomeCache.stampOf(gpa, testing.io, null, "mlir-opt");
    defer if (nowhere.path) |p| gpa.free(p);
    try testing.expect(nowhere.path == null);
}

/// The salt a cache built over this search path carries.
///
/// Through `init` rather than through `saltOf`: the salt has always
/// distinguished stamps it was handed, and what nothing held was that `init`
/// collects one per tool and passes them on.
fn saltOver(gpa: std.mem.Allocator, search_path: []const u8, scratch: []const u8) !u64 {
    const cache = try OutcomeCache.init(gpa, testing.io, search_path, scratch, null, null);
    defer gpa.free(cache.dir);
    return cache.salt;
}

test "the cache stamps every tool a build runs" {
    const gpa = testing.allocator;

    // One directory answering for every tool, so what moves between two salts
    // below is a tool's own file rather than the search path -- which two
    // directories would have changed as well, leaving a test that passes on a
    // cache stamping one tool and ignoring the rest.
    var bin = testing.tmpDir(.{});
    defer bin.cleanup();
    const path = try std.fs.path.join(gpa, &.{ ".zig-cache", "tmp", &bin.sub_path });
    defer gpa.free(path);

    var scratch = testing.tmpDir(.{});
    defer scratch.cleanup();
    const where = try std.fs.path.join(gpa, &.{ ".zig-cache", "tmp", &scratch.sub_path });
    defer gpa.free(where);

    const bytes = "0123456789abcdef";
    for (std.enums.values(toolchain.Tool)) |tool| {
        try bin.dir.writeFile(testing.io, .{ .sub_path = tool.command(), .data = bytes[0..2] });
    }

    var was = try saltOver(gpa, path, where);
    // The same toolchain twice answers the same, or nothing is ever served and
    // the cache is a directory that only grows.
    try testing.expectEqual(was, try saltOver(gpa, path, where));

    // Each tool in turn, replaced underneath while everything else holds still.
    // A key blind to one of them answers a question about a binary built by a
    // toolchain that is no longer there -- and a `Tool` added later and left
    // out of the stamps fails here rather than going quiet.
    for (std.enums.values(toolchain.Tool), 0..) |tool, i| {
        try bin.dir.writeFile(testing.io, .{ .sub_path = tool.command(), .data = bytes[0 .. 4 + i] });
        const now = try saltOver(gpa, path, where);
        try testing.expect(now != was);
        was = now;
    }
}

test "outcome telemetry distinguishes valid hits from absent and malformed records" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    const root = try std.fs.path.join(gpa, &.{ ".zig-cache", "tmp", &tmp.sub_path });
    var stats: OutcomeStats = .{};
    const cache: OutcomeCache = .{ .dir = root, .salt = 0, .stats = &stats };
    try testing.expect(try cache.lookup(gpa, testing.io, .{ .ir = "absent" }) == null);
    try cache.put(gpa, testing.io, .{ .ir = "malformed" }, "not an outcome", null);
    try testing.expect(try cache.lookup(gpa, testing.io, .{ .ir = "malformed" }) == null);
    try cache.put(gpa, testing.io, .{ .ir = "valid" }, "said 0\nprinted 0\nexit 0\n", null);
    const hit = (try cache.lookup(gpa, testing.io, .{ .ir = "valid" })).?;
    try testing.expectEqualStrings("exit 0\n", hit.text);
    try testing.expectEqual(@as(u64, 1), stats.hits.load(.monotonic));
    try testing.expectEqual(@as(u64, 2), stats.misses.load(.monotonic));
    try testing.expectEqual(@as(u64, 0), stats.native_nanoseconds.load(.monotonic));
    var separate: OutcomeStats = .{};
    const other: OutcomeCache = .{ .dir = root, .salt = 0, .stats = &separate };
    _ = try other.lookup(gpa, testing.io, .{ .ir = "valid" });
    try testing.expectEqual(@as(u64, 1), stats.hits.load(.monotonic));
    try testing.expectEqual(@as(u64, 1), separate.hits.load(.monotonic));
}

test "outcome cache write diagnostics can be retained" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    const root = try std.fs.path.join(testing.allocator, &.{ ".zig-cache", "tmp", &tmp.sub_path });
    defer testing.allocator.free(root);
    const missing = try std.fs.path.join(testing.allocator, &.{ root, "missing", "outcomes" });
    defer testing.allocator.free(missing);
    const cache: OutcomeCache = .{ .dir = missing, .salt = 0 };
    var diagnostics: std.Io.Writer.Allocating = .init(testing.allocator);
    defer diagnostics.deinit();

    try testing.expectError(
        error.FileNotFound,
        cache.put(
            testing.allocator,
            testing.io,
            .{ .ir = "module ir" },
            "recorded outcome",
            &diagnostics.writer,
        ),
    );
    try testing.expect(std.mem.startsWith(u8, diagnostics.written(), "conformance: cannot write '"));
    try testing.expect(std.mem.indexOf(u8, diagnostics.written(), missing) != null);
    try testing.expect(std.mem.indexOf(u8, diagnostics.written(), ".writing") == null);
}

test "nested outcomes retain the worker diagnostic writer" {
    if (comptime @hasField(Env, "diagnostics") and @hasDecl(Env, "buildRunOptions")) {
        var diagnostics: std.Io.Writer.Allocating = .init(testing.allocator);
        defer diagnostics.deinit();
        const env: Env = .{
            .scratch = "scratch",
            .runtime = "runtime.a",
            .sanitize = "address",
            .diagnostics = &diagnostics.writer,
        };

        const opts = env.buildRunOptions("nested", "module ir", .{ .driver = "driver source" });
        try testing.expectEqualStrings("scratch", opts.scratch);
        try testing.expectEqualStrings("runtime.a", opts.runtime);
        try testing.expectEqualStrings("address", opts.sanitize.?);
        try testing.expectEqualStrings("nested", opts.name);
        try testing.expectEqualStrings("module ir", opts.ir);
        try testing.expectEqualStrings("driver source", opts.foreign.driver.?);
        try testing.expect(opts.diagnostics == &diagnostics.writer);
    } else {
        try testing.expect(false);
    }
}

/// Everything building a program needs that does not come from the program.
const Env = struct {
    scratch: []const u8,
    runtime: []const u8,
    sanitize: ?[]const u8,
    diagnostics: ?*std.Io.Writer = null,

    fn buildRunOptions(self: Env, name: []const u8, ir: []const u8, foreign: Foreign) BuildRunOptions {
        return .{
            .scratch = self.scratch,
            .name = name,
            .ir = ir,
            .runtime = self.runtime,
            .sanitize = self.sanitize,
            .foreign = foreign,
            .diagnostics = self.diagnostics,
        };
    }
};

/// One program, already compiled and run, ready to be checked against itself.
const Checked = struct {
    display_path: []const u8,
    /// What intermediates for this program are called. A rewrite appends its
    /// own name, so two rewrites of one program do not overwrite each other.
    name: []const u8,
    source: *const Source,
    ast: *const Ast,
    res: *const Resolution,
    /// What the checker settled, for a rewrite that moves a name the resolver
    /// did not pair with its declaration -- an argument naming its parameter.
    typing: *const Typing,
    semantics: TransformSemantics,
    answer: []const u8,
    /// What it printed, which a rewrite has to preserve exactly.
    output: []const u8 = "",
    /// What it said on standard error, on the same terms.
    errors: []const u8 = "",
    /// The code this program generated, for a rewrite that claims to be the
    /// same program rather than merely to answer the same.
    ir: []const u8,
    /// The manifest marking the root, where the case carries one, and the
    /// files its program may embed.
    ///
    /// A rewrite is compiled the way the case was, and what kind of root it is
    /// is part of that: loaded without the manifest, a library is read as a
    /// program and refused for declaring no `main`, and without the data files
    /// an embed names nothing -- disagreements invented by the property rather
    /// than found by it.
    beside: []const loader.InMemoryFile = &.{},
    /// The C driver the case is reached through, where it has one. A rewrite
    /// that cannot change what a program means cannot change what its caller
    /// prints, so the rewrite is run through the same driver.
    foreign: Foreign = .{},
};

/// Property: a rewrite that cannot change what a program means does not change
/// what it answers.
///
/// The program is its own expectation, so there is no golden to record and
/// nothing to accept. It applies equally to a case someone wrote and to a
/// program nobody has ever read.
/// Property: a program built to be ill-formed is rejected, by the rule it
/// breaks.
///
/// The opposite direction to the rewrites. A rewrite preserves meaning, so it
/// can only find a disagreement between two programs the compiler accepts --
/// which a check the compiler never makes cannot cause, because both programs
/// are wrong in the same way. Silence is the failure here, so nothing needs a
/// golden and nothing needs the toolchain.
fn checkMutations(
    gpa: std.mem.Allocator,
    failures: *std.ArrayList(Failure),
    mutations: *std.EnumMap(Mutation, u32),
    display_path: []const u8,
    ast: *const Ast,
    res: *const Resolution,
    types_of: *const Typing,
    text: []const u8,
    kind: ProgramKind,
) !void {
    // One mutant's compilation, released before the next is built. A case is
    // mutated once per rule and each mutant is compiled whole, so holding them
    // made a case cost the sum of its mutants -- which for a case that reaches
    // the text library was over two gigabytes.
    var per_mutation = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer per_mutation.deinit();
    const scratch = per_mutation.allocator();
    var retained_upto = failures.items.len;

    for (std.enums.values(Mutation)) |m| {
        // Taken at the top, so every `continue` below reaches it. Into `gpa`,
        // never this loop's own arena: the copy is what survives the reset on
        // the next line.
        try retainFrom(gpa, failures, retained_upto);
        retained_upto = failures.items.len;
        _ = per_mutation.reset(.{ .retain_with_limit = 4 << 20 });

        const broken = (try m.apply(scratch, ast, res, types_of, text)) orelse continue;
        const verdict = try mutate.verdictOf(scratch, broken, kind);
        mutations.put(m, (mutations.get(m) orelse 0) + 1);

        if (!verdict.rejected) {
            try failures.append(gpa, .{
                .path = display_path,
                .what = m.why(),
                .expected = m.rule(),
                .actual = broken,
            });
            continue;
        }

        // Rejected for the right reason, and for no other. A mutation caught by
        // some unrelated rule proves nothing about the one it was built to
        // break; one caught by its own rule and a second is a program that is
        // wrong twice, which is evidence about neither.
        if (!mutate.asClaimed(verdict, m)) {
            try failures.append(gpa, .{
                .path = display_path,
                .what = m.why(),
                .expected = try mutate.expectation(scratch, m),
                .actual = verdict.text,
            });
        }
    }

    try retainFrom(gpa, failures, retained_upto);
}

/// How many fixes one case is followed through before what remains is
/// reported as two helps that undo each other.
const help_edit_rounds = 8;

/// One error a help's fix answered: its rule and the line it was reported
/// at, moved with every later fix.
const HelpAnswered = struct { code: diagnostic.Code, line: usize };

/// `text` with a fix applied, every edit at once, or why it cannot be: an
/// edit outside `text`, two edits overlapping, or one into another file.
const Applied = union(enum) { text: []const u8, refused: []const u8 };

fn applyFix(scratch: std.mem.Allocator, text: []const u8, file: FileId, fix: diagnostic.Fix) !Applied {
    const edits = try scratch.dupe(diagnostic.Edit, fix.edits);
    std.mem.sortUnstable(diagnostic.Edit, edits, {}, struct {
        fn later(_: void, a: diagnostic.Edit, b: diagnostic.Edit) bool {
            return a.span.start > b.span.start;
        }
    }.later);
    var current = text;
    var floor: u32 = @intCast(text.len);
    for (edits) |edit| {
        if (edit.file != file) return .{ .refused = "an edit into another file" };
        if (edit.span.start > edit.span.end or edit.span.end > text.len) return .{ .refused = "an edit outside the text" };
        if (edit.span.end > floor) return .{ .refused = "two edits of one fix overlap" };
        floor = edit.span.start;
        current = try std.mem.concat(scratch, u8, &.{ current[0..edit.span.start], edit.text, current[edit.span.end..] });
    }
    return .{ .text = current };
}

/// Where `line` of `text` sits once `fix` is applied: moved by the lines
/// each edit starting above it adds or removes.
fn movedLine(text: []const u8, fix: diagnostic.Fix, line: usize) usize {
    var moved = line;
    for (fix.edits) |edit| {
        if (lineAt(text, edit.span.start) >= line) continue;
        const removed = std.mem.count(u8, text[edit.span.start..@min(edit.span.end, text.len)], "\n");
        const added = std.mem.count(u8, edit.text, "\n");
        moved = (moved + added) -| removed;
    }
    return moved;
}

/// What a fix writes, for a failure to show: each edit's text, joined.
fn fixText(gpa: std.mem.Allocator, fix: diagnostic.Fix) ![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    for (fix.edits, 0..) |edit, i| try out.print(gpa, "{s}`{s}`", .{ if (i == 0) "" else " and ", std.mem.trim(u8, edit.text, " \n") });
    return out.items;
}

/// Whether `diagnostics` hold an error under `code` at `line` of `text`.
fn errorAtLine(diagnostics: []const Diagnostic, file: FileId, text: []const u8, code: diagnostic.Code, line: usize) ?Diagnostic {
    for (diagnostics) |d| {
        if (d.severity != .err or d.code != code) continue;
        const label = d.primaryLabel() orelse continue;
        if (label.file != file) continue;
        if (lineAt(text, label.span.start) == line) return d;
    }
    return null;
}

/// The lines of the edited text one edit of a fix wrote, first to last. An
/// edit that removes and writes nothing wrote the line its removal joined.
const Written = struct { first: usize, last: usize };

/// The lines of `edited`, a text with `fix` applied, that each of the fix's
/// edits wrote.
fn writtenLines(scratch: std.mem.Allocator, edited: []const u8, fix: diagnostic.Fix) ![]const Written {
    const edits = try scratch.dupe(diagnostic.Edit, fix.edits);
    std.mem.sortUnstable(diagnostic.Edit, edits, {}, struct {
        fn earlier(_: void, a: diagnostic.Edit, b: diagnostic.Edit) bool {
            return a.span.start < b.span.start;
        }
    }.earlier);
    const lines = try scratch.alloc(Written, edits.len);
    // How far the edits before this one moved its start.
    var moved: i64 = 0;
    for (edits, lines) |edit, *line| {
        const start: u32 = @intCast(@as(i64, edit.span.start) + moved);
        line.* = .{ .first = lineAt(edited, start), .last = lineAt(edited, start + @as(u32, @intCast(edit.text.len))) };
        moved += @as(i64, @intCast(edit.text.len)) - @as(i64, edit.span.end - edit.span.start);
    }
    return lines;
}

/// Whether `line` is one of `written`.
fn wroteLine(written: []const Written, line: usize) bool {
    for (written) |w| if (line >= w.first and line <= w.last) return true;
    return false;
}

/// What a fix left that it must not have: an error the program did not
/// have before -- no error under its rule was reported at the line it moved
/// to -- that is the edit's own doing. Its own doing is a diagnostic loading
/// reported, since the fix left the text not lexing or parsing as before,
/// or one with a label on a line the fix wrote or removed. Any other new
/// error is the program's next mistake. Null where the fix left none.
fn gainedByFix(
    scratch: std.mem.Allocator,
    text: []const u8,
    file: FileId,
    before: []const Diagnostic,
    fix: diagnostic.Fix,
    edited: []const u8,
    again: mutate.Diagnosed,
) !?[]const u8 {
    const written = try writtenLines(scratch, edited, fix);
    for (again.sink.list.items, 0..) |d, index| {
        if (d.severity != .err) continue;
        const code = d.code orelse continue;
        const label = d.primaryLabel() orelse continue;
        if (label.file != again.file) continue;
        const line = lineAt(edited, label.span.start);
        const known = for (before) |earlier| {
            if (earlier.severity != .err or earlier.code != code) continue;
            const was = earlier.primaryLabel() orelse continue;
            if (was.file != file) continue;
            if (movedLine(text, fix, lineAt(text, was.span.start)) == line) break true;
        } else false;
        if (known) continue;
        if (index < again.loaded) return try std.fmt.allocPrint(scratch, "{s} at line {d}, which the program did not lex or parse to before: {s}", .{ code.ruleName(), line, d.message });
        for (d.labels) |l| {
            if (l.file != again.file) continue;
            const at = lineAt(edited, l.span.start);
            if (wroteLine(written, at)) return try std.fmt.allocPrint(scratch, "{s} at line {d}, pointing at line {d}, which the fix wrote: {s}", .{ code.ruleName(), line, at, d.message });
        }
    }
    return null;
}

/// How many cases carried a fix of each kind, for the floors: a kind no case
/// carries is a help that stopped writing its fix.
pub const FixKinds = std.EnumMap(diagnostic.FixKind, u32);

/// Property `help_edits`: every fix a diagnostic of the case carries,
/// applied alone to `text`, the case's one file, must leave no error under
/// that diagnostic's rule at its line, and no error `gainedByFix` reports.
/// Then the fixes are followed in turn, the first one each round, until no
/// error carries one: each fix is held to the same, an error a fix answered
/// must not come back at its line, whichever later fix brings it back, and
/// the fixes must run out within `help_edit_rounds`. A new error elsewhere
/// is the program's next mistake. The kinds of fix the case's diagnostics
/// carried, empty where none did.
///
/// **Bound:** one compilation per fix the case's diagnostics carry, and one
/// per round, at most `help_edit_rounds`.
fn checkHelpEdits(
    gpa: std.mem.Allocator,
    failures: *std.ArrayList(Failure),
    display_path: []const u8,
    reported: []const Diagnostic,
    file: FileId,
    text: []const u8,
    kind: ProgramKind,
) !std.EnumSet(diagnostic.FixKind) {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const scratch = arena.allocator();
    var carried: std.EnumSet(diagnostic.FixKind) = .initEmpty();

    // Each fix alone.
    for (reported) |d| {
        if (d.severity != .err) continue;
        const code = d.code orelse continue;
        const label = d.primaryLabel() orelse continue;
        if (label.file != file) continue;
        for (d.fixes) |fix| {
            carried.insert(fix.kind);
            const help = if (fix.note) |at| d.notes[at] else label.message;
            const failure: ?[]const u8 = switch (try applyFix(scratch, text, file, fix)) {
                .refused => |why| why,
                .text => |edited| failure: {
                    const again = try mutate.diagnose(scratch, edited, kind);
                    const line = movedLine(text, fix, lineAt(text, label.span.start));
                    if (errorAtLine(again.sink.list.items, again.file, edited, code, line)) |left|
                        break :failure try std.fmt.allocPrint(scratch, "{s} at line {d} is still reported: {s}", .{ code.ruleName(), line, left.message });
                    break :failure try gainedByFix(scratch, text, file, reported, fix, edited, again);
                },
            };
            if (failure) |what| try failures.append(gpa, .{
                .path = display_path,
                .what = "a help's edit, applied, leaves the error it was written for or one of its own",
                .expected = try std.fmt.allocPrint(gpa, "no {s} at line {d}, and no error the edit made, after writing {s}, as the help \"{s}\" says", .{ code.ruleName(), lineAt(text, label.span.start), try fixText(scratch, fix), help }),
                .actual = try gpa.dupe(u8, what),
            });
        }
    }
    if (carried.count() == 0) return carried;

    // The fixes in turn.
    var answered: std.ArrayList(HelpAnswered) = .empty;
    var applied: std.ArrayList([]const u8) = .empty;
    var current = text;
    var current_file = file;
    var diagnostics_now: []const Diagnostic = reported;
    var round: usize = 0;
    const failure: ?[]const u8 = failure: while (true) : (round += 1) {
        for (diagnostics_now) |d| {
            if (d.severity != .err) continue;
            const code = d.code orelse continue;
            const label = d.primaryLabel() orelse continue;
            if (label.file != current_file) continue;
            const line = lineAt(current, label.span.start);
            for (answered.items) |earlier| if (earlier.code == code and earlier.line == line)
                break :failure try std.fmt.allocPrint(scratch, "{s} at line {d}, answered by an earlier fix, reported again: {s}", .{ code.ruleName(), line, d.message });
        }
        const next: Diagnostic = for (diagnostics_now) |d| {
            if (d.severity != .err or d.code == null or d.fixes.len == 0) continue;
            const label = d.primaryLabel() orelse continue;
            if (label.file != current_file) continue;
            break d;
        } else break null;
        if (round >= help_edit_rounds) break try std.fmt.allocPrint(scratch, "helps still offer edits after {d}", .{help_edit_rounds});
        const fix = next.fixes[0];
        const edited = switch (try applyFix(scratch, current, current_file, fix)) {
            .refused => |why| break why,
            .text => |t| t,
        };
        for (answered.items) |*earlier| earlier.line = movedLine(current, fix, earlier.line);
        try answered.append(scratch, .{ .code = next.code.?, .line = movedLine(current, fix, lineAt(current, next.primaryLabel().?.span.start)) });
        try applied.append(scratch, try fixText(scratch, fix));
        const again = try mutate.diagnose(scratch, edited, kind);
        if (try gainedByFix(scratch, current, current_file, diagnostics_now, fix, edited, again)) |what| break what;
        current = edited;
        current_file = again.file;
        diagnostics_now = again.sink.list.items;
    };
    if (failure) |what| {
        var edits: std.ArrayList(u8) = .empty;
        for (applied.items, 0..) |t, i| try edits.print(gpa, "{s}{s}", .{ if (i == 0) "" else ", then ", t });
        try failures.append(gpa, .{
            .path = display_path,
            .what = "a help's edit, applied, leaves the error it was written for or one of its own",
            .expected = try std.fmt.allocPrint(gpa, "each error a help's fix answers gone for good, and no error an edit made, after writing {s}", .{edits.items}),
            .actual = try gpa.dupe(u8, what),
        });
    }
    return carried;
}

/// The line, counted from 1, that byte `offset` of `text` sits on.
fn lineAt(text: []const u8, offset: u32) usize {
    return std.mem.count(u8, text[0..@min(offset, text.len)], "\n") + 1;
}

/// One program the run has already built and run./// One program the run has already built and run.
///
/// What a property needs to compare a second build against the first: where the
/// intermediates go, how the case is named to a reader, and what the program
/// answered. `Checked` is this plus the text and the tree a rewrite slices,
/// which a change made below the source has no use for -- and a module of
/// several files has no one tree to hand over.
const Built = struct {
    display_path: []const u8,
    name: []const u8,
    answer: []const u8,
    /// What it said on standard error, which a change below the source has as
    /// much reason to preserve as what it printed.
    errors: []const u8 = "",
    /// The C driver the case is reached through, where it has one.
    ///
    /// A damaged module is built and run the way the case was, and for a
    /// library that means through its caller: built without one there is no
    /// entry point to link, and the link failure would be reported as the
    /// damage having changed what the program does -- a disagreement invented
    /// by the property rather than found by it.
    foreign: Foreign = .{},
};

test "lowered modules release literal bytes and functions on allocation failure" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    var table: FileTable = .empty;
    var interner: Interner = .empty;
    var sink = Sink.init(gpa);
    var program = try loadFromMemory(
        gpa,
        &table,
        &sink,
        &interner,
        "main.lin",
        &.{.{ .path = "main.lin", .text = "fn main() -> UInt8 { let _text = \"kept bytes\"; 0 }\n" }},
        .program,
        true,
        .borrow,
    );
    var semantics = try checkProgram(gpa, testing.allocator, &program, &interner, &sink, .program);
    defer semantics.deinit(gpa);

    try testing.expect(!sink.hasErrors());

    const AllocationCase = struct {
        fn run(allocator: std.mem.Allocator, checked: *const loader.Semantics, diagnostics: *Sink) !void {
            var module = (try lower(
                allocator,
                &checked.expanded,
                &checked.res,
                &checked.typing,
                &checked.disposals,
                diagnostics,
                .program,
            )) orelse return error.SourceRejected;
            defer module.deinit(allocator);
            try testing.expectEqual(@as(usize, 1), module.bytes.len);
            try testing.expectEqualStrings("kept bytes", module.bytes[0]);
        }
    };
    // Exercise ownership transfers even on allocators that cannot shrink in
    // place: toOwnedSlice must allocate its final-sized buffer on that path.
    // The allocator beneath still refuses a double or mismatched free and
    // reports a leak, but records no stack trace per allocation: over
    // thousands of failure points, recording them is most of the cost.
    var checking: std.heap.DebugAllocator(.{ .stack_trace_frames = 0 }) = .init;
    defer if (checking.deinit() == .leak) @panic("the lowering leaked");
    var moving = testing.FailingAllocator.init(checking.allocator(), .{ .resize_fail_index = 0 });
    try testing.checkAllAllocationFailures(moving.allocator(), AllocationCase.run, .{ &semantics, &sink });
}

test "generated entry mutations are rejected by their declared rule" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    const text = "fn main() -> UInt8 { 0 }\n";
    const source: Source = .{ .path = "generated.lin", .text = text };
    var sink = Sink.init(gpa);
    var interner: Interner = .empty;
    const tokens = try tokenize(gpa, &source, .from(0), &sink, &interner);
    var ast = try parse(gpa, &source, .from(0), tokens, &sink);
    var res = try resolveTree(gpa, &ast, &sink);
    var typing = try typecheckTree(gpa, &res, &sink);
    try testing.expect(!sink.hasErrors());
    var failures: std.ArrayList(Failure) = .empty;
    var mutations: std.EnumMap(Mutation, u32) = .{};

    try checkMutations(gpa, &failures, &mutations, source.path, &ast, &res.resolution, &typing, text, .program);
    try testing.expectEqual(@as(?u32, 1), mutations.get(.wrong_entry_type));
    try testing.expectEqual(@as(usize, 0), failures.items.len);
}

test "dump mono renders generated members from expanded syntax" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const text =
        \\struct Mark {}
        \\
        \\trait Structural {
        \\    fn value(self: Self) -> UInt8
        \\}
        \\
        \\template impl Structural {
        \\    fn value(_self: Self) -> UInt8 { 7 }
        \\}
        \\
        \\derive Structural for Mark
        \\
        \\fn main() -> UInt8 {
        \\    let mark: Mark = .{}
        \\    mark.value()
        \\}
    ;
    var table: FileTable = .empty;
    var interner: Interner = .empty;
    var sink = Sink.init(gpa);
    var program = try loadFromMemory(
        gpa,
        &table,
        &sink,
        &interner,
        "main.lin",
        &.{.{ .path = "main.lin", .text = text }},
        .program,
        true,
        .borrow,
    );
    var semantics = try checkProgram(gpa, testing.allocator, &program, &interner, &sink, .program);
    defer semantics.deinit(gpa);
    var module = (try lower(gpa, &semantics.expanded, &semantics.res, &semantics.typing, &semantics.disposals, &sink, .program)) orelse return error.SourceRejected;
    defer module.deinit(gpa);

    var out: std.Io.Writer.Allocating = .init(gpa);
    try annotated.dumpMono(gpa, &out.writer, &semantics.expanded, &semantics.typing, &module);
    try testing.expect(std.mem.indexOf(u8, out.written(), "Structural.value") != null);
}

/// Whether anything the sink holds is the verifier speaking.
///
/// A violation carries no rule code -- no program can provoke one -- so what
/// identifies it is what it says it is. Asked because `emit` writing nothing is
/// the answer this property reads, and a backend that refused for some other
/// reason would be answering a different question.
fn saidDefect(sink: *const Sink) bool {
    for (sink.items()) |d| {
        if (std.mem.indexOf(u8, d.message, "compiler defect") != null) return true;
    }
    return false;
}

/// Property: a change to a module that changes what the program does is not
/// emitted in silence.
///
/// The direction the source mutations cannot reach. A mutation is refused by a
/// rule, and every module arriving at the backend has already satisfied every
/// rule the language states -- so what is left is a question only the verifier
/// answers, and asking it to adjudicate its own answer proves nothing. This is
/// what the corpus has instead: the damaged module is handed to the same
/// backend, and where the backend emitted it anyway the machine says whether
/// the silence cost anything.
///
/// Silence over an inert change is correct and is not reported. What is
/// reported is silence over a change the program noticed.
fn checkDamage(
    gpa: std.mem.Allocator,
    io: std.Io,
    cache: *const OutcomeCache,
    env: Env,
    failures: *std.ArrayList(Failure),
    damages: *std.EnumMap(Damage, u32),
    table: *FileTable,
    from: *const ExpandedProgram,
    res: *const Resolution,
    typing: *const Typing,
    disposals: *const DisposalPlan,
    program: Built,
) !void {
    // Lower a private module once. Each damage restores its changed value,
    // leaving every following oracle the same undamaged representation.
    var baseline = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer baseline.deinit();
    var lowering_sink = Sink.init(baseline.allocator());
    var module = (try lower(baseline.allocator(), from, res, typing, disposals, &lowering_sink, .program)) orelse return error.SourceRejected;
    if (lowering_sink.hasErrors()) return;

    // Emission and native-run scratch is released between damage checks.
    var per_damage = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer per_damage.deinit();
    const scratch = per_damage.allocator();
    var retained_upto = failures.items.len;

    for (std.enums.values(Damage)) |d| {
        // Taken at the top, so every `continue` below reaches it. Into `gpa`,
        // never this loop's own arena: the copy is what survives the reset on
        // the next line.
        try retainFrom(gpa, failures, retained_upto);
        retained_upto = failures.items.len;
        _ = per_damage.reset(.{ .retain_with_limit = 4 << 20 });

        // A sink of its own. What the verifier says about a module built to be
        // wrong is not part of what the case reports, and the case's own sink
        // is what a `.stderr` golden is rendered from.
        var sink = Sink.init(scratch);
        const undo = d.apply(&module) orelse continue;
        defer undo.restore();
        damages.put(d, (damages.get(d) orelse 0) + 1);

        // `emit` verifies first and writes nothing if the module fails, so this
        // call is how the verifier answers -- there is no second entry point
        // that skips it, and there must not be one.
        var ir: std.Io.Writer.Allocating = .init(scratch);
        if (!try emitMlir(scratch, &ir.writer, &module, table, &sink)) {
            if (saidDefect(&sink)) continue;

            var why: std.Io.Writer.Allocating = .init(scratch);
            try render.renderAll(&why.writer, table, &sink, .{ .color = .never });
            try failures.append(gpa, .{
                .path = program.display_path,
                .what = d.why(),
                .expected = "a compiler defect, named as one",
                .actual = why.written(),
            });
            continue;
        }

        if (d.oracle() == .must_refuse) {
            try failures.append(gpa, .{
                .path = program.display_path,
                .what = d.why(),
                .expected = "a compiler defect, named as one",
                .actual = "the damaged representation was emitted",
            });
            continue;
        }

        // Emitted in silence. Whether that was harmless is now the machine's
        // question rather than anyone's opinion.
        const ran = try outcomeOf(
            scratch,
            io,
            cache,
            env.buildRunOptions(
                try std.mem.concat(scratch, u8, &.{ program.name, ".", @tagName(d) }),
                ir.written(),
                program.foreign,
            ),
        );

        // A tool failure here is not a tool that is missing: this case built
        // and ran a moment ago with the same toolchain, so what the tool
        // refused is the damaged code -- which the verifier should have refused
        // first.
        if (ran.tool_failed) {
            try failures.append(gpa, .{
                .path = program.display_path,
                .what = d.why(),
                .expected = "a module the toolchain would take, or one the verifier refused",
                .actual = ran.text,
            });
            continue;
        }

        if (!std.mem.eql(u8, answerOf(program.answer), answerOf(ran.text))) {
            try failures.append(gpa, .{
                .path = program.display_path,
                .what = d.why(),
                .expected = answerOf(program.answer),
                .actual = answerOf(ran.text),
            });
        }

        // What the program said, on the same terms: a damaged module that
        // changed which bytes reach a programmer changed what the program does,
        // whatever status it went on to answer with.
        if (!std.mem.eql(u8, saidOf(program.answer, program.errors), saidOf(ran.text, ran.errors))) {
            try failures.append(gpa, .{
                .path = program.display_path,
                .what = d.why(),
                .expected = saidOf(program.answer, program.errors),
                .actual = saidOf(ran.text, ran.errors),
            });
        }
    }

    try retainFrom(gpa, failures, retained_upto);
}

/// Copies the strings of every failure recorded since `from` into `keep`.
///
/// A property that releases the arena it worked in has to take its record out
/// first: a `Failure` is four slices, and every one of them points at bytes
/// the reset is about to hand back. Copying by index rather than at each site
/// keeps it correct for the helpers that record without being told where the
/// memory came from.
fn retainFrom(keep: std.mem.Allocator, failures: *std.ArrayList(Failure), from: usize) !void {
    for (failures.items[from..]) |*f| {
        f.path = try keep.dupe(u8, f.path);
        f.what = try keep.dupe(u8, f.what);
        f.expected = try keep.dupe(u8, f.expected);
        f.actual = try keep.dupe(u8, f.actual);
    }
}

/// Recompiles one program after replacing every admitted primary-root derive
/// with the immutable ordinary source file expansion produced for it.
fn checkMaterializedDerives(
    gpa: std.mem.Allocator,
    scratch_parent: std.mem.Allocator,
    io: std.Io,
    cache: *const OutcomeCache,
    env: Env,
    failures: *std.ArrayList(Failure),
    count: *u32,
    display_path: []const u8,
    name: []const u8,
    program: *const Program,
    expanded: *const ExpandedProgram,
    resolution: *const Resolution,
    original_ir: []const u8,
    original_answer: []const u8,
    original_output: []const u8,
    original_errors: []const u8,
    /// The manifest and data files the case carries, as `besideOf` gives them.
    beside: []const loader.InMemoryFile,
    foreign: Foreign,
) !void {
    var materialized = (try transform_mod.materializeDerives(gpa, program, expanded, resolution)) orelse return;
    defer materialized.deinit(gpa);

    var files: std.ArrayList(loader.InMemoryFile) = .empty;
    try files.appendSlice(gpa, materialized.files);
    try files.appendSlice(gpa, beside);

    var table: FileTable = .empty;
    var sink = Sink.init(gpa);
    var interner: Interner = .empty;
    const root = program.root().dir;
    var loaded = try loadFromMemory(gpa, &table, &sink, &interner, root, files.items, .program, true, .borrow);
    try table.buildMaps(gpa);
    var settled = try checkProgram(gpa, scratch_parent, &loaded, &interner, &sink, .program);
    defer settled.deinit(gpa);

    if (sink.hasErrors()) {
        var why: std.Io.Writer.Allocating = .init(gpa);
        try render.renderAll(&why.writer, &table, &sink, .{ .color = .never });
        try failures.append(gpa, .{
            .path = display_path,
            .what = "derives replaced by ordinary source",
            .expected = "the same program, accepted",
            .actual = why.written(),
        });
        return;
    }

    const mir = (try lower(gpa, &settled.expanded, &settled.res, &settled.typing, &settled.disposals, &sink, .program)) orelse return error.SourceRejected;
    var ir: std.Io.Writer.Allocating = .init(gpa);
    if (!try emitOrRecord(gpa, failures, &ir, &mir, &table, &sink, display_path)) return;
    if (!try sameCodeIgnoringFunctionOrder(gpa, original_ir, ir.written())) {
        try failures.append(gpa, .{
            .path = display_path,
            .what = "derives replaced by ordinary source",
            .expected = original_ir,
            .actual = ir.written(),
        });
        return;
    }

    const ran = try outcomeOf(gpa, io, cache, env.buildRunOptions(
        try std.mem.concat(gpa, u8, &.{ name, ".materialized-derives" }),
        ir.written(),
        foreign,
    ));
    if (ran.tool_failed or ran.timed_out) {
        if (!ran.tool_missing) try failures.append(gpa, .{
            .path = display_path,
            .what = "derives replaced by ordinary source did not run",
            .expected = "the original program's outcome",
            .actual = ran.text,
        });
        return;
    }

    count.* += 1;
    if (!std.mem.eql(u8, answerOf(original_answer), answerOf(ran.text))) {
        try failures.append(gpa, .{
            .path = display_path,
            .what = "derives replaced by ordinary source",
            .expected = answerOf(original_answer),
            .actual = answerOf(ran.text),
        });
    }
    if (!std.mem.eql(u8, original_output, ran.output)) {
        try failures.append(gpa, .{
            .path = display_path,
            .what = "derives replaced by ordinary source output",
            .expected = original_output,
            .actual = ran.output,
        });
    }
    if (!std.mem.eql(u8, saidOf(original_answer, original_errors), saidOf(ran.text, ran.errors))) {
        try failures.append(gpa, .{
            .path = display_path,
            .what = "derives replaced by ordinary source stderr",
            .expected = saidOf(original_answer, original_errors),
            .actual = saidOf(ran.text, ran.errors),
        });
    }
}

/// Runs one case under every rewrite of its source that cannot change what it
/// means, and answers whether any of them reached it.
///
/// A transform declines a source it has nothing to move, so a program of one
/// declaration and no binding is compared against nothing here. The caller is
/// what knows whether that matters -- which goldens the case records is what
/// says how much of the case this property is the only comparison of.
fn checkRewrites(
    gpa: std.mem.Allocator,
    io: std.Io,
    cache: *const OutcomeCache,
    env: Env,
    failures: *std.ArrayList(Failure),
    rewrites: *std.EnumMap(Transform, u32),
    program: Checked,
) !bool {
    // The tree handed in is of this file alone, for the reason every property
    // that slices its text needs one: a span from the compilation's tree
    // indexes bytes this rewrite is not holding.
    // One transform's compilation, released before the next is built. A case
    // is rewritten once per transform and each rewrite loads, checks, lowers
    // and emits a whole program; holding all of them made a single case cost
    // the sum rather than the largest, which is most of what a walker held.
    var per_rewrite = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer per_rewrite.deinit();
    const scratch = per_rewrite.allocator();
    var retained_upto = failures.items.len;
    var reached = false;

    for (std.enums.values(Transform)) |t| {
        // Taken at the top rather than the bottom, so every `continue` below
        // reaches it. What the last transform recorded is copied out first,
        // because it names bytes in the arena the next line releases.
        try retainFrom(gpa, failures, retained_upto);
        retained_upto = failures.items.len;
        _ = per_rewrite.reset(.{ .retain_with_limit = 4 << 20 });

        const rewritten = (try t.apply(
            scratch,
            program.ast,
            program.res,
            program.typing,
            program.semantics,
            program.source.text,
        )) orelse continue;
        const variant: Source = .{ .path = program.display_path, .text = rewritten };

        var table: FileTable = .empty;
        var sink = Sink.init(scratch);
        var interner: Interner = .empty;

        // Loaded rather than parsed, so the rewrite is compiled the way the
        // case was: a program that names the prelude has to still name it.
        // The file's own path, not the case's display name: a case that is a
        // directory is displayed as one, and the loader reads a module out of
        // `.lin` files rather than out of whatever the case is called.
        var one: std.ArrayList(loader.InMemoryFile) = .empty;
        try one.append(scratch, .{ .path = program.source.path, .text = variant.text });
        try one.appendSlice(scratch, program.beside);
        var loaded = try loadFromMemory(scratch, &table, &sink, &interner, program.source.path, one.items, .program, true, .borrow);
        try table.buildMaps(scratch);
        var settled = try checkProgram(scratch, per_rewrite.child_allocator, &loaded, &interner, &sink, .program);
        defer settled.deinit(scratch);
        const res = &settled.res;
        const disposals = &settled.disposals;
        const typing = &settled.typing;

        // A rewrite the compiler rejects is a failure of the compiler, not of
        // the program: nothing in the rewrite changed what the program says.
        if (sink.hasErrors()) {
            var why: std.Io.Writer.Allocating = .init(scratch);
            try render.renderAll(&why.writer, &table, &sink, .{ .color = .never });
            try failures.append(gpa, .{
                .path = program.display_path,
                .what = t.why(),
                .expected = "the same program, accepted",
                .actual = why.written(),
            });
            continue;
        }

        const mir = (try lower(scratch, &settled.expanded, res, typing, disposals, &sink, .program)) orelse return error.SourceRejected;
        var ir: std.Io.Writer.Allocating = .init(scratch);
        if (!try emitOrRecord(gpa, failures, &ir, &mir, &table, &sink, program.display_path)) continue;

        // Writing an operator out as what it is defined to be must reach the
        // same code, not merely the same answer: the semantics says `is`, and
        // two lowerings that agree only on what they compute would leave that
        // unchecked.
        //
        // Permuting a call's named arguments is held to the same standard, and
        // for the same reason: [T-Call] says the arguments evaluate in the
        // callee's parameter order whatever order the call spells them, so the
        // two spellings are one program rather than two that agree. Comparing
        // answers alone leaves that unchecked wherever the arithmetic happens
        // to commute -- `add(a: 40, b: 2)` answers 42 under a lowering that
        // reads written order too.
        //
        // Tighter than the rule strictly demands, deliberately. A lowering
        // that reordered two arguments it had proved unobservable would be
        // within [T-Call] and would fail here. That trade is right because
        // declaration order is a *stated* rule and not an implementation
        // detail: the day a lowering wants to depart from it, the departure is
        // what should be argued for, and this is what makes it be argued.
        const held_to_the_code = t == .desugared_logic or
            t == .postfix_written_out or
            t == .defer_let_written_out or
            t == .permuted_named_arguments;
        if (held_to_the_code and !sameCode(program.ir, ir.written())) {
            try failures.append(gpa, .{
                .path = program.display_path,
                .what = t.why(),
                .expected = program.ir,
                .actual = ir.written(),
            });
            continue;
        }

        if (!try compareRewrittenRun(gpa, scratch, io, cache, env, failures, .{
            .display_path = program.display_path,
            .name = program.name,
            .answer = program.answer,
            .output = program.output,
            .errors = program.errors,
            .foreign = program.foreign,
        }, @tagName(t), t.why(), ir.written())) continue;
        rewrites.put(t, (rewrites.get(t) orelse 0) + 1);
        reached = true;
    }

    try retainFrom(gpa, failures, retained_upto);
    return reached;
}

/// What an original program answered, for a rewrite of it to answer alike.
const RanAs = struct {
    display_path: []const u8,
    /// What intermediates for this program are called; a rewrite's are this
    /// with its own suffix.
    name: []const u8,
    answer: []const u8,
    output: []const u8 = "",
    errors: []const u8 = "",
    foreign: Foreign = .{},
};

/// Builds and runs `ir`, a rewrite of `program`, and records every stream it
/// answers differently on. Answers whether the rewrite ran: a toolchain that
/// did not says nothing about the rewrite, and one that refused it is recorded.
fn compareRewrittenRun(
    gpa: std.mem.Allocator,
    scratch: std.mem.Allocator,
    io: std.Io,
    cache: *const OutcomeCache,
    env: Env,
    failures: *std.ArrayList(Failure),
    program: RanAs,
    suffix: []const u8,
    why: []const u8,
    ir: []const u8,
) !bool {
    const ran = try outcomeOf(
        scratch,
        io,
        cache,
        env.buildRunOptions(
            try std.mem.concat(scratch, u8, &.{ program.name, ".", suffix }),
            ir,
            program.foreign,
        ),
    );
    if (ran.timed_out) {
        try failures.append(gpa, .{
            .path = program.display_path,
            .what = "did not finish once rewritten",
            .expected = "a program that stops",
            .actual = ran.text,
        });
        return false;
    }
    if (ran.tool_failed) {
        // A missing tool says nothing about the rewrite. A tool that ran
        // and refused does: this case built a moment ago with the same
        // toolchain, so what it refused is the rewritten module -- an
        // emitter defect the rewrite exposed.
        if (!ran.tool_missing) {
            try failures.append(gpa, .{
                .path = program.display_path,
                .what = "the toolchain refused the rewritten module",
                .expected = "a module the toolchain takes, as it took this case's",
                .actual = ran.text,
            });
        }
        return false;
    }

    // What the program answered, and not where a trap said it happened --
    // the rewrite moves the lines, and the location is not the answer.
    if (!std.mem.eql(u8, answerOf(program.answer), answerOf(ran.text))) {
        try failures.append(gpa, .{
            .path = program.display_path,
            .what = why,
            .expected = answerOf(program.answer),
            .actual = answerOf(ran.text),
        });
    }

    // And what it said, in full: output carries no position, so unlike a
    // trap there is nothing here a rewrite is allowed to move. A status is
    // one byte and a render is the bytes that matter, so this is where a
    // rewrite that reorders what a program prints would show up.
    if (!std.mem.eql(u8, program.output, ran.output)) {
        try failures.append(gpa, .{
            .path = program.display_path,
            .what = why,
            .expected = program.output,
            .actual = ran.output,
        });
    }

    // And the other stream, which is the whole of what a program says when
    // it says it to a programmer rather than to whatever reads its output.
    // Left uncompared, a case whose only observation is what it said would
    // be rewritten against nothing but its status -- which a program that
    // says nothing at all answers with too.
    if (!std.mem.eql(u8, saidOf(program.answer, program.errors), saidOf(ran.text, ran.errors))) {
        try failures.append(gpa, .{
            .path = program.display_path,
            .what = why,
            .expected = saidOf(program.answer, program.errors),
            .actual = saidOf(ran.text, ran.errors),
        });
    }
    return true;
}

/// The rules a compilation's errors and warnings name, sorted, one per line.
///
/// What two compilations of one program are compared by where each refused it:
/// the rules and not where they point, because a rewrite moves the text a span
/// indexes, and not the message, which quotes what the rewrite spelled.
fn rulesNamedBy(gpa: std.mem.Allocator, sink: *const Sink) ![]const u8 {
    var names: std.ArrayList([]const u8) = .empty;
    defer names.deinit(gpa);
    for (sink.items()) |d| {
        if (d.severity == .note) continue;
        try names.append(gpa, if (d.code) |c| c.ruleName() else "(no rule)");
    }
    std.mem.sort([]const u8, names.items, {}, struct {
        fn before(_: void, a: []const u8, b: []const u8) bool {
            return std.mem.lessThan(u8, a, b);
        }
    }.before);
    var out: std.Io.Writer.Allocating = .init(gpa);
    for (names.items) |n| try out.writer.print("{s}\n", .{n});
    return out.written();
}

test "the rules a compilation names are listed apart from where they point" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    var sink = Sink.init(gpa);
    try testing.expectEqualStrings("", try rulesNamedBy(gpa, &sink));
    try sink.addError(.o_move, .from(0), .{ .start = 9, .end = 10 }, "moved", "here");
    try sink.addNote(.o_move, .from(0), .{ .start = 1, .end = 2 }, "noted", "here");
    try sink.addError(.o_borrow, .from(0), .{ .start = 1, .end = 2 }, "borrowed", "here");
    try testing.expectEqualStrings("O-Borrow\nO-Move\n", try rulesNamedBy(gpa, &sink));
}

/// A program as its own compilation answered it, for the walks in it written
/// out as the loops they stand for.
const WalkSubject = struct {
    display_path: []const u8,
    /// What the loader is pointed at: the file, or the module's directory.
    entry: []const u8,
    /// The program's own source files, each rewritten on its own.
    files: []const loader.InMemoryFile,
    /// The file each of `files` is in `semantics`, where it was loaded.
    file_ids: []const ?FileId,
    /// The manifest and data files the case carries, as `besideOf` gives them.
    beside: []const loader.InMemoryFile = &.{},
    /// What the original compilation settled; its `file` is set per rewrite.
    semantics: TransformSemantics,
    /// `rulesNamedBy` of the original compilation, through lowering.
    rules: []const u8,
    /// What the program answered, where it was built and run.
    ran: ?struct { env: Env, answered: RanAs } = null,
};

/// Property: every walk answers as the loop it stands for.
///
/// Each file's walks are written out as their loops, one file at a time, and
/// the program with that file rewritten is compiled as the case was. It must be refused by the rules the original was
/// refused by, or accepted where the original was; and where the original was
/// built and run, the rewrite must run to the same answer, output and errors.
///
/// Refused programs are compared as well as accepted ones, in both
/// directions. A walk the ownership pass lets through while its loop is
/// refused is a program reading storage the language promised it could not; a
/// walk refused while its loop is accepted is a rule the walk applies and the
/// loop does not. Rules are compared by name, since the rewrite moves what
/// every span points at.
///
/// Answers whether any file held a walk this could write out.
fn checkWalkLoops(
    gpa: std.mem.Allocator,
    io: std.Io,
    cache: *const OutcomeCache,
    checked_library: ?*const loader.CheckedLibrary,
    failures: *std.ArrayList(Failure),
    subject: WalkSubject,
) !bool {
    // One rewrite's compilation, released before the next one's.
    var per_rewrite = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer per_rewrite.deinit();
    var claimed = false;
    for (subject.files, subject.file_ids, 0..) |file, file_id, k| {
        const id = file_id orelse continue;
        _ = per_rewrite.reset(.retain_capacity);
        const retained_upto = failures.items.len;
        var semantics = subject.semantics;
        semantics.file = id;
        if (try compareWalkLoops(gpa, per_rewrite.allocator(), io, cache, checked_library, failures, subject, semantics, k, file)) claimed = true;
        try retainFrom(gpa, failures, retained_upto);
    }
    return claimed;
}

fn compareWalkLoops(
    gpa: std.mem.Allocator,
    scratch: std.mem.Allocator,
    io: std.Io,
    cache: *const OutcomeCache,
    checked_library: ?*const loader.CheckedLibrary,
    failures: *std.ArrayList(Failure),
    subject: WalkSubject,
    semantics: TransformSemantics,
    /// Which of the subject's files is rewritten.
    k: usize,
    file: loader.InMemoryFile,
) !bool {
    const why = "every walk written out as the loop it stands for";
    const rewritten = (try walk_loops.writeOut(scratch, semantics, file.text)) orelse return false;

    var inputs: std.ArrayList(loader.InMemoryFile) = .empty;
    for (subject.files, 0..) |other, j| try inputs.append(scratch, if (j == k) .{ .path = other.path, .text = rewritten } else other);
    try inputs.appendSlice(scratch, subject.beside);
    const loaded = try generate.checkLoaded(scratch, subject.entry, inputs.items, checked_library);
    const table = &loaded.table;
    const sink = &loaded.sink;
    const settled = &loaded.semantics;
    const mir = if (sink.hasErrors())
        null
    else
        try lower(scratch, &settled.expanded, &settled.res, &settled.typing, &settled.disposals, sink, .program);

    const rules = try rulesNamedBy(scratch, sink);
    if (!std.mem.eql(u8, subject.rules, rules)) {
        var said: std.Io.Writer.Allocating = .init(scratch);
        try render.renderAll(&said.writer, table, sink, .{ .color = .never });
        try failures.append(gpa, .{
            .path = subject.display_path,
            .what = try std.fmt.allocPrint(scratch, "{s}, is answered by other rules", .{why}),
            .expected = if (subject.rules.len == 0) "accepted" else subject.rules,
            .actual = try std.fmt.allocPrint(scratch, "{s}\n{s}\n--- {s} as compared ---\n{s}", .{
                if (rules.len == 0) "accepted" else rules,
                said.written(),
                file.path,
                rewritten,
            }),
        });
        return true;
    }

    const run = subject.ran orelse return true;
    const module = mir orelse return true;
    if (sink.hasErrors()) return true;
    var ir: std.Io.Writer.Allocating = .init(scratch);
    if (!try emitOrRecord(gpa, failures, &ir, &module, table, sink, subject.display_path)) return true;
    const suffix = try std.fmt.allocPrint(scratch, "walks{d}", .{k});
    _ = try compareRewrittenRun(gpa, scratch, io, cache, run.env, failures, run.answered, suffix, why, ir.written());
    return true;
}

/// One file, parsed and resolved on its own.
///
/// A span is an offset into the file that produced it, so a property that
/// slices one file's text has to read a tree of that text -- not the tree of
/// the compilation, which carries the library beside the program.
const Standalone = struct {
    table: FileTable,
    ast: Ast,
    resolved: resolve_mod.ResolvedTree,
    typing: Typing,

    fn of(gpa: std.mem.Allocator, source: *const Source) !Standalone {
        var table: FileTable = .empty;
        const file = try table.add(gpa, source.*);
        try table.buildMaps(gpa);

        var sink = Sink.init(gpa);
        var interner: Interner = .empty;
        const tokens = try tokenize(gpa, source, file, &sink, &interner);
        var ast = try parse(gpa, source, file, tokens, &sink);

        // Typed as well as resolved, because a universe is computed: a
        // property asking whether a written type is Linear reads what the
        // checker settled rather than the modifier on a declaration.
        var res = try resolveTree(gpa, &ast, &sink);
        errdefer res.deinit(gpa);
        const typing = try typecheckTree(gpa, &res, &sink);
        return .{
            .table = table,
            .ast = ast,
            .resolved = res,
            .typing = typing,
        };
    }

    fn deinit(self: *Standalone, gpa: std.mem.Allocator) void {
        self.typing.deinit(gpa);
        self.resolved.deinit(gpa);
    }
};

/// What a case's program did, and whether the toolchain is what said so.
///
/// A toolchain that did not run says nothing about the program, so what it
/// reported must never become an expectation. Accepting one would retire the
/// case: every later run would compare one toolchain failure against another
/// and agree.
const Ran = struct {
    text: []const u8,
    /// What the program wrote to standard output.
    ///
    /// Kept apart from `text` rather than folded into it, because they are
    /// compared against different goldens and one of them existing is not a
    /// reason to record the other. A program that says nothing records an
    /// empty one, which is not the same as a case that does not ask.
    output: []const u8 = "",
    /// What the program wrote to standard error, on the same terms.
    ///
    /// A stream of its own rather than a share of `output`, because a program
    /// says different things on each and the descriptor it reached is what a
    /// case about a debugging aid is asserting.
    errors: []const u8 = "",
    tool_failed: bool,
    /// Whether the tool that failed could not be started at all. A missing
    /// tool says nothing about the program, so a caller may skip it; a tool
    /// that ran and refused is judging the emitted module, and skipping that
    /// is skipping a defect.
    tool_missing: bool = false,
    /// Whether the program was still running when the runner gave up. Held
    /// apart from a broken tool: a missing `mlir-opt` says nothing about the
    /// program and is skipped, while a program that never finished is the
    /// answer -- and the rewrites and the generated programs, which are where
    /// a non-terminating one comes from, were skipping it too.
    timed_out: bool = false,
};

fn outcomeOf(
    gpa: std.mem.Allocator,
    io: std.Io,
    cache: *const OutcomeCache,
    opts: BuildRunOptions,
) !Ran {
    if (try cache.lookup(gpa, io, opts.key())) |recorded| return recorded;

    const outcome = if (cache.stats) |stats| native: {
        const began = std.Io.Timestamp.now(io, .awake);
        defer {
            const elapsed = began.durationTo(std.Io.Timestamp.now(io, .awake));
            _ = stats.native_nanoseconds.fetchAdd(@intCast(elapsed.nanoseconds), .monotonic);
        }
        break :native try buildAndRun(gpa, io, opts);
    } else try buildAndRun(gpa, io, opts);
    var got: std.Io.Writer.Allocating = .init(gpa);
    var printed: []const u8 = "";
    var said: []const u8 = "";
    switch (outcome) {
        .built => |b| {
            printed = b.stdout;
            said = b.stderr;
            switch (b.outcome) {
                .exited => |code| try got.writer.print("exit {d}\n", .{code}),
                .signalled => |sig| {
                    try got.writer.writeAll(trap_answer);
                    try got.writer.writeAll(b.stderr);

                    // The runtime traps by aborting, so `SIGABRT` is the one
                    // signal a program's own code raises. Any other means
                    // something outside the program stopped it -- which is a
                    // fact about the machine and not about the module, so it
                    // is reported and not recorded, exactly as a run that
                    // never finished is.
                    //
                    // An entry keyed by the emitted IR and the toolchain
                    // answers for every later run over unchanged code, so
                    // caching one of these retires the case: a machine having
                    // a bad moment once becomes that program's outcome
                    // forever, and the trap it invents is indistinguishable
                    // from one the program means.
                    if (sig != std.posix.SIG.ABRT) return .{
                        .text = try std.fmt.allocPrint(gpa, "{s}stopped by signal {d}\n", .{ got.written(), @intFromEnum(sig) }),
                        .output = printed,
                        .errors = said,
                        .tool_failed = false,
                    };
                },
            }
        },
        .tool_failed => |f| {
            try got.writer.print("{s} failed\n{s}", .{ f.tool.command(), f.output });
            return .{ .text = got.written(), .tool_failed = true, .tool_missing = f.missing };
        },
        // Reported the way a broken tool is: not cached, and not something
        // `-Dupdate` will write down. A program that never finished has no
        // answer to record, and recording one would retire the case.
        .timed_out => {
            try got.writer.writeAll("did not finish\n");
            return .{ .text = got.written(), .tool_failed = true, .timed_out = true };
        },
    }

    var recorded: std.Io.Writer.Allocating = .init(gpa);
    try recorded.writer.print("{s}{d}\n{s}{d}\n", .{
        said_header,    said.len,
        printed_header, printed.len,
    });
    try recorded.writer.writeAll(said);
    try recorded.writer.writeAll(printed);
    try recorded.writer.writeAll(got.written());

    try cache.put(gpa, io, opts.key(), recorded.written(), opts.diagnostics);
    return .{ .text = got.written(), .output = printed, .errors = said, .tool_failed = false };
}

/// What every recorded outcome begins with, and how many bytes of standard
/// error follow the two counts.
///
/// A length rather than a delimiter, because what a program says is arbitrary
/// bytes and any delimiter is one a program could say. Both counts are written
/// before the first byte either stream produced, so nothing a program says sits
/// where a header is read.
///
/// Leading, so that telling an outcome from an entry a cache still holds that
/// counts one stream costs no reading at all: such an entry begins with the
/// count of what was printed, which is not this, so it is refused at the first
/// byte whatever the streams contain. A cache answering "said nothing" for
/// every case it already held would be a green suite over the one thing this
/// exists to check, and a discriminator that read a program's own bytes would
/// leave that turning on what the program happened to say.
const said_header = "said ";

/// How many bytes of standard output follow the bytes counted before it.
const printed_header = "printed ";

/// A recorded outcome taken apart, or `null` where the bytes are not one.
fn recordedOutcome(recorded: []const u8) ?struct {
    output: []const u8,
    errors: []const u8,
    text: []const u8,
} {
    const said_len, const after_said = countedSection(recorded, said_header) orelse return null;
    const printed_len, const body = countedSection(after_said, printed_header) orelse return null;

    if (said_len > body.len or printed_len > body.len - said_len) return null;
    return .{
        .errors = body[0..said_len],
        .output = body[said_len..][0..printed_len],
        .text = body[said_len + printed_len ..],
    };
}

/// The count one header carries, and what follows the line it sits on.
fn countedSection(recorded: []const u8, header: []const u8) ?struct { usize, []const u8 } {
    if (!std.mem.startsWith(u8, recorded, header)) return null;
    const rest = recorded[header.len..];

    const nl = std.mem.indexOfScalar(u8, rest, '\n') orelse return null;
    const len = std.fmt.parseInt(usize, rest[0..nl], 10) catch return null;
    return .{ len, rest[nl + 1 ..] };
}

test "a recorded outcome carries two streams a delimiter could not" {
    // What each stream carries includes both headers this format begins with
    // and a line that looks like the exit status. Parsed by length, all of it
    // is the program's; parsed by searching, either section would end early.
    const said = "said 4\nprinted 3\n";
    const printed = "exit 0\n";
    const recorded = "said 17\nprinted 7\n" ++ said ++ printed ++ "exit 7\n";

    const split = recordedOutcome(recorded).?;
    try testing.expectEqualStrings(said, split.errors);
    try testing.expectEqualStrings(printed, split.output);
    try testing.expectEqualStrings("exit 7\n", split.text);
}

test "an outcome recorded without both streams is not an outcome" {
    // What a cache holds from a format that counted less. Read as a program
    // that said nothing, every case asserting a stream would pass on a stale
    // entry -- so each has to read as no entry at all.
    try testing.expect(recordedOutcome("exit 0\n") == null);
    try testing.expect(recordedOutcome("trap\nsomewhere:1:1\n") == null);
    try testing.expect(recordedOutcome("printed 3\nabcexit 0\n") == null);

    // And one whose single counted stream opens with the leading header, with
    // lengths that line up under a reading that expected that header second.
    // Which count comes first is what refuses this, at the first byte and
    // without reading a stream -- so what the program said cannot decide
    // whether an entry from a format that counted less is taken for one of
    // these, and a wrong answer served from the cache is a green suite.
    try testing.expect(recordedOutcome("printed 12\nsaid 5\nhellotrap\nsomewhere:1:1\n") == null);

    // A header whose count runs past what follows it: a truncated write, which
    // is the other way a file in the cache can fail to be an outcome.
    try testing.expect(recordedOutcome("said 40\nprinted 0\nshort\n") == null);
    try testing.expect(recordedOutcome("said 0\nprinted 40\nshort\n") == null);
}

/// The line that says what the program answered, without whatever explained it.
fn answerOf(text: []const u8) []const u8 {
    const nl = std.mem.indexOfScalar(u8, text, '\n') orelse return text;
    return text[0 .. nl + 1];
}

/// What a program the machine stopped answers, ahead of the explanation.
///
/// Written and read in one place, so what the runner records for a trap and
/// what tells a trap apart afterwards cannot disagree.
const trap_answer = "trap\n";

/// What a program said on standard error, less what its answer already holds.
///
/// Standard error carries no position of its own, so every byte of it is a
/// rewrite's to preserve -- except where the machine stopped the program. The
/// runtime explains a trap by naming the source position it happened at, and
/// the runner records that same text after the answer line, where `answerOf`
/// drops it because a rewrite moves the lines. A trapping program's standard
/// error is therefore bytes the exit text already carries, and comparing it
/// here would be asking the question `answerOf` deliberately declines.
fn saidOf(answer: []const u8, errors: []const u8) []const u8 {
    return if (std.mem.startsWith(u8, answer, trap_answer)) "" else errors;
}

/// How a built case program ended.
///
/// A program killed by a signal did not choose its status, so the two outcomes
/// are kept apart rather than folded into one number.
const Outcome = union(enum) {
    exited: u8,
    signalled: std.posix.SIG,
};

const BuildRun = union(enum) {
    built: struct { outcome: Outcome, stdout: []const u8, stderr: []const u8 },
    tool_failed: toolchain.Failure,
    /// The program was still running long after any program here should be.
    timed_out: void,
};

const BuildRunOptions = struct {
    scratch: []const u8,
    name: []const u8,
    ir: []const u8,
    runtime: []const u8,
    sanitize: ?[]const u8,
    /// The C source linked against this module, where the case carries one.
    ///
    /// Its presence is what decides the shape of the build: with a driver the
    /// module is compiled to an object and the driver is what starts, which is
    /// the only arrangement that shows a library is callable from outside.
    foreign: Foreign = .{},
    /// The level `cc` compiles the module at, one of `toolchain.levels`.
    opt: []const u8 = toolchain.default_level,
    /// Where a concurrent caller retains harness diagnostics for ordered merge.
    diagnostics: ?*std.Io.Writer = null,

    fn key(self: BuildRunOptions) OutcomeKey {
        return .{ .ir = self.ir, .foreign = self.foreign, .opt = self.opt };
    }
};

/// What one outcome is filed under beside the salt: the module, the driver
/// linked against it, and the level it was compiled at. Everything a program's
/// behaviour depends on reaches its IR, the bytes of every file it embeds
/// included, so a program whose embedded file changed is a different key and
/// never reads the outcome recorded for the old bytes.
const OutcomeKey = struct {
    ir: []const u8,
    foreign: Foreign = .{},
    opt: []const u8 = toolchain.default_level,
};

test "a program is filed under the bytes it embeds" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const checked = test_library.get();
    var irs: [2][]const u8 = undefined;
    // Two files of one length, so only the bytes differ.
    for ([_][]const u8{ "first", "fresh" }, &irs) |motd, *ir| {
        var table: FileTable = .empty;
        var sink = Sink.init(a);
        var interner: Interner = .empty;
        const files = [_]InMemoryFile{
            .{ .path = "app/main.lin", .text = "fn main() -> UInt8 {\n    UInt8(embed(\"motd.txt\").length())\n}\n" },
            .{ .path = "app/motd.txt", .text = motd },
        };
        var loaded = try checked.loadFromMemory(a, &table, &sink, &interner, "app", &files, .program, .borrow);
        var settled = try checked.checkProgram(a, a, &loaded, &interner, &sink, .program);
        const module = (try lower(a, &settled.expanded, &settled.res, &settled.typing, &settled.disposals, &sink, .program)).?;
        var written: std.Io.Writer.Allocating = .init(a);
        try testing.expect(try emitMlir(a, &written.writer, &module, &table, &sink));
        ir.* = written.written();
        try testing.expect(std.mem.indexOf(u8, ir.*, motd) != null);
    }
    const cache: OutcomeCache = .{ .dir = "outcomes", .salt = 7 };
    try testing.expect(!std.mem.eql(u8, try cache.pathFor(a, .{ .ir = irs[0] }), try cache.pathFor(a, .{ .ir = irs[1] })));
}

test "one module built at two levels is filed as two outcomes" {
    const cache: OutcomeCache = .{ .dir = "outcomes", .salt = 7 };
    const at_default = try cache.pathFor(testing.allocator, .{ .ir = "module" });
    defer testing.allocator.free(at_default);
    const at_zero = try cache.pathFor(testing.allocator, .{ .ir = "module", .opt = "0" });
    defer testing.allocator.free(at_zero);
    try testing.expect(!std.mem.eql(u8, at_default, at_zero));
}

/// Every file one build of a case writes.
const BuildFiles = struct {
    executable: []const u8,
    mid: toolchain.Intermediates,
    /// The module compiled on its own, where a driver is linked against it.
    object: []const u8,
    /// The driver's source, where the case carries one.
    driver: []const u8,

    fn of(gpa: std.mem.Allocator, executable: []const u8, mid: toolchain.Intermediates) !BuildFiles {
        return .{
            .executable = executable,
            .mid = mid,
            .object = try std.fmt.allocPrint(gpa, "{s}.o", .{executable}),
            .driver = try std.fmt.allocPrint(gpa, "{s}.c", .{executable}),
        };
    }

    /// Renames each file onto its counterpart in `onto`, and removes a
    /// counterpart this build did not write, so what remains under the case's
    /// own name is one build's files to inspect.
    fn moveOnto(self: BuildFiles, io: std.Io, onto: BuildFiles) void {
        const from = [_][]const u8{ self.executable, self.mid.ir, self.mid.lowered, self.mid.assembly, self.object, self.driver };
        const to = [_][]const u8{ onto.executable, onto.mid.ir, onto.mid.lowered, onto.mid.assembly, onto.object, onto.driver };
        const cwd = std.Io.Dir.cwd();
        for (from, to) |private, public| {
            cwd.rename(private, cwd, public, io) catch |err| switch (err) {
                error.FileNotFound => cwd.deleteFile(io, public) catch {},
                else => cwd.deleteFile(io, private) catch {},
            };
        }
    }
};

/// Assembles, links and runs one case, reporting what the program did.
///
/// Intermediates go to a scratch directory rather than beside the corpus, so a
/// run leaves the checkout as it found it.
fn buildAndRun(gpa: std.mem.Allocator, io: std.Io, opts: BuildRunOptions) !BuildRun {
    // Every file of the build is private to this thread until the program has
    // run. Runners sharing a scratch directory give a case the same name, and a
    // runner built from other sources emits other IR under it, so a shared path
    // lets one runner execute what another wrote. The outcome cache then files
    // that program's answer under this IR, and every later run is served it. A
    // thread builds one program at a time, and a thread id is unique among the
    // threads alive in every process.
    const named = try std.fs.path.join(gpa, &.{ opts.scratch, opts.name });
    const exe_path = try std.fmt.allocPrint(gpa, "{s}.{d}", .{ named, std.Thread.getCurrentId() });
    const mid = try toolchain.Intermediates.of(gpa, exe_path);
    const built: BuildFiles = try .of(gpa, exe_path, mid);
    const kept: BuildFiles = try .of(gpa, named, try toolchain.Intermediates.of(gpa, named));
    defer built.moveOnto(io, kept);

    {
        const file = try std.Io.Dir.cwd().createFile(io, mid.ir, .{});
        defer file.close(io);
        var buf: [4096]u8 = undefined;
        var w = file.writer(io, &buf);
        try w.interface.writeAll(opts.ir);
        try w.interface.flush();
    }

    // The case's C files are written under a directory of this build's own,
    // at their paths in the case, so a source's `#include "x.h"` finds the
    // header beside it and the manifest's paths name them.
    const native_dir = try std.fmt.allocPrint(gpa, "{s}.c-files", .{exe_path});
    defer std.Io.Dir.cwd().deleteTree(io, native_dir) catch {};
    for (opts.foreign.native.files) |file| {
        const path = try std.fs.path.join(gpa, &.{ native_dir, file.path });
        if (std.fs.path.dirname(path)) |parent| try std.Io.Dir.cwd().createDirPath(io, parent);
        const written = try std.Io.Dir.cwd().createFile(io, path, .{});
        defer written.close(io);
        var buf: [4096]u8 = undefined;
        var w = written.writer(io, &buf);
        try w.interface.writeAll(file.text);
        try w.interface.flush();
    }
    const native_sources = try gpa.alloc([]const u8, opts.foreign.native.compile.len);
    for (opts.foreign.native.compile, 0..) |path, i| native_sources[i] = try std.fs.path.join(gpa, &.{ native_dir, path });

    // With a driver the module becomes an object rather than a program: it has
    // no entry point of its own, and what starts is the C program that calls
    // into it. The object, the driver and the runtime are then one link, which
    // is the arrangement a person linking against a published library has.
    const object_path = built.object;
    if (try toolchain.build(gpa, io, .{
        .mid = mid,
        .out_path = if (opts.foreign.driver == null) exe_path else object_path,
        .runtime_path = opts.runtime,
        .sanitize = opts.sanitize,
        .artifact = if (opts.foreign.driver == null) .executable else .object,
        .opt = opts.opt,
        .native = native_sources,
        .link = opts.foreign.native.link,
    })) |f| return .{ .tool_failed = f };

    if (opts.foreign.driver) |source| {
        const driver_path = built.driver;
        {
            const file = try std.Io.Dir.cwd().createFile(io, driver_path, .{});
            defer file.close(io);
            var buf: [4096]u8 = undefined;
            var w = file.writer(io, &buf);
            try w.interface.writeAll(source);
            try w.interface.flush();
        }

        if (try toolchain.linkDriver(gpa, io, exe_path, driver_path, object_path, opts.runtime, opts.sanitize, opts.foreign.native.link)) |f| {
            return .{ .tool_failed = f };
        }
    }

    // A generated or rewritten program that does not terminate would otherwise
    // hang the suite rather than fail it, and a hang leaves nothing to read:
    // one orphaned run of this kind burned days of CPU before anyone noticed.
    // A Linea program in this corpus finishes in milliseconds, so anything
    // still running after this is not slow, it is wrong.
    const result = hermeticRun(gpa, io, .{
        .argv = &.{exe_path},
        .timeout = .{ .duration = .{ .raw = .fromSeconds(30), .clock = .awake } },
    }) catch |err| switch (err) {
        error.Timeout => return .{ .timed_out = {} },
        else => |e| return e,
    };
    return .{ .built = .{
        .outcome = switch (result.term) {
            .exited => |code| .{ .exited = code },
            .signal, .stopped => |sig| .{ .signalled = sig },
            .unknown => .{ .signalled = @enumFromInt(0) },
        },
        .stdout = result.stdout,
        .stderr = result.stderr,
    } };
}

test "native outcome: builds sharing a scratch name each record their own program" {
    // Two runners over one scratch directory build a case under the same name,
    // and a runner built from other sources emits other IR for it. Each outcome
    // is filed under the IR its caller emitted, so it must be what that IR does.
    var directory = testing.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(testing.io, ".", testing.allocator);
    defer testing.allocator.free(root);
    const runtime = try std.fs.path.join(testing.allocator, &.{ root, "runtime.c" });
    defer testing.allocator.free(runtime);
    try writeFile(testing.io, runtime, "int native_outcome_runtime;\n");
    const cache: OutcomeCache = .{ .dir = root, .salt = 0 };

    const Build = struct {
        status: u8,
        text: []const u8 = "",
        recorded: []const u8 = "",
        failed: ?anyerror = null,

        fn run(self: *@This(), scratch: []const u8, runtime_path: []const u8, outcomes: *const OutcomeCache) void {
            self.go(scratch, runtime_path, outcomes) catch |err| {
                self.failed = err;
            };
        }

        fn go(self: *@This(), scratch: []const u8, runtime_path: []const u8, outcomes: *const OutcomeCache) !void {
            // Page-backed, so each thread allocates without a shared allocator.
            const gpa = std.heap.page_allocator;
            const ir = try std.fmt.allocPrint(gpa,
                \\module {{
                \\  func.func @main() -> i32 {{
                \\    %0 = arith.constant {d} : i32
                \\    func.return %0 : i32
                \\  }}
                \\}}
                \\
            , .{self.status});
            const ran = try outcomeOf(gpa, testing.io, outcomes, .{
                .scratch = scratch,
                .name = "shared",
                .ir = ir,
                .runtime = runtime_path,
                .sanitize = null,
            });
            self.text = ran.text;
            const recorded = (try outcomes.lookup(gpa, testing.io, .{ .ir = ir })) orelse return;
            self.recorded = recorded.text;
        }
    };

    for (0..6) |round| {
        var builds: [2]Build = .{
            .{ .status = @intCast(10 + 2 * round) },
            .{ .status = @intCast(11 + 2 * round) },
        };
        var threads: [2]std.Thread = undefined;
        for (&threads, &builds) |*thread, *build| {
            thread.* = try std.Thread.spawn(compiler_stack.spawn_config, Build.run, .{ build, root, runtime, &cache });
        }
        for (threads) |thread| thread.join();

        for (builds) |build| {
            if (build.failed) |err| return err;
            var want: [16]u8 = undefined;
            const expected = try std.fmt.bufPrint(&want, "exit {d}\n", .{build.status});
            try testing.expectEqualStrings(expected, build.text);
            try testing.expectEqualStrings(expected, build.recorded);
        }
    }
}

/// Whether lowering the named case produces the given terminator, or `null`
/// where the case could not be read at all.
///
/// A witness that cannot be read is not a witness that fails: the two are
/// reported apart, or a mistyped path reads as a false claim about the edge
/// table and sends whoever sees it to look at lowering.
const TerminatorWitnesses = std.EnumArray(Inst.Tag, bool);

fn recordTerminatorWitnesses(
    found: *TerminatorWitnesses,
    path: []const u8,
    file: FileId,
    module: *const MirModule,
) void {
    var wanted: TerminatorWitnesses = .initFill(false);
    var any = false;
    for (std.enums.values(Inst.Tag)) |tag| {
        if (!tag.isTerminator() or !std.mem.eql(u8, edges.witnessOf(tag), path)) continue;
        wanted.set(tag, true);
        any = true;
    }
    if (!any) return;
    for (module.functions) |function| {
        // Imported functions cannot supply the named source's witness.
        if (function.file != file) continue;
        for (0..function.blockCount()) |i| {
            const terminator = function.terminatorOf(@enumFromInt(@as(u32, @intCast(i))));
            if (terminator == .none) continue;
            const tag = function.tagOf(terminator);
            if (wanted.get(tag)) found.set(tag, true);
        }
    }
}

test "terminator coverage requires the named case and its own emitted body" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    const source: Source = .{ .path = "main.lin", .text = "fn main() -> UInt8 { 0 }\n" };
    var sink = Sink.init(gpa);
    var interner: Interner = .empty;
    const tokens = try tokenize(gpa, &source, .from(0), &sink, &interner);
    var ast = try parse(gpa, &source, .from(0), tokens, &sink);
    var res = try resolveTree(gpa, &ast, &sink);
    var typing = try typecheckTree(gpa, &res, &sink);
    var disposals = try checkOwnershipTree(gpa, &res, &typing, &sink);
    defer disposals.deinit(gpa);
    const module = (try lowerTree(gpa, &res, &typing, &disposals, &sink, .program)).?;
    try testing.expect(!sink.hasErrors());

    var found: TerminatorWitnesses = .initFill(false);
    recordTerminatorWitnesses(&found, "tests/codegen/another.lin", .from(0), &module);
    try testing.expect(!found.get(.ret));
    recordTerminatorWitnesses(&found, edges.witnessOf(.ret), .from(1), &module);
    try testing.expect(!found.get(.ret));
    recordTerminatorWitnesses(&found, edges.witnessOf(.branch), .from(0), &module);
    try testing.expect(!found.get(.branch));
    try testing.expect(!found.get(.ret));
    recordTerminatorWitnesses(&found, edges.witnessOf(.ret), .from(0), &module);
    try testing.expect(found.get(.ret));
    try testing.expect(!found.get(.branch));
}

/// What a case's intermediates are called, unique across the corpus.
///
/// The whole path with its separators flattened, rather than the last
/// component: twenty-six case names repeat -- `alpha`, `account`, `a` -- and a
/// scratch directory is flat, so those cases were writing over each other's
/// assembly and linking over each other's binaries. Sequentially that is
/// invisible, because each is finished with its files before the next starts.
/// Run two at once and one records the other's exit status.
///
/// A path rather than a number, because these files are read by whoever is
/// working out why a case failed, and `tests_text_a_literal_is_a_str.ssa` says
/// which case it belongs to where an ordinal would send them counting.
fn scratchName(gpa: std.mem.Allocator, stem: []const u8) ![]const u8 {
    const flat = try gpa.dupe(u8, stem);
    for (flat) |*c| {
        if (c.* == '/' or c.* == '\\') c.* = '_';
    }
    return flat;
}

/// What one emitted line carries, told apart from how it is written.
///
/// A rewrite moves the text, so anything the emission records *about the
/// source* differs while the code does not. Naming those pieces rather than
/// slicing at a delimiter is what keeps this honest as the emission grows: a
/// line whose non-semantic part this does not know about is compared whole,
/// which fails loudly rather than passing quietly.
const EmittedLine = union(enum) {
    /// A blob holding a source file's path. Nothing about it is code, and the
    /// rewritten program is compiled under another path besides.
    provenance,
    /// A constant holding the line or the column a trap reports. The name is
    /// code -- the expansion that defines it must still define it -- and the
    /// value is where it came from.
    trap: []const u8,
    /// Everything else, compared as written. A line this does not recognise
    /// is code until someone says otherwise.
    code: []const u8,

    fn of(line: []const u8) EmittedLine {
        // Every operation may end in the location of the instruction it
        // renders. The location is where the code came from, not what it is,
        // so it is cut before the line is classified -- and the path inside
        // it differs between a program and its rewritten copy for the same
        // reason provenance does.
        const body = if (std.mem.lastIndexOf(u8, line, " loc(\"")) |at| line[0..at] else line;
        const op = std.mem.trimStart(u8, body, " ");
        // Anchored to the line's start, never searched for: a string literal
        // passes user bytes into a `@linea_str` blob verbatim, so a spelling
        // merely *contained* in a line is a spelling a program can forge --
        // and a line compared as provenance is compared as nothing.
        if (std.mem.startsWith(u8, op, "llvm.mlir.global internal constant @linea_file")) return .provenance;
        if (std.mem.startsWith(u8, op, "%" ++ mlir_backend.trap_file_name) or
            std.mem.startsWith(u8, op, "%" ++ mlir_backend.panic_file_name)) return .provenance;
        // The prefixes are the emitter's own spellings, imported rather than
        // copied: the claim "these constants hold position" is the emitter's,
        // and a second spelling here would be the rule twice.
        if (std.mem.startsWith(u8, op, "%" ++ mlir_backend.trap_line_name) or
            std.mem.startsWith(u8, op, "%" ++ mlir_backend.trap_col_name))
        {
            if (std.mem.indexOf(u8, body, "= arith.constant ")) |at| return .{ .trap = body[0..at] };
        }
        return .{ .code = body };
    }

    fn same(x: EmittedLine, y: EmittedLine) bool {
        return switch (x) {
            .provenance => y == .provenance,
            .trap => |t| y == .trap and std.mem.eql(u8, t, y.trap),
            .code => |t| y == .code and std.mem.eql(u8, t, y.code),
        };
    }
};

/// Whether two emissions are the same code.
///
/// The claim is stronger than "answers the same": a construct defined as
/// another construct must reach the code that other construct reaches, so
/// this compares what was generated and not what it computed.
fn nextCode(lines: *std.mem.SplitIterator(u8, .scalar)) ?EmittedLine {
    while (lines.next()) |line| {
        const classified = EmittedLine.of(line);
        if (classified != .provenance) return classified;
    }
    return null;
}

fn sameCode(a: []const u8, b: []const u8) bool {
    var ours = std.mem.splitScalar(u8, a, '\n');
    var theirs = std.mem.splitScalar(u8, b, '\n');
    while (true) {
        const x = nextCode(&ours);
        const y = nextCode(&theirs);
        if (x == null or y == null) return x == null and y == null;
        if (!x.?.same(y.?)) return false;
    }
}

const EmittedFunctions = struct {
    prefix: []const u8,
    functions: std.ArrayList([]const u8),

    fn of(gpa: std.mem.Allocator, text: []const u8) !EmittedFunctions {
        const module_end = std.mem.lastIndexOf(u8, text, "\n}\n") orelse text.len;
        const body = text[0..module_end];
        var starts: std.ArrayList(usize) = .empty;
        defer starts.deinit(gpa);
        var cursor: usize = 0;
        while (std.mem.indexOfPos(u8, body, cursor, "  func.func ")) |at| {
            if (at == 0 or body[at - 1] == '\n') try starts.append(gpa, at);
            cursor = at + 1;
        }
        if (starts.items.len == 0) return .{ .prefix = body, .functions = .empty };

        var functions: std.ArrayList([]const u8) = .empty;
        for (starts.items, 0..) |start, i| {
            const end = if (i + 1 < starts.items.len) starts.items[i + 1] else body.len;
            try functions.append(gpa, body[start..end]);
        }
        std.mem.sortUnstable([]const u8, functions.items, {}, struct {
            fn before(_: void, lhs: []const u8, rhs: []const u8) bool {
                const lhs_end = std.mem.indexOfScalar(u8, lhs, '\n') orelse lhs.len;
                const rhs_end = std.mem.indexOfScalar(u8, rhs, '\n') orelse rhs.len;
                return std.mem.order(u8, lhs[0..lhs_end], rhs[0..rhs_end]) == .lt;
            }
        }.before);
        return .{ .prefix = body[0..starts.items[0]], .functions = functions };
    }

    fn deinit(self: *EmittedFunctions, gpa: std.mem.Allocator) void {
        self.functions.deinit(gpa);
    }
};

/// Materializing generated declarations may reorder source files within a
/// module. Function order is not code; each function's body and all module
/// globals still are.
fn sameCodeIgnoringFunctionOrder(gpa: std.mem.Allocator, a: []const u8, b: []const u8) !bool {
    var ours = try EmittedFunctions.of(gpa, a);
    defer ours.deinit(gpa);
    var theirs = try EmittedFunctions.of(gpa, b);
    defer theirs.deinit(gpa);
    if (!sameCode(ours.prefix, theirs.prefix)) return false;
    if (ours.functions.items.len != theirs.functions.items.len) return false;
    for (ours.functions.items, theirs.functions.items) |x, y| {
        if (!sameCode(x, y)) return false;
    }
    return true;
}

test "a location is where a line came from, not what it is" {
    const one =
        "    %v0 = arith.constant 7 : i64 loc(\"a.lin\":3:5)";
    const other =
        "    %v0 = arith.constant 7 : i64 loc(\"b.lin\":9:1)";
    try testing.expect(sameCode(one, other));

    const file_one = "    %tf0 = llvm.mlir.addressof @linea_file0 : !llvm.ptr";
    const file_two = "    %tf0 = llvm.mlir.addressof @linea_file7 : !llvm.ptr";
    try testing.expect(sameCode(file_one, file_two));

    // A different constant is different code, wherever it was written.
    const grown =
        "    %v0 = arith.constant 8 : i64 loc(\"a.lin\":3:5)";
    try testing.expect(!sameCode(one, grown));
}

test "a trap's position is not its code" {
    const one =
        "    %tl3 = arith.constant 12 : i32 loc(\"a.lin\":12:9)\n" ++
        "    %tc3 = arith.constant 9 : i32 loc(\"a.lin\":12:9)";
    const other =
        "    %tl3 = arith.constant 40 : i32 loc(\"a.lin\":40:2)\n" ++
        "    %tc3 = arith.constant 2 : i32 loc(\"a.lin\":40:2)";
    try testing.expect(sameCode(one, other));

    // The kind a trap reports is code: a rewrite may not turn one failure
    // into another.
    const kind_one = "    %tk3 = arith.constant 0 : i32";
    const kind_two = "    %tk3 = arith.constant 2 : i32";
    try testing.expect(!sameCode(kind_one, kind_two));
}

/// Every rule the compiler can emit is provoked by some case.
///
/// The gate beside the codes proves each has prose defining it, which a rule
/// that has never fired satisfies as well as one exercised everywhere -- so a
/// check whose text drifted from its code, or which no longer fires at all,
/// passes it. Provoking one is what compares the two, and a rule nothing
/// provokes has never been compared.
///
/// A rule with no case is a missing case, not a rule to delete: the compiler
/// emits it, so a program reaches it, and the corpus is what says which
/// program. Reported by name because the name is the work item.
fn checkEveryRuleIsReached(
    gpa: std.mem.Allocator,
    failures: *std.ArrayList(Failure),
    reached: *const std.EnumMap(diagnostic.Code, void),
) !void {
    var missing: std.ArrayList(u8) = .empty;
    var count: u32 = 0;
    for (std.enums.values(diagnostic.Code)) |c| {
        if (reached.contains(c)) continue;
        if (count > 0) try missing.appendSlice(gpa, ", ");
        try missing.appendSlice(gpa, c.ruleName());
        count += 1;
    }

    std.debug.print(
        "conformance: {d} of {d} rule(s) reached by some case\n",
        .{ std.enums.values(diagnostic.Code).len - count, std.enums.values(diagnostic.Code).len },
    );
    if (count == 0) return;

    try failures.append(gpa, .{
        .path = "the corpus",
        .what = "does not provoke every rule the compiler can emit",
        .expected = "a case for each",
        .actual = try std.fmt.allocPrint(gpa, "{d} unreached: {s}", .{ count, missing.items }),
    });
}

/// The library the compiler carries is the directory on disk.
///
/// The list is generated by walking `std/` at build time, so this pins that
/// walk rather than a hand-written list. The transition worth guarding is a
/// deletion: a file removed from the directory whose copy stays in the build
/// cache would be carried by a compiler that no longer has the source for it.
fn checkLibrary(
    gpa: std.mem.Allocator,
    io: std.Io,
    failures: *std.ArrayList(Failure),
) !void {
    var dir = std.Io.Dir.cwd().openDir(io, library.prelude_dir, .{ .iterate = true }) catch return;
    defer dir.close(io);

    var walker = try dir.walk(gpa);
    defer walker.deinit();

    var on_disk: usize = 0;
    while (try walker.next(io)) |entry| {
        if (entry.kind != .file) continue;
        // The sources and the manifest that names them the library.
        if (!std.mem.endsWith(u8, entry.basename, ".lin") and !std.mem.eql(u8, entry.path, loader.manifest_name)) continue;
        on_disk += 1;

        var carried = false;
        for (library.files) |f| {
            if (std.mem.endsWith(u8, f.path, entry.path)) carried = true;
        }
        if (carried) continue;

        try failures.append(gpa, .{
            .path = try std.fs.path.join(gpa, &.{ library.prelude_dir, entry.path }),
            .what = "is in the library directory and not in the library",
            .expected = "a file the compiler carries",
            .actual = "a file only on disk",
        });
    }

    // And that each is written the way the formatter writes it. Every gate the
    // corpus has runs over cases, and a library file is not a case -- so the
    // three files compiled into every binary the compiler produces were the
    // only Linea in the repository nothing held to its own formatting.
    for (library.files) |f| {
        if (!std.mem.endsWith(u8, f.path, ".lin")) continue;
        const canonical = try formattedText(gpa, f.text) orelse continue;
        if (std.mem.eql(u8, canonical, f.text)) continue;
        try failures.append(gpa, .{
            .path = f.path,
            .what = "is not written the way the formatter writes it",
            .expected = canonical,
            .actual = f.text,
        });
    }

    if (on_disk == library.files.len) return;
    try failures.append(gpa, .{
        .path = library.prelude_dir,
        .what = "carries a different number of files than the directory holds",
        .expected = try std.fmt.allocPrint(gpa, "{d} file(s)", .{on_disk}),
        .actual = try std.fmt.allocPrint(gpa, "{d} file(s)", .{library.files.len}),
    });
}

/// The files the language server reads for `program`: its sources and the
/// manifest its one walk found.
fn filesOfProgram(gpa: std.mem.Allocator, io: std.Io, docs: *const Documents, program: []const u8) ![]const loader.InMemoryFile {
    const root = try loader.rootOf(gpa, io, program, .its_program, "");
    defer root.deinit(gpa);
    return docs.filesFor(gpa, io, root);
}

fn readIfExists(io: std.Io, gpa: std.mem.Allocator, path: []const u8) !?[]u8 {
    return readFileAlloc(io, gpa, path) catch |err| switch (err) {
        error.FileNotFound => null,
        else => err,
    };
}

/// Appends what the program said on standard error to a mismatching exit
/// status or output, so a run that trapped names its trap in the failure
/// report. A case recording standard error compares it itself, and a refusal
/// golden already holds the report in its status text.
fn showStderrOfMismatches(gpa: std.mem.Allocator, failures: []Failure, errors: []const u8) !void {
    if (errors.len == 0) return;
    for (failures) |*f| {
        const is_run = std.mem.eql(u8, f.what, "exit") or std.mem.eql(u8, f.what, "out");
        if (!is_run or recordsStorageReport(f.expected)) continue;
        if (std.mem.indexOf(u8, f.actual, errors) != null) continue;
        f.actual = try std.fmt.allocPrint(gpa, "{s}\n--- stderr ---\n{s}", .{ f.actual, errors });
    }
}

test "a mismatching run reports what it said on standard error" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var failures = [_]Failure{
        .{ .path = "a.lin", .what = "exit", .expected = "exit 0\n", .actual = "trap\n" },
        .{ .path = "a.lin", .what = "mlir", .expected = "x", .actual = "y" },
        .{ .path = "b.lin", .what = "exit", .expected = "trap\nlinea: storage was freed twice\n", .actual = "exit 0\n" },
    };
    try showStderrOfMismatches(arena.allocator(), &failures, "linea: oops\n");
    try testing.expectEqualStrings("trap\n\n--- stderr ---\nlinea: oops\n", failures[0].actual);
    try testing.expectEqualStrings("y", failures[1].actual);
    try testing.expectEqualStrings("exit 0\n", failures[2].actual);
    var said_already = [_]Failure{.{ .path = "c.lin", .what = "exit", .expected = "exit 0\n", .actual = "trap\nlinea: oops\n" }};
    try showStderrOfMismatches(arena.allocator(), &said_already, "linea: oops\n");
    try testing.expectEqualStrings("trap\nlinea: oops\n", said_already[0].actual);
    try showStderrOfMismatches(arena.allocator(), failures[1..2], "");
    try testing.expectEqualStrings("y", failures[1].actual);
}

fn compare(
    gpa: std.mem.Allocator,
    io: std.Io,
    failures: *std.ArrayList(Failure),
    lin_path: []const u8,
    what: []const u8,
    golden_path: []const u8,
    expected: []const u8,
    actual: []const u8,
    update: bool,
    /// Whether producing nothing is something to record.
    ///
    /// For a pass it is not: an empty golden means the pass produced nothing,
    /// which is never what a case is for. For a command it is the observation
    /// -- printing nothing on a stream is a result, and no other expectation
    /// records it.
    empty_is_an_answer: bool,
) !bool {
    // An expectation recording nothing asserts nothing, and the case around it
    // is a no-op that reports success. That is how a golden created and never
    // accepted, or accepted while the output was empty, retires a case without
    // anyone deciding to. `-Dupdate` still fills one, which is what makes
    // creating the file the way to ask for the expectation.
    if (expected.len == 0 and !empty_is_an_answer and !update) {
        try failures.append(gpa, .{
            .path = lin_path,
            .what = what,
            .expected = "an expectation, and this file records none",
            .actual = actual,
        });
        return false;
    }

    // A golden records no line or column inside `std/`, so an edit to a
    // library file does not rewrite it. A failure still shows the real output.
    const recorded = try std_locations.normalise(gpa, actual);
    defer gpa.free(recorded);
    if (std.mem.eql(u8, expected, recorded)) return false;

    if (update) {
        try writeFile(io, golden_path, recorded);
        return true;
    }

    try failures.append(gpa, .{
        .path = lin_path,
        .what = what,
        .expected = expected,
        .actual = actual,
    });
    return false;
}

test "a golden does not move when a library line does" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var failures: std.ArrayList(Failure) = .empty;
    const recorded = "linea: index out of bounds at std/mem/buffer.lin:L:C\n";
    const moved = "linea: index out of bounds at std/mem/buffer.lin:231:9\n";
    try testing.expect(!try compare(arena.allocator(), testing.io, &failures, "c.lin", "exit", "c.exit", recorded, moved, false, false));
    try testing.expectEqual(@as(usize, 0), failures.items.len);

    // A different library file, or any user file, still fails and reports
    // the output as it was printed.
    const elsewhere = "linea: index out of bounds at std/mem/slice.lin:231:9\n";
    try testing.expect(!try compare(arena.allocator(), testing.io, &failures, "c.lin", "exit", "c.exit", recorded, elsewhere, false, false));
    try testing.expectEqual(@as(usize, 1), failures.items.len);
    try testing.expectEqualStrings(elsewhere, failures.items[0].actual);
}

test "updating a golden writes the placeholders" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const golden = try std.fmt.allocPrint(arena.allocator(), ".zig-cache/tmp/{s}/c.exit", .{tmp.sub_path});
    var failures: std.ArrayList(Failure) = .empty;
    const moved = "linea: index out of bounds at std/mem/buffer.lin:231:9\nat tests/c.lin:7:3\n";
    try testing.expect(try compare(arena.allocator(), testing.io, &failures, "c.lin", "exit", golden, "old\n", moved, true, false));
    const written = try tmp.dir.readFileAlloc(testing.io, "c.exit", arena.allocator(), .limited(1024));
    try testing.expectEqualStrings("linea: index out of bounds at std/mem/buffer.lin:L:C\nat tests/c.lin:7:3\n", written);
}

fn writeFile(io: std.Io, path: []const u8, data: []const u8) !void {
    const file = try std.Io.Dir.cwd().createFile(io, path, .{});
    defer file.close(io);

    var buf: [4096]u8 = undefined;
    var w = file.writer(io, &buf);
    try w.interface.writeAll(data);
    try w.interface.flush();
}

/// What every case's check reads and none of them changes.
const Settings = struct {
    /// The checked library every case resumes from.
    library: *const loader.CheckedLibrary,
    properties: bool = false,
    /// Whether every case is held to the frontend and editor properties the
    /// whole corpus is asked: formatting, poison, extents, scopes, hints,
    /// settled references and completions. A sanitized walk asks only what
    /// a sanitizer can watch, which is what runs, and leaves these to the
    /// unsanitized one.
    corpus_properties: bool = true,
    /// Whether every case that runs is also built at every other optimisation
    /// level and held to answering alike.
    levels: bool = false,
    cache: *const OutcomeCache,
    update: bool,
    sanitize: ?[]const u8,
    runtime_path: ?[]const u8,
    scratch_dir: []const u8,
    /// Whether the runtime holds the checking allocator, read from the archive.
    checks_storage: bool = false,
    /// Counts the cases recording a checking-allocator report that were not
    /// run, because the runtime holds no checking allocator.
    unchecked_skips: ?*std.atomic.Value(u32) = null,
};

/// The reports the checking allocator makes, read from the runtime's own
/// table: each is the text before its first formatted value or its newline.
fn storageReports() []const []const u8 {
    const source = @embedFile("runtime_source");
    const table = comptime blk: {
        @setEvalBranchQuota(1_000_000);
        const open = std.mem.indexOf(u8, source, "static const char *const storage_reports[] = {") orelse
            @compileError("runtime/linea_rt.c no longer declares storage_reports[]");
        const close = std.mem.indexOfPos(u8, source, open, "};").?;
        var found: []const []const u8 = &.{};
        var at = open;
        while (std.mem.indexOfScalarPos(u8, source[0..close], at, '"')) |start| {
            const end = std.mem.indexOfScalarPos(u8, source, start + 1, '"').?;
            const text = source[start + 1 .. end];
            const cut = std.mem.indexOfAny(u8, text, "%\\") orelse text.len;
            found = found ++ [_][]const u8{text[0..cut]};
            at = end + 1;
        }
        break :blk found;
    };
    return table;
}

test "the checking allocator's reports are read from the runtime" {
    const reports = storageReports();
    try testing.expect(reports.len >= 6);
    for (reports) |report| try testing.expect(std.mem.startsWith(u8, report, "linea: "));
    try testing.expect(recordsStorageReport("trap\nlinea: storage was freed twice\n"));
    try testing.expect(recordsStorageReport("trap\nlinea: a disposal named the wrong size: 8 bytes of a 16-byte allocation\n"));
    try testing.expect(!recordsStorageReport("trap\nlinea: index out of bounds at t.lin:1:2\n"));
    try testing.expect(!recordsStorageReport("exit 0\n"));
}

/// Whether a recorded outcome is an abort the checking allocator reported.
/// Only a runtime holding that allocator can produce one, so such a case is
/// not run against any other.
fn recordsStorageReport(recorded: []const u8) bool {
    if (!std.mem.startsWith(u8, recorded, trap_answer)) return false;
    var lines = std.mem.splitScalar(u8, recorded[trap_answer.len..], '\n');
    while (lines.next()) |line| {
        for (storageReports()) |report| if (std.mem.startsWith(u8, line, report)) return true;
    }
    return false;
}

/// What one walk of the corpus accumulates.
///
/// Every field is a total over cases and none is read while the walk runs, so
/// two walks can each keep their own and be added together afterwards. That is
/// what lets the corpus be walked by more than one thread: there is no shared
/// answer to race for, only sums.
/// How many aggregate types the corpus must hand to the oracle.
///
/// Not a target: a number the corpus clears today and would stop clearing if
/// the property silently stopped reaching types -- which is the one failure a
/// green run cannot be told from.
const layout_floor: u32 = 200;

const Work = struct {
    /// What the case in hand recorded. Allocated from that case's own arena,
    /// so it is read and emptied before the arena is reset.
    failures: std.ArrayList(Failure) = .empty,
    /// What every case before it recorded, copied out of the arenas that have
    /// since been reset.
    kept: std.ArrayList(Failure) = .empty,
    /// Layout fragments produced by the case in hand, retained separately so
    /// all cases can share a bounded number of C compiler processes.
    layout_jobs: std.ArrayList(LayoutJob) = .empty,
    kept_layout_jobs: std.ArrayList(LayoutJob) = .empty,
    properties: std.EnumMap(Property, u32) = .{},
    passed_over: std.EnumMap(Property, u32) = .{},
    rewrites: std.EnumMap(Transform, u32) = .{},
    materialized_derives: u32 = 0,
    damages: std.EnumMap(Damage, u32) = .{},
    mutations: std.EnumMap(Mutation, u32) = .{},
    /// The cases that carried a fix of each kind.
    fix_kinds: FixKinds = .{},
    rules_reached: std.EnumMap(diagnostic.Code, void) = .{},
    terminator_witnesses: TerminatorWitnesses = .initFill(false),
    /// The functions this walker's cases declare, the library's excluded,
    /// summed into the corpus once the walkers are joined. Counted per walker
    /// rather than into the corpus directly, because the walkers run at once
    /// and a shared counter would report whatever the scheduler did.
    functions: u32 = 0,
    /// The settled references this walker's cases write, the library's
    /// excluded, summed into the corpus once the walkers are joined. Per walker
    /// for the reason the functions are.
    settled_refs: u32 = 0,
    /// The settled references this walker passed over, apart by which reason,
    /// and the checks apart by which check. Reported because one number covers
    /// unlike things: a refusal has a diagnostic against it, and a signature's
    /// settled reference is checked by nothing.
    declined_settled_refs: PassedSettledRefs = .{},
    /// The points after a dot this walker asked a completion at. Per walker for
    /// the same reason, and reported because the population beside the property
    /// counts *functions*: a function that writes one dot and one that writes
    /// forty are one apiece there, so a dot half that stopped asking would not
    /// move the number it is measured against.
    dots: u32 = 0,
    /// The lending walks this walker also held the consuming form to. Reported
    /// beside the property, because the two halves of it reach different
    /// numbers: only a walk over an array has a consuming form that walks the
    /// same value, and a single count would read as though every lending walk
    /// had been held to both.
    walks_also: u32 = 0,
    /// How many aggregate types `cc` was asked to measure.
    ///
    /// A run in which the oracle compared none proved nothing and reads exactly
    /// like a clean one, so the walk is held to a floor.
    layouts_compared: u32 = 0,
    /// How many cases answered alike at every optimisation level, where the
    /// run asks. Reported and held to a floor for the reason the layouts are.
    levels_agreed: u32 = 0,

    /// Copies what the case in hand recorded into memory that outlives it.
    ///
    /// A case allocates from an arena of its own, which is reset once it is
    /// done: what it recorded names strings in that arena, so the record is
    /// taken out before the arena goes. Every path is copied rather than the
    /// new ones, because a `Failure` carries no mark saying which arena it came
    /// from and a wrong guess is a read of freed memory.
    fn retain(self: *Work, keep: std.mem.Allocator, ordinal: usize) !void {
        for (self.failures.items, 0..) |f, i| {
            try self.kept.append(keep, .{
                .path = try keep.dupe(u8, f.path),
                .what = try keep.dupe(u8, f.what),
                .expected = try keep.dupe(u8, f.expected),
                .actual = try keep.dupe(u8, f.actual),
                .case_ordinal = ordinal + 1,
                // Delayed checks use the odd number between these ordinary
                // failures to recover the point where the check was queued.
                .case_order = i * 2 + 2,
            });
        }
        // Its storage belonged to the arena about to be reset, so the list is
        // abandoned rather than cleared.
        self.failures = .empty;

        for (self.layout_jobs.items) |job| {
            try self.kept_layout_jobs.append(keep, .{
                .display_path = try keep.dupe(u8, job.display_path),
                .text = try keep.dupe(u8, job.text),
                .case_ordinal = job.case_ordinal,
                .case_order = job.case_order,
            });
        }
        self.layout_jobs = .empty;
    }
};

/// Everything the corpus asks of one case.
/// A native outcome certifies that the same emitted bytes passed MLIR's
/// verifier during lowering. Cases without that proof still verify their
/// matching recorded module independently.
fn verifyRecordedModule(gpa: std.mem.Allocator, io: std.Io, failures: *std.ArrayList(Failure), display_path: []const u8, golden: []const u8, native_verified: bool) !void {
    if (native_verified) return;
    if (try toolchain.verifyEmitted(gpa, io, golden)) |failure| {
        try failures.append(gpa, .{
            .path = display_path,
            .what = "records a module MLIR's verifier refuses",
            .expected = "mlir-opt accepts every recorded module",
            .actual = failure.output,
        });
    }
}

test "recorded MLIR verification accepts native cache proof but retains invalid IR checks" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    var directory = testing.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(testing.io, ".", gpa);
    const cache: OutcomeCache = .{ .dir = root, .salt = 0 };
    const valid = "module {}\n";
    try cache.put(gpa, testing.io, .{ .ir = valid }, "said 0\nprinted 0\nexit 0\n", null);
    const cached = try outcomeOf(gpa, testing.io, &cache, .{
        .scratch = "no-such-native-scratch",
        .name = "cached",
        .ir = valid,
        .runtime = "no-such-runtime",
        .sanitize = null,
    });
    try testing.expect(!cached.tool_failed);
    var failures: std.ArrayList(Failure) = .empty;
    try verifyRecordedModule(gpa, testing.io, &failures, "cached", "no-such-recorded-module.mlir", !cached.tool_failed);
    try testing.expectEqual(@as(usize, 0), failures.items.len);

    const invalid = "module { this.is_not_registered }\n";
    const rejected = try outcomeOf(gpa, testing.io, &cache, .{
        .scratch = root,
        .name = "invalid",
        .ir = invalid,
        .runtime = "no-such-runtime",
        .sanitize = null,
    });
    try testing.expect(rejected.tool_failed);
    try testing.expect(!rejected.tool_missing);
    try testing.expect(try cache.lookup(gpa, testing.io, .{ .ir = invalid }) == null);
    const golden = try std.fs.path.join(gpa, &.{ root, "invalid.mlir" });
    try verifyRecordedModule(gpa, testing.io, &failures, "invalid", golden, !rejected.tool_failed);
    try testing.expectEqual(@as(usize, 1), failures.items.len);
    try testing.expect(failures.items[0].actual.len > 0);
    failures.clearRetainingCapacity();
    try verifyRecordedModule(gpa, testing.io, &failures, "mlir-only", golden, false);
    try testing.expectEqual(@as(usize, 1), failures.items.len);
}

fn checkCase(
    gpa: std.mem.Allocator,
    scratch_parent: std.mem.Allocator,
    io: std.Io,
    env: Settings,
    w: *Work,
    case: Case,
    ordinal: usize,
) !bool {
    const stem = case.stem;
    const display_path = case.display_path;

    // A sanitizer watches what runs, and a case runs only where it records
    // an exit status. Under one, a case that only compiles is left to the
    // unsanitized walk, which checks everything else it records.
    if (env.sanitize != null) {
        const exit_golden = try std.mem.concat(gpa, u8, &.{ stem, ".exit" });
        if (try readIfExists(io, gpa, exit_golden) == null) return false;
    }

    // What the mutation had reached before this case. The property it answers
    // for is counted from what it did here, and it runs in the middle of the
    // walk -- so the difference is what says this case was one of them rather
    // than a case somebody counted twice.
    const narrowed_before = w.mutations.get(.narrowed_range) orelse 0;

    var table: FileTable = .empty;
    var sink = Sink.init(gpa);
    var interner: Interner = .empty;

    // Loading, parsing and following imports, which for a case that is one
    // file is loading, parsing and following none. Property: parsing
    // yields a complete tree for any input -- every declaration's body is
    // a block, and the whole tree renders end to end. This is the
    // executable form of the guarantee that the parser has no error path.
    const program = loaded: {
        const load_zone = tracy.beginZone(@src(), "frontend");
        defer load_zone.end();
        const inputs = try inputsOf(gpa, case);
        break :loaded try env.library.loadFromMemory(gpa, &table, &sink, &interner, case.entry, inputs, .program, .borrow);
    };
    try table.buildMaps(gpa);
    const ast = program.ast;
    // Where loading reported nothing, the tree is what the source says rather
    // than what the parser recovered from it.
    const loaded_cleanly = !sink.hasErrors();
    const source_properties_zone = tracy.beginZone(@src(), "case.source-properties");

    // Property: emitting each token's preceding gap followed by its own
    // text reproduces the input -- per file, because a module's spans are
    // offsets into the file that produced them and never into the stream
    // they were appended to. This is the executable form of the guarantee
    // every formatting tool depends on.
    {
        const spans = ast.tokens.items(.span);
        const tags = ast.tokens.items(.tag);
        for (ast.parts) |part| {
            const src = table.get(part.file).*;
            var rebuilt: std.Io.Writer.Allocating = .init(gpa);
            try token.reconstruct(spans[part.token_start..part.token_end], src.text, &rebuilt.writer);

            if (!std.mem.eql(u8, src.text, rebuilt.written())) {
                try w.failures.append(gpa, .{
                    .path = src.path,
                    .what = "token stream does not reconstruct the source",
                    .expected = src.text,
                    .actual = rebuilt.written(),
                });
            }

            // Property: tokenising terminates and yields a well-formed
            // stream. Each file ends in its own eof, which is where its
            // parse stopped.
            if (part.token_end == part.token_start or tags[part.token_end - 1] != .eof) {
                try w.failures.append(gpa, .{
                    .path = src.path,
                    .what = "token stream does not end with eof",
                    .expected = "eof",
                    .actual = if (part.token_end == part.token_start)
                        "empty"
                    else
                        @tagName(tags[part.token_end - 1]),
                });
            }
        }

        // One tally per file the case is made of, rather than one per
        // part: the parts hold the library files an import pulled in --
        // the same handful loaded again for every case that imports them,
        // so counting those would report how many cases import the
        // library. A file the loader never reached is passed over, which
        // is the honest side for a directory whose name the language
        // reserves: nothing parses it, so it has no token stream to
        // compare.
        for (case.files) |cf| {
            const parsed = for (ast.parts) |part| {
                if (std.mem.eql(u8, table.get(part.file).path, cf.path)) break true;
            } else false;
            tally(&w.properties, &w.passed_over, .losslessness, parsed);
            tally(&w.properties, &w.passed_over, .token_stream, parsed);
        }
    }
    {
        tally(&w.properties, &w.passed_over, .complete_tree, true);
        for (0..ast.declCount()) |di| {
            const d = node_mod.DeclId.at(@intCast(di));
            const body = ast.declBody(d);
            if (body == ExprId.none) continue;
            if (ast.exprTag(body) != .block) {
                try w.failures.append(gpa, .{
                    .path = display_path,
                    .what = "a declaration's body is not a block",
                    .expected = "block",
                    .actual = @tagName(ast.exprTag(body)),
                });
            }
        }

        var probe: std.Io.Writer.Allocating = .init(gpa);
        dumpAst(&probe.writer, &ast, program.ownDeclarations()) catch {
            try w.failures.append(gpa, .{
                .path = display_path,
                .what = "tree could not be rendered",
                .expected = "a complete tree",
                .actual = "rendering failed",
            });
        };
    }

    // Property: a module's files have no order. The loader sorts them by
    // name, so supplying them in the opposite order must produce the same
    // tree -- and a loader that numbered by discovery would pass every
    // other case here and fail this one.
    if (env.properties and case.files.len > 1) {
        const beside = try besideOf(gpa, case);
        const flipped = try gpa.alloc(InMemoryFile, case.files.len + beside.len);
        for (case.files, 0..) |f, k| flipped[case.files.len - 1 - k] = f;
        @memcpy(flipped[case.files.len..], beside);

        var other_table: FileTable = .empty;
        var other_sink = Sink.init(gpa);
        var other_interner: Interner = .empty;
        const other = try env.library.loadFromMemory(gpa, &other_table, &other_sink, &other_interner, case.entry, flipped, .program, .borrow);

        var a: std.Io.Writer.Allocating = .init(gpa);
        try dumpAst(&a.writer, &ast, program.ownDeclarations());
        var b: std.Io.Writer.Allocating = .init(gpa);
        try dumpAst(&b.writer, &other.ast, other.ownDeclarations());

        tally(&w.properties, &w.passed_over, .file_order, true);
        if (!std.mem.eql(u8, a.written(), b.written())) {
            try w.failures.append(gpa, .{
                .path = display_path,
                .what = "the order a module's files were found in changed the program",
                .expected = a.written(),
                .actual = b.written(),
            });
        }
    }

    const tokens_golden = try std.mem.concat(gpa, u8, &.{ stem, ".tokens" });
    if (try readIfExists(io, gpa, tokens_golden)) |expected| {
        // The dump numbers tokens from zero within one file. A module's
        // stream holds several files' tokens, so the golden would record
        // where each file happened to land rather than what it says.
        if (case.files.len != 1) {
            try w.failures.append(gpa, .{
                .path = display_path,
                .what = "a module of several files records a token dump",
                .expected = "one file",
                .actual = "a directory",
            });
        } else {
            var out: std.Io.Writer.Allocating = .init(gpa);
            const part = ast.partOfFile(program.primaryFile()).?;
            try lexer_dump.dumpTokens(&out.writer, case.files[0].text, ast.tokens, part.token_start, part.token_end);
            if (try compare(gpa, io, &w.failures, display_path, "tokens", tokens_golden, expected, out.written(), env.update, false)) {
                std.debug.print("updated {s}\n", .{tokens_golden});
            }
        }
    }

    const ast_golden = try std.mem.concat(gpa, u8, &.{ stem, ".ast" });
    if (try readIfExists(io, gpa, ast_golden)) |expected| {
        var out: std.Io.Writer.Allocating = .init(gpa);
        try dumpAst(&out.writer, &ast, program.ownDeclarations());
        if (try compare(gpa, io, &w.failures, display_path, "ast", ast_golden, expected, out.written(), env.update, false)) {
            std.debug.print("updated {s}\n", .{ast_golden});
        }
    }
    source_properties_zone.end();

    // Resolution, type checking and ownership run on every case, so their
    // diagnostics reach the .stderr expectations alongside the parser's.
    // This must happen before that comparison, or the rendered output is
    // missing everything the later passes reported.
    const semantic_check_zone = tracy.beginZone(@src(), "case.semantic-check");
    var settled = try env.library.checkProgram(gpa, scratch_parent, &program, &interner, &sink, .program);
    defer settled.deinit(gpa);
    const res = &settled.res;
    const disposals = &settled.disposals;
    const typing = &settled.typing;

    // Not settled yet: instance discovery reports rules only concrete
    // instances can settle, so a case can still be rejected below.
    var rejected = sink.hasErrors();
    var lowered: ?MirModule = null;

    // The inferred dump reads the checker's answers back into the
    // source, so it is only meaningful where the checker had answers.
    if (!rejected) {
        const golden = try std.mem.concat(gpa, u8, &.{ stem, ".inferred" });
        if (try readIfExists(io, gpa, golden)) |expected| {
            var out: std.Io.Writer.Allocating = .init(gpa);
            try annotated.dumpInferred(gpa, &out.writer, &ast, res, typing, program.ownDeclarations());
            if (try compare(gpa, io, &w.failures, display_path, "inferred", golden, expected, out.written(), env.update, false)) {
                std.debug.print("updated {s}\n", .{golden});
            }
        }

        const lower_zone = tracy.beginZone(@src(), "case.lower");
        lowered = try lower(gpa, &settled.expanded, res, typing, disposals, &sink, .program);
        lower_zone.end();
        rejected = sink.hasErrors();

        const mono_golden = try std.mem.concat(gpa, u8, &.{ stem, ".mono" });
        if (lowered) |*module| if (try readIfExists(io, gpa, mono_golden)) |expected| {
            var out: std.Io.Writer.Allocating = .init(gpa);
            try annotated.dumpMono(gpa, &out.writer, &settled.expanded, typing, module);
            if (try compare(gpa, io, &w.failures, display_path, "mono", mono_golden, expected, out.written(), env.update, false)) {
                std.debug.print("updated {s}\n", .{mono_golden});
            }
        };
    }
    if (!rejected) if (lowered) |*module| {
        recordTerminatorWitnesses(&w.terminator_witnesses, display_path, program.primaryFile(), module);
    };
    // Taken before the backend runs, which reports nothing about the source:
    // what a rewrite of the walks is compared against is what the passes said.
    const rules_named = try rulesNamedBy(gpa, &sink);
    semantic_check_zone.end();

    // Property: a use lies inside the region of source its binding belongs
    // to. Where a use reaches it from is read from the scope chain and
    // where the binding belongs is read from the tree, so the two disagree
    // exactly when a scope fails to close -- which no rewrite of the
    // program can show, because a rewrite driven by resolution cannot
    // contradict it.
    // A property that slices one file's text needs a tree of that text and
    // nothing else. The program's own tree carries the library beside it,
    // and a span from there indexes bytes the property is not holding --
    // which crashes on a long enough library and, on a short case, silently
    // rewrites arbitrary bytes and then reports the compiler for refusing
    // what the harness broke.
    //
    // Built once here rather than per property, so the three that need it
    // cannot drift apart again.
    const transforms_zone = tracy.beginZone(@src(), "case.transforms-format");
    var alone: ?Standalone = null;
    defer if (alone) |*a| a.deinit(gpa);
    if (env.properties and !rejected and case.files.len == 1) {
        alone = try Standalone.of(gpa, &Source{
            .path = case.files[0].path,
            .text = case.files[0].text,
        });
    }

    // The mutations read spans against one file's text, so they run on a
    // case that is one file. A module of several is covered by the file
    // order transform instead, which is what its counter reports.
    if (alone) |*a| {
        try checkMutations(gpa, &w.failures, &w.mutations, display_path, &a.ast, &a.resolved.resolution, &a.typing, case.files[0].text, program.kind);
    }

    // Property: formatting re-parses, preserves the token sequence and the
    // comments, is idempotent, and reaches the same bytes however the
    // source was spaced. Checked on every file the compiler parses, because
    // the fuzzer is unlikely to synthesise a nested `impl` or an arm that
    // binds what its variant carries, and the corpus holds them on purpose.
    const fmt_golden = try std.mem.concat(gpa, u8, &.{ stem, ".fmt" });
    if (env.corpus_properties) for (case.files) |f| {
        // Every file of every case reaches both calls, and each answers for
        // that file on one side of its tally or the other. This loop
        // therefore runs as many times as the corpus has files, which is
        // what the accounting at the end of the run is entitled to assume.
        var formatted: ?[]const u8 = null;
        var formatting_checked = false;
        const formatting = fmt.checkProperties(gpa, f.text) catch |e| blk: {
            try w.failures.append(gpa, .{
                .path = display_path,
                .what = "formatting properties",
                .expected = "preserved, idempotent, re-parsing",
                .actual = @errorName(e),
            });
            formatted = try formattedText(gpa, f.text);
            break :blk null;
        };
        if (formatting) |property| switch (property) {
            .not_applicable => {},
            .checked => |checked| {
                formatting_checked = true;
                formatted = checked.formatted;
            },
        };
        tally(&w.properties, &w.passed_over, .formatting, formatting_checked);

        const normal_form = if (formatted) |canonical|
            perturb.checkNormalForm(gpa, f.text, canonical) catch |e| blk: {
                try w.failures.append(gpa, .{
                    .path = display_path,
                    .what = "formatting is a normal form",
                    .expected = "the same bytes however it was spaced",
                    .actual = @errorName(e),
                });
                break :blk false;
            }
        else
            false;
        tally(&w.properties, &w.passed_over, .normal_form, normal_form);

        // A `.fmt` golden records what formatting does to a case, so such
        // a case is written unformatted on purpose and is not held to the
        // gate below. Every other file the compiler parses must already be
        // formatted. The gate is here rather than in CI so it runs in the
        // edit-compile loop, and because the runner calls the formatter
        // directly rather than through a built binary; a case whose byte
        // layout is its own subject opts out through the language's escape
        // hatch.
        if (formatted) |canonical| {
            if (try readIfExists(io, gpa, fmt_golden)) |expected| {
                if (try compare(gpa, io, &w.failures, display_path, "fmt", fmt_golden, expected, canonical, env.update, false)) {
                    std.debug.print("updated {s}\n", .{fmt_golden});
                }
            } else if (!std.mem.eql(u8, canonical, f.text)) {
                try w.failures.append(gpa, .{
                    .path = display_path,
                    .what = "already formatted",
                    .expected = f.text,
                    .actual = canonical,
                });
            }
        }
    };

    // A case of one file the compiler rejected has no binding to reach,
    // so it is passed over rather than checked -- which is what keeps the
    // two tallies summing to every case of one file the corpus holds.
    if (env.properties and case.files.len == 1 and alone == null) tally(&w.properties, &w.passed_over, .regions, false);
    if (alone) |*a| {
        tally(&w.properties, &w.passed_over, .regions, true);
        if (try regions.firstEscape(gpa, &a.ast, &a.resolved.resolution, case.files[0].text)) |e| {
            try w.failures.append(gpa, .{
                .path = display_path,
                .what = "a use reaches a binding from outside its region",
                .expected = try std.fmt.allocPrint(gpa, "`{s}` within {d}..{d}", .{
                    e.name,
                    e.extent.start,
                    e.extent.end,
                }),
                .actual = try std.fmt.allocPrint(gpa, "used at {d}..{d}", .{
                    e.use.start,
                    e.use.end,
                }),
            });
        }
    }
    transforms_zone.end();

    // Property: every expression has exactly one type, and it is poison
    // if and only if something was reported. Poison with a clean sink
    // means a pass swallowed an error.
    const semantic_properties_zone = tracy.beginZone(@src(), "case.semantic-properties");
    if (env.corpus_properties) {
        {
            tally(&w.properties, &w.passed_over, .poison_free, true);
            var template_extents = try StructuralTemplateExtents.init(gpa, &ast);
            defer template_extents.deinit(gpa);
            var poisoned: ?ExprId = null;
            for (0..ast.exprCount()) |i| {
                const expression = ExprId.at(@intCast(i));
                if (template_extents.contains(ast.exprMain(expression))) continue;
                if (typing.exprType(expression) == .poison) {
                    poisoned = expression;
                    break;
                }
            }
            if (poisoned != null and !sink.hasErrors()) {
                const expression = poisoned.?;
                const at = ast.exprSpan(expression);
                const source = table.get(ast.fileOfExpr(expression));
                try w.failures.append(gpa, .{
                    .path = display_path,
                    .what = "an expression is poisoned but nothing was reported",
                    .expected = "a diagnostic",
                    .actual = try std.fmt.allocPrint(gpa, "{s} expression {d} at {s}:{d}..{d}: {s}", .{
                        @tagName(ast.exprTag(expression)), @intFromEnum(expression), source.path,
                        at.start,                          at.end,                   source.text[at.start..at.end],
                    }),
                });
            }
        }

        // Property: no two of the tree's extents cross, which is what the
        // position index sweeps the tokens with a stack on. A question about
        // the parser, so it is asked of every case rather than of the accepted
        // ones: a tree error recovery built is where a rule could record an
        // extent another rule is still inside.
        tally(&w.properties, &w.passed_over, .nested_extents, true);
        try checkExtentsNest(gpa, &w.failures, display_path, &ast);

        // Property: a parameter hint names the parameter the call reaches.
        // Above the lowering, because a convention is on the signature rather
        // than on the instantiation -- a trait call and a generic call are
        // answered without it, and a rejected case is asked about too: a
        // half-written call is what an editor asks about most.
        // Property: a name reaches a binding the scope tree makes visible where it
        // was written. Asked of every case, accepted or not: the resolver binds
        // what it can whatever else is wrong, and a name it bound is a name the
        // tree has to account for.
        tally(&w.properties, &w.passed_over, .names_in_scope, true);
        try checkNamesInScope(gpa, &w.failures, display_path, &ast, res);

        tally(&w.properties, &w.passed_over, .parameter_hints, true);
        try checkParameterHints(gpa, &w.failures, display_path, &ast, typing);

        // How many functions this case declares, which is what the property below
        // is asked once per. Counted here from the tree rather than inside the
        // property, so the two tallies are held to a number the property did not
        // produce.
        for (program.modules) |m| {
            if (m.library) continue;
            for (m.decls.start..m.decls.end) |i| {
                if (ast.declTag(node_mod.DeclId.at(@intCast(i))) == .function) w.functions += 1;
            }
        }

        // How many settled references this case writes, which is what the property
        // below is asked once per, counted from the tree for the reason the
        // functions are.
        const in_library = try libraryFiles(gpa, &program);
        w.settled_refs += settledRefsWritten(&ast, &program, in_library);

        // Property: a settled reference the checker resolved names the type the
        // implementation settling it wrote, as that implementation's own text says.
        // Asked of a rejected case too: a program with one refusal in it still
        // resolved every settled reference the refusal did not reach, and a case
        // about a refusal is where a reading through the wrong implementation would
        // sit.
        try checkSettledRefs(
            gpa,
            &w.failures,
            &w.properties,
            &w.passed_over,
            &w.declined_settled_refs,
            display_path,
            &program,
            res,
            typing,
            in_library,
        );

        // Property: every name a completion offers at a point is one the resolver
        // would bind there, and every parameter of the function that point is
        // inside is among them. Asked of a rejected case too: a file being typed
        // into is where a completion is asked, and it is the state this is most
        // likely to be wrong in.
        try checkCompletionOffers(
            gpa,
            &w.failures,
            &w.properties,
            &w.passed_over,
            display_path,
            &program,
            res,
            typing,
            &w.dots,
        );
    }
    semantic_properties_zone.end();

    if (env.properties) {
        const lsp_zone = tracy.beginZone(@src(), "case.lsp");

        // Property: a language server publishes the diagnostics `check` reports.
        // Below discovery, because a sink that stopped at the checker is not what
        // `check` writes: compared above it, a server publishing nothing at all
        // for a program discovery rejects read as a server that agreed.
        //
        // A case the protocol cannot carry is passed over by both server
        // properties rather than failed. The protocol is JSON and a JSON
        // string is UTF-8, so a file that is not UTF-8 cannot be sent to a
        // server at all -- and the corpus holds one on purpose, because it is
        // what provokes [S-Encoding]. Nothing about the server is being
        // excused: there is no `didOpen` to send it, so there is no
        // notification it failed to answer with.
        const carriable = for (case.files) |f| {
            if (!std.unicode.utf8ValidateSlice(f.text)) break false;
        } else true;
        // The manifest travels with the source because it decides whether the root
        // is a program or library. This remains a second load and check, independent
        // of the compiler answers above; publication and rename only share that
        // independent answer with each other.
        var lsp_checked = try lsp_analysis.of(gpa, gpa, env.library, try inputsOf(gpa, case), case.entry);
        defer lsp_checked.deinit();

        tally(&w.properties, &w.passed_over, .published_diagnostics, carriable);
        if (carriable) {
            try checkPublished(gpa, &w.failures, display_path, &lsp_checked, &program, &table, &sink);
        }

        // Property: a rename the server answers, applied to the case's own
        // source, leaves a program that still compiles. Above the code
        // generation, because a rename is a question about the source rather
        // than about what it lowers to.
        tally(
            &w.properties,
            &w.passed_over,
            .renamed,
            try checkRenameApplies(gpa, scratch_parent, io, &w.failures, display_path, case, &lsp_checked),
        );

        // Property: a server driven through the protocol over this program
        // finishes and answers. Counted per file, because every file of the
        // case is opened as a document of its own.
        for (case.files) |_| tally(&w.properties, &w.passed_over, .survives, carriable);
        if (carriable) {
            try checkSurvives(gpa, io, env.library, &w.failures, env.scratch_dir, case, ordinal, &program, &table, !rejected);
        }
        lsp_zone.end();
    }

    // Code generation runs only for a case the compiler accepted; a
    // rejected program has no code to generate.
    const backend_zone = tracy.beginZone(@src(), "case.backend");
    var float_literals_survive = false;
    // What the program answered where it was built and run, for the walks
    // written out as loops to answer alike.
    var answered: ?RanAs = null;
    var answered_env: Env = undefined;
    if (lowered) |mir| {
        if (!rejected) {
            const mir_golden = try std.mem.concat(gpa, u8, &.{ stem, ".mir" });
            if (try readIfExists(io, gpa, mir_golden)) |expected| {
                var out: std.Io.Writer.Allocating = .init(gpa);
                try dumpMirModule(&out.writer, &mir);
                if (try compare(gpa, io, &w.failures, display_path, "mir", mir_golden, expected, out.written(), env.update, false)) {
                    std.debug.print("updated {s}\n", .{mir_golden});
                }
            }

            // Property: the layout table survives a second reading of the
            // rule, performed by a compiler that shares no code and no author
            // with this one. Every other check on generated code is relative
            // to this table, so a wrong size here is agreed on by everything
            // downstream and by the running program.
            if (env.runtime_path != null) {
                const layout_zone = tracy.beginZone(@src(), "case.layout-oracle");
                const oracle = try layout_oracle.of(gpa, &mir.types, mir.layouts, ordinal);
                if (oracle.compared > 0) {
                    // The case arena owns the fragment until `Work.retain`
                    // copies it for the batch. Freeing it here poisons the bytes
                    // before the walker has a chance to retain them.
                    w.layouts_compared += oracle.compared;
                    try w.layout_jobs.append(gpa, .{
                        .display_path = display_path,
                        .text = oracle.text,
                        .case_ordinal = ordinal + 1,
                        .case_order = w.failures.items.len * 2 + 1,
                    });
                }
                layout_zone.end();
            }

            var ir: std.Io.Writer.Allocating = .init(gpa);
            if (try emitOrRecord(gpa, &w.failures, &ir, &mir, &table, &sink, display_path)) {
                const mlir_golden = try std.mem.concat(gpa, u8, &.{ stem, ".mlir" });
                var matching_mlir = false;
                var native_verified = false;
                if (try readIfExists(io, gpa, mlir_golden)) |expected| {
                    if (try compare(gpa, io, &w.failures, display_path, "mlir", mlir_golden, expected, ir.written(), env.update, false)) {
                        std.debug.print("updated {s}\n", .{mlir_golden});
                    }

                    matching_mlir = std.mem.eql(u8, expected, ir.written());
                }

                float_literals_survive = try checkFloatRoundTrip(gpa, &w.failures, display_path, &ast, &table, &case, ir.written());

                // Which streams this case records, read once: the same answer
                // says whether the case is built at all, which of its goldens
                // nothing would compare, and what each is compared against.
                // One entry per stream, which is what the question is about.
                var golden_of: [streams.len][]const u8 = undefined;
                var recorded: [streams.len]?[]const u8 = undefined;
                for (streams, 0..) |s, k| {
                    golden_of[k] = try std.mem.concat(gpa, u8, &.{ stem, s.ext });
                    recorded[k] = try readIfExists(io, gpa, golden_of[k]);
                }
                const want_exit = recorded[comptime streamIndex(".exit")];
                const want_err = recorded[comptime streamIndex(".err")];

                // Recording an exit status is how a case asks to be built
                // and run, so a case asking about any other stream without
                // one is never run and its golden is never compared. Nothing
                // fails, and the case reads exactly like one that checks
                // what a program says.
                if (want_exit == null) {
                    for (streams, 0..) |s, k| {
                        if (s.asks_for_a_run) continue;
                        if (recorded[k] == null) continue;
                        try w.failures.append(gpa, .{
                            .path = display_path,
                            .what = "records what it says but not what it answers",
                            .expected = "an `.exit` golden, which is what asks for a run",
                            .actual = try std.fmt.allocPrint(gpa, "a `{s}` golden nothing compares", .{s.ext}),
                        });
                    }
                }

                // Building is the expensive step, so it happens when a case asks
                // for it by recording an exit status -- and, where the run
                // is narrowed to what a sanitizer can see, when the case
                // reaches the runtime at all. It reaches it by printing,
                // which a `.out` golden records, or by trapping, which the
                // exit status records. A case recording a report of the
                // checking allocator is not run against a runtime that holds
                // none: it would differ from its golden, and accepting that
                // difference would record the defect the report is about.
                const needs_checks = want_exit != null and !env.checks_storage and recordsStorageReport(want_exit.?);
                if (needs_checks) {
                    if (env.unchecked_skips) |count| _ = count.fetchAdd(1, .monotonic);
                }
                if (want_exit != null and !needs_checks) {
                    if (env.runtime_path) |rt| {
                        const case_name = try scratchName(gpa, stem);
                        const outcome_zone = tracy.beginZone(@src(), "case.outcome");
                        const ran = try outcomeOf(gpa, io, env.cache, .{
                            .scratch = env.scratch_dir,
                            .name = case_name,
                            .ir = ir.written(),
                            .runtime = rt,
                            .sanitize = env.sanitize,
                            .foreign = case.foreign(&program),
                        });
                        outcome_zone.end();
                        native_verified = !ran.tool_failed;
                        if (!ran.tool_failed) {
                            answered = .{
                                .display_path = display_path,
                                .name = case_name,
                                .answer = ran.text,
                                .output = ran.output,
                                .errors = ran.errors,
                                .foreign = case.foreign(&program),
                            };
                            answered_env = .{
                                .scratch = env.scratch_dir,
                                .runtime = rt,
                                .sanitize = env.sanitize,
                            };
                        }

                        // Every stream against the golden recording it, off
                        // the one table that says which exist. The status is
                        // a byte, so a case that prints is otherwise pinned
                        // by how many bytes went and not by which ones --
                        // and getting the digits of a number wrong is
                        // exactly the failure a count cannot see. Nothing
                        // else says which descriptor bytes reached, either:
                        // a status is the same byte whichever it was, and
                        // the streams are recorded apart precisely so a case
                        // can assert one of them and not the other.
                        const failures_before = w.failures.items.len;
                        for (streams, 0..) |s, k| {
                            const expected = recorded[k] orelse continue;
                            if (try compare(
                                gpa,
                                io,
                                &w.failures,
                                display_path,
                                s.ext[1..],
                                golden_of[k],
                                expected,
                                s.of(ran),
                                env.update and !ran.tool_failed,
                                s.empty_is_an_answer,
                            )) {
                                std.debug.print("updated {s}\n", .{golden_of[k]});
                            }
                        }
                        if (want_err == null) try showStderrOfMismatches(gpa, w.failures.items[failures_before..], ran.errors);

                        if (env.properties and !ran.tool_failed) {
                            try checkMaterializedDerives(
                                gpa,
                                scratch_parent,
                                io,
                                env.cache,
                                .{
                                    .scratch = env.scratch_dir,
                                    .runtime = rt,
                                    .sanitize = env.sanitize,
                                },
                                &w.failures,
                                &w.materialized_derives,
                                display_path,
                                case_name,
                                &program,
                                &settled.expanded,
                                &settled.res,
                                ir.written(),
                                ran.text,
                                ran.output,
                                ran.errors,
                                try besideOf(gpa, case),
                                case.foreign(&program),
                            );
                        }

                        // A program with no undefined behaviour answers alike
                        // however it is optimised, and a whole module is as
                        // good a subject as one file.
                        if (env.levels and !ran.tool_failed) {
                            switch (try levelsAgree(gpa, io, env.cache, &w.failures, .{
                                .scratch = env.scratch_dir,
                                .name = case_name,
                                .ir = ir.written(),
                                .runtime = rt,
                                .sanitize = env.sanitize,
                                .foreign = case.foreign(&program),
                            }, ran, display_path, null)) {
                                .agreed => w.levels_agreed += 1,
                                .disagreed, .unbuilt => {},
                            }
                        }

                        // The rewrites read one file's text. A module of several is
                        // covered by the file order transform instead, which is
                        // what its own counter reports.
                        var rewritten = false;
                        if (env.properties and !ran.tool_failed and case.files.len == 1) {
                            const rewrites_zone = tracy.beginZone(@src(), "case.rewrites");
                            rewritten = try checkRewrites(gpa, io, env.cache, .{
                                .scratch = env.scratch_dir,
                                .runtime = rt,
                                .sanitize = env.sanitize,
                            }, &w.failures, &w.rewrites, .{
                                .display_path = display_path,
                                .name = case_name,
                                .source = &Source{ .path = case.files[0].path, .text = case.files[0].text },
                                .ast = if (alone) |*a| &a.ast else &ast,
                                .res = if (alone) |*a| &a.resolved.resolution else res,
                                .typing = if (alone) |*a| &a.typing else typing,
                                .semantics = .{
                                    .ast = &settled.expanded.ast,
                                    .program = &program,
                                    .res = res,
                                    .typing = typing,
                                    .file = program.primaryFile(),
                                },
                                .answer = ran.text,
                                .output = ran.output,
                                .errors = ran.errors,
                                .ir = ir.written(),
                                .beside = try besideOf(gpa, case),
                                .foreign = case.foreign(&program),
                            });
                            rewrites_zone.end();
                        }

                        // What a case says on standard error is otherwise
                        // compared once, against the golden beside it: the
                        // status is the same byte whatever was said, so the
                        // rewrites are the only thing holding that text to a
                        // source the compiler is free to read differently. A
                        // case every transform declines is outside that
                        // property while reading, from the corpus, exactly
                        // like one inside it.
                        if (env.properties and !ran.tool_failed and want_err != null and !rewritten) {
                            try w.failures.append(gpa, .{
                                .path = display_path,
                                .what = "records what it said but is reached by no rewrite",
                                .expected = "a source some transform applies to",
                                .actual = "a `.err` golden no rewrite holds the case to",
                            });
                        }

                        // Every case that ran, whatever it is made of: a
                        // change below the source slices no text, so a
                        // module of several files is as good a subject as
                        // one of a single file.
                        if (env.properties and !ran.tool_failed) {
                            const damage_zone = tracy.beginZone(@src(), "case.damage");
                            try checkDamage(gpa, io, env.cache, .{
                                .scratch = env.scratch_dir,
                                .runtime = rt,
                                .sanitize = env.sanitize,
                            }, &w.failures, &w.damages, &table, &settled.expanded, res, typing, disposals, .{
                                .display_path = display_path,
                                .name = case_name,
                                .answer = ran.text,
                                .errors = ran.errors,
                                .foreign = case.foreign(&program),
                            });
                            damage_zone.end();
                        }
                    } else {
                        // Without a runtime the case cannot be built, so its
                        // recorded status would be compared against nothing.
                        try w.failures.append(gpa, .{
                            .path = display_path,
                            .what = "records an exit status, and this run has no runtime to build it with",
                            .expected = "`--runtime <archive>`, which is what lets a recorded status be compared",
                            .actual = "no runtime given",
                        });
                    }
                }
                if (matching_mlir) try verifyRecordedModule(gpa, io, &w.failures, display_path, mlir_golden, native_verified);
            }
        }
    }
    backend_zone.end();

    // Property: every float literal the case spells reaches the backend as
    // the double it means. Checked where the case emitted and spelled one;
    // a rejected case, one the backend refused, or one with no float in it
    // gives the property nothing to read and is passed over.
    const finish_zone = tracy.beginZone(@src(), "case.finish");
    defer finish_zone.end();
    tally(&w.properties, &w.passed_over, .float_round_trip, float_literals_survive);

    // The three properties about what a walk does with what it walks. Each
    // reads the program's own tree -- the types are what say a Linear element
    // from a discardable one, and they need the library the case imports -- and cuts
    // the case's own text, which is what the source check inside each holds.
    //
    // A case of several files is passed over: the mutations below are built by
    // splicing one text, and a case that is a directory has no single one.
    var consumes = false;
    var lends = false;
    var named = false;
    if (env.properties and !rejected and case.files.len == 1) {
        const text = case.files[0].text;
        consumes = try checkWalkConsumes(gpa, &w.failures, display_path, &ast, typing, text, program.kind);
        lends = try checkWalkLends(gpa, &w.failures, display_path, &ast, typing, text, &w.walks_also, program.kind);
    }
    // Over every case, rejected ones included: what this reads is a
    // diagnostic, and a case reporting one is a case that was refused.
    named = try checkWalkNamed(gpa, &w.failures, display_path, &ast, &sink);
    if (env.properties) {
        tally(&w.properties, &w.passed_over, .walk_consumes, consumes);
        tally(&w.properties, &w.passed_over, .walk_lends, lends);
    }
    tally(&w.properties, &w.passed_over, .walk_named, named);

    // Every case, rejected ones included and whether or not it was run: a
    // walk the compiler refuses is as much a claim about the loop it stands
    // for as one it runs. A case of several files has each file's walks
    // written out in turn. A case that did not parse is passed over: a walk
    // the parser recovered is written out as a loop the source never spelled,
    // and the rewrite would drop the very mistake the case was refused for.
    var walks_written_out = false;
    if (loaded_cleanly) {
        const walk_zone = tracy.beginZone(@src(), "case.walk-loops");
        // Which loaded file each of the case's files is. A file the loader
        // never reached is not one the rewrite can read the walks of.
        const file_ids = try gpa.alloc(?FileId, case.files.len);
        for (case.files, file_ids) |cf, *id| {
            id.* = for (ast.parts) |part| {
                if (std.mem.eql(u8, table.get(part.file).path, cf.path)) break part.file;
            } else null;
        }
        walks_written_out = try checkWalkLoops(gpa, io, env.cache, env.library, &w.failures, .{
            .display_path = display_path,
            .entry = case.entry,
            .files = case.files,
            .file_ids = file_ids,
            .beside = try besideOf(gpa, case),
            .semantics = .{
                .ast = &settled.expanded.ast,
                .program = &program,
                .res = res,
                .typing = typing,
                .file = program.primaryFile(),
            },
            .rules = rules_named,
            .ran = if (answered) |a| .{ .env = answered_env, .answered = a } else null,
        });
        walk_zone.end();
    }
    tally(&w.properties, &w.passed_over, .walk_loops, walks_written_out);

    // Every case, counted where one of its diagnostics carried a fix. A case
    // of several files is passed over: the fix is written into one file's
    // text and recompiled alone.
    var kinds_carried: std.EnumSet(diagnostic.FixKind) = .initEmpty();
    if (env.corpus_properties and case.files.len == 1 and sink.hasErrors()) {
        kinds_carried = try checkHelpEdits(gpa, &w.failures, display_path, sink.items(), program.primaryFile(), case.files[0].text, program.kind);
    }
    tally(&w.properties, &w.passed_over, .help_edits, kinds_carried.count() > 0);
    var kinds = kinds_carried.iterator();
    while (kinds.next()) |k| w.fix_kinds.put(k, (w.fix_kinds.get(k) orelse 0) + 1);

    // And the one the mutation asserts, counted from what it did rather than
    // asked again: a case is checked here exactly where it claimed it, so a
    // mutation that stops applying takes this number down with it.
    if (env.properties) {
        tally(&w.properties, &w.passed_over, .range_exhaustive, (w.mutations.get(.narrowed_range) orelse 0) > narrowed_before);
    }

    // An expectation that stops being reachable has to say so. A case
    // whose program the compiler now rejects generates no code, and
    // leaving its recorded status uncompared would retire the case without
    // anyone deciding to.
    if (rejected) {
        // Every golden a rejected case cannot produce, not just the exit
        // status. A dump is written from a program that got past the
        // diagnostics, so one recorded beside a case that does not is
        // compared against nothing -- and a golden nothing compares is a
        // check that cannot fail while still being counted.
        for (produced_by_a_run) |ext| {
            const golden = try std.mem.concat(gpa, u8, &.{ stem, ext });
            if (try readIfExists(io, gpa, golden)) |_| {
                try w.failures.append(gpa, .{
                    .path = display_path,
                    .what = try std.fmt.allocPrint(
                        gpa,
                        "records a `{s}` golden but is rejected before code is generated",
                        .{ext},
                    ),
                    .expected = "a program that builds",
                    .actual = "a diagnostic",
                });
            }
        }
    }

    // Read from the sink rather than from the goldens: a case that reports
    // a rule exercises it whether or not it also records the text, and a
    // rule reached only by a case with no `.stderr` would otherwise look
    // unreached.
    for (sink.list.items) |d| {
        if (d.code) |c| w.rules_reached.put(c, {});
    }

    const stderr_golden = try std.mem.concat(gpa, u8, &.{ stem, ".stderr" });
    if (try readIfExists(io, gpa, stderr_golden)) |expected| {
        var out: std.Io.Writer.Allocating = .init(gpa);
        try render.renderAll(&out.writer, &table, &sink, .{ .color = .never });
        if (try compare(gpa, io, &w.failures, display_path, "stderr", stderr_golden, expected, out.written(), env.update, false)) {
            std.debug.print("updated {s}\n", .{stderr_golden});
        }
    }
    return settled.reused_library;
}

test "recovery answers retain results rather than compilation regions" {
    var keep = std.heap.ArenaAllocator.init(testing.allocator);
    defer keep.deinit();
    var counted: Counting = .{ .under = keep.allocator() };
    const gpa = counted.allocator();
    var index: lsp_workspace.Index = .{ .gpa = gpa, .root = "", .programs = &.{}, .entries = .empty };
    const query: lsp_workspace.Query = .{ .index = &index, .modules = &.{}, .entry_order = &.{} };
    const files = [_]InMemoryFile{.{ .path = "p/main.lin", .text = "fn main() -> UInt8 { 0 }\n" }};
    const probe = try recoveryProbe(gpa, "p", .at_a_statement, "");
    for (0..4) |_| {
        const answer = (try answerFor(gpa, testing.allocator, test_library.get(), query, "p", &files, probe)).?;
        try testing.expect(answer.labels.len > 0);
    }
    // Four small label/rule lists need less than one MiB of retained storage.
    try testing.expect(counted.took < 1 << 20);
}

test "body type annotations receive every settled-reference oracle visit" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    var checked = try lsp_analysis.of(gpa, gpa, test_library.get(), &.{.{ .path = "main.lin", .text =
        \\trait Has { type Item: Copyable }
        \\struct Cell[X] { value: X }
        \\fn _invoke[T: Has](value: T.Item) {
        \\    let _direct = [value] || -> T.Item where carries(value) copy(value)
        \\    let _grouped = [value] || -> (T.Item) where carries(value) copy(value)
        \\    let _array = [value] || -> [T.Item; 1] where carries(value) [copy(value)]
        \\    let _borrow = [value] || -> borrow T.Item where borrows(value) borrow value
        \\    let _param_direct = |_item: T.Item| {}
        \\    let _param_grouped = |_item: (T.Item)| {}
        \\    let _param_array = |_item: [T.Item; 1]| {}
        \\    let _param_borrow = |_item: borrow T.Item| {}
        \\    let _literal = Cell[T.Item] { value = copy(value) }
        \\}
        \\fn main() -> UInt8 { 0 }
    }}, "main.lin");
    defer checked.deinit();
    try testing.expect(!checked.sink.hasErrors());
    var failures: std.ArrayList(Failure) = .empty;
    var properties: std.EnumMap(Property, u32) = .{};
    var passed_over: std.EnumMap(Property, u32) = .{};
    var declined: PassedSettledRefs = .{};
    const in_library = try libraryFiles(gpa, &checked.program);
    const written = settledRefsWritten(&checked.program.ast, &checked.program, in_library);
    try testing.expectEqual(@as(u32, 10), written);
    try checkSettledRefs(gpa, &failures, &properties, &passed_over, &declined, "main.lin", &checked.program, &checked.semantics.res, &checked.semantics.typing, in_library);
    try testing.expectEqual(@as(usize, 0), failures.items.len);
    try testing.expectEqual(written, (properties.get(.settled_refs) orelse 0) + (passed_over.get(.settled_refs) orelse 0));
}

test "derive arguments receive every selected reference oracle visit" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    var checked = try lsp_analysis.of(gpa, gpa, test_library.get(), &.{.{ .path = "main.lin", .text =
        \\trait Source { type Item }
        \\struct Token {}
        \\impl Source for Token { type Item = UInt8 }
        \\trait Use[A] { fn consume(_value: A) -> UInt8 }
        \\template impl[A] Use[A] {
        \\    fn consume(_value: A) -> UInt8 { 0 }
        \\}
        \\struct Target {}
        \\derive Use[Token.Item] for Target
        \\fn main() -> UInt8 { let _target: Target = .{}; 0 }
    }}, "main.lin");
    defer checked.deinit();
    try testing.expect(!checked.sink.hasErrors());
    var failures: std.ArrayList(Failure) = .empty;
    var properties: std.EnumMap(Property, u32) = .{};
    var passed_over: std.EnumMap(Property, u32) = .{};
    var declined: PassedSettledRefs = .{};
    const in_library = try libraryFiles(gpa, &checked.program);
    const written = settledRefsWritten(&checked.program.ast, &checked.program, in_library);
    try testing.expectEqual(@as(u32, 1), written);
    try checkSettledRefs(gpa, &failures, &properties, &passed_over, &declined, "main.lin", &checked.program, &checked.semantics.res, &checked.semantics.typing, in_library);
    try testing.expectEqual(@as(usize, 0), failures.items.len);
    try testing.expectEqual(written, (properties.get(.settled_refs) orelse 0) + (passed_over.get(.settled_refs) orelse 0));
}
