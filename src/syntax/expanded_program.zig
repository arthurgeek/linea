const std = @import("std");
const testing = std.testing;

const Sink = @import("../diagnostics/sink.zig").Sink;
const Label = @import("../diagnostics/diagnostic.zig").Label;
const Diagnostic = @import("../diagnostics/diagnostic.zig").Diagnostic;
const Interner = @import("../support/interner.zig").Interner;
const StringId = @import("../support/interner.zig").StringId;
const Source = @import("../support/source.zig").Source;
const FileId = @import("../support/source.zig").FileId;
const Span = @import("../support/span.zig").Span;
const Table = @import("../support/table.zig").Table;
const parser = @import("../parser/parser.zig");
const TokenId = @import("../lexer/token.zig").TokenId;
const Ast = @import("ast.zig").Ast;
const DeclIndex = @import("ast.zig").DeclIndex;
const node = @import("node.zig");
const DeclId = node.DeclId;
const ExprId = node.ExprId;
const program_mod = @import("program.zig");
const Module = program_mod.Module;
const ModuleId = program_mod.ModuleId;
const Program = program_mod.Program;
const Kind = program_mod.Kind;

pub const Origin = struct {
    derive: DeclId,
    derive_trait: TokenId = .none,
    /// Names the struct, enum or newtype the derive implements the trait for.
    target: DeclId = .none,
    template_member: DeclId = .none,
    template_expr: ExprId = .none,
    case_ordinal: ?CaseOrdinal = null,
    component_ordinal: ?ComponentOrdinal = null,
};

pub const OriginId = enum(u32) {
    none = std.math.maxInt(u32),
    _,

    pub fn at(index_: u32) OriginId {
        std.debug.assert(index_ != std.math.maxInt(u32));
        return @enumFromInt(index_);
    }

    pub fn index(self: OriginId) u32 {
        std.debug.assert(self != .none);
        return @intFromEnum(self);
    }
};

pub const GeneratedOriginSegment = struct {
    file: FileId,
    span: Span,
    derive_trait: node.DeriveTraitId = .none,
    origin: Origin,
};

const StoredOriginSegment = struct {
    file: FileId,
    span: Span,
    origin: OriginId,
    parent: u32,
};

const no_segment = std.math.maxInt(u32);

pub const GeneratedDecl = struct {
    module: ModuleId,
    derive_trait: node.DeriveTraitId = .none,
    origin: Origin,
};

pub const GeneratedImport = struct {
    decl: DeclId,
    target: ModuleId,
};

fn validSourceOrigin(ast: *const Ast, origin: Origin, derive_trait: node.DeriveTraitId) bool {
    if (origin.derive.index() >= ast.declCount()) return false;
    if (origin.derive_trait == .none) return derive_trait == .none;
    if (derive_trait == .none or derive_trait.index() >= ast.derive_traits.len or
        origin.derive_trait.index() >= ast.tokenCount())
    {
        return false;
    }
    const range = ast.deriveRequestTraitRange(origin.derive);
    if (derive_trait.index() < range.start or derive_trait.index() >= range.end) return false;
    return ast.deriveTrait(derive_trait).ref.name == origin.derive_trait;
}

/// One source template member and the trait signature the resolver paired it
/// with. The type checker consumes this identity rather than matching names a
/// second time.
pub const TemplateMemberPlan = struct {
    template: DeclId,
    trait: DeclId,
    member: DeclId,
    signature: DeclId,
};

pub const GeneratedImplementationId = enum(u32) {
    none = std.math.maxInt(u32),
    _,

    pub fn at(index_: u32) GeneratedImplementationId {
        return @enumFromInt(index_);
    }

    pub fn index(self: GeneratedImplementationId) u32 {
        return @intFromEnum(self);
    }
};

pub const CaseOrdinal = enum(u32) { _ };
pub const ComponentOrdinal = enum(u32) { _ };
pub const RequirementBoundOrdinal = enum(u32) { _ };

pub const ComponentRequirementRange = struct {
    start: u32,
    end: u32,

    pub const empty: ComponentRequirementRange = .{ .start = 0, .end = 0 };

    pub fn len(self: ComponentRequirementRange) u32 {
        return self.end - self.start;
    }
};

pub const GeneratedImplementation = struct {
    generated_impl: DeclId,
    derive: DeclId,
    derive_trait: node.DeriveTraitId,
    target: DeclId,
    template: DeclId,
    requirements: ComponentRequirementRange,
};

pub const ComponentRequirement = struct {
    implementation: GeneratedImplementationId,
    requirement: node.TemplateRequirementId,
    bound: RequirementBoundOrdinal,
    case: CaseOrdinal = @enumFromInt(0),
    component: ComponentOrdinal,
};

/// Complete immutable generated paths and buffers owned by an expanded
/// compilation. The resolver transfers its allocations before parsing, so the
/// expanded AST borrows these same bytes until it is destroyed.
pub const GeneratedSources = struct {
    paths: []const []const u8 = &.{},
    buffers: []const []const u8 = &.{},

    pub const empty: GeneratedSources = .{};

    fn freeStrings(gpa: std.mem.Allocator, strings: []const []const u8) void {
        for (strings) |string| gpa.free(string);
        gpa.free(strings);
    }

    pub fn path(self: *const GeneratedSources, index: usize) []const u8 {
        return self.paths[index];
    }

    pub fn get(self: *const GeneratedSources, index: usize) []const u8 {
        return self.buffers[index];
    }

    pub fn deinit(self: *GeneratedSources, gpa: std.mem.Allocator) void {
        freeStrings(gpa, self.paths);
        freeStrings(gpa, self.buffers);
        self.* = .empty;
    }
};

const FineOrigins = struct {
    rows: []const Origin,
    segments: []const StoredOriginSegment,
    segment_minima: []const u32,

    fn init(
        gpa: std.mem.Allocator,
        source: *const Program,
        ast: *const Ast,
        generated: []const GeneratedOriginSegment,
    ) (std.mem.Allocator.Error || error{InvalidGeneratedOrigin})!FineOrigins {
        const rows = try gpa.alloc(Origin, generated.len);
        errdefer gpa.free(rows);
        const segments = try gpa.alloc(StoredOriginSegment, generated.len);
        errdefer gpa.free(segments);

        const FileMetadata = struct { source_len: usize, authored: bool };
        var files: std.AutoHashMapUnmanaged(FileId, FileMetadata) = .empty;
        defer files.deinit(gpa);
        if (generated.len != 0) {
            // File IDs need not follow token order. Index each part once
            // instead of scanning the tree for every rendered segment.
            for (ast.parts) |part| {
                const entry = try files.getOrPut(gpa, part.file);
                if (!entry.found_existing) entry.value_ptr.* = .{ .source_len = part.source.len, .authored = false };
            }
            for (source.ast.parts) |part| {
                if (files.getPtr(part.file)) |file| file.authored = true;
            }
        }

        var previous: ?GeneratedOriginSegment = null;
        var nesting: std.ArrayList(usize) = .empty;
        defer nesting.deinit(gpa);
        for (generated, 0..) |segment, i| {
            const metadata = files.get(segment.file) orelse return error.InvalidGeneratedOrigin;
            if (segment.span.start >= segment.span.end or segment.span.end > metadata.source_len or
                metadata.authored or
                !validSourceOrigin(&source.ast, segment.origin, segment.derive_trait) or
                segment.origin.template_member == .none or
                segment.origin.template_member.index() >= source.ast.declCount() or
                segment.origin.template_expr == .none or
                segment.origin.template_expr.index() >= source.ast.exprCount())
            {
                return error.InvalidGeneratedOrigin;
            }
            if (previous) |prior| {
                const prior_file: u32 = @intFromEnum(prior.file);
                const file: u32 = @intFromEnum(segment.file);
                if (file < prior_file or (file == prior_file and segment.span.start < prior.span.start)) {
                    return error.InvalidGeneratedOrigin;
                }
                if (file != prior_file) {
                    nesting.clearRetainingCapacity();
                }
            }
            while (nesting.items.len > 0 and segments[nesting.items[nesting.items.len - 1]].span.end <= segment.span.start) {
                _ = nesting.pop();
            }
            if (nesting.items.len > 0 and segment.span.end > segments[nesting.items[nesting.items.len - 1]].span.end) {
                return error.InvalidGeneratedOrigin;
            }
            previous = segment;
            rows[i] = segment.origin;
            segments[i] = .{
                .file = segment.file,
                .span = segment.span,
                .origin = .at(@intCast(i)),
                .parent = if (nesting.items.len > 0) @intCast(nesting.items[nesting.items.len - 1]) else no_segment,
            };
            try nesting.append(gpa, i);
        }

        const segment_minima = try buildSegmentMinima(gpa, segments);
        errdefer gpa.free(segment_minima);

        return .{
            .rows = rows,
            .segments = segments,
            .segment_minima = segment_minima,
        };
    }

    fn deinit(self: *FineOrigins, gpa: std.mem.Allocator) void {
        gpa.free(self.rows);
        gpa.free(self.segments);
        gpa.free(self.segment_minima);
        self.* = undefined;
    }
};

fn narrowerSegment(segments: []const StoredOriginSegment, lhs: u32, rhs: u32) u32 {
    if (lhs == no_segment) return rhs;
    if (rhs == no_segment) return lhs;
    const lhs_len = segments[lhs].span.len();
    const rhs_len = segments[rhs].span.len();
    if (lhs_len != rhs_len) return if (lhs_len < rhs_len) lhs else rhs;
    return @max(lhs, rhs);
}

fn buildSegmentMinima(gpa: std.mem.Allocator, segments: []const StoredOriginSegment) std.mem.Allocator.Error![]u32 {
    if (segments.len == 0) return gpa.alloc(u32, 0);
    var leaves: usize = 1;
    while (leaves < segments.len) leaves *= 2;
    const tree = try gpa.alloc(u32, leaves * 2);
    @memset(tree, no_segment);
    for (segments, 0..) |_, i| tree[leaves + i] = @intCast(i);
    var i = leaves;
    while (i > 1) {
        i -= 1;
        tree[i] = narrowerSegment(segments, tree[i * 2], tree[i * 2 + 1]);
    }
    return tree;
}

fn segmentLowerBound(segments: []const StoredOriginSegment, file: FileId, start: u32) usize {
    var lo: usize = 0;
    var hi = segments.len;
    const file_index: u32 = @intFromEnum(file);
    while (lo < hi) {
        const mid = lo + (hi - lo) / 2;
        const segment_file: u32 = @intFromEnum(segments[mid].file);
        if (segment_file < file_index or
            (segment_file == file_index and segments[mid].span.start < start))
        {
            lo = mid + 1;
        } else {
            hi = mid;
        }
    }
    return lo;
}

