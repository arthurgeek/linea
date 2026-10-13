# 125. Scalar value positions take snapshots

Status: Accepted — 2026-09-09

Supersedes the universal explicit-copy clause of
[0034](0034-ownership-is-positions-and-a-graph.md). Extends
[0124](0124-copyability-and-settlement-are-independent-capabilities.md).

## Context

Copying an integer from an indexed or borrowed place does not duplicate an
owned container or a resource. Requiring copy around every such value obscures
the operations where aggregate duplication is an actual choice. Broad implicit
copyability would instead conceal large copies and duplicate observation or
allocator descriptors without an explicit operation.

## Decision

A closed scalar classification admits built-in numeric and Boolean values and
explicitly copyable payload-free enums. In a value-consuming position, a place
with one of these types produces a snapshot rather than moving its source.
Unit remains freely usable. A snapshot contains the scalar value and does not
retain the owner's lifetime. Assignment destinations, borrows, and writeback
arguments still identify the original place.

The classification does not follow arbitrary Copyable conformance. Records,
arrays, views, observation descriptors, callable descriptors, and nominal
newtypes require explicit copying when their type permits it. An integer-backed
nominal newtype does not inherit the scalar exception.

An explicit copy of a concretely known snapshot type is rejected as redundant.
The decision uses authored types before monomorphization. A generic body can
still copy symbolic T:Copyable, and instantiating that checked body with a scalar
does not retroactively make it invalid. A concrete scalar expression within a
generic body is nevertheless rejected. Generated code has the same rule, not
a blanket exemption.

One authoritative scalar predicate serves snapshot selection and redundant-copy
diagnostics. Ownership continues to decide positions; type information supplies
the permission. MIR and backend emission consume the settled operation.

## Consequences

Scalar local, field, and indexed reads use the same concise syntax. Aggregate
copies retain their visible cost. Caller and stdlib scalar copies migrate with
this change, including copies emitted through structural templates.

## Alternatives considered

**Implicit copying for all Copyable values.** Hides aggregate and descriptor
duplication beyond the agreed scalar scope.

**Keep concrete scalar copy legal.** Preserves two spellings for the same
operation. The chosen diagnostic keeps concrete source concise while retaining
the operation that generic Copyable code requires.
