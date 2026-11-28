//! Device code from checked MIR. Float32 values are carried as IEEE bits;
//! arithmetic calls the integer-only binary32 implementation.
const std = @import("std");
const mir_mod = @import("../mir/mir.zig");
const Module = mir_mod.Module;
const Mir = mir_mod.Mir;
const FunctionId = mir_mod.FunctionId;
const InstId = mir_mod.InstId;
const BlockId = mir_mod.BlockId;
const TypeId = @import("../sema/types.zig").TypeId;

const Sink = @import("../diagnostics/sink.zig").Sink;
const verify = @import("../mir/verify.zig").verify;
const writeString = @import("text.zig").writeString;

pub const Kind = enum(u64) { map, reduce, matmul };
pub const Format = enum { spirv, staging };
pub const Source = struct { function: FunctionId, mlir: []const u8, kind: Kind = .map, format: Format = .spirv };
pub const Image = struct { function: FunctionId, bytes: []const u8, kind: Kind = .map };

/// Inspection changes symbol presentation and which implementations are
/// externalized; production calls the same producer without this projection.
pub const Projection = struct {
    definitions: []const bool,
    display_names: ?[]const ?[]const u8 = null,
    software_bodies: bool = false,
    launch_support: bool = true,
    compact: bool = true,
};

const Helper = enum {
    add,
    sub,
    mul,
    div,
    eq,
    ne,
    lt,
    le,
    gt,
    ge,

    fn result(self: Helper) []const u8 {
        return switch (self) {
            .add, .sub, .mul, .div => "i32",
            else => "i1",
        };
    }

    fn arithmetic(tag: mir_mod.Inst.Tag) Helper {
        return switch (tag) {
            .add => .add,
            .sub => .sub,
            .mul => .mul,
            .div => .div,
            else => unreachable,
        };
    }

    fn comparison(tag: mir_mod.Inst.Tag) Helper {
        return switch (tag) {
            .cmp_eq => .eq,
            .cmp_ne => .ne,
            .cmp_lt => .lt,
            .cmp_le => .le,
            .cmp_gt => .gt,
            .cmp_ge => .ge,
            else => unreachable,
        };
    }
};

const DeviceUsage = struct {
    helpers: std.EnumSet(Helper) = .initEmpty(),
    calls: std.AutoHashMapUnmanaged(FunctionId, void) = .empty,

    fn deinit(self: *DeviceUsage, gpa: std.mem.Allocator) void {
        self.calls.deinit(gpa);
    }
};

fn writeDeviceName(w: *std.Io.Writer, id: FunctionId, projection: ?Projection) !void {
    if (projection) |view| {
        if (view.display_names) |names| {
            if (names[id.index()]) |name| {
                try w.writeAll("@\"");
                try writeString(w, name);
                try w.writeByte('"');
                return;
            }
        }
    }
    try w.print("@linea_dev{d}", .{id.index()});
}

fn writeHelperCall(w: *std.Io.Writer, usage: ?*DeviceUsage, helper: Helper, result: u32, left: u32, right: u32) !void {
    if (usage) |used| used.helpers.insert(helper);
    try w.print("      %v{d} = spirv.FunctionCall @linea_f32_{s}(%v{d}, %v{d}) : (i32, i32) -> {s}\n", .{ result, @tagName(helper), left, right, helper.result() });
}

fn writeHelperImports(w: *std.Io.Writer, helpers: std.EnumSet(Helper)) !void {
    var selected = helpers.iterator();
    while (selected.next()) |helper| {
        const name = @tagName(helper);
        try w.print("    spirv.func @linea_f32_{s}(i32, i32) -> {s} \"None\" attributes {{linkage_attributes = #spirv.linkage_attributes<linkage_name = \"linea_f32_{s}\", linkage_type = <Import>>, sym_visibility = \"private\"}}\n", .{ name, helper.result(), name });
    }
}

