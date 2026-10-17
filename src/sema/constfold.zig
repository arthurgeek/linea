const std = @import("std");
pub const constants = @import("constants.zig");
pub const ConstantId = constants.ConstantId;
const testing = std.testing;

const node = @import("../syntax/node.zig");
const Ast = @import("../syntax/ast.zig").Ast;
const ExprId = node.ExprId;
const DeclId = node.DeclId;
const StmtId = node.StmtId;
const Source = @import("../support/source.zig").Source;
const Sink = @import("../diagnostics/sink.zig").Sink;
const Interner = @import("../support/interner.zig").Interner;
const StringId = @import("../support/interner.zig").StringId;
const tokenize = @import("../lexer/lexer.zig").tokenize;
const parse = @import("../parser/parser.zig").parse;

/// Where a name written inside a constant expression was declared.
///
/// The two places a binding is written, because those are the two that hold an
/// initialiser: a module's or an `impl`'s constant is a declaration, and a
/// block's binding is a statement. `nothing` covers every other answer,
/// including a name nobody resolved -- what is worth folding is decided here
/// and never by how much a caller managed to look up.
pub const Reach = union(enum) {
    nothing,
    decl: DeclId,
    stmt: StmtId,

    /// The row a site is memoised under. The two spaces are dense and separate,
    /// so the tag rides above the index rather than the two being mixed.
    fn key(self: Reach) u64 {
        return switch (self) {
            .nothing => 0,
            .decl => |d| (@as(u64, 1) << 32) | @intFromEnum(d),
            .stmt => |s| (@as(u64, 2) << 32) | @intFromEnum(s),
        };
    }
};

/// The values a conversion's target can hold.
///
/// A pair of numbers rather than a type, because folding is over the tree: what
/// a written name means is the caller's to answer, and this is the whole of
/// what the answer has to say for a conversion to be worth something.
pub const Range = struct { min: i128, max: i128 };

/// The postfix call that reports an array's length. Its value is the count
/// of the constant array it is called on.
pub const array_length_name = "length";

/// What a call written on a callee does to its operand, where the call is one
/// a constant expression may contain.
pub const ConstantCall = union(enum) {
    /// A primitive conversion, whose value is the operand's where the target
    /// can hold it.
    into: Range,
    /// A newtype's construction, whose value is the operand's. Whether a
    /// refinement admits that value is decided where the construction is
    /// type checked, since the refinement is a property of the checked type.
    construction,
};

/// What folding needs from a pass and the tree does not hold.
///
/// Names supply declaration identity, constant calls, and concrete integer
/// properties. The checker reads finished resolution; the resolver reads the
/// bindings and property selections it is still filling. Evaluation is shared
/// here so both passes use the same constant-expression rules.
pub const Names = struct {
    ctx: *const anyopaque,
    reaches: *const fn (ctx: *const anyopaque, id: ExprId) Reach,
    /// What a call written at this callee does to its operand, or `null`
    /// where the name heads neither a primitive conversion nor a newtype
    /// construction. A conversion's range is read from the one table that says
    /// what a type holds, so a width added there is admitted here without this
    /// knowing what a type is.
    constant_call: *const fn (ctx: *const anyopaque, ast: *const Ast, callee: ExprId) ?ConstantCall,
    /// A compiler-owned integer property already classified by name resolution.
    integer_property: *const fn (ctx: *const anyopaque, expression: ExprId) ?i128,
    /// Whether an expression is a qualified variant selection, which folds to
    /// the variant named by its member.
    variant: *const fn (ctx: *const anyopaque, expression: ExprId) bool,
    /// The field the tuple declaration of `arity` components names its
    /// component at `position`, or `null` where no declaration of that arity
    /// is published. A tuple literal folds to the record its long form folds
    /// to, so a constant read by position and one read by field name are one
    /// value.
    tuple_component: *const fn (ctx: *const anyopaque, ast: *const Ast, arity: usize, position: usize) ?[]const u8,
    /// The bytes an `embed` or `embed_bytes` read, or `null` where the loader
    /// refused it. A refused embed is still a constant expression, one whose
    /// value does not exist, so the refusal is reported once.
    embedded: *const fn (ctx: *const anyopaque, expression: ExprId) ?[]const u8,

    fn of(self: Names, id: ExprId) Reach {
        return self.reaches(self.ctx, id);
    }

    fn tupleComponentAt(self: Names, ast: *const Ast, arity: usize, position: usize) ?[]const u8 {
        return self.tuple_component(self.ctx, ast, arity, position);
    }

    fn constantCallAt(self: Names, ast: *const Ast, callee: ExprId) ?ConstantCall {
        return self.constant_call(self.ctx, ast, callee);
    }
};

/// A constant value independent of its spelling and use-site type.
/// String bytes are owned by the folding memo, then by checked semantics.
///
/// A variant is its declaration-order ordinal. The enum it belongs to, and the
/// instantiation of a generic enum, is the type the checker recorded for the
/// constant, the parameter or the callable parameter holding the value. Every
/// consumer compares and materializes the value together with that type, as an
/// integer's width lives in the type tables rather than in the value.
pub const CheckedValue = union(enum) {
    integer: i128,
    truth: bool,
    string: []const u8,
    aggregate: ConstantId,

    pub fn eql(a: CheckedValue, b: CheckedValue) bool {
        if (std.meta.activeTag(a) != std.meta.activeTag(b)) return false;
        return switch (a) {
            .integer => |n| n == b.integer,
            .truth => |truth| truth == b.truth,
            .string => |bytes| std.mem.eql(u8, bytes, b.string),
            .aggregate => |id| id == b.aggregate,
        };
    }

    pub fn hash(self: CheckedValue, state: anytype) void {
        const tag: u8 = @intFromEnum(std.meta.activeTag(self));
        state.update(std.mem.asBytes(&tag));
        switch (self) {
            .integer => |n| state.update(std.mem.asBytes(&n)),
            .truth => |truth| state.update(std.mem.asBytes(&truth)),
            .aggregate => |id| state.update(std.mem.asBytes(&id)),
            .string => |bytes| {
                state.update(std.mem.asBytes(&bytes.len));
                state.update(bytes);
            },
        }
    }

    pub fn text(self: CheckedValue, gpa: std.mem.Allocator, pool: *const constants.Pool) std.mem.Allocator.Error![]u8 {
        if (self == .aggregate) return pool.display(gpa, self.aggregate);
        var output: std.Io.Writer.Allocating = .init(gpa);
        defer output.deinit();
        self.writeScalar(&output.writer) catch return error.OutOfMemory;
        return output.toOwnedSlice();
    }

    pub fn encoding(self: CheckedValue, gpa: std.mem.Allocator, pool: *const constants.Pool) std.mem.Allocator.Error![]u8 {
        if (self == .aggregate) return pool.encoding(gpa, self.aggregate);
        return self.text(gpa, pool);
    }

    pub fn node(self: CheckedValue, gpa: std.mem.Allocator, pool: *constants.Pool) !ConstantId {
        return switch (self) {
            .aggregate => |id| id,
            .integer => |value| pool.intern(gpa, .{ .integer = value }),
            .truth => |value| pool.intern(gpa, .{ .truth = value }),
            .string => |value| pool.intern(gpa, .{ .string = value }),
        };
    }

    fn writeScalar(self: CheckedValue, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        switch (self) {
            .aggregate => unreachable,
            .integer => |n| try writer.print("{d}", .{n}),
            .truth => |truth| try writer.writeAll(if (truth) "true" else "false"),
            .string => |bytes| try constants.writeString(writer, bytes),
        }
    }
};

