//! [T-ExternPrototype]: every `extern` a root declares for a C function, and
//! every `export` its C declares, is held to the prototype the root's own C
//! declarations give that function.
//!
//! The C declarations are the sources the root's manifest builds under
//! `native` and the headers it names under `headers`. For each of them two C
//! files are written that include it. The first takes each function's
//! address and refers to it from an inline function of external linkage:
//!
//! ```c
//! #include <sqlite3.h>
//! static __typeof__(sqlite3_close_v2) *const linea_probe_0_3 = &sqlite3_close_v2;
//! inline void linea_probe_0_3_linkage(void) { (void)&sqlite3_close_v2; }
//! ```
//!
//! `cc` refuses the second line where the function is `static`, and prints
//! each pointer's type tree with every typedef resolved. The compiler compares
//! that tree, position by position, with what lowering passes there
//! (`foreign.externPrototype`), for every C declaration of the root that
//! declares the function. The comparison is by representation, not by C's
//! type identity: C's `long long` and `long` are both 64-bit signed integers,
//! and a handle's address is any pointer.
//!
//! The second file, compiled to LLVM IR, keeps each declared function's
//! address in a used global:
//!
//! ```c
//! void *const linea_symbol_0_3 __attribute__((used)) = (void *)&sqlite3_close_v2;
//! ```
//!
//! Its IR names the symbol C code calling the function reaches, which an
//! `__asm__` label or `overloadable` changes, and the `extern` links against
//! that symbol. The IR declaration of the function also says how C passes an
//! enumeration: its width, and for one narrower than 32 bits, whether it is
//! sign- or zero-extended. Symbols in the runtime's namespace are held to the
//! runtime's own table instead ([T-ExternRuntime]), and so are the storage
//! primitives lowering replaces.

const std = @import("std");
const builtin = @import("builtin");
const testing = std.testing;
const loader = @import("loader.zig");
const toolchain = @import("toolchain.zig");
const runtime_symbols = @import("../support/runtime_symbols.zig");
const symbol_names = @import("../support/symbol.zig");
const article = @import("../support/article.zig");
const foreign = @import("../sema/foreign.zig");
const ForeignScalar = @import("../sema/types.zig").ForeignScalar;
const ForeignSymbol = @import("../backend/mlir.zig").ForeignSymbol;
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
/// The prefix of the globals whose IR names each function's symbol.
const symbol_prefix = "linea_symbol_";

/// Holds every `extern` and `export` of a program's roots to its C
/// prototype, reporting each that disagrees into `sink`, and answers the
/// symbol C gives each `extern` whose C declaration links it under another
/// symbol than its name, allocated in `gpa`, for the backend to call it by.
/// Reads the declarations the checker settled, so it runs once the semantic
/// passes accepted the program.
pub fn check(gpa: std.mem.Allocator, io: std.Io, semantics: *const loader.Semantics, sink: *Sink, opts: Options) ![]const ForeignSymbol {
    const expanded = &semantics.expanded;
    const program = expanded.source;
    if (program.roots.len == 0) return &.{};
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
                if (semantics.typing.lowers(d)) continue;
            }
            const implied = try foreign.externPrototype(arena, &semantics.typing, d) orelse continue;
            try by_root[module.root.index()].append(arena, .{ .decl = d, .name = name, .implied = implied, .exported = exported });
        }
    }
    var resolved: std.ArrayList(Resolved) = .empty;
    var reporter: Reporter = .{ .arena = arena, .sink = sink, .ast = &expanded.ast };
    for (by_root, program.roots) |subjects, facts| {
        if (subjects.items.len == 0) continue;
        try checkRoot(arena, io, facts, subjects.items, &reporter, opts, &resolved);
    }

    // Every `extern` of one name is one function ([T-ExternAgreement]), so
    // its roots' C must give it one symbol; and one symbol is one function,
    // so every `extern` reaching it must be declared alike.
    var symbols: std.ArrayList(ForeignSymbol) = .empty;
    var by_name: std.StringHashMapUnmanaged(Resolved) = .empty;
    var by_symbol: std.StringHashMapUnmanaged(Resolved) = .empty;
    for (resolved.items) |held| {
        const named = try by_name.getOrPut(arena, held.subject.name);
        if (named.found_existing) {
            if (!std.mem.eql(u8, named.value_ptr.symbol, held.symbol)) try reporter.sharedName(held.subject, named.value_ptr.symbol, held.symbol);
            continue;
        }
        named.value_ptr.* = held;
        const reached = try by_symbol.getOrPut(arena, held.symbol);
        if (reached.found_existing) {
            if (!samePrototype(reached.value_ptr.subject.implied, held.subject.implied)) {
                try reporter.sharedSymbol(held.subject, held.symbol, reached.value_ptr.subject.name);
            }
        } else reached.value_ptr.* = held;
        if (!std.mem.eql(u8, held.symbol, held.subject.name)) try symbols.append(arena, .{ .name = held.subject.name, .symbol = held.symbol });
    }
    const out = try gpa.alloc(ForeignSymbol, symbols.items.len);
    var made: usize = 0;
    errdefer {
        for (out[0..made]) |held| {
            gpa.free(held.name);
            gpa.free(held.symbol);
        }
        gpa.free(out);
    }
    for (symbols.items, out) |held, *copy| {
        const name = try gpa.dupe(u8, held.name);
        errdefer gpa.free(name);
        copy.* = .{ .name = name, .symbol = try gpa.dupe(u8, held.symbol) };
        made += 1;
    }
    return out;
}

/// An `extern` the check accepted, and the symbol it links against.
const Resolved = struct {
    subject: Subject,
    symbol: []const u8,
};

/// Whether two declarations imply one prototype.
fn samePrototype(a: foreign.Prototype, b: foreign.Prototype) bool {
    if (a.params.len != b.params.len) return false;
    for (a.params, b.params) |x, y| if (!sameValue(x, y)) return false;
    if ((a.result == null) != (b.result == null)) return false;
    if (a.result) |r| if (!sameValue(r, b.result.?)) return false;
    return true;
}

