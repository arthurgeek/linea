const std = @import("std");
const DeclId = @import("../syntax/node.zig").DeclId;
const Ast = @import("../syntax/ast.zig").Ast;
const types_mod = @import("types.zig");
const Typing = types_mod.Typing;
const TypeId = types_mod.TypeId;
const ExpandedProgram = @import("../syntax/expanded_program.zig").ExpandedProgram;
const FloatMathOperation = @import("../support/float_math.zig").Operation;
const runtime_symbols = @import("../support/runtime_symbols.zig");

pub const FloatMath = struct {
    declarations: [FloatMathOperation.count]DeclId = @splat(.none),

    /// Candidates retain malformed trusted declarations so checking diagnoses
    /// signature drift even when the written types fit the ordinary integer ABI.
    pub fn candidates(program: *const ExpandedProgram, ast: *const Ast) FloatMath {
        var result: FloatMath = .{};
        for (std.enums.values(FloatMathOperation), 0..) |operation, i| {
            const d = program.libraryDeclIn("scalar", operation.symbol()) orelse continue;
            if (ast.declIsExtern(d)) result.declarations[i] = d;
        }
        return result;
    }

    pub fn checked(self: FloatMath, ast: *const Ast, typing: *const Typing) FloatMath {
        const parameters = [_]TypeId{ .f64, .f64 };
        var result: FloatMath = .{};
        for (self.declarations, std.enums.values(FloatMathOperation), 0..) |d, operation, i| {
            if (d == .none or ast.declVisibility(d) != .private or ast.declIsExport(d) or
                ast.declContracts(d).len != 0 or ast.declWherePredicates(d).len != 0) continue;
            if (matchesExternSignature(ast, typing, d, parameters[0..operation.arity()], .f64))
                result.declarations[i] = d;
        }
        return result;
    }

    pub fn operationOf(self: FloatMath, d: DeclId) ?FloatMathOperation {
        if (d == .none) return null;
        for (self.declarations, std.enums.values(FloatMathOperation)) |declaration, operation| {
            if (declaration == d) return operation;
        }
        return null;
    }
};

/// Whether `t` is a handle to an object C holds ([T-ExternHandle]): a newtype
/// that is not `copyable` and is either sealed in a module its root's
/// manifest grants `extern`, in any root, or a newtype over a handle. Only a
/// module trusted with C makes the innermost one from an address, and a newtype
/// around it names the same object, so each is a handle wherever it crosses an
/// `extern`. A copyable newtype is never one: anyone holding a copy names the
/// object, so nothing read through it can be kept alive by its place. Asked of
/// a pool being built or of a finished typing.
pub fn isForeignHandle(program: *const ExpandedProgram, ast: *const Ast, pool: anytype, t: TypeId) bool {
    var at = t;
    while (true) {
        if (at == .poison) return false;
        const newtype = switch (pool.get(at)) {
            .newtype => |newtype| newtype,
            else => return false,
        };
        const declared = pool.declOfType(at) orelse return false;
        if (ast.declOwnershipPolicy(declared) == .copyable) return false;
        if (sealsForeignObject(program, ast, declared)) return true;
        at = newtype.base;
    }
}

/// Whether the declaration `d` is a newtype sealed (`@opaque`) in a module
/// its root's manifest grants `extern`: only such a module makes one from an
/// address, so it is the shape a value naming a C object takes.
pub fn sealedUnderGrant(program: *const ExpandedProgram, ast: *const Ast, d: DeclId) bool {
    return ast.declTag(d) == .newtype and ast.declVisibility(d) == .opaque_ and
        program.get(program.moduleOf(d)).externs;
}

/// Whether the declaration `d` is the innermost handle to an object C holds:
/// a newtype sealed under a grant that is not `copyable`. A read of the
/// handle may reach C, which has not said two threads may read the object at
/// once, so the type is not `Shareable` unless its declaration is marked
/// `shareable`; [T-ExternHandle] and the `unshareable` table both ask here.
pub fn sealsForeignObject(program: *const ExpandedProgram, ast: *const Ast, d: DeclId) bool {
    return sealedUnderGrant(program, ast, d) and ast.declOwnershipPolicy(d) != .copyable;
}

/// Whether the declaration `d` is a `copyable` newtype sealed under a grant
/// that does not vouch `shareable`. Every copy names what the sealed number
/// names, and a copy crosses to any task whole, so no rule about readers can
/// keep two threads apart: the wrapper must vouch for concurrent use itself
/// ([T-ExternHandle]).
pub fn copiesUnvouchedForeignObject(program: *const ExpandedProgram, ast: *const Ast, d: DeclId) bool {
    return sealedUnderGrant(program, ast, d) and ast.declOwnershipPolicy(d) == .copyable and
        ast.declShareableToken(d) == .none;
}

/// Whether `t` names a C object through a `copyable` newtype sealed under a
/// grant, at any layer: it is one, or a newtype wrapped around one, sealed or
/// not, copyable or not. Every copy of the copyable layer names the same
/// object, so the object must outlive every copy, and a wrapper around it,
/// even a linear one, does not own it: C may take any of them only `read`,
/// neither keeping nor freeing the object, and none crosses from C or back to
/// it by value ([T-ExternHandle]).
///
/// **Bound:** each step enters a newtype's base, so the walk is as deep as
/// `t`'s newtypes nest.
pub fn namesCopiedForeignObject(program: *const ExpandedProgram, ast: *const Ast, pool: anytype, t: TypeId) bool {
    var at = t;
    while (true) {
        if (at == .poison) return false;
        const newtype = switch (pool.get(at)) {
            .newtype => |newtype| newtype,
            else => return false,
        };
        const declared = pool.declOfType(at) orelse return false;
        if (sealedUnderGrant(program, ast, declared) and ast.declOwnershipPolicy(declared) == .copyable) return true;
        at = newtype.base;
    }
}

/// Whether parameter `k` of the `extern` `d`, of type `t`, lends C a handle
/// it may change: a handle taken by a plain lend, without `read`. C receives
/// the handle by value, so the call lends the argument's place as `inout`
/// would, and only a place that may change can be lent so.
pub fn changesForeignHandle(program: *const ExpandedProgram, ast: *const Ast, pool: anytype, d: DeclId, k: usize, t: TypeId) bool {
    const param = ast.declParams(d)[k];
    if (param.convention != .read or ast.paramConventionToken(param) != .none) return false;
    return isForeignHandle(program, ast, pool, t);
}

