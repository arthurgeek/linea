const std = @import("std");
const testing = std.testing;

const Chain = @import("../support/chain.zig").Chain;
const types_mod = @import("types.zig");
const Typing = types_mod.Typing;
const TypeId = types_mod.TypeId;
const CallIndex = types_mod.CallIndex;
const DisposalPlan = @import("../ownership/cfg.zig").DisposalPlan;
const node = @import("../syntax/node.zig");
const Ast = @import("../syntax/ast.zig").Ast;
const ExpandedProgram = @import("../syntax/expanded_program.zig").ExpandedProgram;
const ModuleId = @import("../syntax/program.zig").ModuleId;
const Purpose = @import("resolve.zig").Purpose;
const DeclId = node.DeclId;
const ExprId = node.ExprId;
const TokenId = @import("../lexer/token.zig").TokenId;
const Resolution = @import("resolve.zig").Resolution;
const BindingId = @import("resolve.zig").BindingId;
const ClosureId = @import("resolve.zig").ClosureId;
const Sink = @import("../diagnostics/sink.zig").Sink;
const generated_calls = @import("../support/generated_calls.zig");
const typecheck = @import("typecheck.zig");
const equatableDecl = typecheck.equatableDecl;
const comparableDecl = typecheck.comparableDecl;
const sequenceDecl = typecheck.sequenceDecl;
const iteratorDecl = typecheck.iteratorDecl;
const traitMemberNamed = typecheck.traitMemberNamed;
const rendersDisplayItself = typecheck.rendersDisplayItself;
const FormattingDecls = typecheck.FormattingDecls;
const reportMissingImplementation = typecheck.reportMissingImplementation;
const reportBodilessOperation = typecheck.reportBodilessOperation;
const reportOversizedTypes = typecheck.reportOversizedTypes;
const symbol_names = @import("../support/symbol.zig");

/// Spells the symbol derived from an instance key.
///
/// Two modules may declare one name, and so may a type and the module it sits
/// in, so a symbol carries what it was reached through. Type arguments join
/// them for the same reason: two instantiations of one declaration are two
/// functions. The mutable pool is intentional: settling an implementation's
/// supplied trait arguments may intern types before the pool is sealed.
///
/// Injective by construction, whatever the names are spelled. A symbol is
/// either `route;` then `name[args]` or `Owner[args].name[args]`, or, for an
/// implementation's member, `Head;route;Trait[supplied].name[args]`; a
/// generated body's is `kind.N[args]`. It reads back in three steps:
///
/// - A route is dotted directory names, each an identifier or escaped as one
///   with `$`, so it holds only letters, digits, `_`, `.` and `$`. The longest
///   prefix in that alphabet is followed by `;` exactly when the symbol is a
///   declaration's and either has the first shape or a head that is a named
///   type with no arguments. Any other head opens a bracket or a parenthesis
///   first, and a generated body's `kind.N` is followed by `[` or by nothing.
/// - After that `;`, the longest prefix in the same alphabet is followed by
///   `;` only in the second shape. In the first it is `name`, `Owner` or
///   `Owner.name`, and is followed by `[` or by the end.
/// - Every bracketed list, and a head that is not a plain name, is a type
///   spelling, and a type spelling reads back by its own grammar: a quoted
///   default escapes its quote and backslash, an aggregate's text is length
///   prefixed, and arrays, callables and borrows close what they open. So a
///   list ends where its grammar ends, not at the first `]` or `;` a count of
///   characters meets -- a default's text may hold either.
///
/// Escaping is injective because `$` is always escaped, and the prefix is
/// constant; only a name shortened past the bound to a digest can collide,
/// which the module verifier reports.
fn symbolFor(
    gpa: std.mem.Allocator,
    ast: *const Ast,
    program: *const ExpandedProgram,
    d: DeclId,
    args: []const TypeId,
    pool: *Typing.Builder,
    self_ty: TypeId,
    impl_args: []const TypeId,
) ![]const u8 {
    const written = ast.tokenText(ast.declName(d));
    if (ast.declIsExtern(d)) return gpa.dupe(u8, written);

    const owner = ast.declOwner(d);
    const scope: []const u8 = if (owner == TokenId.none) "" else ast.tokenText(owner);
    var spelled: std.ArrayList(u8) = .empty;
    defer spelled.deinit(gpa);

    const enclosing = pool.view().implementationOf(d);
    const member_of = if (enclosing) |i|
        if (self_ty == .poison) i.ty else self_ty
    else
        TypeId.poison;
    const supplied = try gpa.alloc(TypeId, if (enclosing) |i| i.args.len else 0);
    defer gpa.free(supplied);
    if (enclosing) |i| for (i.args, supplied) |written_arg, *settled| {
        settled.* = try pool.substitute(written_arg, i.decl.index(), impl_args);
    };

    const typing = pool.view();
    if (ast.declIsProvided(d) and self_ty != .poison) {
        // A trait's provided operation is one body per type implementing the
        // trait, so it is named as that type's member is: the type first,
        // then the trait.
        const head = try typing.mangledName(gpa, self_ty);
        defer gpa.free(head);
        try spelled.appendSlice(gpa, head);
        try spelled.append(gpa, route_end);
        try appendRoute(&typing, gpa, &spelled, @intCast(program.moduleOf(d).index()));
        try spelled.appendSlice(gpa, scope);
        try typing.appendArguments(gpa, &spelled, impl_args);
        try spelled.append(gpa, '.');
    } else if (enclosing != null and enclosing.?.ofATrait()) {
        const i = enclosing.?;
        const head = try typing.mangledName(gpa, member_of);
        defer gpa.free(head);
        try spelled.appendSlice(gpa, head);
        try spelled.append(gpa, route_end);

        const trait = DeclId.at(i.trait);
        try appendRoute(&typing, gpa, &spelled, @intCast(program.moduleOf(trait).index()));
        try spelled.appendSlice(gpa, ast.tokenText(ast.declName(trait)));
        try typing.appendArguments(gpa, &spelled, supplied);
        try spelled.append(gpa, '.');
    } else {
        try appendRoute(&typing, gpa, &spelled, @intCast(program.moduleOf(d).index()));
        if (scope.len > 0) {
            try spelled.appendSlice(gpa, scope);
            try typing.appendArguments(gpa, &spelled, typing.appliedTo(member_of));
            try spelled.append(gpa, '.');
        }
    }
    try spelled.appendSlice(gpa, written);
    try typing.appendArguments(gpa, &spelled, args);

    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    try symbol_names.appendBounded(gpa, &out, spelled.items);
    return out.toOwnedSlice(gpa);
}

/// What ends a declaration's module route, and a head that is a named type,
/// in a symbol: a character no route holds.
const route_end = ';';

/// The characters a module route is spelled with: dotted identifiers, and the
/// `$` that escapes a byte of a directory name no identifier holds.
const route_alphabet = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.$";

/// Appends a declaration's module route, dotted, and the `;` that ends it. The
/// root's route is empty and is ended all the same: omitting it left the root's
/// names bare, spelled exactly like another module's route.
fn appendRoute(typing: *const Typing, gpa: std.mem.Allocator, out: *std.ArrayList(u8), module: u32) !void {
    if (module < typing.module_paths.len) {
        const path = typing.module_paths[module];
        std.debug.assert(std.mem.indexOfNone(u8, path, route_alphabet) == null);
        try out.appendSlice(gpa, path);
    }
    try out.append(gpa, route_end);
}

test "a symbol's route is the prefix its alphabet allows, and the separator follows it" {
    // The shapes that met under dots alone read apart at the first step: the
    // prefix in the route alphabet, and what follows it.
    const pairs = [_][2][]const u8{
        .{ ";_1.helper", "_1;helper" },
        .{ "A;;_1[W].size", "A;_1;W.size" },
        .{ "_1;_2.helper", "_1._2;helper" },
        .{ ";Cell._1[_2]", "Cell;;_1._2" },
    };
    for (pairs) |pair| {
        const left = std.mem.indexOfNone(u8, pair[0], route_alphabet).?;
        const right = std.mem.indexOfNone(u8, pair[1], route_alphabet).?;
        const same_prefix = std.mem.eql(u8, pair[0][0..left], pair[1][0..right]);
        const rest_left = pair[0][left + 1 ..];
        const rest_right = pair[1][right + 1 ..];
        const second_left = std.mem.indexOfNone(u8, rest_left, route_alphabet);
        const second_right = std.mem.indexOfNone(u8, rest_right, route_alphabet);
        try testing.expect(!same_prefix or !std.meta.eql(second_left, second_right) or
            !std.mem.eql(u8, rest_left, rest_right));
    }
}

test "a default's text in a type spelling does not end the list it sits in" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    // Two functions whose aggregate defaults are spelled with a `;` after
    // every part, each instantiated as the argument of one generic. A default
    // string's text, which may hold `[` and `]` as well, is in the corpus case
    // that loads the library. Counting separators by character misreads both
    // symbols; the type grammar does not.
    const source: @import("../support/source.zig").Source = .{ .path = "defaults.lin", .text =
        \\@copyable
        \\struct P { a: UInt8, b: UInt8 }
        \\fn greet(p: P = P { a = 1, b = 2 }) -> UInt8 { p.a + p.b }
        \\fn hail(p: P = P { a = 2, b = 1 }) -> UInt8 { p.a + p.b }
        \\fn id[T](sink t: T) -> T { t }
        \\fn main() -> UInt8 {
        \\    let f = id(greet)
        \\    let g = id(hail)
        \\    f() + g() - 6
        \\}
    };
    var interner: @import("../support/interner.zig").Interner = .empty;
    var sink = Sink.init(gpa);
    const tokens = try @import("../lexer/lexer.zig").tokenize(gpa, &source, .from(0), &sink, &interner);
    var ast = try @import("../parser/parser.zig").parse(gpa, &source, .from(0), tokens, &sink);
    var resolved = try @import("resolve.zig").resolveTree(gpa, &ast, &sink);
    var typing = try typecheck.typecheckTree(gpa, &resolved, &sink);
    var disposals = try @import("../ownership/check.zig").checkTree(gpa, &resolved, &typing, &sink);
    defer disposals.deinit(gpa);
    var instances = try instantiate(gpa, &resolved.expanded, &resolved.resolution, &typing, &disposals, &sink, .program);
    defer instances.deinit();
    try testing.expectEqual(@as(u32, 0), sink.error_count);

    var ids: std.ArrayList([]const u8) = .empty;
    const table = instances.table();
    for (0..table.count()) |i| {
        const name = table.get(.at(@intCast(i))).name;
        if (std.mem.startsWith(u8, name, ";id[")) try ids.append(gpa, name);
    }
    try testing.expectEqual(@as(usize, 2), ids.items.len);
    try testing.expect(!std.mem.eql(u8, ids.items[0], ids.items[1]));
    for (ids.items) |name| {
        // The type spelling the argument list holds carries the default's
        // encoding, so it holds `;` outside any bracket of its own: a
        // separator is not what ends a part of a symbol.
        const argument = name[";id[".len .. name.len - 1];
        var depth: isize = 0;
        var outside: usize = 0;
        for (argument) |c| switch (c) {
            '[' => depth += 1,
            ']' => depth -= 1,
            ';' => if (depth <= 0) {
                outside += 1;
            },
            else => {},
        };
        try testing.expect(outside > 1);
        try testing.expect(symbol_names.holds(name));
    }
}

