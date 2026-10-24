const std = @import("std");

const token = @import("../lexer/token.zig");
const Ast = @import("../syntax/ast.zig").Ast;
const node = @import("../syntax/node.zig");
const ids = @import("ids.zig");
const expanded = @import("../syntax/expanded_program.zig");

const BindingId = ids.BindingId;
const DeclId = node.DeclId;
const ExprId = node.ExprId;
const CaseOrdinal = expanded.CaseOrdinal;
const ComponentOrdinal = expanded.ComponentOrdinal;

pub const RenderError = std.mem.Allocator.Error || error{
    Overflow,
    GeneratedSourceTooLarge,
    UnsupportedReflectionTarget,
    ComponentPlaceOutsideLoop,
};

pub const ReflectedCasePlan = struct {
    match: ExprId,
    pattern: ExprId,
    subject: ExprId,
    subject_binding: BindingId,
    body: ExprId,
};

pub const ComponentLoopPlan = struct {
    loop: ExprId,
    binder: BindingId,
    body: ExprId,
    reversed: bool,
};

pub const ComponentPlacePlan = struct {
    call: ExprId,
    loop: ExprId,
    subject_binding: BindingId,
};

pub const SameCasePlan = struct {
    match: ExprId,
    subject: ExprId,
    subject_binding: BindingId,
    same_body: ExprId,
    other_body: ?ExprId,
};

pub const MetadataPlan = struct {
    expression: ExprId,
    kind: Kind,

    pub const Kind = enum {
        case_name,
        case_ordinal,
        components_named,
        component_name,
        component_ordinal,
    };
};

pub const OrdinalPlan = struct {
    call: ExprId,
    operand: ExprId,
};

/// One `reflect.wrap(value)`: the callee is replaced by the constructor of
/// the variant the derive selected for `parameter`'s written type.
pub const WrapPlan = struct {
    call: ExprId,
    callee: ExprId,
    parameter: u32,
};

pub const FreeReference = struct {
    at: token.TokenId,
    member: token.TokenId,
    /// How the generated member spells the name: through the import of the
    /// trait's module, through an import of its own, or as written.
    route: Route = .through_trait,

    pub const Route = union(enum) {
        /// Qualified by the trait's module, where the target imports it.
        through_trait,
        /// Qualified by this alias, an import of the declaring module.
        through: []const u8,
        /// Written as the template wrote it, because the target's module
        /// already reaches the same declaration by that name.
        as_written,
    };

    /// Whether rendering replaces the reference's token, given the trait's
    /// qualifier.
    fn rewritten(self: FreeReference, qualifier: ?[]const u8) bool {
        return switch (self.route) {
            .through_trait => qualifier != null,
            .through => true,
            .as_written => false,
        };
    }
};

pub const TypeParameterReference = struct { at: token.TokenId, parameter: u32, selection_base: bool = false };

pub const ParameterReference = struct { at: token.TokenId, contract: bool = false };

pub const ParameterPlan = struct {
    declaration: token.TokenId,
    references: []ParameterReference,
};

pub const ConstructionPlan = struct {
    call: ExprId,
    recipe: ExprId,
    finalization: ExprId,
    result: BindingId,
    product: bool,
};

pub const ComponentTypePlan = struct { tokens: token.TokenRange, selection_base: bool = false };

pub const LocalRename = struct {
    at: token.TokenId,
    binding: BindingId,
    kind: enum { plain, field_value, field_binder, capture } = .plain,
    source: BindingId = .none,
};

pub const ComponentTypes = struct {
    offsets: []const u32,
    text: []const []const u8,
};

pub const ReflectionMemberPlan = struct {
    member: DeclId,
    cases: []const ReflectedCasePlan,
    same_cases: []const SameCasePlan,
    loops: []const ComponentLoopPlan,
    places: []const ComponentPlacePlan,
    metadata: []const MetadataPlan,
    ordinals: []const OrdinalPlan,
    wraps: []const WrapPlan = &.{},
    parameters: []const ParameterPlan,
    type_parameters: []const TypeParameterReference = &.{},
    constructions: []const ConstructionPlan = &.{},
    component_types: []const ComponentTypePlan = &.{},
    locals: []const LocalRename = &.{},

    pub fn deinit(self: *const ReflectionMemberPlan, gpa: std.mem.Allocator) void {
        gpa.free(self.cases);
        gpa.free(self.same_cases);
        gpa.free(self.loops);
        gpa.free(self.places);
        gpa.free(self.metadata);
        gpa.free(self.ordinals);
        gpa.free(self.wraps);
        for (self.parameters) |parameter| gpa.free(parameter.references);
        gpa.free(self.parameters);
        gpa.free(self.type_parameters);
        gpa.free(self.constructions);
        gpa.free(self.component_types);
        gpa.free(self.locals);
    }
};

