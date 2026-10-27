# 241. Declared answers are settled when first needed

Status: Accepted — 2026-10-18. Extends
[0087](0087-an-associated-type-is-a-function-of-the-coherence-key.md) and
[0165](0165-an-attached-derive-requires-each-field-type.md). Extended by
[0251](0251-an-alike-instantiation-is-answered-from-one-representative.md),
under which the walk over what types own steps from an alike instantiation
to its representative.

## Context

Before any body is checked, the checker decides four kinds of declared answer:

- the **parts** of each structure, enum and newtype: field types, variant
  payloads and newtype bases;
- the **settled type** each implementation gives an associated type,
  `type Reading = UInt8`;
- the **element** a field delegation answers `Elem` with,
  `impl Index[UInt64] for Board via values`;
- the **type each alias names**.

Each of these may be written in terms of the others, in any direction:

- A part reads a settled type: `struct Sample { reading: Celsius.Reading }`.
- A settled type reads another settled type, or a delegated element:
  `type Reading = Celsius.Reading`, `type Reading = Board.Elem`.
- A settled type selects an implementation whose bounds ask for a type's
  capabilities, and those come from that type's parts. Given
  `impl[T: Discardable] Pick for Chooser[T]`, the type
  `type Item = Chooser[Tray].Out` exists only if `Tray` can be discarded.
- A delegated element is read from a field, whose type may itself be a settled
  type or another delegated element: `values: [Inner.Elem; 2]`.
- An alias may name any of these.

The checker decided them in fixed batch phases:

1. Read every part.
2. Refill the instantiations.
3. Settle every associated type, in rounds: a definition that reads another
   still waiting is read again in the next round, and what still waits when
   a round settles nothing is a cycle.
4. Settle every delegation.

Any answer that read one decided in a later phase found nothing there. It became poison with no diagnostic. `linea check`
accepted `struct Sample { reading: Celsius.Reading }`, and `linea run` stopped
with "invalid storage representation". Whether a program compiled depended on
the order its declarations were written in. On `main`,
`struct B { values: [B.Elem; 2] }` with `impl Index[UInt64] for B via values`
reaches itself, and is accepted and then crashes, because the delegation phase
never sees the part that names it.

Two repairs short of this one were built and measured: answers read again
after a provisional first reading, and rounds to a fixed point. Both are
rejected under *Alternatives considered*.

## Decision

**Every declared answer is computed by one routine, at the moment something
first needs it. A cycle among answers is a diagnostic. A diagnostic is only
ever produced from an answer that is final.**

1. **One routine per kind, each with a reading/settled state.**
   - `readPart` reads one part of a declaration.
   - `AnswerSettling.settle` reads an implementation member's written type
     (`settleMember`) or a field delegation's element (`delegatedElement`).
   - `aliasedType` reads an alias.
   - `AnswerSettling.owned` reads, before a capability is asked of a type,
     the parts of everything the type owns that were waiting on a settled
     answer.

   Each records its answer once. A later demand for the same answer reads the
   record. The driver walks every declaration, member, delegation and alias
   once and demands each. The walk's order decides nothing, because every
   dependency is demanded before it is read.

2. **Reading through any of them demands it.**
   - A settled reference demands the member it reaches. This goes through
     `Builder.demand`, so a reference found while substituting into
     an instantiation is covered too.
   - A delegated `X.Elem` demands the delegation.
   - A delegation demands the parts of the type it delegates from.
   - A capability or bound question about a type demands every part, of
     every declaration the type owns transitively, whose type waited on a
     settled answer. Which parts those are is recorded when parts are first
     read: a part is one if reading it passed over a settled reference,
     however reached -- written in it, through an alias, or through a
     parameter's default. Every other part already holds its type.
   - Writing an instantiation's parts demands its template's parts. See
     *Settling and writing an instantiation* below.

3. **A demand that reaches an answer still being read is a cycle.** It is
   reported where it closes, and the answer reads as poison.
   - A settled type that leads back to itself is [T-Impl], "this associated
     type is defined through itself", reported at the definition on the
     cycle written first and naming what each definition on it is written
     as.
   - An alias that leads back through a settled type is [T-Impl].
   - A delegation whose element is read from a field naming that same element
     is [T-Projection], "a delegated projection reaches itself". This is the
     diagnostic `settleDelegation` already defines for a backing chain that
     loops. It fixes `main`'s `struct B { values: [B.Elem; 2] }` crash.
   - A capability question about a type whose capabilities depend on a part
     still being read is [T-Bound]. See *A type whose parts depend on its own
     capabilities* below.