fn symbolForClosure(
    gpa: std.mem.Allocator,
    closure: ClosureId,
    args: []const TypeId,
    self_ty: TypeId,
    impl_args: []const TypeId,
    pool: *Typing.Builder,
) ![]const u8 {
    return symbolForGenerated(gpa, "closure", @intFromEnum(closure), args, self_ty, impl_args, pool);
}

fn symbolForGenerated(
    gpa: std.mem.Allocator,
    kind: []const u8,
    identity: u32,
    args: []const TypeId,
    self_ty: TypeId,
    impl_args: []const TypeId,
    pool: *Typing.Builder,
) ![]const u8 {
    var spelled: std.ArrayList(u8) = .empty;
    defer spelled.deinit(gpa);
    const base = try std.fmt.allocPrint(gpa, "{s}.{d}", .{ kind, identity });
    defer gpa.free(base);
    try spelled.appendSlice(gpa, base);
    try pool.view().appendArguments(gpa, &spelled, args);
    if (self_ty != .poison) try pool.view().appendArguments(gpa, &spelled, &.{self_ty});
    if (impl_args.len > 0) {
        try spelled.appendSlice(gpa, ".impl");
        try pool.view().appendArguments(gpa, &spelled, impl_args);
    }
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    try symbol_names.appendBounded(gpa, &out, spelled.items);
    return out.toOwnedSlice(gpa);
}

/// The identity of one instance, and the whole of it.
///
/// The key is the tuple and nothing else: which declaration, at which nominal
/// member and implementation type arguments, running for which `Self`. Every
/// checker-side property that does not participate in type identity -- where a
/// record was settled, which bound admitted a type, which region lent a value
/// -- is excluded by construction, because equality below reads these
/// fields and can read nothing else. Two calls with the same key name one
/// instance; different keys never share a symbol, which is derived from the
/// key downstream rather than carried as identity of its own.
pub const BodyOrigin = types_mod.BodyOrigin;

/// A concrete implementation's declaration already identifies its receiver;
/// a generic implementation needs the concrete receiver in its instance key.
pub fn receiverKeying(ast: *const Ast, implementation: DeclId, held: TypeId) TypeId {
    return if (ast.declTypeParams(implementation).len == 0) .poison else held;
}

pub const InherentHead = struct { held: TypeId, impl_args: []const TypeId };

/// Reads an inherent implementation's arguments from the pool discovery is
/// still building, settling them where they are not yet recorded.
const PoolArguments = struct {
    pool: *Typing.Builder,

    fn of(self: PoolArguments, implementation: types_mod.ImplementationId, receiver: TypeId) std.mem.Allocator.Error!?[]const TypeId {
        return self.pool.implementationArguments(implementation, &.{}, receiver);
    }
};

/// Reads the arguments discovery recorded, which lowering consumes without
/// settling anything.
pub const RecordedArguments = struct {
    typing: *const Typing,

    pub fn of(self: RecordedArguments, implementation: types_mod.ImplementationId, receiver: TypeId) error{}!?[]const TypeId {
        return self.typing.implementationArgumentsWithin(.none, implementation, &.{}, receiver);
    }
};

/// The receiver keying and implementation arguments of a member of an
/// inherent implementation, for a concrete receiver, or null where the member
/// belongs to no implementation or its implementation does not apply to the
/// receiver. Discovery and lowering both key an instance through this one
/// routine, each reading the arguments through its own `arguments.of`, so a
/// call and a function value naming the member cannot disagree about what the
/// absence of an implementation means.
pub fn inherentHead(ast: *const Ast, typing: *const Typing, member: DeclId, receiver: TypeId, arguments: anytype) !?InherentHead {
    const enclosing = typing.implementationOf(member) orelse return null;
    return .{
        .held = receiverKeying(ast, enclosing.decl, receiver),
        .impl_args = try arguments.of(typing.implementationIdOf(member).?, receiver) orelse return null,
    };
}

pub const SelectedMember = struct {
    body: BodyOrigin,
    self_ty: TypeId,
    impl_args: []const TypeId,
};

pub fn selectedMember(ast: *const Ast, typing: *const Typing, choice: types_mod.ImplementationChoice, member: DeclId) ?SelectedMember {
    // A trait's provided operation is its own body at every type that
    // implements the trait, keyed by that type as its `Self` and by the
    // trait's arguments it was reached through, which stand for the trait's
    // parameters as an implementation's arguments stand for its own.
    if (ast.declIsProvided(member)) return switch (choice.supplier) {
        .bound => null,
        .declared, .closure_release => .{ .body = .{ .declaration = member }, .self_ty = choice.implementedFor(), .impl_args = choice.trait_args },
    };
    return switch (choice.supplier) {
        .bound => null,
        .closure_release => if (typing.closure_release != null and typing.closure_release.?.member == member)
            .{ .body = .{ .closure_release = choice.receiver }, .self_ty = .poison, .impl_args = &.{} }
        else
            null,
        .declared => |id| blk: {
            const row = typing.implementations[id.index()];
            if (row.isAmbient()) break :blk null;
            const supplied = typing.supply_index.memberOf(row.decl, member) orelse break :blk null;
            break :blk .{ .body = .{ .declaration = supplied }, .self_ty = receiverKeying(ast, row.decl, choice.implementedFor()), .impl_args = choice.impl_args };
        },
    };
}

/// The body a function value naming `trait`'s `member` holds, for one
/// implementation choice: the member that implementation supplies; for an
/// operation the compiler provides, a body generated to perform it; and for
/// an array that answers through its slice view, a body generated to view
/// its array arguments and call the slice's member. Null where the receiver
/// answers only through an observation of itself, which no body taking the
/// receiver as it is can stand for.
pub fn valueMember(ast: *const Ast, typing: *const Typing, choice: types_mod.ImplementationChoice, trait: DeclId, member: DeclId) ?SelectedMember {
    if (choice.observations != 0) return null;
    const at: types_mod.OperationAt = .{ .trait = trait, .member = member, .receiver = choice.receiver };
    if (choice.view != .poison) return .{ .body = .{ .viewed = at }, .self_ty = .poison, .impl_args = &.{} };
    if (selectedMember(ast, typing, choice, member)) |selected| return selected;
    return switch (choice.supplier) {
        .declared => |id| if (typing.implementations[id.index()].isAmbient())
            .{ .body = .{ .built_in = at }, .self_ty = .poison, .impl_args = &.{} }
        else
            null,
        .bound, .closure_release => null,
    };
}

/// The signature a generated operation's body has: its trait member's,
/// with `Self`, which the member's signature places after its own parameters,
/// read as the receiver. The operations the compiler provides take no
/// parameters of their own.
pub fn builtInSignature(ast: *const Ast, typing: *const Typing, pool: *Typing.Builder, built_in: types_mod.OperationAt) std.mem.Allocator.Error!TypeId {
    std.debug.assert(ast.declTypeParams(built_in.member).len == 0);
    return pool.substitute(typing.declSignature(built_in.member), @intCast(built_in.member.index()), &.{built_in.receiver});
}

pub const ClosureReleaseCall = struct {
    field: types_mod.FieldOrdinal,
    callee: InstanceId,
};

pub const ClosureReleasePlan = struct {
    signature: TypeId,
    calls: []const ClosureReleaseCall,
};

/// The key of the instance a closure of this type runs as: the closure and
/// what its type is instantiated over. Its enclosing body's instance key
/// differs for a provided operation, whose substitution also binds `Self`, so
/// every path reaching a closure body -- a direct call, a function value, a
/// generic callable, an erased entry -- keys it here, from its type. The
/// argument slices borrow the pool's storage.
fn closureKey(pool: *const Typing.Builder, closure: types_mod.ClosureType) InstanceKey {
    return .{ .body = .{ .closure = closure.closure }, .args = pool.closureArgs(closure), .self_ty = closure.self_ty, .impl_args = pool.closureImplArgs(closure) };
}

pub const InstanceKey = struct {
    body: BodyOrigin,
    args: []const TypeId,
    self_ty: TypeId,
    impl_args: []const TypeId = &.{},

    /// What the index files a key under, as one number. Hashed and then
    /// verified, because only the comparison decides that two keys are one.
    fn hash(self: InstanceKey) u64 {
        var h: std.hash.Wyhash = .init(0);
        const tag: u8 = @intFromEnum(std.meta.activeTag(self.body));
        h.update(std.mem.asBytes(&tag));
        const at: u32 = switch (self.body) {
            .declaration => |decl| @intCast(decl.index()),
            .closure => |closure| @intCast(closure.index()),
            .closure_release => |closure| @intFromEnum(closure),
            .constructor => |constructor| @intFromEnum(constructor.id),
            .erased_entry => |entry| @intFromEnum(entry.callable) ^ (@intFromEnum(entry.signature) << 16),
            .erased_settle => |callable| @intFromEnum(callable),
            .built_in, .viewed => |at| @as(u32, @intCast(at.member.index())) ^ (@intFromEnum(at.receiver) << 16),
        };
        h.update(std.mem.asBytes(&at));
        h.update(std.mem.asBytes(&self.args.len));
        for (self.args) |a| {
            const v: u32 = @intFromEnum(a);
            h.update(std.mem.asBytes(&v));
        }
        const held: u32 = @intFromEnum(self.self_ty);
        h.update(std.mem.asBytes(&held));
        h.update(std.mem.asBytes(&self.impl_args.len));
        h.update(std.mem.sliceAsBytes(self.impl_args));
        return h.final();
    }

    fn eql(self: InstanceKey, other: InstanceKey) bool {
        return std.meta.eql(self.body, other.body) and
            self.self_ty == other.self_ty and
            std.mem.eql(TypeId, self.args, other.args) and
            std.mem.eql(TypeId, self.impl_args, other.impl_args);
    }
};

/// Each `extern` declaration repeating an earlier one's symbol, and that
/// earlier declaration, as the checker settled them.
const ExternSymbols = std.AutoHashMapUnmanaged(DeclId, DeclId);

const no_extern_symbols: ExternSymbols = .empty;

/// The body a key names. Every `extern` declaration of one symbol names the
/// one function the runtime provides, so each is keyed as the first
/// declaration of its symbol and all of them share one instance.
fn keyedBody(externs: *const ExternSymbols, body: BodyOrigin) BodyOrigin {
    return switch (body) {
        .declaration => |decl| .{ .declaration = externs.get(decl) orelse decl },
        .closure, .closure_release, .constructor, .erased_entry, .erased_settle, .built_in, .viewed => body,
    };
}

/// One discovered instance: its identity, and the symbol derived from it.
pub const Instance = struct {
    key: InstanceKey,
    name: []const u8,
};

/// A position in the instance set, in first-discovery order.
pub const InstanceId = enum(u32) {
    _,

    pub fn index(self: InstanceId) u32 {
        return @intFromEnum(self);
    }

    pub fn at(i: u32) InstanceId {
        return @enumFromInt(i);
    }
};

