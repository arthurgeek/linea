//! The bytes of a `CheckedLibrary`, and a `CheckedLibrary` read back from them.
//!
//! Everything a resumed compilation reads from the library is encoded: the
//! parsed sources, their file table and interner; the expanded program, its
//! resolution, the resolver's continuation rows and the expanded interner; the
//! typing and the checker's continuation rows; and ownership's disposal plan.
//! The encoding is `support/serial.zig`'s, so it is a function of those values
//! alone and two checks of the same library encode to the same bytes.
//!
//! An encoding is read back only by the compiler binary that wrote it: the
//! layout follows the compiler's own types, so the reader trusts the version
//! below only as far as a caller has matched the writer's identity.

const std = @import("std");
const testing = std.testing;
const serial = @import("../support/serial.zig");
const loader = @import("loader.zig");
const CheckedLibrary = loader.CheckedLibrary;
const Interner = @import("../support/interner.zig").Interner;
const Source = @import("../support/source.zig").Source;
const Program = @import("../syntax/program.zig").Program;
const resolve_mod = @import("../sema/resolve.zig");
const typecheck_mod = @import("../sema/typecheck.zig");
const types = @import("../sema/types.zig");
const retained_typing = @import("../sema/retained_typing.zig");
const Expr = @import("../syntax/node.zig").Expr;
const Expressions = std.MultiArrayList(Expr).Slice;

/// Raised whenever what is encoded, or how, changes.
pub const format_version: u32 = 1;

/// The parts of a `CheckedLibrary` that are data, in the order they are
/// written.
const Parts = struct {
    program: Program,
    /// The file table's sources; its line maps are built when a diagnostic
    /// needs them.
    sources: []const Source,
    source_names: Interner,
    result: resolve_mod.ResolveResult,
    resolved_names: Interner,
    resolve_seed: @FieldType(resolve_mod.LibraryPrefix, "seed"),
    typing: @FieldType(typecheck_mod.LibraryPrefix, "typing"),
    check_seed: @FieldType(typecheck_mod.LibraryPrefix, "seed"),
    disposals: @FieldType(CheckedLibrary, "disposals"),
};

