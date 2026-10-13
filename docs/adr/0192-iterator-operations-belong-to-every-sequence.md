# 192. Iterator operations belong to every sequence

Status: Accepted — 2026-09-28. Builds on
[0186](0186-a-type-reaches-the-operations-of-the-traits-it-implements.md) and
[0187](0187-a-bound-brings-its-traits-operations-into-reach.md) for reach.
Refines the disjointness sentence of
[0148](0148-parameter-heads-match-complete-trait-keys.md). Refines the method-call fallback
clause of [0152](0152-an-integer-literals-type-is-settled-by-its-uses.md).

## Context

`std.iter` offered its adapters and terminals as module functions:
`iter.fold(iter.filter(iter.map(values.as_slice().iterate(), f), p), 0, add)`.
A pipeline read inside out, and the spelling a newcomer from Rust, Kotlin,
Swift or JavaScript writes first, `values.as_slice().iterate().map(f)`, was
refused: `map` is a function, not an operation of `mem.SliceIter[UInt64]`
([T-UnknownOperation]). Each lambda passed to the refused call was then
reported again as [T-Infer], one report per lambda, beneath the one that
mattered.

The functions took `I: Iterator`, so a slice, a `Sequence` but not an
`Iterator`, had to be walked with `.iterate()` first, and
`iter.map(values.as_slice(), f)` was refused with a [T-Infer] on the lambda
that named neither trait.

ADR 0187 already lets a bound's trait operations be called with a dot, and
ADR 0186 lets a type reach the operations of the traits it implements. Neither
helped, because `Iterator` declares only `next` and the adapters were not
operations of any trait.

## Decision

**A trait may provide an operation.** A trait's operation written with its
body is provided: every type implementing the trait offers it, reached as any
trait operation is -- by dot, through the trait, through a bound -- and runs
the trait's one body with `Self` settled to that type. The body is checked
once over the trait's symbolic `Self`, the reading the trait's signatures
already take, so it calls the trait's other operations and reads the types an
implementation settles, but nothing one implementation holds. An
implementation does not supply a provided operation, and one that does is
refused ([T-Impl]): two bodies for one operation would let one type run a
different pipeline than every other. Each instantiation is keyed by the type
it runs for, which stands in the symbolic `Self`'s position after the
operation's own type parameters, and by the trait's arguments it was reached
through: a body provided by `Scale[K]` runs at the `K` of the implementation
that answered, as an implementation's member runs at what its head bound. The
body names the trait's parameters as its signature does, `let unit: K`, and
reads the trait's signatures at them, so `Self.Out` in its result and in what a
call inside it returns is one type. It may call itself, by dot, through the
trait or through a bound, as a function may.

**The walking operations are `Sequence`'s.** `Sequence` provides `map`,
`filter_map`, `filter`, `fold`, `fold_inout`, `find_map`, `find_map_inout`,
`for_each`, `for_each_inout`, `any`, `any_inout`, `all`, `all_inout`, `find`,
`find_inout` and `collect`. Each takes the sequence and walks the iterator
`iterate` gives it. `values.as_slice().map(f)` and
`Sequence.map(values.as_slice(), f)` are the same call to the same body, the
second written through the trait as ADR 0186 allows. A slice needs no
`iterate()`. `Iterator` provides the searches that run in place,
`find_counted` and `find_counted_inout`: they take `inout self` and leave the
iterator with the caller, positioned after the match,
`&arrivals.find_counted(p)`. Both traits are already in the prelude, which the
syntax requires, so the operations add no name to any module: a module that
declares a `Walk` or a `Search` of its own keeps every chain.

**Every plain operation calls its callback `inout`.** `map`, `filter_map`,
`filter`, `fold`, `find_map`, `for_each`, `any`, `all`, `find` and
`find_counted` take the callback `sink`, bounded by an `inout fn`
(`F: inout fn(…)`). A read callable satisfies an `inout fn` bound (ADR 0131), and
a closure written in the call may change what it owns or a place it is lent
`inout` (ADR 0193): `xs.fold(0, inout [inout n] |sum, x| …)`. The operations
that walk now consume their callback and drop it on return, so they also
require `F: Discardable`, and each runs by lending its callback to its `_inout`
form, which holds the one body. The `_inout` forms borrow a callback the caller
keeps, which is the form for a callback called again by a later operation, or
one owning a linear capture the caller settles afterwards.

Consuming the callback has two consequences a caller sees. A closure bound to a
name is moved by the first operation it is passed to, so passing it to a second
is [O-Move]; a copyable callback is passed as `copy(heavy)` to all but the last
use, and one that cannot be copied goes to the `_inout` form where the
operation has one; `merge`, `update` and `each_allocation_failure` have none,
so such a callback is written at each call, or captures by `read` what it would
own. A generic function
that borrowed its callback cannot move it on: it takes the callback `sink` with
`F: Discardable`, lends it to the `_inout` form, where there is one, from an
`inout` parameter, or
requires `F: Copyable` and passes `copy(f)`. A function name is unaffected,
since it is copied wherever it is used.

