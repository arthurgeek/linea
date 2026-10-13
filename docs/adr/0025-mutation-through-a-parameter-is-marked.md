# 25. Mutation through a parameter is a convention, and it is marked at the call

Status: Accepted — 2026-07-26

The reference/address ABI and storage lifetime clauses are superseded by
[0123](0123-observations-carry-owner-dependencies-through-callable-contracts.md).

## Context

A function that changes its caller's data needs some way to say so. The
obvious mechanism is a reference type — `&mut T` or `T*` — but a reference is
a value that names storage, and once one exists the language has to answer
what may be stored in it, how long it stays valid, and what happens when two
of them name the same thing. Those are the questions lifetimes exist to
answer.

Linea has no references and does not want them yet. It needs mutation across a
call boundary without them.

## Decision

**`inout` is a convention on the parameter, not a type.** A parameter is
`read` unless it says otherwise; `inout` marks one the function writes back
through. The parameter's type is `u8`, not "reference to `u8`" — there is no
type spelling for the second thing, and nothing can hold one.

**`&` marks the argument at the call site, and is required and exclusive.** An
`inout` argument carries it; a `read` argument does not. It is **not
address-of and not a reference** — there are no references in the language to
take. It is a visibility annotation: a reader of a call sees which of its
arguments can change without opening the function it calls.

**Exclusivity is checked per call site, from the argument list alone — no
inference, no lifetimes.** A place passed `&` may not overlap any other
argument's places, whether that argument is marked or merely reads it. Two
places overlap when they share a root and one path is a prefix of the other;
today a place is a name, so this is name equality, and field paths slot in
when aggregates arrive without the rule being restated.

**Superseded by
[0053](0053-exclusivity-is-triggered-by-mutation.md):** naming the marker
names only half of what mutates a place. An argument may also assign to one,
and a block is an expression, so it can do that inside an argument list. The
replacement is triggered by mutation and covers both; everything else in this
clause stands.

**An address is passed.** A slot already is its own address, so the caller
hands the slot over; the callee's parameter slot holds that address, and
reading or writing the parameter is a load or store through what it holds.

## Why the exclusivity rule exists

Not to prevent confusing code. It exists so that **the representation is the
compiler's to choose**.

Because no program can observe whether an argument was passed as an address or
copied in and copied back, the backend may pick either — and may change its
mind. A later pass converting `&` of a small scalar into value-in/value-out at
a known call site is then legal rather than a special case. That is also the
reason the convention sits on the parameter rather than in its type: a
reference type fixes the representation at the signature, and a convention
does not.

`f(&x, x)` is rejected for the same reason `f(&x, &x)` is. The callee would
observe its storage changing through an argument nobody marked, and that
difference *is* observable — which would take the choice away.

## Consequences

**MIR gains three instructions** — `addr_of`, `load_indirect`,
`store_indirect` — rather than a flag on a local. A flag would make `load` and
`store` mean two different things depending on which slot they name, which is
the implicitness [ADR 0022](0022-mir-is-explicit-control-flow.md) was written
against.

**A marked argument's slot escapes.** QBE registerises small stack slots, but
only those that do not escape, so passing `&x` keeps `x` in memory for the rest
of the function. This is the cost of the address representation, and it is
what the reverse optimisation above would recover.

**No aliasing information reaches the backend.** QBE's IL has no `restrict`,
no `noalias` and no type-based alias analysis, so the exclusivity rule buys
soundness of the representation and nothing else. A backend that could express
it would additionally get the callee-side optimisations — that is a reason to
record the guarantee now, not a reason to change backends.

**`()` became writable.** A function that exists to mutate returns nothing,
and until this decision nothing could say so: the semantics named Unit and the
grammar had no spelling for it.

## Alternatives considered

**A reference type, `&T` or `*T`.** Rejected. It makes storage a value, which
requires answering how long it stays valid — lifetimes, or a garbage
collector, or unsoundness. The whole point of a convention is that the
question never arises: an argument is reachable for exactly the duration of
the call, syntactically.

**Copy-in/copy-out as the *semantics*, as Swift has it.** Not actually an
alternative — it is a different layer. Swift's semantics are copy-in/copy-out
and its implementation passes an address, and the two are reconciled by
exactly the exclusivity rule adopted here. Stating the semantics as
move-in/move-out instead would import an obligation Linea cannot yet check:
that a parameter moved out of is refilled before the function returns. There
is no move, no linear type and no definite-initialisation pass to enforce it,
so the words would promise something nothing verifies. They arrive with
ownership.

**Optional `&`, or `&` permitted but meaningless on a `read` argument.**
Rejected: the marker's only job is to be evidence. If it may be absent where
mutation happens, or present where it does not, seeing `&x` stops telling a
reader anything and the annotation costs ceremony for nothing.

**`&` meaning `inout` specifically.** The marker is defined as "mutating
access" rather than "inout", so that `set` can join it later without
respelling existing call sites. Only `inout` exists today, so nothing yet
distinguishes them.

**Two returns instead of an out-parameter.** A function returning a pair, the
caller rebinding. Rejected as a general mechanism: it needs aggregates, which
do not exist, and it forces every mutation into a rebinding at the call site
even where the value is large.
