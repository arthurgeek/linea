# 202. A line beginning with `(` is noted only as an empty call

Status: Accepted — 2026-10-02

Refines [0190](0190-a-variant-line-is-not-a-continuation.md) and
[0196](0196-a-selection-line-continues-the-line-above.md), which keep every
`(` among the tokens whose line [S-Continuation] notes, and
[0043](0043-a-separator-that-answers-a-note-is-kept.md), whose kept `;` is
the one before such a line and which rejected dropping the note.

## Context

[S-Continuation] notes a line opening with `-`, `(` or a `.` that could select
from the line above, where a newline ended the statement before it, because
each could have continued the expression above. For `(` the note exists for
the reader who wrote `foo` at the end of one line and `(bar)` at the start of
the next, meaning `foo(bar)`.

Tuples make `(` a high-frequency legitimate expression starter. The tail of a
function returning a tuple is `let hi = ...` followed by `(lo, hi)`, so the
note would follow every such function into its diagnostics, every golden that
records them and every excerpt in the guide. A note that fires on the
idiomatic program teaches its readers to stop reading notes.

A split call is two statements, and what refuses it is [T-Discard]: a
statement whose value is not Unit and that nothing uses. The split forms were
run against the compiler with the note in place:

- `let x = foo` then `(bar)`: `(bar)` is a discarded `UInt8`, refused.
- `foo` then `(bar)` as a tail, `foo` a function: the bare `foo` is a
  discarded function value, refused.
- `let x = foo` then `(bar)`, and `foo` then `(bar)`, both locals: refused
  the same way.
- `let _ = launch` then `()`, `launch` a function taking nothing: compiles
  with only the note. `let _` discards the function value deliberately,
  `()` is the unit value standing alone, which [T-Discard] does not refuse,
  and `launch` is never called. `let _status = launch` behaves the same, since
  a name beginning with `_` may go unused.
- `let x = make` then `(log())`, `log` returning Unit: compiles with only the
  note, for the same reason.

So [T-Discard] refuses a split only when the parenthesised half, or the bare
callee left above it, is a value that is not Unit. A zero-argument call split
before its `()` is the common shape that slips through.

ADR 0043 considered dropping the note and rejected it: "the day an expression
whose value is nothing can stand alone as a statement, both halves of a
misread newline are legal and the mistake compiles". That day has come, and
the last two probes are that mistake.

## Decision

**A line beginning with `(` is noted only when `)` follows directly.**
`Tag.opensAContinuation` answers true for `(` exactly when the next token is
`)`. The parser's `noteContinuation` notes such a line, saying it "begins with
`()`, which could have called the expression above", and the formatter, which
reads the same predicate, keeps a `;` written before it. A line opening with
`(` and anything else is not noted, and the formatter keeps no `;` before it.
A newline still ends a statement before any `(` line exactly as before; only
the note changes.

`-` and `.` are noted as before.

This differs from what 0043 rejected because the note is kept where the
hazard is common. A split before `()` leaves both halves legal, and it keeps
its note. A split before an argument that is not Unit is refused by
[T-Discard] as a hard error, so the note beside it added nothing. What is
given up is the note on a split before a parenthesised argument that is Unit
but not written `()`.

## Consequences

- A function returning a tuple ends with its tuple on its own line, with no
  note and no `;` after the line above. So does any tail opening with `(`,
  such as `(lo + half)`.
- `let x = foo` followed by `(bar)`, with `bar` not Unit, is two statements
  and an error at `(bar)`, with no note beside it. A reader who meant a call
  writes it on one line, or ends the line with the `(`.
- `let _ = launch` followed by `()` is noted, as before. It still compiles,
  and `launch` is not called.
- A split before a parenthesised Unit argument other than `()`, such as
  `let x = make` then `(log())`, compiles with no note and no error. It needs
  a callee whose parameter is Unit, an argument written as a Unit-valued
  expression in parentheses, and a binding above that is never used as the
  call's result: unused, `let _`, a `_` name, or used only as the function
  it is.
- A `;` written before a `(` line that is not `()` no longer answers a note,
  and `fmt` removes it.
- The cases that recorded the note on a `(` line no longer print it, and their
  `.stderr` goldens are deleted, since a golden recording nothing is refused.

## Alternatives considered

**(a) Note `()` only.** Chosen. It keeps the rule on token shape: one more
token of lookahead, read by the one predicate both the parser and the
formatter ask. No tuple, and no tail that produces a value, opens with `()`,
so it never fires on the idiomatic program. And it keeps the note for the
shape that is common and that nothing else catches, a zero-argument call.

**(b) Note a `(` line only when it is not a block's tail.** Tuples live in the
tail, and a `(` statement that is not the tail is either refused by
[T-Discard] or Unit, which is exactly the hazard, so this would also catch
`(log())`. It loses because the predicate would stop being token shape: the
parser notes the line before it knows whether the block ends after it, and
the formatter decides from the statement list. That is two places answering
whether a line is a tail, where today one predicate answers whether it is
noted. And the one shape it adds, a Unit argument that is not `()`, needs a
callee taking Unit, which is rare.

**Drop the note for every `(` line.** The first form of this decision. It
removed the note from `let _ = launch` followed by `()`, which then compiled
silently without calling `launch`: the case 0043 rejected dropping the note
for.

**Keep the note and teach `return (a, b)`.** The tail form is the natural one,
and every other tail in the language is written without `return`. A note on
every tuple-returning function teaches readers to ignore notes.

**Note only when the token before the break can be called.** A call ending in
`)` is the commonest tail before a line break and can be called again, so the
note would still fire on most tuple tails; and deciding what can be called is
a second place reasoning about callability, beside the type checker's.
