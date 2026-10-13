# 0141: JSON documents own bounded trees and validated number tokens

## Status

Accepted. Builds on [0095](0095-the-system-allocator-is-named-rather-than-received.md),
[0123](0123-observations-carry-owner-dependencies-through-callable-contracts.md)
and [0140](0140-aggregate-constants-retain-checked-construction-plans.md).

## Context

JSON values must survive disposal of input bytes and must report malformed
input and allocation refusal without trapping. Arbitrary numeric tokens cannot
be represented losslessly by Int64, UInt64 or Float64. A depth check confined to
the parser would leave manually built trees able to overflow recursive traversal.
Borrowed child mutation would bypass cached height checks.

## Decision

`std.json.Value[A]` is opaque, stores a private recursive node, its allocator
and exact container height. Nodes use ordinary String, Vec and Map ownership.
Handwritten Release settles their payloads and backing storage without allocating;
no compiler exception or implicit disposal is introduced.

Scalars have height zero, empty containers one, and populated containers one
plus their greatest child height. Parsing and every public attachment enforce
128 containers. Child observations are read-only. Removing or replacing a child
recomputes height over immediate siblings; object iteration visits retained
bucket capacity. New object names are bounded at 4,096.

A number owns its validated decimal token. Parse and write preserve its bytes,
including negative zero, fraction precision and large exponents. Integer access
requires an integer spelling and checks machine range. JSON numbers and strings
use shared scanners; output uses one escaping routine. Public constructors
accept borrowed text and explicit allocators.

Parse limits are an aggregate constant with caller-overridable fields. Options
and encoded input extent precede UTF-8 checking; grammar/traversal checks follow.
Duplicate decoded member names are rejected at the second opening quote before
parsing that member's value. Errors retain an independent kind and byte offset.
Bulk parsing builds containers directly and maintains height incrementally.

Mutation refuses before changing the destination and returns the complete
incoming owner. Replacement returns the previous value. Reusing the exact stored
key after removal reaches its tombstone before Map's allocation path, so
same-key replacement needs no allocation even at the member limit.

`write` borrows the document and forwards the writer's exact error/dependencies,
without closing or flushing it. `render` owns separate output and settles its
partial text on refusal. A failed write may have emitted a prefix. Object member
order is unspecified. The deterministic Map hash is not collision-resistant;
input/member bounds do not imply constant-time hostile lookup.

Typed codecs are ordinary `Encode` and `Decode[A]: Release` implementations.
Top-level decode builds a temporary document, constructs an independently owned
target, and releases the document on either outcome. `from_value` uses the same
Decode operation with an existing document and the same allocator type. Decode
errors own field/index path segments; failed path allocation releases the partial
error and becomes Allocation. Parse errors retain their original byte offsets.

Struct templates use [ordinary construction derivation](0142-construction-derives-expand-to-ordinary-source.md),
explicit field defers and final unknown-field checking. Missing Option fields
become None through the ordinary `Decode.missing` operation; custom defaults,
validation and enum mappings remain handwritten. Map key decoding refuses
collisions between distinct names after conversion. Encoding borrows input,
threads the writer separately from bounded state, and checks one value per
nested codec. Writer errors poison that state and retain their dependencies.
Custom key encoders must map unequal keys to distinct names; streaming output
does not retain a duplicate-name set.

## Consequences

Documents own their text and may outlive input; an allocation copy is the cost.
Allocator dependencies, including distinct handles of one allocator type,
remain visible to ordinary ownership checking. Runtime stack depth is bounded
independently of compiler type depth. Height-changing replacement/removal may
scan siblings, while append and parser bulk construction maintain height
incrementally. Number conversion is an explicit, separately checked operation.

Adjacent stdlib tests cover grammar, limits, mutation and writer behavior.
Private allocator instrumentation checks individual disposal and allocation
refusal. Negative source cases protect child/allocator lifetimes. A pinned,
optional JSONTestSuite corpus records Linea's duplicate and Unicode policies.
Typed decode temporarily retains both document and target storage. Borrowed
text decoding and streaming decode require separate ownership/API designs;
there is no owning Decode implementation for Str.

## Alternatives considered

- Borrow input text: avoids copies but prevents independent document ownership
  and needs a distinct lifetime/API design.
- Convert every token to a machine number: loses large integers and lexical
  precision, or rejects valid JSON that needs no arithmetic.
- Expose mutable children or check depth only while parsing: allows attachments
  that invalidate cached height and the traversal bound.
- Allocate a new key during replacement: makes an otherwise storage-neutral
  operation fail under allocator exhaustion.
- Use last-wins duplicate semantics: discards a supplied value and hides
  ambiguous configuration before domain validation can see it.
