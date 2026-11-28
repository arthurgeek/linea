//! Source selection for readable backend inspection. Source identity stays in
//! the retained expansion and MIR origins; only the definition choice is new.
const std = @import("std");
const ExpandedProgram = @import("../syntax/expanded_program.zig").ExpandedProgram;
const DeclId = @import("../syntax/node.zig").DeclId;
const Module = @import("../mir/mir.zig").Module;

pub const Scope = enum { user, all };
pub const Target = enum { host, gpu };
pub const Stage = enum { lowered, spirv };
pub const Detail = enum { compact, full };
pub const Request = struct {
    scope: Scope = .user,
    target: Target = .host,
    stage: Stage = .lowered,
    function: ?[]const u8 = null,
    detail: Detail = .compact,
    locations: bool = false,

    pub fn problem(self: Request) ?[]const u8 {
        if (self.target == .host and self.stage == .spirv) return "--stage=spirv requires --target=gpu";
        if (self.function) |name| if (name.len == 0) return "--function requires a qualified source function";
        return null;
    }
};

pub const SelectionError = error{ UnknownFunction, AmbiguousFunction, FunctionOutsideScope, UnmaterializedFunction };

/// One bit per materialized function, including concrete generic instances.
/// The caller owns the slice. No source identities are copied or inferred
/// from backend symbols.
pub fn select(gpa: std.mem.Allocator, program: *const ExpandedProgram, module: *const Module, request: Request) (std.mem.Allocator.Error || SelectionError)![]bool {
    var selected: DeclId = .none;
    if (request.function) |name| {
        var name_buffer: std.Io.Writer.Allocating = .init(gpa);
        defer name_buffer.deinit();
        for (0..program.ast.declCount()) |i| {
            const decl = DeclId.at(@intCast(i));
            if (program.ast.declTag(decl) != .function) continue;
            name_buffer.clearRetainingCapacity();
            writeSourceName(&name_buffer.writer, program, decl) catch return error.OutOfMemory;
            if (!std.mem.eql(u8, name, name_buffer.written())) continue;
            if (selected != .none) return error.AmbiguousFunction;
            selected = decl;
        }
        if (selected == .none) return error.UnknownFunction;
        if (!inScope(program, selected, request.scope)) return error.FunctionOutsideScope;
    }
    const definitions = try gpa.alloc(bool, module.functions.len);
    for (definitions, 0..) |*include, i| {
        include.* = false;
        if (i >= module.origins.len) continue;
        const origin = module.origins[i];
        if (origin.decl == .none) continue;
        const original = program.originalDeclId(origin.decl);
        const generated = original != origin.decl;
        const implicit = selected == .none and (request.scope == .all or !generated);
        include.* = inScope(program, origin.decl, request.scope) and (implicit or selected == origin.decl or (!generated and selected == original));
    }
    if (selected != .none and std.mem.indexOfScalar(bool, definitions, true) == null) {
        gpa.free(definitions);
        return error.UnmaterializedFunction;
    }
    return definitions;
}

fn inScope(program: *const ExpandedProgram, decl: DeclId, scope: Scope) bool {
    if (scope == .all) return true;
    const owner = program.moduleOf(decl);
    return owner != .none and program.get(owner).root == .primary;
}

pub fn writeSourceName(w: *std.Io.Writer, program: *const ExpandedProgram, declaration: DeclId) std.Io.Writer.Error!void {
    const decl = program.originalDeclId(declaration);
    const owner = program.source.moduleOf(decl);
    if (owner != .none) {
        const route = program.source.modulePath(owner);
        if (route.len != 0) try w.print("{s}.", .{route});
    }
    const ast = &program.source.ast;
    const member = ast.memberOwner(decl);
    if (member != .none) try w.print("{s}.", .{ast.tokenText(member)});
    try w.writeAll(ast.tokenText(ast.declName(decl)));
    if (decl != declaration) {
        try w.writeByte('.');
        try w.writeAll(program.ast.tokenText(program.ast.declName(declaration)));
    }
}

/// Presentation names are rendered once from typed origins. They never change
/// MIR identity or the names used for runtime/foreign certification.
pub fn displayNames(gpa: std.mem.Allocator, program: *const ExpandedProgram, module: *const Module) ![]?[]const u8 {
    var counts: std.AutoHashMapUnmanaged(DeclId, u32) = .empty;
    defer counts.deinit(gpa);
    for (module.origins) |origin| {
        if (origin.decl == .none or origin.body != .declaration) continue;
        const entry = try counts.getOrPut(gpa, origin.decl);
        if (!entry.found_existing) entry.value_ptr.* = 0;
        entry.value_ptr.* += 1;
    }
    const names = try gpa.alloc(?[]const u8, module.functions.len);
    @memset(names, null);
    errdefer deinitNames(gpa, names);
    for (names, 0..) |*name, i| {
        if (module.isExternal(.at(@intCast(i)))) continue;
        var out: std.Io.Writer.Allocating = .init(gpa);
        defer out.deinit();
        try out.writer.writeAll("source.");
        if (i < module.origins.len and module.origins[i].decl != .none) {
            const origin = module.origins[i];
            try writeSourceName(&out.writer, program, origin.decl);
            // Distinct implementation members may share the same written
            // owner/name (different traits, heads or bounds). Their instance
            // identity keeps those presentation symbols injective too.
            if (origin.body != .declaration or program.originalDeclId(origin.decl) != origin.decl or program.ast.memberOwner(origin.decl) != .none or (counts.get(origin.decl) orelse 0) > 1) {
                try out.writer.print(".instance{d}", .{i});
            }
        } else {
            try out.writer.print("generated.instance{d}", .{i});
        }
        name.* = try out.toOwnedSlice();
    }
    return names;
}

