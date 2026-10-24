# 247. A test in an inherent `impl` is a member of nothing

Status: Accepted — 2026-10-24

## Context

A `test fn` was refused inside every `impl` ([S-Test]), so a type's tests were
written after its implementation, away from the methods they exercise. The
refusal was a parser rule with no record behind it. The standard library wanted
its tests beside the functions they test, which inside an `impl` means inside
the braces, and the refusal was lifted for inherent implementations: most of
`std/` now writes tests there, including inside generic implementations such as
`impl[T] Option[T]` and `impl[T, A: Allocator] Vec[T, A]`.

Lifting it left a declaration that was half a member. It was named at module
scope and called by the test runner, but `Self` written in its annotations
resolved to the implementation's type while `Self` before a call did not, and
the implementation's type parameters did not resolve at all. Four places in the
resolver each carried an exception for it, and the trait-implementation checks
paired a test with the trait's signatures by name.

Three facts constrain what a test inside an `impl` can mean. A test is not
instantiated: the compiler writes its one call, with no arguments to settle a
type parameter from, which is also why a test declares none of its own. No
expression names a test, so no path through the type can reach one. And a test
is reported by its module's path and its own name, which every tool reading
`linea test` output already relies on.

## Decision

A test inside an inherent `impl` is a member of nothing. It is named, resolved
and run as if it were written at module scope; the braces decide only where it
is written, which the formatter and source rewrites keep.

- Neither `Self` nor the implementation's type parameters name a type in it.
  Writing either is refused under [S-Test], and the help writes the type for
  `Self` where the implementation is for one concrete type.
- Its name is in the module's namespace, so two implementations in one module
  do not each declare a test of one name ([N-Duplicate]). Its qualified name
  is its module's path and its own name.
- In a trait implementation or a template it is still refused. Refused there,
  it is still a test, so neither the unused rule nor the trait's pairing
  reports it a second time.

In the compiler, `Ast.memberOwner` answers whether a declaration is a member,
and is `.none` for every test. `Ast.declOwner` keeps the braces a declaration
is written in.

## Consequences

A test in a generic implementation writes concrete types, `Boxed[UInt8]`
rather than `Self`, which makes the instance it tests visible where it is
tested. A test cannot be written once for every instance of a generic type;
that would need a test to be instantiated, which nothing in the runner does.

Every membership question asks one accessor, so a pass written later cannot
treat a test as half a member by asking the containment question instead.

## Alternatives considered

**`Self` and the parameters mean what they mean in a member.** Natural in a
non-generic implementation, where `Self` has one meaning. In a generic one
nothing settles the parameters, so `Self` would mean one thing in a concrete
implementation and be refused in a generic one, and moving a test between the
two would change whether it compiles. Rejected for one rule over two.

**Refuse a test in a generic implementation.** Removes the question of what the
parameters mean by keeping tests out of the implementations whose meaning they
could not have. Rejected because those are where the library's tests sit,
beside the generic operations they test, and the refusal would move them back
out of the braces for a restriction a concrete type in the test already meets.

**Scope a test's name by its implementation, reported as `Inbox.starts_empty`.**
Lets two implementations each declare a test of one name. Rejected because it
makes the braces part of the test's identity: moving a test out of an `impl`,
which changes nothing it runs, would rename it in every report and every
filter, and a test would then be the one declaration whose name depended on the
braces around it.
