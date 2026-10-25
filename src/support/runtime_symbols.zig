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
/// Defined only by the checking runtime, so an archive answers whether it
/// checks storage.
pub const storage_checked = "linea_storage_checked";

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
    storage_checked,
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
/// spells it, so only the symbols the compiler owns use it.
pub const Scalar = enum { u8, i32, u32, i64, u64, f32, f64, ptr, unit };

/// How a runtime function takes a parameter: by value, or through a pointer
/// the callee writes, which a Linea declaration spells `inout`.
pub const Passing = enum { read, inout };

pub const Parameter = struct { scalar: Scalar, passing: Passing = .read };

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

/// One function in the `linea_` namespace and the signature it has.
pub const Signature = struct {
    symbol: []const u8,
    parameters: []const Parameter,
    result: Scalar,
    provider: Provider = .runtime,
    /// For a symbol lowering replaces, the standard library operation a
    /// program calls instead, which the refusal of its own declaration names.
    reached_through: []const u8 = "",
    /// Control never returns from a call to it.
    noreturn: bool = false,
};

fn p(scalar: Scalar) Parameter {
    return .{ .scalar = scalar };
}

const written: Parameter = .{ .scalar = .u64, .passing = .inout };

/// What C's startup calls: the wrapper the emitted module defines around the
/// program's entry. The runtime's `linea_set_args` receives what it is passed.
pub const entry_signature: Signature = .{
    .symbol = entry,
    .parameters = &.{ p(.i32), p(.ptr) },
    .result = .i32,
    .provider = .generated,
};
/// A trap: the kind's number, then the file name and the line and column.
pub const trap_signature: Signature = .{
    .symbol = trap,
    .parameters = &.{ p(.i32), p(.ptr), p(.i32), p(.i32) },
    .result = .unit,
    .noreturn = true,
};
/// A panic: the message's address and length, then the file name and the line
/// and column.
pub const panic_signature: Signature = .{
    .symbol = panic,
    .parameters = &.{ p(.u64), p(.u64), p(.ptr), p(.i32), p(.i32) },
    .result = .unit,
    .noreturn = true,
};
/// The program's argument count and vector, handed over before it runs.
pub const set_args_signature: Signature = .{
    .symbol = set_args,
    .parameters = &.{ p(.i32), p(.ptr) },
    .result = .unit,
};
pub const storage_extent_signature: Signature = .{
    .symbol = storage_extent,
    .parameters = &.{ p(.u64), p(.u64) },
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
} ++ math_functions;

test "every function the compiler owns is a name the runtime refuses" {
    for (owned_functions) |signature| try testing.expect(holds(signature.symbol));
}