/// What the encoding cannot follow alone. An interner's lookup map is rebuilt
/// from its texts. The expanded program's pointer to its source program is the
/// library's own program, which is written once. A typing's fields a resumed
/// check never reads (`retained_typing.unread_fields`) are working state of
/// the check that wrote them and are not written; its layout memos
/// (`retained_typing.layout_memo_fields`) hold unstamped entries whose bytes
/// are whatever an allocation held, so only their lengths are written and
/// they are read back unstamped. Read-only columns are
/// written column by column and read back into a `std.MultiArrayList`. An
/// expression's payload is an untagged union whose variant its tag names, so
/// only that variant is written.
const Hooks = struct {
    /// The library's source program: compared against when encoding, and
    /// pointed at when decoding.
    program: *const Program,

    pub fn custom(comptime T: type) bool {
        return T == Interner or T == *const Program or T == types.Typing or
            T == types.FieldColumns or T == types.VariantColumns or T == Expressions;
    }

    fn RowOf(comptime T: type) type {
        return if (T == types.FieldColumns) types.Field else types.Variant;
    }

    fn unread(comptime name: []const u8) bool {
        return listed(name, &retained_typing.unread_fields);
    }

    fn memo(comptime name: []const u8) bool {
        return listed(name, &retained_typing.layout_memo_fields);
    }

    fn listed(comptime name: []const u8, comptime names: []const []const u8) bool {
        @setEvalBranchQuota(100_000);
        inline for (names) |field| if (comptime std.mem.eql(u8, field, name)) return true;
        return false;
    }

    pub fn encode(self: *Hooks, e: anytype, comptime T: type, v: *const T) std.mem.Allocator.Error!void {
        if (T == Interner) {
            try e.value([]const []const u8, &v.texts.items);
            try e.value(?u32, &v.owned_start);
        } else if (T == *const Program) {
            std.debug.assert(v.* == self.program);
        } else if (T == types.Typing) {
            inline for (std.meta.fields(types.Typing)) |field| {
                if (comptime memo(field.name)) {
                    try e.length(@field(v.*, field.name).len);
                } else if (comptime !unread(field.name)) {
                    comptime serial.assertEncodable(field.type, Hooks);
                    try e.value(field.type, &@field(v.*, field.name));
                }
            }
        } else if (T == types.FieldColumns or T == types.VariantColumns) {
            const Row = RowOf(T);
            try e.length(v.len);
            inline for (comptime std.enums.values(std.MultiArrayList(Row).Field)) |column| {
                const items = v.items(column);
                try e.value(@TypeOf(items), &items);
            }
        } else if (T == Expressions) {
            try e.length(v.len);
            inline for (comptime std.enums.values(std.MultiArrayList(Expr).Field)) |column| {
                if (column != .data) {
                    const items = v.items(column);
                    try e.value(@TypeOf(items), &items);
                }
            }
            for (v.items(.tag), v.items(.data)) |tag, *data| switch (tag.payload()) {
                inline else => |payload| {
                    const Payload = @FieldType(Expr.Data, @tagName(payload));
                    try e.value(Payload, &@field(data.*, @tagName(payload)));
                },
            };
        } else comptime unreachable;
    }

    pub fn decode(self: *Hooks, d: anytype, comptime T: type) serial.DecodeError!T {
        if (T == Interner) {
            const texts = try d.value([]const []const u8);
            var names: Interner = .{ .owned_start = try d.value(?u32) };
            names.texts = .{ .items = @constCast(texts), .capacity = texts.len };
            try names.ids.ensureTotalCapacity(d.arena, std.math.cast(u32, texts.len) orelse return error.Corrupt);
            for (texts, 0..) |text, i| {
                const slot = names.ids.getOrPutAssumeCapacity(text);
                if (slot.found_existing) return error.Corrupt;
                slot.value_ptr.* = .at(@intCast(i));
            }
            return names;
        } else if (T == *const Program) {
            return self.program;
        } else if (T == types.Typing) {
            var typing: types.Typing = undefined;
            inline for (std.meta.fields(types.Typing)) |field| {
                @field(typing, field.name) = if (comptime unread(field.name))
                    field.defaultValue().?
                else if (comptime memo(field.name)) blk: {
                    // Unstamped: every entry is computed again when read.
                    const Element = std.meta.Elem(field.type);
                    const entries = try d.arena.alloc(Element, try d.length());
                    @memset(entries, std.mem.zeroes(Element));
                    break :blk entries;
                } else try d.value(field.type);
            }
            return typing;
        } else if (T == types.FieldColumns or T == types.VariantColumns) {
            const Row = RowOf(T);
            const List = std.MultiArrayList(Row);
            const n = try d.length();
            var list: List = .empty;
            try list.setCapacity(d.arena, n);
            list.len = n;
            const slice = list.slice();
            inline for (comptime std.enums.values(List.Field)) |column| {
                const items = try d.value([]const @FieldType(Row, @tagName(column)));
                if (items.len != n) return error.Corrupt;
                @memcpy(slice.items(column), items);
            }
            return .fromSlice(slice);
        } else if (T == Expressions) {
            const List = std.MultiArrayList(Expr);
            const n = try d.length();
            var list: List = .empty;
            try list.setCapacity(d.arena, n);
            list.len = n;
            const slice = list.slice();
            inline for (comptime std.enums.values(List.Field)) |column| {
                if (column != .data) {
                    const items = try d.value([]const @FieldType(Expr, @tagName(column)));
                    if (items.len != n) return error.Corrupt;
                    @memcpy(slice.items(column), items);
                }
            }
            for (slice.items(.tag), slice.items(.data)) |tag, *data| switch (tag.payload()) {
                inline else => |payload| {
                    const Payload = @FieldType(Expr.Data, @tagName(payload));
                    data.* = @unionInit(Expr.Data, @tagName(payload), try d.value(Payload));
                },
            };
            return slice;
        } else comptime unreachable;
    }
};