fn sameValue(a: foreign.Value, b: foreign.Value) bool {
    if (std.meta.activeTag(a) != std.meta.activeTag(b)) return false;
    return switch (a) {
        .scalar => |x| std.meta.eql(x, b.scalar),
        .address_of => |x| std.meta.eql(x, b.address_of),
        .context => true,
        .callback => |x| samePrototype(x.*, b.callback.*),
    };
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
    /// Whether C declares the function `static`, which leaves it no symbol.
    internal: bool = false,
    /// Whether `cc` refused the probe taking the function's address, as it
    /// does where nothing declares the name.
    refused: bool = false,
    /// What the IR says of the function: the symbol C calls it by, as LLVM
    /// spells a symbol, and its signature.
    linked: ?Linked = null,
};

fn checkRoot(arena: std.mem.Allocator, io: std.Io, facts: RootFacts, subjects: []const Subject, reporter: *Reporter, opts: Options, resolved: *std.ArrayList(Resolved)) !void {
    var units: std.ArrayList(Unit) = .empty;
    if (facts.headers.len > 0) {
        const lines = try arena.alloc([]const u8, facts.headers.len);
        for (facts.headers, lines) |header, *line| line.* = try std.fmt.allocPrint(arena, "#include <{s}>", .{header});
        const shown = if (facts.headers.len == 1)
            try std.fmt.allocPrint(arena, "`{s}`", .{facts.headers[0]})
        else
            try std.fmt.allocPrint(arena, "the {d} headers " ++ loader.manifest_name ++ " names", .{facts.headers.len});
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

    var exports = false;
    for (subjects) |subject| exports = exports or subject.exported;

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
        // A probe `cc` refused declares nothing, whatever recovery left in
        // its tree.
        for (row, 0..) |*seen, i| {
            seen.macro = dumps.sections.contains(try probeName(arena, k, i, "_macro"));
            if (!seen.refused) seen.ctype = try dumps.function(arena, k, i);
        }

        // The IR of every function the unit declares names its symbol and
        // how C passes each of its values.
        const ir_path = try std.fmt.allocPrint(arena, "{s}/unit{d}-symbols.c", .{ dir, k });
        const ir_out = try std.fmt.allocPrint(arena, "{s}/unit{d}-symbols.ll", .{ dir, k });
        if (!try writeSymbols(arena, io, ir_path, k, unit, subjects, row) and !exports) continue;
        const lowered = try toolchain.lowerC(arena, io, include_dir, ir_path, ir_out) orelse {
            return reporter.unread(subjects[0], "`cc` is not installed");
        };
        const ir = switch (lowered) {
            .ir => |text| text,
            .refused => |reports| return reporter.unread(subjects[0], firstError(reports) orelse "`cc` could not compile the declarations"),
        };
        const index = try IrIndex.of(arena, ir);
        // C may call an export under another name, through a label; every
        // IR declaration of the export's symbol is held to the export. A
        // unit that declares it by its name is compared by its prototype,
        // which says more.
        for (subjects, row) |subject, seen| {
            if (!subject.exported or seen.ctype != null) continue;
            for (try index.signaturesNamed(arena, subject.name)) |signature| {
                if (signatureAgrees(subject.implied, signature)) continue;
                if (try reporter.called(subject, unit.shown, signature)) break;
            }
        }
        for (row, 0..) |*seen, i| {
            if (seen.ctype == null or seen.macro) continue;
            seen.linked = try index.linkedOf(arena, k, i);
            if (seen.linked) |linked| if (linked.signature) |signature| {
                widenEnumerations(&seen.ctype.?, signature);
            };
        }
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
        const symbol = try heldAcross(reporter, subject, units.items, found, subjects.len, i) orelse continue;
        try resolved.append(arena, .{ .subject = subject, .symbol = symbol });
    }
}

/// Holds subject `i` to every C declaration of it the units give, since any
/// of them may be the one C code calling it was built with, and an `extern`
/// to the one symbol all of them must give it. Answers that symbol, or null
/// once it reported a disagreement, and for an export, which links against
/// nothing.
fn heldAcross(reporter: *Reporter, subject: Subject, units: []const Unit, found: []const Found, per_unit: usize, i: usize) !?[]const u8 {
    var symbol: ?struct { name: []const u8, unit: Unit } = null;
    for (units, 0..) |unit, k| {
        const seen = found[k * per_unit + i];
        const ctype = seen.ctype orelse continue;
        if (!subject.exported) {
            if (seen.internal) {
                try reporter.internal(subject, unit.shown);
                return null;
            }
            const linked = seen.linked orelse {
                try reporter.unread(subject, "`cc` names no symbol for it");
                return null;
            };
            if (linked.kind != .function) {
                try reporter.notFunction(subject, unit.shown, linked.kind);
                return null;
            }
            const name = callableSymbol(linked.symbol) orelse {
                try reporter.unnameable(subject, unit.shown, linked.symbol);
                return null;
            };
            // A symbol C names is held to the reservations a written name
            // is: it may not be one the runtime, this compiler's own
            // definitions or LLVM spell.
            if (!std.mem.eql(u8, name, subject.name) and symbol_names.reservedForeign(name)) {
                try reporter.reserved(subject, unit.shown, name);
                return null;
            }
            if (symbol) |earlier| {
                if (!std.mem.eql(u8, earlier.name, name)) {
                    try reporter.symbols(subject, earlier.unit.shown, earlier.name, unit.shown, name);
                    return null;
                }
            } else symbol = .{ .name = name, .unit = unit };
        }
        if (try reporter.compare(subject, ctype, unit.shown)) return null;
    }
    return if (symbol) |held| held.name else null;
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
    /// The line referring to the subject from an inline function of external
    /// linkage.
    linkage: usize,
    /// A line taking the subject's address, which is refused where nothing
    /// declares it.
    address: usize,
};

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
        try w.print("static __typeof__({s}) *const {s} = &{s};\n", .{ name, try probeName(arena, unit_index, i, ""), name });
        try roles.append(arena, .{ .address = i });
        if (!subject.exported) {
            try w.print("inline void {s}(void) {{ (void)&{s}; }}\n", .{ try probeName(arena, unit_index, i, "_linkage"), name });
            try roles.append(arena, .{ .linkage = i });
        }
    }
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = text.written() });
    return roles.items;
}

