# 172. An array reports its length

Status: Accepted — 2026-09-25

Extends [0061](0061-an-array-is-a-value-of-a-fixed-size-type.md),
[0083](0083-an-arrays-length-is-part-of-its-type-everywhere-it-is-written.md)
and [0137](0137-arrays-expose-checked-borrowed-slices.md).

## Context

An array's count is part of its type, but a program could read it only as
`values.as_slice().length()`. That builds a borrowed view to ask a question the
type already answers, needs a stable place, so a temporary array cannot answer
it at all, and is never a constant expression. A table whose length is inferred
with `[T; _]` then has no way to size a parallel table from it:
`let open_days: [Bool; weekday_names.length()]` was not expressible, so the
count had to be written again.

## Decision

**`values.length()` on any array, or on an observation of one, is a `UInt64`
holding the count of the array's type.** It takes no arguments and no mutable
invocation marker. The receiver is read, not consumed or borrowed past the
call, and it is still evaluated, so its effects happen in order; the result
depends on the receiver's type alone.

Typing recognizes the call as it recognizes `as_slice()`: a postfix call named
`length` whose receiver is an array through any number of observations records
a `NormalizedCall` with target `.array_length`, the receiver adjustment, and a
read parameter with no contract. Ownership reads that call like any other.
Lowering evaluates the receiver and yields the type's count as a constant.

**A length call is a constant expression when its receiver is a constant
expression whose value is an array.** The folder shared by resolution and
checking counts the elements of the folded array, so `weekday_names.length()`
folds to 7 wherever an array length, constant or default reads it, in any
declaration order. Any other receiver leaves the call outside the definition:
a call, a `var`, a parameter, an index, text or a record.

## Consequences

- `[Bool; weekday_names.length()]` sizes one table from another, and
  `let days = weekday_names.length()` is a constant.
- Loops over an array can bound themselves with `values.length()` instead of
  a written count or a slice view.
- A temporary array answers `length()` as a constant, where `as_slice()`
  borrows it as a temporary of its statement.
- Cost: one call record per length call; folding counts one already-folded
  array, so it adds no walk.

## Alternatives considered

**Admit any receiver of array type as a constant expression**, since the type
fixes the count. The folder runs over the tree before and during checking, and
resolution folds lengths before any expression has a type, so the two folds
could not agree about a receiver the tree alone does not settle. Reading the
count from the folded value keeps one folder answering both. A receiver whose
evaluation has effects would also have to be skipped in a constant context,
which makes the same call evaluate its receiver in one position and not in
another.

**Forward every `Slice` operation to arrays through the view.** Rejected for the
reasons ADR 0166 gives for forwarding traits: arrays would acquire an
open-ended set of operations, and none of them would be constant expressions.
