# 60. A library declaration the compiler must name is named through the prelude

Status: Accepted — 2026-08-02

## Context

`?` is nominal over `Option` and `Result` and over nothing else. That makes it
the first construct in the language whose meaning depends on the compiler
knowing which declarations two library types are.

Before it, the compiler named none. Every primitive it knows — `UInt8`, `Bool`,
the rest — it provides itself, and `builtinNames` answers for all of them
without consulting the library at all. `Convert`, the one trait the language
leans on, is not named anywhere in `src/`: the conversion syntax reaches it
through the primitives, not through its name. So there was no existing way to
say *which declaration is `Option`*, and inventing one was unavoidable.

Three ways were available, and the choice is a compiler invariant rather than a
language rule: it decides where an answer lives, not what any program means.

## Decision

**A library declaration the compiler must name is found in `Resolution.prelude`,
by name.**

`Resolution.prelude` already holds the declarations the prelude publishes, as
the list every ambient name in every module is resolved against. Asking it for
the one named `Option` gives one answer to *which declaration is `Option`*, and
it is the answer every reference to `Option` in every program already gets.

Two consequences follow and are intended.

**Recognition is by identity, not by shape.** A user type whose alternatives
are spelled `Ok` and `Err` is not a `Result`, and `?` refuses it. Declaring a
second `Option` is not a way around that: the prelude's name is already
declared and a second is `[N-Duplicate]`, so there is no shadowing question
for this record to answer.

**A library file may move without the compiler changing.** Nothing here names a
directory.

## Consequences

The compiler now depends on the prelude publishing `Option` and `Result` under
those names. Renaming either in `std/` breaks `?`, and breaks it as a `?` that
reports `[T-Try]` on a correct program rather than as anything louder. That is
the cost of nominal recognition and is not specific to this mechanism; the
alternatives carry it too.

Which declarations the two are is settled once, where the prelude is, and kept
on the checker. Not for the scan's cost — the prelude holds a handful of
declarations — but because which declaration `Option` is is a fact about a
compilation rather than a search each site repeats.

**Recognising the type and finding its alternatives are one answer, and the
coupling is deliberate.** A `Result` whose alternatives are not `Ok` and `Err`
is not one `?` can use, so a caller never carries a "recognised but unusable"
case. Answering separately is what produced a poison type on a node nothing had
reported, and a comparison of two poisons that agreed — so the rule that error
types must match passed by accident exactly when its input was missing.

The cost is worth stating plainly, because it is stronger coupling than a
reader expects. Rename `Err` in the library and `Result` stops being recognised
at all: every `?` over one reports `[T-Try]`, a message that names the type it
is refusing and so contradicts itself. The library is what is broken there, and
the diagnostic blames the program.

Splitting the two answers apart would let the message say which failure it is,
at the price of restoring the case above. The better fix is neither: check the
library's shape once where the prelude is loaded, and refuse a library `?`
cannot use before any program is compiled against it. That is not owed yet —
nothing can provoke it without editing `std/`, so it would be a rule with no
case, which this project does not add. It becomes owed the day a second
construct depends on a library declaration's shape, because then the assumption
is load-bearing in two places.

Which alternative of a carrier is the successful one — `Some` or `Ok`, `None`
or `Err` — is answered by one routine that the checker and lowering both call.
The checker asks it to say what `?` yields; lowering asks it to say which tag
`?` tests. Asking separately is the shape that drifts the first time a variant
is written in another order, which is the failure
[0048](0048-one-question-has-one-answer.md) is about.

## Alternatives considered

**A hard-coded path to `std/option`.** The checker walks to the module and
takes `Option` from it. Rejected because it ties the compiler to where the
library keeps its files — moving one becomes a compiler change — and because
the path is a second way to name a declaration the prelude already names. Two
ways to name one thing is the precondition for them disagreeing, and here they
would disagree exactly when the library was reorganised, which is when nobody
is looking at `?`.

**A marker in library source.** The language gains a way for a declaration to
say "I am what `?` recognises", and `?` finds whatever carries the marker. This
is the most general and would extend to a third type without a compiler change.
Rejected because it is a language feature — new syntax, a rule about where the
marker may appear, a diagnostic for two declarations claiming the same role —
introduced for a milestone whose entire scope is one operator. It also settles
by anticipation a question nothing has asked: no type outside the library wants
this control flow, and if one ever does, a trait is the better answer than a
marker.

**A trait `?` dispatches through.** Any type could implement it. Rejected for
the same reason and one more: it makes `?` open, and an open `?` has to say
what happens when two implementations are in scope. Nominal recognition is the
smaller thing that works, and widening it later is additive — a trait admitting
these two types accepts every program this accepts.