4. **Diagnostics come only from final answers.** A routine reads its
   dependencies through demand, so they are settled before it runs. The
   diagnostics it produces therefore describe the final program. The only
   exception is a value that reads as poison because a cycle was reported.
   The suppression a poisoned value already earns covers that case. No
   refusal is made on stale data, so no refusal is pinned by `refusedBefore`
   and later contradicted. A chain such as `T_k { f: Holder[T_{k+1}].Item }`
   gives the same diagnostics in either declaration order.

5. **The pass that callable shapes need keeps running first.** The first
   visit to every part runs before implementation heads are settled, and
   only provides callable shapes. It passes over settled references, and
   records the parts that did. Implementation heads and trait arguments are
   settled the same way, and those that passed over a settled reference --
   through a parameter's default, `impl Holder` with
   `struct Holder[T = Chooser[Tray].Out]` -- are read again once declared
   answers are settled.

## Settling and writing an instantiation

[0248](0248-an-instantiation-holding-a-parameter-is-written-when-read.md)
writes an instantiation's parts the first time something reads them
(`Builder.ensureFilled`, through `fillInstance`). That is a second answer
computed on first need, and the two stay separate questions with one
ordering between them:

- **Settling** reads a declaration's written source -- a part, a member, a
  delegation, an alias -- into the answer it names. It belongs to the
  checker, may report, and can meet a cycle.
- **Writing** an instantiation substitutes its arguments into its template's
  parts. It belongs to the builder, reads only what the template already
  holds, reports nothing, and its only reentrancy is the `writing` state
  0248 defines.

Writing copies what settling produced, so a question about a type demands in
one order, in one routine (`Builder.settleFactsOf`): the declared parts the
type depends on are settled first (`AnswerSettling.owned`), then the type is
written if it is unwritten and not answered from a representative
([0251](0251-an-alike-instantiation-is-answered-from-one-representative.md)),
then the capability facts are brought up to the pool. An instantiation written before its template's parts were settled is
written again from the template once they are, through the same
`fillInstance`: by `Builder.refillInstance` when a question walks it, and by
`refillInstances` once every declared answer is settled. Merging the two into one routine would put
the checker's diagnostics and cycle rules inside every builder part read, and
the finished pool's readers, which cannot report, would need a second path.

## Depth

Each demand reads what it depends on before it returns, so the checker's
stack grows with the chain of answers it walks. A chain of 30,000 settled
types or delegations overflowed it. **A chain of declared answers passes
through at most 1000 links, and a longer one is [T-AnswerDepth]**: the same
bound, for the same reason, as [S-Nesting]. Acceptance must not depend on the
stack an optimisation level happens to leave.

A link is a written settled reference (`Celsius.Reading`, `B.Elem`,
`Chooser[S1].Out`), an alias, or a member the builder demands while it
substitutes into a settled reference written in a template: `type Item =
H[S1]` with `struct H[T: Tr] { v: T.Item }` writes `H[S1]`, which reads
`S1.Item` without that reference being written anywhere. Every recursion
from one declared answer into another passes through one of these: a member
reaches another member, a delegation another delegation, and a part another
type's parts only through a settled reference, written or substituted, or an
alias. A demand made while a written reference is read is that reference's
link, not a second one, and a reference read through a parameter's bounds,
`T.Item` in `struct H[T: Tr]`, reads no other declared answer and is no
link. A generic member or alias is read once, at its parameters, so its own
height is that of what it reads there; what it reads at each argument is
counted where the argument's reference is. Parts, members, delegations and
capability questions add no link. A structure nested inside another 45,000 times adds none, and
neither does a chain of 200,000 types each held only as an argument of the
one before (`struct N0 { x: Marker[N1] }`), because reading what a type owns,
and then the arguments it is applied to, is a walk with its own stack
(`AnswerSettling.owned`), not a recursion. Counting links therefore bounds the recursion, and nothing
else needs bounding.

The depth is a height, not the nesting of the walk at the moment it is
measured:

- every answer, alias, part and owned type records the most links it rests
  on, once read;
- a reader takes the tallest of what it read, whether it read it now or
  read the record;
- a link adds one.

So the measure is the same whichever end of the chain is read first, and a
program is accepted or refused alike in either declaration order. The walk
also stops descending at 1000 open links, which is where the height would
pass the bound anyway, so it never recurses further than that. The error
names where the chain starts, says the limit, and suggests writing a type
directly somewhere along it. It is reported once per program, because every
answer above a chain that is too deep is too deep as well. Where it is
reported can follow declaration order; whether it is reported does not.

A plain alias chain counts too: `alias A0 = A1`, ..., `alias A1000 = UInt8`
is refused. That is new; such a chain was accepted before.

## Cost

- Each declaration's parts, each member, each delegation and each alias is
  read at most once. That is the single reading the batch phases already did.
