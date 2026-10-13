# 30. A variant carries several values, and what stops a layout is a cycle

Status: Accepted — 2026-07-26

Supersedes the `[T-Payload]` clause of
[0028](0028-a-type-is-a-pool-handle-and-layout-is-a-table.md). The rest of that
record stands: a type is still a pool handle, layout still travels as a table,
and a tag still occupies a word.

## Context

0028 laid out an enum under a rule narrow enough to be three constants, and
added `[T-Payload]` to reject everything the rule could not describe — a
variant carrying more than one value, or carrying something that carries values
of its own. The record stated the reason plainly: such a payload "would be
sized as a word and read as one — a wrong answer rather than a missing
feature."

The rule did not do that. `enum List { Cons(List), Nil }` was accepted. When
`Cons` is checked, `List` has no payload yet, so it does not look like
something that carries anything, and the rule waved through the one payload
that is its own type. The program was then laid out flatly — a value holding a
copy of itself, sized as one word, which is exactly the wrong answer the rule
was written to prevent.

So the restriction was not protecting the layout. It was excluding the cases
the algorithm could not describe, and one case it could not describe got in
anyway.

## Decision

**A variant carries a run of values, in the same table a structure's fields
live in.** One piece of code places both, so a variant and a structure cannot
be arranged by rules that disagree.

**`[T-Payload]` is removed.** What replaces it is not a narrower version of the
same restriction but a different rule about a different thing:
`[T-InfiniteLayout]` says the graph of types reached by traversing inline parts
is acyclic.

That is what actually cannot be laid out. A payload carrying values of its own
is laid out by the same rule that lays out anything else. A payload that
reaches its own type is not, because computing the size requires the size — and
no restriction on how many values a variant carries would have caught it.

**The rule is about layout, not recursion.** A type that reaches itself through
an indirection is well formed: the outer size stops needing the inner one. So
the rule outlives the absence of pointers rather than being restated when they
arrive, and it is named for the condition rather than for the shape — a rule
called `T-Recursive` would be reporting what it is about to permit.

## Consequences

Two constructs that were refused now compile, and one that was accepted is now
refused. The last is the point: the program that most needed rejecting was the
one the old rule let through.

Detection walks the type graph marking each type as *on the current path* or as
*finished*, never as *seen*. Those differ on a type reached twice without a
cycle, which must be accepted — an enum held by two variants of another is an
ordinary program, and a visited set refuses it. That distinction is a test
rather than a comment, because it is the whole of what makes the walk correct.

A reported cycle is broken in the pool rather than only reported. The type
stays there and every pass below asks for a layout; one that cannot terminate
does not stop being asked because a diagnostic was emitted.

`[T-Bind]` gains a sharper edge: an arm binds every value or none. A prefix
would bind the first and leave the rest unnamed, which reads as a choice and is
a miscount.

## Alternatives considered

**Keep `[T-Payload]` and fix its hole.** Check the payload against the enum
being declared as well as against what is in the pool. Rejected because it
treats the symptom: the hole was one instance of a general condition, and the
general condition is cheap to check directly. Fixing the narrow rule would have
left a variant unable to carry two values for no reason connected to layout.

**Forbid recursive types by name.** Simpler to state and simpler to implement,
and wrong the day indirection exists — at which point the rule would have to be
withdrawn and replaced rather than kept. A rule that has to be unsaid was never
the rule.

**Lay every variant's payload out at a fixed offset per enum.** Would have
avoided per-variant offsets entirely. Rejected because a variant carrying a
`u64` and one carrying two `u8`s want different arrangements, and forcing one
on both wastes space in every enum to save a function that already exists.