/// The functions of `std.task` whose `body` argument crosses into a task
/// ([O-Cross]). `RawAccesses` names each as the field `task_` and its name,
/// and the soundness matrix starts a live task through each.
pub const task_entry_points = [_][]const u8{ "prepare", "prepare_in", "start", "start_in" };

pub const RawAccesses = struct {
    storage: DeclId = .none,
    buffer: DeclId = .none,
    slice: DeclId = .none,
    /// `mem.address.Address`, the newtype over a `UInt64` that names the type
    /// of the values kept at it; `address.raw`, the one function that reads
    /// the number in one ([T-RawAddress]); `mem.address_in`, the address of
    /// slots at an offset into a buffer, which lowering computes and which
    /// borrows the buffer; `mem.owned_address_in`, the same address for a
    /// value that takes the buffer and keeps the address beside it, which
    /// carries what the buffer carries; and `mem.slice_address`, the address
    /// of a slice's first element, which carries what the slice carries.
    address: DeclId = .none,
    address_raw: DeclId = .none,
    /// `address.nowhere`, the address of no bytes, which any `Storage`
    /// literal may hold.
    address_nowhere: DeclId = .none,
    address_in: DeclId = .none,
    owned_address_in: DeclId = .none,
    slice_address: DeclId = .none,
    /// `mem.number_address`, the address at a number: C's, or one the
    /// library's test logs carry through text. It names whatever the number
    /// does, so only the declarations `number_address_callers` lists call it
    /// ([T-RawAddress]).
    number_address: DeclId = .none,
    number_address_callers: [2]DeclId = @splat(.none),
    /// `mem.foreign_at`, through which `std.ffi` reads the memory a C view
    /// names; only the members of `CText` and `CTextList` and its own test
    /// call it.
    foreign_at: DeclId = .none,
    foreign_at_test: DeclId = .none,
    /// The declarations beside a C view's own members that build one: a lent
    /// view of bytes (`bytes_of`), a `CString`'s text (`CString.text`), and an
    /// entry of a list C handed over (`CTextList.get`).
    foreign_view_builders: [3]DeclId = @splat(.none),
    /// The declarations that may build a certified `Storage` from a literal
    /// with an address other than `address.nowhere()`, and so choose its `at`
    /// ([T-RawAddress]): `Storage.from_buffer`, whose address is its own
    /// buffer's, and `keep_body`, `take_kept_body` and `release_kept_bytes`,
    /// which reach a kept task body through the addresses that own it.
    storage_builders: [4]DeclId = @splat(.none),
    /// `Storage.address`, the one declaration that reads a storage's `at`;
    /// its contract borrows the storage, so the address lives no longer.
    storage_address: DeclId = .none,
    /// `Closure.erase`, the one declaration that takes a storage apart and
    /// keeps its address, as the `at` of the closure that then owns the bytes.
    closure_erase: DeclId = .none,
    /// The declarations that may call `owned_address_in`, whose address
    /// outlives the buffer's place: `Storage.from_buffer` and `keep_body`,
    /// each of which takes the buffer into what the address names.
    owned_address_callers: [3]DeclId = @splat(.none),
    /// `mem.keep_body`, `mem.take_kept_body` and `mem.release_kept_bytes`,
    /// which move a task's body into bytes, out of them, and free them, each
    /// trusting the address it is handed. `task.Slot.start` alone keeps a
    /// body and names the release, and `task.run_body`, the entry the new
    /// thread runs, alone takes it ([T-RawAddress]).
    keep_body: DeclId = .none,
    take_kept_body: DeclId = .none,
    release_kept_bytes: DeclId = .none,
    task_run_body: DeclId = .none,
    /// `mem.Vec`, whose `storage` and `len` are the bytes it owns and how many
    /// of its slots are live, which `slot_place` and its release trust.
    vec: DeclId = .none,
    /// `mem.Kept`, the addresses that own a task body kept in bytes.
    kept: DeclId = .none,
    /// `mem.vector_from_buffer` and `mem.vector_into_buffer`, which make a
    /// byte vector from a buffer and take it back.
    vector_from_buffer: DeclId = .none,
    vector_into_buffer: DeclId = .none,
    /// `Vec.split_inout`, which lends a vector's two sides as views.
    vec_split_inout: DeclId = .none,
    /// The declarations that hand a buffer's or a slice's bytes out as
    /// numbers: an arena's own bookkeeping (`Arena.rewind`, `arena_reserve`),
    /// and the logs the library's tests write through
    /// (`AllocationLog.refuse_attempt`, `ReleaseLog.words`).
    buffer_numbers: [9]DeclId = @splat(.none),
    /// `mem.Arena`, whose `chunks` is the address of its table of later chunks
    /// inside its first buffer, and the free declarations of its allocator
    /// that read it.
    arena: DeclId = .none,
    arena_users: [5]DeclId = @splat(.none),
    arena_table_of: DeclId = .none,
    /// `mem.Handle` and the arena's free functions that trust the first chunk
    /// they are handed: `arena_zero` and `arena_give_back` are named only by
    /// `Arena`'s members, `arena_reserve` and `arena_holds` only by `Handle`'s,
    /// and `arena_table_of` only by the three that read the table.
    handle: DeclId = .none,
    arena_zero: DeclId = .none,
    arena_give_back: DeclId = .none,
    arena_reserve: DeclId = .none,
    arena_holds: DeclId = .none,
    /// `Storage.from_buffer`, which takes a buffer apart into slot storage.
    storage_from_buffer: DeclId = .none,
    /// `Storage.dispose` and `Storage.into_buffer`, which give up a storage's
    /// slots without settling them.
    storage_dispose: DeclId = .none,
    storage_into_buffer: DeclId = .none,
    /// The declarations beside `Storage`'s and `Vec`'s own members that move
    /// values in and out of slots and give storage up: each takes or hands
    /// on every value it puts before it disposes, so no slot is left live
    /// ([T-RawAddress]). A task body's keeping, taking and release, a
    /// closure's erasure, a payload's send and receive, an owning task's call
    /// and request, the release of a vector's elements, and the byte vector
    /// given back as a buffer, whose bytes need no settling.
    slot_users: [14]DeclId = @splat(.none),
    /// The test allocators that build a buffer of their backing allocator,
    /// which they hand out and take back on its behalf.
    backing_buffer_builders: [7]DeclId = @splat(.none),
    /// `mem.Drain`, which takes a vector's elements out of its storage.
    drain: DeclId = .none,
    /// `mem.release_from`, which releases the slots between two counts it
    /// trusts; only `Vec`'s and `Drain`'s members name it ([T-RawAddress]).
    release_from: DeclId = .none,
    /// `Chan.opened` and the three that move a value through an endpoint,
    /// which trust that the endpoint carries a value of the type asked for:
    /// only a `Chan`'s own members move one, and only `task.Slot.start` and
    /// `task.run_body` open a `Chan` on the endpoint a task was started with.
    chan_opened: DeclId = .none,
    send_payload: DeclId = .none,
    receive_payload: DeclId = .none,
    receive_payload_until: DeclId = .none,
    /// `call_owner` and `next_owner_request`, which trust that a queue holds
    /// jobs for the state asked for: `task.Client.call` and `task.run_owner`.
    call_owner: DeclId = .none,
    next_owner_request: DeclId = .none,
    client_call: DeclId = .none,
    /// `task.Owner`, whose `queue` is trusted as an endpoint is, and the
    /// declarations beside its members that name its fields.
    owner: DeclId = .none,
    owner_users: [6]DeclId = @splat(.none),
    run_owner: DeclId = .none,
    /// The free declarations that name a `Chan`'s fields.
    endpoint_users: [6]DeclId = @splat(.none),
    /// `record_release`, which writes at the number it is given, and its two
    /// callers: `ReleaseTag.release`, whose number is its log's, and the HTTP
    /// test `ProbeTag`, whose extractor reaches the log only through a request
    /// header, so the number crosses as text. `ProbeTag` is built only by
    /// `probe_tag`.
    record_release: DeclId = .none,
    record_release_callers: [2]DeclId = @splat(.none),
    probe_tag: DeclId = .none,
    probe_tag_builder: DeclId = .none,
    /// `foreign_byte` and `foreign_word`, which read at an extent they cannot
    /// check, C's memory having none: only `CText`'s and `CTextList`'s members,
    /// `copied_in` and their own tests name them.
    foreign_byte: DeclId = .none,
    foreign_word: DeclId = .none,
    foreign_readers: [5]DeclId = @splat(.none),
    /// The declarations beside `Buffer`'s and `Storage`'s and `Chan`'s own
    /// members that hand the runtime or a raw load an address and an extent,
    /// each an extent it has read from what owns the bytes
    /// ([T-RawAddress]).
    byte_operations: [31]DeclId = @splat(.none),
    /// `mem.Carried`, the zero-sized field type that carries its argument's
    /// dependencies.
    carried: DeclId = .none,
    /// The `Dual` and `Step` that `session.Protocol` declares. Wherever `P`
    /// still awaits a type, `P.Dual.Dual` is read as `P` and `P.Dual.Step`
    /// as `P.Step.Dual`.
    protocol_dual: DeclId = .none,
    protocol_step: DeclId = .none,
    span: DeclId = .none,
    buffer_span: DeclId = .none,
    subspan: DeclId = .none,
    slice_place: DeclId = .none,
    /// `mem.View`, a writable view of a contiguous run of elements another
    /// value owns, and `view_place`, which names one of its elements in place
    /// as `slice_place` does a slice's.
    view: DeclId = .none,
    view_place: DeclId = .none,
    /// `argument_span` and `environment_span` view text the process was
    /// started with; each lowers to the runtime's count, address and length
    /// for its source, which `processText` names.
    argument_span: DeclId = .none,
    argument_count: DeclId = .none,
    argument_at: DeclId = .none,
    argument_len: DeclId = .none,
    environment_span: DeclId = .none,
    environment_count: DeclId = .none,
    environment_at: DeclId = .none,
    environment_len: DeclId = .none,
    stride: DeclId = DeclId.none,
    take: DeclId = DeclId.none,
    put: DeclId = DeclId.none,
    place: DeclId = DeclId.none,
    store: DeclId = DeclId.none,
    load: DeclId = DeclId.none,
    store8: DeclId = DeclId.none,
    load8: DeclId = DeclId.none,
    /// `linea_float64_to_bits`, `linea_float64_from_bits` and their Float32
    /// forms: a float's bits reinterpreted as the unsigned integer of its
    /// width, and back. Each lowers to one bit cast.
    float_bits: [4]DeclId = @splat(DeclId.none),
    /// `mem.Closure`, the type every erased callable is kept behind, and
    /// `mem.ClosureEntry`, whose instance for a callable `S` is `S` with the
    /// stored callable's address and length appended.
    closure: DeclId = .none,
    closure_entry_type: DeclId = .none,
    /// `session.Chan`, an end of a session and every task's handle: a value
    /// holding one may wait on another task, so it is not `Isolated`.
    endpoint: DeclId = .none,
    /// `Closure.open_in` and `Closure.open`, whose callback must be callable
    /// as the closure's `S`. The second opens in the system allocator.
    closure_open_in: DeclId = .none,
    closure_open: DeclId = .none,
    /// The generated entry and release addresses for a callable type, and
    /// that type's size.
    closure_entry: DeclId = .none,
    closure_settle: DeclId = .none,
    closure_size: DeclId = .none,
    /// `task.prepare`, `task.prepare_in`, `task.start` and `task.start_in`,
    /// whose `body` argument crosses into a task ([O-Cross]), and the two
    /// `start` forms, which drop a body a failed start could not keep and so
    /// take only a Discardable one.
    task_prepare: DeclId = .none,
    task_prepare_in: DeclId = .none,
    task_start: DeclId = .none,
    task_start_in: DeclId = .none,
    /// `task.Unstarted`, the failure of a preparation, which holds the body.
    task_unstarted: DeclId = .none,
    /// `task.Slot.start`, the one function that may call a runtime symbol
    /// that starts a thread ([T-ThreadStart]): the handle it answers carries
    /// the body's dependencies until the thread is joined.
    task_slot_start: DeclId = .none,
    /// `ffi.Bytes`, `ffi.CText` and `ffi.CTextList`: copyable newtypes over a
    /// C address whose dependencies originate at the value, as a
    /// `mem.Slice`'s do, so a contract can tie one to what it views.
    foreign_views: [3]DeclId = .{ .none, .none, .none },
    /// `ffi.Errno`, which an `extern` answers to have `errno` read after the
    /// call, and the runtime's `linea_errno` that reads it.
    errno: DeclId = .none,
    errno_read: DeclId = .none,

    /// Identify private storage declarations before checking their generic signatures.
    pub fn init(program: *const ExpandedProgram, ast: *const Ast) RawAccesses {
        var raw: RawAccesses = .{
            .storage = structIn(program, ast, "mem", "Storage"),
            .buffer = structIn(program, ast, "mem", "Buffer"),
            .slice = structIn(program, ast, "mem", "Slice"),
            .address = program.libraryDeclIn("address", "Address") orelse .none,
            .address_raw = moduleFunction(program, ast, "address", "raw"),
            .address_nowhere = moduleFunction(program, ast, "address", "nowhere"),
            .address_in = rawAccessDecl(program, ast, "address_in", 2),
            .owned_address_in = rawAccessDecl(program, ast, "owned_address_in", 2),
            .slice_address = rawAccessDecl(program, ast, "slice_address", 1),
            .number_address = rawAccessDecl(program, ast, "number_address", 1),
            .number_address_callers = .{
                moduleFunction(program, ast, "mem", "foreign_at"),
                moduleFunction(program, ast, "mem", "record_release"),
            },
            .foreign_at = moduleFunction(program, ast, "mem", "foreign_at"),
            .foreign_at_test = testIn(program, ast, "mem", "an_address_at_a_number_names_the_bytes_there"),
            .foreign_view_builders = .{
                moduleFunction(program, ast, "ffi", "bytes_of"),
                memberOf(program, ast, "ffi", "CString", "text"),
                memberOf(program, ast, "ffi", "CTextList", "get"),
            },
            .storage_builders = .{
                memberOf(program, ast, "mem", "Storage", "from_buffer"),
                moduleFunction(program, ast, "mem", "keep_body"),
                moduleFunction(program, ast, "mem", "take_kept_body"),
                moduleFunction(program, ast, "mem", "release_kept_bytes"),
            },
            .keep_body = moduleFunction(program, ast, "mem", "keep_body"),
            .take_kept_body = moduleFunction(program, ast, "mem", "take_kept_body"),
            .release_kept_bytes = moduleFunction(program, ast, "mem", "release_kept_bytes"),
            .task_run_body = moduleFunction(program, ast, "task", "run_body"),
            .vec = structIn(program, ast, "mem", "Vec"),
            .kept = structIn(program, ast, "mem", "Kept"),
            .vector_from_buffer = moduleFunction(program, ast, "mem", "vector_from_buffer"),
            .vector_into_buffer = moduleFunction(program, ast, "mem", "vector_into_buffer"),
            .vec_split_inout = memberOf(program, ast, "mem", "Vec", "split_inout"),
            .buffer_numbers = .{
                memberOf(program, ast, "mem", "Arena", "rewind"),
                moduleFunction(program, ast, "mem", "arena_reserve"),
                memberOf(program, ast, "mem", "AllocationLog", "refuse_attempt"),
                memberOf(program, ast, "mem", "ReleaseLog", "words"),
                memberOf(program, ast, "mem", "Arena", "open"),
                moduleFunction(program, ast, "mem", "arena_table_of"),
                moduleFunction(program, ast, "mem", "arena_zero"),
                moduleFunction(program, ast, "mem", "arena_give_back"),
                moduleFunction(program, ast, "mem", "arena_holds"),
            },
            .arena = structIn(program, ast, "mem", "Arena"),
            .arena_users = .{
                moduleFunction(program, ast, "mem", "arena_table_of"),
                moduleFunction(program, ast, "mem", "arena_give_back"),
                moduleFunction(program, ast, "mem", "arena_reserve"),
                moduleFunction(program, ast, "mem", "arena_holds"),
                memberOf(program, ast, "mem", "Handle", "dispose"),
            },
            .arena_table_of = moduleFunction(program, ast, "mem", "arena_table_of"),
            .handle = structIn(program, ast, "mem", "Handle"),
            .arena_zero = moduleFunction(program, ast, "mem", "arena_zero"),
            .arena_give_back = moduleFunction(program, ast, "mem", "arena_give_back"),
            .arena_reserve = moduleFunction(program, ast, "mem", "arena_reserve"),
            .arena_holds = moduleFunction(program, ast, "mem", "arena_holds"),
            .chan_opened = memberOf(program, ast, "session", "Chan", "opened"),
            .send_payload = moduleFunction(program, ast, "mem", "send_payload"),
            .receive_payload = moduleFunction(program, ast, "mem", "receive_payload"),
            .receive_payload_until = moduleFunction(program, ast, "mem", "receive_payload_until"),
            .call_owner = moduleFunction(program, ast, "mem", "call_owner"),
            .next_owner_request = moduleFunction(program, ast, "mem", "next_owner_request"),
            .client_call = memberOf(program, ast, "task", "Client", "call"),
            .owner = structIn(program, ast, "task", "Owner"),
            .owner_users = .{ memberOf(program, ast, "task", "Client", "call"), moduleFunction(program, ast, "task", "own"), .none, .none, .none, .none },
            .run_owner = moduleFunction(program, ast, "task", "run_owner"),
            .endpoint_users = .{ moduleFunction(program, ast, "session", "detach"), .none, .none, .none, .none, .none },
            .record_release = moduleFunction(program, ast, "mem", "record_release"),
            .record_release_callers = .{ memberOf(program, ast, "mem", "ReleaseTag", "release"), memberOf(program, ast, "http", "ProbeTag", "release") },
            .probe_tag = structIn(program, ast, "http", "ProbeTag"),
            .probe_tag_builder = moduleFunction(program, ast, "http", "probe_tag"),
            .foreign_byte = moduleFunction(program, ast, "mem", "foreign_byte"),
            .foreign_word = moduleFunction(program, ast, "mem", "foreign_word"),
            .foreign_readers = .{
                moduleFunction(program, ast, "ffi", "copied_in"),
                testIn(program, ast, "mem", "a_foreign_address_is_where_the_bytes_are"),
                testIn(program, ast, "mem", "a_foreign_byte_is_read_at_its_offset"),
                testIn(program, ast, "mem", "a_foreign_word_is_read_at_its_offset"),
                testIn(program, ast, "mem", "an_address_at_a_number_names_the_bytes_there"),
            },
            .byte_operations = .{
                moduleFunction(program, ast, "mem", "arena_reserve"),
                moduleFunction(program, ast, "mem", "arena_zero"),
                moduleFunction(program, ast, "mem", "arena_give_back"),
                moduleFunction(program, ast, "mem", "arena_holds"),
                memberOf(program, ast, "mem", "Arena", "rewind"),
                memberOf(program, ast, "mem", "SystemAllocator", "dispose"),
                moduleFunction(program, ast, "mem", "read_fd"),
                moduleFunction(program, ast, "mem", "write_slice_fd"),
                moduleFunction(program, ast, "mem", "read_fd_at"),
                moduleFunction(program, ast, "mem", "write_slice_fd_at"),
                moduleFunction(program, ast, "mem", "_random_bytes"),
                moduleFunction(program, ast, "mem", "_open_parent_fd"),
                moduleFunction(program, ast, "mem", "_open_at_fd"),
                moduleFunction(program, ast, "mem", "_mode_at_fd"),
                moduleFunction(program, ast, "mem", "_publish_at_fd"),
                moduleFunction(program, ast, "mem", "_unlink_at_fd"),
                moduleFunction(program, ast, "mem", "parse_float64_bits"),
                moduleFunction(program, ast, "mem", "parse_float32_bits"),
                moduleFunction(program, ast, "mem", "call_owner"),
                moduleFunction(program, ast, "mem", "next_owner_request"),
                moduleFunction(program, ast, "mem", "send_payload"),
                moduleFunction(program, ast, "mem", "receive_payload"),
                moduleFunction(program, ast, "mem", "receive_payload_until"),
                memberOf(program, ast, "mem", "AllocationLog", "refuse_attempt"),
                memberOf(program, ast, "mem", "RefusingAllocator", "acquire"),
                memberOf(program, ast, "mem", "RefusingAllocator", "dispose"),
                moduleFunction(program, ast, "mem", "record_release"),
                moduleFunction(program, ast, "mem", "foreign_byte"),
                moduleFunction(program, ast, "mem", "foreign_word"),
                moduleFunction(program, ast, "mem", "vec_test_log_store"),
                memberOf(program, ast, "task", "Slot", "start"),
            },
            .storage_from_buffer = memberOf(program, ast, "mem", "Storage", "from_buffer"),
            .storage_dispose = memberOf(program, ast, "mem", "Storage", "dispose"),
            .storage_into_buffer = memberOf(program, ast, "mem", "Storage", "into_buffer"),
            .drain = structIn(program, ast, "mem", "Drain"),
            .release_from = moduleFunction(program, ast, "mem", "release_from"),
            .backing_buffer_builders = .{
                memberOf(program, ast, "mem", "RefusingAllocator", "acquire"),
                memberOf(program, ast, "mem", "RefusingAllocator", "dispose"),
                memberOf(program, ast, "mem", "SharedRefusingAllocator", "acquire"),
                memberOf(program, ast, "mem", "SharedRefusingAllocator", "dispose"),
                memberOf(program, ast, "mem", "VecTestAllocator", "acquire"),
                memberOf(program, ast, "mem", "VecTestAllocator", "dispose"),
                memberOf(program, ast, "mem", "Handle", "dispose"),
            },
            .slot_users = .{
                moduleFunction(program, ast, "mem", "keep_body"),
                moduleFunction(program, ast, "mem", "take_kept_body"),
                moduleFunction(program, ast, "mem", "release_kept_bytes"),
                memberOf(program, ast, "mem", "Closure", "erase"),
                moduleFunction(program, ast, "mem", "send_payload"),
                moduleFunction(program, ast, "mem", "receive_payload"),
                moduleFunction(program, ast, "mem", "receive_payload_until"),
                moduleFunction(program, ast, "mem", "call_owner"),
                moduleFunction(program, ast, "mem", "next_owner_request"),
                moduleFunction(program, ast, "mem", "release_from"),
                moduleFunction(program, ast, "mem", "vector_into_buffer"),
                moduleFunction(program, ast, "mem", "arena_give_back"),
                moduleFunction(program, ast, "mem", "arena_reserve"),
                moduleFunction(program, ast, "mem", "arena_holds"),
            },
            .storage_address = memberOf(program, ast, "mem", "Storage", "address"),
            .closure_erase = memberOf(program, ast, "mem", "Closure", "erase"),
            .owned_address_callers = .{
                memberOf(program, ast, "mem", "Arena", "open"),
                memberOf(program, ast, "mem", "Storage", "from_buffer"),
                moduleFunction(program, ast, "mem", "keep_body"),
            },
            .carried = structIn(program, ast, "mem", "Carried"),
            .span = rawAccessDecl(program, ast, "slot_span", 4),
            .buffer_span = rawAccessDecl(program, ast, "buffer_span", 3),
            .subspan = rawAccessDecl(program, ast, "slice_subspan", 3),
            .slice_place = rawAccessDecl(program, ast, "slice_place", 2),
            .view = structIn(program, ast, "mem", "View"),
            .view_place = rawAccessDecl(program, ast, "view_place", 2),
            .argument_span = rawAccessDecl(program, ast, "argument_span", 1),
            .environment_span = rawAccessDecl(program, ast, "environment_span", 1),
            .stride = rawAccessDecl(program, ast, "slot_stride", 1),
            .take = rawAccessDecl(program, ast, "slot_take", 2),
            .put = rawAccessDecl(program, ast, "slot_put", 3),
            .place = rawAccessDecl(program, ast, "slot_place", 3),
            .closure = structIn(program, ast, "mem", "Closure"),
            .closure_entry_type = structIn(program, ast, "mem", "ClosureEntry"),
            .endpoint = structIn(program, ast, "session", "Chan"),
            .closure_open_in = memberOf(program, ast, "mem", "Closure", "open_in"),
            .closure_open = memberOf(program, ast, "mem", "Closure", "open"),
            .closure_entry = rawAccessDecl(program, ast, "closure_entry", 1),
            .closure_settle = rawAccessDecl(program, ast, "closure_settle", 1),
            .closure_size = rawAccessDecl(program, ast, "closure_size", 1),
            .task_unstarted = program.libraryDeclIn("task", "Unstarted") orelse .none,
            .task_slot_start = memberOf(program, ast, "task", "Slot", "start"),
            .foreign_views = .{
                program.libraryDeclIn("ffi", "Bytes") orelse .none,
                program.libraryDeclIn("ffi", "CText") orelse .none,
                program.libraryDeclIn("ffi", "CTextList") orelse .none,
            },
            .errno = program.libraryDeclIn("ffi", "Errno") orelse .none,
        };
        inline for (task_entry_points) |name| @field(raw, "task_" ++ name) = moduleFunction(program, ast, "task", name);
        return raw;
    }

    /// Scalar operations become intrinsics only after their complete signatures are checked.
    pub fn withCheckedScalars(self: RawAccesses, program: *const ExpandedProgram, ast: *const Ast, typing: *const Typing) RawAccesses {
        var checked = self;
        checked.argument_count = libraryExternDecl(program, ast, typing, "linea_arg_count");
        checked.argument_at = libraryExternDecl(program, ast, typing, "linea_arg_at");
        checked.argument_len = libraryExternDecl(program, ast, typing, "linea_arg_len");
        checked.environment_count = libraryExternDecl(program, ast, typing, "linea_env_count");
        checked.environment_at = libraryExternDecl(program, ast, typing, "linea_env_at");
        checked.environment_len = libraryExternDecl(program, ast, typing, "linea_env_len");
        checked.errno_read = libraryExternDecl(program, ast, typing, "linea_errno");
        checked.store = libraryExternDecl(program, ast, typing, "linea_raw_store");
        checked.load = libraryExternDecl(program, ast, typing, "linea_raw_load");
        checked.store8 = libraryExternDecl(program, ast, typing, "linea_raw_store8");
        checked.load8 = libraryExternDecl(program, ast, typing, "linea_raw_load8");
        for (float_bits_symbols, &checked.float_bits) |symbol, *d| d.* = libraryExternDecl(program, ast, typing, symbol);
        return checked;
    }

    /// The fields of `ffi.Errno`, in the order its declaration lists them:
    /// `value`, the `R` C returned, and `code`, the `errno` the runtime read
    /// after the call. The checker certifies the library's declaration
    /// against these names and positions, and lowering writes an `Errno`'s
    /// fields by them.
    pub const ErrnoField = enum(u32) { value, code };

    /// The fields of `mem.Closure`, in the order its declaration lists them.
    /// The checker certifies the library's declaration against these names
    /// and positions, and lowering reads a closure's fields by them.
    pub const ClosureField = enum(u32) { entry, settle, at, len, storage };

    /// The `R` of `ffi.Errno[R]` where `t` is one, asked of a pool being
    /// built or of a finished typing, or null where `t` is any other type.
    /// An `extern` answering `t` returns `R` from C.
    pub fn errnoValue(self: RawAccesses, pool: anytype, t: TypeId) ?TypeId {
        if (self.errno == .none) return null;
        const instance = pool.instanceOf(t) orelse return null;
        if (instance.decl != self.errno) return null;
        return pool.appliedTo(t)[0];
    }

    /// The signature C is called with for an `extern` of `signature`: the
    /// same parameters answering `R` where it answers `ffi.Errno[R]`, or null
    /// where it answers anything else. Discovery interns it before the pool
    /// closes and lowering finds it there.
    pub fn errnoSignature(self: RawAccesses, gpa: std.mem.Allocator, pool: *Typing.Builder, signature: TypeId) std.mem.Allocator.Error!?TypeId {
        const declared = pool.get(signature).callable;
        const value = self.errnoValue(pool, declared.result) orelse return null;
        const params = try gpa.dupe(types_mod.CallableParam, pool.callableParams(declared));
        defer gpa.free(params);
        const contracts = try gpa.dupe(types_mod.CallableContract, declared.contracts);
        defer gpa.free(contracts);
        return try pool.internCallable(params, value, contracts, declared.invocation);
    }

    /// The standard library's declarations of the float bit casts, by name
    /// before their signatures are checked, so the checker can hold each to
    /// the runtime table instead of to the foreign ABI, since no call to one
    /// reaches C.
    pub fn floatBitsCandidate(program: *const ExpandedProgram, ast: *const Ast, d: DeclId) bool {
        if (d == DeclId.none or !ast.declIsExtern(d)) return false;
        for (float_bits_symbols) |symbol| {
            if (program.libraryDeclIn("mem", symbol) == d) return true;
        }
        return false;
    }

    /// Whether `d` is a checked float bit cast.
    pub fn floatBits(self: RawAccesses, d: DeclId) bool {
        if (d == DeclId.none) return false;
        for (self.float_bits) |bits| if (bits == d) return true;
        return false;
    }

    /// Whether `d` opens a closure: its first type parameter is the callback,
    /// which must be callable as the closure's `S`.
    pub fn opensClosure(self: RawAccesses, d: DeclId) bool {
        return d != DeclId.none and (d == self.closure_open_in or d == self.closure_open);
    }

    pub fn contains(self: RawAccesses, d: DeclId) bool {
        return d != DeclId.none and
            (d == self.store or d == self.load or d == self.store8 or d == self.load8 or self.floatBits(d) or self.typed(d));
    }
    /// Whether `d` prepares a joinable task (`prepare`, `prepare_in`).
    pub fn preparesTask(self: RawAccesses, d: DeclId) bool {
        return d != DeclId.none and (d == self.task_prepare or d == self.task_prepare_in);
    }

    /// Whether `d` prepares and starts a joinable task in one call (`start`, `start_in`).
    pub fn startsTask(self: RawAccesses, d: DeclId) bool {
        return d != DeclId.none and (d == self.task_start or d == self.task_start_in);
    }

    /// Whether `d` is one of the library functions whose `body` crosses into
    /// a task.
    pub fn crossesTask(self: RawAccesses, d: DeclId) bool {
        return self.preparesTask(d) or self.startsTask(d);
    }

    /// A raw type: one whose fields hold an address, an extent of bytes, or
    /// what the bytes they describe hold, which the slot primitives, the
    /// runtime or lowering trust. Every field of one is named (read, written,
    /// lent, bound by a pattern or given in a literal) only in a member of an
    /// implementation for the type itself, in a member of an implementation
    /// of `mem.Allocator` where `allocators` says so, and in the declarations
    /// `also` lists ([T-RawAddress]). A field added to one later is covered as
    /// its others are.
    const also_slots = 10;

    pub const RawType = struct {
        decl: DeclId,
        also: [also_slots]DeclId = @splat(.none),
        allocators: bool = false,
    };

    /// The raw types, with where else each one's fields are named. A
    /// storage's are named where a task body is kept and where a closure
    /// erases the callable it holds; a buffer's by the allocators that hand
    /// it out and take it back; a view's where `Vec.split_inout` lends its
    /// two sides; a vector's where a byte vector is made from a buffer and
    /// taken back; a kept body's where `task.Slot.start` hands its
    /// addresses to the thread it starts; a buffer's where
    /// `Storage.from_buffer` takes it into slot storage; and a buffer's and a
    /// slice's where `buffer_numbers` and `foreign_address` hand their bytes
    /// out as numbers.
    pub fn rawTypes(self: RawAccesses) [11]RawType {
        return .{
            .{ .decl = self.storage, .also = also(.{ self.keep_body, self.take_kept_body, self.release_kept_bytes, self.closure_erase, self.arena_table_of }) },
            .{ .decl = self.buffer, .allocators = true, .also = also(self.buffer_numbers ++ [1]DeclId{self.storage_from_buffer}) },
            .{ .decl = self.slice },
            .{ .decl = self.view, .also = also(.{self.vec_split_inout}) },
            .{ .decl = self.closure },
            .{ .decl = self.vec, .also = also(.{ self.vector_from_buffer, self.vector_into_buffer }) },
            .{ .decl = self.kept, .also = also(.{ self.keep_body, self.task_slot_start }) },
            .{ .decl = self.endpoint, .also = also(self.endpoint_users) },
            .{ .decl = self.owner, .also = also(self.owner_users) },
            .{ .decl = self.arena, .also = also(self.arena_users) },
            .{ .decl = self.probe_tag, .also = also(.{self.probe_tag_builder}) },
        };
    }

    /// A row's listed declarations, the rest of its slots empty.
    fn also(listed: anytype) [also_slots]DeclId {
        var row: [also_slots]DeclId = @splat(.none);
        inline for (listed, 0..) |d, i| row[i] = d;
        return row;
    }

    pub fn typed(self: RawAccesses, d: DeclId) bool {
        return d != DeclId.none and (d == self.stride or d == self.take or d == self.put or d == self.place or d == self.span or d == self.buffer_span or d == self.subspan or d == self.slice_place or d == self.view_place or d == self.address_in or d == self.owned_address_in or d == self.slice_address or d == self.number_address or self.processText(d) != null or self.erasure(d));
    }

    /// The runtime declarations a process-text span reads: how many entries
    /// its source holds, and one entry's address and length.
    pub const ProcessText = struct { count: DeclId, at: DeclId, len: DeclId };

    /// The runtime source `d` views when it is `argument_span` or
    /// `environment_span`, or null for any other declaration.
    pub fn processText(self: RawAccesses, d: DeclId) ?ProcessText {
        if (d == DeclId.none) return null;
        if (d == self.argument_span) return .{ .count = self.argument_count, .at = self.argument_at, .len = self.argument_len };
        if (d == self.environment_span) return .{ .count = self.environment_count, .at = self.environment_at, .len = self.environment_len };
        return null;
    }

    /// Whether `d` is one of the declarations lowering replaces with what it
    /// generates for an erased closure's callable.
    pub fn erasure(self: RawAccesses, d: DeclId) bool {
        return d != DeclId.none and (d == self.closure_entry or d == self.closure_settle or d == self.closure_size);
    }

    /// The body a call to `closure_entry[S, F]` or `closure_settle[F]` takes
    /// the address of, from the type arguments the call settled; null for
    /// any other declaration. Discovery interns it and lowering finds it by
    /// this one reading of the intrinsics' parameter order.
    pub fn erasedBody(self: RawAccesses, d: DeclId, settled: []const TypeId) ?types_mod.BodyOrigin {
        if (d == DeclId.none) return null;
        if (d == self.closure_entry) return .{ .erased_entry = .{ .callable = settled[1], .signature = settled[0] } };
        if (d == self.closure_settle) return .{ .erased_settle = settled[0] };
        return null;
    }

    test "an erasure intrinsic names the body it generates" {
        const raw: RawAccesses = .{ .closure_entry = DeclId.at(1), .closure_settle = DeclId.at(2), .closure_size = DeclId.at(3) };
        const entry = raw.erasedBody(DeclId.at(1), &.{ .u8, .u16 }).?;
        try std.testing.expectEqual(TypeId.u16, entry.erased_entry.callable);
        try std.testing.expectEqual(TypeId.u8, entry.erased_entry.signature);
        try std.testing.expectEqual(TypeId.u32, raw.erasedBody(DeclId.at(2), &.{.u32}).?.erased_settle);
        try std.testing.expect(raw.erasedBody(DeclId.at(3), &.{.u8}) == null);
    }

    test "the erasure intrinsics are the closure entry, release and size" {
        const raw: RawAccesses = .{ .closure_entry = DeclId.at(1), .closure_settle = DeclId.at(2), .closure_size = DeclId.at(3), .closure_open_in = DeclId.at(4) };
        try std.testing.expect(raw.erasure(DeclId.at(1)) and raw.erasure(DeclId.at(2)) and raw.erasure(DeclId.at(3)));
        try std.testing.expect(!raw.erasure(DeclId.at(4)) and !raw.erasure(DeclId.none));
        // They are typed storage primitives, so a program cannot reach them.
        try std.testing.expect(raw.typed(DeclId.at(3)) and raw.contains(DeclId.at(1)));
    }
};

