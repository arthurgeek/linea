# 117. Local callable selections preserve their targets

Status: Accepted — 2026-09-08. Extends
[0105](0105-callable-values-have-static-call-targets.md).

## Context

A structural callable can select one of two known function values and then be
called through an immutable local. Its one-pointer representation preserves the
language value, but exposing only an indirect call can prevent LLVM from
inlining either body and scalarizing an aggregate result. A measured two-target
source control demonstrates material runtime headroom for this shape.

The checker already records each contextual function value's target, exact
signature, and generic arguments. Selecting those functions again by source name
would duplicate semantic responsibility. Re-evaluating the conditional at the
call would change behavior if its inputs or effects had changed in between.

## Decision

Existing lowering may specialize a call through an immutable local initialized
by a conditional whose two effect-free leaves are checked declared function
values with the same exact structural signature and existing concrete bodies.
It reads the checker-owned FunctionValue records and uses the same monomorphic
target lookup as function-address emission. It does not resolve names or traits,
change the normalized call signature, or discover additional instances.

Lowering retains the condition value evaluated at initialization and the two
FunctionIds in sparse, per-function local provenance. The structural value still
has one code pointer and remains available to other consumers. At a proven call,
the already-normalized arguments and defaults are evaluated once in their usual
order before an ordinary MIR branch dispatches to either direct call. The usual
result and Never conventions apply. At most two call instructions replace one.

The transformation adds no pass or callable ABI. Mutable values, unknown targets,
branch bodies with effects, and callable forms outside this proof continue to
use the ordinary structural-call representation. Capturing closures remain
outside callable core as decided by 0105. MIR verification still checks target
signatures and representation; the backend receives no new semantic decision.

## Consequences

Known alternatives become visible to ordinary LLVM inlining and scalarization
without alias premises, unchecked operations, or changed evaluation effects.
Compiler storage follows eligible locals, and code expansion is bounded by two
targets per selected call. Shared target lookup may repeat small interning-key
preparation while emitting the still-observable pointer value. Runtime, compiler
allocation, and object size must be assessed together; the source control alone
is not evidence that the production transformation improves every workload.
