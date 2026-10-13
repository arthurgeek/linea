# 118. Unobserved array initializers are omitted during lowering

Status: Accepted — 2026-09-08. Extends
[0061](0061-an-array-is-a-value-of-a-fixed-size-type.md).

## Context

An array initialized with primitive literals may subsequently have every
observed element overwritten. A measured prefix-writing kernel retained its
512-byte initialization in optimized machine code, even though both writing
and reading loops use the same immutable bound. Removing only that initialization
in a native control improved runtime while preserving checked accesses.

The AST retains resolved binding identities and the structured loops needed to
prove this relationship. MIR control flow and checked index operations make
reconstructing it later more expensive. The language still requires initialized
array values; an optimization cannot make an unwritten element observable.

## Decision

Lowering records an ExprId-keyed side table for literal initializers whose
values cannot be observed. Eligible arrays are mutable locals of primitive
element types, initialized by nonempty lists of numeric or Boolean literals.
The proof reads existing resolver bindings and checker types.

A complete prefix write must be unconditional within a zero-origin UInt64 loop
whose induction advances by one to an immutable local bound. All later array
accesses must occur in loops over the same bound. Reading the array before the
prefix write completes, observing a suffix, passing the array elsewhere,
changing the induction unexpectedly, or encountering unsupported control flow
rejects the proof. A bound larger than the array still reaches the existing
index trap before any later observation; the proof does not elide checks.

The array-literal producer claims its ordinary storage but omits element stores
only for a recorded initializer. There is no new language form, MIR instruction,
backend assumption, or optimization pass. Literal eligibility excludes effects
and primitive element eligibility excludes resource cleanup.

## Consequences

The proof exposes dead initialization before lowering obscures the structured
relationship. Storage layout, ownership, source diagnostics, and checked
arithmetic remain unchanged. Functions without eligible array declarations
perform only a scan of their top-level statements and allocate no proof tables.
Eligible bodies require a bounded walk and sparse tables keyed by local binding
and expression identities. The implementation rejects unsupported shapes
conservatively; it does not claim general definite-initialization analysis.

Compiler cost and generated runtime must be measured together. The native
control establishes headroom, while production measurements establish whether
the added proof work is justified.

## Alternatives considered

A general dead-store or loop optimization pass would need to recover alias and
control-flow relationships that already exist in the producer's input. Exposing
uninitialized arrays to source programs would change language semantics and is
unnecessary for eliminating stores proven unobservable.
