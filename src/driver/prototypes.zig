//! [T-ExternPrototype]: every `extern` a root declares for a C function is
//! held to the prototype the root's own C declarations give that function.
//!
//! The C declarations are the sources the root's manifest builds under
//! `native` and the headers it names under `headers`. For each of them one C
//! file is written that includes it and declares, for every `extern` of the
//! root, a pointer to the declared function:
//!
//! ```c
//! #include <sqlite3.h>
//! static __typeof__(sqlite3_close_v2) *const linea_probe_0_3 = &sqlite3_close_v2;
//! ```
//!
//! `cc` reads the file and prints each pointer's type tree with every typedef
//! resolved, and the compiler compares that tree, position by position, with
//! what lowering passes there (`foreign.externPrototype`). The comparison is
//! by representation, not by C's type identity: C's `long long` and `long`
//! are both 64-bit signed integers, and a handle's address is any pointer.
//! Symbols in the runtime's namespace are held to the runtime's own table
//! instead ([T-ExternRuntime]), and the standard library declares no other C.

const std = @import("std");
const builtin = @import("builtin");
const testing = std.testing;
const loader = @import("loader.zig");
const toolchain = @import("toolchain.zig");
const runtime_symbols = @import("../support/runtime_symbols.zig");
const foreign = @import("../sema/foreign.zig");
const ForeignScalar = @import("../sema/types.zig").ForeignScalar;
const Sink = @import("../diagnostics/sink.zig").Sink;
const diagnostic = @import("../diagnostics/diagnostic.zig");
const Label = diagnostic.Label;
const node = @import("../syntax/node.zig");
const DeclId = node.DeclId;
const ModuleId = @import("../syntax/program.zig").ModuleId;
const RootFacts = @import("../syntax/program.zig").RootFacts;
const Ast = @import("../syntax/ast.zig").Ast;

pub const Options = struct {
    /// The directory the roots' `native` paths and manifest directories are
    /// named relative to; empty for the working directory.
    base: []const u8 = "",
    /// The directory the C files read by `cc` are written beneath.
    scratch: []const u8,
};

/// The prefix every probe declaration's name begins with, which is what
/// `cc` is asked to describe.
const probe_prefix = "linea_probe_";

/// Holds every `extern` of a program's roots to its C prototype, reporting
/// each that disagrees into `sink`. Reads the declarations the checker
/// settled, so it runs once the semantic passes accepted the program.
pub fn check(gpa: std.mem.Allocator, io: std.Io, semantics: *const loader.Semantics, sink: *Sink, opts: Options) !void {
    const expanded = &semantics.expanded;
    const program = expanded.source;
    if (program.roots.len == 0) return;
    var arena_state = std.heap.ArenaAllocator.init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const by_root = try arena.alloc(std.ArrayList(Extern), program.roots.len);
    for (by_root) |*list| list.* = .empty;
    for (program.modules, 0..) |module, mi| {
        // The standard library's `extern` declarations name the runtime's
        // symbols, or storage primitives lowering replaces.
        if (!module.externs or module.library or module.root == .standard or module.root == .none) continue;
        for (expanded.declsOf(ModuleId.from(mi))) |d| {
            if (!expanded.ast.declIsExtern(d) or expanded.ast.declTypeParams(d).len != 0) continue;
            const name = expanded.ast.tokenText(expanded.ast.declName(d));
            if (std.mem.startsWith(u8, name, runtime_symbols.namespace) or runtime_symbols.signatureOf(name) != null) continue;
            const implied = try foreign.externPrototype(arena, &semantics.typing, d) orelse continue;
            try by_root[module.root.index()].append(arena, .{ .decl = d, .name = name, .implied = implied });
        }
    }
    for (by_root, program.roots) |externs, facts| {
        if (externs.items.len == 0) continue;
        var reporter: Reporter = .{ .arena = arena, .sink = sink, .ast = &expanded.ast };
        try checkRoot(arena, io, facts, externs.items, &reporter, opts);
    }
}

const Extern = struct {
    decl: DeclId,
    name: []const u8,
    implied: foreign.Prototype,
};

/// One C file `cc` reads: the declarations a header list or a native source
/// gives, and a probe for every `extern` of the root.
const Unit = struct {
    /// What the diagnostics call where the declaration was found.
    shown: []const u8,
    /// The lines including the declarations, before the probes.
    includes: []const []const u8,
};

