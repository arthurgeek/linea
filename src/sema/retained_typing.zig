//! Attachment of an immutable checked type artifact to relocated expanded syntax.
const std = @import("std");
const types = @import("types.zig");
const node = @import("../syntax/node.zig");
const relocation_mod = @import("../syntax/relocation.zig");
const Relocation = relocation_mod.Relocation;
const Domain = relocation_mod.Domain;
const Allocator = std.mem.Allocator;

/// Storage belongs to a caller arena; unchanged tables and spellings borrow
/// `saved`, which must outlive this view and any builder reopened from it.
/// Do not call Typing.deinit on this borrowed view. Contextual constraints,
/// capabilities and implementation decisions must be prepared again before
/// checking additional bodies in the attached program.
pub fn attach(gpa: Allocator, saved: *const types.Typing, relocation: Relocation) !types.Typing {
    var result = saved.*;
    inline for (std.meta.fields(types.Typing)) |field| {
        try attachField(field, gpa, saved, relocation, &result);
    }
    result.defaults = .{};
    var defaults = saved.defaults.values.iterator();
    while (defaults.next()) |entry| {
        const decl: u32 = @intCast(entry.key_ptr.* >> 32);
        const param: u32 = @truncate(entry.key_ptr.*);
        try result.defaults.note(gpa, rawDecl(relocation, decl), param, entry.value_ptr.*);
    }
    result.impl_index = try types.ImplIndex.build(gpa, result.implementations);
    result.supply_index = try supplyIndex(gpa, relocation, &saved.supply_index);
    result.call_index = try types.CallIndex.build(gpa, @intCast(result.expr_types.len), &result);
    return result;
}

fn attachField(comptime field: std.builtin.Type.StructField, gpa: Allocator, saved: *const types.Typing, relocation: Relocation, result: *types.Typing) !void {
    const name = field.name;
    if (comptime in(name, &.{
        "literal_values",          "conversion_targets",      "integer_properties",  "selected_places",     "place_projections",
        "implicit_test_successes", "field_names",             "type_selections",     "contract_variants",   "readonly_places",
        "carried_places",          "borrowed_temporaries",    "constant_values",     "contract_parameters", "variant_uses",
        "part_selections",         "interpolation_positions", "refused",             "folded_indices",      "field_name_spellings",
        "traversal_positions",     "expansion_of_impl",       "try_conversions",     "declined_contracts",  "adopted_contracts",
        "binding_labels",          "aliased",                 "defaulted_contracts", "fixed_functions",     "refused_members",
    })) {
        @field(result, name) = try mapMap(gpa, relocation, @field(saved, name));
    } else if (comptime in(name, &.{
        "pool",            "closures",        "closure_release",             "raw_accesses", "float_math", "calls",       "recovered_call_args", "recovered_calls",
        "function_values", "implementations", "suppressed_generated_bodies", "projected",    "traversals", "expansions",  "range_places",        "postfix",
        "named",           "templates",       "instances",                   "owned_bounds", "standins",   "tuple_decls",
    })) {
        @field(result, name) = try mapValue(gpa, relocation, @field(saved, name));
    } else if (comptime in(name, &.{ "expr_types", "construction_types" })) {
        @field(result, name) = try dense(gpa, relocation, .exprs, @field(saved, name), types.TypeId.poison);
    } else if (comptime std.mem.eql(u8, name, "written_types")) {
        result.written_types = try dense(gpa, relocation, .tokens, saved.written_types, types.TypeId.poison);
    } else if (comptime std.mem.eql(u8, name, "observation_traits")) {
        result.observation_traits = try dense(gpa, relocation, .decls, saved.observation_traits, false);
    } else if (comptime std.mem.eql(u8, name, "impl_of_decl")) {
        result.impl_of_decl = try dense(gpa, relocation, .decls, saved.impl_of_decl, std.math.maxInt(u32));
    } else if (comptime in(name, &.{ "decl_returns", "decl_signatures" })) {
        @field(result, name).entries = try dense(gpa, relocation, .decls, @field(saved, name).entries, types.TypeId.poison);
    } else if (comptime std.mem.eql(u8, name, "declared_requirements")) {
        result.declared_requirements = try dense(gpa, relocation, .decls, saved.declared_requirements, types.CapabilityRequirement.unrestricted);
    } else if (comptime std.mem.eql(u8, name, "declared_traits")) {
        result.declared_traits = try dense(gpa, relocation, .decls, saved.declared_traits, @as([]const types.BoundTrait, &.{}));
    } else if (comptime std.mem.eql(u8, name, "declared_callables")) {
        result.declared_callables = try dense(gpa, relocation, .decls, saved.declared_callables, @as([]const types.TypeId, &.{}));
    } else if (comptime in(name, &.{ "scoped_capabilities", "prepared_implementations", "implementation_selections", "contextual_constraints" })) {
        @field(result, name) = .{};
    } else if (comptime std.mem.eql(u8, name, "extern_symbols")) {
        // The checker settles extern symbols over every declaration of the
        // attached program, so a symbol a later module repeats is grouped with
        // the library's declaration of it. Nothing reads a retained copy.
        result.extern_symbols = .empty;
    } else if (comptime std.mem.eql(u8, name, "capability_watch")) {
        // Lent only while declared answers are settled.
        result.capability_watch = null;
    } else if (comptime std.mem.eql(u8, name, "open_types")) {
        // Lent only while a check runs; a retained typing holds no open integer.
        result.open_types = null;
    } else if (comptime in(name, &.{ "laid_out", "offsets", "placed_at", "by_name", "sorted" })) {
        // These are mutable layout scratch even on an otherwise immutable Typing.
        @field(result, name) = try gpa.dupe(std.meta.Elem(field.type), @field(saved, name));
    } else if (comptime in(name, &.{ "call_index", "impl_index", "supply_index", "defaults" })) {
        // Rebuilt below from relocated semantic records.
    } else if (comptime in(name, &.{
        "capabilities",   "dependency_containment", "writer_containment",    "constant_texts",        "constant_pool",    "constant_materializations", "variants",     "fields",
        "interpolations", "interpolation_pieces",   "interpolation_formats", "interpolation_borrows", "interpolation_of", "callable_params",           "closure_args", "template_of",
        "module_paths",   "instance_args",          "instance_of",           "owned_names",           "owned_contracts",  "owned_callable_bounds",     "from_end",     "binding_types",
        "generation",     "standin_args",           "standin_of",            "broken_types",          "alike_sources",    "templates_complete",
    })) {
        // Type, binding, closure, string and compact semantic-run IDs stay fixed.
    } else @compileError("classify retained Typing field: " ++ name);
}