test "device arithmetic import signatures match the production helpers" {
    const source = @embedFile("gpu/float32.mlir");
    var signature: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer signature.deinit();
    for (std.meta.tags(Helper)) |helper| {
        signature.clearRetainingCapacity();
        try signature.writer.print("spirv.func @linea_f32_{s}(%a: i32, %b: i32) -> {s} \"None\"", .{ @tagName(helper), helper.result() });
        try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, source, signature.written()));
    }
}

const Candidate = struct { function: FunctionId, kind: Kind };

fn candidates(gpa: std.mem.Allocator, module: *const Module) ![]Candidate {
    var roots: std.AutoHashMapUnmanaged(FunctionId, void) = .empty;
    defer roots.deinit(gpa);
    var ordered: std.ArrayList(Candidate) = .empty;
    errdefer ordered.deinit(gpa);
    for (module.functions) |*f| {
        for (f.insts.items(.tag), 0..) |tag, i| {
            if (tag != .function_addr) continue;
            const target = f.functionOf(InstId.at(@intCast(i)));
            const body = module.functionOf(target);
            if (module.isExternal(target) or body.return_type != .f32) continue;
            const kind: Kind = if (body.param_count == 1 and body.locals[0] == .f32 and module.gpu_function != .none)
                .map
            else if (body.param_count == 2 and body.locals[0] == .f32 and body.locals[1] == .f32 and module.gpu_reduce_function != .none)
                .reduce
            else
                continue;
            const entry = try roots.getOrPut(gpa, target);
            if (!entry.found_existing) try ordered.append(gpa, .{ .function = target, .kind = kind });
        }
    }
    return ordered.toOwnedSlice(gpa);
}

const Visit = enum { visiting, accepted };
const Body = struct { blocks: []BlockId, calls: []FunctionId, state: Visit = .visiting };

fn scalar(ty: TypeId) bool {
    return ty == .f32 or ty == .bool_;
}

fn gpuType(ty: TypeId) []const u8 {
    return if (ty == .bool_) "i1" else "i32";
}

