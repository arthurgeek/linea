const std = @import("std");
const tracy = @import("../support/tracy.zig");
const testing = std.testing;
const library = @import("library.zig");

const source_mod = @import("../support/source.zig");
const Source = source_mod.Source;
const FileId = source_mod.FileId;
const FileTable = source_mod.FileTable;
const Sink = @import("../diagnostics/sink.zig").Sink;
const Code = @import("../diagnostics/diagnostic.zig").Code;
const Interner = @import("../support/interner.zig").Interner;
const resolve = @import("../sema/resolve.zig").resolve;
const Resolution = @import("../sema/resolve.zig").Resolution;
const ExpandedProgram = @import("../syntax/expanded_program.zig").ExpandedProgram;
const Typing = @import("../sema/types.zig").Typing;
const typecheck = @import("../sema/typecheck.zig").typecheck;
const checkOwnership = @import("../ownership/check.zig").check;
const DisposalPlan = @import("../ownership/cfg.zig").DisposalPlan;
const node = @import("../syntax/node.zig");
const DeclId = node.DeclId;
const program_mod = @import("../syntax/program.zig");
const ModuleId = program_mod.ModuleId;
const Module = program_mod.Module;
const Import = program_mod.Import;
const Program = program_mod.Program;
const standard_root = program_mod.RootId.from(1);
const Modules = @import("../parser/parser.zig").Modules;
const ParsedFile = @import("../parser/parser.zig").ParsedFile;
const instantiate = @import("../sema/instantiate.zig").instantiate;
const Purpose = @import("../sema/resolve.zig").Purpose;

/// The first element of an import path that reaches the `std` dependency
/// rather than the importing root. A directory of the program with that name
/// cannot capture it, so what `std` means does not depend on what happens to
/// sit beside the importing module.
pub const standard_dependency = library.dependency_name;

/// A file as a test supplies it, without touching the filesystem.
pub const InMemoryFile = struct {
    path: []const u8,
    text: []const u8,
};

fn lessByPath(_: void, a: InMemoryFile, b: InMemoryFile) bool {
    return std.mem.lessThan(u8, a.path, b.path);
}

/// The directory part of a path, or "" for a bare filename.
fn dirOf(path: []const u8) []const u8 {
    const slash = std.mem.lastIndexOfScalar(u8, path, '/') orelse return "";
    return path[0..slash];
}

/// The last element of a path, which for a directory is the module's name.
pub fn nameOf(dir: []const u8) []const u8 {
    if (dir.len == 0) return "";
    const slash = std.mem.lastIndexOfScalar(u8, dir, '/') orelse return dir;
    return dir[slash + 1 ..];
}

/// Whether source paths and text borrow the input buffers or are copied into
/// a source allocator. Copied buffers have that allocator's lifetime; module
/// metadata uses the allocator supplied to loading and is owned by the program.
pub const MemoryOwnership = union(enum) { borrow, copy: std.mem.Allocator };

const Input = union(enum) { disk: std.Io, memory: MemoryOwnership };

/// Every module the entry reaches, with its imports resolved.
///
/// `entry` is either one file's path -- in which case that file alone is the
/// root module -- or a directory prefix, in which case every `.lin` file
/// directly inside it is. The asymmetry is deliberate: a conformance corpus is
/// a flat directory of unrelated single-file programs, and a directory-only
/// rule would make one module of them all.
pub fn loadFromMemory(
    gpa: std.mem.Allocator,
    table: *FileTable,
    sink: *Sink,
    interner: *Interner,
    entry: []const u8,
    files: []const InMemoryFile,
    /// What the compilation is for, which decides whether every module beneath
    /// the root is loaded or only those an import reaches.
    purpose: Purpose,
    /// Whether the standard library is loaded beside the program.
    ///
    /// The caller's decision rather than this pass's: a test that asks what a
    /// set of files loads to is asking about those files, and a compilation
    /// is asking about a program, which the library is part of.
    with_library: bool,
    ownership: MemoryOwnership,
) !Program {
    return loadInputs(gpa, .{ .memory = ownership }, table, sink, interner, entry, null, files, purpose, with_library, null);
}

/// Parsed embedded library storage shared by compilations in one driver session.
/// The prefix must outlive every compilation loaded from it.
pub const LibraryPrefix = struct {
    arena: std.heap.ArenaAllocator,
    program: Program,
    table: FileTable,
    interner: Interner,

    pub fn init(backing: std.mem.Allocator) !LibraryPrefix {
        var arena: std.heap.ArenaAllocator = .init(backing);
        errdefer arena.deinit();
        const gpa = arena.allocator();
        var table: FileTable = .empty;
        var sink: Sink = .init(gpa);
        var interner: Interner = .empty;
        const program: Program = blk: {
            var loader: Loader = .{
                .gpa = gpa,
                .table = &table,
                .sink = &sink,
                .files = &.{},
                .input = .{ .memory = .borrow },
                .trees = Modules.init(gpa, &sink, &interner),
            };
            defer loader.deinit();
            try loader.loadLibrary();
            if (sink.hasErrors()) return error.InvalidLibraryPrefix;
            break :blk .{
                .modules = try loader.modules.toOwnedSlice(gpa),
                .import_routes = try loader.routes.toOwnedSlice(gpa),
                .primary = loader.prelude,
                .prelude = loader.prelude,
                .kind = .library,
                .ast = try loader.trees.finish(),
            };
        };
        return .{ .arena = arena, .program = program, .table = table, .interner = interner };
    }

    pub fn deinit(self: *LibraryPrefix) void {
        self.arena.deinit();
        self.* = undefined;
    }

    /// Loads with stable library source IDs into an empty file/name context.
    /// Mutable syntax and module storage belongs to the supplied allocator.
    pub fn loadFromMemory(
        self: *const LibraryPrefix,
        gpa: std.mem.Allocator,
        table: *FileTable,
        sink: *Sink,
        interner: *Interner,
        entry: []const u8,
        files: []const InMemoryFile,
        purpose: Purpose,
        ownership: MemoryOwnership,
    ) !Program {
        std.debug.assert(table.count() == 0 and interner.count() == 0);
        // The library compiled as itself shares nothing with the copy a
        // prefix holds; it is loaded on its own.
        if ((try declaredGiven(gpa, files)).standard) return loadInputs(gpa, .{ .memory = ownership }, table, sink, interner, entry, null, files, purpose, true, null);
        interner.* = try Interner.initPrefix(gpa, &self.interner);
        for (self.table.sources.items) |source| _ = try table.add(gpa, source);
        return loadInputs(gpa, .{ .memory = ownership }, table, sink, interner, entry, null, files, purpose, true, self);
    }
};

/// Immutable library state shared by compilations in a driver session.
/// Each resumed compilation owns its mutable tables and must end before this
/// session is released. The heap address keeps borrowed program pointers stable.
pub const CheckedLibrary = struct {
    backing: std.mem.Allocator,
    arena: std.heap.ArenaAllocator,
    sources: LibraryPrefix,
    resolved: @import("../sema/resolve.zig").LibraryPrefix,
    checked: @import("../sema/typecheck.zig").LibraryPrefix,
    disposals: DisposalPlan,

    pub fn init(backing: std.mem.Allocator) !*CheckedLibrary {
        const self = try backing.create(CheckedLibrary);
        errdefer backing.destroy(self);
        self.backing = backing;
        self.arena = std.heap.ArenaAllocator.init(backing);
        errdefer self.arena.deinit();
        self.sources = try LibraryPrefix.init(backing);
        errdefer self.sources.deinit();
        var sink = Sink.init(self.arena.allocator());
        self.resolved = try @import("../sema/resolve.zig").resolveLibraryPrefix(backing, &self.sources.program, &self.sources.interner, &sink);
        errdefer self.resolved.deinit();
        self.checked = try @import("../sema/typecheck.zig").typecheckLibraryPrefix(backing, &self.resolved.result.expanded, &self.resolved.result.resolution, &sink);
        errdefer self.checked.deinit();
        var scratch = std.heap.ArenaAllocator.init(backing);
        defer scratch.deinit();
        self.disposals = try checkOwnership(self.arena.allocator(), scratch.allocator(), &self.resolved.result.expanded, &self.resolved.result.resolution, &self.checked.typing, &sink);
        if (sink.hasErrors()) return error.InvalidLibraryPrefix;
        return self;
    }

    pub fn deinit(self: *CheckedLibrary) void {
        const backing = self.backing;
        self.checked.deinit();
        self.resolved.deinit();
        self.sources.deinit();
        self.arena.deinit();
        backing.destroy(self);
    }

    pub fn loadFromMemory(
        self: *const CheckedLibrary,
        gpa: std.mem.Allocator,
        table: *FileTable,
        sink: *Sink,
        interner: *Interner,
        entry: []const u8,
        files: []const InMemoryFile,
        purpose: Purpose,
        ownership: MemoryOwnership,
    ) !Program {
        std.debug.assert(table.count() == 0 and interner.count() == 0);
        // The library compiled as itself shares nothing with the copy a
        // prefix holds; it is loaded on its own.
        if ((try declaredGiven(gpa, files)).standard) return loadInputs(gpa, .{ .memory = ownership }, table, sink, interner, entry, null, files, purpose, true, null);
        const diagnostic_count = sink.list.items.len;
        const error_count = sink.error_count;
        const warning_count = sink.warning_count;
        interner.* = try Interner.initPrefix(gpa, &self.resolved.interner);
        for (self.sources.table.sources.items) |source| _ = try table.add(gpa, source);
        // Borrow while deciding eligibility: copied source buffers belong to the
        // caller and cannot be reclaimed through Program or FileTable.
        var candidate = try loadInputs(gpa, .{ .memory = .borrow }, table, sink, interner, entry, null, files, purpose, true, &self.sources);
        const compatible = self.resolved.canResume(&candidate, interner);
        if (compatible and ownership == .borrow) return candidate;
        candidate.deinit(gpa);
        interner.deinit(gpa);
        table.deinit(gpa);
        interner.* = .empty;
        table.* = .empty;
        sink.list.items.len = diagnostic_count;
        sink.error_count = error_count;
        sink.warning_count = warning_count;
        if (compatible) {
            interner.* = try Interner.initPrefix(gpa, &self.resolved.interner);
            for (self.sources.table.sources.items) |source| _ = try table.add(gpa, source);
        }
        return loadInputs(gpa, .{ .memory = ownership }, table, sink, interner, entry, null, files, purpose, true, if (compatible) &self.sources else null);
    }

    pub fn checkProgram(
        self: *const CheckedLibrary,
        gpa: std.mem.Allocator,
        scratch: std.mem.Allocator,
        program: *const Program,
        source_interner: *const Interner,
        sink: *Sink,
        purpose: Purpose,
    ) !Semantics {
        return checkProgramInternal(gpa, scratch, program, source_interner, sink, purpose, self, false);
    }

    /// Editor analysis prepares complete method lists at written selections.
    pub fn checkEditorProgram(
        self: *const CheckedLibrary,
        gpa: std.mem.Allocator,
        scratch: std.mem.Allocator,
        program: *const Program,
        source_interner: *const Interner,
        sink: *Sink,
    ) !Semantics {
        return checkProgramInternal(gpa, scratch, program, source_interner, sink, .program, self, true);
    }
};

fn loadInputs(
    gpa: std.mem.Allocator,
    input: Input,
    table: *FileTable,
    sink: *Sink,
    interner: *Interner,
    entry: []const u8,
    /// The directory of the module a named file selected as the entry, inside
    /// the source root `entry` names; null makes the root's own module the
    /// entry.
    module: ?[]const u8,
    files: []const InMemoryFile,
    purpose: Purpose,
    with_library: bool,
    prefix: ?*const LibraryPrefix,
) !Program {
    const zone = tracy.beginZone(@src(), "load");
    defer zone.end();

    const sorted = try gpa.dupe(InMemoryFile, files);
    defer gpa.free(sorted);
    std.mem.sort(InMemoryFile, sorted, {}, lessByPath);

    var l: Loader = .{
        .gpa = gpa,
        .table = table,
        .sink = sink,
        .files = sorted,
        .input = input,
        .trees = if (prefix) |cached|
            try Modules.initPrefix(gpa, sink, interner, &cached.program.ast)
        else
            Modules.init(gpa, sink, interner),
    };
    defer l.deinit();
    if (prefix) |cached| try l.seedLibrary(cached);
    const prefix_modules = l.modules.items.len;

    const entry_is_file = std.mem.endsWith(u8, entry, ".lin");
    const dir = if (entry_is_file) dirOf(entry) else entry;
    l.primary_dir = dir;

    // Decided before anything is loaded, because the first import followed may
    // already be a rooted one and the answer decides what it names. Read from
    // the root's manifest, which is what says a root is the library every
    // program depends on -- never from where the root sits or how it is named.
    const declared = try declaredGiven(gpa, sorted);
    l.program_is_library = declared.standard;

    var primary = if (module) |named| try l.load(named, null) else try l.load(dir, if (entry_is_file) entry else null);

    // Every module beneath the root, and not only those an import reaches.
    //
    // What a program's artefact needs is what its entry point reaches, which
    // is why loading follows imports. What a root's tests are is a different
    // question with a different answer: a module written to hold tests is
    // exactly the one nothing imports, so answering it by reachability finds
    // none of them and says so in a transcript that reads as success.
    //
    // Idempotent, because a module already loaded is returned rather than
    // loaded twice -- one directory is one module however many routes reach
    // it, and this is another route.
    if (purpose == .tests and !entry_is_file) {
        for (sorted) |f| {
            // A named module's tests are its own and those beneath it.
            if (module) |named| if (!within(dirOf(f.path), named)) continue;
            _ = try l.load(dirOf(f.path), null);
        }
    }

    // A program with no readable entry still has to be a program: every pass
    // below takes a tree, and an empty one reports the missing entry point
    // exactly as an empty file does.
    //
    // Before the library rather than after, for the reason the library is
    // loaded last at all: the root module is index zero, and a program that
    // read nothing would otherwise leave that index to the library -- which
    // then answers every question asked of the program, including which
    // source is missing a `main`.
    if (l.modules.items.len == prefix_modules) {
        // The directory, copied once and held by the module, which is what
        // releases it. The table and module name borrow that owned copy:
        // the entry argument only needs to live through the load.
        var transferred = false;
        const named = try gpa.dupe(u8, dir);
        errdefer if (!transferred) gpa.free(named);
        const empty: Source = .{ .path = named, .text = "" };
        const files_of = try gpa.alloc(FileId, 1);
        errdefer if (!transferred) gpa.free(files_of);
        files_of[0] = try table.add(gpa, empty);
        const decls = try l.trees.add(&.{.{ .file = files_of[0], .source = empty }});
        try l.modules.append(gpa, .{
            .name = nameOf(named),
            .dir = named,
            .files = files_of,
            .decls = decls,
            .imports = &.{},
        });
        transferred = true;
        const route = try gpa.dupe(u8, "");
        l.routes.append(gpa, route) catch |err| {
            gpa.free(route);
            return err;
        };
    }

    if (primary == .none) primary = .from(prefix_modules);

    {
        const z = tracy.beginZone(@src(), "load.library");
        defer z.end();
        // A package is never its own dependency: the library compiled as
        // itself is already every module an import of it could reach.
        if (with_library and !l.program_is_library) try l.loadLibrary();
    }

    // The library loaded as the program is its own prelude. Nothing else can
    // be: the prelude is what every module names without asking, and the
    // module that publishes those names is the root here rather than something
    // loaded beside it. Without this the library compiles unable to see
    // `Option`, which is a program that cannot be built out of its own source.
    // The library loaded as the program rather than beside one, which is what
    // testing it on its own terms means.
    //
    // Both of these are otherwise `loadLibrary`'s to say, and it did not run:
    // which modules are the library's, so that a generated call can find what
    // it needs, and which module is the prelude, so that every module can name
    // `Option` without asking. Read from the root's manifest, the same answer
    // that kept the embedded copy from loading -- a second rule about what
    // counts as the library is the one thing this must not become.
    if (l.program_is_library) {
        // The library's own root module is its prelude, whichever of its
        // modules a named file made the entry.
        l.prelude = if (module != null) try l.load(dir, null) else primary;
        for (l.modules.items[prefix_modules..]) |*m| m.library = true;
    }

    // What the root's manifest grants, its modules may do. The library loaded
    // beside it took its own manifest's grant as it was loaded.
    for (l.modules.items[prefix_modules..]) |*m| {
        if (m.root == .primary) m.externs = declared.externs;
    }

    const z_tree = tracy.beginZone(@src(), "load.tree");
    defer z_tree.end();
    const kind = declared.kind;
    var ast = try l.trees.finish();
    errdefer ast.deinit(gpa);
    const modules = try l.modules.toOwnedSlice(gpa);
    errdefer {
        for (modules) |loaded| deinitModule(gpa, loaded);
        gpa.free(modules);
    }
    const routes = try l.routes.toOwnedSlice(gpa);
    return .{
        .modules = modules,
        .primary = primary,
        .import_routes = routes,
        .prelude = l.prelude,
        .named_module = module != null,
        // Read from the files in hand, because a manifest among them is what
        // marks the root whichever way they were gathered. A caller that read a
        // directory and one that built a program in memory are both loading a
        // root, and a kind recorded on only one of those paths is a library
        // that is a library to the compiler and a program to everything that
        // tests it.
        .kind = kind,
        .ast = ast,
    };
}

/// What a manifest among these files declares about the root.
///
/// The shallowest one, because a root's manifest sits above every module of it:
/// a program holding a submodule that carries a manifest of its own would
/// otherwise be read as whatever that submodule said.
pub fn declaredGiven(gpa: std.mem.Allocator, files: []const InMemoryFile) std.mem.Allocator.Error!Declared {
    // Total, unlike the read from disk. A manifest that will not parse stops a
    // command run against a root, because the person who ran it is there to be
    // told; in memory it leaves the files standing, because an editor holds
    // whatever is being typed and a half-written manifest is a normal state for
    // a file to be in. A root read as a program is what one without a manifest
    // already is.
    var shallowest: ?[]const u8 = null;
    var depth: usize = std.math.maxInt(usize);
    for (files) |f| {
        if (!std.mem.eql(u8, std.fs.path.basename(f.path), manifest_name)) continue;
        const at = std.mem.count(u8, f.path, "/");
        if (at < depth) {
            depth = at;
            shallowest = f.text;
        }
    }

    const text = shallowest orelse return .{};
    var parsed = std.json.parseFromSlice(Written, gpa, text, .{
        .ignore_unknown_fields = true,
    }) catch return .{};
    defer parsed.deinit();
    return declaredFrom(parsed.value) catch .{};
}

test "the shallowest manifest among the files declares the root" {
    const declared = try declaredGiven(testing.allocator, &.{
        .{ .path = "lib/inner/linea.json", .text = "{}" },
        .{ .path = "lib/linea.json", .text = "{ \"kind\": \"library\", \"name\": \"std\", \"extern\": true }" },
        .{ .path = "lib/main.lin", .text = "" },
    });
    try testing.expectEqual(Declared{ .kind = .library, .standard = true, .externs = true }, declared);
    try testing.expectEqual(Declared{}, try declaredGiven(testing.allocator, &.{.{ .path = "a/linea.json", .text = "{ not json" }}));
    try testing.expectEqual(Declared{}, try declaredGiven(testing.allocator, &.{.{ .path = "a/main.lin", .text = "" }}));
}

/// Every module the entry reaches, read from the filesystem.
///
/// Paths beneath the entry's directory are indexed up front. Source bytes are
/// read when a module is reached, so unrelated modules consume no source
/// buffers and cannot fail a compilation through an unreadable source file.
///
/// An entry naming a file is opened before that subtree is walked, so a path
/// that is not there is refused as itself. The walk starts one directory up
/// from a file, and a directory always answers with whatever it holds: a path
/// naming no file loaded that directory's other files and reported the module
/// they make short of a `main`, which is a statement about a program nobody
/// asked about.
pub fn loadFromDisk(
    gpa: std.mem.Allocator,
    io: std.Io,
    table: *FileTable,
    sink: *Sink,
    interner: *Interner,
    entry: []const u8,
    purpose: Purpose,
    with_library: bool,
) !Program {
    // A command line says which it means and is believed. Bounded by the
    // directory the compiler was run in, so a manifest further up names
    // somebody else's program and not this one.
    const found = try rootOf(gpa, io, entry, .as_named, "");
    defer found.deinit(gpa);
    const given = found.entry;

    if (std.mem.endsWith(u8, given, ".lin")) {
        const named = try std.Io.Dir.cwd().openFile(io, given, .{});
        named.close(io);
    }

    // Read strictly here, because the person who ran the command is there to
    // be told: a manifest that will not parse, or says what a root cannot be,
    // stops the command rather than loading the root as something else.
    if (found.manifest) |path| {
        const manifest = try readManifest(gpa, io, dirOf(path));
        if (manifest) |m| if (m.source) |named| gpa.free(named);
    }

    const paths = try pathsOfRoot(gpa, io, found);
    defer {
        for (paths) |q| gpa.free(q);
        gpa.free(paths);
    }

    var files: std.ArrayList(InMemoryFile) = .empty;
    defer files.deinit(gpa);
    var manifest_text: ?[]u8 = null;
    defer if (manifest_text) |text| gpa.free(text);

    // Sources are read when their module is reached. The manifest is read
    // now: what it declares decides how the first module is loaded.
    for (paths) |rel| {
        const is_manifest = if (found.manifest) |m| std.mem.eql(u8, rel, m) else false;
        if (is_manifest) manifest_text = try source_mod.readFileAlloc(io, gpa, rel);
        try files.append(gpa, .{
            .path = rel,
            .text = if (is_manifest) manifest_text.? else "",
        });
    }

    return loadInputs(gpa, .{ .disk = io }, table, sink, interner, given, found.module, files.items, purpose, with_library, null);
}

test "a path naming no file is refused as that path" {
    const gpa = testing.allocator;

    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "main.lin", .data = "fn main() -> UInt8 { 0 }\n" });

    const root = try std.fmt.allocPrint(gpa, ".zig-cache/tmp/{s}", .{tmp.sub_path});
    defer gpa.free(root);
    const absent = try std.fs.path.join(gpa, &.{ root, "not_here.lin" });
    defer gpa.free(absent);

    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();

    var table: FileTable = .empty;
    defer table.deinit(gpa);
    var sink = Sink.init(arena.allocator());
    var interner: Interner = .empty;
    defer interner.deinit(gpa);

    // The directory the path sits in holds a `main.lin`, so a load reaching the
    // walk would return that program and answer nothing about what was named.
    try testing.expectError(
        error.FileNotFound,
        loadFromDisk(gpa, testing.io, &table, &sink, &interner, absent, .program, false),
    );
}

