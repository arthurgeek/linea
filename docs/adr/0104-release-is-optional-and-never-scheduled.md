# 104. Release is optional and never scheduled

Status: Accepted - 2026-08-25; supersedes
[0097](0097-release-is-named-never-scheduled.md) in full and extends
[0063](0063-disposal-is-scheduled-never-inserted.md). Proposed
[0103](0103-linear-constrains-consumption-release-grants-one-way.md) would
extend this record with deferred container decisions.
[0208](0208-defer-let-binds-and-schedules-its-release.md) narrows its
no-scheduling sentence to "never without a written `defer`".

## Context

ADR 0097 separated an explicitly named release operation from compiler-created
disposal, but made `Release` total over every type. The ordinary-operation
decision is implemented: release is reached through source and checked through
the same trait machinery as any other call. Totality is not. Types without one
context-free terminal operation are valid, and pretending that every type has
one would erase useful protocol distinctions.

The capability also has a settled library boundary. It is declared by its own
module rather than by the compiler or the memory library, and no syntax makes
its name ambient.

## Decision

**`Release` is an optional ordinary trait. Every invocation is reached through
an expression written in source; the compiler never selects, inserts, or
schedules a release invocation.**

The exact capability is `std.release.Release`, with this declaration:

```linea
pub trait Release {
    fn release(sink self: Self) -> ()
}
```

It is declared in `std.release` and is not part of the prelude. A module that
names the capability imports `std.release` and brings `release.Release` into
scope through the ordinary library mechanism.

A type conforms only when it has an implementation. Missing conformance is
valid until an operation requires a `Release` bound, where ordinary bound
checking reports `[T-Bound]`. The compiler gives the trait no special universe,
ownership, scheduling, MIR, ABI, or backend meaning.

`Linear` and `Release` answer independent questions. `Linear` means that a value
must be consumed exactly once. `Release` means that one context-free consuming
operation is available. Neither implies the other: a Linear type may omit
`Release`, a Free type may omit or implement it, and implementing `Release`
does not make a type Linear.

`defer value.release()` remains a schedule the programmer wrote. ADR 0063
decides where that expression runs and ownership decides where a move cancels
it. The trait itself schedules nothing.

## Consequences

Types whose terminal transitions require policy or additional context do not
need a generic escape operation. Generic operations state `T: Release` only
when they call the capability, and each use discharges that bound through the
ordinary implementation index.

Existing `Release` implementations remain ordinary named behavior. Nothing is
called at scope exit unless source explicitly scheduled or directly reached the
call.

Container storage and terminal-operation policy remain deferred. ADR 0103 may
extend this decision when those operations are built; it does not decide whether
the capability is optional or whether the compiler schedules it.

## Alternatives considered

**Keep `Release` total over every type.** Rejected because a no-op
implementation for every Free type is boilerplate rather than a semantic
guarantee, while requiring one terminal fallback for every Linear protocol
weakens protocols whose caller must choose the transition.

**Infer release conformance from `Linear`.** Rejected because an exact-once
consumption obligation does not choose how the value is consumed. The two
questions remain independent.

**Schedule release from the compiler.** Rejected because it is implicit
disposal under another name and contradicts ADR 0063. Written direct calls and
written `defer` expressions already provide the required mechanism.

**Place `Release` in the prelude or under `std.mem`.** Rejected because no syntax
requires the name and the capability does not imply memory ownership. The
dedicated non-prelude module states the narrower contract.
