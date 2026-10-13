const std = @import("std");
const testing = std.testing;

const FileId = @import("../support/source.zig").FileId;
const Ast = @import("ast.zig").Ast;
const node = @import("node.zig");
const DeclId = node.DeclId;
const DeclRange = node.DeclRange;

/// Which module, within one compilation. Modules are numbered in the order the
/// loader reaches them. The program records its primary module separately.
pub const ModuleId = enum(u32) {
    /// Named a directory that could not be loaded. Already diagnosed.
    none = std.math.maxInt(u32),
    _,

    pub fn from(i: usize) ModuleId {
        return @enumFromInt(i);
    }

    pub fn index(self: ModuleId) usize {
        return @intFromEnum(self);
    }
};

/// Which independently loaded source root owns a module.
///
/// A compilation may contain the primary root, the standard library and, in
/// future, dependency libraries. The loader assigns this identity; no pass
/// infers it from paths or standard-library authority.
pub const RootId = enum(u32) {
    primary = 0,
    none = std.math.maxInt(u32),
    _,

    pub fn from(i: usize) RootId {
        return @enumFromInt(i);
    }

    pub fn index(self: RootId) usize {
        return @intFromEnum(self);
    }
};

/// One resolved `import`, tying the declaration that wrote it to the module it
/// named.
///
/// Kept per module rather than in one table: the same path names different
/// directories from different modules, so the pair is what is meaningful.
pub const Import = struct {
    decl: DeclId,
    module: ModuleId,
};

/// A canonical source spelling and the loaded module it names.
pub const ImportRoute = struct {
    target: ModuleId,
    syntax: []const u8,
};

/// One namespace: every `.lin` file in one directory.
///
/// The files see each other's declarations without importing, and have no
/// order between them -- which is why they are sorted by name before ids are
/// handed out. A directory listing's order is the filesystem's business, and a
/// program's meaning may not depend on it.
pub const Module = struct {
    /// The directory's name, which is the module's. Nothing declares it.
    name: []const u8,
    /// The directory itself, which is what an `import` inside this module
    /// resolves against.
    dir: []const u8,
    files: []const FileId,
    /// This module's declarations within the program's tree.
    decls: DeclRange,
    /// What each `import` declaration in `decls` resolved to, in the order the
    /// declarations are written -- so the decl ids ascend, which is what
    /// `importedBy` searches on.
    imports: []const Import,
    /// The independently loaded source root this module belongs to.
    root: RootId = .primary,
    /// Whether this module is the standard library rather than the program.
    ///
    /// Recorded by whoever loaded it, because that is who decided. A pass that
    /// worked it out from the directory would be answering a question about
    /// where the library lives, which is not a question about a program.
    library: bool = false,
    /// Whether this module may declare `extern` functions, as its root's
    /// manifest grants ([M-Extern]). Recorded by the loader, which read the
    /// manifest.
    externs: bool = false,

    /// Which module an import declaration named, or `.none` where the path
    /// named nothing that could be loaded.
    ///
    /// Searched, not walked. This is asked once per name written through a
    /// module's own name, and a module that imports many is exactly the one
    /// that writes many such names -- so a walk was those two multiplied. The
    /// imports are recorded as the declarations are read, so their ids ascend
    /// and a search over the module's own imports answers in `O(log k)` for
    /// `k` imports of that module.
    pub fn importedBy(self: *const Module, d: DeclId) ModuleId {
        var lo: usize = 0;
        var hi: usize = self.imports.len;
        while (lo < hi) {
            const mid = lo + (hi - lo) / 2;
            if (self.imports[mid].decl.index() < d.index()) lo = mid + 1 else hi = mid;
        }
        if (lo < self.imports.len and self.imports[lo].decl == d) return self.imports[lo].module;
        return .none;
    }
};

/// Every module one compilation reaches, in load order, and the one tree they
/// were parsed into.
///
/// The tree is the program's rather than each module's, so a pass over a
/// compilation stays a walk over a representation and a module is a range
/// within it. What a module boundary means -- which names are visible where --
/// is a rule the resolver applies, not a fact about which arena a node is in.
/// What a root is built as.
///
/// A library is not a program with a piece missing: it is a root that declares
/// no entry point and may not declare one, and what it produces is an object
/// rather than something to run. The manifest is what says which, so this is
/// recorded by whoever loaded it for the reason the prelude is -- the loader is
/// the only thing that read the manifest.
pub const Kind = enum { program, library };