fn checkRoot(arena: std.mem.Allocator, io: std.Io, facts: RootFacts, externs: []const Extern, reporter: *Reporter, opts: Options) !void {
    var units: std.ArrayList(Unit) = .empty;
    if (facts.headers.len > 0) {
        const lines = try arena.alloc([]const u8, facts.headers.len);
        for (facts.headers, lines) |header, *line| line.* = try std.fmt.allocPrint(arena, "#include <{s}>", .{header});
        const shown = if (facts.headers.len == 1)
            try std.fmt.allocPrint(arena, "`{s}`", .{facts.headers[0]})
        else
            try std.fmt.allocPrint(arena, "the {d} headers linea.json names", .{facts.headers.len});
        try units.append(arena, .{ .shown = shown, .includes = lines });
    }
    for (facts.native) |source| {
        const on_disk = try joined(arena, opts.base, source);
        const absolute = std.Io.Dir.cwd().realPathFileAlloc(io, on_disk, arena) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            // The loader refused a source that is not there.
            else => continue,
        };
        const line = try std.fmt.allocPrint(arena, "#include \"{s}\"", .{absolute});
        try units.append(arena, .{ .shown = try std.fmt.allocPrint(arena, "`{s}`", .{relativeTo(facts.manifest_dir, source)}), .includes = try arena.dupe([]const u8, &.{line}) });
    }

    // What each unit says about each `extern`, by unit then by `extern`.
    const found = try arena.alloc(?Found, units.items.len * externs.len);
    @memset(found, null);
    if (units.items.len > 0) {
        const include_dir = std.Io.Dir.cwd().realPathFileAlloc(io, try joined(arena, opts.base, if (facts.manifest_dir.len == 0) "." else facts.manifest_dir), arena) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => try arena.dupe(u8, "."),
        };
        const dir = try toolchain.uniqueTarget(arena, io, opts.scratch, "linea-prototypes");
        try std.Io.Dir.cwd().createDirPath(io, dir);
        defer std.Io.Dir.cwd().deleteTree(io, dir) catch {};
        for (units.items, 0..) |unit, k| {
            const path = try std.fmt.allocPrint(arena, "{s}/unit{d}.c", .{ dir, k });
            try writeProbe(arena, io, path, k, unit, externs);
            const described = try toolchain.describeC(arena, io, include_dir, path, probe_prefix) orelse {
                return reporter.unread(externs[0], "`cc` is not installed");
            };
            if (unreadReason(described.reports, path, unit.includes.len)) |reason| {
                return reporter.unread(externs[0], reason);
            }
            var dumps = try Dumps.parse(arena, described.dump);
            for (externs, 0..) |_, i| found[k * externs.len + i] = try dumps.lookup(arena, k, i);
        }
    }

    for (externs, 0..) |declared, i| {
        var first: ?struct { shape: Found, unit: Unit } = null;
        var macro = false;
        for (units.items, 0..) |unit, k| {
            const seen = found[k * externs.len + i] orelse continue;
            if (seen.macro) macro = true;
            if (seen.ctype != null and first == null) first = .{ .shape = seen, .unit = unit };
        }
        if (macro) {
            try reporter.macro(declared);
            continue;
        }
        const seen = first orelse {
            try reporter.undeclared(declared, facts.headers.len + facts.native.len);
            continue;
        };
        try reporter.compare(declared, seen.shape.ctype.?, seen.unit.shown);
    }
}

fn joined(arena: std.mem.Allocator, base: []const u8, path: []const u8) ![]const u8 {
    if (base.len == 0 or std.fs.path.isAbsolute(path)) return path;
    return std.fs.path.join(arena, &.{ base, path });
}

/// `path` as written below `dir`, the manifest's directory it was joined to.
fn relativeTo(dir: []const u8, path: []const u8) []const u8 {
    if (dir.len == 0 or !std.mem.startsWith(u8, path, dir)) return path;
    const rest = path[dir.len..];
    return if (rest.len > 0 and rest[0] == '/') rest[1..] else rest;
}

test "a native source is shown as its manifest names it" {
    try testing.expectEqualStrings("counter/counter.c", relativeTo("tests/ffi/case", "tests/ffi/case/counter/counter.c"));
    try testing.expectEqualStrings("counter/counter.c", relativeTo("", "counter/counter.c"));
}

fn writeProbe(arena: std.mem.Allocator, io: std.Io, path: []const u8, unit_index: usize, unit: Unit, externs: []const Extern) !void {
    var text: std.Io.Writer.Allocating = .init(arena);
    const w = &text.writer;
    for (unit.includes) |line| try w.print("{s}\n", .{line});
    for (externs, 0..) |declared, i| {
        try w.print("#ifdef {s}\nstatic int {s}{d}_{d}_macro;\n#endif\n", .{ declared.name, probe_prefix, unit_index, i });
        try w.print("static __typeof__({s}) *const {s}{d}_{d} = &{s};\n", .{ declared.name, probe_prefix, unit_index, i, declared.name });
    }
    const file = try std.Io.Dir.cwd().createFile(io, path, .{});
    defer file.close(io);
    var buffer: [4096]u8 = undefined;
    var writer = file.writer(io, &buffer);
    try writer.interface.writeAll(text.written());
    try writer.interface.flush();
}

/// The first error `cc` reported outside the probes, without its location,
/// or null where every error is a probe naming something no included file
/// declares. The probes follow the `includes` lines of the file at `path`.
fn unreadReason(reports: []const u8, path: []const u8, includes: usize) ?[]const u8 {
    var lines = std.mem.splitScalar(u8, reports, '\n');
    while (lines.next()) |line| {
        const at = std.mem.indexOf(u8, line, "error: ") orelse continue;
        const location = line[0..at];
        if (std.mem.startsWith(u8, location, path) and location.len > path.len + 1 and location[path.len] == ':') {
            const rest = location[path.len + 1 ..];
            const end = std.mem.indexOfScalar(u8, rest, ':') orelse rest.len;
            const number = std.fmt.parseInt(usize, rest[0..end], 10) catch 0;
            if (number > includes) continue;
        }
        return line[at + "error: ".len ..];
    }
    return null;
}