test "disk loading reads source bytes only for reached modules" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "main.lin", .data = "fn main() -> UInt8 { 0 }\n" });
    try tmp.dir.createDirPath(testing.io, "unimported");
    const oversized = try tmp.dir.createFile(testing.io, "unimported/payload.lin", .{});
    defer oversized.close(testing.io);
    try oversized.setLength(testing.io, source_mod.max_bytes + 1);

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    const root = try std.fmt.allocPrint(gpa, ".zig-cache/tmp/{s}", .{tmp.sub_path});
    var table: FileTable = .empty;
    var sink = Sink.init(gpa);
    var interner: Interner = .empty;
    const program = try loadFromDisk(gpa, testing.io, &table, &sink, &interner, root, .program, false);
    try testing.expectEqual(@as(usize, 1), program.modules.len);
    try testing.expect(!sink.hasErrors());

    // Test discovery reaches modules even when the entry imports none of them.
    try testing.expectError(error.SourceTooLarge, loadFromDisk(gpa, testing.io, &table, &sink, &interner, root, .tests, false));
}

/// An entry as every comparison against it is written.
///
/// A trailing slash is what a shell's completion writes, and every path this
/// compares against is written without one -- so `dir/` matched no file, the
/// module loaded empty, and the compiler reported a program with no `main`
/// about source it never read.
///
/// One slash, not every trailing one: `trimEnd` turns `/` into the empty
/// string, which `rootOfEntry` reads as "no directory given" and resolves to
/// the working one, so naming the root would silently compile something else
/// entirely.
pub fn trimmedEntry(entry: []const u8) []const u8 {
    if (entry.len > 1 and entry[entry.len - 1] == '/') return entry[0 .. entry.len - 1];
    return entry;
}

/// The directory whose files an entry is looked for among.
///
/// Naming a file compiles the module that file belongs to, so the search
/// starts one level up; naming a directory starts there.
pub fn dirOfEntry(entry: []const u8) []const u8 {
    if (std.mem.endsWith(u8, entry, ".lin")) return dirOf(entry);
    return entry;
}

/// What marks a directory as the root of a program.
///
/// Its presence is the whole fact; an empty object is a complete one. It is
/// read rather than assumed, so a manifest that will not parse stops the
/// compilation instead of marking nothing.
pub const manifest_name = "linea.json";

/// What a caller can say about the path it named.
pub const Naming = enum {
    /// The path is what the caller meant. A directory names the program it
    /// sits in. A `.lin` file names its own module, as the entry of the
    /// program whose source holds it, or stands on its own where no
    /// program's source does.
    as_named,
    /// The path is a file or directory the caller found and nothing more, so it
    /// resolves to the program whose source holds it. An editor has a file and
    /// cannot say which program it meant.
    its_program,
};

/// A root a load starts from, and the manifest that identified it.
pub const Root = struct {
    /// Names what the load reads: the source root directory, or a file that
    /// stands on its own.
    entry: []u8,
    /// The path of the manifest that made `entry` a program's source root, or
    /// null where no manifest did. Its keys decide how the root is loaded, so
    /// it is found by the walk that found the root and never by another.
    manifest: ?[]u8 = null,
    /// The directory of the module a named `.lin` file belongs to, when that
    /// module is the entry rather than the source root's own module. Import
    /// paths still resolve from `entry`.
    module: ?[]u8 = null,

    pub fn deinit(self: Root, gpa: std.mem.Allocator) void {
        gpa.free(self.entry);
        if (self.manifest) |path| gpa.free(path);
        if (self.module) |dir| gpa.free(dir);
    }
};

/// Finds where a load starts, given a path somebody named, and the manifest
/// that identified it.
///
/// One composition of the three steps -- trim what a shell's completion wrote,
/// find the program the path belongs to, read where that program's source
/// begins -- because a command line and an editor must reach the same program
/// from the same path. The manifest comes from the same walk, so it always
/// describes the entry returned beside it.
///
/// A file the program's source root does not hold is a program on its own. An
/// editor opens such a file -- a scratch beside `src/`, a tool the build does
/// not compile -- and a program it is not part of has nothing to say about it,
/// so resolving it there leaves the document analysed by nothing at all.
/// Where a file under no manifest already lands is exactly here. A file the
/// source root does hold, named on the command line, names its own module as
/// the program's entry (`module`); a directory named on the command line
/// names the program it sits in, and an editor's path always names the whole
/// program, which is the whole of what `naming` says.
///
/// The walk covers the ancestors of the path that `bound` contains: the
/// command line does not look above the directory it was run in, and the
/// server does not look above the root the client sent. Unbounded, a manifest
/// in a home directory would capture every project beneath it.
///
/// Costs one `stat` per ancestor of the path, against a depth that is the
/// path's own and not the program's. The caller owns the result.
pub fn rootOf(
    gpa: std.mem.Allocator,
    io: std.Io,
    path: []const u8,
    naming: Naming,
    bound: []const u8,
) !Root {
    const trimmed = trimmedEntry(path);
    const marked = programRootOf(io, trimmed, bound);
    if (std.mem.endsWith(u8, marked, ".lin")) return .{ .entry = try canonical(gpa, marked) };

    const root = try sourceRootOf(gpa, io, marked);
    defer gpa.free(root);
    const settled = try canonical(gpa, root);
    errdefer gpa.free(settled);

    // A file, or a directory an editor found, stands on its own where the
    // program's source does not hold it.
    const is_file = std.mem.endsWith(u8, trimmed, ".lin");
    var module: ?[]u8 = null;
    errdefer if (module) |dir| gpa.free(dir);
    if (naming == .its_program or is_file) {
        const named = try canonical(gpa, trimmed);
        defer gpa.free(named);
        if (!within(dirOfEntry(named), settled)) {
            gpa.free(settled);
            return .{ .entry = try canonical(gpa, named) };
        }
        if (naming == .as_named and is_file and !std.mem.eql(u8, dirOfEntry(named), settled)) {
            module = try gpa.dupe(u8, dirOfEntry(named));
        }
    }
    const manifest = if (holdsManifest(io, marked))
        try std.fs.path.join(gpa, &.{ if (marked.len == 0) "." else marked, manifest_name })
    else
        null;
    return .{ .entry = settled, .manifest = manifest, .module = module };
}

test "a file inside a program's source is that program's entry module, with its manifest" {
    const gpa = testing.allocator;

    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "linea.json", .data = "{\"kind\": \"library\"}" });
    try tmp.dir.createDirPath(testing.io, "mem");
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "lib.lin", .data = "pub fn one() -> UInt8 { 1 }\n" });
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "mem/allocator.lin", .data = "pub fn two() -> UInt8 { 2 }\n" });

    const root = try std.fmt.allocPrint(gpa, ".zig-cache/tmp/{s}", .{tmp.sub_path});
    defer gpa.free(root);
    const file = try std.fs.path.join(gpa, &.{ root, "mem/allocator.lin" });
    defer gpa.free(file);
    const manifest = try std.fs.path.join(gpa, &.{ root, manifest_name });
    defer gpa.free(manifest);

    const mem = try std.fs.path.join(gpa, &.{ root, "mem" });
    defer gpa.free(mem);
    // The command line names the file's own module as the entry; an editor
    // names the whole program. Both read the program's manifest.
    const named = try rootOf(gpa, testing.io, file, .as_named, "");
    defer named.deinit(gpa);
    try testing.expectEqualStrings(root, named.entry);
    try testing.expectEqualStrings(manifest, named.manifest.?);
    try testing.expectEqualStrings(mem, named.module.?);
    const opened = try rootOf(gpa, testing.io, file, .its_program, "");
    defer opened.deinit(gpa);
    try testing.expectEqualStrings(root, opened.entry);
    try testing.expectEqualStrings(manifest, opened.manifest.?);
    try testing.expect(opened.module == null);
    const directory = try rootOf(gpa, testing.io, root, .as_named, "");
    defer directory.deinit(gpa);
    try testing.expectEqualStrings(root, directory.entry);
    try testing.expectEqualStrings(manifest, directory.manifest.?);
}

/// Returns `rootOf`'s entry, freeing the rest of what it found.
pub fn entryOf(
    gpa: std.mem.Allocator,
    io: std.Io,
    path: []const u8,
    naming: Naming,
    bound: []const u8,
) ![]u8 {
    const found = try rootOf(gpa, io, path, naming, bound);
    if (found.manifest) |manifest| gpa.free(manifest);
    if (found.module) |module| gpa.free(module);
    return found.entry;
}

/// Every file a root is made of, by path: its sources, and the manifest that
/// identified it. Both readers of a root from disk -- the command line and the
/// editor -- take their files here, so a root's manifest reaches both.
pub fn pathsOfRoot(gpa: std.mem.Allocator, io: std.Io, root: Root) ![][]const u8 {
    const sources = try pathsOfModule(gpa, io, dirOfEntry(root.entry));
    const manifest = root.manifest orelse return sources;
    defer gpa.free(sources);
    errdefer for (sources) |p| gpa.free(p);
    const all = try gpa.alloc([]const u8, sources.len + 1);
    errdefer gpa.free(all);
    @memcpy(all[0..sources.len], sources);
    all[sources.len] = try gpa.dupe(u8, manifest);
    return all;
}

test "a root's paths are its sources and the manifest that identified it" {
    const gpa = testing.allocator;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "linea.json", .data = "{\"source\": \"src\"}" });
    try tmp.dir.createDirPath(testing.io, "src");
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "src/main.lin", .data = "fn main() -> UInt8 { 0 }\n" });
    const root = try std.fmt.allocPrint(gpa, ".zig-cache/tmp/{s}", .{tmp.sub_path});
    defer gpa.free(root);

    const found = try rootOf(gpa, testing.io, root, .as_named, "");
    defer found.deinit(gpa);
    const paths = try pathsOfRoot(gpa, testing.io, found);
    defer {
        for (paths) |q| gpa.free(q);
        gpa.free(paths);
    }
    try testing.expectEqual(@as(usize, 2), paths.len);
    try testing.expect(std.mem.endsWith(u8, paths[0], "src/main.lin"));
    try testing.expect(std.mem.endsWith(u8, paths[1], manifest_name));
}

/// A path with the spellings that name one file written one way: `.` segments,
/// repeated separators and a trailing separator removed.
///
/// Which file a path names is decided by comparing the string, and two
/// spellings are two files. A buffer the editor holds is keyed by the path its
/// URI names and found by the path the loader's walk produced, so a manifest
/// of `{"source": "."}` -- which joins to `p/.` and walks to `p/./main.lin` --
/// was enough to make the server check the file on disk while the programmer
/// typed into the buffer, and to answer `null` to every question about the
/// document.
///
/// `..` is left alone: which directory it names is a question for the
/// filesystem, and this decides how a name is written rather than what it
/// points at. The empty path is left empty, since that is not a spelling
/// anybody wrote but the one that means no directory was given.
pub fn canonical(gpa: std.mem.Allocator, path: []const u8) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);

    const rooted = path.len > 0 and path[0] == '/';
    if (rooted) try out.append(gpa, '/');

    var segments = std.mem.tokenizeScalar(u8, path, '/');
    var wrote = false;
    while (segments.next()) |segment| {
        if (std.mem.eql(u8, segment, ".")) continue;
        if (wrote) try out.append(gpa, '/');
        try out.appendSlice(gpa, segment);
        wrote = true;
    }

    // A relative path of nothing but `.` names where it started, which is
    // written `.` rather than left empty.
    if (!wrote and !rooted and path.len > 0) try out.append(gpa, '.');
    return out.toOwnedSlice(gpa);
}

/// The program an entry belongs to: the nearest ancestor directory holding a
/// manifest, or the entry itself where there is none.
///
/// A module is a directory, and this says which module is the *program*.
/// Resolving a file to itself asks a module member to declare `main`, and
/// resolving it to its own directory asks the same of whichever submodule it
/// sits in.
///
/// The result is a slice of `entry`.
fn programRootOf(io: std.Io, entry: []const u8, bound: []const u8) []const u8 {
    var dir = dirOfEntry(entry);
    // A path the bound does not contain has no ancestor inside it, so there is
    // nothing to walk. Compared as a prefix rather than by length: a path
    // outside the workspace is longer than one inside it as often as not, and
    // a walk that stopped when the string got short enough climbed three
    // directories of somebody else's project and read the manifest it found
    // there.
    if (!within(dir, bound)) return entry;
    while (true) {
        if (holdsManifest(io, dir)) return dir;
        if (dir.len <= bound.len) return entry;
        const parent = dirOf(dir);
        if (parent.len == dir.len) return entry;
        dir = parent;
    }
}

/// How far above the working directory a project is looked for.
///
/// A bound rather than a walk to the filesystem root, because ascending by
/// `..` cannot tell the root from its own parent: `/..` is `/`, so an
/// unbounded loop would stat the same directory until something stopped it.
/// Deep enough that no real checkout is missed.
const roots_looked_up_through = 64;

/// The root of the project the working directory sits in, or null where none
/// does.
///
/// What a command with no path means. The manifest is what marks a program
/// ([ADR 0075](../../docs/adr/0075-a-program-root-is-a-directory-holding-a-manifest.md)),
/// so the nearest one above the working directory is the project a command run
/// without one is about -- and where there is none, there is no project here
/// and the caller says so rather than this guessing at a file.
///
/// Ascended by `..` rather than from an absolute path, because the answer is
/// handed to the same resolution a written path gets and a relative one is
/// what that already takes.
///
/// The caller owns the result.
pub fn rootFromHere(gpa: std.mem.Allocator, io: std.Io) !?[]const u8 {
    var above: std.ArrayList(u8) = .empty;
    defer above.deinit(gpa);
    try above.appendSlice(gpa, ".");

    for (0..roots_looked_up_through) |_| {
        if (holdsManifest(io, above.items)) return try gpa.dupe(u8, above.items);
        // `./..`, `./../..`, and so on. Kept as one string rather than
        // rebuilt, so the walk costs a stat per level and nothing else.
        try above.appendSlice(gpa, "/..");
    }
    return null;
}

/// Whether a directory is `bound` or sits beneath it. An empty bound contains
/// every path, which is what a caller that named no workspace means.
fn within(dir: []const u8, bound: []const u8) bool {
    if (bound.len == 0) return true;
    if (!std.mem.startsWith(u8, dir, bound)) return false;
    return dir.len == bound.len or dir[bound.len] == '/';
}

/// The directory whose files form a program's root module.
///
/// The manifest marks the program; this says where its source begins. They are
/// the same directory unless the manifest says otherwise, which is what keeps
/// a manifest holding `{}` a complete one and a flat layout the default.
///
/// A named source root is a directory like any other -- its subdirectories are
/// submodules exactly as they would be one level up -- so this decides one
/// thing only, and nothing downstream learns that `src` was involved.
///
/// The caller owns the result.
fn sourceRootOf(gpa: std.mem.Allocator, io: std.Io, root: []const u8) ![]const u8 {
    const manifest = try readManifest(gpa, io, root);
    defer if (manifest) |m| if (m.source) |named| gpa.free(named);

    const named = (manifest orelse return gpa.dupe(u8, root)).source orelse
        return gpa.dupe(u8, root);
    if (root.len == 0) return gpa.dupe(u8, named);
    return std.fs.path.join(gpa, &.{ root, named });
}

/// What a directory's manifest names as its source root, if it names one.
///
/// A manifest that will not parse is `error.ManifestNotJson` rather than a
/// program laid out flat. Read as flat, a typo in a project's one
/// configuration file reads back as a program with no `main`, which sends the
/// programmer looking through their source for a problem in a line of JSON.
///
/// A manifest that cannot be opened is no manifest, which is a different
/// thing: the walk that found this directory looked for the file, and a race
/// between the two is not a broken project.
/// A manifest as it was written, with every key this compiler reads.
///
/// One reader, because a file read twice is a file that can be answered two
/// ways. What each key means is decided beside it and nowhere else.
const Manifest = struct {
    /// Where the root module's source begins, or null for the manifest's own
    /// directory.
    source: ?[]const u8,
    declared: Declared,
};

/// What a root's manifest says about the root beyond where its source sits:
/// how it is built, whether it is the library every program depends on, and
/// whether it may declare `extern` functions. A root without a manifest is a
/// program that is neither.
pub const Declared = struct {
    kind: program_mod.Kind = .program,
    /// Whether the manifest names the root `std`. That root is the library
    /// every program depends on, so compiling it loads its own modules as the
    /// library rather than beside a second copy: a package is never its own
    /// dependency.
    standard: bool = false,
    /// Whether the root may declare `extern` functions ([M-Extern]).
    externs: bool = false,
};

/// Reads the keys that make up `Declared`, refusing a `kind` it does not know.
fn declaredFrom(written: Written) !Declared {
    const kind = try kindNamed(written.kind);
    const standard = if (written.name) |name| std.mem.eql(u8, name, library.dependency_name) else false;
    // The name every program's dependency answers to belongs to a library. A
    // program taking it would be loaded as the library and lose the prelude
    // it expects, which reads as every ordinary name gone undefined.
    if (standard and kind != .library) return error.ManifestNamesTheLibrary;
    return .{ .kind = kind, .standard = standard, .externs = written.@"extern" };
}

test "a manifest declares a library's name and its extern capability" {
    const standard = try declaredFrom(.{ .kind = "library", .name = "std", .@"extern" = true });
    try testing.expectEqual(Declared{ .kind = .library, .standard = true, .externs = true }, standard);
    const other = try declaredFrom(.{ .kind = "library", .name = "geometry" });
    try testing.expectEqual(Declared{ .kind = .library }, other);
    try testing.expectEqual(Declared{}, try declaredFrom(.{}));
    try testing.expectError(error.ManifestKindUnknown, declaredFrom(.{ .kind = "plugin" }));
    try testing.expectError(error.ManifestNamesTheLibrary, declaredFrom(.{ .name = "std" }));
}

fn readManifest(gpa: std.mem.Allocator, io: std.Io, dir: []const u8) !?Manifest {
    var buffer: [std.fs.max_path_bytes]u8 = undefined;
    const path = std.fmt.bufPrint(&buffer, "{s}{s}{s}", .{
        dir,
        if (dir.len == 0) "" else "/",
        manifest_name,
    }) catch return null;

    const text = source_mod.readFileAlloc(io, gpa, path) catch return null;
    defer gpa.free(text);

    const parsed = std.json.parseFromSlice(Written, gpa, text, .{
        .ignore_unknown_fields = true,
    }) catch return error.ManifestNotJson;
    defer parsed.deinit();

    const declared = try declaredFrom(parsed.value);
    const named = parsed.value.source orelse return .{ .source = null, .declared = declared };
    if (named.len == 0) return .{ .source = null, .declared = declared };
    return .{ .source = try gpa.dupe(u8, named), .declared = declared };
}

/// The keys a manifest may write. Unknown ones are ignored, so a manifest may
/// carry what a later version of this compiler reads.
const Written = struct {
    source: ?[]const u8 = null,
    kind: ?[]const u8 = null,
    /// The library's name, which is how a root is known to be a dependency
    /// that programs import.
    name: ?[]const u8 = null,
    /// Whether the root is trusted to declare `extern` functions.
    @"extern": bool = false,
};

/// What a manifest says its root is built as.
///
/// An absent `kind` is a program, which is what leaves `{}` a complete manifest
/// and every root written before this keeping its meaning. A `kind` this
/// compiler does not know is refused rather than read as the default: a value
/// that falls back to `program` is a typo whose only symptom is a library that
/// quietly demands an entry point.
fn kindNamed(written: ?[]const u8) !program_mod.Kind {
    const named = written orelse return .program;
    if (std.mem.eql(u8, named, "program")) return .program;
    if (std.mem.eql(u8, named, "library")) return .library;
    return error.ManifestKindUnknown;
}

fn holdsManifest(io: std.Io, dir: []const u8) bool {
    var buffer: [std.fs.max_path_bytes]u8 = undefined;
    const path = std.fmt.bufPrint(&buffer, "{s}{s}{s}", .{
        dir,
        if (dir.len == 0) "" else "/",
        manifest_name,
    }) catch return false;
    const opened = std.Io.Dir.cwd().openFile(io, path, .{}) catch return false;
    opened.close(io);
    return true;
}

/// Every source file a module directory holds, by path.
///
/// Recursive, because a module's own subdirectories are part of it: a program
/// laid out as a directory of directories is one program, and a walk stopping
/// at the first level would compile a different one.
///
/// Separate from reading them, so that a caller holding text of its own --
/// an editor's unsaved buffer -- substitutes it without deciding for itself
/// what the module contains. Which files a module holds is one question, and
/// a second walk answering it agrees on the corpus and diverges on the first
/// program with a subdirectory in it.
pub fn pathsOfModule(gpa: std.mem.Allocator, io: std.Io, root: []const u8) ![][]const u8 {
    var found: std.ArrayList([]const u8) = .empty;
    errdefer {
        for (found.items) |q| gpa.free(q);
        found.deinit(gpa);
    }

    var dir = try std.Io.Dir.cwd().openDir(io, if (root.len == 0) "." else root, .{ .iterate = true });
    defer dir.close(io);

    var walker = try dir.walkSelectively(gpa);
    defer walker.deinit();

    while (try walker.next(io)) |e| {
        try enterListed(&walker, io, e);
        if (e.kind != .file) continue;
        if (!std.mem.endsWith(u8, e.basename, ".lin")) continue;

        const rel = if (root.len == 0)
            try gpa.dupe(u8, e.path)
        else
            try std.fs.path.join(gpa, &.{ root, e.path });
        try found.append(gpa, rel);
    }

    return found.toOwnedSlice(gpa);
}

/// Descends into a directory the walk listed, skipping one removed since.
///
/// A directory beside the entry can be removed between the listing that names
/// it and the open that enters it: another program's build directory, an
/// editor's backup. It holds nothing this load can read either way, so
/// failing the load on it reports a missing source for a file that is present.
fn enterListed(walker: *std.Io.Dir.SelectiveWalker, io: std.Io, entry: std.Io.Dir.Walker.Entry) !void {
    walker.enter(io, entry) catch |err| switch (err) {
        error.FileNotFound => {},
        else => |e| return e,
    };
}

