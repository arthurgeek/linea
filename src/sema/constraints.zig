const std = @import("std");

const TokenId = @import("../lexer/token.zig").TokenId;
const StringId = @import("../support/interner.zig").StringId;
const Ast = @import("../syntax/ast.zig").Ast;
const node = @import("../syntax/node.zig");

/// Generic-list bounds and trailing predicates, normalized once.
///
/// A direct predicate joins the parameter's own requirement run. A projected
/// predicate remains a record with its complete subject. Both passes that read
/// constraints therefore see the same declaration-local environment.
pub const Constraints = struct {
    parameter_ranges: []node.BoundRange = &.{},
    declaration_ranges: []node.BoundRange = &.{},
    records: []Constraint = &.{},
    items: []node.TraitBound = &.{},

    pub const Subject = union(enum) {
        parameter: u32,
        written: node.TypeRef,
    };

    pub const Constraint = struct {
        subject: Subject,
        named: TokenId,
        requirements: node.BoundRange,
    };

    pub fn init(gpa: std.mem.Allocator, ast: *const Ast) !Constraints {
        const parameter_ranges = try gpa.alloc(node.BoundRange, ast.type_params.len);
        errdefer gpa.free(parameter_ranges);
        const declaration_ranges = try gpa.alloc(node.BoundRange, ast.declCount());
        errdefer gpa.free(declaration_ranges);
        const counts = try gpa.alloc(u32, ast.type_params.len);
        defer gpa.free(counts);
        @memset(counts, 0);

        var projected_count: u32 = 0;
        var projected_requirements: u32 = 0;

        var names: std.AutoHashMapUnmanaged(StringId, u32) = .empty;
        defer names.deinit(gpa);

        for (0..ast.declCount()) |i| {
            const d = node.DeclId.at(@intCast(i));
            const params = ast.declTypeParams(d);
            const range = ast.declTypeParamRange(d);
            names.clearRetainingCapacity();
            try names.ensureTotalCapacity(gpa, @intCast(params.len));
            for (params, 0..) |p, k| {
                const at = range.start + @as(u32, @intCast(k));
                counts[at] = p.bounds.len();
                const entry = names.getOrPutAssumeCapacity(ast.tokenName(p.name));
                if (!entry.found_existing) entry.value_ptr.* = at;
            }
            for (ast.declWherePredicates(d)) |predicate| {
                if (directPredicateParameter(ast, predicate, &names)) |at| {
                    counts[at] += predicate.bounds.len();
                } else {
                    projected_count += 1;
                    projected_requirements += predicate.bounds.len();
                }
            }
        }

        var total: u32 = 0;
        for (parameter_ranges, counts) |*range, count| {
            range.* = .{ .start = total, .end = total + count };
            total += count;
        }
        const items = try gpa.alloc(node.TraitBound, total + projected_requirements);
        errdefer gpa.free(items);
        for (parameter_ranges, counts) |range, *cursor| cursor.* = range.start;

        for (0..ast.declCount()) |i| {
            const d = node.DeclId.at(@intCast(i));
            const params = ast.declTypeParams(d);
            const range = ast.declTypeParamRange(d);
            names.clearRetainingCapacity();
            try names.ensureTotalCapacity(gpa, @intCast(params.len));
            for (params, 0..) |p, k| {
                const at = range.start + @as(u32, @intCast(k));
                const written = ast.boundsIn(p.bounds);
                @memcpy(items[counts[at]..][0..written.len], written);
                counts[at] += @intCast(written.len);
                const entry = names.getOrPutAssumeCapacity(ast.tokenName(p.name));
                if (!entry.found_existing) entry.value_ptr.* = at;
            }
            for (ast.declWherePredicates(d)) |predicate| {
                const at = directPredicateParameter(ast, predicate, &names) orelse continue;
                const written = ast.boundsIn(predicate.bounds);
                @memcpy(items[counts[at]..][0..written.len], written);
                counts[at] += @intCast(written.len);
            }
        }

        const records = try gpa.alloc(Constraint, ast.type_params.len + projected_count);
        errdefer gpa.free(records);
        var record_at: u32 = 0;
        var item_at = total;

        for (0..ast.declCount()) |i| {
            const d = node.DeclId.at(@intCast(i));
            const start = record_at;
            for (ast.declTypeParams(d), 0..) |p, k| {
                const global = ast.declTypeParamRange(d).start + @as(u32, @intCast(k));
                records[record_at] = .{
                    .subject = .{ .parameter = @intCast(k) },
                    .named = p.name,
                    .requirements = parameter_ranges[global],
                };
                record_at += 1;
            }

            names.clearRetainingCapacity();
            try names.ensureTotalCapacity(gpa, @intCast(ast.declTypeParams(d).len));
            for (ast.declTypeParams(d), 0..) |p, k| {
                const entry = names.getOrPutAssumeCapacity(ast.tokenName(p.name));
                if (!entry.found_existing) entry.value_ptr.* = @intCast(k);
            }
            for (ast.declWherePredicates(d)) |predicate| {
                if (directPredicateParameter(ast, predicate, &names) != null) continue;
                const written = ast.boundsIn(predicate.bounds);
                @memcpy(items[item_at..][0..written.len], written);
                records[record_at] = .{
                    .subject = .{ .written = predicate.subject },
                    .named = subjectName(ast, predicate.subject),
                    .requirements = .{ .start = item_at, .end = item_at + @as(u32, @intCast(written.len)) },
                };
                item_at += @intCast(written.len);
                record_at += 1;
            }
            declaration_ranges[i] = .{ .start = start, .end = record_at };
        }

        return .{
            .parameter_ranges = parameter_ranges,
            .declaration_ranges = declaration_ranges,
            .records = records,
            .items = items,
        };
    }

    pub fn deinit(self: *Constraints, gpa: std.mem.Allocator) void {
        gpa.free(self.parameter_ranges);
        gpa.free(self.declaration_ranges);
        gpa.free(self.records);
        gpa.free(self.items);
        self.* = .{};
    }

    pub fn parameterBounds(self: *const Constraints, ast: *const Ast, d: node.DeclId, index: usize) []const node.TraitBound {
        const params = ast.declTypeParamRange(d);
        if (index >= params.len()) return &.{};
        const range = self.parameter_ranges[params.start + @as(u32, @intCast(index))];
        return self.items[range.start..range.end];
    }

    pub fn rangeOfDeclaration(self: *const Constraints, d: node.DeclId) node.BoundRange {
        if (d == .none or d.index() >= self.declaration_ranges.len) return .empty;
        return self.declaration_ranges[d.index()];
    }

    pub fn ofDeclaration(self: *const Constraints, d: node.DeclId) []const Constraint {
        const range = self.rangeOfDeclaration(d);
        return self.records[range.start..range.end];
    }

    pub fn requirementsOf(self: *const Constraints, constraint: Constraint) []const node.TraitBound {
        return self.items[constraint.requirements.start..constraint.requirements.end];
    }

    fn directPredicateParameter(
        ast: *const Ast,
        predicate: node.WherePredicate,
        names: *const std.AutoHashMapUnmanaged(StringId, u32),
    ) ?u32 {
        if (predicate.subject.kind != .named or predicate.subject.args.len() != 0) return null;
        if (predicate.subject.name == TokenId.none) return null;
        return names.get(ast.tokenName(predicate.subject.name));
    }

    fn subjectName(_: *const Ast, subject: node.TypeRef) TokenId {
        return switch (subject.kind) {
            .named => subject.name,
            .selection => subject.name,
            .array, .callable, .borrow, .grouped, .tuple => subject.at,
        };
    }
};
