const std = @import("std");
const testing = std.testing;

const loader = @import("../driver/loader.zig");
const source_mod = @import("../support/source.zig");
const symbol_names = @import("../support/symbol.zig");
const exports = @import("exports.zig");
const RootId = @import("../syntax/program.zig").RootId;
const Reach = @import("../sema/resolve.zig").Reach;

/// One name a program exports, and where it was written.
pub const Entry = struct {
    /// Typed identity of the independently indexed source root supplying it.
    /// A query is a run of one root's entries, and comparing this small identity
    /// is what makes that run contiguous.
    root: RootId,
    /// How far the declaration's module passes this name.
    reach: Reach,
    name: []const u8,
    kind: exports.Kind,
    /// The directory of the module that wrote it, which is the module an
    /// `import` would have to name.
    module: []const u8,
    header: []const u8,
    /// The file it was read from. What a rebuild replaces is one file's
    /// entries, so each carries the file it came from.
    file: []const u8,
};

/// An entry's position in the index's authoritative export ordering.
pub const EntryId = enum(u32) {
    _,

    fn from(i: usize) EntryId {
        return @enumFromInt(@as(u32, @intCast(i)));
    }

    pub fn index(self: EntryId) usize {
        return @intFromEnum(self);
    }
};

/// One module a program holds, named the way an `import` names one.
///
/// What an import binds is the last element of the path it writes, so a
/// module's name is the last element of its directory. The directory is kept
/// beside it because the leaf alone does not say which directory it is, and two
/// modules of one program may share a leaf.
pub const Module = struct {
    /// Which program holds it, as an index into the index's own list of
    /// program roots -- the same numbering an entry carries, so a query for one
    /// program is a run here for the same reason it is a run there.
    program: u32,
    /// The directory the module is. Borrowed from the entries the module was
    /// read off, and valid for exactly as long as they are.
    dir: []const u8,
    /// The last element of that directory, which is the name an import binds.
    /// A slice of `dir`.
    leaf: []const u8,
};

/// An index whose lazy query data has already been built.
///
/// Every operation is allocation-free and reads only immutable index storage,
/// so one prepared query may be shared between concurrent requests. Borrowed
/// from the index and valid until the index is rebuilt or released.
pub const Query = struct {
    index: *const Index,
    modules: []const Module,
    entry_order: []const EntryId,

    pub fn offers(self: Query, program: []const u8, prefix: []const u8) []const Entry {
        return self.index.offers(program, prefix);
    }

    pub fn modulesNamed(self: Query, program: []const u8, leaf: []const u8) []const Module {
        const held = self.modulesIn(program);

        var lo: usize = 0;
        var hi: usize = held.len;
        while (lo < hi) {
            const mid = lo + (hi - lo) / 2;
            if (std.mem.lessThan(u8, held[mid].leaf, leaf)) lo = mid + 1 else hi = mid;
        }

        var end = lo;
        while (end < held.len) : (end += 1) {
            if (!std.mem.eql(u8, held[end].leaf, leaf)) break;
        }
        return held[lo..end];
    }

    /// One module's exported entries, in their original relative order.
    /// The lookup costs O(log exports + returned entries); unrelated modules
    /// contribute no rows to the returned run.
    pub fn entriesIn(self: Query, module: Module) []const EntryId {
        var lo: usize = 0;
        var hi: usize = self.entry_order.len;
        while (lo < hi) {
            const mid = lo + (hi - lo) / 2;
            if (beforeModule({}, moduleOf(self.entry(self.entry_order[mid])), module)) lo = mid + 1 else hi = mid;
        }
        var end = lo;
        while (end < self.entry_order.len) : (end += 1) {
            const e = self.entry(self.entry_order[end]);
            if (e.root.index() != module.program or !std.mem.eql(u8, e.module, module.dir)) break;
        }
        return self.entry_order[lo..end];
    }

    pub fn entry(self: Query, id: EntryId) Entry {
        return self.index.entries.items[id.index()];
    }

    pub fn modulesIn(self: Query, program: []const u8) []const Module {
        const which = self.index.programIndex(program) orelse return &.{};

        var lo: usize = 0;
        var hi: usize = self.modules.len;
        while (lo < hi) {
            const mid = lo + (hi - lo) / 2;
            if (self.modules[mid].program < which) lo = mid + 1 else hi = mid;
        }

        const begin = lo;
        hi = self.modules.len;
        while (lo < hi) {
            const mid = lo + (hi - lo) / 2;
            if (self.modules[mid].program <= which) lo = mid + 1 else hi = mid;
        }
        return self.modules[begin..lo];
    }
};

/// The text an `import` written in a program rooted at `root` has to spell to name the module the
/// directory `dir` is, or null where no import written there can name it.
///
/// **This is the answer to what text names a module from a given source root**, and
/// the only one: it is the inverse of the rule the loader follows to turn an
/// import path into a directory, so a second implementation would resolve to a
/// directory the loader does not.
///
/// [M-Import] decides what is writable. An import names a directory beneath
/// the independently loaded source root, so a directory outside `root` and
/// the root module itself answer null rather than a path that would not
/// resolve. The dots are the separators of what remains, since they separate
/// directories rather than namespaces. A path whose first element is
/// the reserved root names the standard library wherever it appears, so a
/// directory of that name is one an import cannot spell.
///
/// The loader consumes the identifiers a path was lexed into, so every element
/// has to be one: a directory whose name the lexer reads as anything else has
/// no import that names it, and the answer is null rather than a text nothing
/// would parse.
///
/// Costs one canonicalisation of each path, one scan of each element of the
/// remainder, and one pass over it. The caller owns the result.
pub fn importOf(gpa: std.mem.Allocator, root: []const u8, dir: []const u8) !?[]const u8 {
    const from = try loader.canonical(gpa, loader.trimmedEntry(root));
    defer gpa.free(from);
    const to = try loader.canonical(gpa, loader.trimmedEntry(dir));
    defer gpa.free(to);

    // Strictly beneath, and at a separator: a directory whose name merely
    // begins with another's is not inside it.
    if (to.len <= from.len) return null;
    if (!std.mem.startsWith(u8, to, from)) return null;
    if (from.len > 0 and to[from.len] != '/') return null;
    const under = if (from.len > 0) to[from.len + 1 ..] else to;
    if (!try loader.importable(gpa, under)) return null;

    // Every name is an identifier here, so the route `appendRoute` spells is
    // the dotted text an import writes.
    var written: std.ArrayList(u8) = .empty;
    errdefer written.deinit(gpa);
    try symbol_names.appendRoute(gpa, &written, under);
    return try written.toOwnedSlice(gpa);
}