/// What a constant expression is worth.
///
/// The definition is a list of forms and this folds that list: an integer
/// literal, a truth value, a string literal, a selected payload-free enum
/// variant, a parenthesised constant expression, a negation or a conversion of
/// one, arithmetic over two of them, and a reference to an immutable binding
/// whose initialiser is one.
///
/// Being on the list and having a value are two answers, so they are two
/// variants: an operation with no result and a ring of constants each waiting
/// on the next are forms the definition admits, and a caller that reports "this
/// is not a constant expression" about either would report one mistake twice.
///
/// Integers, truth values, text and variants remain distinct. Only an integer
/// can supply a count; its fixed-width type belongs to the checked declaration.
pub const Value = union(enum) {
    /// A form the definition does not admit.
    not_constant,
    /// A form it admits whose value does not exist.
    absent,
    integer: i128,
    truth: bool,
    string: []const u8,
    aggregate: ConstantId,

    pub fn checked(self: Value) ?CheckedValue {
        return switch (self) {
            .integer => |n| .{ .integer = n },
            .truth => |truth| .{ .truth = truth },
            .string => |bytes| .{ .string = bytes },
            .aggregate => |id| .{ .aggregate = id },
            .not_constant, .absent => null,
        };
    }

    pub fn eql(a: Value, b: Value) bool {
        const left = a.checked() orelse return std.meta.activeTag(a) == std.meta.activeTag(b);
        const right = b.checked() orelse return false;
        return left.eql(right);
    }

    /// Whether the definition admits the form, whatever it turned out to be
    /// worth. The membership half of the question, and the only place it is
    /// decided.
    pub fn isConstant(self: Value) bool {
        return self != .not_constant;
    }

    /// The number this is worth, or `null` where it is not a number. What a
    /// count reads: a truth value is a constant expression and says nothing
    /// about how many elements a type holds.
    pub fn number(self: Value) ?i128 {
        return switch (self) {
            .integer => |v| v,
            .not_constant, .absent, .truth, .string, .aggregate => null,
        };
    }
};

/// What one run has folded, and what it is still working out.
///
/// Owned by the pass that folds -- one per run, handed to every call -- so
/// nothing here outlives the pass and no two runs share a row. It is what makes
/// the cost linear: a constant's initialiser is folded once however many
/// references read it, and an expression is folded once however many
/// comparisons ask for it. Without it, a chain of constants each naming the one
/// before costs what the chain spells out, which doubles per link where a
/// name is written twice.
///
/// It is also the one place a ring is found. A site being worked out is a site
/// a name may not reach: the reference that comes back around gets no value,
/// which is what every member of a ring is worth. Two walks share it -- the
/// checker takes a constant's initialiser to know its type, and folding takes
/// it to know its value -- and either marking a site open is what the other
/// tests against, so there is one detector rather than one apiece.
pub const Memo = struct {
    pool: constants.Pool = .{},
    aggregates: std.AutoHashMapUnmanaged(ExprId, AggregateWork) = .empty,

    /// What each site the run has reached is worth, or that it is open.
    sites: std.AutoHashMapUnmanaged(u64, State) = .empty,
    texts: std.StringHashMapUnmanaged(void) = .empty,

    /// What each expression the run has folded is worth.
    exprs: std.AutoHashMapUnmanaged(ExprId, Value) = .empty,
    /// The sites whose initialisers are waiting on one another, outermost
    /// first. A chain is followed by pushing onto this rather than by calling
    /// deeper, so its length is bounded by what a program can allocate and not
    /// by what a stack can hold.
    waiting: std.ArrayListUnmanaged(Reach) = .empty,

    const AggregateWork = struct { values: []ConstantId, next: usize = 0 };

    fn finishAggregate(self: *Memo, gpa: std.mem.Allocator, id: ExprId) void {
        if (self.aggregates.fetchRemove(id)) |entry| gpa.free(entry.value.values);
    }

    const State = union(enum) {
        /// Being worked out. A name reaching it has come back around.
        open,
        settled: Value,
    };

    pub fn takeTexts(self: *Memo, gpa: std.mem.Allocator) ![][]const u8 {
        const owned = try gpa.alloc([]const u8, self.texts.count());
        var keys = self.texts.keyIterator();
        var at: usize = 0;
        while (keys.next()) |key| : (at += 1) owned[at] = key.*;
        self.texts.clearRetainingCapacity();
        return owned;
    }

    fn literalText(self: *Memo, gpa: std.mem.Allocator, ast: *const Ast, id: ExprId) ![]const u8 {
        var decoded: std.ArrayList(u8) = .empty;
        defer decoded.deinit(gpa);
        _ = try ast.literalText(gpa, &decoded, id);
        if (self.texts.getKey(decoded.items)) |held| return held;
        const owned = try gpa.dupe(u8, decoded.items);
        errdefer gpa.free(owned);
        try self.texts.put(gpa, owned, {});
        return owned;
    }
    pub const empty: Memo = .{};

    pub fn deinit(self: *Memo, gpa: std.mem.Allocator) void {
        self.pool.deinit(gpa);
        var aggregates = self.aggregates.valueIterator();
        while (aggregates.next()) |work| gpa.free(work.values);
        self.aggregates.deinit(gpa);
        var texts = self.texts.keyIterator();
        while (texts.next()) |bytes| gpa.free(bytes.*);
        self.texts.deinit(gpa);
        self.sites.deinit(gpa);
        self.exprs.deinit(gpa);
        self.waiting.deinit(gpa);
        self.* = .empty;
    }

    /// Marks a site as being worked out, so a name reaching it is a ring.
    pub fn open(self: *Memo, gpa: std.mem.Allocator, site: Reach) !void {
        try self.sites.put(gpa, site.key(), .open);
    }

    /// Gives up a site the caller opened without settling it, which leaves it
    /// exactly as unknown as it was before. For a walk that took a constant's
    /// initialiser for something other than its value.
    pub fn close(self: *Memo, site: Reach) void {
        const held = self.sites.getPtr(site.key()) orelse return;
        if (held.* == .open) _ = self.sites.remove(site.key());
    }

    /// Whether a site is being worked out by whichever walk opened it.
    pub fn isOpen(self: *const Memo, site: Reach) bool {
        const held = self.sites.get(site.key()) orelse return false;
        return held == .open;
    }

    fn settle(self: *Memo, gpa: std.mem.Allocator, site: Reach, v: Value) !void {
        try self.sites.put(gpa, site.key(), .{ .settled = v });
    }

    /// What an expression this run already folded is worth, or `null` where
    /// nothing has asked for it. For a reader that must work nothing out --
    /// a comparison reading what keying an implementation already settled.
    pub fn worthOf(self: *const Memo, id: ExprId) ?Value {
        return self.exprs.get(id);
    }

    /// Type checking can establish that an arithmetic expression depends on
    /// a symbolic numeric type. Replace an earlier syntax-only fold with that
    /// authoritative classification before constants or defaults consume it.
    pub fn recordNotConstant(self: *Memo, gpa: std.mem.Allocator, id: ExprId) !void {
        try self.exprs.put(gpa, id, .not_constant);
    }

    fn note(self: *Memo, gpa: std.mem.Allocator, id: ExprId, v: Value) !Value {
        try self.exprs.put(gpa, id, v);
        return v;
    }
};

