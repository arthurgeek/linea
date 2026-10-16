# 221. `Owned` admits a type that can carry no borrow

Status: Accepted — 2026-10-12.
Extends [0123](0123-observations-carry-owner-dependencies-through-callable-contracts.md)
and [0124](0124-copyability-and-settlement-are-independent-capabilities.md).

## Context

A dependency set belongs to a value and is not split by layer. `mem.Slice[T]`
is a carrier whatever `T` is, so in

```linea
fn append_all[T: Copyable, A: mem.Allocator](inout values: mem.Vec[T, A], items: mem.Slice[T]) -> ()
```

a body that pushes `copy(*item)` is [O-Escapes] at the push, and the only clause
that admits it, `retains(values: items)`, says the vector keeps the slice's
backing owner as well as whatever the elements carry. A caller whose vector can
carry, `Vec[UInt8, mem.Handle]`, then holds the slice's owner for as long as the
vector lives, although every byte it copied carries nothing. The same is true of
`iter.extend` (`retains(values: iterator)`) over bytes behind a handle. Written
with a concrete element type the loop needs no clause, because the compiler
already knows that `UInt8` or a struct of integers carries nothing: it computes
that answer for every type (`mayCarryDependencies`), and every contract and
ownership check reads it. Source cannot state it. Every type parameter is
seeded as able to carry, whatever its bounds, so even `T: Integer` carries.

The library worked around this with a byte-specific method,
`Vec[UInt8].append_bytes`, beside the generic operations it duplicates.

## Decision

**`Owned` is a built-in capability bound. A type satisfies it exactly when no
value of it can carry a dependency** — nothing reachable through its fields,
variant payloads, array elements, newtype base, closure environment or stored
container elements is an observation, a view, or a value holding one. That is
the answer the compiler already computes; the bound lets source ask for it.

- **One answer.** A type parameter bounded `Owned` is not seeded as a carrier.
  Inside the declaration that bounds it, a value of that parameter carries
  nothing: it is never an eligible contract source, and storing it adds nothing
  to a result or an `inout` destination. Contract inference, the ownership
  checker and storage lowering read the same containment table they read for a
  concrete type, so the bound changes one seed and nothing else. Storage's
  filter, which keeps a dependency on a value only where its type may carry one
  (`holdsDependencies`, over `mayCarry`), reads that table too: `Owned` is the
  negation of `mayCarry`, not a second classifier.
- **Checked at instantiation by the same table.** A type argument for an
  `Owned` parameter must carry nothing, which is the same `mayCarryDependencies`
  answer. A generic argument passes only when its own parameter is bounded
  `Owned`, as with `Copyable`. The [T-Bound] refusal names a path from the
  argument to what it carries, found over the same containment edges the table
  is computed from, never by a second classifier: `Label` is refused because its
  field `text` is a `Str`, which holds a view. The path names only parts the
  program can select, so it stops at a sealed type such as `Str` or `Vec`, whose
  fields are private, and at a newtype, whose base is reached by a pattern. A
  trait argument is checked against the trait's own parameter bounds the same
  way, so `C: Conv[U]` under `trait Conv[T: Owned]` needs `U: Owned`, as a
  written `Pool[U]` does. An associated type has no bound list, so the help
  for one says to add `where I.Item: Owned`. The help
  goes through the same edit routine as every other unmet bound, so it offers
  only edits the program can make: adding `Owned` to the bounds of a parameter
  the path ends at, and dropping the bound only where the program wrote it, not
  on a library operation such as `Vec.append_slice`.
- **Structural, never declared.** It is decided by the type's representation,
  private fields included, as `Copyable` is answered through an opaque type's
  fields. No declaration can claim it: `impl Owned for T` is [T-Bound], and so
  is an implementation of any other built-in bound. A hand-written claim would
  be unsound, because nothing would then check the fields.
- **Independent of settlement and copying.** A linear file owner and
  `Vec[UInt8]` over the system allocator are `Owned`; `Str`, any `borrow`,
  `Vec[UInt8, mem.Handle]` and a closure holding a lent place are not. `Owned`
  neither implies nor is implied by `Copyable`, `Discardable` or `Linear`.