const Plan = struct {
    gpa: std.mem.Allocator,
    module: *const Module,
    functions: std.AutoHashMapUnmanaged(FunctionId, Body) = .empty,
    bodies: std.ArrayList(FunctionId) = .empty,

    fn deinit(self: *Plan) void {
        var bodies = self.functions.valueIterator();
        while (bodies.next()) |body| {
            self.gpa.free(body.blocks);
            self.gpa.free(body.calls);
        }
        self.functions.deinit(self.gpa);
        self.bodies.deinit(self.gpa);
    }

    fn admits(self: *Plan, root: FunctionId) std.mem.Allocator.Error!bool {
        const Frame = struct { id: FunctionId, next: usize = 0 };
        var stack: std.ArrayList(Frame) = .empty;
        defer stack.deinit(self.gpa);
        const root_body = (try self.prepare(root)) orelse return false;
        try self.keep(root, root_body);
        try stack.append(self.gpa, .{ .id = root });
        while (stack.items.len != 0) {
            const frame = &stack.items[stack.items.len - 1];
            const id = frame.id;
            const body = self.functions.get(id).?;
            if (frame.next == body.calls.len) {
                self.functions.getPtr(id).?.state = .accepted;
                try self.bodies.append(self.gpa, id);
                _ = stack.pop();
                continue;
            }
            const target = body.calls[frame.next];
            frame.next += 1;
            if (self.functions.get(target)) |known| {
                if (known.state != .accepted) return false;
            } else {
                const called = (try self.prepare(target)) orelse return false;
                try self.keep(target, called);
                try stack.append(self.gpa, .{ .id = target });
            }
        }
        return true;
    }

    fn keep(self: *Plan, id: FunctionId, body: Body) !void {
        errdefer self.gpa.free(body.blocks);
        errdefer self.gpa.free(body.calls);
        try self.functions.put(self.gpa, id, body);
    }

    fn prepare(self: *Plan, id: FunctionId) std.mem.Allocator.Error!?Body {
        if (self.module.isExternal(id)) return null;
        const f = self.module.functionOf(id);
        if (!scalar(f.return_type)) return null;
        for (f.locals, f.slot_roles) |ty, role| if (!scalar(ty) or role != .value) return null;
        var blocks: std.ArrayList(BlockId) = .empty;
        defer blocks.deinit(self.gpa);
        var calls: std.ArrayList(FunctionId) = .empty;
        defer calls.deinit(self.gpa);
        const seen = try self.gpa.alloc(bool, f.blocks.len);
        defer self.gpa.free(seen);
        @memset(seen, false);
        try blocks.append(self.gpa, f.entry);
        seen[f.entry.index()] = true;
        var cursor: usize = 0;
        while (cursor < blocks.items.len) : (cursor += 1) {
            const block = blocks.items[cursor];
            for (f.instsOf(block)) |inst| switch (f.tagOf(inst)) {
                .constant => if (!scalar(f.typeOf(inst)) and f.typeOf(inst) != .unit) return null,
                .load => if (!scalar(f.typeOf(inst))) return null,
                .add, .sub, .mul, .div, .neg => if (f.typeOf(inst) != .f32) return null,
                .cmp_eq, .cmp_ne, .cmp_lt, .cmp_le, .cmp_gt, .cmp_ge => {
                    const operands = f.binaryOf(inst);
                    if (!scalar(f.typeOf(operands.lhs)) or !scalar(f.typeOf(operands.rhs))) return null;
                },
                .call => {
                    if (!scalar(f.typeOf(inst))) return null;
                    try calls.append(self.gpa, f.callOf(inst).func);
                },
                .store => {},
                else => return null,
            };
            const term = f.terminatorOf(block);
            switch (f.tagOf(term)) {
                .ret => {},
                .jump => try appendBlock(self.gpa, &blocks, seen, f.targetOf(term)),
                .branch => {
                    const branch = f.branchOf(term);
                    try appendBlock(self.gpa, &blocks, seen, branch.then_block);
                    try appendBlock(self.gpa, &blocks, seen, branch.else_block);
                },
                else => return null,
            }
        }
        const kept_blocks = try blocks.toOwnedSlice(self.gpa);
        errdefer self.gpa.free(kept_blocks);
        return .{ .blocks = kept_blocks, .calls = try calls.toOwnedSlice(self.gpa) };
    }
};

fn appendBlock(gpa: std.mem.Allocator, blocks: *std.ArrayList(BlockId), seen: []bool, id: BlockId) !void {
    if (seen[id.index()]) return;
    seen[id.index()] = true;
    try blocks.append(gpa, id);
}

