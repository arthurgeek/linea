# 63. Disposal is scheduled, never inserted

Status: Accepted — 2026-08-02; extends
[0034](0034-ownership-is-positions-and-a-graph.md), which it does **not**
supersede — the disposal is one the programmer wrote. Extended by
[0208](0208-defer-let-binds-and-schedules-its-release.md) and by
[0104](0104-release-is-optional-and-never-scheduled.md), which supersedes
[0097](0097-release-is-named-never-scheduled.md). Proposed
[0103](0103-linear-constrains-consumption-release-grants-one-way.md) would
extend 0104 with deferred container decisions without changing scheduling.

## Context

[0034](0034-ownership-is-positions-and-a-graph.md) made Linea's types linear
rather than affine: a value is consumed exactly once, explicitly, on every path,
and there is no implicit drop. That decision was taken against the ergonomic
cost knowingly, and R2 is where the cost arrives — a heap buffer must be freed
on every path out of a function, including the paths a `?` or a `return` takes,
and writing the free at each of them is both tedious and the exact thing a
reader stops verifying.

The ergonomic answer every affine language reaches for is a destructor. That is
the option 0034 rejected, and this record does not reopen it.

## Decision

**`defer e` schedules an expression the programmer wrote to run at scope exit.
The compiler never invents the expression, and never inserts one where none was
written.**

```linea
fn use() -> UInt8 {
    let b = alloc(16)
    defer free(b)
    b.len()
}
```

`free(b)` is written. What the compiler does is decide *where* it runs — at
every exit from the enclosing scope, in reverse order of scheduling — and
**verify** that the schedule discharges what the scope owes.

### Why this is not implicit Drop

A destructor and a `defer` differ on the question that matters: **who chooses
the expression.**

| | Implicit Drop | `defer` |
| --- | --- | --- |
| the disposal expression | the compiler, from the type | the programmer, in the source |
| where it is written | in an `impl Drop`, once per type | at the site, per value |
| what a reader greps for | nothing at the use site | the word `free` |
| whether it runs | always, on every path | on the paths the value is still owned |
| a value moved away | the drop is suppressed at run time | the schedule is cancelled at compile time |

The last row is the sharpest. Rust suppresses a drop by keeping a **runtime drop
flag** — a hidden boolean per conditionally-moved value, tested at scope exit.
Linea needs none, because the ownership pass already computes per-path
init/moved state for every binding. **The state the drop flag would carry at run
time is a state the ownership graph already carries at compile time.**

### How it is checked

A `defer consume(x)` is an ordinary consuming position, placed at each exit edge
of its scope. The ownership walk already visits those edges — `dies` operations
mark them, and `[O-Leak]` is asked there. So:

- On a path where `x` is still owned at the exit, the deferred consume runs and
  discharges it.
- On a path where `x` was moved away, **the schedule is cancelled**: the walk
  sees `x` as `moved`, a deferred consume of it would be `[O-Move]`, and the
  cancellation is what stops that. Move-cancels-defer is not a special case; it
  is the lattice already saying the value is gone.
- On a path where a `defer` was never reached — control left before the
  statement — nothing is scheduled, and the value it would have disposed of is
  either still owed, which is `[O-Leak]`, or was never created.

**Nothing new is decided at run time.** That is the whole claim, and it is what
makes `defer` compatible with 0034 rather than a retreat from it.

### The ownership pass gains a second output, and it is not an implementation detail

Until now the ownership pass produced **diagnostics** and nothing else. It now
also produces the **schedule-cancellation relation**: which placements of a
schedule do not run, as pairs of *(the `defer`'s expression, the exit that
placed it)*. Lowering reads it and emits every placement not in it.

That is deliberate and it is the right home — the relation is what the lattice
already computes, and the alternative is lowering deriving it a second time from
information it does not have. But it changes what the pass *is*. Anyone
simplifying ownership on the belief that its only product is messages will
delete something lowering depends on, and the failure is a program that frees
twice rather than a build that breaks.

A relation rather than a set of expressions, because one schedule fires at one
exit and not another: neither half of the pair identifies a placement alone.

## Consequences

**`[O-Leak]` gets much rarer, and stays exactly as strict.** A program that
forgets disposal is still refused; a program that writes it once at the top is
now accepted where it previously had to write it at every exit.

**A deferred expression is checked where it is scheduled and again where it
runs.** It is one expression appearing at several exits, which means a
diagnostic about it can point at several places. The message names the `defer`
and the exit, the way `[O-Uncommitted]` names a transfer and the jump that
crossed it.

**There is no `errdefer`, and its absence is the clearest evidence for this
record.** See below.

**Order is reverse of scheduling**, because a later `defer` may depend on what
an earlier one holds. This is the only ordering that composes.

**A `defer` in a loop schedules per iteration.** Its scope is the body, so it
runs at the end of each iteration, not at the end of the loop. The alternative —
accumulating schedules — needs a runtime list, which is the drop-flag machinery
under another name.

## Alternatives considered

**A `Drop` trait.** The ergonomic winner, and what 0034 rejected. Nothing has
changed about why: a disposal a reader cannot see at the use site is a disposal
they stop reasoning about, and the ordering of implicit drops becomes a language
rule that every later feature has to respect. Not reopened.

**Nothing — write the disposal at every exit.** The status quo, and what R1
leaves in place. Rejected at R2 because a heap buffer in a function with three
`?`s needs four frees, and the fourth is the one nobody writes. The suite would
catch it, which is the point in one sense and misses it in another: a language
whose correct programs are tedious to write gets written incorrectly first.

**A block-scoped `with`/`using` form.** `with b = alloc(16) { … }` binds and
disposes at the block's end. Rejected because it forces the value's lifetime to
be a block, and the common case is a value created mid-function and owned to the
end of it. `defer` expresses that; `with` needs the whole body indented under it.

**An `errdefer`, running only on abrupt exits.** Zig has one and its canonical
use is the reason: build two resources, transfer both out on success, release
what you built on failure. Rejected because **Linea already derives it**:

```linea
let a = alloc()?
defer free(a)
let b = alloc()?
defer free(b)
Result.Ok(Thing.of(a, b))
```

On success `Thing.of` consumes both, both schedules see `moved`, and both are
skipped. On the second `?`'s failing edge only `a` is scheduled and still owned,
so only `a` is freed. That is `errdefer`'s behaviour, and nothing declared it.

Zig needs the keyword *because* it has no ownership tracking — it cannot know
that `a` was transferred out on the success path, so the programmer must say so.
Linea knows, by the same lattice that removes the drop flag. Adding `errdefer`
would be adding a keyword to state what the graph already computes, which is the
mistake this record exists to avoid.

What is genuinely left over is a side effect on a failure path with no linear
value to cancel it — `errdefer log("failed")`. That is not disposal, it is "run
this where control leaves abruptly", and it is only wanted because `?` makes
those exits invisible. It is a different feature and should earn its own record
if anything ever needs it.

**Deferring a *statement* rather than an expression.** A block after `defer`
would let several things be scheduled at once. Rejected for now as unnecessary:
`defer` twice schedules twice, in the right order, and a block form can be added
later without invalidating anything written against this.

## Deliberately open

**Whether a `defer` may itself complete abruptly.** `defer return 1` inside a
function is a jump out of a scope exit, which is a control-flow shape nothing in
the language has. The likely answer is that it is refused, and the question that
settles it is whether any useful `defer` needs to fail.

**Whether a deferred expression may name a binding declared after it.** It
cannot today, by scoping. Whether that is a rule worth stating or a fact that
falls out is a question for the semantics.
