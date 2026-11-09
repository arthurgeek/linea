const std = @import("std");
const testing = std.testing;

pub const library_name = "linea_rt";
pub const archive_name = "lib" ++ library_name ++ ".a";
/// The same runtime with the checking allocator, which turns a use of freed
/// storage, a second disposal or a store outside an allocation into an abort.
pub const checked_archive_name = "lib" ++ library_name ++ "_checked.a";

pub const entry = "main";
pub const trap = "linea_trap";
pub const panic = "linea_panic";
pub const set_args = "linea_set_args";
/// What the runtime's I/O entries hand every extent to before a system call.
pub const storage_extent = "linea_storage_extent";
/// What the socket operations call to check the bytes they are handed, as the
/// I/O entries do.
pub const byte_range = "linea_io_byte_range";
/// Defined only by the checking runtime, so an archive answers whether it
/// checks storage.
pub const storage_checked = "linea_storage_checked";
/// What a task's thread calls before and after it runs Linea code, to install
/// and remove its alternate signal stack and record its stack's guard.
pub const thread_begin = "linea_thread_begin";
pub const thread_end = "linea_thread_end";

/// Whether a runtime archive holds the checking allocator: whether its bytes
/// name the symbol only that allocator defines. Every archive format spells a
/// defined symbol in its symbol table.
pub fn holdsStorageChecks(archive: []const u8) bool {
    return std.mem.indexOf(u8, archive, storage_checked) != null;
}

test "an archive holds the checking allocator where it names its marker" {
    try testing.expect(holdsStorageChecks("!<arch>\n..._linea_storage_checked..."));
    try testing.expect(!holdsStorageChecks("!<arch>\n..._linea_alloc..._linea_free..."));
}

/// Every symbol the runtime and the C startup path own.
///
/// A symbol this language defines carries a prefix, and that prefix is what
/// stops a declaration called `linea_trap` linking against the runtime's — a
/// trap that does not trap is the worst shape of failure. An `export`
/// deliberately steps outside the prefix, because a C header has to read like
/// the source, so it needs this instead: the one place that says which names
/// are already spoken for.
///
/// Two passes read it for opposite reasons. The checker reads it to refuse an
/// export that would collide, before anything is emitted. The backend reads it
/// to spell the symbols themselves, so what is refused and what is defined
/// cannot drift into disagreeing about a name.
const owned = [_][]const u8{
    // What the C runtime calls, which the entry wrapper defines for a program.
    entry,
    // What a trap reaches, and what a program hands its arguments to.
    trap,
    panic,
    set_args,
    // What the runtime's own files call between themselves.
    storage_extent,
    byte_range,
    storage_checked,
    thread_begin,
    thread_end,
};

/// Whether a name is one the runtime already owns.
pub fn holds(name: []const u8) bool {
    for (owned) |s| {
        if (std.mem.eql(u8, s, name)) return true;
    }
    for (std.enums.values(@import("float_math.zig").Operation)) |operation| {
        if (std.mem.eql(u8, operation.symbol(), name)) return true;
    }
    return false;
}

test "a runtime symbol is refused and an ordinary name is not" {
    try testing.expect(holds("linea_trap"));
    try testing.expect(holds("linea_panic"));
    try testing.expect(holds("main"));
    try testing.expect(!holds("square"));
    // A name that merely begins the same way is a different symbol: a linker
    // compares the whole of one.
    try testing.expect(!holds("linea_trap_of_mine"));
    try testing.expect(!holds(""));
}

/// A scalar a runtime function's signature names, as C and Linea agree on it.
/// `ptr` is an address the compiler passes as a pointer: no Linea declaration
/// spells it, so only the symbols the compiler owns use it. `callback` is the
/// address of a function C calls: the Linea declaration spells a plain `fn`
/// type, whose parameters and result [T-ExternCallback] holds to what
/// crosses, and C a function pointer type.
pub const Scalar = enum { u8, i32, u32, i64, u64, f32, f64, ptr, callback, unit };

/// How a runtime function takes a parameter: by value, or through a pointer
/// the callee writes, which a Linea declaration spells `inout`.
pub const Passing = enum { read, inout };

