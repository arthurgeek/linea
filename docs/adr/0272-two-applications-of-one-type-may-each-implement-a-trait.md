# 272. Two applications of one type may each implement a trait

Status: Accepted — 2026-11-15; supersedes the constructor coherence key of
[0081](0081-an-implementation-is-generic-over-its-head.md), the clause
"Coherence keys on the head's constructor: one implementation per (trait
declaration, trait arguments, head constructor)" and the consequence "One
member of a family cannot be special-cased" as far as it speaks of two settled
heads, and the Duplicates clause of
[0213](0213-a-trait-may-be-implemented-for-a-callable-type.md), "Two
implementations of one trait at one shape and one argument list are
[N-Duplicate], whatever types their signatures write". Extends
[0093](0093-two-implementations-that-could-answer-once-are-refused.md), whose
overlap rule decides whether two implementations may coexist.

## Context

[0081](0081-an-implementation-is-generic-over-its-head.md) keyed coherence on
the head's constructor: one implementation per (trait declaration, trait
arguments, head constructor), "the constructor and not what the head applies".
Its reason was that an implementation generic over its head stands for every
application of that constructor, so a second one is a second answer for all of
them. The key was written for families and applied to every head, so it also
refused two implementations that declare no parameters and name two different
types:

```linea
struct Crate[T] {
    item: T,
}

trait Weigh {
    fn weigh(self: Self) -> UInt8
}

impl Weigh for Crate[UInt8] { ... }
impl Weigh for Crate[UInt16] { ... }
```

The second was `[N-Duplicate]`, "`Weigh` is already implemented for `Crate`".
`Crate[UInt8]` and `Crate[UInt16]` are two types. No value has both, no bound
is discharged by both, and no call could reach either implementation in place
of the other. The refusal protected nothing, and it had a cost: a program that
wanted the two bodies wrapped one application in a new type to give it a head
of its own. Rust accepts the equivalent program.

[0213](0213-a-trait-may-be-implemented-for-a-callable-type.md) carried the
same key to callable heads, by shape: `impl Run for fn(x: UInt8) -> UInt8`
beside `impl Run for fn(x: Bool) -> UInt8` was `[N-Duplicate]`, though no
function has both types. A derive carried it too, in a key of its own: a type
could request a trait once, whichever application the request named.

When 0081 was written the constructor key was the only coherence check there
was. [0093](0093-two-implementations-that-could-answer-once-are-refused.md)
has since added the check the key was standing in for: two implementations
whose heads and trait arguments unify are refused with `[T-Impl]`. The key and
the overlap rule then answered one question twice, and disagreed on exactly
the programs above.

What the compiler relied on was traced before the key was changed:

- **Lookup never took the first row of a chain.** An implementation is filed
  under (trait, head constructor) in `ImplIndex`, and every lookup matched
  each row's whole header against the receiver and the trait arguments
  (`matchHeader`, through `bindKey`) before it answered.
- **Prepared answers are keyed by the receiver type**, not by its
  constructor: `(trait, arguments, receiver)` for a selection and
  `(implementation, receiver)` for the arguments a receiver settles.
- **A settled reference selects through the same lookup**, so
  `Crate[UInt8].Label` and `Crate[UInt16].Label` read the type each
  implementation settles.
- **A member's symbol spells the head type with its arguments**, then the
  trait and its arguments, so members of two applications never share a name.
- **A default implementation is blocked by a header that matches**, or by an
  open receiver whose constructor has any ordinary implementation. Neither
  reads how many implementations the constructor has.
- **The language server reads the checker's selections and the list of
  members supplying a signature**, and keeps no index of its own.

Four places assumed the key. The resolver's `sameImplementation` reported the
duplicate. The checker's overlap pass unified every pair of one chain whose
ground argument lists are equal, on the premise that such a pair is at most
one mistake. A lookup walked every row of the receiver's constructor, which
the key held to one row for each argument list. And the unifier compared two
callable types' contracts as written, which was enough only while a generic
callable head beside a concrete one was refused before it was asked.

## Decision

**Two implementations of one trait may coexist unless they overlap, as
[0093](0093-two-implementations-that-could-answer-once-are-refused.md) defines
it: unless a substitution for both declarations' parameters makes their heads
one type and their trait arguments the same types.** The types compared are
the ones the headers are settled to, so a declared type's name stands for what
it is settled to: with `S.Reading` settled to `UInt8`, `Crate[S.Reading]` is
`Crate[UInt8]`. This is the rule for every ordinary implementation and every
kind of head. Default implementations keep the fallback tier of
[0139](0139-default-implementations-follow-ordinary-selection.md), and where an
implementation may be written at all is still [M-Impl]'s question.

Two heads that are settled to different types do not unify, so
`impl Weigh for Crate[UInt8]` beside `impl Weigh for Crate[UInt16]` is
accepted, with any number of further applications, nested ones
(`Crate[Option[UInt8]]` beside `Crate[Option[UInt16]]`), tuples of one arity,
and callable types of one shape. Each call, bound and settled reference
reaches the implementation whose head is the type it asks about, and a type
no implementation's head matches does not implement the trait (`[T-Bound]`).

