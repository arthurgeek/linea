# 82. A comparison is a call on the trait it names

Status: Accepted — 2026-08-13; extended by ADR 0112

Extended by [0138](0138-hash-maps-preserve-entry-ownership.md) for hash-map key and ownership contracts.

## Context

`<` was a rule of the checker rather than an operation of a type. It admitted
the nine primitives and refused everything else, under a rule of its own —
`[T-Compare]` — and there was no way for a type to say how it ordered. So a
generic body could not compare what it held, `Range` could not iterate, and a
sort had nothing to sort by.

Two rules were already in place and pointed the other way. `[T-Bound]` is how a
type says it answers an operation, and an implementation is how it says what
the answer is; nothing about a comparison made it a different kind of question.
What kept it separate was that the primitives cannot answer it in Linea — a
`less` for `Int64` written with `<` is `Comparable.less` calling itself — so
the operators had to keep an implementation the language does not spell.

## Decision

**Each of the six comparison operators is a call on a trait `std` declares.**

| written | means |
| --- | --- |
| `a == b` | `Equatable.equals(a, b)` |
| `a != b` | `!Equatable.equals(a, b)` |
| `a < b` | `Comparable.less(a, b)` |
| `a > b` | `Comparable.less(b, a)` |
| `a <= b` | `Comparable.less(a, b) \|\| Equatable.equals(a, b)` |
| `a >= b` | `Comparable.less(b, a) \|\| Equatable.equals(a, b)` |

The desugar is in the checker and in lowering, not in the parser: the tree
holds what was written, so a formatter reproduces the operator and an editor
points at it.

**Five traits, two of which declare no members.**

```linea
pub trait Equatable {
    fn equals(read self: Self, read other: Self) -> Bool
}

pub trait Equivalent: Equatable {}

pub trait Comparable: Equatable {
    fn less(read self: Self, read other: Self) -> Bool
}

pub trait Ordered: Comparable + Equivalent {}

pub trait Steppable {
    fn forward(read self: Self) -> Self
}
```

`Comparable` is a **strict partial order** by decision: a pair may be ordered
by neither `less` nor `equals`, and `less(x, x)` is false for every `x`. The
decision belongs to the float milestone, which is the only thing in the
language that needs a partial one, and is settled here so nothing has to widen
later. `Ordered` and `Equivalent` are what a type promises beyond it —
trichotomy and a reflexive equality — and each is a promise about the two
operations rather than an operation of its own, which is why neither declares a
member.

**`<=` and `>=` are an order *or* an equality, never the negation of the
swap.** `||` short-circuits, so `equals` is reached exactly where `less`
answered false. Over a partial order `!less(b, a)` answers true for a pair
related neither way, where all four of `<`, `<=`, `>`, `>=` must be false.

**One `less` and one `equals` per type, and no comparison trait takes a type
argument.** No trait declares a second ordering member and no marker declares a
member of any kind, so an implementation has nothing to disagree with. The
absent type argument is load-bearing beyond spelling: the checker's demand and
lowering's lookup are the two questions this index answers — whether a trait is
implemented at all, and which row a call runs — and they agree on a trait
taking no arguments because the first ignores arguments and the second requires
them to match.

**A trait may require other traits, written as a `+`-separated list after its
name, and a bound naming a trait carries what that trait requires,
transitively.** `Comparable: Equatable` is discharged where the implementation
is written and read where a body is bounded, so `fn f[T: Ordered]` may call
`Comparable.less`. A trait's bounds may not cycle.

**The primitives' implementations are the compiler's.** The resolver seeds a
row per trait and primitive beside the ambient bindings it already seeds — nine
`Equatable`, nine `Equivalent`, eight `Comparable`, eight `Ordered`, eight
`Steppable` in this tree, `Bool` carrying the two that do not order — and they
are found through the one index a written implementation is found through, so a
bound is discharged the same way. Lowering emits the comparison instruction for
such a row rather than a call, which is what keeps `while i < n` one
instruction with no inliner in the pipeline.

**`[T-Compare]` is gone.** The refusal it named is now a type failing to
implement the trait its operator names, which is `[T-Bound]` and reads the same
as every other unmet bound. The rule count moved from 94 to 93.

## Consequences

**A user type is compared with the operators.** `impl Comparable for Mark`
makes `a < b` legal, and `a <= b` on it is two calls and a branch rather than
one instruction. That cost is the decision: there is no inliner in this
pipeline and `qbe` does not inline, so a call written here is a call executed.

**No integer program changed meaning.** Over a total order
`less(a, b) || equals(a, b)` and `!less(b, a)` agree, and both lower to one
instruction for a primitive.

**`Bool` is findable and unordered.** It carries `Equatable` and `Equivalent`
and neither `Comparable` nor `Ordered`, which is the pair that makes the second
marker load-bearing: an algorithm that only needs to recognise a value it was
handed bounds on `Equivalent` and admits `Bool`.

**`std` gained implementations for its own types.** `Str` compares by its
bytes — equality byte for byte, order lexicographic with a prefix preceding
what extends it — and `Option` through generic heads bounded on what it holds,
with `None` preceding every `Some`. That ordering is stated rather than left to
whoever writes it, because either would be defensible and only one can be the
answer.

**The prelude's re-exports are the order the library is declared in.** `cmp`
now re-exports ahead of `option`, because `option` writes implementations of
the traits `cmp` declares. A module naming a trait is declared after the module
declaring it, and the manifest is where that order is written.

**A row the compiler provides is implemented once, like every other.** No
program outside the standard library can write one for a primitive — a
primitive is declared by no module, so a head naming one owns neither side and
is `[M-Impl]`. The trait's own module owns the other side and may write the
head, and what it would write there is already implemented: the resolver
records the rows it seeds, coherence holds every written header against them,
and `impl Equatable for Int64` added to `std/cmp/cmp.lin` is `[N-Duplicate]`
reported at the header. Otherwise the written body would lose to the
instruction with nothing said, which is a body the library's own author cannot
see is dead.

The record the checker reads is that same one. Which prelude declaration each
of these traits is, is decided where the prelude is settled and read from there,
so a row the checker turns into an implementation is a row a header was held
against — deciding it twice from the spellings is what would let the two drift
apart again.

## Alternatives considered

**Leave `<` built in and put a trait beside it.** Two ways to compare, free to
disagree, which is the drift every demonstrated defect in this compiler has
been. It also arrives through a back door if a type is refused the traits and
keeps its operators, which is why the traits cover every type the operators do
even where the order is partial.

**Desugar fully and add an inliner.** A representation or a pass is introduced
when a named problem demands one, and this would be that problem — but it is a
milestone about a pass, and every comparison on a user type stays a call until
it lands.

**`<=` as the negation of the swap.** Cheaper by a call on a user type and
wrong wherever a pair is ordered by neither `less` nor `equals`: the negation
yields true where all four operators must be false. For a total order the two
agree, which is why nothing over the primitives can tell them apart and why the
difference has to be decided here rather than observed.

**One marker instead of two.** `Ordered` alone leaves a reflexive equality
reachable only through an order, so `Bool` — which has no order by decision —
could never carry it, and neither could a structure whose author declined to
invent one.

**Derive equality from what a type holds.** A structure whose fields are all
equatable becoming equatable without saying so. What identity means for a type
is the author's to say, and a derived answer is one the author never wrote and
cannot see at the place it is wrong.
