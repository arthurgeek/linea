//! The soundness matrix: every operation that may move, grow or free an
//! owner's storage, met with every live observation of that storage, at every
//! kind of place the two can meet.
//!
//! Each cell is written twice. The `live` program uses the observation after
//! the operation, so the language has to refuse it by [O-Borrow]; accepting
//! it is a failure, decided before anything runs. Nothing would catch it at
//! run time: a read of storage the operation left allocated returns plausible
//! values, and the generated code carries no sanitizer instrumentation. The
//! `ended` program makes the observation's last use come before the
//! operation, so it must be accepted, built, and run clean. The pair is what
//! keeps the matrix from passing vacuously: a template the compiler refuses
//! for a reason unrelated to the observation refuses its `ended` program too,
//! and that is a failure.
//!
//! The owner is a whole local, a vector held in a structure's field -- changed
//! through the field or through an `inout` of the whole structure -- a fixed
//! array, or a handle to an object C holds, whose text C answers, so a live
//! observation is held against every way one place can overlap another.
//!
//! One meeting puts the observation and the operation in one call: the
//! observation is lent to the call by one argument, and the operation runs
//! inside another, or is the argument a `sink` parameter takes. The owner
//! itself lent beside a take of it is an observation of its own, refused by
//! [O-Move] rather than [O-Borrow], since what the call holds is the place
//! and not a view of it.
//!
//! Cells are enumerated rather than drawn. The cross product is a few hundred
//! programs, each compiled once against the checked library, and only the
//! programs the compiler accepts are built; the `ended` half is built once and
//! then served from the outcome cache.

const std = @import("std");
const testing = std.testing;

comptime {
    _ = Storage;
    _ = Operation;
    _ = Observation;
    _ = Cell;
}

/// What owns the storage an operation changes.
pub const Storage = enum {
    vec,
    map,
    /// A local the closure holding an `[inout]` lend writes through.
    scalar,
    /// A vector held in a field of a structure, `holder.items`, which an
    /// operation may change through the field or through an `inout` of the
    /// whole structure.
    field,
    /// A fixed array, whose storage is the local itself.
    array,
    /// A vector lent by a `for inout` walk, `for inout owner in owners`: the
    /// owner is the walk's binder, and every operation and observation sits
    /// inside the walk's body.
    walked,
    /// A handle to a block C allocates, sealed in the program's own root,
    /// which its manifest grants `extern`. C answers text inside the block.
    handle,

    /// How the cell's program names the owner where the template says
    /// `owner`.
    fn owner(self: Storage) []const u8 {
        return switch (self) {
            .field => "holder.items",
            else => "owner",
        };
    }

    /// The local an `[inout]` capture of the owner lends: the whole structure
    /// where the owner is one of its fields.
    fn root(self: Storage) []const u8 {
        return switch (self) {
            .field => "holder",
            else => "owner",
        };
    }

    /// Statements that give a vector or map the three elements an observation
    /// reads.
    fn fill(self: Storage) []const u8 {
        return switch (self) {
            .vec, .field, .walked =>
            \\&owner.push(1).unwrap()
            \\&owner.push(2).unwrap()
            \\&owner.push(3).unwrap()
            ,
            .map =>
            \\&owner.insert(1, 10).unwrap().release()
            \\&owner.insert(2, 20).unwrap().release()
            \\&owner.insert(3, 30).unwrap().release()
            ,
            .scalar, .array, .handle => unreachable,
        };
    }

    /// The manifest the program is compiled under, where it needs one: a
    /// handle is a type only a root trusted with C may seal.
    fn manifest(self: Storage) ?[]const u8 {
        return switch (self) {
            .handle => "{ \"extern\": [\".\"] }",
            else => null,
        };
    }

    test "a field owner is named by its path and lent by its structure" {
        try testing.expectEqualStrings("holder.items", Storage.field.owner());
        try testing.expectEqualStrings("holder", Storage.field.root());
        try testing.expectEqualStrings("owner", Storage.array.owner());
    }
};