test "an error at a probe is not a failure to read the declarations" {
    const reports =
        \\/tmp/p/unit0.c:4:19: error: use of undeclared identifier 'labs'
        \\1 error generated.
    ;
    try testing.expectEqual(@as(?[]const u8, null), unreadReason(reports, "/tmp/p/unit0.c", 1));
    const missing = "/tmp/p/unit0.c:1:10: fatal error: 'nowhere.h' file not found\n";
    try testing.expectEqualStrings("'nowhere.h' file not found", unreadReason(missing, "/tmp/p/unit0.c", 1).?);
    const inside = "/x/counter.c:3:1: error: unknown type name 'in'\n";
    try testing.expectEqualStrings("unknown type name 'in'", unreadReason(inside, "/tmp/p/unit0.c", 1).?);
}

/// What `cc` says a C name is.
pub const CType = struct {
    /// The type as the C declaration spells it, typedefs and all.
    spelled: []const u8,
    shape: Shape,

    pub const Shape = union(enum) {
        integer: struct { bits: u8, signed: bool },
        /// An enumeration, whose integer type the C compiler chooses: a
        /// 32-bit integer of either signedness for every enumeration whose
        /// values fit one.
        enumeration,
        float: u8,
        void,
        boolean,
        pointer: *const CType,
        function: Function,
        /// A structure, a union or an array.
        object,
        /// Anything else, which no Linea type crosses as.
        other,
    };

    pub const Function = struct {
        result: *const CType,
        params: []const CType,
        variadic: bool,
        /// False for a declaration written `f()`, which states no parameters.
        prototyped: bool,
    };
};

/// What one probe found in one unit.
const Found = struct {
    /// The function's type, or null where the unit does not declare the name.
    ctype: ?CType,
    /// Whether the name is a macro in the unit.
    macro: bool,
};

/// The probe sections of one `cc` dump, by the name each describes.
const Dumps = struct {
    sections: std.StringHashMapUnmanaged([]const Line) = .empty,

    fn parse(arena: std.mem.Allocator, dump: []const u8) !Dumps {
        var out: Dumps = .{};
        var current: ?[]const u8 = null;
        var lines: std.ArrayList(Line) = .empty;
        var it = std.mem.splitScalar(u8, dump, '\n');
        while (it.next()) |raw| {
            if (std.mem.startsWith(u8, raw, "Dumping ")) {
                if (current) |name| try out.sections.put(arena, name, try lines.toOwnedSlice(arena));
                current = std.mem.trimEnd(u8, raw["Dumping ".len..], ":");
                continue;
            }
            if (current == null or raw.len == 0) continue;
            try lines.append(arena, Line.of(raw));
        }
        if (current) |name| try out.sections.put(arena, name, try lines.toOwnedSlice(arena));
        return out;
    }

    fn lookup(self: *Dumps, arena: std.mem.Allocator, unit: usize, index: usize) !?Found {
        const name = try std.fmt.allocPrint(arena, "{s}{d}_{d}", .{ probe_prefix, unit, index });
        const macro = self.sections.contains(try std.fmt.allocPrint(arena, "{s}_macro", .{name}));
        const lines = self.sections.get(name) orelse return .{ .ctype = null, .macro = macro };
        return .{ .ctype = try declaredFunction(arena, lines), .macro = macro };
    }
};

/// One line of a type tree: how deep it sits, the node's kind, the type it
/// spells and the words after it.
const Line = struct {
    depth: usize,
    kind: []const u8,
    spelled: []const u8,
    flags: []const u8,

    fn of(raw: []const u8) Line {
        var at: usize = 0;
        while (at < raw.len and (raw[at] == ' ' or raw[at] == '|' or raw[at] == '`' or raw[at] == '-')) at += 1;
        const rest = raw[at..];
        const kind_end = std.mem.indexOfScalar(u8, rest, ' ') orelse rest.len;
        var spelled: []const u8 = "";
        var flags: []const u8 = "";
        if (std.mem.indexOfScalar(u8, rest, '\'')) |open| {
            if (std.mem.indexOfScalarPos(u8, rest, open + 1, '\'')) |close| {
                spelled = rest[open + 1 .. close];
                var after = rest[close + 1 ..];
                // A sugared type is followed by its canonical spelling.
                if (std.mem.startsWith(u8, after, ":'")) {
                    if (std.mem.indexOfScalarPos(u8, after, 2, '\'')) |end| after = after[end + 1 ..];
                }
                flags = after;
            }
        }
        return .{ .depth = at / 2, .kind = rest[0..kind_end], .spelled = spelled, .flags = flags };
    }

    fn isType(self: Line) bool {
        return std.mem.endsWith(u8, self.kind, "Type");
    }

    fn has(self: Line, flag: []const u8) bool {
        var words = std.mem.tokenizeScalar(u8, self.flags, ' ');
        while (words.next()) |word| if (std.mem.eql(u8, word, flag)) return true;
        return false;
    }
};