/// The finished instance set, and the one way a later pass reaches it.
///
/// Immutable by shape rather than by promise: this view holds no interner, so
/// a consumer holding it can ask which instances exist and cannot cause one
/// to. Lowering resolves keys through this view rather than the instance
/// builder; missing required keys are compiler defects.
pub const InstanceTable = struct {
    instances: []const Instance,
    keyed: *const Chain(.newest_first),
    release_plans: *const std.AutoHashMapUnmanaged(InstanceId, ClosureReleasePlan),
    implementation_rows: []const types_mod.Implementation,
    zeroed_allocator: DeclId = .none,
    extern_symbols: *const ExternSymbols = &no_extern_symbols,
    /// The complete pool discovery settled keys through. It is a read-only
    /// view over the sealed pool, whose ownership transfers to emission.
    typing: Typing = .{
        .pool = &.{},
        .variants = .empty,
        .fields = .empty,
        .expr_types = &.{},
        .binding_types = .empty,
        .decl_returns = .empty,
    },

    /// Reads the concrete choice retained by checking or discovery. An absent row is a
    /// diagnosed missing implementation; an absent key is a broken handoff.
    pub fn selectedImplementation(self: *const InstanceTable, trait: DeclId, args: []const TypeId, receiver: TypeId) ?types_mod.Implementation {
        const choice = self.selectedChoice(trait, args, receiver);
        const id = choice.declaredImplementation() orelse return null;
        return self.implementation_rows[id.index()];
    }

    pub fn selectedChoice(self: *const InstanceTable, trait: DeclId, args: []const TypeId, receiver: TypeId) types_mod.ImplementationChoice {
        return self.typing.implementation_selections.choiceOf(trait, args, receiver) orelse
            @panic("compiler defect: implementation choice was not discovered");
    }

    pub fn selectedReceiver(self: *const InstanceTable, trait: DeclId, args: []const TypeId, receiver: TypeId) TypeId {
        return self.typing.implementation_selections.receiverOf(trait, args, receiver) orelse
            @panic("compiler defect: implementation receiver was not discovered");
    }

    pub fn selectedArguments(self: *const InstanceTable, trait: DeclId, args: []const TypeId, receiver: TypeId) []const TypeId {
        return (self.typing.implementation_selections.choiceOf(trait, args, receiver) orelse
            @panic("compiler defect: implementation arguments were not discovered")).impl_args;
    }

    pub fn lookup(
        self: *const InstanceTable,
        decl: DeclId,
        args: []const TypeId,
        self_ty: TypeId,
        impl_args: []const TypeId,
    ) ?InstanceId {
        return self.lookupBody(.{ .declaration = decl }, args, self_ty, impl_args);
    }

    pub fn lookupClosure(self: *const InstanceTable, pool: *const Typing.Builder, closure: types_mod.ClosureType) ?InstanceId {
        const key = closureKey(pool, closure);
        return self.lookupBody(key.body, key.args, key.self_ty, key.impl_args);
    }

    test "lookupClosure finds the one instance a closure type runs as" {
        var arena = std.heap.ArenaAllocator.init(testing.allocator);
        defer arena.deinit();
        const gpa = arena.allocator();
        const source: @import("../support/source.zig").Source = .{ .path = "closures.lin", .text =
            \\trait Weighed {
            \\    fn weight(self: Self) -> UInt8
            \\    fn doubled(self: Self) -> UInt8 {
            \\        let twice = [self] |n: UInt8| self.weight() * n
            \\        twice(2)
            \\    }
            \\}
            \\@copyable
            \\struct Crate { kilos: UInt8 }
            \\@copyable
            \\struct Sack { grams: UInt8 }
            \\impl Weighed for Crate { fn weight(self: Self) -> UInt8 { self.kilos } }
            \\impl Weighed for Sack { fn weight(self: Self) -> UInt8 { self.grams } }
            \\fn main() -> UInt8 { Crate { kilos = 1 }.doubled() + Sack { grams = 2 }.doubled() }
        };
        var interner: @import("../support/interner.zig").Interner = .empty;
        var sink = Sink.init(gpa);
        const tokens = try @import("../lexer/lexer.zig").tokenize(gpa, &source, .from(0), &sink, &interner);
        var ast = try @import("../parser/parser.zig").parse(gpa, &source, .from(0), tokens, &sink);
        var resolved = try @import("resolve.zig").resolveTree(gpa, &ast, &sink);
        var typing = try typecheck.typecheckTree(gpa, &resolved, &sink);
        var disposals = try @import("../ownership/check.zig").checkTree(gpa, &resolved, &typing, &sink);
        defer disposals.deinit(gpa);
        var instances = try instantiate(gpa, &resolved.expanded, &resolved.resolution, &typing, &disposals, &sink, .program);
        defer instances.deinit();
        try testing.expectEqual(@as(u32, 0), sink.error_count);
        const table = instances.table();

        var closure_instances: usize = 0;
        for (0..table.count()) |at| {
            if (table.get(.at(@intCast(at))).key.body == .closure) closure_instances += 1;
        }
        // One closure body, run at each of the two `Self` types.
        try testing.expectEqual(@as(usize, 2), closure_instances);

        var found = [_]?InstanceId{ null, null };
        var hits: usize = 0;
        for (instances.pool.pool.items) |ty| switch (ty) {
            .closure => |closure| {
                const id = table.lookupClosure(&instances.pool, closure) orelse continue;
                const key = table.get(id).key;
                try testing.expectEqual(closure.closure, key.body.closure);
                try testing.expectEqual(closure.self_ty, key.self_ty);
                if (found[0] == null or found[0].? == id) found[0] = id else found[1] = id;
                hits += 1;
            },
            else => {},
        };
        try testing.expect(hits >= 2);
        try testing.expect(found[1] != null and found[0].? != found[1].?);
    }

    pub fn lookupConstructor(self: *const InstanceTable, constructor: types_mod.ConstructorBody, args: []const TypeId, self_ty: TypeId, impl_args: []const TypeId) ?InstanceId {
        return self.lookupBody(.{ .constructor = constructor }, args, self_ty, impl_args);
    }

    pub fn lookupBody(self: *const InstanceTable, body: BodyOrigin, args: []const TypeId, self_ty: TypeId, impl_args: []const TypeId) ?InstanceId {
        const key: InstanceKey = .{ .body = keyedBody(self.extern_symbols, body), .args = args, .self_ty = self_ty, .impl_args = impl_args };
        var run = self.keyed.walk(key.hash());
        while (run.next()) |i| {
            if (self.instances[i].key.eql(key)) return InstanceId.at(i);
        }
        return null;
    }

    pub fn get(self: *const InstanceTable, id: InstanceId) Instance {
        return self.instances[id.index()];
    }

    pub fn count(self: *const InstanceTable) u32 {
        return @intCast(self.instances.len);
    }
};

/// Builds the set during discovery. The only interner there is: everything
/// downstream sees the `InstanceTable` view, so growth ends where this ends.
pub const TableBuilder = struct {
    gpa: std.mem.Allocator,
    instances: std.ArrayList(Instance) = .empty,
    /// Which entries carry each key, so interning is a walk of one chain
    /// rather than of everything discovered so far.
    keyed: Chain(.newest_first) = .empty,
    release_plans: std.AutoHashMapUnmanaged(InstanceId, ClosureReleasePlan) = .empty,
    implementation_rows: []const types_mod.Implementation = &.{},
    /// The trusted zeroed allocation producer; it remains an ordinary call.
    zeroed_allocator: DeclId = .none,
    extern_symbols: *const ExternSymbols = &no_extern_symbols,
    /// The two formatting traits and members interpolation discovery selects.
    /// They belong to the compilation, so every reached instance reads this
    /// one index rather than scanning all declarations again.
    formatting: ?FormattingDecls = null,
    /// A laid-out interpolation value renders through these library
    /// functions, found once for the same reason.
    layouts: ?LayoutDecls = null,

    pub fn init(gpa: std.mem.Allocator) TableBuilder {
        return .{ .gpa = gpa };
    }

    pub fn deinit(self: *TableBuilder) void {
        for (self.instances.items) |i| {
            self.gpa.free(i.key.args);
            self.gpa.free(i.key.impl_args);
            self.gpa.free(i.name);
        }
        var plans = self.release_plans.valueIterator();
        while (plans.next()) |plan| self.gpa.free(plan.calls);
        self.release_plans.deinit(self.gpa);
        self.instances.deinit(self.gpa);
        self.keyed.deinit(self.gpa);
    }

    /// The id a key names, claiming one where it was never asked for before.
    ///
    /// A new key owns one spelling. Its supplied trait arguments are settled
    /// while spelling that first instance; another request for the same
    /// canonical key reads the retained answer without touching the pool.
    pub fn intern(
        self: *TableBuilder,
        requested: InstanceKey,
        program: *const ExpandedProgram,
        pool: *Typing.Builder,
    ) !struct { id: InstanceId, fresh: bool } {
        var key = requested;
        key.body = keyedBody(self.extern_symbols, requested.body);
        const filed = key.hash();
        var run = self.keyed.walk(filed);
        while (run.next()) |i| {
            if (self.instances.items[i].key.eql(key)) {
                return .{ .id = InstanceId.at(i), .fresh = false };
            }
        }

        // Copy before spelling: settling supplied arguments can grow the
        // type pool, which may own the request's argument slice.
        const owned = try self.gpa.dupe(TypeId, key.args);
        errdefer self.gpa.free(owned);
        const owned_impl = try self.gpa.dupe(TypeId, key.impl_args);
        errdefer self.gpa.free(owned_impl);
        const name = switch (key.body) {
            .declaration => |decl| try symbolFor(self.gpa, &program.ast, program, decl, owned, pool, key.self_ty, owned_impl),
            .closure => |closure| try symbolForClosure(self.gpa, closure, owned, key.self_ty, owned_impl, pool),
            .closure_release => |closure| try symbolForGenerated(self.gpa, "closure_release", @intFromEnum(closure), owned, key.self_ty, owned_impl, pool),
            .constructor => |constructor| try symbolForGenerated(self.gpa, "constructor", @intFromEnum(constructor.id), owned, key.self_ty, owned_impl, pool),
            .erased_entry => |entry| try symbolForGenerated(self.gpa, "closure_entry", @intFromEnum(entry.callable), &.{entry.signature}, key.self_ty, owned_impl, pool),
            .erased_settle => |callable| try symbolForGenerated(self.gpa, "closure_settle", @intFromEnum(callable), owned, key.self_ty, owned_impl, pool),
            .built_in => |built_in| try symbolForGenerated(self.gpa, "built_in", @intCast(built_in.member.index()), &.{built_in.receiver}, key.self_ty, owned_impl, pool),
            .viewed => |viewed| try symbolForGenerated(self.gpa, "viewed", @intCast(viewed.member.index()), &.{viewed.receiver}, key.self_ty, owned_impl, pool),
        };
        errdefer self.gpa.free(name);
        const claimed: u32 = @intCast(self.instances.items.len);
        try self.instances.append(self.gpa, .{
            .key = .{ .body = key.body, .args = owned, .self_ty = key.self_ty, .impl_args = owned_impl },
            .name = name,
        });
        errdefer _ = self.instances.pop();
        try self.keyed.note(self.gpa, filed, claimed);
        return .{ .id = InstanceId.at(claimed), .fresh = true };
    }

    /// The finished view. The builder still owns the memory; nothing about the
    /// view can grow it.
    pub fn table(self: *const TableBuilder) InstanceTable {
        return .{ .instances = self.instances.items, .keyed = &self.keyed, .release_plans = &self.release_plans, .implementation_rows = self.implementation_rows, .zeroed_allocator = self.zeroed_allocator, .extern_symbols = self.extern_symbols };
    }
};