/// The function a `callback` parameter's address names, as C calls it: the
/// scalars it takes, each by value, and the one it answers. `address` is the
/// position of a parameter C passes an address of typed bytes in, the one the
/// call that took the callback was given; the function a program passes may
/// declare that parameter as a `mem.address.Address`, which crosses as its
/// `UInt64`.
pub const Callback = struct { parameters: []const Scalar, result: Scalar, address: ?u8 = null };

/// A parameter's scalar, how it is passed, and for a `callback` the shape of
/// the function C calls through it, which [T-ExternRuntime] holds the Linea
/// declaration's function type to. `address` marks a `u64` that is the
/// address of bytes the runtime reads, writes or frees: typed bytes it copies
/// to another task before the call returns, writes with bytes another task
/// sent, or keeps for a task it starts, and a buffer's or a slice's bytes it
/// hands a system call, parses or frees. It is the one place [T-RawAddress]
/// lets `address.raw` turn an address into a number, so the argument there
/// is an `Address` the standard library made from what owns the bytes.
pub const Parameter = struct { scalar: Scalar, passing: Passing = .read, callback: ?*const Callback = null, address: bool = false, held: Held = .none };

/// What a number crossing to or from the runtime stands for, where a value
/// must own it for the call to be safe: the address of bytes a buffer or a
/// slice holds, a descriptor, or an allocation. The runtime trusts each such
/// number, so a symbol taking or answering one is confined to the standard
/// library module whose types keep it, which the table's test holds.
pub const Held = enum { none, bytes, descriptor, allocation };

/// Whether two parameters are the same as C declares them, a callback's shape
/// compared by what it holds rather than by where it is. Which parameter is an
/// address of typed bytes is the table's to say, and C's prototype says
/// nothing of it, so the mark is not compared.
pub fn sameParameter(a: Parameter, b: Parameter) bool {
    if (a.scalar != b.scalar or a.passing != b.passing) return false;
    const left = a.callback orelse return b.callback == null;
    const right = b.callback orelse return false;
    return left.result == right.result and std.mem.eql(Scalar, left.parameters, right.parameters);
}

test "parameters are compared by the callback shape they hold" {
    const three: Callback = .{ .parameters = &.{ .u64, .u64, .u64 }, .result = .unit };
    const also: Callback = .{ .parameters = &.{ .u64, .u64, .u64 }, .result = .unit };
    const two: Callback = .{ .parameters = &.{ .u64, .u64 }, .result = .unit };
    try testing.expect(sameParameter(.{ .scalar = .callback, .callback = &three }, .{ .scalar = .callback, .callback = &also }));
    try testing.expect(!sameParameter(.{ .scalar = .callback, .callback = &three }, .{ .scalar = .callback, .callback = &two }));
    try testing.expect(!sameParameter(.{ .scalar = .callback, .callback = &three }, .{ .scalar = .callback }));
    try testing.expect(sameParameter(.{ .scalar = .u64 }, .{ .scalar = .u64 }));
}

/// Where a symbol's definition comes from.
pub const Provider = enum {
    /// The runtime library defines it; `runtime/` holds its C prototype.
    runtime,
    /// Lowering replaces the standard library's declaration of it with a
    /// checked access or a bit cast, so no definition exists anywhere to link
    /// against.
    lowering,
    /// The emitted module defines it, because C's startup calls it.
    generated,
};

/// Which declarations may name a symbol ([T-ExternRuntime]).
pub const DeclaredBy = union(enum) {
    /// The compiler, which refuses the name in any declaration ([T-Extern]).
    compiler,
    /// Any module its root grants `extern`, the standard library's included.
    /// Only a symbol that neither answers nor takes a number something must
    /// own -- an allocation, a descriptor, an address of bytes -- is open.
    granted,
    /// The standard library's `module` alone. The runtime trusts every call of
    /// such a symbol with a number only that module's types keep: an
    /// allocation, a descriptor, a parked thread, a call queue or an endpoint
    /// that a linear value owns, the address of bytes a buffer or a slice
    /// holds, or the address of typed bytes `address.raw` gives. A symbol lowering replaces
    /// is held here too, since only that module's declaration is replaced.
    /// `reached_through` is the standard library operation a program calls
    /// instead, which the refusal of another declaration names.
    library: struct { module: []const u8, reached_through: []const u8 },

    /// The standard library module that alone may declare the symbol, or null.
    pub fn home(self: DeclaredBy) ?[]const u8 {
        return switch (self) {
            .library => |library| library.module,
            else => null,
        };
    }
};