/// Whether the program whose files begin at `entry` reaches the module the
/// directory `dir` is.
///
/// The entry module is the program, and every other module is reached by an
/// import written in it. Every module resolves imports from the same source
/// root, so the root module can name exactly the non-library modules any of its
/// files can name.
///
/// Costs what `importOf` costs.
pub fn reaches(gpa: std.mem.Allocator, entry: []const u8, dir: []const u8) !bool {
    const from = try loader.canonical(gpa, loader.trimmedEntry(entry));
    defer gpa.free(from);
    const to = try loader.canonical(gpa, loader.trimmedEntry(dir));
    defer gpa.free(to);
    if (std.mem.eql(u8, from, to)) return true;

    const path = try importOf(gpa, from, to) orelse return false;
    gpa.free(path);
    return true;
}

/// Every `pub` name the programs under a workspace export.
///
/// A tooling cache and nothing else. Nothing in the compiler reads it: name
/// resolution is the resolver's over the program it was given, and a pass
/// consulting this would decide what a name means from files the program does
/// not include. That is what makes every approximation here safe -- it may be
/// stale between edits and wrong about a file being rewritten, because nothing
/// depends on it for meaning.
pub const Index = struct {
    gpa: std.mem.Allocator,
    /// The workspace this was built over, and the highest a search for a
    /// program's manifest rises. Owned.
    root: []const u8,
    /// Where each program's files are read from, sorted, one per manifest
    /// found. Owned, and fixed once built: a program is a directory holding a
    /// manifest, and finding a new one is a walk.
    programs: []const []const u8,
    /// Sorted by root, then name, then module, then file. The order is what
    /// makes a query for one root and one prefix a single contiguous run.
    entries: std.ArrayList(Entry),
    /// The modules the entries were read from, sorted by program, then leaf,
    /// then directory -- which is what makes a lookup by leaf a lookup rather
    /// than a scan of everything the workspace exports.
    ///
    /// Built on the first ask and dropped whenever the entries move, because it
    /// borrows from them and because a batch of changes on disk is the shape
    /// that would pay for rebuilding it and is the one shape that never asks.
    modules: ?[]Module = null,
    /// The same entries grouped by module, retaining their original order
    /// inside each module. Built with the module list by sorting compact IDs.
    entry_order: []EntryId = &.{},

    /// What the programs under a workspace export.
    ///
    /// Every directory holding a manifest is a program, and the loader says
    /// where each program's files are read from -- so a program written
    /// `{"source": "src"}` keeps its modules under `src/` and they are found
    /// there. Nothing here reads the manifest: a second reader of a file whose
    /// meaning the loader defines would disagree the first time it grew a key.
    ///
    /// A directory under no manifest is not indexed, and neither is one no
    /// import of its program can name. Those are the same rule stated once
    /// rather than two exclusions: what this holds is what somebody can
    /// import, and a `.lin` file under no manifest is a program on its own
    /// whose one file exports nothing anybody imports.
    ///
    /// Costs one walk of the workspace for its manifests, and for each program
    /// one walk of its source root and one lex and parse of every `.lin` file
    /// beneath it, plus one resolution per file of which program holds it --
    /// which is one `stat` per ancestor of that file and one read and one
    /// parse of the manifest it finds. Linear in the workspace's source, paid
    /// once.
    ///
    /// Holds one entry per exported name and, while it runs, the tokens and
    /// tree of one file: what a file is read into is released before the next
    /// file is read, so the peak is the entries plus the largest file rather
    /// than the parsed form of the workspace.
    pub fn build(gpa: std.mem.Allocator, io: std.Io, root: []const u8) !Index {
        var self: Index = .{
            .gpa = gpa,
            .root = try gpa.dupe(u8, root),
            .programs = &.{},
            .entries = .empty,
            .modules = null,
        };
        errdefer self.deinit();

        // One arena for what the walk itself needs -- the manifests it found
        // and the paths beneath each of them -- and it lasts the walk.
        var walked = std.heap.ArenaAllocator.init(gpa);
        defer walked.deinit();
        const w = walked.allocator();

        self.programs = try programsUnder(gpa, w, io, root);

        // One arena for what reading a file costs, released before the next
        // one is read. A file's text, its tokens and its syntax tree are the
        // largest thing here and the index keeps none of them, so an arena
        // outliving the file would hold the parsed form of the whole
        // workspace at once -- what the index costs would be what the
        // workspace costs to compile rather than what its exports weigh.
        var each = std.heap.ArenaAllocator.init(gpa);
        defer each.deinit();

        for (self.programs, 0..) |program, i| {
            const paths = loader.pathsOfModule(w, io, loader.dirOfEntry(program)) catch continue;
            for (paths) |path| {
                // Kept rather than returned, so the peak is the largest file
                // read and the next file reuses what it left.
                _ = each.reset(.retain_capacity);
                const s = each.allocator();

                // A file belongs to the nearest ancestor holding a manifest,
                // so a nested program's files are that program's and not this
                // one's. The loader decides, because deciding it here would be
                // a second answer to which program a file belongs to.
                const holder = loader.entryOf(s, io, path, .its_program, root) catch continue;
                if (!std.mem.eql(u8, holder, program)) continue;

                const text = source_mod.readFileAlloc(io, s, path) catch continue;
                try self.gather(s, @intCast(i), path, text, &self.entries);
            }
        }

        std.mem.sort(Entry, self.entries.items, {}, before);
        return self;
    }

    pub fn deinit(self: *Index) void {
        self.forgetModules();
        for (self.entries.items) |e| self.release(e);
        self.entries.deinit(self.gpa);
        for (self.programs) |p| self.gpa.free(p);
        self.gpa.free(self.programs);
        self.gpa.free(self.root);
    }

    /// Prepares every allocation a query may need, then returns an immutable
    /// view over the result.
    pub fn query(self: *Index) !Query {
        if (self.modules == null) try self.prepareModules();
        return .{ .index = self, .modules = self.modules.?, .entry_order = self.entry_order };
    }

    fn release(self: *const Index, e: Entry) void {
        self.gpa.free(e.name);
        self.gpa.free(e.module);
        self.gpa.free(e.header);
        self.gpa.free(e.file);
    }

    /// What one program exports whose name begins with `prefix`.
    ///
    /// `program` is the entry a path resolves to, which is what the loader
    /// answers for the file a request named. Only that program's names: an
    /// `import` resolves relative to the program's independently loaded source
    /// root, so one program cannot reach a module in another, and offering a
    /// name across that line suggests an import that cannot be written.
    ///
    /// Entries are sorted by program and then by name, so one program's
    /// matches for one prefix are a single contiguous run: a binary search and
    /// a slice. Costs the logarithm of the index to find the run and then the
    /// answer's own size, never the workspace's.
    ///
    /// Borrowed from the index, and valid until it is rebuilt.
    pub fn offers(self: *const Index, program: []const u8, prefix: []const u8) []const Entry {
        const which = self.programIndex(program) orelse return &.{};
        const items = self.entries.items;

        var lo: usize = 0;
        var hi: usize = items.len;
        while (lo < hi) {
            const mid = lo + (hi - lo) / 2;
            const e = items[mid];
            const root = e.root.index();
            const short = root < which or
                (root == which and std.mem.lessThan(u8, e.name, prefix));
            if (short) lo = mid + 1 else hi = mid;
        }

        // Every name that begins with the prefix sorts at or after it, and the
        // first name that does not ends the run.
        var end = lo;
        while (end < items.len) : (end += 1) {
            if (items[end].root.index() != which) break;
            if (!std.mem.startsWith(u8, items[end].name, prefix)) break;
        }
        return items[lo..end];
    }

    /// Replaces what one file contributed.
    ///
    /// One file's entries and no others': the text is the caller's, so nothing
    /// is read from disk and no directory is walked. A file the index holds
    /// nothing for adds what it now exports, and a file belonging to no
    /// indexed program leaves the index as it was.
    ///
    /// Costs one lex and parse of that file, one resolution of which program
    /// holds it, and a pass over the index to compare the file's exports.
    /// Changed exports require two further passes to splice the entries out
    /// and merge their replacements. Unchanged exports retain the entries and
    /// their borrowed module list. Nothing else is parsed.
    pub fn reindex(self: *Index, io: std.Io, path: []const u8, text: []const u8) !void {
        var scratch = std.heap.ArenaAllocator.init(self.gpa);
        defer scratch.deinit();
        const s = scratch.allocator();

        // Spelled the way the walk spelled it, because which file a path names
        // is decided by comparing the string.
        const named = try loader.canonical(s, loader.trimmedEntry(path));

        var fresh: std.ArrayList(Entry) = .empty;
        defer fresh.deinit(self.gpa);
        errdefer for (fresh.items) |e| self.release(e);

        if (loader.entryOf(s, io, named, .its_program, self.root) catch |err| switch (err) {
            error.OutOfMemory => return err,
            else => null,
        }) |holder| {
            if (self.programIndex(holder)) |which| {
                try self.gather(s, which, named, text, &fresh);
            }
        }
        std.mem.sort(Entry, fresh.items, {}, before);

        // A body edit can leave every exported fact identical. Compare the
        // file's sorted run including multiplicity before releasing anything
        // the prepared module list borrows.
        var previous: usize = 0;
        var unchanged = true;
        for (self.entries.items) |e| {
            if (!std.mem.eql(u8, e.file, named)) continue;
            defer previous += 1;
            if (previous >= fresh.items.len) {
                unchanged = false;
                continue;
            }
            const replacement = fresh.items[previous];
            if (e.root != replacement.root or e.reach != replacement.reach or
                e.kind != replacement.kind or
                !std.mem.eql(u8, e.name, replacement.name) or
                !std.mem.eql(u8, e.module, replacement.module) or
                !std.mem.eql(u8, e.header, replacement.header) or
                !std.mem.eql(u8, e.file, replacement.file)) unchanged = false;
        }
        if (unchanged and previous == fresh.items.len) {
            for (fresh.items) |e| self.release(e);
            return;
        }

        // Finish every allocation before releasing entries or their borrowed
        // module list, so an allocation failure leaves the query intact.
        var merged: std.ArrayList(Entry) = .empty;
        errdefer merged.deinit(self.gpa);
        try merged.ensureTotalCapacityPrecise(self.gpa, self.entries.items.len - previous + fresh.items.len);
        self.forgetModules();

        // What the file used to say, dropped in one pass over the index, which
        // leaves the rest of it sorted.
        var kept: usize = 0;
        for (self.entries.items) |e| {
            if (std.mem.eql(u8, e.file, named)) {
                self.release(e);
                continue;
            }
            self.entries.items[kept] = e;
            kept += 1;
        }
        self.entries.shrinkRetainingCapacity(kept);

        // Two sorted runs merged into one, so the order a query binary
        // searches over is restored without sorting the index again.
        var a: usize = 0;
        var b: usize = 0;
        while (a < kept or b < fresh.items.len) {
            const take_new = a == kept or
                (b < fresh.items.len and before({}, fresh.items[b], self.entries.items[a]));
            if (take_new) {
                merged.appendAssumeCapacity(fresh.items[b]);
                b += 1;
            } else {
                merged.appendAssumeCapacity(self.entries.items[a]);
                a += 1;
            }
        }

        fresh.clearRetainingCapacity();
        self.entries.deinit(self.gpa);
        self.entries = merged;
    }

    /// One compact ordering supplies both module discovery and the run of
    /// exports each module contributes. Preparation sorts O(exports) IDs,
    /// then allocates exactly one Module row per distinct module.
    fn prepareModules(self: *Index) !void {
        const order = try self.gpa.alloc(EntryId, self.entries.items.len);
        errdefer self.gpa.free(order);
        for (order, 0..) |*id, i| id.* = .from(i);
        std.mem.sort(EntryId, order, @as([]const Entry, self.entries.items), struct {
            fn less(entries: []const Entry, a: EntryId, b: EntryId) bool {
                const left = moduleOf(entries[a.index()]);
                const right = moduleOf(entries[b.index()]);
                if (beforeModule({}, left, right)) return true;
                if (beforeModule({}, right, left)) return false;
                return a.index() < b.index();
            }
        }.less);

        var count: usize = 0;
        var previous: ?Module = null;
        for (order) |id| {
            const module = moduleOf(self.entries.items[id.index()]);
            if (previous) |last| {
                if (last.program == module.program and std.mem.eql(u8, last.dir, module.dir)) continue;
            }
            previous = module;
            count += 1;
        }
        const modules = try self.gpa.alloc(Module, count);
        errdefer self.gpa.free(modules);
        var written: usize = 0;
        for (order) |id| {
            const module = moduleOf(self.entries.items[id.index()]);
            if (written > 0) {
                const last = modules[written - 1];
                if (last.program == module.program and std.mem.eql(u8, last.dir, module.dir)) continue;
            }
            modules[written] = module;
            written += 1;
        }
        self.entry_order = order;
        self.modules = modules;
    }

    /// Drops the module view, which borrows from the entries.
    fn forgetModules(self: *Index) void {
        if (self.modules) |held| self.gpa.free(held);
        self.modules = null;
        self.gpa.free(self.entry_order);
        self.entry_order = &.{};
    }

    /// Where a program's entry sits in the sorted list, if the index holds it.
    ///
    /// Costs the logarithm of how many programs the workspace holds.
    fn programIndex(self: *const Index, program: []const u8) ?u32 {
        var lo: usize = 0;
        var hi: usize = self.programs.len;
        while (lo < hi) {
            const mid = lo + (hi - lo) / 2;
            if (std.mem.lessThan(u8, self.programs[mid], program)) lo = mid + 1 else hi = mid;
        }
        if (lo == self.programs.len) return null;
        if (!std.mem.eql(u8, self.programs[lo], program)) return null;
        return @intCast(lo);
    }

    /// Reads one file's exports into `into`, as entries the index owns.
    fn gather(
        self: *const Index,
        scratch: std.mem.Allocator,
        program: u32,
        path: []const u8,
        text: []const u8,
        into: *std.ArrayList(Entry),
    ) !void {
        // A module is a directory, so the module a name was written in is the
        // directory of the file that wrote it.
        const module = std.fs.path.dirname(path) orelse "";

        // A module no import of this program can name is not indexed. That is
        // the same rule that keeps a file under no manifest out: what an index
        // of exports holds is what somebody can import, and a name under a
        // directory nothing can name is a name nothing can reach.
        if (!try reaches(scratch, self.programs[program], module)) return;

        const found = try exports.exportsOf(scratch, path, text);
        defer exports.free(scratch, found);

        for (found) |e| {
            const name = try self.gpa.dupe(u8, e.name);
            errdefer self.gpa.free(name);
            const in = try self.gpa.dupe(u8, module);
            errdefer self.gpa.free(in);
            const header = try self.gpa.dupe(u8, e.header);
            errdefer self.gpa.free(header);
            const file = try self.gpa.dupe(u8, path);
            errdefer self.gpa.free(file);

            try into.append(self.gpa, .{
                .root = .from(program),
                .reach = e.reach,
                .name = name,
                .kind = e.kind,
                .module = in,
                .header = header,
                .file = file,
            });
        }
    }
};