/// The completed discovery and the type pool it completed.
///
/// A consumer reaches instances through `table`, which exposes lookup only,
/// and the pool is sealed when discovery finishes, making every later growth
/// attempt a named compiler defect.
pub const Instantiation = struct {
    builder: TableBuilder,
    pool: Typing.Builder,

    pub fn deinit(self: *Instantiation) void {
        self.builder.deinit();
        self.pool.deinit();
    }

    pub fn table(self: *const Instantiation) InstanceTable {
        var view = self.builder.table();
        view.typing = self.pool.view();
        return view;
    }
};

/// Discovers the complete ordered instance set for one compilation.
///
/// Roots are records earlier passes validated: the entry point, a library's
/// root exports, or the test dispatcher calls. Each appended entry is walked
/// exactly once, in first-discovery order. The pool is sealed only after that
/// queue drains, so nothing after this pass can quietly extend the answer.
pub fn instantiate(
    gpa: std.mem.Allocator,
    program: *const ExpandedProgram,
    resolution: *const Resolution,
    typing: *const Typing,
    disposals: *const DisposalPlan,
    sink: *Sink,
    purpose: Purpose,
) !Instantiation {
    var out: Instantiation = .{
        .builder = TableBuilder.init(gpa),
        .pool = try Typing.Builder.reopen(gpa, typing),
    };
    errdefer out.deinit();
    out.builder.implementation_rows = typing.implementations;
    out.builder.extern_symbols = &typing.extern_symbols;
    out.builder.zeroed_allocator = @import("intrinsics.zig").libraryExternDecl(program, &program.ast, typing, "linea_alloc");

    switch (purpose) {
        .program => if (resolution.entry != DeclId.none) {
            _ = try internRoot(&out, program, resolution.entry, &.{});
        } else {
            const publishes = program.kind == .library;
            for (program.modules, 0..) |_, module_index| {
                if (publishes and ModuleId.from(module_index) != program.source.primary) continue;
                for (program.declsOf(ModuleId.from(module_index))) |d| {
                    if (publishes and !program.ast.declIsExport(d)) continue;
                    if (program.ast.declTag(d) != .function) continue;
                    if (program.ast.declTypeParams(d).len > 0) continue;
                    if (isFamilyMember(&program.ast, resolution, typing, d)) continue;
                    if (program.ast.declBody(d) == ExprId.none) continue;
                    _ = try internRoot(&out, program, d, &.{});
                }
            }
        },
        .tests => try seedDispatcher(&out, program, resolution, typing),
    }

    var at: u32 = 0;
    while (at < out.builder.table().count()) : (at += 1) {
        try discoverReporting(
            gpa,
            &program.ast,
            program,
            resolution,
            typing,
            &out.pool,
            &out.builder,
            .at(at),
            disposals,
            sink,
        );

        // The runtime unwraps a Result-returning entry and reports its failure.
        // That generated call is emitted after the source body, so it is
        // discovered here, after the body's sites and before the next work item.
        const instance = out.builder.instances.items[at];
        if (instance.key.body == .declaration and instance.key.body.declaration == resolution.entry) {
            const decl = instance.key.body.declaration;
            const origin: types_mod.Instantiation = .{
                .decl = decl,
                .args = instance.key.args,
            };
            const answer = try origin.through(&out.pool, typing.declReturn(decl));
            const view = out.pool.view();
            if (view.failureVariantOf(answer)) |bad| {
                if (view.variantFieldCount(answer, bad) > 0) {
                    const held = view.variantFieldType(answer, bad, 0);
                    const report = generatedCall(program, "report");
                    if (report != DeclId.none) _ = try internRoot(&out, program, report, &.{held});
                }
            }
        }
    }

    // Type sizes require the complete pool. Missing implementations were
    // reported at their call sites during instance discovery.
    try reportOversizedTypes(sink, program, &out.pool, @intCast(typing.pool.len));

    out.pool.seal();
    return out;
}

/// Whether `d` is a member of something generic: an implementation with
/// parameters or a parameterised head, or a trait, whose default body has
/// `Self` as a parameter. Such a body has no concrete instance until a call
/// supplies the receiver.
fn isFamilyMember(ast: *const Ast, resolution: *const Resolution, typing: *const Typing, d: DeclId) bool {
    if (resolution.signatures.traitOf(ast, d) != null) return true;
    const implementation = typing.implementationOf(d) orelse return false;
    return ast.declTypeParams(implementation.decl).len > 0 or ast.declHead(implementation.decl).args.len() > 0;
}

/// An interpolation calls one of these library functions for a value whose
/// format spec lays it out. They are found once per program. Discovery and
/// lowering both ask `of`, so the function one reaches is the function the
/// other calls.
pub const LayoutDecls = struct {
    display: DeclId,
    debug: DeclId,
    integer: DeclId,
    float: DeclId,

    pub fn init(program: *const ExpandedProgram) LayoutDecls {
        return .{
            .display = generatedCall(program, "interpolate_display"),
            .debug = generatedCall(program, "interpolate_debug"),
            .integer = generatedCall(program, "interpolate_integer"),
            .float = generatedCall(program, "interpolate_float"),
        };
    }

    test "a program's own layout names are not the library's" {
        var arena = std.heap.ArenaAllocator.init(testing.allocator);
        defer arena.deinit();
        const gpa = arena.allocator();
        const source: @import("../support/source.zig").Source = .{ .path = "layouts.lin", .text =
            \\fn interpolate_display() -> UInt8 { 1 }
            \\fn main() -> UInt8 { interpolate_display() }
        };
        var interner: @import("../support/interner.zig").Interner = .empty;
        var sink = Sink.init(gpa);
        const tokens = try @import("../lexer/lexer.zig").tokenize(gpa, &source, .from(0), &sink, &interner);
        var ast = try @import("../parser/parser.zig").parse(gpa, &source, .from(0), tokens, &sink);
        var resolved = try @import("resolve.zig").resolveTree(gpa, &ast, &sink);
        const layouts = LayoutDecls.init(&resolved.expanded);
        try testing.expectEqual(DeclId.none, layouts.display);
        try testing.expectEqual(DeclId.none, layouts.debug);
        try testing.expectEqual(DeclId.none, layouts.integer);
        try testing.expectEqual(DeclId.none, layouts.float);
    }

    /// Answer the function that lays out a value of this shape in this
    /// format. The shape is the value's concrete type's, so a generic body
    /// lays a number out as a number once it is instantiated with one.
    pub fn of(self: LayoutDecls, format: node.InterpolationFormat, shape: types_mod.LayoutShape) Layout {
        return switch (shape) {
            .integer => .{ .decl = self.integer, .takes_value_type = true },
            .float => .{ .decl = self.float, .takes_value_type = false },
            .general => .{ .decl = if (format.debug) self.debug else self.display, .takes_value_type = true },
        };
    }

    test "each shape lays out through its own function" {
        const layouts: LayoutDecls = .{ .display = DeclId.at(1), .debug = DeclId.at(2), .integer = DeclId.at(3), .float = DeclId.at(4) };
        const padded: node.InterpolationFormat = .{ .width = 4 };
        const debugged: node.InterpolationFormat = .{ .width = 4, .debug = true };
        try testing.expectEqual(DeclId.at(1), layouts.of(padded, .general).decl);
        try testing.expectEqual(DeclId.at(2), layouts.of(debugged, .general).decl);
        try testing.expectEqual(DeclId.at(3), layouts.of(debugged, .integer).decl);
        try testing.expectEqual(DeclId.at(4), layouts.of(padded, .float).decl);
        try testing.expect(layouts.of(padded, .integer).takes_value_type);
        try testing.expect(!layouts.of(padded, .float).takes_value_type);
    }
};

/// A Layout names the function that lays a value out and says how its type
/// arguments are formed.
pub const Layout = struct {
    decl: DeclId,
    /// This is true when the function's first type parameter is the value's
    /// type. The Float64 function has none, since its value's type is fixed.
    takes_value_type: bool,

    /// Form the function's type arguments: the value's type where it takes
    /// one, then the writer's, which are the rendering call's own arguments.
    pub fn arguments(self: Layout, gpa: std.mem.Allocator, value: TypeId, rendering: []const TypeId) std.mem.Allocator.Error![]TypeId {
        const first: usize = @intFromBool(self.takes_value_type);
        const out = try gpa.alloc(TypeId, first + rendering.len);
        if (self.takes_value_type) out[0] = value;
        @memcpy(out[first..], rendering);
        return out;
    }

    test "a layout's type arguments put the value's type before the writer's" {
        const gpa = testing.allocator;
        const generic: Layout = .{ .decl = DeclId.at(1), .takes_value_type = true };
        const with_value = try generic.arguments(gpa, .u8, &.{.i64});
        defer gpa.free(with_value);
        try testing.expectEqualSlices(TypeId, &.{ .u8, .i64 }, with_value);
        const fixed: Layout = .{ .decl = DeclId.at(2), .takes_value_type = false };
        const writer_only = try fixed.arguments(gpa, .f64, &.{.i64});
        defer gpa.free(writer_only);
        try testing.expectEqualSlices(TypeId, &.{.i64}, writer_only);
    }
};

// Makes every test build compile the tests `LayoutDecls`, `Layout` and
// `InstanceTable` hold, including a build filtered to one of them, which would
// otherwise never look inside them.
comptime {
    _ = LayoutDecls;
    _ = Layout;
    _ = InstanceTable;
}

pub fn generatedCall(program: *const ExpandedProgram, name: []const u8) DeclId {
    for (generated_calls.table) |call| {
        if (!std.mem.eql(u8, call.name, name)) continue;
        return program.libraryDeclIn(call.module, call.name) orelse DeclId.none;
    }
    return DeclId.none;
}

/// The raw-access declarations lowering replaces, found once per program.
///
/// Identity rather than spelling: a program may declare a function carrying
/// one of these names, and it remains an ordinary call. Finding the library's
/// declarations walks the modules before it reaches `std`, so doing that at
/// every call makes a program with one call per module pay their product.
pub const RawAccesses = @import("intrinsics.zig").RawAccesses;

fn internRoot(
    self: *Instantiation,
    program: *const ExpandedProgram,
    decl: DeclId,
    args: []const TypeId,
) !InstanceId {
    return (try self.builder.intern(
        .{ .body = .{ .declaration = decl }, .args = args, .self_ty = .poison },
        program,
        &self.pool,
    )).id;
}