fn in(comptime name: []const u8, comptime names: []const []const u8) bool {
    inline for (names) |candidate| if (std.mem.eql(u8, name, candidate)) return true;
    return false;
}

fn rawDecl(r: Relocation, value: u32) u32 {
    return @intFromEnum(r.id(node.DeclId, @enumFromInt(value)));
}

fn rawExpr(r: Relocation, value: u32) u32 {
    return @intFromEnum(r.id(node.ExprId, @enumFromInt(value)));
}

fn hasPointers(comptime T: type) bool {
    return switch (@typeInfo(T)) {
        .pointer => true,
        .@"struct" => |info| blk: {
            inline for (info.fields) |field| if (hasPointers(field.type)) break :blk true;
            break :blk false;
        },
        .@"union" => |info| blk: {
            inline for (info.fields) |field| if (hasPointers(field.type)) break :blk true;
            break :blk false;
        },
        .optional => |info| hasPointers(info.child),
        else => false,
    };
}

pub fn mapValue(gpa: Allocator, r: Relocation, value: anytype) Allocator.Error!@TypeOf(value) {
    const T = @TypeOf(value);
    if (T == types.Type) {
        var result = value;
        if (result == .parameter) {
            result.parameter.owner = rawDecl(r, value.parameter.owner);
            result.parameter.traits = try mapValue(gpa, r, value.parameter.traits);
        }
        return result;
    }
    if (T == types.BoundTrait) {
        var result = r.value(value);
        result.trait = rawDecl(r, value.trait);
        return result;
    }
    if (T == types.RangePlace) {
        var result = value;
        result.at = rawExpr(r, value.at);
        return result;
    }
    if (comptime !hasPointers(T)) return r.value(value);
    var result: T = switch (@typeInfo(T)) {
        .pointer => |info| blk: {
            if (info.size != .slice) @compileError("unexpected pointer in retained semantic record");
            if (info.child == u8 or info.child == types.TypeId or info.child == types.FieldOrdinal) break :blk value;
            const mapped = try gpa.alloc(info.child, value.len);
            for (value, mapped) |old, *new| new.* = try mapValue(gpa, r, old);
            break :blk mapped;
        },
        .@"struct" => |info| blk: {
            var mapped = value;
            inline for (info.fields) |field| @field(mapped, field.name) = try mapValue(gpa, r, @field(value, field.name));
            break :blk mapped;
        },
        .@"union" => switch (value) {
            inline else => |payload, tag| @unionInit(T, @tagName(tag), try mapValue(gpa, r, payload)),
        },
        .optional => if (value) |some| try mapValue(gpa, r, some) else null,
        else => r.value(value),
    };
    if (T == types.Implementation or T == types.Standin or T == types.CallImpl) result.trait = rawDecl(r, value.trait);
    if (T == types.Postfix or T == types.CallImpl) result.call = rawExpr(r, value.call);
    if (T == types.Projected or T == types.Traversal) result.at = rawExpr(r, value.at);
    return result;
}