/// One function in the `linea_` namespace and the signature it has.
pub const Signature = struct {
    symbol: []const u8,
    parameters: []const Parameter,
    result: Scalar,
    /// What the result stands for, where something must own it.
    answers: Held = .none,
    provider: Provider = .runtime,
    /// Which declarations may name it. Every row states it, so a symbol added
    /// to the table is not open to every module granted `extern` unless its
    /// row says so.
    declared_by: DeclaredBy,
    /// Control never returns from a call to it.
    noreturn: bool = false,
    /// The runtime calls back into Linea code on a thread it creates, so a
    /// body handed to it runs while its caller goes on ([T-ThreadStart]).
    starts_thread: bool = false,
};

fn p(scalar: Scalar) Parameter {
    return .{ .scalar = scalar };
}

/// The address of typed bytes another task reads or writes; see
/// `Parameter.address`.
const typed_bytes: Parameter = .{ .scalar = .u64, .address = true };

/// A `callback` parameter naming a function C calls with `parameters` and
/// expects `result` from, whose parameter at `address` is the address the
/// call was given for it.
fn cb(comptime parameters: []const Scalar, comptime result: Scalar, comptime address: u8) Parameter {
    const shape = comptime Callback{ .parameters = parameters, .result = result, .address = address };
    return .{ .scalar = .callback, .callback = &shape };
}

const written: Parameter = .{ .scalar = .u64, .passing = .inout };

/// The address of bytes a buffer or a slice holds, which the runtime reads or
/// writes. Passed as `address.raw` of an `Address[UInt8]` the standard
/// library made from the buffer or slice.
const bytes_at: Parameter = .{ .scalar = .u64, .held = .bytes, .address = true };
/// The address of bytes a storage primitive reads or writes. Lowering replaces
/// the call with an access it checks against the extent beside it, so no
/// runtime is handed it; the number may be one C handed over, which no
/// `Address` names.
const checked_at: Parameter = .{ .scalar = .u64, .held = .bytes };
/// A descriptor a linear value owns.
const descriptor: Parameter = .{ .scalar = .i32, .held = .descriptor };
/// The address of an allocation a buffer owns, which the runtime frees.
const allocation: Parameter = .{ .scalar = .u64, .held = .allocation, .address = true };

/// What C's startup calls: the wrapper the emitted module defines around the
/// program's entry. The runtime's `linea_set_args` receives what it is passed.
pub const entry_signature: Signature = .{
    .symbol = entry,
    .declared_by = .compiler,
    .parameters = &.{ p(.i32), p(.ptr) },
    .result = .i32,
    .provider = .generated,
};
/// A trap: the kind's number, then the file name and the line and column.
pub const trap_signature: Signature = .{
    .symbol = trap,
    .declared_by = .compiler,
    .parameters = &.{ p(.i32), p(.ptr), p(.i32), p(.i32) },
    .result = .unit,
    .noreturn = true,
};
/// A panic: the message's address and length, then the file name and the line
/// and column.
pub const panic_signature: Signature = .{
    .symbol = panic,
    .declared_by = .compiler,
    .parameters = &.{ p(.u64), p(.u64), p(.ptr), p(.i32), p(.i32) },
    .result = .unit,
    .noreturn = true,
};
/// The program's argument count and vector, handed over before it runs.
pub const set_args_signature: Signature = .{
    .symbol = set_args,
    .declared_by = .compiler,
    .parameters = &.{ p(.i32), p(.ptr) },
    .result = .unit,
};
pub const storage_extent_signature: Signature = .{
    .symbol = storage_extent,
    .declared_by = .compiler,
    .parameters = &.{ p(.u64), p(.u64) },
    .result = .unit,
};
/// The alternate signal stack's address and size, then the bounds of the
/// stack's guard pages. It answers zero, or the errno that kept the signal
/// stack from being installed.
/// The address and length of a program's bytes; it answers zero, or the errno
/// that keeps them from a system call.
pub const byte_range_signature: Signature = .{
    .symbol = byte_range,
    .declared_by = .compiler,
    .parameters = &.{ p(.u64), p(.u64) },
    .result = .i32,
};
pub const thread_begin_signature: Signature = .{
    .symbol = thread_begin,
    .declared_by = .compiler,
    .parameters = &.{ p(.u64), p(.u64), p(.u64), p(.u64) },
    .result = .i32,
};
pub const thread_end_signature: Signature = .{
    .symbol = thread_end,
    .declared_by = .compiler,
    .parameters = &.{},
    .result = .unit,
};

