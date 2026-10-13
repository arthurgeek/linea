# 105. Callable values have static call targets

Status: Accepted - 2026-08-26. Contextual-conversion name equality superseded by
[0136](0136-callback-binders-are-local-to-the-implementation.md). Capture exclusion superseded by
[0130](0130-explicit-captures-use-inline-environments.md). Extended by
[0117](0117-local-callable-selections-preserve-their-targets.md),
[0128](0128-qualified-enum-constructors-are-contextual-callables.md) and
[0153](0153-an-inherent-impl-function-is-a-function-value.md).

Extended by [0173](0173-a-capturing-closure-is-erased-into-allocator-owned-storage.md).
Extended by [0176](0176-a-function-name-is-a-value-its-uses-instantiate.md).

## Context

A stored callback needs one concrete runtime representation, while a generic
higher-order function needs a lambda's identity to survive until
monomorphisation so its body can be specialised and called directly. Erasing
both to one dynamic closure pair would make every stateless callback larger and
every generic lambda call indirect. Treating every lambda as a code pointer
would leave nowhere for capture to live and would discard source identity before
specialisation.

Calls also carry semantic facts beyond the callee spelling: named arguments,
defaults, conventions, selected generic arguments, and the implementation or
generated body that answers. Reconstructing those independently in ownership,
lowering, and tooling would give one call several answers.

Callable core admits non-capturing lambdas and structural function values. It
must establish their boundary without installing an environment ABI that only a
later capture design can justify.

## Decision

Every accepted callable-core lambda expression has one resolver-owned
`ClosureId`. Its zero-capture static closure type is that source identity applied
to the enclosing declaration's type arguments. A value of such a type selects
its generated body statically; after monomorphisation a call is an ordinary
direct call to the concrete closure body.

A structural `fn(parameters) -> Result` value is a distinct type whose complete
signature is exact. Its runtime representation is one code pointer and its call
is indirect. An eligible non-capturing lambda or selected top-level function
becomes that representation only where an exact structural type flows inward.
The conversion does not replace the lambda's unique type in generic callable
inference.

The type checker owns call normalisation. It records the target, exact
signature, selected arguments, and argument expressions in parameter declaration
order, including omitted defaults. Ownership and lowering consume that record;
they do not match names, select a body, or classify the call again.

There is no closure-conversion pass. Lowering already turns generic source into
reachable concrete MIR functions, so it emits each reachable closure body there
and records `Origin.closure` from the resolver's source identity. It emits
`function_addr` for contextual pointer conversion and `call_indirect` for a
structural value call.

An accepted callable-core closure is non-capturing. Its generated body receives
only the user-written parameters and has no runtime environment parameter or
value. How a capturing lambda is represented, owned, and called remains
undecided and requires a separate implemented decision.

## Consequences

Generic higher-order calls over lambdas remain direct and specialise per
enclosing instantiation. Stored callbacks have one pointer of representation and
retain named/defaulted call semantics through their exact structural signature.

MIR carries two explicit operations in addition to direct `call`, and the
verifier checks function targets, exact signatures, code-pointer provenance,
argument extents, and argument/result representations before the backend emits
them. The backend renders those recorded facts and owns no callable decision.

Unique closure identity and structural callable identity remain distinct even
when their signatures match. Callable values have no equality, no hidden
adapter between signatures, no foreign ABI, and no dynamic dispatch.

Capture cannot be added by appending a hidden argument to existing generated
bodies. The representation and ownership of capturing values, and the calling
convention for their bodies, remain undecided and require a separate accepted,
implemented decision. Non-capturing bodies retain the no-environment ABI fixed
here.

## Alternatives considered

**Represent every callable as `{ code, environment }`.** Rejected because it
makes stateless values twice as large, makes specialised lambda calls indirect,
and requires a lifetime or allocation answer callable core does not need.

**Represent every lambda as a code pointer.** Rejected because source identity
would be erased before monomorphisation and a capturing value would have nowhere
to store its state.

**Add a closure-conversion pass before MIR.** Rejected because all callable facts
key onto AST and typing IDs until the same lowering boundary that already adds
concrete generic bodies. A new representation would duplicate that boundary
without discarding or simplifying anything.

**Let each consumer interpret call syntax.** Rejected because named arguments,
defaults, generic selection, and direct-versus-indirect classification would be
implemented independently in every downstream pass. Checker-owned normalisation
records one answer instead.

**Give non-capturing bodies an empty environment parameter.** Rejected because
it would make their generated signature differ from the structural signature,
requiring a shim for pointer conversion and establishing an ABI for state that
does not exist.