test "a directory removed after the walk listed it is skipped" {
    const gpa = testing.allocator;
    var tmp = testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    try tmp.dir.createDirPath(testing.io, "gone");

    var walker = try tmp.dir.walkSelectively(gpa);
    defer walker.deinit();
    const listed = (try walker.next(testing.io)).?;
    try testing.expectEqualStrings("gone", listed.basename);
    try tmp.dir.deleteDir(testing.io, "gone");

    try enterListed(&walker, testing.io, listed);
    try testing.expect((try walker.next(testing.io)) == null);
}

/// Walks the import graph depth-first from the entry.
///
/// A module already loaded is reused rather than reloaded: one directory is
/// one module however many routes reach it, which is what makes `a.b` and
/// `a` then `b` name the same thing.
///
/// A ring needs no separate cycle state. The module enters `by_dir` before its
/// imports are followed, so a route returning to it reuses the existing ID.
fn deinitModule(gpa: std.mem.Allocator, module: Module) void {
    gpa.free(module.dir);
    gpa.free(module.files);
    gpa.free(module.imports);
}

const Loader = struct {
    const LoadError = std.mem.Allocator.Error || @typeInfo(@typeInfo(@TypeOf(source_mod.readFileAlloc)).@"fn".return_type.?).error_union.error_set;

    gpa: std.mem.Allocator,
    table: *FileTable,
    sink: *Sink,
    files: []const InMemoryFile,
    /// Source buffers are acquired only when the import walk reaches a file.
    /// Embedded library sources have static lifetime and need no copy.
    input: Input,
    /// The one tree every module is parsed into, a module at a time.
    trees: Modules,
    modules: std.ArrayList(Module) = .empty,
    /// Canonical root-relative source spelling for each module.
    routes: std.ArrayList([]const u8) = .empty,
    /// Directory that import paths in the primary root are relative to.
    primary_dir: []const u8 = "",
    /// The prelude, once it is loaded.
    prelude: ModuleId = .none,
    /// Directory to module, so a diamond loads once.
    by_dir: std.StringHashMapUnmanaged(ModuleId) = .empty,
    /// Which of `files` each directory holds, built once on first use.
    ///
    /// A module took its files by reading every file the program supplies, so
    /// loading a program of many modules read all of them once per module --
    /// and a module is a directory, so both sides of that grow together.
    ///
    /// Not a range over the sorted list: sorting by whole path does not order
    /// directories, since `p/b/b.lin` sorts before `p/z.lin` while their
    /// directories sort the other way. The keys borrow from the paths, which
    /// outlive this.
    in_dir: std.StringHashMapUnmanaged(std.ArrayList(u32)) = .empty,
    indexed: bool = false,
    /// What a load of the library has already read, held between calls.
    ///
    /// A program's walk may name the library more than once, and each of the
    /// three above is about whichever set of files is being read. Rebuilding
    /// them per import would reparse the library once for every import that
    /// names it.
    library_dirs: std.StringHashMapUnmanaged(ModuleId) = .empty,
    library_in_dir: std.StringHashMapUnmanaged(std.ArrayList(u32)) = .empty,
    library_indexed: bool = false,
    /// Whether the four fields above are the ones in play, which is what makes
    /// reaching a library module from inside the library an ordinary load.
    in_library: bool = false,
    /// Whether the program being loaded is the library, which is what testing
    /// the library on its own terms means.
    ///
    /// A rooted path then names a module of this program: the modules `std.`
    /// would reach are the ones already being loaded, and fetching a second
    /// copy of them declares every name in the library twice.
    program_is_library: bool = false,

    fn seedLibrary(self: *Loader, prefix: *const LibraryPrefix) !void {
        try self.modules.ensureTotalCapacity(self.gpa, prefix.program.modules.len);
        try self.routes.ensureTotalCapacity(self.gpa, prefix.program.import_routes.len);
        try self.library_dirs.ensureTotalCapacity(self.gpa, @intCast(prefix.program.modules.len));
        for (prefix.program.modules, prefix.program.import_routes, 0..) |module, route, i| {
            const dir = try self.gpa.dupe(u8, module.dir);
            errdefer self.gpa.free(dir);
            const files = try self.gpa.dupe(FileId, module.files);
            errdefer self.gpa.free(files);
            const imports = try self.gpa.dupe(Import, module.imports);
            errdefer self.gpa.free(imports);
            const copied_route = try self.gpa.dupe(u8, route);
            self.modules.appendAssumeCapacity(.{
                .name = nameOf(dir),
                .dir = dir,
                .files = files,
                .decls = module.decls,
                .imports = imports,
                .root = module.root,
                .library = true,
                .externs = module.externs,
            });
            self.routes.appendAssumeCapacity(copied_route);
            self.library_dirs.putAssumeCapacity(dir, .from(i));
        }
        self.prelude = prefix.program.prelude;
    }

    fn deinit(self: *Loader) void {
        self.by_dir.deinit(self.gpa);
        var held = self.in_dir.valueIterator();
        while (held.next()) |v| v.deinit(self.gpa);
        self.in_dir.deinit(self.gpa);

        // The library's, which outlive each load of it rather than each call.
        self.library_dirs.deinit(self.gpa);
        var library_held = self.library_in_dir.valueIterator();
        while (library_held.next()) |v| v.deinit(self.gpa);
        self.library_in_dir.deinit(self.gpa);
        for (self.routes.items) |route| self.gpa.free(route);
        self.routes.deinit(self.gpa);
        for (self.modules.items) |module| deinitModule(self.gpa, module);
        self.modules.deinit(self.gpa);
        self.trees.deinit();
    }

    /// Groups the supplied files by the directory each sits in.
    fn indexFiles(self: *Loader) std.mem.Allocator.Error!void {
        if (self.indexed) return;
        self.indexed = true;
        for (self.files, 0..) |f, i| {
            if (!std.mem.endsWith(u8, f.path, ".lin")) continue;
            const gop = try self.in_dir.getOrPut(self.gpa, dirOf(f.path));
            if (!gop.found_existing) gop.value_ptr.* = .empty;
            try gop.value_ptr.append(self.gpa, @intCast(i));
        }
    }

    /// Loads the standard library beside the program.
    ///
    /// After the entry, so the root module keeps index zero -- the runtime
    /// calls the root module's `main`, and which module is the root is not a
    /// question the library should be able to change by existing.
    /// Loads a library module, with the loader looking at the library rather
    /// than at the program.
    ///
    /// The library is a second set of files under a directory namespace of its
    /// own, so reaching one of its modules means repointing what a load reads
    /// and what a load has already read. Two callers need that: the bootstrap
    /// below, and an `import std.…` followed while a program is still being
    /// walked, which happens at a moment the bootstrap has not run.
    fn inLibrary(self: *Loader, dir: []const u8) LoadError!ModuleId {
        // Already looking at it, which is a library module importing a sibling.
        // Swapping again would hand this load the program's maps and load a
        // module the library already holds a second time -- and two modules for
        // one directory are two identities for every type it declares.
        if (self.in_library) {
            const from = self.modules.items.len;
            const loaded = try self.load(dir, null);
            const externs = try self.libraryExterns();
            for (self.modules.items[from..]) |*m| {
                m.root = standard_root;
                m.library = true;
                m.externs = externs;
            }
            return loaded;
        }

        self.in_library = true;
        defer self.in_library = false;

        const program_files = self.files;
        defer self.files = program_files;
        self.files = &library.files;

        // Its own directory namespace. A program whose entry is a directory
        // called `std` had already claimed that name, so the library was never
        // loaded -- or worse, the program's directory was pulled into the
        // library's own graph and the compiler reported errors inside its
        // source at a path the user cannot open.
        const program_dirs = self.by_dir;
        self.by_dir = self.library_dirs;
        defer {
            self.library_dirs = self.by_dir;
            self.by_dir = program_dirs;
        }

        // The index holds positions in `files`, which is another list for the
        // length of this call, so it is put aside with everything else that was
        // about the program.
        const program_in_dir = self.in_dir;
        const program_indexed = self.indexed;
        self.in_dir = self.library_in_dir;
        self.indexed = self.library_indexed;
        defer {
            self.library_in_dir = self.in_dir;
            self.library_indexed = self.indexed;
            self.in_dir = program_in_dir;
            self.indexed = program_indexed;
        }

        const from = self.modules.items.len;
        const loaded = try self.load(dir, null);
        const externs = try self.libraryExterns();
        for (self.modules.items[from..]) |*m| {
            m.root = standard_root;
            m.library = true;
            m.externs = externs;
        }
        return loaded;
    }

    /// Whether the embedded library's manifest grants it `extern`, read the
    /// way every root's manifest is read.
    fn libraryExterns(self: *Loader) std.mem.Allocator.Error!bool {
        return (try declaredGiven(self.gpa, &library.files)).externs;
    }

    fn loadLibrary(self: *Loader) LoadError!void {
        // Kept rather than discarded: which module the prelude is, is what
        // loading it decides, and every later pass that wants to know has
        // otherwise to guess from where it sits.
        self.prelude = try self.inLibrary(library.prelude_dir);
    }

    fn sourceFor(self: *Loader, file: InMemoryFile) !Source {
        if (self.in_library) return .{ .path = file.path, .text = file.text };
        const storage = switch (self.input) {
            .memory => |ownership| switch (ownership) {
                .borrow => return .{ .path = file.path, .text = file.text },
                .copy => |allocator| allocator,
            },
            .disk => self.gpa,
        };
        const path = try storage.dupe(u8, file.path);
        errdefer storage.free(path);
        const text = switch (self.input) {
            .memory => try storage.dupe(u8, file.text),
            .disk => |io| try source_mod.readFileAlloc(io, storage, path),
        };
        return .{ .path = path, .text = text };
    }

    /// Loads the module in `dir`, or returns the one already there.
    /// `only` names a single entry file; null takes every `.lin` file in `dir`.
    fn load(self: *Loader, dir: []const u8, only: ?[]const u8) LoadError!ModuleId {
        if (self.by_dir.get(dir)) |already| return already;

        const zone = tracy.beginZone(@src(), "load.module");
        defer zone.end();

        var ids: std.ArrayList(FileId) = .empty;
        errdefer ids.deinit(self.gpa);

        // The id and the bytes travel as one value, so nothing downstream can
        // pair a span with the wrong file.
        var parsed: std.ArrayList(ParsedFile) = .empty;
        defer parsed.deinit(self.gpa);

        if (only) |one| {
            for (self.files) |f| {
                if (!std.mem.eql(u8, f.path, one)) continue;
                const source = try self.sourceFor(f);
                const id = try self.table.add(self.gpa, source);
                try ids.append(self.gpa, id);
                try parsed.append(self.gpa, .{ .file = id, .source = source });
            }
        } else {
            try self.indexFiles();
            if (self.in_dir.get(dir)) |held| {
                for (held.items) |i| {
                    const f = self.files[i];
                    const source = try self.sourceFor(f);
                    const id = try self.table.add(self.gpa, source);
                    try ids.append(self.gpa, id);
                    try parsed.append(self.gpa, .{ .file = id, .source = source });
                }
            }
        }
        if (parsed.items.len == 0) return .none;

        // The module owns its directory string from here on: the caller's may
        // be a scratch buffer, and `by_dir` keys and `Module.dir` both outlive
        // the walk that produced it.
        var transferred = false;
        const owned_dir = try self.gpa.dupe(u8, dir);
        errdefer if (!transferred) self.gpa.free(owned_dir);

        const file_ids = try ids.toOwnedSlice(self.gpa);
        errdefer if (!transferred) self.gpa.free(file_ids);
        const decls = try self.trees.add(parsed.items);

        const id: ModuleId = .from(self.modules.items.len);
        try self.by_dir.put(self.gpa, owned_dir, id);
        try self.modules.append(self.gpa, .{
            .name = nameOf(owned_dir),
            .dir = owned_dir,
            .files = file_ids,
            .decls = decls,
            .imports = &.{},
        });
        transferred = true;
        const route = try self.routeTo(owned_dir);
        self.routes.append(self.gpa, route) catch |err| {
            self.gpa.free(route);
            return err;
        };

        var imports: std.ArrayList(Import) = .empty;
        errdefer imports.deinit(self.gpa);

        // A fresh view per declaration. Following an import loads a module,
        // which appends to the tree and moves it, so a view taken before the
        // loop is stale from the first import onwards -- and reads whatever
        // now sits where the declarations used to be.
        for (decls.start..decls.end) |i| {
            const d = DeclId.at(@intCast(i));
            if (self.trees.view().declTag(d) != .import_) continue;
            // The one place a module's imports are recorded, and they are
            // recorded ascending -- which is what `Module.importedBy` searches
            // on rather than walks. A loader that collected them any other way
            // would leave that search answering wrongly rather than slowly, so
            // the order is asserted where it is produced.
            if (imports.items.len > 0) {
                std.debug.assert(imports.items[imports.items.len - 1].decl.index() < i);
            }
            try imports.append(self.gpa, .{ .decl = d, .module = try self.follow(d) });
        }
        self.modules.items[id.index()].imports = try imports.toOwnedSlice(self.gpa);

        return id;
    }

    /// Retains the canonical import spelling for one loaded directory.
    fn routeTo(self: *Loader, dir: []const u8) std.mem.Allocator.Error![]const u8 {
        // The embedded library's directories are spelled the way an import
        // reaches them already.
        if (self.in_library) return self.spelledRoute(dir);
        const relative = if (std.mem.eql(u8, dir, self.primary_dir))
            ""
        else blk: {
            std.debug.assert(std.mem.startsWith(u8, dir, self.primary_dir));
            const start = self.primary_dir.len + @intFromBool(self.primary_dir.len > 0);
            std.debug.assert(start <= dir.len);
            break :blk dir[start..];
        };
        // The library compiled as itself is reached as `std` wherever its
        // directory sits, exactly as its embedded copy is.
        if (self.program_is_library) {
            const named = if (relative.len == 0)
                try self.gpa.dupe(u8, standard_dependency)
            else
                try std.mem.concat(self.gpa, u8, &.{ standard_dependency, "/", relative });
            defer self.gpa.free(named);
            return self.spelledRoute(named);
        }
        return self.spelledRoute(relative);
    }

    /// A directory path written with the dots an import path uses.
    fn spelledRoute(self: *Loader, relative: []const u8) std.mem.Allocator.Error![]const u8 {
        const route = try self.gpa.dupe(u8, relative);
        for (route) |*c| {
            if (c.* == '/') c.* = '.';
        }
        return route;
    }

    /// Resolves one `import` against its independently loaded root.
    ///
    /// Every read of the tree takes a fresh view: loading a module appends to
    /// it, so a view held across the recursion below would point into storage
    /// that has since moved.
    fn follow(self: *Loader, d: DeclId) LoadError!ModuleId {
        const path = self.trees.view().declPath(d);
        if (path.len() == 0) return .none;

        // The dots are path separators, so the whole path is one directory
        // reached from here. Nothing named by an element other than the last
        // is loaded, and no enclosing package is implied.
        var joined: std.ArrayList(u8) = .empty;
        defer joined.deinit(self.gpa);

        // Where the path starts. `std` names the `std` dependency wherever it
        // appears, so it is answered here and every other first element is
        // resolved against the root that wrote the import -- one routine, so
        // there is no second rule about what `std` means.
        //
        // The dependency's modules sit under its own directory: the embedded
        // copy's `std/…`, or, where the library is the root being compiled,
        // that root's directory. So a rooted path is that directory followed
        // by the path's remaining elements.
        const rooted = std.mem.eql(u8, self.trees.view().tokenText(path.start), standard_dependency);
        const root_dir = if (self.in_library)
            library.prelude_dir
        else if (rooted and !self.program_is_library)
            library.prelude_dir
        else
            self.primary_dir;
        if (root_dir.len > 0) try joined.appendSlice(self.gpa, root_dir);

        {
            const ast = self.trees.view();
            var elements = ast.pathElements(d);
            if (rooted) _ = elements.next();
            while (elements.next()) |tok| {
                if (joined.items.len > 0) try joined.append(self.gpa, '/');
                try joined.appendSlice(self.gpa, ast.tokenText(tok));
            }
        }

        if (rooted and path.len() == 1) {
            try self.report(d, "this names no module", "`{s}` says where a path starts, and holds nothing of its own", .{standard_dependency});
            return .none;
        }

        const dir = joined.items;

        // The library's own directories are `std` and what sits below it, so a
        // rooted path is already the directory -- and one directory is one
        // module, whichever route reached it.
        // Which module a directory already is, is `load`'s answer and only its:
        // the map holding it is swapped for the length of a library load, so a
        // reader here would have to know which of the two is live and would be
        // reading a stale copy of the other.
        if (rooted) {
            // The library reaching its own sibling while it *is* the program:
            // an ordinary load, against the modules already here. Fetching the
            // library separately would load a second copy of every module and
            // declare every name in it twice.
            const loaded = if (self.program_is_library)
                try self.load(dir, null)
            else
                try self.inLibrary(dir);
            if (loaded != .none) return loaded;

            // Named the way the program wrote it, after `std`: a message
            // answering `std.nosuch` with `std/nosuch` names a spelling the
            // language does not have.
            var written: std.ArrayList(u8) = .empty;
            defer written.deinit(self.gpa);
            var local: std.ArrayList(u8) = .empty;
            defer local.deinit(self.gpa);
            if (self.primary_dir.len > 0) try local.appendSlice(self.gpa, self.primary_dir);
            {
                const ast = self.trees.view();
                var elements = ast.pathElements(d);
                while (elements.next()) |tok| {
                    if (local.items.len > 0) try local.append(self.gpa, '/');
                    try local.appendSlice(self.gpa, ast.tokenText(tok));
                    if (tok == path.start) continue;
                    if (written.items.len > 0) try written.append(self.gpa, '.');
                    try written.appendSlice(self.gpa, ast.tokenText(tok));
                }
            }
            // A directory of the program's own spelled the same way is not
            // what the import reached, and saying so is the only way the
            // programmer learns why the file they can see was not found.
            if (!self.in_library and !self.program_is_library) {
                try self.indexFiles();
                if (self.in_dir.contains(local.items)) {
                    try self.report(d, "cannot import it", "the standard library holds no module named `{s}`; an import starting with `std` names it, so this program's `{s}` cannot be imported", .{ written.items, local.items });
                    return .none;
                }
            }
            try self.report(d, "cannot import it", "the standard library holds no module named `{s}`", .{written.items});
            return .none;
        }

        // One directory is one module, whichever route reached it.
        if (self.by_dir.get(dir)) |already| return already;

        const loaded = try self.load(dir, null);
        if (loaded == .none) {
            try self.report(d, "cannot import it", "no directory named `{s}` holds a `.lin` file", .{dir});
        }
        return loaded;
    }

    /// Reports at the path an import names, which is what a reader edits.
    fn report(
        self: *Loader,
        d: DeclId,
        label: []const u8,
        comptime fmt: []const u8,
        args: anytype,
    ) std.mem.Allocator.Error!void {
        const ast = self.trees.view();
        try self.sink.addErrorFmt(
            .m_import,
            ast.fileOfDecl(d),
            ast.rangeSpan(ast.declPath(d)),
            label,
            fmt,
            args,
        );
    }
};

test "copied memory sources release partial acquisition on allocation failure" {
    for (0..2) |fail_index| {
        var metadata = std.heap.ArenaAllocator.init(testing.allocator);
        defer metadata.deinit();
        const a = metadata.allocator();
        var storage = testing.FailingAllocator.init(testing.allocator, .{ .fail_index = fail_index });
        var table: FileTable = .empty;
        var sink = Sink.init(a);
        var interner: Interner = .empty;
        try testing.expectError(error.OutOfMemory, loadFromMemory(a, &table, &sink, &interner, "app", &.{
            .{ .path = "app/main.lin", .text = "fn main() -> UInt8 { 0 }" },
        }, .program, false, .{ .copy = storage.allocator() }));
        try testing.expect(storage.has_induced_failure);
        try testing.expectEqual(storage.allocated_bytes, storage.freed_bytes);
        try testing.expectEqual(@as(usize, 0), table.count());
    }
}

test "borrowed memory sources retain the caller's buffers" {
    const input: InMemoryFile = .{ .path = "app/main.lin", .text = "fn main() -> UInt8 { 0 }" };
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var table: FileTable = .empty;
    var sink = Sink.init(a);
    var interner: Interner = .empty;
    const program = try loadFromMemory(a, &table, &sink, &interner, "app", &.{input}, .program, false, .borrow);
    const source = table.get(program.modules[0].files[0]);
    try testing.expect(source.path.ptr == input.path.ptr);
    try testing.expect(source.text.ptr == input.text.ptr);
}

test "the program's root is module zero, whatever else was loaded" {
    // The library is loaded after the program, and the order is the whole
    // reason: module zero is the root, and a program that read nothing would
    // otherwise leave that index to the library -- so every later question
    // about "the root" would be answered about the standard library.
    //
    // Reaching a library module from inside the program's own walk means
    // loading one at a moment the bootstrap has not run. This is what that must
    // not disturb.
    const gpa = testing.allocator;

    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();

    var table: FileTable = .empty;
    defer table.deinit(gpa);
    var sink = Sink.init(arena.allocator());
    var interner: Interner = .empty;
    defer interner.deinit(gpa);

    var program = try loadFromMemory(gpa, &table, &sink, &interner, "main.lin", &.{
        .{ .path = "main.lin", .text = "fn main() -> UInt8 {\n    0\n}\n" },
    }, .program, true, .borrow);
    defer program.deinit(gpa);

    try testing.expect(!program.modules[0].library);
    try testing.expectEqual(program_mod.RootId.primary, program.modules[0].root);
    try testing.expect(program.prelude != .none);
    try testing.expect(program.get(program.prelude).library);
    const library_root = program.get(program.prelude).root;
    try testing.expect(library_root != .primary);
    for (program.modules) |module| {
        try testing.expectEqual(if (module.library) library_root else program_mod.RootId.primary, module.root);
    }
}