/// The signature of every float-math operation, in the operation's own order.
pub const math_functions = math: {
    const operations = std.enums.values(@import("float_math.zig").Operation);
    var table: [operations.len]Signature = undefined;
    for (operations, 0..) |operation, i| {
        table[i] = .{
            .symbol = operation.symbol(),
            .parameters = if (operation.arity() == 2) &.{ p(.f64), p(.f64) } else &.{p(.f64)},
            .result = .f64,
            .declared_by = .compiler,
        };
    }
    break :math table;
};

/// Every function the compiler owns, with the signature its emitted calls and
/// declarations are written from and that the runtime's C is held to. The
/// emitter prints from these rows rather than restating widths, so a width
/// changed here changes the module and is compared with the C by the test in
/// `build/`.
pub const owned_functions = [_]Signature{
    entry_signature,
    trap_signature,
    panic_signature,
    set_args_signature,
    storage_extent_signature,
    byte_range_signature,
    thread_begin_signature,
    thread_end_signature,
} ++ math_functions;

test "every function the compiler owns is a name the runtime refuses" {
    for (owned_functions) |signature| try testing.expect(holds(signature.symbol));
}

fn heldBy(comptime module: []const u8, comptime reached_through: []const u8) DeclaredBy {
    return .{ .library = .{ .module = module, .reached_through = reached_through } };
}

// An allocation is a number the runtime answers and takes back; `mem.Buffer`,
// a linear value, is what keeps it, so a second disposal or one at another
// size is unwritable outside `mem`.
const mem_allocation = heldBy("mem", "`acquire` on an allocator");
const mem_release = heldBy("mem", "`release` on a `mem.Buffer`");
// A descriptor is a number a linear `fs.File`, `net.Connection` or
// `net.Listener` keeps, and each of these also takes the address of bytes a
// `mem.Buffer` or `mem.Slice` holds.
const mem_transfer = heldBy("mem", "the reads and writes of `io`, `fs.File` and `net.Connection`");
const mem_close = heldBy("mem", "`close` on an `fs.File`, a `net.Connection` or a `net.Listener`");
const mem_files = heldBy("mem", "the standard library's `fs` operations");
const mem_arguments = heldBy("mem", "`env.args`");
const mem_environment = heldBy("mem", "`env.variable` and `env.variables`");
const mem_parse = heldBy("mem", "parsing a `Float64` or a `Float32` from text");
const fs_mode = heldBy("fs", "the standard library's `fs` operations");
const net_listener = heldBy("net", "`net.listen` and the `net.Listener` it answers");
const net_connection = heldBy("net", "`net.connect` and the `net.Connection` it answers");

