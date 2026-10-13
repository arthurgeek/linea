const std = @import("std");
const tracy = @import("../support/tracy.zig");
const testing = std.testing;

const loader = @import("../driver/loader.zig");
const source_mod = @import("../support/source.zig");
const FileTable = source_mod.FileTable;
const Sink = @import("../diagnostics/sink.zig").Sink;
const Interner = @import("../support/interner.zig").Interner;
const Program = @import("../syntax/program.zig").Program;
const positions = @import("positions.zig");
const publish = @import("publish.zig");
const uses_mod = @import("uses.zig");
const test_library = @import("../driver/test_library.zig");

/// Everything one check of one module produced, held together because a
/// capability needs several of them at once and they must describe the same
/// analysis.
///
/// Semantic storage and retained input bytes have separate arenas with the
/// same lifetime and caller-supplied backing. Source acquisition does not change
/// the growth of compiler tables, and both regions are released when the next
/// check replaces them.
pub const Analysis = struct {
    arena: std.heap.ArenaAllocator,
    /// Owned paths and text for reached input files; the library is static.
    source_arena: std.heap.ArenaAllocator,
    /// Every file the check read, with the source its spans index.
    table: FileTable,
    program: Program,
    semantics: loader.Semantics,
    sink: Sink,
    /// What sits at each byte of the module.
    cursors: positions.Index,
    /// Which expressions reach each binding, and which binding each token
    /// declares.
    uses: uses_mod.Uses,
    /// Which files the compilation loaded as the standard library, by file.
    ///
    /// Read from what the loader recorded on each module, which is the only
    /// thing that decided it: a table worked out from the shape of a path
    /// would be answering where the library happens to live, and would
    /// disagree the moment it moved.
    ///
    /// Held here rather than built by whoever asks, because two capabilities
    /// ask and a per-request table is sized by the compilation rather than by
    /// the request. One byte per file, filled in one pass over the modules.
    library: []const bool,

    pub fn deinit(self: *Analysis) void {
        self.arena.deinit();
        self.source_arena.deinit();
    }

    /// Which file of the checked program a path names, or null where the
    /// program holds no such file.
    ///
    /// One walk, asked by every capability about a document, because "which
    /// file is this" answered two ways is two capabilities disagreeing about
    /// the same path -- and the walk is `publish.files`, so what a capability
    /// speaks about is exactly what the server publishes about. Costs the
    /// program's files, which is what a module holds and never what the
    /// library adds.
    pub fn fileNamed(self: *const Analysis, path: []const u8) ?source_mod.FileId {
        var it = publish.files(&self.program);
        while (it.next()) |file| {
            if (std.mem.eql(u8, self.table.get(file).path, path)) return file;
        }
        return null;
    }
};