test "buffered I/O loads only through an explicit import" {
    const gpa = testing.allocator;
    for ([_]bool{ false, true }) |explicit_io| {
        var arena = std.heap.ArenaAllocator.init(gpa);
        defer arena.deinit();
        var table: FileTable = .empty;
        defer table.deinit(gpa);
        var sink = Sink.init(arena.allocator());
        var interner: Interner = .empty;
        defer interner.deinit(gpa);
        const source = if (explicit_io)
            "import std.io\nfn main() -> UInt8 { 0 }\n"
        else
            "fn main() -> UInt8 { 0 }\n";
        var program = try loadFromMemory(gpa, &table, &sink, &interner, "main.lin", &.{
            .{ .path = "main.lin", .text = source },
        }, .program, true, .borrow);
        defer program.deinit(gpa);
        var core = false;
        var buffered = false;
        var json = false;
        for (program.modules) |module| {
            if (!module.library) continue;
            core = core or std.mem.eql(u8, module.dir, "std/io/core");
            buffered = buffered or std.mem.eql(u8, module.dir, "std/io");
            json = json or std.mem.eql(u8, module.dir, "std/json");
        }
        try testing.expect(core);
        try testing.expectEqual(explicit_io, buffered);
        try testing.expect(!json);
    }
}

test "the loader retains canonical routes through a same-root import ring" {
    const gpa = testing.allocator;

    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();

    var table: FileTable = .empty;
    defer table.deinit(gpa);
    var sink = Sink.init(arena.allocator());
    var interner: Interner = .empty;
    defer interner.deinit(gpa);

    var program = try loadFromMemory(gpa, &table, &sink, &interner, "app", &.{
        .{ .path = "app/main.lin", .text = "import a\nimport b\n" },
        .{ .path = "app/a/a.lin", .text = "import b\n" },
        .{ .path = "app/b/b.lin", .text = "import a\n" },
    }, .program, false, .borrow);
    defer program.deinit(gpa);

    try testing.expectEqual(@as(usize, 3), program.modules.len);
    try testing.expectEqual(ModuleId.from(2), program.get(.from(1)).imports[0].module);
    try testing.expectEqual(ModuleId.from(1), program.get(.from(2)).imports[0].module);
    try testing.expectEqualStrings("b", program.importRoute(.from(1), .from(2)).?.syntax);
    try testing.expectEqualStrings("a", program.importRoute(.from(2), .from(1)).?.syntax);
}

test "one file is spelled one way" {
    const gpa = testing.allocator;
    for ([_]struct { written: []const u8, canonically: []const u8 }{
        .{ .written = "p/.", .canonically = "p" },
        .{ .written = "/p/./main.lin", .canonically = "/p/main.lin" },
        .{ .written = "p/src/", .canonically = "p/src" },
        .{ .written = "p//src", .canonically = "p/src" },
        .{ .written = ".", .canonically = "." },
        .{ .written = "./", .canonically = "." },
        .{ .written = "/", .canonically = "/" },
        .{ .written = "", .canonically = "" },
        // Where a `..` leads is the filesystem's answer, not a spelling.
        .{ .written = "p/../q", .canonically = "p/../q" },
    }) |c| {
        const got = try canonical(gpa, c.written);
        defer gpa.free(got);
        try testing.expectEqualStrings(c.canonically, got);
    }
}

test "a file named on the command line is the program, and a file an editor opened is not" {
    const gpa = testing.allocator;

    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "linea.json", .data = "{\"source\": \"src\"}" });
    try tmp.dir.createDirPath(testing.io, "src");
    try tmp.dir.createDirPath(testing.io, "scratch");
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "src/main.lin", .data = "fn main() -> UInt8 { 7 }\n" });
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "scratch/spare.lin", .data = "fn main() -> UInt8 { 42 }\n" });

    const root = try std.fmt.allocPrint(gpa, ".zig-cache/tmp/{s}", .{tmp.sub_path});
    defer gpa.free(root);
    const spare = try std.fs.path.join(gpa, &.{ root, "scratch/spare.lin" });
    defer gpa.free(spare);

    const named = try entryOf(gpa, testing.io, spare, .as_named, "");
    defer gpa.free(named);
    try testing.expectEqualStrings(spare, named);

    const inside = try std.fs.path.join(gpa, &.{ root, "src/main.lin" });
    defer gpa.free(inside);
    const opened = try entryOf(gpa, testing.io, inside, .its_program, root);
    defer gpa.free(opened);
    const source_root = try std.fs.path.join(gpa, &.{ root, "src" });
    defer gpa.free(source_root);
    try testing.expectEqualStrings(source_root, opened);
}

test "a file a program's source root does not hold is a program on its own" {
    const gpa = testing.allocator;

    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "linea.json", .data = "{\"source\": \"src\"}" });
    try tmp.dir.createDirPath(testing.io, "src");
    try tmp.dir.createDirPath(testing.io, "scratch");
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "src/main.lin", .data = "fn main() -> UInt8 { 7 }\n" });
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "scratch/spare.lin", .data = "fn main() -> UInt8 { 42 }\n" });

    const root = try std.fmt.allocPrint(gpa, ".zig-cache/tmp/{s}", .{tmp.sub_path});
    defer gpa.free(root);
    const spare = try std.fs.path.join(gpa, &.{ root, "scratch/spare.lin" });
    defer gpa.free(spare);

    // The manifest marks the directory above it, and the source root it names
    // does not reach here. A file no program holds is a program on its own,
    // which is what a file under no manifest at all already resolves to.
    const opened = try entryOf(gpa, testing.io, spare, .its_program, root);
    defer gpa.free(opened);
    try testing.expectEqualStrings(spare, opened);
}

test "a manifest outside the workspace is not the opened file's program" {
    const gpa = testing.allocator;

    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDirPath(testing.io, "ws");
    try tmp.dir.createDirPath(testing.io, "elsewhere");
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "elsewhere/linea.json", .data = "{}" });
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "elsewhere/main.lin", .data = "fn main() -> UInt8 { 0 }\n" });

    const tmp_root = try std.fmt.allocPrint(gpa, ".zig-cache/tmp/{s}", .{tmp.sub_path});
    defer gpa.free(tmp_root);
    const workspace = try std.fs.path.join(gpa, &.{ tmp_root, "ws" });
    defer gpa.free(workspace);
    const opened = try std.fs.path.join(gpa, &.{ tmp_root, "elsewhere/main.lin" });
    defer gpa.free(opened);

    // The file sits beside a manifest, and neither is under the workspace the
    // client opened. Nothing inside the workspace marks it, so the file is a
    // program on its own.
    const entry = try entryOf(gpa, testing.io, opened, .its_program, workspace);
    defer gpa.free(entry);
    try testing.expectEqualStrings(opened, entry);
}

test "a source root written as this directory names the files the walk found" {
    const gpa = testing.allocator;

    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "linea.json", .data = "{\"source\": \".\"}" });
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "main.lin", .data = "fn main() -> UInt8 { 0 }\n" });

    const root = try std.fmt.allocPrint(gpa, ".zig-cache/tmp/{s}", .{tmp.sub_path});
    defer gpa.free(root);
    const opened = try std.fs.path.join(gpa, &.{ root, "main.lin" });
    defer gpa.free(opened);

    const entry = try entryOf(gpa, testing.io, opened, .its_program, root);
    defer gpa.free(entry);

    const paths = try pathsOfModule(gpa, testing.io, dirOfEntry(entry));
    defer {
        for (paths) |p| gpa.free(p);
        gpa.free(paths);
    }

    try testing.expectEqual(@as(usize, 1), paths.len);
    try testing.expectEqualStrings(opened, paths[0]);
}

test "a program in a directory called std does not displace the library" {
    // Imports resolve `std` to the library even when the program entry lives
    // in a directory with that name. Separate roots prevent program files
    // from satisfying a standard-library import.
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var sink = Sink.init(arena.allocator());
    var interner: Interner = .empty;
    defer interner.deinit(testing.allocator);

    var table: FileTable = .empty;
    defer table.deinit(testing.allocator);

    var p = try loadFromMemory(testing.allocator, &table, &sink, &interner, "std", &.{
        .{ .path = "std/main.lin", .text = "fn main() -> UInt8 { 1 }" },
    }, .program, true, .borrow);
    defer p.deinit(testing.allocator);

    // The program and prelude share a directory spelling, but belong to
    // different roots. Library modules are loaded through imports, so unrelated
    // library directories need not appear in this program's module graph.
    try testing.expect(p.prelude != .none);
    const prelude = p.get(p.prelude);
    try testing.expect(prelude.library);
    try testing.expect(prelude.root != .primary);
    try testing.expectEqualStrings(standard_dependency, prelude.dir);

    // The entry point remains in the program root even though its directory
    // has the reserved library spelling.
    try testing.expect(!p.modules[0].library);
    try testing.expectEqual(program_mod.RootId.primary, p.modules[0].root);
    try testing.expectEqualStrings(standard_dependency, p.modules[0].dir);
    try testing.expectEqualStrings("std/main.lin", table.get(p.modules[0].files[0]).path);
}

test "an entry holding no source is still the root module" {
    // The library is loaded last so the program keeps index zero, and every
    // pass asks the program what it declares by asking index zero. An entry
    // that read nothing produced no module at all, so the library took the
    // index -- and the missing `main` was then reported against library
    // source, at a token the programmer has no way to change.
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var sink = Sink.init(arena.allocator());
    var interner: Interner = .empty;
    defer interner.deinit(testing.allocator);

    var table: FileTable = .empty;
    defer table.deinit(testing.allocator);

    var p = try loadFromMemory(testing.allocator, &table, &sink, &interner, "app", &.{}, .program, true, .borrow);
    defer p.deinit(testing.allocator);

    try testing.expect(!p.root().library);
    try testing.expectEqualStrings("app", p.root().dir);
    try testing.expectEqual(@as(usize, 1), p.root().files.len);
    try testing.expectEqualStrings("app", table.get(p.root().files[0]).path);
}

test "a file entry is a one-file root module" {
    // Not an optimisation. tests/enums/ holds ~100 unrelated programs in one
    // directory, and a directory-only rule makes them one module declaring a
    // hundred `main`s.
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var sink = Sink.init(arena.allocator());
    var interner: Interner = .empty;
    defer interner.deinit(testing.allocator);

    var table: FileTable = .empty;
    defer table.deinit(testing.allocator);

    var p = try loadFromMemory(testing.allocator, &table, &sink, &interner, "case.lin", &.{
        .{ .path = "case.lin", .text = "fn main() -> UInt8 { 1 }" },
        .{ .path = "other.lin", .text = "fn main() -> UInt8 { 2 }" },
    }, .program, false, .borrow);
    defer p.deinit(testing.allocator);

    try testing.expectEqual(@as(usize, 1), p.modules.len);
    try testing.expectEqual(@as(usize, 1), p.root().files.len);
    try testing.expectEqualStrings("case.lin", table.get(p.root().files[0]).path);
}

test "a directory entry takes every .lin file in it, and nothing else" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var sink = Sink.init(arena.allocator());
    var interner: Interner = .empty;
    defer interner.deinit(testing.allocator);

    var table: FileTable = .empty;
    defer table.deinit(testing.allocator);

    var p = try loadFromMemory(testing.allocator, &table, &sink, &interner, "app", &.{
        .{ .path = "app/main.lin", .text = "fn main() -> UInt8 { helper() }" },
        .{ .path = "app/helper.lin", .text = "fn helper() -> UInt8 { 3 }" },
        .{ .path = "app/notes.txt", .text = "ignored" },
    }, .program, false, .borrow);
    defer p.deinit(testing.allocator);

    try testing.expectEqual(@as(usize, 1), p.modules.len);
    try testing.expectEqual(@as(usize, 2), p.root().files.len);
    try testing.expectEqualStrings("app", p.root().name);
}

test "a subdirectory is a different module, not part of this one" {
    // `app/key/` is module `key`. Were it swept into `app`, sealing would have
    // nothing to seal: the two would share one namespace.
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var sink = Sink.init(arena.allocator());
    var interner: Interner = .empty;
    defer interner.deinit(testing.allocator);

    var table: FileTable = .empty;
    defer table.deinit(testing.allocator);

    var p = try loadFromMemory(testing.allocator, &table, &sink, &interner, "app", &.{
        .{ .path = "app/main.lin", .text = "fn main() -> UInt8 { 1 }" },
        .{ .path = "app/key/key.lin", .text = "fn mint() -> UInt8 { 2 }" },
    }, .program, false, .borrow);
    defer p.deinit(testing.allocator);

    try testing.expectEqual(@as(usize, 1), p.root().files.len);
    try testing.expectEqualStrings("app/main.lin", table.get(p.root().files[0]).path);
}

test "files are ordered by name, not by the order they were found" {
    // A module's files have no order. Numbering them by discovery would let a
    // filesystem's listing decide which duplicate declaration is reported
    // first, and that is not the filesystem's decision to make.
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var sink = Sink.init(arena.allocator());
    var interner: Interner = .empty;
    defer interner.deinit(testing.allocator);

    var table: FileTable = .empty;
    defer table.deinit(testing.allocator);

    var p = try loadFromMemory(testing.allocator, &table, &sink, &interner, "app", &.{
        .{ .path = "app/z.lin", .text = "fn z() -> UInt8 { 1 }" },
        .{ .path = "app/a.lin", .text = "fn a() -> UInt8 { 2 }" },
    }, .program, false, .borrow);
    defer p.deinit(testing.allocator);

    try testing.expectEqualStrings("app/a.lin", table.get(p.root().files[0]).path);
    try testing.expectEqualStrings("app/z.lin", table.get(p.root().files[1]).path);
}

test "a bare filename entry has an empty directory and still loads" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var sink = Sink.init(arena.allocator());
    var interner: Interner = .empty;
    defer interner.deinit(testing.allocator);

    var table: FileTable = .empty;
    defer table.deinit(testing.allocator);

    var p = try loadFromMemory(testing.allocator, &table, &sink, &interner, "t.lin", &.{
        .{ .path = "t.lin", .text = "fn main() -> UInt8 { 1 }" },
    }, .program, false, .borrow);
    defer p.deinit(testing.allocator);

    try testing.expectEqual(@as(usize, 1), p.root().files.len);
    try testing.expectEqualStrings("", p.root().dir);
}

test "the last element of a path is the module's name" {
    try testing.expectEqualStrings("hash", nameOf("app/util/hash"));
    try testing.expectEqualStrings("app", nameOf("app"));
    try testing.expectEqualStrings("", nameOf(""));
}

/// What the semantic passes settled about a program.
pub const Semantics = struct {
    expanded: ExpandedProgram,
    res: Resolution,
    typing: Typing,
    /// Ordered disposals that ownership permits at each exit.
    disposals: DisposalPlan,
    type_arena: ?std.heap.ArenaAllocator = null,
    reused_library: bool = false,

    /// Reverse of the order they were produced in, because a later pass may
    /// hold what an earlier one allocated.
    pub fn deinit(self: *Semantics, gpa: std.mem.Allocator) void {
        self.disposals.deinit(gpa);
        if (self.type_arena) |*arena| arena.deinit() else self.typing.deinit(gpa);
        self.res.deinit(gpa);
        self.expanded.deinit(gpa);
    }
};

/// Resolves, type-checks and ownership-checks a loaded program.
///
/// The order is a rule rather than a convenience -- ownership reads what the
/// checker settled -- and so is the one step that has no condition on it.
/// Ownership runs whether or not the checker was happy: a place whose type is
/// poison adds no settlement obligation, avoiding ownership cascades. A
/// program with an unrelated mistake would otherwise never be
/// told about the leak in it.
///
/// One routine, because the command line and the conformance suite compile the
/// same program and a second statement of the order is a second answer. A pass
/// one of them ran and the other did not is a rule the suite cannot see, and
/// the condition on ownership is exactly the kind of detail a second copy
/// keeps and then loses.
///
/// Retained semantic tables use `gpa`. Ownership's temporary graph and flow
/// buffers use a pass-scoped arena backed by `scratch`, so they cannot strand
/// storage in a longer-lived semantic arena. A caller with one compilation
/// lifetime may supply the same allocator for both.
pub fn checkProgram(
    gpa: std.mem.Allocator,
    scratch: std.mem.Allocator,
    program: *const Program,
    source_interner: *const Interner,
    sink: *Sink,
    purpose: Purpose,
) !Semantics {
    return checkProgramInternal(gpa, scratch, program, source_interner, sink, purpose, null, false);
}

fn checkProgramInternal(
    gpa: std.mem.Allocator,
    scratch: std.mem.Allocator,
    program: *const Program,
    source_interner: *const Interner,
    sink: *Sink,
    purpose: Purpose,
    library_prefix: ?*const CheckedLibrary,
    prepare_completions: bool,
) !Semantics {
    const retained = if (library_prefix) |prefix|
        if (prefix.resolved.canResume(program, source_interner)) prefix else null
    else
        null;
    const z_resolve = tracy.beginZone(@src(), "resolve");
    const resolved = if (retained) |prefix|
        try @import("../sema/resolve.zig").resolveWithPrefix(gpa, program, source_interner, sink, purpose, &prefix.resolved)
    else
        try resolve(gpa, program, source_interner, sink, purpose);
    z_resolve.end();
    var expanded = resolved.expanded;
    errdefer expanded.deinit(gpa);
    var res = resolved.resolution;
    errdefer res.deinit(gpa);
    try expanded.collapseGeneratedDiagnostics(sink);

    const z_typecheck = tracy.beginZone(@src(), "typecheck");
    const relocation_mod = @import("../syntax/relocation.zig");
    const relocation: ?relocation_mod.Relocation = if (retained) |prefix| .{
        .source = relocation_mod.Mark.of(&prefix.sources.program.ast),
        .destination = relocation_mod.Mark.of(&program.ast),
    } else null;
    var type_arena: ?std.heap.ArenaAllocator = null;
    var typing = if (retained) |prefix| blk: {
        const continued = try @import("../sema/typecheck.zig").typecheckWithPrefix(gpa, &expanded, &res, sink, &prefix.checked, relocation.?, prepare_completions);
        type_arena = continued.arena;
        break :blk continued.typing;
    } else if (prepare_completions)
        try @import("../sema/typecheck.zig").typecheckForEditor(gpa, &expanded, &res, sink)
    else
        try typecheck(gpa, &expanded, &res, sink);
    z_typecheck.end();
    errdefer if (type_arena) |*arena| arena.deinit() else typing.deinit(gpa);
    try expanded.collapseGeneratedDiagnostics(sink);

    const z_ownership = tracy.beginZone(@src(), "ownership");
    var disposals = blk: {
        var temporary = std.heap.ArenaAllocator.init(scratch);
        defer temporary.deinit();
        if (retained) |prefix| {
            const temp = temporary.allocator();
            var declarations: std.AutoHashMapUnmanaged(DeclId, void) = .empty;
            for (0..prefix.resolved.result.expanded.ast.declCount()) |i| {
                try declarations.put(temp, relocation.?.id(DeclId, DeclId.at(@intCast(i))), {});
            }
            const expressions = try temp.alloc(node.ExprId, prefix.resolved.result.expanded.ast.exprCount());
            for (expressions, 0..) |*expression, i| expression.* = relocation.?.id(node.ExprId, node.ExprId.at(@intCast(i)));
            break :blk try @import("../ownership/check.zig").checkWithRetained(gpa, temp, &expanded, &res, &typing, sink, .{
                .declarations = &declarations,
                .disposals = &prefix.disposals,
                .expressions = expressions,
            });
        }
        break :blk try checkOwnership(gpa, temporary.allocator(), &expanded, &res, &typing, sink);
    };
    z_ownership.end();
    errdefer disposals.deinit(gpa);
    try expanded.collapseGeneratedDiagnostics(sink);

    return .{ .expanded = expanded, .res = res, .typing = typing, .disposals = disposals, .type_arena = type_arena, .reused_library = retained != null };
}

/// The rules only instance discovery can settle, reported.
///
/// A body is checked once in terms of its parameters and discovered once per
/// instantiation, so a rule about a concrete instance -- how wide one is, how
/// deep the chain that produced it went -- has nothing to fire against until
/// discovery has run. Reporting without retaining generated code is still
/// reporting: a file that checks clean has to be a file that builds.
///
/// Only where the passes above were happy, because discovery walks a
/// program they approved and a tree they rejected has instantiations nobody
/// settled.
///
/// One routine, because a command line and an editor asking what is wrong
/// with a program is one question. A copy that stopped at the checker is
/// exactly what left the editor showing a clean file for a program that does
/// not compile.
///
pub fn checkInstantiations(
    gpa: std.mem.Allocator,
    semantics: *const Semantics,
    sink: *Sink,
) !void {
    if (sink.hasErrors()) return;
    var instances = try instantiate(gpa, &semantics.expanded, &semantics.res, &semantics.typing, &semantics.disposals, sink, .program);
    defer instances.deinit();
    try semantics.expanded.collapseGeneratedDiagnostics(sink);
}

/// What a test asserts against, so a case reads as its claim rather than as
/// the pipeline that produced it.
pub const Checked = struct {
    errors: u32,
    /// `.s_entry` when there were none, so a test never reads a null.
    first_code: Code,
    /// Every rule that fired, so a test can say which one it is about rather
    /// than which one happened to be reported first.
    seen: std.EnumSet(Code),
    /// How many modules the entry reached.
    modules: u32,
    /// How many of the diagnostics were about loading rather than about what
    /// the modules say. A test about the graph asserts on this: until a name
    /// can be reached through an import, every import is also unused.
    import_errors: u32,

    pub fn has(self: Checked, code: Code) bool {
        return self.seen.contains(code);
    }
};

/// Loads, parses, resolves and type-checks files held in memory.
///
/// The entry is the directory of `files[0]`, so a case is its files and
/// nothing else; a single file with no `/` in its path is its own module.
pub fn checkModules(gpa: std.mem.Allocator, files: []const InMemoryFile) !Checked {
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();

    var table: FileTable = .empty;
    defer table.deinit(gpa);

    var sink = Sink.init(arena.allocator());
    var interner: Interner = .empty;
    defer interner.deinit(gpa);

    var program = try loadFromMemory(gpa, &table, &sink, &interner, dirOf(files[0].path), files, .program, false, .borrow);
    defer program.deinit(gpa);

    // The passes allocate diagnostic text the sink then holds, so they are
    // given the arena the sink was built on rather than the allocator whose
    // leaks this test is watching.
    const scratch = arena.allocator();
    var settled = try checkProgram(scratch, gpa, &program, &interner, &sink, .program);
    defer settled.deinit(scratch);

    var import_errors: u32 = 0;
    var seen: std.EnumSet(Code) = .initEmpty();
    for (sink.items()) |d| {
        if (d.code) |c| seen.insert(c);
        if (d.code == .m_import) import_errors += 1;
    }

    return .{
        .errors = @intCast(sink.items().len),
        .first_code = if (sink.items().len == 0) .s_entry else sink.items()[0].code.?,
        .seen = seen,
        .modules = @intCast(program.modules.len),
        .import_errors = import_errors,
    };
}