fn narrowestInRange(segments: []const StoredOriginSegment, minima: []const u32, start: usize, end: usize) u32 {
    if (start >= end) return no_segment;
    const leaves = minima.len / 2;
    var left = leaves + start;
    var right = leaves + end;
    var best: u32 = no_segment;
    while (left < right) {
        if (left % 2 == 1) {
            best = narrowerSegment(segments, best, minima[left]);
            left += 1;
        }
        if (right % 2 == 1) {
            right -= 1;
            best = narrowerSegment(segments, best, minima[right]);
        }
        left /= 2;
        right /= 2;
    }
    return best;
}

/// The narrowest generated segment touching a location. Segments are ordered
/// by file and start, with containing segments before contained ones.
fn originAt(segments: []const StoredOriginSegment, minima: []const u32, file: FileId, span: Span) OriginId {
    if (span.start >= span.end or segments.len == 0) return .none;
    const at_start = segmentLowerBound(segments, file, span.start);
    const at_end = segmentLowerBound(segments, file, span.end);
    var best = narrowestInRange(segments, minima, at_start, at_end);

    if (at_start > 0) {
        var candidate: u32 = @intCast(at_start - 1);
        while (segments[candidate].file == file) {
            if (segments[candidate].span.end > span.start) {
                best = narrowerSegment(segments, best, candidate);
                break;
            }
            candidate = segments[candidate].parent;
            if (candidate == no_segment) break;
        }
    }
    return if (best == no_segment) .none else segments[best].origin;
}

test "generated origin index finds the narrowest overlapping segment" {
    const segments = [_]StoredOriginSegment{
        .{ .file = .from(0), .span = .{ .start = 0, .end = 100 }, .origin = .at(0), .parent = no_segment },
        .{ .file = .from(0), .span = .{ .start = 10, .end = 20 }, .origin = .at(1), .parent = 0 },
        .{ .file = .from(0), .span = .{ .start = 30, .end = 35 }, .origin = .at(2), .parent = 0 },
        .{ .file = .from(1), .span = .{ .start = 0, .end = 10 }, .origin = .at(3), .parent = no_segment },
    };
    const minima = try buildSegmentMinima(testing.allocator, &segments);
    defer testing.allocator.free(minima);

    try testing.expectEqual(OriginId.at(1), originAt(&segments, minima, .from(0), .{ .start = 12, .end = 13 }));
    try testing.expectEqual(OriginId.at(2), originAt(&segments, minima, .from(0), .{ .start = 15, .end = 34 }));
    try testing.expectEqual(OriginId.at(0), originAt(&segments, minima, .from(0), .{ .start = 25, .end = 26 }));
    try testing.expectEqual(OriginId.none, originAt(&segments, minima, .from(0), .{ .start = 100, .end = 101 }));
    try testing.expectEqual(OriginId.at(3), originAt(&segments, minima, .from(1), .{ .start = 1, .end = 2 }));
}

/// A half-open range of positions in `ExpandedProgram.module_decls`.
pub const ModuleDeclListRange = struct {
    start: u32,
    end: u32,
};