fn seedDispatcher(
    self: *Instantiation,
    program: *const ExpandedProgram,
    resolution: *const Resolution,
    typing: *const Typing,
) !void {
    const selected = generatedCall(program, "selected");
    const ran = generatedCall(program, "ran");
    for (resolution.tests) |test_case| {
        if (selected != DeclId.none) _ = try internRoot(self, program, selected, &.{});
        _ = try internRoot(self, program, test_case.decl, &.{});

        const answer = typing.declReturn(test_case.decl);
        const bad = typing.failureVariantOf(answer) orelse continue;
        if (typing.variantFieldCount(answer, bad) == 0) continue;
        const held = typing.variantFieldType(answer, bad, 0);
        if (ran != DeclId.none) _ = try internRoot(self, program, ran, &.{held});
    }
    const no_such_test = generatedCall(program, "no_such_test");
    if (no_such_test != DeclId.none) _ = try internRoot(self, program, no_such_test, &.{});
}

fn discoverReporting(
    gpa: std.mem.Allocator,
    ast: *const Ast,
    program: *const ExpandedProgram,
    resolution: *const Resolution,
    typing: *const Typing,
    pool: *Typing.Builder,
    builder: *TableBuilder,
    from: InstanceId,
    disposals: *const DisposalPlan,
    sink: *Sink,
) !void {
    const key = builder.instances.items[from.index()].key;
    if (key.body == .closure_release) {
        const closure_type = key.body.closure_release;
        const metadata = pool.closure_release.?;
        const signature = try pool.internCallable(&.{.{ .spelling = "self", .convention = .sink, .ty = closure_type, .default = .absent }}, .unit, &.{}, .read);
        // A structural function value owns no field, so its release calls nothing.
        const closure = switch (pool.get(closure_type)) {
            .closure => |closure| closure,
            else => {
                try builder.release_plans.put(gpa, from, .{ .signature = signature, .calls = &.{} });
                return;
            },
        };
        const owned_fields = typing.closureOf(closure.closure).owned_fields;
        var calls: std.ArrayList(ClosureReleaseCall) = .empty;
        defer calls.deinit(gpa);
        var remaining = owned_fields.len;
        while (remaining != 0) {
            remaining -= 1;
            const field = owned_fields[remaining];
            const field_type = pool.view().fieldType(closure.environment, field.index());
            const choice = try pool.implementationChoice(metadata.trait, &.{}, field_type) orelse {
                const expr = typing.closureOf(closure.closure).expr;
                try reportMissingImplementation(gpa, sink, ast, pool, metadata.trait, &.{}, field_type, ast.fileOfExpr(expr), ast.exprSpan(expr));
                return;
            };
            const view = pool.view();
            const selected = selectedMember(ast, &view, choice, metadata.member) orelse
                @panic("compiler defect: releasable capture has no Release body");
            const target = try builder.intern(.{ .body = selected.body, .args = &.{}, .self_ty = selected.self_ty, .impl_args = selected.impl_args }, program, pool);
            try calls.append(gpa, .{ .field = field, .callee = target.id });
        }
        const recorded = try calls.toOwnedSlice(gpa);
        errdefer gpa.free(recorded);
        try builder.release_plans.put(gpa, from, .{ .signature = signature, .calls = recorded });
        return;
    }
    switch (key.body) {
        // The entry calls the stored callable. A closure's body is its own
        // instance; a function value is called through its address, which
        // names no body here.
        .erased_entry => |entry| {
            _ = try pool.closureEntrySignature(entry.signature);
            switch (pool.get(entry.callable)) {
                .closure => |closure| {
                    try pool.prepareClosureBodySignature(entry.callable);
                    _ = try builder.intern(closureKey(pool, closure), program, pool);
                },
                .callable => {},
                // Only a closure and a function value satisfy a callable bound.
                else => @panic("compiler defect: an erased closure stores a callable of no known kind"),
            }
            return;
        },
        // The release reads the stored callable out and releases it through
        // the supplier every closure and function value releases through.
        .erased_settle => |callable| {
            _ = try builder.intern(.{ .body = .{ .closure_release = callable }, .args = &.{}, .self_ty = .poison }, program, pool);
            return;
        },
        // A built-in operation calls nothing. Its signature is read through
        // its receiver here, while the pool may still grow, so lowering finds
        // it interned.
        .built_in => |built_in| {
            _ = try builtInSignature(ast, typing, pool, built_in);
            return;
        },
        // A viewed operation calls the slice's member, so that instance is
        // discovered with the signature the body is read through.
        .viewed => |viewed| {
            _ = try builtInSignature(ast, typing, pool, viewed);
            const choice = try pool.implementationChoice(viewed.trait, &.{}, viewed.receiver) orelse
                @panic("compiler defect: a viewed operation's receiver answers no implementation");
            const view = pool.view();
            const selected = selectedMember(ast, &view, choice, viewed.member) orelse
                @panic("compiler defect: a viewed operation's slice supplies no member");
            _ = try builder.intern(.{ .body = selected.body, .args = &.{}, .self_ty = selected.self_ty, .impl_args = selected.impl_args }, program, pool);
            return;
        },
        else => {},
    }
    const SourceBody = struct {
        decl: DeclId,
        body: ExprId,
        params: []const BindingId,
        returns: TypeId,
        signature: TypeId,
    };
    const source: SourceBody = switch (key.body) {
        .closure_release, .erased_entry, .erased_settle, .built_in, .viewed => unreachable,
        .declaration => |decl| .{
            .decl = decl,
            .body = ast.declBody(decl),
            .params = resolution.parametersOf(decl),
            .returns = typing.declReturn(decl),
            .signature = typing.declSignature(decl),
        },
        .closure => |closure| blk: {
            const descriptor = typing.closureOf(closure);
            const signature = typing.get(descriptor.signature).callable;
            break :blk .{
                .decl = descriptor.enclosing,
                .body = descriptor.body,
                .params = resolution.closureParameters(closure),
                .returns = signature.result,
                .signature = descriptor.signature,
            };
        },
        .constructor => |constructor| blk: {
            const value = typing.call_index.functionValueOf(typing, constructor.expr).?;
            break :blk .{
                .decl = constructor.enclosing,
                .body = .none,
                .params = &.{},
                .returns = typing.get(value.signature).callable.result,
                .signature = value.signature,
            };
        },
    };
    if (builder.formatting == null) builder.formatting = FormattingDecls.init(ast, resolution);
    if (builder.layouts == null) builder.layouts = LayoutDecls.init(program);

    const parameters = typecheck.bodyParametersOf(ast, resolution, typing, source.decl);
    const instance = try parameters.instantiation(gpa, key.body, source.decl, key.args, key.self_ty, key.impl_args);
    defer gpa.free(instance.args);

    var walk: Discovery = .{
        .gpa = gpa,
        .ast = ast,
        .program = program,
        .resolution = resolution,
        .typing = typing,
        .pool = pool,
        .table = builder,
        .calls = &typing.call_index,
        .raw_accesses = typing.raw_accesses,
        .formatting = builder.formatting.?,
        .layouts = builder.layouts.?,
        .sink = sink,
        .disposals = disposals,
        .instance = instance,
    };
    defer walk.splices.deinit(gpa);
    defer walk.active_projections.deinit(gpa);

    // Emission reads a concrete signature before it reaches the body. Settle
    // both halves here so the sealed pool already contains every handle the
    // function header names.
    _ = try walk.through(source.returns);
    _ = try walk.through(source.signature);
    if (key.body == .closure) {
        const descriptor = typing.closureOf(key.body.closure);
        const authored = typing.exprType(descriptor.expr);
        if (typing.get(authored) == .closure) {
            const concrete = try walk.through(authored);
            try pool.prepareClosureBodySignature(concrete);
        }
    }
    for (source.params) |parameter| {
        _ = try walk.through(typing.bindingType(parameter));
    }

    if (source.body != ExprId.none) try walk.expr(source.body);
}