/// The function a probe's pointer points at, or null where the probe was
/// invalid because nothing declared the name, or names something that is not
/// a function.
fn declaredFunction(arena: std.mem.Allocator, lines: []const Line) !?CType {
    for (lines) |line| {
        if (line.depth == 0 and std.mem.eql(u8, line.kind, "VarDecl") and std.mem.indexOf(u8, line.flags, " invalid") != null) return null;
    }
    // `cc` prints the probe's own type as a tree at depth 0, after the
    // declaration and its initializer.
    for (lines, 0..) |line, i| {
        if (line.depth != 0 or !line.isType()) continue;
        const pointer = try convert(arena, lines, i);
        return switch (pointer.shape) {
            .pointer => |pointee| switch (pointee.shape) {
                .function => pointee.*,
                else => null,
            },
            else => null,
        };
    }
    return null;
}

/// The children of the line at `at` that are types.
fn typeChildren(arena: std.mem.Allocator, lines: []const Line, at: usize) ![]const usize {
    var out: std.ArrayList(usize) = .empty;
    const depth = lines[at].depth;
    var i = at + 1;
    while (i < lines.len and lines[i].depth > depth) : (i += 1) {
        if (lines[i].depth == depth + 1 and lines[i].isType()) try out.append(arena, i);
    }
    return out.items;
}

/// The canonical type the line at `at` and its children describe: sugar is
/// read through to the type it stands for, and qualifiers are dropped, since
/// neither changes how a value crosses.
fn convert(arena: std.mem.Allocator, lines: []const Line, at: usize) std.mem.Allocator.Error!CType {
    const line = lines[at];
    const children = try typeChildren(arena, lines, at);
    // A qualified type's one child is the type it qualifies, and a sugared
    // one's last child is the type it stands for.
    if (std.mem.eql(u8, line.kind, "QualType") or line.has("sugar")) {
        if (children.len == 0) return .{ .spelled = line.spelled, .shape = .other };
        var inner = try convert(arena, lines, children[children.len - 1]);
        // `typeof (f)` names the probe's expression, not a type C spells.
        if (!std.mem.startsWith(u8, line.kind, "TypeOf")) inner.spelled = line.spelled;
        return inner;
    }
    const shape: CType.Shape = if (std.mem.eql(u8, line.kind, "BuiltinType"))
        builtinShape(line.spelled)
    else if (std.mem.eql(u8, line.kind, "PointerType")) blk: {
        if (children.len == 0) break :blk .other;
        const pointee = try arena.create(CType);
        pointee.* = try convert(arena, lines, children[0]);
        break :blk .{ .pointer = pointee };
    } else if (std.mem.eql(u8, line.kind, "FunctionProtoType") or std.mem.eql(u8, line.kind, "FunctionNoProtoType")) blk: {
        if (children.len == 0) break :blk .other;
        const result = try arena.create(CType);
        result.* = try convert(arena, lines, children[0]);
        const params = try arena.alloc(CType, children.len - 1);
        for (children[1..], params) |child, *param| param.* = try convert(arena, lines, child);
        break :blk .{ .function = .{
            .result = result,
            .params = params,
            .variadic = line.has("variadic"),
            .prototyped = std.mem.eql(u8, line.kind, "FunctionProtoType"),
        } };
    } else if (std.mem.eql(u8, line.kind, "EnumType"))
        .enumeration
    else if (std.mem.eql(u8, line.kind, "RecordType") or std.mem.endsWith(u8, line.kind, "ArrayType"))
        .object
    else
        .other;
    return .{ .spelled = line.spelled, .shape = shape };
}

/// The shape of a C builtin type on the supported targets, all LP64: `int`
/// is 32 bits, `long` and `long long` 64, and plain `char` is signed or not
/// as the target says.
fn builtinShape(name: []const u8) CType.Shape {
    const Entry = struct { []const u8, CType.Shape };
    const plain_char_signed = builtin.target.cCharSignedness() == .signed;
    const table = [_]Entry{
        .{ "char", .{ .integer = .{ .bits = 8, .signed = plain_char_signed } } },
        .{ "signed char", .{ .integer = .{ .bits = 8, .signed = true } } },
        .{ "unsigned char", .{ .integer = .{ .bits = 8, .signed = false } } },
        .{ "short", .{ .integer = .{ .bits = 16, .signed = true } } },
        .{ "unsigned short", .{ .integer = .{ .bits = 16, .signed = false } } },
        .{ "int", .{ .integer = .{ .bits = 32, .signed = true } } },
        .{ "unsigned int", .{ .integer = .{ .bits = 32, .signed = false } } },
        .{ "long", .{ .integer = .{ .bits = 64, .signed = true } } },
        .{ "unsigned long", .{ .integer = .{ .bits = 64, .signed = false } } },
        .{ "long long", .{ .integer = .{ .bits = 64, .signed = true } } },
        .{ "unsigned long long", .{ .integer = .{ .bits = 64, .signed = false } } },
        .{ "float", .{ .float = 32 } },
        .{ "double", .{ .float = 64 } },
        .{ "void", .void },
        .{ "_Bool", .boolean },
        .{ "bool", .boolean },
    };
    for (table) |entry| if (std.mem.eql(u8, entry[0], name)) return entry[1];
    return .other;
}

