# 146. Payload-free variants are constant expressions

Status: Accepted — 2026-09-22. Extends the constant-expression domain of
[0020](0020-a-constant-expression-is-defined.md), the shared value table of
[0059](0059-one-table-answers-both-questions-about-a-constant-expression.md) and
the typed value representation of
[0127](0127-constants-retain-distinct-values-and-infer-their-types.md), and
admits payload-free variants into the aggregate domain of
[0140](0140-aggregate-constants-retain-checked-construction-plans.md). Refines
the default clause of
[0077](0077-arguments-match-by-name-and-evaluate-by-declaration.md) and the
construction sites of [0033](0033-sealing-is-checked-not-omitted.md).

## Context

Atomic saving had two entry points because its permission choice could not be a
default: `save_atomic` forwarded to `save_atomic_with_permissions(..., .Preserve)`.
`SavePermissions.Preserve` carries nothing and is fully known where it is
written, yet the constant-expression definition listed only integers, truth
values and text, so `permissions: SavePermissions = .Preserve` was refused by
[T-Default]. Every enum-valued option faced the same choice between a wrapper
and a required argument.

Admitting variants raises four questions the existing domain never had to
answer. A contextual `.Preserve` has no meaning until an expected enum selects
it, and implementation coherence compares callable-type defaults before type
checking runs. The same ordinal in two enums must not be one value. A variant is
a value of a user-defined type, so it can carry an ownership obligation and can
be sealed. And a generic enum's variant has a type only once its instantiation
is known.

## Decision

**A payload-free variant is a constant expression.** Qualified (`Mode.Preserve`)
and contextual (`.Preserve`) references qualify, as do parentheses around them
and immutable aliases to them. A payload-bearing sibling does not matter. A
variant built with constant payloads is an enum construction under 0140; a
payload variant named without its payload is not a value, and the checker
refuses it. No evaluation is added: the value is a selection, not a computation.

**The value is the variant's name in the constant graph; the type is the enum.**
A variant is a node of 0140's interned graph holding its name and payloads, so
a payload-free variant is that node with no payloads. The enum, and a generic
enum's instantiation, is the type the checker records for the constant, the
parameter or the callable parameter holding the value, exactly as 0127 keeps an
integer's width in the type tables. Every consumer reads the pair: callable
interning keys each parameter by type and default together, coherence compares
the written parameter types before the defaults, and lowering materializes the
value through the checked construction plan, which retains the ordinal the
checker selected at the parameter's type. So `First.Preserve` and
`Second.Preserve` are distinct typed values although both nodes spell
`Preserve`. A variant is never a number; it supplies no count and takes no
arithmetic or conversion.

**Selection happens once, in the checker.** The folder needs no selection: a
contextual `.Preserve` folds to the node named `Preserve` before any type is
known, which is all coherence and callable identity compare alongside the
written parameter type. Resolution records a qualified selection in
`variant_ordinals`, as before, and the checker selects a contextual variant
against the expected type and records it in `variant_uses`. A later use never
retypes a constant, and an unannotated constant cannot take a contextual
variant.

**A constant's type must be discardable.** A constant is built afresh wherever
it is read and a default wherever it is omitted; nothing at that point takes
ownership. A type owing settlement — a `linear` enum, or an enum whose payload
propagates an obligation even when the selected variant carries none — would
create a value nothing can discharge. [T-Const] and [T-Default] refuse it,
using the ordinary capability query. Copyability is not required: fresh
construction is not duplication, and a payload-free variant stores nothing.
0140's Copyable requirement therefore does not apply to it.

**A default's type is concrete.** 0077 already refuses a default whose type is a
type parameter. A type mentioning one, such as `Choice[T]`, is equally unsettled
at the declaration, so [T-Default] refuses it too.

**Naming a sealed payload-free variant builds it.** `.Closed` and `a.Door.Closed`
construct a value of a sealed type exactly as `.Forged(7)` does, so [M-Opaque]
applies to both forms outside the declaring module, including in a constant or a
callable-type default.

**Materialization reuses enum construction.** An omitted argument and a read of
a named enum constant lower through the same routine that builds a written
variant, so a register-sized enum becomes its tag and an enum with a payload
sibling gets its aggregate layout.

`save_atomic` now takes a final `permissions: SavePermissions = .Preserve`, and
`save_atomic_with_permissions` is removed.

## Consequences

`fn save(permissions: SavePermissions = .Preserve)` and
`let fallback: Mode = .Preserve` are ordinary. Writing the variant at a call and
omitting the argument remain the same program.

A variant constant appears in callable type names and generated closure
renderings as `.Preserve`, rendered from the graph node by the one routine that
renders every constant; symbol mangling uses the graph's compact encoding.

## Alternatives considered

- **Store the enum declaration in the value.** It would make the value compare
  correctly on its own, but it still would not tell `Choice[UInt8]` from
  `Choice[Int8]`, so the type tables would remain the authority. It would also
  put a declaration ID into callable parameters and default tables that
  checked-library relocation keeps fixed today, and it would duplicate the
  type system inside the value tag, which 0127 rejected for integers.
- **Hold the declaration-order ordinal in the value.** An ordinal has no
  meaning until an enum is known, so a contextual `.Preserve` in a callable-type
  default would need resolution to select its enum before checking, through a
  second selection table. A node named by the variant needs no selection until
  the checker plans its materialization in a concrete type, and a variant with
  payloads needs the graph regardless.
- **Re-fold after checking, discarding earlier `not_constant` answers.** Two
  answers for one expression at two times is the drift this compiler guards
  against; the early answer would still have shaped coherence.
- **Admit every variant and let the payload be absent.** A payload variant named
  bare has no payload to materialize; making it a constant would build a value
  whose payload was never written.
- **Admit linear constants and settle them at the use.** Every constant
  reference, field selection, parenthesis and early exit would need an ownership
  operation, and a default would construct an owned value invisibly — the
  implicit construction 0077 refuses for `sink` defaults.
- **A filesystem-specific default.** A sentinel permission value or an overload
  would solve one API and leave the next enum option with the same wrapper.