test "files in one module see each other with no import" {
    // The whole claim of directory granularity. If this fails the resolver is
    // still per-file, and a module is a directory in name only.
    const got = try checkModules(testing.allocator, &.{
        .{ .path = "app/main.lin", .text = "fn main() -> UInt8 { helper() }" },
        .{ .path = "app/helper.lin", .text = "fn helper() -> UInt8 { 3 }" },
    });
    try testing.expectEqual(@as(u32, 0), got.errors);
}

test "a name declared twice in one module is duplicate, across files" {
    const got = try checkModules(testing.allocator, &.{
        .{ .path = "app/a.lin", .text = "fn open() -> UInt8 { 1 }\nfn main() -> UInt8 { open() }" },
        .{ .path = "app/b.lin", .text = "fn open() -> UInt8 { 2 }" },
    });
    try testing.expectEqual(@as(u32, 1), got.errors);
    try testing.expectEqual(Code.n_duplicate, got.first_code);
}

test "one `main` across the module is enough, and two is too many" {
    const one = try checkModules(testing.allocator, &.{
        .{ .path = "app/a.lin", .text = "fn helper() -> UInt8 { 1 }" },
        .{ .path = "app/b.lin", .text = "fn main() -> UInt8 { helper() }" },
    });
    try testing.expectEqual(@as(u32, 0), one.errors);

    const two = try checkModules(testing.allocator, &.{
        .{ .path = "app/a.lin", .text = "fn main() -> UInt8 { 1 }" },
        .{ .path = "app/b.lin", .text = "fn main() -> UInt8 { 2 }" },
    });
    // Two `main`s in one module are also two declarations of one name, so the
    // entry-point rule and the duplicate rule both fire.
    try testing.expect(two.errors >= 1);
}

test "a diagnostic in the second file names the second file" {
    // The failure this exists for: ids run across a module's files, so a
    // second file's spans are offsets into a stream but not into the first
    // file's text. A label that kept the module's first file renders a caret
    // at a plausible position in the wrong source.
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    var table: FileTable = .empty;
    defer table.deinit(testing.allocator);

    var sink = Sink.init(arena.allocator());
    var interner: Interner = .empty;
    defer interner.deinit(testing.allocator);

    var program = try loadFromMemory(testing.allocator, &table, &sink, &interner, "app", &.{
        .{ .path = "app/a.lin", .text = "fn main() -> UInt8 { helper() }" },
        .{ .path = "app/b.lin", .text = "fn helper() -> UInt8 { nope }" },
    }, .program, false, .borrow);
    defer program.deinit(testing.allocator);

    var resolved = try resolve(testing.allocator, &program, &interner, &sink, .program);
    defer resolved.resolution.deinit(testing.allocator);
    defer resolved.expanded.deinit(testing.allocator);

    try testing.expectEqual(@as(usize, 1), sink.items().len);
    const label = sink.items()[0].primaryLabel().?;
    try testing.expectEqualStrings("app/b.lin", table.get(label.file).path);
    try testing.expectEqualStrings("nope", label.span.slice(table.get(label.file).text));
}

test "a module's tree reproduces each file's text from its own spans" {
    // The lossless property, which a module has to keep per file: spans are
    // offsets into the file that produced them, never into the concatenation.
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    var table: FileTable = .empty;
    defer table.deinit(testing.allocator);

    var sink = Sink.init(arena.allocator());
    var interner: Interner = .empty;
    defer interner.deinit(testing.allocator);

    var program = try loadFromMemory(testing.allocator, &table, &sink, &interner, "app", &.{
        .{ .path = "app/a.lin", .text = "fn main() -> UInt8 { alpha() }" },
        .{ .path = "app/b.lin", .text = "fn alpha() -> UInt8 { 7 }" },
    }, .program, false, .borrow);
    defer program.deinit(testing.allocator);

    const ast = &program.ast;
    try testing.expectEqual(@as(usize, 2), ast.parts.len);
    for (0..ast.declCount()) |i| {
        const d = @import("../syntax/node.zig").DeclId.at(@intCast(i));
        const text = table.get(ast.fileOfDecl(d)).text;
        try testing.expect(std.mem.startsWith(u8, ast.declSpan(d).slice(text), "fn "));
    }
}

test "a dotted path names directories, not a namespace" {
    // Readers from Java or C# expect `util.hash` to be inside a package
    // `util`. It is not: `util` is not an enclosing anything, is not bound,
    // and is not loaded at all.
    const got = try checkModules(testing.allocator, &.{
        .{ .path = "app/main.lin", .text = "import util.hash;\nfn main() -> UInt8 { 1 }" },
        .{ .path = "app/util/hash/h.lin", .text = "fn d() -> UInt8 { 4 }" },
        .{ .path = "app/util/u.lin", .text = "fn other() -> UInt8 { 5 }" },
    });
    // The root and `util/hash`. `util` itself is never reached.
    try testing.expectEqual(@as(u32, 2), got.modules);
}

test "an import is relative to the source root" {
    // `app/a/a.lin` says `import b;` and gets `app/b/`, whichever module wrote
    // the route.
    const got = try checkModules(testing.allocator, &.{
        .{ .path = "app/main.lin", .text = "import a;\nfn main() -> UInt8 { 1 }" },
        .{ .path = "app/a/a.lin", .text = "import b;\nfn f() -> UInt8 { 1 }" },
        .{ .path = "app/a/b/b.lin", .text = "fn g() -> UInt8 { 6 }" },
        .{ .path = "app/b/wrong.lin", .text = "fn g() -> UInt8 { 9 }" },
    });
    try testing.expectEqual(@as(u32, 3), got.modules);
}

test "declarations of one extern symbol agree on its signature" {
    // Each module is outside the library, so every case also reports
    // [M-Extern]; the agreement rule is checked beside it. The symbol is
    // outside the runtime's `linea_` namespace, whose declarations answer to
    // the runtime's own signatures instead ([T-ExternRuntime]).
    const cases = [_]struct { other: []const u8, agrees: bool, refused: ?Code = null }{
        .{ .other = "extern fn close_descriptor(fd: Int32) -> Int64", .agrees = true },
        .{ .other = "extern fn close_descriptor(descriptor: Int32) -> Int64", .agrees = true },
        .{ .other = "extern fn close_descriptor(fd: Int64) -> Int64", .agrees = false },
        .{ .other = "extern fn close_descriptor(fd: Int32) -> Int32", .agrees = false },
        .{ .other = "extern fn close_descriptor(sink fd: Int32) -> Int64", .agrees = false },
        .{ .other = "extern fn close_descriptor(fd: Int32, flags: Int32) -> Int64", .agrees = false },
        // A signature that was already refused is not compared as well.
        .{ .other = "extern fn close_descriptor(fd: Missing) -> Int64", .agrees = true, .refused = .n_undefined },
        .{ .other = "extern fn close_descriptor(fd: Int32) -> Missing", .agrees = true, .refused = .n_undefined },
    };
    for (cases) |case| {
        const got = try checkModules(testing.allocator, &.{
            .{ .path = "app/main.lin", .text = "import a;\nimport b;\nfn main() -> UInt8 { UInt8(a.close() + b.close()) }" },
            .{ .path = "app/a/a.lin", .text = "extern fn close_descriptor(fd: Int32) -> Int64\npub fn close() -> Int64 { close_descriptor(3) }" },
            .{ .path = "app/b/b.lin", .text = case.other },
            .{ .path = "app/b/close.lin", .text = "pub fn close() -> Int64 { 0 }" },
        });
        try testing.expect(got.has(.m_extern));
        if (case.refused) |code| try testing.expect(got.has(code));
        try testing.expectEqual(!case.agrees, got.has(.t_extern_agreement));
    }
}

test "a root-relative import ring reuses loaded modules" {
    const got = try checkModules(testing.allocator, &.{
        .{ .path = "app/main.lin", .text = "import a;\nfn main() -> UInt8 { a.f() }" },
        .{ .path = "app/a/a.lin", .text = "import b;\npub fn f() -> UInt8 { b.g() }\npub fn zero() -> UInt8 { 7 }" },
        .{ .path = "app/b/b.lin", .text = "import a;\npub fn g() -> UInt8 { a.zero() }" },
    });
    try testing.expectEqual(@as(u32, 0), got.errors);
    try testing.expectEqual(@as(u32, 3), got.modules);
}

test "a generated implementation preserves a qualified derive bound" {
    const got = try checkModules(testing.allocator, &.{
        .{ .path = "app/main.lin", .text =
        \\import protocol as p
        \\struct Box[T] { value: T }
        \\derive[T: p.Mark] p.Mark for Box[T]
        \\fn main() -> UInt8 { let _box: Box[UInt8] = .{ value = 1 }; 0 }
        },
        .{ .path = "app/protocol/protocol.lin", .text =
        \\pub trait Mark {}
        \\template impl Mark {}
        },
    });
    try testing.expectEqual(@as(u32, 0), got.errors);
}

test "grouped generated implementations import every qualified bound module" {
    const got = try checkModules(testing.allocator, &.{
        .{ .path = "app/main.lin", .text =
        \\import first
        \\import second
        \\import protocol as p
        \\import formatting as f
        \\struct Box[T] { value: T }
        \\struct Value {}
        \\impl first.Mark for Value {}
        \\impl second.Tag for Value {}
        \\derive[T: first.Mark + second.Tag] (p.Render, f.Inspect) for Box[T]
        \\fn main() -> UInt8 { let _box: Box[Value] = .{ value = .{} }; 0 }
        },
        .{ .path = "app/first/first.lin", .text = "pub trait Mark {}\n" },
        .{ .path = "app/second/second.lin", .text = "pub trait Tag {}\n" },
        .{ .path = "app/protocol/protocol.lin", .text =
        \\pub trait Render {}
        \\template impl Render {}
        },
        .{ .path = "app/formatting/formatting.lin", .text =
        \\pub trait Inspect {}
        \\template impl Inspect {}
        },
    });
    try testing.expectEqual(@as(u32, 0), got.errors);
}

test "a generated generic member resolves a projected bound type" {
    const got = try checkModules(testing.allocator, &.{
        .{ .path = "app/main.lin", .text =
        \\import protocol
        \\@derive(protocol.Render)
        \\struct Mark {}
        \\fn main() -> UInt8 { let _mark: Mark = .{}; 0 }
        },
        .{ .path = "app/protocol/protocol.lin", .text =
        \\pub trait Sink { type Error }
        \\pub trait Render {
        \\    fn render[W: Sink](self: Self, sink value: W.Error) -> W.Error where carries(value)
        \\}
        \\template impl Render {
        \\    fn render[W: Sink](_self: Self, sink value: W.Error) -> W.Error where carries(value) { value }
        \\}
        },
    });
    try testing.expectEqual(@as(u32, 0), got.errors);
}

test "an erased generated parameter is deliberately unused" {
    const got = try checkModules(testing.allocator, &.{
        .{ .path = "app/main.lin", .text =
        \\import protocol
        \\@derive(protocol.Render)
        \\enum Empty {}
        \\fn main() -> UInt8 { 0 }
        },
        .{ .path = "app/protocol/protocol.lin", .text =
        \\pub trait Render {
        \\    fn render(self: Self, value: UInt8) -> UInt8
        \\}
        \\template impl Render {
        \\    fn render(self: Self, value: UInt8) -> UInt8 {
        \\        match read self {
        \\            reflect.case => value,
        \\        }
        \\    }
        \\}
        },
    });
    try testing.expectEqual(@as(u32, 0), got.errors);
}

test "one directory is one module, whichever route reaches it" {
    // `app/a/b` is named directly and through `a`. Loading it twice would give
    // one directory two module ids, and a name declared in it would collide
    // with itself.
    const got = try checkModules(testing.allocator, &.{
        .{ .path = "app/main.lin", .text = "import a.b;\nimport a;\nfn main() -> UInt8 { b.g() + a.f() }" },
        .{ .path = "app/a/a.lin", .text = "import a.b;\npub fn f() -> UInt8 { b.g() }" },
        .{ .path = "app/a/b/b.lin", .text = "pub fn g() -> UInt8 { 7 }" },
    });
    try testing.expectEqual(@as(u32, 0), got.errors);
    try testing.expectEqual(@as(u32, 3), got.modules);
}

test "two modules importing one root-relative route reach one module" {
    const got = try checkModules(testing.allocator, &.{
        .{ .path = "app/main.lin", .text = "import b;\nimport c;\nfn main() -> UInt8 { 1 }" },
        .{ .path = "app/b/b.lin", .text = "import d;\nfn f() -> UInt8 { 1 }" },
        .{ .path = "app/c/c.lin", .text = "import d;\nfn g() -> UInt8 { 1 }" },
        .{ .path = "app/d/d.lin", .text = "fn h() -> UInt8 { 1 }" },
    });
    try testing.expectEqual(@as(u32, 0), got.import_errors);
    try testing.expectEqual(@as(u32, 4), got.modules);
}

test "`std` is reserved, and a local directory of that name says so" {
    // Otherwise what `std` means would depend on whether a directory of that
    // name happens to sit beside the importing module, which is a question a
    // reader cannot answer from the import.
    const got = try checkModules(testing.allocator, &.{
        .{ .path = "app/main.lin", .text = "import std;\nfn main() -> UInt8 { 1 }" },
        .{ .path = "app/std/s.lin", .text = "fn f() -> UInt8 { 8 }" },
    });
    try testing.expectEqual(Code.m_import, got.first_code);
}

test "an import of nothing is reported at the path" {
    const got = try checkModules(testing.allocator, &.{
        .{ .path = "app/main.lin", .text = "import missing;\nfn main() -> UInt8 { 1 }" },
    });
    try testing.expectEqual(Code.m_import, got.first_code);
    try testing.expectEqual(@as(u32, 1), got.modules);
}

test "a directory holding no .lin file is not a module" {
    // The directory exists in the listing, and holds nothing the compiler can
    // read. That is the same failure as naming a directory that is not there.
    const got = try checkModules(testing.allocator, &.{
        .{ .path = "app/main.lin", .text = "import notes;\nfn main() -> UInt8 { 1 }" },
        .{ .path = "app/notes/readme.txt", .text = "not a module" },
    });
    try testing.expectEqual(Code.m_import, got.first_code);
}

test "a name crosses a module boundary only through an import" {
    const got = try checkModules(testing.allocator, &.{
        .{ .path = "app/main.lin", .text = "import a;\nfn main() -> UInt8 { a.open() }" },
        .{ .path = "app/a/a.lin", .text = "pub fn open() -> UInt8 { 5 }" },
    });
    try testing.expectEqual(@as(u32, 0), got.errors);
}

test "a private declaration cannot be named from another module" {
    const got = try checkModules(testing.allocator, &.{
        .{ .path = "app/main.lin", .text = "import a;\nfn main() -> UInt8 { a.hidden() }" },
        .{ .path = "app/a/a.lin", .text = "fn hidden() -> UInt8 { 1 }" },
    });
    try testing.expectEqual(Code.m_vis, got.first_code);
}

test "a module name is resolvable, not evaluable" {
    // A module is a scope, not a value. There is no `type` and no compile-time
    // evaluation, so there is nothing for `let m = a;` to mean -- and the
    // qualifier position is the only place the name is visible at all.
    const got = try checkModules(testing.allocator, &.{
        .{ .path = "app/main.lin", .text = "import a;\nfn main() -> UInt8 { let m = a; a.f() }" },
        .{ .path = "app/a/a.lin", .text = "pub fn f() -> UInt8 { 1 }" },
    });
    try testing.expectEqual(Code.n_undefined, got.first_code);
}

test "an exported declaration is used by being reachable" {
    // Without the exemption, `pub` would make exporting something a mistake
    // wherever the exporting module does not also use it.
    const got = try checkModules(testing.allocator, &.{
        .{ .path = "app/main.lin", .text = "import a;\nfn main() -> UInt8 { a.f() }" },
        .{ .path = "app/a/a.lin", .text = "pub fn f() -> UInt8 { 1 }\npub fn unreferenced() -> UInt8 { 2 }" },
    });
    try testing.expectEqual(@as(u32, 0), got.errors);
}

test "a private declaration is still checked for use" {
    const got = try checkModules(testing.allocator, &.{
        .{ .path = "app/main.lin", .text = "import a;\nfn main() -> UInt8 { a.f() }" },
        .{ .path = "app/a/a.lin", .text = "pub fn f() -> UInt8 { 1 }\nfn dead() -> UInt8 { 2 }" },
    });
    try testing.expectEqual(@as(u32, 1), got.errors);
    try testing.expectEqual(Code.n_unused, got.first_code);
}

test "an unused import is reported as an import" {
    const got = try checkModules(testing.allocator, &.{
        .{ .path = "app/main.lin", .text = "import a;\nfn main() -> UInt8 { 1 }" },
        .{ .path = "app/a/a.lin", .text = "pub fn f() -> UInt8 { 1 }" },
    });
    try testing.expectEqual(@as(u32, 1), got.errors);
    try testing.expectEqual(Code.m_unused, got.first_code);
}

test "two modules may declare the same name" {
    const got = try checkModules(testing.allocator, &.{
        .{ .path = "app/main.lin", .text = "import a;\nimport b;\nfn main() -> UInt8 { a.open() + b.open() }" },
        .{ .path = "app/a/a.lin", .text = "pub fn open() -> UInt8 { 1 }" },
        .{ .path = "app/b/b.lin", .text = "pub fn open() -> UInt8 { 2 }" },
    });
    try testing.expectEqual(@as(u32, 0), got.errors);
}

test "two imports ending in the same element collide, and `as` resolves it" {
    const clash = try checkModules(testing.allocator, &.{
        .{ .path = "app/main.lin", .text = "import util.hash;\nimport crypto.hash;\nfn main() -> UInt8 { hash.d() }" },
        .{ .path = "app/util/hash/a.lin", .text = "pub fn d() -> UInt8 { 1 }" },
        .{ .path = "app/crypto/hash/b.lin", .text = "pub fn d() -> UInt8 { 2 }" },
    });
    try testing.expectEqual(Code.n_duplicate, clash.first_code);

    const ok = try checkModules(testing.allocator, &.{
        .{ .path = "app/main.lin", .text = "import util.hash;\nimport crypto.hash as ch;\nfn main() -> UInt8 { hash.d() + ch.d() }" },
        .{ .path = "app/util/hash/a.lin", .text = "pub fn d() -> UInt8 { 1 }" },
        .{ .path = "app/crypto/hash/b.lin", .text = "pub fn d() -> UInt8 { 2 }" },
    });
    try testing.expectEqual(@as(u32, 0), ok.errors);
}

test "a name the module does not declare is undefined, not private" {
    const got = try checkModules(testing.allocator, &.{
        .{ .path = "app/main.lin", .text = "import a;\nfn main() -> UInt8 { a.missing() }" },
        .{ .path = "app/a/a.lin", .text = "pub fn f() -> UInt8 { 1 }" },
    });
    try testing.expectEqual(Code.n_undefined, got.first_code);
}

test "a phase runs across every module before the next begins" {
    // The spec's phase ordering, and the only thing that tests it: a driver
    // that resolved and typed each module in turn would stop at the first
    // module's error, so the second module's would never appear. Both must.
    const got = try checkModules(testing.allocator, &.{
        .{ .path = "app/main.lin", .text = "import a;\nfn main() -> UInt8 { a.f() + true }" },
        .{ .path = "app/a/a.lin", .text = "pub fn f() -> UInt8 { 1 + false }" },
    });
    try testing.expectEqual(@as(u32, 2), got.errors);
}

test "a name is resolved in every module before any module is typed" {
    // What the ordering buys: `main` is checked against `f`'s real signature,
    // so the mismatch is a type error rather than an undefined name.
    const got = try checkModules(testing.allocator, &.{
        .{ .path = "app/main.lin", .text = "import a;\nfn main() -> UInt8 { a.f(1) }" },
        .{ .path = "app/a/a.lin", .text = "pub fn f() -> UInt8 { 1 }" },
    });
    try testing.expectEqual(@as(u32, 1), got.errors);
    try testing.expectEqual(Code.t_arity, got.first_code);
}

/// A module whose type is sealed, and the two functions that are the only way
/// to get one or learn anything from one.
const vault_lin =
    \\@opaque enum Key { Forged(UInt8) }
    \\
    \\pub fn mint(id: UInt8) -> Key {
    \\    Key.Forged(id)
    \\}
    \\
    \\pub fn tag(k: Key) -> UInt8 {
    \\    match read k { Forged(n) => n }
    \\}
;

fn outsideVault(body: []const u8) !Checked {
    return checkModules(testing.allocator, &.{
        .{ .path = "app/main.lin", .text = body },
        .{ .path = "app/vault/key.lin", .text = vault_lin },
    });
}

test "inside its own module a sealed type is an ordinary one" {
    // The seal is boundary-relative. If this fails, `opaque` has become
    // `no one may use this`, which is a different and useless feature.
    const got = try outsideVault("import vault;\nfn main() -> UInt8 { vault.tag(vault.mint(7)) }");
    try testing.expectEqual(@as(u32, 0), got.errors);
}

test "a sealed variant cannot be named from context" {
    // The site an omission cannot close. `.Forged` resolves against the type
    // the parameter expects, not against a scope, so nothing was left out that
    // would have stopped it.
    const got = try outsideVault("import vault;\nfn main() -> UInt8 { vault.tag(.Forged(7)) }");
    try testing.expectEqual(Code.m_opaque, got.first_code);
}

test "a sealed variant cannot be named through its type" {
    const got = try outsideVault("import vault;\nfn main() -> UInt8 { vault.tag(vault.Key.Forged(7)) }");
    try testing.expectEqual(Code.m_opaque, got.first_code);
}

