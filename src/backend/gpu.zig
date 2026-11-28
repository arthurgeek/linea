//! Device code from checked MIR. Float32 values are carried as IEEE bits;
//! arithmetic calls the integer-only binary32 implementation.
const std = @import("std");
const mir_mod = @import("../mir/mir.zig");
const Module = mir_mod.Module;
const Mir = mir_mod.Mir;
const FunctionId = mir_mod.FunctionId;
const InstId = mir_mod.InstId;
const BlockId = mir_mod.BlockId;
const LocalId = mir_mod.LocalId;
const gpu_ranges = @import("gpu_ranges.zig");
const Ranges = gpu_ranges.Ranges;
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
const Buffer = union(enum) {
    local: LocalId,
    returned: InstId,
    argument: struct { call: InstId, index: u32 },
    output,

    fn ty(self: Buffer, f: *const Mir) TypeId {
        return switch (self) {
            .local => |local| f.locals[local.index()],
            .returned => |call| f.typeOf(call),
            .argument => |arg| f.typeOf(f.callOf(arg.call).args[arg.index]),
            .output => f.return_type,
        };
    }

    fn write(self: Buffer, w: *std.Io.Writer) !void {
        switch (self) {
            .local => |local| try w.print("%s{d}", .{local.index()}),
            .returned => |call| try w.print("%r{d}", .{call.index()}),
            .argument => |arg| try w.print("%arg{d}_{d}", .{ arg.call.index(), arg.index }),
            .output => try w.writeAll("%result"),
        }
    }
};
const Address = struct {
    buffer: Buffer,
    offset: gpu_ranges.Interval = gpu_ranges.Interval.constant(0),

    fn fits(self: Address, module: *const Module, f: *const Mir, ty: TypeId) bool {
        const words = numericWords(module, ty) orelse return false;
        const capacity = module.layoutOf(self.buffer.ty(f)).size;
        return !self.offset.empty and self.offset.alignment >= 2 and
            @as(u64, self.offset.max) + @as(u64, words) * 4 <= capacity;
    }

    fn canCopy(source: Address, destination: Address, module: *const Module, f: *const Mir, ty: TypeId) bool {
        if (!source.fits(module, f, ty) or !destination.fits(module, f, ty)) return false;
        const bytes = module.layoutOf(ty).size;
        if (bytes == 0 or !std.meta.eql(source.buffer, destination.buffer)) return true;
        const a = source.offset;
        const b = destination.offset;
        return (a.min == a.max and b.min == b.max and a.min == b.min) or
            @as(u64, a.max) + bytes <= b.min or @as(u64, b.max) + bytes <= a.min;
    }
};
const Body = struct {
    blocks: []BlockId,
    calls: []FunctionId,
    indices: Ranges,
    addresses: []?Address,
    state: Visit = .visiting,

    fn deinit(self: *Body, gpa: std.mem.Allocator) void {
        gpa.free(self.blocks);
        gpa.free(self.calls);
        gpa.free(self.addresses);
        self.indices.deinit(gpa);
    }
};

fn numericWords(module: *const Module, ty: TypeId) ?u32 {
    if (ty == .f32) return 1;
    if (module.types.matrixInfo(ty)) |matrix| {
        if (matrix.element != .f32) return null;
    } else {
        var element = ty;
        while (module.types.get(element) == .array) element = module.types.get(element).array.element;
        if (element != .f32) return null;
    }
    const layout = module.layoutOf(ty);
    if (layout.too_wide or layout.size % 4 != 0) return null;
    return layout.size / 4;
}

fn aggregate(module: *const Module, ty: TypeId) bool {
    return !scalar(ty) and numericWords(module, ty) != null;
}

fn writeBufferType(w: *std.Io.Writer, module: *const Module, ty: TypeId) !void {
    try w.print("memref<{d}xi32, #spirv.storage_class<Function>>", .{slotWords(module, ty)});
}

fn writeAbiType(w: *std.Io.Writer, module: *const Module, ty: TypeId) !void {
    if (aggregate(module, ty))
        try w.print("memref<{d}xi32, #spirv.storage_class<Function>>", .{slotWords(module, ty)})
    else
        try w.writeAll(gpuType(ty));
}