/// The library's bytes, allocated in `gpa`.
pub fn encode(gpa: std.mem.Allocator, library: *const CheckedLibrary) std.mem.Allocator.Error![]u8 {
    var scratch = std.heap.ArenaAllocator.init(gpa);
    defer scratch.deinit();
    var hooks: Hooks = .{ .program = &library.sources.program };
    comptime serial.assertEncodable(Parts, Hooks);
    var e: serial.Encoder(Hooks) = .{ .gpa = gpa, .scratch = scratch.allocator(), .hooks = &hooks };
    errdefer e.deinit();
    const parts: Parts = .{
        .program = library.sources.program,
        .sources = library.sources.table.sources.items,
        .source_names = library.sources.interner,
        .result = library.resolved.result,
        .resolved_names = library.resolved.interner,
        .resolve_seed = library.resolved.seed,
        .typing = library.checked.typing,
        .check_seed = library.checked.seed,
        .disposals = library.disposals,
    };
    try e.value(Parts, &parts);
    return e.out.toOwnedSlice(gpa);
}

/// A library read back from `bytes`, which it copies, owned by `backing`.
pub fn decode(backing: std.mem.Allocator, bytes: []const u8) serial.DecodeError!*CheckedLibrary {
    const self = try backing.create(CheckedLibrary);
    errdefer backing.destroy(self);
    self.backing = backing;
    self.arena = std.heap.ArenaAllocator.init(backing);
    errdefer self.arena.deinit();
    const arena = self.arena.allocator();
    var hooks: Hooks = .{ .program = &self.sources.program };
    // Byte slices borrow the input, so the input lives as long as the library.
    var d: serial.Decoder(Hooks) = .{ .input = try arena.dupe(u8, bytes), .arena = arena, .hooks = &hooks };
    // The program is decoded into its place first, so the expanded program
    // that points at it points at the library's own copy.
    self.sources.program = try d.value(Program);
    const parts: Parts = .{
        .program = self.sources.program,
        .sources = try d.value([]const Source),
        .source_names = try d.value(Interner),
        .result = try d.value(resolve_mod.ResolveResult),
        .resolved_names = try d.value(Interner),
        .resolve_seed = try d.value(@FieldType(Parts, "resolve_seed")),
        .typing = try d.value(@FieldType(Parts, "typing")),
        .check_seed = try d.value(@FieldType(Parts, "check_seed")),
        .disposals = try d.value(@FieldType(Parts, "disposals")),
    };
    if (!d.finished()) return error.Corrupt;
    // Every part lives in `self.arena`; the arenas the parts would own when
    // built are empty.
    self.sources.arena = .init(backing);
    self.sources.table = .empty;
    try self.sources.table.sources.appendSlice(arena, parts.sources);
    self.sources.interner = parts.source_names;
    self.resolved = .{ .arena = .init(backing), .result = parts.result, .interner = parts.resolved_names, .seed = parts.resolve_seed };
    self.checked = .{ .arena = .init(backing), .typing = parts.typing, .seed = parts.check_seed };
    self.disposals = parts.disposals;
    return self;
}

test "checked library encoding: two checks of the library encode to the same bytes, and a decoded library encodes to them again" {
    const first = try CheckedLibrary.init(testing.allocator);
    defer first.deinit();
    const second = try CheckedLibrary.init(testing.allocator);
    defer second.deinit();
    const a = try encode(testing.allocator, first);
    defer testing.allocator.free(a);
    const b = try encode(testing.allocator, second);
    defer testing.allocator.free(b);
    try testing.expectEqualSlices(u8, a, b);

    const decoded = try decode(testing.allocator, a);
    defer decoded.deinit();
    const again = try encode(testing.allocator, decoded);
    defer testing.allocator.free(again);
    try testing.expectEqualSlices(u8, a, again);
}