/// The order a query reads: by root, so one root's names are one run, and then
/// by name, so one prefix's matches are one run inside it. Module and
/// file settle the rest, because two modules of a program may export one name
/// and an answer whose order depended on nothing would not be the same answer
/// twice.
fn before(_: void, a: Entry, b: Entry) bool {
    if (a.root != b.root) return a.root.index() < b.root.index();
    switch (std.mem.order(u8, a.name, b.name)) {
        .lt => return true,
        .gt => return false,
        .eq => {},
    }
    switch (std.mem.order(u8, a.module, b.module)) {
        .lt => return true,
        .gt => return false,
        .eq => {},
    }
    return std.mem.lessThan(u8, a.file, b.file);
}

fn moduleOf(e: Entry) Module {
    return .{ .program = @intCast(e.root.index()), .dir = e.module, .leaf = std.fs.path.basename(e.module) };
}

/// The order a leaf query reads: by program, so one program's modules are one
/// run, and then by the leaf an import would write, so one leaf's modules are
/// one run inside it. The directory settles the rest, because two modules of a
/// program may share a leaf and an answer whose order depended on nothing would
/// not be the same answer twice.
fn beforeModule(_: void, a: Module, b: Module) bool {
    if (a.program != b.program) return a.program < b.program;
    switch (std.mem.order(u8, a.leaf, b.leaf)) {
        .lt => return true,
        .gt => return false,
        .eq => {},
    }
    return std.mem.lessThan(u8, a.dir, b.dir);
}

