# 70. Explicit failure is acknowledged

Status: Accepted — 2026-08-04

## Context

`let _ = write_to(s, fd)` compiled. So did the same line four times over in the
standard library's own printing, where every write to a file descriptor had its
answer thrown away — including the answer that said the write did not happen.

The language already refuses most ways of doing this. A bare call in statement
position is [T-Discard](../linea-semantics.md); a name nothing reads is
[N-Unused]. What was left was the one that looks intentional: binding to `_`.

Three answers were considered and two are wrong in instructive ways.

**A `must_use` attribute**, as Rust has. Linea has no attributes, and Rust's is
a lint that can be silenced — it exists because Rust has no stronger tool.

**Making `Result` linear.** This is the tempting one, because Linea *does* have
a stronger tool, `let _ = w` on a linear `w` really is `[O-Leak]`, and no new
mechanism would be needed. It fails twice.

It fails **semantically**: linearity guarantees a value is *consumed*, not that
anyone looked at it. `match r { Ok(_) => {}, Err(_) => {} }` discharges a linear
`Result` perfectly while ignoring the failure completely. The instrument does
not measure the thing.

It fails **structurally**, and this is the decisive one. A container in Linea
inherits the universe of what it holds: `Result[Str, IoError]` is Free because
neither payload owes anything, and that is not an accident but the rule that
makes universes compose. A container that confers ownership of its own inverts
where ownership comes from. `Option` would have to follow, then every future
container, and the structural rule would be gone —
[0034](0034-ownership-is-positions-and-a-graph.md)'s composition traded for a
lint.

## Decision

**[T-DiscardFailure]: a `Result` may not be bound to `_`.** It must be matched, handed
on with `?`, returned, or passed to something that takes it.

### It is its own rule, not a clause of [T-Discard]

The two govern different constructs. [T-Discard] is about **statement
position** — an expression evaluated for its effect. This is about a **binder**.
Their conditions do not overlap and neither implies the other; that the
implementations sit beside each other is not a reason to fuse them, and fusing
them would turn a purely type-shaped rule into "Unit, or not a `Result`".

### What is asked for is acknowledgement, not observation

A `match` whose only arm is `_` satisfies this rule.

That is the line, and it is drawn deliberately. Such a match names the
alternatives and chooses to treat them alike — it is written down, it appears in
a diff, a reader sees the choice being made. `let _` says the report was never
there at all.

Requiring instead that both alternatives be *inspected* would cross from *did
the program deal with this* into *did the program reason about it the way the
compiler wanted*. The second is style. It is also unimplementable without
making legitimate code unwritable: ignoring a failure on purpose is something
programs need, and this repository's own debug-tier printing is the first
example.

No language enforces observation. Rust's `must_use` is silenced by `let _`;
Zig's error unions are discharged by `catch {}`. Both settle for
acknowledgement, and so does this.

### `Result` is language-significant, and this says so

The rule is keyed on the prelude's own `Result` declaration — the mechanism
[0060](0060-a-library-declaration-is-named-through-the-prelude.md) established
and that `?` already uses.

This does mean `Result` is part of the language and not merely a type the
library happens to declare. That was already true the moment `?` recognised it;
what is new is only that a second thing is keyed on the same identity. It is
recorded here rather than left implied, because a reader who finds
`if type == Result` in the checker deserves to find the reason written down
rather than inferred.

## Consequences

**Four sites in the standard library were ignoring a write failure**, and all
four were in `std/text/out.lin`'s printing. Nothing else in the library was
sweeping anything under the rug — which is a smaller number than expected and is
the measurement that justified doing this before touching `Writer`.

**Printing splits into two tiers**, which is the split Zig draws and which the
rule forces into the open. `print` and `println` go to standard output, which is
what the program is *for*, and hand the answer back. `eprint` and `eprintln` go
to standard error, are the debug tier, and ignore the failure — written as a
`match` with one arm, so that the ignoring is visible rather than absent.

**A failure now has to go somewhere, which is where
[0071](0071-a-failure-may-leave-through-the-entry-point.md) comes from.** A
program that prints and does not care must say so, and the shortest way to say
it is `?` — which needs an entry point that can carry a failure out. This rule
makes the question unavoidable; that one answers it.

**[T-Discard]'s hint had to change.** It advised `let _ =`, which for a `Result`
now sends the reader straight into this rule. One diagnostic must not recommend
the next.

## Alternatives considered

**Leave it.** The library demonstrated where that goes: four ignored failures,
none of them decided on, all of them invisible.

**A `must_use` attribute.** No attribute system exists, and building one for a
single use is a mechanism in search of a second caller.

**Linear `Result`.** Rejected above, on the structural argument rather than the
semantic one: it would break universe composition, which is a property worth
more than this rule.

**Closing the `_ =>` arm as well.** Rejected: it enforces observation, which is
style, and it makes deliberate ignoring unwritable.

## Deliberately open

**Whether `Option` should be treated the same.** It is recognised by the same
mechanism and `let _ = maybe()` discards an absence as quietly as this discarded
a failure. The argument is weaker — an absence is a value, where a failure is a
report — and no caller has wanted it yet.

**What `print` should do about the `Result` it now returns** is the caller's
question and not the library's, and it stays that way until something other than
an example is calling it.
