//! Check the witnesses for compiler-generated counted index loops. The CFG,
//! counter writes and lexical scopes establish bounds independently of typing.
const std = @import("std");
const mir_mod = @import("mir.zig");
const Mir = mir_mod.Mir;
const InstId = mir_mod.InstId;
const BlockId = mir_mod.BlockId;
const IndexLoopId = mir_mod.IndexLoopId;

pub const Position = struct { block: ?BlockId = null, order: u32 = std.math.maxInt(u32) };

pub fn indexInstructions(gpa: std.mem.Allocator, mir: *const Mir) ![]Position {
    const positions = try gpa.alloc(Position, mir.insts.len);
    @memset(positions, .{});
    for (0..mir.blocks.len) |i| {
        const block = BlockId.at(@intCast(i));
        for (mir.instsOf(block), 0..) |inst, order|
            positions[inst.index()] = .{ .block = block, .order = @intCast(order) };
        positions[mir.terminatorOf(block).index()] = .{ .block = block, .order = @intCast(mir.instsOf(block).len) };
    }
    return positions;
}

pub const Result = union(enum) { valid: Facts, invalid: []const u8 };

/// Function-sized indexes, rebuilt from an already structurally checked MIR.
/// Construction and validation visit each instruction, block, edge and loop
/// once. No per-block table is sized by the function's local count.
pub const Facts = struct {
    positions: []const Position,
    owns_positions: bool = false,
    local_loops: []IndexLoopId,
    header_loops: []IndexLoopId,
    mir: *const Mir,

    pub fn deinit(self: *Facts, gpa: std.mem.Allocator) void {
        if (self.owns_positions) gpa.free(self.positions);
        gpa.free(self.local_loops);
        gpa.free(self.header_loops);
        self.* = undefined;
    }

    pub fn blockOf(self: Facts, inst: InstId) BlockId {
        return self.positions[inst.index()].block.?;
    }

    pub fn scope(self: Facts, block: BlockId) IndexLoopId {
        return if (self.mir.block_index_loops.len == 0) .none else self.mir.block_index_loops[block.index()];
    }

    pub fn contains(self: Facts, outer: IndexLoopId, inner: IndexLoopId) bool {
        return inner != .none and inner.index() >= outer.index() and inner.index() < self.mir.index_loops[outer.index()].past_last;
    }

    pub fn limit(self: Facts, id: IndexLoopId) u64 {
        return @intCast(self.mir.constantOf(self.mir.index_loops[id.index()].limit));
    }

    /// Only a use inside the guarded body excludes the final counter value.
    /// A zero-length loop has no reachable body use.
    pub fn counterBound(self: Facts, position: InstId, use: InstId) ?struct { max: u64, empty: bool } {
        if (self.mir.tagOf(position) != .load) return null;
        const loop_id = self.local_loops[self.mir.localOf(position).index()];
        if (loop_id == .none or self.mir.index_loops[loop_id.index()].position != position) return null;
        const count = self.limit(loop_id);
        const inside = self.contains(loop_id, self.scope(self.blockOf(use)));
        return .{ .max = if (inside and count != 0) count - 1 else count, .empty = inside and count == 0 };
    }

    fn invalid(self: Facts) ?[]const u8 {
        const mir = self.mir;
        if (scopeError(mir)) |reason| return reason;
        var enclosing: IndexLoopId = .none;
        for (mir.index_loops, 0..) |loop, i| {
            while (enclosing != .none and mir.index_loops[enclosing.index()].past_last <= i)
                enclosing = mir.index_loops[enclosing.index()].parent;
            if (loop.parent != enclosing or loop.past_last <= i or loop.past_last > mir.index_loops.len or
                (enclosing != .none and loop.past_last > mir.index_loops[enclosing.index()].past_last))
                return "index loop nesting is not a depth-first interval";
            const id = IndexLoopId.at(@intCast(i));
            enclosing = id;
            for ([_]BlockId{ loop.header, loop.body, loop.exit }) |block|
                if (block.index() >= mir.blocks.len) return "index loop names no block";
            for ([_]InstId{ loop.initialize, loop.position, loop.limit, loop.step }) |inst|
                if (inst.index() >= mir.insts.len) return "index loop names no instruction";
            if (loop.header == mir.entry or loop.header == loop.body or loop.header == loop.exit or loop.body == loop.exit)
                return "index loop control blocks are not distinct";
            if (self.header_loops[loop.header.index()] != .none) return "two index loops share a header";
            self.header_loops[loop.header.index()] = id;
            if (self.scope(loop.header) != loop.parent or self.scope(loop.body) != id or self.scope(loop.exit) != loop.parent)
                return "index loop control blocks have incompatible scopes";
            if (mir.tagOf(loop.position) != .load or mir.typeOf(loop.position) != .u64 or
                mir.tagOf(loop.limit) != .constant or mir.typeOf(loop.limit) != .u64 or
                mir.constantOf(loop.limit) < 0 or mir.constantOf(loop.limit) > std.math.maxInt(u64))
                return "index loop counter and limit are not UInt64 values";
            const local = mir.localOf(loop.position);
            if (local.index() < mir.param_count or mir.locals[local.index()] != .u64 or
                mir.slotRoleOf(local) != .value or self.local_loops[local.index()] != .none)
                return "index loop counter does not have its own UInt64 slot";
            self.local_loops[local.index()] = id;
            const header = mir.instsOf(loop.header);
            if (header.len != 3 or header[0] != loop.position or header[1] != loop.limit or mir.tagOf(header[2]) != .cmp_lt)
                return "index loop header is not a counted comparison";
            const comparison = mir.binaryOf(header[2]);
            if (comparison.lhs != loop.position or comparison.rhs != loop.limit)
                return "index loop header compares different values";
            const terminal = mir.terminatorOf(loop.header);
            if (mir.tagOf(terminal) != .branch) return "index loop header does not branch";
            const branch = mir.branchOf(terminal);
            if (branch.cond != header[2] or branch.then_block != loop.body or branch.else_block != loop.exit)
                return "index loop header does not guard its body";
            for ([_]InstId{ loop.initialize, loop.step }) |store|
                if (mir.tagOf(store) != .store or mir.storeOf(store).local != local)
                    return "index loop does not initialize and advance its counter";
            const zero = mir.storeOf(loop.initialize).value;
            if (mir.tagOf(zero) != .constant or mir.typeOf(zero) != .u64 or mir.constantOf(zero) != 0)
                return "index loop counter does not start at zero";
            const next = mir.storeOf(loop.step).value;
            if (mir.tagOf(next) != .add or mir.typeOf(next) != .u64) return "index loop counter does not advance by one";
            const increment = mir.binaryOf(next);
            if (increment.lhs != loop.position or mir.tagOf(increment.rhs) != .constant or
                mir.typeOf(increment.rhs) != .u64 or mir.constantOf(increment.rhs) != 1)
                return "index loop counter does not advance by one";
            const initial_block = self.blockOf(loop.initialize);
            const step_block = self.blockOf(loop.step);
            if (self.scope(initial_block) != loop.parent or self.scope(step_block) != id)
                return "index loop counter writes lie outside their scopes";
            for ([_]InstId{ loop.initialize, loop.step }) |store| {
                const block = self.blockOf(store);
                const instructions = mir.instsOf(block);
                const last = mir.terminatorOf(block);
                if (instructions.len == 0 or instructions[instructions.len - 1] != store or
                    mir.tagOf(last) != .jump or mir.targetOf(last) != loop.header)
                    return "index loop counter write does not enter its header";
            }
        }
        for (0..mir.insts.len) |i| {
            const inst = InstId.at(@intCast(i));
            switch (mir.tagOf(inst)) {
                .load, .store, .addr_of => {
                    const local = if (mir.tagOf(inst) == .store) mir.storeOf(inst).local else mir.localOf(inst);
                    const loop_id = self.local_loops[local.index()];
                    if (loop_id != .none) {
                        const loop = mir.index_loops[loop_id.index()];
                        if (inst != loop.initialize and inst != loop.position and inst != loop.step)
                            return "index loop counter has another access";
                    }
                },
                else => {},
            }
        }
        for (0..mir.blocks.len) |i| {
            const source = BlockId.at(@intCast(i));
            const terminal = mir.terminatorOf(source);
            switch (mir.tagOf(terminal)) {
                .jump => if (!self.validEdge(source, mir.targetOf(terminal))) return "index loop has an unguarded control-flow edge",
                .branch => {
                    const branch = mir.branchOf(terminal);
                    if (!self.validEdge(source, branch.then_block) or !self.validEdge(source, branch.else_block))
                        return "index loop has an unguarded control-flow edge";
                },
                else => {},
            }
        }
        return null;
    }

    fn validEdge(self: Facts, source: BlockId, destination: BlockId) bool {
        const mir = self.mir;
        const header_loop = self.header_loops[destination.index()];
        if (header_loop != .none) {
            const loop = mir.index_loops[header_loop.index()];
            return source == self.blockOf(loop.initialize) or source == self.blockOf(loop.step);
        }
        const from = self.scope(source);
        const to = self.scope(destination);
        if (from == to) return true;
        if (to == .none) return false;
        const entered = mir.index_loops[to.index()];
        return source == entered.header and destination == entered.body;
    }
};