/// An unavailable device profile writes nothing. Its caller can preserve a
/// host function without pretending that function has a device implementation.
fn emit(gpa: std.mem.Allocator, w: *std.Io.Writer, module: *const Module, root: FunctionId, kind: Kind, projection: ?Projection) !bool {
    var plan: Plan = .{ .gpa = gpa, .module = module };
    defer plan.deinit();
    if (kind != .matmul and !try plan.admits(root)) return false;
    if (projection) |view| {
        var any = kind == .matmul and view.launch_support;
        for (plan.bodies.items) |id| any = any or view.definitions[id.index()];
        if (!any) return false;
    }
    const staged = kind != .matmul;
    const launch = if (projection) |view| view.launch_support else true;
    const software = if (projection) |view| view.software_bodies else true;
    if (staged and projection != null) {
        try w.print("module {{\n  gpu.module @linea_device{d} attributes {{sym_visibility = \"private\", spirv.target_env = #spirv.target_env<#spirv.vce<v1.3, [Shader], []>, #spirv.resource_limits<>>}} {{\n", .{root.index()});
    } else {
        try w.writeAll(if (staged)
            "module {\n  gpu.module @linea_device attributes {sym_visibility = \"private\", spirv.target_env = #spirv.target_env<#spirv.vce<v1.3, [Shader], []>, #spirv.resource_limits<>>} {\n"
        else
            "spirv.module Logical GLSL450 requires #spirv.vce<v1.3, [Shader], []> {\n");
    }
    // The production order remains exact. Inspection emits source bodies before
    // support, collecting references in the same instruction writer.
    if (projection == null) {
        try writeGlobals(w, kind);
        try w.writeAll(@embedFile("gpu/float32.mlir"));
    }
    var usage: DeviceUsage = .{};
    defer usage.deinit(gpa);
    for (plan.bodies.items) |id| {
        if (projection) |view| {
            if (!view.definitions[id.index()]) continue;
        }
        try writeFunction(gpa, w, module, id, plan.functions.get(id).?.blocks, projection, if (projection != null) &usage else null);
    }
    if (projection) |view| {
        if (launch and kind != .matmul) try usage.calls.put(gpa, root, {});
        for (plan.bodies.items) |id| {
            if (!view.definitions[id.index()] and usage.calls.contains(id)) try writeDeclaration(w, module, id, projection);
        }
        if (software) {
            try w.writeAll(@embedFile("gpu/float32.mlir"));
        } else {
            if (kind == .matmul and launch) {
                usage.helpers.insert(.mul);
                usage.helpers.insert(.add);
            }
            try writeHelperImports(w, usage.helpers);
        }
        if (launch) try writeGlobals(w, kind);
    }
    if (launch) {
        var name: std.Io.Writer.Allocating = .init(gpa);
        defer name.deinit();
        try writeDeviceName(&name.writer, root, projection);
        const template = switch (kind) {
            .map => @embedFile("gpu/map.mlir"),
            .reduce => @embedFile("gpu/reduce.mlir") ++ @embedFile("gpu/binary_map.mlir"),
            .matmul => @embedFile("gpu/matmul.mlir"),
        };
        const calls = try std.mem.replaceOwned(u8, gpa, template, "spirv.FunctionCall @ROOT", "func.call @ROOT");
        defer gpa.free(calls);
        const entry = try std.mem.replaceOwned(u8, gpa, calls, "@ROOT", name.written());
        defer gpa.free(entry);
        try w.writeAll(entry);
    }
    try w.writeAll(if (staged) "  }\n}\n" else "}\n");
    return true;
}

fn writeGlobals(w: *std.Io.Writer, kind: Kind) !void {
    try w.writeAll(switch (kind) {
        .map => @embedFile("gpu/globals.mlir"),
        .reduce => @embedFile("gpu/reduce_globals.mlir"),
        .matmul => @embedFile("gpu/matmul_globals.mlir"),
    });
}

/// SPIR-V conversion preserves the unprefixed linkage attribute. An ordinary
/// external func without this would become an invalid external spirv.func.
fn writeDeclaration(w: *std.Io.Writer, module: *const Module, id: FunctionId, projection: ?Projection) !void {
    const f = module.functionOf(id);
    try w.writeAll("    func.func private ");
    try writeDeviceName(w, id, projection);
    try w.writeByte('(');
    for (0..f.param_count) |i| {
        if (i != 0) try w.writeAll(", ");
        try w.writeAll(gpuType(f.locals[i]));
    }
    try w.print(") -> {s} attributes {{linkage_attributes = #spirv.linkage_attributes<linkage_name = \"", .{gpuType(f.return_type)});
    if (projection) |view| {
        if (view.display_names) |names| {
            if (names[id.index()]) |name| {
                try writeString(w, name);
                try w.writeAll("\", linkage_type = <Import>>}\n");
                return;
            }
        }
    }
    try w.print("linea_dev{d}\", linkage_type = <Import>>}}\n", .{id.index()});
}

