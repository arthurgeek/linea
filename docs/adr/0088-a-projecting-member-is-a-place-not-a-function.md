# 88. A projecting member is a place, not a function

Status: Accepted — 2026-08-15

Extended by [0126](0126-observations-project-referent-places-transparently.md).
Partially superseded by [0135](0135-field-delegation-uses-checked-projection-plans.md)
for canonical representation and generic cycle-check timing.

## Context

`v[i]` on an array is a **place**: assignable, lendable, checked. For `v[i]` on
a user container to mean the same thing, a container has to hand out a place —
and this language has no references, so a member cannot return one. A member
returning `Elem` returns a copy, and `g[i] = x` over a copy writes into a value
nobody can see.

So the member cannot be a function. What it has to be is decided by what a
container's storage actually is: a field, reached by a path the language can
already write. `self.cells[i]` is a place today, `b.field[i]` is a place today,
and everything ownership knows about parts it knows about those.

That suggests two tiers, and the language's growth plan needs both. A **structural**
projection's meaning is entirely a place path that already exists — it is a
place former with typing rules. A **computational** projection's meaning
depends on running code: a hash lookup, a decompression, a virtual member.
The second is a construct with control flow in it, and control flow in this
compiler is built twice — once by MIR and once by the ownership pass — so
every new construct owes an answer to both. Each such construct owes an answer
to that at design time.

The structural tier owes neither builder anything, and that is the whole reason
to take it alone.

## Decision

**A projecting member is a place, not a function.** `proj` declares one beside
`fn`, and the difference is what its braces hold: a function's body is code a
call runs, and a projection's body is a path a site becomes.

**Its body is a place rooted at `self`**, reached by field selection and
indexing and by nothing else. A body that computes a value, branches, or calls
is refused (`[T-Projection]`). Where a path leads is read from the tree by the
walk that already answers it for ownership, so the spellings a projection may
be written with are exactly the spellings ownership already governs.

**It is expanded once per implementation into a canonical place path**, and
every use site extends that path. No later pass sees the declaration: ownership
and MIR see a path rooted at a binding, which is what they already read. That
is the structural tier stated as an implementation invariant rather than as an
intention.

**Expansion carries a cycle check.** `proj at(…) { self[i] }` is syntactically
a place rooted at `self` and semantically a projection expanding into itself, so
a projection whose expansion reaches a projection already being expanded —
directly or through any chain — is refused, naming the cycle. The check is
per-implementation and runs at declaration checking, never per use site.

**The mode on `self` is a ceiling.** Three properties are distinct and each of
them is one: evaluation access is what reaching the place needs from the
container, and for a structural projection it is always a read; place access is
what the site does with the place it reached, decided by position exactly as
every access already is; and the ceiling is the most place access may reach
through this implementation. The trait writes the maximum a conforming
implementation may offer and an implementation may write less — `Index` reserves
`inout` and a read-only container declares `read self`. A write above the
ceiling is the existing assignment-demands-a-mutable-place refusal, pointing at
that `read self` as the reason.

**`sink` through a projection does not exist.** It falls out of the ceiling
rather than needing a rule: `sink` grants more than any ceiling a trait writes,
so it is refused by the same comparison. Moving an element out leaves a hole the
container has to mediate, and mediation is an operation with a body — R4's
`remove(i) -> T`.

**A projection answers a trait's declaration and nothing else.** An inherent
`impl` may not hold one. Everything else about it is the member rules that
already exist: impl-completeness for a missing one, duplicate-member for a
doubled one, and signature agreement under whatever the implementation settled
its declared types to for the result — so `type Elem = UInt8` beside
`proj at(…) -> UInt8` agrees, `-> Self.Elem` spells the same type and agrees
too, and any other type is refused by the rule that refuses a wrong `fn` result.

**A projection is generic only where its trait is.** The trait supplies the
arguments and the declared type is the output, so `proj` adds no parameters of
its own and no new inference or coherence dimension exists to legislate.

## Consequences

**Neither control-flow builder learns a construct, and that is this record's
verification obligation.** MIR's builder and the ownership pass's builder are
two readings of the same flow, and a construct added to one and not the other is
the defect this compiler has had before. A projection adds no flow at all: it is
gone before either builder runs. What holds that claim is testable and is held
by tests rather than by this paragraph — an `.ssa` golden on a projected site
containing address arithmetic, no `call`, and no projection artifact of any
kind; and a differential pair whose emitted IR is identical to the hand-written
path the projection names. A change that routed projections through a call would
fail both.

**Ownership sees only paths it already governs.** A projected place is a part
beneath a root, so every part rule applies verbatim and with no
projection-shaped case: reading a part is a reading position, a partial move
does not exist so `let x = b[i]` over a Linear element is `[O-Move]` by the
existing rule, and overwriting a live Linear part is `[O-Leak]` by the existing
rule. That is a consequence of expansion happening before the ownership pass,
not a set of rules this record adds.

**The heavy tier re-opens the flow question in its own record.** A computational
projection runs code, so it owes both builders an answer, and it will be
weighed against what a method already does rather than inherited from here.

## Alternatives considered

**A member returning the element.** `fn at(read self: Self, i: I) -> Elem`
compiles and is wrong: it hands out a copy, so `b[i] = x` writes nowhere and
`f(&b[i])` lends a temporary. The language has no reference to return instead,
which is the constraint the whole design sits under.

**Admit inherent projections.** `impl Grid { proj at(…) }` needs no trait and
reads naturally. It also settles by accident what a bracket on a type with no
`Index` means: whether a bracket looks for an inherent member before a trait
one, what happens when both exist, and what a generic body bounded on `Index`
reaches. Nothing needs one today, and a question that size is a design rather
than a consequence of admitting a form.

**A body that is a block with statements, refused later.** Reading the body as
ordinary code and refusing the parts that are not a path leaves "which parts"
open, and the answer drifts toward admitting a call that is *probably* pure.
Refusing at the declaration on the tree's own reading of a path keeps the tier
boundary a syntactic fact rather than a judgement.

**Mode agreement rather than a ceiling.** Holding an implementation's `self` to
the trait's mode exactly is the rule every other parameter is held to and needs
no new comparison. It also forbids a read-only container from implementing
`Index` at all, because the trait must reserve the maximum a bracket may ever
demand — and a trait that reserved only `read` could never be widened without
breaking every implementation. The ceiling is the one place a mode is a maximum,
and it is confined to a projection's receiver.

**A `sink` projection for moving an element out.** It reads as the natural way
to take an element, and it cannot mean anything: the container is left holding a
place with no value and no way to say so, and the type system has no partial
move to describe the result. A method that mediates the hole is what says it.