/// Every `linea_` function an `extern` may name, with its signature. The
/// namespace is the runtime's: a declaration of one of these is held to the
/// signature here in whatever root declares it, the standard library's
/// included, and a `linea_` symbol this table does not hold is refused
/// ([T-ExternRuntime]). A test in `build/` reads the runtime's C and holds this
/// table to it, so the two cannot drift.
///
/// The symbols `holds` names -- the entry point, traps, argument setup and the
/// float-math operations -- are owned by the compiler and refused by name
/// ([T-Extern]), so they are not repeated here.
pub const runtime_functions = [_]Signature{
    .{ .symbol = "linea_alloc", .parameters = &.{ p(.u64), p(.u64) }, .result = .u64 },
    .{ .symbol = "linea_free", .parameters = &.{ p(.u64), p(.u64), p(.u64) }, .result = .unit },
    .{ .symbol = "linea_arg_count", .parameters = &.{}, .result = .u64 },
    .{ .symbol = "linea_arg_at", .parameters = &.{p(.u64)}, .result = .u64 },
    .{ .symbol = "linea_arg_len", .parameters = &.{p(.u64)}, .result = .u64 },
    .{ .symbol = "linea_env_count", .parameters = &.{}, .result = .u64 },
    .{ .symbol = "linea_env_at", .parameters = &.{p(.u64)}, .result = .u64 },
    .{ .symbol = "linea_env_len", .parameters = &.{p(.u64)}, .result = .u64 },
    .{ .symbol = "linea_io_category", .parameters = &.{p(.i32)}, .result = .u8 },
    .{ .symbol = "linea_errno", .parameters = &.{}, .result = .i32 },
    .{ .symbol = "linea_read_some", .parameters = &.{ p(.i32), p(.u64), p(.u64) }, .result = .i64 },
    .{ .symbol = "linea_write_some", .parameters = &.{ p(.i32), p(.u64), p(.u64) }, .result = .i64 },
    .{ .symbol = "linea_close", .parameters = &.{p(.i32)}, .result = .i64 },
    .{ .symbol = "linea_random_bytes", .parameters = &.{ p(.u64), p(.u64) }, .result = .i64 },
    .{ .symbol = "linea_open_parent", .parameters = &.{ p(.u64), p(.u64) }, .result = .i64 },
    .{ .symbol = "linea_open_at", .parameters = &.{ p(.i32), p(.u64), p(.u64), p(.u8), p(.u64) }, .result = .i64 },
    .{ .symbol = "linea_mode_at", .parameters = &.{ p(.i32), p(.u64), p(.u64) }, .result = .i64 },
    .{ .symbol = "linea_set_mode", .parameters = &.{ p(.i32), p(.u64) }, .result = .i64 },
    .{ .symbol = "linea_publish_at", .parameters = &.{ p(.i32), p(.u64), p(.u64), p(.u64), p(.u64), p(.u8) }, .result = .i64 },
    .{ .symbol = "linea_unlink_at", .parameters = &.{ p(.i32), p(.u64), p(.u64) }, .result = .i64 },
    .{ .symbol = "linea_net_listen", .parameters = &.{ p(.u64), p(.u64) }, .result = .i64 },
    .{ .symbol = "linea_net_accept", .parameters = &.{p(.i32)}, .result = .i64 },
    .{ .symbol = "linea_net_connect", .parameters = &.{p(.u64)}, .result = .i64 },
    .{ .symbol = "linea_net_local_address", .parameters = &.{p(.i32)}, .result = .i64 },
    .{ .symbol = "linea_net_peer_address", .parameters = &.{p(.i32)}, .result = .i64 },
    .{ .symbol = "linea_net_set_timeouts", .parameters = &.{ p(.i32), p(.u64), p(.u64) }, .result = .i64 },
    .{ .symbol = "linea_net_shutdown_write", .parameters = &.{p(.i32)}, .result = .i64 },
    .{ .symbol = "linea_net_reset", .parameters = &.{p(.i32)}, .result = .i64 },
    .{ .symbol = "linea_clock_read", .parameters = &.{ p(.u8), .{ .scalar = .i64, .passing = .inout }, written }, .result = .i64 },
    .{ .symbol = "linea_clock_sleep", .parameters = &.{p(.u64)}, .result = .i64 },
    .{ .symbol = "linea_float64_parse", .parameters = &.{ p(.u64), p(.u64), written, written }, .result = .u64 },
    .{ .symbol = "linea_float64_debug", .parameters = &.{ p(.u64), written, written, written, written }, .result = .u64 },
    .{ .symbol = "linea_float64_shortest", .parameters = &.{ p(.u64), .{ .scalar = .i64, .passing = .inout } }, .result = .u64 },
    .{ .symbol = "linea_float32_parse", .parameters = &.{ p(.u64), p(.u64), written, written }, .result = .u64 },
    .{ .symbol = "linea_float32_debug", .parameters = &.{ p(.u64), written, written, written, written }, .result = .u64 },
    .{ .symbol = "linea_float32_shortest", .parameters = &.{ p(.u64), .{ .scalar = .i64, .passing = .inout } }, .result = .u64 },
    .{ .symbol = "linea_raw_load", .parameters = &.{ p(.u64), p(.u64), p(.u64) }, .result = .u64, .provider = .lowering, .reached_through = "the standard library's checked storage operations" },
    .{ .symbol = "linea_raw_load8", .parameters = &.{ p(.u64), p(.u64), p(.u64) }, .result = .u8, .provider = .lowering, .reached_through = "the standard library's checked storage operations" },
    .{ .symbol = "linea_raw_store", .parameters = &.{ p(.u64), p(.u64), p(.u64), p(.u64) }, .result = .unit, .provider = .lowering, .reached_through = "the standard library's checked storage operations" },
    .{ .symbol = "linea_raw_store8", .parameters = &.{ p(.u64), p(.u64), p(.u64), p(.u8) }, .result = .unit, .provider = .lowering, .reached_through = "the standard library's checked storage operations" },
    // A float's IEEE 754 bits as the unsigned integer of its width, and back.
    // Lowering replaces each with a bit-for-bit reinterpretation.
    .{ .symbol = "linea_float64_to_bits", .parameters = &.{p(.f64)}, .result = .u64, .provider = .lowering, .reached_through = "`Float64.to_bits`" },
    .{ .symbol = "linea_float64_from_bits", .parameters = &.{p(.u64)}, .result = .f64, .provider = .lowering, .reached_through = "`Float64.from_bits`" },
    .{ .symbol = "linea_float32_to_bits", .parameters = &.{p(.f32)}, .result = .u32, .provider = .lowering, .reached_through = "`Float32.to_bits`" },
    .{ .symbol = "linea_float32_from_bits", .parameters = &.{p(.u32)}, .result = .f32, .provider = .lowering, .reached_through = "`Float32.from_bits`" },
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
        // A symbol lowering replaces names the operation to call instead, and
        // only such a symbol has one.
        try testing.expectEqual(signature.provider == .lowering, signature.reached_through.len > 0);
    }
}