- Each demand is a state lookup in a table sized by the program's
  declarations, made once per reference written. The work is therefore linear
  in the written types read, plus the selections they make.
- A chain of N delegations or N settled references costs N readings, not
  N × program, for N up to the 1000 that [T-AnswerDepth] admits; the
  rounds rejected below re-read the whole program per link. Sweep
  dimensions for both chain shapes hold this.
- The transitive demand of a capability question visits each owned-part edge
  once over the whole check: see *One walk over what types own* below.
- Capability facts must not be rebuilt each time a part is read. Today a
  replaced field marks the whole fact graph dirty, and the next question
  rebuilds it from scratch. Reading parts lazily, between capability
  questions, would make that O(questions × pool). So replacing a part that
  gives its owner nothing in a table -- poison, or a type built from it such
  as `[poison; 2]` -- adds one edge to that table instead, and a callable
  shape gaining its effects changes nothing any table reads. Any other
  replacement still marks the table dirty, and lazy reading makes none.

## A type whose parts depend on its own capabilities

```linea
impl[T: Discardable] Pick for Chooser[T] {
    type Out = UInt8
}

struct Tray {
    held: Chooser[Tray].Out,
}
```

Reading `Tray`'s parts selects `Pick` for `Chooser[Tray]`. That asks whether
`Tray` can be discarded, which depends on `Tray`'s parts. The same shape
arises through a member, `held: Desk.Item` with
`type Item = Chooser[Tray].Out`, and through two types whose parts ask about
each other. With `type Out = Ticket` instead, where `Ticket` is linear, the
program refutes itself: `Tray` would have to be discardable to hold a
`Ticket`, and holding one makes it linear.

**A capability question asked about a type is refused when the answer
depends on one of that type's parts, or of the parts it owns, that waits on a
settled answer and whose reading is what asked the question.** The refusal is
[T-Bound]: "`Tray`'s parts depend on whether `Tray` can be discarded" (or
"copied", or "on `Tray`'s own capabilities" where the question read them
without a requirement). It names the type the question was about, with help
to write the part's type. It is reported at the part being read when the
question was asked, and that part reads as poison. Both programs above are
refused, and so are the member form and the form that reaches the settled
type through a parameter's default, `struct Holder[T = Chooser[Tray].Out]`
with `struct Tray { held: Holder }`.