/// Loads and checks a module the editor is looking at.
///
/// Reached sources are copied into their own arena, so what the caller
/// supplied may be freed the moment this returns: a diagnostic's span indexes
/// the bytes it was reported against, and an `Analysis` that pointed at a
/// caller's buffer would answer about text the editor has since replaced.
///
/// The library is checked once for a session and each module resumes from it,
/// so an edit costs a check of the module rather than of the library as well.
/// The analysis borrows the library's sources and must end before it does.
pub fn of(
    gpa: std.mem.Allocator,
    /// Backing for retained semantic and source arenas. General scratch uses
    /// `gpa`, so releasing a region follows the caller's backing policy.
    region_backing: std.mem.Allocator,
    library: *const loader.CheckedLibrary,
    files: []const loader.InMemoryFile,
    entry: []const u8,
) !Analysis {
    var arena = std.heap.ArenaAllocator.init(region_backing);
    errdefer arena.deinit();
    const a = arena.allocator();
    var source_arena = std.heap.ArenaAllocator.init(region_backing);
    errdefer source_arena.deinit();

    var table: FileTable = .empty;
    var interner: Interner = .empty;
    var sink = Sink.init(a);

    // The editor is looking at a program, and the library is part of one.
    // Loading through the checked library falls back to an ordinary load
    // where the program cannot resume from it, such as the library itself.
    // Copying what it reached means the library loads the module twice, once
    // borrowed to decide whether it can resume and once copying: copying
    // first would copy files the module never reaches.
    const z_load = tracy.beginZone(@src(), "load");
    const source_program = try a.create(Program);
    source_program.* = try library.loadFromMemory(a, &table, &sink, &interner, entry, files, .program, .{ .copy = source_arena.allocator() });
    const program = source_program.*;
    z_load.end();
    const z_check = tracy.beginZone(@src(), "check");
    const semantics = try library.checkEditorProgram(a, gpa, source_program, &interner, &sink);
    z_check.end();

    // What an editor shows is what `check` reports, and `check` runs
    // monomorphisation for the rules only it can settle. Stopping at the
    // checker showed a clean file for a program that does not compile.
    const z_instantiate = tracy.beginZone(@src(), "instantiate");
    try loader.checkInstantiations(a, &semantics, &sink);
    z_instantiate.end();

    // A capability asked where a cursor is needs this index. Building it per
    // request would sort the module's nodes again for every keystroke. One
    // sweep over the tokens and one sort of the nodes, which is under what
    // the check itself cost.
    const z_cursors = tracy.beginZone(@src(), "cursors");
    const cursors = try positions.Index.build(a, &program.ast);
    z_cursors.end();

    // Built here for the same reason, from the same allocator: a capability
    // asked where else a name is used reads one group of this, and finding
    // that group by walking the module's expressions is every expression read
    // for every name asked about.
    const z_uses = tracy.beginZone(@src(), "uses");
    const uses = try uses_mod.Uses.build(a, &program.ast, &semantics.res, &semantics.typing, &semantics.typing.call_index);
    z_uses.end();

    const library_files = try a.alloc(bool, table.count());
    @memset(library_files, false);
    for (program.modules) |m| {
        for (m.files) |f| library_files[f.index()] = m.library;
    }

    return .{
        .arena = arena,
        .source_arena = source_arena,
        .table = table,
        .program = program,
        .semantics = semantics,
        .sink = sink,
        .cursors = cursors,
        .uses = uses,
        .library = library_files,
    };
}

test "unrelated source payloads do not increase analysis allocation" {
    const sizes = [_]usize{ 0, 64 << 10, 256 << 10, 1 << 20 };
    var allocated: [sizes.len]usize = undefined;
    const text = "fn main() -> UInt8 { 0 }\n";
    for (sizes, 0..) |size, i| {
        const unrelated = try testing.allocator.alloc(u8, size);
        defer testing.allocator.free(unrelated);
        @memset(unrelated, 'x');
        var counting = testing.FailingAllocator.init(testing.allocator, .{});
        var source_bytes: usize = 0;
        {
            var checked = try of(counting.allocator(), counting.allocator(), test_library.get(), &.{
                .{ .path = "app/main.lin", .text = text },
                .{ .path = "app/unrelated/payload.lin", .text = unrelated },
            }, "app");
            defer checked.deinit();
            try testing.expect(!checked.sink.hasErrors());
            for (0..checked.table.count()) |file| {
                if (checked.library[file]) continue;
                const source = checked.table.get(.from(file));
                try testing.expectEqualStrings("app/main.lin", source.path);
                source_bytes += source.text.len;
            }
            try testing.expectEqual(text.len, source_bytes);
            allocated[i] = counting.allocated_bytes;
        }
        try testing.expectEqual(counting.allocated_bytes, counting.freed_bytes);
    }
    for (allocated[1..]) |bytes| try testing.expectEqual(allocated[0], bytes);
}

