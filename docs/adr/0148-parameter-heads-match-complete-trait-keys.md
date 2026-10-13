# Parameter-headed implementations match complete trait keys

Status: Accepted — 2026-09-21

Extended by [0213](0213-a-trait-may-be-implemented-for-a-callable-type.md)
with callable-type heads keyed by shape.

Partially superseded by [0165](0165-an-attached-derive-requires-each-field-type.md):
an exact cycle that passes through a derived implementation holds.
The sentence that open trait predicates do not prove headers disjoint is
refined by [0192](0192-iterator-operations-belong-to-every-sequence.md).

Supersedes the constructor-only ordinary head restriction in
[0081](0081-an-implementation-is-generic-over-its-head.md) and the
constructor-only coherence partition in
[0093](0093-two-implementations-that-could-answer-once-are-refused.md).
Their structural overlap rule and applied-constructor head restrictions remain.
The separate default tier in
[0139](0139-default-implementations-follow-ordinary-selection.md) is unchanged.

## Context

Explicit total conversion should have one implementation point. Defining
`From[Source]` for Destination can supply `Into[Destination]` for Source through
an ordinary generic implementation. The source and destination are independent
key parameters, so a constructor-headed family cannot express the bridge.

The compiler already admits Integer-constrained parameter heads and recovers
parameters from receiver plus trait arguments. Its parameter bucket, lookup
preparation and cross-head coherence checks were restricted to integer
receivers. Simply removing the head diagnostic would leave noninteger lookup
and coherence incomplete. Receiver-only method discovery also cannot infer the
destination until the call supplies result context.

## Decision

An ordinary trait implementation may use one declared parameter as its entire
head, without an Integer bound. Every implementation parameter must be
recoverable by structural matching of the receiver and trait arguments.
Associated projections cannot be inverted to recover a parameter. Applied
constructor heads keep their parameter order and admit no partially specialized
patterns; which binders they may omit is the complete-key rule of
[0142](0142-construction-derives-expand-to-ordinary-source.md).

A parameter head has no type-side module owner. Its implementation belongs in
the trait's declaring module, and cannot be inherent.

Parameter-headed implementations use a trait-indexed bucket. Complete-key
matching binds parameters once and the canonical constraint solver decides
applicability. A parameter head may overlap an ordinary constructor head of the
same trait, so declaration-time coherence compares those pairs as well as the
existing within-constructor pairs. Open trait predicates do not prove headers
disjoint. Integer retains its closed eight-type receiver domain: an
Integer-constrained receiver cannot overlap a noninteger constructor. There is
no ordering by specificity among ordinary implementations.

A method name can be a potential candidate while destination parameters remain
unknown. This is discovery, not evidence satisfying a trait bound. Ordinary
argument/result inference must settle the full key and prove all prerequisites
before selecting the implementation. Missing destination context is diagnosed;
competing unrelated trait members remain ambiguous. Potential discovery checks
the closed receiver domain, but does not partially solve user predicates with
unresolved implementation parameters. A false receiver-only user prerequisite
therefore does not eliminate an otherwise open candidate. Prepared typing records
selection for instantiation and lowering. A generic implementation member is
not a concrete emission root merely because its head has no applied arguments.

A recursive prerequisite proof may re-enter an active implementation only with
a strictly smaller complete receiver-and-trait-argument key. Exact, mutual and
structurally growing cycles do not establish applicability and produce the
ordinary missing-bound diagnostic. Shrinking nested-container and trait-argument
requirements remain supported. The measure sums each key root's distinct reachable type nodes separately.
It follows applied arguments, borrow referents, array elements and callable
parameter/result types. Unresolved parameters/projections are leaves; nominal
storage fields are excluded. Per-root counting preserves progress when an
unchanged trait argument shares nodes with a shrinking receiver. Counts fit the
TypeId domain; a wider sum avoids overflow without expanding shared DAGs. This conservative rule bounds proof search without an arbitrary
recursion-depth limit; it does not assert that every rejected trait equation is
mathematically unsatisfiable. A failed ordinary prerequisite still blocks the
default tier under the existing structural-precedence rule.

The standard library defines consuming From and Into with carried dependencies:

```linea
pub trait From[T] {
    fn from(sink source: T) -> Self where carries(source)
}

pub trait Into[T] {
    fn into(sink self: Self) -> T where carries(self)
}

impl[T, U: From[T]] Into[U] for T {
    fn into(sink self: T) -> U where carries(self) {
        From.from(self)
    }
}
```

From is the implementation point. Under structural coherence, a direct Into
implementation overlaps the bridge even when its From prerequisite is absent.
The adoption shares Rust's one-way bridge, not its full coherence behavior.
There is no automatic reverse conversion, identity bridge, assignment coercion,
error conversion through `?`, or conversion-specific compiler dispatch. The
existing observing Convert trait continues returning Option. Ordinary module
ownership still applies: a From implementation belongs to its trait or
destination's module; a locally declared source alone grants no ownership.

## Consequences

Ordinary user traits can express the same delegation shape as conversion. A
single From implementation supplies both explicit call orientations while
ownership checking still requires the source's obligations to be transferred
or settled. Result dependencies cannot refer into storage destroyed by the
conversion.

Cross-head coherence is confined to one trait: with P parameter heads and C
constructor heads, it adds at most P times C structural comparisons, excluding
closed-domain mismatches. Existing within-bucket checks retain their indexed
filtering. No global implementation scan belongs inside this operation.
Normal checking prepares exact trait queries and requested method names.
Editor analysis requests complete member availability from the same checker;
ordinary compilation does not precompute every receiver/blanket pair for
possible editor queries. Applicability remains memoized compiler work, not a
new pass or persistent global cache.

## Alternatives

Conversion-specific compiler synthesis would give library names privileged
semantics and duplicate ordinary dispatch. Parameterized defaults would change
ADR 0139's fallback and generic-stability contract, yet still need destination
inference. Explicit-priority specialization would replace structural coherence
with a new ranking rule. Requiring users to implement both traits repeats the
conversion body and permits the two implementations to disagree.
