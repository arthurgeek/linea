# 272. Two applications of one type may each implement a trait

Status: Accepted — 2026-11-15; supersedes the constructor coherence key of
[0081](0081-an-implementation-is-generic-over-its-head.md), the clause
"Coherence keys on the head's constructor: one implementation per (trait
declaration, trait arguments, head constructor)" and the consequence "One
member of a family cannot be special-cased" as far as it speaks of two settled
heads, and the comparison with "two tuple heads of one arity" in the
Duplicates clause of
[0213](0213-a-trait-may-be-implemented-for-a-callable-type.md). Extends
[0093](0093-two-implementations-that-could-answer-once-are-refused.md), whose
overlap rule becomes the only rule deciding whether two different
implementations may coexist.

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

When 0081 was written the constructor key was the only coherence check there
was. [0093](0093-two-implementations-that-could-answer-once-are-refused.md)
has since added the check the key was standing in for: two implementations
whose heads and trait arguments unify are refused with `[T-Impl]`. The key and
the overlap rule then answered one question twice, and disagreed on exactly
the programs above.

What the compiler relied on was traced before the key was changed:

- **Lookup never took the first row of a chain.** An implementation is filed
  under (trait, head constructor) in `ImplIndex`, and every lookup walks that
  chain and matches each row's whole header against the receiver and the
  trait arguments (`matchHeader`, through `bindKey`) before it answers. A
  chain already held several rows wherever one type implements a trait at
  several argument lists, so a row for another application is one more row
  that does not match.
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

Only two places assumed the key: the resolver's `sameImplementation`, which
reported the duplicate, and the checker's overlap pass, which unified every
pair of one chain whose ground argument lists are equal on the premise that
such a pair is at most one mistake.

## Decision

**Whether two different implementations of one trait may coexist is decided
by one rule: they may unless they overlap, as
[0093](0093-two-implementations-that-could-answer-once-are-refused.md) defines
it.** Two implementations whose heads apply one constructor to different types
do not unify, so `impl Weigh for Crate[UInt8]` beside
`impl Weigh for Crate[UInt16]` is accepted, with any number of further
applications, nested ones (`Crate[Option[UInt8]]` beside
`Crate[Option[UInt16]]`) and tuples of one arity included. Each call, bound
and settled reference reaches the implementation whose head is the type it
asks about, and a type no implementation's head matches does not implement the
trait (`[T-Bound]`).

**`[N-Duplicate]` reports one implementation written twice: the same trait,
the same head and the same trait arguments, up to the names of the parameters
each declares.** Two implementations declaring no parameters are the same
where their heads name one type and their arguments name the same types, read
as coherence reads every written type: through aliases, qualified names and
folded lengths. Two families are the same where one's head and arguments, with
its parameters read as what the other's head applies in the same positions,
are the other's. The report names the head as written, `Crate[UInt8]`, since
the constructor alone no longer says which implementation is repeated.

**A family and an implementation declaring no parameters are never a
duplicate; they overlap.** `impl[T] Weigh for Crate[T]` beside
`impl Weigh for Crate[UInt8]` is `[T-Impl]`, "these two both answer `Weigh`
for `Crate[UInt8]`", in either order, where it was `[N-Duplicate]`. The
program is refused as before; the report now names the type both answer for.

**What stays refused.**

- The same head twice, with the same trait arguments: `[N-Duplicate]`.
- A family written twice, however its parameters are spelled:
  `[N-Duplicate]`.
- A family beside any application of its constructor, and two families that
  unify: `[T-Impl]`. A family's bounds still do not make two headers disjoint.
- A head that declares parameters and is not its constructor applied to them,
  each once and in order: `[T-Impl]`, 0081's head rule, which this record does
  not touch. `impl[T] Count for Crate[Option[T]]` is still not a head.
- Specialisation. Nothing ranks two implementations; there is no pair left to
  rank, because every pair that could answer for one type is refused.

**A callable head keeps its shape key.**
[0213](0213-a-trait-may-be-implemented-for-a-callable-type.md) decided that a
trait takes one implementation per callable shape, whatever types the
signature writes, and that decision stands. Its Duplicates clause compares
this to "two tuple heads of one arity"; a tuple is an application of a
declared type and follows this record, so that comparison no longer holds and
0213 is marked.

## Consequences

**A wrapper type is no longer needed to give a second application its own
implementation.** `std`, the examples and the guide held no such wrapper when
this was decided, so nothing was migrated.

**The implementation index is unchanged.** Rows are still chained by (trait,
head constructor); overlap is still checked within a chain, and lookup still
walks one chain. A chain grows by one row for each application a trait is
implemented for, and a lookup pays one header match per row of the receiver's
chain, as it already did for a type implementing a trait at several argument
lists.

**Declaration-time cost stays linear in the applications.** The resolver
files each implementation by the root of one written position, chosen per
chain among the trait arguments and now the head's arguments too, so two
applications that differ at that position are never compared. Applications
that agree at the chosen position and differ beneath it,
`Crate[Option[UInt8]]` beside `Crate[Option[UInt16]]`, are compared pairwise;
that bound is quadratic in the implementations of one trait for one
constructor whose chosen argument shares a root, as it already was for trait
arguments. The checker hashes a ground head together with a ground argument
list, since two ground headers unify only where they are one header, so k
applications cost k lookups and no unification.

**Symbols and dumps are unchanged.** No existing `.mono`, `.exit` or `.out`
golden moved.

**Tooling needed no change.** Go-to-definition, references and completion
read what the checker selected.

**Reports changed.** A repeated implementation is named by its written head
(`Holder[T]`, `(UInt8, Bool)`) where it was named by its constructor
(`Holder`, `Tuple2`), and the label "a trait is implemented once for all
tuples of one arity" is gone with the rule it stated. A family beside one of
its applications is reported as the overlap it is.

**A derive follows the same two rules.** A derive attached to a generic type
is a family, so a handwritten implementation for one application of that type
overlaps it (`[T-Impl]`, where it was `[N-Duplicate]`); a derive naming one
application, `derive Score for Mark[UInt8]`, stands beside a handwritten
implementation for `Mark[UInt16]`.

**A head refused for its form is compared as it is written.** Two heads that
break 0081's head rule, `Pair[T, UInt8]` beside `Pair[T, T]`, were reported
as one implementation written twice because they share a constructor. They are
now compared like any two headers, and reported as an overlap where they
unify, beside the `[T-Impl]` each earns for its form.

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
of their own.** A third rule beside the duplicate and the overlap: "two heads
declaring no parameters may differ". It gives the same answers as this record
for every program, since two settled headers unify exactly where they are
equal, and it lost for that reason: it would be a special case of the overlap
rule written a second time, and the next reader would have to prove the two
agree.

**Specialisation: let `impl Weigh for Crate[UInt8]` override
`impl[T] Weigh for Crate[T]`.** It is what a reader may expect once two
applications can each have an implementation. It stays refused for the reasons
0081 and 0093 give: it needs a total order on specificity and a guarantee that
every call agrees on which implementation it reached, and a declared type read
through `Self.Item` would have two candidates. This record admits only pairs
that no type can reach together, so it needs neither.

**Extend the rule to callable heads now.** Uniform, and the lookup already
matches a function value against the written signature. It lost here because
0213 decided the opposite for a stated reason, a library treating parameter
types differently writes one implementation with a type parameter and a bound,
and nothing this record was asked to settle depends on reversing that.