/// An owner operation that may move, grow or free the owner's storage.
pub const Operation = enum {
    push,
    pop,
    remove,
    clear,
    truncate,
    reserve,
    index_write,
    release,
    drain,
    finish,
    insert,
    remove_key,
    merge,
    update,
    release_map,
    drain_map,
    assign,
    compound_assign,
    /// `reset(&holder)`, which clears the field through an `inout` of the
    /// whole structure.
    reset_holder,
    /// A push through the field's own path.
    field_push,
    /// An assignment to one element of a fixed array.
    element_write,
    /// An assignment of a whole new array.
    array_assign,
    /// A push through a `for inout` walk's binder.
    walk_push,
    /// A clear through a `for inout` walk's binder.
    walk_clear,
    /// An `extern` call taking the handle without `read`, which lets C change
    /// the block: `memset` clears it.
    handle_change,
    /// The handle given to C to free, then a new block opened.
    handle_close,
    /// The handle lent `inout` to a function that frees it and opens another.
    handle_renew,

    pub fn storage(self: Operation) Storage {
        return switch (self) {
            .push, .pop, .remove, .clear, .truncate, .reserve, .index_write, .release, .drain, .finish => .vec,
            .insert, .remove_key, .merge, .update, .release_map, .drain_map => .map,
            .assign, .compound_assign => .scalar,
            .reset_holder, .field_push => .field,
            .element_write, .array_assign => .array,
            .walk_push, .walk_clear => .walked,
            .handle_change, .handle_close, .handle_renew => .handle,
        };
    }

    test "an operation changes the storage it is written against" {
        try testing.expectEqual(Storage.vec, Operation.push.storage());
        try testing.expectEqual(Storage.map, Operation.merge.storage());
        try testing.expectEqual(Storage.scalar, Operation.assign.storage());
        try testing.expectEqual(Storage.field, Operation.reset_holder.storage());
        try testing.expectEqual(Storage.array, Operation.element_write.storage());
    }

    /// Whether the operation consumes the owner. Outside a `defer` the owner
    /// is opened again right after, so the program can go on using it.
    pub fn consumes(self: Operation) bool {
        return switch (self) {
            .release, .drain, .finish, .release_map, .drain_map, .handle_close => true,
            else => false,
        };
    }

    /// What opens the owner again after a consuming operation, so the program
    /// can go on using it.
    fn reopen(self: Operation) []const u8 {
        return switch (self) {
            .release, .drain, .finish => "owner = Vec.new()",
            .release_map, .drain_map => "owner = collections.Map.new()",
            .handle_close => "owner = calloc(1, 16)",
            else => unreachable,
        };
    }

    test "an operation that frees the owner whole consumes it" {
        try testing.expect(Operation.release.consumes());
        try testing.expect(Operation.drain_map.consumes());
        try testing.expect(!Operation.clear.consumes());
        try testing.expect(!Operation.assign.consumes());
    }

    /// Whether running the operation twice leaves fewer elements than an
    /// observation made afterwards reads.
    fn shrinks(self: Operation) bool {
        return switch (self) {
            .pop, .remove, .clear, .truncate, .release, .drain, .finish, .release_map, .drain_map, .reset_holder, .walk_clear => true,
            else => false,
        };
    }

    /// The operation as statements. `owner` names the owner.
    fn statements(self: Operation) []const u8 {
        return switch (self) {
            .push => "&owner.push(4).unwrap()",
            .pop => "let _popped = &owner.pop()",
            .remove => "let _removed = &owner.remove(0)",
            .clear => "&owner.clear()",
            .truncate => "&owner.truncate(1)",
            .reserve => "&owner.reserve(64).unwrap()",
            .index_write => "owner[0] = 9",
            .release => "owner.release()\nowner = Vec.new()",
            .drain => "owner.drain().release()\nowner = Vec.new()",
            .finish =>
            \\match owner.finish() {
            \\    Ok(_) => {},
            \\    Err(back) => back.release(),
            \\}
            \\owner = Vec.new()
            ,
            .insert => "&owner.insert(4, 40).unwrap().release()",
            .remove_key => "let _removed = &owner.remove(1)",
            .merge => "&owner.merge(2, 5, |sink held: UInt64, sink incoming: UInt64| held + incoming).unwrap()",
            .update => "let _updated = &owner.update(2, |sink value: UInt64| value + 1)",
            .release_map => "owner.release()\nowner = collections.Map.new()",
            .drain_map => "owner.drain().release()\nowner = collections.Map.new()",
            .assign => "owner = 5",
            .compound_assign => "owner += 1",
            .reset_holder => "reset(&holder)",
            .field_push => "&owner.push(4).unwrap()",
            .element_write => "owner[0] = 9",
            .array_assign => "owner = [UInt64(4), 5, 6]",
            .walk_push => "&owner.push(4).unwrap()",
            .walk_clear => "&owner.clear()",
            .handle_change => "let _cleared = memset(owner, 0, 16)",
            .handle_close => "free(owner)\nowner = calloc(1, 16)",
            .handle_renew => "renew(&owner)",
        };
    }

    /// The operation as the one expression a `defer` takes, or null where it
    /// is an assignment and so has no expression form. A result nothing reads
    /// is taken apart by a `match` that discards it, which is an expression
    /// where `let _ =` is not. A consuming operation deferred settles the owner
    /// for good.
    fn expression(self: Operation) ?[]const u8 {
        return switch (self) {
            .push => "&owner.push(4).unwrap()",
            .pop => "match &owner.pop() { _ => {} }",
            .remove => "match &owner.remove(0) { _ => {} }",
            .clear => "&owner.clear()",
            .truncate => "&owner.truncate(1)",
            .reserve => "&owner.reserve(64).unwrap()",
            .release, .release_map => "owner.release()",
            .drain, .drain_map => "owner.drain().release()",
            .finish =>
            \\match owner.finish() {
            \\    Ok(_) => {},
            \\    Err(back) => back.release(),
            \\}
            ,
            .insert => "&owner.insert(4, 40).unwrap().release()",
            .remove_key => "match &owner.remove(1) { _ => {} }",
            .merge => "&owner.merge(2, 5, |sink held: UInt64, sink incoming: UInt64| held + incoming).unwrap()",
            .update => "match &owner.update(2, |sink value: UInt64| value + 1) { _ => {} }",
            .reset_holder => "reset(&holder)",
            .field_push, .walk_push => "&owner.push(4).unwrap()",
            .walk_clear => "&owner.clear()",
            .handle_change => "match memset(owner, 0, 16) { _ => {} }",
            .handle_close => "free(owner)",
            .handle_renew => "renew(&owner)",
            .index_write, .assign, .compound_assign, .element_write, .array_assign => null,
        };
    }

    /// The operation as the statements of a block written as a call's
    /// argument, ending in the block's value: a consuming one gives the owner
    /// up there and the owner is opened again after the call, since the
    /// argument may not assign a place the call is lent.
    fn inArgument(self: Operation) []const u8 {
        if (self.consumes()) return self.expression().?;
        return self.statements();
    }
};

