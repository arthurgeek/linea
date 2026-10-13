# 142. Construction derives expand to ordinary source

Status: Accepted — 2026-09-21

Partially superseded by [0165](0165-an-attached-derive-requires-each-field-type.md):
expansion of an attached request adds one predicate per field type naming a
parameter.

Partially supersedes [0081](0081-an-implementation-is-generic-over-its-head.md):
trait implementation binders may be determined by the complete coherence key,
not only the receiver. Partially supersedes
[0113](0113-structural-derivation-is-library-defined-source.md): erased structural
reflection admits explicit construction as well as observation. Its ordinary
source, ownership and coherence guarantees remain in force.

Extends [0087](0087-an-associated-type-is-a-function-of-the-coherence-key.md)
with selection from recursively written type bases. Extends
[0047](0047-instantiation-is-a-backend-concern.md) with a finite-height proof for
generic call cycles; instantiation remains a backend responsibility. Preserves
[0079](0079-a-projection-is-one-structural-step.md)'s opaque projection measure
and [0093](0093-two-implementations-that-could-answer-once-are-refused.md)'s
complete-key coherence rule.

## Context

A library that loads fields into an owned record needs to construct fields in
declaration order, retain completed owners while later work can fail, and
release those owners on failure. A library template must express that work
without an implicit destructor or compiler knowledge of the library's trait.
The same requirement occurs in configuration loading and typed JSON decoding.

Allocator-parameterized operations also need implementations such as
`impl[A: Allocator] Build[A] for Bool`. The trait argument determines A even
though Bool has no type parameters. Derivation cannot grant generated source
a relationship that handwritten implementations cannot express.

Substitution must remain closed over ordinary written types. Replacing A in
`A.Item` by `Wrapper[T]` requires the ordinary type `Wrapper[T].Item`.
Template-only projection evidence would break source materialization.

## Decision

### Implementations use complete keys

Every ordinary trait implementation binder must be recoverable from the
receiver and requested trait arguments together. Injective structure can
supply a binder; associated-type projections and bounds cannot be inverted to
supply one. Constructor-uniform nominal heads still use bare distinct binders
in relative declaration order and fill the target arity. Their arguments may
be an ordered subset of the implementation binders. Partial concrete,
repeated and reordered receiver patterns remain refused.

The complete key and written predicates use the existing canonical selection
relation. Constraints decide applicability without ranking ordinary candidates.
Overlap compares receiver and trait arguments together. Receiver-only discovery
must decline when trait-only arguments remain undetermined. `Self` denotes the
checked receiver, and selected implementation arguments remain in binder order.

### Templates have explicit parameter mappings

A trait's module declares at most one template for that trait. A template binds
one parameter per trait parameter and applies them once in order. Their bounds
match the trait's bounds under positional substitution. Specialized templates
and general trailing template predicates are not admitted.

Each derive entry independently supplies ordinary trait arguments and must
determine all its implementation binders. A target application and a trait
application have separate mappings: target parameters select the derive
binders written in the target positions, while template parameters select the
entry's trait arguments. An invalid grouped entry does not invalidate a valid
sibling or silently discard its own unused binders.

Component requirements may mention template parameters. They are checked in
that symbolic scope, substituted per derive and discharged through ordinary
implementation evidence. Expansion infers no bounds or generated predicates.
`reflect.target: struct`, `enum` or `type` restricts the target declaration
kind; it grants no extra operation on that representation.

### Construction is a flat ordinary block

A template function may use
`reflect.construct(selector, |component| { ...; local }, { ... })`.
The selector is a struct's `reflect.product` or an active `reflect.case` for a
struct or enum variant. Newtype construction is excluded: an ordinary checked
constructor owns its refinement and failure policy.

The recipe has one descriptor and no explicit captures, callable convention,
return annotation or contracts. Its metadata is `name`, `ordinal` and written
`Type`. Its final expression names a binding declared directly in that recipe.
The finalization argument is an ordinary block that falls through with unit.
It runs after every component succeeds and before assembling the result.

Expansion copies each component recipe's top-level statements into one block,
in declaration order. It renames locals and references by resolved binding
identity, including shadows and shorthand fields. Nested lambda parameter labels
and capture aliases keep their source spelling; shorthand captures name their
renamed source explicitly. Finalization cannot access those recipe locals through their original names. One ordinary
contextual struct literal or selected enum constructor consumes the yielded
bindings exactly once. An empty product runs finalization without a recipe.