/// Every `linea_` function an `extern` may name, with its signature. The
/// namespace is the runtime's: a declaration of one of these is held to the
/// signature here in whatever root declares it, the standard library's
/// included, and a `linea_` symbol this table does not hold is refused
/// ([T-ExternRuntime]). A test in `build/` reads the runtime's C and holds this
/// table to it, so the two cannot drift.
///
/// A row's `declared_by` says which roots may declare it: any module granted
/// `extern`, or one module of the standard library, whose types keep what the
/// runtime hands out and takes in.
///
/// The symbols `holds` names -- the entry point, traps, argument setup and the
/// float-math operations -- are owned by the compiler and refused by name
/// ([T-Extern]), so they are not repeated here.
pub const runtime_functions = [_]Signature{
    .{ .symbol = "linea_alloc", .parameters = &.{ p(.u64), p(.u64) }, .result = .u64, .answers = .allocation, .declared_by = mem_allocation },
    .{ .symbol = "linea_free", .parameters = &.{ allocation, p(.u64), p(.u64) }, .result = .unit, .declared_by = mem_release },
    .{ .symbol = "linea_arg_count", .parameters = &.{}, .result = .u64, .declared_by = .granted },
    .{ .symbol = "linea_arg_at", .parameters = &.{p(.u64)}, .result = .u64, .answers = .bytes, .declared_by = mem_arguments },
    .{ .symbol = "linea_arg_len", .parameters = &.{p(.u64)}, .result = .u64, .declared_by = .granted },
    .{ .symbol = "linea_env_count", .parameters = &.{}, .result = .u64, .declared_by = .granted },
    .{ .symbol = "linea_env_at", .parameters = &.{p(.u64)}, .result = .u64, .answers = .bytes, .declared_by = mem_environment },
    .{ .symbol = "linea_env_len", .parameters = &.{p(.u64)}, .result = .u64, .declared_by = .granted },
    .{ .symbol = "linea_io_category", .parameters = &.{p(.i32)}, .result = .u8, .declared_by = .granted },
    .{ .symbol = "linea_errno", .parameters = &.{}, .result = .i32, .declared_by = .granted },
    .{ .symbol = "linea_read_some", .parameters = &.{ descriptor, bytes_at, p(.u64) }, .result = .i64, .declared_by = mem_transfer },
    .{ .symbol = "linea_write_some", .parameters = &.{ descriptor, bytes_at, p(.u64) }, .result = .i64, .declared_by = mem_transfer },
    .{ .symbol = "linea_net_read", .parameters = &.{ descriptor, bytes_at, p(.u64), p(.u64) }, .result = .i64, .declared_by = mem_transfer },
    .{ .symbol = "linea_net_write", .parameters = &.{ descriptor, bytes_at, p(.u64), p(.u64) }, .result = .i64, .declared_by = mem_transfer },
    .{ .symbol = "linea_read_at", .parameters = &.{ descriptor, bytes_at, p(.u64), p(.u64) }, .result = .i64, .declared_by = mem_transfer },
    .{ .symbol = "linea_write_at", .parameters = &.{ descriptor, bytes_at, p(.u64), p(.u64) }, .result = .i64, .declared_by = mem_transfer },
    .{ .symbol = "linea_close", .parameters = &.{descriptor}, .result = .i64, .declared_by = mem_close },
    .{ .symbol = "linea_random_bytes", .parameters = &.{ bytes_at, p(.u64) }, .result = .i64, .declared_by = mem_files },
    .{ .symbol = "linea_random_words", .parameters = &.{ written, written }, .result = .i64, .declared_by = .granted },
    .{ .symbol = "linea_open_parent", .parameters = &.{ bytes_at, p(.u64) }, .result = .i64, .answers = .descriptor, .declared_by = mem_files },
    .{ .symbol = "linea_open_at", .parameters = &.{ descriptor, bytes_at, p(.u64), p(.u8), p(.u64) }, .result = .i64, .answers = .descriptor, .declared_by = mem_files },
    .{ .symbol = "linea_mode_at", .parameters = &.{ descriptor, bytes_at, p(.u64) }, .result = .i64, .declared_by = mem_files },
    .{ .symbol = "linea_set_mode", .parameters = &.{ descriptor, p(.u64) }, .result = .i64, .declared_by = fs_mode },
    .{ .symbol = "linea_publish_at", .parameters = &.{ descriptor, bytes_at, p(.u64), bytes_at, p(.u64), p(.u8) }, .result = .i64, .declared_by = mem_files },
    .{ .symbol = "linea_unlink_at", .parameters = &.{ descriptor, bytes_at, p(.u64) }, .result = .i64, .declared_by = mem_files },
    .{ .symbol = "linea_raise_open_files", .parameters = &.{}, .result = .i64, .declared_by = .granted },
    .{ .symbol = "linea_net_listen", .parameters = &.{ p(.u64), p(.u64) }, .result = .i64, .answers = .descriptor, .declared_by = net_listener },
    .{ .symbol = "linea_net_accept", .parameters = &.{ descriptor, p(.u64) }, .result = .i64, .answers = .descriptor, .declared_by = net_listener },
    .{ .symbol = "linea_net_connect", .parameters = &.{ p(.u64), p(.u64) }, .result = .i64, .answers = .descriptor, .declared_by = net_connection },
    .{ .symbol = "linea_net_local_address", .parameters = &.{descriptor}, .result = .i64, .declared_by = net_listener },
    .{ .symbol = "linea_net_peer_address", .parameters = &.{descriptor}, .result = .i64, .declared_by = net_connection },
    .{ .symbol = "linea_net_shutdown_write", .parameters = &.{descriptor}, .result = .i64, .declared_by = net_connection },
    .{ .symbol = "linea_net_reset", .parameters = &.{descriptor}, .result = .i64, .declared_by = net_connection },
    .{ .symbol = "linea_clock_read", .parameters = &.{ p(.u8), .{ .scalar = .i64, .passing = .inout }, written }, .result = .i64, .declared_by = .granted },
    .{ .symbol = "linea_clock_sleep", .parameters = &.{p(.u64)}, .result = .i64, .declared_by = .granted },
    // A task's thread and the rendezvous channel of its session.
    .{ .symbol = "linea_task_prepare", .parameters = &.{p(.u64)}, .result = .i64, .declared_by = .{ .library = .{ .module = "task", .reached_through = "`task.prepare` and `task.prepare_in`" } } },
    .{ .symbol = "linea_owner_open", .parameters = &.{}, .result = .u64, .declared_by = .{ .library = .{ .module = "task", .reached_through = "`task.own`" } } },
    .{ .symbol = "linea_owner_call", .parameters = &.{ p(.u64), typed_bytes, p(.u64), typed_bytes, p(.u64) }, .result = .unit, .declared_by = .{ .library = .{ .module = "mem", .reached_through = "`call` on a `task.Client`" } } },
    .{ .symbol = "linea_owner_next", .parameters = &.{ p(.u64), typed_bytes, p(.u64) }, .result = .u8, .declared_by = .{ .library = .{ .module = "mem", .reached_through = "`task.own`" } } },
    .{ .symbol = "linea_owner_answer", .parameters = &.{ p(.u64), typed_bytes, p(.u64) }, .result = .unit, .declared_by = .{ .library = .{ .module = "mem", .reached_through = "`call` on a `task.Client`" } } },
    .{ .symbol = "linea_owner_done", .parameters = &.{p(.u64)}, .result = .unit, .declared_by = .{ .library = .{ .module = "task", .reached_through = "`task.own`" } } },
    .{ .symbol = "linea_owner_close", .parameters = &.{p(.u64)}, .result = .unit, .declared_by = .{ .library = .{ .module = "task", .reached_through = "`close` on a `task.Owner`" } } },
    .{ .symbol = "linea_owner_free", .parameters = &.{p(.u64)}, .result = .unit, .declared_by = .{ .library = .{ .module = "task", .reached_through = "`close` on a `task.Owner`" } } },
    .{ .symbol = "linea_task_start", .parameters = &.{ p(.u64), cb(&.{ .u64, .u64, .u64 }, .unit, 1), cb(&.{ .u64, .u64 }, .unit, 0), typed_bytes, p(.u64), typed_bytes }, .result = .u64, .starts_thread = true, .declared_by = .{ .library = .{ .module = "task", .reached_through = "`start` on a `task.Slot`" } } },
    .{ .symbol = "linea_task_cancel", .parameters = &.{p(.u64)}, .result = .unit, .declared_by = .{ .library = .{ .module = "task", .reached_through = "`cancel` on a `task.Slot`" } } },
    .{ .symbol = "linea_chan_send", .parameters = &.{ p(.u64), typed_bytes, p(.u64) }, .result = .unit, .declared_by = .{ .library = .{ .module = "mem", .reached_through = "`send` on a `session.Chan`" } } },
    .{ .symbol = "linea_chan_recv", .parameters = &.{ p(.u64), typed_bytes, p(.u64) }, .result = .unit, .declared_by = .{ .library = .{ .module = "mem", .reached_through = "`recv` on a `session.Chan`" } } },
    .{ .symbol = "linea_chan_choose", .parameters = &.{ p(.u64), p(.u8) }, .result = .unit, .declared_by = .{ .library = .{ .module = "session", .reached_through = "`choose_left` and `choose_right` on a `session.Chan`" } } },
    .{ .symbol = "linea_chan_offer", .parameters = &.{p(.u64)}, .result = .u8, .declared_by = .{ .library = .{ .module = "session", .reached_through = "`offer` on a `session.Chan`" } } },
    .{ .symbol = "linea_chan_close", .parameters = &.{p(.u64)}, .result = .unit, .declared_by = .{ .library = .{ .module = "session", .reached_through = "`close` on a `session.Chan`" } } },
    .{ .symbol = "linea_chan_recv_until", .parameters = &.{ p(.u64), typed_bytes, p(.u64), p(.u64) }, .result = .u8, .declared_by = .{ .library = .{ .module = "mem", .reached_through = "`recv_until` on a `session.Chan`" } } },
    .{ .symbol = "linea_float64_parse", .parameters = &.{ bytes_at, p(.u64), written, written }, .result = .u64, .declared_by = mem_parse },
    .{ .symbol = "linea_float64_debug", .parameters = &.{ p(.u64), written, written, written, written }, .result = .u64, .declared_by = .granted },
    .{ .symbol = "linea_float64_shortest", .parameters = &.{ p(.u64), .{ .scalar = .i64, .passing = .inout } }, .result = .u64, .declared_by = .granted },
    .{ .symbol = "linea_float32_parse", .parameters = &.{ bytes_at, p(.u64), written, written }, .result = .u64, .declared_by = mem_parse },
    .{ .symbol = "linea_float32_debug", .parameters = &.{ p(.u64), written, written, written, written }, .result = .u64, .declared_by = .granted },
    .{ .symbol = "linea_float32_shortest", .parameters = &.{ p(.u64), .{ .scalar = .i64, .passing = .inout } }, .result = .u64, .declared_by = .granted },
    .{ .symbol = "linea_raw_load", .parameters = &.{ checked_at, p(.u64), p(.u64) }, .result = .u64, .provider = .lowering, .declared_by = .{ .library = .{ .module = "mem", .reached_through = "the standard library's checked storage operations" } } },
    .{ .symbol = "linea_raw_load8", .parameters = &.{ checked_at, p(.u64), p(.u64) }, .result = .u8, .provider = .lowering, .declared_by = .{ .library = .{ .module = "mem", .reached_through = "the standard library's checked storage operations" } } },
    .{ .symbol = "linea_raw_store", .parameters = &.{ checked_at, p(.u64), p(.u64), p(.u64) }, .result = .unit, .provider = .lowering, .declared_by = .{ .library = .{ .module = "mem", .reached_through = "the standard library's checked storage operations" } } },
    .{ .symbol = "linea_raw_store8", .parameters = &.{ checked_at, p(.u64), p(.u64), p(.u8) }, .result = .unit, .provider = .lowering, .declared_by = .{ .library = .{ .module = "mem", .reached_through = "the standard library's checked storage operations" } } },
    // A float's IEEE 754 bits as the unsigned integer of its width, and back.
    // Lowering replaces each with a bit-for-bit reinterpretation.
    .{ .symbol = "linea_float64_to_bits", .parameters = &.{p(.f64)}, .result = .u64, .provider = .lowering, .declared_by = .{ .library = .{ .module = "mem", .reached_through = "`Float64.to_bits`" } } },
    .{ .symbol = "linea_float64_from_bits", .parameters = &.{p(.u64)}, .result = .f64, .provider = .lowering, .declared_by = .{ .library = .{ .module = "mem", .reached_through = "`Float64.from_bits`" } } },
    .{ .symbol = "linea_float32_to_bits", .parameters = &.{p(.f32)}, .result = .u32, .provider = .lowering, .declared_by = .{ .library = .{ .module = "mem", .reached_through = "`Float32.to_bits`" } } },
    .{ .symbol = "linea_float32_from_bits", .parameters = &.{p(.u32)}, .result = .f32, .provider = .lowering, .declared_by = .{ .library = .{ .module = "mem", .reached_through = "`Float32.from_bits`" } } },
};