/// Ordered declaration runs chosen by the caller, without allocating ID lists.
pub const DeclarationSelection = union(enum) {
    range: DeclRange,
    modules: []const Module,

    pub fn all(len: u32) DeclarationSelection {
        return .{ .range = .{ .start = 0, .end = len } };
    }

    pub fn iterator(self: DeclarationSelection) Iterator {
        return .{ .selection = self };
    }

    pub fn count(self: DeclarationSelection) u32 {
        switch (self) {
            .range => |r| return r.end - r.start,
            .modules => |modules| {
                var len: u32 = 0;
                for (modules) |m| {
                    if (!m.library) len += m.decls.end - m.decls.start;
                }
                return len;
            },
        }
    }

    pub const Iterator = struct {
        selection: DeclarationSelection,
        module: usize = 0,
        offset: u32 = 0,
        /// Whether omitted modules separate this declaration from the previous one.
        skipped_modules: bool = false,

        pub fn next(self: *Iterator) ?DeclId {
            self.skipped_modules = false;
            switch (self.selection) {
                .range => |r| {
                    if (self.offset == r.end - r.start) return null;
                    defer self.offset += 1;
                    return .at(r.start + self.offset);
                },
                .modules => |modules| {
                    while (self.module < modules.len) {
                        const m = modules[self.module];
                        if (!m.library and self.offset < m.decls.end - m.decls.start) {
                            defer self.offset += 1;
                            return .at(m.decls.start + self.offset);
                        }
                        if (m.library) self.skipped_modules = true;
                        self.module += 1;
                        self.offset = 0;
                    }
                    return null;
                },
            }
        }
    };
};

