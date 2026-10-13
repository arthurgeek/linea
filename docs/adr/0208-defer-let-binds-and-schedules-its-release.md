# 208. `defer let` binds a value and schedules its release

Status: Accepted — 2026-10-06; extends
[0063](0063-disposal-is-scheduled-never-inserted.md) and narrows the
no-scheduling sentence of
[0104](0104-release-is-optional-and-never-scheduled.md) to "never without a
written `defer`".

## Context

In `examples/`, 96 of the 97 `defer` lines are `defer x.release()`, and 78 of
those sit directly under the `let` or `var` that binds `x`; in `std/` it is
778 of 796 and 743. The line is identical each time, forgetting it is already
[O-Leak], and so it records no decision: it is the repeated ceremony that
carries an ownership proof the compiler checks anyway.

[0063](0063-disposal-is-scheduled-never-inserted.md) admitted `defer` because
the programmer writes the expression, and refused a destructor and a
block-scoped `with`. [0097](0097-release-is-named-never-scheduled.md) stated
the test, authorship of the call site, and 0104 (which supersedes 0097)
restates it as "the compiler never selects, inserts, or schedules a release
invocation". 0063 was decided before any container existed. It weighed a
block form and never a binding-level one.

## Decision

**`defer let x = e` (and `defer var x = e`) is the binding `let x = e`
followed by the written statement `defer x.release()`, for a type that
implements `Release`.** The form is
admitted for a single-name binding whose type implements
`std.release.Release`; a type that does not, a pattern, and a `let read` are
refused with a message that points at the explicit `defer`.

The compiler still never invents the expression. The `defer` keyword is
written, the binding it attaches to is written, and the scheduled call is the
one `defer x.release()` would be: this narrows 0104's "never selects, inserts,
or schedules" to "never without a written `defer`". A destructor, an automatic
release at scope exit, and a block form stay refused.

## Consequences

- No ownership change. Placement at every exit, reverse order, move-cancels-
  defer and [O-DeferDead] apply to the desugared pair as to the written one.
- A type with no single context-free ending (a transaction with commit and
  rollback) is refused, and the refusal's help is where the language teaches
  "choose its ending". The compiler never picks one for it.
- The 0104 sentence about scheduling becomes conditional on the written
  keyword. A reader who relied on "no `release` call without a `release`
  token in the source" now has to know `defer let` is one.
- Parser, formatter, tree-sitter and the semantics document each gain one
  small construct.
- Examples and std lose one line at roughly 78 and 743 sites.

## Alternatives considered

**A block `with x = e { ... }`.** Rejected by 0063 and still rejected: it forces
the value's lifetime to be a block, and the common case is a value created
mid-function and owned to its end. It would also push the whole body under it.

**The status quo.** Honest, and the position until now. It keeps the line
visible at the cost of 88 identical copies in 89, with the compiler checking
the proof and the human writing the receipt. The evidence is what changed:
the 88-of-89 figure was unknowable in August.

**A destructor or automatic release at scope exit.** Refused for the reasons
of 0034 and 0063 and a further one from
[0184](0184-a-failure-holding-an-owned-value-settles-to-its-reason.md): the
automatic call runs on error paths, where a close error is dropped by code
nobody wrote, and it divides linear types into those with a context-free
ending and those without.

**A scoped helper such as `mem.with_arena(parent, size, |arena| ...)`.** Closures
holding an `inout` place exist
([0193](0193-a-closure-may-hold-a-place-lent-inout.md)), so it is expressible
for arenas. It serves one type at a time and is a library operation each
resource would have to grow; it is not rejected, it does not substitute.

## Built as

The parser reads `defer let x = e` as two statements, the binding and a
`defer_release` that schedules `x.release()`, and every later pass reads the
pair as it reads the two statements a programmer could have written. The
checker finds `release` by the lookup a written `x.release()` is answered by,
restricted to `Release.release`. `defer var` ships with `defer let`. A type
without `Release` is [T-DeferLet]; a pattern and a `let read` are
[S-DeferLet].
