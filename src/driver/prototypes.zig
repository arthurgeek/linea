//! [T-ExternPrototype]: every `extern` a root declares for a C function, and
//! every `export` its C declares, is held to the prototype the root's own C
//! declarations give that function.
//!
//! The C declarations are the sources the root's manifest builds under
//! `native` and the headers it names under `headers`. For each of them one C
//! file is written that includes it and, for every function of the root,
//! takes the function's address, names its symbol and refers to it from an
//! inline function of external linkage:
//!
//! ```c
//! #include <sqlite3.h>
//! extern __typeof__(sqlite3_close_v2) sqlite3_close_v2 __asm__("_sqlite3_close_v2");
//! static __typeof__(sqlite3_close_v2) *const linea_probe_0_3 = &sqlite3_close_v2;
//! inline void linea_probe_0_3_linkage(void) { (void)&sqlite3_close_v2; }
//! ```
//!
//! `cc` refuses the second line where C gives the function another symbol,
//! and the fourth where the function is `static`. It prints each pointer's
//! type tree with every typedef resolved, and the compiler compares that
//! tree, position by position, with what lowering passes there
//! (`foreign.externPrototype`), for every C declaration of the root that
//! declares the function. The comparison is by representation, not by C's
//! type identity: C's `long long` and `long` are both 64-bit signed integers,
//! and a handle's address is any pointer. An enumeration's width and
//! signedness are the compiler's choice, so a second file asks `cc` for them.
//! Symbols in the runtime's namespace are held to the runtime's own table
//! instead ([T-ExternRuntime]), and so are the storage primitives lowering
//! replaces.

const std = @import("std");
const builtin = @import("builtin");
const testing = std.testing;
const loader = @import("loader.zig");
const toolchain = @import("toolchain.zig");
const runtime_symbols = @import("../support/runtime_symbols.zig");
const foreign = @import("../sema/foreign.zig");
const RawAccesses = @import("../sema/intrinsics.zig").RawAccesses;
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

/// Holds every `extern` and `export` of a program's roots to its C
/// prototype, reporting each that disagrees into `sink`. Reads the
/// declarations the checker settled, so it runs once the semantic passes
/// accepted the program.
pub fn check(gpa: std.mem.Allocator, io: std.Io, semantics: *const loader.Semantics, sink: *Sink, opts: Options) !void {
    const expanded = &semantics.expanded;
    const program = expanded.source;
    if (program.roots.len == 0) return;
    var arena_state = std.heap.ArenaAllocator.init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const by_root = try arena.alloc(std.ArrayList(Subject), program.roots.len);
    for (by_root) |*list| list.* = .empty;
    for (program.modules, 0..) |module, mi| {
        if (module.root == .none) continue;
        for (expanded.declsOf(ModuleId.from(mi))) |d| {
            const ast = &expanded.ast;
            const exported = ast.declIsExport(d);
            if (!(ast.declIsExtern(d) and module.externs) and !exported) continue;
            if (ast.declTypeParams(d).len != 0) continue;
            const name = ast.tokenText(ast.declName(d));
            if (!exported) {
                if (std.mem.startsWith(u8, name, runtime_symbols.namespace) or runtime_symbols.signatureOf(name) != null) continue;
                if (namedByCompiler(semantics.typing.raw_accesses, d)) continue;
            }
            const implied = try foreign.externPrototype(arena, &semantics.typing, d) orelse continue;
            try by_root[module.root.index()].append(arena, .{ .decl = d, .name = name, .implied = implied, .exported = exported });
        }
    }
    for (by_root, program.roots) |subjects, facts| {
        if (subjects.items.len == 0) continue;
        var reporter: Reporter = .{ .arena = arena, .sink = sink, .ast = &expanded.ast };
        try checkRoot(arena, io, facts, subjects.items, &reporter, opts);
    }
}

/// Whether `d` is one of the standard library's storage primitives, whose
/// calls lowering replaces and the checker certifies, so no C defines it.
fn namedByCompiler(raw: RawAccesses, d: DeclId) bool {
    inline for (@typeInfo(RawAccesses).@"struct".fields) |field| {
        const value = @field(raw, field.name);
        switch (@TypeOf(value)) {
            DeclId => if (value == d) return true,
            else => switch (@typeInfo(@TypeOf(value))) {
                .array => |array| if (array.child == DeclId) {
                    for (value) |held| if (held == d) return true;
                },
                else => {},
            },
        }
    }
    return false;
}

/// A declaration held to C: an `extern`, which C must declare, or an
/// `export`, which is compared wherever C declares it.
const Subject = struct {
    decl: DeclId,
    name: []const u8,
    implied: foreign.Prototype,
    exported: bool,
};

/// One C file `cc` reads: the declarations a header list or a native source
/// gives, and the probes for every subject of the root.
const Unit = struct {
    /// What the diagnostics call where the declaration was found.
    shown: []const u8,
    /// The lines including the declarations, before the probes.
    includes: []const []const u8,
};

/// What one unit says about one subject.
const Found = struct {
    /// The function's type, or null where the unit does not declare the name.
    ctype: ?CType = null,
    /// Whether the name is a macro in the unit.
    macro: bool = false,
    /// Why C gives the function another symbol than its name, where it does.
    symbol: ?[]const u8 = null,
    /// Whether C declares the function `static`, which leaves it no symbol.
    internal: bool = false,
    /// Whether `cc` refused the probe taking the function's address, as it
    /// does where nothing declares the name.
    refused: bool = false,
};