/// The member `member` of an implementation whose head names `owner`, the
/// library's type of that name in `module_name`: `Closure.open_in` and
/// `Closure.open` in `mem`, or `Slot.start` in `task`. Other types in a module
/// declare members of the same names, so the name alone does not identify it.
pub fn memberOf(program: *const ExpandedProgram, ast: *const Ast, module_name: []const u8, owner: []const u8, member: []const u8) DeclId {
    const declared = program.libraryDeclIn(module_name, owner) orelse return .none;
    for (program.declsOf(program.moduleOf(declared))) |d| {
        const name = ast.declName(d);
        const head = ast.memberOwner(d);
        if (name == .none or head == .none) continue;
        if (std.mem.eql(u8, ast.tokenText(name), member) and std.mem.eql(u8, ast.tokenText(head), owner)) return d;
    }
    return .none;
}

/// The library struct `name` of `module_name`. An implementation for a type
/// is named by its head, so the first declaration with the name may be one.
fn structIn(program: *const ExpandedProgram, ast: *const Ast, module_name: []const u8, name: []const u8) DeclId {
    const declared = program.libraryDeclIn(module_name, name) orelse return .none;
    for (program.declsOf(program.moduleOf(declared))) |d| {
        const named = ast.declName(d);
        if (named == .none or ast.declTag(d) != .struct_) continue;
        if (std.mem.eql(u8, ast.tokenText(named), name)) return d;
    }
    return .none;
}