/// The prefix that marks a symbol as the runtime's.
pub const namespace = "linea_";

/// The signature the runtime gives `name`, or null where it gives none.
pub fn signatureOf(name: []const u8) ?*const Signature {
    for (&runtime_functions) |*signature| {
        if (std.mem.eql(u8, signature.symbol, name)) return signature;
    }
    return null;
}

test "a runtime function is found by its whole symbol" {
    const close = signatureOf("linea_close").?;
    try testing.expectEqual(Scalar.i64, close.result);
    try testing.expectEqual(@as(usize, 1), close.parameters.len);
    try testing.expectEqual(Provider.lowering, signatureOf("linea_raw_load8").?.provider);
    try testing.expect(signatureOf("linea_close_all") == null);
    try testing.expect(signatureOf("linea_trap") == null);
    // Each symbol appears once, and none is one the compiler owns.
    for (runtime_functions, 0..) |signature, i| {
        try testing.expect(std.mem.startsWith(u8, signature.symbol, namespace));
        try testing.expect(!holds(signature.symbol));
        for (runtime_functions[i + 1 ..]) |other| try testing.expect(!std.mem.eql(u8, signature.symbol, other.symbol));
        // The compiler's own symbols are refused by name, so no row of this
        // table is one of them.
        try testing.expect(signature.declared_by != .compiler);
        // Only the standard library's declaration of a symbol lowering
        // replaces is replaced. A symbol taking the address of typed bytes or
        // a callback, or starting a thread, is trusted with numbers only its
        // module's types keep.
        // A symbol taking or answering an allocation, a descriptor or the
        // address of bytes is trusted with a number a value must own.
        const confined = signature.provider == .lowering or signature.starts_thread or signature.answers != .none or
            for (signature.parameters) |parameter| {
                if (parameter.address or parameter.callback != null or parameter.held != .none) break true;
            } else false;
        if (confined) try testing.expect(signature.declared_by.home() != null);
        // A runtime the program calls reads, writes or frees bytes only at
        // the number in an `Address`, so every parameter naming them is
        // typed. Only a call lowering replaces checks a plain number.
        if (signature.provider == .runtime) for (signature.parameters) |parameter| {
            if (parameter.held == .bytes or parameter.held == .allocation) try testing.expect(parameter.address);
        };
        if (signature.declared_by.home() != null) try testing.expect(signature.declared_by.library.reached_through.len > 0);
    }
    for (owned_functions) |signature| try testing.expect(signature.declared_by == .compiler);
}

test "an allocation, a descriptor and an address of bytes are confined to the module that owns them" {
    for ([_][]const u8{ "linea_alloc", "linea_free", "linea_close", "linea_read_some", "linea_write_some", "linea_random_bytes", "linea_open_at", "linea_float64_parse" }) |name| {
        try testing.expectEqualStrings("mem", signatureOf(name).?.declared_by.home().?);
    }
    try testing.expectEqualStrings("fs", signatureOf("linea_set_mode").?.declared_by.home().?);
    try testing.expectEqualStrings("net", signatureOf("linea_net_accept").?.declared_by.home().?);
    try testing.expect(signatureOf("linea_clock_sleep").?.declared_by == .granted);
}
