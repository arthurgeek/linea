const std = @import("std");
const Ast = @import("../syntax/ast.zig").Ast;
const node = @import("../syntax/node.zig");
const resolve = @import("../sema/resolve.zig");
const types = @import("../sema/types.zig");

/// Initializers whose elements cannot be observed before an unconditional
/// prefix write. This is a lowering fact, not permission to read uninitialized
/// storage: every later access must use that same immutable bound.
pub const Elisions = std.AutoHashMapUnmanaged(node.ExprId, void);

const Candidate = struct {
    initializer: node.ExprId,
    bound: resolve.BindingId = .none,
    rejected: bool = false,
    pending: bool = false,
};

const Loop = struct {
    induction: resolve.BindingId,
    bound: resolve.BindingId,
    written: std.ArrayList(u32) = .empty,
};

/// Inspects a function once, using resolved binding identities. The quick scan
/// only visits top-level declarations; functions without eligible arrays do
/// not acquire tables or traverse expression bodies. With candidates, work is
/// O(body nodes + initializer elements), with storage bounded by local bindings.
pub fn find(gpa: std.mem.Allocator, ast: *const Ast, res: *const resolve.Resolution, typing: *const types.Typing, body: node.ExprId) std.mem.Allocator.Error!Elisions {
    var out: Elisions = .empty;
    errdefer out.deinit(gpa);
    const root = ast.withoutGroups(body);
    if (ast.exprTag(root) != .block) return out;
    var proof: Proof = .{ .gpa = gpa, .ast = ast, .res = res, .typing = typing };
    defer proof.deinit();
    const block = ast.blockOf(root);
    for (ast.blockStmts(block)) |s| {
        if (ast.stmtTag(s) != .let_decl or !ast.stmtIsMutable(s)) continue;
        const init = ast.stmtData(s).init;
        if (init == .none) continue;
        const value = ast.withoutGroups(init);
        if (ast.exprTag(value) != .array_literal) continue;
        const binding = res.bindingOf(s);
        if (binding == .none) continue;
        const ty = typing.get(typing.bindingType(binding));
        if (ty != .array) continue;
        switch (ty.array.element) {
            .i8, .i16, .i32, .i64, .u8, .u16, .u32, .u64, .bool_, .f64 => {},
            else => continue,
        }
        const elements = ast.call(value).args;
        if (elements.len == 0) continue;
        var pure = true;
        for (elements) |element| switch (ast.exprTag(ast.withoutGroups(element))) {
            .int_literal, .float_literal, .bool_literal => {},
            else => {
                pure = false;
                break;
            },
        };
        if (!pure) continue;
        try proof.by_binding.put(gpa, binding, @intCast(proof.candidates.items.len));
        try proof.candidates.append(gpa, .{ .initializer = value });
    }
    if (proof.candidates.items.len == 0) return out;
    for (ast.blockStmts(block)) |s| {
        if (ast.stmtTag(s) == .expr_stmt) {
            const expr = ast.withoutGroups(ast.stmtData(s).init);
            if (ast.exprTag(expr) == .while_) {
                if (!try proof.loop(expr)) return out;
                continue;
            }
        }
        if (!try proof.statement(s, null)) return out;
    }
    if (!try proof.expression(block.tail, null)) return out;
    for (proof.candidates.items) |candidate| {
        if (!candidate.rejected and candidate.bound != .none)
            try out.put(gpa, candidate.initializer, {});
    }
    return out;
}