/// Basic MIR reference/payload validation must precede this check. Metadata's
/// own handles are validated before they are dereferenced here.
pub fn analyze(gpa: std.mem.Allocator, mir: *const Mir) std.mem.Allocator.Error!Result {
    const positions = try indexInstructions(gpa, mir);
    var retained = false;
    defer if (!retained) gpa.free(positions);
    var result = try analyzeUsingPositions(gpa, mir, positions);
    if (result == .valid) {
        result.valid.owns_positions = true;
        retained = true;
    }
    return result;
}

pub fn scopeError(mir: *const Mir) ?[]const u8 {
    if ((mir.block_index_loops.len != 0 and mir.block_index_loops.len != mir.blocks.len) or
        (mir.index_loops.len != 0 and mir.block_index_loops.len == 0))
        return "index loop scopes do not cover the blocks";
    for (mir.block_index_loops) |id|
        if (id != .none and id.index() >= mir.index_loops.len) return "index loop scope names no loop";
    if (mir.block_index_loops.len != 0 and mir.block_index_loops[mir.entry.index()] != .none)
        return "entry lies inside an index loop body";
    return null;
}

pub fn analyzeUsingPositions(gpa: std.mem.Allocator, mir: *const Mir, positions: []const Position) std.mem.Allocator.Error!Result {
    var facts: Facts = .{ .positions = positions, .local_loops = &.{}, .header_loops = &.{}, .mir = mir };
    var retained = false;
    defer if (!retained) facts.deinit(gpa);
    facts.local_loops = try gpa.alloc(IndexLoopId, mir.locals.len);
    facts.header_loops = try gpa.alloc(IndexLoopId, mir.blocks.len);
    @memset(facts.local_loops, .none);
    @memset(facts.header_loops, .none);
    if (facts.invalid()) |reason| return .{ .invalid = reason };
    retained = true;
    return .{ .valid = facts };
}

