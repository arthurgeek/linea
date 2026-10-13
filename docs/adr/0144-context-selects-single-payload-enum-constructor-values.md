# 144. Context selects single-payload enum constructor values

Status: Accepted — 2026-09-21. Extends
[0128](0128-qualified-enum-constructors-are-contextual-callables.md) and
[0132](0132-callable-results-separate-types-from-dependencies.md).

## Context

An enum constructor already forms a structural callable value when its enum is
qualified. Higher-order operations therefore repeated an enum name even when
their callable result fixed that enum exactly. Error mapping made the cost
especially visible: propagation could determine the enclosing `Result` error,
yet `map_err` still required `Failure.Allocation` instead of `.Allocation`.

Selecting a variant by searching every enum that declares the same spelling
would make inference depend on unrelated declarations. Treating propagation as
a special `Result.map_err` rule would put library identity into the compiler and
leave other higher-order functions with different inference behaviour.

## Decision

**A leading-dot, single-payload enum variant is a constructor value when an
exact structural callable context supplies its result enum.** Selection uses
that result's nominal enum identity and declaration-order variant ordinal. It
does not search declarations by name. The qualified and contextual spellings
share one validator for payload count, consuming parameter convention,
defaults, stable-address requirements, generic arguments and bounds, dependency
contracts, and opaque construction.

Ordinary call inference may constrain an open callback result from the
enclosing expression. In a `Result`-returning function, propagation supplies
its error type at the corresponding nested carrier depth. A callback worklist
uses known payloads and sibling callback signatures in either argument order;
each callback is checked once. These constraints settle only open parameters.
They do not convert known mismatches, cross another carrier kind, or enter a
lambda with its own return context.

Typing records the selected signature and ordinal as the constructor function
value. It also records enum identities and ordinals for written dependency
contract targets, so editor consumers never repeat semantic name selection.

## Consequences

`result.map_err(.Allocation)` uses the same callable conversion and ownership
rules as `result.map_err(RenderError.Allocation)`. Generic enum arguments may
come from the payload, contextual result, sibling callbacks, or propagation,
while declaration bounds remain checked at every accepted conversion.

Nullary and multi-payload variants remain direct constructors rather than
callable values. A leading-dot constructor without a known result enum remains
uninferable, and a known enum missing that variant receives the ordinary
variant diagnostic.

Failure-context traversal is linear in carrier depth. Callback dependency
collection visits each relevant callable parameter and result type once per
argument. Selecting a contextual variant reuses the existing lookup, which is
linear in the selected enum's variant count. Constructor and contract identities
occupy sparse tables proportional to accepted written uses.

## Alternatives considered

**Search visible enums by variant spelling.** Rejected because unrelated imports
would change inference and same-named variants would become ambiguous without
an expression that names either enum.

**Teach the compiler about `Result.map_err`.** Rejected because the behaviour is
ordinary callback inference and must work for user-defined higher-order
functions.

**Infer only from the constructor payload.** Rejected because enum parameters
that occur only in the result still need ordinary contextual or sibling
evidence, while associated payload projections cannot reliably recover their
owner from a concrete payload alone.

**Treat a known concrete result as proof that its generic bounds were checked.**
Rejected because inferred instances do not carry that certificate. Constructor
conversion validates declaration bounds even when another contextual check may
report the same violated bound.