fn writeFunction(gpa: std.mem.Allocator, w: *std.Io.Writer, module: *const Module, id: FunctionId, blocks: []const BlockId, projection: ?Projection, usage: ?*DeviceUsage) !void {
    const f = module.functionOf(id);
    try w.writeAll("    func.func ");
    try writeDeviceName(w, id, projection);
    try w.writeByte('(');
    for (0..f.param_count) |i| {
        if (i != 0) try w.writeAll(", ");
        try w.print("%p{d}: {s}", .{ i, gpuType(f.locals[i]) });
    }
    try w.print(") -> {s} {{\n", .{gpuType(f.return_type)});
    try w.writeAll("      %slot_index = arith.constant 0 : index\n");
    for (f.locals, 0..) |_, i| try w.print("      %s{d} = memref.alloca() : memref<1xi32, #spirv.storage_class<Function>>\n", .{i});
    for (0..f.param_count) |i| {
        if (f.locals[i] == .bool_) try w.print("      %encoded_p{d} = arith.extui %p{d} : i1 to i32\n", .{ i, i });
        try w.print("      memref.store %{s}{d}, %s{d}[%slot_index] : memref<1xi32, #spirv.storage_class<Function>>\n", .{ if (f.locals[i] == .bool_) "encoded_p" else "p", i, i });
    }
    try w.print("      cf.br ^b{d}\n", .{f.entry.index()});
    for (blocks) |block| {
        try w.print("    ^b{d}:\n", .{block.index()});
        for (f.instsOf(block)) |inst| {
            const n = inst.index();
            switch (f.tagOf(inst)) {
                .constant => {
                    if (f.typeOf(inst) == .unit) continue;
                    if (f.typeOf(inst) == .bool_) {
                        try w.print("      %v{d} = arith.constant {s}\n", .{ n, if (f.constantOf(inst) == 0) "false" else "true" });
                    } else {
                        const bits: i32 = @bitCast(@as(f32, @floatCast(f.floatConstantOf(inst))));
                        try w.print("      %v{d} = arith.constant {d} : i32\n", .{ n, bits });
                    }
                },
                .load => {
                    const local = f.localOf(inst);
                    if (f.typeOf(inst) == .bool_) {
                        try w.print("      %loaded{d} = memref.load %s{d}[%slot_index] : memref<1xi32, #spirv.storage_class<Function>>\n", .{ n, local.index() });
                        try w.print("      %zero{d} = arith.constant 0 : i32\n      %v{d} = arith.cmpi ne, %loaded{d}, %zero{d} : i32\n", .{ n, n, n, n });
                    } else try w.print("      %v{d} = memref.load %s{d}[%slot_index] : memref<1xi32, #spirv.storage_class<Function>>\n", .{ n, local.index() });
                },
                .store => {
                    const store = f.storeOf(inst);
                    const boolean = f.locals[store.local.index()] == .bool_;
                    if (boolean) try w.print("      %encoded{d} = arith.extui %v{d} : i1 to i32\n", .{ n, store.value.index() });
                    try w.print("      memref.store %{s}{d}, %s{d}[%slot_index] : memref<1xi32, #spirv.storage_class<Function>>\n", .{ if (boolean) "encoded" else "v", if (boolean) n else store.value.index(), store.local.index() });
                },
                .add, .sub, .mul, .div => {
                    const binary = f.binaryOf(inst);
                    try writeHelperCall(w, usage, Helper.arithmetic(f.tagOf(inst)), n, binary.lhs.index(), binary.rhs.index());
                },
                .neg => {
                    try w.print("      %sign{d} = arith.constant -2147483648 : i32\n      %v{d} = arith.xori %v{d}, %sign{d} : i32\n", .{ n, n, f.unaryOf(inst).index(), n });
                },
                .cmp_eq, .cmp_ne, .cmp_lt, .cmp_le, .cmp_gt, .cmp_ge => {
                    const binary = f.binaryOf(inst);
                    const name = @tagName(f.tagOf(inst))[4..];
                    if (f.typeOf(binary.lhs) == .f32) {
                        try writeHelperCall(w, usage, Helper.comparison(f.tagOf(inst)), n, binary.lhs.index(), binary.rhs.index());
                    } else {
                        try w.print("      %v{d} = arith.cmpi {s}{s}, %v{d}, %v{d} : i1\n", .{ n, if (f.tagOf(inst) == .cmp_eq or f.tagOf(inst) == .cmp_ne) "" else "u", name, binary.lhs.index(), binary.rhs.index() });
                    }
                },
                .call => {
                    const call = f.callOf(inst);
                    if (usage) |used| try used.calls.put(gpa, call.func, {});
                    try w.print("      %v{d} = func.call ", .{n});
                    try writeDeviceName(w, call.func, projection);
                    try w.writeByte('(');
                    for (call.args, 0..) |arg, i| {
                        if (i != 0) try w.writeAll(", ");
                        try w.print("%v{d}", .{arg.index()});
                    }
                    try w.writeAll(") : (");
                    for (call.args, 0..) |arg, i| {
                        if (i != 0) try w.writeAll(", ");
                        try w.writeAll(gpuType(f.typeOf(arg)));
                    }
                    try w.print(") -> {s}\n", .{gpuType(f.typeOf(inst))});
                },
                else => unreachable,
            }
        }
        const term = f.terminatorOf(block);
        switch (f.tagOf(term)) {
            .ret => try w.print("      return %v{d} : {s}\n", .{ f.unaryOf(term).index(), gpuType(f.return_type) }),
            .jump => try w.print("      cf.br ^b{d}\n", .{f.targetOf(term).index()}),
            .branch => {
                const branch = f.branchOf(term);
                try w.print("      cf.cond_br %v{d}, ^b{d}, ^b{d}\n", .{ branch.cond.index(), branch.then_block.index(), branch.else_block.index() });
            },
            else => unreachable,
        }
    }
    try w.writeAll("    }\n");
}