test "checked library encoding: a truncated encoding is corrupt" {
    const library = try CheckedLibrary.init(testing.allocator);
    defer library.deinit();
    const bytes = try encode(testing.allocator, library);
    defer testing.allocator.free(bytes);
    for ([_]usize{ 0, 1, bytes.len / 3, bytes.len / 2, bytes.len - 1 }) |cut| {
        try testing.expectError(error.Corrupt, decode(testing.allocator, bytes[0..cut]));
    }
}

test "checked library encoding: a decoded library checks and emits every program as a freshly checked one does" {
    const fresh = try CheckedLibrary.init(testing.allocator);
    defer fresh.deinit();
    const bytes = try encode(testing.allocator, fresh);
    defer testing.allocator.free(bytes);
    const decoded = try decode(testing.allocator, bytes);
    defer decoded.deinit();
    const Sink = @import("../diagnostics/sink.zig").Sink;
    const FileTable = @import("../support/source.zig").FileTable;
    const Case = struct { text: []const u8, reused: ?bool = null, library: bool = false };
    const cases = [_]Case{
        .{ .text = "fn main() -> UInt8 { var total: UInt8 = 0; while total < 3 { total += 1 }; total }", .reused = true },
        .{ .text = "fn main() -> UInt8 { let n = \"42\".parse[UInt8]().unwrap_or(0); n - 42 }", .reused = true },
        .{ .text = "import std.io\nfn main() -> Result[UInt8, io.IoError] { let name = \"Ada\"\n io.println(\"Hello, {name}!\")?\n .Ok(0) }" },
        .{ .text = "import std.collections\nfn main() -> UInt8 { var v: collections.Vec[UInt8] = .new(); v.push(3); defer v.release(); v.len().to[UInt8]().unwrap_or(0) - 1 }" },
        .{ .text = "fn main() -> UInt8 { let held: UInt8 = 7; let apply = [held] || held; apply() }", .reused = false },
        .{ .text = "@derive(Equatable)\nstruct Value {}\nfn main() -> UInt8 { let _value: Value = .{}; 0 }", .reused = false },
        .{ .text = "export fn square(num: Int32) -> Int32 { num * num }", .reused = true, .library = true },
        .{ .text = "fn main() -> UInt8 { 1 + false }" },
    };
    for (cases) |case| {
        var arena = std.heap.ArenaAllocator.init(testing.allocator);
        defer arena.deinit();
        const gpa = arena.allocator();
        var output: [2][]const u8 = undefined;
        var reused: [2]bool = undefined;
        for ([_]*const CheckedLibrary{ fresh, decoded }, 0..) |library, i| {
            var table: FileTable = .empty;
            var sink = Sink.init(gpa);
            var names: Interner = .empty;
            const files = &.{
                loader.InMemoryFile{ .path = "main.lin", .text = case.text },
                loader.InMemoryFile{ .path = "linea.json", .text = if (case.library) "{\"kind\":\"library\"}" else "{}" },
            };
            const program = try library.loadFromMemory(gpa, &table, &sink, &names, "main.lin", files, .program, .borrow);
            var semantics = try library.checkProgram(gpa, testing.allocator, &program, &names, &sink, .program);
            defer semantics.deinit(gpa);
            reused[i] = semantics.reused_library;
            var writer: std.Io.Writer.Allocating = .init(gpa);
            if (sink.hasErrors()) {
                for (sink.items()) |diagnostic| try writer.writer.print("{s}\n", .{diagnostic.message});
            } else {
                var module = (try @import("../mir/lower.zig").lowerProgram(gpa, &semantics.expanded, &semantics.res, &semantics.typing, &semantics.disposals, &sink, .program)) orelse return error.TestUnexpectedResult;
                defer module.deinit(gpa);
                try testing.expect(!sink.hasErrors());
                try table.buildMaps(gpa);
                try testing.expect(try @import("../backend/mlir.zig").emit(gpa, &writer.writer, &module, &table, &sink));
            }
            output[i] = writer.written();
        }
        if (case.reused) |expected| try testing.expectEqual(expected, reused[0]);
        try testing.expectEqual(reused[0], reused[1]);
        try testing.expect(output[0].len > 0);
        try testing.expectEqualStrings(output[0], output[1]);
    }
}