/// What a constant expression is worth, folded once per run and remembered.
///
/// A value and not a type: which type a number belongs to is the declaration's
/// to say. A caller that needs the value to be something in particular -- a
/// count, a width -- asks that where it reads it.
pub fn foldConstant(
    gpa: std.mem.Allocator,
    ast: *const Ast,
    names: Names,
    memo: *Memo,
    id: ExprId,
) !Value {
    if (memo.worthOf(id)) |v| return v;

    // A chain of constants naming one another is followed by walking down it
    // and back, because a chain is linear and as long as it is written. What
    // recursion is left is over an expression's own tree, whose depth the
    // parser already bounds.
    const floor = memo.waiting.items.len;
    defer memo.waiting.shrinkRetainingCapacity(floor);

    var at = id;
    while (true) {
        switch (try step(gpa, ast, names, memo, at)) {
            .done => |v| {
                if (memo.waiting.items.len == floor) return v;
                const site = memo.waiting.pop().?;
                try memo.settle(gpa, site, v);
                at = if (memo.waiting.items.len == floor)
                    id
                else
                    initialiserOf(ast, memo.waiting.items[memo.waiting.items.len - 1]).?;
            },
            .waits => |site| {
                try memo.open(gpa, site);
                try memo.waiting.append(gpa, site);
                at = initialiserOf(ast, site).?;
            },
        }
    }
}

/// How far folding one expression got.
const Step = union(enum) {
    done: Value,
    /// It reads a name whose binding has not been worked out yet, and that
    /// binding's initialiser is what has to be folded before this can be.
    waits: Reach,
};

fn step(
    gpa: std.mem.Allocator,
    ast: *const Ast,
    names: Names,
    memo: *Memo,
    id: ExprId,
) !Step {
    if (id == ExprId.none) return .{ .done = .not_constant };
    if (memo.worthOf(id)) |v| return .{ .done = v };

    switch (ast.exprTag(id)) {
        .int_literal => {
            const digits = literalValue(ast.tokenText(ast.exprMain(id)));
            return .{
                .done = try memo.note(gpa, id, if (digits) |v|
                    .{ .integer = v }
                else
                    // Digits no integer type could hold. A literal all the same,
                    // and one whose value does not exist.
                    .absent),
            };
        },
        .str_literal => return .{ .done = try memo.note(gpa, id, .{ .string = try memo.literalText(gpa, ast, id) }) },
        // The bytes are the program's, held as long as its sources, so the
        // value borrows them rather than copying a file into the memo.
        .embed, .embed_bytes => return .{ .done = try memo.note(gpa, id, if (names.embedded(names.ctx, id)) |bytes| .{ .string = bytes } else .absent) },
        .bool_literal => return .{ .done = try memo.note(gpa, id, .{ .truth = ast.boolIsTrue(id) }) },
        .unit_literal => return .{ .done = try memo.note(gpa, id, .{ .aggregate = try memo.pool.intern(gpa, .unit) }) },
        .struct_literal, .array_literal, .tuple_literal => return aggregate(gpa, ast, names, memo, id, null),
        .variant_ref => return aggregate(gpa, ast, names, memo, id, ast.tokenText(ast.exprMain(id))),
        .grouped => {
            const inner = switch (try step(gpa, ast, names, memo, ast.unaryOperand(id))) {
                .waits => |w| return .{ .waits = w },
                .done => |v| v,
            };
            return .{ .done = try memo.note(gpa, id, inner) };
        },
        .negate => {
            const inner = switch (try step(gpa, ast, names, memo, ast.unaryOperand(id))) {
                .waits => |w| return .{ .waits = w },
                .done => |v| v,
            };
            return .{ .done = try memo.note(gpa, id, negated(inner)) };
        },
        .add, .sub, .mul, .div, .rem => {
            const b = ast.binary(id);
            const lhs = switch (try step(gpa, ast, names, memo, b.lhs)) {
                .waits => |w| return .{ .waits = w },
                .done => |v| v,
            };
            const rhs = switch (try step(gpa, ast, names, memo, b.rhs)) {
                .waits => |w| return .{ .waits = w },
                .done => |v| v,
            };
            return .{ .done = try memo.note(gpa, id, combined(ast.exprTag(id), lhs, rhs)) };
        },
        // A conversion or a newtype construction of a constant expression.
        // Which names head one is the caller's answer, so a call to anything
        // else falls through to the clause that admits no form.
        .call => {
            const c = ast.call(id);
            if (!ast.callFallible(id) and (ast.exprTag(c.callee) == .variant_ref or names.variant(names.ctx, c.callee)))
                return aggregate(gpa, ast, names, memo, id, ast.tokenText(ast.exprMain(c.callee)));
            // `a.length()` on a constant array is the number of elements the
            // array holds. A receiver that is text, a record or no constant at
            // all leaves the call outside the definition.
            if (c.args.len == 0 and !ast.callFallible(id) and ast.exprTag(c.callee) == .field and
                std.mem.eql(u8, ast.tokenText(ast.exprMain(c.callee)), array_length_name))
            {
                const receiver = switch (try step(gpa, ast, names, memo, ast.unaryOperand(c.callee))) {
                    .waits => |w| return .{ .waits = w },
                    .done => |v| v,
                };
                return .{ .done = try memo.note(gpa, id, arrayLength(memo, receiver)) };
            }
            // A fallible construction produces something that may hold no
            // value at all, which is not a number and is not decided here.
            if (c.args.len != 1 or ast.callFallible(id)) {
                return .{ .done = try memo.note(gpa, id, .not_constant) };
            }
            const call = names.constantCallAt(ast, c.callee) orelse {
                return .{ .done = try memo.note(gpa, id, .not_constant) };
            };
            const inner = switch (try step(gpa, ast, names, memo, c.args[0])) {
                .waits => |w| return .{ .waits = w },
                .done => |v| v,
            };
            return .{ .done = try memo.note(gpa, id, switch (call) {
                .into => |range| converted(inner, range),
                .construction => inner,
            }) };
        },
        // A name and a name reached through what declares it are one clause:
        // which binding is written where decides what the reference is worth,
        // and the spelling decides nothing.
        .name_ref, .field => {
            if (names.variant(names.ctx, id)) return aggregate(gpa, ast, names, memo, id, ast.tokenText(ast.exprMain(id)));
            if (names.integer_property(names.ctx, id)) |value|
                return .{ .done = try memo.note(gpa, id, .{ .integer = value }) };
            const site = names.of(id);
            if (memo.sites.get(site.key())) |held| switch (held) {
                // A constant reached while it is being worked out waits on
                // itself, and so does every member of a ring of them.
                .open => return .{ .done = try memo.note(gpa, id, .absent) },
                .settled => |v| return .{ .done = try memo.note(gpa, id, v) },
            };
            // Only an immutable binding with an initialiser to read: a `var`
            // may be assigned again, and a destructuring `let` binds part of a
            // value rather than what was written.
            if (initialiserOf(ast, site) == null) {
                return .{ .done = try memo.note(gpa, id, .not_constant) };
            }
            return .{ .waits = site };
        },
        else => return .{ .done = try memo.note(gpa, id, .not_constant) },
    }
}

