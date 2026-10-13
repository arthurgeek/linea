# 158. A function value implements Release

Status: Accepted — 2026-09-24. Extends 0104 and 0131.

Extended by [0173](0173-a-capturing-closure-is-erased-into-allocator-owned-storage.md).

## Context

[ADR 0104](0104-release-is-optional-and-never-scheduled.md) makes `Release` an
optional capability: a type conforms only when an implementation says so. The
standard library supplies one for every scalar, `Str` and `()`, and
[ADR 0131](0131-closure-invocation-and-capture-ownership-are-independent.md)
gives a closure one exactly when every owned capture has one, so a
noncapturing closure always releases.

A structural function value, `fn(value: UInt8) -> UInt8`, had none, and no
source could supply one: an implementation names one type, and a callable type
is one type per signature. So `mem.Vec[fn(...), A]` could be built and filled
but never released, because `Vec`'s `Release` requires its element's. The
HTTP router keeps its handlers in exactly that vector. A noncapturing closure
converted to a function value also lost the capability it had as a closure,
though the value it became owns strictly less.

## Decision

**Every structural function value implements `std.release.Release`, and
releasing one does nothing.** A function value is a code pointer: it owns no
storage and observes nothing an owner must settle. The supplier is the one that
already answers for closures, so availability and selection stay one rule:
a function value is a closure with no owned field. Instance discovery plans its
release with no calls, and lowering emits an empty body placed at the trait
member it implements.

## Consequences

- A container of function values is released like a container of numbers, so a
  dispatch table needs no wrapper type whose only purpose is a no-op release.
- Converting a noncapturing closure to a function value keeps its `Release`.
- Nothing is scheduled: as for every `Release`, a call happens only where source
  writes one.

## Alternatives considered

**A wrapper struct with a hand-written no-op release.** Each dispatch table
would declare one, which is the boilerplate ADR 0104 rejected when it declined
to make `Release` total, and it leaves the gap for the next table.

**Make `Release` total over copyable types.** Rejected for the reason ADR 0104
gives: a copyable type may still carry a protocol whose terminal step needs a
choice, so conformance stays declared. A function value is included because
its representation, not its copyability, settles that it has nothing to settle.