test "a sealed type cannot be matched" {
    const got = try outsideVault(
        "import vault;\nfn main() -> UInt8 { let k = vault.mint(7); match k { Forged(n) => n } }",
    );
    try testing.expectEqual(Code.m_opaque, got.first_code);
}

test "a catch-all does not defeat the seal" {
    // The row that matters. `_` names no variant and so needs nothing from the
    // sealed type, which makes it the obvious exemption -- and the exemption
    // would defeat the whole point, since `match k { _ => 0 }` would be the
    // way to learn that `k` is a `k`. What is sealed is the scrutinee's type.
    const got = try outsideVault(
        "import vault;\nfn main() -> UInt8 { let k = vault.mint(7); match k { _ => 0 } }",
    );
    try testing.expectEqual(Code.m_opaque, got.first_code);
}

const bank_lin =
    \\@opaque struct Account { id: UInt8, balance: UInt8 }
    \\
    \\pub fn open(id: UInt8) -> Account {
    \\    .{ id = id, balance = 0 }
    \\}
    \\
    \\pub fn total(a: Account) -> UInt8 {
    \\    a.balance
    \\}
;

fn outsideBank(body: []const u8) !Checked {
    return checkModules(testing.allocator, &.{
        .{ .path = "app/main.lin", .text = body },
        .{ .path = "app/bank/b.lin", .text = bank_lin },
    });
}

test "a sealed struct cannot be built from a literal" {
    const got = try outsideBank(
        "import bank;\nfn main() -> UInt8 { bank.total(.{ id = 1, balance = 0 }) }",
    );
    try testing.expectEqual(Code.m_opaque, got.first_code);
}

test "a sealed struct's field cannot be read" {
    const got = try outsideBank(
        "import bank;\nfn main() -> UInt8 { let a = bank.open(1); a.balance }",
    );
    try testing.expectEqual(Code.m_opaque, got.first_code);
}

test "a sealed struct's field cannot be assigned" {
    const got = try outsideBank(
        "import bank;\nfn main() -> UInt8 { var a = bank.open(1); a.balance = 9; bank.total(a) }",
    );
    try testing.expectEqual(Code.m_opaque, got.first_code);
}

test "a bare type name does not reach across a module boundary" {
    // Types live in one tree with every other module's, so nothing but the
    // module's own range keeps `Account` from being nameable here.
    const got = try outsideBank(
        "import bank;\nfn open(id: Account) -> UInt8 { 1 }\nfn main() -> UInt8 { bank.total(bank.open(1)) }",
    );
    try testing.expect(got.errors > 0);
}

const account_with_open =
    \\struct Account { id: UInt8, balance: UInt8 }
    \\
    \\impl Account {
    \\    pub fn open(id: UInt8) -> Account {
    \\        .{ id = id, balance = 0 }
    \\    }
    \\}
    \\
    \\fn main() -> UInt8 {
    \\    Account.open(7).id
    \\}
;

test "a struct may declare a function beside its fields" {
    const got = try checkModules(testing.allocator, &.{
        .{ .path = "case.lin", .text = account_with_open },
    });
    try testing.expectEqual(@as(u32, 0), got.errors);
}

test "a declaration inside a type sees no instance" {
    // Namespace, not method. If `id` resolves here a receiver has been
    // invented, and every later feature has to say what it binds to.
    const got = try checkModules(testing.allocator, &.{
        .{ .path = "case.lin", .text =
        \\struct Account { id: UInt8 }
        \\impl Account { pub fn bad() -> UInt8 { id } }
        \\fn main() -> UInt8 { Account.bad() }
        },
    });
    try testing.expectEqual(Code.n_undefined, got.first_code);
}

test "a member is not a name in the module that holds its type" {
    // Reached through the type or not at all. A member that leaked into the
    // module scope would collide with a function of the same name.
    const got = try checkModules(testing.allocator, &.{
        .{ .path = "case.lin", .text =
        \\struct Account { id: UInt8 }
        \\impl Account { pub fn open(id: UInt8) -> Account { .{ id = id } } }
        \\fn open() -> UInt8 { 1 }
        \\fn main() -> UInt8 { Account.open(7).id + open() }
        },
    });
    try testing.expectEqual(@as(u32, 0), got.errors);
}

test "a private member does not cross a module boundary" {
    const got = try checkModules(testing.allocator, &.{
        .{ .path = "app/main.lin", .text = "import bank;\nfn main() -> UInt8 { bank.Account.secret() }" },
        .{ .path = "app/bank/b.lin", .text =
        \\pub struct Account { id: UInt8 }
        \\impl Account { fn secret() -> UInt8 { 1 } }
        },
    });
    try testing.expectEqual(Code.m_vis, got.first_code);
}

test "an unused private member is reported like any other declaration" {
    const got = try checkModules(testing.allocator, &.{
        .{ .path = "case.lin", .text =
        \\struct Account { id: UInt8 }
        \\impl Account { fn dead() -> UInt8 { 1 } }
        \\fn main() -> UInt8 { let a: Account = .{ id = 1 }; a.id }
        },
    });
    try testing.expectEqual(Code.n_unused, got.first_code);
}

test "a type's members are named once" {
    const got = try checkModules(testing.allocator, &.{
        .{ .path = "case.lin", .text =
        \\struct Account { id: UInt8 }
        \\impl Account {
        \\    pub fn open() -> UInt8 { 1 }
        \\    pub fn open() -> UInt8 { 2 }
        \\}
        \\fn main() -> UInt8 { Account.open() }
        },
    });
    try testing.expectEqual(Code.n_duplicate, got.first_code);
}

test "the order a module's files were found in cannot change the program" {
    // The claim directory granularity makes: a module's files have no order.
    // A loader that numbered them by discovery would pass every other test
    // here and fail this one, because a directory listing's order is the
    // filesystem's business and a program's meaning may not depend on it.
    const forward = try checkModules(testing.allocator, &.{
        .{ .path = "app/a.lin", .text = "fn helper() -> UInt8 { 3 }" },
        .{ .path = "app/b.lin", .text = "fn main() -> UInt8 { helper() }" },
    });
    const reversed = try checkModules(testing.allocator, &.{
        .{ .path = "app/b.lin", .text = "fn main() -> UInt8 { helper() }" },
        .{ .path = "app/a.lin", .text = "fn helper() -> UInt8 { 3 }" },
    });
    try testing.expectEqual(forward.errors, reversed.errors);
    try testing.expectEqual(forward.first_code, reversed.first_code);
    try testing.expectEqual(@as(u32, 0), forward.errors);
}

test "which file of a module reports a duplicate does not depend on the listing" {
    // The sharper form: a duplicate is reported at the second declaration, so
    // which one is second has to be decided by the sort and not by whoever
    // listed the directory.
    const forward = try checkModules(testing.allocator, &.{
        .{ .path = "app/a.lin", .text = "fn open() -> UInt8 { 1 }\nfn main() -> UInt8 { open() }" },
        .{ .path = "app/b.lin", .text = "fn open() -> UInt8 { 2 }" },
    });
    const reversed = try checkModules(testing.allocator, &.{
        .{ .path = "app/b.lin", .text = "fn open() -> UInt8 { 2 }" },
        .{ .path = "app/a.lin", .text = "fn open() -> UInt8 { 1 }\nfn main() -> UInt8 { open() }" },
    });
    try testing.expectEqual(forward.errors, reversed.errors);
    try testing.expectEqual(Code.n_duplicate, forward.first_code);
    try testing.expectEqual(Code.n_duplicate, reversed.first_code);
}

test "`@linear` declares a universe and rides on the type" {
    // The key is bound and then taken apart. Written as `tag(Key.Forged(3))`
    // it is a value no place names and only lent, which nothing can consume
    // afterwards -- a leak, and not what this test is about.
    const got = try checkModules(testing.allocator, &.{
        .{ .path = "case.lin", .text =
        \\@linear enum Key { Forged(UInt8) }
        \\fn tag(k: Key) -> UInt8 { match read k { Forged(n) => n } }
        \\fn main() -> UInt8 {
        \\    let k = Key.Forged(3)
        \\    let t = tag(k)
        \\    match k { Forged(_n) => t }
        \\}
        },
    });
    try testing.expectEqual(@as(u32, 0), got.errors);
}

test "an ordinary wrapper inherits its linear field's settlement" {
    const got = try checkModules(testing.allocator, &.{
        .{ .path = "case.lin", .text =
        \\@linear enum Key { Forged(UInt8) }
        \\struct Holder { k: Key }
        \\fn main() -> UInt8 { let _h: Holder = .{ k = Key.Forged(1) }; 0 }
        },
    });
    try testing.expect(got.has(.o_leak));
    try testing.expect(!got.has(.o_universe));
}

test "a Linear type may hold a Linear one" {
    const got = try checkModules(testing.allocator, &.{
        .{ .path = "case.lin", .text =
        \\@linear enum Key { Forged(UInt8) }
        \\@linear enum Holder { Holds(Key) }
        \\fn take(sink h: Holder) -> UInt8 { match h { Holds(k) => release(k) } }
        \\fn release(sink k: Key) -> UInt8 { match k { Forged(n) => n } }
        \\fn main() -> UInt8 { take(Holder.Holds(Key.Forged(1))) }
        },
    });
    try testing.expectEqual(@as(u32, 0), got.errors);
}

test "nested ordinary wrappers inherit settlement without declaration errors" {
    const got = try checkModules(testing.allocator, &.{
        .{ .path = "case.lin", .text =
        \\@linear enum Key { Forged(UInt8) }
        \\struct Inner { k: Key }
        \\struct Outer { i: Inner }
        \\fn main() -> UInt8 { let _o: Outer = .{ i = .{ k = Key.Forged(1) } }; 0 }
        },
    });
    try testing.expect(got.has(.o_leak));
    try testing.expect(!got.has(.o_universe));
    try testing.expectEqual(@as(u32, 1), got.errors);
}

test "`pub` and `@linear` separate names from value obligations" {
    const got = try checkModules(testing.allocator, &.{
        .{ .path = "app/main.lin", .text =
        \\import vault
        \\fn main() -> UInt8 {
        \\    let k = vault.mint(4)
        \\    let t = vault.tag(k)
        \\    vault.burn(k) + t
        \\}
        },
        .{ .path = "app/vault/v.lin", .text =
        \\@linear pub enum Key { Forged(UInt8) }
        \\pub fn mint(id: UInt8) -> Key { Key.Forged(id) }
        \\pub fn tag(k: Key) -> UInt8 { match read k { Forged(n) => n } }
        \\pub fn burn(sink k: Key) -> UInt8 { match k { Forged(n) => n } }
        },
    });
    try testing.expectEqual(@as(u32, 0), got.errors);
}

test "`&` on a `sink` argument is rejected" {
    // Neither convention lends: `read` may not be written through and `sink`
    // is given away outright, so `&` says nothing true of either.
    const got = try checkModules(testing.allocator, &.{
        .{ .path = "case.lin", .text =
        \\fn release(sink _n: UInt8) -> () {}
        \\fn main() -> UInt8 { var x: UInt8 = 1; release(&x); 2 }
        },
    });
    try testing.expect(got.errors > 0);
    try testing.expectEqual(Code.s_mutation, got.first_code);
}

test "a linear value is minted, lent, and given away" {
    // The three conventions over one linear type, which is the shape every
    // program in this stage has. Nothing yet checks that `release` is called
    // exactly once -- that is the CFG's job, and it does not exist.
    const got = try checkModules(testing.allocator, &.{
        .{ .path = "case.lin", .text =
        \\@linear enum Key { Forged(UInt8) }
        \\fn tag(k: Key) -> UInt8 { match read k { Forged(n) => n } }
        \\fn release(sink k: Key) -> () { match k { Forged(_) => {} } }
        \\fn main() -> UInt8 { let k = Key.Forged(9); let t = tag(k); release(k); t }
        },
    });
    try testing.expectEqual(@as(u32, 0), got.errors);
}

/// A module whose type must be consumed, and the only two ways to do anything
/// with one. Every ownership test below is written against this.
const key_lin =
    \\@linear pub enum Key { Forged(UInt8) }
    \\
    \\pub fn mint(id: UInt8) -> Key { Key.Forged(id) }
    \\
    \\pub fn tag(k: Key) -> UInt8 { match read k { Forged(n) => n } }
    \\
    \\pub fn release(sink k: Key) -> () { match k { Forged(_) => {} } }
    \\
;

test "a linear value consumed exactly once is accepted" {
    const got = try checkModules(testing.allocator, &.{
        .{ .path = "case.lin", .text = key_lin ++
            \\fn main() -> UInt8 {
            \\    let k = mint(7);
            \\    let t = tag(k);
            \\    release(k);
            \\    t
            \\}
        },
    });
    try testing.expectEqual(@as(u32, 0), got.errors);
}

test "a linear value never consumed leaks" {
    const got = try checkModules(testing.allocator, &.{
        .{ .path = "case.lin", .text = key_lin ++
            \\fn main() -> UInt8 {
            \\    let k = mint(7);
            \\    tag(k)
            \\}
        },
    });
    try testing.expect(got.has(.o_leak));
}

test "using a value after it was taken is the same rule as taking it twice" {
    // Use-after-free and double-free are one question -- the root is moved and
    // something reads it -- so they are one code.
    const after = try checkModules(testing.allocator, &.{
        .{ .path = "case.lin", .text = key_lin ++
            \\fn main() -> UInt8 {
            \\    let k = mint(7);
            \\    release(k);
            \\    tag(k)
            \\}
        },
    });
    try testing.expect(after.has(.o_move));

    const twice = try checkModules(testing.allocator, &.{
        .{ .path = "case.lin", .text = key_lin ++
            \\fn main() -> UInt8 {
            \\    let k = mint(7);
            \\    release(k);
            \\    release(k);
            \\    0
            \\}
        },
    });
    try testing.expect(twice.has(.o_move));
}

test "`_` is exempt from unused and not from linearity" {
    // The prefix says the programmer will not use the value. That is not the
    // same claim as that it may be discarded, and confusing the two is how a
    // leak escapes.
    const got = try checkModules(testing.allocator, &.{
        .{ .path = "case.lin", .text = key_lin ++
            \\fn main() -> UInt8 {
            \\    let _k = mint(7);
            \\    0
            \\}
        },
    });
    try testing.expect(got.has(.o_leak));
}

test "arms that disagree about a linear binding are reported at the join" {
    // There is nothing to answer: calling it moved makes one path leak and
    // calling it initialised makes the other free twice.
    const got = try checkModules(testing.allocator, &.{
        .{ .path = "case.lin", .text = key_lin ++
            \\fn main() -> UInt8 {
            \\    let k = mint(7);
            \\    let c = tag(k);
            \\    if c == 7 { release(k); }
            \\    0
            \\}
        },
    });
    try testing.expect(got.has(.o_merge));
}

test "arms that agree about a linear binding are accepted" {
    const got = try checkModules(testing.allocator, &.{
        .{ .path = "case.lin", .text = key_lin ++
            \\fn main() -> UInt8 {
            \\    let k = mint(7);
            \\    let c = tag(k);
            \\    if c == 7 { release(k); } else { release(k); }
            \\    0
            \\}
        },
    });
    try testing.expectEqual(@as(u32, 0), got.errors);
}

test "a copyable binding is moved by a consuming position, and `copy` keeps it" {
    // Explicit copying preserves the source of a consuming aggregate argument.
    const moved = try checkModules(testing.allocator, &.{
        .{ .path = "case.lin", .text =
        \\@copyable struct Account { id: UInt8 }
        \\fn take(sink a: Account) -> () { let _n = a.id; }
        \\fn main() -> UInt8 {
        \\    let a: Account = .{ id = 1 };
        \\    take(a);
        \\    take(a);
        \\    0
        \\}
        },
    });
    try testing.expect(moved.has(.o_move));

    const kept = try checkModules(testing.allocator, &.{
        .{ .path = "case.lin", .text =
        \\@copyable struct Account { id: UInt8 }
        \\fn take(sink a: Account) -> () { let _n = a.id; }
        \\fn main() -> UInt8 {
        \\    let a: Account = .{ id = 1 };
        \\    take(copy(a));
        \\    take(a);
        \\    0
        \\}
        },
    });
    try testing.expectEqual(@as(u32, 0), kept.errors);
}

test "`copy` of a Linear value is refused" {
    // Copying is precisely what linearity forbids, and an escape hatch for it
    // would make the guarantee advisory.
    const got = try checkModules(testing.allocator, &.{
        .{ .path = "case.lin", .text = key_lin ++
            \\fn main() -> UInt8 {
            \\    let k = mint(7);
            \\    let j = copy(k);
            \\    release(k);
            \\    release(j);
            \\    0
            \\}
        },
    });
    try testing.expect(got.has(.o_copy));
}

test "a move inside a loop is rejected at the move" {
    const got = try checkModules(testing.allocator, &.{
        .{ .path = "case.lin", .text = key_lin ++
            \\fn main() -> UInt8 {
            \\    let k = mint(7);
            \\    var c: UInt8 = 0;
            \\    while c == 0 { release(k); c = 1; }
            \\    0
            \\}
        },
    });
    try testing.expect(got.has(.o_loop));
}

test "a binding declared inside a loop may be moved there" {
    // It is fresh on every iteration, so moving it moves a different value
    // each time and nothing runs twice.
    const got = try checkModules(testing.allocator, &.{
        .{ .path = "case.lin", .text = key_lin ++
            \\fn main() -> UInt8 {
            \\    var c: UInt8 = 0;
            \\    while c == 0 {
            \\        let k = mint(7);
            \\        release(k);
            \\        c = 1;
            \\    }
            \\    0
            \\}
        },
    });
    try testing.expectEqual(@as(u32, 0), got.errors);
}

test "a lend may not be taken from, regardless of settlement" {
    // The caller still owns what it lent. Copyable aggregates permit an
    // explicit copy; lending itself grants no consuming authority.
    const linear_taken = try checkModules(testing.allocator, &.{
        .{ .path = "case.lin", .text = key_lin ++
            \\fn steal(k: Key) -> () { release(k) }
            \\fn main() -> UInt8 { let k = mint(1); steal(k); release(k); 0 }
        },
    });
    try testing.expect(linear_taken.has(.o_move));

    const copyable_taken = try checkModules(testing.allocator, &.{
        .{ .path = "case.lin", .text =
        \\@copyable struct Account { id: UInt8 }
        \\fn open(id: UInt8) -> Account { .{ id = id } }
        \\fn take(sink account: Account) -> UInt8 { account.id }
        \\fn inspect(account: Account) -> UInt8 { take(account) }
        \\fn main() -> UInt8 { inspect(open(3)) }
        },
    });
    try testing.expect(copyable_taken.has(.o_move));

    const copied = try checkModules(testing.allocator, &.{
        .{ .path = "case.lin", .text =
        \\@copyable struct Account { id: UInt8 }
        \\fn open(id: UInt8) -> Account { .{ id = id } }
        \\fn take(sink account: Account) -> UInt8 { account.id }
        \\fn inspect(account: Account) -> UInt8 { take(copy(account)) }
        \\fn main() -> UInt8 { inspect(open(3)) }
        },
    });
    try testing.expectEqual(@as(u32, 0), copied.errors);
}

test "an `inout` parameter moved out and not put back is reported" {
    const got = try checkModules(testing.allocator, &.{
        .{ .path = "case.lin", .text = key_lin ++
            \\fn drain(inout k: Key) -> () { release(k) }
            \\fn main() -> UInt8 { var k = mint(1); drain(&k); 0 }
        },
    });
    try testing.expect(got.has(.o_reinit));
}

test "an `inout` parameter moved out and refilled is accepted" {
    const got = try checkModules(testing.allocator, &.{
        .{ .path = "case.lin", .text = key_lin ++
            \\fn swap(inout k: Key) -> () { release(k); k = mint(2); }
            \\fn main() -> UInt8 { var k = mint(1); swap(&k); release(k); 0 }
        },
    });
    try testing.expectEqual(@as(u32, 0), got.errors);
}

test "a copyable part is copied out of a linear whole without taking it" {
    // A part is read where it is named and taken where it is consumed, so a
    // `copy` is how a value comes out of something that must be disposed of
    // in one piece.
    const got = try checkModules(testing.allocator, &.{
        .{ .path = "case.lin", .text =
        \\@(opaque, linear) enum Account { Open(UInt8) }
        \\pub fn open(b: UInt8) -> Account { Account.Open(b) }
        \\pub fn balance(a: Account) -> UInt8 { match read a { Open(b) => b } }
        \\pub fn close(sink a: Account) -> UInt8 { match a { Open(b) => b } }
        \\fn main() -> UInt8 { let a = open(4); let b = balance(a); close(a) + b }
        },
    });
    try testing.expectEqual(@as(u32, 0), got.errors);
}

test "a linear struct is taken apart by destructuring it" {
    // The terminal consumer a linear `struct` would otherwise lack: `match`
    // takes an enum apart, and without this a linear structure would be a type
    // whose values could be made and never destroyed.
    const got = try checkModules(testing.allocator, &.{
        .{ .path = "case.lin", .text =
        \\@linear struct Account { id: UInt8, balance: UInt8 }
        \\impl Account {
        \\    pub fn open(opening: UInt8) -> Account { .{ id = 1, balance = opening } }
        \\    pub fn close(sink account: Account) -> UInt8 {
        \\        let Account { id: _, balance: remaining } = account;
        \\        remaining
        \\    }
        \\}
        \\fn main() -> UInt8 { Account.close(Account.open(6)) }
        },
    });
    try testing.expectEqual(@as(u32, 0), got.errors);
}

test "a destructure names every field exactly once" {
    // Whole-struct, because there are no partial moves: a field left out is a
    // part of the value nothing became responsible for.
    const missing = try checkModules(testing.allocator, &.{
        .{ .path = "case.lin", .text =
        \\struct Account { id: UInt8, balance: UInt8 }
        \\impl Account {
        \\    pub fn close(sink account: Account) -> UInt8 {
        \\        let Account { balance: remaining } = account;
        \\        remaining
        \\    }
        \\}
        \\fn main() -> UInt8 { Account.close(.{ id = 1, balance = 2 }) }
        },
    });
    try testing.expect(missing.has(.t_missing_field));

    const unknown = try checkModules(testing.allocator, &.{
        .{ .path = "case.lin", .text =
        \\struct Account { id: UInt8 }
        \\impl Account {
        \\    pub fn close(sink account: Account) -> UInt8 {
        \\        let Account { nope: n } = account;
        \\        n
        \\    }
        \\}
        \\fn main() -> UInt8 { Account.close(.{ id = 1 }) }
        },
    });
    try testing.expect(unknown.has(.t_unknown_field));
}