pub fn deinitNames(gpa: std.mem.Allocator, names: []?[]const u8) void {
    for (names) |name| if (name) |text| gpa.free(text);
    gpa.free(names);
}

pub fn writeHeader(w: *std.Io.Writer, program: *const ExpandedProgram, module: *const Module, definitions: []const bool) std.Io.Writer.Error!void {
    try w.writeAll("// Inspection projection; not a standalone executable.\n");
    for (definitions, 0..) |included, i| if (included) {
        try writeIdentity(w, program, module, i);
    };
}

/// Comments distinguish a source declaration's instances from generated
/// bodies whose substitution owner is that declaration.
pub fn writeIdentity(w: *std.Io.Writer, program: *const ExpandedProgram, module: *const Module, index: usize) std.Io.Writer.Error!void {
    if (index >= module.origins.len or module.origins[index].decl == .none) return;
    const origin = module.origins[index];
    const original = program.originalDeclId(origin.decl);
    const kind = if (original != origin.decl) "generated_declaration" else @tagName(origin.body);
    try w.print("// source {s} ", .{kind});
    try writeSourceName(w, program, origin.decl);
    try w.print(" originalDeclId={d} instance={d} args=[", .{ original.index(), index });
    for (origin.args, 0..) |arg, i| {
        if (i != 0) try w.writeAll(", ");
        try w.writeAll(module.types.nameOf(arg));
    }
    try w.print("] self={s} impl_args=[", .{module.types.nameOf(origin.self_ty)});
    for (origin.impl_args, 0..) |arg, i| {
        if (i != 0) try w.writeAll(", ");
        try w.writeAll(module.types.nameOf(arg));
    }
    try w.writeAll("]\n");
}

test "inspection request validates only real stage boundaries" {
    const testing = std.testing;
    try testing.expect((Request{}).problem() == null);
    try testing.expect((Request{ .target = .gpu, .stage = .spirv }).problem() == null);
    try testing.expect((Request{ .stage = .spirv }).problem() != null);
    try testing.expect((Request{ .function = "" }).problem() != null);
}

test "inspection scopes use roots and source selectors keep every concrete instance" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    const parser = @import("../parser/parser.zig");
    const program_mod = @import("../syntax/program.zig");
    var sink = @import("../diagnostics/sink.zig").Sink.init(gpa);
    var names: @import("../support/interner.zig").Interner = .empty;
    var parsing = parser.Modules.init(gpa, &sink, &names);
    defer parsing.deinit();
    const root_decls = try parsing.add(&.{.{ .file = .from(0), .source = .{ .path = "project/main.lin", .text = "fn main() -> UInt8 { 0 }" } }});
    const own_decls = try parsing.add(&.{.{ .file = .from(1), .source = .{ .path = "project/helper/helper.lin", .text = "fn value[T](input: T) -> T { input }" } }});
    const dep_decls = try parsing.add(&.{.{ .file = .from(2), .source = .{ .path = "dependency/helper/helper.lin", .text = "fn value() -> UInt8 { 1 }" } }});
    const ast = try parsing.finish();
    var modules = [_]program_mod.Module{
        .{ .name = "project", .dir = "project", .files = &.{.from(0)}, .decls = root_decls, .imports = &.{} },
        .{ .name = "helper", .dir = "project/helper", .files = &.{.from(1)}, .decls = own_decls, .imports = &.{} },
        .{ .name = "helper", .dir = "dependency/helper", .files = &.{.from(2)}, .decls = dep_decls, .imports = &.{}, .root = .first_dependency },
    };
    const source: program_mod.Program = .{ .modules = &modules, .ast = ast, .import_routes = &.{ "", "helper", "dep.helper" } };
    var expanded = try ExpandedProgram.borrowSource(gpa, &source);
    var module: Module = undefined;
    var functions: [5]@import("../mir/mir.zig").Mir = undefined;
    module.functions = &functions;
    module.origins = &.{
        .{ .decl = .at(root_decls.start), .body = .{ .declaration = .at(root_decls.start) } },
        .{ .decl = .at(own_decls.start), .body = .{ .declaration = .at(own_decls.start) }, .args = &.{.u8} },
        .{ .decl = .at(own_decls.start), .body = .{ .declaration = .at(own_decls.start) }, .args = &.{.u64} },
        .{ .decl = .at(dep_decls.start), .body = .{ .declaration = .at(dep_decls.start) } },
        .{ .decl = .at(own_decls.start), .body = .{ .closure = .at(0) } },
    };
    try testing.expectEqualSlices(bool, &.{ true, true, true, false, true }, try select(gpa, &expanded, &module, .{}));
    try testing.expectEqualSlices(bool, &.{ false, true, true, false, true }, try select(gpa, &expanded, &module, .{ .function = "helper.value" }));
    try testing.expectEqualSlices(bool, &.{ true, true, true, true, true }, try select(gpa, &expanded, &module, .{ .scope = .all }));
    try testing.expectError(error.FunctionOutsideScope, select(gpa, &expanded, &module, .{ .function = "dep.helper.value" }));
    try testing.expectError(error.UnknownFunction, select(gpa, &expanded, &module, .{ .function = "absent" }));
}