pub const Program = struct {
    /// Source declarations selected for program dumps, excluding the library.
    pub fn ownDeclarations(self: *const Program) DeclarationSelection {
        return .{ .modules = self.modules };
    }

    modules: []Module,
    primary: ModuleId = .from(0),
    /// Canonical root-relative import spelling for each loaded module.
    ///
    /// The loader owns path semantics. Later passes may reproduce a loaded
    /// import through this table without inspecting module directories.
    import_routes: []const []const u8 = &.{},
    /// The module whose exported names every other module can see without
    /// naming it, or `.none` where the program was built without a library.
    ///
    /// Recorded by whoever loaded it, which is the only thing that knows. It
    /// was worked out again from the shape of a module's directory -- a
    /// library module whose path holds no separator -- which is a fact about
    /// where the library happens to be laid out rather than about which
    /// module the prelude is.
    prelude: ModuleId = .none,
    /// What the root is built as, which its manifest names.
    kind: Kind = .program,
    /// Whether the entry is a module a named file selected rather than the
    /// root's own module. Such a module need declare no `main` to be
    /// checked; running it needs one.
    named_module: bool = false,
    ast: Ast,

    pub fn root(self: *const Program) *const Module {
        return self.get(self.primary);
    }

    pub fn primaryFile(self: *const Program) FileId {
        return self.root().files[0];
    }

    pub fn get(self: *const Program, m: ModuleId) *const Module {
        return &self.modules[m.index()];
    }

    /// The dotted path a module is known by: its import route, which the
    /// loader recorded -- `std.mem` for the library's `mem` wherever the
    /// library's directory sits, `util.hash` for a program's `util/hash`, and
    /// nothing for the root. A program assembled without the loader records no
    /// routes, and its modules are known by their names.
    pub fn modulePath(self: *const Program, m: ModuleId) []const u8 {
        if (m.index() < self.import_routes.len) return self.import_routes[m.index()];
        if (m == self.primary) return "";
        return self.get(m).name;
    }

    test "a module is known by its import route wherever its directory sits" {
        const modules = [_]Module{
            .{ .name = "app", .dir = "/checkout/app", .files = &.{}, .decls = .{ .start = 0, .end = 0 }, .imports = &.{} },
            .{ .name = "mem", .dir = "/elsewhere/my lib/mem", .files = &.{}, .decls = .{ .start = 0, .end = 0 }, .imports = &.{}, .root = .from(1), .library = true },
        };
        const routes = [_][]const u8{ "", "std.mem" };
        const loaded: Program = .{ .modules = @constCast(&modules), .import_routes = @constCast(&routes), .ast = undefined };
        try testing.expectEqualStrings("", loaded.modulePath(.from(0)));
        try testing.expectEqualStrings("std.mem", loaded.modulePath(.from(1)));
        const assembled: Program = .{ .modules = @constCast(&modules), .ast = undefined };
        try testing.expectEqualStrings("", assembled.modulePath(.from(0)));
        try testing.expectEqualStrings("mem", assembled.modulePath(.from(1)));
    }

    /// A canonical route from one loaded module to another.
    ///
    /// Same-module references need no import. A module may import another
    /// module in its own root or a standard-library module; no other root is
    /// implicitly reachable.
    pub fn importRoute(self: *const Program, from: ModuleId, to: ModuleId) ?ImportRoute {
        if (from == .none or to == .none or from == to) return null;
        if (from.index() >= self.modules.len or to.index() >= self.modules.len) return null;
        if (to.index() >= self.import_routes.len) return null;

        const source = self.get(from);
        const target = self.get(to);
        if (source.root != target.root and !target.library) return null;
        const syntax = self.import_routes[to.index()];
        if (syntax.len == 0) return null;
        return .{ .target = to, .syntax = syntax };
    }

    /// Which module a declaration belongs to.
    ///
    /// Searched, not walked. A module is a directory, so the number of them
    /// grows with the source tree -- and this is asked once per symbol
    /// emitted and once per declaration checked, which grow with it too.
    /// Modules numbering in the handful is true of one program rather than of
    /// the question.
    ///
    /// Each module owns a run of the tree and the runs are laid down in the
    /// order the modules were reached, so they ascend and do not overlap.
    pub fn moduleOf(self: *const Program, d: DeclId) ModuleId {
        var lo: usize = 0;
        var hi: usize = self.modules.len;
        while (lo < hi) {
            const mid = lo + (hi - lo) / 2;
            if (self.modules[mid].decls.end <= d.index()) lo = mid + 1 else hi = mid;
        }
        if (lo < self.modules.len and self.modules[lo].decls.contains(d)) return .from(lo);
        return .none;
    }

    /// The library declaration named by a module and a name, or null where the
    /// library holds none.
    ///
    /// How the compiler names a library declaration it must find but no program
    /// wrote a reference to. Visibility is not consulted, because visibility
    /// decides what a *program* may write and this is not a program writing
    /// anything -- which is what lets such a declaration stay private, and so
    /// out of every program's reach, while the compiler still finds it.
    ///
    /// Null where the library holds no such module, which is what a compilation
    /// with no library at all gets: the compiler's own tests compile programs
    /// without one, and everything keyed on this is simply absent there.
    ///
    /// **Bound:** the library's modules, and the declarations of the one that
    /// matches. Both are fixed by the library rather than by the program being
    /// compiled, and every caller asks once per compilation.
    pub fn libraryDeclIn(self: *const Program, module: []const u8, name: []const u8) ?DeclId {
        for (self.modules) |m| {
            if (!m.library) continue;
            if (!std.mem.eql(u8, m.name, module)) continue;
            for (m.decls.start..m.decls.end) |i| {
                const d = DeclId.at(@intCast(i));
                const named = self.ast.declName(d);
                if (named == .none) continue;
                if (std.mem.eql(u8, self.ast.tokenText(named), name)) return d;
            }
        }
        return null;
    }

    pub fn deinit(self: *Program, gpa: std.mem.Allocator) void {
        for (self.modules) |*m| {
            gpa.free(m.dir);
            gpa.free(m.files);
            gpa.free(m.imports);
        }
        for (self.import_routes) |route| gpa.free(route);
        gpa.free(self.import_routes);
        gpa.free(self.modules);
        self.ast.deinit(gpa);
        self.* = undefined;
    }
};

// Makes every test build compile the tests `Program` holds, including a build
// filtered to one of them, which would otherwise never look inside it.
comptime {
    _ = Program;
}

test "a declaration belongs to the module whose range holds it" {
    const modules = [_]Module{
        .{
            .name = "app",
            .dir = "app",
            .files = &.{},
            .decls = .{ .start = 0, .end = 2 },
            .imports = &.{},
        },
        .{
            .name = "a",
            .dir = "app/a",
            .files = &.{},
            .decls = .{ .start = 2, .end = 5 },
            .imports = &.{},
        },
    };
    const p: Program = .{ .modules = @constCast(&modules), .ast = undefined };

    try testing.expectEqual(ModuleId.from(0), p.moduleOf(DeclId.at(1)));
    try testing.expectEqual(ModuleId.from(1), p.moduleOf(DeclId.at(4)));
    // Past the last module's range, which is what a caller holding a stale id
    // would ask, and must not silently answer with the last module.
    try testing.expectEqual(ModuleId.none, p.moduleOf(DeclId.at(5)));
}