/// The library function `name` of `module_name` that is no type's member.
fn moduleFunction(program: *const ExpandedProgram, ast: *const Ast, module_name: []const u8, name: []const u8) DeclId {
    const declared = program.libraryDeclIn(module_name, name) orelse return .none;
    for (program.declsOf(program.moduleOf(declared))) |d| {
        const named = ast.declName(d);
        if (named == .none or ast.memberOwner(d) != .none or ast.declTag(d) != .function) continue;
        if (std.mem.eql(u8, ast.tokenText(named), name)) return d;
    }
    return .none;
}

/// A private library extern by its name and its number of parameters. The
/// checker holds each to its whole signature, so a parameter's name decides
/// nothing: a name is a label.
const float_bits_symbols = [_][]const u8{ "linea_float64_to_bits", "linea_float64_from_bits", "linea_float32_to_bits", "linea_float32_from_bits" };

/// The library test `name` of `module_name`.
fn testIn(program: *const ExpandedProgram, ast: *const Ast, module_name: []const u8, name: []const u8) DeclId {
    const declared = program.libraryDeclIn(module_name, name) orelse return .none;
    return if (ast.declIsTest(declared)) declared else .none;
}

fn rawAccessDecl(program: *const ExpandedProgram, ast: *const Ast, name: []const u8, arity: usize) DeclId {
    const d = program.libraryDeclIn("mem", name) orelse return DeclId.none;
    if (!ast.declIsExtern(d) or ast.declParams(d).len != arity) return DeclId.none;
    return d;
}