**A callable head follows the same rule.** `impl Run for fn(x: UInt8) -> UInt8`
beside `impl Run for fn(x: Bool) -> UInt8` is accepted, and a function passed
where `Run` is required reaches the implementation written for its own type.
Two written callable types are one type where they agree in what the
semantics makes a callable type's identity: the invocation, each parameter's
convention, type and default, the result, and the contract. A parameter's
label is no part of it. So two heads that differ only in a label are one head;
two that differ in a convention, in the result or in a contract are two. The
shape, a head's invocation and conventions, remains how a callable head is
filed and found, and everything else
[0213](0213-a-trait-may-be-implemented-for-a-callable-type.md) and
[0271](0271-a-callable-head-of-any-length-has-a-shape.md) decided stands: a
closure matches no callable head, and a function value matches a head whose
signature is exactly its own. A generic callable head overlaps a concrete one
it could be settled to: `impl[T] Run for fn(x: T) -> T` beside
`impl Run for fn(x: UInt8) -> UInt8` is `[T-Impl]`.

A contract is part of a callable type only where it names a dependency, so one
written over a type the implementation leaves open, a parameter or a settled
type's name, stands at some settlements and not at others: `carries(a)` over
`a: T` stands at `Str` and is no part of the type at `UInt8`. Overlap asks
whether any settlement is answered by both, so such a contract proves no two
heads apart. `impl[T] Run for fn(a: T) -> Str where carries(a)` beside
`impl[U] Run for fn(a: U) -> Str where carries()` is `[T-Impl]`: both are
`fn(a: UInt8) -> Str` at `UInt8`, where a lookup, which drops the contract once
it has bound `T`, matches one function against both. Two contract lists keep
two heads apart only where a contract that stands whatever the open types
become has no counterpart on the other side that stands or may stand. The
comparison reads each undecided contract as free to stand or not on its own.
That admits no pair a lookup could match twice; it may refuse a pair whose
undecided contracts rest on one open type and could never agree, which is
the direction a rule that refuses what it cannot rule out errs in.

**`[N-Duplicate]` reports one implementation written twice: the same trait,
the same head and the same trait arguments as written, up to the names of the
parameters each declares.** Two implementations declaring no parameters are
the same where their heads and their arguments are written as the same types,
read through aliases, qualified names, a tuple's long form and folded lengths.
Two families are the same where one's head and arguments, with its parameters
read as what the other's head applies in the same positions, are the other's.
The report stands at the one written second and names its head as written,
`Crate[UInt8]`.

**Which comparison decides what.** Whether two implementations may coexist is
decided by the overlap rule, which unifies the settled types, with the two
exclusions [0148](0148-parameter-heads-match-complete-trait-keys.md) and
[0192](0192-iterator-operations-belong-to-every-sequence.md) record for a head
that is a bare parameter. The written comparison is no part of that decision.
It decides only which report a refused pair earns: a pair it
calls the same is reported as a repetition, and that implementation takes part
in no overlap report. A repetition the written comparison cannot see, because
a name stands for a type settled later, is still refused, as the overlap it
also is: `impl Weigh for Crate[S.Reading]` beside `impl Weigh for Crate[UInt8]`
is `[T-Impl]`. The written comparison never admits a pair.

**A family and an implementation declaring no parameters are never a
repetition; they overlap.** `impl[T] Weigh for Crate[T]` beside
`impl Weigh for Crate[UInt8]` is `[T-Impl]`, "these two both answer `Weigh`
for `Crate[UInt8]`", in either order, where it was `[N-Duplicate]`.

**A derive is a request for an implementation, and is one request for each
implementation it asks for.** A derive attached to a declaration, and a
standalone one whose head applies the target to its own parameters, request
the family. A standalone derive that declares no parameter and applies the
target to types requests that one application, so `derive Score for
Mark[UInt8]` beside `derive Score for Mark[UInt16]` is two requests. The same
request written twice is `[T-Derive]`, as before; the implementations two
different requests generate are held to the two rules above like any others.

**What stays refused.**

- The same header twice: `[N-Duplicate]`, or `[T-Derive]` for a derive
  requested twice.
- A family beside any type it could be settled to, and two families that
  unify: `[T-Impl]`. A family's bounds still do not make two headers disjoint.
- A head that declares parameters and is not its constructor applied to them,
  each once and in order: `[T-Impl]`, 0081's head rule, which this record does
  not touch. `impl[T] Count for Crate[Option[T]]` is still not a head. An
  implementation refused for the form of its head is compared with no other.
- Specialisation. Nothing ranks two implementations; there is no pair left to
  rank, because every pair that could answer for one type is refused.

## Consequences

**A wrapper type is no longer needed to give a second application its own
implementation.** `std`, the examples and the guide held no such wrapper when
this was decided, so nothing was migrated; `examples/recipe_quantities.lin`
shows the form.