The standard library's other operations that call a callback without keeping
it follow the same convention: `Option` and `Result` `map`, `map_err`,
`and_then` and `unwrap_or_else`, `Vec.from_fn`, `Map` `merge`, `update` and
`upsert`, and `testing.each_allocation_failure` take the callback `sink` under
an `inout fn` bound and require it Discardable. `Map.upsert_inout` joins the
existing `_inout` forms, because an upsert factory is the callback most often
reused across calls and the one most likely to own something the caller
recovers afterwards.

**Every iterator is a sequence of itself, and of nothing else.** `std.iter`
declares `impl[I: Iterator] Sequence for I`, an ordinary implementation headed
by a bare parameter, whose `iterate` returns the iterator. An iterator
therefore offers every operation `Sequence` provides, so
`values.as_slice().iterate().map(f)` compiles, and a `for` walks any iterator
directly. The bound `I: Iterator` selects this implementation, so inside
`fn f[I: Iterator]`, `I.Iter` is `I`: `values.map(f)` and `for x in values`
walk `values` itself, and a `where I.Item: …` covers what they yield. The
same holds under a bound that names `Sequence` as well, `I: Iterator +
Sequence`: the bound answers `Sequence` for `I`, and still stands for the one
implementation the parameter head is, so a `where` clause about `I.Iter` is
one about `I`.

For that to be what walking an iterator means, no iterator may be walked some
other way, so a `Sequence` implementation for a type that implements
`Iterator` is refused as overlapping. That is coherence's own question with one
clause added: a head that is a bare parameter bounded by a trait does not
overlap a constructor-headed implementation when no implementation of that
trait could answer for the constructor. Every implementation of the trait is
in the program, so the answer holds for the whole of it:
`impl[T] Sequence for Slice[T]` stands beside the iterator head because
nothing implements `Iterator` for a `Slice`, and `impl Sequence for Pages`
beside `impl Iterator for Pages` is refused. This narrows ADR 0148's sentence
that open trait predicates do not prove headers disjoint, for this one shape.
The identity implementations the library wrote for each of its iterators --
the adapters, `SliceIter`, `Range`, `Split`, `Scalars`, `Headers` and
`Entries` -- are removed, as are the corpus's.

**The free functions are removed.** One spelling is taught, the chain;
`iter.map(xs, f)` no longer exists and `Sequence.map(xs, f)` is the written
form, for the cases a written form is for, such as settling an ambiguity. A
free function beside each operation would be a second spelling of the same
call, and forwarding to the operation would make it a second routine that
could drift from it. `iter.extend(&values, &iterator)` stays a function: its
receiver is the vector it appends to, and the operation belongs with `Vec`,
whose operations `std.mem` declares.

**A requirement one operation has stays on that operation.** `filter` drops
the items its predicate rejects, so its own `where` clause asks
`Self.Iter.Item: Discardable`, as `find` does. A walk of linear items still
offers `map`, `filter_map` and every other operation, and a `filter` over them
is refused with [T-Bound], labelled at that `where` clause.