/// The operation as statements over the owner `name`, for a mutation that
/// writes one into a program whose owners have names of their own.
pub fn operationText(gpa: std.mem.Allocator, operation: Operation, name: []const u8) ![]u8 {
    return std.mem.replaceOwned(u8, gpa, operation.statements(), "owner", name);
}

test "an operation is written over the owner it is given" {
    const text = try operationText(testing.allocator, .release, "v1");
    defer testing.allocator.free(text);
    try testing.expectEqualStrings("v1.release()\nv1 = Vec.new()", text);
}

/// A live observation of an owner's storage.
pub const Observation = enum {
    slice,
    /// A slice held in a newtype, whose construction keeps what the slice
    /// observes.
    wrapped,
    subspan,
    element,
    iterator,
    mapped,
    filtered,
    lent_walk,
    read_capture,
    inout_capture,
    value_view,
    entries,
    map_inout_capture,
    scalar_inout_capture,
    scalar_read_capture,
    /// A `for` loop over the vector's slice whose body never reads an item:
    /// `for _ in v.as_slice() { v.push(x) }` is the walk itself observing the
    /// storage, with no element use after the operation to refuse it.
    bare_slice,
    /// The same walk over the slice's iterator.
    bare_iterator,
    /// The same walk over an adapter of the slice.
    bare_mapped,
    /// The same walk over a map's entries.
    bare_entries,
    /// Text C answers from inside the block a handle holds.
    text,
    /// The owner itself, lent to a call beside an argument that takes it. It
    /// is made by the call, so it meets an operation only there.
    argument,

    /// Whether the observation can be made of the storage. A vector held in
    /// a field and a fixed array are observed as a vector is, through their
    /// slice; an `[inout]` capture of either is not, since its closure body
    /// pushes.
    pub fn fits(self: Observation, storage: Storage) bool {
        return switch (self) {
            .slice, .wrapped, .subspan, .element, .iterator, .mapped, .filtered, .lent_walk, .read_capture => storage == .vec or storage == .field or storage == .array or storage == .walked,
            .bare_slice, .bare_iterator, .bare_mapped => storage == .vec or storage == .field or storage == .array or storage == .walked,
            .inout_capture => storage == .vec or storage == .walked,
            .value_view, .entries, .map_inout_capture, .bare_entries => storage == .map,
            .scalar_inout_capture, .scalar_read_capture => storage == .scalar,
            .text => storage == .handle,
            .argument => storage == .vec or storage == .map or storage == .handle,
        };
    }

    test "an observation of a slice fits every storage that has one" {
        for ([_]Storage{ .vec, .field, .array }) |storage| try testing.expect(Observation.bare_slice.fits(storage));
        try testing.expect(!Observation.inout_capture.fits(.field));
        try testing.expect(!Observation.value_view.fits(.vec));
        try testing.expect(Observation.scalar_read_capture.fits(.scalar));
    }

    /// Statements that make `seen` observe the owner.
    fn open(self: Observation) []const u8 {
        return switch (self) {
            .slice => "let seen = owner.as_slice()",
            .wrapped => "let seen = Wrapped(owner.as_slice())",
            .subspan => "let seen = owner.as_slice().subspan(1, 2).unwrap()",
            .element => "let seen = owner.as_slice().get(2).unwrap()",
            .iterator, .lent_walk => "var seen = owner.as_slice().iterate()",
            .mapped => "var seen = owner.as_slice().map(|sink item: borrow UInt64| -> UInt64 where carries() { *item + 1 })",
            .filtered => "var seen = owner.as_slice().filter(|item| *item > 1)",
            .read_capture => "let view = owner.as_slice()\nlet seen = [view] || view[0]",
            .inout_capture =>
            \\var seen = inout [inout owner] || {
            \\    &owner.push(7).unwrap()
            \\    owner.length()
            \\}
            ,
            .value_view => "let seen = owner.get(2).unwrap()",
            .entries => "var seen = owner.entries()",
            .map_inout_capture =>
            \\var seen = inout [inout owner] || {
            \\    &owner.insert(5, 50).unwrap().release()
            \\    owner.length()
            \\}
            ,
            .scalar_inout_capture =>
            \\var seen = inout [inout owner] || {
            \\    owner += 1
            \\    owner
            \\}
            ,
            .scalar_read_capture => "let seen = [owner] || owner",
            .text => "let seen = strchr(owner, 0)",
            // The walk is opened by the loop that walks it, and the owner is
            // lent by the call it is an argument of.
            .bare_slice, .bare_iterator, .bare_mapped, .bare_entries, .argument => "",
        };
    }

    /// The sequence a bare walk names in its `for`, or null where the
    /// observation is opened by a statement of its own.
    fn bare(self: Observation) ?[]const u8 {
        return switch (self) {
            .bare_slice => "owner.as_slice()",
            .bare_iterator => "owner.as_slice().iterate()",
            .bare_mapped => "owner.as_slice().map(|sink item: borrow UInt64| -> UInt64 where carries() { *item + 1 })",
            .bare_entries => "owner.entries()",
            else => null,
        };
    }

    /// One read through `seen`, as an expression of type `UInt64`.
    fn read(self: Observation) []const u8 {
        return switch (self) {
            .slice => "seen[0]",
            .wrapped => "first(seen)",
            .subspan => "seen[1]",
            .element, .value_view => "*seen",
            .iterator, .lent_walk, .filtered => "match Iterator.next(&seen) { Some(item) => *item, None => 0 }",
            .mapped => "match Iterator.next(&seen) { Some(item) => item, None => 0 }",
            .read_capture, .scalar_read_capture => "seen()",
            .inout_capture, .map_inout_capture, .scalar_inout_capture => "&seen()",
            .entries => "match Iterator.next(&seen) { Some(entry) => entry.value, None => 0 }",
            .text => "seen.length()",
            // A bare walk is used only by walking it, inside a `for` meeting,
            // and a lent owner only by the call it is lent to.
            .bare_slice, .bare_iterator, .bare_mapped, .bare_entries, .argument => unreachable,
        };
    }

    /// What the call of a `one_call` meeting is lent: the observation, or the
    /// owner itself.
    fn lent(self: Observation) []const u8 {
        return if (self == .argument) "owner" else "seen";
    }

    /// The rule that refuses the observation used across the operation: a
    /// view or capture is ended by it, and the owner lent itself is a place
    /// the call holds while another argument takes it.
    pub fn refusal(self: Observation) []const u8 {
        return if (self == .argument) "O-Move" else "O-Borrow";
    }

    /// How a `for` loop walks `seen`, where it can: the sequence it names and
    /// the item's value inside the body.
    fn walk(self: Observation) ?struct { sequence: []const u8, item: []const u8 } {
        return switch (self) {
            .slice, .subspan, .iterator, .filtered => .{ .sequence = "seen", .item = "*item" },
            .lent_walk => .{ .sequence = "&seen", .item = "*item" },
            .mapped => .{ .sequence = "seen", .item = "item" },
            .entries => .{ .sequence = "seen", .item = "item.value" },
            .element, .wrapped, .read_capture, .inout_capture, .value_view, .map_inout_capture, .scalar_inout_capture, .scalar_read_capture => null,
            .bare_slice, .bare_iterator, .bare_mapped, .bare_entries, .text, .argument => null,
        };
    }
};

