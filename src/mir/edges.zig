const Inst = @import("mir.zig").Inst;

/// A corpus case that produces each terminator. Conformance lowers the named
/// case and checks that the terminator is present.
///
/// Exhaustive over every tag, so adding a terminator requires a witness before
/// the compiler builds.
pub fn witnessOf(tag: Inst.Tag) []const u8 {
    return switch (tag) {
        .ret => "tests/codegen/zero.lin",

        .jump => "tests/control/if_yields_a_value.lin",

        .branch => "tests/control/if_yields_a_value.lin",

        .trap => "tests/codegen/a_direct_never_call_is_a_terminator.lin",

        .call_noreturn => "tests/codegen/a_direct_never_call_is_a_terminator.lin",

        .call_indirect_noreturn => "tests/codegen/an_indirect_never_call_is_a_terminator.lin",

        // Not terminators. Listed rather than caught by `else`, so a tag added
        // anywhere has to be classified here before the build succeeds.
        .constant,
        .bytes_addr,
        .static_addr,
        .address_bits,
        .load,
        .store,
        .add,
        .sub,
        .mul,
        .div,
        .rem,
        .neg,
        .cmp_eq,
        .cmp_ne,
        .cmp_lt,
        .cmp_le,
        .cmp_gt,
        .cmp_ge,
        .check,
        .call,
        .function_addr,
        .foreign_function_addr,
        .call_indirect,
        .addr_of,
        .borrow,
        .observe,
        .load_indirect,
        .store_indirect,
        .load_raw,
        .store_raw,
        .storage_addr,
        .field_addr,
        .copy_value,
        .move_value,
        .int_to_float,
        .float_to_int,
        .float_math,
        => unreachable,
    };
}