test "analysis owns reached source and generated module metadata after input buffers are freed" {
    const original = [_]loader.InMemoryFile{
        .{ .path = "app/main.lin", .text = "import dep\nfn main() -> UInt8 { dep.value() }\n" },
        .{ .path = "app/dep/item.lin", .text =
        \\import protocol
        \\@derive(protocol.Mark)
        \\struct Item {}
        \\
        \\pub fn value() -> UInt8 { let _item: Item = .{}; 0 }
        },
        .{ .path = "app/protocol/item.lin", .text = "pub trait Mark {}\ntemplate impl Mark {}\n" },
        .{ .path = "app/unrelated/never.lin", .text = "not a parsed source" },
    };
    var inputs = std.heap.ArenaAllocator.init(testing.allocator);
    defer inputs.deinit();
    const input = inputs.allocator();
    const files = try input.alloc(loader.InMemoryFile, original.len);
    for (files, original) |*file, source| file.* = .{
        .path = try input.dupe(u8, source.path),
        .text = try input.dupe(u8, source.text),
    };
    const entry = try input.dupe(u8, "app");
    var checked = try of(testing.allocator, testing.allocator, test_library.get(), files, entry);
    defer checked.deinit();
    for (files) |file| {
        @memset(@constCast(file.path), 'x');
        @memset(@constCast(file.text), 'x');
    }
    @memset(entry, 'x');
    _ = inputs.reset(.free_all);

    try testing.expect(!checked.sink.hasErrors());
    var reached: usize = 0;
    for (0..checked.table.count()) |i| {
        if (checked.library[i]) continue;
        const source = checked.table.get(.from(i));
        var found = false;
        for (original[0..3]) |expected| {
            if (!std.mem.eql(u8, expected.path, source.path)) continue;
            try testing.expectEqualStrings(expected.text, source.text);
            found = true;
        }
        try testing.expect(found);
        reached += 1;
    }
    try testing.expectEqual(@as(usize, 3), reached);
    try testing.expectEqualStrings("app", checked.program.root().name);
    for (checked.program.modules) |module| {
        try testing.expectEqualStrings(loader.nameOf(module.dir), module.name);
    }
    var derives: usize = 0;
    for (checked.semantics.expanded.generated_sources.buffers) |text| {
        if (std.mem.indexOf(u8, text, " for Item") == null) continue;
        try testing.expect(std.mem.indexOf(u8, text, "import protocol as ") != null);
        derives += 1;
    }
    try testing.expectEqual(@as(usize, 1), derives);
}

test "an empty analysis owns its entry module name" {
    const entry = try testing.allocator.dupe(u8, "empty/root");
    defer testing.allocator.free(entry);
    var checked = try of(testing.allocator, testing.allocator, test_library.get(), &.{}, entry);
    defer checked.deinit();
    @memset(entry, 'x');
    try testing.expectEqualStrings("root", checked.program.root().name);
    try testing.expectEqualStrings("empty/root", checked.program.root().dir);
    try testing.expectEqualStrings("empty/root", checked.table.get(checked.program.primaryFile()).path);
}

test "an analysis reports what the module says, not what the caller still holds" {
    const gpa = testing.allocator;

    var text: std.ArrayList(u8) = .empty;
    defer text.deinit(gpa);
    try text.appendSlice(gpa, "fn main() -> UInt8 {\n    let x: UInt8 = true\n    x\n}\n");

    const path = try gpa.dupe(u8, "main.lin");
    defer gpa.free(path);

    var checked = try of(gpa, gpa, test_library.get(), &.{.{ .path = path, .text = text.items }}, "main.lin");
    defer checked.deinit();

    // The caller's buffer is gone from here on, and the analysis still holds
    // the bytes its spans index.
    text.clearAndFree(gpa);

    try testing.expect(checked.sink.items().len > 0);
    const label = checked.sink.items()[0].primaryLabel().?;
    try testing.expectEqualStrings("true", label.span.slice(checked.table.get(label.file).text));
}