/// Where the operation sits while the observation is live.
pub const Meeting = enum {
    straight,
    for_body,
    while_body,
    closure_body,
    /// Between two calls of a closure holding the owner lent `inout`: the
    /// observation is made after the first call and the second call is the
    /// operation, as `&act(); let seen = ...; &act()`. Reading the owner to
    /// make the observation ends the closure's lend, so the observation
    /// cannot end before the second call; the `ended` program instead makes
    /// it after the closure's last call.
    closure_between,
    deferred,
    match_arm,
    /// In one call: the observation is lent to `meet` by its first argument,
    /// and the operation runs inside the second, as a block, or is the second
    /// where a `sink` parameter takes the owner. The `ended` program lends the
    /// observation to one call and runs the operation after it.
    one_call,

    fn loops(self: Meeting) bool {
        return self == .for_body or self == .while_body;
    }
};

/// Whether the observation is used after the operation.
pub const Liveness = enum { live, ended };

pub const Cell = struct {
    operation: Operation,
    observation: Observation,
    meeting: Meeting,

    /// Whether the cell is a program worth writing.
    ///
    /// An operation meets only observations of its own kind of storage. A
    /// consuming operation inside a loop is refused by [O-Loop] whatever the
    /// observation does, so neither program of the pair would say anything
    /// about the observation. An assignment has no expression form, so it
    /// cannot be the call a `defer` schedules. A bare walk observes only while
    /// its loop runs, so it meets an operation only inside that loop's body.
    pub fn applies(self: Cell) bool {
        if (!self.observation.fits(self.operation.storage())) return false;
        if (self.observation.bare() != null and self.meeting != .for_body) return false;
        if (self.operation.consumes() and self.meeting.loops()) return false;
        if (self.meeting == .deferred and self.operation.expression() == null) return false;
        // A second `inout` capture of the place the closure holds is refused
        // whatever the observation does.
        if (self.meeting == .closure_between and (self.observation == .inout_capture or self.observation == .map_inout_capture or self.observation == .scalar_inout_capture)) return false;
        // The owner lent itself exists only in the call it is lent to, and
        // meets only what takes it there: an operation that writes it inside
        // another argument is [N-Aliased], whatever the call holds.
        if (self.observation == .argument) return self.meeting == .one_call and self.operation.consumes();
        // A walk is used by walking it, which no call does.
        if (self.meeting == .one_call and self.observation == .lent_walk) return false;
        return true;
    }

    /// The rule that refuses the cell's `live` program.
    pub fn refusal(self: Cell) []const u8 {
        return self.observation.refusal();
    }

    /// The manifest both of the cell's programs are compiled under, or null.
    pub fn manifest(self: Cell) ?[]const u8 {
        return self.operation.storage().manifest();
    }

    test "a cell applies only where its program can say something about the observation" {
        try testing.expect((Cell{ .operation = .push, .observation = .bare_slice, .meeting = .for_body }).applies());
        try testing.expect(!(Cell{ .operation = .push, .observation = .bare_slice, .meeting = .straight }).applies());
        try testing.expect(!(Cell{ .operation = .push, .observation = .value_view, .meeting = .straight }).applies());
        try testing.expect(!(Cell{ .operation = .release, .observation = .slice, .meeting = .while_body }).applies());
        try testing.expect(!(Cell{ .operation = .index_write, .observation = .slice, .meeting = .deferred }).applies());
        try testing.expect((Cell{ .operation = .release, .observation = .argument, .meeting = .one_call }).applies());
        try testing.expect(!(Cell{ .operation = .push, .observation = .argument, .meeting = .one_call }).applies());
        try testing.expect(!(Cell{ .operation = .release, .observation = .argument, .meeting = .straight }).applies());
        try testing.expect(!(Cell{ .operation = .push, .observation = .lent_walk, .meeting = .one_call }).applies());
    }

    test "the owner lent itself is refused as a take of what a call holds" {
        try testing.expectEqualStrings("O-Move", (Cell{ .operation = .release, .observation = .argument, .meeting = .one_call }).refusal());
        try testing.expectEqualStrings("O-Borrow", (Cell{ .operation = .release, .observation = .slice, .meeting = .one_call }).refusal());
        try testing.expectEqualStrings("{ \"extern\": [\".\"] }", (Cell{ .operation = .handle_close, .observation = .text, .meeting = .straight }).manifest().?);
        try testing.expect((Cell{ .operation = .push, .observation = .slice, .meeting = .straight }).manifest() == null);
    }

    /// The cell's name, which is also how a failure names it.
    pub fn format(self: Cell, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        try writer.print("{s}/{s}/{s}/{s}", .{
            @tagName(self.operation.storage()),
            @tagName(self.operation),
            @tagName(self.observation),
            @tagName(self.meeting),
        });
    }

    test "a cell is named by its storage, operation, observation and meeting" {
        var buffer: [128]u8 = undefined;
        const cell: Cell = .{ .operation = .reset_holder, .observation = .slice, .meeting = .closure_body };
        try testing.expectEqualStrings("field/reset_holder/slice/closure_body", try std.fmt.bufPrint(&buffer, "{f}", .{cell}));
    }
};

