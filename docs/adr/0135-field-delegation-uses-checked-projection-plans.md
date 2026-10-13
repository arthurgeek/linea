# 135. Field delegation uses checked projection plans

Status: Accepted — 2026-09-17

Supersedes the AST-path-only representation and declaration-only cycle-check
timing in [0088](0088-a-projecting-member-is-a-place-not-a-function.md).
Its place semantics, access ceilings and cycle rejection remain in force.
Extends [0122](0122-a-traversal-may-read-its-receiver.md).

## Decision

`impl Index[I] for Wrapper via field` delegates through one stored field in
the wrapper's defining module. It is the whole implementation, not a derive
or a member override. Other traits are rejected. It shares coherence, element
types, bounds checks, access ceilings and owner dependencies with handwritten
Index projections. Each source operand is evaluated once.

`trav positions via field` separately enables lending traversal over a fixed
array's ascending positions. Infer its sole applicable integer Index key;
ignore FromEnd, and diagnose absent or ambiguous integer keys. An explicitly
typed ordinary traversal remains the way to choose another key or order.
The exclusive endpoint must fit the key, including every type admitted by a
symbolic integer key's bounds. Existing Iterator requirements still apply.
Neither form grants consuming iteration or schedules cleanup.

The AST preserves the authored target token. Type checking records field
identity and a canonical projection plan: an authored path or forwarding
through an optional stored-field step. Forwarding retains either a selected
backing projection or a generic Index obligation. Ordinary bound indexing uses
the same record without a field step. There is one coherence candidate per
authored implementation and no generated source implementation.

Static paths are checked at declaration time. For generic obligations,
instantiation discovery selects the concrete backing with the shared
implementation query and validates its ceiling and expansion cycle. Lowering
consumes that prepared answer. Ownership consumes the checked projection path,
including for lending loop binders. Unknown backing contents conservatively
retain their owner dependencies; discarding values performs no cleanup.

Traversal plans distinguish authored expressions from checked constant array
ranges. Tooling reads the field-reference table; retained-library snapshots
relocate the plans' typed identities. Neither reconstructs delegation syntax.

## Alternatives

A derive would add a second spelling for implementation selection. Implicit
traversal would conflate indexing with iteration order. Generating source AST
bodies after type checking would violate representation ownership. Keeping a
second generic-index resolver in lowering would allow selection to diverge
from discovery. The checked plans avoid each of these obligations.
