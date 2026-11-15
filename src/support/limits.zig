//! The numeric limits the language states, each with the rule that reports a
//! program past it.
//!
//! Every pass that enforces a limit reads it here, and the program generator
//! reads the same table to write a program at each limit and one past it. A
//! limit added here is therefore generated without a second edit: the
//! generator switches over `Limit` exhaustively, so it does not compile until
//! it says how the new limit is reached or why it cannot be yet.

const std = @import("std");

pub const Limit = enum {
    /// The levels an expression, a pattern or a written type nests.
    tree_height,
    /// The components of a tuple literal, type or pattern.
    tuple_components,
    /// The parameters of a callable type that heads an implementation.
    callable_head_parameters,
    /// The settled references and aliases a chain of declared answers passes
    /// through.
    answer_links,
    /// The matrix cells one `match`'s coverage check builds.
    coverage_cells,
    /// The elements of an array type.
    array_length,
    /// The bytes one type is wide.
    type_bytes,

    /// The greatest count the language accepts.
    pub fn most(self: Limit) u64 {
        return switch (self) {
            .tree_height => 1000,
            .tuple_components => 8,
            .callable_head_parameters => 60,
            .answer_links => 1000,
            .coverage_cells => 1 << 20,
            .array_length => std.math.maxInt(u32),
            .type_bytes => std.math.maxInt(u32),
        };
    }

    /// The name of the rule a program past the limit is refused under, as
    /// `docs/linea-semantics.md` writes it.
    pub fn rule(self: Limit) []const u8 {
        return switch (self) {
            .tree_height => "S-Nesting",
            .tuple_components => "S-Tuple",
            .callable_head_parameters => "T-Impl",
            .answer_links => "T-AnswerDepth",
            .coverage_cells => "T-CoverLimit",
            .array_length => "T-ArraySize",
            .type_bytes => "L-Size",
        };
    }
};