/// Where each program under the workspace reads its files from, sorted.
///
/// The walk finds manifests; the loader says what each one means. Two
/// manifests can name one source root -- an outer program whose `source` is
/// the directory an inner manifest marks -- and one directory is one program,
/// so the list holds it once.
///
/// Costs one walk of the workspace, and one resolution per manifest found.
fn programsUnder(
    gpa: std.mem.Allocator,
    scratch: std.mem.Allocator,
    io: std.Io,
    root: []const u8,
) ![]const []const u8 {
    var found: std.ArrayList([]const u8) = .empty;
    errdefer {
        for (found.items) |p| gpa.free(p);
        found.deinit(gpa);
    }

    // A workspace nobody has named holds no programs. The alternative spelling
    // of an empty root is the process's working directory, which is wherever
    // the editor happened to start the server -- and the programs under that
    // are somebody else's.
    if (root.len == 0) return found.toOwnedSlice(gpa);

    // `iterate` is what makes the walk legal: a directory opened without it can
    // still be iterated on some hosts and not on others.
    var dir = std.Io.Dir.cwd().openDir(io, root, .{ .iterate = true }) catch
        return found.toOwnedSlice(gpa);
    defer dir.close(io);

    var walker = try dir.walk(scratch);
    defer walker.deinit();

    while (try walker.next(io)) |e| {
        if (e.kind != .file) continue;
        if (!std.mem.eql(u8, e.basename, loader.manifest_name)) continue;

        const holding = if (std.fs.path.dirname(e.path)) |under|
            try std.fs.path.join(scratch, &.{ root, under })
        else
            root;

        // What the manifest marks is the program; where its source begins is
        // the loader's answer and not a second reading of the same file.
        const entry = loader.entryOf(scratch, io, holding, .as_named, root) catch continue;
        try found.append(gpa, try gpa.dupe(u8, entry));
    }

    std.mem.sort([]const u8, found.items, {}, lessByPath);

    var kept: usize = 0;
    for (found.items, 0..) |p, i| {
        if (i > 0 and std.mem.eql(u8, p, found.items[i - 1])) {
            gpa.free(p);
            continue;
        }
        found.items[kept] = p;
        kept += 1;
    }
    found.shrinkRetainingCapacity(kept);

    return found.toOwnedSlice(gpa);
}

fn lessByPath(_: void, a: []const u8, b: []const u8) bool {
    return std.mem.lessThan(u8, a, b);
}

/// A workspace on disk, and the paths a case names it by.
const Scratch = struct {
    dir: testing.TmpDir,
    root: []const u8,

    fn init(files: []const struct { at: []const u8, text: []const u8 }) !Scratch {
        var tmp = testing.tmpDir(.{ .iterate = true });
        errdefer tmp.cleanup();

        for (files) |f| {
            if (std.fs.path.dirname(f.at)) |parent| try tmp.dir.createDirPath(testing.io, parent);
            try tmp.dir.writeFile(testing.io, .{ .sub_path = f.at, .data = f.text });
        }

        return .{
            .dir = tmp,
            .root = try std.fmt.allocPrint(testing.allocator, ".zig-cache/tmp/{s}", .{tmp.sub_path}),
        };
    }

    fn deinit(self: *Scratch) void {
        testing.allocator.free(self.root);
        self.dir.cleanup();
    }

    /// The path a case writes, under the workspace.
    fn at(self: *const Scratch, rest: []const u8) ![]u8 {
        return std.fs.path.join(testing.allocator, &.{ self.root, rest });
    }

    /// The program an opened file belongs to, resolved exactly as the server
    /// resolves one.
    fn programOf(self: *const Scratch, path: []const u8) ![]u8 {
        return loader.entryOf(testing.allocator, testing.io, path, .its_program, self.root);
    }
};

/// The names a query answered with, sorted, for a case to compare against.
fn namesOf(found: []const Entry) ![]const []const u8 {
    const out = try testing.allocator.alloc([]const u8, found.len);
    for (out, found) |*name, e| name.* = e.name;
    return out;
}