/// Writes the file whose IR names the symbol of every function the unit
/// declares, and answers whether it names any.
fn writeSymbols(arena: std.mem.Allocator, io: std.Io, path: []const u8, unit_index: usize, unit: Unit, subjects: []const Subject, row: []const Found) !bool {
    var text: std.Io.Writer.Allocating = .init(arena);
    const w = &text.writer;
    for (unit.includes) |line| try w.print("{s}\n", .{line});
    var any = false;
    for (subjects, row, 0..) |subject, seen, i| {
        if (seen.ctype == null or seen.macro) continue;
        try w.print("void *const {s}{d}_{d} __attribute__((used)) = (void *)&{s};\n", .{ symbol_prefix, unit_index, i, subject.name });
        any = true;
    }
    // Written even with no probe, where the root exports: the IR of what
    // the unit's own code calls is what an export is held to.
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = text.written() });
    return any;
}

/// An error `cc` reported on one line: where, and what it says.
const Reported = struct {
    /// Everything before the message: the file, line and column, and for a
    /// fatal error the word `fatal`.
    location: []const u8,
    message: []const u8,

    /// The error `line` reports, or null where it reports none.
    fn of(line: []const u8) ?Reported {
        const at = std.mem.indexOf(u8, line, "error: ") orelse return null;
        return .{ .location = line[0..at], .message = line[at + "error: ".len ..] };
    }
};

/// The first error `cc` reported, without its location.
fn firstError(reports: []const u8) ?[]const u8 {
    var lines = std.mem.splitScalar(u8, reports, '\n');
    while (lines.next()) |line| if (Reported.of(line)) |reported| return reported.message;
    return null;
}

