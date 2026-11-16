//! The counts the language bounds, each with the rule that reports a program
//! past it.
//!
//! A limit is listed here when a rule of the language states it as a number
//! and a diagnostic under that rule refuses the program that passes it. The
//! pass that enforces a limit reads it here, and the program generator reads
//! the same table to write a program at each limit and one past it. The
//! generator switches over `Limit` exhaustively, so a limit added here does
//! not compile into it until it says how the limit is reached or why it
//! cannot be yet.
//!
//! Two bounds the compiler holds are not listed, because neither is a rule
//! of the language. `source.max_bytes` is the largest source a position can
//! address, and a file past it is unreadable and reported with no rule name.
//! The bounds of the integer and float types are the types' own values and
//! not counts of anything a program writes.

const std = @import("std");

pub const Limit = enum {
    /// The levels an expression, a pattern or a written type nests.
    tree_height,
    /// The components of a tuple literal, type or pattern.
    tuple_components,
    /// The settled references and aliases a chain of declared answers passes
    /// through.
    answer_links,
    /// The matrix cells one `match`'s coverage check builds.
    coverage_cells,
    /// The elements of an array type.
    array_length,
    /// The bytes one type is wide.
    type_bytes,
    /// The `#` that open a raw string literal.
    raw_literal_hashes,
    /// The interpolations open at once inside one string literal.
    interpolation_depth,
    /// The width or the precision a format spec writes.
    format_count,
    /// The bytes of a file `embed` or `embed_bytes` names.
    embedded_bytes,

    /// The greatest count the language accepts.
    pub fn most(self: Limit) u64 {
        return switch (self) {
            .tree_height => 1000,
            .tuple_components => 8,
            .answer_links => 1000,
            .coverage_cells => 1 << 20,
            .array_length => std.math.maxInt(u32),
            .type_bytes => std.math.maxInt(u32),
            .raw_literal_hashes => 8,
            .interpolation_depth => 16,
            .format_count => std.math.maxInt(u16),
            .embedded_bytes => 16 << 20,
        };
    }

    /// The smallest count the language accepts, where it states one.
    pub fn fewest(self: Limit) ?u64 {
        return switch (self) {
            .tuple_components => 2,
            else => null,
        };
    }

    /// The name of the rule a program past the limit is refused under, as
    /// `docs/linea-semantics.md` writes it.
    pub fn rule(self: Limit) []const u8 {
        return switch (self) {
            .tree_height => "S-Nesting",
            .tuple_components => "S-Tuple",
            .answer_links => "T-AnswerDepth",
            .coverage_cells => "T-CoverLimit",
            .array_length => "T-ArraySize",
            .type_bytes => "L-Size",
            .raw_literal_hashes, .interpolation_depth => "S-String",
            .format_count => "S-Format",
            .embedded_bytes => "M-Embed",
        };
    }
};
