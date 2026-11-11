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
    /// does, so only `foreign_at` and `record_release` call it
    /// ([T-RawAddress]).
    number_address: DeclId = .none,
    /// `mem.foreign_at`, through which `std.ffi` reads the memory a C view
    /// names; only the members of `CText` and `CTextList` and its own test
    /// call it.
    foreign_at: DeclId = .none,
    foreign_at_test: DeclId = .none,
    /// The declarations beside a C view's own members that build one: a lent
    /// view of bytes (`bytes_of`), a `CString`'s text (`CString.text`), and an
    /// entry of a list C handed over (`CTextList.get`).
    bytes_of: DeclId = .none,
    c_string_text: DeclId = .none,
    c_text_list_get: DeclId = .none,
    /// `Closure.erase`, the one declaration that takes a storage apart and
    /// keeps its address, as the `at` of the closure that then owns the bytes.
    closure_erase: DeclId = .none,
    /// `mem.keep_body`, `mem.take_kept_body` and `mem.release_kept_bytes`,
    /// which move a task's body into bytes, out of them, and free them, each
    /// trusting the address it is handed. `task.Slot.start` alone keeps a
    /// body and names the release, and `task.run_body`, the entry the new
    /// thread runs, alone takes it ([T-RawAddress]).
    keep_body: DeclId = .none,
    take_kept_body: DeclId = .none,
    release_kept_bytes: DeclId = .none,
    task_run_body: DeclId = .none,
    /// `mem.keep_value` and `mem.take_value`, which move a value into bytes
    /// whose type no longer names it and back out as the type asked for.
    /// Only the members of `task.WaitSet` call them, which take a value out
    /// under the key its registration minted, and the test beside them.
    keep_value: DeclId = .none,
    take_value: DeclId = .none,
    kept_value_test: DeclId = .none,
    /// `task.WaitSet`, whose `set` names the runtime's registrations and
    /// whose `held` keeps their values, slot for slot, and `task.Registered`,
    /// a key: the set, slot and generation of one registration and, as its
    /// type argument, the type of the value kept there. `Registered.minted`
    /// builds one, for the registrations a `WaitSet`'s members make.
    wait_set: DeclId = .none,
    registered: DeclId = .none,
    registered_minted: DeclId = .none,
    registered_minted_test: DeclId = .none,
    registered_names_test: DeclId = .none,
    /// `mem.Vec`, whose `storage` and `len` are the bytes it owns and how many
    /// of its slots are live, which `slot_place` and its release trust.
    vec: DeclId = .none,
    /// `mem.Kept`, the addresses that own a task body kept in bytes.
    kept: DeclId = .none,
    /// `mem.vector_from_buffer` and `mem.vector_into_buffer`, which make a
    /// byte vector from a buffer and take it back.
    vector_from_buffer: DeclId = .none,
    vector_into_buffer: DeclId = .none,
    /// `Vec.split`, which lends a vector's two sides as views.
    vec_split: DeclId = .none,
    /// `mem.Arena`, whose `chunks` is the address of its table of later chunks
    /// inside its first buffer; `Arena.open`, which builds one, and
    /// `Arena.rewind`, which takes back what it handed out.
    arena: DeclId = .none,
    arena_open: DeclId = .none,
    arena_rewind: DeclId = .none,
    /// `mem.Handle` and the arena's free functions that trust the first chunk
    /// they are handed: `arena_give_back` is named only by `Arena`'s members,
    /// `arena_reserve` and `arena_holds` only by `Handle`'s, `arena_table_of`
    /// only by the three that read the table, and `arena_write`, which writes
    /// a word of the first chunk, only by `Arena`'s members and the two free
    /// functions that write its words.
    handle: DeclId = .none,
    handle_dispose: DeclId = .none,
    arena_table_of: DeclId = .none,
    arena_give_back: DeclId = .none,
    arena_reserve: DeclId = .none,
    arena_holds: DeclId = .none,
    arena_write: DeclId = .none,
    /// `Storage.from_buffer`, which takes a buffer apart into slot storage.
    storage_from_buffer: DeclId = .none,
    /// `Storage.dispose` and `Storage.into_buffer`, which give up a storage's
    /// slots without settling them.
    storage_dispose: DeclId = .none,
    storage_into_buffer: DeclId = .none,
    /// The test allocators that build a buffer of their backing allocator,
    /// which they hand out and take back on its behalf, and the members of an
    /// allocation log and a release log that read or write the log's words.
    allocation_log_refuse_attempt: DeclId = .none,
    refusing_acquire: DeclId = .none,
    refusing_dispose: DeclId = .none,
    shared_refusing_acquire: DeclId = .none,
    shared_refusing_dispose: DeclId = .none,
    vec_test_acquire: DeclId = .none,
    vec_test_dispose: DeclId = .none,
    release_log_words: DeclId = .none,
    /// `SystemAllocator.dispose`, which hands the runtime a buffer's address
    /// and extent to free.
    system_allocator_dispose: DeclId = .none,
    /// The free functions of `mem` that hand the runtime a buffer's or a
    /// slice's bytes for a file, a socket, a random source or a float parser, by their
    /// names in `runtime_byte_functions`.
    runtime_byte_callers: [runtime_byte_functions.len]DeclId = @splat(.none),
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
    /// `session.detach`, the free declaration that names a `Chan`'s fields.
    session_detach: DeclId = .none,
    /// `call_owner` and `next_owner_request`, which trust that a queue holds
    /// jobs for the state asked for: `task.Client.call` and `task.run_owner`.
    call_owner: DeclId = .none,
    next_owner_request: DeclId = .none,
    client_call: DeclId = .none,
    /// `task.Owner`, whose `queue` is trusted as an endpoint is, and `task.own`,
    /// which builds one beside its members.
    owner: DeclId = .none,
    task_own: DeclId = .none,
    run_owner: DeclId = .none,
    /// `record_release`, which writes at the number it is given, and its two
    /// callers: `ReleaseTag.release`, whose number is its log's, and the HTTP
    /// test `ProbeTag`, whose extractor reaches the log only through a request
    /// header, so the number crosses as text. `ProbeTag` is built only by
    /// `probe_tag`.
    record_release: DeclId = .none,
    release_tag_release: DeclId = .none,
    probe_tag_release: DeclId = .none,
    probe_tag: DeclId = .none,
    probe_tag_builder: DeclId = .none,
    /// `foreign_byte` and `foreign_word`, which read at an extent they cannot
    /// check, C's memory having none: only `CText`'s and `CTextList`'s members,
    /// `copied_in` and the tests below name them.
    foreign_byte: DeclId = .none,
    foreign_word: DeclId = .none,
    copied_in: DeclId = .none,
    foreign_address_test: DeclId = .none,
    foreign_byte_test: DeclId = .none,
    foreign_word_test: DeclId = .none,
    /// `mem.vec_test_log_store`, which writes a word of a vector test's log.
    vec_test_log_store: DeclId = .none,
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
    foreign_bytes: DeclId = .none,
    c_text: DeclId = .none,
    c_text_list: DeclId = .none,
    /// `ffi.Errno`, which an `extern` answers to have `errno` read after the
    /// call, and the runtime's `linea_errno` that reads it.
    errno: DeclId = .none,
    errno_read: DeclId = .none,

    /// The free functions of `mem` that `runtime_byte_callers` holds.
    const runtime_byte_functions = [_][]const u8{
        "read_fd",            "write_slice_fd",     "read_fd_at",     "write_slice_fd_at",
        "read_socket",        "write_slice_socket", "_random_bytes",  "_open_parent_fd",
        "_open_at_fd",        "_mode_at_fd",        "_publish_at_fd", "_unlink_at_fd",
        "parse_float64_bits", "parse_float32_bits",
    };

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
            .foreign_at = moduleFunction(program, ast, "mem", "foreign_at"),
            .foreign_at_test = testIn(program, ast, "mem", "an_address_at_a_number_names_the_bytes_there"),
            .bytes_of = moduleFunction(program, ast, "ffi", "bytes_of"),
            .c_string_text = memberOf(program, ast, "ffi", "CString", "text"),
            .c_text_list_get = memberOf(program, ast, "ffi", "CTextList", "get"),
            .closure_erase = memberOf(program, ast, "mem", "Closure", "erase"),
            .keep_body = moduleFunction(program, ast, "mem", "keep_body"),
            .take_kept_body = moduleFunction(program, ast, "mem", "take_kept_body"),
            .release_kept_bytes = moduleFunction(program, ast, "mem", "release_kept_bytes"),
            .task_run_body = moduleFunction(program, ast, "task", "run_body"),
            .keep_value = moduleFunction(program, ast, "mem", "keep_value"),
            .take_value = moduleFunction(program, ast, "mem", "take_value"),
            .kept_value_test = testIn(program, ast, "mem", "a_kept_value_comes_back_as_it_went_in"),
            .wait_set = structIn(program, ast, "task", "WaitSet"),
            .registered = structIn(program, ast, "task", "Registered"),
            .registered_minted = memberOf(program, ast, "task", "Registered", "minted"),
            .registered_minted_test = testIn(program, ast, "task", "a_minted_key_names_what_it_was_minted_for"),
            .registered_names_test = testIn(program, ast, "task", "a_copied_key_names_the_same_registration"),
            .vec = structIn(program, ast, "mem", "Vec"),
            .kept = structIn(program, ast, "mem", "Kept"),
            .vector_from_buffer = moduleFunction(program, ast, "mem", "vector_from_buffer"),
            .vector_into_buffer = moduleFunction(program, ast, "mem", "vector_into_buffer"),
            .vec_split = memberOf(program, ast, "mem", "Vec", "split"),
            .arena = structIn(program, ast, "mem", "Arena"),
            .arena_open = memberOf(program, ast, "mem", "Arena", "open"),
            .arena_rewind = memberOf(program, ast, "mem", "Arena", "rewind"),
            .handle = structIn(program, ast, "mem", "Handle"),
            .handle_dispose = memberOf(program, ast, "mem", "Handle", "dispose"),
            .arena_table_of = moduleFunction(program, ast, "mem", "arena_table_of"),
            .arena_give_back = moduleFunction(program, ast, "mem", "arena_give_back"),
            .arena_reserve = moduleFunction(program, ast, "mem", "arena_reserve"),
            .arena_holds = moduleFunction(program, ast, "mem", "arena_holds"),
            .arena_write = moduleFunction(program, ast, "mem", "arena_write"),
            .storage_from_buffer = memberOf(program, ast, "mem", "Storage", "from_buffer"),
            .storage_dispose = memberOf(program, ast, "mem", "Storage", "dispose"),
            .storage_into_buffer = memberOf(program, ast, "mem", "Storage", "into_buffer"),
            .allocation_log_refuse_attempt = memberOf(program, ast, "mem", "AllocationLog", "refuse_attempt"),
            .refusing_acquire = memberOf(program, ast, "mem", "RefusingAllocator", "acquire"),
            .refusing_dispose = memberOf(program, ast, "mem", "RefusingAllocator", "dispose"),
            .shared_refusing_acquire = memberOf(program, ast, "mem", "SharedRefusingAllocator", "acquire"),
            .shared_refusing_dispose = memberOf(program, ast, "mem", "SharedRefusingAllocator", "dispose"),
            .vec_test_acquire = memberOf(program, ast, "mem", "VecTestAllocator", "acquire"),
            .vec_test_dispose = memberOf(program, ast, "mem", "VecTestAllocator", "dispose"),
            .release_log_words = memberOf(program, ast, "mem", "ReleaseLog", "words"),
            .system_allocator_dispose = memberOf(program, ast, "mem", "SystemAllocator", "dispose"),
            .drain = structIn(program, ast, "mem", "Drain"),
            .release_from = moduleFunction(program, ast, "mem", "release_from"),
            .chan_opened = memberOf(program, ast, "session", "Chan", "opened"),
            .send_payload = moduleFunction(program, ast, "mem", "send_payload"),
            .receive_payload = moduleFunction(program, ast, "mem", "receive_payload"),
            .receive_payload_until = moduleFunction(program, ast, "mem", "receive_payload_until"),
            .session_detach = moduleFunction(program, ast, "session", "detach"),
            .call_owner = moduleFunction(program, ast, "mem", "call_owner"),
            .next_owner_request = moduleFunction(program, ast, "mem", "next_owner_request"),
            .client_call = memberOf(program, ast, "task", "Client", "call"),
            .owner = structIn(program, ast, "task", "Owner"),
            .task_own = moduleFunction(program, ast, "task", "own"),
            .run_owner = moduleFunction(program, ast, "task", "run_owner"),
            .record_release = moduleFunction(program, ast, "mem", "record_release"),
            .release_tag_release = memberOf(program, ast, "mem", "ReleaseTag", "release"),
            .probe_tag_release = memberOf(program, ast, "http", "ProbeTag", "release"),
            .probe_tag = structIn(program, ast, "http", "ProbeTag"),
            .probe_tag_builder = moduleFunction(program, ast, "http", "probe_tag"),
            .foreign_byte = moduleFunction(program, ast, "mem", "foreign_byte"),
            .foreign_word = moduleFunction(program, ast, "mem", "foreign_word"),
            .copied_in = moduleFunction(program, ast, "ffi", "copied_in"),
            .foreign_address_test = testIn(program, ast, "mem", "a_foreign_address_is_where_the_bytes_are"),
            .foreign_byte_test = testIn(program, ast, "mem", "a_foreign_byte_is_read_at_its_offset"),
            .foreign_word_test = testIn(program, ast, "mem", "a_foreign_word_is_read_at_its_offset"),
            .vec_test_log_store = moduleFunction(program, ast, "mem", "vec_test_log_store"),
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
            .foreign_bytes = program.libraryDeclIn("ffi", "Bytes") orelse .none,
            .c_text = program.libraryDeclIn("ffi", "CText") orelse .none,
            .c_text_list = program.libraryDeclIn("ffi", "CTextList") orelse .none,
            .errno = program.libraryDeclIn("ffi", "Errno") orelse .none,
        };
        for (runtime_byte_functions, &raw.runtime_byte_callers) |name, *d| d.* = moduleFunction(program, ast, "mem", name);
        inline for (task_entry_points) |name| @field(raw, "task_" ++ name) = moduleFunction(program, ast, "task", name);
        return raw;
    }

    /// `ffi.Bytes`, `ffi.CText` and `ffi.CTextList`, the C views.
    pub fn foreignViews(self: *const RawAccesses) [3]DeclId {
        return .{ self.foreign_bytes, self.c_text, self.c_text_list };
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
    /// its others are. Each declaration is named by its field of
    /// `RawAccesses`.
    pub const RawType = struct {
        decl: []const u8,
        also: []const []const u8 = &.{},
        allocators: bool = false,
    };

    /// The declarations that read or write a buffer's own fields beside
    /// `Buffer`'s members: an arena's bookkeeping, which reads where its
    /// chunks lie and writes its words, and the members of the library's test
    /// logs that read or write their words.
    const buffer_numbers = [_][]const u8{ "arena_open", "arena_rewind", "arena_table_of", "arena_reserve", "arena_holds", "arena_write", "allocation_log_refuse_attempt", "release_log_words" };

    /// The test allocators that build a buffer of their backing allocator,
    /// which they hand out and take back on its behalf, and an arena's handle,
    /// which takes apart a buffer it handed out.
    const backing_buffer_builders = [_][]const u8{ "refusing_acquire", "refusing_dispose", "shared_refusing_acquire", "shared_refusing_dispose", "vec_test_acquire", "vec_test_dispose", "handle_dispose" };

    /// The raw types, with where else each one's fields are named. A
    /// storage's are named where a task body is kept and where a closure
    /// erases the callable it holds, and where an arena reads its table of
    /// chunks; a buffer's where `buffer_numbers` and `Storage.from_buffer`
    /// read or take it apart, and by the allocators that hand one out and
    /// take it back on a backing allocator's behalf; a view's where
    /// `Vec.split` lends its two sides; a vector's where a byte vector
    /// is made from a buffer and taken back; a kept body's where
    /// `task.Slot.start` hands its addresses to the thread it starts; a
    /// `Chan`'s where `session.detach` takes one apart; an owner's where
    /// `task.own` builds one and `task.Client.call` reaches its queue; an
    /// arena's where its free functions and its handle's release read it;
    /// a `ProbeTag`'s where `probe_tag` builds one; and a wait set's and a
    /// key's nowhere else, since the set's number and the key's slot and
    /// generation say which kept value a call takes and as what type.
    pub const raw_types = [_]RawType{
        .{ .decl = "storage", .also = &.{ "keep_body", "take_kept_body", "release_kept_bytes", "closure_erase", "arena_table_of" } },
        .{ .decl = "buffer", .allocators = true, .also = &(buffer_numbers ++ [_][]const u8{"storage_from_buffer"} ++ backing_buffer_builders) },
        .{ .decl = "slice" },
        .{ .decl = "view", .also = &.{"vec_split"} },
        .{ .decl = "closure" },
        .{ .decl = "vec", .also = &.{ "vector_from_buffer", "vector_into_buffer" } },
        .{ .decl = "kept", .also = &.{ "keep_body", "task_slot_start" } },
        .{ .decl = "endpoint", .also = &.{"session_detach"} },
        .{ .decl = "owner", .also = &.{ "client_call", "task_own" } },
        .{ .decl = "arena", .also = &.{ "arena_table_of", "arena_give_back", "arena_reserve", "arena_holds", "handle_dispose" } },
        .{ .decl = "probe_tag", .also = &.{"probe_tag_builder"} },
        .{ .decl = "wait_set" },
        .{ .decl = "registered" },
    };

    /// Whether `owner` is one of the declarations `fields` lists beside the
    /// members of raw type `row` of `raw_types`.
    pub fn rawTypeAlso(self: *const RawAccesses, row: usize, owner: DeclId) bool {
        inline for (raw_types, 0..) |raw_type, i| if (i == row) return self.among(raw_type.also, owner);
        return false;
    }

    /// A raw declaration only the places a row names may name, as a callee or
    /// as a value ([T-RawAddress]): a declaration `allowed` lists, or a
    /// member of an implementation for one of `types`. Each declaration is
    /// named by its field of `RawAccesses`.
    pub const Confinement = struct {
        decls: []const []const u8,
        allowed: []const []const u8 = &.{},
        types: []const []const u8 = &.{},
        message: []const u8,
        help: []const u8,
    };

    /// The declarations beside `Storage`'s and `Vec`'s own members that move
    /// values in and out of slots and give storage up: each takes or hands
    /// on every value it puts before it disposes, so no slot is left live. A
    /// task body's keeping, taking and release, a closure's erasure, a
    /// payload's send and receive, an owning task's call and request, the
    /// release of a vector's elements, the byte vector given back as a
    /// buffer, whose bytes need no settling, and an arena's table of chunks.
    const slot_users = [_][]const u8{ "keep_value", "take_value", "keep_body", "take_kept_body", "release_kept_bytes", "closure_erase", "send_payload", "receive_payload", "receive_payload_until", "call_owner", "next_owner_request", "release_from", "vector_into_buffer", "arena_give_back", "arena_reserve", "arena_holds" };

    const slots_message = "a slot is taken, put, placed or given up only by `Storage` and `Vec` and the declarations the table names, each of which settles or hands on every value it puts";
    const task_help = "start the task with `task.prepare(body)` and `start()`";
    const closure_help = "build the closure with `Closure.open` or `Closure.open_in`";
    const channel_message = "an endpoint is trusted to carry the value asked of it, so only a `Chan`'s own members move a value through one, and only `task.Slot.start` opens one";
    const channel_help = "send or receive through a `Chan`";
    const queue_message = "a queue is trusted to hold jobs for the state asked of it, so only `task.Client.call` and the owning task reach one";
    const queue_help = "call the owning task through a `task.Client`";
    const arena_message = "an arena's bookkeeping trusts the first chunk it is handed, so only the arena's and its handle's own operations call it";
    const arena_help = "use the arena or its handle";
    const wait_set_help = "register the value in a `task.WaitSet`, which answers its key";

    /// The confined declarations and the places each may be named.
    pub const confinements = [_]Confinement{
        .{ .decls = &.{"owned_address_in"}, .allowed = &.{ "arena_open", "storage_from_buffer", "keep_body" }, .message = "`owned_address_in` makes an address that outlives its buffer, so only a declaration that takes the buffer into what the address names calls it", .help = "call `address_in`, whose address borrows the buffer" },
        .{ .decls = &.{"closure_entry"}, .allowed = &.{"closure_erase"}, .message = "a closure's entry is made only where `Closure.erase` erases a callable", .help = closure_help },
        .{ .decls = &.{"closure_settle"}, .allowed = &.{"closure_erase"}, .message = "a closure's release is made only where `Closure.erase` erases a callable", .help = closure_help },
        .{ .decls = &.{"closure_size"}, .allowed = &.{"closure_erase"}, .message = "a closure's size is read only where `Closure.erase` erases a callable", .help = closure_help },
        .{ .decls = &.{"keep_body"}, .allowed = &.{"task_slot_start"}, .message = "a task's body is kept in bytes only by `task.Slot.start`, which hands the addresses to the thread it starts", .help = task_help },
        .{ .decls = &.{"release_kept_bytes"}, .allowed = &.{"task_slot_start"}, .message = "a kept task body's bytes are released only by the thread `task.Slot.start` starts", .help = task_help },
        .{ .decls = &.{"take_kept_body"}, .allowed = &.{"task_run_body"}, .message = "a kept task body is taken only by the thread `task.Slot.start` starts", .help = task_help },
        .{ .decls = &.{"task_run_body"}, .allowed = &.{"task_slot_start"}, .message = "a task's entry is handed only to the thread `task.Slot.start` starts, with the addresses `keep_body` answered", .help = task_help },
        .{ .decls = &.{ "take", "put", "place", "span", "storage_dispose", "storage_into_buffer" }, .allowed = &slot_users, .types = &.{ "storage", "vec", "drain" }, .message = slots_message, .help = "use the vector's or the storage's own operations" },
        .{ .decls = &.{"number_address"}, .allowed = &.{ "foreign_at", "record_release" }, .message = "`number_address` makes an address of any number, so only the declarations the table names, each reading memory C or a test log handed over, call it", .help = "reach bytes through an address made from what owns them" },
        .{ .decls = &.{"foreign_at"}, .allowed = &.{"foreign_at_test"}, .types = &.{ "c_text", "c_text_list" }, .message = "`foreign_at` makes an address of the number a C view holds, so only that view's own members call it, under a contract tying the address to the view", .help = "read the view through its own operations" },
        .{ .decls = &.{ "send_payload", "receive_payload", "receive_payload_until" }, .types = &.{"endpoint"}, .message = channel_message, .help = channel_help },
        .{ .decls = &.{"chan_opened"}, .allowed = &.{ "task_run_body", "task_slot_start" }, .types = &.{"endpoint"}, .message = channel_message, .help = channel_help },
        .{ .decls = &.{"call_owner"}, .allowed = &.{"client_call"}, .message = queue_message, .help = queue_help },
        .{ .decls = &.{"next_owner_request"}, .allowed = &.{"run_owner"}, .message = queue_message, .help = queue_help },
        .{ .decls = &.{"arena_give_back"}, .types = &.{"arena"}, .message = arena_message, .help = arena_help },
        .{ .decls = &.{ "arena_reserve", "arena_holds" }, .types = &.{"handle"}, .message = arena_message, .help = arena_help },
        .{ .decls = &.{"arena_table_of"}, .allowed = &.{ "arena_give_back", "arena_reserve", "arena_holds" }, .message = arena_message, .help = arena_help },
        .{ .decls = &.{"arena_write"}, .allowed = &.{ "arena_give_back", "arena_reserve" }, .types = &.{"arena"}, .message = arena_message, .help = arena_help },
        .{ .decls = &.{"record_release"}, .allowed = &.{ "release_tag_release", "probe_tag_release" }, .message = "`record_release` writes at the number it is given, so only the declarations the table names call it", .help = "release a `ReleaseTag`" },
        .{ .decls = &.{ "foreign_byte", "foreign_word" }, .allowed = &.{ "copied_in", "foreign_address_test", "foreign_byte_test", "foreign_word_test", "foreign_at_test" }, .types = &.{ "c_text", "c_text_list" }, .message = "C's memory has no extent to check a read against, so only a C view's own operations read it", .help = "read the view through its own operations" },
        .{ .decls = &.{ "keep_value", "take_value" }, .allowed = &.{"kept_value_test"}, .types = &.{"wait_set"}, .message = "a kept value is trusted to be of the type asked for, so only a `task.WaitSet`'s own members keep one and take it back, under the key its registration minted", .help = wait_set_help },
        .{ .decls = &.{"registered_minted"}, .allowed = &.{ "registered_minted_test", "registered_names_test" }, .types = &.{"wait_set"}, .message = "a key is trusted to name a value of its type, so only the registrations of a `task.WaitSet` mint one", .help = wait_set_help },
        .{ .decls = &.{"release_from"}, .types = &.{ "vec", "drain" }, .message = "`release_from` trusts the counts it is given, so only a vector's and a drain's own members, which know how many slots are live, call it", .help = "release the vector or the drain itself" },
    };

    /// The places that may hand a runtime symbol or lowered primitive an
    /// address and the extent beside it, which the symbol trusts: the members
    /// of `Buffer`, `Storage` and `Chan`, and the declarations beside them
    /// that `allowed` lists, each an extent it has read from what owns the
    /// bytes ([T-RawAddress]).
    pub const byte_operations: Confinement = .{
        .decls = &.{},
        .allowed = &.{ "arena_write", "system_allocator_dispose", "runtime_byte_callers", "call_owner", "next_owner_request", "send_payload", "receive_payload", "receive_payload_until", "allocation_log_refuse_attempt", "refusing_acquire", "refusing_dispose", "record_release", "foreign_byte", "foreign_word", "vec_test_log_store", "task_slot_start" },
        .types = &.{ "buffer", "storage", "endpoint" },
        .message = "trusts the extent beside its address, so only the declarations the table names pass one",
        .help = "use the operation of what owns the bytes",
    };

    /// The declarations beside a C view's own members that build one.
    const foreign_view_builders = [_][]const u8{ "bytes_of", "c_string_text", "c_text_list_get" };

    /// Whether `owner` is one of `foreign_view_builders`.
    pub fn buildsForeignView(self: *const RawAccesses, owner: DeclId) bool {
        return self.among(&foreign_view_builders, owner);
    }

    /// Whether `owner` may name the declarations of row `row` of
    /// `confinements`; `members.memberOfType(owner, decl)` answers whether
    /// `owner` is a member of an implementation for the type `decl`.
    pub fn confinementAdmits(self: *const RawAccesses, row: usize, owner: DeclId, members: anytype) bool {
        inline for (confinements, 0..) |confinement, i| if (i == row) return self.admits(confinement, owner, members);
        return false;
    }

    /// Whether `owner` is one of the places `confinement` names.
    pub fn admits(self: *const RawAccesses, comptime confinement: Confinement, owner: DeclId, members: anytype) bool {
        if (self.among(confinement.allowed, owner)) return true;
        inline for (confinement.types) |name| if (members.memberOfType(owner, @field(self, name))) return true;
        return false;
    }

    /// Whether `d` is one of the declarations the fields `names` hold.
    fn among(self: *const RawAccesses, comptime names: []const []const u8, d: DeclId) bool {
        if (d == .none) return false;
        inline for (names) |name| {
            const held = @field(self, name);
            if (@TypeOf(held) == DeclId) {
                if (held == d) return true;
            } else if (std.mem.indexOfScalar(DeclId, &held, d) != null) return true;
        }
        return false;
    }

    /// The rows of `raw_types` and `confinements` by the declaration each
    /// names, so a check asks one lookup per expression. Where two rows name
    /// one declaration the first answers.
    pub const Index = struct {
        raw_types: std.AutoHashMapUnmanaged(DeclId, u8) = .empty,
        confined: std.AutoHashMapUnmanaged(DeclId, u8) = .empty,

        pub fn init(gpa: std.mem.Allocator, raw: *const RawAccesses) std.mem.Allocator.Error!Index {
            var index: Index = .{};
            errdefer index.deinit(gpa);
            inline for (raw_types, 0..) |raw_type, i| try put(gpa, &index.raw_types, @field(raw, raw_type.decl), i);
            inline for (confinements, 0..) |confinement, i| {
                inline for (confinement.decls) |name| try put(gpa, &index.confined, @field(raw, name), i);
            }
            return index;
        }

        fn put(gpa: std.mem.Allocator, map: *std.AutoHashMapUnmanaged(DeclId, u8), d: DeclId, row: usize) std.mem.Allocator.Error!void {
            if (d == .none) return;
            const entry = try map.getOrPut(gpa, d);
            if (!entry.found_existing) entry.value_ptr.* = @intCast(row);
        }

        pub fn deinit(self: *Index, gpa: std.mem.Allocator) void {
            self.raw_types.deinit(gpa);
            self.confined.deinit(gpa);
        }
    };

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
