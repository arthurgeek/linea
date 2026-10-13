# 127. Constants retain distinct values and infer their types

Status: Accepted — 2026-09-09; extended by [0140](0140-aggregate-constants-retain-checked-construction-plans.md)

Supersedes the numeric truth-value representation decision in
[0078](0078-a-truth-value-is-a-constant-expression.md). Extends the constant
expression domain of [0020](0020-a-constant-expression-is-defined.md) and the
shared-value table of [0059](0059-one-table-answers-both-questions-about-a-constant-expression.md).

## Context

Naming the decimal formatter's pair table exposed two restrictions: module
constants required type annotations even for an unambiguous initializer, and
string literals were excluded from constant expressions. A local named table
could infer Str, while the same declaration at module scope could do neither.

The compiler also stored checked constants and default arguments numerically.
That erased the distinction between a boolean value and an integer value after
the folder had established it. Adding text only to named constants would leave
ordinary defaults, callable type identity and omitted argument lowering with a
different definition of constant value.

## Decision

**Constant annotations are optional.** Module and implementation constants infer
their types from their initializers when no annotation is written, for every
visibility. Inference uses the ordinary literal defaults and never receives
context from later uses. Existing iterative dependency ordering settles forward
references; the shared cycle detector remains the authority for value cycles.

**Literal-backed text is a constant expression.** String literals without
interpolation, parentheses, and immutable aliases to those literals join the
syntactic domain. String API calls, equality, concatenation and interpolation do
not join it. Ordinary and callable defaults use the same domain; there is no
separate exemption for a parameter default.

**Checked values preserve their kind.** One domain distinguishes integers,
booleans and decoded string bytes. A boolean remains true or false in semantic
tables and default identity. Integer widths and nominal types remain in the
type tables, so the value tag does not duplicate the type system. Numeric counts
accept integers only. Lowering chooses a boolean's machine encoding.

**Default identity is value identity.** The same decoded text compares equal
whether written literally, through aliases or with equivalent escapes.
Different text and different value kinds remain distinct. Named constants,
ordinary defaults and callable defaults share value comparison, hashing and
materialization rules.

**Decode once through the shared decoder.** The folding memo interns decoded
text and transfers its ownership to the checked result. Alias chains propagate
the settled value. Later passes retain the checked value rather than replaying
an initializer, and MIR uses its byte pool and ordinary Str construction.
Runtime storage is static, with no new allocation or release operation.

## Consequences

A declaration such as `let decimal_pairs = "000102"` has type Str without an
annotation. `let count = 3` keeps its ordinary Int64 default regardless of how a
caller wants to use it. Explicit annotations and conversions remain available
where they select the intended numeric type.

Changing the value domain requires migrating every consumer: constant folding,
default tables, callable identity/coherence, symbols, dumps and argument
materialization. Equal bytes cannot be compared by pointer or source-expression
identity. Transferred compiler-owned text must remain live through reopening
and use of the checked type tables, including allocation-failure cleanup.

The change introduces no whole-program type inference, compile-time function
execution, implicit integer conversion or hidden resource cleanup. Constant
validity remains independent of optimization power.

## Alternatives considered

- **Keep explicit annotations only for public constants.** Visibility does not
  make initializer inference ambiguous; a visibility-dependent exception adds
  a rule without solving a type dependency problem.
- **Keep the table local.** This avoids the missing feature for one formatter
  but leaves module and implementation constants unable to express the same
  literal-backed value.
- **Admit strings only as named constants.** Defaults read the same domain;
  splitting them would recreate the duplicated semantic definition rejected
  by 0059.
- **Encode booleans as integers and recover meaning from the expected type.**
  This loses value distinctions unnecessarily and makes semantic identity rely
  on reconstructing a fact already known to the folder.
- **Compare text defaults by literal identity.** Aliases and different escape
  spellings can denote equal bytes. Literal identity is not value identity.