pub const OriginSegment = struct {
    start: u32,
    end: u32,
    template_expr: ExprId,
    case_ordinal: ?CaseOrdinal,
    component_ordinal: ?ComponentOrdinal,
};

pub const RenderedMember = struct {
    text: []u8,
    origins: []OriginSegment,

    pub fn deinit(self: *RenderedMember, gpa: std.mem.Allocator) void {
        gpa.free(self.text);
        gpa.free(self.origins);
        self.* = undefined;
    }
};

const Operation = struct {
    span: @import("../support/span.zig").Span,
    kind: Kind,
    index: u32,

    const Kind = enum { case, same_case, loop, place, metadata, ordinal, free_reference, parameter_declaration, parameter_reference, parameter_contract_reference, type_parameter, construction, component_type, local, wrap };

    fn before(_: void, lhs: Operation, rhs: Operation) bool {
        if (lhs.span.start != rhs.span.start) return lhs.span.start < rhs.span.start;
        if (lhs.span.end != rhs.span.end) return lhs.span.end > rhs.span.end;
        return lhs.kind == .local and rhs.kind != .local;
    }
};

const BindingKey = struct {
    subject: BindingId,
    case: CaseOrdinal,
    component: ComponentOrdinal,
};

const RenderState = struct {
    case: ?CaseOrdinal = null,
    component: ?ComponentOrdinal = null,
};

fn ordinalIndex(ordinal: anytype) usize {
    return @intFromEnum(ordinal);
}