/// The length of a folded array, or what the receiver is worth where it holds
/// no array. A receiver without a value leaves the length without one.
fn arrayLength(memo: *const Memo, receiver: Value) Value {
    return switch (receiver) {
        .aggregate => |id| switch (memo.pool.get(id)) {
            .array => |values| .{ .integer = @intCast(values.len) },
            else => .not_constant,
        },
        .absent => .absent,
        .not_constant, .integer, .truth, .string => .not_constant,
    };
}

/// Resume at the first unfinished edge after an alias dependency is folded.
/// Each written edge is visited once, including wide aggregates of aliases.
fn aggregate(gpa: std.mem.Allocator, ast: *const Ast, names: Names, memo: *Memo, id: ExprId, variant: ?[]const u8) std.mem.Allocator.Error!Step {
    const tag = ast.exprTag(id);
    const args = if (tag == .struct_literal or tag == .array_literal or tag == .tuple_literal or tag == .call) ast.call(id).args else &.{};
    const written = if (tag == .struct_literal) args.len / 2 else args.len;
    // A structure literal's base is folded last, after the fields it writes,
    // which is the order the literal evaluates them in.
    const base = if (tag == .struct_literal) ast.structLiteralBase(id) else null;
    const count = written + @intFromBool(base != null);
    if (!memo.aggregates.contains(id)) {
        const values = try gpa.alloc(ConstantId, count);
        errdefer gpa.free(values);
        try memo.aggregates.put(gpa, id, .{ .values = values });
    }
    while (memo.aggregates.get(id).?.next < count) {
        const work = memo.aggregates.get(id).?;
        const child = if (work.next == written)
            base.?
        else
            args[if (tag == .struct_literal) work.next * 2 + 1 else work.next];
        const value = switch (try step(gpa, ast, names, memo, child)) {
            .waits => |site| return .{ .waits = site },
            .done => |value| value,
        };
        const checked = value.checked() orelse {
            memo.finishAggregate(gpa, id);
            return .{ .done = try memo.note(gpa, id, value) };
        };
        work.values[work.next] = try checked.node(gpa, &memo.pool);
        memo.aggregates.getPtr(id).?.next += 1;
    }
    const values = memo.aggregates.get(id).?.values;
    const result = if (variant) |name|
        try memo.pool.intern(gpa, .{ .variant = .{ .name = name, .payloads = values } })
    else if (tag == .array_literal)
        try memo.pool.intern(gpa, .{ .array = values })
    else record: {
        const inherited: []const constants.Field = if (base != null) switch (memo.pool.get(values[written])) {
            .record => |fields| fields,
            // A base that is not a record is refused by the checker, and a
            // record cannot be built from it here.
            else => {
                memo.finishAggregate(gpa, id);
                return .{ .done = try memo.note(gpa, id, .not_constant) };
            },
        } else &.{};
        var fields: std.ArrayList(constants.Field) = .empty;
        defer fields.deinit(gpa);
        for (values[0..written], 0..) |value, at| try fields.append(gpa, .{
            // A tuple's components are the fields its declaration names, by
            // position. An arity the parser refused or the prelude does not
            // declare has none, and is no constant.
            .name = if (tag == .tuple_literal) names.tupleComponentAt(ast, written, at) orelse {
                memo.finishAggregate(gpa, id);
                return .{ .done = try memo.note(gpa, id, .not_constant) };
            } else ast.tokenText(ast.exprMain(args[at * 2])),
            .value = value,
        });
        // Both runs in name order, so the base's fields the literal does not
        // write are found in one walk. A pool record is already in name order.
        std.mem.sort(constants.Field, fields.items, {}, fieldBefore);
        const own = fields.items.len;
        var mine: usize = 0;
        for (inherited) |field| {
            while (mine < own and std.mem.order(u8, fields.items[mine].name, field.name) == .lt) mine += 1;
            if (mine < own and std.mem.eql(u8, fields.items[mine].name, field.name)) continue;
            try fields.append(gpa, field);
        }
        break :record try memo.pool.record(gpa, fields.items);
    };
    memo.finishAggregate(gpa, id);
    return .{ .done = try memo.note(gpa, id, .{ .aggregate = result }) };
}

test "a tuple literal folds to the fields its declaration names, by position" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    const source: Source = .{ .path = "t.lin", .text =
        \\struct Tuple2[A, B] { fst: A, snd: B }
        \\struct Tuple3[A, B, C] { x: A, y: B, z: C }
        \\let pair = (1, true)
        \\let triple = (1, 2, 3)
        \\let many = (1, 2, 3, 4, 5, 6, 7, 8, 9)
    };
    const ast = try treeOf(gpa, &source);
    var spelled = try Spelled.init(gpa, &ast);
    var memo: Memo = .empty;
    const names = spelled.names();
    var folded: [3]Value = undefined;
    var at: usize = 0;
    for (0..ast.declCount()) |i| {
        const d = DeclId.at(@intCast(i));
        if (ast.declTag(d) != .constant) continue;
        folded[at] = try foldConstant(gpa, &ast, names, &memo, ast.declInit(d));
        at += 1;
    }
    const pair = memo.pool.get(folded[0].aggregate).record;
    try testing.expectEqualStrings("fst", pair[0].name);
    try testing.expectEqualStrings("snd", pair[1].name);
    const triple = memo.pool.get(folded[1].aggregate).record;
    try testing.expectEqualStrings("x", triple[0].name);
    try testing.expectEqualStrings("y", triple[1].name);
    try testing.expectEqualStrings("z", triple[2].name);
    // No declaration names a nine-part tuple's components, so it is no constant.
    try testing.expectEqual(Value.not_constant, folded[2]);
}