test "an import declaration names the module it resolved to" {
    const imports = [_]Import{
        .{ .decl = DeclId.at(0), .module = .from(1) },
        .{ .decl = DeclId.at(1), .module = .none },
        // A module writes declarations of other kinds between its imports, so
        // the ids the search runs over have gaps in them.
        .{ .decl = DeclId.at(4), .module = .from(2) },
    };
    const m: Module = .{
        .name = "app",
        .dir = "app",
        .files = &.{},
        .decls = .{ .start = 0, .end = 6 },
        .imports = &imports,
    };

    try testing.expectEqual(ModuleId.from(1), m.importedBy(DeclId.at(0)));
    // An import that could not be loaded was reported, and every later pass
    // has to keep working rather than reach through it.
    try testing.expectEqual(ModuleId.none, m.importedBy(DeclId.at(1)));
    try testing.expectEqual(ModuleId.from(2), m.importedBy(DeclId.at(4)));
    // Declarations in the gaps, and past the last import, are not imports and
    // name no module -- which a search that stopped at the nearest id would
    // answer wrongly.
    try testing.expectEqual(ModuleId.none, m.importedBy(DeclId.at(2)));
    try testing.expectEqual(ModuleId.none, m.importedBy(DeclId.at(3)));
    try testing.expectEqual(ModuleId.none, m.importedBy(DeclId.at(5)));
}

test "import routes name same-root rings and the standard library canonically" {
    const modules = [_]Module{
        .{ .name = "app", .dir = "app", .files = &.{}, .decls = .{ .start = 0, .end = 0 }, .imports = &.{} },
        .{ .name = "a", .dir = "app/a", .files = &.{}, .decls = .{ .start = 0, .end = 0 }, .imports = &.{} },
        .{ .name = "b", .dir = "app/b", .files = &.{}, .decls = .{ .start = 0, .end = 0 }, .imports = &.{} },
        .{ .name = "fmt", .dir = "std/fmt", .files = &.{}, .decls = .{ .start = 0, .end = 0 }, .imports = &.{}, .root = .from(1), .library = true },
    };
    const routes = [_][]const u8{ "", "a", "b", "std.fmt" };
    const p: Program = .{
        .modules = @constCast(&modules),
        .import_routes = @constCast(&routes),
        .ast = undefined,
    };

    try testing.expectEqualStrings("b", p.importRoute(.from(1), .from(2)).?.syntax);
    try testing.expectEqualStrings("a", p.importRoute(.from(2), .from(1)).?.syntax);
    try testing.expectEqualStrings("std.fmt", p.importRoute(.from(0), .from(3)).?.syntax);
    try testing.expectEqual(ModuleId.from(2), p.importRoute(.from(1), .from(2)).?.target);
    try testing.expect(p.importRoute(.from(1), .from(1)) == null);
}

test "primary module selection is independent of storage order" {
    var modules = [_]Module{
        .{ .name = "std", .dir = "std", .files = &.{.from(0)}, .decls = .{ .start = 0, .end = 2 }, .imports = &.{}, .root = .from(1), .library = true },
        .{ .name = "app", .dir = "app", .files = &.{.from(1)}, .decls = .{ .start = 2, .end = 4 }, .imports = &.{} },
        .{ .name = "dependency", .dir = "dependency", .files = &.{.from(2)}, .decls = .{ .start = 4, .end = 5 }, .imports = &.{}, .root = .from(2), .library = true },
        .{ .name = "child", .dir = "app/child", .files = &.{.from(3)}, .decls = .{ .start = 5, .end = 7 }, .imports = &.{} },
    };
    const program: Program = .{ .modules = &modules, .primary = .from(1), .ast = undefined };
    try testing.expectEqualStrings("app", program.root().name);
    try testing.expectEqual(FileId.from(1), program.primaryFile());
    try testing.expectEqual(@as(u32, 4), program.ownDeclarations().count());
    {
        var selected = program.ownDeclarations().iterator();
        for ([_]u32{ 2, 3, 5, 6 }) |expected| try testing.expectEqual(DeclId.at(expected), selected.next().?);
        try testing.expectEqual(@as(?DeclId, null), selected.next());
    }
    for (&modules) |*m| m.library = true;
    try testing.expectEqual(@as(u32, 0), program.ownDeclarations().count());
    var library_only = program.ownDeclarations().iterator();
    try testing.expectEqual(@as(?DeclId, null), library_only.next());
}