**A receiver finds the implementation written for its type by that type.**
Rows are still chained by (trait, head constructor), and a trait implemented
for k applications of one constructor puts k rows on one chain. A lookup that
walked the chain would cost k header matches for each receiver, k² for a
program that uses each application once. `ImplIndex.candidatesFor` gives a
ground receiver the rows whose head is its own type, found by hashing the
trait and the type, and at the requested arguments where those are ground;
only the rows that declare parameters are walked. A callable type is interned
without its labels and with the contracts that stand for it, so a function
value whose signature a ground callable head writes has that head's type and
finds its row the same way. `ImplIndex.rowsUnder` does the same for a reader that asks for
the rows of every trait under one type's head, which is how a lookup is
prepared. A receiver that still holds a parameter walks the chain as before:
no ground row matches it.

**Declaration-time cost is linear in the implementations that declare no
parameters.** The resolver finds one by a hash of its whole written header, so
it is compared only with the earlier ones written alike. The checker hashes a
ground head with a ground argument list, since two ground headers unify only
where they are one header. Implementations that declare parameters are still
compared with the others of their trait and head constructor whose trait
argument at one chosen position has the same root: quadratic in the families
of one trait for one constructor that agree there.

**Measured.** `zig build sweep -Drelease` holds both shapes as dimensions.
"Applications each implementing a trait and used once", one implementation
for each of n applications and each handed once to a bound, read n^1.04
(149 ms, 261 ms and 548 ms at 4000, 8000 and 16000) where a linear doubling
on the same machine reads n^1.04. "Nested applications each implementing a
trait", n heads that agree in an outer constructor, read n^0.95 (67 ms,
129 ms and 247 ms). "Callable heads of one shape each implementing a trait
and used once" read n^1.06 (106 ms, 219 ms and 453 ms) where a linear
doubling read n^1.06. Before the index and the header hash a debug compiler
took 14.5 s and 4.5 s to check the two shapes at 2000; it takes 2.6 s and
2.3 s, of which about 2 s is reading the library.

**Symbols and dumps are unchanged.** No existing `.mono`, `.exit` or `.out`
golden moved.

**Tooling needed no change.** Go-to-definition, references and completion
read what the checker selected.

**Reports changed.** A repeated implementation is named by its written head
(`Holder[T]`, `(UInt8, Bool)`) where it was named by its constructor
(`Holder`, `Tuple2`), and the labels "a trait is implemented once for all
tuples of one arity" and "once for each callable shape" are gone with the
rules they stated. A family beside one of its applications is reported as the
overlap it is. An overlap between two headers of one file is reported at the
one written later, which for a derive is where its request is written and not
where the implementation it generates is declared. An implementation written three
times is reported twice, each time against the first, and not as an overlap as
well.

**A head refused for its form earns one report.** Two heads that break 0081's
head rule, `Pair[T, UInt8]` beside `Pair[T, T]`, were reported as one
implementation written twice because they share a constructor. Such a head is
now compared with nothing: which types it would answer for is a question the
refusal leaves unasked.

**0083's remark that an array cannot head an implementation is untouched.** An
array type is still not written after `for`.

## Alternatives considered

**Keep the constructor key.** It is one comparison and it needs no argument
about bounds. It lost because it refuses programs in which no type has two
answers, which is the only thing coherence protects, and because it left two
rules deciding one question: the key called `Crate[UInt8]` and `Crate[UInt16]`
one implementation while unification, asked about the same pair, says they
never meet.

**Admit distinct applied heads only where both are fully settled, by a rule
of their own.** A third rule beside the repetition and the overlap: "two heads
declaring no parameters may differ". It gives the same answers as this record
for every program, since two settled headers unify exactly where they are
equal, and it lost for that reason: it would be a special case of the overlap
rule written a second time, and the next reader would have to prove the two
agree.

**Decide coexistence by the written comparison.** The resolver already
compares two written headers, and admitting whatever it calls different needs
no unifier. It lost because a written type is not always the type: a declared
type's name is settled after the headers are read, so two headers written
differently can be one type, and admitting them would give that type two
implementations, with the one a call reaches decided by which was written
first.

**Specialisation: let `impl Weigh for Crate[UInt8]` override
`impl[T] Weigh for Crate[T]`.** It is what a reader may expect once two
applications can each have an implementation. It stays refused for the reasons
0081 and 0093 give: it needs a total order on specificity and a guarantee that
every call agrees on which implementation it reached, and a declared type read
through `Self.Item` would have two candidates. This record admits only pairs
that no type can reach together, so it needs neither.

**Leave callable heads on the shape key.** 0213's reason was that a library
treating parameter types differently writes one implementation with a type
parameter and a bound. That still works and is still the way to answer for
every function of a shape. It lost as a restriction because it is the same
refusal this record removes for named types, with the same absence of a type
that has two answers, and because one rule for every head is what lets a
reader predict a refusal from the two headers alone.

**Walk the chain at lookup and accept the cost.** The mechanism predates this
record: a type implementing one trait at k argument lists already paid k per
lookup. It lost because this record makes the ordinary shape reach it, one
implementation for each application of a container, and a question asked once
per receiver is an index.