fn checkRoot(arena: std.mem.Allocator, io: std.Io, facts: RootFacts, subjects: []const Subject, reporter: *Reporter, opts: Options) !void {
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
        // The loader admits only a path of letters, digits and `_.+-/`, so
        // the include line holds nothing but the path.
        const line = try std.fmt.allocPrint(arena, "#include \"{s}\"", .{absolute});
        try units.append(arena, .{ .shown = try std.fmt.allocPrint(arena, "`{s}`", .{relativeTo(facts.manifest_dir, source)}), .includes = try arena.dupe([]const u8, &.{line}) });
    }
    if (units.items.len == 0) {
        for (subjects) |subject| if (!subject.exported) try reporter.undeclared(subject, 0);
        return;
    }

    // What each unit says about each subject, by unit then by subject.
    const found = try arena.alloc(Found, units.items.len * subjects.len);
    @memset(found, .{});
    const include_dir = std.Io.Dir.cwd().realPathFileAlloc(io, try joined(arena, opts.base, if (facts.manifest_dir.len == 0) "." else facts.manifest_dir), arena) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => try arena.dupe(u8, "."),
    };
    const dir = try toolchain.uniqueTarget(arena, io, opts.scratch, "linea-prototypes");
    try std.Io.Dir.cwd().createDirPath(io, dir);
    defer std.Io.Dir.cwd().deleteTree(io, dir) catch {};
    for (units.items, 0..) |unit, k| {
        const path = try std.fmt.allocPrint(arena, "{s}/unit{d}.c", .{ dir, k });
        const roles = try writeProbe(arena, io, path, k, unit, subjects);
        const described = try toolchain.describeC(arena, io, include_dir, path, probe_prefix) orelse {
            return reporter.unread(subjects[0], "`cc` is not installed");
        };
        const row = found[k * subjects.len ..][0..subjects.len];
        if (try readReports(described.reports, path, unit.includes.len, roles, row)) |reason| {
            return reporter.unread(subjects[0], reason);
        }
        const dumps = try Dumps.parse(arena, described.dump);

        // An enumeration's width is learnt from a second file, which names
        // each enumeration the first one's type trees spell.
        var widths: Widths = .{};
        for (row, 0..) |_, i| _ = try dumps.function(arena, k, i, &widths);
        if (widths.wanted.items.len > 0) {
            const sizes = try std.fmt.allocPrint(arena, "{s}/unit{d}-widths.c", .{ dir, k });
            try writeWidths(arena, io, sizes, unit, widths.wanted.items);
            const measured = try toolchain.describeC(arena, io, include_dir, sizes, probe_prefix) orelse {
                return reporter.unread(subjects[0], "`cc` is not installed");
            };
            try widths.read(arena, try Dumps.parse(arena, measured.dump));
        }
        // A probe `cc` refused declares nothing, whatever recovery left in
        // its tree.
        for (row, 0..) |*seen, i| seen.ctype = if (seen.refused) null else try dumps.function(arena, k, i, &widths);
        for (row, 0..) |*seen, i| seen.macro = dumps.sections.contains(try probeName(arena, k, i, "_macro"));
    }

    for (subjects, 0..) |subject, i| {
        var declared = false;
        var macro = false;
        for (units.items, 0..) |_, k| {
            const seen = found[k * subjects.len + i];
            if (seen.macro) macro = true;
            if (seen.ctype != null) declared = true;
        }
        if (subject.exported) {
            // C names an export only where it calls it; a macro of that
            // name is C's own business.
            if (macro) continue;
        } else {
            if (macro) {
                try reporter.macro(subject);
                continue;
            }
            if (!declared) {
                try reporter.undeclared(subject, facts.headers.len + facts.native.len);
                continue;
            }
        }
        // Every C declaration of the function is held to the declaration,
        // since any of them may be the one C code calling it was built with.
        for (units.items, 0..) |unit, k| {
            const seen = found[k * subjects.len + i];
            const ctype = seen.ctype orelse continue;
            if (!subject.exported) {
                if (seen.internal) {
                    try reporter.internal(subject, unit.shown);
                    break;
                }
                if (seen.symbol) |reason| {
                    try reporter.symbol(subject, unit.shown, reason);
                    break;
                }
            }
            if (try reporter.compare(subject, ctype, unit.shown)) break;
        }
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

fn probeName(arena: std.mem.Allocator, unit: usize, index: usize, suffix: []const u8) ![]const u8 {
    return std.fmt.allocPrint(arena, "{s}{d}_{d}{s}", .{ probe_prefix, unit, index, suffix });
}

/// What a line of a probe file asks of the subject it names.
const Role = union(enum) {
    /// A line including C declarations, or one that asks nothing.
    none,
    /// The line naming the symbol the subject links against.
    symbol: usize,
    /// The line referring to the subject from an inline function of external
    /// linkage.
    linkage: usize,
    /// A line taking the subject's address, which is refused where nothing
    /// declares it.
    address: usize,
};

/// The symbol a C function named `name` has: the name, with an underscore
/// before it on Darwin.
fn symbolOf(arena: std.mem.Allocator, name: []const u8) ![]const u8 {
    return std.fmt.allocPrint(arena, "{s}{s}", .{ if (builtin.target.os.tag.isDarwin()) "_" else "", name });
}

/// Writes the probe file and answers what each of its lines asks.
fn writeProbe(arena: std.mem.Allocator, io: std.Io, path: []const u8, unit_index: usize, unit: Unit, subjects: []const Subject) ![]const Role {
    var text: std.Io.Writer.Allocating = .init(arena);
    const w = &text.writer;
    var roles: std.ArrayList(Role) = .empty;
    for (unit.includes) |line| {
        try w.print("{s}\n", .{line});
        try roles.append(arena, .none);
    }
    for (subjects, 0..) |subject, i| {
        const name = subject.name;
        try w.print("#ifdef {s}\nstatic int {s};\n#endif\n", .{ name, try probeName(arena, unit_index, i, "_macro") });
        try roles.appendSlice(arena, &.{ .none, .none, .none });
        if (!subject.exported) {
            try w.print("extern __typeof__({s}) {s} __asm__(\"{s}\");\n", .{ name, name, try symbolOf(arena, name) });
            try roles.append(arena, .{ .symbol = i });
        }
        try w.print("static __typeof__({s}) *const {s} = &{s};\n", .{ name, try probeName(arena, unit_index, i, ""), name });
        try roles.append(arena, .{ .address = i });
        if (!subject.exported) {
            try w.print("inline void {s}(void) {{ (void)&{s}; }}\n", .{ try probeName(arena, unit_index, i, "_linkage"), name });
            try roles.append(arena, .{ .linkage = i });
        }
    }
    try writeFile(io, path, text.written());
    return roles.items;
}

fn writeFile(io: std.Io, path: []const u8, text: []const u8) !void {
    const file = try std.Io.Dir.cwd().createFile(io, path, .{});
    defer file.close(io);
    var buffer: [4096]u8 = undefined;
    var writer = file.writer(io, &buffer);
    try writer.interface.writeAll(text);
    try writer.interface.flush();
}

/// Records what `cc`'s errors at the probe lines say into `row`, and answers
/// the first error outside the probes, without its location, or null where
/// there is none. An error at a probe taking an address says nothing a
/// missing type tree does not; one at a symbol or linkage probe is recorded
/// for the subject it names.
fn readReports(reports: []const u8, path: []const u8, includes: usize, roles: []const Role, row: []Found) !?[]const u8 {
    var lines = std.mem.splitScalar(u8, reports, '\n');
    while (lines.next()) |line| {
        const at = std.mem.indexOf(u8, line, "error: ") orelse continue;
        const message = line[at + "error: ".len ..];
        const location = line[0..at];
        if (std.mem.startsWith(u8, location, path) and location.len > path.len + 1 and location[path.len] == ':') {
            const rest = location[path.len + 1 ..];
            const end = std.mem.indexOfScalar(u8, rest, ':') orelse rest.len;
            const number = std.fmt.parseInt(usize, rest[0..end], 10) catch 0;
            if (number > includes and number <= roles.len) {
                switch (roles[number - 1]) {
                    .symbol => |i| if (row[i].symbol == null and std.mem.indexOf(u8, message, "undeclared") == null) {
                        row[i].symbol = message;
                    },
                    .linkage => |i| if (std.mem.indexOf(u8, message, "static-in-inline") != null) {
                        row[i].internal = true;
                    },
                    .address => |i| row[i].refused = true,
                    .none => {},
                }
                continue;
            }
        }
        return message;
    }
    return null;
}

test "an error at a probe is not a failure to read the declarations" {
    var row = [_]Found{.{}};
    const roles = [_]Role{ .none, .none, .none, .none, .{ .symbol = 0 }, .{ .address = 0 }, .{ .linkage = 0 } };
    const undeclared =
        \\/tmp/p/unit0.c:5:19: error: use of undeclared identifier 'labs'
        \\/tmp/p/unit0.c:6:19: error: use of undeclared identifier 'labs'
        \\1 error generated.
    ;
    try testing.expectEqual(@as(?[]const u8, null), try readReports(undeclared, "/tmp/p/unit0.c", 1, &roles, &row));
    try testing.expectEqual(@as(?[]const u8, null), row[0].symbol);
    try testing.expect(row[0].refused);
    const labelled = "/tmp/p/unit0.c:5:26: error: conflicting asm label\n/tmp/p/unit0.c:7:40: error: static function 'twice' is used in an inline function with external linkage [-Werror,-Wstatic-in-inline]\n";
    try testing.expectEqual(@as(?[]const u8, null), try readReports(labelled, "/tmp/p/unit0.c", 1, &roles, &row));
    try testing.expectEqualStrings("conflicting asm label", row[0].symbol.?);
    try testing.expect(row[0].internal);
    const missing = "/tmp/p/unit0.c:1:10: fatal error: 'nowhere.h' file not found\n";
    try testing.expectEqualStrings("'nowhere.h' file not found", (try readReports(missing, "/tmp/p/unit0.c", 1, &roles, &row)).?);
    const inside = "/x/counter.c:3:1: error: unknown type name 'in'\n";
    try testing.expectEqualStrings("unknown type name 'in'", (try readReports(inside, "/tmp/p/unit0.c", 1, &roles, &row)).?);
}

/// The width and signedness of each enumeration a unit's type trees name,
/// by the spelling that names it.
const Widths = struct {
    known: std.StringHashMapUnmanaged(?Integer) = .empty,
    /// The spellings asked about and not yet answered, each one a type name
    /// a C file can write.
    wanted: std.ArrayList([]const u8) = .empty,

    fn lookup(self: *Widths, arena: std.mem.Allocator, spelled: []const u8) !?Integer {
        if (self.known.get(spelled)) |held| return held;
        if (!nameable(spelled)) return null;
        for (self.wanted.items) |asked| if (std.mem.eql(u8, asked, spelled)) return null;
        try self.wanted.append(arena, spelled);
        return null;
    }

    /// Reads the answers `writeWidths` asked for, as `char[size][signed + 1]`.
    fn read(self: *Widths, arena: std.mem.Allocator, dumps: Dumps) !void {
        for (self.wanted.items, 0..) |spelled, n| {
            const name = try std.fmt.allocPrint(arena, "{s}width_{d}", .{ probe_prefix, n });
            var answer: ?Integer = null;
            if (dumps.sections.get(name)) |lines| {
                for (lines) |line| {
                    if (line.depth != 0 or !std.mem.eql(u8, line.kind, "VarDecl") or std.mem.indexOf(u8, line.flags, " invalid") != null) continue;
                    answer = arrayWidth(line.spelled);
                }
            }
            try self.known.put(arena, spelled, answer);
        }
        self.wanted.clearRetainingCapacity();
    }
};

const Integer = struct { bits: u8, signed: bool };

/// Whether `spelled` is a type name a C file can write: an identifier, or
/// `enum` and one. An enumeration without a name is spelled by where it is.
fn nameable(spelled: []const u8) bool {
    if (spelled.len == 0) return false;
    for (spelled) |c| if (!(std.ascii.isAlphanumeric(c) or c == '_' or c == ' ')) return false;
    return true;
}

/// The integer a width probe's `char[size][signed + 1]` describes.
fn arrayWidth(spelled: []const u8) ?Integer {
    if (!std.mem.startsWith(u8, spelled, "char[")) return null;
    var parts = std.mem.tokenizeAny(u8, spelled["char".len..], "[]");
    const size = std.fmt.parseInt(u8, parts.next() orelse return null, 10) catch return null;
    const sign = std.fmt.parseInt(u8, parts.next() orelse return null, 10) catch return null;
    if (size == 0 or size > 8 or (size & (size - 1)) != 0) return null;
    return .{ .bits = size * 8, .signed = sign == 2 };
}

test "an enumeration's width is read from the array its probe declares" {
    try testing.expectEqual(Integer{ .bits = 64, .signed = false }, arrayWidth("char[8][1]").?);
    try testing.expectEqual(Integer{ .bits = 8, .signed = true }, arrayWidth("char[1][2]").?);
    try testing.expectEqual(@as(?Integer, null), arrayWidth("int[4]"));
    try testing.expect(nameable("enum big"));
    try testing.expect(nameable("size_hint"));
    try testing.expect(!nameable("enum (unnamed at /tmp/x.h:3:1)"));
}

fn writeWidths(arena: std.mem.Allocator, io: std.Io, path: []const u8, unit: Unit, wanted: []const []const u8) !void {
    var text: std.Io.Writer.Allocating = .init(arena);
    const w = &text.writer;
    for (unit.includes) |line| try w.print("{s}\n", .{line});
    for (wanted, 0..) |spelled, n| {
        try w.print("static char {s}width_{d}[sizeof({s})][((({s})-1) < 0) + 1];\n", .{ probe_prefix, n, spelled, spelled });
    }
    try writeFile(io, path, text.written());
}

/// What `cc` says a C name is.
pub const CType = struct {
    /// The type as the C declaration spells it, typedefs and all.
    spelled: []const u8,
    shape: Shape,

    pub const Shape = union(enum) {
        integer: Integer,
        /// An enumeration, whose integer type the C compiler chooses from its
        /// values, or from the type it is declared over; null where that
        /// cannot be learnt, because nothing names the enumeration.
        enumeration: ?Integer,
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
        /// The calling convention C declares beside the default one, such as
        /// `preserve_none`, or null for C's own.
        convention: ?[]const u8,
    };
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

    /// The function the probe of subject `index` in unit `unit` points at,
    /// or null where nothing declared the name, or names something that is
    /// not a function.
    fn function(self: Dumps, arena: std.mem.Allocator, unit: usize, index: usize, widths: *Widths) !?CType {
        const lines = self.sections.get(try probeName(arena, unit, index, "")) orelse return null;
        for (lines) |line| {
            if (line.depth == 0 and std.mem.eql(u8, line.kind, "VarDecl") and std.mem.indexOf(u8, line.flags, " invalid") != null) return null;
        }
        // `cc` prints the probe's own type as a tree at depth 0, after the
        // declaration and its initializer.
        for (lines, 0..) |line, i| {
            if (line.depth != 0 or !line.isType()) continue;
            const pointer = try convert(arena, lines, i, widths);
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

/// The words a function type's line may carry besides its calling
/// convention.
const function_words = [_][]const u8{ "variadic", "noreturn", "const", "volatile", "restrict", "&", "&&", "trailing_return", "cdecl", "exceptionspec_basic_noexcept" };

/// The calling convention a function type's line names other than C's own,
/// `cdecl` on every supported target, or null where it names C's own.
fn conventionOf(line: Line) ?[]const u8 {
    if (line.has("cdecl")) return null;
    var words = std.mem.tokenizeScalar(u8, line.flags, ' ');
    while (words.next()) |word| {
        for (function_words) |known| {
            if (std.mem.eql(u8, word, known)) break;
        } else return word;
    }
    return "an unnamed";
}

/// The canonical type the line at `at` and its children describe: sugar is
/// read through to the type it stands for, and qualifiers are dropped, since
/// neither changes how a value crosses. Each enumeration's width is looked up
/// in `widths` by every spelling naming it.
fn convert(arena: std.mem.Allocator, lines: []const Line, at: usize, widths: *Widths) std.mem.Allocator.Error!CType {
    const line = lines[at];
    const children = try typeChildren(arena, lines, at);
    // A qualified type's one child is the type it qualifies, and a sugared
    // one's last child is the type it stands for.
    if (std.mem.eql(u8, line.kind, "QualType") or line.has("sugar")) {
        if (children.len == 0) return .{ .spelled = line.spelled, .shape = .other };
        var inner = try convert(arena, lines, children[children.len - 1], widths);
        // `typeof (f)` names the probe's expression, not a type C spells.
        if (std.mem.startsWith(u8, line.kind, "TypeOf")) return inner;
        if (inner.shape == .enumeration and inner.shape.enumeration == null and !std.mem.eql(u8, line.kind, "QualType")) {
            inner.shape = .{ .enumeration = try widths.lookup(arena, line.spelled) };
        }
        inner.spelled = line.spelled;
        return inner;
    }
    const shape: CType.Shape = if (std.mem.eql(u8, line.kind, "BuiltinType"))
        builtinShape(line.spelled)
    else if (std.mem.eql(u8, line.kind, "PointerType")) blk: {
        if (children.len == 0) break :blk .other;
        const pointee = try arena.create(CType);
        pointee.* = try convert(arena, lines, children[0], widths);
        break :blk .{ .pointer = pointee };
    } else if (std.mem.eql(u8, line.kind, "FunctionProtoType") or std.mem.eql(u8, line.kind, "FunctionNoProtoType")) blk: {
        if (children.len == 0) break :blk .other;
        const result = try arena.create(CType);
        result.* = try convert(arena, lines, children[0], widths);
        const params = try arena.alloc(CType, children.len - 1);
        for (children[1..], params) |child, *param| param.* = try convert(arena, lines, child, widths);
        break :blk .{ .function = .{
            .result = result,
            .params = params,
            .variadic = line.has("variadic"),
            .prototyped = std.mem.eql(u8, line.kind, "FunctionProtoType"),
            .convention = conventionOf(line),
        } };
    } else if (std.mem.eql(u8, line.kind, "EnumType"))
        .{ .enumeration = try widths.lookup(arena, line.spelled) }
    else if (std.mem.eql(u8, line.kind, "RecordType") or std.mem.endsWith(u8, line.kind, "ArrayType"))
        .object
    else
        .other;
    return .{ .spelled = line.spelled, .shape = shape };
}

/// The shape of a C builtin type on the target, whose C type sizes the
/// target states, with plain `char` signed or not as the target says.
fn builtinShape(name: []const u8) CType.Shape {
    const Entry = struct { []const u8, CType.Shape };
    const target = builtin.target;
    const plain_char_signed = target.cCharSignedness() == .signed;
    const bits = struct {
        fn of(comptime c: std.Target.CType) u8 {
            return @intCast(target.cTypeBitSize(c));
        }
    }.of;
    const table = [_]Entry{
        .{ "char", .{ .integer = .{ .bits = 8, .signed = plain_char_signed } } },
        .{ "signed char", .{ .integer = .{ .bits = 8, .signed = true } } },
        .{ "unsigned char", .{ .integer = .{ .bits = 8, .signed = false } } },
        .{ "short", .{ .integer = .{ .bits = bits(.short), .signed = true } } },
        .{ "unsigned short", .{ .integer = .{ .bits = bits(.ushort), .signed = false } } },
        .{ "int", .{ .integer = .{ .bits = bits(.int), .signed = true } } },
        .{ "unsigned int", .{ .integer = .{ .bits = bits(.uint), .signed = false } } },
        .{ "long", .{ .integer = .{ .bits = bits(.long), .signed = true } } },
        .{ "unsigned long", .{ .integer = .{ .bits = bits(.ulong), .signed = false } } },
        .{ "long long", .{ .integer = .{ .bits = bits(.longlong), .signed = true } } },
        .{ "unsigned long long", .{ .integer = .{ .bits = bits(.ulonglong), .signed = false } } },
        .{ "float", .{ .float = bits(.float) } },
        .{ "double", .{ .float = bits(.double) } },
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
        \\
        \\Dumping linea_probe_0_2:
        \\VarDecl 0x20 <a.c:19:1, col:48> col:30 linea_probe_0_2 'typeof (pn) *const' static cinit
        \\QualType 0x21 'typeof (pn) *const' const
        \\`-PointerType 0x22 'typeof (pn) *'
        \\  `-TypeOfExprType 0x23 'typeof (pn)' sugar
        \\    `-AttributedType 0x24 '__attribute__((preserve_none)) long long (long long)' sugar
        \\      `-FunctionProtoType 0x25 'long long (long long) __attribute__((preserve_none))' preserve_none
        \\        |-BuiltinType 0x26 'long long'
        \\        `-EnumType 0x27 'enum big'
    ;
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const dumps = try Dumps.parse(arena, dump);
    var widths: Widths = .{};
    const column = (try dumps.function(arena, 0, 0, &widths)).?;
    try testing.expectEqualStrings("sqlite3_int64 (sqlite3_stmt *, int)", column.spelled);
    const function = column.shape.function;
    try testing.expectEqualStrings("sqlite3_int64", function.result.spelled);
    try testing.expectEqual(CType.Shape{ .integer = .{ .bits = 64, .signed = true } }, function.result.shape);
    try testing.expectEqual(@as(usize, 2), function.params.len);
    try testing.expectEqual(CType.Shape.object, function.params[0].shape.pointer.shape);
    try testing.expectEqual(CType.Shape{ .integer = .{ .bits = 32, .signed = true } }, function.params[1].shape);
    try testing.expect(!function.variadic);
    try testing.expectEqual(@as(?[]const u8, null), function.convention);
    try testing.expectEqual(@as(?CType, null), try dumps.function(arena, 0, 1, &widths));
    const other = (try dumps.function(arena, 0, 2, &widths)).?.shape.function;
    try testing.expectEqualStrings("preserve_none", other.convention.?);
    try testing.expectEqual(@as(?Integer, null), other.params[0].shape.enumeration);
    try testing.expectEqualStrings("enum big", widths.wanted.items[0]);
}

/// Why a C position disagrees with what lowering passes there.
const Mismatch = union(enum) {
    /// C states no parameters: `f()`.
    unprototyped,
    variadic,
    convention: []const u8,
    arity: struct { c: usize, linea: usize },
    param: struct { index: usize, c: CType, implied: foreign.Value, inner: ?*const Mismatch = null },
    result: struct { c: CType, implied: ?foreign.Value },
};

fn scalarAccepts(scalar: ForeignScalar, c: CType) bool {
    return switch (scalar) {
        .float64 => c.shape == .float and c.shape.float == 64,
        .integer => |integer| switch (c.shape) {
            .integer => |held| held.bits == integer.bits and held.signed == integer.signed,
            .enumeration => |width| if (width) |held| held.bits == integer.bits and held.signed == integer.signed else false,
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
    if (c.convention) |convention| return .{ .convention = convention };
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

    fn nameLabel(self: *Reporter, subject: Subject, message: []const u8) ![]const Label {
        const labels = try self.sink.arena.alloc(Label, 1);
        labels[0] = .{ .file = self.ast.fileOf(self.ast.declName(subject.decl)), .span = self.ast.tokenSpan(self.ast.declName(subject.decl)), .message = message };
        return labels;
    }

    fn declaredBy(self: *Reporter, subject: Subject, shown: []const u8) ![]const []const u8 {
        const a = self.sink.arena;
        return a.dupe([]const u8, &.{try std.fmt.allocPrint(a, "`{s}` is declared by {s}", .{ subject.name, shown })});
    }

    fn unread(self: *Reporter, subject: Subject, reason: []const u8) !void {
        const a = self.sink.arena;
        try self.sink.add(.{
            .severity = .err,
            .code = .t_extern_prototype,
            .message = try std.fmt.allocPrint(a, "the C declarations this root names cannot be read, so `{s}` cannot be held to its prototype: {s}", .{ subject.name, reason }),
            .labels = try self.nameLabel(subject, "held to the prototype its root's C declarations give it"),
            .notes = try a.dupe([]const u8, &.{"correct `headers` or `native` in linea.json, or install the C library whose header it names"}),
        });
    }

    fn macro(self: *Reporter, subject: Subject) !void {
        const a = self.sink.arena;
        try self.sink.add(.{
            .severity = .err,
            .code = .t_extern_prototype,
            .message = try std.fmt.allocPrint(a, "`{s}` is a macro in C, so C code calling it reaches what the macro expands to, not the symbol this declaration names", .{subject.name}),
            .labels = try self.nameLabel(subject, "a macro has no prototype to hold this to"),
            .notes = try a.dupe([]const u8, &.{"declare the function the macro expands to, or call it through a C function in `native`"}),
        });
    }

    fn undeclared(self: *Reporter, subject: Subject, named: usize) !void {
        const a = self.sink.arena;
        const why = if (named == 0)
            "linea.json names no C declarations for this root"
        else
            "neither the `headers` nor the `native` sources its linea.json names declare it";
        try self.sink.add(.{
            .severity = .err,
            .code = .t_extern_prototype,
            .message = try std.fmt.allocPrint(a, "no C declaration of `{s}` is in reach: {s}", .{ subject.name, why }),
            .labels = try self.nameLabel(subject, "held to the prototype C gives it, and C gives it none"),
            .notes = try a.dupe([]const u8, &.{"name the header that declares it under \"headers\" in linea.json, such as \"stdlib.h\", or build the C that defines it under \"native\""}),
        });
    }

    fn internal(self: *Reporter, subject: Subject, shown: []const u8) !void {
        const a = self.sink.arena;
        try self.sink.add(.{
            .severity = .err,
            .code = .t_extern_prototype,
            .message = try std.fmt.allocPrint(a, "C declares `{s}` `static`, so it has no symbol this declaration could link against", .{subject.name}),
            .labels = try self.nameLabel(subject, "C gives this function no symbol"),
            .remarks = try self.declaredBy(subject, shown),
            .notes = try a.dupe([]const u8, &.{"call it through a C function that is not `static`, built under \"native\""}),
        });
    }

    fn symbol(self: *Reporter, subject: Subject, shown: []const u8, reason: []const u8) !void {
        const a = self.sink.arena;
        const remarks = try a.dupe([]const u8, &.{
            (try self.declaredBy(subject, shown))[0],
            try std.fmt.allocPrint(a, "`cc` says: {s}", .{reason}),
        });
        try self.sink.add(.{
            .severity = .err,
            .code = .t_extern_prototype,
            .message = try std.fmt.allocPrint(a, "C code calling `{s}` reaches another symbol than `{s}`, which this declaration links against", .{ subject.name, subject.name }),
            .labels = try self.nameLabel(subject, "C's declaration gives this function another symbol"),
            .remarks = remarks,
            .notes = try a.dupe([]const u8, &.{"call it through a C function with a plain symbol, built under \"native\""}),
        });
    }

    /// Reports where C's prototype `c` disagrees with the subject, and
    /// answers whether it did.
    fn compare(self: *Reporter, subject: Subject, c: CType, shown: []const u8) !bool {
        const function = c.shape.function;
        const mismatch = try functionMismatch(self.arena, subject.implied, function) orelse return false;
        const a = self.sink.arena;
        const found = try rendered(a, c.spelled, subject.name);
        const implied = try impliedText(a, subject, function);
        const params = self.ast.declParams(subject.decl);
        const file = self.ast.fileOf(self.ast.declName(subject.decl));
        var span = self.ast.tokenSpan(self.ast.declName(subject.decl));
        var label: []const u8 = "";
        var help: []const u8 = "";
        switch (mismatch) {
            .unprototyped => {
                label = "C's declaration lists no parameters";
                help = "declare the function with its parameters in C, as a prototype";
            },
            .convention => |convention| {
                label = try std.fmt.allocPrint(a, "C declares it with the `{s}` calling convention, which is not C's own", .{convention});
                help = "call it through a C function with C's own calling convention, built under \"native\"";
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
                span = self.ast.writtenWholeSpan(params[at.index].written);
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
                const returns = self.ast.declReturnRef(subject.decl);
                if (returns.wasWritten()) span = self.ast.writtenWholeSpan(returns);
                label = try std.fmt.allocPrint(a, "C answers `{s}`", .{at.c.spelled});
                help = try resultHelp(a, at.implied, at.c, subject.implied.errno);
            },
        }
        const labels = try a.alloc(Label, 1);
        labels[0] = .{ .file = file, .span = span, .message = label };
        const verb = if (subject.exported) "this export defines it as" else "this declaration calls it as";
        try self.sink.add(.{
            .severity = .err,
            .code = .t_extern_prototype,
            .message = try std.fmt.allocPrint(a, "C declares `{s}`, and {s} `{s}`", .{ found, verb, implied }),
            .labels = labels,
            .remarks = try self.declaredBy(subject, shown),
            .notes = try a.dupe([]const u8, &.{help}),
        });
        return true;
    }
};

fn plural(n: usize) []const u8 {
    return if (n == 1) "" else "s";
}

/// `a` or `an` before `word`, by its first letter.
fn article(word: []const u8) []const u8 {
    if (word.len > 0 and std.mem.indexOfScalar(u8, "aeiouAEIOU", word[0]) != null) return "an";
    return "a";
}

fn innerHelp(a: std.mem.Allocator, mismatch: Mismatch) ![]const u8 {
    return switch (mismatch) {
        .unprototyped => "C's function type lists no parameters",
        .convention => |convention| try std.fmt.allocPrint(a, "C calls it with the `{s}` calling convention, which a callback does not take", .{convention}),
        .variadic => "C passes a variable list of arguments, which a callback cannot take",
        .arity => |counts| try std.fmt.allocPrint(a, "take one parameter for each of the {d} C passes, the context first", .{counts.c}),
        .param => |at| if (at.inner) |inner| innerHelp(a, inner.*) else try std.fmt.allocPrint(a, "C passes `{s}` as parameter {d}: {s}", .{ at.c.spelled, at.index + 1, try positionHelp(a, at.implied, at.c, "that parameter") }),
        .result => |at| resultHelp(a, at.implied, at.c, false),
    };
}

/// The Linea type a C scalar crosses as, or null for one none does.
fn lineaName(c: CType) ?[]const u8 {
    const integer: Integer = switch (c.shape) {
        .integer => |held| held,
        .enumeration => |width| width orelse return null,
        .float => |bits| return if (bits == 64) "Float64" else null,
        .pointer => return "UInt64",
        else => return null,
    };
    return switch (integer.bits) {
        8 => if (integer.signed) "Int8" else "UInt8",
        16 => if (integer.signed) "Int16" else "UInt16",
        32 => if (integer.signed) "Int32" else "UInt32",
        64 => if (integer.signed) "Int64" else "UInt64",
        else => null,
    };
}

/// Why no Linea type crosses as C's `c`, or null where one does.
fn untranslatable(a: std.mem.Allocator, c: CType) !?[]const u8 {
    return switch (c.shape) {
        .boolean => "C's `bool` has no Linea type that crosses: call it through a C function, built under \"native\", that takes an integer",
        .object => "C takes a structure by value, which no Linea type crosses as: call it through a C function, built under \"native\", that takes its address",
        .enumeration => |width| if (width == null) try std.fmt.allocPrint(a, "C's `{s}` is an enumeration nothing names, so its width cannot be learnt: call it through a C function, built under \"native\", that takes an integer", .{c.spelled}) else null,
        .void, .function, .other => try std.fmt.allocPrint(a, "C's `{s}` has no Linea type that crosses", .{c.spelled}),
        .float => |bits| if (bits != 64) try std.fmt.allocPrint(a, "C's `{s}` has no Linea type that crosses", .{c.spelled}) else null,
        else => null,
    };
}

/// The edit that makes a parameter written as `implied` take C's `c`. `name`
/// is how the help names the parameter: its name in backticks, or a phrase.
fn positionHelp(a: std.mem.Allocator, implied: foreign.Value, c: CType, name: []const u8) ![]const u8 {
    if (try untranslatable(a, c)) |why| return why;
    switch (implied) {
        .context => return "a callback's context crosses as C's `void *`: declare C's parameter `void *`",
        .callback => return "C takes a value here, not a function to call back",
        .address_of => |scalar| switch (c.shape) {
            .pointer => |pointee| {
                if (pointee.shape == .void or pointee.shape == .object or pointee.shape == .other)
                    return try std.fmt.allocPrint(a, "C takes the object's own address, which a plain parameter passes: drop `inout` from {s}", .{name});
                if (try untranslatable(a, pointee.*)) |why| return why;
                const held = lineaName(pointee.*).?;
                return try std.fmt.allocPrint(a, "C writes {s} `{s}` through the address: declare {s} as an `inout` `{s}`, or a newtype over it", .{ article(pointee.spelled), pointee.spelled, name, held });
            },
            else => {
                if (scalarAccepts(scalar, c)) return try std.fmt.allocPrint(a, "C takes the value itself: drop `inout` from {s}", .{name});
                const held = lineaName(c).?;
                return try std.fmt.allocPrint(a, "C takes the value itself: declare {s} as `{s}`, or a newtype over it, without `inout`", .{ name, held });
            },
        },
        .scalar => |scalar| switch (c.shape) {
            .pointer => |pointee| {
                if (scalarAccepts(scalar, pointee.*)) return try std.fmt.allocPrint(a, "C takes `{s}`, the address of a place it reads or writes: make {s} `inout`, which passes its place's address", .{ c.spelled, name });
                if (pointee.shape != .pointer) if (lineaName(pointee.*)) |held| {
                    return try std.fmt.allocPrint(a, "C takes `{s}`, the address of a place it reads or writes: declare {s} as an `inout` `{s}`, which passes its place's address", .{ c.spelled, name, held });
                };
                return try std.fmt.allocPrint(a, "C takes an address: declare {s} as `UInt64`, or as a handle or `std.ffi` view over one", .{name});
            },
            else => {
                const held = lineaName(c).?;
                return try std.fmt.allocPrint(a, "declare {s} as `{s}`, or a newtype over it, the Linea type of C's `{s}`", .{ name, held, c.spelled });
            },
        },
    }
}

fn resultHelp(a: std.mem.Allocator, implied: ?foreign.Value, c: CType, errno: bool) ![]const u8 {
    if (c.shape == .void) return "C answers nothing: drop the result";
    if (try untranslatable(a, c)) |why| return why;
    const held = lineaName(c).?;
    if (errno) return try std.fmt.allocPrint(a, "declare the result `ffi.Errno[{s}]`, the Linea type of C's `{s}` beside `errno`", .{ held, c.spelled });
    if (implied == null) return try std.fmt.allocPrint(a, "declare the result `-> {s}`, the Linea type of C's `{s}`", .{ held, c.spelled });
    return try std.fmt.allocPrint(a, "declare the result `{s}`, or a newtype over it, the Linea type of C's `{s}`", .{ held, c.spelled });
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
fn impliedText(a: std.mem.Allocator, subject: Subject, c: CType.Function) ![]const u8 {
    var text: std.Io.Writer.Allocating = .init(a);
    const w = &text.writer;
    const result = if (subject.implied.result) |value|
        if (try valueMismatch(a, value, c.result.*) == null) c.result.spelled else try impliedSpelling(a, value)
    else
        "void";
    try w.writeAll(result);
    if (result.len == 0 or result[result.len - 1] != '*') try w.writeAll(" ");
    try w.print("{s}(", .{subject.name});
    if (subject.implied.params.len == 0) try w.writeAll("void");
    for (subject.implied.params, 0..) |value, i| {
        if (i > 0) try w.writeAll(", ");
        const agrees = i < c.params.len and c.prototyped and try valueMismatch(a, value, c.params[i]) == null;
        try w.writeAll(if (agrees) c.params[i].spelled else try impliedSpelling(a, value));
    }
    try w.writeAll(")");
    return text.written();
}