fn fieldBefore(_: void, a: constants.Field, b: constants.Field) bool {
    return std.mem.order(u8, a.name, b.name) == .lt;
}

/// What the binding a site names was initialised with, or `null` where the site
/// is not a binding a constant expression may read.
fn initialiserOf(ast: *const Ast, site: Reach) ?ExprId {
    const written = switch (site) {
        .nothing => return null,
        .decl => |d| if (ast.declTag(d) == .constant) ast.declInit(d) else return null,
        .stmt => |s| blk: {
            if (ast.stmtTag(s) != .let_decl or ast.stmtIsMutable(s)) return null;
            const data = ast.stmtData(s);
            // A destructuring `let` binds part of a value rather than the
            // initialiser, so its name stands for something this cannot read.
            if (data.pattern != ExprId.none) return null;
            break :blk data.init;
        },
    };
    return if (written == ExprId.none) null else written;
}

/// The digits of an integer literal, or `null` where no integer type could
/// hold what they spell.
pub fn literalValue(text: []const u8) ?i128 {
    return std.fmt.parseInt(i128, text, 10) catch null;
}

/// A negation reaches a number. No arithmetic is defined over a truth value, so
/// negating one is a form the definition admits and a value that does not
/// exist.
fn negated(v: Value) Value {
    return switch (v) {
        .not_constant => .not_constant,
        .absent, .truth, .string, .aggregate => .absent,
        .integer => |n| if (std.math.negate(n)) |r| .{ .integer = r } else |_| .absent,
    };
}

/// A conversion reaches a number, and the number has to be one its target can
/// hold: a conversion that cannot succeed has no value, exactly as an operation
/// that leaves its type has none.
fn converted(v: Value, range: Range) Value {
    return switch (v) {
        .not_constant => .not_constant,
        .absent, .truth, .string, .aggregate => .absent,
        .integer => |n| if (n >= range.min and n <= range.max) .{ .integer = n } else .absent,
    };
}

/// An operation over two folds. An operand off the list leaves the operation
/// off it; an operand on the list with no value, or one that is not a number,
/// leaves an operation with no value.
fn combined(op: node.Expr.Tag, a: Value, b: Value) Value {
    if (a == .not_constant or b == .not_constant) return .not_constant;
    const lhs = a.number() orelse return .absent;
    const rhs = b.number() orelse return .absent;
    return if (arithmetic(op, lhs, rhs)) |v| .{ .integer = v } else .absent;
}

/// What an operation over two constants is worth, or `null` where it has no
/// value.
///
/// Folded in `i128` rather than in the operand type, so a result the type
/// cannot hold is a value here and refused where the type is known. Nothing
/// leaves `i128` without being refused: the operands are as wide as a literal
/// may be written, so a product of two of them can leave it. Every tag the
/// parser gives an arithmetic operation is answered, and a tag that is not one
/// of them never reaches here -- the callers switch on the same five.
pub fn arithmetic(op: node.Expr.Tag, a: i128, b: i128) ?i128 {
    return switch (op) {
        .add => std.math.add(i128, a, b) catch null,
        .sub => std.math.sub(i128, a, b) catch null,
        .mul => std.math.mul(i128, a, b) catch null,
        .div => divided(a, b),
        .rem => remainder(a, b),
        else => unreachable,
    };
}

fn divided(a: i128, b: i128) ?i128 {
    if (b == 0) return null;
    return std.math.divTrunc(i128, a, b) catch null;
}

/// What a truncating division leaves, so the sign follows the dividend. Where
/// that division has no value there is nothing for a remainder to be left over
/// from, which is also what keeps the operation below in range.
fn remainder(a: i128, b: i128) ?i128 {
    _ = divided(a, b) orelse return null;
    return @rem(a, b);
}

/// The names a test's source writes, answered by spelling.
///
/// A binding is found by the name it declares, which is what these sources
/// hold: each declares every name once, so a spelling reaches one declaration
/// and the answer is the one a resolution would give. The names are indexed
/// once by interned identity, so a long chain spends expected constant time
/// finding each predecessor. A name spelling a primitive heads a conversion
/// into that primitive's range, and a name spelling a declared newtype heads
/// its construction, which are the answers the two passes give from their own
/// tables.
const Spelled = struct {
    ast: *const Ast,
    bindings: std.AutoHashMapUnmanaged(StringId, Reach) = .empty,

    const widths = [_]struct { name: []const u8, signed: bool, bits: u8 }{
        .{ .name = "Int8", .signed = true, .bits = 8 },
        .{ .name = "Int16", .signed = true, .bits = 16 },
        .{ .name = "Int32", .signed = true, .bits = 32 },
        .{ .name = "Int64", .signed = true, .bits = 64 },
        .{ .name = "UInt8", .signed = false, .bits = 8 },
        .{ .name = "UInt16", .signed = false, .bits = 16 },
        .{ .name = "UInt32", .signed = false, .bits = 32 },
        .{ .name = "UInt64", .signed = false, .bits = 64 },
    };

    fn init(gpa: std.mem.Allocator, ast: *const Ast) !Spelled {
        var self: Spelled = .{ .ast = ast };
        errdefer self.deinit(gpa);
        for (0..ast.declCount()) |i| {
            const d = DeclId.at(@intCast(i));
            if (ast.declName(d) == .none) continue;
            if (ast.declTag(d) != .constant) continue;
            try self.bindings.put(gpa, ast.tokenName(ast.declName(d)), .{ .decl = d });
        }
        for (0..ast.stmtCount()) |i| {
            const s = StmtId.at(@intCast(i));
            const name = ast.stmtData(s).name;
            if (name == .none) continue;
            try self.bindings.put(gpa, ast.tokenName(name), .{ .stmt = s });
        }
        return self;
    }

    fn deinit(self: *Spelled, gpa: std.mem.Allocator) void {
        self.bindings.deinit(gpa);
    }

    fn names(self: *const Spelled) Names {
        return .{ .ctx = self, .reaches = reaches, .constant_call = constantCall, .integer_property = integerProperty, .variant = spelledVariant, .tuple_component = spelledTupleComponent, .embedded = noEmbeds };
    }

    /// The tests fold source alone, which no loader read a file for.
    fn noEmbeds(_: *const anyopaque, _: ExprId) ?[]const u8 {
        return null;
    }

    /// The field the source's own `Tuple<arity>` declaration names at
    /// `position`.
    fn spelledTupleComponent(_: *const anyopaque, ast: *const Ast, arity: usize, position: usize) ?[]const u8 {
        for (0..ast.declCount()) |i| {
            const d = DeclId.at(@intCast(i));
            if (ast.declTag(d) != .struct_) continue;
            const name = ast.tokenText(ast.declName(d));
            if (!std.mem.startsWith(u8, name, "Tuple")) continue;
            if ((std.fmt.parseInt(usize, name["Tuple".len..], 10) catch continue) != arity) continue;
            const fields = ast.declFields(d);
            return if (position < fields.len) ast.tokenText(fields[position].name) else null;
        }
        return null;
    }

    fn integerProperty(_: *const anyopaque, _: ExprId) ?i128 {
        return null;
    }

    /// `Enum.Name` written with a head spelling an enum the source declares,
    /// which the pool records by the member's own name.
    fn spelledVariant(ctx: *const anyopaque, id: ExprId) bool {
        const self: *const Spelled = @ptrCast(@alignCast(ctx));
        const ast = self.ast;
        if (ast.exprTag(id) != .field) return false;
        const base = ast.unaryOperand(id);
        if (ast.exprTag(base) != .name_ref) return false;
        const head = ast.tokenText(ast.exprMain(base));
        for (0..ast.declCount()) |i| {
            const d = DeclId.at(@intCast(i));
            if (ast.declTag(d) != .enum_ or !std.mem.eql(u8, ast.tokenText(ast.declName(d)), head)) continue;
            const wanted = ast.tokenText(ast.exprMain(id));
            for (ast.declVariants(d)) |v| {
                if (std.mem.eql(u8, ast.tokenText(v.name), wanted)) return true;
            }
        }
        return false;
    }

    fn reaches(ctx: *const anyopaque, id: ExprId) Reach {
        const self: *const Spelled = @ptrCast(@alignCast(ctx));
        return self.bindings.get(self.ast.tokenName(self.ast.exprMain(id))) orelse .nothing;
    }

    fn constantCall(ctx: *const anyopaque, ast: *const Ast, callee: ExprId) ?ConstantCall {
        _ = ctx;
        if (ast.exprTag(callee) != .name_ref) return null;
        const wanted = ast.tokenText(ast.exprMain(callee));
        for (widths) |w| {
            if (!std.mem.eql(u8, w.name, wanted)) continue;
            if (!w.signed) return .{ .into = .{ .min = 0, .max = (@as(i128, 1) << @intCast(w.bits)) - 1 } };
            return .{ .into = .{
                .min = -(@as(i128, 1) << @intCast(w.bits - 1)),
                .max = (@as(i128, 1) << @intCast(w.bits - 1)) - 1,
            } };
        }
        for (0..ast.declCount()) |i| {
            const d = DeclId.at(@intCast(i));
            if (ast.declTag(d) == .newtype and std.mem.eql(u8, ast.tokenText(ast.declName(d)), wanted)) return .construction;
        }
        return null;
    }
};