/// The immutable syntax and declaration roots consumed after expansion.
pub const ExpandedProgram = struct {
    source: *const Program,
    modules: []Module,
    prelude: ModuleId,
    kind: Kind,
    ast: Ast,
    decl_modules: Table(DeclId, ModuleId),
    import_targets: Table(DeclId, ModuleId),
    active: Table(DeclId, bool),
    module_decl_ranges: Table(ModuleId, ModuleDeclListRange),
    module_decls: []const DeclId,
    origins: Table(DeclId, ?Origin),
    /// The origin of each generated file, indexed by `FileId`, and null for
    /// a file the source wrote. A generated file holds the declarations of
    /// one expansion, so its first declaration's origin is the file's.
    ///
    /// **Bound:** one entry per file id the parts number, filled by one visit
    /// per part. A diagnostic asking which derive a file came from reads one
    /// entry rather than walking the file's declarations.
    file_origins: Table(FileId, ?Origin),
    origin_rows: []const Origin,
    origin_segments: []const StoredOriginSegment,
    origin_segment_minima: []const u32,
    template_members: []const TemplateMemberPlan,
    generated_implementations: []const GeneratedImplementation,
    component_requirements: []const ComponentRequirement,
    interner: Interner,
    generated_sources: GeneratedSources,
    borrowed_source: bool = false,

    pub const InitError = std.mem.Allocator.Error || error{
        InvalidGeneratedDeclarationCount,
        InvalidGeneratedModule,
        InvalidGeneratedOrigin,
        InvalidGeneratedImport,
        InvalidTemplatePlan,
        InvalidGeneratedImplementation,
        InvalidComponentRequirement,
    };

    pub fn borrowSource(gpa: std.mem.Allocator, source: *const Program) !ExpandedProgram {
        var decl_modules = try source.ast.declTable(gpa, ModuleId, .none);
        errdefer decl_modules.deinit(gpa);
        var active = try source.ast.declTable(gpa, bool, true);
        errdefer active.deinit(gpa);
        var import_targets = try source.ast.declTable(gpa, ModuleId, .none);
        errdefer import_targets.deinit(gpa);
        var origins = try source.ast.declTable(gpa, ?Origin, null);
        errdefer origins.deinit(gpa);
        var module_decl_ranges = try Table(ModuleId, ModuleDeclListRange).of(
            gpa,
            source.modules.len,
            .{ .start = 0, .end = 0 },
        );
        errdefer module_decl_ranges.deinit(gpa);
        const module_decls = try gpa.alloc(DeclId, source.ast.declCount());
        errdefer gpa.free(module_decls);
        var at: u32 = 0;
        for (source.modules, 0..) |module, module_index| {
            const start = at;
            for (module.decls.start..module.decls.end) |i| {
                const decl = DeclId.at(@intCast(i));
                module_decls[at] = decl;
                decl_modules.set(decl, ModuleId.from(module_index));
                at += 1;
            }
            module_decl_ranges.set(ModuleId.from(module_index), .{ .start = start, .end = at });
        }
        return .{
            .source = source,
            .modules = source.modules,
            .prelude = source.prelude,
            .kind = source.kind,
            .ast = source.ast,
            .decl_modules = decl_modules,
            .import_targets = import_targets,
            .active = active,
            .module_decl_ranges = module_decl_ranges,
            .module_decls = module_decls,
            .origins = origins,
            .file_origins = try fileOrigins(gpa, &source.ast, source.ast.parts.len, origins),
            .origin_rows = &.{},
            .origin_segments = &.{},
            .origin_segment_minima = &.{},
            .template_members = &.{},
            .generated_implementations = &.{},
            .component_requirements = &.{},
            .interner = .empty,
            .generated_sources = .empty,
            .borrowed_source = true,
        };
    }

    /// Takes ownership of joined syntax and its interner, including on failure.
    /// Library module IDs and metadata ordinals remain stable; generated syntax
    /// IDs move after the application's complete source prefix.
    pub fn attachLibraryPrefix(
        gpa: std.mem.Allocator,
        source: *const Program,
        ast: *Ast,
        interner: *Interner,
        cached: *const ExpandedProgram,
        relocation: @import("relocation.zig").Relocation,
    ) InitError!ExpandedProgram {
        var owned_ast = ast.*;
        ast.* = undefined;
        var owned_interner = interner.*;
        interner.* = .empty;
        var transferred = false;
        errdefer if (!transferred) {
            owned_ast.deinit(gpa);
            owned_interner.deinit(gpa);
        };

        var sources: GeneratedSources = .empty;
        defer sources.deinit(gpa);
        sources.paths = try dupeStrings(gpa, cached.generated_sources.paths);
        sources.buffers = try dupeStrings(gpa, cached.generated_sources.buffers);
        std.debug.assert(owned_ast.parts.len - source.ast.parts.len == sources.buffers.len);
        for (@constCast(owned_ast.parts[source.ast.parts.len..]), 0..) |*part, i| {
            part.path = sources.paths[i];
            part.source = sources.buffers[i];
        }

        // Origin tables retain the written trait token. Recover its typed row
        // once, so rebuilding both coarse and fine origins is linear.
        var derive_traits = try Table(TokenId, node.DeriveTraitId).of(gpa, cached.source.ast.tokenCount(), .none);
        defer derive_traits.deinit(gpa);
        for (cached.source.ast.derive_traits, 0..) |trait, i| {
            if (trait.ref.name != .none) derive_traits.set(trait.ref.name, .at(@intCast(i)));
        }
        const generated = try gpa.alloc(GeneratedDecl, cached.ast.declCount() - cached.source.ast.declCount());
        defer gpa.free(generated);
        var imports: std.ArrayList(GeneratedImport) = .empty;
        defer imports.deinit(gpa);
        for (generated, 0..) |*entry, i| {
            const decl = DeclId.at(cached.source.ast.declCount() + @as(u32, @intCast(i)));
            const origin = cached.origins.get(decl).?;
            entry.* = .{
                .module = cached.decl_modules.get(decl),
                .origin = relocation.value(origin),
                .derive_trait = if (origin.derive_trait == .none) .none else relocation.value(derive_traits.get(origin.derive_trait)),
            };
            const target = cached.import_targets.get(decl);
            if (target != .none) try imports.append(gpa, .{ .decl = relocation.value(decl), .target = target });
        }
        const segments = try gpa.alloc(GeneratedOriginSegment, cached.origin_segments.len);
        defer gpa.free(segments);
        for (segments, cached.origin_segments) |*entry, segment| {
            const origin = cached.origin_rows[segment.origin.index()];
            entry.* = .{
                .file = relocation.value(segment.file),
                .span = segment.span,
                .origin = relocation.value(origin),
                .derive_trait = if (origin.derive_trait == .none) .none else relocation.value(derive_traits.get(origin.derive_trait)),
            };
        }
        const plans = try gpa.alloc(TemplateMemberPlan, cached.template_members.len);
        defer gpa.free(plans);
        for (plans, cached.template_members) |*out, row| out.* = relocation.value(row);
        var implementations = try gpa.alloc(GeneratedImplementation, cached.generated_implementations.len);
        defer gpa.free(implementations);
        for (implementations, cached.generated_implementations) |*out, row| out.* = relocation.value(row);
        var requirements = try gpa.alloc(ComponentRequirement, cached.component_requirements.len);
        defer gpa.free(requirements);
        for (requirements, cached.component_requirements) |*out, row| out.* = relocation.value(row);
        transferred = true;
        return init(gpa, source, &owned_ast, &owned_interner, &sources, plans, &implementations, &requirements, generated, imports.items, segments);
    }

    /// Takes ownership of the expanded representations and generated tables,
    /// including on failure, and copies the resolver's immutable template plans.
    pub fn init(
        gpa: std.mem.Allocator,
        source: *const Program,
        ast: *Ast,
        interner: *Interner,
        generated_sources: *GeneratedSources,
        template_members: []const TemplateMemberPlan,
        generated_implementations: *[]GeneratedImplementation,
        component_requirements: *[]ComponentRequirement,
        generated: []const GeneratedDecl,
        generated_imports: []const GeneratedImport,
        generated_origin_segments: []const GeneratedOriginSegment,
    ) InitError!ExpandedProgram {
        var owned_generated_sources = generated_sources.*;
        generated_sources.* = .empty;
        errdefer owned_generated_sources.deinit(gpa);

        var owned_interner = interner.*;
        interner.* = .empty;
        errdefer owned_interner.deinit(gpa);

        var owned_ast = ast.*;
        ast.* = undefined;
        errdefer owned_ast.deinit(gpa);

        const owned_generated_implementations = generated_implementations.*;
        generated_implementations.* = &.{};
        errdefer gpa.free(owned_generated_implementations);
        const owned_component_requirements = component_requirements.*;
        component_requirements.* = &.{};
        errdefer gpa.free(owned_component_requirements);

        const source_decl_count = source.ast.declCount();
        const expanded_decl_count = owned_ast.declCount();
        try validateGenerated(source_decl_count, source.ast.tokenCount(), expanded_decl_count, source.modules.len, generated);
        for (generated) |entry| {
            if (!validSourceOrigin(&source.ast, entry.origin, entry.derive_trait)) return error.InvalidGeneratedOrigin;
        }
        try validateTemplateMembers(source_decl_count, template_members);
        const owned_template_members = try gpa.dupe(TemplateMemberPlan, template_members);
        errdefer gpa.free(owned_template_members);

        try validateGeneratedImplementations(
            &source.ast,
            &owned_ast,
            owned_generated_implementations,
            owned_component_requirements,
        );

        var decl_modules = try owned_ast.declTable(gpa, ModuleId, .none);
        errdefer decl_modules.deinit(gpa);
        var active = try owned_ast.declTable(gpa, bool, false);
        errdefer active.deinit(gpa);
        var import_targets = try owned_ast.declTable(gpa, ModuleId, .none);
        errdefer import_targets.deinit(gpa);
        var origins = try owned_ast.declTable(gpa, ?Origin, null);
        errdefer origins.deinit(gpa);
        var fine_origins = try FineOrigins.init(gpa, source, &owned_ast, generated_origin_segments);
        errdefer fine_origins.deinit(gpa);

        const module_counts = try gpa.alloc(u32, source.modules.len);
        defer gpa.free(module_counts);
        @memset(module_counts, 0);

        var mapped_source: u32 = 0;
        for (source.modules, 0..) |module, module_index| {
            std.debug.assert(module.decls.end <= source_decl_count);
            const module_id = ModuleId.from(module_index);
            for (module.decls.start..module.decls.end) |i| {
                const decl = DeclId.at(@intCast(i));
                std.debug.assert(decl_modules.get(decl) == .none);
                decl_modules.set(decl, module_id);
                mapped_source += 1;

                const is_active = switch (owned_ast.declTag(decl)) {
                    .template_impl, .derive_impl => false,
                    else => true,
                };
                active.set(decl, is_active);
            }
        }
        std.debug.assert(mapped_source == source_decl_count);

        var decl_index = try DeclIndex.build(gpa, &source.ast);
        defer decl_index.deinit(gpa);
        for (0..source_decl_count) |i| {
            const template = DeclId.at(@intCast(i));
            if (source.ast.declTag(template) != .template_impl) continue;
            // A template's members are instantiated where it is expanded, not
            // read where they are written. A test in its braces is a member of
            // nothing and stays an ordinary declaration of the module, refused
            // where it was parsed and resolved like any other test.
            for (decl_index.within(source.ast.declTokens(template))) |decl| {
                if (decl != template and source.ast.memberOwner(decl) == .none) continue;
                active.set(decl, false);
            }
        }
        for (source.modules, 0..) |module, module_index| {
            for (module.decls.start..module.decls.end) |i| {
                if (active.get(DeclId.at(@intCast(i)))) module_counts[module_index] += 1;
            }
        }

        for (generated, 0..) |entry, ordinal| {
            const decl = DeclId.at(source_decl_count + @as(u32, @intCast(ordinal)));
            decl_modules.set(decl, entry.module);
            active.set(decl, true);
            origins.set(decl, entry.origin);
            module_counts[entry.module.index()] += 1;
        }
        for (generated_imports) |entry| {
            if (entry.decl.index() < source_decl_count or entry.decl.index() >= expanded_decl_count or
                owned_ast.declTag(entry.decl) != .import_ or entry.target == .none or
                entry.target.index() >= source.modules.len or import_targets.get(entry.decl) != .none)
            {
                return error.InvalidGeneratedImport;
            }
            import_targets.set(entry.decl, entry.target);
        }

        var module_decl_ranges = try Table(ModuleId, ModuleDeclListRange).of(
            gpa,
            source.modules.len,
            .{ .start = 0, .end = 0 },
        );
        errdefer module_decl_ranges.deinit(gpa);

        var total: u32 = 0;
        for (module_counts, 0..) |count, module_index| {
            const start = total;
            total += count;
            module_decl_ranges.set(ModuleId.from(module_index), .{ .start = start, .end = total });
            module_counts[module_index] = start;
        }

        const module_decls = try gpa.alloc(DeclId, total);
        errdefer gpa.free(module_decls);
        var declarations = decl_modules.pairs();
        while (declarations.next()) |entry| {
            if (!active.get(entry.id)) continue;
            std.debug.assert(entry.value != .none);
            const cursor = &module_counts[entry.value.index()];
            module_decls[cursor.*] = entry.id;
            cursor.* += 1;
        }

        return .{
            .source = source,
            .modules = source.modules,
            .prelude = source.prelude,
            .kind = source.kind,
            .ast = owned_ast,
            .decl_modules = decl_modules,
            .import_targets = import_targets,
            .active = active,
            .module_decl_ranges = module_decl_ranges,
            .module_decls = module_decls,
            .origins = origins,
            .file_origins = try fileOrigins(gpa, &owned_ast, source.ast.parts.len, origins),
            .origin_rows = fine_origins.rows,
            .origin_segments = fine_origins.segments,
            .origin_segment_minima = fine_origins.segment_minima,
            .template_members = owned_template_members,
            .generated_implementations = owned_generated_implementations,
            .component_requirements = owned_component_requirements,
            .interner = owned_interner,
            .generated_sources = owned_generated_sources,
        };
    }

    /// The origin of every generated file, read off each generated part's
    /// first declaration; the parts before `source_parts` are the source's
    /// and have none.
    fn fileOrigins(gpa: std.mem.Allocator, ast: *const Ast, source_parts: usize, origins: Table(DeclId, ?Origin)) !Table(FileId, ?Origin) {
        var files: usize = 0;
        for (ast.parts) |part| files = @max(files, part.file.index() + 1);
        var table = try Table(FileId, ?Origin).of(gpa, files, null);
        errdefer table.deinit(gpa);
        for (ast.parts[source_parts..]) |part| {
            if (part.decl_start == part.decl_end) continue;
            table.set(part.file, origins.get(DeclId.at(part.decl_start)));
        }
        return table;
    }

    fn validateGenerated(
        source_decl_count: u32,
        source_token_count: u32,
        expanded_decl_count: u32,
        module_count: usize,
        generated: []const GeneratedDecl,
    ) error{ InvalidGeneratedDeclarationCount, InvalidGeneratedModule, InvalidGeneratedOrigin }!void {
        if (source_decl_count > expanded_decl_count or
            generated.len != expanded_decl_count - source_decl_count)
        {
            return error.InvalidGeneratedDeclarationCount;
        }
        for (generated) |entry| {
            if (entry.module.index() >= module_count) return error.InvalidGeneratedModule;
            if (entry.origin.derive.index() >= source_decl_count or
                (entry.origin.derive_trait != .none and
                    entry.origin.derive_trait.index() >= source_token_count) or
                (entry.origin.template_member != .none and
                    entry.origin.template_member.index() >= source_decl_count))
            {
                return error.InvalidGeneratedOrigin;
            }
        }
    }

    fn validateTemplateMembers(
        source_decl_count: u32,
        plans: []const TemplateMemberPlan,
    ) error{InvalidTemplatePlan}!void {
        for (plans) |plan| {
            if (plan.template.index() >= source_decl_count or
                plan.trait.index() >= source_decl_count or
                plan.member.index() >= source_decl_count or
                plan.signature.index() >= source_decl_count)
            {
                return error.InvalidTemplatePlan;
            }
        }
    }

    fn validateGeneratedImplementations(
        source: *const Ast,
        expanded: *const Ast,
        implementations: []const GeneratedImplementation,
        requirements: []const ComponentRequirement,
    ) error{ InvalidGeneratedImplementation, InvalidComponentRequirement }!void {
        if (implementations.len > std.math.maxInt(u32)) return error.InvalidGeneratedImplementation;
        if (requirements.len > std.math.maxInt(u32)) return error.InvalidComponentRequirement;

        var requirement_cursor: u32 = 0;
        for (implementations, 0..) |implementation, implementation_index| {
            const implementation_id = GeneratedImplementationId.at(
                std.math.cast(u32, implementation_index) orelse return error.InvalidGeneratedImplementation,
            );
            if (implementation.generated_impl.index() < source.declCount() or
                implementation.generated_impl.index() >= expanded.declCount() or
                expanded.declTag(implementation.generated_impl) != .impl_ or
                implementation.derive.index() >= source.declCount() or
                source.deriveRequestTraitRange(implementation.derive).len() == 0 or
                implementation.target.index() >= source.declCount() or
                (source.declTag(implementation.target) != .struct_ and
                    source.declTag(implementation.target) != .enum_ and
                    source.declTag(implementation.target) != .newtype) or
                implementation.template.index() >= source.declCount() or
                source.declTag(implementation.template) != .template_impl)
            {
                return error.InvalidGeneratedImplementation;
            }

            const derive_range = source.deriveRequestTraitRange(implementation.derive);
            if (implementation.derive_trait == .none or
                implementation.derive_trait.index() < derive_range.start or
                implementation.derive_trait.index() >= derive_range.end)
            {
                return error.InvalidGeneratedImplementation;
            }

            if (implementation.requirements.start != requirement_cursor or
                implementation.requirements.end < implementation.requirements.start or
                implementation.requirements.end > requirements.len)
            {
                return error.InvalidComponentRequirement;
            }

            const template_requirement_range = source.templateRequirementRange(implementation.template);
            if (template_requirement_range.end < template_requirement_range.start or
                template_requirement_range.end > source.template_requirements.len)
            {
                return error.InvalidComponentRequirement;
            }
            const template_requirements = source.template_requirements[template_requirement_range.start..template_requirement_range.end];
            const case_count: u32 = switch (source.declTag(implementation.target)) {
                .struct_, .newtype => 1,
                .enum_ => std.math.cast(u32, source.declVariants(implementation.target).len) orelse
                    return error.InvalidComponentRequirement,
                else => unreachable,
            };

            var row_index = implementation.requirements.start;
            for (0..case_count) |case_index| {
                const component_count: u32 = switch (source.declTag(implementation.target)) {
                    .struct_ => std.math.cast(u32, source.declFields(implementation.target).len) orelse
                        return error.InvalidComponentRequirement,
                    .newtype => 1,
                    .enum_ => std.math.cast(
                        u32,
                        source.variantFields(source.declVariants(implementation.target)[case_index]).len,
                    ) orelse return error.InvalidComponentRequirement,
                    else => unreachable,
                };
                for (0..component_count) |component_index| {
                    for (template_requirements, 0..) |requirement, requirement_offset| {
                        const requirement_index = std.math.add(
                            u32,
                            template_requirement_range.start,
                            std.math.cast(u32, requirement_offset) orelse return error.InvalidComponentRequirement,
                        ) catch return error.InvalidComponentRequirement;
                        for (source.boundsIn(requirement.bounds), 0..) |_, bound_index| {
                            if (row_index >= implementation.requirements.end) return error.InvalidComponentRequirement;
                            const row = requirements[row_index];
                            if (row.implementation != implementation_id or
                                row.requirement.index() != requirement_index or
                                @intFromEnum(row.bound) != bound_index or
                                @intFromEnum(row.case) != case_index or
                                @intFromEnum(row.component) != component_index)
                            {
                                return error.InvalidComponentRequirement;
                            }
                            row_index = std.math.add(u32, row_index, 1) catch return error.InvalidComponentRequirement;
                        }
                    }
                }
            }
            if (row_index != implementation.requirements.end) return error.InvalidComponentRequirement;
            requirement_cursor = implementation.requirements.end;
        }
        if (requirement_cursor != requirements.len) return error.InvalidComponentRequirement;
    }

    pub fn moduleOf(self: *const ExpandedProgram, decl: DeclId) ModuleId {
        return self.decl_modules.get(decl);
    }

    pub fn root(self: *const ExpandedProgram) *const Module {
        return &self.modules[self.source.primary.index()];
    }

    pub fn get(self: *const ExpandedProgram, module: ModuleId) *const Module {
        return &self.modules[module.index()];
    }

    /// Whether module `m` belongs to a library root.
    pub fn inLibraryRoot(self: *const ExpandedProgram, m: ModuleId) bool {
        if (m == .none) return false;
        return program_mod.moduleInLibraryRoot(self.get(m), self.kind);
    }

    /// Whether `decl` is an `export` the artefact being built publishes. One
    /// in a dependency publishes nothing to the program that depends on it,
    /// which calls it as an ordinary public function.
    pub fn publishesExport(self: *const ExpandedProgram, decl: DeclId) bool {
        if (!self.ast.declIsExport(decl)) return false;
        const module = self.moduleOf(decl);
        return module == .none or !self.get(module).root.isDependency();
    }

    /// The dotted path a module is known by, which the loaded program
    /// recorded as its import route.
    pub fn modulePath(self: *const ExpandedProgram, module: ModuleId) []const u8 {
        if (module.index() < self.source.modules.len) return self.source.modulePath(module);
        return self.get(module).name;
    }

    pub fn importedBy(self: *const ExpandedProgram, decl: DeclId) ModuleId {
        const generated = self.import_targets.get(decl);
        if (generated != .none) return generated;
        const module = self.moduleOf(decl);
        if (module == .none) return .none;
        return self.get(module).importedBy(decl);
    }

    pub fn libraryDeclIn(self: *const ExpandedProgram, module: []const u8, name: []const u8) ?DeclId {
        return self.source.libraryDeclIn(module, name);
    }

    pub fn declsOf(self: *const ExpandedProgram, module: ModuleId) []const DeclId {
        const range = self.module_decl_ranges.get(module);
        return self.module_decls[range.start..range.end];
    }

    pub fn isActive(self: *const ExpandedProgram, decl: DeclId) bool {
        return self.active.get(decl);
    }

    pub const GeneratedSourceView = struct {
        path: []const u8,
        text: []const u8,
        module: ModuleId,
        origin: Origin,
    };

    pub fn generatedSourceCount(self: *const ExpandedProgram) u32 {
        return @intCast(self.generated_sources.buffers.len);
    }

    pub fn generatedSource(self: *const ExpandedProgram, index: u32) GeneratedSourceView {
        const source_part = self.source.ast.parts.len + index;
        const part = self.ast.parts[source_part];
        std.debug.assert(part.decl_start < part.decl_end);
        const declaration = DeclId.at(part.decl_start);
        return .{
            .path = self.generated_sources.path(index),
            .text = self.generated_sources.get(index),
            .module = self.moduleOf(declaration),
            .origin = self.originOf(declaration).?,
        };
    }

    pub fn generatedImplementationCount(self: *const ExpandedProgram) u32 {
        return @intCast(self.generated_implementations.len);
    }

    pub fn generatedImplementation(
        self: *const ExpandedProgram,
        id: GeneratedImplementationId,
    ) GeneratedImplementation {
        return self.generated_implementations[id.index()];
    }

    pub fn componentRequirements(
        self: *const ExpandedProgram,
        implementation: GeneratedImplementationId,
    ) []const ComponentRequirement {
        const range = self.generatedImplementation(implementation).requirements;
        return self.component_requirements[range.start..range.end];
    }

    /// Whether this token declares part of a source template's callable
    /// interface: its member name or one of that member's parameters.
    pub fn isTemplateInterfaceToken(self: *const ExpandedProgram, token: TokenId) bool {
        if (token == .none) return false;
        for (self.template_members) |plan| {
            if (self.source.ast.declName(plan.member) == token) return true;
            for (self.source.ast.declParams(plan.member)) |param| {
                if (param.name == token) return true;
            }
        }
        return false;
    }

    pub fn originOf(self: *const ExpandedProgram, decl: DeclId) ?Origin {
        return self.origins.get(decl);
    }

    fn primaryDecl(self: *const ExpandedProgram, decl: DeclId) DeclId {
        return if (self.originOf(decl)) |origin| origin.derive else decl;
    }

    pub fn primaryFileOfDecl(self: *const ExpandedProgram, decl: DeclId) FileId {
        if (self.originOf(decl)) |origin| {
            if (origin.derive_trait != .none) return self.source.ast.fileOf(origin.derive_trait);
        }
        return self.source.ast.fileOfDecl(self.primaryDecl(decl));
    }

    pub fn primarySpanOfDecl(self: *const ExpandedProgram, decl: DeclId) Span {
        if (self.originOf(decl)) |origin| {
            if (origin.derive_trait != .none) return self.source.ast.tokenSpan(origin.derive_trait);
        }
        return self.source.ast.declSpan(self.primaryDecl(decl));
    }

    /// The narrowest origin recorded for a span of a generated file, and null
    /// where the file is written source. A span a template rendered once per
    /// component records that component, which is what lets a diagnostic name
    /// a generated binding by the part of the type it holds.
    pub fn generatedOriginAt(self: *const ExpandedProgram, file: FileId, span: Span) ?Origin {
        const whole = self.originOfGeneratedFile(file) orelse return null;
        const id = originAt(self.origin_segments, self.origin_segment_minima, file, span);
        return if (id == .none) whole else self.origin_rows[id.index()];
    }

    test "a generated span's origin is the narrowest one recorded for it" {
        const gpa = testing.allocator;
        var sink = Sink.init(gpa);
        var source_interner: Interner = .empty;
        defer source_interner.deinit(gpa);

        var source_parser = parser.Modules.init(gpa, &sink, &source_interner);
        defer source_parser.deinit();
        const files = [_]parser.ParsedFile{.{
            .file = .from(0),
            .source = Source{ .path = "root.lin", .text =
            \\template impl Structural {
            \\    fn value(self: Self) -> UInt8 { 0 }
            \\}
            \\derive Structural for Mark
            \\
            },
        }};
        const decls = try source_parser.add(&files);
        var modules = [_]Module{.{ .name = "root", .dir = "root", .files = &.{.from(0)}, .decls = decls, .imports = &.{} }};
        var source: Program = .{ .modules = &modules, .ast = try source_parser.finish() };
        defer source.ast.deinit(gpa);

        var template_expr = ExprId.none;
        for (0..source.ast.exprCount()) |i| {
            const expression = ExprId.at(@intCast(i));
            if (source.ast.exprTag(expression) == .int_literal) template_expr = expression;
        }
        try testing.expect(template_expr != .none);

        const text = "fn generated() -> UInt8 { let x: UInt8 = 2; x }\n";
        var generated_sources: GeneratedSources = .empty;
        defer generated_sources.deinit(gpa);
        generated_sources.paths = try dupeStrings(gpa, &.{"generated.lin"});
        generated_sources.buffers = try dupeStrings(gpa, &.{text});

        var expanded_interner = try Interner.initPrefix(gpa, &source_interner);
        defer expanded_interner.deinit(gpa);
        var generated_parser = try parser.Modules.initPrefix(gpa, &sink, &expanded_interner, &source.ast);
        defer generated_parser.deinit();
        _ = try generated_parser.add(&.{.{ .file = .from(1), .source = Source{ .path = generated_sources.path(0), .text = generated_sources.get(0) } }});
        var expanded_ast = try generated_parser.finish();

        const let_start: u32 = @intCast(std.mem.indexOf(u8, text, "let x").?);
        const let_end: u32 = @intCast(std.mem.indexOfScalarPos(u8, text, let_start, ';').? + 1);
        const whole: Origin = .{ .derive = .at(2), .template_member = .at(0), .template_expr = template_expr, .component_ordinal = @enumFromInt(1) };
        const narrow: Origin = .{ .derive = .at(2), .template_member = .at(0), .template_expr = template_expr, .component_ordinal = @enumFromInt(2) };
        const segments = [_]GeneratedOriginSegment{
            .{ .file = .from(1), .span = .{ .start = 0, .end = @intCast(text.len) }, .origin = whole },
            .{ .file = .from(1), .span = .{ .start = let_start, .end = let_end }, .origin = narrow },
        };
        var generated_implementations: []GeneratedImplementation = &.{};
        var component_requirements: []ComponentRequirement = &.{};
        var expanded = try ExpandedProgram.init(gpa, &source, &expanded_ast, &expanded_interner, &generated_sources, &.{}, &generated_implementations, &component_requirements, &.{
            .{ .module = .from(0), .origin = .{ .derive = .at(2), .template_member = .at(0) } },
        }, &.{}, &segments);
        defer expanded.deinit(gpa);
        try testing.expectEqual(@as(u32, 0), sink.error_count);

        const x_start: u32 = let_start + 4;
        try testing.expectEqualDeep(narrow, expanded.generatedOriginAt(.from(1), .{ .start = x_start, .end = x_start + 1 }).?);
        try testing.expectEqualDeep(whole, expanded.generatedOriginAt(.from(1), .{ .start = 0, .end = 2 }).?);
        try testing.expectEqual(@as(?Origin, null), expanded.generatedOriginAt(.from(0), .{ .start = 0, .end = 2 }));
    }

    test "collapseGeneratedDiagnostics gives each label its own origin's provenance" {
        const gpa = testing.allocator;
        var sink = Sink.init(gpa);
        var source_interner: Interner = .empty;
        defer source_interner.deinit(gpa);

        var source_parser = parser.Modules.init(gpa, &sink, &source_interner);
        defer source_parser.deinit();
        const files = [_]parser.ParsedFile{.{
            .file = .from(0),
            .source = Source{ .path = "root.lin", .text =
            \\struct Pair { first: UInt8, second: UInt8 }
            \\template impl Structural {
            \\    fn value(self: Self) -> UInt8 { 0 }
            \\}
            \\derive Structural for Pair
            \\
            },
        }};
        const decls = try source_parser.add(&files);
        var modules = [_]Module{.{ .name = "root", .dir = "root", .files = &.{.from(0)}, .decls = decls, .imports = &.{} }};
        var source: Program = .{ .modules = &modules, .ast = try source_parser.finish() };
        defer source.ast.deinit(gpa);

        var pair_decl = DeclId.none;
        var derive_decl = DeclId.none;
        var template_member = DeclId.none;
        for (0..source.ast.declCount()) |i| {
            const id = DeclId.at(@intCast(i));
            switch (source.ast.declTag(id)) {
                .struct_ => pair_decl = id,
                .derive_impl => derive_decl = id,
                .function => template_member = id,
                else => {},
            }
        }
        try testing.expect(pair_decl != .none);
        try testing.expect(derive_decl != .none);
        try testing.expect(template_member != .none);

        var template_expr = ExprId.none;
        for (0..source.ast.exprCount()) |i| {
            const expression = ExprId.at(@intCast(i));
            if (source.ast.exprTag(expression) == .int_literal) template_expr = expression;
        }
        try testing.expect(template_expr != .none);

        const text = "fn generated() -> UInt8 { let x: UInt8 = 2; x }\n";
        var generated_sources: GeneratedSources = .empty;
        defer generated_sources.deinit(gpa);
        generated_sources.paths = try dupeStrings(gpa, &.{"generated.lin"});
        generated_sources.buffers = try dupeStrings(gpa, &.{text});

        var expanded_interner = try Interner.initPrefix(gpa, &source_interner);
        defer expanded_interner.deinit(gpa);
        var generated_parser = try parser.Modules.initPrefix(gpa, &sink, &expanded_interner, &source.ast);
        defer generated_parser.deinit();
        _ = try generated_parser.add(&.{.{ .file = .from(1), .source = Source{ .path = generated_sources.path(0), .text = generated_sources.get(0) } }});
        var expanded_ast = try generated_parser.finish();

        // Two segments of the one generated file, one per field, so a label
        // in the first half names `Pair.first` and one in the second half
        // names `Pair.second`.
        const half: u32 = @intCast(text.len / 2);
        const first_origin: Origin = .{ .derive = derive_decl, .target = pair_decl, .template_member = template_member, .template_expr = template_expr, .component_ordinal = @enumFromInt(0) };
        const second_origin: Origin = .{ .derive = derive_decl, .target = pair_decl, .template_member = template_member, .template_expr = template_expr, .component_ordinal = @enumFromInt(1) };
        const segments = [_]GeneratedOriginSegment{
            .{ .file = .from(1), .span = .{ .start = 0, .end = half }, .origin = first_origin },
            .{ .file = .from(1), .span = .{ .start = half, .end = @intCast(text.len) }, .origin = second_origin },
        };
        var generated_implementations: []GeneratedImplementation = &.{};
        var component_requirements: []ComponentRequirement = &.{};
        var expanded = try ExpandedProgram.init(gpa, &source, &expanded_ast, &expanded_interner, &generated_sources, &.{}, &generated_implementations, &component_requirements, &.{
            .{ .module = .from(0), .origin = .{ .derive = derive_decl, .target = pair_decl, .template_member = template_member } },
        }, &.{}, &segments);
        defer expanded.deinit(gpa);
        try testing.expectEqual(@as(u32, 0), sink.error_count);

        var diagnostic_arena = std.heap.ArenaAllocator.init(gpa);
        defer diagnostic_arena.deinit();
        var diagnostics = Sink.init(diagnostic_arena.allocator());

        // One diagnostic whose two labels name different fields: each must
        // keep its own template and field annotation, naming its own field.
        try diagnostics.add(.{
            .severity = .err,
            .code = .t_derive,
            .message = "generated error",
            .labels = try diagnostics.arena.dupe(Label, &.{
                .{ .file = .from(1), .span = .{ .start = 0, .end = 1 }, .message = "primary", .style = .primary },
                .{ .file = .from(1), .span = .{ .start = half, .end = half + 1 }, .message = "secondary", .style = .secondary },
            }),
        });
        // A second diagnostic whose two labels both fall in the first half:
        // they share one origin, so its provenance is added once, not twice.
        try diagnostics.add(.{
            .severity = .err,
            .code = .t_derive,
            .message = "another generated error",
            .labels = try diagnostics.arena.dupe(Label, &.{
                .{ .file = .from(1), .span = .{ .start = 0, .end = 1 }, .message = "primary", .style = .primary },
                .{ .file = .from(1), .span = .{ .start = 1, .end = 2 }, .message = "secondary", .style = .secondary },
            }),
        });
        try expanded.collapseGeneratedDiagnostics(&diagnostics);

        try testing.expectEqual(@as(usize, 2), diagnostics.items().len);

        const differing = diagnostics.items()[0];
        try testing.expectEqual(@as(usize, 6), differing.labels.len);
        var saw_first = false;
        var saw_second = false;
        for (differing.labels) |label| {
            if (std.mem.indexOf(u8, label.message, "Pair.first") != null) saw_first = true;
            if (std.mem.indexOf(u8, label.message, "Pair.second") != null) saw_second = true;
        }
        try testing.expect(saw_first);
        try testing.expect(saw_second);

        const shared = diagnostics.items()[1];
        try testing.expectEqual(@as(usize, 4), shared.labels.len);
    }

    fn originOfGeneratedFile(self: *const ExpandedProgram, file: FileId) ?Origin {
        if (file.index() >= self.file_origins.len()) return null;
        return self.file_origins.get(file);
    }

    /// Describes the source component a generated origin was rendered for: the
    /// target type, the variant for an enum, and the field's position and token.
    const ComponentField = struct {
        target: DeclId,
        variant: TokenId = .none,
        ordinal: usize,
        /// Points at the field's name where it has one, and otherwise at its
        /// written type.
        at: TokenId,
        named: bool,
    };

    fn componentField(self: *const ExpandedProgram, origin: Origin) ?ComponentField {
        const component: usize = @intFromEnum(origin.component_ordinal orelse return null);
        const target = origin.target;
        if (target == .none) return null;
        const ast = &self.source.ast;
        switch (ast.declTag(target)) {
            .struct_ => {
                const fields = ast.declFields(target);
                if (component >= fields.len) return null;
                return .{ .target = target, .ordinal = component, .at = fields[component].name, .named = true };
            },
            .enum_ => {
                const case: usize = @intFromEnum(origin.case_ordinal orelse return null);
                const variants = ast.declVariants(target);
                if (case >= variants.len) return null;
                const fields = ast.variantFields(variants[case]);
                if (component >= fields.len) return null;
                const named = fields[component].name != .none;
                return .{
                    .target = target,
                    .variant = variants[case].name,
                    .ordinal = component,
                    .at = if (named) fields[component].name else fields[component].written.at,
                    .named = named,
                };
            },
            .newtype => return .{ .target = target, .ordinal = 0, .at = ast.declReturnRef(target).at, .named = false },
            else => return null,
        }
    }

    /// Returns the enum variant a generated origin's case was rendered for,
    /// where the target is an enum.
    fn caseVariant(self: *const ExpandedProgram, origin: Origin) ?TokenId {
        const case: usize = @intFromEnum(origin.case_ordinal orelse return null);
        if (origin.target == .none or self.source.ast.declTag(origin.target) != .enum_) return null;
        const variants = self.source.ast.declVariants(origin.target);
        return if (case < variants.len) variants[case].name else null;
    }

    /// Spells a component as a message names it: `Pair.first` for a struct field,
    /// `Shape.Circle.radius` or `Reading.Taken.0` for a variant payload, and
    /// `Meters.0` for a newtype's base.
    fn spellComponent(self: *const ExpandedProgram, arena: std.mem.Allocator, field: ComponentField) std.mem.Allocator.Error![]const u8 {
        const ast = &self.source.ast;
        const type_name = ast.tokenText(ast.declName(field.target));
        if (field.variant == .none) {
            if (field.named) return std.fmt.allocPrint(arena, "{s}.{s}", .{ type_name, ast.tokenText(field.at) });
            return std.fmt.allocPrint(arena, "{s}.{d}", .{ type_name, field.ordinal });
        }
        const variant = ast.tokenText(field.variant);
        if (field.named) return std.fmt.allocPrint(arena, "{s}.{s}.{s}", .{ type_name, variant, ast.tokenText(field.at) });
        return std.fmt.allocPrint(arena, "{s}.{s}.{d}", .{ type_name, variant, field.ordinal });
    }

    /// Names the source field that a binding generated for one component
    /// holds, as a diagnostic spells it. It returns null for a span no
    /// generated component binding covers, which a diagnostic names as written.
    pub fn generatedComponentName(self: *const ExpandedProgram, arena: std.mem.Allocator, file: FileId, span: Span) std.mem.Allocator.Error!?[]const u8 {
        const origin = self.generatedOriginAt(file, span) orelse return null;
        const field = self.componentField(origin) orelse return null;
        return try self.spellComponent(arena, field);
    }

    /// How a report names the binding declared at `tok`: its name in
    /// backticks, or for one a derive generated, the component it was
    /// generated for, since the generated name means nothing to a reader.
    pub fn subjectAt(self: *const ExpandedProgram, arena: std.mem.Allocator, tok: TokenId) std.mem.Allocator.Error![]const u8 {
        const file = self.ast.fileOf(tok);
        const span = self.ast.tokenSpan(tok);
        if (self.generatedOriginAt(file, span) != null) {
            if (try self.generatedComponentName(arena, file, span)) |part| {
                return std.fmt.allocPrint(arena, "`{s}`", .{part});
            }
            return "a value the derive generated";
        }
        return std.fmt.allocPrint(arena, "`{s}`", .{self.ast.tokenText(tok)});
    }

    /// Appends the provenance labels for one generated origin -- the template
    /// expression that rendered it, and, where the origin names one, the
    /// source field or component it stands for -- unless `extra` already
    /// holds one that would say the same thing. Two labels in one diagnostic
    /// attributed to origins that name the same source add that provenance
    /// once; two naming different source each keep their own, so a report
    /// naming `Pair.first` is never captioned with `Pair.second`.
    ///
    /// A template label's message already names the field or case it was
    /// rendered for, so two such labels are the same provenance exactly when
    /// they read the same, regardless of which expression in the template
    /// produced each -- a template can render more than one expression for
    /// one component. A field label's message never names the field, so its
    /// span is what identifies it there instead.
    fn appendProvenance(self: *const ExpandedProgram, arena: std.mem.Allocator, extra: *std.ArrayList(Label), origin: Origin) std.mem.Allocator.Error!void {
        const field: ?ComponentField = self.componentField(origin);
        if (origin.template_expr != .none) {
            const message = if (field) |component|
                try std.fmt.allocPrint(arena, "generated from this template code for `{s}`", .{try self.spellComponent(arena, component)})
            else if (self.caseVariant(origin)) |variant|
                try std.fmt.allocPrint(arena, "generated from this template code for `{s}.{s}`", .{ self.source.ast.tokenText(self.source.ast.declName(origin.target)), self.source.ast.tokenText(variant) })
            else
                "generated from this template code";
            var repeated = false;
            for (extra.items) |existing| {
                if (existing.style == .secondary and std.mem.eql(u8, existing.message, message)) {
                    repeated = true;
                    break;
                }
            }
            if (!repeated) {
                try extra.append(arena, .{
                    .file = self.source.ast.fileOfExpr(origin.template_expr),
                    .span = self.source.ast.exprSpan(origin.template_expr),
                    .message = message,
                    .style = .secondary,
                });
            }
        }
        if (field) |component| {
            const file = self.source.ast.fileOf(component.at);
            const span = self.source.ast.tokenSpan(component.at);
            var repeated = false;
            for (extra.items) |existing| {
                if (existing.file == file and existing.span.start == span.start and existing.span.end == span.end) {
                    repeated = true;
                    break;
                }
            }
            if (!repeated) {
                try extra.append(arena, .{
                    .file = file,
                    .span = span,
                    .message = if (component.named) "the code was generated for this field" else "the code was generated for this component",
                    .style = .secondary,
                });
            }
        }
    }

    /// Attributes diagnostics from generated files to the derive the source
    /// wrote, and to the source field where the generated code was rendered for
    /// one. A label already mapped to source has no generated origin, so
    /// repeated calls leave it unchanged. Two generated diagnostics that say
    /// the same thing about the same source are reported once.
    ///
    /// **Bound:** the sink's diagnostics, each compared by one hashed key.
    pub fn collapseGeneratedDiagnostics(self: *const ExpandedProgram, sink: *Sink) std.mem.Allocator.Error!void {
        var seen: std.StringHashMapUnmanaged(void) = .empty;
        var kept: std.ArrayList(Diagnostic) = .empty;
        for (sink.items()) |item| {
            var diagnostic = item;
            var generated = false;

            // Each label that came from generated code earns its own
            // provenance, rather than sharing whichever origin looked most
            // specific across the whole diagnostic -- which could caption one
            // label with another's field -- deduplicated by what each
            // provenance label would say, not by which label asked for it.
            var extra: std.ArrayList(Label) = .empty;
            for (diagnostic.labels) |label| {
                if (self.originOfGeneratedFile(label.file) == null) continue;
                generated = true;
                const id = originAt(self.origin_segments, self.origin_segment_minima, label.file, label.span);
                if (id == .none) continue;
                try self.appendProvenance(sink.arena, &extra, self.origin_rows[id.index()]);
            }
            // A template expression captioned for a component already says
            // it was generated from there, so the uncaptioned label for the
            // same expression is dropped.
            var provenance: usize = 0;
            for (extra.items) |label| {
                const plain = std.mem.eql(u8, label.message, "generated from this template code") and for (extra.items) |other| {
                    if (other.file == label.file and other.span.start == label.span.start and other.span.end == label.span.end and !std.mem.eql(u8, other.message, label.message)) break true;
                } else false;
                if (plain) continue;
                extra.items[provenance] = label;
                provenance += 1;
            }
            extra.items.len = provenance;
            if (!generated) {
                try kept.append(sink.arena, diagnostic);
                continue;
            }

            const labels = try sink.arena.alloc(Label, diagnostic.labels.len + extra.items.len);
            @memcpy(labels[0..diagnostic.labels.len], diagnostic.labels);
            for (labels[0..diagnostic.labels.len]) |*label| {
                const origin = self.originOfGeneratedFile(label.file) orelse continue;
                if (origin.derive_trait != .none) {
                    label.file = self.source.ast.fileOf(origin.derive_trait);
                    label.span = self.source.ast.tokenSpan(origin.derive_trait);
                } else {
                    label.file = self.source.ast.fileOfDecl(origin.derive);
                    label.span = self.source.ast.declSpan(origin.derive);
                }
            }
            @memcpy(labels[diagnostic.labels.len..], extra.items);
            diagnostic.labels = labels;

            var key: std.ArrayList(u8) = .empty;
            try key.print(sink.arena, "{d}|{d}|{s}", .{ @intFromEnum(diagnostic.severity), if (diagnostic.code) |code| @as(i64, @intFromEnum(code)) else -1, diagnostic.message });
            for (diagnostic.labels) |label| try key.print(sink.arena, "|{d}:{d}:{d}:{d}:{s}", .{ @intFromEnum(label.file), label.span.start, label.span.end, @intFromEnum(label.style), label.message });
            for (diagnostic.notes) |note| try key.print(sink.arena, "|{s}", .{note});
            if ((try seen.getOrPut(sink.arena, key.items)).found_existing) continue;
            try kept.append(sink.arena, diagnostic);
        }
        try sink.replaceAll(kept.items);
    }

    test "collapseGeneratedDiagnostics keeps the captioned template label of one expression" {
        const gpa = testing.allocator;
        var sink = Sink.init(gpa);
        var source_interner: Interner = .empty;
        defer source_interner.deinit(gpa);

        var source_parser = parser.Modules.init(gpa, &sink, &source_interner);
        defer source_parser.deinit();
        const files = [_]parser.ParsedFile{.{
            .file = .from(0),
            .source = Source{ .path = "root.lin", .text =
            \\struct Pair { first: UInt8, second: UInt8 }
            \\template impl Structural {
            \\    fn value(self: Self) -> UInt8 { 0 }
            \\}
            \\derive Structural for Pair
            \\
            },
        }};
        const decls = try source_parser.add(&files);
        var modules = [_]Module{.{ .name = "root", .dir = "root", .files = &.{.from(0)}, .decls = decls, .imports = &.{} }};
        var source: Program = .{ .modules = &modules, .ast = try source_parser.finish() };
        defer source.ast.deinit(gpa);

        var pair_decl = DeclId.none;
        var derive_decl = DeclId.none;
        var template_member = DeclId.none;
        for (0..source.ast.declCount()) |i| {
            const id = DeclId.at(@intCast(i));
            switch (source.ast.declTag(id)) {
                .struct_ => pair_decl = id,
                .derive_impl => derive_decl = id,
                .function => template_member = id,
                else => {},
            }
        }
        try testing.expect(pair_decl != .none);
        try testing.expect(derive_decl != .none);
        try testing.expect(template_member != .none);

        var template_expr = ExprId.none;
        for (0..source.ast.exprCount()) |i| {
            const expression = ExprId.at(@intCast(i));
            if (source.ast.exprTag(expression) == .int_literal) template_expr = expression;
        }
        try testing.expect(template_expr != .none);

        const text = "fn generated() -> UInt8 { let x: UInt8 = 2; x }\n";
        var generated_sources: GeneratedSources = .empty;
        defer generated_sources.deinit(gpa);
        generated_sources.paths = try dupeStrings(gpa, &.{"generated.lin"});
        generated_sources.buffers = try dupeStrings(gpa, &.{text});

        var expanded_interner = try Interner.initPrefix(gpa, &source_interner);
        defer expanded_interner.deinit(gpa);
        var generated_parser = try parser.Modules.initPrefix(gpa, &sink, &expanded_interner, &source.ast);
        defer generated_parser.deinit();
        _ = try generated_parser.add(&.{.{ .file = .from(1), .source = Source{ .path = generated_sources.path(0), .text = generated_sources.get(0) } }});
        var expanded_ast = try generated_parser.finish();

        // Two segments of one template expression: the first rendered for
        // `Pair.first`, the second for no component. A diagnostic with a
        // label in each captions that expression once, for `Pair.first`.
        const half: u32 = @intCast(text.len / 2);
        const captioned: Origin = .{ .derive = derive_decl, .target = pair_decl, .template_member = template_member, .template_expr = template_expr, .component_ordinal = @enumFromInt(0) };
        const plain: Origin = .{ .derive = derive_decl, .target = pair_decl, .template_member = template_member, .template_expr = template_expr };
        const segments = [_]GeneratedOriginSegment{
            .{ .file = .from(1), .span = .{ .start = 0, .end = half }, .origin = captioned },
            .{ .file = .from(1), .span = .{ .start = half, .end = @intCast(text.len) }, .origin = plain },
        };
        var generated_implementations: []GeneratedImplementation = &.{};
        var component_requirements: []ComponentRequirement = &.{};
        var expanded = try ExpandedProgram.init(gpa, &source, &expanded_ast, &expanded_interner, &generated_sources, &.{}, &generated_implementations, &component_requirements, &.{
            .{ .module = .from(0), .origin = .{ .derive = derive_decl, .target = pair_decl, .template_member = template_member } },
        }, &.{}, &segments);
        defer expanded.deinit(gpa);
        try testing.expectEqual(@as(u32, 0), sink.error_count);

        var diagnostic_arena = std.heap.ArenaAllocator.init(gpa);
        defer diagnostic_arena.deinit();
        var diagnostics = Sink.init(diagnostic_arena.allocator());
        try diagnostics.add(.{
            .severity = .err,
            .code = .t_derive,
            .message = "generated error",
            .labels = try diagnostics.arena.dupe(Label, &.{
                .{ .file = .from(1), .span = .{ .start = half, .end = half + 1 }, .message = "primary", .style = .primary },
                .{ .file = .from(1), .span = .{ .start = 0, .end = 1 }, .message = "secondary", .style = .secondary },
            }),
        });
        try expanded.collapseGeneratedDiagnostics(&diagnostics);

        var captions: usize = 0;
        for (diagnostics.items()[0].labels) |label| {
            if (!std.mem.startsWith(u8, label.message, "generated from this template code")) continue;
            try testing.expectEqualStrings("generated from this template code for `Pair.first`", label.message);
            captions += 1;
        }
        try testing.expectEqual(@as(usize, 1), captions);
    }

    pub fn deinit(self: *ExpandedProgram, gpa: std.mem.Allocator) void {
        if (!self.borrowed_source) self.ast.deinit(gpa);
        self.decl_modules.deinit(gpa);
        self.import_targets.deinit(gpa);
        self.active.deinit(gpa);
        self.module_decl_ranges.deinit(gpa);
        gpa.free(self.module_decls);
        self.origins.deinit(gpa);
        self.file_origins.deinit(gpa);
        if (!self.borrowed_source) {
            gpa.free(self.origin_rows);
            gpa.free(self.origin_segments);
            gpa.free(self.origin_segment_minima);
            gpa.free(self.template_members);
            gpa.free(self.generated_implementations);
            gpa.free(self.component_requirements);
            self.interner.deinit(gpa);
            self.generated_sources.deinit(gpa);
        }
        self.* = undefined;
    }
};