fn slotWords(module: *const Module, ty: TypeId) u32 {
    return @max(numericWords(module, ty) orelse 1, 1);
}

/// Addresses retain their allocation origin and a checked byte interval.
/// Integer narrowing alone cannot establish that an access stays in storage.
fn addressFacts(gpa: std.mem.Allocator, module: *const Module, f: *const Mir, ranges: *const Ranges) ![]?Address {
    const addresses = try gpa.alloc(?Address, f.insts.len);
    @memset(addresses, null);
    for (addresses, 0..) |*address, i| {
        const inst = InstId.at(@intCast(i));
        if (f.resultRoleOf(inst) != .managed_address) continue;
        switch (f.tagOf(inst)) {
            .addr_of => {
                const local = f.localOf(inst);
                if (f.slotRoleOf(local) == .value and numericWords(module, f.locals[local.index()]) != null)
                    address.* = .{ .buffer = .{ .local = local } };
            },
            .load => {
                const local = f.localOf(inst);
                if (f.resultRoleOf(inst) == .managed_address and aggregate(module, f.typeOf(inst)) and local.index() < f.param_count)
                    address.* = .{ .buffer = .{ .local = local } };
            },
            .call => if (aggregate(module, f.typeOf(inst))) {
                address.* = .{ .buffer = .{ .returned = inst } };
            },
            .field_addr => {
                const field = f.fieldAddrOf(inst);
                const base = addresses[field.base.index()] orelse continue;
                if (!valueOfType(f, field.offset, .u64)) continue;
                const offset = ranges.at(field.offset, inst) orelse continue;
                const at: Address = .{ .buffer = base.buffer, .offset = gpu_ranges.operation(.add, base.offset, offset) orelse continue };
                if (at.fits(module, f, f.typeOf(inst))) address.* = at;
            },
            else => {},
        }
    }
    return addresses;
}

fn scalar(ty: TypeId) bool {
    return ty == .f32 or ty == .bool_;
}

fn valueOfType(f: *const Mir, inst: InstId, ty: TypeId) bool {
    return f.resultRoleOf(inst) == .value and f.typeOf(inst) == ty;
}

