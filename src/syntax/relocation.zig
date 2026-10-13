const std = @import("std");
const Ast = @import("ast.zig").Ast;
const FilePart = @import("ast.zig").FilePart;
const node = @import("node.zig");
const token = @import("../lexer/token.zig");
const FileId = @import("../support/source.zig").FileId;

/// Counts at the boundary between source syntax and generated syntax.
pub const Mark = struct {
    parts: u32 = 0,
    tokens: u32 = 0,
    exprs: u32 = 0,
    stmts: u32 = 0,
    blocks: u32 = 0,
    block_stmts: u32 = 0,
    decls: u32 = 0,
    decl_attribute_groups: u32 = 0,
    params: u32 = 0,
    captures: u32 = 0,
    type_params: u32 = 0,
    bounds: u32 = 0,
    where_predicates: u32 = 0,
    contracts: u32 = 0,
    contract_steps: u32 = 0,
    derive_traits: u32 = 0,
    attribute_items: u32 = 0,
    attribute_groups: u32 = 0,
    template_requirements: u32 = 0,
    type_refs: u32 = 0,
    callable_types: u32 = 0,
    variants: u32 = 0,
    fields: u32 = 0,
    extra: u32 = 0,
    call_names: u32 = 0,
    interpolation_formats: u32 = 0,
    struct_literal_heads: u32 = 0,
    bracket_types: u32 = 0,
    files: u32 = 0,

    pub fn of(ast: *const Ast) Mark {
        var result: Mark = .{};
        inline for (@typeInfo(Ast).@"struct".fields) |field| {
            @field(result, field.name) = @intCast(@field(ast, field.name).len);
        }
        for (ast.parts) |part| result.files = @max(result.files, @intFromEnum(part.file) + 1);
        return result;
    }
};
pub const Domain = enum { parts, tokens, exprs, stmts, blocks, block_stmts, decls, decl_attribute_groups, params, captures, type_params, bounds, where_predicates, contracts, contract_steps, derive_traits, attribute_items, attribute_groups, template_requirements, type_refs, callable_types, variants, fields, extra, call_names, interpolation_formats, struct_literal_heads, bracket_types, files };

