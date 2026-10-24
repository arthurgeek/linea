# 248. An instantiation holding a parameter is written when it is read

Status: Accepted — 2026-10-24. Supersedes the ordinary-fields clause of
[0047](0047-instantiation-is-a-backend-concern.md).

## Context

[0047](0047-instantiation-is-a-backend-concern.md) made an instantiation an
ordinary declared type: `Builder.instantiate` interned `Cell[u8]` and, in the
same call, wrote its fields by substituting the template's, so "layout,
matching and field lookup need no case for it". Writing a field substitutes its
type, and substituting a generic type mints that type's instantiation, whose
fields are written in turn.

That recursion has no bound but the program's own reach, and generic
structures that name one another in their fields make it reach far. With
`Ring0[X]` holding `Many[Ring1[X]]` and every `RingK` holding the next two,
`Ring0`'s own fields mint `Ring1[X0]` at `Ring0`'s parameter, whose fields mint
`Ring2[X0]`, and so on round the ring: every declaration's parameter reaches
every structure. Five hundred such structures minted about a million
instantiations, and three refills of every instantiation before any body was
checked made checking them quadratic in the number of declarations. Almost none
of those copies is read: no value has the type `Ring7[X0]`, and nothing asks
what it holds.

The copies are not interchangeable with their templates, so they cannot simply
be skipped: `Ring1[X0].x` is `X0`, not `Ring1`'s own `X`. And the answer must be
there for whoever does ask: the checker reads a field of `Ring1[T]` in a generic
body, and ownership reads the finished pool, which it cannot write to.

## Decision

**An instantiation whose arguments hold a type parameter or an unsettled
reference is minted with its parts unwritten, and they are written the first
time something reads them.** A ground instantiation is written as it is
minted, as before, because lowering lays out every one it reaches.

- `Instance.parts` records whether the parts are written, and
  `Builder.fillInstance` is the one routine that writes them: for a ground
  instantiation as it is minted, for an unwritten one on first need, and for
  every written one when `refillInstances` copies the completed templates
  again. An unwritten one is not refilled; it copies its template when read.
- Writing an instantiation writes every unwritten one among its parts —
  fields, payloads, array elements, newtype bases, closure environments and
  observed referents — so a written type holds only written types. A layout, a
  cycle walk or a copyability check follows parts and never arguments, so it
  meets no unwritten type.
- The builder's part accessors (`fieldType`, `lookupField`,
  `variantFieldCount`, `variantFieldType`) write an unwritten type before they
  answer, and so do its capability, dependency and writer queries.
- The capability, dependency and writer tables record a type's edges once its
  parts are written. A recorded type holding an unwritten one leaves it for the
  builder to write before the facts are read; in the writer table, whose edges
  include every argument, an unwritten instantiation records its arguments
  instead, and an argument holding a parameter settles it without its parts.
- Before the checker hands the pool on, `fillMinted` writes every
  instantiation it minted. What stays unwritten is only what those writes mint
  as arguments, which no recorded type holds. The finished pool refuses a read
  of an unwritten type's parts, its layout or its capability as a compiler
  defect, and the walks over every pool entry pass over one.

## Consequences

A program pays to write an instantiation's parts only where something reads
them, so the ring above costs its size rather than its square, and the
`generic structures holding one another` sweep dimension holds that.

What an instantiation holds is no longer a fact of the pool the moment it is
minted. A reader in the checker must ask through a builder accessor, and the
accessors became fallible, because writing parts allocates. A reader holding a
slice into the builder's lists across such a call holds a slice that may move,
which is the rule for every builder call that mints and now covers part reads
too.

Three walks over the finished pool name the unwritten case: lowering lays one
out empty, since no lowered value has a type holding a parameter, and the
layout oracle and the corpus-coverage tally pass over one.

Proving a structural derive is a separate cost this does not change. A derived
`Settle` for `RingK[X]` asks whether each component is `Settle`, which asks it
of `RingK+1[X]` at the same parameter, so every declaration's derive still
reaches every structure in the ring: the written parts are no longer the
quadratic, the proofs are.

## Alternatives considered

**Write every instantiation at minting, and make the refill cheaper.** The
refills were the larger constant, but the instantiations themselves are
quadratic, and every walk over the pool pays for each of them.

**Answer a symbolic instantiation's questions from its template.** A field of
`Ring1[X0]` is `Ring1`'s field with `X0` for `X`, so a reader could substitute
on every read instead of storing the copy. Every reader would then carry the
substitution, and the finished pool's readers cannot mint the types a
substitution produces.

**Write unwritten instantiations only at the checker's hand-off, reading
templates until then.** It moves the same substitution into every checker
reader, and the copyability and layout walks would need a second path for a
type with no parts yet.
