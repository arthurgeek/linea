# 130. Explicit captures use inline environments

Status: Accepted — 2026-09-10. Read-only restriction superseded by
[0131](0131-closure-invocation-and-capture-ownership-are-independent.md).
Supersedes the capture exclusion in
[0105](0105-callable-values-have-static-call-targets.md); extends
[0123](0123-observations-carry-owner-dependencies-through-callable-contracts.md),
[0124](0124-copyability-and-settlement-are-independent-capabilities.md) and
[0129](0129-struct-destructuring-may-infer-its-type.md).

Extended by [0173](0173-a-capturing-closure-is-erased-into-allocator-owned-storage.md).

## Context

Configured callbacks need access to selected enclosing places without implicit
copying or allocation. A code pointer alone cannot store their owner
dependencies. An erased closure representation would discard the static call
target already established by callable typing and enlarge every stateless value.

## Decision

Capture declarations belong to a lambda's syntax. Resolution assigns each
capture alias its own binding and records its source expression and convention
in closure-indexed rows. Unlisted enclosing references remain errors.

Typing records an environment struct for each closure source identity. Each
specialized closure type retains the corresponding concrete environment TypeId,
interned with the closure's enclosing generic arguments. Its fields use the
existing semantic FieldList; no declaration or expression is synthesized in the
AST. The same struct identity supports whole-environment recovery and inferred
struct destructuring without requiring a source-visible type name.

Read captures store observations of their source places. Capture alias bindings
have their source types and read-only lending semantics in the body. Capability
and dependency preparation follows the environment's canonical owned parts;
borrowed referents contribute dependencies but no owned settlement obligations.

Ownership evaluates capture sources at construction and records their owners
through the existing dependency graph. MIR materializes the inline environment
and passes it to the statically selected body through an additional read
parameter. Explicit parameter order remains unchanged. Noncapturing values and
bodies retain their environment-free ABI, and structural function values remain
code pointers. Capturing closures cannot convert to structural function values.

The first implementation admits read captures and read invocation. Owned
captures, recovery, release and mutable/consuming invocation are decided here
but not implemented; syntax for modes
whose ownership rules are not implemented is diagnosed rather than accepted.

## Consequences

Read callbacks can retain configuration with no heap allocation or dynamic
call-target selection. Moving a callback preserves its observed owner
relationships. Generic instantiation specializes the environment alongside the
body. A concrete semantic struct can participate in inferred destructuring even
when no AST declaration names it.

## Alternatives considered

**Synthesize an AST struct and generated methods.** Rejected because capture
identity and field types are semantic facts already representable by resolution
and typing tables. Inventing source declarations would complicate tooling and
repeat the compiler's structural type machinery.

**Store a code pointer and erased environment pointer.** Rejected because it
adds allocation or lifetime machinery and discards static specialization.

**Introduce a closure-conversion pass.** Rejected because every capture fact
keys onto existing AST, binding, closure or type IDs, and MIR already constructs
reachable specialized bodies.