/// Every cell that applies, in enumeration order.
pub fn cells(gpa: std.mem.Allocator) ![]Cell {
    var out: std.ArrayList(Cell) = .empty;
    errdefer out.deinit(gpa);
    for (std.enums.values(Operation)) |operation| {
        for (std.enums.values(Observation)) |observation| {
            for (std.enums.values(Meeting)) |meeting| {
                const cell: Cell = .{ .operation = operation, .observation = observation, .meeting = meeting };
                if (cell.applies()) try out.append(gpa, cell);
            }
        }
    }
    return out.toOwnedSlice(gpa);
}

test "the matrix holds every applicable cell of the three axes" {
    const all = try cells(testing.allocator);
    defer testing.allocator.free(all);

    // Ten vector operations meet ten vector observations, six map
    // operations meet three map observations, and two assignments meet two
    // captures, at eight meetings. Consuming operations leave both loops,
    // assignments leave `defer`, an `inout` capture leaves the meeting between
    // two calls of a closure already holding the place, and a lent walk leaves
    // the meeting in one call. Bare walks meet only the non-consuming
    // operations, in a `for` body. The owner lent itself meets each consuming
    // operation in one call. A field and an array meet the nine observations a
    // slice offers, less `defer` for an array's assignments and the lent walk
    // in one call, and the three bare walks. A walked owner's two operations
    // meet everything a vector's do. A handle's three operations meet the text
    // C answers from it, and its close meets the handle lent itself.
    const vec = 10 * 10 * 8 - 3 * 10 * 2 - 1 * 10 - 10 * 1 - 10 * 1 + 7 * 3 + 3;
    const map = 6 * 3 * 8 - 2 * 3 * 2 - 6 * 1 + 4 * 1 + 2;
    const scalar = 2 * 2 * 8 - 2 * 2 - 2 * 1;
    const field = 2 * (9 * 8 - 1 + 3);
    const array = 2 * (9 * 7 - 1 + 3);
    const walked = 2 * (10 * 8 - 1 - 1 + 3);
    const handle = 3 * 8 - 1 * 2 + 1;
    try testing.expectEqual(@as(usize, vec + map + scalar + field + array + walked + handle), all.len);
    for (all) |cell| try testing.expect(cell.applies());
    // The shape the matrix exists for is one of its cells.
    var motivating = false;
    for (all) |cell| motivating = motivating or (cell.operation == .push and cell.observation == .bare_slice and cell.meeting == .for_body);
    try testing.expect(motivating);
    // So are a walk binder captured `inout` and read between two calls.
    var between = false;
    for (all) |cell| between = between or (cell.operation == .walk_push and cell.observation == .slice and cell.meeting == .closure_between);
    try testing.expect(between);
    // So is an owner below the path root, changed through its structure.
    var through_structure = false;
    for (all) |cell| through_structure = through_structure or (cell.operation == .reset_holder and cell.observation == .slice and cell.meeting == .straight);
    try testing.expect(through_structure);
    // So are an owner lent and taken in one call, and a handle's text met
    // with each change C may make.
    var lent_and_taken = false;
    for (all) |cell| lent_and_taken = lent_and_taken or (cell.operation == .release and cell.observation == .argument and cell.meeting == .one_call);
    try testing.expect(lent_and_taken);
    var handle_text = false;
    for (all) |cell| handle_text = handle_text or (cell.operation == .handle_change and cell.observation == .text and cell.meeting == .straight);
    try testing.expect(handle_text);
}