fn dense(gpa: Allocator, r: Relocation, comptime domain: Domain, values: anytype, fill: std.meta.Elem(@TypeOf(values))) ![]std.meta.Elem(@TypeOf(values)) {
    const T = std.meta.Elem(@TypeOf(values));
    if (values.len == 0) return &.{};
    const cut = @field(r.source, @tagName(domain));
    const destination = @field(r.destination, @tagName(domain));
    std.debug.assert(destination >= cut);
    const count = @max(values.len, cut) + (destination - cut);
    const result = try gpa.alloc(T, count);
    @memset(result, fill);
    for (values, 0..) |value, i| result[r.index(domain, @intCast(i))] = try mapValue(gpa, r, value);
    return result;
}

fn mapMap(gpa: Allocator, r: Relocation, source: anytype) !@TypeOf(source) {
    var result: @TypeOf(source) = .empty;
    var it = source.iterator();
    while (it.next()) |entry| try result.put(gpa, try mapValue(gpa, r, entry.key_ptr.*), try mapValue(gpa, r, entry.value_ptr.*));
    return result;
}

fn supplyIndex(gpa: Allocator, r: Relocation, source: *const types.SupplyIndex) !types.SupplyIndex {
    var result: types.SupplyIndex = .{};
    var entries = source.member_of.iterator();
    while (entries.next()) |entry| {
        const impl = rawDecl(r, @intCast(entry.key_ptr.* >> 32));
        const sig = rawDecl(r, @truncate(entry.key_ptr.*));
        try result.member_of.put(gpa, (@as(u64, impl) << 32) | sig, rawDecl(r, entry.value_ptr.*));
    }
    const by_sig = try gpa.alloc(u32, source.by_sig.len);
    for (source.by_sig, by_sig) |old, *new| new.* = rawDecl(r, old);
    result.by_sig = by_sig;
    const sig_of = try dense(gpa, r, .decls, source.sig_of, types.SupplyIndex.absent);
    for (sig_of) |*sig| sig.* = rawDecl(r, sig.*);
    result.sig_of = sig_of;
    if (source.sig_starts.len > 0) {
        const starts = try gpa.alloc(u32, sig_of.len + 1);
        const cut = r.source.decls;
        const gap = r.destination.decls - cut;
        for (starts, 0..) |*start, i| {
            const old = if (i < cut) i else if (i < cut + gap) cut else i - gap;
            start.* = source.sig_starts[@min(old, source.sig_starts.len - 1)];
        }
        result.sig_starts = starts;
    }
    return result;
}

