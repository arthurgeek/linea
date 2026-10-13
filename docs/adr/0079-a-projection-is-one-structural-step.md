# 79. A projection is one structural step for the termination measure

Status: Accepted — 2026-08-11

## Context

`[T-PolyRec]` makes the set of instantiations a program reaches finite by
refusing an argument that puts the declaration's own type parameter beneath a
type constructor: `f[T]` calling `f[Wrap[T]]` grows, and a part is held to the
same measure as a call. Every argument the measure had ever seen was either a
parameter exactly, or a written type built out of constructors it could walk.

A settled reference off a type parameter — `S.Next` — was neither, and until
this milestone it did not have to be. A reference was a head and one name, so
the only thing that could be selected from was the head, and a chain could not
be written at all. Nothing stopped a chain from growing because nothing could
write one.

Bounds on a declared type
remove that limit: a projection is admissible wherever the type it is selected
from carries a bound declaring the name, so `type Next: Step` makes `S.Next`
itself a type that `Next` can be selected from, and a chain grows one segment
per selection. **What the two-segment limit was silently supplying was a
termination argument nobody had written down**, and lifting it without counting
projections removed a guarantee the compiler had been relying on without
stating.

That is not a hypothetical. At the commit that lifted the limit and before this
rule was implemented, both

```linea
struct Chain[S: Step] { rest: Chain[S.Next] }
```

and a mutually recursive variant through a second declaration —
`Left[S]` holding a `Right[S.Next]`, `Right[S]` holding a `Left[S]` — killed the
compiler by signal, exit status 134, with three thousand frames of
`instantiate` → `substitute` → `fillInstance` on the stack. Each level minted a
type one projection deeper than the last and the walk never reached a fixed
point. Both are refused with `[T-PolyRec]` now.

## Decision

**A settled reference contributes one structural step to the `[T-PolyRec]`
measure.** An argument that selects a name off the declaration's own type
parameter puts that parameter beneath a type-level operation, exactly as a
constructor does, so `walk[S]` calling `walk[S.Next]` is refused and
`struct Chain[S: Step] { rest: Chain[S.Next] }` is refused for the same reason.
A run of selections is a step per segment, and no length is admissible that one
selection is not.

**A projection is not a type constructor, and this is the only place it is
treated as one.** A constructor is larger than what it wraps; a projection
stands for whatever an implementation settled, which may be smaller than the
type it was selected from, or the same type. The measure counts it as one
opaque step regardless, because the step it is counting is the selection itself
rather than the type that comes out of it.

**The checker does not read what a projection settles to.** `walk[S]` calling
`walk[S.Next]` is refused where every implementation in the program settles
`Next` to a type that would end the chain after one step. `[T-PolyRec]` is a
structural approximation of termination and stays one.

## Consequences

**A program that would in fact terminate can be refused.** A trait whose
implementations all settle `Next` to themselves describes a chain that closes
immediately, and a recursive call through `S.Next` is ill-formed anyway. This is
the same conservatism the rule already has for `f[Wrap[T]]` where the recursion
would bottom out, and the way out is the same: pass the parameter itself and let
the operation return the projection.

**Depth is not a defence.** Because one selection already grows the measure, a
chain of two is refused by the same test rather than by a second one, and a
future feature that produces projections inherits the rule by producing them.

**The measure now walks through a construct whose contents it does not
interpret.** What a projection says about a declaration's type parameters is
whatever the type it was selected from says, asked recursively; what an
implementation settles it to is deliberately unreachable from there.

**Inference and the measure ask different questions at a projection, and the one
walk that answers both is told which.** Nothing can be matched *into* a
projection — `T.Item` handed a `UInt8` says nothing about `T` — so inference
stops where the measure walks on. Both are the same traversal with the same
answer everywhere else, which is why they are one function with a parameter and
not two functions.

## Alternatives considered

**A projection is stationary for the measure** — treat `S.Next` as no larger
than `S`, on the argument that a projection is a lookup rather than a
construction. Nothing then bounds the chain, and the program the compiler
accepts is one it cannot compile: this is precisely the state measured above,
where lowering minted a type per level until the stack ran out. A rule whose
failure mode is a signal with no diagnostic is
[0013](0013-no-undefined-behaviour.md)'s and
[0003](0003-infallible-frontend.md)'s failure at once.

**A separate depth limit on instantiation** — count levels while lowering and
report past some number. It bounds the compiler rather than the language: the
number is unprincipled, a program's acceptance would depend on it, and the same
program would be refused at a depth chosen by whoever picked the constant. This
milestone removed exactly that shape of limit from settled references; replacing
it with another one a level down would be trading a stated rule for an
unstated number.

**Look through the projection to what it settles to** — accept `walk[S.Next]`
where every implementation settles `Next` to something that ends the chain. This
makes `[T-PolyRec]` an evaluator of declared types: it would have to enumerate
the implementations admissible for the bound, follow each settlement, and detect
a cycle among them — which is a larger feature than associated types are,
arriving unannounced inside a milestone about bounds. It also decides a call's
admissibility from implementations written elsewhere in the program, so adding
an implementation could make an existing generic function ill-formed, which is
the property trait resolution is otherwise built to avoid.