/// A use of the observation that adds what it reads to `total`. A lent walk
/// is used by walking it; everything else is read once.
fn use(w: Lines, depth: u32, observation: Observation) !void {
    if (observation == .lent_walk) {
        try w.line(depth, "for item in &seen {");
        try w.line(depth + 1, "total += *item");
        try w.line(depth + 1, "break");
        try w.line(depth, "}");
        return;
    }
    try w.print(depth, "total += {s}", .{observation.read()});
}

/// Writes indented lines. Text holding several lines is indented line by line.
const Lines = struct {
    out: *std.Io.Writer,
    /// Levels every line is indented beyond its depth: one inside the walk a
    /// walked owner is lent by.
    extra: u32 = 0,

    fn raw(self: Lines, text: []const u8) !void {
        try self.out.writeAll(text);
    }

    fn line(self: Lines, depth: u32, text: []const u8) !void {
        var lines = std.mem.splitScalar(u8, text, '\n');
        while (lines.next()) |one| {
            for (0..depth + self.extra) |_| try self.out.writeAll("    ");
            try self.out.writeAll(one);
            try self.out.writeByte('\n');
        }
    }

    fn print(self: Lines, depth: u32, comptime fmt: []const u8, args: anytype) !void {
        var buffer: [512]u8 = undefined;
        try self.line(depth, try std.fmt.bufPrint(&buffer, fmt, args));
    }
};

/// The largest total a clean run reads. A read of storage the owner no longer
/// holds usually lands far outside it, so a program that exceeds it exits 1
/// even where no sanitizer is watching.
const total_bound = 1000;