test "retained typing relocates generated semantic records without changing type handles" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    var returns = [_]types.TypeId{ .u8, .u8, .u8 };
    var saved: types.Typing = .{
        .pool = &.{.{ .parameter = .{ .name = "T", .owner = 2, .index = 0, .traits = &.{.{ .trait = 2 }} } }},
        .variants = .empty,
        .fields = .empty,
        .expr_types = &.{ .u8, .u8, .u8, .u8 },
        .binding_types = .empty,
        .decl_returns = .{ .entries = &returns },
        .calls = &.{.{ .at = .at(3), .target = .{ .declared = .at(2) }, .signature = .u8, .args = &.{.at(2)} }},
        .postfix = &.{.{ .call = 3, .args = &.{.at(2)} }},
        .projected = &.{.{ .at = 2, .expansion = 0 }},
        .range_places = &.{.{ .at = 2, .first = 9 }},
        .expansions = &.{
            .{
                .member = .at(2),
                .path = .none,
                .receiver = types.Expansion.no_binding,
                .index = types.Expansion.no_binding,
                .impl_args = &.{ .u8, .u16 },
                .delegation = .{ .field_name = @as(@import("../support/interner.zig").StringId, @enumFromInt(7)), .field = 2, .field_type = .u16, .key_type = .u64, .backing = 1, .backing_args = &.{.u8} },
            },
            .{ .member = .at(1), .path = .at(3), .receiver = 2, .index = 3 },
            .{
                .member = .at(2),
                .path = .none,
                .receiver = types.Expansion.no_binding,
                .index = types.Expansion.no_binding,
                .delegation = .{ .field_name = @as(@import("../support/interner.zig").StringId, @enumFromInt(7)), .field = 0, .field_type = .u16, .key_type = .u64, .deferred_trait = .at(2) },
            },
            .{
                .member = .at(2),
                .path = .none,
                .receiver = types.Expansion.no_binding,
                .index = types.Expansion.no_binding,
                .delegation = .{ .owner = .at(2), .field_type = .u16, .key_type = .u64, .deferred_trait = .at(2) },
            },
        },
        .traversals = &.{
            .{ .at = 2, .decl = .at(2), .impl_args = &.{.u16}, .positions = .{ .array = .{ .key = .u64, .count = 4, .iterator = .u32 } } },
            .{ .at = 3, .decl = .at(1), .positions = .{ .expression = .at(3) } },
        },
        .standins = &.{.{ .trait = 2, .member = .at(2), .held = .u8, .ty = .u8, .named = "Item" }},
    };
    const sqrt_index = @intFromEnum(@import("../support/float_math.zig").Operation.sqrt);
    saved.float_math.declarations[sqrt_index] = .at(2);
    try saved.literal_values.put(gpa, .at(2), .{ .integer = 7 });
    try saved.contract_variants.put(gpa, .at(2), .{ .receiver = .u16, .ordinal = @enumFromInt(3) });
    try saved.traversal_positions.put(gpa, .at(2), .{ .array = .{ .key = .u64, .count = 4, .iterator = .u32 } });
    try saved.traversal_positions.put(gpa, .at(1), .{ .expression = .at(3) });
    try saved.expansion_of_impl.put(gpa, .at(2), 2);
    try saved.try_conversions.put(gpa, .at(3), .{ .trait = .at(2), .member = .at(1), .source = .u8, .target = .u16 });
    try saved.defaults.note(gpa, 2, 9, .{ .integer = 11 });
    saved.supply_index = try types.SupplyIndex.build(gpa, 3, &.{.{ .impl = .at(1), .sig = .at(2), .member = .at(0) }});
    const r: Relocation = .{
        .source = .{ .decls = 2, .exprs = 2, .tokens = 2 },
        .destination = .{ .decls = 5, .exprs = 4, .tokens = 6 },
    };
    const attached = try attach(gpa, &saved, r);
    try testing.expectEqual(node.DeclId.at(5), attached.float_math.declarations[sqrt_index]);
    try testing.expectEqual(node.DeclId.at(2), saved.float_math.declarations[sqrt_index]);
    try testing.expectEqual(@as(u32, 5), attached.pool[0].parameter.owner);
    try testing.expectEqual(@as(u32, 5), attached.pool[0].parameter.traits[0].trait);
    try testing.expectEqual(@as(usize, 6), attached.expr_types.len);
    try testing.expectEqual(types.TypeId.poison, attached.expr_types[2]);
    try testing.expectEqual(types.TypeId.u8, attached.expr_types[4]);
    const call = attached.call_index.callOf(&attached, .at(5)).?;
    try testing.expectEqual(node.DeclId.at(5), call.target.declared);
    try testing.expectEqual(node.ExprId.at(4), call.args[0]);
    try testing.expectEqual(types.TypeId.u8, call.signature);
    try testing.expectEqual(@as(u32, 5), attached.postfix[0].call);
    try testing.expectEqual(@as(u32, 4), attached.projected[0].at);
    try testing.expectEqual(@as(u32, 4), attached.range_places[0].at);
    try testing.expectEqual(@as(u32, 9), attached.range_places[0].first);
    try testing.expectEqual(@as(u32, 5), attached.standins[0].trait);
    const delegated = attached.expansions[0];
    try testing.expectEqual(node.DeclId.at(5), delegated.member);
    try testing.expectEqual(node.ExprId.none, delegated.path);
    try testing.expectEqual(types.Expansion.no_binding, delegated.receiver);
    try testing.expectEqual(types.Expansion.no_binding, delegated.index);
    try testing.expectEqualSlices(types.TypeId, &.{ .u8, .u16 }, delegated.impl_args);
    try testing.expectEqual(@as(u32, 7), @intFromEnum(delegated.delegation.?.field_name.?));
    try testing.expectEqual(@as(?u32, 2), delegated.delegation.?.field);
    try testing.expectEqual(types.TypeId.u16, delegated.delegation.?.field_type);
    try testing.expectEqual(types.TypeId.u64, delegated.delegation.?.key_type);
    try testing.expectEqual(@as(?u32, 1), delegated.delegation.?.backing);
    try testing.expectEqualSlices(types.TypeId, &.{.u8}, delegated.delegation.?.backing_args);
    try testing.expectEqual(node.DeclId.at(1), attached.expansions[1].member);
    try testing.expectEqual(node.ExprId.at(5), attached.expansions[1].path);
    try testing.expectEqual(@as(u32, 2), attached.expansions[1].receiver);
    try testing.expectEqual(@as(u32, 3), attached.expansions[1].index);
    try testing.expectEqual(node.DeclId.at(5), attached.expansions[2].delegation.?.deferred_trait.?);
    try testing.expectEqual(@as(u32, 2), attached.expansion_of_impl.get(.at(5)).?);
    try testing.expectEqualDeep(types.TryConversion{ .trait = .at(5), .member = .at(1), .source = .u8, .target = .u16 }, attached.try_conversions.get(.at(5)).?);
    try testing.expectEqual(node.DeclId.at(2), saved.expansions[2].delegation.?.deferred_trait.?);
    try testing.expectEqual(node.DeclId.at(5), attached.expansions[3].delegation.?.owner.?);
    try testing.expect(attached.expansions[3].delegation.?.field == null);
    try testing.expect(attached.expansions[3].delegation.?.field_name == null);
    try testing.expectEqual(node.DeclId.at(5), attached.traversals[0].decl);
    try testing.expectEqual(@as(u32, 4), attached.traversals[0].at);
    try testing.expectEqualSlices(types.TypeId, &.{.u16}, attached.traversals[0].impl_args);
    try testing.expectEqualDeep(saved.traversals[0].positions.array, attached.traversals[0].positions.array);
    try testing.expectEqual(node.ExprId.at(5), attached.traversals[1].positions.expression);
    try testing.expectEqual(node.DeclId.at(1), attached.traversals[1].decl);
    try testing.expectEqualDeep(saved.traversal_positions.get(.at(2)).?.array, attached.traversal_positions.get(.at(5)).?.array);
    try testing.expect(!attached.traversal_positions.contains(.at(2)));
    try testing.expectEqual(node.ExprId.at(5), attached.traversal_positions.get(.at(1)).?.expression);
    try testing.expectEqual(node.DeclId.at(2), saved.expansions[0].member);
    try testing.expectEqual(node.ExprId.at(3), saved.traversal_positions.get(.at(1)).?.expression);
    try testing.expectEqual(@as(i128, 7), attached.literal_values.get(.at(4)).?.integer);
    try testing.expectEqualDeep(types.VariantIdentity{ .receiver = .u16, .ordinal = @enumFromInt(3) }, attached.contract_variants.get(.at(6)).?);
    try testing.expect(!attached.contract_variants.contains(.at(2)));
    try testing.expectEqualDeep(types.VariantIdentity{ .receiver = .u16, .ordinal = @enumFromInt(3) }, saved.contract_variants.get(.at(2)).?);
    try testing.expectEqual(@as(i128, 11), attached.defaults.get(5, 9).?.integer);
    try testing.expectEqual(node.DeclId.at(0), attached.supply_index.memberOf(.at(1), .at(5)).?);
    try testing.expectEqualSlices(u32, &.{0}, attached.supply_index.membersOf(.at(5)));
    try testing.expectEqual(node.DeclId.at(5), attached.supply_index.signatureOf(.at(0)).?);
    try testing.expectEqual(@as(u32, 2), saved.pool[0].parameter.owner);
    try testing.expectEqual(node.ExprId.at(3), saved.calls[0].at);
}