test "a binder carries the type of the field it was given" {
    const got = try checkModules(testing.allocator, &.{
        .{ .path = "case.lin", .text =
        \\struct Account { id: UInt8, flag: Bool }
        \\impl Account {
        \\    pub fn close(sink account: Account) -> Bool {
        \\        let Account { id: _, flag: f } = account;
        \\        f
        \\    }
        \\}
        \\fn main() -> UInt8 { let _b = Account.close(.{ id = 1, flag = true }); 0 }
        },
    });
    try testing.expectEqual(@as(u32, 0), got.errors);
}

test "a Linear part may not be taken out of a Linear whole" {
    // There is no partial move: a partially-moved value is a state the
    // language would then have to describe everywhere else.
    const got = try checkModules(testing.allocator, &.{
        .{ .path = "case.lin", .text =
        \\@linear pub enum Key { Forged(UInt8) }
        \\@linear pub struct Holder { k: Key }
        \\pub fn release(sink k: Key) -> () { match k { Forged(_) => {} } }
        \\pub fn take(sink h: Holder) -> () { release(h.k) }
        \\fn main() -> UInt8 { take(.{ k = Key.Forged(1) }); 0 }
        },
    });
    try testing.expect(got.has(.o_move));
}

test "a variant may carry a structure" {
    // The other shape of aggregate payload. A variant carrying an enum was
    // covered and one carrying a structure was not, so a payload that held an
    // address rather than a value went unnoticed.
    const got = try checkModules(testing.allocator, &.{
        .{ .path = "case.lin", .text =
        \\struct Point { x: UInt8, y: UInt8 }
        \\enum Held { Holds(Point), Empty }
        \\fn sum(p: Point) -> UInt8 { p.x + p.y }
        \\fn main() -> UInt8 {
        \\    let held: Held = .Holds(.{ x = 2, y = 3 });
        \\    match held { Holds(p) => sum(p), Empty => 0 }
        \\}
        },
    });
    try testing.expectEqual(@as(u32, 0), got.errors);
}

test "inferred destructure preserves field coverage and binder types" {
    const accepted = try checkModules(testing.allocator, &.{
        .{ .path = "case.lin", .text =
        \\@linear struct Pair[T] { first: T, second: UInt8 }
        \\fn main() -> UInt8 {
        \\    let pair: Pair[UInt8] = .{ first = 3, second = 4 }
        \\    let { first, second: remaining } = pair
        \\    first + remaining
        \\}
        },
    });
    try testing.expectEqual(@as(u32, 0), accepted.errors);

    const cases = .{
        .{ "let { first } = pair; first", Code.t_missing_field },
        .{ "let { first, first: again, second: _ } = pair; first + again", Code.t_duplicate_field },
        .{ "let { first, second: _, unknown: _ } = pair; first", Code.t_unknown_field },
        .{ "var { first, second: _ } = pair; first", Code.s_destructure },
        .{ "let { first: _, second: _ } = pair; let { first, second: _ } = pair; first", Code.o_move },
    };
    inline for (cases) |case| {
        const got = try checkModules(testing.allocator, &.{
            .{ .path = "case.lin", .text = "struct Pair { first: UInt8, second: UInt8 }\n" ++
                "fn main() -> UInt8 { let pair: Pair = .{ first = 3, second = 4 }; " ++ case[0] ++ " }" },
        });
        try testing.expect(got.has(case[1]));
    }
}

test "inferred destructure requires a known struct and preserves opacity" {
    const scalar = try checkModules(testing.allocator, &.{
        .{ .path = "case.lin", .text = "fn main() -> UInt8 { let scalar: UInt8 = 1; let {} = scalar; 0 }" },
    });
    try testing.expect(scalar.has(.t_unknown_field));
    const unknown = try checkModules(testing.allocator, &.{
        .{ .path = "case.lin", .text = "fn main() -> UInt8 { let { field } = .{ field = 1 }; field }" },
    });
    try testing.expect(unknown.has(.t_infer));
    const sealed = try outsideBank(
        "import bank;\nfn main() -> UInt8 { let { id: _, balance } = bank.open(1); balance }",
    );
    try testing.expect(sealed.has(.m_opaque));
}

test "inferred destructure transfers linear fields without partial moves" {
    const prefix =
        \\@linear struct Key { id: UInt8 }
        \\@linear struct Holder { key: Key }
        \\fn mint() -> Holder { .{ key = .{ id = 7 } } }
        \\
    ;
    const accepted = try checkModules(testing.allocator, &.{
        .{ .path = "case.lin", .text = prefix ++
            "fn main() -> UInt8 { let { key } = mint(); let { id } = key; id }" },
    });
    try testing.expectEqual(@as(u32, 0), accepted.errors);
    const discarded = try checkModules(testing.allocator, &.{
        .{ .path = "case.lin", .text = prefix ++
            "fn main() -> UInt8 { let { key: _ } = mint(); 0 }" },
    });
    try testing.expect(discarded.has(.o_leak));
    const partial = try checkModules(testing.allocator, &.{
        .{ .path = "case.lin", .text = prefix ++
            "fn main() -> UInt8 { let holder = mint(); let { id } = holder.key; id }" },
    });
    try testing.expect(partial.has(.o_move));
}

test "library prefix loads independent primary compilations" {
    var prefix = try LibraryPrefix.init(testing.allocator);
    defer prefix.deinit();
    for (0..2) |_| {
        var arena: std.heap.ArenaAllocator = .init(testing.allocator);
        defer arena.deinit();
        const gpa = arena.allocator();
        var table: FileTable = .empty;
        var sink: Sink = .init(gpa);
        var names: Interner = .empty;
        const program = try prefix.loadFromMemory(gpa, &table, &sink, &names, "main.lin", &.{.{ .path = "main.lin", .text = "fn main() -> UInt8 { 0 }" }}, .program, .borrow);
        try testing.expect(!sink.hasErrors());
        try testing.expect(program.primary.index() > 0);
        try testing.expectEqualStrings("main.lin", table.get(program.primaryFile()).path);
        try testing.expectEqual(prefix.program.ast.declCount(), program.root().decls.start);
        try testing.expectEqual(prefix.interner.count() <= names.count(), true);
        var semantics = try checkProgram(gpa, gpa, &program, &names, &sink, .program);
        defer semantics.deinit(gpa);
        try testing.expect(!sink.hasErrors());
        try testing.expectEqual(program.primary, semantics.expanded.moduleOf(semantics.res.entry));
    }
}

test "library prefix extends imports without changing cached graph" {
    var prefix = try LibraryPrefix.init(testing.allocator);
    defer prefix.deinit();
    const cached_modules = prefix.program.modules.len;
    const cached_declarations = prefix.program.ast.declCount();
    for ([_][]const u8{ "import std.fs\nfn main() -> UInt8 { 0 }", "fn main() -> UInt8 { 0 }", "" }) |text| {
        var arena: std.heap.ArenaAllocator = .init(testing.allocator);
        defer arena.deinit();
        const gpa = arena.allocator();
        var table: FileTable = .empty;
        var sink: Sink = .init(gpa);
        var names: Interner = .empty;
        const files: []const InMemoryFile = if (text.len == 0) &.{} else &.{.{ .path = "app/main.lin", .text = text }};
        const program = try prefix.loadFromMemory(gpa, &table, &sink, &names, "app", files, .program, .borrow);
        try testing.expect(!sink.hasErrors());
        try testing.expect(!program.root().library);
        try testing.expectEqualStrings("app", program.root().dir);
        try testing.expect(program.primary.index() >= cached_modules);
        if (std.mem.startsWith(u8, text, "import")) {
            const target = program.root().importedBy(.at(program.root().decls.start));
            try testing.expect(target != .none);
            try testing.expectEqualStrings("std/fs", program.get(target).dir);
            var count: usize = 0;
            for (program.modules) |module| {
                if (std.mem.eql(u8, module.dir, "std/fs")) count += 1;
            }
            try testing.expectEqual(@as(usize, 1), count);
        } else try testing.expectEqual(cached_modules + 1, program.modules.len);
        try testing.expectEqual(cached_modules, prefix.program.modules.len);
        try testing.expectEqual(cached_declarations, prefix.program.ast.declCount());
    }
}

test "library prefix preserves inferred source output" {
    const dumpInferred = @import("../fmt/annotated.zig").dumpInferred;
    var prefix = try LibraryPrefix.init(testing.allocator);
    defer prefix.deinit();
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    const files = [_]InMemoryFile{.{ .path = "main.lin", .text = "fn main() -> UInt8 { let n: UInt8 = 2; n + 1 }" }};
    var outputs: [2][]const u8 = undefined;
    for (0..2) |i| {
        var table: FileTable = .empty;
        var sink: Sink = .init(gpa);
        var names: Interner = .empty;
        const program = if (i == 0)
            try loadFromMemory(gpa, &table, &sink, &names, "main.lin", &files, .program, true, .borrow)
        else
            try prefix.loadFromMemory(gpa, &table, &sink, &names, "main.lin", &files, .program, .borrow);
        const semantics = try checkProgram(gpa, gpa, &program, &names, &sink, .program);
        try testing.expect(!sink.hasErrors());
        var out: std.Io.Writer.Allocating = .init(gpa);
        try dumpInferred(gpa, &out.writer, &program.ast, &semantics.res, &semantics.typing, program.ownDeclarations());
        outputs[i] = out.written();
    }
    try testing.expectEqualStrings(outputs[0], outputs[1]);
}

test "library prefix load releases partial allocation failures" {
    var prefix = try LibraryPrefix.init(testing.allocator);
    defer prefix.deinit();
    const Attempt = struct {
        fn load(gpa: std.mem.Allocator, cached: *const LibraryPrefix) !void {
            var table: FileTable = .empty;
            defer table.deinit(gpa);
            var names: Interner = .empty;
            defer names.deinit(gpa);
            var sink: Sink = .init(gpa);
            defer sink.list.deinit(gpa);
            var program = try cached.loadFromMemory(gpa, &table, &sink, &names, "main.lin", &.{.{ .path = "main.lin", .text = "fn main() -> UInt8 { 0 }" }}, .program, .borrow);
            defer program.deinit(gpa);
            try testing.expect(!sink.hasErrors());
        }
    };
    try testing.checkAllAllocationFailures(testing.allocator, Attempt.load, .{&prefix});
}

test "checked library session resumes independent application checks" {
    var prefix = try CheckedLibrary.init(testing.allocator);
    defer prefix.deinit();
    const texts = [_][]const u8{
        "fn main() -> UInt8 { 0 }",
        "@copyable\nstruct Limits { bytes: UInt8 }\nlet defaults: Limits = .{ bytes = 7 }\nfn pick(value: Limits = defaults) -> UInt8 { value.bytes }\nfn main() -> UInt8 { pick() }",
    };
    for (texts) |text| {
        var arena = std.heap.ArenaAllocator.init(testing.allocator);
        defer arena.deinit();
        const gpa = arena.allocator();
        var table: FileTable = .empty;
        var sink = Sink.init(gpa);
        var interner: Interner = .empty;
        const program = try prefix.loadFromMemory(gpa, &table, &sink, &interner, "main.lin", &.{.{ .path = "main.lin", .text = text }}, .program, .borrow);
        var semantics = try prefix.checkProgram(gpa, testing.allocator, &program, &interner, &sink, .program);
        defer semantics.deinit(gpa);
        try testing.expect(semantics.reused_library);
        try testing.expectEqual(@as(u32, 0), sink.error_count);
    }
}

test "checked library session matches fresh diagnostics and inferred source" {
    var prefix = try CheckedLibrary.init(testing.allocator);
    defer prefix.deinit();
    const cases = [_]struct { text: []const u8, reused: bool, ambiguous_traversal: bool = false }{
        .{ .text = "fn main() -> UInt8 { missing }", .reused = true },
        .{ .text = "@derive(Equatable)\nstruct Value {}\nfn main() -> UInt8 { let _value: Value = .{}; 0 }", .reused = false },
        .{ .text = "struct Value {}\nderive Equatable for Value\nfn main() -> UInt8 { let _value: Value = .{}; 0 }", .reused = false },
        .{ .text =
        \\import std.mem
        \\fn main() -> UInt8 {
        \\    var values: Vec[UInt8, mem.SystemAllocator] = Vec.new()
        \\    defer values.release()
        \\    Vec.push(&values, 7).unwrap()
        \\    let view = values.as_slice()
        \\    view[0]
        \\}
        , .reused = true },
        .{ .text =
        \\import std.mem
        \\fn main() -> UInt8 {
        \\    var values: Vec[UInt8, mem.SystemAllocator] = Vec.new()
        \\    defer values.release()
        \\    Vec.push(&values, 7).unwrap()
        \\    let view = values.as_slice()
        \\    view[0] = 9
        \\    0
        \\}
        , .reused = true },
        .{ .text =
        \\struct _Board { values: [UInt8; 2] }
        \\impl Index[UInt64] for _Board via values
        \\impl Index[Int64] for _Board via values
        \\impl _Board { trav positions via values }
        \\fn main() -> UInt8 { 0 }
        , .reused = true, .ambiguous_traversal = true },
    };
    for (cases) |case| {
        var arena = std.heap.ArenaAllocator.init(testing.allocator);
        defer arena.deinit();
        const gpa = arena.allocator();
        var table: FileTable = .empty;
        var load_sink = Sink.init(gpa);
        var names: Interner = .empty;
        const program = try prefix.loadFromMemory(gpa, &table, &load_sink, &names, "main.lin", &.{.{ .path = "main.lin", .text = case.text }}, .program, .borrow);
        try testing.expect(!load_sink.hasErrors());
        var fresh_sink = Sink.init(gpa);
        var cached_sink = Sink.init(gpa);
        var fresh = try checkProgram(gpa, testing.allocator, &program, &names, &fresh_sink, .program);
        defer fresh.deinit(gpa);
        var cached = try prefix.checkProgram(gpa, testing.allocator, &program, &names, &cached_sink, .program);
        defer cached.deinit(gpa);
        try testing.expectEqual(case.reused, cached.reused_library);
        if (case.ambiguous_traversal) {
            try testing.expect(fresh_sink.hasErrors());
            var found = false;
            for (fresh_sink.items()) |diagnostic| {
                if (diagnostic.code == .t_lend and std.mem.indexOf(u8, diagnostic.message, "more than one applicable integer indexing key") != null)
                    found = true;
            }
            try testing.expect(found);
        }
        try testing.expectEqual(fresh_sink.error_count, cached_sink.error_count);
        try testing.expectEqual(fresh_sink.list.items.len, cached_sink.list.items.len);
        for (fresh_sink.list.items, cached_sink.list.items) |a, b| {
            try testing.expectEqual(a.code, b.code);
            try testing.expectEqualStrings(a.message, b.message);
        }
        var a: std.Io.Writer.Allocating = .init(gpa);
        var b: std.Io.Writer.Allocating = .init(gpa);
        const dump = @import("../fmt/annotated.zig").dumpInferred;
        try dump(gpa, &a.writer, &program.ast, &fresh.res, &fresh.typing, program.ownDeclarations());
        try dump(gpa, &b.writer, &program.ast, &cached.res, &cached.typing, program.ownDeclarations());
        try testing.expectEqualStrings(a.written(), b.written());
    }
}

test "inferred index keys agree between literals, traversals and cached checks" {
    var prefix = try CheckedLibrary.init(testing.allocator);
    defer prefix.deinit();
    const cases = [_]struct { text: []const u8, ambiguous: bool }{
        .{ .text =
        \\struct Week { values: [UInt8; 2] }
        \\impl Index[Int16] for Week via values
        \\impl Week { trav positions via values }
        \\fn main() -> UInt8 {
        \\    var week = Week { values = [3, 4] }
        \\    week[-(0)] += 1
        \\    for inout value in week { value += 1 }
        \\    week[1] - week[Int16(0)]
        \\}
        , .ambiguous = false },
        .{ .text =
        \\struct Week { values: [UInt8; 2] }
        \\impl Index[Int16] for Week via values
        \\impl Index[UInt8] for Week via values
        \\fn main() -> UInt8 { let week = Week { values = [3, 4] }; week[0] }
        , .ambiguous = true },
    };
    for (cases) |case| {
        var arena = std.heap.ArenaAllocator.init(testing.allocator);
        defer arena.deinit();
        const gpa = arena.allocator();
        var table: FileTable = .empty;
        var load_sink = Sink.init(gpa);
        var names: Interner = .empty;
        const program = try prefix.loadFromMemory(gpa, &table, &load_sink, &names, "main.lin", &.{.{ .path = "main.lin", .text = case.text }}, .program, .borrow);
        try testing.expect(!load_sink.hasErrors());
        var fresh_sink = Sink.init(gpa);
        var cached_sink = Sink.init(gpa);
        var fresh = try checkProgram(gpa, testing.allocator, &program, &names, &fresh_sink, .program);
        defer fresh.deinit(gpa);
        var cached = try prefix.checkProgram(gpa, testing.allocator, &program, &names, &cached_sink, .program);
        defer cached.deinit(gpa);
        for ([_]*const Sink{ &fresh_sink, &cached_sink }) |sink| {
            if (!case.ambiguous) {
                try testing.expect(!sink.hasErrors());
                continue;
            }
            try testing.expectEqual(@as(usize, 1), sink.items().len);
            try testing.expectEqual(.t_infer, sink.items()[0].code);
            try testing.expectEqualStrings("`Week` is indexed by more than one integer type, including `Int16` and `UInt8`", sink.items()[0].message);
        }
    }
}

test "checked library session retains typing after scratch reset" {
    var prefix = try CheckedLibrary.init(testing.allocator);
    defer prefix.deinit();
    var retained = std.heap.ArenaAllocator.init(testing.allocator);
    defer retained.deinit();
    const gpa = retained.allocator();
    var temporary = std.heap.ArenaAllocator.init(testing.allocator);
    defer temporary.deinit();
    var scratch = testing.FailingAllocator.init(temporary.allocator(), .{});
    var table: FileTable = .empty;
    var sink = Sink.init(gpa);
    var interner: Interner = .empty;
    const program = try prefix.loadFromMemory(gpa, &table, &sink, &interner, "main.lin", &.{.{
        .path = "main.lin",
        .text = "@copyable\nstruct Limits { bytes: UInt8 }\nlet defaults: Limits = .{ bytes = 7 }\nfn pick(value: Limits = defaults) -> UInt8 { value.bytes }\nfn main() -> UInt8 { pick() }",
    }}, .program, .borrow);
    var semantics = try prefix.checkProgram(gpa, scratch.allocator(), &program, &interner, &sink, .program);
    defer semantics.deinit(gpa);
    try testing.expect(semantics.reused_library);
    try testing.expect(!sink.hasErrors());
    // Check the lifetime boundary before resetting, so a failing test never
    // dereferences or frees storage after its allocator has released it.
    try testing.expectEqual(scratch.allocated_bytes, scratch.freed_bytes);
    try testing.expect(temporary.reset(.free_all));
    const reused = try temporary.allocator().alloc(u8, 64 * 1024);
    @memset(reused, 0xa5);
    const body = semantics.expanded.ast.declBody(semantics.res.entry);
    try testing.expectEqual(@import("../sema/types.zig").TypeId.u8, semantics.typing.exprType(body));
}

test "checked library reuse and fallback preserve emitted MLIR" {
    var prefix = try CheckedLibrary.init(testing.allocator);
    defer prefix.deinit();
    const Case = struct { text: []const u8, reused: bool, library: bool = false };
    const cases = [_]Case{
        .{ .text = "fn main() -> UInt8 { var total: UInt8 = 0; while total < 3 { total += 1 }; total }", .reused = true },
        .{ .text = "fn main() -> UInt8 { let n = \"42\".parse[UInt8]().unwrap_or(0); n - 42 }", .reused = true },
        .{ .text = "fn main() -> UInt8 { let held: UInt8 = 7; let apply = [held] || held; apply() }", .reused = false },
        .{ .text = "@derive(Equatable)\nstruct Value {}\nfn main() -> UInt8 { let _value: Value = .{}; 0 }", .reused = false },
        .{ .text = "struct Value {}\nderive Equatable for Value\nfn main() -> UInt8 { let _value: Value = .{}; 0 }", .reused = false },
        .{ .text = "export fn square(num: Int32) -> Int32 { num * num }", .reused = true, .library = true },
        .{ .reused = true, .text =
        \\struct Board {
        \\    scores: [UInt8; 4],
        \\}
        \\
        \\impl Index[UInt64] for Board via scores
        \\impl Index[FromEnd] for Board via scores
        \\
        \\fn main() -> UInt8 {
        \\    var board: Board = .{ scores = [1, 2, 3, 4] }
        \\    board[0] += 2
        \\    board[^1] += 1
        \\    return board[0] + board[^1] - 8
        \\}
        },
        .{ .reused = true, .text =
        \\struct Board {
        \\    scores: [UInt8; 4],
        \\}
        \\
        \\impl Index[UInt64] for Board via scores
        \\impl Board {
        \\    trav positions via scores
        \\}
        \\
        \\fn main() -> UInt8 {
        \\    var board: Board = .{ scores = [1, 2, 3, 4] }
        \\    for inout score in board {
        \\        score += 1
        \\    }
        \\    var total: UInt8 = 0
        \\    for read score in board {
        \\        total += score
        \\    }
        \\    return total - 14
        \\}
        },
        .{ .text = "@copyable\nstruct Limits { bytes: [UInt8; 2] }\nlet defaults: Limits = .{ bytes = [3, 7] }\nlet equal: Limits = .{ bytes = [3, 7] }\nlet different: Limits = .{ bytes = [7, 3] }\nfn pick(value: Limits = defaults) -> UInt8 { value.bytes[1] }\nfn main() -> UInt8 { pick() + pick(equal) - pick(different) }", .reused = true },
    };
    for (cases) |case| {
        var arena = std.heap.ArenaAllocator.init(testing.allocator);
        defer arena.deinit();
        const gpa = arena.allocator();
        var output: [2][]const u8 = undefined;
        for (0..2) |i| {
            var table: FileTable = .empty;
            var sink = Sink.init(gpa);
            var names: Interner = .empty;
            const files = &.{
                InMemoryFile{ .path = "main.lin", .text = case.text },
                InMemoryFile{ .path = "linea.json", .text = if (case.library) "{\"kind\":\"library\"}" else "{}" },
            };
            const program = if (i == 0)
                try loadFromMemory(gpa, &table, &sink, &names, "main.lin", files, .program, true, .borrow)
            else
                try prefix.loadFromMemory(gpa, &table, &sink, &names, "main.lin", files, .program, .borrow);
            if (i == 0 or !case.reused) {
                try testing.expectEqual(ModuleId.from(0), program.primary);
                try testing.expectEqual(FileId.from(0), program.primaryFile());
            }
            var semantics = if (i == 0)
                try checkProgram(gpa, testing.allocator, &program, &names, &sink, .program)
            else
                try prefix.checkProgram(gpa, testing.allocator, &program, &names, &sink, .program);
            defer semantics.deinit(gpa);
            try testing.expectEqual(i == 1 and case.reused, semantics.reused_library);
            try testing.expect(!sink.hasErrors());
            var module = (try @import("../mir/lower.zig").lowerProgram(gpa, &semantics.expanded, &semantics.res, &semantics.typing, &semantics.disposals, &sink, .program)) orelse return error.TestUnexpectedResult;
            defer module.deinit(gpa);
            try testing.expect(!sink.hasErrors());
            try table.buildMaps(gpa);
            var writer: std.Io.Writer.Allocating = .init(gpa);
            try testing.expect(try @import("../backend/mlir.zig").emit(gpa, &writer.writer, &module, &table, &sink));
            output[i] = writer.written();
        }
        try testing.expectEqualStrings(output[0], output[1]);
    }
}