/// Scalar ABI arguments and results use registers. Aggregate values are copied
/// into the exact argument or output buffer that the emitter allocates.
fn abiOperand(module: *const Module, f: *const Mir, addresses: []const ?Address, inst: InstId, ty: TypeId, destination: Buffer) bool {
    if (scalar(ty)) return valueOfType(f, inst, ty);
    if (f.typeOf(inst) != ty or !aggregate(module, ty)) return false;
    const source = addresses[inst.index()] orelse return false;
    return source.canCopy(.{ .buffer = destination }, module, f, ty);
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
            body.deinit(self.gpa);
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
        var owned = body;
        errdefer owned.deinit(self.gpa);
        try self.functions.put(self.gpa, id, body);
    }

    fn prepare(self: *Plan, id: FunctionId) std.mem.Allocator.Error!?Body {
        if (self.module.isExternal(id)) return null;
        const f = self.module.functionOf(id);
        if (!scalar(f.return_type) and !aggregate(self.module, f.return_type)) return null;
        var indices = (try Ranges.init(self.gpa, f)) orelse return null;
        var retained = false;
        defer if (!retained) indices.deinit(self.gpa);
        const params = self.module.types.callableParams(self.module.types.get(f.signature).callable);
        for (f.locals, f.slot_roles, 0..) |ty, role, i| {
            if (i < f.param_count) {
                const param = params[i];
                if (param.convention == .inout or param.stable_address) return null;
                if (aggregate(self.module, ty)) continue;
            }
            if (role != .value) return null;
            if (scalar(ty)) continue;
            if (i < f.param_count) return null;
            if (ty == .u64 and indices.loops.local_loops[i] != .none) continue;
            if (numericWords(self.module, ty) == null) return null;
        }
        const addresses = try addressFacts(self.gpa, self.module, f, &indices);
        defer if (!retained) self.gpa.free(addresses);
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
                .constant => if (!scalar(f.typeOf(inst)) and f.typeOf(inst) != .unit and indices.at(inst, inst) == null) return null,
                .load => {
                    const ty = f.typeOf(inst);
                    if (aggregate(self.module, ty)) {
                        if (addresses[inst.index()] == null) return null;
                    } else if (!valueOfType(f, inst, f.locals[f.localOf(inst).index()]) or
                        (!scalar(ty) and indices.at(inst, inst) == null)) return null;
                },
                .neg => if (f.typeOf(inst) != .f32 or !valueOfType(f, f.unaryOf(inst), .f32)) return null,
                .add, .sub, .mul, .div, .rem => {
                    const ty = f.typeOf(inst);
                    const operands = f.binaryOf(inst);
                    if (!valueOfType(f, operands.lhs, ty) or !valueOfType(f, operands.rhs, ty)) return null;
                    if (ty == .f32) {
                        if (f.tagOf(inst) == .rem) return null;
                    } else if (ty != .u64 or indices.at(inst, inst) == null) return null;
                },
                .cmp_eq, .cmp_ne, .cmp_lt, .cmp_le, .cmp_gt, .cmp_ge => {
                    const operands = f.binaryOf(inst);
                    const ty = f.typeOf(operands.lhs);
                    if (!valueOfType(f, operands.lhs, ty) or !valueOfType(f, operands.rhs, ty)) return null;
                    if (!scalar(ty) and (ty != .u64 or indices.at(operands.lhs, inst) == null or indices.at(operands.rhs, inst) == null)) return null;
                },
                .addr_of, .field_addr => if (addresses[inst.index()] == null) return null,
                .load_indirect => {
                    const address = addresses[f.unaryOf(inst).index()] orelse return null;
                    if (f.typeOf(inst) != .f32 or !address.fits(self.module, f, .f32)) return null;
                },
                .store_indirect => {
                    const pair = f.binaryOf(inst);
                    const address = addresses[pair.lhs.index()] orelse return null;
                    if (f.typeOf(inst) != .f32 or !valueOfType(f, pair.rhs, .f32) or !address.fits(self.module, f, .f32)) return null;
                },
                .copy_value, .move_value => {
                    const pair = f.binaryOf(inst);
                    const destination = addresses[pair.lhs.index()] orelse return null;
                    const source = addresses[pair.rhs.index()] orelse return null;
                    if (!source.canCopy(destination, self.module, f, f.typeOf(inst))) return null;
                },
                .check => if (indices.at(inst, inst) == null) return null,
                .call => {
                    const call = f.callOf(inst);
                    const callee = self.module.functionOf(call.func);
                    if (call.args.len != callee.param_count or callee.return_type != f.typeOf(inst)) return null;
                    if (scalar(f.typeOf(inst))) {
                        if (f.resultRoleOf(inst) != .value) return null;
                    } else if (addresses[inst.index()] == null) return null;
                    for (call.args, 0..) |arg, i| {
                        const destination: Buffer = .{ .argument = .{ .call = inst, .index = @intCast(i) } };
                        if (!abiOperand(self.module, f, addresses, arg, callee.locals[i], destination)) return null;
                    }
                    try calls.append(self.gpa, call.func);
                },
                .store => {
                    const stored = f.storeOf(inst);
                    const ty = f.locals[stored.local.index()];
                    if (!valueOfType(f, stored.value, ty) or (!scalar(ty) and (ty != .u64 or indices.at(stored.value, inst) == null))) return null;
                },
                else => return null,
            };
            const term = f.terminatorOf(block);
            switch (f.tagOf(term)) {
                .ret => if (!abiOperand(self.module, f, addresses, f.unaryOf(term), f.return_type, .output)) return null,
                .jump => try appendBlock(self.gpa, &blocks, seen, f.targetOf(term)),
                .branch => {
                    const branch = f.branchOf(term);
                    if (!valueOfType(f, branch.cond, .bool_)) return null;
                    if (indices.knownBranch(term)) |target| {
                        try appendBlock(self.gpa, &blocks, seen, target);
                    } else {
                        try appendBlock(self.gpa, &blocks, seen, branch.then_block);
                        try appendBlock(self.gpa, &blocks, seen, branch.else_block);
                    }
                },
                else => return null,
            }
        }
        const kept_blocks = try blocks.toOwnedSlice(self.gpa);
        errdefer self.gpa.free(kept_blocks);
        const kept_calls = try calls.toOwnedSlice(self.gpa);
        retained = true;
        return .{ .blocks = kept_blocks, .calls = kept_calls, .indices = indices, .addresses = addresses };
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
        try writeFunction(gpa, w, module, id, plan.functions.get(id).?, projection, if (projection != null) &usage else null);
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
        try writeAbiType(w, module, f.locals[i]);
    }
    if (aggregate(module, f.return_type)) {
        if (f.param_count != 0) try w.writeAll(", ");
        try writeAbiType(w, module, f.return_type);
    }
    try w.print(") -> {s} attributes {{linkage_attributes = #spirv.linkage_attributes<linkage_name = \"", .{if (aggregate(module, f.return_type)) "()" else gpuType(f.return_type)});
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

