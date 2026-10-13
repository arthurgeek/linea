# 165. An attached derive requires each field type

Status: Accepted — 2026-09-24

Partially supersedes [0145](0145-closed-attributes-attach-ordinary-derive-requests.md):
an attached derive no longer uses the type's written constraints alone.
Partially supersedes [0142](0142-construction-derives-expand-to-ordinary-source.md):
expansion of an attached request adds generated predicates. Partially
supersedes [0148](0148-parameter-heads-match-complete-trait-keys.md): an exact
cycle that passes through a derived implementation holds.

## Context

`@derive(Equatable)` on `struct Labelled[T] { label: Str, value: T }` was
refused: an attached request used only the type's own constraints, and nothing
there says `T` has `==`. The workaround was a standalone request,
`derive[T: Equatable] Equatable for Labelled[T]`, repeated per trait, or a
bound on the type itself, which forbids `Labelled[Token]` from existing at all
when `Token` has no equality.

The derived body compares each field with the field type's own
implementation. What it needs is therefore exactly "every field type implements
the trait". Any rule that states the requirement some other way either demands
more than the body uses or less than it needs.

Recursive types sharpen the question. `struct Tree[T] { value: T, children:
Vec[Tree[T], A] }` needs `Vec[Tree[T], A]: Release`, which needs
`Tree[T]: Release` — the implementation being derived. Implementation lookup
refused every exact cycle, so a field-type requirement on a recursive type
could never be proved at a use.

## Decision

**An attached derive on a generic type is conditional on its field types.**
For each struct field or variant payload whose written type names one of the
type's parameters, expansion adds a trailing predicate to the generated header:
that field type, bounded by every trait the template's component requirements
name, at the entry's trait arguments. Equal field types contribute one
predicate. A field that names no parameter is checked once at the derive, as
before. A `phantom` parameter appears in no field and so is never constrained.
The type's own written bounds stay in the header and still apply.

`Labelled[T]` implements `Equatable` where `T: Equatable`.
`struct Handle[T] { inner: Shared[T] }` implements it where
`Shared[T]: Equatable`, which asks nothing of `T` when `Shared`'s implementation
asks nothing. `ReadFileFailure[A: Allocator]`, whose field is
`Option[Vec[UInt8, A]]`, releases for every allocator.

**An exact cycle that passes through a derived implementation holds.** When
lookup re-enters a key it is still deciding, it holds if some implementation on
the cycle, from that key's frame to the innermost, is derived; otherwise it is
refused, as every other cycle is. The answer then rests on the requirements
outside the cycle: `Tree[Str]` releases because `Str` does, and so does
`Vec[Tree[Str], A]`, whichever of the two is asked first. A derived body
recurses only through the fields of the value it receives, and every value is
finite, so the assumption admits exactly the recursive types whose fields
support the trait. Deciding by the cycle rather than by the key re-entered is
what makes the answer independent of the order questions are asked in. An
answer resting on a cycle still being decided, positive or negative, is not
recorded until that key is settled, so no later question reads it.

**A derived `Release` settles each component, last first, and discards what it
may.** Each component is decided once, at the derive, under the derive's own
constraints (the type's written bounds for an attached request, the written
environment for a standalone one). A component whose type implements `Release`
there is released. One whose type is discardable there and not proven to
implement `Release` is discarded: it adds no field requirement, and the
generated release call for it runs `release.discard`, which does nothing. Any
other component is released: a type naming a parameter keeps its field
requirement, and a closed type is [T-Derive] at that field. An allocator field
`allocator: A` with `A: mem.Allocator` is discarded, because every allocator is
copyable, so `ResponseHeaders[A]`, `Router[A]` and `net.Address` derive
`Release`. The order is last component first, which releases in the reverse of
construction and keeps an earlier component, such as an allocator, alive while
later ones are settled.