test "an analysis says what a cursor sits on" {
    const gpa = testing.allocator;

    const text = "fn main() -> UInt8 {\n    let x: UInt8 = 1\n    x + 2\n}\n";
    var checked = try of(gpa, gpa, test_library.get(), &.{.{ .path = "main.lin", .text = text }}, "main.lin");
    defer checked.deinit();

    const ast = &checked.program.ast;
    const file = checked.program.primaryFile();
    try testing.expectEqualStrings("main.lin", checked.table.get(file).path);

    const at = std.mem.lastIndexOf(u8, text, "x + 2").?;
    switch (checked.cursors.at(ast, file, @intCast(at)).?) {
        .expr => |e| try testing.expectEqualStrings("x", ast.exprText(e)),
        else => return error.TestUnexpectedResult,
    }
}

test "an attached derive on a type without a name expands nothing" {
    const gpa = testing.allocator;
    for ([_][]const u8{
        "fn main() -> UInt8 { 0 }\n@derive(Debug)\nstruct\n",
        "fn main() -> UInt8 { 0 }\n@derive(Debug)\nenum\n",
        "@derive(Debug)\nstruct 1 { x: UInt8 }\nfn main() -> UInt8 { 0 }\n",
        "@derive(Debug)\nstruct { x: UInt8 }\nfn main() -> UInt8 { 0 }\n",
    }) |text| {
        var checked = try of(gpa, gpa, test_library.get(), &.{.{ .path = "main.lin", .text = text }}, "main.lin");
        defer checked.deinit();
        // The parser's report of the missing name leads, and nothing is
        // reported from generated source.
        try testing.expectEqual(.s_name, checked.sink.items()[0].code);
        for (checked.sink.items()) |item| {
            try testing.expect(item.code == .s_name or item.code == .s_struct or item.code == .s_enum or item.code == .s_entry);
            for (item.labels) |label| try testing.expectEqualStrings("main.lin", checked.table.get(label.file).path);
        }
    }
}

test "a module of several files is checked whole" {
    const gpa = testing.allocator;

    var checked = try of(gpa, gpa, test_library.get(), &.{
        .{ .path = "app/main.lin", .text = "fn main() -> UInt8 { helper() }\n" },
        .{ .path = "app/helper.lin", .text = "fn helper() -> UInt8 { nope }\n" },
    }, "app");
    defer checked.deinit();

    try testing.expectEqual(@as(usize, 1), checked.sink.items().len);
    const label = checked.sink.items()[0].primaryLabel().?;
    try testing.expectEqualStrings("app/helper.lin", checked.table.get(label.file).path);
}

test "generated trait import aliases avoid every module name" {
    const gpa = testing.allocator;

    var checked = try of(gpa, gpa, test_library.get(), &.{
        .{ .path = "app/main.lin", .text =
        \\import helper as _linea_trait_0
        \\import protocol
        \\
        \\fn _linea_trait_1() -> UInt8 { 0 }
        \\
        \\@derive(protocol.Label)
        \\struct Item {}
        \\
        \\@derive(protocol.Label)
        \\struct Other {}
        \\
        \\fn main() -> UInt8 {
        \\    let item: Item = .{}
        \\    let other: Other = .{}
        \\    protocol.Label.label(item) + protocol.Label.label(other) + _linea_trait_0.zero()
        \\}
        },
        .{ .path = "app/helper/helper.lin", .text = "pub fn zero() -> UInt8 { 0 }\n" },
        .{ .path = "app/protocol/protocol.lin", .text =
        \\pub trait Label { fn label(self: Self) -> UInt8 }
        \\pub fn seven() -> UInt8 { 7 }
        \\template impl Label { fn label(_self: Self) -> UInt8 { seven() } }
        },
    }, "app");
    defer checked.deinit();

    try testing.expectEqual(@as(u32, 0), checked.sink.error_count);
    const generated = checked.semantics.expanded.generated_sources.buffers;
    var protocol_files: usize = 0;
    var found_two = false;
    var found_three = false;
    for (generated) |text| {
        if (std.mem.indexOf(u8, text, "import protocol as ") == null) continue;
        protocol_files += 1;
        found_two = found_two or std.mem.indexOf(u8, text, "import protocol as _linea_trait_2") != null;
        found_three = found_three or std.mem.indexOf(u8, text, "import protocol as _linea_trait_3") != null;
    }
    try testing.expectEqual(@as(usize, 2), protocol_files);
    try testing.expect(found_two);
    try testing.expect(found_three);
}