Only source-written defers schedule cleanup. Those defers remain active across
later recipes and finalization; successful construction moves their owners,
while failure follows ordinary reverse-order cleanup. The renderer inserts no
release, rollback, default or initialization state. Missing cleanup and dead
defers are ordinary ownership errors. Recipe early exits leave the enclosing
function; the recipe is not a runtime closure. Nested reflected construction
and component recipes are excluded.

### Written selections have recursive bases

A member selection follows a complete written type base, including an applied,
grouped, array or callable type. Module qualification still names declarations.
Type selection uses one associated declaration and complete trait key. Existing
scoped bounds take precedence; bare open parameters require them and remain
opaque. A known structural base may use ordinary visible trait implementations
under its checked constraints. Ambiguity, unavailable evidence and undetermined
trait-only arguments are refused; a desired result type does not supply a key.
Associated types take no arguments.

One flat syntax node holds a typed base ID, dot token, selected member and
ordinary type-argument children. It replaces path-only written projections.
Trait-name namespace paths retain their separate role. The dot token preserves
incomplete source for recovery and completion. Parameter substitution inserts
ordinary grouping where necessary, so `(borrow T).Item` cannot become
`borrow T.Item`.

Open selected keys retain the existing canonical projection identity. Closed
keys may settle through ordinary typing. Generic growth analysis retains the
opaque projection step; knowing a particular settlement does not justify
unbounded instantiation. Visibility and opaque representations are unchanged.

### Generic call cycles have bounded type height

The checker proves that a cycle's complete function and implementation argument
vectors remain bounded by `max(H, C)`, where H is the entering type height and C
is a finite height supplied by closed types in the checked source. A growing
intermediate call is permitted when subsequent calls establish that bound.
Receiver-only and trait-only implementation parameters participate equally;
when an abstract call has no complete implementation bindings, its receiver and
trait arguments remain part of the growth question.

The proof consumes normalized calls. Exact dispatch uses the canonical
implementation selector; an unresolved trait call conservatively admits its
ordinary suppliers. A declaration's exact arguments widen to unknown when
incoming paths disagree. Type transfers contribute weighted edges between
parameter slots, using the same injective origins that establish implementation
binder admission. Selecting a visible child precedes subtracting a remaining
constructor path. An opaque projection supplies no finite result-height bound.

Sparse slot alternatives retain their known outer type heads. Constructor
formation contributes only its own head; parameter transfer preserves a head;
supplier descent admits its matching head and genuinely unknown inputs. A
known-headed contribution never becomes an unknown-headed contribution merely
because another path disagrees. This preserves the correlation required by
recursive containers without enumerating concrete instantiations.

Separate sources represent entering height, closed constants and unbounded
values. A positive-weight cycle reaching reentry, or an unbounded contribution,
refuses the cycle. Finite maximum paths establish the bound. The graph and its
memoized traversals are local to the reached declarations and sparse head
alternatives; checked arithmetic rejects representation overflow. This is a
conservative source rule: discarded deeper correlations may cause refusal,
but they cannot justify an unbounded instance queue.

## Responsibility and consequences

The resolver validates reflection syntax, records binding identities and renders
ordinary generated files with typed origins. Component type text uses resolved
target identities and canonical import planning. The checker owns signatures,
complete-key admission and evidence, component requirement discharge and
associated settlement. Ownership consumes the generated ordinary body. There
is no construction operation in MIR and no trait-specific backend path.

`ImplementationParameters.init` supplies the shared binder-origin answer.
Associated selection uses `Reach.associated` and canonical implementation keys.
The sparse `Typing.type_selections` table records the checked base, member and
associated declaration at each dot; retained and editor consumers read that
answer rather than implementing another selection relation.

Wide products add a flat statement sequence instead of one nested scope per
field. Expansion work follows copied source and emitted components; it does not
walk all program declarations for every field. Existing source-size and syntax
height bounds apply. Fresh names reserve template, target and derive identifiers.

Generated and materialized source must agree in checking, ownership and runtime
behavior. Required witnesses include a non-JSON three-field loader with two
owners and failure at later construction/finalization; an active enum case;
empty products; hygienic shadows and captures; retained-library reuse; and
ordinary/materialized applied projections with visibility, ambiguity and
undetermined-key refusals.