/// Source IDs remain fixed; generated IDs move after the destination source.
/// String IDs remain fixed because the destination interner contains the full
/// cached expanded interner before any additional source is parsed.
pub const Relocation = struct {
    source: Mark,
    destination: Mark,

    pub fn index(self: Relocation, comptime domain: Domain, at: u32) u32 {
        const cut = @field(self.source, @tagName(domain));
        return if (at < cut) at else @field(self.destination, @tagName(domain)) + (at - cut);
    }

    pub fn id(self: Relocation, comptime T: type, at: T) T {
        if (@intFromEnum(at) == std.math.maxInt(u32)) return at;
        if (T == token.TokenId) return @enumFromInt(self.index(.tokens, @intFromEnum(at)));
        if (T == node.ExprId) return @enumFromInt(self.index(.exprs, @intFromEnum(at)));
        if (T == node.StmtId) return @enumFromInt(self.index(.stmts, @intFromEnum(at)));
        if (T == node.BlockId) return @enumFromInt(self.index(.blocks, @intFromEnum(at)));
        if (T == node.DeclId) return @enumFromInt(self.index(.decls, @intFromEnum(at)));
        if (T == node.ExtraIndex) return @enumFromInt(self.index(.extra, @intFromEnum(at)));
        if (T == node.InterpolationFormatIndex) return @enumFromInt(self.index(.interpolation_formats, @intFromEnum(at)));
        if (T == node.TypeRefId) return @enumFromInt(self.index(.type_refs, @intFromEnum(at)));
        if (T == node.CallableTypeId) return @enumFromInt(self.index(.callable_types, @intFromEnum(at)));
        if (T == node.DeriveTraitId) return @enumFromInt(self.index(.derive_traits, @intFromEnum(at)));
        if (T == node.TemplateRequirementId) return @enumFromInt(self.index(.template_requirements, @intFromEnum(at)));
        if (T == FileId) return @enumFromInt(self.index(.files, @intFromEnum(at)));
        @compileError("not a syntax ID: " ++ @typeName(T));
    }

    /// A range ending at the source boundary still belongs to source syntax.
    pub fn range(self: Relocation, comptime domain: Domain, start: u32, end: u32) struct { start: u32, end: u32 } {
        std.debug.assert(start <= end);
        const cut = @field(self.source, @tagName(domain));
        if (start < cut) {
            std.debug.assert(end <= cut);
            return .{ .start = start, .end = end };
        }
        return .{ .start = self.index(domain, start), .end = self.index(domain, end) };
    }

    /// Optional runs preserve their absent zero range. Owning rows below
    /// distinguish allocated empty runs, whose builder cursor must move.
    pub fn value(self: Relocation, input: anytype) @TypeOf(input) {
        const T = @TypeOf(input);
        if (T == token.TokenId) return self.id(T, input);
        if (T == node.ExprId) return self.id(T, input);
        if (T == node.StmtId) return self.id(T, input);
        if (T == node.BlockId) return self.id(T, input);
        if (T == node.DeclId) return self.id(T, input);
        if (T == node.ExtraIndex) return self.id(T, input);
        if (T == node.InterpolationFormatIndex) return self.id(T, input);
        if (T == node.TypeRefId) return self.id(T, input);
        if (T == node.CallableTypeId) return self.id(T, input);
        if (T == node.DeriveTraitId) return self.id(T, input);
        if (T == node.TemplateRequirementId) return self.id(T, input);
        if (T == FileId) return self.id(T, input);
        if (T == token.TokenRange) {
            if (input.end.index() == 0) return input;
            const mapped = self.range(.tokens, input.start.index(), input.end.index());
            return .{ .start = token.TokenId.at(mapped.start), .end = token.TokenId.at(mapped.end) };
        }
        if (T == node.DeclRange) {
            if (input.end == 0) return input;
            const mapped = self.range(.decls, input.start, input.end);
            return .{ .start = mapped.start, .end = mapped.end };
        }
        if (T == node.StmtRange) {
            const mapped = self.range(.block_stmts, input.start, input.end);
            return .{ .start = mapped.start, .end = mapped.end };
        }
        if (T == node.ParamRange) {
            if (input.end == 0) return input;
            const mapped = self.range(.params, input.start, input.end);
            return .{ .start = mapped.start, .end = mapped.end };
        }
        if (T == node.TypeParamRange) {
            if (input.end == 0) return input;
            const mapped = self.range(.type_params, input.start, input.end);
            return .{ .start = mapped.start, .end = mapped.end };
        }
        if (T == node.BoundRange) {
            if (input.end == 0) return input;
            const mapped = self.range(.bounds, input.start, input.end);
            return .{ .start = mapped.start, .end = mapped.end };
        }
        if (T == node.WherePredicateRange) {
            if (input.end == 0) return input;
            const mapped = self.range(.where_predicates, input.start, input.end);
            return .{ .start = mapped.start, .end = mapped.end };
        }
        if (T == node.ContractRange) {
            if (input.end == 0) return input;
            const mapped = self.range(.contracts, input.start, input.end);
            return .{ .start = mapped.start, .end = mapped.end };
        }
        if (T == node.ContractStepRange) {
            if (input.end == 0) return input;
            const mapped = self.range(.contract_steps, input.start, input.end);
            return .{ .start = mapped.start, .end = mapped.end };
        }
        if (T == node.DeriveTraitRange) {
            if (input.end == 0) return input;
            const mapped = self.range(.derive_traits, input.start, input.end);
            return .{ .start = mapped.start, .end = mapped.end };
        }
        if (T == node.AttributeItemRange) {
            if (input.end == 0) return input;
            const mapped = self.range(.attribute_items, input.start, input.end);
            return .{ .start = mapped.start, .end = mapped.end };
        }
        if (T == node.AttributeGroupRange) {
            if (input.end == 0) return input;
            const mapped = self.range(.attribute_groups, input.start, input.end);
            return .{ .start = mapped.start, .end = mapped.end };
        }
        if (T == node.TemplateRequirementRange) {
            if (input.end == 0) return input;
            const mapped = self.range(.template_requirements, input.start, input.end);
            return .{ .start = mapped.start, .end = mapped.end };
        }
        if (T == node.TypeRefRange) {
            if (input.end == 0) return input;
            const mapped = self.range(.type_refs, input.start, input.end);
            return .{ .start = mapped.start, .end = mapped.end };
        }
        if (T == node.VariantRange) {
            if (input.end == 0) return input;
            const mapped = self.range(.variants, input.start, input.end);
            return .{ .start = mapped.start, .end = mapped.end };
        }
        if (T == node.FieldRange) {
            if (input.end == 0) return input;
            const mapped = self.range(.fields, input.start, input.end);
            return .{ .start = mapped.start, .end = mapped.end };
        }
        if (T == node.Expr) {
            var result = input;
            result.main_token = self.value(input.main_token);
            result.token_range = self.value(input.token_range);
            switch (input.tag.payload()) {
                inline else => |tag| {
                    const name = @tagName(tag);
                    @field(result.data, name) = self.value(@field(input.data, name));
                },
            }
            return result;
        }
        if (T == FilePart) {
            var result = input;
            result.file = self.id(FileId, input.file);
            inline for (.{ "token", "decl", "stmt", "expr" }, .{ Domain.tokens, .decls, .stmts, .exprs }) |name, domain| {
                const mapped = self.range(domain, @field(input, name ++ "_start"), @field(input, name ++ "_end"));
                @field(result, name ++ "_start") = mapped.start;
                @field(result, name ++ "_end") = mapped.end;
            }
            return result;
        }
        return switch (@typeInfo(T)) {
            .@"struct" => blk: {
                var result = input;
                inline for (@typeInfo(T).@"struct".fields) |field| @field(result, field.name) = self.value(@field(input, field.name));
                if (T == node.Decl) {
                    switch (input.tag) {
                        .function, .projection => result.params = self.positioned(.params, input.params),
                        else => {},
                    }
                    switch (input.tag) {
                        .function, .projection, .struct_, .enum_, .trait_, .impl_, .derive_impl => result.type_params = self.positioned(.type_params, input.type_params),
                        else => {},
                    }
                    if (input.tag == .trait_ or input.tag == .associated_type) result.bounds = self.positioned(.bounds, input.bounds);
                    if (input.where_at != .none) {
                        result.where_predicates = self.positioned(.where_predicates, input.where_predicates);
                        if (input.tag == .function or input.tag == .projection) result.contracts = self.positioned(.contracts, input.contracts);
                        if (input.tag == .template_impl) result.template_requirements = self.positioned(.template_requirements, input.template_requirements);
                    }
                    if (input.tag == .enum_) result.variants = self.positioned(.variants, input.variants);
                    if (input.tag == .struct_) result.fields = self.positioned(.fields, input.fields);
                    if (input.tag == .derive_impl) result.derive_traits = self.positioned(.derive_traits, input.derive_traits);
                }
                if (T == node.CallableType) {
                    result.params = self.positioned(.params, input.params);
                    result.contracts = self.positioned(.contracts, input.contracts);
                }
                if (T == node.TypeParam or T == node.WherePredicate or T == node.TemplateRequirement) result.bounds = self.positioned(.bounds, input.bounds);
                if (T == node.Variant) result.fields = self.positioned(.fields, input.fields);
                if (T == node.ContractPath and input.root != .none) result.steps = self.positioned(.contract_steps, input.steps);
                break :blk result;
            },
            .@"union" => switch (input) {
                inline else => |payload, tag| @unionInit(T, @tagName(tag), self.value(payload)),
            },
            .array => blk: {
                var result = input;
                for (&result) |*item| item.* = self.value(item.*);
                break :blk result;
            },
            .optional => if (input) |some| self.value(some) else null,
            else => input,
        };
    }

    /// An allocated run retains its cursor even when it contains no rows.
    fn positioned(self: Relocation, comptime domain: Domain, input: anytype) @TypeOf(input) {
        const mapped = self.range(domain, input.start, input.end);
        return .{ .start = mapped.start, .end = mapped.end };
    }

    /// Relocates only the ID slots of the heterogeneous expression payloads.
    pub fn extra(self: Relocation, expression: node.Expr, source_extra: []const node.ExprId, destination_extra: []node.ExprId) void {
        switch (expression.tag.payload()) {
            .none, .unary, .binary, .block => {},
            .conditional => {
                const at = expression.data.conditional.arms.index();
                for (0..2) |offset| self.extraId(node.ExprId, at + @as(u32, @intCast(offset)), source_extra, destination_extra);
            },
            .call, .interpolation => |tag| {
                const at = if (tag == .call) expression.data.call.args.index() else expression.data.interpolation.pieces.index();
                const count = source_extra[at].index();
                for (0..count) |offset| self.extraId(node.ExprId, at + 1 + @as(u32, @intCast(offset)), source_extra, destination_extra);
            },
            .range => self.extraId(node.ExprId, expression.data.range.extra.index(), source_extra, destination_extra),
            .lambda => {
                const at = expression.data.lambda.extra.index();
                inline for (.{ Domain.params, .captures, .contracts }, .{ 0, 5, 9 }) |domain, offset| {
                    // A lambda without an arrow has no parsed contract run.
                    if (domain != .contracts or source_extra[at + 12] != .none) {
                        const mapped = self.range(domain, source_extra[at + offset].index(), source_extra[at + offset + 1].index());
                        destination_extra[self.index(.extra, at + offset)] = .at(mapped.start);
                        destination_extra[self.index(.extra, at + offset + 1)] = .at(mapped.end);
                    }
                }
                inline for (.{ 2, 3, 7, 8, 12 }) |offset| self.extraId(token.TokenId, at + offset, source_extra, destination_extra);
                self.extraId(node.TypeRefId, at + 11, source_extra, destination_extra);
            },
        }
    }

    fn extraId(self: Relocation, comptime T: type, at: u32, source_extra: []const node.ExprId, destination_extra: []node.ExprId) void {
        const old: T = @enumFromInt(source_extra[at].index());
        destination_extra[self.index(.extra, at)] = @enumFromInt(@intFromEnum(self.id(T, old)));
    }
};