const Proof = struct {
    gpa: std.mem.Allocator,
    ast: *const Ast,
    res: *const resolve.Resolution,
    typing: *const types.Typing,
    by_binding: std.AutoHashMapUnmanaged(resolve.BindingId, u32) = .empty,
    candidates: std.ArrayList(Candidate) = .empty,
    zero: std.AutoHashMapUnmanaged(resolve.BindingId, bool) = .empty,

    fn deinit(self: *Proof) void {
        self.by_binding.deinit(self.gpa);
        self.candidates.deinit(self.gpa);
        self.zero.deinit(self.gpa);
    }

    fn binding(self: *const Proof, expr: node.ExprId) resolve.BindingId {
        if (expr == .none) return .none;
        const at = self.ast.withoutGroups(expr);
        if (self.ast.exprTag(at) != .name_ref) return .none;
        return self.res.targetOf(at);
    }

    fn literal(self: *const Proof, expr: node.ExprId, value: i128) bool {
        if (expr == .none) return false;
        const at = self.ast.withoutGroups(expr);
        if (self.ast.exprTag(at) != .int_literal) return false;
        return switch (self.typing.literalValue(at) orelse return false) {
            .integer => |integer| integer == value,
            .float => false,
        };
    }

    fn statement(self: *Proof, s: node.StmtId, context: ?*Loop) std.mem.Allocator.Error!bool {
        switch (self.ast.stmtTag(s)) {
            .expr_stmt => return self.expression(self.ast.stmtData(s).init, context),
            .let_decl => {
                const init = self.ast.stmtData(s).init;
                const b = self.res.bindingOf(s);
                if (self.by_binding.contains(b)) return true;
                if (!try self.expression(init, context)) return false;
                if (b != .none and self.typing.bindingType(b) == .u64)
                    try self.zero.put(self.gpa, b, self.literal(init, 0));
                return true;
            },
            .defer_stmt, .defer_release, .let_destructure, .let_read_destructure, .err => return false,
        }
    }

    fn loop(self: *Proof, expr: node.ExprId) std.mem.Allocator.Error!bool {
        const pair = self.ast.binary(expr);
        const cond = self.ast.withoutGroups(pair.lhs);
        const body = self.ast.withoutGroups(pair.rhs);
        if (self.ast.exprTag(cond) != .lt or self.ast.exprTag(body) != .block) return false;
        const compare = self.ast.binary(cond);
        const induction = self.binding(compare.lhs);
        const bound = self.binding(compare.rhs);
        if (induction == .none or bound == .none) return false;
        if (!(self.zero.get(induction) orelse false)) return false;
        if (self.typing.bindingType(induction) != .u64 or self.typing.bindingType(bound) != .u64) return false;
        const declaration = self.res.stmtOf(bound);
        if (declaration == .none or self.ast.stmtTag(declaration) != .let_decl or self.ast.stmtIsMutable(declaration)) return false;
        const block = self.ast.blockOf(body);
        const statements = self.ast.blockStmts(block);
        if (statements.len == 0 and block.tail == .none) return false;
        const tail_step = block.tail != .none;
        const step = self.ast.withoutGroups(if (tail_step) block.tail else blk: {
            const last = statements[statements.len - 1];
            if (self.ast.stmtTag(last) != .expr_stmt) return false;
            break :blk self.ast.stmtData(last).init;
        });
        switch (self.ast.exprTag(step)) {
            .assign => {
                const assign = self.ast.binary(step);
                if (self.binding(assign.lhs) != induction) return false;
                const rhs = self.ast.withoutGroups(assign.rhs);
                if (self.ast.exprTag(rhs) != .add) return false;
                const add = self.ast.binary(rhs);
                if (self.binding(add.lhs) != induction or !self.literal(add.rhs, 1)) return false;
            },
            .add_assign => {
                const add = self.ast.binary(step);
                if (self.binding(add.lhs) != induction or !self.literal(add.rhs, 1)) return false;
            },
            else => return false,
        }
        var context: Loop = .{ .induction = induction, .bound = bound };
        defer context.written.deinit(self.gpa);
        for (statements[0 .. statements.len - @intFromBool(!tail_step)]) |s|
            if (!try self.statement(s, &context)) return false;
        for (context.written.items) |i| {
            const candidate = &self.candidates.items[i];
            candidate.pending = false;
            if (!candidate.rejected) candidate.bound = bound;
        }
        try self.zero.put(self.gpa, induction, false);
        return true;
    }

    fn indexed(self: *Proof, expr: node.ExprId, context: ?*Loop, write: bool) std.mem.Allocator.Error!bool {
        const pair = self.ast.binary(expr);
        const b = self.binding(pair.lhs);
        if (self.by_binding.get(b)) |i| {
            const candidate = &self.candidates.items[i];
            if (context) |active| {
                if (self.binding(pair.rhs) != active.induction) {
                    candidate.rejected = true;
                } else if (candidate.bound != .none) {
                    if (candidate.bound != active.bound) candidate.rejected = true;
                } else if (write) {
                    if (!candidate.pending) {
                        try active.written.append(self.gpa, i);
                        candidate.pending = true;
                    }
                } else candidate.rejected = true;
            } else candidate.rejected = true;
            return self.expression(pair.rhs, context);
        }
        return try self.expression(pair.lhs, context) and try self.expression(pair.rhs, context);
    }

    fn expression(self: *Proof, expr: node.ExprId, context: ?*Loop) std.mem.Allocator.Error!bool {
        if (expr == .none) return true;
        const at = self.ast.withoutGroups(expr);
        switch (self.ast.exprTag(at)) {
            .name_ref => {
                if (self.by_binding.get(self.res.targetOf(at))) |i| self.candidates.items[i].rejected = true;
                return true;
            },
            .int_literal, .float_literal, .str_literal, .embed, .embed_bytes, .bool_literal => return true,
            .index => return self.indexed(at, context, false),
            .assign, .add_assign, .sub_assign, .mul_assign, .div_assign, .rem_assign => {
                const pair = self.ast.binary(at);
                const lhs = self.ast.withoutGroups(pair.lhs);
                const b = self.binding(lhs);
                if (context) |active| if (b == active.induction) return false;
                if (self.ast.exprTag(lhs) == .index) {
                    if (self.ast.exprTag(at) != .assign and !try self.indexed(lhs, context, false)) return false;
                    if (!try self.indexed(lhs, context, true)) return false;
                } else if (!try self.expression(lhs, context)) return false;
                if (!try self.expression(pair.rhs, context)) return false;
                if (self.zero.getPtr(b)) |known|
                    known.* = self.ast.exprTag(at) == .assign and self.literal(pair.rhs, 0);
                return true;
            },
            .add, .sub, .mul, .div, .rem, .eq, .ne, .lt, .le, .gt, .ge => {
                const pair = self.ast.binary(at);
                return try self.expression(pair.lhs, context) and try self.expression(pair.rhs, context);
            },
            .negate, .not, .copy_, .field, .variant_ref => return self.expression(self.ast.unaryOperand(at), context),
            .return_ => {
                if (context != null) return false;
                return self.expression(self.ast.unaryOperand(at), context);
            },
            .call, .array_literal => {
                const call = self.ast.call(at);
                if (!try self.expression(call.callee, context)) return false;
                for (call.args) |arg| if (!try self.expression(arg, context)) return false;
                return true;
            },
            .block => {
                const block = self.ast.blockOf(at);
                for (self.ast.blockStmts(block)) |s| if (!try self.statement(s, context)) return false;
                return self.expression(block.tail, context);
            },
            // Unsupported control flow and borrowing invalidate this bounded
            // proof, including uses hidden in closures or delayed cleanup.
            else => return false,
        }
    }
};