test "checked unused library delegation resumes generic indexing and traversal" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    var prefix: CheckedLibrary = undefined;
    prefix.backing = gpa;
    prefix.arena = std.heap.ArenaAllocator.init(gpa);
    defer prefix.arena.deinit();
    prefix.sources = .{
        .arena = std.heap.ArenaAllocator.init(gpa),
        .program = undefined,
        .table = .empty,
        .interner = .empty,
    };
    defer prefix.sources.deinit();
    const sources_gpa = prefix.sources.arena.allocator();
    const files = try sources_gpa.alloc(InMemoryFile, library.files.len + 1);
    @memcpy(files[0..library.files.len], &library.files);
    files[library.files.len] = .{ .path = "std/index/delegation.lin", .text =
        \\pub struct DelegatedBoard[T] { scores: [T; 2] }
        \\impl[T] Index[UInt64] for DelegatedBoard[T] via scores
        \\impl[T] DelegatedBoard[T] { trav positions via scores }
    };
    var library_sink = Sink.init(sources_gpa);
    prefix.sources.program = try loadFromMemory(
        sources_gpa,
        &prefix.sources.table,
        &library_sink,
        &prefix.sources.interner,
        library.prelude_dir,
        files,
        .program,
        false,
        .borrow,
    );
    prefix.sources.program.kind = .library;
    for (prefix.sources.program.modules) |module| try testing.expect(module.library);
    prefix.resolved = try @import("../sema/resolve.zig").resolveLibraryPrefix(gpa, &prefix.sources.program, &prefix.sources.interner, &library_sink);
    defer prefix.resolved.deinit();
    prefix.checked = try @import("../sema/typecheck.zig").typecheckLibraryPrefix(gpa, &prefix.resolved.result.expanded, &prefix.resolved.result.resolution, &library_sink);
    defer prefix.checked.deinit();
    prefix.disposals = try checkOwnership(gpa, gpa, &prefix.resolved.result.expanded, &prefix.resolved.result.resolution, &prefix.checked.typing, &library_sink);
    defer prefix.disposals.deinit(gpa);
    try testing.expect(!library_sink.hasErrors());

    const saved_ast = &prefix.resolved.result.expanded.ast;
    var delegated_impl: DeclId = .none;
    var delegated_traversal: DeclId = .none;
    for (0..saved_ast.declCount()) |i| {
        const decl = DeclId.at(@intCast(i));
        if (saved_ast.declDelegation(decl) == .none) continue;
        switch (saved_ast.declTag(decl)) {
            .impl_ => delegated_impl = decl,
            .traversal_ => delegated_traversal = decl,
            else => {},
        }
    }
    try testing.expect(delegated_impl != .none and delegated_traversal != .none);
    const saved_positions = prefix.checked.typing.traversal_positions.get(delegated_traversal).?;
    try testing.expectEqual(@as(u32, 2), saved_positions.array.count);
    var has_unused_expansion = false;
    for (prefix.checked.typing.expansions) |expansion| {
        if (expansion.member == delegated_impl and expansion.delegation != null) has_unused_expansion = true;
    }
    try testing.expect(has_unused_expansion);
    for (prefix.checked.typing.traversals) |traversal| try testing.expect(traversal.decl != delegated_traversal);

    const application = [_]InMemoryFile{.{ .path = "main.lin", .text =
        \\import std.index
        \\fn main() -> UInt8 {
        \\    var board: index.DelegatedBoard[UInt8] = .{ scores = [1, 2] }
        \\    board[UInt64(0)] += 1
        \\    for inout score in board { score += 1 }
        \\    var total: UInt8 = 0
        \\    for read score in board { total += score }
        \\    total - 6
        \\}
    }};
    var output: [2][]const u8 = undefined;
    const DiagnosticAnswer = struct { code: ?Code, message: []const u8 };
    var diagnostics: []DiagnosticAnswer = &.{};
    for (0..2) |mode| {
        var table: FileTable = .empty;
        var names: Interner = .empty;
        var sink = Sink.init(gpa);
        const program = try prefix.loadFromMemory(gpa, &table, &sink, &names, "main.lin", &application, .program, .borrow);
        try testing.expect(prefix.resolved.canResume(&program, &names));
        var semantics = if (mode == 0)
            try checkProgram(gpa, gpa, &program, &names, &sink, .program)
        else
            try prefix.checkProgram(gpa, gpa, &program, &names, &sink, .program);
        defer semantics.deinit(gpa);
        try testing.expectEqual(mode == 1, semantics.reused_library);
        try testing.expect(!sink.hasErrors());
        if (mode == 0) {
            diagnostics = try gpa.alloc(DiagnosticAnswer, sink.items().len);
            for (sink.items(), diagnostics) |item, *answer| answer.* = .{ .code = item.code, .message = item.message };
        } else {
            try testing.expectEqual(diagnostics.len, sink.items().len);
            for (diagnostics, sink.items()) |answer, item| {
                try testing.expectEqual(answer.code, item.code);
                try testing.expectEqualStrings(answer.message, item.message);
            }
        }
        const attached_positions = semantics.typing.traversal_positions.get(delegated_traversal).?;
        try testing.expectEqual(saved_positions.array.key, attached_positions.array.key);
        try testing.expectEqual(saved_positions.array.count, attached_positions.array.count);
        if (mode == 1) try testing.expectEqual(saved_positions.array.iterator, attached_positions.array.iterator);
        var used_traversals: usize = 0;
        for (semantics.typing.traversals) |traversal| {
            if (traversal.decl != delegated_traversal) continue;
            used_traversals += 1;
            try testing.expectEqual(@as(u32, 2), traversal.positions.array.count);
        }
        try testing.expectEqual(@as(usize, 2), used_traversals);
        var module = (try @import("../mir/lower.zig").lowerProgram(gpa, &semantics.expanded, &semantics.res, &semantics.typing, &semantics.disposals, &sink, .program)) orelse return error.TestUnexpectedResult;
        defer module.deinit(gpa);
        try testing.expect(!sink.hasErrors());
        try table.buildMaps(gpa);
        var writer: std.Io.Writer.Allocating = .init(gpa);
        try testing.expect(try @import("../backend/mlir.zig").emit(gpa, &writer.writer, &module, &table, &sink));
        output[mode] = writer.written();
    }
    try testing.expectEqualStrings(output[0], output[1]);
    try testing.expectEqualDeep(saved_positions, prefix.checked.typing.traversal_positions.get(delegated_traversal).?);
}

test "checked construction derives survive library reuse and fallback" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    var prefix: CheckedLibrary = undefined;
    prefix.backing = gpa;
    prefix.arena = std.heap.ArenaAllocator.init(gpa);
    defer prefix.arena.deinit();
    prefix.sources = .{
        .arena = std.heap.ArenaAllocator.init(gpa),
        .program = undefined,
        .table = .empty,
        .interner = .empty,
    };
    defer prefix.sources.deinit();
    const sources_gpa = prefix.sources.arena.allocator();
    const files = try sources_gpa.alloc(InMemoryFile, library.files.len + 1);
    @memcpy(files[0..library.files.len], &library.files);
    files[library.files.len] = .{ .path = "std/index/construction.lin", .text =
        \\pub trait ConstructSeed { fn seed(value: UInt8) -> Self }
        \\impl ConstructSeed for UInt8 { fn seed(value: UInt8) -> Self { value } }
        \\impl ConstructSeed for UInt64 { fn seed(value: UInt8) -> Self { UInt64(value) } }
        \\template impl ConstructSeed where reflect.target: struct, reflect.components: ConstructSeed {
        \\    fn seed(value: UInt8) -> Self {
        \\        reflect.construct(reflect.product, |component| {
        \\            let field: component.Type = ConstructSeed.seed(value)
        \\            field
        \\        }, {})
        \\    }
        \\}
        \\pub struct Constructed[T] { first: T, second: T }
        \\derive[Item: ConstructSeed] ConstructSeed for Constructed[Item]
    };
    var library_sink = Sink.init(sources_gpa);
    prefix.sources.program = try loadFromMemory(
        sources_gpa,
        &prefix.sources.table,
        &library_sink,
        &prefix.sources.interner,
        library.prelude_dir,
        files,
        .program,
        false,
        .borrow,
    );
    prefix.sources.program.kind = .library;
    for (prefix.sources.program.modules) |module| try testing.expect(module.library);
    prefix.resolved = try @import("../sema/resolve.zig").resolveLibraryPrefix(gpa, &prefix.sources.program, &prefix.sources.interner, &library_sink);
    defer prefix.resolved.deinit();
    prefix.checked = try @import("../sema/typecheck.zig").typecheckLibraryPrefix(gpa, &prefix.resolved.result.expanded, &prefix.resolved.result.resolution, &library_sink);
    defer prefix.checked.deinit();
    prefix.disposals = try checkOwnership(gpa, gpa, &prefix.resolved.result.expanded, &prefix.resolved.result.resolution, &prefix.checked.typing, &library_sink);
    defer prefix.disposals.deinit(gpa);
    try testing.expect(!library_sink.hasErrors());

    const cases = [_]struct { text: []const u8, reused: bool }{
        .{ .text =
        \\import std.index
        \\fn main() -> UInt8 {
        \\    let pair: index.Constructed[UInt8] = index.ConstructSeed.seed(3)
        \\    pair.first + pair.second - 6
        \\}
        , .reused = true },
        .{ .text = try std.mem.concat(gpa, u8, &.{
            files[library.files.len].text,
            \\
            \\struct Local { first: UInt64, second: UInt8 }
            \\derive ConstructSeed for Local
            \\fn main() -> UInt8 {
            \\    let pair: Constructed[UInt64] = ConstructSeed.seed(7)
            \\    let local: Local = ConstructSeed.seed(3)
            \\    if pair.first + pair.second == 14 && local.first == 3 && local.second == 3 { 0 } else { 1 }
            \\}
        }), .reused = false },
    };
    for (cases) |case| {
        var output: [2][]const u8 = undefined;
        const application = [_]InMemoryFile{.{ .path = "main.lin", .text = case.text }};
        for (0..2) |mode| {
            var table: FileTable = .empty;
            var names: Interner = .empty;
            var sink = Sink.init(gpa);
            const program = try prefix.loadFromMemory(gpa, &table, &sink, &names, "main.lin", &application, .program, .borrow);
            var scratch = std.heap.ArenaAllocator.init(gpa);
            defer scratch.deinit();
            var measured = testing.FailingAllocator.init(scratch.allocator(), .{});
            var semantics = if (mode == 0)
                try checkProgram(gpa, measured.allocator(), &program, &names, &sink, .program)
            else
                try prefix.checkProgram(gpa, measured.allocator(), &program, &names, &sink, .program);
            defer semantics.deinit(gpa);
            try testing.expectEqual(mode == 1 and case.reused, semantics.reused_library);
            try testing.expect(!sink.hasErrors());
            try testing.expectEqual(measured.allocated_bytes, measured.freed_bytes);
            try testing.expect(scratch.reset(.free_all));
            const overwrite = try scratch.allocator().alloc(u8, 64 * 1024);
            @memset(overwrite, 0xa5);
            var module = (try @import("../mir/lower.zig").lowerProgram(gpa, &semantics.expanded, &semantics.res, &semantics.typing, &semantics.disposals, &sink, .program)) orelse return error.TestUnexpectedResult;
            defer module.deinit(gpa);
            try testing.expect(!sink.hasErrors());
            try table.buildMaps(gpa);
            var writer: std.Io.Writer.Allocating = .init(gpa);
            try testing.expect(try @import("../backend/mlir.zig").emit(gpa, &writer.writer, &module, &table, &sink));
            output[mode] = writer.written();
        }
        try testing.expectEqualStrings(output[0], output[1]);
    }
}

/// Checks one in-memory program against the library prefix and hands back its
/// semantics, for tests that read what checking settled.
/// The program, its file table and names live in `gpa`, which must be an
/// arena the caller keeps while it reads the result.
fn checkedWithLibrary(prefix: *LibraryPrefix, gpa: std.mem.Allocator, sink: *Sink, text: []const u8) !Semantics {
    const table = try gpa.create(FileTable);
    table.* = .empty;
    const names = try gpa.create(Interner);
    names.* = .empty;
    const program = try gpa.create(Program);
    program.* = try prefix.loadFromMemory(gpa, table, sink, names, "main.lin", &.{.{ .path = "main.lin", .text = text }}, .program, .borrow);
    return checkProgram(gpa, gpa, program, names, sink, .program);
}

test "implementationChoice runs an array's selection through its slice view" {
    var prefix = try LibraryPrefix.init(testing.allocator);
    defer prefix.deinit();
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    var sink: Sink = .init(gpa);
    const semantics = try checkedWithLibrary(&prefix, gpa, &sink, "fn main() -> UInt8 { if [UInt8(1), 2] == [UInt8(1), 2] { 0 } else { 1 } }");
    try testing.expect(!sink.hasErrors());
    const typing = &semantics.typing;
    var viewed: usize = 0;
    var rows = typing.implementation_selections.rows.iterator();
    while (rows.next()) |row| {
        const choice = row.value_ptr.* orelse continue;
        if (typing.get(row.key_ptr.receiver) != .array) continue;
        viewed += 1;
        // The call is typed with the array; the implementation runs for its
        // view, an instance of the library's `Slice`.
        try testing.expectEqual(row.key_ptr.receiver, choice.receiver);
        try testing.expect(choice.view != .poison);
        try testing.expectEqual(choice.view, choice.implementedFor());
        try testing.expectEqual(typing.raw_accesses.slice, typing.instanceOf(choice.view).?.decl);
    }
    try testing.expect(viewed > 0);
}

test "the library's erased closure declarations are found and certified" {
    var prefix = try LibraryPrefix.init(testing.allocator);
    defer prefix.deinit();
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    var sink: Sink = .init(gpa);
    const semantics = try checkedWithLibrary(&prefix, gpa, &sink, "fn main() -> UInt8 { 0 }");
    try testing.expect(!sink.hasErrors());
    const raw = semantics.typing.raw_accesses;
    for ([_]DeclId{ raw.closure, raw.closure_entry_type, raw.closure_open_in, raw.closure_open, raw.closure_entry, raw.closure_settle, raw.closure_size }) |d| {
        try testing.expect(d != DeclId.none);
    }
    // `open_in` and `open` are the ones `Closure` declares, not another type's
    // of those names.
    const ast = &semantics.expanded.ast;
    try testing.expectEqualStrings("Closure", ast.tokenText(ast.declOwner(raw.closure_open_in)));
    try testing.expectEqualStrings("Closure", ast.tokenText(ast.declOwner(raw.closure_open)));
    try testing.expect(raw.erasure(raw.closure_size) and !raw.erasure(raw.closure_open_in) and !raw.erasure(raw.closure_open));
}

test "generatedComponentName and subjectAt spell struct fields, enum payloads and newtype bases" {
    var prefix = try LibraryPrefix.init(testing.allocator);
    defer prefix.deinit();
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    var sink: Sink = .init(gpa);
    const semantics = try checkedWithLibrary(&prefix, gpa, &sink,
        \\@derive(Equatable)
        \\struct Pair { first: UInt8, second: UInt8 }
        \\@derive(Equatable)
        \\enum Slot { Empty, Held(UInt8) }
        \\@derive(Equatable)
        \\type Meters = UInt8
        \\fn main() -> UInt8 {
        \\    let pair: Pair = .{ first = 1, second = 2 }
        \\    let slot: Slot = .Held(3)
        \\    if pair == pair && slot == slot && Meters(4) == Meters(4) { 0 } else { 1 }
        \\}
    );
    try testing.expect(!sink.hasErrors());
    const expanded = &semantics.expanded;
    var names: std.StringHashMapUnmanaged(void) = .empty;
    for (0..expanded.generatedSourceCount()) |index| {
        const part = expanded.ast.parts[expanded.source.ast.parts.len + index];
        for (part.token_start..part.token_end) |at| {
            const token = @import("../lexer/token.zig").TokenId.at(@intCast(at));
            if (!std.mem.startsWith(u8, expanded.ast.tokenText(token), "_linea_derive_")) continue;
            const spelled = try expanded.generatedComponentName(gpa, part.file, expanded.ast.tokenSpan(token)) orelse continue;
            try names.put(gpa, spelled, {});
        }
    }
    for ([_][]const u8{ "Pair.first", "Pair.second", "Slot.Held.0", "Meters.0" }) |expected| {
        try testing.expect(names.contains(expected));
    }
    // A report names a generated binding by its component and a written
    // binding by its name.
    var subjects: std.StringHashMapUnmanaged(void) = .empty;
    for (0..expanded.ast.tokens.len) |at| {
        const token = @import("../lexer/token.zig").TokenId.at(@intCast(at));
        const text = expanded.ast.tokenText(token);
        if (!std.mem.startsWith(u8, text, "_linea_derive_") and !std.mem.eql(u8, text, "slot")) continue;
        try subjects.put(gpa, try expanded.subjectAt(gpa, token), {});
    }
    try testing.expect(subjects.contains("`Pair.first`"));
    try testing.expect(subjects.contains("`slot`"));
    // A span no generated binding covers has no component name.
    try testing.expectEqual(@as(?[]const u8, null), try expanded.generatedComponentName(gpa, expanded.source.ast.parts[0].file, .{ .start = 0, .end = 1 }));
}

test "unmetRequirement explains through the requirement that fails on its own" {
    var prefix = try LibraryPrefix.init(testing.allocator);
    defer prefix.deinit();
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    var sink: Sink = .init(gpa);
    _ = try checkedWithLibrary(&prefix, gpa, &sink,
        \\trait Mark {}
        \\struct Wrap[T] { value: T }
        \\struct Pair[T] { value: T }
        \\struct Plain {}
        \\impl[T: Mark] Mark for Wrap[T] {}
        \\impl[T] Mark for Pair[T] where Wrap[Pair[T]]: Mark, T: Mark {}
        \\fn need[T: Mark](_value: T) -> UInt8 { 0 }
        \\fn main() -> UInt8 { need(Pair[Plain] { value = .{} }) }
    );
    var found = false;
    for (sink.items()) |diagnostic| {
        if (diagnostic.code != .t_bound) continue;
        try testing.expect(diagnostic.notes.len > 0);
        // `Wrap[Pair[Plain]]` fails only because `Pair[Plain]` does, so the
        // note names the requirement on `T` instead.
        try testing.expectEqualStrings("`Pair[T]` implements `Mark` when `T` implements `Mark`, and `Plain` does not", diagnostic.notes[0]);
        found = true;
    }
    try testing.expect(found);
}

// A module nested in another library module, such as `std.io.core` in
// `std.io`, has every public trait passed on by the module enclosing it.
// A diagnostic that asks for a `use` names such a trait through the
// enclosing module, whether or not a program loads that module, so the
// enclosing module must offer it.
test "a nested library module's public traits are passed on by the module enclosing it" {
    for (library.files) |nested| {
        if (!std.mem.endsWith(u8, nested.path, ".lin")) continue;
        const dir = std.fs.path.dirnamePosix(nested.path) orelse continue;
        const outer = std.fs.path.dirnamePosix(dir) orelse continue;
        // A module directly under the library root is not nested.
        if (std.mem.indexOfScalar(u8, outer, '/') == null) continue;
        const inner = std.fs.path.basenamePosix(dir);
        var lines = std.mem.splitScalar(u8, nested.text, '\n');
        while (lines.next()) |line| {
            if (!std.mem.startsWith(u8, line, "pub trait ")) continue;
            const rest = line["pub trait ".len..];
            var end: usize = 0;
            while (end < rest.len and (std.ascii.isAlphanumeric(rest[end]) or rest[end] == '_')) end += 1;
            const name = rest[0..end];
            var wanted: [256]u8 = undefined;
            const written = try std.fmt.bufPrint(&wanted, "pub use {s}.{s}", .{ inner, name });
            var passed_on = false;
            for (library.files) |enclosing| {
                if (!std.mem.eql(u8, std.fs.path.dirnamePosix(enclosing.path) orelse "", outer)) continue;
                var enclosing_lines = std.mem.splitScalar(u8, enclosing.text, '\n');
                while (enclosing_lines.next()) |held| {
                    if (std.mem.eql(u8, std.mem.trim(u8, held, " \r"), written)) passed_on = true;
                }
            }
            if (!passed_on) {
                std.debug.print("{s} declares `{s}`, and nothing in `{s}` writes `{s}`\n", .{ nested.path, name, outer, written });
                return error.NestedTraitNotPassedOn;
            }
        }
    }
}