The same cycle closes through an instantiation's parts: `type Item =
Ch[W[S]].Out`, with `impl[T: Discardable] Pick for Ch[T]` and
`struct W[T: Tr] { v: T.Item }`, asks whether `W[S]` can be discarded, and
`W[S]` holds `S.Item`, the settled type being read. An instantiation whose
parts are written while a member they read is still being read waits on that
member, and the question is refused at the member's written type.

**Each part whose own cycle remains is reported.** A part refused while
another part is read reads as poison, and what its question found is no
longer something the other depends on; the other is then refused only if
its own question still closes a cycle. So two parts asking about one holder
that holds both, `Y0.p` and `Y1.p` with `p: Chooser[B0].Out` and `B0`
holding an `X` that holds `Y0` and `Y1`, are two reports: writing either
part's type leaves the other's cycle, so each is an edit the reader must
make. Two types whose parts ask about each other, `Tray.held` asking about
`Pan` and `Pan.part` about `Tray`, are one report: writing either part's
type removes both cycles. A selection answered while a refused question
was open is asked again, not reused.

A question its type's declaration already answers is no cycle: a type not
declared `copyable` is never copied, and one declared `linear` is never
discarded, whatever its parts hold. A trait question is no cycle either:
whether `Tray` implements a trait is decided by its implementations, and a
derived implementation's requirements on `Tray`'s parts are checked once the
parts are read.

The rule is exactly a cycle in the demand graph. When the question arrives,
`AnswerSettling.owned` first reads every other waiting part of the type, and
of the types the type owns. Only a waiting part that is itself still on the
reading stack blocks the answer, however many types lie between: a part of
`Y` asking about `B`, with `B` holding an `X` that holds the `Y`, is refused
whichever declaration asks about `X` first. Which parts wait is recorded when they are
first read, from what the reading passed over, not from how the part is
written, so no spelling of the dependency escapes the rule. The rule does
not depend on the order of a type's fields.

### One walk over what types own

A question asked while a part is read starts a walk of its own, inside the
walk that was reading the part, and that walk can reach the types the outer
walk has open. The walks are one depth-first search over the graph whose
edges are owned parts, and its strongly connected components are found as
in Tarjan's algorithm (`AnswerSettling.OwnedWalk`):

- a type is pushed once: its waiting parts are read and what it owns is
  listed;
- a type reached again while its component is open is a back edge, which
  joins its component; reached from a nested walk, it is also a dependency
  on every part the outer walk is still reading below it;
- a question asked while a type's parts are read makes that type depend on
  whatever the question's search reached: on the component the asked type
  belongs to, if that is still open, so the type is decided with that
  component rather than ahead of it, and on the part it waits on;
- a component is decided when its root is popped: complete, or, where it
  depends on a part still being read further out, watched until that part
  is read and complete then.

Every type is pushed and decided once over the whole settling, and every
edge followed once, so the walk is linear in the owned-part graph whatever
order declarations, or questions, come in. A type asked about while its
component is open is watched with the part the open walk is reading, which
is what makes a nested question about it the cycle above.

A recursive type with no such part is unaffected. In
`struct Node { log: Ledger[Node] }` with `Ledger[phantom T: Discardable]`,
`Node`'s parts name no settled type, so each is known from its written type
when the bound is asked. The coinductive rule for recursive types
([0165](0165-an-attached-derive-requires-each-field-type.md)) answers it as
before.

The choice was between this rule and two others:

- **Assume, then verify.** Answer from the parts read so far, counting unread
  settled parts as permissive, as recursive capabilities already are. Ask
  again once the parts are read, and refuse only if the answer changed. This
  accepts the `UInt8` program and refuses the `Ticket` one. It was not taken
  because:
  - an answer the program never states would be accepted on the strength of
    its own assumption;
  - every assumption needs a second question and a record of the first;
  - whether a program compiles would depend on a fixed point, not on an
    acyclic chain of demands that a reader can follow.
- **Assume without verifying.** Answer from the parts read so far and keep
  the answer. Rejected: in the `Ticket` program it applies an implementation
  whose bound is false.

Rust makes the same choice. A field type that needs a trait bound on the
type being defined, `struct Tray { held: <Chooser<Tray> as Pick>::Out }` with
`impl<T: Copy> Pick for Chooser<T>`, is a cycle error ("cycle detected when
computing type of"), and the fix is to write the field's type.

Before this record, no build decided the question on purpose:

- `main` refused the directly written form with [T-Impl], by accident: the
  first visit to the part ran before implementation heads were settled, and
  that refusal was kept.
- `main` crashed in lowering on the member form.
- A rounds-based repair accepted the `UInt8` program in both forms.

## Alternatives considered

**Fixed phases in another order.** Settling associated types before reading
parts fixes `Sample`, but `Chooser[Tray].Out` then selects over a `Tray` whose
parts are not read. Reading parts first gives back the original defect. A
dependency can run in either direction, so no fixed order of whole phases
answers every program.

**Provisional answers, read again afterwards.** Settle what a part demands, mark
it provisional, then read members and parts once more. One re-read settles a
chain of depth one. A delegation is memoised and cannot be re-read, so a
nested delegation stayed poison. A refusal made on the provisional answer is
kept by `refusedBefore` even when the second reading accepts.

**Rounds to a fixed point.** Read every part, member, delegation and alias,
refill, and repeat until a snapshot stops changing. The answers come out
right, but each round carries an answer only one link further. A chain of N
delegations costs N rounds over the whole program, including the standard
library: 200 links took 20s against 1.3s. Refusals made in early rounds are
kept, and silencing them on poisoned subjects hid a real cycle
(`B.Elem = Wrap[B.Elem]`) entirely. The fixed point also has nothing to say
about a genuine cycle, which simply converges to poison. `main`'s third
phase is this, for associated type definitions alone, at a cost quadratic in
the length of a chain of definitions; this record replaces it, and keeps its
cycle report.

**Report every diagnostic in a last round.** Run the rounds quietly and report
in one final round. This needs every refusal table the checker keeps
(`bounds_reported`, `refused_demands` and more) restored between rounds, and
it keeps the N × program cost.

## Consequences

- `linea check` accepts exactly the programs whose declared answers exist and
  agree, independent of declaration order. Cases under
  `tests/traits/declared_answers/` and the reversed-declaration property hold
  it, and the conformance harness's tests generate each chain shape at 1000
  and 1001 links in both declaration orders, a chain of 30,000 delegations
  and a structure nested 45,000 deep, which are too long to keep as cases.
- A delegation that reaches itself, and an alias or settled type that leads
  back to itself, is reported rather than crashing lowering.
- The rule for a type whose parts depend on its own capabilities is
  [T-Bound] in `docs/linea-semantics.md`.
- **Whether a cycle is reported does not depend on order.** A cycle of
  definitions is reported once, at the definition on it written first; a
  delegation or part cycle is reported where the walk closes it, which
  follows the order the walk reached its members.
