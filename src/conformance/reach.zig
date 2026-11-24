//! Which rules the generated programs reach.
//!
//! Every generator part that writes a refused program names the rule that
//! must refuse it, and is held to that rule where it runs: a mutation by the
//! walk that applies it, a hostile shape by the check of what it states. A
//! rule no part names is compared only against the cases written by hand.
//! This file lists those rules, and the list is exact: a rule the compiler
//! can emit is named by a part or listed here, and never both.

const std = @import("std");
const testing = std.testing;

const Code = @import("../diagnostics/diagnostic.zig").Code;
const Mutation = @import("mutate.zig").Mutation;
const hostile = @import("hostile.zig");

/// Whether some generator part writes a program `rule` must refuse, and the
/// program's check is compared against that rule.
pub fn generated(rule: Code) bool {
    for (std.enums.values(Mutation)) |mutation| {
        if (std.mem.eql(u8, mutation.rule(), rule.ruleName())) return true;
    }
    return hostile.reaches(rule);
}

/// Rules that share one reason no generated program reaches them yet.
pub const NotYet = struct {
    why: []const u8,
    rules: []const Code,
};

pub const not_yet_generated = [_]NotYet{
    .{
        .why = "A syntax rule is reached by a form written almost right. Every generator part writes " ++
            "complete forms, and no mutation removes or swaps a token.",
        .rules = &.{
            .s_test,
            .s_escape,
            .s_encoding,
            .s_embed,
            .s_char,
            .s_float,
            .s_expr,
            .s_name,
            .s_type,
            .s_unit_result,
            .s_bracket,
            .s_equals,
            .s_destructure,
            .s_separator,
            .s_continuation,
            .s_paren,
            .s_brace,
            .s_base_last,
            .s_chain,
            .s_break,
            .s_params,
            .s_mutation,
            .s_enum,
            .s_struct,
            .s_field,
            .s_match,
            .s_for,
            .s_let_else,
            .s_range,
            .s_args,
            .s_default,
            .s_lambda,
            .s_defer,
            .s_defer_let,
        },
    },
    .{
        .why = "A name rule is reached by a declaration or a use the resolver refuses. The mutations that " ++
            "rename a use reach [N-Variant] alone, and no part declares a name twice, shadows one or " ++
            "uses one as another kind.",
        .rules = &.{
            .n_undefined,
            .n_immutable,
            .n_duplicate,
            .n_not_callable,
            .n_not_a_value,
            .n_aliased,
            .n_ambiguous,
            .n_shadowed,
            .n_case,
            .n_not_a_type,
            .n_type_alias,
        },
    },
    .{
        .why = "A module rule is reached across files. A generated program is one file beside the library.",
        .rules = &.{
            .m_impl,
            .m_import,
            .m_dependency,
            .m_embed,
            .m_embed_text,
            .m_unused,
            .m_vis,
            .m_entry,
            .m_standard,
            .m_opaque,
        },
    },
    .{
        .why = "These ownership rules are reached by a value used after it was lent, captured, deferred or " ++
            "walked. The disposal mutations move and drop linear values only.",
        .rules = &.{
            .o_capture,
            .o_reinit,
            .o_defer_dead,
            .o_escapes,
            .o_cross,
            .o_borrow,
            .o_temporary,
            .o_loop,
            .o_scalar_copy,
            .o_linear_walk,
            .o_linear_tail,
            .o_lent,
            .o_copy_read,
            .o_copy_dead,
        },
    },
    .{
        .why = "A type rule is reached by one planted mistake in an otherwise well-typed program. The " ++
            "mutations plant the mistakes their own rules name, and none plants these.",
        .rules = &.{
            .t_literal,
            .t_convert,
            .t_overflow,
            .t_infer,
            .t_call,
            .t_array_length,
            .t_length_parameter,
            .t_index,
            .t_poly_rec,
            .t_bound,
            .t_format,
            .t_where,
            .t_dual,
            .t_reflection,
            .t_divide_by_zero,
            .t_condition,
            .t_for,
            .t_lend,
            .t_borrow_contract,
            .t_arms,
            .t_arity,
            .t_unknown_parameter,
            .t_duplicate_parameter,
            .t_missing_argument,
            .t_default,
            .t_argument_default,
            .t_defaulted_allocator,
            .t_unreachable,
            .t_refutable,
            .t_infinite_layout,
            .t_missing_field,
            .t_duplicate_field,
            .t_unused_base,
            .t_unknown_operation,
            .t_discard,
            .t_discard_failure,
            .t_const,
            .t_defer_let,
            .t_try,
            .t_try_answer,
            .t_let_else,
            .t_phantom,
            .t_projection,
            .t_range_place,
        },
    },
    .{
        .why = "A rule about foreign code is reached by an `extern` or `export` declaration, and no " ++
            "generated program declares one.",
        .rules = &.{
            .s_export,
            .s_extern,
            .m_extern,
            .m_foreign,
            .m_export,
            .t_extern,
            .t_extern_agreement,
            .t_extern_callback,
            .t_extern_handle,
            .t_extern_runtime,
            .t_extern_prototype,
            .t_thread_start,
            .t_raw_address,
            .t_export,
        },
    },
    .{
        .why = "The limit table lists the cells a coverage check builds, and no generator part writes a " ++
            "`match` that reaches them.",
        .rules = &.{
            .t_cover_limit,
        },
    },
};

fn listed(rule: Code) u32 {
    var times: u32 = 0;
    for (not_yet_generated) |group| {
        for (group.rules) |r| times += @intFromBool(r == rule);
    }
    return times;
}

test "every rule the compiler can emit is generated or listed as not yet generated" {
    var wrong: u32 = 0;
    for (std.enums.values(Code)) |rule| {
        const times = listed(rule);
        if (generated(rule) and times != 0) {
            std.debug.print("[{s}] is generated, so its entry in `not_yet_generated` is removed\n", .{rule.ruleName()});
            wrong += 1;
        } else if (!generated(rule) and times != 1) {
            std.debug.print("[{s}] is emitted, no generator part names it, and `not_yet_generated` lists it {d} time(s)\n", .{ rule.ruleName(), times });
            wrong += 1;
        }
    }
    try testing.expectEqual(@as(u32, 0), wrong);
}
