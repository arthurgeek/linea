const std = @import("std");
const Ast = @import("../syntax/ast.zig").Ast;
const node = @import("../syntax/node.zig");
const resolve = @import("resolve.zig");
const Resolution = resolve.Resolution;
const DeclId = node.DeclId;

/// Settle forwarding once for every trait. Non-trait declarations have false
/// entries. The caller owns the returned declaration-domain table.
///
/// Each signature type and supertrait edge is visited once. Rejected traits
/// propagate through reverse edges, taking O(declarations + written types +
/// supertrait edges) expected time and linear temporary storage.
pub fn compute(gpa: std.mem.Allocator, ast: *const Ast, resolution: *const Resolution) ![]bool {
    const eligible = try gpa.alloc(bool, ast.declCount());
    errdefer gpa.free(eligible);
    @memset(eligible, false);
    var scan: Scan = .{ .gpa = gpa, .ast = ast };
    defer scan.pending.deinit(gpa);
    var dependents: @import("../support/chain.zig").Chain(.newest_first) = .empty;
    defer dependents.deinit(gpa);
    var children: std.ArrayList(DeclId) = .empty;
    defer children.deinit(gpa);
    var rejected: std.ArrayList(DeclId) = .empty;
    defer rejected.deinit(gpa);

    for (0..ast.declCount()) |i| {
        const decl = DeclId.at(@intCast(i));
        if (ast.declTag(decl) == .trait_) eligible[i] = true;
    }
    for (0..ast.declCount()) |i| {
        const decl = DeclId.at(@intCast(i));
        const trait = if (ast.declTag(decl) == .trait_) decl else resolution.signatures.traitOf(ast, decl) orelse continue;
        if (!try scan.declaration(decl)) eligible[trait.index()] = false;
        if (decl != trait) continue;
        for (ast.declBounds(trait)) |bound| {
            if (bound.kind != .named) {
                eligible[i] = false;
                continue;
            }
            const binding = resolution.writtenAt(bound.named.name);
            if (binding == .none) {
                eligible[i] = false;
                continue;
            }
            if (resolution.kindOf(binding) != .trait) continue;
            const parent = resolution.declaredBy(binding);
            try dependents.note(gpa, parent.index(), @intCast(children.items.len));
            try children.append(gpa, trait);
        }
    }
    for (0..ast.declCount()) |i| {
        const decl = DeclId.at(@intCast(i));
        if (ast.declTag(decl) == .trait_ and !eligible[i]) try rejected.append(gpa, decl);
    }
    var cursor: usize = 0;
    while (cursor < rejected.items.len) : (cursor += 1) {
        var uses = dependents.walk(rejected.items[cursor].index());
        while (uses.next()) |edge| {
            const child = children.items[edge];
            if (!eligible[child.index()]) continue;
            eligible[child.index()] = false;
            try rejected.append(gpa, child);
        }
    }
    return eligible;
}

const Scan = struct {
    gpa: std.mem.Allocator,
    ast: *const Ast,
    pending: std.ArrayList(node.TypeRef) = .empty,

    fn containsSelf(self: *Scan, written: node.TypeRef) !bool {
        self.pending.clearRetainingCapacity();
        try self.pending.append(self.gpa, written);
        while (self.pending.pop()) |ref| {
            if (resolve.namesSelf(self.ast, ref.name)) return true;
            try self.pending.appendSlice(self.gpa, self.ast.typeArgs(ref.args));
            // `Self.Item` reaches `Self` through the type it selects from.
            if (ref.kind == .selection) try self.pending.append(self.gpa, self.ast.selectionBase(ref));
            if (ref.kind == .callable) {
                const callable = self.ast.callableType(ref);
                try self.pending.append(self.gpa, callable.result);
                for (self.ast.params[callable.params.start..callable.params.end]) |param| {
                    try self.pending.append(self.gpa, param.written);
                }
            }
        }
        return false;
    }

    fn bounds(self: *Scan, written: []const node.TraitBound) !bool {
        for (written) |bound| switch (bound.kind) {
            .named => {
                if (resolve.namesSelf(self.ast, bound.named.name)) return false;
                for (self.ast.typeArgs(bound.named.args)) |arg| {
                    if (try self.containsSelf(arg)) return false;
                }
            },
            .callable => if (try self.containsSelf(self.ast.callableRef(bound.callable))) return false,
        };
        return true;
    }

    fn declaration(self: *Scan, decl: DeclId) !bool {
        if (try self.containsSelf(self.ast.declReturnRef(decl))) return false;
        for (self.ast.declParams(decl)) |param| {
            const ref = self.ast.withoutTypeGroups(param.written);
            const whole_read = param.convention == .read and ref.kind == .named and
                ref.args.len() == 0 and resolve.namesSelf(self.ast, ref.name);
            if (!whole_read and try self.containsSelf(ref)) return false;
        }
        if (!try self.bounds(self.ast.declBounds(decl))) return false;
        for (self.ast.declTypeParams(decl)) |param| {
            if (!try self.bounds(self.ast.boundsOf(param))) return false;
        }
        for (self.ast.declWherePredicates(decl)) |predicate| {
            if (try self.containsSelf(predicate.subject)) return false;
            if (!try self.bounds(self.ast.boundsIn(predicate.bounds))) return false;
        }
        return true;
    }
};

