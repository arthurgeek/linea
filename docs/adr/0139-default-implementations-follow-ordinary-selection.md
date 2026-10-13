# Default implementations follow ordinary selection

Status: Accepted — 2026-09-17

Supersedes [0093](0093-two-implementations-that-could-answer-once-are-refused.md)
for explicitly marked default implementations; its ordinary coherence rules
remain in force. Extends [0081](0081-an-implementation-is-generic-over-its-head.md)
and [0138](0138-hash-maps-preserve-entry-ownership.md).

## Context

Map queries need a separate representation for owned text: String is stored,
while Str is enough to look up or compare it. Ordinary struct keys need only
their existing equality. Requiring an identical Key block on every struct makes
derived Hash incomplete for its common use. Putting query types into Hash would
couple content hashing to a collection's query policy.

An unrestricted blanket implementation conflicts with explicit String queries.
Choosing whichever applicable implementation happens to appear first would
also let checking and monomorphisation disagree about associated types.

## Decision

`default impl[T: Bound] Trait for T` declares one explicit fallback in the trait's
module. The trait has no type parameters, and the implementation has exactly one
parameter used as its whole head. It supplies ordinary functions and associated
types. Inherent implementations, templates and delegated implementations cannot
be defaults. Duplicate defaults are rejected.

Ordinary implementations retain their existing coherence rules and structural
precedence. Their failed bounds do not activate a default. Existing ambient,
closure, bound and observation-forwarding suppliers keep precedence. Only a
remaining lookup may select the default after proving its bounds.

Unresolved receiver parameters and associated projections cannot select defaults.
A nominal generic receiver may select one only if no ordinary implementation
exists for its constructor. Otherwise later substitution could change the
associated types selected while checking. Generic Key code consequently uses
K.Query rather than assuming it equals K.

The canonical indexed matcher records structural and applicability evidence;
the same evidence answers availability and selection. Frozen typing carries
prepared results into instantiation and MIR. No library trait name is privileged.

## Consequences

Hash retains only its hashing contract. Key supplies a default using Query=Self
and equality, while String's explicit Key uses Str. Derived and handwritten
hashable concrete keys share that default. Redundant same-type Key implementations
are removed.

Default candidates add a trait-indexed lookup and their ordinary memoized bound
obligations. They do not require scanning every implementation. Open generic code
may need an explicit trait bound even when all its known instantiations happen
to use the default. Parameterized default traits remain unsupported.

## Alternatives

Combining Hash and Key removes boilerplate by giving hashing an unrelated query
responsibility. Automatically deriving Key whenever Hash is derived makes one
library name special or requires a separate compound derivation mechanism.
Unmarked blanket specialization obscures which implementation is a fallback.
Falling back after an ordinary bound fails makes selection depend on predicates
and can change associated types between generic checking and instantiation.