// Makes every test build compile the tests `ExpandedProgram` holds, including
// a build filtered to one of them, which would otherwise never look inside it.
comptime {
    _ = ExpandedProgram;
}

fn dupeStrings(gpa: std.mem.Allocator, strings: []const []const u8) ![]const []const u8 {
    const out = try gpa.alloc([]const u8, strings.len);
    errdefer gpa.free(out);
    var initialized: usize = 0;
    errdefer for (out[0..initialized]) |string| gpa.free(string);
    for (strings, out) |string, *owned| {
        owned.* = try gpa.dupe(u8, string);
        initialized += 1;
    }
    return out;
}

test "expanded module roots" {
    const gpa = testing.allocator;
    var sink = Sink.init(gpa);
    var source_interner: Interner = .empty;
    defer source_interner.deinit(gpa);

    var source_parser = parser.Modules.init(gpa, &sink, &source_interner);
    defer source_parser.deinit();
    const root_files = [_]parser.ParsedFile{.{
        .file = .from(0),
        .source = Source{ .path = "root.lin", .text =
        \\fn first() -> UInt8 { 0 }
        \\fn second() -> UInt8 { 1 }
        \\
        },
    }};
    const child_files = [_]parser.ParsedFile{.{
        .file = .from(1),
        .source = Source{ .path = "child.lin", .text =
        \\template impl Structural {
        \\    fn value(self: Self) -> UInt8 { 0 }
        \\}
        \\derive Structural for Mark
        \\
        },
    }};
    const root_decls = try source_parser.add(&root_files);
    const child_decls = try source_parser.add(&child_files);
    const source_ast = try source_parser.finish();

    var source_modules = [_]Module{
        .{
            .name = "root",
            .dir = "root",
            .files = &.{.from(0)},
            .decls = root_decls,
            .imports = &.{},
        },
        .{
            .name = "child",
            .dir = "root/child",
            .files = &.{.from(1)},
            .decls = child_decls,
            .imports = &.{},
        },
    };
    var source: Program = .{ .modules = &source_modules, .ast = source_ast };
    defer source.ast.deinit(gpa);

    const derive_trait_range = source.ast.deriveTraitRange(.at(4));
    const derive_trait = node.DeriveTraitId.at(derive_trait_range.start);
    const derive_trait_token = source.ast.deriveTrait(derive_trait).ref.name;
    try testing.expect(validSourceOrigin(
        &source.ast,
        .{ .derive = .at(4), .derive_trait = derive_trait_token },
        derive_trait,
    ));
    try testing.expect(!validSourceOrigin(
        &source.ast,
        .{ .derive = .at(4), .derive_trait = derive_trait_token },
        .none,
    ));

    const source_name_count = source_interner.count();
    var expanded_interner = try Interner.initPrefix(gpa, &source_interner);
    defer expanded_interner.deinit(gpa);
    const generated_texts = [_][]const u8{
        "fn rootGeneratedA() -> UInt8 { let x: UInt8 = 2; x }\n",
        "fn childGeneratedA() -> UInt8 { 3 }\n",
        "fn rootGeneratedB() -> UInt8 { 4 }\n",
        "fn childGeneratedB() -> UInt8 { 5 }\n",
    };
    const generated_paths = [_][]const u8{
        "root-generated-a.lin",
        "child-generated-a.lin",
        "root-generated-b.lin",
        "child-generated-b.lin",
    };
    var generated_sources: GeneratedSources = .empty;
    defer generated_sources.deinit(gpa);
    generated_sources.paths = try dupeStrings(gpa, &generated_paths);
    generated_sources.buffers = try dupeStrings(gpa, &generated_texts);
    const owned_paths = generated_sources.paths;
    const owned_texts = generated_sources.buffers;

    var generated_parser = try parser.Modules.initPrefix(gpa, &sink, &expanded_interner, &source.ast);
    defer generated_parser.deinit();
    for (generated_paths, 0..) |_, i| {
        const files = [_]parser.ParsedFile{.{
            .file = .from(i + 2),
            .source = Source{ .path = generated_sources.path(i), .text = generated_sources.get(i) },
        }};
        _ = try generated_parser.add(&files);
    }
    var expanded_ast = try generated_parser.finish();

    var template_expr = ExprId.none;
    for (0..source.ast.exprCount()) |i| {
        const expression = ExprId.at(@intCast(i));
        if (source.ast.fileOfExpr(expression) == FileId.from(1) and source.ast.exprTag(expression) == .int_literal) {
            template_expr = expression;
        }
    }
    try testing.expect(template_expr != .none);
    const segment_start: u32 = @intCast(std.mem.indexOf(u8, generated_texts[0], "let x") orelse return error.TestUnexpectedResult);
    const segment_end: u32 = @intCast((std.mem.indexOfScalarPos(u8, generated_texts[0], segment_start, ';') orelse return error.TestUnexpectedResult) + 1);
    const literal_start: u32 = @intCast(std.mem.indexOfScalarPos(u8, generated_texts[0], segment_start, '2') orelse return error.TestUnexpectedResult);
    const fine_segments = [_]GeneratedOriginSegment{
        .{
            .file = .from(2),
            .span = .{ .start = 0, .end = @intCast(generated_texts[0].len) },
            .origin = .{
                .derive = .at(4),
                .template_member = .at(2),
                .template_expr = template_expr,
                .component_ordinal = @enumFromInt(1),
            },
        },
        .{
            .file = .from(2),
            .span = .{ .start = segment_start, .end = segment_end },
            .origin = .{
                .derive = .at(4),
                .template_member = .at(2),
                .template_expr = template_expr,
                .component_ordinal = @enumFromInt(2),
            },
        },
        .{
            .file = .from(2),
            .span = .{ .start = literal_start, .end = literal_start + 1 },
            .origin = .{
                .derive = .at(4),
                .template_member = .at(2),
                .template_expr = template_expr,
                .component_ordinal = @enumFromInt(3),
            },
        },
    };

    {
        const sparse_parts = try gpa.dupe(@import("ast.zig").FilePart, expanded_ast.parts);
        defer gpa.free(sparse_parts);
        for (sparse_parts[2..], [_]usize{ 900, 37, 8000, 12 }) |*part, file| part.file = .from(file);
        var sparse_ast = expanded_ast;
        sparse_ast.parts = sparse_parts;
        var sparse_segments = fine_segments;
        for (&sparse_segments) |*segment| segment.file = .from(900);
        var sparse_origins = try FineOrigins.init(gpa, &source, &sparse_ast, &sparse_segments);
        defer sparse_origins.deinit(gpa);
        try testing.expectEqualDeep(fine_segments[2].origin, sparse_origins.rows[2]);
        try testing.expectEqual(OriginId.at(2), originAt(sparse_origins.segments, sparse_origins.segment_minima, .from(900), .{
            .start = literal_start,
            .end = literal_start + 1,
        }));

        var invalid_segment = sparse_segments[0];
        invalid_segment.file = .from(0);
        invalid_segment.span = .{ .start = 0, .end = 1 };
        try testing.expectError(error.InvalidGeneratedOrigin, FineOrigins.init(gpa, &source, &sparse_ast, &.{invalid_segment}));
        invalid_segment.file = .from(901);
        try testing.expectError(error.InvalidGeneratedOrigin, FineOrigins.init(gpa, &source, &sparse_ast, &.{invalid_segment}));
        invalid_segment = sparse_segments[0];
        invalid_segment.span.end += 1;
        try testing.expectError(error.InvalidGeneratedOrigin, FineOrigins.init(gpa, &source, &sparse_ast, &.{invalid_segment}));
    }

    var generated_implementations: []GeneratedImplementation = &.{};
    var component_requirements: []ComponentRequirement = &.{};
    var expanded = try ExpandedProgram.init(gpa, &source, &expanded_ast, &expanded_interner, &generated_sources, &.{}, &generated_implementations, &component_requirements, &.{
        .{ .module = .from(0), .origin = .{ .derive = .at(4), .template_member = .at(2) } },
        .{ .module = .from(1), .origin = .{ .derive = .at(4) } },
        .{ .module = .from(0), .origin = .{ .derive = .at(4), .template_member = .at(2) } },
        .{ .module = .from(1), .origin = .{ .derive = .at(4) } },
    }, &.{}, &fine_segments);
    defer expanded.deinit(gpa);
    generated_sources.deinit(gpa);

    try testing.expectEqual(@as(u32, 0), sink.error_count);
    // A program assembled without the loader records no routes, so its
    // modules are known by their names and its root by nothing.
    try testing.expectEqualStrings("", expanded.modulePath(.from(0)));
    try testing.expectEqualStrings("child", expanded.modulePath(.from(1)));
    try testing.expectEqual(ModuleId.from(0), expanded.moduleOf(.at(0)));
    try testing.expectEqual(ModuleId.from(1), expanded.moduleOf(.at(2)));
    try testing.expectEqual(ModuleId.from(1), expanded.moduleOf(.at(3)));
    try testing.expect(!expanded.isActive(.at(2)));
    try testing.expect(!expanded.isActive(.at(3)));
    try testing.expect(!expanded.isActive(.at(4)));
    try testing.expectEqual(ModuleId.from(0), expanded.moduleOf(.at(5)));
    try testing.expectEqual(ModuleId.from(1), expanded.moduleOf(.at(6)));
    try testing.expectEqual(ModuleId.from(0), expanded.moduleOf(.at(7)));
    try testing.expectEqual(ModuleId.from(1), expanded.moduleOf(.at(8)));
    try testing.expectEqualSlices(DeclId, &.{ .at(0), .at(1), .at(5), .at(7) }, expanded.declsOf(.from(0)));
    try testing.expectEqualSlices(DeclId, &.{ .at(6), .at(8) }, expanded.declsOf(.from(1)));
    try testing.expect(expanded.isActive(.at(5)));
    try testing.expectEqual(Origin{ .derive = .at(4), .template_member = .at(2) }, expanded.originOf(.at(5)).?);
    try testing.expectEqual(Origin{ .derive = .at(4) }, expanded.originOf(.at(6)).?);
    try testing.expectEqual(Origin{ .derive = .at(4), .template_member = .at(2) }, expanded.originOf(.at(7)).?);
    try testing.expectEqual(Origin{ .derive = .at(4) }, expanded.originOf(.at(8)).?);
    try testing.expectEqual(@as(?Origin, null), expanded.originOf(.at(0)));

    var diagnostic_arena = std.heap.ArenaAllocator.init(gpa);
    defer diagnostic_arena.deinit();
    var diagnostics = Sink.init(diagnostic_arena.allocator());
    for ([_]u32{ 0, segment_start, literal_start }) |start| {
        try diagnostics.addError(.t_derive, .from(2), .{ .start = start, .end = start + 1 }, "generated error", "generated location");
    }
    try expanded.collapseGeneratedDiagnostics(&diagnostics);
    // Collapsing again must neither remap source labels nor add another note.
    try expanded.collapseGeneratedDiagnostics(&diagnostics);
    // These origins name no target, so the three errors say the same thing
    // about the same source and are reported once.
    try testing.expectEqual(@as(usize, 1), diagnostics.items().len);
    try testing.expectEqual(@as(u32, 1), diagnostics.error_count);
    for (diagnostics.items()) |diagnostic| {
        try testing.expectEqual(@as(usize, 2), diagnostic.labels.len);
        const primary = diagnostic.labels[0];
        try testing.expectEqual(source.ast.fileOfDecl(.at(4)), primary.file);
        try testing.expectEqual(source.ast.declSpan(.at(4)), primary.span);
        const secondary = diagnostic.labels[1];
        try testing.expectEqual(source.ast.fileOfExpr(template_expr), secondary.file);
        try testing.expectEqual(source.ast.exprSpan(template_expr), secondary.span);
        try testing.expectEqualStrings("generated from this template code", secondary.message);
    }

    try testing.expectEqual(@as(usize, 9), expanded.decl_modules.len());
    try testing.expectEqual(@as(usize, 9), expanded.active.len());
    try testing.expectEqual(@as(usize, 2), expanded.module_decl_ranges.len());
    try testing.expectEqual(@as(usize, 6), expanded.module_decls.len);
    try testing.expectEqual(@as(usize, 9), expanded.origins.len());
    try testing.expectEqual(@as(usize, 0), expanded.template_members.len);
    try testing.expectEqual(source_name_count + 5, expanded.interner.count());
    for (0..source_name_count) |i| {
        const id = StringId.at(@intCast(i));
        try testing.expectEqualStrings(source_interner.textOf(id).?, expanded.interner.textOf(id).?);
        try testing.expect(source_interner.textOf(id).?.ptr == expanded.interner.textOf(id).?.ptr);
    }
    for (generated_texts, 0..) |text, i| {
        try testing.expectEqualStrings(text, expanded.ast.parts[i + 2].source);
        try testing.expect(expanded.generated_sources.get(i).ptr == owned_texts[i].ptr);
        try testing.expect(expanded.generated_sources.path(i).ptr == owned_paths[i].ptr);
        try testing.expect(expanded.ast.parts[i + 2].source.ptr == expanded.generated_sources.get(i).ptr);
        try testing.expect(expanded.ast.parts[i + 2].path.ptr == expanded.generated_sources.path(i).ptr);
    }
    var joined_interner = try Interner.initPrefix(gpa, &expanded.interner);
    defer joined_interner.deinit(gpa);
    var joined_parser = try parser.Modules.initPrefix(gpa, &sink, &joined_interner, &source.ast);
    defer joined_parser.deinit();
    const app_decls = try joined_parser.add(&.{.{ .file = .from(2), .source = .{ .path = "app.lin", .text = "fn app() -> UInt8 { 9 }" } }});
    var application_ast = try joined_parser.finish();
    defer application_ast.deinit(gpa);
    var application_modules = [_]Module{ source_modules[0], source_modules[1], .{
        .name = "app",
        .dir = "app",
        .files = &.{.from(2)},
        .decls = app_decls,
        .imports = &.{},
    } };
    var application: Program = .{ .modules = &application_modules, .ast = application_ast, .primary = .from(2) };
    var append_parser = try parser.Modules.initPrefix(gpa, &sink, &joined_interner, &application.ast);
    defer append_parser.deinit();
    const relocation = try append_parser.appendGenerated(&source.ast, &expanded.ast);
    var joined_ast = try append_parser.finish();
    var attached = try ExpandedProgram.attachLibraryPrefix(gpa, &application, &joined_ast, &joined_interner, &expanded, relocation);
    defer attached.deinit(gpa);
    try testing.expectEqual(ModuleId.from(2), attached.moduleOf(.at(5)));
    try testing.expectEqual(ModuleId.from(0), attached.moduleOf(.at(6)));
    try testing.expectEqualDeep(expanded.originOf(.at(5)), attached.originOf(.at(6)));
    try testing.expectEqualSlices(DeclId, &.{ .at(0), .at(1), .at(6), .at(8) }, attached.declsOf(.from(0)));
    try testing.expect(!attached.isActive(.at(2)));
    try testing.expectEqualStrings(generated_texts[0], attached.ast.parts[3].source);
    try testing.expect(attached.ast.parts[3].source.ptr == attached.generated_sources.get(0).ptr);
    try testing.expect(attached.generated_sources.get(0).ptr != expanded.generated_sources.get(0).ptr);
    var attached_sink = Sink.init(diagnostic_arena.allocator());
    try attached_sink.addError(.t_derive, .from(3), .{ .start = literal_start, .end = literal_start + 1 }, "generated error", "generated location");
    try attached.collapseGeneratedDiagnostics(&attached_sink);
    try testing.expectEqualDeep(diagnostics.items()[0].labels, attached_sink.items()[0].labels);

    const generated_name = expanded.ast.declName(.at(5));
    const generated_name_text = expanded.ast.tokenText(generated_name);
    try testing.expectEqualStrings("rootGeneratedA", generated_name_text);
    try testing.expect(generated_name_text.ptr != expanded.interner.textOf(expanded.ast.tokenName(generated_name)).?.ptr);
}