const Discovery = struct {
    gpa: std.mem.Allocator,
    ast: *const Ast,
    program: *const ExpandedProgram,
    resolution: *const Resolution,
    typing: *const Typing,
    pool: *Typing.Builder,
    table: *TableBuilder,
    calls: *const CallIndex,
    raw_accesses: RawAccesses,
    formatting: FormattingDecls,
    layouts: LayoutDecls,
    sink: *Sink,
    instance: types_mod.Instantiation,
    disposals: *const DisposalPlan,
    placing: bool = false,
    splices: std.ArrayList(Splice) = .empty,
    projection_write: bool = false,
    projection_floor: usize = 0,
    active_projections: std.ArrayList(struct { member: DeclId, receiver: TypeId }) = .empty,

    const Splice = struct {
        binding: BindingId,
        wrote: ExprId,
        read: bool = false,
    };

    fn through(self: *Discovery, ty: TypeId) !TypeId {
        return self.instance.through(self.pool, ty);
    }

    fn schedulesAt(self: *Discovery, exit: ExprId) std.mem.Allocator.Error!void {
        if (self.placing) return;
        self.placing = true;
        defer self.placing = false;
        for (self.disposals.schedulesAt(exit)) |expression| try self.expr(expression);
    }

    fn block(self: *Discovery, id: ExprId) std.mem.Allocator.Error!void {
        const block_node = self.ast.blockOf(id);

        for (self.ast.blockStmts(block_node)) |stmt| {
            const data = self.ast.stmtData(stmt);
            switch (self.ast.stmtTag(stmt)) {
                .err => {},
                .defer_stmt, .defer_release => {},
                .let_decl, .let_destructure, .let_read_destructure, .expr_stmt => if (data.init != ExprId.none)
                    try self.expr(data.init),
            }
        }
        if (block_node.tail != ExprId.none) try self.expr(block_node.tail);
        try self.schedulesAt(id);
    }

    fn expr(self: *Discovery, id: ExprId) std.mem.Allocator.Error!void {
        if (id == ExprId.none) return;
        if (self.spliceAt(id)) |at| return self.readSplice(at);

        // Every reached expression is emitted at its concrete type. Settling
        // it is discovery work even where the expression contributes no call
        // key of its own.
        _ = try self.through(self.typing.exprType(id));

        // A checked constant contributes its retained value and concrete type,
        // with no calls or dependencies left to discover in its initializer.
        if (self.typing.constantValue(self.resolution.targetOf(id)) != null) return;

        if (self.calls.functionValueOf(self.typing, id)) |value| {
            switch (value.target) {
                .constructor => |constructor| {
                    _ = try self.table.intern(
                        .{ .body = .{ .constructor = constructor }, .args = self.instance.args, .self_ty = self.instance.self_ty, .impl_args = self.instance.impl_args },
                        self.program,
                        self.pool,
                    );
                },
                .closure => try self.closureReached(value.closure_type),
                .declared => |decl| {
                    const args = try self.gpa.alloc(TypeId, value.type_args.len);
                    defer self.gpa.free(args);
                    for (value.type_args, 0..) |arg, i| args[i] = try self.through(arg);
                    const body: SelectedMember = if (value.implementation) |record|
                        try self.implementedBody(decl, record, id, true) orelse return
                    else
                        .{ .body = .{ .declaration = decl }, .self_ty = .poison, .impl_args = &.{} };
                    // A generated body, such as a closure's release, takes no
                    // arguments of its own.
                    const own: []const TypeId = if (body.body == .declaration) args else &.{};
                    _ = try self.table.intern(
                        .{ .body = body.body, .args = own, .self_ty = body.self_ty, .impl_args = body.impl_args },
                        self.program,
                        self.pool,
                    );
                },
            }
            return;
        }

        const tag = self.ast.exprTag(id);
        switch (tag) {
            .err,
            .int_literal,
            .float_literal,
            .str_literal,
            .bool_literal,
            .unit_literal,
            .name_ref,
            .param_argument,
            .reflection_root,
            .struct_pattern,
            .tuple_pattern,
            => {},

            .lambda => for (self.ast.lambda(id).captures) |capture| try self.expr(capture.source),

            .block => try self.block(id),
            .conditional => {
                const c = self.ast.conditional(id);
                try self.expr(c.cond);
                try self.expr(c.then);
                if (c.otherwise != ExprId.none) try self.expr(c.otherwise);
            },
            .while_ => {
                const pair = self.ast.binary(id);
                try self.expr(pair.lhs);
                try self.expr(pair.rhs);
            },
            .loop_ => {
                try self.expr(self.ast.unaryOperand(id));
            },
            .return_ => {
                try self.expr(self.ast.unaryOperand(id));
                try self.schedulesAt(id);
                try self.entryReport();
            },
            .break_ => {
                try self.expr(self.ast.unaryOperand(id));
                try self.schedulesAt(id);
            },
            .try_ => {
                try self.expr(self.ast.unaryOperand(id));
                // The failing edge leaves the function before the success edge
                // resumes, which is the order lowering emits those blocks. A
                // converted error is built before the scheduled operations run,
                // as the operand of a `return` is.
                if (self.typing.try_conversions.get(id)) |conversion| try self.errorConversion(conversion, id);
                try self.schedulesAt(id);
                try self.entryReport();
            },
            .continue_ => {
                try self.schedulesAt(id);
            },

            .assign, .add_assign, .sub_assign, .mul_assign, .div_assign, .rem_assign => {
                const pair = self.ast.binary(id);
                try self.expr(pair.rhs);
                try self.expr(pair.lhs);
            },
            .add,
            .sub,
            .mul,
            .div,
            .rem,
            .logical_and,
            .logical_or,
            => {
                const pair = self.ast.binary(id);
                try self.expr(pair.lhs);
                try self.expr(pair.rhs);
            },
            .index => if (self.calls.projectionOf(self.typing, id)) |found|
                try self.projected(id, found)
            else {
                const pair = self.ast.binary(id);
                try self.expr(pair.lhs);
                const write = self.projection_write;
                self.projection_write = false;
                defer self.projection_write = write;
                try self.expr(pair.rhs);
            },
            .eq, .ne, .lt, .le, .gt, .ge => {
                const pair = self.ast.binary(id);
                try self.expr(pair.lhs);
                try self.expr(pair.rhs);
                try self.comparison(id, tag, pair.lhs);
            },
            .range => {
                const ends = self.ast.rangeEnds(id);
                try self.expr(ends.lhs);
                try self.expr(ends.rhs);
            },
            .grouped, .negate, .not, .marked, .field, .dereference, .copy_, .borrow, .panic, .from_end => try self.expr(self.ast.unaryOperand(id)),
            .variant_ref => {},

            .interp => for (self.ast.interpolation(id).pieces) |part| try self.expr(part),
            .array_literal, .tuple_literal => for (self.ast.call(id).args) |part| try self.expr(part),
            .struct_literal => {
                const fields = self.ast.call(id).args;
                var i: usize = 1;
                while (i < fields.len) : (i += 2) try self.expr(fields[i]);
                if (self.ast.structLiteralBase(id)) |base| try self.expr(base);
            },
            .unwrap_else => {
                const u = self.ast.unwrapElse(id);
                try self.expr(u.operand);
                try self.expr(u.body);
            },
            .match_, .match_read => {
                const match = self.ast.call(id);
                try self.expr(match.callee);
                var i: usize = 1;
                while (i < match.args.len) : (i += 2) try self.expr(match.args[i]);
            },
            .for_, .for_read, .for_inout => {
                const loop = self.ast.call(id);
                try self.walkFor(id, tag, loop.callee);
                if (loop.args.len > 1) try self.expr(loop.args[1]);
            },
            .call => try self.call(id),
        }
    }

    fn spliceAt(self: *const Discovery, id: ExprId) ?usize {
        if (self.splices.items.len == 0) return null;
        const at = self.ast.withoutGroups(id);
        if (self.ast.exprTag(at) != .name_ref) return null;
        const target = self.resolution.targetOf(at);
        if (target == BindingId.none) return null;

        var i = self.splices.items.len;
        while (i > 0) {
            i -= 1;
            if (self.splices.items[i].binding == target) return i;
        }
        return null;
    }

    fn readSplice(self: *Discovery, at: usize) std.mem.Allocator.Error!void {
        if (self.splices.items[at].read) return;
        self.splices.items[at].read = true;
        const wrote = self.splices.items[at].wrote;
        if (wrote != ExprId.none) try self.projectionOperand(wrote);
    }

    /// Site operands are evaluated outside the projection path they fill.
    fn projectionOperand(self: *Discovery, at: ExprId) std.mem.Allocator.Error!void {
        const floor = self.projection_floor;
        const write = self.projection_write;
        self.projection_floor = self.active_projections.items.len;
        self.projection_write = false;
        defer {
            self.projection_floor = floor;
            self.projection_write = write;
        }
        try self.expr(at);
    }

    fn projected(self: *Discovery, id: ExprId, found: types_mod.Expansion) std.mem.Allocator.Error!void {
        const pair = self.ast.binary(id);
        const receiver = try self.through(self.typing.exprType(pair.lhs));
        try self.splicedPath(found, pair.lhs, pair.rhs, receiver);
    }

    /// Walks the path a routed bracket becomes. Its two site expressions are
    /// slots: each runs where the path first names it, and an unused one runs
    /// after the path, in receiver/index order. That is lowering's splice
    /// order, including through composed projections.
    fn splicedPath(
        self: *Discovery,
        found: types_mod.Expansion,
        receiver: ExprId,
        index: ExprId,
        receiver_ty: TypeId,
    ) std.mem.Allocator.Error!void {
        const writable = self.projection_write or found.requires_write;
        if (writable and !found.writable) {
            try self.sink.addError(.n_immutable, self.ast.fileOf(self.ast.declName(found.member)), self.ast.declSpan(found.member), "an indexed write reaches a read-only projection", "the concrete backing implementation must permit mutation");
            return;
        }
        const direct_bound = if (found.delegation) |forward| forward.field == null else false;
        if (!direct_bound) for (self.active_projections.items[self.projection_floor..]) |active| {
            if (active.member == found.member and active.receiver == receiver_ty) {
                try self.sink.addError(.t_projection, self.ast.fileOf(self.ast.declName(found.member)), self.ast.declSpan(found.member), "a concrete delegated projection reaches itself", "break the projection cycle");
                return;
            }
        };
        if (!direct_bound) try self.active_projections.append(self.gpa, .{ .member = found.member, .receiver = receiver_ty });
        defer if (!direct_bound) {
            _ = self.active_projections.pop();
        };
        const previous_write = self.projection_write;
        self.projection_write = writable;
        defer self.projection_write = previous_write;
        if (found.delegation) |delegation| {
            if (receiver != .none) try self.projectionOperand(receiver);
            if (index != .none) try self.projectionOperand(index);
            if (delegation.deferred_trait) |trait| {
                const bound = try self.gpa.alloc(TypeId, found.impl_args.len);
                defer self.gpa.free(bound);
                for (found.impl_args, bound) |written, *settled| settled.* = try self.through(written);
                const key = if (delegation.field == null) try self.through(delegation.key_type) else try self.pool.substitute(delegation.key_type, found.member.index(), bound);
                const field_ty = if (delegation.field) |field| self.pool.view().fieldType(receiver_ty, field) else receiver_ty;
                if (try self.pool.projectionFor(self.typing, trait, key, field_ty)) |backing|
                    try self.splicedPath(backing, .none, .none, field_ty);
            } else if (delegation.backing) |row| {
                const bound = try self.gpa.alloc(TypeId, found.impl_args.len);
                defer self.gpa.free(bound);
                for (found.impl_args, bound) |written, *settled| settled.* = try self.through(written);
                const args = try self.gpa.alloc(TypeId, delegation.backing_args.len);
                defer self.gpa.free(args);
                for (delegation.backing_args, args) |written, *settled|
                    settled.* = try self.pool.substitute(written, found.member.index(), bound);
                var backing = self.typing.expansions[row];
                backing.impl_args = args;
                const field_ty = if (delegation.field) |field| self.pool.view().fieldType(receiver_ty, field) else receiver_ty;
                try self.splicedPath(backing, .none, .none, field_ty);
            }
            return;
        }
        const mark = self.splices.items.len;
        defer self.splices.shrinkRetainingCapacity(mark);

        try self.splices.append(self.gpa, .{
            .binding = BindingId.at(found.receiver),
            .wrote = receiver,
        });
        if (found.index != types_mod.Expansion.no_binding) {
            try self.splices.append(self.gpa, .{
                .binding = BindingId.at(found.index),
                .wrote = index,
            });
        }

        const bound = try self.gpa.alloc(TypeId, found.impl_args.len);
        defer self.gpa.free(bound);
        for (found.impl_args, bound) |written, *settled| settled.* = try self.through(written);
        const member_instance = try typecheck.bodyParametersOf(self.ast, self.resolution, self.typing, found.member).splicedAt(self.gpa, found.member, receiver_ty, bound);
        defer self.gpa.free(member_instance.args);

        const saved = self.instance;
        {
            self.instance = member_instance;
            defer self.instance = saved;
            try self.expr(found.path);
        }

        var at = mark;
        while (at < self.splices.items.len) : (at += 1) try self.readSplice(at);
    }

    /// Interns the closure instance a value of `written` runs as, read at this
    /// instance; a value of any other callable type names no body here.
    fn closureReached(self: *Discovery, written: TypeId) std.mem.Allocator.Error!void {
        const concrete = try self.through(written);
        switch (self.pool.get(concrete)) {
            .closure => |closure| _ = try self.table.intern(closureKey(self.pool, closure), self.program, self.pool),
            else => {},
        }
    }

    fn call(self: *Discovery, id: ExprId) std.mem.Allocator.Error!void {
        const call_node = self.ast.call(id);
        const normal = self.calls.callOf(self.typing, id) orelse {
            for (call_node.args) |arg| try self.expr(arg);
            return;
        };
        if (normal.target.calleeIsValue()) try self.expr(call_node.callee);
        for (normal.args) |arg| {
            if (arg != ExprId.none) try self.expr(arg);
        }

        const named = switch (normal.target) {
            .closure_recovery, .array_view, .array_length => return,
            .declared => |decl| decl,
            .closure => return self.closureReached(self.typing.exprType(call_node.callee)),
            // A callable typed by a generic parameter reaches the closure body
            // that parameter settles to; any other callable is called
            // indirectly and names no body.
            .generic_callable => |parameter| return self.closureReached(parameter),
            .indirect, .erased => return,
        };
        if (try self.renderedInterpolation(id, named)) return;

        var decl = named;
        var held = TypeId.poison;
        var impl_args: []const TypeId = &.{};
        if (normal.selection.implementation) |record| {
            const body = try self.implementedBody(named, record, id, false) orelse return;
            switch (body.body) {
                .declaration => |member| decl = member,
                else => {
                    _ = try self.table.intern(.{ .body = body.body, .args = &.{}, .self_ty = .poison }, self.program, self.pool);
                    return;
                },
            }
            held = body.self_ty;
            impl_args = body.impl_args;
        }

        // The raw access declarations are compiler intrinsics. Lowering
        // replaces their calls with checked accesses before asking `Mono` for
        // an id, so they contribute no instance to the ordered set.
        if (self.raw_accesses.processText(decl)) |source| {
            for ([_]DeclId{ source.count, source.at, source.len }) |runtime_decl| {
                if (runtime_decl == .none) continue;
                _ = try self.table.intern(.{ .body = .{ .declaration = runtime_decl }, .args = &.{}, .self_ty = .poison }, self.program, self.pool);
            }
        }
        // An erased closure's entry and release are bodies this compiler
        // generates for the callable type the call settled.
        if (decl == self.raw_accesses.closure_entry or decl == self.raw_accesses.closure_settle) {
            const recorded_args = normal.selection.own_args;
            const settled = try self.gpa.alloc(TypeId, recorded_args.len);
            defer self.gpa.free(settled);
            for (recorded_args, 0..) |arg, i| settled[i] = try self.through(arg);
            const body = self.raw_accesses.erasedBody(decl, settled).?;
            _ = try self.table.intern(.{ .body = body, .args = &.{}, .self_ty = .poison }, self.program, self.pool);
            return;
        }
        if (self.raw_accesses.contains(decl) or self.typing.float_math.operationOf(decl) != null) return;
        if (self.ast.declBody(decl) == ExprId.none and !self.ast.declIsExtern(decl)) return;
        const recorded = normal.selection.own_args;
        const args = try self.gpa.alloc(TypeId, recorded.len);
        defer self.gpa.free(args);
        for (recorded, 0..) |arg, i| args[i] = try self.through(arg);
        _ = try self.table.intern(
            .{ .body = .{ .declaration = decl }, .args = args, .self_ty = held, .impl_args = impl_args },
            self.program,
            self.pool,
        );
    }

    /// The body a call or a function value naming `named` reaches through
    /// what the checker recorded for its head: the member of an inherent
    /// implementation at a concrete receiver, or the implementing member a
    /// trait's operation selects. Null where no body is reached, which a
    /// missing implementation reports. A call to an operation the compiler
    /// provides is lowered as that operation; a function value reaching one
    /// has nothing to hold, and `value` reports it.
    fn implementedBody(self: *Discovery, named: DeclId, record: types_mod.CallImpl, at: ExprId, value: bool) std.mem.Allocator.Error!?SelectedMember {
        const receiver = try self.through(record.self_ty);
        if (!record.ofATrait()) {
            const head = try inherentHead(self.ast, self.typing, named, receiver, PoolArguments{ .pool = self.pool }) orelse return null;
            return .{ .body = .{ .declaration = named }, .self_ty = head.held, .impl_args = head.impl_args };
        }
        const args = try self.gpa.alloc(TypeId, record.args.len);
        defer self.gpa.free(args);
        for (record.args, 0..) |arg, i| args[i] = try self.through(arg);
        const choice = try self.pool.implementationChoice(DeclId.at(record.trait), args, receiver) orelse {
            try self.missingImplementation(DeclId.at(record.trait), args, receiver, at);
            return null;
        };
        const view = self.pool.view();
        const found = if (value) valueMember(self.ast, &view, choice, DeclId.at(record.trait), named) else selectedMember(self.ast, &view, choice, named);
        return found orelse {
            if (value) try reportBodilessOperation(self.sink, self.ast.fileOfExpr(at), self.ast.exprSpan(at), self.ast.tokenText(self.ast.declName(named)), view.nameOf(receiver));
            return null;
        };
    }

    fn missingImplementation(
        self: *Discovery,
        trait: DeclId,
        args: []const TypeId,
        held: TypeId,
        at: ExprId,
    ) std.mem.Allocator.Error!void {
        const sink = self.sink;
        try reportMissingImplementation(
            self.gpa,
            sink,
            self.ast,
            self.pool,
            trait,
            args,
            held,
            self.ast.fileOfExpr(at),
            self.ast.exprSpan(at),
        );
    }

    /// The generated reporting call on one early edge out of a Result-returning
    /// entry point. Lowering emits it at each `?` and written `return`; the
    /// interner makes later edges lookups, but the first edge fixes its place
    /// in the ordered set.
    fn entryReport(self: *Discovery) std.mem.Allocator.Error!void {
        if (self.instance.decl != self.resolution.entry) return;
        const answer = try self.through(self.typing.declReturn(self.instance.decl));
        const view = self.pool.view();
        const bad = view.failureVariantOf(answer) orelse return;
        if (view.variantFieldCount(answer, bad) == 0) return;
        const held = view.variantFieldType(answer, bad, 0);
        const report = generatedCall(self.program, "report");
        if (report == DeclId.none) return;
        _ = try self.table.intern(
            .{ .body = .{ .declaration = report }, .args = &.{held}, .self_ty = .poison },
            self.program,
            self.pool,
        );
    }

    fn renderedInterpolation(self: *Discovery, id: ExprId, signature: DeclId) std.mem.Allocator.Error!bool {
        const normal = self.calls.callOf(self.typing, id) orelse return false;
        const record = normal.selection.implementation orelse return false;
        if (!record.ofATrait() or signature != (self.formatting.display.member orelse return false)) return false;

        const held = try self.through(record.self_ty);
        {
            const view = self.pool.view();
            if (!rendersDisplayItself(&view, self.formatting.display.trait, held, DeclId.at(record.trait))) return false;
        }

        const recorded = normal.selection.own_args;
        const settled = try self.gpa.alloc(TypeId, recorded.len);
        defer self.gpa.free(settled);
        for (recorded, 0..) |arg, i| settled[i] = try self.through(arg);

        try self.renderedPieces(held, settled, id);
        return true;
    }

    /// Discover what renders each piece of the interpolation `held` for a
    /// writer settled to `settled`. A piece that is itself an interpolation
    /// rendered through `Display` has no implementation to reach; its own
    /// pieces are discovered instead, so a literal may hold another one.
    /// The recursion is as deep as the literals are nested in source.
    fn renderedPieces(self: *Discovery, held: TypeId, settled: []const TypeId, id: ExprId) std.mem.Allocator.Error!void {
        const pieces = self.pool.view().fieldCount(held);
        var i: u32 = 0;
        while (i < pieces) : (i += 1) {
            const piece = self.pool.view().interpolationValue(held, i);
            if (i % 2 == 1) {
                const format = self.pool.interpolationFormats(held)[i / 2];
                if (format.laysOut()) {
                    const layout = self.layouts.of(format, self.pool.view().layoutShape(DeclId.none, piece));
                    if (layout.decl == DeclId.none) continue;
                    const args = try layout.arguments(self.gpa, piece, settled);
                    defer self.gpa.free(args);
                    _ = try self.table.intern(
                        .{ .body = .{ .declaration = layout.decl }, .args = args, .self_ty = .poison },
                        self.program,
                        self.pool,
                    );
                    continue;
                }
            }
            const target = if (i % 2 == 0)
                self.formatting.display
            else
                self.formatting.target(self.pool.interpolationFormats(held)[i / 2]);
            const trait = target.trait orelse continue;
            const signature_for_piece = target.member orelse continue;
            {
                const view = self.pool.view();
                if (rendersDisplayItself(&view, self.formatting.display.trait, piece, trait)) {
                    try self.renderedPieces(piece, settled, id);
                    continue;
                }
            }
            const row = try self.pool.implementationRow(trait, &.{}, piece) orelse {
                try self.missingImplementation(trait, &.{}, piece, id);
                continue;
            };
            const implementation = row.decl;
            const member = self.typing.supply_index.memberOf(implementation, signature_for_piece) orelse continue;
            const choice = self.pool.implementation_selections.choiceOf(trait, &.{}, piece).?;
            const receiver = receiverKeying(self.ast, implementation, choice.implementedFor());
            _ = try self.table.intern(
                .{ .body = .{ .declaration = member }, .args = settled, .self_ty = receiver, .impl_args = choice.impl_args },
                self.program,
                self.pool,
            );
        }
    }

    const Implemented = struct {
        row: types_mod.Implementation,
        member: DeclId,
        held: TypeId,
        impl_args: []const TypeId,
    };

    fn implemented(
        self: *Discovery,
        trait: ?DeclId,
        member: ?DeclId,
        args: []const TypeId,
        held: TypeId,
        at: ExprId,
    ) std.mem.Allocator.Error!?Implemented {
        const declared = trait orelse return null;
        const signature = member orelse return null;
        const row = try self.pool.implementationRow(declared, args, held) orelse {
            try self.missingImplementation(declared, args, held, at);
            return null;
        };
        if (row.isAmbient()) return null;
        const choice = self.pool.implementation_selections.choiceOf(declared, args, held).?;
        return .{
            .row = row,
            .member = self.typing.supply_index.memberOf(row.decl, signature) orelse return null,
            .held = receiverKeying(self.ast, row.decl, choice.implementedFor()),
            .impl_args = choice.impl_args,
        };
    }

    /// The `From` implementation a converting `?` calls in this instance.
    fn errorConversion(self: *Discovery, conversion: types_mod.TryConversion, at: ExprId) std.mem.Allocator.Error!void {
        const source = try self.through(conversion.source);
        const target = try self.through(conversion.target);
        if (try self.implemented(conversion.trait, conversion.member, &.{source}, target, at)) |found|
            try self.internImplemented(found);
    }

    fn internImplemented(self: *Discovery, found: Implemented) std.mem.Allocator.Error!void {
        _ = try self.table.intern(
            .{ .body = .{ .declaration = found.member }, .args = &.{}, .self_ty = found.held, .impl_args = found.impl_args },
            self.program,
            self.pool,
        );
    }

    fn comparison(self: *Discovery, id: ExprId, tag: node.Expr.Tag, lhs: ExprId) std.mem.Allocator.Error!void {
        const operand = try self.through(self.typing.exprType(lhs));
        const equality = equatableDecl(self.ast, self.resolution);
        const comparable = comparableDecl(self.ast, self.resolution);
        const equals = traitMemberNamed(self.ast, self.resolution, equality, "equals");
        const less = traitMemberNamed(self.ast, self.resolution, comparable, "less");

        switch (tag) {
            .eq, .ne => if (try self.implemented(equality, equals, &.{}, operand, id)) |found|
                try self.internImplemented(found),
            .lt, .gt => if (try self.implemented(comparable, less, &.{}, operand, id)) |found|
                try self.internImplemented(found),
            .le, .ge => {
                if (try self.implemented(comparable, less, &.{}, operand, id)) |found|
                    try self.internImplemented(found);
                if (try self.implemented(equality, equals, &.{}, operand, id)) |equal|
                    try self.internImplemented(equal);
            },
            else => unreachable,
        }
    }

    fn walkFor(self: *Discovery, id: ExprId, tag: node.Expr.Tag, head: ExprId) std.mem.Allocator.Error!void {
        const walked = try self.through(self.typing.exprType(head));
        try self.expr(head);

        switch (self.pool.view().get(walked)) {
            // A walk whose head diverges never asks what it yields.
            .array, .never => return,
            else => {},
        }

        const iterator = iteratorDecl(self.ast, self.resolution);
        const next = traitMemberNamed(self.ast, self.resolution, iterator, "next");
        // `for x in &it` advances the iterator itself, so only its `next` is
        // reached.
        if (tag == .for_ and self.ast.exprTag(head) == .marked) {
            if (try self.implemented(iterator, next, &.{}, walked, id)) |steps|
                try self.internImplemented(steps);
            return;
        }
        if (tag == .for_) {
            const sequence = sequenceDecl(self.ast, self.resolution);
            const iterate = traitMemberNamed(self.ast, self.resolution, sequence, "iterate");
            const begins = (try self.implemented(sequence, iterate, &.{}, walked, id)) orelse return;
            try self.internImplemented(begins);
            const positions = try self.pool.settledBy(begins.row, iterate orelse return, begins.impl_args) orelse return;
            if (try self.implemented(iterator, next, &.{}, positions, id)) |steps|
                try self.internImplemented(steps);
            return;
        }

        const plan = self.calls.traversalPlan(self.typing, id) orelse return;
        const traversal = plan.decl;
        const recorded = plan.impl_args;
        const bound = try self.gpa.alloc(TypeId, recorded.len);
        defer self.gpa.free(bound);
        for (recorded, bound) |written, *settled| settled.* = try self.through(written);
        const member_instance = try typecheck.bodyParametersOf(self.ast, self.resolution, self.typing, traversal).splicedAt(self.gpa, traversal, walked, bound);
        defer self.gpa.free(member_instance.args);

        const positions = position: {
            const saved = self.instance;
            self.instance = member_instance;
            defer self.instance = saved;
            switch (plan.positions) {
                .expression => |init| {
                    const ty = try self.through(self.typing.exprType(init));
                    try self.expr(init);
                    break :position ty;
                },
                .array => |array| break :position try self.through(array.iterator),
            }
        };

        if (positions != .poison) {
            if (try self.implemented(iterator, next, &.{}, positions, id)) |steps|
                try self.internImplemented(steps);
        }

        if (self.calls.projectionOf(self.typing, id)) |found| {
            try self.splicedPath(found, ExprId.none, ExprId.none, walked);
        }
    }
};