test "an import names a module by its path from the source root" {
    const gpa = testing.allocator;

    const one = (try importOf(gpa, "examples/accounts", "examples/accounts/ledger")).?;
    defer gpa.free(one);
    try testing.expectEqualStrings("ledger", one);

    // The dots separate directories, so a module further down is named by the
    // whole of the path that descends to it.
    const two = (try importOf(gpa, "examples/accounts", "examples/accounts/coins/ledger")).?;
    defer gpa.free(two);
    try testing.expectEqualStrings("coins.ledger", two);

    // Spellings of one directory are one directory, since the path an import
    // writes is decided by comparing the strings.
    const same = (try importOf(gpa, "examples/./accounts/", "examples/accounts/ledger")).?;
    defer gpa.free(same);
    try testing.expectEqualStrings("ledger", same);
}

test "a module outside the source root is named by nothing" {
    const gpa = testing.allocator;

    // An import names a directory beneath the source root, so a sibling of the
    // root, an ancestor and the root itself are each unwritable.
    try testing.expectEqual(@as(?[]const u8, null), try importOf(gpa, "examples/accounts", "examples/bank/ledger"));
    try testing.expectEqual(@as(?[]const u8, null), try importOf(gpa, "examples/accounts", "examples"));
    try testing.expectEqual(@as(?[]const u8, null), try importOf(gpa, "examples/accounts", "examples/accounts"));

    // A prefix of a directory's name is not a directory above it.
    try testing.expectEqual(@as(?[]const u8, null), try importOf(gpa, "examples/accounts", "examples/accounts_extra/ledger"));

    // `std` names the standard library wherever it appears, so a directory of
    // that name beside the importing module is one no import can spell.
    try testing.expectEqual(@as(?[]const u8, null), try importOf(gpa, "examples/accounts", "examples/accounts/std"));
    try testing.expectEqual(@as(?[]const u8, null), try importOf(gpa, "examples/accounts", "examples/accounts/std/hash"));
}

test "a directory the lexer does not read as one identifier is named by no import" {
    const gpa = testing.allocator;

    // The loader consumes the identifiers a path was lexed into, so an element
    // the lexer reads as anything else -- two tokens, an operator, a number,
    // nothing at all -- is a directory no import reaches. A text written for it
    // is one the parser refuses, which is worse than no answer.
    for ([_][]const u8{ "my-lib", "v1.2", ".vendor", "my lib", "2fast", "let" }) |element| {
        const dir = try std.fmt.allocPrint(gpa, "examples/accounts/{s}/ledger", .{element});
        defer gpa.free(dir);
        try testing.expectEqual(@as(?[]const u8, null), try importOf(gpa, "examples/accounts", dir));
    }

    // The last element is read the same way as the ones above it.
    try testing.expectEqual(@as(?[]const u8, null), try importOf(gpa, "examples/accounts", "examples/accounts/my-lib"));
}

test "a query for one program offers nothing another program exports" {
    var ws = try Scratch.init(&.{
        .{ .at = "a/linea.json", .text = "{}" },
        .{ .at = "a/main.lin", .text = "internal fn alpha() -> UInt8 { 1 }\n" },
        .{ .at = "b/linea.json", .text = "{}" },
        .{ .at = "b/main.lin", .text = "pub fn beta() -> UInt8 { 2 }\n" },
    });
    defer ws.deinit();

    var index = try Index.build(testing.allocator, testing.io, ws.root);
    defer index.deinit();

    const a = try ws.at("a/main.lin");
    defer testing.allocator.free(a);
    const b = try ws.at("b/main.lin");
    defer testing.allocator.free(b);

    const in_a = try ws.programOf(a);
    defer testing.allocator.free(in_a);
    const in_b = try ws.programOf(b);
    defer testing.allocator.free(in_b);

    // `import` resolves relative to its program's source root, so a module in
    // one program cannot reach one in the other. An offer across that line is
    // an import that cannot be written.
    const from_a = try namesOf(index.offers(in_a, ""));
    defer testing.allocator.free(from_a);
    try testing.expectEqual(@as(usize, 1), from_a.len);
    try testing.expectEqualStrings("alpha", from_a[0]);
    try testing.expectEqual(Reach.root, index.offers(in_a, "")[0].reach);
    try testing.expectEqual(RootId.primary, index.offers(in_a, "")[0].root);

    const from_b = try namesOf(index.offers(in_b, ""));
    defer testing.allocator.free(from_b);
    try testing.expectEqual(@as(usize, 1), from_b.len);
    try testing.expectEqualStrings("beta", from_b[0]);
    try testing.expectEqual(Reach.public, index.offers(in_b, "")[0].reach);
    try testing.expectEqual(RootId.from(1), index.offers(in_b, "")[0].root);
}

test "a program whose manifest names a source root has its modules found a level down" {
    var ws = try Scratch.init(&.{
        .{ .at = "linea.json", .text = "{\"source\": \"src\"}" },
        .{ .at = "src/main.lin", .text = "pub fn opened() -> UInt8 { 1 }\n" },
        .{ .at = "src/ledger/l.lin", .text = "pub fn tally() -> UInt8 { 2 }\n" },
    });
    defer ws.deinit();

    var index = try Index.build(testing.allocator, testing.io, ws.root);
    defer index.deinit();

    const main = try ws.at("src/main.lin");
    defer testing.allocator.free(main);
    const program = try ws.programOf(main);
    defer testing.allocator.free(program);

    // The manifest is read rather than merely found: a walk of the directory
    // holding it would find no `.lin` file at all.
    const found = index.offers(program, "");
    try testing.expectEqual(@as(usize, 2), found.len);

    const ledger = try ws.at("src/ledger");
    defer testing.allocator.free(ledger);
    for (found) |e| {
        if (std.mem.eql(u8, e.name, "tally")) try testing.expectEqualStrings(ledger, e.module);
    }
}

test "a manifest inside a program marks a program of its own" {
    var ws = try Scratch.init(&.{
        .{ .at = "linea.json", .text = "{}" },
        .{ .at = "main.lin", .text = "pub fn outer() -> UInt8 { 1 }\n" },
        .{ .at = "vendor/linea.json", .text = "{}" },
        .{ .at = "vendor/v.lin", .text = "pub fn inner() -> UInt8 { 2 }\n" },
    });
    defer ws.deinit();

    var index = try Index.build(testing.allocator, testing.io, ws.root);
    defer index.deinit();

    const main = try ws.at("main.lin");
    defer testing.allocator.free(main);
    const outer = try ws.programOf(main);
    defer testing.allocator.free(outer);

    const vendored = try ws.at("vendor/v.lin");
    defer testing.allocator.free(vendored);
    const inner = try ws.programOf(vendored);
    defer testing.allocator.free(inner);

    // A file belongs to the nearest ancestor holding a manifest, so `vendor`
    // is not a module of the program above it.
    const from_outer = try namesOf(index.offers(outer, ""));
    defer testing.allocator.free(from_outer);
    try testing.expectEqual(@as(usize, 1), from_outer.len);
    try testing.expectEqualStrings("outer", from_outer[0]);

    const from_inner = try namesOf(index.offers(inner, ""));
    defer testing.allocator.free(from_inner);
    try testing.expectEqual(@as(usize, 1), from_inner.len);
    try testing.expectEqualStrings("inner", from_inner[0]);
}

