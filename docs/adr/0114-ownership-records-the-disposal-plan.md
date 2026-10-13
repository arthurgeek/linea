# 114. Ownership records the disposal plan that lowering emits

Status: Accepted — 2026-09-05; refines 0034 and 0063

## Context

Ownership, instance discovery, and MIR each maintained stacks of deferred
expressions and loop scope marks. Ownership placed schedules and decided
their cancellations; later passes reconstructed the placements. MIR also
consulted the cancellations. A check
that the second walk only emitted placements seen by the first detected some
drift, but could not prevent omitted placements or disagreement about order.

## Decision

Ownership owns placement, order, and cancellation of deferred expressions.
Its graph builder records each placement in execution order, including
expressions that produce no ownership operations. After flow checking,
ownership freezes surviving placements into a `DisposalPlan`, keyed by the
expanded expression ID of each exit.

Instance discovery visits the ordered expressions recorded at each exit, and
MIR emits them. Neither maintains a deferred-expression stack, loop schedule
marks, or a cancellation policy.
Callers that instantiate or lower syntax first run ownership and pass its plan, including
debug and test callers. An empty plan means no deferred expressions run.

The two graphs retain their distinct representations. Constructing MIR control
flow does not authorize it to decide a schedule a second time. Nested exits
inside a rejected deferred body do not recursively emit its enclosing plan.

## Consequences

The intermediate placement list costs O(P), where P is the number of placements
visited by the ownership builder. The finalized plan costs O(S + E), where S
is the number of surviving placements and E the number of exits with surviving
schedules. Producing the plan is O(P) expected time; querying one exit is
expected O(1), followed by O(k) work to emit its k scheduled expressions.
No table is sized by all program expressions.

Cancellation data remains private to ownership. The pass hands lowering a
positive answer about what runs, rather than information requiring another
pass to reconstruct candidates before it can use the answer.

## Alternatives considered

**Keep both walks and strengthen the agreement check.** Still requires two
implementations of placement and order, and an additional comparison mechanism.

**Share only the reverse-stack traversal.** Removes repeated loop syntax but
leaves both phases deciding which scopes and schedules an exit includes.

**Lower MIR from the ownership graph.** Changes every control-flow lowering
site to resolve a narrower duplication. An exit-keyed side table carries the
missing answer without introducing another graph or replacing either one.