test "duplicate generic requests retain one symbol without allocating" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    const source: @import("../support/source.zig").Source = .{ .path = "instances.lin", .text =
        \\@copyable
        \\type Quantity = UInt8
        \\fn identity[T: Copyable](value: T) -> T { copy(value) }
        \\struct Holder[T] { value: T }
        \\impl[T: Copyable] Holder[T] { fn get(self: Self) -> T { copy(self.value) } }
        \\fn main() -> UInt8 {
        \\    let value = Quantity(7)
        \\    let _ = identity(value)
        \\    let _ = identity(value)
        \\    let _ = identity(true)
        \\    let a: Holder[UInt8] = .{ value = 7 }
        \\    let b: Holder[Bool] = .{ value = true }
        \\    let _ = a.get()
        \\    let _ = a.get()
        \\    let _ = b.get()
        \\    0
        \\}
    };
    var interner: @import("../support/interner.zig").Interner = .empty;
    var sink = Sink.init(gpa);
    const tokens = try @import("../lexer/lexer.zig").tokenize(gpa, &source, .from(0), &sink, &interner);
    var ast = try @import("../parser/parser.zig").parse(gpa, &source, .from(0), tokens, &sink);
    var resolved = try @import("resolve.zig").resolveTree(gpa, &ast, &sink);
    var typing = try typecheck.typecheckTree(gpa, &resolved, &sink);
    var disposals = try @import("../ownership/check.zig").checkTree(gpa, &resolved, &typing, &sink);
    defer disposals.deinit(gpa);
    var instances = try instantiate(gpa, &resolved.expanded, &resolved.resolution, &typing, &disposals, &sink, .program);
    defer instances.deinit();
    try testing.expectEqual(@as(u32, 0), sink.error_count);
    const table = instances.table();
    try testing.expectEqual(@as(u32, 5), table.count());
    const first = table.get(.at(1));
    const other = table.get(.at(2));
    try testing.expectEqual(first.key.body.declaration, other.key.body.declaration);
    try testing.expect(!std.mem.eql(TypeId, first.key.args, other.key.args));
    try testing.expect(!std.mem.eql(u8, first.name, other.name));
    try testing.expectEqual(InstanceId.at(1), table.lookup(first.key.body.declaration, first.key.args, first.key.self_ty, first.key.impl_args).?);
    try testing.expectEqual(@as(?InstanceId, null), table.lookup(.none, first.key.args, first.key.self_ty, first.key.impl_args));

    const receiver_a = table.get(.at(3));
    const receiver_b = table.get(.at(4));
    try testing.expectEqual(receiver_a.key.body.declaration, receiver_b.key.body.declaration);
    try testing.expect(receiver_a.key.self_ty != receiver_b.key.self_ty);
    try testing.expect(!std.mem.eql(u8, receiver_a.name, receiver_b.name));
    try testing.expectEqual(InstanceId.at(3), table.lookup(receiver_a.key.body.declaration, receiver_a.key.args, receiver_a.key.self_ty, receiver_a.key.impl_args).?);

    // An existing identity and its retained symbol survive when no further
    // allocation is available, including after discovery seals its type pool.
    var failing = testing.FailingAllocator.init(gpa, .{ .fail_index = 0 });
    instances.builder.gpa = failing.allocator();
    defer instances.builder.gpa = gpa;
    const duplicate = try instances.builder.intern(
        first.key,
        &resolved.expanded,
        &instances.pool,
    );
    try testing.expect(!duplicate.fresh);
    try testing.expectEqual(InstanceId.at(1), duplicate.id);
    try testing.expectEqual(first.name.ptr, instances.table().get(duplicate.id).name.ptr);
    try testing.expectEqual(@as(u32, 5), instances.table().count());
}

