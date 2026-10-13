//! Inputs the fuzzer found, replayed by every run after it.
//!
//! CI retains failed fuzz artifacts for thirty days. Entries here remain
//! regression tests after those artifacts expire and seed later searches.
//!
//! An entry goes in with its fix, in the same commit, and stays afterwards. It
//! is a regression test, and it is also seed material -- a search starts from
//! these rather than from noise, so the next one begins where the last one
//! found something.
//!
//! To add one: save the bytes beside this file under the property they broke,
//! then name it below with a line saying what it broke. The comment is the
//! point; a filename cannot carry it.

/// `[S-Lossless]` — the token stream reconstructs its input byte for byte.
pub const lexer: []const []const u8 = &.{};

/// The parser is total: any input yields a complete tree.
pub const parser: []const []const u8 = &.{};

/// A diagnostic renders whatever span it is given, including a degenerate one.
pub const render: []const []const u8 = &.{};

/// A diff applied to the text it was computed from yields the other text.
pub const diff: []const []const u8 = &.{};

/// Formatting re-parses, preserves tokens and comments, and is idempotent.
pub const fmt: []const []const u8 = &.{};

/// A language server finishes a session whatever the messages in it are.
/// Smith decodes these choice streams into newline-delimited client messages.
pub const lsp: []const []const u8 = &.{
    // Malformed JSON is reported through the session's captured diagnostics.
    @embedFile("lsp/malformed-json-log.bin"),
};

/// A module lowered from a program the compiler accepted is one the verifier
/// accepts. The bytes here are a choice stream rather than source: they decide
/// what the generator writes.
pub const verify: []const []const u8 = &.{
    // A conditional arm naming a place, read by a call argument, was blitted as
    // a move and the place was read again afterwards.
    @embedFile("verify/join-arm-place-read-after.bin"),
};

/// A generated storage program is accepted, runs clean and computes its
/// model's total, and each of its mutants is refused or runs clean. The bytes
/// are a choice stream for `conformance/storage.zig`, replayed by every
/// soundness run as well as by the fuzz target.
pub const storage: []const []const u8 = &.{};