fn treeOf(gpa: std.mem.Allocator, source: *const Source) !Ast {
    var sink = Sink.init(gpa);
    var interner: Interner = .empty;
    const tokens = try tokenize(gpa, source, .from(0), &sink, &interner);
    return try parse(gpa, source, .from(0), tokens, &sink);
}

/// The initialiser of the constant the module declares last, which is what
/// each test writes the expression it is about into.
fn lastInitialiser(ast: *const Ast) ExprId {
    var found = ExprId.none;
    for (0..ast.declCount()) |i| {
        const d = DeclId.at(@intCast(i));
        if (ast.declTag(d) == .constant) found = ast.declInit(d);
    }
    return found;
}

/// What the last constant of `text` is worth.
fn worth(gpa: std.mem.Allocator, source: *const Source) !Value {
    const ast = try treeOf(gpa, source);
    var spelled = try Spelled.init(gpa, &ast);
    defer spelled.deinit(gpa);
    var memo: Memo = .empty;
    defer memo.deinit(gpa);
    return foldConstant(gpa, &ast, spelled.names(), &memo, lastInitialiser(&ast));
}

/// The expression naming `spelling`, which is what a test folds when what it
/// is about is written inside a function rather than as a constant.
fn nameWritten(ast: *const Ast, spelling: []const u8) ExprId {
    for (0..ast.exprCount()) |i| {
        const e = ExprId.at(@intCast(i));
        if (ast.exprTag(e) != .name_ref) continue;
        if (std.mem.eql(u8, ast.tokenText(ast.exprMain(e)), spelling)) return e;
    }
    return ExprId.none;
}

/// What the name `spelling` is worth where `text` writes it.
fn worthOfName(gpa: std.mem.Allocator, source: *const Source, spelling: []const u8) !Value {
    const ast = try treeOf(gpa, source);
    var spelled = try Spelled.init(gpa, &ast);
    defer spelled.deinit(gpa);
    var memo: Memo = .empty;
    defer memo.deinit(gpa);
    return foldConstant(gpa, &ast, spelled.names(), &memo, nameWritten(&ast, spelling));
}

test "an integer literal is worth what it spells" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const source: Source = .{ .path = "t.lin", .text = "let K: UInt8 = 3\n" };
    try testing.expectEqual(Value{ .integer = 3 }, try worth(arena.allocator(), &source));
}

test "a truth value preserves true or false" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const yes: Source = .{ .path = "t.lin", .text = "let K: Bool = true\n" };
    const no: Source = .{ .path = "t.lin", .text = "let K: Bool = false\n" };
    try testing.expectEqual(Value{ .truth = true }, try worth(arena.allocator(), &yes));
    try testing.expectEqual(Value{ .truth = false }, try worth(arena.allocator(), &no));
}

test "a truth value is a constant expression and is not a count" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const source: Source = .{ .path = "t.lin", .text = "let K: Bool = true\n" };
    const v = try worth(arena.allocator(), &source);
    try testing.expect(v.isConstant());
    try testing.expectEqual(@as(?i128, null), v.number());
}

test "arithmetic over constant expressions folds" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const sum: Source = .{ .path = "t.lin", .text = "let K: UInt8 = 2 + 2\n" };
    try testing.expectEqual(Value{ .integer = 4 }, try worth(gpa, &sum));

    const grouped: Source = .{ .path = "t.lin", .text = "let K: UInt8 = (1 + 2) * 3\n" };
    try testing.expectEqual(Value{ .integer = 9 }, try worth(gpa, &grouped));

    const negative: Source = .{ .path = "t.lin", .text = "let K: Int8 = 0 - 1\n" };
    try testing.expectEqual(Value{ .integer = -1 }, try worth(gpa, &negative));

    const written_negative: Source = .{ .path = "t.lin", .text = "let K: Int8 = -1\n" };
    try testing.expectEqual(Value{ .integer = -1 }, try worth(gpa, &written_negative));

    // An operation with no result is not a value, and being one is not what
    // decides whether the form was admitted.
    const by_zero: Source = .{ .path = "t.lin", .text = "let K: UInt8 = 1 / 0\n" };
    try testing.expectEqual(Value.absent, try worth(gpa, &by_zero));

    // No arithmetic is defined over a truth value, so an operation reaching one
    // is a form the definition admits and a value that does not exist.
    const over_truth: Source = .{ .path = "t.lin", .text = "let K: UInt8 = true + true\n" };
    try testing.expectEqual(Value.absent, try worth(gpa, &over_truth));
}

