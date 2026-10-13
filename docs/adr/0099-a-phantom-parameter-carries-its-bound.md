# 99. A phantom parameter carries its bound

Status: Accepted — 2026-08-21; supersedes the bound clause of
[0065](0065-a-phantom-type-parameter-is-declared.md), which stands in every
other respect.

## Context

0065 established `phantom`, and refused a bound on one:

> **A phantom parameter takes no bound.** A bound constrains what an argument
> may be, and nothing about a type that appears nowhere can be constrained — a
> vacuous bound is the same mistake as a vacuous modifier.

The allocator work is the first declaration that wants one. A buffer names the
allocator that produced it so that disposal through another kind is a type
error, and the parameter is phantom because the name costs no field and no
word. Written out, the type it wants is

```linea
opaque linear struct Buffer[phantom A: Allocator]
```

and what 0065 leaves instead is `Buffer[phantom A]`, which admits

```linea
Buffer[UInt8]
```

as a type any program may write. Nothing inhabits it — `Buffer` is `opaque`,
so only its own module builds one, and the only constructor is a trait method
whose `Self` is an implementor. But that is a fact about another module's
construction discipline rather than about the type, and a reader who asks what
`A` must be finds the declaration silent.

## Decision

**A phantom parameter may carry bounds.** They constrain the argument at
instantiation, exactly as any other parameter's do.

The clause this supersedes rests on a step that does not follow. *"Nothing
about a type that appears nowhere can be constrained"* is true of the **value**
— there is no field holding it, so nothing inspects it at run time. A bound is
not an inspection. It is a condition on which types may stand as the argument,
settled where the argument is written, before any value exists. Representation
and well-formedness are separate questions, and `phantom` answers only the
first.

That the two are separate is visible in what the compiler already did. The
bound was parsed, recorded, and **discharged** — `[T-Bound]` reported an
argument failing the bound of a phantom parameter, beside the refusal that said
the bound could not be written. One rule said the declaration was meaningless
while another was busy enforcing it.

## Consequences

`Buffer[UInt8]` becomes a type nobody can write, rather than a type nobody can
inhabit. The parameter still contributes no field, no word and no obligation,
because `phantom` decides that and nothing here moves it.

0065's own example gains the same expressiveness. `Handle[DocTag]` against
`Handle[AstTag]` is provenance, and provenance is worth as much as the set of
tags is constrained: a tag parameter admitting any type at all admits
`Handle[UInt8]`, which claims a provenance nothing gave it.

**One thing this does not reach.** `Buffer[phantom A: Allocator]` is not yet
what `std.mem` writes, because the trait declares `Buffer[Self]` in its own
signatures and `Self` is not known to satisfy the trait it is declared in —
true by construction, and not something the checker records. Until it does,
`Buffer` keeps an unbounded parameter. That is a gap in what a bound can be
discharged by, not a reason to refuse the bound.

## Alternatives considered

**Leave the prohibition and document the wart.** The semantics would distinguish a
well-formed type from an inhabited one, and a reader would learn that `A` is
constrained by a discipline held elsewhere. That is a true sentence about a
type system that could have said it directly, and it leaves the language unable
to express a constraint it already checks.

**Spell it `A: phantom`.** Rejected by 0065 and still rejected: the position
after the colon is where a bound goes, and putting a statement about *how a
parameter is used* there would collide with the statement about *what its
argument must be*. With bounds admitted, `phantom A: Allocator` reads as the
modifier it is followed by the bound it carries, and the collision 0065 feared
is what the two spellings avoid.
