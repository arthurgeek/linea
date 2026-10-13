# 113. Structural derivation is library-defined source

Status: Accepted - 2026-09-05

Partially superseded by [0142](0142-construction-derives-expand-to-ordinary-source.md):
parameterized templates admit explicit construction with ordinary source cleanup.

Extends ADR 0035, ADR 0045, ADR 0049 and ADR 0093.

Extended by [0138](0138-hash-maps-preserve-entry-ownership.md) for hash-map key and ownership contracts.
Extended by [0145](0145-closed-attributes-attach-ordinary-derive-requests.md)
for derive requests attached to nominal type declarations.
Extended by [0209](0209-a-from-derive-converts-the-variant-the-source-names.md)
for a template that wraps a parameter in the enum variant its type names.

## Context

A derive mechanism has to generate behavior without creating a second trait
relation, a privileged ownership path, or compiler branches for each standard
trait. It must work across modules and generic heads, and it must state the
evidence that makes a structural implementation valid. Empty products,
uninhabited enums, enum payloads, newtypes, dependent trait families and
consuming release all have to use one mechanism.

Generated behavior also has to remain inspectable. If replacing a derive with
the generated text changes checking, ownership, emitted code or runtime output,
the generated implementation is not ordinary source in the meaningful sense.

## Decision

A trait's own module may declare one `template impl` for that trait. A template
is library source, not an implementation selected by dispatch. Each admitted
`derive` entry generates an ordinary implementation file in the target type's
module before type checking. The ordinary implementation relation, coherence,
type checking, ownership, instantiation, MIR lowering and verification then
treat that file exactly like handwritten source.

Structural reflection is template-only, observation-only and erased during
source generation. It exposes cases, declaration-ordered components, component
names and ordinals, case metadata, and forward or reversed component traversal.
It creates no runtime reflection value.

A template states component evidence explicitly with
`reflect.components: Trait`; a dependent structural trait states provenance
with `reflect.supertraits: derived`. Generic derives state their own bounds and
trailing predicates. The compiler infers none of these promises.

The initial standard-library applications are `Equatable`, `Equivalent`,
`Comparable`, `Ordered`, `Display`, `Debug` and `Release`. Their names are not
known to structural expansion. `Release` remains an optional operation invoked
by source; deriving it never schedules a call or follows from a type being
Linear.

The conformance suite materializes admitted primary-root derives from the same
immutable generated-source rows used by `dump-expanded`, removes the replaced
source requests, and recompiles the ordinary files. It compares acceptance,
ownership, normalized MLIR, exit status, stdout and stderr. Generated file order
is not semantic, so normalized MLIR compares complete function bodies while
ignoring function order and source provenance.

`Hash` remains a later library contract. A user-defined `Fingerprint` trait
with the same structural shape derives and executes without any compiler change
or compiler-known name.

## Consequences

Adding another structural trait is a library operation when its implementation
can be expressed by the erased reflection API and its evidence can be stated by
template requirements. Standard traits receive no expansion privilege.

Generated code is debuggable as source and testable independently of the
expander. A generated import uses the loader's canonical route and a fresh
alias, so target-module name collisions and qualified generic bounds retain
their ordinary meaning.

Declaration order is observable to structural algorithms. Equality and order
walk forward; release walks backward. Reordering a type's fields is therefore
not a semantics-preserving transformation for a program that derives and
observes such behavior.

The cost is a larger source pipeline: the resolver plans and renders immutable
files, reparses them, records typed origins and validates generated declarations
before later passes. Component and provenance tables are sized by their own
domains, and conformance sweeps hold their growth to those domains.

## Alternatives considered

**Hard-code each derivable standard trait in the compiler.** Rejected because
every new trait would add a compiler feature and a second implementation of its
library algorithm. The user-defined fingerprint proof contradicts the need.

**Attach behavior to type representation braces.** Rejected by ADR 0035:
representation and behavior are separate, and a derive is an implementation
request rather than a field of the type.

**Infer component bounds or release from structure and universe.** Rejected
because it hides generic requirements and turns optional policy into compiler
behavior. Linear requires consumption; it does not choose `Release` as the way.

**Keep generated implementations as privileged semantic rows.** Rejected
because they would bypass ordinary source checking and ownership, and could not
be validated by replacing derives with their files.

**Expose runtime or general compile-time reflection.** Rejected because the
required information is source-generation input. Erasing it keeps runtime
representation and optimization independent of derivation.