test "a conversion of a constant expression is one" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const converted_literal: Source = .{ .path = "t.lin", .text = "let K: UInt32 = UInt32(3)\n" };
    try testing.expectEqual(Value{ .integer = 3 }, try worth(gpa, &converted_literal));

    const over_a_name: Source = .{
        .path = "t.lin",
        .text = "let A: UInt8 = 2\nlet K: UInt32 = UInt32(A + 1)\n",
    };
    try testing.expectEqual(Value{ .integer = 3 }, try worth(gpa, &over_a_name));

    // A conversion its target cannot hold is a constant expression whose value
    // does not exist, exactly as an operation that leaves its type is.
    const too_wide: Source = .{ .path = "t.lin", .text = "let K: UInt8 = UInt8(300)\n" };
    try testing.expectEqual(Value.absent, try worth(gpa, &too_wide));

    // A call reaching something that is not a conversion is a form the
    // definition does not admit.
    const call: Source = .{
        .path = "t.lin",
        .text = "fn f() -> UInt8 {\n    1\n}\n\nlet K: UInt8 = f()\n",
    };
    try testing.expectEqual(Value.not_constant, try worth(gpa, &call));
}

test "a newtype construction of a constant expression is worth its operand" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    // The refinement is not consulted here: an operand outside it keeps its
    // value, and the construction is refused where it is type checked.
    const refined: Source = .{
        .path = "t.lin",
        .text = "type Percent = UInt8 where it in 0..=100\n\nlet K: Percent = Percent(150)\n",
    };
    try testing.expectEqual(Value{ .integer = 150 }, try worth(gpa, &refined));

    const over_a_name: Source = .{
        .path = "t.lin",
        .text = "type Meters = UInt8\n\nlet A: UInt8 = 2\nlet K: Meters = Meters(A * 3)\n",
    };
    try testing.expectEqual(Value{ .integer = 6 }, try worth(gpa, &over_a_name));

    // The fallible form holds an option, so it is not a constant expression.
    const fallible: Source = .{
        .path = "t.lin",
        .text = "type Percent = UInt8 where it in 0..=100\n\nlet K: Percent = Percent?(50)\n",
    };
    try testing.expectEqual(Value.not_constant, try worth(gpa, &fallible));
}

test "a name reaching an immutable binding is worth its initialiser" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    // Through two constants and an operation on them, and in the direction
    // that reads a declaration written below the one reading it.
    const chain: Source = .{ .path = "t.lin", .text = "let A: UInt8 = 2\nlet B: UInt8 = A + 1\n" };
    try testing.expectEqual(Value{ .integer = 3 }, try worth(gpa, &chain));

    const shared: Source = .{
        .path = "t.lin",
        .text = "let A: UInt8 = 1\nlet B: UInt8 = A + A\nlet C: UInt8 = B + B\n",
    };
    try testing.expectEqual(Value{ .integer = 4 }, try worth(gpa, &shared));

    const below: Source = .{ .path = "t.lin", .text = "let B: UInt8 = A + 1\nlet A: UInt8 = 2\n" };
    const ast = try treeOf(gpa, &below);
    var spelled = try Spelled.init(gpa, &ast);
    defer spelled.deinit(gpa);
    var memo: Memo = .empty;
    defer memo.deinit(gpa);
    const first = ast.declInit(DeclId.at(0));
    try testing.expectEqual(
        Value{ .integer = 3 },
        try foldConstant(gpa, &ast, spelled.names(), &memo, first),
    );
}

test "a chain is as long as it is written" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    // Long enough that a routine calling itself once per link would not come
    // back, and written so each link is read twice -- the shape whose cost
    // doubles per link where nothing is remembered.
    const links = 40000;
    var text: std.ArrayListUnmanaged(u8) = .empty;
    try text.appendSlice(gpa, "let A0: UInt8 = 1\n");
    for (1..links) |i| {
        const line = try std.fmt.allocPrint(gpa, "let A{d}: UInt8 = A{d} * A{d}\n", .{ i, i - 1, i - 1 });
        try text.appendSlice(gpa, line);
    }
    const source: Source = .{ .path = "t.lin", .text = text.items };
    try testing.expectEqual(Value{ .integer = 1 }, try worth(gpa, &source));
}

test "a block's immutable binding is such a binding" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    const source: Source = .{
        .path = "t.lin",
        .text = "fn main() -> UInt8 {\n    let n = 4\n    n\n}\n",
    };
    try testing.expectEqual(Value{ .integer = 4 }, try worthOfName(gpa, &source, "n"));
}

test "a var is not a constant expression" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    const source: Source = .{
        .path = "t.lin",
        .text = "fn main() -> UInt8 {\n    var m = 3\n    m\n}\n",
    };
    try testing.expectEqual(Value.not_constant, try worthOfName(gpa, &source, "m"));
}

test "an array constant's length is the number of elements it holds" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const named: Source = .{ .path = "t.lin", .text = "let names = [\"a\", \"b\", \"c\"]\nlet K = names.length()\n" };
    try testing.expectEqual(Value{ .integer = 3 }, try worth(gpa, &named));

    const empty: Source = .{ .path = "t.lin", .text = "let K = [].length()\n" };
    try testing.expectEqual(Value{ .integer = 0 }, try worth(gpa, &empty));

    const summed: Source = .{ .path = "t.lin", .text = "let rows = [[1, 2], [3, 4]]\nlet K = rows.length() + 1\n" };
    try testing.expectEqual(Value{ .integer = 3 }, try worth(gpa, &summed));

    // Text has a length at run time, and it is not a constant expression.
    const text: Source = .{ .path = "t.lin", .text = "let word = \"abc\"\nlet K = word.length()\n" };
    try testing.expectEqual(Value.not_constant, try worth(gpa, &text));

    // A call has to run before its array exists.
    const called: Source = .{ .path = "t.lin", .text = "let K = row().length()\n" };
    try testing.expectEqual(Value.not_constant, try worth(gpa, &called));

    const ring: Source = .{ .path = "t.lin", .text = "let K = [K].length()\n" };
    try testing.expectEqual(Value.absent, try worth(gpa, &ring));
}

test "a name nobody resolved is not a constant expression" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const source: Source = .{ .path = "t.lin", .text = "let K: UInt8 = Q\n" };
    try testing.expectEqual(Value.not_constant, try worth(arena.allocator(), &source));
}

test "a form the definition does not admit is worth nothing" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const logical: Source = .{ .path = "t.lin", .text = "let K: Bool = true && false\n" };
    try testing.expectEqual(Value.not_constant, try worth(gpa, &logical));

    const compared: Source = .{ .path = "t.lin", .text = "let K: Bool = 1 < 2\n" };
    try testing.expectEqual(Value.not_constant, try worth(gpa, &compared));
}

