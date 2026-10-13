# 115. Emission reads settled semantic answers

Status: Accepted — 2026-09-05; extends 0048

## Context

Concrete instance discovery selected implementations to discover callees, then
MIR searched the implementation index again for the same concrete trait,
arguments, and receiver. Both invoked the same solver, but a shared solver
still repeated a completed decision across a pass boundary. Associated-type
settling also searched that index through the type pool, and checking had
already settled some concrete keys.

The checker also parsed numeric literals and decoded scalar range endpoints.
MIR parsed or decoded their source again. Floating-point comments even claimed
that emission performed the only parse, although checking already converted
the decimal spelling to Float64 to reject non-finite values.

## Decision

A semantic answer needed after its producing pass survives as an immutable
side table. A downstream consumer does not rerun the solver or reread the
source to recover that answer.

The type pool records concrete implementation queries, keyed by trait
declaration, concrete trait arguments, and receiver type. Once implementation
headers and requirements are complete, checking retains its concrete answers.
Instantiation reopens that pool, reads those answers, and adds only queries
that concrete substitutions introduce. Associated-type settling uses the same
entry point. The finished pool retains typed IDs into the original
implementation rows, including a recorded absence for a diagnosed missing
implementation. Emission reads those selections; its sealed pool cannot
solve an unrecorded key.

CLI and editor checks stop after instantiation. They do not emit MIR only to
discard it: the semantic diagnostics already belong to the earlier passes.

Checking records numeric literal values, decoded scalar range endpoints, and
negated integer literals by expanded expression ID. The value remains semantic:
an integer or a Float64. MIR converts a checked Float64 to instruction bits,
but does not perform another decimal conversion. This does not admit floats
as constant expressions; membership and constant folding remain governed by
0059 and their existing table.

## Consequences

Selection storage follows distinct concrete queries and their argument lists,
not every expression in the source. Query hashing and equality take O(A) for
A trait arguments, plus expected constant map work. Only the first query runs
the implementation solver once the implementation relation is settled. Pool
reopening copies the recorded keys in O(Q + A) expected work for Q selections
and A total arguments; it does not solve them again. Keys own their argument
slices; result IDs borrow
the original immutable implementation rows for the compilation's lifetime.

Literal storage is O(L), for the L checked literal nodes whose values emission
needs. Lookup is expected O(1). Checker-local folding state is still discarded;
the handoff does not retain every constant-expression intermediate.

Tests disable implementation search before instantiation and emission, and change literal source
spellings after checking. Emission must retain the recorded semantic answers.

## Alternatives considered

**Share the parser and solver functions only.** Prevents separate algorithms,
but still recomputes answers that a completed pass already owns.

**Memoize inside emission.** Avoids some repeated work within that phase while
leaving the first repeated decision across the boundary intact.

**Retain every checker cache.** Keeps temporary state with no downstream
reader. Only answers needed by later consumers cross the boundary.