const Mutation = enum { none, parameter_counter, nonzero_start, wrong_step, extra_read, extra_write, escape, wrong_guard, wrong_scope, unguarded_entry };

fn fixture(gpa: std.mem.Allocator, count: u64, mutation: Mutation) !Mir {
    const span = @import("../support/span.zig").Span.empty;
    var builder = Mir.Builder.init(gpa);
    defer builder.deinit();
    builder.return_type = .u64;
    if (mutation == .parameter_counter) builder.param_count = 1;
    const counter = try builder.addLocal(.u64, .value);
    const entry = try builder.addBlock();
    const header = try builder.addBlock();
    const body = try builder.addBlock();
    const exit = try builder.addBlock();
    const zero = try builder.addInst(entry, .{ .tag = .constant, .ty = .u64, .span = span, .data = .{ .constant = if (mutation == .nonzero_start) 1 else 0 } });
    const initial = try builder.addInst(entry, .{ .tag = .store, .ty = .u64, .span = span, .data = .{ .store = .{ .local = counter, .value = zero } } });
    _ = try builder.setTerminator(entry, .{ .tag = .jump, .ty = .unit, .span = span, .data = .{ .target = header } });
    const position = try builder.addInst(header, .{ .tag = .load, .ty = .u64, .span = span, .data = .{ .local = counter } });
    const limit = try builder.addInst(header, .{ .tag = .constant, .ty = .u64, .span = span, .data = .{ .constant = count } });
    const less = try builder.addInst(header, .{ .tag = if (mutation == .wrong_guard) .cmp_le else .cmp_lt, .ty = .bool_, .span = span, .data = .{ .binary = .{ .lhs = position, .rhs = limit } } });
    _ = try builder.setTerminator(header, .{ .tag = .branch, .ty = .unit, .span = span, .data = .{ .branch = .{ .cond = less, .then_block = body, .else_block = exit } } });
    const loop = try builder.beginIndexLoop(.{ .parent = .none, .initialize = initial, .position = position, .limit = limit, .header = header, .body = body, .exit = exit });
    if (mutation == .extra_read or mutation == .escape)
        _ = try builder.addInst(body, .{ .tag = if (mutation == .escape) .addr_of else .load, .ty = .u64, .span = span, .data = .{ .local = counter } });
    if (mutation == .extra_write)
        _ = try builder.addInst(body, .{ .tag = .store, .ty = .u64, .span = span, .data = .{ .store = .{ .local = counter, .value = zero } } });
    const one = try builder.addInst(body, .{ .tag = .constant, .ty = .u64, .span = span, .data = .{ .constant = if (mutation == .wrong_step) 2 else 1 } });
    const next = try builder.addInst(body, .{ .tag = .add, .ty = .u64, .span = span, .data = .{ .binary = .{ .lhs = position, .rhs = one } } });
    const step = try builder.addInst(body, .{ .tag = .store, .ty = .u64, .span = span, .data = .{ .store = .{ .local = counter, .value = next } } });
    _ = try builder.setTerminator(body, .{ .tag = .jump, .ty = .unit, .span = span, .data = .{ .target = header } });
    builder.endIndexLoop(loop, step);
    _ = try builder.setTerminator(exit, .{ .tag = .ret, .ty = .unit, .span = span, .data = .{ .unary = zero } });
    if (mutation == .wrong_scope) builder.block_index_loops.items[body.index()] = .none;
    const root = if (mutation == .unguarded_entry) block: {
        const bypass = try builder.addBlock();
        _ = try builder.setTerminator(bypass, .{ .tag = .jump, .ty = .unit, .span = span, .data = .{ .target = body } });
        break :block bypass;
    } else entry;
    return builder.finish(root, .from(0));
}

