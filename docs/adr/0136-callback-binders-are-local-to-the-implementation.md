# 136. Callback binders are local to the implementation

Status: Accepted — 2026-09-17. Contract equality at contextual conversion superseded by
[0159](0159-a-converted-function-fits-its-carries-bound.md). Labels in callable type
identity, and the positional conversion that existed to bridge them, superseded by
[0177](0177-a-parameter-name-is-a-label-not-part-of-a-function-type.md).

Supersedes the contextual-conversion name-equality requirement in
[0105](0105-callable-values-have-static-call-targets.md). Refines
[0077](0077-arguments-match-by-name-and-evaluate-by-declaration.md).

## Context

A callback supplied to Option.map had to name its local parameter `value`,
while the same computation supplied to iterator map had to name it `item`.
Named functions could not be reused across these APIs when their parameter
labels differed. Those names control source-level calls, not runtime parameter
positions or the callback body's ownership obligations.

## Decision

An implementation supplied to a contextual callable requirement may choose its
own outer parameter names. Contextual conversion of an eligible named function
or noncapturing lambda compares its parameters by position. Generic callable
bound satisfaction uses the same positional rule while retaining concrete
callback identity and the existing invocation/effect compatibility rules.

All other signature requirements remain: conventions, types, defaults,
stable-address requirements, result and dependency contracts. Nested callable
types are exact. A labelled dependency path is normalized to parameter positions
before compatibility is checked, so renaming cannot erase an observation.

Labels remain part of structural callable type identity. An already-typed
structural value does not generally convert to another structural type. A direct
call uses the function or closure's declared labels; a call through a structural
value or callable bound uses that interface's labels. Typing records arguments
in parameter order once, preserving source evaluation semantics.

The shared semantic comparison distinguishes exact identity, contextual
conversion and callable demands. MIR function-address verification uses the
contextual conversion predicate to compare the pointer interface with the
concrete body. Lowering and ownership read normalized calls; neither matches
names again. Label-only adaptation emits no wrapper and changes no ABI.

## Consequences

One named function or lambda vocabulary can serve multiple callback APIs.
Structural callable signatures still describe named calls unambiguously, and
direct calls retain their original public parameter names. Comparison visits
the outer parameters and existing contract data once; it introduces no program
scan, runtime allocation or new representation.

## Alternatives considered

- Remove names from all callable identity. This would make differently labelled
  stored interfaces indistinguishable despite their different named calls.
- Generate wrappers to rename parameters. Labels have no runtime representation;
  a wrapper would add an unnecessary target and another contract to maintain.
- Permit renaming only for lambdas. Named functions and forwarded callback
  bounds encounter the same composition problem and use the same rule.