/// The standard library's `mem` declaration of the runtime symbol `symbol`,
/// where its checked signature is the one the runtime table gives it. The
/// checker reports one that is not ([T-ExternRuntime]), so a mismatched
/// declaration receives no intrinsic fact and is never left to the linker.
pub fn libraryExternDecl(program: *const ExpandedProgram, ast: *const Ast, typing: *const Typing, symbol: []const u8) DeclId {
    const expected = runtime_symbols.signatureOf(symbol) orelse return .none;
    const d = program.libraryDeclIn("mem", symbol) orelse return DeclId.none;
    if (!ast.declIsExtern(d) or ast.declTypeParams(d).len != 0) return .none;
    const signature = switch (typing.get(typing.declSignature(d))) {
        .callable => |signature| signature,
        else => return .none,
    };
    if (signature.invocation != .read or signature.contracts.len != 0) return .none;
    for (ast.declParams(d)) |written| if (written.default != .none) return .none;
    return if (matchesRuntime(typing, signature, expected.*)) d else .none;
}

/// Whether a checked `extern` signature is the one the runtime gives: its
/// parameters' types and conventions, and its result, by position.
pub fn matchesRuntime(typing: *const Typing, declared: types_mod.CallableSignature, expected: runtime_symbols.Signature) bool {
    if (declared.result != runtimeScalarType(expected.result)) return false;
    const params = typing.callableParams(declared);
    if (params.len != expected.parameters.len) return false;
    for (params, expected.parameters) |param, want| {
        if (want.scalar == .callback) {
            // The function type must be the one C calls through the address:
            // the same scalars, each by value, and the same result.
            const shape = want.callback orelse return false;
            if (param.convention != .read) return false;
            const called = switch (typing.get(param.ty)) {
                .callable => |callable| callable,
                else => return false,
            };
            if (called.result != runtimeScalarType(shape.result)) return false;
            const taken = typing.callableParams(called);
            if (taken.len != shape.parameters.len) return false;
            for (taken, shape.parameters) |inner, scalar| {
                if (inner.ty != runtimeScalarType(scalar) or inner.convention != .read) return false;
            }
            continue;
        }
        if (param.ty != runtimeScalarType(want.scalar)) return false;
        const convention: @TypeOf(param.convention) = switch (want.passing) {
            .read => .read,
            .inout => .inout,
        };
        if (param.convention != convention) return false;
    }
    return true;
}

