# 188. The unit value is written as its type is, `()`

Status: Accepted — 2026-09-27. Supersedes the unit-expression clause of
[0140](0140-aggregate-constants-retain-checked-construction-plans.md).

## Context

The unit type is written `()`. Its one value had no spelling of its own: a
program wrote an empty block, `{}`, wherever it needed the value, so a call
that can fail and reports nothing on success answered `.Ok({})`, and a unit
constant was `let nothing: () = {}`. `()` in value position was
[S-Expr]. ADR 0140 admitted "the unit expression `{}`" to the constant domain,
so the folder treated one shape of block, the empty one, as a constant while
every other block was excluded.

The type and its value were therefore spelled differently, and the value's
spelling was a block, which also means "run these statements". A reader who
knows Rust, Swift or any ML reads `()` as the value and `{}` as a scope or an
empty body, and the standard library spelled `.Ok({})` hundreds of times.

## Decision

**`()` is the unit value.** It is an expression of type Unit wherever a value
may stand: an argument, an initializer, a returned value, a block's tail, an
arm's value, and a constant expression. The parser builds a `unit_literal`
node for `(` followed by `)` with nothing but whitespace or a comment
between them, and every pass treats it as a
literal: the checker gives it type Unit, the constant folder folds it to the
unit constant, and lowering produces the unit value.

**`{}` is an empty block, and nothing else.** An empty block may stand
wherever a block may: an empty function body, a `match` arm that does
nothing, an `if` arm. It computes nothing, so its value is `()`, as in Rust.
It stays accepted in value position, since a block is an expression, and
`.Ok({})` still compiles; the formatter prints it as written.

**An empty block is not a constant expression.** The constant list names
`()`, and a block is run rather than worked out, so `let nothing: () = {}` is
[T-Const]. The folder no longer special-cases a block by its emptiness.

## Consequences

- The type and the value share one spelling, `Result[(), E]` and `.Ok(())`.
- The standard library, the examples and the guides write `()` wherever they
  mean the value, and keep `{}` for empty bodies and arms that do nothing.
- A block used as a constant's initializer is refused whatever it holds,
  which removes the one case where the constant folder inspected a block.
- The tree-sitter grammar gains a unit expression. The formatter prints the
  unit value as `()`, including one written with space between its
  parentheses, `( )`.
- `()` is not a pattern. The unit type has one value, so matching it tests
  nothing. In a `match` arm `_` matches it, since a bare name there is a
  variant; a variant's payload binder, as in `Dot(u)`, binds it.

## Alternatives considered

**Keep `{}` as the unit value.** Rejected: the type and the value are spelled
differently, and a reader coming from Rust writes `()` and gets [S-Expr].

**Accept both `()` and `{}` as the unit value.** Rejected: two spellings for
one value, and the constant list would name a block shape beside a literal.
An empty block still has the value `()` wherever a block is an expression,
because that is what a block's value is, not a second spelling of the unit
value.
