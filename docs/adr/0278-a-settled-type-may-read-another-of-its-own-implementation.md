# 278. A settled type may read another of its own implementation

Status: Accepted — 2026-11-17; extends
[0241](0241-declared-answers-are-settled-when-first-needed.md), whose
scheduler now decides every reading of one definition by another

## Context

An implementation settles each type its trait declares: `type Item = UInt8`.
A definition could read what *another* implementation settled, `type Dual =
Pong.Dual`, and the declared-answer scheduler decides each such answer once,
after everything it reads, whichever implementation is written first. It
reports a definition that reads back to itself, `Ping.Dual` reading
`Pong.Dual` reading `Ping.Dual`, as [T-Impl] once per cycle, and
[T-AnswerDepth] bounds how many links any answer rests on.

A definition could not read a type its own implementation settles through
`Self`, a rule the language definition stated and no record decided: `type Second = fn(value: Self.First) -> UInt8` was refused with "a
settled type is not written as a settled reference", by a check that looked
for a selection headed by `Self` anywhere in the written type before reading
it. The same dependency spelled through the implementing type's name,
`fn(value: Value.First) -> UInt8`, was accepted, because the scheduler reads
`Value.First` like any other implementation's answer, and a generic
implementation could already read a sibling of its own at a concrete argument,
`Wrap[UInt16].Tag`. The ban therefore refused no dependency the language
otherwise refuses. It refused one spelling of it, and the spelling it refused
is the one that carries the most information: `Self.First` names the
implementation being written, its trait and its arguments, where `Value.First`
must be resolved again and is ambiguous when two traits implemented for
`Value` both declare `First`.

The rule it stood for, that a definition must not depend on itself, is already
enforced by the scheduler for every other spelling.

## Decision

A definition may read a type its own implementation settles through `Self`,
anywhere inside the type it writes: `type Item = Self.Other`, `type Held =
Option[Self.Item]`, `type Second = fn(value: Self.First) -> UInt8`. `Self.Name`
there is the type the enclosing implementation settles `Name` to, read through
that implementation's own trait and arguments. It is decided as any other
declared answer is:

- once, after the definitions it reads, whichever order they are written in;
- a definition that reads back to itself, `type Item = Self.Item`, or a set
  that read each other round, `type First = Self.Second` with `type Second =
  Option[Self.First]`, defines no type and is [T-Impl], reported once per
  cycle by the same report every other cycle of definitions gets;
- each `Self.Name` read counts as one link toward [T-AnswerDepth].

The syntactic refusal and the walk that looked for `Self` inside a written
type are removed. Nothing below the checker changes, because ownership,
instance discovery and lowering already read the settled type, never the
spelling that produced it.

## Consequences

- One rule decides every dependency between definitions. A reader no longer
  has to learn that `Self.First` is refused where `Value.First` is accepted.
- `Self.Name` inside an implementation never meets the ambiguity a settled
  reference through the type's name can: with `Count` and `Weigh` both
  declaring `Unit` for `Crate`, `Crate.Unit` names neither, and `Self.Unit`
  inside each implementation names that implementation's.
- A cycle written through `Self` is now reported as a cycle, naming each
  definition on it, rather than as a refused spelling at each `Self`.
- An inherent implementation settles no trait members, so `Self.Item` inside
  one still selects through the type's traits as it did; this record changes
  only what a trait implementation's own definitions may read.

## Alternatives considered

**Keep the ban.** It costs a second, spelling-only rule beside the scheduler
and refuses programs whose dependencies are acyclic and accepted in another
spelling. It added no safety: every cycle it would have caught is one the
scheduler reports.

**Rewrite `Self.Name` to the implementing type's name before reading it.** The
rewrite loses which implementation `Self` meant. Where two traits implemented
for one type declare the same name, or one trait is implemented at two
argument lists, the rewritten reference is ambiguous or selects another
implementation, so the rewrite would change meaning exactly where `Self` is
the clearer spelling.

**Read sibling definitions in declaration order, refusing a forward read.**
The scheduler exists so that what a definition means never depends on where it
is written; a forward-read rule would make swapping two lines refuse a program,
which the rest of the language does not do for declared answers.
