# 269. A test in a trait declaration is a member of nothing

Status: Accepted — 2026-11-10; extends 0247

## Context

A trait may give an operation a body, which every implementing type runs
(`Sequence.map`, `Iterator.find_counted`). A trait's braces refused a `test fn`,
so the tests of a provided operation were written at module scope, away from
the operation, while the tests of every other function in the library sit
immediately after it, inside an inherent `impl` where the function is a member
(ADR 0247). The refusal also carried the rule code [S-Entry], the entry-point
rule, although nothing in that rule says what a trait's braces hold.

The three facts ADR 0247 records about a test hold in a trait as they do in an
`impl`: a test is not instantiated, no expression names one, and it is reported
by its module's path and its own name. A trait adds one more: its body is
written over a symbolic `Self`, the trait's parameters and its associated
types, none of which stands for a type until an implementation is selected, and
no implementation is selected where a test runs.

## Decision

A `test fn` or `test trap fn` may sit inside a trait declaration. It is a
member of nothing there, under the rules ADR 0247 gives a test in an inherent
`impl`: named, resolved and run as if it were written at module scope.

- It is no part of what the trait declares. An implementation neither supplies
  it nor sees it, `Trait.name` does not reach it, and an import of the trait
  reaches no test.
- Neither `Self`, the trait's type parameters nor its associated types, alone
  or through `Self`, name a type in it. Writing one is refused under [S-Test],
  and the test names a type that implements the trait.
- Its name is in the module's namespace ([N-Duplicate]), and its qualified name
  is its module's path and its own name.
- A test declares no visibility there, as anywhere, and `export` before it is
  refused under [S-Export], as in an `impl`.

A declaration a trait's braces do not hold is refused under [T-Impl], the rule
that says what a trait declares and what an implementation supplies. The same
refusal in an `impl` stays [S-Entry]: that rule's text is where the language
says an `impl` contains only the member declarations its grammar lists.

In the compiler the parser reads the test with the routine that reads one at
module scope and marks it a test, so `Ast.memberOwner` is `.none` for it and
`Ast.declOwner` keeps the trait it is written in. No pass that pairs a trait's
members with an implementation's sees it. The resolver reads which `impl` or
trait holds a test only to refuse `Self`, a parameter or an associated type in
it, and records each name it refused, so the checker compares a pattern headed
by `Self` with the one type the help names where there is one, and otherwise
checks only the pattern's parts.

## Consequences

The tests of a provided operation sit immediately after it, and the standard
library's `Sequence` and `Iterator` hold theirs. A test in a trait names one
implementing type, so it checks the provided body through that type; a test
cannot be written once for every implementation, which would need a test to be
instantiated.

The help for `Self` in a trait's test carries no fix. An inherent `impl` for
one concrete type names the type `Self` stands for; a trait names none, and
which implementing type the test means is the reader's choice.

## Alternatives considered

**Let `Self` name a type the test declares, as `test[Meter] fn`.** Would let a
test use the trait's vocabulary. Rejected: it adds syntax for one position,
and the test already names the type where it builds the value.

**Run a trait's test once for every implementation.** Makes a trait's test a
law every implementation is held to. Rejected here because a test takes no
arguments and builds its own values, and nothing says how to build a value of
an arbitrary implementing type; a law checked per implementation is a
different feature from placing a test beside its subject.

**Keep the refusal and leave provided operations' tests at module scope.** No
change to the language. Rejected because it leaves provided operations the one
kind of function whose tests cannot sit after it.