/// Verify once for the whole device-emission request, before traversing IDs.
/// Source text owns no compiler state and can be serialized by the driver.
pub fn emitAll(gpa: std.mem.Allocator, module: *const Module, sink: *Sink) !?[]Source {
    return emitSources(gpa, module, sink, null);
}

/// Inspection shares admission and emission with production. Only the choice
/// of source definitions versus matching import declarations differs.
pub fn emitAllInspected(gpa: std.mem.Allocator, module: *const Module, sink: *Sink, projection: Projection) !?[]Source {
    std.debug.assert(projection.definitions.len == module.functions.len);
    return emitSources(gpa, module, sink, projection);
}

fn emitSources(gpa: std.mem.Allocator, module: *const Module, sink: *Sink, projection: ?Projection) !?[]Source {
    if (module.gpu_function == .none and module.gpu_reduce_function == .none and module.gpu_matmul_function == .none) return try gpa.alloc(Source, 0);
    if (!try verify(gpa, module, sink)) return null;
    const roots = try candidates(gpa, module);
    defer gpa.free(roots);
    var sources: std.ArrayList(Source) = .empty;
    errdefer {
        for (sources.items) |source| gpa.free(source.mlir);
        sources.deinit(gpa);
    }
    var all: std.ArrayList(Candidate) = .empty;
    defer all.deinit(gpa);
    try all.appendSlice(gpa, roots);
    if (module.gpu_matmul_function != .none) try all.append(gpa, .{ .function = module.gpu_matmul_function, .kind = .matmul });
    for (all.items) |root| {
        var output = std.Io.Writer.Allocating.init(gpa);
        defer output.deinit();
        if (!try emit(gpa, &output.writer, module, root.function, root.kind, projection)) continue;
        const text = try output.toOwnedSlice();
        errdefer gpa.free(text);
        try sources.append(gpa, .{ .function = root.function, .kind = root.kind, .format = if (root.kind == .matmul) .spirv else .staging, .mlir = text });
    }
    return try sources.toOwnedSlice(gpa);
}