test "generated trait import aliases avoid copied local names" {
    const gpa = testing.allocator;

    var checked = try of(gpa, gpa, test_library.get(), &.{
        .{ .path = "app/main.lin", .text =
        \\import protocol
        \\
        \\@derive(protocol.Label)
        \\struct Item {}
        \\
        \\fn main() -> UInt8 {
        \\    let item: Item = .{}
        \\    protocol.Label.label(item)
        \\}
        },
        .{ .path = "app/protocol/protocol.lin", .text =
        \\pub trait Label { fn label(self: Self) -> UInt8 }
        \\pub fn seven() -> UInt8 { 7 }
        \\template impl Label {
        \\    fn label(_self: Self) -> UInt8 {
        \\        let _linea_trait_0: UInt8 = 0
        \\        _linea_trait_0 + seven()
        \\    }
        \\}
        },
    }, "app");
    defer checked.deinit();

    try testing.expectEqual(@as(u32, 0), checked.sink.error_count);
    const generated = checked.semantics.expanded.generated_sources.buffers;
    var found = false;
    for (generated) |text| {
        found = found or std.mem.indexOf(u8, text, "import protocol as _linea_trait_1") != null;
    }
    try testing.expect(found);
}

test "generated trait import aliases skip one dense source prefix across modules" {
    const gpa = testing.allocator;

    var checked = try of(gpa, gpa, test_library.get(), &.{
        .{ .path = "app/main.lin", .text =
        \\import a
        \\import b
        \\fn _linea_trait_18446744073709551614() -> UInt8 { 0 }
        \\fn _linea_trait_18446744073709551615() -> UInt8 { 0 }
        \\fn main() -> UInt8 { a.value() + b.value() }
        },
        .{ .path = "app/a/a.lin", .text =
        \\import protocol
        \\fn _linea_trait_0() -> UInt8 { 0 }
        \\fn _linea_trait_1() -> UInt8 { 0 }
        \\@derive(protocol.First)
        \\struct A {}
        \\
        \\pub fn value() -> UInt8 { let _a: A = .{}; 0 }
        },
        .{ .path = "app/b/b.lin", .text =
        \\import protocol
        \\fn _linea_trait_2() -> UInt8 { 0 }
        \\fn _linea_trait_3() -> UInt8 { 0 }
        \\@derive(protocol.Second)
        \\struct B {}
        \\
        \\pub fn value() -> UInt8 { let _b: B = .{}; 0 }
        },
        .{ .path = "app/protocol/protocol.lin", .text =
        \\pub trait First {}
        \\template impl First {}
        \\pub trait Second {}
        \\template impl Second {}
        },
    }, "app");
    defer checked.deinit();

    try testing.expectEqual(@as(u32, 0), checked.sink.error_count);
    const generated = checked.semantics.expanded.generated_sources.buffers;
    var protocol_aliases: usize = 0;
    for (generated) |text| {
        if (std.mem.indexOf(u8, text, "import protocol as _linea_trait_4") != null) protocol_aliases += 1;
    }
    try testing.expectEqual(@as(usize, 2), protocol_aliases);
}

test "grouped generated implementations rewrite every qualified bound independently" {
    const gpa = testing.allocator;

    var checked = try of(gpa, gpa, test_library.get(), &.{
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
    }, "app");
    defer checked.deinit();

    try testing.expectEqual(@as(u32, 0), checked.sink.error_count);
    const generated = checked.semantics.expanded.generated_sources.buffers;
    var box_implementations: usize = 0;
    for (generated) |text| {
        if (std.mem.indexOf(u8, text, " for Box[T]") == null) continue;
        box_implementations += 1;
        try testing.expect(std.mem.indexOf(u8, text, "import first as ") != null);
        try testing.expect(std.mem.indexOf(u8, text, "import second as ") != null);
        try testing.expect(std.mem.indexOf(u8, text, "first.Mark") == null);
        try testing.expect(std.mem.indexOf(u8, text, "second.Tag") == null);
        const imports_protocol = std.mem.indexOf(u8, text, "import protocol as ") != null;
        const imports_formatting = std.mem.indexOf(u8, text, "import formatting as ") != null;
        try testing.expect(imports_protocol != imports_formatting);
    }
    try testing.expectEqual(@as(usize, 2), box_implementations);
}