/// Records what `cc`'s errors at the probe lines say into `row`, and answers
/// the first error outside the probes, without its location, or null where
/// there is none. An error at a probe taking an address means nothing
/// declares the name; one at a linkage probe that the function is `static`.
fn readReports(reports: []const u8, path: []const u8, includes: usize, roles: []const Role, row: []Found) !?[]const u8 {
    var lines = std.mem.splitScalar(u8, reports, '\n');
    while (lines.next()) |line| {
        const reported = Reported.of(line) orelse continue;
        const message = reported.message;
        const location = reported.location;
        if (std.mem.startsWith(u8, location, path) and location.len > path.len + 1 and location[path.len] == ':') {
            const rest = location[path.len + 1 ..];
            const end = std.mem.indexOfScalar(u8, rest, ':') orelse rest.len;
            const number = std.fmt.parseInt(usize, rest[0..end], 10) catch 0;
            if (number > includes and number <= roles.len) {
                switch (roles[number - 1]) {
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
    const roles = [_]Role{ .none, .none, .none, .none, .{ .address = 0 }, .{ .linkage = 0 } };
    const undeclared =
        \\/tmp/p/unit0.c:5:19: error: use of undeclared identifier 'labs'
        \\/tmp/p/unit0.c:6:19: error: use of undeclared identifier 'labs'
        \\1 error generated.
    ;
    try testing.expectEqual(@as(?[]const u8, null), try readReports(undeclared, "/tmp/p/unit0.c", 1, &roles, &row));
    try testing.expect(row[0].refused);
    const internal = "/tmp/p/unit0.c:6:40: error: static function 'twice' is used in an inline function with external linkage [-Werror,-Wstatic-in-inline]\n";
    try testing.expectEqual(@as(?[]const u8, null), try readReports(internal, "/tmp/p/unit0.c", 1, &roles, &row));
    try testing.expect(row[0].internal);
    const missing = "/tmp/p/unit0.c:1:10: fatal error: 'nowhere.h' file not found\n";
    try testing.expectEqualStrings("'nowhere.h' file not found", (try readReports(missing, "/tmp/p/unit0.c", 1, &roles, &row)).?);
    const inside = "/x/counter.c:3:1: error: unknown type name 'in'\n";
    try testing.expectEqualStrings("unknown type name 'in'", (try readReports(inside, "/tmp/p/unit0.c", 1, &roles, &row)).?);
}

/// What the IR says of one function: the symbol C calls it by, as the IR
/// spells it, what the IR makes of that symbol, and the function's signature
/// where the IR declares or defines it.
const Linked = struct {
    symbol: []const u8,
    kind: Kind,
    signature: ?Signature,

    /// A symbol is held to a prototype only where the IR declares or
    /// defines it as a function. Every other kind of global, whatever the C
    /// declaration says, names code or data no prototype describes.
    const Kind = enum {
        function,
        /// An `alias` of another symbol.
        alias,
        /// An `ifunc`, resolved to some function when the program loads.
        ifunc,
        /// A variable, or anything else that is not a function.
        other,
    };
};

/// An IR signature: how C passes each parameter and the result.
const Signature = struct {
    result: Passed,
    params: []const Passed,
};

/// How the IR passes one value: an integer of `bits`, extended by sign or by
/// zero where it is narrower than 32 bits, or something else.
const Passed = struct {
    bits: ?u8,
    extension: ?bool = null,
    kind: Kind = .other,

    const Kind = enum { integer, float, pointer, void, other };
};

/// What one unit's IR says of its globals and functions, read in one pass
/// and asked once per subject.
const IrIndex = struct {
    /// The IR name each `linea_symbol_K_I` global points at, or null where
    /// its line points at none, by the global's name.
    targets: std.StringHashMapUnmanaged(?[]const u8) = .empty,
    /// What the last global line of each IR name makes of it.
    kinds: std.StringHashMapUnmanaged(Linked.Kind) = .empty,
    /// The last `declare` or `define` line of each IR name.
    functions: std.StringHashMapUnmanaged(Declared) = .empty,
    /// Every `declare` or `define` line, in order, by the symbol an `extern`
    /// is emitted under to reach it.
    callable: std.StringHashMapUnmanaged(std.ArrayList(Declared)) = .empty,

    /// A `declare` or `define` line, and where its function's name begins.
    const Declared = struct { line: []const u8, at: usize };

    fn of(arena: std.mem.Allocator, ir: []const u8) !IrIndex {
        var index: IrIndex = .{};
        var lines = std.mem.splitScalar(u8, ir, '\n');
        while (lines.next()) |line| {
            if (std.mem.startsWith(u8, line, "@")) {
                const name = irName(line) orelse continue;
                if (std.mem.startsWith(u8, line[1..], symbol_prefix) and std.mem.startsWith(u8, line[1 + name.len ..], " = ")) {
                    const target = try index.targets.getOrPut(arena, name);
                    if (!target.found_existing) target.value_ptr.* = if (std.mem.indexOf(u8, line, " ptr @")) |at| irName(line[at + " ptr ".len ..]) else null;
                }
                try index.kinds.put(arena, name, if (std.mem.indexOf(u8, line, " alias ") != null)
                    .alias
                else if (std.mem.indexOf(u8, line, " ifunc ") != null)
                    .ifunc
                else
                    .other);
                continue;
            }
            if (!std.mem.startsWith(u8, line, "declare ") and !std.mem.startsWith(u8, line, "define ")) continue;
            const at = std.mem.indexOf(u8, line, " @") orelse continue;
            const name = irName(line[at + 1 ..]) orelse continue;
            const declared: Declared = .{ .line = line, .at = at };
            try index.functions.put(arena, name, declared);
            const symbol = callableSymbol(name) orelse continue;
            const listed = try index.callable.getOrPut(arena, symbol);
            if (!listed.found_existing) listed.value_ptr.* = .empty;
            try listed.value_ptr.append(arena, declared);
        }
        return index;
    }

    /// The symbol global `linea_symbol_K_I` holds, its signature and what
    /// the IR makes of it, or null where the IR holds no such global.
    fn linkedOf(self: *const IrIndex, arena: std.mem.Allocator, unit: usize, index: usize) !?Linked {
        const global = try std.fmt.allocPrint(arena, "{s}{d}_{d}", .{ symbol_prefix, unit, index });
        const named = (self.targets.get(global) orelse return null) orelse return null;
        const signature = if (self.functions.get(named)) |declared| signatureOf(arena, declared.line, declared.at) catch null else null;
        // A global of the symbol's name is never a function, so it decides; a
        // function is one only where a `declare` or `define` gives a signature.
        const kind = self.kinds.get(named) orelse if (signature != null) Linked.Kind.function else .other;
        return .{ .symbol = named, .kind = kind, .signature = signature };
    }

    /// Every signature the IR declares or defines a function by whose symbol
    /// is `name` once emitted, whatever C calls the function.
    fn signaturesNamed(self: *const IrIndex, arena: std.mem.Allocator, name: []const u8) ![]const Signature {
        var out: std.ArrayList(Signature) = .empty;
        const declared = self.callable.get(name) orelse return &.{};
        for (declared.items) |held| {
            if (try signatureOf(arena, held.line, held.at)) |signature| try out.append(arena, signature);
        }
        return out.items;
    }
};

/// The IR name `text` begins with, `@name` or `@"name"`, as written between
/// the quotes, or null where it begins with none.
fn irName(text: []const u8) ?[]const u8 {
    if (text.len < 2 or text[0] != '@') return null;
    if (text[1] == '"') {
        const end = std.mem.indexOfScalarPos(u8, text, 2, '"') orelse return null;
        return text[2..end];
    }
    var end: usize = 1;
    while (end < text.len and (std.ascii.isAlphanumeric(text[end]) or text[end] == '_' or text[end] == '.' or text[end] == '$' or text[end] == '-')) end += 1;
    return text[1..end];
}

/// The signature on a `declare` or `define` line whose function's name
/// begins at `at`.
fn signatureOf(arena: std.mem.Allocator, line: []const u8, at: usize) !?Signature {
    const open = std.mem.indexOfScalarPos(u8, line, at, '(') orelse return null;
    var params: std.ArrayList(Passed) = .empty;
    // A comma at depth one, directly inside the parameter list, ends a
    // parameter, and so does the bracket that closes the list.
    var depth: usize = 0;
    var start = open + 1;
    var close = open;
    while (close < line.len) : (close += 1) {
        switch (line[close]) {
            '(', '[', '{', '<' => depth += 1,
            ')', ']', '}', '>' => {
                depth -= 1;
                if (depth == 0) break;
            },
            ',' => if (depth == 1) {
                try appendPassed(arena, &params, line[start..close]);
                start = close + 1;
            },
            else => {},
        }
    }
    if (close >= line.len) return null;
    try appendPassed(arena, &params, line[start..close]);
    const head = line[std.mem.indexOfScalar(u8, line, ' ').? + 1 .. at];
    return .{ .result = passedOf(head), .params = params.items };
}

/// Appends how the IR passes the parameter `piece` spells, where it spells
/// one.
fn appendPassed(arena: std.mem.Allocator, params: *std.ArrayList(Passed), piece: []const u8) !void {
    const trimmed = std.mem.trim(u8, piece, " ");
    if (trimmed.len > 0) try params.append(arena, passedOf(trimmed));
}

/// How the IR passes a value whose type and attributes `text` holds.
fn passedOf(text: []const u8) Passed {
    var passed: Passed = .{ .bits = null };
    var words = std.mem.tokenizeScalar(u8, text, ' ');
    while (words.next()) |word| {
        if (std.mem.eql(u8, word, "signext")) passed.extension = true;
        if (std.mem.eql(u8, word, "zeroext")) passed.extension = false;
        if (word.len > 1 and word[0] == 'i' and std.ascii.isDigit(word[1])) {
            passed.bits = std.fmt.parseInt(u8, word[1..], 10) catch null;
            passed.kind = .integer;
        }
        if (std.mem.eql(u8, word, "double")) {
            passed.kind = .float;
            passed.bits = 64;
        }
        if (std.mem.eql(u8, word, "float")) {
            passed.kind = .float;
            passed.bits = 32;
        }
        if (std.mem.eql(u8, word, "ptr")) passed.kind = .pointer;
        if (std.mem.eql(u8, word, "void")) passed.kind = .void;
    }
    return passed;
}

/// Whether the IR passes a value as `implied` crosses: an integer of its
/// width, extended by its signedness where the IR extends it, a `double` for
/// a `Float64`, and an address for an `inout` place, a context or a callback,
/// or for a `UInt64`, which an address crosses as.
fn passedAgrees(implied: foreign.Value, passed: Passed) bool {
    return switch (implied) {
        .scalar => |scalar| switch (scalar) {
            .float64 => passed.kind == .float and passed.bits == 64,
            .integer => |integer| switch (passed.kind) {
                .integer => passed.bits == integer.bits and (passed.extension == null or passed.extension.? == integer.signed),
                .pointer => integer.bits == 64 and !integer.signed,
                else => false,
            },
        },
        .address_of, .context, .callback => passed.kind == .pointer,
    };
}

/// Whether the IR signature C calls a function by agrees with the prototype
/// a Linea declaration of it implies.
fn signatureAgrees(implied: foreign.Prototype, signature: Signature) bool {
    if (implied.params.len != signature.params.len) return false;
    for (implied.params, signature.params) |value, passed| if (!passedAgrees(value, passed)) return false;
    if (implied.result) |value| return passedAgrees(value, signature.result);
    return signature.result.kind == .void;
}

test "a signature C calls an export by is compared whatever C names it" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const ir = if (builtin.target.os.tag.isDarwin())
        "declare i64 @\"\\01_scale\"(i64 noundef) #1\n"
    else
        "declare i64 @scale(i64 noundef) #1\n";
    const index = try IrIndex.of(arena, ir);
    const found = try index.signaturesNamed(arena, "scale");
    try testing.expectEqual(@as(usize, 1), found.len);
    const narrow: foreign.Prototype = .{ .params = &.{.{ .scalar = .{ .integer = .{ .bits = 32, .signed = true } } }}, .result = .{ .scalar = .{ .integer = .{ .bits = 32, .signed = true } } } };
    try testing.expect(!signatureAgrees(narrow, found[0]));
    const wide: foreign.Prototype = .{ .params = &.{.{ .scalar = .{ .integer = .{ .bits = 64, .signed = true } } }}, .result = .{ .scalar = .{ .integer = .{ .bits = 64, .signed = true } } } };
    try testing.expect(signatureAgrees(wide, found[0]));
}

test "the IR names the symbol C reaches and how it passes each value" {
    const ir =
        \\@linea_symbol_0_0 = constant ptr @"\01_realpath$DARWIN_EXTSN", align 8
        \\@linea_symbol_0_1 = constant ptr @raise_, align 8
        \\declare ptr @"\01_realpath$DARWIN_EXTSN"(ptr noundef, ptr noundef) #2
        \\declare zeroext i8 @raise_(i8 noundef zeroext, i64 noundef) #2
    ;
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const index = try IrIndex.of(arena, ir);
    const realpath = (try index.linkedOf(arena, 0, 0)).?;
    try testing.expectEqualStrings("\\01_realpath$DARWIN_EXTSN", realpath.symbol);
    try testing.expectEqual(Linked.Kind.function, realpath.kind);
    const raise = (try index.linkedOf(arena, 0, 1)).?;
    try testing.expectEqualStrings("raise_", raise.symbol);
    const signature = raise.signature.?;
    try testing.expectEqual(Passed{ .bits = 8, .extension = false, .kind = .integer }, signature.result);
    try testing.expectEqual(Passed{ .bits = 8, .extension = false, .kind = .integer }, signature.params[0]);
    try testing.expectEqual(Passed{ .bits = 64, .kind = .integer }, signature.params[1]);
    try testing.expectEqual(@as(?Linked, null), try index.linkedOf(arena, 0, 2));
    const resolved =
        \\@linea_symbol_0_0 = constant ptr @twice, align 8
        \\@twice = ifunc i64 (i64), ptr @resolve
    ;
    try testing.expectEqual(Linked.Kind.ifunc, (try (try IrIndex.of(arena, resolved)).linkedOf(arena, 0, 0)).?.kind);
    const variable =
        \\@linea_symbol_0_0 = constant ptr @count, align 8
        \\@count = global i32 0, align 4
    ;
    try testing.expectEqual(Linked.Kind.other, (try (try IrIndex.of(arena, variable)).linkedOf(arena, 0, 0)).?.kind);
}

/// The symbol an `extern` is emitted under to reach the IR symbol `spelled`,
/// as LLVM spells one, or null where no symbol a Linea declaration can name
/// reaches it. `\01` marks a symbol written as the object file spells it,
/// which on Darwin begins with the underscore LLVM adds to every other name.
fn callableSymbol(spelled: []const u8) ?[]const u8 {
    var name = spelled;
    if (std.mem.startsWith(u8, spelled, "\\01")) {
        name = spelled[3..];
        if (builtin.target.os.tag.isDarwin()) {
            if (!std.mem.startsWith(u8, name, "_")) return null;
            name = name[1..];
        }
    }
    if (name.len == 0 or !symbol_names.holds(name)) return null;
    return name;
}

test "a symbol C names is the one an extern is emitted under" {
    try testing.expectEqualStrings("lseek64", callableSymbol("lseek64").?);
    if (builtin.target.os.tag.isDarwin()) {
        try testing.expectEqualStrings("realpath$DARWIN_EXTSN", callableSymbol("\\01_realpath$DARWIN_EXTSN").?);
        try testing.expectEqual(@as(?[]const u8, null), callableSymbol("\\01twice_impl"));
    } else {
        try testing.expectEqualStrings("twice_impl", callableSymbol("\\01twice_impl").?);
    }
}

/// Gives each enumeration at the top of `ctype`'s parameters and result the
/// width and extension the IR passes it with.
fn widenEnumerations(ctype: *CType, signature: Signature) void {
    const function = &ctype.shape.function;
    const params = @constCast(function.params);
    if (params.len == signature.params.len) {
        for (params, signature.params) |*param, passed| widen(param, passed);
    }
    widen(@constCast(function.result), signature.result);
}

fn widen(c: *CType, passed: Passed) void {
    if (c.shape != .enumeration) return;
    const bits = passed.bits orelse return;
    switch (bits) {
        8, 16, 32, 64 => {},
        else => return,
    }
    // Narrower than 32 bits, the extension says the signedness; a 32- or
    // 64-bit value is passed alike whatever its signedness.
    c.shape = .{ .enumeration = .{ .bits = bits, .signed = if (bits < 32) passed.extension else null } };
}

/// The width and signedness of an integer type.
const Integer = struct { bits: u8, signed: bool };

/// How C passes an enumeration: its width, and its signedness where that
/// changes how it is passed.
const Enumeration = struct { bits: u8, signed: ?bool };

/// What `cc` says a C name is.
pub const CType = struct {
    /// The type as the C declaration spells it, typedefs and all.
    spelled: []const u8,
    shape: Shape,

    pub const Shape = union(enum) {
        integer: Integer,
        /// An enumeration, whose integer type the C compiler chooses from its
        /// values, or from the type it is declared over. Null until the IR
        /// says how C passes it, which it says only for a parameter or a
        /// result, not behind a pointer or in a callback.
        enumeration: ?Enumeration,
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
        /// False for a declaration written `f()` or a definition written
        /// `f(x) int x; {…}`, neither of which states parameter types a
        /// caller passes by.
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
            var line = Line.of(raw);
            line.spelled = try withoutDirectories(arena, line.spelled);
            try lines.append(arena, line);
        }
        if (current) |name| try out.sections.put(arena, name, try lines.toOwnedSlice(arena));
        return out;
    }

    /// The function the probe of subject `index` in unit `unit` points at,
    /// or null where nothing declared the name, or names something that is
    /// not a function.
    fn function(self: Dumps, arena: std.mem.Allocator, unit: usize, index: usize) !?CType {
        const lines = self.sections.get(try probeName(arena, unit, index, "")) orelse return null;
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
};

/// `spelled` with the directories taken out of each path clang writes where
/// it spells a type that has no name, `enum (unnamed at /tmp/x/c.c:1:1)`, so
/// the spelling names the file as the manifest's directory does not change.
fn withoutDirectories(arena: std.mem.Allocator, spelled: []const u8) ![]const u8 {
    if (std.mem.indexOf(u8, spelled, " at /") == null) return spelled;
    var out: std.ArrayList(u8) = .empty;
    var rest = spelled;
    while (std.mem.indexOf(u8, rest, " at /")) |at| {
        try out.appendSlice(arena, rest[0 .. at + " at ".len]);
        const path_start = at + " at ".len;
        const path_end = std.mem.indexOfScalarPos(u8, rest, path_start, ':') orelse rest.len;
        const path = rest[path_start..path_end];
        try out.appendSlice(arena, std.fs.path.basename(path));
        rest = rest[path_end..];
    }
    try out.appendSlice(arena, rest);
    return out.items;
}

test "a type without a name is spelled with its file, not where the file sits" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    try testing.expectEqualStrings("enum (unnamed enum at c.c:1:1)", try withoutDirectories(arena_state.allocator(), "enum (unnamed enum at /tmp/probe/c/c.c:1:1)"));
    try testing.expectEqualStrings("enum big", try withoutDirectories(arena_state.allocator(), "enum big"));
}

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
/// neither changes how a value crosses.
fn convert(arena: std.mem.Allocator, lines: []const Line, at: usize) std.mem.Allocator.Error!CType {
    const line = lines[at];
    const children = try typeChildren(arena, lines, at);
    // A qualified type's one child is the type it qualifies, and a sugared
    // one's last child is the type it stands for.
    if (std.mem.eql(u8, line.kind, "QualType") or line.has("sugar")) {
        if (children.len == 0) return .{ .spelled = line.spelled, .shape = .other };
        var inner = try convert(arena, lines, children[children.len - 1]);
        // `typeof (f)` names the probe's expression, not a type C spells, and
        // a typedef naming a function type, `op_t`, shows none of its
        // parameters, so the function keeps its own spelling.
        if (std.mem.startsWith(u8, line.kind, "TypeOf")) return inner;
        if (inner.shape == .function and parameterListStart(line.spelled) == null) return inner;
        inner.spelled = line.spelled;
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
            .convention = conventionOf(line),
        } };
    } else if (std.mem.eql(u8, line.kind, "EnumType"))
        .{ .enumeration = null }
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
    const column = (try dumps.function(arena, 0, 0)).?;
    try testing.expectEqualStrings("sqlite3_int64 (sqlite3_stmt *, int)", column.spelled);
    const function = column.shape.function;
    try testing.expectEqualStrings("sqlite3_int64", function.result.spelled);
    try testing.expectEqual(CType.Shape{ .integer = .{ .bits = 64, .signed = true } }, function.result.shape);
    try testing.expectEqual(@as(usize, 2), function.params.len);
    try testing.expectEqual(CType.Shape.object, function.params[0].shape.pointer.shape);
    try testing.expectEqual(CType.Shape{ .integer = .{ .bits = 32, .signed = true } }, function.params[1].shape);
    try testing.expect(!function.variadic);
    try testing.expectEqual(@as(?[]const u8, null), function.convention);
    try testing.expectEqual(@as(?CType, null), try dumps.function(arena, 0, 1));
    var other = (try dumps.function(arena, 0, 2)).?;
    try testing.expectEqualStrings("preserve_none", other.shape.function.convention.?);
    try testing.expectEqual(@as(?Enumeration, null), other.shape.function.params[0].shape.enumeration);
    widenEnumerations(&other, .{ .result = .{ .bits = 64, .kind = .integer }, .params = &.{.{ .bits = 64, .kind = .integer }} });
    try testing.expectEqual(Enumeration{ .bits = 64, .signed = null }, other.shape.function.params[0].shape.enumeration.?);
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
            .enumeration => |width| if (width) |held| held.bits == integer.bits and (held.signed == null or held.signed.? == integer.signed) else false,
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
    /// The exports already reported as called by another signature.
    called_exports: std.ArrayList(DeclId) = .empty,

    /// A label at the subject's name.
    fn atName(self: *Reporter, subject: Subject, message: []const u8) Label {
        const name = self.ast.declName(subject.decl);
        return .{ .file = self.ast.fileOf(name), .span = self.ast.tokenSpan(name), .message = message };
    }

    /// The remark naming the C declarations `shown` describes.
    fn declaredBy(self: *Reporter, subject: Subject, shown: []const u8) ![]const u8 {
        return std.fmt.allocPrint(self.sink.arena, "`{s}` is declared by {s}", .{ subject.name, shown });
    }

    /// Adds one [T-ExternPrototype] error: the message `fmt` and `args`
    /// spell, `label` on the source, `remark` where there is one, and the
    /// help `note`.
    fn report(self: *Reporter, label: Label, remark: ?[]const u8, note: []const u8, comptime fmt: []const u8, args: anytype) !void {
        const a = self.sink.arena;
        try self.sink.add(.{
            .severity = .err,
            .code = .t_extern_prototype,
            .message = try std.fmt.allocPrint(a, fmt, args),
            .labels = try a.dupe(Label, &.{label}),
            .remarks = if (remark) |text| try a.dupe([]const u8, &.{text}) else &.{},
            .notes = try a.dupe([]const u8, &.{note}),
        });
    }

    fn unread(self: *Reporter, subject: Subject, reason: []const u8) !void {
        try self.report(
            self.atName(subject, "held to the prototype its root's C declarations give it"),
            null,
            "correct `headers` or `native` in " ++ loader.manifest_name ++ ", or install the C library whose header it names",
            "the C declarations this root names cannot be read, so `{s}` cannot be held to its prototype: {s}",
            .{ subject.name, reason },
        );
    }

    fn macro(self: *Reporter, subject: Subject) !void {
        try self.report(
            self.atName(subject, "a macro has no prototype to hold this to"),
            null,
            "declare the function the macro expands to, or call it through a C function in `native`",
            "`{s}` is a macro in C, so C code calling it reaches what the macro expands to, not the symbol this declaration names",
            .{subject.name},
        );
    }

    fn undeclared(self: *Reporter, subject: Subject, named: usize) !void {
        const why = if (named == 0)
            loader.manifest_name ++ " names no C declarations for this root"
        else
            "neither the `headers` nor the `native` sources its " ++ loader.manifest_name ++ " names declare it";
        try self.report(
            self.atName(subject, "held to the prototype C gives it, and C gives it none"),
            null,
            "name the header that declares it under \"headers\" in " ++ loader.manifest_name ++ ", such as \"stdlib.h\", or build the C that defines it under \"native\"",
            "no C declaration of `{s}` is in reach: {s}",
            .{ subject.name, why },
        );
    }

    fn internal(self: *Reporter, subject: Subject, shown: []const u8) !void {
        try self.report(
            self.atName(subject, "C gives this function no symbol"),
            try self.declaredBy(subject, shown),
            "call it through a C function that is not `static`, built under \"native\"",
            "C declares `{s}` `static`, so it has no symbol this declaration could link against",
            .{subject.name},
        );
    }

    fn notFunction(self: *Reporter, subject: Subject, shown: []const u8, kind: Linked.Kind) !void {
        const what = switch (kind) {
            .alias => "an alias of another function",
            .ifunc => "an `ifunc`, which the program's loader resolves to some function",
            .other, .function => "something that is not a function",
        };
        try self.report(
            self.atName(subject, "C's symbol for this is not a function its declaration describes"),
            try self.declaredBy(subject, shown),
            "declare the function itself, or call it through a C function, built under \"native\"",
            "C defines `{s}` as {s}, whose prototype its declaration does not show",
            .{ subject.name, what },
        );
    }

    fn reserved(self: *Reporter, subject: Subject, shown: []const u8, symbol: []const u8) !void {
        try self.report(
            self.atName(subject, "C gives this function a symbol no `extern` may link against"),
            try self.declaredBy(subject, shown),
            "declare the C function under its own symbol, or reach the runtime through the standard library",
            "C code calling `{s}` reaches the symbol `{s}`, which belongs to the Linea runtime or the program's own code",
            .{ subject.name, symbol },
        );
    }

    /// Reports C calling an export by an IR signature the export does not
    /// have, once per export, and answers whether it reported.
    fn called(self: *Reporter, subject: Subject, shown: []const u8, signature: Signature) !bool {
        for (self.called_exports.items) |held| if (held == subject.decl) return false;
        try self.called_exports.append(self.arena, subject.decl);
        const a = self.sink.arena;
        var text: std.Io.Writer.Allocating = .init(a);
        if (signature.params.len == 0) try text.writer.writeAll("nothing");
        for (signature.params, 0..) |param, i| {
            if (i > 0) try text.writer.writeAll(", ");
            try text.writer.writeAll(passedSpelling(param));
        }
        try self.report(
            self.atName(subject, "C calls this export through a declaration of another prototype"),
            try std.fmt.allocPrint(a, "the call is compiled from {s}", .{shown}),
            "declare the export as C calls it, or the C declaration that reaches it as the export is",
            "C code calls the symbol `{s}` this export defines through a declaration that takes {s} and answers {s}, which this export does not",
            .{ subject.name, text.written(), passedSpelling(signature.result) },
        );
        return true;
    }

    fn sharedName(self: *Reporter, subject: Subject, first: []const u8, then: []const u8) !void {
        try self.report(
            self.atName(subject, "this root's C calls it by another symbol"),
            null,
            "give the function one symbol in every root's C, or declare one of them under another name",
            "C gives `{s}` the symbol `{s}` in one root and `{s}` in another, and every `extern` of one name is one function",
            .{ subject.name, first, then },
        );
    }

    fn sharedSymbol(self: *Reporter, subject: Subject, symbol: []const u8, other: []const u8) !void {
        try self.report(
            self.atName(subject, "one symbol is one function, with one signature"),
            null,
            "declare both alike, since C calls one function through both",
            "C gives `{s}` the symbol `{s}`, which `{s}` also links against with another signature",
            .{ subject.name, symbol, other },
        );
    }

    fn unnameable(self: *Reporter, subject: Subject, shown: []const u8, spelled: []const u8) !void {
        const symbol = if (std.mem.startsWith(u8, spelled, "\\01")) spelled[3..] else spelled;
        try self.report(
            self.atName(subject, "C gives this function a symbol Linea cannot link against"),
            try self.declaredBy(subject, shown),
            "call it through a C function with a plain symbol, built under \"native\"",
            "C code calling `{s}` reaches the symbol `{s}`, which a Linea declaration cannot name",
            .{ subject.name, symbol },
        );
    }

    fn symbols(self: *Reporter, subject: Subject, first_shown: []const u8, first: []const u8, then_shown: []const u8, then: []const u8) !void {
        try self.report(
            self.atName(subject, "this links against one symbol, and C code calls two"),
            null,
            "declare the function alike in every C source and header " ++ loader.manifest_name ++ " names",
            "C's declarations give `{s}` two symbols: `{s}` in {s} and `{s}` in {s}",
            .{ subject.name, first, first_shown, then, then_shown },
        );
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
        var at = self.atName(subject, "");
        var help: []const u8 = "";
        switch (mismatch) {
            .unprototyped => {
                at.message = "C declares this without a prototype, which states no parameter types";
                help = "declare the function in C with a prototype, `long long f(long long value)` rather than `long long f()`";
            },
            .convention => |convention| {
                at.message = try std.fmt.allocPrint(a, "C declares it with the `{s}` calling convention, which is not C's own", .{convention});
                help = "call it through a C function with C's own calling convention, built under \"native\"";
            },
            .variadic => {
                at.message = "C reads a variable list of arguments, which an `extern` cannot pass";
                help = "call it through a C function with fixed parameters, built under \"native\"";
            },
            .arity => |counts| {
                at.message = try std.fmt.allocPrint(a, "C takes {d} parameter{s}, and this declares {d}", .{ counts.c, plural(counts.c), counts.linea });
                help = try std.fmt.allocPrint(a, "declare one parameter for each of the {d} C takes, in its order", .{counts.c});
            },
            .param => |position| {
                at.span = self.ast.writtenWholeSpan(params[position.index].written);
                const name = self.ast.tokenText(params[position.index].name);
                if (position.inner) |inner| {
                    at.message = try std.fmt.allocPrint(a, "C calls this back as `{s}`", .{position.c.spelled});
                    help = try std.fmt.allocPrint(a, "in the callback, {s}", .{try innerHelp(a, inner.*)});
                } else {
                    at.message = try std.fmt.allocPrint(a, "C takes `{s}` here", .{position.c.spelled});
                    help = try positionHelp(a, position.implied, position.c, try std.fmt.allocPrint(a, "`{s}`", .{name}));
                }
            },
            .result => |position| {
                const returns = self.ast.declReturnRef(subject.decl);
                if (returns.wasWritten()) at.span = self.ast.writtenWholeSpan(returns);
                at.message = try std.fmt.allocPrint(a, "C answers `{s}`", .{position.c.spelled});
                help = try resultHelp(a, position.implied, position.c, subject.implied.errno);
            },
        }
        const verb = if (subject.exported) "this export defines it as" else "this declaration calls it as";
        try self.report(at, try self.declaredBy(subject, shown), help, "C declares `{s}`, and {s} `{s}`", .{ found, verb, implied });
        return true;
    }
};