fn writeBufferCopy(w: *std.Io.Writer, module: *const Module, f: *const Mir, prefix: []const u8, source: Buffer, source_offset: ?InstId, destination: Buffer, destination_offset: ?InstId, words: u32) !void {
    if (words == 0) return;
    var source_name: [96]u8 = undefined;
    var destination_name: [96]u8 = undefined;
    if (source_offset) |at|
        try w.print("      %{s}_src = arith.index_castui %a{d} : i32 to index\n", .{ prefix, at.index() });
    if (destination_offset) |at|
        try w.print("      %{s}_dst = arith.index_castui %a{d} : i32 to index\n", .{ prefix, at.index() });
    try w.print("      %{s}_count = arith.constant {d} : index\n      scf.for %{s}_i = %slot_index to %{s}_count step %index_one {{\n", .{ prefix, words, prefix, prefix });
    try w.print("        %{s}_from = arith.addi %{s}, %{s}_i : index\n", .{ prefix, if (source_offset != null) try std.fmt.bufPrint(&source_name, "{s}_src", .{prefix}) else "slot_index", prefix });
    try w.print("        %{s}_to = arith.addi %{s}, %{s}_i : index\n", .{ prefix, if (destination_offset != null) try std.fmt.bufPrint(&destination_name, "{s}_dst", .{prefix}) else "slot_index", prefix });
    try w.print("        %{s}_value = memref.load ", .{prefix});
    try source.write(w);
    try w.print("[%{s}_from] : ", .{prefix});
    try writeBufferType(w, module, source.ty(f));
    try w.print("\n        memref.store %{s}_value, ", .{prefix});
    try destination.write(w);
    try w.print("[%{s}_to] : ", .{prefix});
    try writeBufferType(w, module, destination.ty(f));
    try w.writeAll("\n      }\n");
}

fn writeCopy(w: *std.Io.Writer, module: *const Module, f: *const Mir, body: Body, inst: InstId) !void {
    const pair = f.binaryOf(inst);
    var name: [64]u8 = undefined;
    const prefix = try std.fmt.bufPrint(&name, "copy{d}", .{inst.index()});
    try writeBufferCopy(w, module, f, prefix, body.addresses[pair.rhs.index()].?.buffer, pair.rhs, body.addresses[pair.lhs.index()].?.buffer, pair.lhs, numericWords(module, f.typeOf(inst)).?);
}

