# 102. Computation and storage representations are separate

Status: Accepted - 2026-08-24

Extends [0028](0028-a-type-is-a-pool-handle-and-layout-is-a-table.md).
Supersedes [0031](0031-fields-are-packed-at-their-natural-alignment.md)'s and
[0052](0052-a-slot-is-as-wide-as-the-widest-access-to-it.md)'s scalar-word
consequences; 0052's widest-access rule remains accepted.

## Context

Layout answers how many bytes a type occupies and how those bytes are arranged.
It does not answer how a value is represented while it is computed, how those
bytes are typed when they occupy storage, or whether a MIR result denotes a
value or the managed address of one. Inferring those answers in the verifier and
backend from `TypeId`, instruction tags, and calling-convention predicates gave
one semantic question several implementations.

The initial MLIR backend represented every non-floating scalar as `i64`, every
slot as raw bytes, and every managed address as an integer. That established the
backend but erased declared storage widths and pointer identity. Extending that
model to vectors, additional floating-point widths, or address spaces would
multiply consumer-side inference rather than add one representation case.

## Decision

`mir.Module` carries one `TypeRepresentations` table keyed by every `TypeId` in
the sealed type pool. Each row records a `ComputationRepresentation` and a
`StorageRepresentation`. Lowering derives the complete table once after
monomorphisation has drained and layouts are complete.

Every MIR instruction records a `ResultRole`: `value`, `managed_address`, or
`none`. Every local records a `SlotRole`: `value` or `managed_address`. Lowering
owns these facts and records them while constructing MIR. `arrivesByAddress` and
`returnsIndirectly` remain the shared calling-convention answers.

Integer computation remains wide at `i64`, including the existing overflow and
conversion checks. Integer storage uses the declared width. Boolean computation
and storage, floating-point values, enum tags, aggregate bytes, unit, and invalid
types each have explicit representation cases. Aggregate values travel through
managed addresses and retain canonical byte storage from the layout table.

A managed address is distinct from a raw integer address. Managed addresses
preserve pointer identity through compiler-owned storage and internal calling
conventions. `bytes_addr` and checked raw-buffer handles remain ordinary integer
values and may become pointers only through `load_raw` and `store_raw`. Those
instructions record the region length plus the overflow, bounds, and optional
alignment checks that guard them; verification follows the recorded data flow,
requires the bounds check to use that length, and requires every dependency to
precede its use in the access's block. Generic indirect loads and stores accept
managed addresses only.

The verifier and backend consume `representationOf`, `resultRepresentationOf`,
and `slotRepresentationOf`. They do not derive physical representation from
semantic type structure or independently map instruction tags to backend types.
The verifier proves exact table coverage and role consistency before any
consumer indexes these facts.

## Consequences

Layout and representation remain separate tables because they answer separate
questions. Aggregate size, alignment, offsets, and ABI classification remain
canonical layout answers; representation determines only the physical value or
storage spelling.

Typed scalar accesses change ADR 0052's implemented scalar consequence. A
scalar slot is now as wide as its declared storage access rather than always a
word. Address slots remain pointer-wide, aggregate slots retain canonical
layout, and the governing widest-access rule remains unchanged.

Adding a computation or storage form extends exhaustive MIR switches. A new
form cannot silently inherit the integer spelling. The cost is one immutable row
per sealed type, one role per instruction, one role per local, and linear
verification over those domains.

## Alternatives considered

**Record a complete physical representation on every instruction.** Rejected
because most results use their type's computation representation. Repeating it
per instruction wastes space and permits two instructions of one type to drift.
The role records only the distinction the type table cannot answer.

**Let each consumer infer representation.** Rejected because this is the model
being replaced. The verifier, dump, and backend would each maintain a switch
over types, tags, and conventions, and agreement would be a testing property
rather than an architectural invariant.

**Convert MIR to full SSA with block arguments and aggregate values.** Rejected
for this change. Typed values and managed pointers do not require replacing
slot-backed named storage or control-flow joins. Aggregate SSA remains a
separate decision with different ownership, optimization, and backend costs.
