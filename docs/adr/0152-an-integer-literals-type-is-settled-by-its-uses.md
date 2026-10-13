# 152. An integer literal's type is settled by its uses

Status: Accepted — 2026-09-23. Extends [0018](0018-the-integer-model.md);
partially supersedes [0092](0092-a-settled-type-parameter-flows-inward.md).
Extended by [0176](0176-a-function-name-is-a-value-its-uses-instantiate.md).
Method-call fallback clause refined by
[0192](0192-iterator-operations-belong-to-every-sequence.md).

## Context

0018 types a literal by its context and falls back to `Int64` where there is
none. "Context" meant only the expected type at the literal itself, so a literal
with nothing expected committed to `Int64` before a later use could say
otherwise:

```linea
let n: UInt8 = 2
let a = 1 + n                  // [T-Operands]: expected `Int64`, found `UInt8`
let r = 0..3
var total: UInt64 = 0
for i in r { total += i }      // [T-Operands]: `r` is `Range[Int64]`
var count = 0
count += total                 // [T-Operands]: `count` is `Int64`
```

Every one of these compiles when the literal is written where its use is. The
program was refused for the order of its lines, which is the remaining gap in
the language DX review's D04 ("let known types survive ordinary composition").
It shows up most in generic callbacks: `iter.map(0..3, |sink item| Row.of(item))`
with `Row.of(index: UInt64)` fixed the range at `Int64` before the callback,
which is the only place that says what the range holds, was checked.

## Decision

**An integer literal with no expected type has an open integer type.** So does
an expression built only from such literals: a range whose ends are both open,
arithmetic and negation over open operands, a group, and a `let` or `var`
binding whose initializer is open. A literal checked against an expected type
takes that type exactly as before.

**An open type settles on the first concrete integer type it must equal.** It
settles only where two types are already required to agree: an expected type
flowing in, including an argument meeting its parameter and an initializer
meeting an annotation; an operand whose partner is concrete; an assignment's
target; a callback parameter meeting a concrete demand inside the callback; a
range end meeting the other end; an array element meeting its siblings; an
index meeting the container's key, which is `UInt64` for an array; and two
arguments settling one type parameter. Two open types that meet become one. **Settling is equality, not conversion**:
0018's ban on implicit conversion between integer types is unchanged, and a
value already typed `Int64` never becomes a `UInt64`.

**Fallback is `Int64`.** A type still open when its enclosing body finishes
becomes `Int64`. The enclosing body is a function body, a constant's
initializer or a parameter default; a lambda belongs to the body it is written
in. An operation that needs a concrete type before any use has settled the
value applies the fallback there:
- a method call or field selection on the value;
- an implementation query no implementation answers while an open integer
  stands in its types, which falls back those integers and asks again;
- a `match` on it, where it is itself the open integer. A `match` on a value
  whose type only holds one -- the `Option` that `next` hands back from a
  `Range` of literals -- takes it apart by its known head and binds the open
  type, which the binder's uses settle, as `let ... else` and a walk's binder
  do;
- a conversion's operand;
- a generic argument nothing else settles.

**Open types never escape a body.** A signature, a constant's type and a
default's value are settled before anything outside the body reads them. After
every body is checked, one pass replaces each recorded open type with what it
settled on. An open type that survives that pass is a compiler defect, not a
type.

**A conflict is reported where it happens.** An open type that settled on one
type and then meets another is refused at the second meeting, under the rule
that site already uses, with a label where it settled ("settled to `UInt8`
here") or where an operation forced the fallback ("fell back to `Int64` here,
where an operation needed a type"). **A literal's range is checked against the
type it finally has.** `let big = 300` followed by `let small: UInt8 = big` is
[T-Literal] at `300`, labelled at the use that settled it.

**What 0092 changes.** 0092's two passes keep their division: a bare literal
waits, and a range of literals determines its own type. What the range
determines is now `Range[open]`, so a type parameter it settles still holds an
open element type, and the callback's body settles that. A parameter settled to
an open type needs no waiting, because what settled it is itself settled later.
The expected result type also settles parameters no argument has settled,
between the two passes. 0092 rejected that on the evidence of
`tests/generics/an_annotation_does_not_reach_back.lin`; that case no longer
exists, and the checker follows this rule. It is recorded here rather than left
implicit.

## Consequences

The type pool gains one kind, `open_integer`, an ordinary `TypeId`, so an open
type flows through binding types, callback parameters and instantiations such
as `Range[open]` with no parallel channel. One union-find table decides
settling; every meeting site reaches it through the checks that already compare
types. A site that compares types by identity instead can only refuse a valid
program, never accept a wrong one, and the finishing pass's assertion catches a
type nobody resolved.

The table holds one entry per literal site and each body keeps the variables it
created, so both are sized by the source. Resolution is near-constant with path
compression, and the finishing pass is linear in the tables it rewrites.

An accepted program that relied on the old default only ever had its literals
meet `Int64` or nothing, so its types and its emitted code are unchanged.
Programs that were refused for line order now compile.

An open integer answers a trait query only when every integer type answers it,
so `Range[open]` meets `Range`'s bounds without being forced; the concrete
implementation is chosen once the type is settled. A query that finds nothing,
such as `Equatable` for `Maybe[open]` where only `Maybe[Int64]` implements it,
falls back and is asked again, which is the answer the old default gave.

A folded value is checked against the type it finally has, not the type it had
when it was folded: a literal, a negation and an arithmetic result each wait for
their variable's final type, so `let sum = 200 + 100` used as a `UInt8` is
[T-Overflow] at compile time, as the annotated spelling is.

Some compiler-generated symbols, such as `closure_release.N`, are numbered by
pool position. The open entries shift those positions, so the numbers move; the
code they name does not.

## Alternatives considered

**Untyped constants, typed at each use.** A literal-valued binding would stay
untyped and take a type each time it is read. That handles `let k = 5` read as
two types, but not a `var` accumulator, whose one storage location needs one
type, or a range handed to a generic callback, whose element type is one type
parameter. Rejected because those are the cases D04 exists for, and a binding
with a different type at each read is harder to explain than a binding with one.

**A structural pre-scan of each body for the first concrete use.** A walk ahead
of checking would find what each literal meets. It is a second implementation of
typing, which is the defect shape this compiler has had most often
([0048](0048-one-question-has-one-answer.md)): it would have to know every
meeting site the checker knows and would disagree on the ones it missed.

**A `match` forces every open integer its scrutinee's type holds.** The
arms are checked against the scrutinee's type, which suggests settling all of
it before any arm is read. Rejected because a pattern under a variant is a
flat list of binders: it compares nothing inside the payload, so nothing there
needs a type yet. Forcing it made `match` the one form that disagreed with
`let ... else`, the walk binder, and a method call on the same value: the loop
`match Iterator.next(&range) { Some(i) => total += i, ... }` fixed a range of
literals at `Int64` where `for i in range` settled it from `total`. A
differential of the compiler with and without the forcing over every case in
`tests/` and `examples/` found no accepted program whose code, types or
diagnostics changed; only programs it refused became accepted. A `match` on a
binder that holds the open type is a match on an open integer itself, so
`Some(x) => match x { 0..=255 => ... }` still falls back at the inner match.

**Check, and rewind if a later use disagrees.** Check with `Int64` and redo the
body with the type a later use named. Rejected because the diagnostic sink
appends and has no rewind, and every side table the checker writes would need
one too; a body checked twice also doubles the cost of the pass on the programs
that need it.
