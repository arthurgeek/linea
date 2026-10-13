# 131. Closure invocation and capture ownership are independent

Status: Accepted — 2026-09-10; stored inout capture clause superseded by
[0193](0193-a-closure-may-hold-a-place-lent-inout.md). Supersedes the read-only invocation and capture
restriction in [0130](0130-explicit-captures-use-inline-environments.md); extends
[0123](0123-observations-carry-owner-dependencies-through-callable-contracts.md)
and [0124](0124-copyability-and-settlement-are-independent-capabilities.md).

Extended by [0132](0132-callable-results-separate-types-from-dependencies.md) and
[0173](0173-a-capturing-closure-is-erased-into-allocator-owned-storage.md).

## Context

A callback may own a resource while being called repeatedly. Consuming that
resource on each invocation, copying the callback per item, or requiring every
capture to be discardable prevents stateful adapters and protocol resources.
Neither an empty input nor early termination authorizes implicit cleanup.

## Decision

Capture convention determines each environment field's ownership. Invocation
convention determines access to the environment: read lends it, inout permits
mutation and requires reinitialization, and sink consumes it. Read callbacks
satisfy inout callable requirements; sink requirements remain separate. Direct
mutable invocation uses `&callback(args)`. Stored inout captures remain forbidden.

The typed closure descriptor records owned field ordinals and the invocation
signature. Ownership uses these answers in the existing owner graph. MIR passes
the inline environment with the selected convention; noncapturing bodies keep
their environment-free ABI.

`into_captures()` consumes the closure and returns its concrete environment.
Field names, obligations and external dependencies survive recovery. Conditional
Release is available exactly when every owned field supports Release. Explicit
release visits owned fields in reverse order and never invokes the callback or
releases a read capture's owner. Trait availability and selection share one
semantic supplier; instantiation prepares concrete release calls before MIR
emits their generated body.

Normalized contract paths identify a parameter or a capture by closure identity
and field ordinal. Captured result sources and retained destinations use the
same dependency operations as ordinary parameters. Retaining an input in an
owned capture requires an authored destination contract and inout invocation.
Results may carry external dependencies but cannot borrow closure-owned storage.

Lazy adapters invoke one stored callback and expose `into_parts()` for complete
recovery. Borrowed mutable callback APIs use `_inout` names and leave callback
ownership with the caller, including skipped and allocation-refusal paths.

## Consequences

Stateful and resource-owning callbacks require no heap allocation, implicit
copying or automatic cleanup. Generic code must express the invocation and
settlement capabilities it needs. Callers recovering protocol captures retain
responsibility for their terminal operations. Closure-owned result borrows and
stored exclusive observations remain outside this model.

## Alternatives considered

**Derive invocation from capture ownership.** Rejected because owning a resource
does not imply consuming it on every call, and read captures can coexist with
mutable owned state.

**Copy callbacks before invoking them.** Rejected because mutations would affect
copies and mandatory resources may not be copyable.

**Automatically release an adapter's callback at exhaustion.** Rejected because
exhaustion does not settle arbitrary protocols and would introduce hidden work.

**Reconstruct captured contract sources from names during lowering.** Rejected
because aliases and generic specialization require stable semantic identities;
ownership must validate those dependencies before lowering.
