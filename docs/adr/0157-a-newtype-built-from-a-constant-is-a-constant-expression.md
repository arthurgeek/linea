# 157. A newtype built from a constant is a constant expression

Status: Accepted — 2026-09-23. Extends the constant-expression domain of
[0020](0020-a-constant-expression-is-defined.md), the typed value
representation of
[0127](0127-constants-retain-distinct-values-and-infer-their-types.md) and the
construction plans of
[0140](0140-aggregate-constants-retain-checked-construction-plans.md).

## Context

`std.net.listen` takes a backlog the runtime accepts in `0..=4096`. The
library admits `1..=4096`, because a backlog of 0 lets some systems refuse a
connection that arrives before `accept` is called. The type that says so is a
refined newtype, `type Backlog = UInt64 where it in 1..=4096`, and the natural
signature gives it a default:
`backlog: Backlog = Backlog(128)`. That was refused by [T-Default], and
`let cap: Percent = Percent(50)` at module scope by [T-Const]: the definition
listed conversions into primitives but not constructions of newtypes, so a
library had to choose between a bare integer that documents nothing and a
required argument nobody wants to write.

The construction needs nothing new to be evaluated. `Percent(50)` holds the
value its operand holds, and [T-Refine] already proves at the construction
whether a known value is in range. What was missing is only the folder's
classification of the call.

The folder runs at two times. Resolution folds array lengths and callable-type
defaults before any type exists, to key implementations; the checker folds
constants and defaults afterwards. A refinement's bounds are a property of the
checked type, so they do not exist when resolution folds.

## Decision

**A newtype construction of a constant expression is a constant expression.**
`Name(e)` qualifies when `e` is a constant expression of the base type, whether
`Name` is refined or not and whether it is named bare or through its module.
Its value is the operand's value; the newtype is the type the checker records
for the constant or parameter holding it, as 0127 keeps an integer's width in
the type tables. The fallible form `Name?(e)` produces an `Option` whose
contents are decided at run time, so it remains outside the domain.

**The range is proven where the construction is checked, by the routine that
proves every construction.** The folder answers "a call on this callee
constructs a newtype" from the same predicate the checker uses to decide that a
call is a construction, and folds the operand through unchanged. It does not
consult the refinement. The checker type checks every constant initializer and
every default before it reads the fold, and that check is where
`dischargeRefinement` refuses `Percent(150)` with
`150 is not in 0..=100 for Percent`. A refused construction poisons the
expression, so it is not reported a second time as a non-constant. Putting a
second bounds check in the folder would be a second answer to whether a value
is in range, available only to one of the folder's two callers.

**The newtype must be Copyable.** Each read of a constant builds its value
afresh. An affine newtype, which is what a newtype is unless declared
`copyable`, may stand for something that must not be duplicated, so a constant
of one is refused by [T-Const] exactly as an affine structure literal is under
0140. The check lives in the construction plan: a newtype's plan is its base's
plan under a Copyable newtype, so a newtype nested inside a record or a
variant payload is held to the same rule.

**A newtype's constant is not a number.** It folds to the integer it holds but
has its own type, which has no arithmetic and supplies no count. An array
length written with one is refused by [T-ArraySize], as it is when the length
is not constant at all.

**Lowering erases the name.** A materialized constant is built at its
representation, the way a newtype construction already lowers to its operand,
so no plan is recorded under the newtype and no backend sees one.

## Consequences

`net.listen(address)` listens with a backlog of 128, and a caller supplying one
writes `backlog: net.Backlog(1024)`; a known value outside the range is refused
where it is written. Any library can give a refined parameter a default or
publish a refined constant.

Resolution now treats a newtype construction in a callable-type default or an
array length as a folded value. Both remain subject to the checker, which
refuses an out-of-range construction or a newtype length.

## Alternatives considered

- **A bare integer parameter.** It restates the range in a comment and makes
  the runtime the only place a bad backlog is reported.
- **Check the refinement in the folder.** The bounds do not exist when
  resolution folds, and passing them in would give the folder a second range
  check beside `dischargeRefinement`.
- **Admit affine newtypes.** A constant read twice would duplicate a value its
  type says is unique.
- **Admit the fallible form.** Its value is an `Option` decided by a run-time
  comparison in the general case; admitting only the foldable instances would
  make constancy depend on what the compiler proved.