test "a type tree is read through its sugar to the type C passes" {
    const dump =
        \\Dumping linea_probe_0_0:
        \\VarDecl 0x1 <p.c:6:1, col:65> col:48 linea_probe_0_0 'typeof (sqlite3_column_int64) *const' static cinit
        \\`-UnaryOperator 0x2 <col:64, col:65> 'sqlite3_int64 (*)(sqlite3_stmt *, int)' prefix '&' cannot overflow
        \\  `-DeclRefExpr 0x3 <col:65> 'sqlite3_int64 (sqlite3_stmt *, int)' Function 0x4 'sqlite3_column_int64' 'sqlite3_int64 (sqlite3_stmt *, int)'
        \\QualType 0x5 'typeof (sqlite3_column_int64) *const' const
        \\`-PointerType 0x6 'typeof (sqlite3_column_int64) *'
        \\  `-TypeOfExprType 0x7 'typeof (sqlite3_column_int64)' sugar
        \\    |-ParenExpr 0x8 <p.c:6:18, col:39> 'sqlite3_int64 (sqlite3_stmt *, int)'
        \\    | `-DeclRefExpr 0x9 <col:19> 'sqlite3_int64 (sqlite3_stmt *, int)' Function 0x4 'sqlite3_column_int64' 'sqlite3_int64 (sqlite3_stmt *, int)' non_odr_use_unevaluated
        \\    `-FunctionProtoType 0xa 'sqlite3_int64 (sqlite3_stmt *, int)' cdecl
        \\      |-ElaboratedType 0xb 'sqlite3_int64' sugar
        \\      | `-TypedefType 0xc 'sqlite3_int64' sugar
        \\      |   |-Typedef 0xd 'sqlite3_int64'
        \\      |   `-BuiltinType 0xe 'long long'
        \\      |-PointerType 0xf 'sqlite3_stmt *'
        \\      | `-ElaboratedType 0x10 'sqlite3_stmt' sugar
        \\      |   `-TypedefType 0x11 'sqlite3_stmt' sugar
        \\      |     |-Typedef 0x12 'sqlite3_stmt'
        \\      |     `-RecordType 0x13 'struct sqlite3_stmt'
        \\      |       `-Record 0x14 'sqlite3_stmt'
        \\      `-BuiltinType 0x15 'int'
        \\
        \\Dumping linea_probe_0_1:
        \\VarDecl 0x16 <q.c:4:1, col:29> col:29 invalid linea_probe_0_1 'int *const' static
        \\QualType 0x17 'int *const' const
        \\`-PointerType 0x18 'int *'
        \\  `-BuiltinType 0x19 'int'
    ;
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var dumps = try Dumps.parse(arena, dump);
    const column = (try dumps.lookup(arena, 0, 0)).?.ctype.?;
    try testing.expectEqualStrings("sqlite3_int64 (sqlite3_stmt *, int)", column.spelled);
    const function = column.shape.function;
    try testing.expectEqualStrings("sqlite3_int64", function.result.spelled);
    try testing.expectEqual(CType.Shape{ .integer = .{ .bits = 64, .signed = true } }, function.result.shape);
    try testing.expectEqual(@as(usize, 2), function.params.len);
    try testing.expectEqual(CType.Shape.object, function.params[0].shape.pointer.shape);
    try testing.expectEqual(CType.Shape{ .integer = .{ .bits = 32, .signed = true } }, function.params[1].shape);
    try testing.expect(!function.variadic);
    try testing.expectEqual(@as(?CType, null), (try dumps.lookup(arena, 0, 1)).?.ctype);
}

/// Why a C position disagrees with what lowering passes there.
const Mismatch = union(enum) {
    /// C states no parameters: `f()`.
    unprototyped,
    variadic,
    arity: struct { c: usize, linea: usize },
    param: struct { index: usize, c: CType, implied: foreign.Value, inner: ?*const Mismatch = null },
    result: struct { c: CType, implied: ?foreign.Value },
};

fn scalarAccepts(scalar: ForeignScalar, c: CType) bool {
    return switch (scalar) {
        .float64 => c.shape == .float and c.shape.float == 64,
        .integer => |integer| switch (c.shape) {
            .integer => |held| held.bits == integer.bits and held.signed == integer.signed,
            .enumeration => integer.bits == 32,
            // A pointer is a 64-bit address, which a `UInt64` and every
            // newtype over one carries: a handle, or a `std.ffi` view.
            .pointer => integer.bits == 64 and !integer.signed,
            else => false,
        },
    };
}

/// How one position disagrees: by its own type, or inside the function a
/// callback parameter points at.
const Disagreement = union(enum) {
    own,
    callback: *const Mismatch,
};

fn valueMismatch(arena: std.mem.Allocator, implied: foreign.Value, c: CType) std.mem.Allocator.Error!?Disagreement {
    const agrees = switch (implied) {
        .scalar => |scalar| scalarAccepts(scalar, c),
        .address_of => |scalar| switch (c.shape) {
            .pointer => |pointee| scalarAccepts(scalar, pointee.*),
            else => false,
        },
        .context => switch (c.shape) {
            .pointer => |pointee| pointee.shape == .void,
            else => false,
        },
        .callback => |called| switch (c.shape) {
            .pointer => |pointee| switch (pointee.shape) {
                .function => |function| {
                    const inner = try functionMismatch(arena, called.*, function) orelse return null;
                    const held = try arena.create(Mismatch);
                    held.* = inner;
                    return .{ .callback = held };
                },
                else => false,
            },
            else => false,
        },
    };
    return if (agrees) null else .own;
}

/// The first position at which `c` disagrees with `implied`, or null where
/// every position agrees.
fn functionMismatch(arena: std.mem.Allocator, implied: foreign.Prototype, c: CType.Function) std.mem.Allocator.Error!?Mismatch {
    if (!c.prototyped) return .unprototyped;
    if (c.variadic) return .variadic;
    if (c.params.len != implied.params.len) return .{ .arity = .{ .c = c.params.len, .linea = implied.params.len } };
    for (implied.params, c.params, 0..) |value, param, i| {
        const seen = try valueMismatch(arena, value, param) orelse continue;
        return .{ .param = .{ .index = i, .c = param, .implied = value, .inner = switch (seen) {
            .own => null,
            .callback => |inner| inner,
        } } };
    }
    const answers = if (implied.result) |value| try valueMismatch(arena, value, c.result.*) != null else c.result.shape != .void;
    if (answers) return .{ .result = .{ .c = c.result.*, .implied = implied.result } };
    return null;
}

/// Writes what reaches the diagnostics sink.
const Reporter = struct {
    arena: std.mem.Allocator,
    sink: *Sink,
    ast: *const Ast,

    fn nameLabel(self: *Reporter, declared: Extern, message: []const u8) ![]const Label {
        const labels = try self.sink.arena.alloc(Label, 1);
        labels[0] = .{ .file = self.ast.fileOf(self.ast.declName(declared.decl)), .span = self.ast.tokenSpan(self.ast.declName(declared.decl)), .message = message };
        return labels;
    }

    fn unread(self: *Reporter, declared: Extern, reason: []const u8) !void {
        const a = self.sink.arena;
        try self.sink.add(.{
            .severity = .err,
            .code = .t_extern_prototype,
            .message = try std.fmt.allocPrint(a, "the C declarations this root names cannot be read, so `{s}` cannot be held to its prototype: {s}", .{ declared.name, reason }),
            .labels = try self.nameLabel(declared, "held to the prototype its root's C declarations give it"),
            .notes = try a.dupe([]const u8, &.{"correct `headers` or `native` in linea.json, or install the C library whose header it names"}),
        });
    }

    fn macro(self: *Reporter, declared: Extern) !void {
        const a = self.sink.arena;
        try self.sink.add(.{
            .severity = .err,
            .code = .t_extern_prototype,
            .message = try std.fmt.allocPrint(a, "`{s}` is a macro in C, so C code calling it reaches what the macro expands to, not the symbol this declaration names", .{declared.name}),
            .labels = try self.nameLabel(declared, "a macro has no prototype to hold this to"),
            .notes = try a.dupe([]const u8, &.{"declare the function the macro expands to, or call it through a C function in `native`"}),
        });
    }

    fn undeclared(self: *Reporter, declared: Extern, named: usize) !void {
        const a = self.sink.arena;
        const why = if (named == 0)
            "linea.json names no C declarations for this root"
        else
            "neither the `headers` nor the `native` sources its linea.json names declare it";
        try self.sink.add(.{
            .severity = .err,
            .code = .t_extern_prototype,
            .message = try std.fmt.allocPrint(a, "no C declaration of `{s}` is in reach: {s}", .{ declared.name, why }),
            .labels = try self.nameLabel(declared, "held to the prototype C gives it, and C gives it none"),
            .notes = try a.dupe([]const u8, &.{"name the header that declares it under \"headers\" in linea.json, such as \"stdlib.h\", or build the C that defines it under \"native\""}),
        });
    }

    fn compare(self: *Reporter, declared: Extern, c: CType, shown: []const u8) !void {
        const function = c.shape.function;
        const mismatch = try functionMismatch(self.arena, declared.implied, function) orelse return;
        const a = self.sink.arena;
        const found = try rendered(a, c.spelled, declared.name);
        const implied = try impliedText(a, declared, function);
        const params = self.ast.declParams(declared.decl);
        const file = self.ast.fileOf(self.ast.declName(declared.decl));
        var span = self.ast.tokenSpan(self.ast.declName(declared.decl));
        var label: []const u8 = "";
        var help: []const u8 = "";
        switch (mismatch) {
            .unprototyped => {
                label = "C's declaration lists no parameters";
                help = "declare the function with its parameters in C, as a prototype";
            },
            .variadic => {
                label = "C reads a variable list of arguments, which an `extern` cannot pass";
                help = "call it through a C function with fixed parameters, built under \"native\"";
            },
            .arity => |counts| {
                label = try std.fmt.allocPrint(a, "C takes {d} parameter{s}, and this declares {d}", .{ counts.c, plural(counts.c), counts.linea });
                help = try std.fmt.allocPrint(a, "declare one parameter for each of the {d} C takes, in its order", .{counts.c});
            },
            .param => |at| {
                span = self.ast.writtenSpan(params[at.index].written);
                const name = self.ast.tokenText(params[at.index].name);
                if (at.inner) |inner| {
                    label = try std.fmt.allocPrint(a, "C calls this back as `{s}`", .{at.c.spelled});
                    help = try std.fmt.allocPrint(a, "in the callback, {s}", .{try innerHelp(a, inner.*)});
                } else {
                    label = try std.fmt.allocPrint(a, "C takes `{s}` here", .{at.c.spelled});
                    help = try positionHelp(a, at.implied, at.c, try std.fmt.allocPrint(a, "`{s}`", .{name}));
                }
            },
            .result => |at| {
                const returns = self.ast.declReturnRef(declared.decl);
                if (returns.wasWritten()) span = self.ast.writtenSpan(returns);
                label = try std.fmt.allocPrint(a, "C answers `{s}`", .{at.c.spelled});
                help = try resultHelp(a, at.implied, at.c);
            },
        }
        const labels = try a.alloc(Label, 1);
        labels[0] = .{ .file = file, .span = span, .message = label };
        try self.sink.add(.{
            .severity = .err,
            .code = .t_extern_prototype,
            .message = try std.fmt.allocPrint(a, "C declares `{s}`, and this declaration calls it as `{s}`", .{ found, implied }),
            .labels = labels,
            .remarks = try a.dupe([]const u8, &.{try std.fmt.allocPrint(a, "`{s}` is declared by {s}", .{ declared.name, shown })}),
            .notes = try a.dupe([]const u8, &.{help}),
        });
    }
};

fn plural(n: usize) []const u8 {
    return if (n == 1) "" else "s";
}

fn innerHelp(a: std.mem.Allocator, mismatch: Mismatch) ![]const u8 {
    return switch (mismatch) {
        .unprototyped => "C's function type lists no parameters",
        .variadic => "C passes a variable list of arguments, which a callback cannot take",
        .arity => |counts| try std.fmt.allocPrint(a, "take one parameter for each of the {d} C passes, the context first", .{counts.c}),
        .param => |at| if (at.inner) |inner| innerHelp(a, inner.*) else try std.fmt.allocPrint(a, "C passes `{s}` as parameter {d}: {s}", .{ at.c.spelled, at.index + 1, try positionHelp(a, at.implied, at.c, "that parameter") }),
        .result => |at| resultHelp(a, at.implied, at.c),
    };
}

/// The Linea type a C scalar crosses as, or null for one none does.
fn lineaName(c: CType) ?[]const u8 {
    return switch (c.shape) {
        .integer => |integer| switch (integer.bits) {
            8 => if (integer.signed) "Int8" else "UInt8",
            16 => if (integer.signed) "Int16" else "UInt16",
            32 => if (integer.signed) "Int32" else "UInt32",
            64 => if (integer.signed) "Int64" else "UInt64",
            else => null,
        },
        .enumeration => "Int32",
        .float => |bits| if (bits == 64) "Float64" else null,
        .pointer => "UInt64",
        else => null,
    };
}

/// The edit that makes a parameter written as `implied` take C's `c`. `name`
/// is how the help names the parameter: its name in backticks, or a phrase.
fn positionHelp(a: std.mem.Allocator, implied: foreign.Value, c: CType, name: []const u8) ![]const u8 {
    switch (c.shape) {
        .boolean => return "C's `bool` has no Linea type that crosses: call it through a C function, built under \"native\", that takes an integer",
        .object => return "C takes a structure by value, which no Linea type crosses as: call it through a C function, built under \"native\", that takes its address",
        .void, .function, .other => return try std.fmt.allocPrint(a, "C's `{s}` has no Linea type that crosses", .{c.spelled}),
        else => {},
    }
    switch (implied) {
        .context => return "a callback's context crosses as C's `void *`: declare C's parameter `void *`",
        .callback => return "C takes a value here, not a function to call back",
        .address_of => |scalar| switch (c.shape) {
            .pointer => |pointee| {
                if (pointee.shape == .void or pointee.shape == .object or pointee.shape == .other)
                    return try std.fmt.allocPrint(a, "C takes the object's own address, which a plain parameter passes: drop `inout` from {s}", .{name});
                const held = lineaName(pointee.*) orelse return try std.fmt.allocPrint(a, "C's `{s}` has no Linea type that crosses", .{pointee.spelled});
                return try std.fmt.allocPrint(a, "C writes a `{s}` through the address: declare {s} as an `inout` `{s}`", .{ pointee.spelled, name, held });
            },
            else => {
                if (scalarAccepts(scalar, c)) return try std.fmt.allocPrint(a, "C takes the value itself: drop `inout` from {s}", .{name});
                const held = lineaName(c) orelse return try std.fmt.allocPrint(a, "C's `{s}` has no Linea type that crosses", .{c.spelled});
                return try std.fmt.allocPrint(a, "C takes the value itself: declare {s} as `{s}`, without `inout`", .{ name, held });
            },
        },
        .scalar => |scalar| switch (c.shape) {
            .pointer => |pointee| {
                if (scalarAccepts(scalar, pointee.*)) return try std.fmt.allocPrint(a, "C takes `{s}`, the address of a place it reads or writes: make {s} `inout`, which passes its place's address", .{ c.spelled, name });
                return try std.fmt.allocPrint(a, "C takes an address: declare {s} as `UInt64`, or as a handle or `std.ffi` view over one", .{name});
            },
            else => {
                const held = lineaName(c) orelse return try std.fmt.allocPrint(a, "C's `{s}` has no Linea type that crosses", .{c.spelled});
                return try std.fmt.allocPrint(a, "declare {s} as `{s}`, the Linea type of C's `{s}`", .{ name, held, c.spelled });
            },
        },
    }
}

fn resultHelp(a: std.mem.Allocator, implied: ?foreign.Value, c: CType) ![]const u8 {
    if (c.shape == .void) return "C answers nothing: drop the result";
    const held = lineaName(c) orelse return try std.fmt.allocPrint(a, "C's `{s}` has no Linea type that crosses: call it through a C function, built under \"native\", that answers one", .{c.spelled});
    if (implied == null) return try std.fmt.allocPrint(a, "declare the result `-> {s}`, the Linea type of C's `{s}`", .{ held, c.spelled });
    return try std.fmt.allocPrint(a, "declare the result `{s}`, the Linea type of C's `{s}`", .{ held, c.spelled });
}

/// C's function type spelled with `name` before its parameter list:
/// `int (sqlite3 *)` becomes `int sqlite3_close_v2(sqlite3 *)`.
fn rendered(a: std.mem.Allocator, spelled: []const u8, name: []const u8) ![]const u8 {
    const open = parameterListStart(spelled) orelse return std.fmt.allocPrint(a, "{s} {s}", .{ spelled, name });
    const head = std.mem.trimEnd(u8, spelled[0..open], " ");
    const separator: []const u8 = if (head.len > 0 and head[head.len - 1] == '*') "" else " ";
    return std.fmt.allocPrint(a, "{s}{s}{s}{s}", .{ head, separator, name, spelled[open..] });
}

/// Where the parameter list that closes `spelled` opens.
fn parameterListStart(spelled: []const u8) ?usize {
    if (spelled.len == 0 or spelled[spelled.len - 1] != ')') return null;
    var depth: usize = 0;
    var i = spelled.len;
    while (i > 0) {
        i -= 1;
        switch (spelled[i]) {
            ')' => depth += 1,
            '(' => {
                depth -= 1;
                if (depth == 0) return i;
            },
            else => {},
        }
    }
    return null;
}

test "a C prototype is shown with its function's name" {
    const gpa = testing.allocator;
    const plain = try rendered(gpa, "int (sqlite3 *)", "sqlite3_close_v2");
    defer gpa.free(plain);
    try testing.expectEqualStrings("int sqlite3_close_v2(sqlite3 *)", plain);
    const pointer = try rendered(gpa, "const char *(sqlite3 *)", "sqlite3_errmsg");
    defer gpa.free(pointer);
    try testing.expectEqualStrings("const char *sqlite3_errmsg(sqlite3 *)", pointer);
    const callback = try rendered(gpa, "int (int (*)(void *, int), void *)", "visit");
    defer gpa.free(callback);
    try testing.expectEqualStrings("int visit(int (*)(void *, int), void *)", callback);
}

/// The C type lowering passes as `implied`, as C would spell it.
fn impliedSpelling(a: std.mem.Allocator, implied: foreign.Value) ![]const u8 {
    return switch (implied) {
        .scalar => |scalar| scalarSpelling(scalar),
        .address_of => |scalar| std.fmt.allocPrint(a, "{s} *", .{scalarSpelling(scalar)}),
        .context => "void *",
        .callback => |called| blk: {
            var text: std.Io.Writer.Allocating = .init(a);
            try text.writer.print("{s} (*)(", .{if (called.result) |r| try impliedSpelling(a, r) else "void"});
            if (called.params.len == 0) try text.writer.writeAll("void");
            for (called.params, 0..) |param, i| {
                if (i > 0) try text.writer.writeAll(", ");
                try text.writer.writeAll(try impliedSpelling(a, param));
            }
            try text.writer.writeAll(")");
            break :blk text.written();
        },
    };
}

fn scalarSpelling(scalar: ForeignScalar) []const u8 {
    return switch (scalar) {
        .float64 => "double",
        .integer => |integer| switch (integer.bits) {
            8 => if (integer.signed) "int8_t" else "uint8_t",
            16 => if (integer.signed) "int16_t" else "uint16_t",
            32 => if (integer.signed) "int32_t" else "uint32_t",
            else => if (integer.signed) "int64_t" else "uint64_t",
        },
    };
}

/// The prototype the declaration implies, spelled as C would write it, with
/// C's own spelling kept at each position that agrees.
fn impliedText(a: std.mem.Allocator, declared: Extern, c: CType.Function) ![]const u8 {
    var text: std.Io.Writer.Allocating = .init(a);
    const w = &text.writer;
    const result = if (declared.implied.result) |value|
        if (try valueMismatch(a, value, c.result.*) == null) c.result.spelled else try impliedSpelling(a, value)
    else
        "void";
    try w.writeAll(result);
    if (result.len == 0 or result[result.len - 1] != '*') try w.writeAll(" ");
    try w.print("{s}(", .{declared.name});
    if (declared.implied.params.len == 0) try w.writeAll("void");
    for (declared.implied.params, 0..) |value, i| {
        if (i > 0) try w.writeAll(", ");
        const agrees = i < c.params.len and c.prototyped and try valueMismatch(a, value, c.params[i]) == null;
        try w.writeAll(if (agrees) c.params[i].spelled else try impliedSpelling(a, value));
    }
    try w.writeAll(")");
    return text.written();
}
