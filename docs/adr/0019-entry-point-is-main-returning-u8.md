# 19. A program is `fn main() -> u8`

Status: Superseded by [0024](0024-a-program-is-a-list-of-declarations.md) — 2026-07-26

## Context

Stage 1's program was a sequence of bindings followed by a trailing expression,
and `linea run` printed its value. That shape has no meaning once the compiler
produces an executable: an operating system starts a process at an entry point
and observes an exit status, neither of which a bare expression describes.

The exit status is the constraint. POSIX accepts `exit(int)` but a parent
observes only the low eight bits, so `exit(300)` is seen as 44. Whatever a
program returns, the observable result is a byte.

## Decision

A program declares its entry point:

```linea
fn main() -> u8 {
    let x = 4;
    x * 2 + 1
}
```

The block's trailing expression is the return value, and it becomes the process
exit status directly. `u8` is the honest type for a thing an operating system
will observe as a byte, and it is what Zig's entry point returns.

**The return type constrains the body.** `u8` is pushed inward, so the
arithmetic inside `main` is `u8` arithmetic and its literals are `u8` literals.
`fn main() -> u8 { 200 + 100 }` reports an overflow of `u8` rather than
computing 300 in a wider type and rejecting it at the boundary — the failure is
reported where it happens rather than where it is noticed.

A file with no `main` is an error, and the bare-expression program is gone.

Stage 2a introduces exactly this declaration and nothing more: no parameters,
no other functions, no calls. The body is a block, which is already an
expression ([ADR 0006](0006-typed-per-category-ast.md)), so the grammar gains
`fn`, `->`, a type name and braces. General functions arrive when they can be
designed against calls, parameters and generics rather than against one
declaration.

A trap is distinguishable from any of this because it aborts rather than exits
([ADR 0017](0017-failure-is-a-trap-or-a-value.md)). Every value in `0..255` is
a legitimate result, so no exit status could have been reserved for failure.

## Consequences

- Every Stage 1 test case is invalidated and the corpus migrates in one
  change. The token and node numbering shifts, so every expectation
  regenerates — a large diff that alters no behaviour, reviewed once.
- The value's type is `u8`, so a program cannot return an arbitrary integer.
  This is a real restriction and the correct one: the operating system cannot
  observe anything wider.
- Pushing the return type inward requires bidirectional checking, which is
  what makes a literal's type depend on context
  ([ADR 0018](0018-the-integer-model.md)). The entry point is therefore what
  forces inference into the compiler.
- `fn main` as a special form is a special case in the parser and the checker
  until general functions replace it. It is expected to be deleted rather than
  grown.
- Returning a `Result` from `main`, as Rust and Zig both allow, is not
  available. That becomes possible once `Result` exists, and it is worth
  revisiting then.

## Alternatives considered

**The trailing expression becomes the exit status, with no `main`.** Keeps the
Stage 1 program shape and the corpus intact. Rejected: a program with no
declared entry point cannot later grow one without the same migration, and the
shape has no meaning in a language with functions.

**Print the value and always exit zero.** Makes a compiled program's observable
behaviour identical to `linea run`, which would make the two directly
comparable for testing. Rejected: it requires a formatter and a write in every
binary to observe a value the exit status can carry, and it makes every program
a program that prints.

**`fn main() -> i64`, truncated to a byte on exit.** Removes the `u8`
restriction and lets `main` return any integer. Rejected: the truncation is
either silent, which contradicts a language that reports everything, or
diagnosed, which is the `u8` restriction with extra steps.