A discardable component adds no `Release` requirement whichever way it is
settled, since one proven to implement `Release` under the type's own bounds
needs no requirement to say so. The checker withdraws those requirements from
every derived `Release` before it makes any choice, so a choice that asks
whether another derived type implements `Release` reads that type's final
requirements. Declaration order cannot change the answer: with
`Outer[A] { inner: Inner[A] }` declared before
`@copyable Inner[A] { allocator: A, noise: Noisy }`, `Inner[A]` implements
`Release` for every allocator and `Outer` releases it, as it does in the other
order.

The standalone form is unchanged. `derive[T: Equatable] Equatable for
Labelled[T]` states its whole environment and infers nothing; it remains the
form for bounds other than the field types', such as a stronger or weaker
requirement than the body needs.

A use whose field type lacks the trait is [T-Bound] at the use. The report
names the implementation's unmet requirement and follows it one level at a
time: `Shelf[T]` implements `Equatable` when `Labelled[T]` does, and
`Labelled[Token]` does not; `Labelled[T]` implements it when `T` does, and
`Token` does not.

## Consequences

- Generic structural types derive without restating bounds, and a type's
  implementation exists for exactly the arguments its fields support.
- A type's derived bounds follow its field types. Changing a field's type can
  change which arguments the implementation accepts, so for a public type the
  field types' implementations become part of the derived contract, including
  for an opaque type whose fields a user cannot read. The documented signature
  of such a type states the traits it derives and what they require. Linea is
  unreleased, so no published contract moves.
- Cost: expansion walks each field's written type once per trait entry, and a
  per-entry hash set removes duplicate field types, so expansion is linear in
  the type's fields. Each predicate is one more requirement checked when a use
  selects the implementation; selection answers are cached per implementation
  and receiver, so a field adds one check per distinct instantiation, sized by
  the type's fields rather than the program. Instance discovery gains nothing
  new: the generated bodies and their calls are those a standalone derive
  produces.
- Diagnostics at a use gain notes naming the unmet requirement, for every
  conditional implementation, derived or written.

## Alternatives considered

**Require `Release` of every component of a derived `Release`.** The first
form of this record. An allocator field then required `A: Release`, which no
allocator implements, so every type holding its allocator wrote `Release` by
hand. Implementing a no-op `Release` for allocators does not help generic code:
a default implementation does not apply to a type parameter, so
`serve[A: Allocator]` still could not release `ResponseHeaders[A]`.

**Iterate the discard choices to a fixed point, or make them in type-dependency
order.** Either would stop one derive reading another's requirements before
they are settled. Both work around an order the choice does not need: the only
requirement a choice changes is `Release` on a discardable component, and
discardability is a capability that no implementation affects. Withdrawing
those requirements first is one pass with no ordering. It also needs no answer
for dependency cycles, which the coinductive rule above already permits.

**Decide discard per instantiation.** Releasing a component where the concrete
type implements `Release` and discarding it otherwise would make one generic
body run different code for different arguments, a specialisation the language
does not have. Deciding at the derive keeps one body and one answer; a type
that wants an effectful release of such a component bounds the parameter by
`Release`.

**Refuse generic derives the declaration does not already prove.** The previous
rule. It sent every generic type to a standalone request per trait, which
restates what the fields already say and drifts from them when a field changes.

**Bound every type parameter by the trait, as Rust's `#[derive]` does.** Rejected
because it demands more than the body uses. `Handle[T] { inner: Shared[T] }`
would require `T: Equatable` even where `Shared[T]` compares for every `T`, and
`ReadFileFailure[A: Allocator]` would require its allocator to implement
`Release`, which no allocator does. Rust carries the same flaw for `Arc<T>` and
`PhantomData<T>` fields.

**Accept only explicit bounds.** Keep attached derives on generic types refused
unless the declaration's bounds prove the requirement, and use standalone
requests otherwise. Rejected for the same restating cost as the first
alternative; the standalone form remains available for the cases where explicit
bounds are the point.

**Exclude recursive fields from the predicates instead of assuming the
implementation.** Checking a field of the type's own type at the derive, under
the other predicates, handles `children: Vec[Tree[T], A]` but refuses a field
that mixes the recursive occurrence with another parameter, and it misses
mutual recursion through a second derived type. The assumption handles both
with one rule in the one lookup.
