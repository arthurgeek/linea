# 316. Device aggregate calls use independent caller storage

Status: Accepted — 2026-11-27.

## Context

Ordinary numerical functions construct arrays and fixed matrices through helper
calls. A scalar-only internal device ABI excludes these functions even when all
of their data and operations are admitted. Returning a pointer into a helper’s
Function-storage allocation would leave the caller referring to expired storage.
Passing an aggregate’s existing allocation directly would also conflate value
arguments with aliases, and subobjects need not share the callee’s pointer type.

## Decision

Keep the public scalar map/reduce root ABI. Internal admitted helpers may accept
fixed Float32 arrays and certified fixed matrices by read or sink, and return
these aggregates by value. Copy every aggregate argument into an independent,
exactly sized caller allocation. Give each aggregate result a caller-owned
output allocation, passed as an additional argument; copy the return value there
before the helper returns. Private storage uses fixed Function-storage memrefs
of raw Float32 words, preserving bit patterns.

Admission consumes verified MIR and retains allocation origins and checked
byte-offset intervals. Copies require aligned, contained ranges and refuse
unresolved overlap. Admission refuses `inout` and stable-address parameters
of every type because a private copy cannot preserve their caller-visible
storage identity.
Recursion, indirect calls, host pointers and resource-bearing aggregates remain
outside the device profile.

Convert structured control flow, memrefs and arithmetic to SPIR-V explicitly
before reconciling conversion casts. A helper signature must not leave an
unrealized pointer-to-memref materialization in its converted body.

## Consequences

Source functions keep one meaning on CPU and GPU. The ABI adds private copies
and caller allocations; these costs can later be optimized without changing the
public tensor interface. Unsupported functions still have no device image and
remain valid CPU functions. No implicit CPU fallback is introduced.

## Alternatives considered

- **Return a pointer to a helper local:** violates allocation lifetime.
- **Pass existing storage without independent argument copies:** introduces
  aliases and incompatible subobject pointer types across a value-call boundary.
- **Admit inout through copy-in alone:** loses caller-visible writes.
- **Require users to inline numerical helpers:** makes library abstraction change
  which otherwise identical numerical functions can execute on the device.