- **`Integer` implies it.** Every member of the closed integer family carries
  nothing, so a parameter bounded `Integer` is not seeded either.
- **Where it may be written.** On a type parameter, inline or in its
  declaration's own `where` clause, and in that clause on an associated type
  read through one of the declaration's own parameters: `where I.Item: Owned`
  under `[I: Iterator]`, or `where Self.Item: Owned` on a trait signature,
  whose symbolic `Self` is its own. The seed is read from the record of the
  parameter a type stands for, and the stand-in for `I.Item` is a parameter
  record keyed by `I`, which no other declaration can name, so the promise is
  relied on exactly where it was made and checked at every call. Written on a
  parameter of an enclosing declaration, such as an implementation's `T` in a
  method's `where`, in a trait's bound list, or on an associated type's
  declaration, it is [T-Bound]: that record is shared by declarations that
  never made the promise, and a promise scoped to one of them would need
  containment computed per scope, which does not exist.

Soundness: the containment answer is monotone in its seeds. Substituting an
argument that seeds nothing for a parameter that seeded nothing marks no new
type, so a body proved with the parameter unseeded stays proved for every
admitted argument.

## Consequences

`Vec[T, A].append_slice` for `T: Copyable + Owned` replaces
`Vec[UInt8].append_bytes`, and a generic `fn tagged[T: Copyable + Owned](value:
T, tag: Str) -> T` needs no clause, because `value` is no longer a candidate
source.

Changing a private field of a type changes whether it is `Owned`, which is a
public fact: the hazard Rust's auto traits are known for. A library type that
starts holding a view stops satisfying every `Owned` bound it met.

`Owned` does not help an operation that must accept both borrowing and owned
elements, such as `iter.extend` over an arbitrary `Item`, which still retains
the iterator. A sibling bounded `where I.Item: Owned` serves the owned case; a
contract that disappears for an instantiation whose element is `Owned` is the
open question below.

Making `Integer` imply `Owned` changes what an `Integer`-bounded body may
return or store without a clause: a value of the parameter is no longer a
source.

## Alternatives considered

**Name it `Detached` or `Independent`.** `Independent` already means copy
non-aliasing in §5.3: a copied `Str` is independent of its source and still
carries. `Detached` says what the value is not attached to but not what it
is. `Owned` says that the value owns everything it holds, which is the rule;
the collision with the library trait `mem.Owner`, which supplies an allocator
handle, is removed by renaming that trait `mem.Lender`.

**Parameters carry nothing by default, and a borrowing parameter opts in**, as
Swift makes generic parameters escapable by default. Every existing
`Vec[Str]`, `Map[Str, _]` and `Option[borrow T]` would be refused until its
declaration opted in. The default stays as it is.

**A contract gated on a type: `retains(values: iterator) unless I.Item:
Owned`.** One function would serve both cases, and `extend` and `collect` would
need no split. The body must then be checked again with the gate assumed and
the clause removed, because a body could store something other than the
elements in the destination; with several gates the configurations multiply.
It builds on this bound rather than replacing it, and is recorded as an open
question.

**Specialisation: an `Owned` implementation narrows the contract.** A call is
checked against the trait signature whichever implementation answers it, and
overlapping implementations are refused, so a narrower implementation cannot
narrow what the caller sees.

**Keep the byte-specific methods.** The duplication is one method today, but
every new bulk operation (`append_slice`, `from_slice`, `fill_from`) would
repeat it, and the predicate the compiler computes would stay one source cannot
state.

**A declared opt-in, `impl Owned for T`, as Rust's `unsafe impl Send`.** It
would be unsound with nothing behind it to check the fields, and the structural
answer is never wrong.

## Open questions

Whether a contract may be **gated on a type**, so that `iter.extend` drops its
retention for an instantiation whose `Item` is `Owned`. The body would be
checked again with the gate assumed, and each source and destination pair could
be gated by at most one subject, so the configurations do not multiply.