/// The cell's program, written as its liveness asks.
pub fn render(gpa: std.mem.Allocator, cell: Cell, liveness: Liveness) ![]const u8 {
    std.debug.assert(cell.applies());
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    var w: Lines = .{ .out = &out.writer };
    const storage = cell.operation.storage();
    const operation = cell.operation;
    const observation = cell.observation;
    const live = liveness == .live;

    switch (storage) {
        .vec, .walked => try w.raw("import std.mem\n\n"),
        .map => try w.raw("import std.collections\nimport std.mem\n\n"),
        .field => {
            try w.raw("import std.mem\n\nstruct Holder { items: Vec[UInt64, mem.SystemAllocator] }\n\n");
            if (operation == .reset_holder) try w.raw(
                \\fn reset(inout holder: Holder) {
                \\    &holder.items.clear()
                \\}
                \\
                \\
            );
        },
        .handle => {
            if (observation == .text) try w.raw("import std.ffi\n\n");
            try w.raw(
                \\@(opaque, linear)
                \\type Block = UInt64
                \\
                \\extern fn calloc(count: UInt64, size: UInt64) -> Block
                \\
                \\extern fn free(sink block: Block)
                \\
                \\
            );
            if (observation == .text) try w.raw("extern fn strchr(read text: Block, character: Int32) -> ffi.CText where borrows(text)\n\n");
            if (operation == .handle_change) try w.raw("extern fn memset(block: Block, value: Int32, count: UInt64) -> UInt64\n\n");
            if (operation == .handle_renew) try w.raw(
                \\fn renew(inout block: Block) {
                \\    free(block)
                \\    block = calloc(1, 16)
                \\}
                \\
                \\
            );
        },
        .scalar, .array => {},
    }
    // A vector lent to a call beside its own release is, in the `live`
    // program, given straight to the `sink` parameter that releases it.
    const gives_directly = operation == .release and observation == .argument and cell.meeting == .one_call and live;
    if (cell.meeting == .one_call) try w.raw(if (gives_directly)
        \\fn meet[T](_lent: T, sink taken: Vec[UInt64, mem.SystemAllocator]) -> UInt64 {
        \\    taken.release()
        \\    0
        \\}
        \\
        \\
    else
        \\fn meet[T](_lent: T, done: UInt64) -> UInt64 {
        \\    done
        \\}
        \\
        \\
    );
    if (observation == .wrapped) {
        if (storage == .array) try w.raw("import std.mem\n\n");
        try w.raw(
            \\@copyable
            \\type Wrapped = mem.Slice[UInt64]
            \\
            \\
        );
        // A call lends the wrapped slice itself and reads nothing through it.
        if (cell.meeting != .one_call) try w.raw(
            \\fn first(wrapped: Wrapped) -> UInt64 {
            \\    let Wrapped(view) = copy(wrapped)
            \\    view[0]
            \\}
            \\
            \\
        );
    }
    if (cell.meeting == .deferred) try w.raw(
        \\fn add(inout total: UInt64, amount: UInt64) {
        \\    total += amount
        \\}
        \\
        \\
    );
    try w.raw("fn main() -> UInt8 {\n");
    try w.line(1, "var total: UInt64 = 0");
    switch (storage) {
        .vec => {
            try w.line(1, "var owner: Vec[UInt64, mem.SystemAllocator] = Vec.new()");
            try w.line(1, storage.fill());
        },
        .map => {
            try w.line(1, "var owner: collections.Map[UInt64, UInt64, mem.SystemAllocator] = collections.Map.new()");
            try w.line(1, storage.fill());
        },
        .scalar => try w.line(1, "var owner: UInt64 = 1"),
        .field => {
            try w.line(1, "var holder = Holder { items = Vec.new() }");
            try w.line(1, storage.fill());
        },
        .array => try w.line(1, "var owner = [UInt64(1), 2, 3]"),
        .handle => try w.line(1, "var owner = calloc(1, 16)"),
        .walked => {
            try w.line(1, "var owners: [Vec[UInt64, mem.SystemAllocator]; 1] = [Vec.new()]");
            try w.line(1, "for inout owner in owners {");
            w.extra = 1;
            try w.line(1, storage.fill());
        },
    }
    if (observation.bare() == null and cell.meeting != .closure_between) try w.line(1, observation.open());

    // Whether the owner is still held once the meeting is over. A deferred
    // consuming operation settles it at the end of the inner scope.
    var settled = false;
    switch (cell.meeting) {
        .straight => if (live) {
            try w.line(1, operation.statements());
            try use(w, 1, observation);
        } else {
            try use(w, 1, observation);
            try w.line(1, operation.statements());
        },
        .for_body => if (observation.bare()) |sequence| {
            // The body counts its passes and never reads an item.
            try w.print(1, "for _item in {s} {{", .{sequence});
            try w.line(2, "total += 1");
            if (live) try w.line(2, operation.statements());
            try w.line(1, "}");
            if (!live) {
                try w.line(1, "for _round in UInt64(0)..2 {");
                try w.line(2, operation.statements());
                try w.line(1, "}");
            }
        } else {
            const walk = observation.walk();
            if (live) {
                if (walk) |how| {
                    try w.print(1, "for item in {s} {{", .{how.sequence});
                    try w.print(2, "total += {s}", .{how.item});
                    try w.line(2, operation.statements());
                    try w.line(1, "}");
                    // A lent walk leaves the iterator with its owner, which
                    // reads it again afterwards.
                    if (observation == .lent_walk) try use(w, 1, observation);
                } else {
                    try w.line(1, "for _round in UInt64(0)..2 {");
                    try use(w, 2, observation);
                    try w.line(2, operation.statements());
                    try w.line(1, "}");
                    try use(w, 1, observation);
                }
            } else {
                if (walk) |how| {
                    try w.print(1, "for item in {s} {{", .{how.sequence});
                    try w.print(2, "total += {s}", .{how.item});
                    try w.line(1, "}");
                    if (observation == .lent_walk) try use(w, 1, observation);
                } else {
                    try use(w, 1, observation);
                }
                try w.line(1, "for _round in UInt64(0)..2 {");
                try w.line(2, operation.statements());
                try w.line(1, "}");
            }
        },
        .while_body => {
            if (!live) try use(w, 1, observation);
            try w.line(1, "var round: UInt64 = 0");
            try w.line(1, "while round < 2 {");
            if (live) try use(w, 2, observation);
            try w.line(2, operation.statements());
            try w.line(2, "round += 1");
            try w.line(1, "}");
            if (live) try use(w, 1, observation);
        },
        .closure_body => {
            if (!live) try use(w, 1, observation);
            try w.print(1, "var act = inout [inout {s}] || {{", .{storage.root()});
            try w.line(2, operation.statements());
            try w.line(1, "}");
            try w.line(1, "&act()");
            if (live) try use(w, 1, observation);
        },
        .closure_between => {
            try w.print(1, "var act = inout [inout {s}] || {{", .{storage.root()});
            try w.line(2, operation.statements());
            try w.line(1, "}");
            try w.line(1, "&act()");
            if (!live) {
                try w.line(1, "&act()");
                if (operation.shrinks()) try w.line(1, storage.fill());
            }
            try w.line(1, observation.open());
            if (live) try w.line(1, "&act()");
            try use(w, 1, observation);
        },
        .deferred => {
            // Deferred expressions run last scheduled first, so the one
            // written second runs first. The single arm is the scope they run
            // at the end of: unlike an `if`, it has no other path on which a
            // deferred consuming operation would leave the owner held.
            const deferred_read = try std.fmt.allocPrint(gpa, "defer add(&total, {s})", .{observation.read()});
            defer gpa.free(deferred_read);
            const deferred_operation = try std.fmt.allocPrint(gpa, "defer {s}", .{operation.expression().?});
            defer gpa.free(deferred_operation);
            try w.line(1, "match total {");
            try w.line(2, "_ => {");
            if (live) {
                try w.line(3, deferred_read);
                try w.line(3, deferred_operation);
            } else {
                try w.line(3, deferred_operation);
                try w.line(3, deferred_read);
            }
            try w.line(2, "},");
            try w.line(1, "}");
            settled = operation.consumes();
        },
        .match_arm => {
            if (!live) try use(w, 1, observation);
            try w.line(1, "match total {");
            try w.line(2, "1000000 => {},");
            try w.line(2, "_ => {");
            try w.line(3, operation.statements());
            try w.line(2, "},");
            try w.line(1, "}");
            if (live) try use(w, 1, observation);
        },
        .one_call => if (live) {
            if (gives_directly) {
                try w.print(1, "total += meet({s}, owner)", .{observation.lent()});
            } else {
                try w.print(1, "total += meet({s}, {{", .{observation.lent()});
                try w.line(2, operation.inArgument());
                try w.line(2, "0");
                try w.line(1, "})");
            }
            if (operation.consumes()) try w.line(1, operation.reopen());
        } else {
            try w.print(1, "total += meet({s}, 0)", .{observation.lent()});
            try w.line(1, operation.statements());
        },
    }

    switch (storage) {
        .vec, .map => if (!settled) try w.line(1, "owner.release()"),
        .handle => if (!settled) try w.line(1, "free(owner)"),
        .field => try w.line(1, "let Holder { items } = holder\nitems.release()"),
        .scalar, .array => {},
        .walked => {
            w.extra = 0;
            try w.line(1, "}");
            try w.line(1, "for owner in owners {\n    owner.release()\n}");
        },
    }
    const measured = switch (storage) {
        .scalar => "total + owner",
        .array => "total + owner[0]",
        .vec, .map, .field, .walked, .handle => "total",
    };
    try w.print(1, "if {s} > {d} {{", .{ measured, total_bound });
    try w.line(2, "1");
    try w.line(1, "} else {");
    try w.line(2, "0");
    try w.line(1, "}");
    try w.raw("}\n");
    const text = try out.toOwnedSlice();
    if (std.mem.eql(u8, storage.owner(), "owner")) return text;
    defer gpa.free(text);
    return std.mem.replaceOwned(u8, gpa, text, "owner", storage.owner());
}