test matchesRuntime {
    var b = try Typing.Builder.init(std.testing.allocator);
    defer b.deinit();
    const load = try b.internCallable(&.{
        .{ .spelling = "", .convention = .read, .ty = .u64, .default = .absent },
        .{ .spelling = "", .convention = .read, .ty = .u64, .default = .absent },
        .{ .spelling = "", .convention = .read, .ty = .u64, .default = .absent },
    }, .u64, &.{}, .read);
    const view = b.view();
    try std.testing.expect(matchesRuntime(&view, view.get(load).callable, runtime_symbols.signatureOf("linea_raw_load").?.*));
    try std.testing.expect(!matchesRuntime(&view, view.get(load).callable, runtime_symbols.signatureOf("linea_raw_load8").?.*));
}

/// The type a runtime signature's scalar is in Linea.
pub fn runtimeScalarType(scalar: runtime_symbols.Scalar) TypeId {
    return switch (scalar) {
        .u8 => .u8,
        .i32 => .i32,
        .u32 => .u32,
        .i64 => .i64,
        .u64 => .u64,
        .f32 => .f32,
        .f64 => .f64,
        .unit => .unit,
        // Only the symbols the compiler owns take a pointer, and none of them
        // is declared in Linea. A callback is a callable type of its own
        // declaration, which `matchesRuntime` reads before asking here.
        .ptr, .callback => unreachable,
    };
}

test runtimeScalarType {
    try std.testing.expectEqual(TypeId.i32, runtimeScalarType(.i32));
    try std.testing.expectEqual(TypeId.unit, runtimeScalarType(.unit));
}

/// Whether a scalar-math declaration takes `params` read by value, with no
/// default, and answers `result`.
fn matchesExternSignature(ast: *const Ast, typing: *const Typing, d: DeclId, params: []const TypeId, result: TypeId) bool {
    if (!ast.declIsExtern(d) or ast.declTypeParams(d).len != 0) return false;
    const signature = switch (typing.get(typing.declSignature(d))) {
        .callable => |signature| signature,
        else => return false,
    };
    if (signature.result != result or signature.invocation != .read or signature.contracts.len != 0) return false;
    const declared = typing.callableParams(signature);
    if (declared.len != params.len) return false;
    for (declared, params, ast.declParams(d)) |param, want, written| {
        if (param.ty != want or param.convention != .read or param.default != .absent or written.default != .none) return false;
    }
    return true;
}

// Makes every test build compile the tests `RawAccesses` holds, including a
// build filtered to one of them, which would otherwise never look inside it.
comptime {
    _ = RawAccesses;
}