**The checker reads a trait signature's bounds at the call.** A callable
bound on a signature's own type parameter, `F: inout fn(sink item:
Self.Iter.Item) -> U`, and a `where` subject such as `Self.Iter.Item`, were
read with no `Self` in scope, so the bound became poison and was dropped, and
the `where` subject was never checked at a call. Both are now read over the
signature's symbolic `Self`, the reading its parameter annotations already
took, and a call substitutes the `Self` it settled: a lambda takes its
parameter types from the receiver's implementation, and a failed `where`
clause is refused. This is the reading `paramType` gives a signature's
parameter types; one substitution, `withSettledSelf`, serves the bounds and
the `where` subjects.

**A projection through a parameter-headed implementation is its
definition.** In `fn count[I: Iterator](sink values: I)`, `values.fold(…)`
reads `I.Iter.Item`. A key that still holds a type parameter was always left
as a stand-in awaiting the instantiation, so `I.Iter` said nothing about `I`
and the callback's item type was unknown. Where the parameter's bounds select
an implementation headed by a bare parameter, coherence leaves no other
implementation any instantiation could reach, so the builder settles the
member through it: `I.Iter` is `I`. One routine, `settledAt`, answers this for
every reader.

**A signature read at a call is read in the caller's scope.** The callable
bound a call infers a callback against is read again where the call is,
with the call's `Self` -- the reading a bound check at the call already took
-- and a projection is settled in the scope of the declaration being checked,
so that declaration's `where` clauses prove what the implementation answering
needs. Inside `fn count[S: Sequence]` with `where S.Iter.Item: Discardable`,
`values.filter(p).fold(0, f)` reads `Filter[S.Iter, F]`'s items as
`S.Iter.Item`; without the clause, `filter` is refused at its own `where`
clause, and the report names it.

**A refused call asks nothing of its callbacks.** Where the callee is refused
-- an operation the receiver lacks, a free function written as an operation,
an undefined name -- a lambda among the arguments is checked with its
unwritten parameter types unknown rather than reported as [T-Infer]. A
receiver that implements no `Sequence` is told so: `count.map(f)` on a
`UInt64` reports that `Sequence` declares `map` and `UInt64` does not
implement `Sequence`, and `Sequence.map(count, f)` adds that every type
implementing `Iterator` implements `Sequence`, and `UInt64` does not implement
`Iterator`. A collection that offers a slice which does, as a `Vec` and an
array do, is pointed at `values.as_slice()`. A bound refused at a `where`
clause names its subject in full, `Self.Iter.Item`, and an implementation
refused as overlapping another is not reported again for the operations it
leaves out, nor is a call refused for its bounds reported again for the
operations its result lacks. The explanation of why a type does not implement a trait now asks
implementations headed by a parameter as well as the receiver constructor's,
except one held to integers, and a trait operation refused for its `Self`
carries it, as every other unmet bound already did.

## Consequences

- A pipeline reads left to right from what it walks:
  `values.as_slice().map(f).filter(p).fold(0, add)`, and `for x in xs.map(f)`.
- A type implementing `Sequence` whose own operation has one of these names
  keeps its own, under ADR 0160; a trait in scope that declares one of the
  names for a sequence makes the dot call [N-Ambiguous], and the call is then
  written through a trait.
- A postfix call such as `xs.map(f)` costs what ADR 0186 states for any trait
  operation: one hash lookup of the name among the traits the module sees,
  keyed by module and name, and one applicability question for each trait
  that lookup returns -- here `Sequence`, a keyed implementation lookup whose
  answer the builder keeps. Nothing is sized by the number of traits or
  implementations in the program.
- A provided operation is instantiated once per type it runs for, as a
  generic function is per argument list; its symbol names that type first.
- A method call and a function call settle open integers alike. A receiver
  whose type holds an open integer inside a known head, `Range` of literals,
  is looked up by that head and left open, and the call's arguments settle it:
  `(0..3).map(|i| Row.of(i))` walks a `Range[UInt64]`. A postfix call's
  receiver is checked once, as an argument is, so a chain settles as the
  nested calls it stands for do: every call in
  `(0..6).filter(p).fold(0, f)` is instantiated at the type the whole chain
  settled the literals to. Only a receiver that is
  itself an open integer takes the default where the call is, since its type
  decides what the call reaches. This narrows ADR 0152's clause that any method
  call on an open value falls back. A `for` reads its walk at the type the
  `Sequence` question answered for, with whatever that question settled.
- A `where` clause on a trait operation is now checked at every call, so an
  operation whose clause no call met before now refuses those calls.
- Settling through a parameter head costs one walk of the trait's
  parameter-headed bucket for each key read with a parameter in it, and one
  implementation choice where that bucket holds a row.

## Alternatives considered

**A trait for the operations, implemented once for every sequence.**
`trait Walk { … }` with `impl[S: Sequence] Walk for S`, published from the
prelude, gives the same calls with no new kind of declaration. It costs two
common words in every module, `Walk` and `Search`, which a user may not then
declare without losing every chain in that module: a module's own name
shadows the prelude's, the trait leaves reach, and the help that names
`use iter.Walk` collides with the user's type. It also offers a second bound,
`W: Walk`, weaker than `Sequence`, which a `for` refuses.

**Keep the free functions beside the operations.** Both spellings would be
taught or one would rot, and a forwarding function is a second routine for
one operation.

**Keep read callbacks on the walking operations.** `fold`, `for_each`, `any`,
`all`, `find`, `find_map` and `find_counted` took `F: fn(…)` and called the
callback for reading, so a closure that changes a place it is lent was refused
([T-Call]) and had to be bound to a name and lent to the `_inout` form. That
split the terminal operations from `map` and `filter`, which already called
their callbacks `inout`, for no gain: a read callback satisfies the `inout fn`
bound as well. The change does refuse programs the read form accepted: a named
closure passed to two operations, which now needs `copy(…)` on the first or the
`_inout` form; a generic function forwarding a callback it borrowed, which now
takes it `sink`, lends it from an `inout` parameter, or requires `F: Copyable`;
and a callback owning something that must be released, which now goes to the
`_inout` form. Rust's `Iterator::any` and `fold` take their closure by value
under the same trade, and the `_inout` forms keep the borrowed route open.

**Operations on `Iterator` only.** Every pipeline over a collection would
still start with `.iterate()`, the call newcomers found unnecessary.

**Let implementations override a provided operation.** Rust does. Then a
type's `fold` could walk something other than its `iterate`, and every call
site would have to ask which body runs; one body per operation keeps the
answer in the trait.

**Make every iterator a sequence through a default implementation.** A
default, ADR 0139's tier, is a fallback an ordinary implementation overrides,
so a type parameter bounded by `Iterator` cannot select it: generic code
bounded by `Iterator` would get no operations, and an iterator overriding it
would be walked two ways, `fold` through its other `Sequence` and
`find_counted` through itself.

**Keep each iterator's identity `Sequence` implementation.** Every iterator
author would restate `iterate` as `self`, and an iterator that did not would
offer no operations and could not be walked by a `for`.