test "a prefix matching a name two modules export answers both" {
    var ws = try Scratch.init(&.{
        .{ .at = "linea.json", .text = "{}" },
        .{ .at = "main.lin", .text = "pub fn size() -> UInt8 { 1 }\n" },
        .{ .at = "ledger/l.lin", .text = "pub fn size() -> UInt8 { 2 }\npub fn sift() -> UInt8 { 3 }\n" },
        .{ .at = "ledger/other.lin", .text = "pub fn tally() -> UInt8 { 4 }\n" },
    });
    defer ws.deinit();

    var index = try Index.build(testing.allocator, testing.io, ws.root);
    defer index.deinit();

    const main = try ws.at("main.lin");
    defer testing.allocator.free(main);
    const program = try ws.programOf(main);
    defer testing.allocator.free(program);

    const found = index.offers(program, "si");
    try testing.expectEqual(@as(usize, 3), found.len);

    // Sorted by name, so the two spellings of `size` sit together and the run
    // a prefix matches is contiguous.
    try testing.expectEqualStrings("sift", found[0].name);
    try testing.expectEqualStrings("size", found[1].name);
    try testing.expectEqualStrings("size", found[2].name);

    // And the two are told apart by the module that wrote each.
    try testing.expect(!std.mem.eql(u8, found[1].module, found[2].module));

    // A prefix nothing begins with answers nothing.
    try testing.expectEqual(@as(usize, 0), index.offers(program, "zz").len);
}

test "a prepared workspace query is read without mutating its index" {
    var ws = try Scratch.init(&.{
        .{ .at = "linea.json", .text = "{}" },
        .{ .at = "main.lin", .text = "pub fn opened() -> UInt8 { 1 }\n" },
        .{ .at = "ledger/l.lin", .text = "pub fn tally() -> UInt8 { 2 }\n" },
    });
    defer ws.deinit();

    var index = try Index.build(testing.allocator, testing.io, ws.root);
    defer index.deinit();
    try testing.expectEqual(@as(?[]Module, null), index.modules);

    const main = try ws.at("main.lin");
    defer testing.allocator.free(main);
    const program = try ws.programOf(main);
    defer testing.allocator.free(program);

    const query = try index.query();
    try testing.expectEqual(@as(usize, 2), query.offers(program, "").len);
    try testing.expectEqual(@as(usize, 2), query.modulesIn(program).len);
    const ledger = query.modulesNamed(program, "ledger");
    try testing.expectEqual(@as(usize, 1), ledger.len);
    try testing.expectEqualStrings("ledger", ledger[0].leaf);

    const again = try index.query();
    try testing.expect(query.modules.ptr == again.modules.ptr);
    try testing.expect(query.entry_order.ptr == again.entry_order.ptr);
}

test "workspace query preparation remains retryable after allocation failure" {
    var ws = try Scratch.init(&.{
        .{ .at = "linea.json", .text = "{}" },
        .{ .at = "ledger/item.lin", .text = "pub fn alpha() -> UInt8 { 0 }\npub fn zeta() -> UInt8 { 0 }\n" },
    });
    defer ws.deinit();
    const path = try ws.at("ledger/item.lin");
    defer testing.allocator.free(path);
    const program = try ws.programOf(path);
    defer testing.allocator.free(program);
    for (0..2) |offset| {
        var failing = testing.FailingAllocator.init(testing.allocator, .{});
        var index = try Index.build(failing.allocator(), testing.io, ws.root);
        defer index.deinit();
        failing.fail_index = failing.alloc_index + offset;
        try testing.expectError(error.OutOfMemory, index.query());
        try testing.expect(failing.has_induced_failure);
        try testing.expect(index.modules == null);
        try testing.expectEqual(@as(usize, 0), index.entry_order.len);
        failing.fail_index = std.math.maxInt(usize);
        const query = try index.query();
        const modules = query.modulesNamed(program, "ledger");
        try testing.expectEqual(@as(usize, 1), modules.len);
        const entries = query.entriesIn(modules[0]);
        try testing.expectEqual(@as(usize, 2), entries.len);
        try testing.expectEqualStrings("alpha", query.entry(entries[0]).name);
        try testing.expectEqualStrings("zeta", query.entry(entries[1]).name);
    }
}

test "a file re-indexed offers what it now exports and not what it did" {
    var ws = try Scratch.init(&.{
        .{ .at = "linea.json", .text = "{}" },
        .{ .at = "main.lin", .text = "pub fn before() -> UInt8 { 1 }\n" },
        .{ .at = "ledger/l.lin", .text = "pub fn kept() -> UInt8 { 2 }\n" },
    });
    defer ws.deinit();

    var index = try Index.build(testing.allocator, testing.io, ws.root);
    defer index.deinit();

    const main = try ws.at("main.lin");
    defer testing.allocator.free(main);
    const program = try ws.programOf(main);
    defer testing.allocator.free(program);

    const first = try namesOf(index.offers(program, ""));
    defer testing.allocator.free(first);
    try testing.expectEqual(@as(usize, 2), first.len);

    try index.reindex(testing.io, main, "pub fn after() -> UInt8 { 1 }\n");

    const then = try namesOf(index.offers(program, ""));
    defer testing.allocator.free(then);
    try testing.expectEqual(@as(usize, 2), then.len);
    try testing.expectEqualStrings("after", then[0]);
    // What another file contributed is untouched: a rebuild is one file's.
    try testing.expectEqualStrings("kept", then[1]);
}

/// The directories a leaf query answered with, for a case to compare against.
fn dirsOf(found: []const Module) ![]const []const u8 {
    const out = try testing.allocator.alloc([]const u8, found.len);
    for (out, found) |*dir, m| dir.* = m.dir;
    return out;
}

test "a module is found by the last element of its directory" {
    var ws = try Scratch.init(&.{
        .{ .at = "linea.json", .text = "{}" },
        .{ .at = "main.lin", .text = "pub fn opened() -> UInt8 { 1 }\n" },
        .{ .at = "vault/ledger/l.lin", .text = "pub fn size() -> UInt8 { 2 }\n" },
    });
    defer ws.deinit();

    var index = try Index.build(testing.allocator, testing.io, ws.root);
    defer index.deinit();

    const main = try ws.at("main.lin");
    defer testing.allocator.free(main);
    const program = try ws.programOf(main);
    defer testing.allocator.free(program);
    const query = try index.query();

    // What an import binds is the last element of the path it writes, so a
    // module nested two deep is named by its own last element and not by the
    // path that reaches it.
    const found = query.modulesNamed(program, "ledger");
    try testing.expectEqual(@as(usize, 1), found.len);

    const ledger = try ws.at("vault/ledger");
    defer testing.allocator.free(ledger);
    try testing.expectEqualStrings(ledger, found[0].dir);
    try testing.expectEqualStrings("ledger", found[0].leaf);

    // The element in the middle of that path is a module too, and it is named
    // by itself rather than by what it holds.
    try testing.expectEqual(@as(usize, 0), query.modulesNamed(program, "vault/ledger").len);
    try testing.expectEqual(@as(usize, 0), query.modulesNamed(program, "coins").len);
}