test "source uses exclude contextual callable values in generated bodies" {
    var checked = try of(testing.allocator, testing.allocator, test_library.get(), &.{.{ .path = "main.lin", .text =
        \\@derive(Label)
        \\struct Item {}
        \\trait Label { fn label(self: Self) -> UInt8 }
        \\fn seven(number: UInt8) -> UInt8 { number }
        \\template impl Label {
        \\    fn label(_self: Self) -> UInt8 {
        \\        let held: fn(read number: UInt8) -> UInt8 = seven
        \\        held(number: 7)
        \\    }
        \\}
        \\
        \\fn main() -> UInt8 {
        \\    let item: Item = .{}
        \\    Label.label(item)
        \\}
    }}, "main.lin");
    defer checked.deinit();
    try testing.expect(!checked.sink.hasErrors());
    const source_count = checked.program.ast.exprCount();
    var generated: usize = 0;
    for (checked.semantics.typing.function_values) |value| {
        if (value.at.index() >= source_count) generated += 1;
    }
    try testing.expect(generated > 0);
    var generated_named: usize = 0;
    for (checked.semantics.typing.named) |named| {
        if (named.call.index() >= source_count) generated_named += 1;
    }
    try testing.expect(generated_named > 0);
}

test "analysis retains its region without holding general allocation" {
    var general = testing.FailingAllocator.init(testing.allocator, .{});
    var region = testing.FailingAllocator.init(testing.allocator, .{});
    {
        var checked = try of(general.allocator(), region.allocator(), test_library.get(), &.{.{
            .path = "app/main.lin",
            .text = "fn main() -> UInt8 { 0 }\n",
        }}, "app");
        defer checked.deinit();
        try testing.expect(!checked.sink.hasErrors());
        try testing.expect(general.allocated_bytes > 0);
        try testing.expectEqual(general.allocated_bytes, general.freed_bytes);
        try testing.expect(region.allocated_bytes > region.freed_bytes);
        try testing.expectEqualStrings("app/main.lin", checked.table.get(checked.fileNamed("app/main.lin").?).path);
        try testing.expectEqualStrings("fn main() -> UInt8 { 0 }\n", checked.table.get(checked.fileNamed("app/main.lin").?).text);
        try testing.expect(checked.program.ast.declCount() > 0);
        try testing.expect(checked.semantics.res.entry != .none);
    }
    try testing.expectEqual(general.allocated_bytes, general.freed_bytes);
    try testing.expectEqual(region.allocated_bytes, region.freed_bytes);
}

test "analysis region and general failures release both domains" {
    for ([_]bool{ false, true }) |fail_region| {
        for (0..2) |cut| {
            var general = testing.FailingAllocator.init(testing.allocator, .{
                .fail_index = if (fail_region) std.math.maxInt(usize) else cut,
            });
            var region = testing.FailingAllocator.init(testing.allocator, .{
                .fail_index = if (fail_region) cut else std.math.maxInt(usize),
            });
            try testing.expectError(error.OutOfMemory, of(general.allocator(), region.allocator(), test_library.get(), &.{.{
                .path = "app/main.lin",
                .text = "fn main() -> UInt8 { 0 }\n",
            }}, "app"));
            try testing.expect(if (fail_region) region.has_induced_failure else general.has_induced_failure);
            try testing.expectEqual(general.allocated_bytes, general.freed_bytes);
            try testing.expectEqual(region.allocated_bytes, region.freed_bytes);
        }
    }
}