fn writeFunction(gpa: std.mem.Allocator, w: *std.Io.Writer, module: *const Module, id: FunctionId, body: Body, projection: ?Projection, usage: ?*DeviceUsage) !void {
    const f = module.functionOf(id);
    try w.writeAll("    func.func ");
    try writeDeviceName(w, id, projection);
    try w.writeByte('(');
    for (0..f.param_count) |i| {
        if (i != 0) try w.writeAll(", ");
        try w.print("%{s}{d}: ", .{ if (aggregate(module, f.locals[i])) "s" else "p", i });
        try writeAbiType(w, module, f.locals[i]);
    }
    if (aggregate(module, f.return_type)) {
        if (f.param_count != 0) try w.writeAll(", ");
        try w.writeAll("%result: ");
        try writeAbiType(w, module, f.return_type);
    }
    try w.print(") -> {s} {{\n", .{if (aggregate(module, f.return_type)) "()" else gpuType(f.return_type)});
    try w.writeAll("      %slot_index = arith.constant 0 : index\n");
    try w.writeAll("      %word_bytes = arith.constant 4 : i32\n      %index_one = arith.constant 1 : index\n");
    for (f.locals, 0..) |ty, i| {
        if (i < f.param_count and aggregate(module, ty)) continue;
        try w.print("      %s{d} = memref.alloca() : memref<{d}xi32, #spirv.storage_class<Function>>\n", .{ i, slotWords(module, ty) });
    }
    for (body.blocks) |block| for (f.instsOf(block)) |inst| {
        if (f.tagOf(inst) != .call) continue;
        if (aggregate(module, f.typeOf(inst))) {
            try w.print("      %r{d} = memref.alloca() : ", .{inst.index()});
            try writeAbiType(w, module, f.typeOf(inst));
            try w.writeByte('\n');
        }
        for (f.callOf(inst).args, 0..) |arg, i| if (aggregate(module, f.typeOf(arg))) {
            try w.print("      %arg{d}_{d} = memref.alloca() : ", .{ inst.index(), i });
            try writeAbiType(w, module, f.typeOf(arg));
            try w.writeByte('\n');
        };
    };
    for (0..f.param_count) |i| {
        if (aggregate(module, f.locals[i])) continue;
        if (f.locals[i] == .bool_) try w.print("      %encoded_p{d} = arith.extui %p{d} : i1 to i32\n", .{ i, i });
        try w.print("      memref.store %{s}{d}, %s{d}[%slot_index] : memref<1xi32, #spirv.storage_class<Function>>\n", .{ if (f.locals[i] == .bool_) "encoded_p" else "p", i, i });
    }
    try w.print("      cf.br ^b{d}\n", .{f.entry.index()});
    for (body.blocks) |block| {
        try w.print("    ^b{d}:\n", .{block.index()});
        for (f.instsOf(block)) |inst| {
            const n = inst.index();
            switch (f.tagOf(inst)) {
                .constant => {
                    if (f.typeOf(inst) == .unit) continue;
                    if (f.typeOf(inst) == .bool_) {
                        try w.print("      %v{d} = arith.constant {s}\n", .{ n, if (f.constantOf(inst) == 0) "false" else "true" });
                    } else {
                        const bits: i32 = if (f.typeOf(inst) == .u64)
                            @bitCast(@as(u32, @intCast(f.constantOf(inst))))
                        else
                            @bitCast(@as(f32, @floatCast(f.floatConstantOf(inst))));
                        try w.print("      %v{d} = arith.constant {d} : i32\n", .{ n, bits });
                    }
                },
                .load => {
                    const local = f.localOf(inst);
                    if (aggregate(module, f.typeOf(inst))) {
                        try w.print("      %a{d} = arith.constant 0 : i32\n", .{n});
                        continue;
                    }
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
                .add, .sub, .mul, .div, .rem => {
                    const binary = f.binaryOf(inst);
                    if (f.typeOf(inst) == .f32) {
                        try writeHelperCall(w, usage, Helper.arithmetic(f.tagOf(inst)), n, binary.lhs.index(), binary.rhs.index());
                    } else {
                        const op = switch (f.tagOf(inst)) {
                            .add => "addi",
                            .sub => "subi",
                            .mul => "muli",
                            .div => "divui",
                            .rem => "remui",
                            else => unreachable,
                        };
                        try w.print("      %v{d} = arith.{s} %v{d}, %v{d} : i32\n", .{ n, op, binary.lhs.index(), binary.rhs.index() });
                    }
                },
                .addr_of => try w.print("      %a{d} = arith.constant 0 : i32\n", .{n}),
                .field_addr => {
                    const field = f.fieldAddrOf(inst);
                    try w.print("      %words{d} = arith.divui %v{d}, %word_bytes : i32\n      %a{d} = arith.addi %a{d}, %words{d} : i32\n", .{ n, field.offset.index(), n, field.base.index(), n });
                },
                .load_indirect => {
                    const pointer = f.unaryOf(inst);
                    const address = body.addresses[pointer.index()].?;
                    try w.print("      %index{d} = arith.index_castui %a{d} : i32 to index\n      %v{d} = memref.load ", .{ n, pointer.index(), n });
                    try address.buffer.write(w);
                    try w.print("[%index{d}] : ", .{n});
                    try writeBufferType(w, module, address.buffer.ty(f));
                    try w.writeByte('\n');
                },
                .store_indirect => {
                    const pair = f.binaryOf(inst);
                    const address = body.addresses[pair.lhs.index()].?;
                    try w.print("      %index{d} = arith.index_castui %a{d} : i32 to index\n      memref.store %v{d}, ", .{ n, pair.lhs.index(), pair.rhs.index() });
                    try address.buffer.write(w);
                    try w.print("[%index{d}] : ", .{n});
                    try writeBufferType(w, module, address.buffer.ty(f));
                    try w.writeByte('\n');
                },
                .copy_value, .move_value => try writeCopy(w, module, f, body, inst),
                .check => {
                    const value = f.checkOf(inst).value;
                    try w.print("      %v{d} = arith.ori %v{d}, %v{d} : {s}\n", .{ n, value.index(), value.index(), gpuType(f.typeOf(inst)) });
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
                        try w.print("      %v{d} = arith.cmpi {s}{s}, %v{d}, %v{d} : {s}\n", .{ n, if (f.tagOf(inst) == .cmp_eq or f.tagOf(inst) == .cmp_ne) "" else "u", name, binary.lhs.index(), binary.rhs.index(), gpuType(f.typeOf(binary.lhs)) });
                    }
                },
                .call => {
                    const call = f.callOf(inst);
                    if (usage) |used| try used.calls.put(gpa, call.func, {});
                    for (call.args, 0..) |arg, i| if (aggregate(module, f.typeOf(arg))) {
                        var name: [64]u8 = undefined;
                        const prefix = try std.fmt.bufPrint(&name, "call{d}_arg{d}", .{ n, i });
                        try writeBufferCopy(w, module, f, prefix, body.addresses[arg.index()].?.buffer, arg, .{ .argument = .{ .call = inst, .index = @intCast(i) } }, null, numericWords(module, f.typeOf(arg)).?);
                    };
                    if (aggregate(module, f.typeOf(inst)))
                        try w.writeAll("      func.call ")
                    else
                        try w.print("      %v{d} = func.call ", .{n});
                    try writeDeviceName(w, call.func, projection);
                    try w.writeByte('(');
                    for (call.args, 0..) |arg, i| {
                        if (i != 0) try w.writeAll(", ");
                        if (aggregate(module, f.typeOf(arg)))
                            try w.print("%arg{d}_{d}", .{ n, i })
                        else
                            try w.print("%v{d}", .{arg.index()});
                    }
                    if (aggregate(module, f.typeOf(inst))) {
                        if (call.args.len != 0) try w.writeAll(", ");
                        try w.print("%r{d}", .{n});
                    }
                    try w.writeAll(") : (");
                    for (call.args, 0..) |arg, i| {
                        if (i != 0) try w.writeAll(", ");
                        try writeAbiType(w, module, f.typeOf(arg));
                    }
                    if (aggregate(module, f.typeOf(inst))) {
                        if (call.args.len != 0) try w.writeAll(", ");
                        try writeAbiType(w, module, f.typeOf(inst));
                    }
                    try w.print(") -> {s}\n", .{if (aggregate(module, f.typeOf(inst))) "()" else gpuType(f.typeOf(inst))});
                    if (aggregate(module, f.typeOf(inst))) try w.print("      %a{d} = arith.constant 0 : i32\n", .{n});
                },
                else => unreachable,
            }
        }
        const term = f.terminatorOf(block);
        switch (f.tagOf(term)) {
            .ret => if (aggregate(module, f.return_type)) {
                const value = f.unaryOf(term);
                var name: [64]u8 = undefined;
                const prefix = try std.fmt.bufPrint(&name, "return{d}", .{term.index()});
                try writeBufferCopy(w, module, f, prefix, body.addresses[value.index()].?.buffer, value, .output, null, numericWords(module, f.return_type).?);
                try w.writeAll("      return\n");
            } else try w.print("      return %v{d} : {s}\n", .{ f.unaryOf(term).index(), gpuType(f.return_type) }),
            .jump => try w.print("      cf.br ^b{d}\n", .{f.targetOf(term).index()}),
            .branch => {
                const branch = f.branchOf(term);
                if (body.indices.knownBranch(term)) |target|
                    try w.print("      cf.br ^b{d}\n", .{target.index()})
                else
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

test "device proof checks scalar uses, parameter conventions and complete copy extents" {
    const Harness = @import("../mir/verify.zig").Harness;
    const span = @import("../support/span.zig").Span.empty;
    const Case = enum {
        valid,
        address_comparison,
        address_arithmetic,
        address_negation,
        address_argument,
        address_return,
        address_store,
        address_indirect_store,
        value_load_address,
        inout_parameter,
        stable_parameter,
        boolean_offset,
        misaligned,
        wide_copy,
        wide_destination,
        empty_load,
        empty_store,
        empty_at_end,
        empty_past_end,
        overlapping_copy,
        disjoint_copy,
        identical_copy,
        wide_argument,
        wide_return,
    };
    var unexpected = false;
    for (std.enums.values(Case)) |case| {
        const gpa = std.testing.allocator;
        var b = Mir.Builder.init(gpa);
        defer b.deinit();
        b.return_type = if (case == .wide_return) Harness.float_pair else .f32;
        b.param_count = 1;
        const block = try b.addBlock();
        const param = try b.addLocal(.f32, .value);
        const array_ty = switch (case) {
            .overlapping_copy, .disjoint_copy, .identical_copy => Harness.float_pairs,
            .empty_load, .empty_store => Harness.empty_floats,
            else => Harness.float_pair,
        };
        const array = try b.addLocal(array_ty, .value);
        const value = try b.addInst(block, .{ .tag = .load, .ty = .f32, .span = span, .data = .{ .local = param } });
        const address_ty: TypeId = if (case == .wide_argument or case == .wide_return) Harness.float_pair else .f32;
        const address = try b.addInst(block, .{ .tag = .addr_of, .result_role = .managed_address, .ty = address_ty, .span = span, .data = .{ .local = param } });
        const base = try b.addInst(block, .{ .tag = .addr_of, .result_role = .managed_address, .ty = array_ty, .span = span, .data = .{ .local = array } });
        const byte_offset: u32 = switch (case) {
            .boolean_offset, .identical_copy => 0,
            .misaligned => 2,
            .disjoint_copy, .empty_at_end => 8,
            .empty_past_end => 12,
            else => 4,
        };
        const offset = try b.addInst(block, .{ .tag = .constant, .ty = if (case == .boolean_offset) .bool_ else .u64, .span = span, .data = .{ .constant = byte_offset } });
        const part_ty: TypeId = if (case == .empty_at_end or case == .empty_past_end) Harness.empty_floats else .f32;
        const part = if (case == .empty_load or case == .empty_store) base else try b.addInst(block, .{ .tag = .field_addr, .result_role = .managed_address, .ty = part_ty, .span = span, .data = .{ .field = .{ .base = base, .offset = offset } } });
        var returned = value;
        switch (case) {
            .address_comparison, .address_arithmetic => _ = try b.addInst(block, .{ .tag = if (case == .address_comparison) .cmp_eq else .add, .ty = if (case == .address_comparison) .bool_ else .f32, .span = span, .data = .{ .binary = .{ .lhs = address, .rhs = address } } }),
            .address_negation => _ = try b.addInst(block, .{ .tag = .neg, .ty = .f32, .span = span, .data = .{ .unary = address } }),
            .address_argument, .wide_argument => _ = try b.addCall(block, .value, .f32, span, .at(1), &.{address}),
            .address_return => returned = address,
            .wide_return => returned = address,
            .address_store => _ = try b.addInst(block, .{ .tag = .store, .ty = .f32, .span = span, .data = .{ .store = .{ .local = param, .value = address } } }),
            .address_indirect_store => _ = try b.addInst(block, .{ .tag = .store_indirect, .ty = .f32, .span = span, .data = .{ .binary = .{ .lhs = address, .rhs = address } } }),
            .value_load_address => _ = try b.addInst(block, .{ .tag = .load_indirect, .ty = .f32, .span = span, .data = .{ .unary = value } }),
            .empty_load => _ = try b.addInst(block, .{ .tag = .load_indirect, .ty = .f32, .span = span, .data = .{ .unary = base } }),
            .empty_store => _ = try b.addInst(block, .{ .tag = .store_indirect, .ty = .f32, .span = span, .data = .{ .binary = .{ .lhs = base, .rhs = value } } }),
            .empty_at_end, .empty_past_end => _ = try b.addInst(block, .{ .tag = .copy_value, .ty = Harness.empty_floats, .span = span, .data = .{ .binary = .{ .lhs = base, .rhs = part } } }),
            .wide_destination => _ = try b.addInst(block, .{ .tag = .move_value, .ty = Harness.float_pair, .span = span, .data = .{ .binary = .{ .lhs = address, .rhs = base } } }),
            .wide_copy, .overlapping_copy, .disjoint_copy, .identical_copy => _ = try b.addInst(block, .{ .tag = .copy_value, .ty = Harness.float_pair, .span = span, .data = .{ .binary = .{ .lhs = base, .rhs = if (case == .wide_copy) address else part } } }),
            else => {},
        }
        _ = try b.setTerminator(block, .{ .tag = .ret, .ty = .unit, .span = span, .data = .{ .unary = returned } });
        var callee = Mir.Builder.init(gpa);
        defer callee.deinit();
        callee.param_count = 1;
        callee.return_type = .f32;
        const cb = try callee.addBlock();
        _ = try callee.addLocal(if (case == .wide_argument) Harness.float_pair else .f32, if (case == .wide_argument) .managed_address else .value);
        const zero = try callee.addInst(cb, .{ .tag = .constant, .ty = .f32, .span = span, .data = .{ .constant = 0 } });
        _ = try callee.setTerminator(cb, .{ .tag = .ret, .ty = .unit, .span = span, .data = .{ .unary = zero } });
        const functions = try gpa.dupe(Mir, &.{ try b.finish(block, .from(0)), try callee.finish(cb, .from(0)) });
        var harness = try Harness.initShaped(gpa, functions, &.{ .{}, .{ .conventions = &.{.read} } });
        defer harness.deinit();
        const p = &@constCast(harness.module.types.callable_params)[harness.module.types.get(functions[0].signature).callable.first_param];
        if (case == .inout_parameter) p.convention = .inout;
        if (case == .stable_parameter) p.stable_address = true;
        switch (case) {
            .valid => try std.testing.expect((try harness.run()).ok),
            .address_arithmetic,
            .address_negation,
            .address_argument,
            .address_return,
            .address_store,
            .address_indirect_store,
            .value_load_address,
            .inout_parameter,
            .stable_parameter,
            .wide_copy,
            .wide_argument,
            .wide_return,
            => try std.testing.expect(!(try harness.run()).ok),
            else => {},
        }
        if (case == .valid) {
            // A data-dependent word offset can coincide with a fixed one
            // on some iterations and be disjoint on others.
            const start: Address = .{ .buffer = .{ .local = array } };
            const selected: Address = .{ .buffer = start.buffer, .offset = .{ .min = 0, .max = 4, .alignment = 2 } };
            try std.testing.expect(!start.canCopy(selected, &harness.module, &functions[0], .f32));
            try std.testing.expect(!selected.canCopy(start, &harness.module, &functions[0], .f32));
        }
        var plan: Plan = .{ .gpa = gpa, .module = &harness.module };
        defer plan.deinit();
        const admitted = try plan.admits(.at(0));
        const expected = switch (case) {
            .valid, .disjoint_copy, .identical_copy, .empty_at_end => true,
            else => false,
        };
        if (admitted != expected) {
            std.debug.print("unexpected device admission for {s}: {}\n", .{ @tagName(case), admitted });
            unexpected = true;
        }
    }
    try std.testing.expect(!unexpected);
}