const Renderer = struct {
    gpa: std.mem.Allocator,
    ast: *const Ast,
    plan: *const ReflectionMemberPlan,
    free_references: []const FreeReference,
    qualifier: ?[]const u8,
    template_arguments: []const []const u8,
    /// The variant each `plan.wraps` entry constructs, in the same order.
    wrapped: []const CaseOrdinal,
    source: []const u8,
    target: DeclId,
    component_types: ComponentTypes,
    out: std.ArrayList(u8) = .empty,
    origins: std.ArrayList(OriginSegment) = .empty,
    operations: []Operation,
    bindings: std.ArrayList([]const u8) = .empty,
    binding_index: std.AutoHashMapUnmanaged(BindingKey, u32) = .empty,
    occupied: std.StringHashMapUnmanaged(void) = .empty,
    parameter_used: []bool,
    parameter_positions: std.ArrayList(struct { parameter: u32, offset: u32 }) = .empty,

    fn deinit(self: *Renderer) void {
        self.out.deinit(self.gpa);
        self.origins.deinit(self.gpa);
        self.parameter_positions.deinit(self.gpa);
        for (self.bindings.items) |name| self.gpa.free(name);
        self.bindings.deinit(self.gpa);
        self.binding_index.deinit(self.gpa);
        self.occupied.deinit(self.gpa);
    }

    fn append(self: *Renderer, bytes: []const u8) RenderError!void {
        if (bytes.len > std.math.maxInt(u32) - self.out.items.len) return error.GeneratedSourceTooLarge;
        try self.out.appendSlice(self.gpa, bytes);
    }

    fn caseCount(self: *const Renderer) RenderError!usize {
        return switch (self.ast.declTag(self.target)) {
            .struct_, .newtype => 1,
            .enum_ => self.ast.declVariants(self.target).len,
            else => error.UnsupportedReflectionTarget,
        };
    }

    fn componentCount(self: *const Renderer, case: CaseOrdinal) RenderError!usize {
        return switch (self.ast.declTag(self.target)) {
            .struct_ => self.ast.declFields(self.target).len,
            .newtype => 1,
            .enum_ => self.ast.variantFields(self.ast.declVariants(self.target)[ordinalIndex(case)]).len,
            else => error.UnsupportedReflectionTarget,
        };
    }

    fn binding(self: *const Renderer, subject: BindingId, case: CaseOrdinal, component: ComponentOrdinal) RenderError![]const u8 {
        const index = self.binding_index.get(.{ .subject = subject, .case = case, .component = component }) orelse
            return error.ComponentPlaceOutsideLoop;
        return self.bindings.items[index];
    }

    fn buildBindings(self: *Renderer, derive: DeclId) RenderError!void {
        for ([_]DeclId{ self.plan.member, self.target, derive }) |declaration| {
            const tokens = self.ast.declTokens(declaration);
            for (tokens.start.index()..tokens.end.index()) |i| {
                const at = token.TokenId.at(@intCast(i));
                if (self.ast.tokenTag(at) == .identifier) {
                    try self.occupied.put(self.gpa, self.ast.tokenText(at), {});
                }
            }
        }

        var subjects: std.ArrayList(BindingId) = .empty;
        defer subjects.deinit(self.gpa);
        for (self.plan.cases) |case| {
            var found = false;
            for (subjects.items) |subject| {
                if (subject == case.subject_binding) {
                    found = true;
                    break;
                }
            }
            if (!found) try subjects.append(self.gpa, case.subject_binding);
        }
        for (self.plan.same_cases) |same_case| {
            var found = false;
            for (subjects.items) |subject| {
                if (subject == same_case.subject_binding) {
                    found = true;
                    break;
                }
            }
            if (!found) try subjects.append(self.gpa, same_case.subject_binding);
        }

        var local_subjects: std.AutoHashMapUnmanaged(BindingId, void) = .empty;
        defer local_subjects.deinit(self.gpa);
        for (self.plan.locals) |local| {
            if (local.kind == .capture) continue;
            const entry = try local_subjects.getOrPut(self.gpa, local.binding);
            if (!entry.found_existing) try subjects.append(self.gpa, local.binding);
        }
        const case_count = try self.caseCount();
        for (subjects.items, 0..) |subject, subject_ordinal| {
            for (0..case_count) |case_index| {
                const case: CaseOrdinal = @enumFromInt(case_index);
                const component_count = try self.componentCount(case);
                for (0..component_count) |component_index| {
                    const component: ComponentOrdinal = @enumFromInt(component_index);
                    var local = std.math.cast(u32, subject_ordinal) orelse return error.Overflow;
                    while (true) : (local = try std.math.add(u32, local, 1)) {
                        const candidate = try std.fmt.allocPrint(
                            self.gpa,
                            "_linea_derive_{d}_{d}_{d}_{d}",
                            .{ derive.index(), case_index, component_index, local },
                        );
                        if (self.occupied.contains(candidate)) {
                            self.gpa.free(candidate);
                            continue;
                        }
                        const index = std.math.cast(u32, self.bindings.items.len) orelse {
                            self.gpa.free(candidate);
                            return error.Overflow;
                        };
                        self.occupied.put(self.gpa, candidate, {}) catch |err| {
                            self.gpa.free(candidate);
                            return err;
                        };
                        self.bindings.append(self.gpa, candidate) catch |err| {
                            _ = self.occupied.remove(candidate);
                            self.gpa.free(candidate);
                            return err;
                        };
                        self.binding_index.put(
                            self.gpa,
                            .{ .subject = subject, .case = case, .component = component },
                            index,
                        ) catch |err| {
                            _ = self.bindings.pop();
                            _ = self.occupied.remove(candidate);
                            self.gpa.free(candidate);
                            return err;
                        };
                        break;
                    }
                }
            }
        }
    }

    fn firstOperation(self: *const Renderer, start: u32) usize {
        var lo: usize = 0;
        var hi = self.operations.len;
        while (lo < hi) {
            const mid = lo + (hi - lo) / 2;
            if (self.operations[mid].span.start < start) lo = mid + 1 else hi = mid;
        }
        return lo;
    }

    fn renderRange(self: *Renderer, start: u32, end: u32, state: RenderState) RenderError!void {
        return self.renderRangeWithLocals(start, end, state, true);
    }

    fn renderRangeWithLocals(self: *Renderer, start: u32, end: u32, state: RenderState, locals: bool) RenderError!void {
        var copied = start;
        var i = self.firstOperation(start);
        while (i < self.operations.len) : (i += 1) {
            const operation = self.operations[i];
            if (operation.span.start >= end) break;
            if (!locals and operation.kind == .local) continue;
            if (operation.span.start < copied or operation.span.end > end) continue;
            try self.append(self.source[copied..operation.span.start]);
            switch (operation.kind) {
                .construction => try self.renderConstruction(self.plan.constructions[operation.index], state),
                .component_type => {
                    const case = state.case orelse return error.UnsupportedReflectionTarget;
                    const component = state.component orelse return error.ComponentPlaceOutsideLoop;
                    const at = self.component_types.offsets[ordinalIndex(case)] + ordinalIndex(component);
                    const plan = self.plan.component_types[operation.index];
                    if (plan.selection_base) try self.append("(");
                    try self.append(self.component_types.text[at]);
                    if (plan.selection_base) try self.append(")");
                },
                .local => try self.renderLocal(self.plan.locals[operation.index], state),
                .case => try self.renderCase(self.plan.cases[operation.index], state),
                .same_case => try self.renderSameCase(self.plan.same_cases[operation.index], state),
                .loop => try self.renderLoop(self.plan.loops[operation.index], state),
                .place => try self.renderPlace(self.plan.places[operation.index], state),
                .metadata => try self.renderMetadata(self.plan.metadata[operation.index], state),
                .ordinal => try self.renderOrdinal(self.plan.ordinals[operation.index]),
                .wrap => try self.renderWrap(self.plan.wraps[operation.index], self.wrapped[operation.index]),
                .type_parameter => {
                    const reference = self.plan.type_parameters[operation.index];
                    if (reference.selection_base) try self.append("(");
                    try self.append(self.template_arguments[reference.parameter]);
                    if (reference.selection_base) try self.append(")");
                },
                .free_reference => try self.renderFreeReference(self.free_references[operation.index]),
                .parameter_declaration, .parameter_contract_reference => {
                    const offset = std.math.cast(u32, self.out.items.len) orelse return error.GeneratedSourceTooLarge;
                    try self.parameter_positions.append(self.gpa, .{ .parameter = operation.index, .offset = offset });
                    try self.append(self.source[operation.span.start..operation.span.end]);
                },
                .parameter_reference => {
                    self.parameter_used[operation.index] = true;
                    try self.append(self.source[operation.span.start..operation.span.end]);
                },
            }
            copied = operation.span.end;
        }
        try self.append(self.source[copied..end]);
    }

    fn beginOrigin(self: *Renderer, expression: ExprId, state: RenderState) RenderError!usize {
        const start = std.math.cast(u32, self.out.items.len) orelse return error.GeneratedSourceTooLarge;
        const index = self.origins.items.len;
        try self.origins.append(self.gpa, .{
            .start = start,
            .end = start,
            .template_expr = expression,
            .case_ordinal = state.case,
            .component_ordinal = state.component,
        });
        return index;
    }

    fn endOrigin(self: *Renderer, index: usize) RenderError!void {
        self.origins.items[index].end = std.math.cast(u32, self.out.items.len) orelse return error.GeneratedSourceTooLarge;
    }

    fn appendOrdinal(self: *Renderer, value: usize) RenderError!void {
        var buffer: [32]u8 = undefined;
        try self.append(std.fmt.bufPrint(&buffer, "{d}", .{value}) catch return error.Overflow);
    }

    fn appendQuoted(self: *Renderer, value: []const u8) RenderError!void {
        try self.append("\"");
        try self.append(value);
        try self.append("\"");
    }

    fn fieldsOfCase(self: *const Renderer, case: CaseOrdinal) []const node.Field {
        return switch (self.ast.declTag(self.target)) {
            .struct_ => self.ast.declFields(self.target),
            .enum_ => self.ast.variantFields(self.ast.declVariants(self.target)[ordinalIndex(case)]),
            .newtype => &.{},
            else => unreachable,
        };
    }

    fn caseName(self: *const Renderer, case: CaseOrdinal) []const u8 {
        return switch (self.ast.declTag(self.target)) {
            .struct_, .newtype => self.ast.tokenText(self.ast.declName(self.target)),
            .enum_ => self.ast.tokenText(self.ast.declVariants(self.target)[ordinalIndex(case)].name),
            else => unreachable,
        };
    }

    /// Renders a case's pattern. Each component binding it writes is an origin of its
    /// own, so a diagnostic about that binding names the component.
    fn renderPattern(
        self: *Renderer,
        expression: ExprId,
        subject: BindingId,
        case: CaseOrdinal,
        bind_components: bool,
    ) RenderError!void {
        try self.append(self.caseName(case));
        switch (self.ast.declTag(self.target)) {
            .struct_ => {
                try self.append(" {");
                for (self.fieldsOfCase(case), 0..) |field, component_index| {
                    const component: ComponentOrdinal = @enumFromInt(component_index);
                    try self.append(" ");
                    try self.append(self.ast.tokenText(field.name));
                    try self.append(": ");
                    if (bind_components) {
                        try self.appendComponentBinding(expression, subject, case, component);
                    } else {
                        try self.append("_");
                    }
                    try self.append(",");
                }
                try self.append(" }");
            },
            .newtype, .enum_ => {
                const count = try self.componentCount(case);
                if (count == 0) return;
                try self.append("(");
                for (0..count) |component_index| {
                    if (component_index != 0) try self.append(", ");
                    const component: ComponentOrdinal = @enumFromInt(component_index);
                    if (bind_components) {
                        try self.appendComponentBinding(expression, subject, case, component);
                    } else {
                        try self.append("_");
                    }
                }
                try self.append(")");
            },
            else => return error.UnsupportedReflectionTarget,
        }
    }

    fn appendComponentBinding(self: *Renderer, expression: ExprId, subject: BindingId, case: CaseOrdinal, component: ComponentOrdinal) RenderError!void {
        const origin = try self.beginOrigin(expression, .{ .case = case, .component = component });
        try self.append(try self.binding(subject, case, component));
        try self.endOrigin(origin);
    }

    fn renderCase(self: *Renderer, plan: ReflectedCasePlan, state: RenderState) RenderError!void {
        std.debug.assert(state.case == null and state.component == null);
        try self.append("match ");
        if (self.ast.exprTag(plan.match) == .match_read) try self.append("read ");
        const subject = self.ast.exprSpan(plan.subject);
        try self.renderRange(subject.start, subject.end, .{});
        try self.append(" {\n");
        const case_count = try self.caseCount();
        for (0..case_count) |case_index| {
            const case: CaseOrdinal = @enumFromInt(case_index);
            try self.renderPattern(plan.match, plan.subject_binding, case, true);
            try self.append(" => ");
            const body = self.ast.exprSpan(plan.body);
            const origin = try self.beginOrigin(plan.body, .{ .case = case });
            try self.renderRange(body.start, body.end, .{ .case = case });
            try self.endOrigin(origin);
            try self.append(",\n");
        }
        try self.append("}");
    }

    fn renderSameCase(self: *Renderer, plan: SameCasePlan, state: RenderState) RenderError!void {
        const case = state.case orelse return error.UnsupportedReflectionTarget;
        std.debug.assert(state.component == null);
        try self.append("match ");
        if (self.ast.exprTag(plan.match) == .match_read) try self.append("read ");
        const subject = self.ast.exprSpan(plan.subject);
        try self.renderRange(subject.start, subject.end, state);
        try self.append(" {\n");
        try self.renderPattern(plan.match, plan.subject_binding, case, true);
        try self.append(" => ");
        const same_body = self.ast.exprSpan(plan.same_body);
        const same_origin = try self.beginOrigin(plan.same_body, state);
        try self.renderRange(same_body.start, same_body.end, state);
        try self.endOrigin(same_origin);
        try self.append(",\n");
        if (plan.other_body) |other_body_id| {
            if (try self.caseCount() > 1) {
                try self.append("_ => ");
                const other_body = self.ast.exprSpan(other_body_id);
                const other_origin = try self.beginOrigin(other_body_id, state);
                try self.renderRange(other_body.start, other_body.end, state);
                try self.endOrigin(other_origin);
                try self.append(",\n");
            }
        }
        try self.append("}");
    }

    fn renderLoop(self: *Renderer, plan: ComponentLoopPlan, state: RenderState) RenderError!void {
        const case = state.case orelse return error.ComponentPlaceOutsideLoop;
        std.debug.assert(state.component == null);
        const body = self.ast.exprSpan(plan.body);
        const count = try self.componentCount(case);
        const loop_origin = try self.beginOrigin(plan.body, state);
        try self.append("{\n");
        for (0..count) |step| {
            const component_index = if (plan.reversed) count - 1 - step else step;
            const component: ComponentOrdinal = @enumFromInt(component_index);
            const component_state: RenderState = .{ .case = case, .component = component };
            const component_origin = try self.beginOrigin(plan.body, component_state);
            try self.renderRange(body.start, body.end, component_state);
            try self.endOrigin(component_origin);
            try self.append("\n");
        }
        try self.append("}");
        try self.endOrigin(loop_origin);
    }

    fn renderLocal(self: *Renderer, local: LocalRename, state: RenderState) RenderError!void {
        const case = state.case orelse return error.ComponentPlaceOutsideLoop;
        const component = state.component orelse return error.ComponentPlaceOutsideLoop;
        if (local.kind == .field_value or local.kind == .field_binder) {
            try self.append(self.ast.tokenText(local.at));
            try self.append(if (local.kind == .field_value) " = " else ": ");
        }
        if (local.kind == .capture) {
            try self.append(self.ast.tokenText(local.at));
        } else {
            try self.append(try self.binding(local.binding, case, component));
        }
        if (local.kind == .capture) {
            try self.append(" = ");
            if (local.source != .none) {
                try self.append(try self.binding(local.source, case, component));
            } else {
                const span = self.ast.tokenSpan(local.at);
                try self.renderRangeWithLocals(span.start, span.end, state, false);
            }
        }
    }

    fn renderConstruction(self: *Renderer, plan: ConstructionPlan, state: RenderState) RenderError!void {
        const case: CaseOrdinal = if (plan.product) @enumFromInt(0) else state.case orelse return error.UnsupportedReflectionTarget;
        if (self.ast.declTag(self.target) == .newtype or
            (plan.product and self.ast.declTag(self.target) != .struct_)) return error.UnsupportedReflectionTarget;
        const origin = try self.beginOrigin(plan.call, .{ .case = case });
        try self.append("{\n");
        const block = self.ast.blockOf(plan.recipe);
        const tokens = self.ast.exprTokens(plan.recipe);
        const start = self.ast.tokenSpan(tokens.start).end;
        const end = self.ast.exprSpan(block.tail).start;
        const count = try self.componentCount(case);
        var closing = tokens.end.index();
        while (closing > tokens.start.index() and self.ast.tokenTag(token.TokenId.at(closing - 1)).isTrivia()) closing -= 1;
        const tail_end = self.ast.exprSpan(block.tail).end;
        const trailing_end = if (closing > tokens.start.index() and self.ast.tokenTag(token.TokenId.at(closing - 1)) == .r_brace)
            self.ast.tokenSpan(token.TokenId.at(closing - 1)).start
        else
            tail_end;
        for (0..count) |index| {
            const component: ComponentOrdinal = @enumFromInt(index);
            const component_state: RenderState = .{ .case = case, .component = component };
            const component_origin = try self.beginOrigin(plan.recipe, component_state);
            try self.renderRange(start, end, component_state);
            try self.renderRange(tail_end, trailing_end, component_state);
            try self.append("\n");
            try self.endOrigin(component_origin);
        }
        try self.append("let _: () = ");
        const finalization = self.ast.exprSpan(plan.finalization);
        try self.renderRange(finalization.start, finalization.end, .{ .case = case });
        try self.append(";\n");
        if (self.ast.declTag(self.target) == .struct_) {
            try self.append(".{ ");
        } else {
            try self.append(self.ast.tokenText(self.ast.declName(self.target)));
            try self.append(".");
            try self.append(self.caseName(case));
            if (count != 0) try self.append("(");
        }
        for (0..count) |index| {
            const component: ComponentOrdinal = @enumFromInt(index);
            const component_origin = try self.beginOrigin(plan.call, .{ .case = case, .component = component });
            if (index != 0) try self.append(", ");
            if (self.ast.declTag(self.target) == .struct_) {
                try self.append(self.ast.tokenText(self.fieldsOfCase(case)[index].name));
                try self.append(" = ");
            }
            try self.append(try self.binding(plan.result, case, component));
            try self.endOrigin(component_origin);
        }
        if (self.ast.declTag(self.target) == .struct_) try self.append(" }") else if (count != 0) try self.append(")");
        try self.append("\n}");
        try self.endOrigin(origin);
    }

    fn renderPlace(self: *Renderer, plan: ComponentPlacePlan, state: RenderState) RenderError!void {
        const case = state.case orelse return error.ComponentPlaceOutsideLoop;
        const component = state.component orelse return error.ComponentPlaceOutsideLoop;
        const origin = try self.beginOrigin(plan.call, state);
        try self.append(try self.binding(plan.subject_binding, case, component));
        try self.endOrigin(origin);
    }

    fn renderMetadata(self: *Renderer, plan: MetadataPlan, state: RenderState) RenderError!void {
        const case = state.case orelse return error.UnsupportedReflectionTarget;
        const origin = try self.beginOrigin(plan.expression, state);
        switch (plan.kind) {
            .case_name => try self.appendQuoted(self.caseName(case)),
            .case_ordinal => {
                try self.append("UInt64(");
                try self.appendOrdinal(ordinalIndex(case));
                try self.append(")");
            },
            .components_named => try self.append(if (self.ast.declTag(self.target) == .struct_) "true" else "false"),
            .component_name => {
                const component = state.component orelse return error.ComponentPlaceOutsideLoop;
                if (self.ast.declTag(self.target) == .struct_) {
                    try self.appendQuoted(self.ast.tokenText(self.fieldsOfCase(case)[ordinalIndex(component)].name));
                } else {
                    try self.append("\"");
                    try self.appendOrdinal(ordinalIndex(component));
                    try self.append("\"");
                }
            },
            .component_ordinal => {
                try self.append("UInt64(");
                try self.appendOrdinal(ordinalIndex(state.component orelse return error.ComponentPlaceOutsideLoop));
                try self.append(")");
            },
        }
        try self.endOrigin(origin);
    }

    fn renderOrdinal(self: *Renderer, plan: OrdinalPlan) RenderError!void {
        const outer_origin = try self.beginOrigin(plan.call, .{});
        try self.append("match read ");
        const operand = self.ast.exprSpan(plan.operand);
        try self.renderRange(operand.start, operand.end, .{});
        try self.append(" {\n");
        const case_count = try self.caseCount();
        for (0..case_count) |case_index| {
            const case: CaseOrdinal = @enumFromInt(case_index);
            const arm_origin = try self.beginOrigin(plan.call, .{ .case = case });
            try self.renderPattern(plan.call, BindingId.none, case, false);
            try self.append(" => UInt64(");
            try self.appendOrdinal(case_index);
            try self.append("),\n");
            try self.endOrigin(arm_origin);
        }
        try self.append("}");
        try self.endOrigin(outer_origin);
    }

    /// Renders the callee of `reflect.wrap(value)` as the selected variant's
    /// constructor, leaving the argument list as written.
    fn renderWrap(self: *Renderer, plan: WrapPlan, case: CaseOrdinal) RenderError!void {
        if (self.ast.declTag(self.target) != .enum_) return error.UnsupportedReflectionTarget;
        const origin = try self.beginOrigin(plan.call, .{ .case = case });
        try self.append(self.ast.tokenText(self.ast.declName(self.target)));
        try self.append(".");
        try self.append(self.caseName(case));
        try self.endOrigin(origin);
    }

    fn renderFreeReference(self: *Renderer, reference: FreeReference) RenderError!void {
        try self.append(switch (reference.route) {
            .through_trait => self.qualifier orelse return,
            .through => |alias| alias,
            .as_written => return,
        });
        try self.append(".");
        try self.append(self.ast.tokenText(reference.member));
    }

    /// Marks parameters whose body references were erased. Contract roots
    /// follow the same fresh spelling without counting as body uses.
    /// Generated member origins retain the public template parameter names.
    fn markErasedParametersUnused(self: *Renderer) RenderError!void {
        const prefixes = try self.gpa.alloc(u32, self.plan.parameters.len);
        defer self.gpa.free(prefixes);
        @memset(prefixes, 0);
        for (self.plan.parameters, 0..) |parameter, i| {
            if (self.parameter_used[i] or parameter.declaration == .none) continue;
            const original = self.ast.tokenText(parameter.declaration);
            if (std.mem.startsWith(u8, original, "_")) continue;
            var candidate: std.ArrayList(u8) = .empty;
            defer candidate.deinit(self.gpa);
            try candidate.appendSlice(self.gpa, original);
            while (true) {
                if (candidate.items.len == std.math.maxInt(u32)) return error.GeneratedSourceTooLarge;
                try candidate.insert(self.gpa, 0, '_');
                prefixes[i] += 1;
                if (!self.occupied.contains(candidate.items)) break;
            }
        }
        var kept: usize = 0;
        var growth: usize = 0;
        for (self.parameter_positions.items) |position| {
            const prefix = prefixes[position.parameter];
            if (prefix == 0) continue;
            growth = try std.math.add(usize, growth, prefix);
            self.parameter_positions.items[kept] = position;
            kept += 1;
        }
        self.parameter_positions.shrinkRetainingCapacity(kept);
        if (kept == 0) return;
        if (growth > std.math.maxInt(u32) - self.out.items.len) return error.GeneratedSourceTooLarge;
        var renamed: std.ArrayList(u8) = .empty;
        errdefer renamed.deinit(self.gpa);
        try renamed.ensureTotalCapacity(self.gpa, self.out.items.len + growth);
        var copied: usize = 0;
        for (self.parameter_positions.items) |position| {
            renamed.appendSliceAssumeCapacity(self.out.items[copied..position.offset]);
            for (0..prefixes[position.parameter]) |_| renamed.appendAssumeCapacity('_');
            copied = position.offset;
        }
        renamed.appendSliceAssumeCapacity(self.out.items[copied..]);
        self.out.deinit(self.gpa);
        self.out = renamed;
        // All renamed spellings are in the signature, before reflected bodies.
        const last = self.parameter_positions.items[kept - 1].offset;
        for (self.origins.items) |*origin| {
            std.debug.assert(origin.start >= last);
            origin.start = try std.math.add(u32, origin.start, @intCast(growth));
            origin.end = try std.math.add(u32, origin.end, @intCast(growth));
        }
    }
};