test "expanded module roots reject invalid generated metadata" {
    const valid = GeneratedDecl{ .module = .from(0), .origin = .{ .derive = .at(4) } };
    try testing.expectError(
        error.InvalidGeneratedDeclarationCount,
        ExpandedProgram.validateGenerated(5, 10, 7, 2, &.{valid}),
    );
    try testing.expectError(
        error.InvalidGeneratedModule,
        ExpandedProgram.validateGenerated(5, 10, 6, 2, &.{.{ .module = .from(2), .origin = .{ .derive = .at(4) } }}),
    );
    try testing.expectError(
        error.InvalidGeneratedOrigin,
        ExpandedProgram.validateGenerated(5, 10, 6, 2, &.{.{ .module = .from(0), .origin = .{ .derive = .at(5) } }}),
    );
    try testing.expectError(
        error.InvalidGeneratedOrigin,
        ExpandedProgram.validateGenerated(5, 10, 6, 2, &.{.{
            .module = .from(0),
            .origin = .{ .derive = .at(4), .template_member = .at(5) },
        }}),
    );
    try testing.expectError(
        error.InvalidGeneratedOrigin,
        ExpandedProgram.validateGenerated(5, 10, 6, 2, &.{.{
            .module = .from(0),
            .origin = .{ .derive = .at(4), .derive_trait = .at(10) },
        }}),
    );
    try ExpandedProgram.validateGenerated(5, 10, 6, 2, &.{valid});
    try testing.expectError(
        error.InvalidTemplatePlan,
        ExpandedProgram.validateTemplateMembers(5, &.{.{
            .template = .at(2),
            .trait = .at(1),
            .member = .at(3),
            .signature = .at(5),
        }}),
    );
}