fn plural(n: usize) []const u8 {
    return if (n == 1) "" else "s";
}

/// How the IR passes a value, as its type reads in C.
fn passedSpelling(passed: Passed) []const u8 {
    return switch (passed.kind) {
        .integer => switch (passed.bits orelse 0) {
            8 => "an 8-bit integer",
            16 => "a 16-bit integer",
            32 => "a 32-bit integer",
            64 => "a 64-bit integer",
            else => "an integer of another width",
        },
        .float => if (passed.bits == 64) "a `double`" else "a `float`",
        .pointer => "an address",
        .void => "nothing",
        .other => "a value no Linea type crosses as",
    };
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

/// Whether `held`, a `lineaName`, names two types of one width.
fn paired(held: []const u8) bool {
    return std.mem.indexOf(u8, held, "` or `") != null;
}

/// What a newtype is over in a help naming `held`.
fn overWhich(held: []const u8) []const u8 {
    return if (paired(held)) "either" else "it";
}

/// How a help names what `held` is to C's type.
fn theLineaTypes(held: []const u8) []const u8 {
    return if (paired(held)) "the Linea types" else "the Linea type";
}

/// The Linea type a C scalar crosses as, or null for one none does.
fn lineaName(c: CType) ?[]const u8 {
    const integer: Integer = switch (c.shape) {
        .integer => |held| held,
        // How C passes an enumeration fixes its width, and its signedness
        // only on some targets, so both types of the width are named, each
        // quoted where the help quotes one.
        .enumeration => |width| return if (width) |held| switch (held.bits) {
            8 => "Int8` or `UInt8",
            16 => "Int16` or `UInt16",
            32 => "Int32` or `UInt32",
            64 => "Int64` or `UInt64",
            else => null,
        } else null,
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
        .enumeration => |width| if (width == null) try std.fmt.allocPrint(a, "C's `{s}` is an enumeration behind a pointer or in a callback, whose width only the C compiler knows: call it through a C function, built under \"native\", that takes an integer", .{c.spelled}) else null,
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
                return try std.fmt.allocPrint(a, "C writes {s} `{s}` through the address: declare {s} as an `inout` `{s}`, or a newtype over {s}", .{ article.before(pointee.spelled), pointee.spelled, name, held, overWhich(held) });
            },
            else => {
                if (scalarAccepts(scalar, c)) return try std.fmt.allocPrint(a, "C takes the value itself: drop `inout` from {s}", .{name});
                const held = lineaName(c).?;
                return try std.fmt.allocPrint(a, "C takes the value itself: declare {s} as `{s}`, or a newtype over {s}, without `inout`", .{ name, held, overWhich(held) });
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
                return try std.fmt.allocPrint(a, "declare {s} as `{s}`, or a newtype over {s}, {s} of C's `{s}`", .{ name, held, overWhich(held), theLineaTypes(held), c.spelled });
            },
        },
    }
}