test "a leaf two modules of one program share answers both" {
    var ws = try Scratch.init(&.{
        .{ .at = "linea.json", .text = "{}" },
        .{ .at = "main.lin", .text = "pub fn opened() -> UInt8 { 1 }\n" },
        .{ .at = "vault/hash/h.lin", .text = "pub fn digest() -> UInt8 { 2 }\n" },
        .{ .at = "crypto/hash/h.lin", .text = "pub fn digest() -> UInt8 { 3 }\n" },
    });
    defer ws.deinit();

    var index = try Index.build(testing.allocator, testing.io, ws.root);
    defer index.deinit();

    const main = try ws.at("main.lin");
    defer testing.allocator.free(main);
    const program = try ws.programOf(main);
    defer testing.allocator.free(program);
    const query = try index.query();

    // Two paths ending in the same element are two modules, and which of them
    // was meant is not a question about the name.
    const dirs = try dirsOf(query.modulesNamed(program, "hash"));
    defer testing.allocator.free(dirs);
    try testing.expectEqual(@as(usize, 2), dirs.len);

    const crypto = try ws.at("crypto/hash");
    defer testing.allocator.free(crypto);
    const vault = try ws.at("vault/hash");
    defer testing.allocator.free(vault);
    try testing.expectEqualStrings(crypto, dirs[0]);
    try testing.expectEqualStrings(vault, dirs[1]);
}

test "a module of one program is not named for another" {
    var ws = try Scratch.init(&.{
        .{ .at = "a/linea.json", .text = "{}" },
        .{ .at = "a/main.lin", .text = "pub fn alpha() -> UInt8 { 1 }\n" },
        .{ .at = "b/linea.json", .text = "{}" },
        .{ .at = "b/main.lin", .text = "pub fn beta() -> UInt8 { 2 }\n" },
        .{ .at = "b/ledger/l.lin", .text = "pub fn size() -> UInt8 { 3 }\n" },
    });
    defer ws.deinit();

    var index = try Index.build(testing.allocator, testing.io, ws.root);
    defer index.deinit();

    const a = try ws.at("a/main.lin");
    defer testing.allocator.free(a);
    const b = try ws.at("b/main.lin");
    defer testing.allocator.free(b);

    const in_a = try ws.programOf(a);
    defer testing.allocator.free(in_a);
    const in_b = try ws.programOf(b);
    defer testing.allocator.free(in_b);
    const query = try index.query();

    // An import descends from its program's source root, so a module of another
    // program is one no import written here can reach.
    try testing.expectEqual(@as(usize, 0), query.modulesNamed(in_a, "ledger").len);
    try testing.expectEqual(@as(usize, 1), query.modulesNamed(in_b, "ledger").len);
}

test "a module the index has read no name from is not one it can name" {
    var ws = try Scratch.init(&.{
        .{ .at = "linea.json", .text = "{}" },
        .{ .at = "main.lin", .text = "pub fn opened() -> UInt8 { 1 }\n" },
        .{ .at = "ledger/l.lin", .text = "pub fn size() -> UInt8 { 2 }\n" },
    });
    defer ws.deinit();

    var index = try Index.build(testing.allocator, testing.io, ws.root);
    defer index.deinit();

    const main = try ws.at("main.lin");
    defer testing.allocator.free(main);
    const program = try ws.programOf(main);
    defer testing.allocator.free(program);
    var query = try index.query();

    const ledger = try ws.at("ledger/l.lin");
    defer testing.allocator.free(ledger);
    try testing.expectEqual(@as(usize, 1), query.modulesNamed(program, "ledger").len);

    // The index holds a module because it read a name from it, so a module
    // that exports nothing is one whose names there is nothing to offer.
    try index.reindex(testing.io, ledger, "fn kept() -> UInt8 { 2 }\n");
    query = try index.query();
    try testing.expectEqual(@as(usize, 0), query.modulesNamed(program, "ledger").len);

    try index.reindex(testing.io, ledger, "pub fn size() -> UInt8 { 2 }\n");
    query = try index.query();
    try testing.expectEqual(@as(usize, 1), query.modulesNamed(program, "ledger").len);
}

test "a module no import of its program can name is not one the index holds" {
    var ws = try Scratch.init(&.{
        .{ .at = "linea.json", .text = "{}" },
        .{ .at = "main.lin", .text = "pub fn opened() -> UInt8 { 1 }\n" },
        .{ .at = "ledger/l.lin", .text = "pub fn size() -> UInt8 { 2 }\n" },
        .{ .at = "my-lib/coins/c.lin", .text = "pub fn tally() -> UInt8 { 3 }\n" },
        .{ .at = "std/hash/h.lin", .text = "pub fn digest() -> UInt8 { 4 }\n" },
    });
    defer ws.deinit();

    var index = try Index.build(testing.allocator, testing.io, ws.root);
    defer index.deinit();

    const main = try ws.at("main.lin");
    defer testing.allocator.free(main);
    const program = try ws.programOf(main);
    defer testing.allocator.free(program);
    const query = try index.query();

    // An element the lexer does not read as an identifier, and one that names
    // the standard library wherever it appears: a name under either is a name
    // no import of this program reaches, so there is nothing to offer under it.
    const found = try namesOf(index.offers(program, ""));
    defer testing.allocator.free(found);
    try testing.expectEqual(@as(usize, 2), found.len);
    try testing.expectEqualStrings("opened", found[0]);
    try testing.expectEqualStrings("size", found[1]);

    try testing.expectEqual(@as(usize, 0), query.modulesNamed(program, "coins").len);
    try testing.expectEqual(@as(usize, 0), query.modulesNamed(program, "hash").len);

    // And a file of one changing on disk adds nothing either, because what a
    // rebuild holds is decided the same way the walk decided it.
    const coins = try ws.at("my-lib/coins/c.lin");
    defer testing.allocator.free(coins);
    try index.reindex(testing.io, coins, "pub fn tally() -> UInt8 { 5 }\npub fn spend() -> UInt8 { 6 }\n");
    try testing.expectEqual(@as(usize, 2), index.offers(program, "").len);
}

test "a workspace nobody named holds no programs" {
    // The client says which directory it opened, and until it has there is no
    // workspace to walk. The process's working directory is wherever the
    // editor happened to start the server, and the programs under it are
    // somebody else's.
    var index = try Index.build(testing.allocator, testing.io, "");
    defer index.deinit();

    try testing.expectEqual(@as(usize, 0), index.programs.len);
    try testing.expectEqual(@as(usize, 0), index.entries.items.len);
}