test "cached raw access identities exclude unrelated declarations" {
    const accesses: RawAccesses = .{
        .store = DeclId.at(1),
        .load = DeclId.at(2),
        .store8 = DeclId.at(3),
        .load8 = DeclId.at(4),
    };

    for ([_]DeclId{
        DeclId.at(1),
        DeclId.at(2),
        DeclId.at(3),
        DeclId.at(4),
    }) |intrinsic| try testing.expect(accesses.contains(intrinsic));
    try testing.expect(!accesses.contains(DeclId.at(6)));
    try testing.expect(!accesses.contains(DeclId.none));
}

test "discovery hands off concrete implementation selections without another lookup" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    const source: @import("../support/source.zig").Source = .{ .path = "selection.lin", .text =
        \\struct Meter {}
        \\trait Value { fn value(self: Self) -> UInt8 }
        \\impl Value for Meter { fn value(_self: Self) -> UInt8 { 7 } }
        \\fn main() -> UInt8 {
        \\    let meter: Meter = .{}
        \\    meter.value()
        \\}
    };
    var interner: @import("../support/interner.zig").Interner = .empty;
    var sink = Sink.init(gpa);
    const tokens = try @import("../lexer/lexer.zig").tokenize(gpa, &source, .from(0), &sink, &interner);
    var ast = try @import("../parser/parser.zig").parse(gpa, &source, .from(0), tokens, &sink);
    var resolved = try @import("resolve.zig").resolveTree(gpa, &ast, &sink);
    var typing = try typecheck.typecheckTree(gpa, &resolved, &sink);
    var disposals = try @import("../ownership/check.zig").checkTree(gpa, &resolved, &typing, &sink);
    defer disposals.deinit(gpa);
    var without_search = typing;
    without_search.impl_index.chained.heads.restart();
    var instances = try instantiate(gpa, &resolved.expanded, &resolved.resolution, &without_search, &disposals, &sink, .program);
    defer instances.deinit();
    try testing.expectEqual(@as(u32, 0), sink.error_count);

    const table = instances.table();
    var checked = false;
    for (typing.implementations) |implementation| {
        if (implementation.isAmbient() or implementation.trait == types_mod.Implementation.no_trait) continue;
        const selected = table.selectedImplementation(DeclId.at(implementation.trait), &.{}, implementation.ty).?;
        try testing.expectEqual(implementation.decl, selected.decl);
        checked = true;
    }
    try testing.expect(checked);

    // Keep the implementation rows, but make their search index answer no
    // queries. Emission must consume discovery's selections without solving.
    var module = try @import("../mir/lower.zig").lower(gpa, &resolved.expanded, &resolved.resolution, &without_search, &instances, &disposals, &sink, .program);
    defer module.deinit(gpa);
    try testing.expectEqual(@as(u32, 0), sink.error_count);
    try testing.expectEqual(@as(usize, 2), module.functions.len);
}

test "an inherent head is keyed by the enclosing implementation, and a member outside one has none" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    const source: @import("../support/source.zig").Source = .{ .path = "head.lin", .text =
        \\struct Meter {}
        \\struct Holder[T] { value: T }
        \\impl Meter { fn read(_self: Self) -> UInt8 { 7 } }
        \\impl[T] Holder[T] { fn first(_self: Self) -> UInt8 { 1 } }
        \\fn plain() -> UInt8 { 3 }
        \\fn main() -> UInt8 { plain() }
    };
    var interner: @import("../support/interner.zig").Interner = .empty;
    var sink = Sink.init(gpa);
    const tokens = try @import("../lexer/lexer.zig").tokenize(gpa, &source, .from(0), &sink, &interner);
    var ast = try @import("../parser/parser.zig").parse(gpa, &source, .from(0), tokens, &sink);
    var resolved = try @import("resolve.zig").resolveTree(gpa, &ast, &sink);
    var typing = try typecheck.typecheckTree(gpa, &resolved, &sink);
    // Every implementation applies to every receiver, so the answer under test
    // is the one `inherentHead` itself gives.
    const Applies = struct {
        fn of(_: @This(), _: types_mod.ImplementationId, _: TypeId) error{}!?[]const TypeId {
            return &.{};
        }
    };
    const ast_view = &ast;
    var found_read = false;
    var found_first = false;
    var found_plain = false;
    for (0..ast_view.declCount()) |index| {
        const decl = DeclId.at(@intCast(index));
        if (ast_view.declTag(decl) != .function) continue;
        const name = ast_view.tokenText(ast_view.declName(decl));
        const head = try inherentHead(ast_view, &typing, decl, .u8, Applies{});
        if (std.mem.eql(u8, name, "read")) {
            found_read = true;
            // A concrete implementation names its receiver itself.
            try testing.expectEqual(TypeId.poison, head.?.held);
        } else if (std.mem.eql(u8, name, "first")) {
            found_first = true;
            // A generic one needs the receiver in the key.
            try testing.expectEqual(TypeId.u8, head.?.held);
        } else if (std.mem.eql(u8, name, "plain")) {
            found_plain = true;
            try testing.expect(head == null);
        }
    }
    try testing.expect(found_read and found_first and found_plain);
}