pub fn renderMember(
    gpa: std.mem.Allocator,
    ast: *const Ast,
    derive: DeclId,
    target: DeclId,
    plan: *const ReflectionMemberPlan,
    free_references: []const FreeReference,
    qualifier: ?[]const u8,
    template_arguments: []const []const u8,
    wrapped: []const CaseOrdinal,
    component_types: ComponentTypes,
) RenderError!RenderedMember {
    std.debug.assert(wrapped.len == plan.wraps.len);
    const existing_reflection_operations = try std.math.add(
        usize,
        try std.math.add(usize, plan.cases.len, plan.same_cases.len),
        try std.math.add(
            usize,
            try std.math.add(usize, plan.loops.len, plan.places.len),
            try std.math.add(usize, plan.metadata.len, plan.ordinals.len),
        ),
    );
    const construction_operations = try std.math.add(
        usize,
        try std.math.add(usize, plan.constructions.len, plan.wraps.len),
        try std.math.add(usize, plan.component_types.len, plan.locals.len),
    );
    const reflection_operations = try std.math.add(usize, existing_reflection_operations, construction_operations);
    var parameter_operations = try std.math.add(usize, plan.parameters.len, plan.type_parameters.len);
    for (plan.parameters) |parameter| {
        parameter_operations = try std.math.add(usize, parameter_operations, parameter.references.len);
    }
    const operation_count = try std.math.add(
        usize,
        try std.math.add(
            usize,
            reflection_operations,
            rewritten: {
                var n: usize = 0;
                for (free_references) |reference| {
                    if (reference.rewritten(qualifier)) n += 1;
                }
                break :rewritten n;
            },
        ),
        parameter_operations,
    );
    const operations = try gpa.alloc(Operation, operation_count);
    defer gpa.free(operations);
    var at: usize = 0;
    for (plan.cases, 0..) |case, i| {
        operations[at] = .{ .span = ast.exprSpan(case.match), .kind = .case, .index = @intCast(i) };
        at += 1;
    }
    for (plan.same_cases, 0..) |same_case, i| {
        operations[at] = .{ .span = ast.exprSpan(same_case.match), .kind = .same_case, .index = @intCast(i) };
        at += 1;
    }
    for (plan.loops, 0..) |loop, i| {
        operations[at] = .{ .span = ast.exprSpan(loop.loop), .kind = .loop, .index = @intCast(i) };
        at += 1;
    }
    for (plan.places, 0..) |place, i| {
        operations[at] = .{ .span = ast.exprSpan(place.call), .kind = .place, .index = @intCast(i) };
        at += 1;
    }
    for (plan.metadata, 0..) |metadata, i| {
        operations[at] = .{ .span = ast.exprSpan(metadata.expression), .kind = .metadata, .index = @intCast(i) };
        at += 1;
    }
    for (plan.ordinals, 0..) |ordinal, i| {
        operations[at] = .{ .span = ast.exprSpan(ordinal.call), .kind = .ordinal, .index = @intCast(i) };
        at += 1;
    }
    for (free_references, 0..) |reference, i| {
        if (!reference.rewritten(qualifier)) continue;
        operations[at] = .{ .span = ast.tokenSpan(reference.at), .kind = .free_reference, .index = @intCast(i) };
        at += 1;
    }
    for (plan.parameters, 0..) |parameter, i| {
        operations[at] = .{ .span = ast.tokenSpan(parameter.declaration), .kind = .parameter_declaration, .index = @intCast(i) };
        at += 1;
        for (parameter.references) |reference| {
            operations[at] = .{ .span = ast.tokenSpan(reference.at), .kind = if (reference.contract) .parameter_contract_reference else .parameter_reference, .index = @intCast(i) };
            at += 1;
        }
    }
    for (plan.type_parameters, 0..) |reference, i| {
        operations[at] = .{ .span = ast.tokenSpan(reference.at), .kind = .type_parameter, .index = @intCast(i) };
        at += 1;
    }
    for (plan.wraps, 0..) |wrap, i| {
        operations[at] = .{ .span = ast.exprSpan(wrap.callee), .kind = .wrap, .index = @intCast(i) };
        at += 1;
    }
    for (plan.constructions, 0..) |construction, i| {
        operations[at] = .{ .span = ast.exprSpan(construction.call), .kind = .construction, .index = @intCast(i) };
        at += 1;
    }
    for (plan.component_types, 0..) |component_type, i| {
        operations[at] = .{ .span = ast.rangeSpan(component_type.tokens), .kind = .component_type, .index = @intCast(i) };
        at += 1;
    }
    for (plan.locals, 0..) |local, i| {
        operations[at] = .{ .span = ast.tokenSpan(local.at), .kind = .local, .index = @intCast(i) };
        at += 1;
    }
    std.debug.assert(at == operations.len);
    std.mem.sortUnstable(Operation, operations, {}, Operation.before);

    const source = ast.partOf(ast.declTokens(plan.member).start).source;
    const parameter_used = try gpa.alloc(bool, plan.parameters.len);
    defer gpa.free(parameter_used);
    @memset(parameter_used, false);
    var renderer: Renderer = .{
        .gpa = gpa,
        .ast = ast,
        .plan = plan,
        .free_references = free_references,
        .qualifier = qualifier,
        .template_arguments = template_arguments,
        .wrapped = wrapped,
        .source = source,
        .target = target,
        .component_types = component_types,
        .operations = operations,
        .parameter_used = parameter_used,
    };
    defer renderer.deinit();
    try renderer.buildBindings(derive);
    const member = ast.declSpan(plan.member);
    try renderer.renderRange(member.start, member.end, .{});
    try renderer.markErasedParametersUnused();
    const text = try renderer.out.toOwnedSlice(gpa);
    errdefer gpa.free(text);
    const origins = try renderer.origins.toOwnedSlice(gpa);
    return .{ .text = text, .origins = origins };
}