test "a file under no manifest is a program of its own, and the index offers it nothing" {
    var ws = try Scratch.init(&.{
        .{ .at = "a/linea.json", .text = "{}" },
        .{ .at = "a/main.lin", .text = "pub fn alpha() -> UInt8 { 1 }\n" },
        .{ .at = "loose.lin", .text = "fn main() -> UInt8 { 0 }\n" },
    });
    defer ws.deinit();

    var index = try Index.build(testing.allocator, testing.io, ws.root);
    defer index.deinit();

    const loose = try ws.at("loose.lin");
    defer testing.allocator.free(loose);
    const program = try ws.programOf(loose);
    defer testing.allocator.free(program);

    // A program of one file exports nothing anybody imports, and the program
    // beside it is one no import from here can reach.
    try testing.expectEqual(@as(usize, 0), index.offers(program, "").len);
}

test "body-only reindex retains prepared export and module storage" {
    var ws = try Scratch.init(&.{
        .{ .at = "linea.json", .text = "{}" },
        .{ .at = "main.lin", .text = "pub fn needle() -> UInt8 { 1 }\n" },
        .{ .at = "other/item.lin", .text = "pub fn other() -> UInt8 { 3 }\n" },
    });
    defer ws.deinit();
    var index = try Index.build(testing.allocator, testing.io, ws.root);
    defer index.deinit();
    const main = try ws.at("main.lin");
    defer testing.allocator.free(main);
    const program = try ws.programOf(main);
    defer testing.allocator.free(program);
    const query = try index.query();
    const entries = index.entries.items.ptr;
    const name = query.offers(program, "needle")[0].name.ptr;

    try index.reindex(testing.io, main, "pub fn needle() -> UInt8 { 2 }\n// body detail\n");
    try testing.expect(index.modules != null);
    try testing.expect(index.modules.?.ptr == query.modules.ptr);
    try testing.expect(index.entry_order.ptr == query.entry_order.ptr);
    try testing.expect(index.entries.items.ptr == entries);
    const after = try index.query();
    const found = after.offers(program, "needle");
    try testing.expectEqual(@as(usize, 1), found.len);
    try testing.expectEqualStrings("pub fn needle() -> UInt8", found[0].header);
    try testing.expect(found[0].name.ptr == name);
}

test "reindex observes export headers reach kinds and multiplicity" {
    var ws = try Scratch.init(&.{
        .{ .at = "linea.json", .text = "{}" },
        .{ .at = "main.lin", .text = "pub fn needle() -> UInt8 { 1 }\n" },
    });
    defer ws.deinit();
    var index = try Index.build(testing.allocator, testing.io, ws.root);
    defer index.deinit();
    const main = try ws.at("main.lin");
    defer testing.allocator.free(main);
    const program = try ws.programOf(main);
    defer testing.allocator.free(program);
    const cases = [_]struct { text: []const u8, header: []const u8, kind: exports.Kind, reach: Reach, count: usize = 1 }{
        .{ .text = "pub fn needle(n: UInt8) -> UInt8 { n }\n", .header = "pub fn needle(n: UInt8) -> UInt8", .kind = .function, .reach = .public },
        .{ .text = "internal fn needle(n: UInt8) -> UInt8 { n }\n", .header = "internal fn needle(n: UInt8) -> UInt8", .kind = .function, .reach = .root },
        .{ .text = "pub struct needle { value: UInt8 }\n", .header = "pub struct needle", .kind = .struct_, .reach = .public },
        .{ .text = "pub struct needle { value: UInt8 }\npub struct needle { other: UInt8 }\n", .header = "pub struct needle", .kind = .struct_, .reach = .public, .count = 2 },
        .{ .text = "pub struct needle { value: UInt8 }\n", .header = "pub struct needle", .kind = .struct_, .reach = .public },
    };
    for (cases) |case| {
        _ = try index.query();
        try index.reindex(testing.io, main, case.text);
        try testing.expect(index.modules == null);
        const query = try index.query();
        const found = query.offers(program, "needle");
        try testing.expectEqual(case.count, found.len);
        for (found) |entry| {
            try testing.expectEqualStrings(case.header, entry.header);
            try testing.expectEqual(case.kind, entry.kind);
            try testing.expectEqual(case.reach, entry.reach);
        }
    }
    try index.reindex(testing.io, main, "fn needle() -> UInt8 { 0 }\n");
    const query = try index.query();
    try testing.expectEqual(@as(usize, 0), query.offers(program, "needle").len);
    try testing.expectEqual(@as(usize, 0), query.modulesIn(program).len);
}

test "reindex allocation failure preserves the prepared export query" {
    var ws = try Scratch.init(&.{
        .{ .at = "linea.json", .text = "{}" },
        .{ .at = "main.lin", .text = "pub fn before() -> UInt8 { 1 }\n" },
    });
    defer ws.deinit();
    const main = try ws.at("main.lin");
    defer testing.allocator.free(main);
    const program = try ws.programOf(main);
    defer testing.allocator.free(program);

    var fail_index: usize = 0;
    while (true) : (fail_index += 1) {
        var failing = testing.FailingAllocator.init(testing.allocator, .{});
        var index = try Index.build(failing.allocator(), testing.io, ws.root);
        defer index.deinit();
        const prepared = try index.query();
        const entries = index.entries.items.ptr;
        const name = prepared.offers(program, "before")[0].name.ptr;
        // Setup succeeds; each iteration refuses one allocation in reindex.
        // Refusing resizes also exercises allocation-backed growth paths.
        failing.fail_index = failing.alloc_index + fail_index;
        failing.resize_fail_index = failing.resize_index;
        const outcome = index.reindex(testing.io, main, "pub fn after() -> UInt8 { 2 }\n");
        failing.fail_index = std.math.maxInt(usize);
        failing.resize_fail_index = std.math.maxInt(usize);
        if (failing.has_induced_failure) {
            try testing.expectError(error.OutOfMemory, outcome);
            try testing.expect(index.modules != null);
            try testing.expect(index.modules.?.ptr == prepared.modules.ptr);
            try testing.expect(index.entry_order.ptr == prepared.entry_order.ptr);
            try testing.expect(index.entries.items.ptr == entries);
            const retained = try index.query();
            const found = retained.offers(program, "before");
            try testing.expectEqual(@as(usize, 1), found.len);
            try testing.expectEqualStrings("pub fn before() -> UInt8", found[0].header);
            try testing.expect(found[0].name.ptr == name);
            try testing.expectEqual(@as(usize, 0), retained.offers(program, "after").len);
        } else {
            try outcome;
            const replaced = try index.query();
            try testing.expectEqual(@as(usize, 0), replaced.offers(program, "before").len);
            try testing.expectEqual(@as(usize, 1), replaced.offers(program, "after").len);
            break;
        }
    }
}