test "a live cell uses its observation after the operation and an ended one before" {
    const gpa = testing.allocator;
    const cell: Cell = .{ .operation = .push, .observation = .slice, .meeting = .straight };
    const live = try render(gpa, cell, .live);
    defer gpa.free(live);
    const ended = try render(gpa, cell, .ended);
    defer gpa.free(ended);

    const op_live = std.mem.indexOf(u8, live, "&owner.push(4)").?;
    const read_live = std.mem.indexOf(u8, live, "total += seen[0]").?;
    try testing.expect(op_live < read_live);
    const op_ended = std.mem.indexOf(u8, ended, "&owner.push(4)").?;
    const read_ended = std.mem.indexOf(u8, ended, "total += seen[0]").?;
    try testing.expect(read_ended < op_ended);
}

test "a deferred operation runs before the deferred read of a live cell" {
    const gpa = testing.allocator;
    const cell: Cell = .{ .operation = .release, .observation = .element, .meeting = .deferred };
    const live = try render(gpa, cell, .live);
    defer gpa.free(live);
    // Written second, so it runs first.
    const read = std.mem.indexOf(u8, live, "defer add(&total, *seen)").?;
    const release = std.mem.indexOf(u8, live, "defer owner.release()").?;
    try testing.expect(read < release);
    // The deferred release is the owner's settlement.
    try testing.expectEqual(@as(usize, 1), std.mem.count(u8, live, "owner.release()"));
}

test "every cell renders a program the parser reads whole" {
    const tokenize = @import("../lexer/lexer.zig").tokenize;
    const parse = @import("../parser/parser.zig").parse;
    const Sink = @import("../diagnostics/sink.zig").Sink;
    const Interner = @import("../support/interner.zig").Interner;
    const Source = @import("../support/source.zig").Source;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    for (try cells(gpa)) |cell| {
        for (std.enums.values(Liveness)) |liveness| {
            const text = try render(gpa, cell, liveness);
            const source: Source = .{ .path = "main.lin", .text = text };
            var sink = Sink.init(gpa);
            var interner: Interner = .empty;
            const tokens = try tokenize(gpa, &source, .from(0), &sink, &interner);
            _ = try parse(gpa, &source, .from(0), tokens, &sink);
            if (sink.hasErrors()) {
                std.debug.print("{f} ({s}) does not parse:\n{s}\n", .{ cell, @tagName(liveness), text });
                return error.TestUnexpectedResult;
            }
        }
    }
}