test "expanded program rejects invalid component requirement rows" {
    const gpa = testing.allocator;
    var sink = Sink.init(gpa);
    var interner: Interner = .empty;
    defer interner.deinit(gpa);
    var source_parser = parser.Modules.init(gpa, &sink, &interner);
    defer source_parser.deinit();
    const source_decls = try source_parser.add(&.{.{
        .file = .from(0),
        .source = .{ .path = "source.lin", .text =
        \\trait Required {}
        \\trait Structural {}
        \\template impl Structural where reflect.components: Required {}
        \\struct Pair { left: UInt8, right: UInt16 }
        \\derive Structural for Pair
        \\
        },
    }});
    var source_modules = [_]Module{.{
        .name = "",
        .dir = "",
        .files = &.{.from(0)},
        .decls = source_decls,
        .imports = &.{},
    }};
    var source: Program = .{ .modules = &source_modules, .ast = try source_parser.finish() };
    defer source.ast.deinit(gpa);

    var expanded_interner = try Interner.initPrefix(gpa, &interner);
    defer expanded_interner.deinit(gpa);
    var generated_parser = try parser.Modules.initPrefix(gpa, &sink, &expanded_interner, &source.ast);
    defer generated_parser.deinit();
    _ = try generated_parser.add(&.{.{
        .file = .from(1),
        .source = .{ .path = "generated.lin", .text = "impl Structural for Pair {}\n" },
    }});
    var expanded_ast = try generated_parser.finish();
    defer expanded_ast.deinit(gpa);

    const derive_trait = node.DeriveTraitId.at(source.ast.deriveTraitRange(.at(4)).start);
    const valid = GeneratedImplementation{
        .generated_impl = .at(5),
        .derive = .at(4),
        .derive_trait = derive_trait,
        .target = .at(3),
        .template = .at(2),
        .requirements = .{ .start = 0, .end = 2 },
    };
    const rows = [_]ComponentRequirement{
        .{ .implementation = .at(0), .requirement = .at(0), .bound = @enumFromInt(0), .component = @enumFromInt(0) },
        .{ .implementation = .at(0), .requirement = .at(0), .bound = @enumFromInt(0), .component = @enumFromInt(1) },
    };
    try ExpandedProgram.validateGeneratedImplementations(&source.ast, &expanded_ast, &.{valid}, &rows);

    var invalid = valid;
    invalid.generated_impl = .at(4);
    try testing.expectError(
        error.InvalidGeneratedImplementation,
        ExpandedProgram.validateGeneratedImplementations(&source.ast, &expanded_ast, &.{invalid}, &rows),
    );
    invalid = valid;
    invalid.requirements.end = 3;
    try testing.expectError(
        error.InvalidComponentRequirement,
        ExpandedProgram.validateGeneratedImplementations(&source.ast, &expanded_ast, &.{invalid}, &rows),
    );
    var unordered = rows;
    unordered[0].component = @enumFromInt(1);
    try testing.expectError(
        error.InvalidComponentRequirement,
        ExpandedProgram.validateGeneratedImplementations(&source.ast, &expanded_ast, &.{valid}, &unordered),
    );
}