test "a constant reached from its own initialiser is worth nothing" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const itself: Source = .{ .path = "t.lin", .text = "let A: UInt8 = A + 1\n" };
    try testing.expectEqual(Value.absent, try worth(gpa, &itself));

    const ring: Source = .{ .path = "t.lin", .text = "let A: UInt8 = B\nlet B: UInt8 = A\n" };
    try testing.expectEqual(Value.absent, try worth(gpa, &ring));
}

test "a site a caller is holding open is a ring" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    // A walk that takes a constant's initialiser for something other than its
    // value marks the site open, and folding tests against that one mark --
    // which is what leaves one detector for the two walks.
    const source: Source = .{ .path = "t.lin", .text = "let A: UInt8 = 2\nlet B: UInt8 = A + 1\n" };
    const ast = try treeOf(gpa, &source);
    var spelled = try Spelled.init(gpa, &ast);
    defer spelled.deinit(gpa);
    var memo: Memo = .empty;
    defer memo.deinit(gpa);

    const site: Reach = .{ .decl = DeclId.at(0) };
    try memo.open(gpa, site);
    try testing.expect(memo.isOpen(site));
    try testing.expectEqual(
        Value.absent,
        try foldConstant(gpa, &ast, spelled.names(), &memo, ast.declInit(DeclId.at(1))),
    );

    // Given up rather than settled, so what the site is worth is exactly as
    // unknown as it was before.
    memo.close(site);
    try testing.expect(!memo.isOpen(site));
}

test "an operation no i128 could hold has no value" {
    // The operands of a fold are as wide as a literal may be written, so a
    // product of two of them can leave the type the fold is carried in.
    const wide = std.math.maxInt(i128);
    try testing.expectEqual(@as(?i128, null), arithmetic(.mul, wide, wide));
    try testing.expectEqual(@as(?i128, null), arithmetic(.add, wide, 1));
    try testing.expectEqual(@as(?i128, 0), arithmetic(.rem, wide, wide));
}

test "string constants resolve to one literal through aliases" {
    const source: Source = .{ .path = "t.lin", .text = "let first = (second)\nlet second = \"hello\"\n" };
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const value = try worthOfName(arena.allocator(), &source, "second");
    try testing.expect(value == .string);
    try testing.expect(value.isConstant());
    try testing.expectEqual(@as(?i128, null), value.number());
}

test "constants preserve truth separately from integer identity" {
    const truth: CheckedValue = .{ .truth = true };
    const integer: CheckedValue = .{ .integer = 1 };
    try testing.expect(!truth.eql(integer));
    const folded: Value = .{ .truth = true };
    try testing.expectEqual(@as(?i128, null), folded.number());
    try testing.expect(folded.checked().?.eql(truth));
}

test "enum constant: a payload-free variant is a value and not a number" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    const source: Source = .{
        .path = "t.lin",
        .text = "enum Mode { Preserve, Exact(UInt64) }\nlet chosen = Mode.Preserve\nlet K = (chosen)\n",
    };
    const value = try worth(gpa, &source);
    try testing.expect(value == .aggregate);
    try testing.expectEqual(@as(?i128, null), value.number());
    try testing.expect(!value.checked().?.eql(.{ .integer = 0 }));
}

test "enum constant: a variant construction and a contextual variant both fold" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    const built: Source = .{ .path = "t.lin", .text = "enum Mode { Preserve, Exact(UInt64) }\nlet K = Mode.Exact(3)\n" };
    try testing.expect(try worth(gpa, &built) == .aggregate);
    const contextual: Source = .{ .path = "t.lin", .text = "enum Mode { Preserve }\nlet K: Mode = .Preserve\n" };
    try testing.expect(try worth(gpa, &contextual) == .aggregate);
}

test "enum constant: variants hash and compare apart from other kinds" {
    var pool: constants.Pool = .{};
    defer pool.deinit(testing.allocator);
    const gpa = testing.allocator;
    const preserve: CheckedValue = .{ .aggregate = try pool.intern(gpa, .{ .variant = .{ .name = "Preserve", .payloads = &.{} } }) };
    const exact: CheckedValue = .{ .aggregate = try pool.intern(gpa, .{ .variant = .{ .name = "Exact", .payloads = &.{} } }) };
    try testing.expect(preserve.eql(.{ .aggregate = try pool.intern(gpa, .{ .variant = .{ .name = "Preserve", .payloads = &.{} } }) }));
    try testing.expect(!preserve.eql(exact));
    try testing.expect(!preserve.eql(.{ .integer = 0 }));
    var a: std.hash.Wyhash = .init(0);
    preserve.hash(&a);
    var b: std.hash.Wyhash = .init(0);
    (CheckedValue{ .integer = 0 }).hash(&b);
    try testing.expect(a.final() != b.final());
}

fn foldTextWithFailures(gpa: std.mem.Allocator, ast: *const Ast) !void {
    var spelled = try Spelled.init(gpa, ast);
    defer spelled.deinit(gpa);
    var memo: Memo = .empty;
    defer memo.deinit(gpa);
    const value = try foldConstant(gpa, ast, spelled.names(), &memo, lastInitialiser(ast));
    try testing.expect(value == .string);
    const texts = try memo.takeTexts(gpa);
    defer {
        for (texts) |text| gpa.free(text);
        gpa.free(texts);
    }
    try testing.expectEqualStrings("hello", value.string);
}

test "constants release decoded text on allocation failure" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const source: Source = .{ .path = "t.lin", .text = "let first = \"hello\"\nlet second = first\n" };
    const ast = try treeOf(arena.allocator(), &source);
    try testing.checkAllAllocationFailures(testing.allocator, foldTextWithFailures, .{&ast});
}

test "aggregate constants fold records arrays unit and immutable aliases" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const source: Source = .{ .path = "aggregate.lin", .text =
        \\let leaf = .{ bytes = 32, enabled = true }
        \\let aliases = [leaf, leaf]
        \\let value = .{ empty = (), nested = aliases }
    };
    try testing.expect((try worth(arena.allocator(), &source)).isConstant());
}

test "aggregate constants release partial records and alias work on allocation failure" {
    const Case = struct {
        fn run(gpa: std.mem.Allocator, ast: *const Ast) !void {
            var spelled = try Spelled.init(gpa, ast);
            defer spelled.deinit(gpa);
            var memo: Memo = .empty;
            defer memo.deinit(gpa);
            const value = try foldConstant(gpa, ast, spelled.names(), &memo, lastInitialiser(ast));
            try testing.expect(value == .aggregate);
            const rendered = try value.checked().?.text(gpa, &memo.pool);
            defer gpa.free(rendered);
        }
    };
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const source: Source = .{ .path = "aggregate.lin", .text =
        \\let text = "hello"
        \\let leaf = .{ text = text, count = 3 }
        \\let value = .{ pair = [leaf, leaf], unit = () }
    };
    const ast = try treeOf(arena.allocator(), &source);
    try testing.checkAllAllocationFailures(testing.allocator, Case.run, .{&ast});
}
