# 126. Observations project referent places transparently

Status: Accepted — 2026-09-09

Supersedes the synthetic `.value` projection syntax of
[0123](0123-observations-carry-owner-dependencies-through-callable-contracts.md).
Its dependency, ABI, and trait-conformance rules remain in force. Extends
[0088](0088-a-projecting-member-is-a-place-not-a-function.md).

## Context

A stored observation of a record with a value field requires value.value to
reach that field. Lending bindings already provide direct field access, so the
wrapper property makes ordinary stored observations unnecessarily different.
Its removal needs an unambiguous whole-referent projection and must not grant
write or consuming authority through shared storage.

## Decision

Unary `*` selects exactly one readonly referent place. Field lookup follows
observation layers transparently. A real field named value is addressed as
reference.value, while *reference addresses the whole referent. The synthetic
property is removed without a fallback or compatibility spelling.

Read-only target methods are available through both dot and qualified calls,
even if the selected method's trait includes mutating members. Check the actual
receiver operation. Prefer an applicable explicit observation implementation
before referent forwarding. This does not grant target-trait conformance at
generic bounds or consume/mutate a noncopyable referent through a shared borrow.

Contract source paths may dereference observations. Carries of the observation
and carries of its referent represent different dependency sources. Result
targets still name owned result components and cannot cross an observation into
external referent storage. Retention cannot write through readonly dereference.

Typing records one projection and receiver-adjustment answer. Ownership paths,
contract projection, lowering, completion, and rename consume it. Migration
distinguishes synthetic projections from real fields by resolved identities,
not by replacing every occurrence of the word value.

## Consequences

Stored and lending observations have consistent field ergonomics. Copying an
eligible referent remains a separate operation, except for scalar snapshots.
No mutable stored observation, full mixed-trait forwarding, or new region model
is introduced.
