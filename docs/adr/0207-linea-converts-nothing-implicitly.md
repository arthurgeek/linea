# 207. Linea converts nothing implicitly

Status: Accepted — 2026-10-05; collects a position the language already
holds in several records and says what none of them decides.
Extends [0018](0018-the-integer-model.md) and
[0061](0061-an-array-is-a-value-of-a-fixed-size-type.md).

## Context

A reviewer proposed that a `String[A]` argument be accepted where a `Str` is
read, as Rust accepts `&String` for `&str`. The refusal was defended by citing
[0148](0148-parameter-heads-match-complete-trait-keys.md) and the 2026-09-09
affine-default design. Neither decides it, and the policy deserves a record
that says so, because a position cited through records that do not say it is a
position that cannot be argued with on its merits.

What each source says, read in full:

- [0148](0148-parameter-heads-match-complete-trait-keys.md) (the `From`/`Into`
  adoption): "There is no automatic reverse conversion, identity bridge,
  assignment coercion, error conversion through `?`, or conversion-specific
  compiler dispatch." It scopes what that adoption adds. It also shows the
  list is not permanent: `?` converting through `From` was on it and was
  added by [0162](0162-question-mark-converts-an-error-through-from.md).
- The affine-default design: "Writable stored observations and arbitrary
  implicit argument coercions are not introduced by this design." Scoped to
  that design.
- The semantics sentence "There is no implicit conversion from `borrow T` to
  `T`" (in the read-only observations section) concerns `borrow`, not text.

What is decided elsewhere, and consistent with each other: integers convert
only explicitly ([0018](0018-the-integer-model.md), with literals typed by
their uses in [0152](0152-an-integer-literals-type-is-settled-by-its-uses.md));
floats and integers never convert implicitly; arrays of different lengths are
different types with no coercion
([0061](0061-an-array-is-a-value-of-a-fixed-size-type.md)); an alias is the same
type, so nothing converts
([0194](0194-an-alias-names-a-type-that-exists.md)); and `?` converts an error
through a trait the programmer implemented, visible at the implementation
([0162](0162-question-mark-converts-an-error-through-from.md)).

## Decision

**A value's type changes only where the source writes the change.** Linea has
no implicit conversion between types: no numeric widening, no array to slice,
no `String[A]` to `Str`, no conversion selected by the receiving position, and
no blanket `From` or `Into` the compiler applies on its own. A conversion is a
call (`.view()`, `Int64(x)`, `.into()`, `From.from`), or the one place a rule
names the trait that runs and the program implements it (`?` through `From`).

This record decides the policy and nothing about any single conversion's
merits beyond the list below. It does not decide:

- the library answer below, which gives `String` the read-only `Str`
  operations and `String == Str`, and leaves the policy untouched;
- whether a trait such as `From` gains blanket implementations when
  coherence can read `where` bounds
  ([0184](0184-a-failure-holding-an-owned-value-settles-to-its-reason.md) defers
  that for mechanics, not principle).

## Consequences

- `.view()` marks where a borrow begins, which the ownership reader relies on
  when a result carries from it ([O-Borrow]). A coercion would hide that origin.
- The language is uniform to teach: nothing is converted for you.
- `.view()` appears in 35 example lines and 344 in std (counted 2026-10-05).
  That is the price, and the evidence for the reopening test below.

## Alternatives considered

**Coerce `String[A]` to `Str` in read positions.** The conversion is total,
free and lossless, and
[0175](0175-a-borrowed-temporary-lives-until-the-end-of-its-statement.md) gives
a borrowed temporary the lifetime of its statement. Rejected on four counts.
(1) It does not reach the places it is wanted: `testing.assert_eq[T]` infers
`T = String`, so at least 11 of the 35 example `.view()` sites are such
arguments and the language would behave one way for `append` and another for
`assert_eq`, which is less uniform, not more. (2) A coercion hides the origin
of a borrow where the result carries from the argument (`trim`, `parse`), and
that is where an [O-Borrow] reader needs it. (3) A coercion site interacts with
trait selection and inference, the area 0148 deliberately keeps rigid.
(4) It breaks the rule the language teaches.

**A narrow rule: coerce only into a concrete `Str` parameter whose contract
carries nothing from it.** The borrow cannot escape the statement, which meets
objection (2). It remains a conversion the receiving position selects, and it
still misses generic parameters. Not adopted; it is the candidate to weigh if
the census below shows most sites are non-generic and non-carrying.

**Give `String` the read-only `Str` API and `String == Str`.** Chosen. It is
an answer within the policy, not an exception to it: `String` gains the
`Str` read methods it lacks (`to_owned`, `as_bytes`, `byte`, `slice`, `find`,
`starts_with`, `ends_with`, `split`, `trim_ascii`, `trim_unicode`, `parse`,
`scalars`, `equals_ascii_folded`), each forwarded through **one routine** so the
`Str` rule has a single implementation and the forwarders cannot drift, and
`String == Str` (and `!=`) compares the two. No coercion is added.

Census of 2026-10-05, 379 `.view()` calls (344 in std, 35 in examples):

- 90 are arguments to a read `Str` parameter. These stay: without a coercion
  an argument is still written `.view()`.
- 25 are receivers of a `Str` method `String` lacks; they vanish with the
  forwarded methods.
- 208 are arguments to a generic `T`, almost all
  `testing.assert_eq(out.view(), expected, ..)`, and 26 are `==` or `!=`
  operands. `String == Str` is what makes the 26 vanish and, where the
  comparison is written as an equality, the `assert_eq` pair; the 208 are
  measured again once it lands.
- 22 must stay: the intentional `.view()` in the `String` impls that forward to
  `Str`, `let` bindings, and values stored, returned or wrapped.

**An autoview rule (a `String` receiver or argument read as `Str` at a
concrete `Str` position).** Weighed and not chosen. It would remove the 90
argument sites as well, and the census found no overload ambiguity. It is a
coercion the receiving position selects, so it hides where a borrow begins
(objection 2 above) and breaks the rule the language teaches. What would
reopen it: `assert_eq` sites staying written with `.view()` after
`String == Str` lands, or a visible call-site marker for the borrow being
found, so the origin is not hidden.

## What would reopen it

A census of `.view().method()` chains and `.view()` arguments across non-std
code showing that most sites are non-generic, non-carrying receivers or
arguments, together with programs where `.view()` is the top complaint of the
people writing them. That census is being run separately; this record does not
anticipate its result. A reopening is a new record that supersedes this one
and names which positions it admits, never a general coercion.
