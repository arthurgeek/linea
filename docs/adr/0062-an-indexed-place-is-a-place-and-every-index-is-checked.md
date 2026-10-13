# 62. An indexed place is a place, and every index is checked

Status: Accepted — 2026-08-02. Bracket clause, never implemented, replaced by
[0181](0181-a-call-may-name-its-type-arguments.md).

## Context

`a[i]` has to answer two questions that a field selection already answers, and
one it does not.

The two it shares: what does `a[i]` *name*, and how is its address computed.
`o.f` names a place — it can be assigned to, marked with `&`, and moved
through — and `placeAddress` computes its address as the root's address plus a
constant offset. An index is the same shape with a computed offset.

The one it does not share: `o.f` cannot fail. The field exists because the type
says so, and the offset is a constant the compiler chose. `a[i]` can be handed
an `i` no element sits at, and
[0013](0013-no-undefined-behaviour.md) forbids the result being undefined.

## Decision

**`a[i]` is a place, reached by a path exactly as `o.f` is, and every index is
bounds-checked with a trap on violation.**

### A place, not a value

The path an ownership place already carries — a root binding and a depth —
gains an index component. `a[i] = e` is an assignment to a place, `&a[i]` is a
marked place, and `a[i]` in a reading position is a load through the place's
address. The ownership pass sees a `Place` with the same root it already sees,
so `[O-Move]`'s existing answer for a partial move — *move the whole binding, or
`copy` this part out of it* — covers `sink f(a[i])` with no new rule.

Lowering computes the address as `base + i × stride`, where `field_addr`
already computes `base + constant`. One instruction generalises: the offset
operand becomes an arbitrary value rather than a constant, which it was already
typed to be.

### Checked, always, and it traps

The check is `i < N`, emitted before the address is computed, and its failure is
a trap of a new kind. It is **not** removable by an optimisation level, because
0013 makes the presence of a defined result independent of one.

`N` is in the type, so the bound is a constant and the comparison is against a
constant. Where the index is itself a constant expression, the comparison folds
and the check disappears — that is constant folding producing a defined result
early, not an unchecked access.

**A statically-known out-of-range index is a diagnosed error, not a trap.**
`a[9]` on a `[u8; 4]` is refused by `[T-Index]` at compile time. The two are not
in tension: 0020 makes "is this a constant expression" a syntactic question, so
which indices are refused at compile time never depends on analysis quality, and
one that is not refused is checked at run time.

## Consequences

**A new trap kind, and the runtime interface moves.** `TrapKind` is a numbering
the runtime shares, so `index_out_of_bounds` is appended and never renumbered,
and `runtime/linea_rt.c` carries a matching entry. The reserved slots that
already exist are what makes this an append rather than a break.

**The bracket is decided by what the name means, not by the grammar.**
`f[x]` is an instantiation where `f` names a declaration and an index where it
names a value. One symbol space and a resolver that decides — which the generics
design already committed to for types, and which now has to hold in expression
position. That is a resolution question, not a parse one: the parser records a
bracketed form and the resolver classifies it, the same division `p.x` already
uses.

**Indexing is not yet a trait.** R1 wires `[]` to arrays directly. R3 makes it
a blessed trait whose member is a projecting one, and the arrays case becomes
an implementation. This record does not decide that; it decides that whatever
`[]` reaches, it reaches a *place* and it is checked.

## Alternatives considered

**An unchecked index, with a checked one behind a function.** The fastest thing,
and what C gives. Rejected by 0013 outright: an index outside an array would
have no defined result, and the language does not have a category for that.

**Checked, but elidable at higher optimisation levels.** Rejected for the same
reason and a sharper one — 0013 says which of "defined result" or "diagnosed
error" happens must not depend on the optimisation level. A check that
disappears at `-O2` makes the language's meaning a build flag.

**A value rather than a place.** `a[i]` yielding a copy would need no path
extension and no place machinery. Rejected because `a[i] = e` and `&a[i]` are
the point: a container you cannot write into through the bracket is a container
that needs a second, uglier way in. It would also make an element of a Linear
array unreachable, since copying one is what `[O-LinearCopy]` refuses.

**A bespoke `subscript` keyword.** Rejected as a one-off. The projecting-member
kind is needed anyway for R3, and wiring `[]` to a trait is how the same
machinery serves arrays and every user container. A keyword would be a second
mechanism for the thing the trait does.

## Deliberately open

**Whether the check can be proven away.** A loop whose bound is the array's
length performs a comparison per iteration that is provably true. Eliminating it
is an optimisation over MIR that must not change which programs are defined —
so it is sound only where it removes a check that could never have failed. The
question that settles it is whether MIR ever gains a pass at all; today it has
none, and a redundant comparison is the price of that.

**Negative and wide indices.** An index of a signed type, or one wider than the
address space, needs a rule for what the comparison compares. R1 admits
`UInt64` and anything that converts to it, which is the narrow answer; whether a
signed index is a `[T-Index]` or a run-time trap is open.