test "counted index loop bounds distinguish header, body and empty iterations" {
    const testing = std.testing;
    const gpa = testing.allocator;
    for ([_]u64{ 0, 1, 4, std.math.maxInt(u32), std.math.maxInt(u64) }) |count| {
        var mir = try fixture(gpa, count, .none);
        defer mir.deinit(gpa);
        var result = try analyze(gpa, &mir);
        try testing.expect(result == .valid);
        defer result.valid.deinit(gpa);
        const loop = mir.index_loops[0];
        const at_header = result.valid.counterBound(loop.position, loop.position).?;
        const inside = result.valid.counterBound(loop.position, loop.step).?;
        try testing.expectEqual(count, at_header.max);
        try testing.expect(!at_header.empty);
        try testing.expectEqual(if (count == 0) 0 else count - 1, inside.max);
        try testing.expectEqual(count == 0, inside.empty);
    }
}

test "counted index loop bounds reject forged guards, writes, aliases and entry edges" {
    const testing = std.testing;
    const gpa = testing.allocator;
    for (std.meta.tags(Mutation)) |mutation| {
        if (mutation == .none) continue;
        var mir = try fixture(gpa, 4, mutation);
        defer mir.deinit(gpa);
        var result = try analyze(gpa, &mir);
        if (result == .valid) {
            defer result.valid.deinit(gpa);
            std.debug.print("accepted forged index loop: {s}\n", .{@tagName(mutation)});
            return error.TestUnexpectedResult;
        }
    }
}

/// Shared compiler-test fixture; production does not instantiate it.
pub const Test = struct {
    pub fn counted(gpa: std.mem.Allocator, count: u64) !Mir {
        return fixture(gpa, count, .none);
    }
};