fn resultHelp(a: std.mem.Allocator, implied: ?foreign.Value, c: CType, errno: bool) ![]const u8 {
    if (c.shape == .void) return "C answers nothing: drop the result";
    if (try untranslatable(a, c)) |why| return why;
    const held = lineaName(c).?;
    if (errno) {
        if (paired(held)) return try std.fmt.allocPrint(a, "declare the result `ffi.Errno[R]` with `R` one of `{s}`, {s} of C's `{s}` beside `errno`", .{ held, theLineaTypes(held), c.spelled });
        return try std.fmt.allocPrint(a, "declare the result `ffi.Errno[{s}]`, {s} of C's `{s}` beside `errno`", .{ held, theLineaTypes(held), c.spelled });
    }
    if (implied == null) return try std.fmt.allocPrint(a, "declare the result `-> {s}`, {s} of C's `{s}`", .{ held, theLineaTypes(held), c.spelled });
    return try std.fmt.allocPrint(a, "declare the result `{s}`, or a newtype over {s}, {s} of C's `{s}`", .{ held, overWhich(held), theLineaTypes(held), c.spelled });
}

/// C's function type spelled with `name` before its parameter list:
/// `int (sqlite3 *)` becomes `int sqlite3_close_v2(sqlite3 *)`.
fn rendered(a: std.mem.Allocator, spelled: []const u8, name: []const u8) ![]const u8 {
    // A calling convention clang writes after the parameter list follows it.
    if (std.mem.lastIndexOf(u8, spelled, " __attribute__((")) |at| {
        if (std.mem.endsWith(u8, spelled, "))") and parameterListStart(spelled[0..at]) != null) {
            const head = try rendered(a, spelled[0..at], name);
            defer a.free(head);
            return std.fmt.allocPrint(a, "{s}{s}", .{ head, spelled[at..] });
        }
    }
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
    const convention = try rendered(gpa, "long long (long long) __attribute__((preserve_none))", "twice");
    defer gpa.free(convention);
    try testing.expectEqualStrings("long long twice(long long) __attribute__((preserve_none))", convention);
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