test "observation forwarding examines the entire trait surface" {
    try expectEligibility(
        \\pub struct Box[T] { value: T }
        \\pub trait Readable { fn read_it(self: Self) -> UInt8 }
        \\pub trait Grouped { fn inspect(self: (Self)) -> UInt8 }
        \\pub trait Mixed { fn read_it(self: Self) -> UInt8; fn change(inout self: Self) -> () }
        \\pub trait Consuming { fn take(sink self: Self) -> () }
        \\pub trait Returning { fn make() -> Self }
        \\pub trait Nested { fn nested(self: Box[Self]) -> () }
        \\pub trait Callback { fn callback(self: Self, call: fn(read x: Self) -> ()) -> () }
        \\pub trait Projection { type Item; fn get(self: Self) -> Self.Item }
        \\pub trait Independent[T] { fn inspect(self: Self, other: T) -> UInt8 }
    ,
        &.{ "Readable", "Grouped", "Independent" },
    );
}

test "observation forwarding includes transitive supertraits and their arguments" {
    try expectEligibility(
        \\pub trait Readable { fn read_it(self: Self) -> UInt8 }
        \\pub trait Parent: Readable {}
        \\pub trait Child: Parent {}
        \\pub trait Mutable { fn change(inout self: Self) -> () }
        \\pub trait Middle: Mutable {}
        \\pub trait Leaf: Middle {}
        \\pub trait Generic[T] { fn inspect(self: Self, other: T) -> UInt8 }
        \\pub trait RecursiveArgument: Generic[Self] {}
    ,
        &.{ "Readable", "Parent", "Child", "Generic" },
    );
}

fn expectEligibility(source_text: []const u8, eligible_names: []const []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    var sink = @import("../diagnostics/sink.zig").Sink.init(gpa);
    var interner: @import("../support/interner.zig").Interner = .empty;
    const source: @import("../support/source.zig").Source = .{ .path = "observations.lin", .text = source_text };
    const tokens = try @import("../lexer/lexer.zig").tokenize(gpa, &source, .from(0), &sink, &interner);
    var ast = try @import("../parser/parser.zig").parse(gpa, &source, .from(0), tokens, &sink);
    try std.testing.expectEqual(0, sink.error_count);
    const tree = try resolve.resolveTree(gpa, &ast, &sink);
    const expanded = &tree.expanded.ast;
    const eligible = try compute(gpa, expanded, &tree.resolution);
    defer gpa.free(eligible);
    for (0..expanded.declCount()) |i| {
        const decl = DeclId.at(@intCast(i));
        const name = expanded.tokenText(expanded.declName(decl));
        var expected = false;
        if (expanded.declTag(decl) == .trait_) {
            for (eligible_names) |candidate| {
                if (std.mem.eql(u8, name, candidate)) expected = true;
            }
        }
        if (eligible[i] != expected) std.debug.print("unexpected observation forwarding eligibility: {s}\n", .{name});
        try std.testing.expectEqual(expected, eligible[i]);
    }
}
