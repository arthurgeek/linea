# Local array literals infer written lengths

Status: Accepted — 2026-09-21

Extends [0061](0061-an-array-is-a-value-of-a-fixed-size-type.md) and
[0083](0083-an-arrays-length-is-part-of-its-type-everywhere-it-is-written.md).

## Context

An array literal can infer its type without an annotation, but anonymous struct
elements and chosen numeric types need element context. Writing that context as
`[T; N]` also repeats the literal's count. Editing a table then requires two
changes even when the count states no independent requirement.

## Decision

An initialized local `let` or `var` may write `[T; _]` when its initializer is
an array literal, optionally grouped. The marker requests the literal's item
count. It does not introduce an unsized array, coercion, runtime length or
constant generic. Empty typed literals infer zero. The element annotation still
supplies context to every element.

Directly nested arrays may infer dimensions from the first literal row at each
level. Ordinary element checking then enforces the same concrete array type for
every row. Ragged rows fail. Empty outer literals cannot establish unknown inner
lengths; those inner lengths must be explicit. Signatures, fields, module
constants, nested generic arguments and nonliteral initializers cannot infer
lengths through this rule. Explicit counts and fixed call/return requirements
retain their exact-length checks.

The parser stores the marker as a token distinct from the explicit length
expression. Resolution never treats it as a variable. Local annotation checking
settles the count once before element checking and interns the same concrete
array type as an explicit count. All later passes retain their existing array
representation and ownership rules. Counting elements neither evaluates them
nor changes their evaluation order, moves, borrows or settlement obligations.

## Consequences

Literal tables can preserve element context without maintaining a repeated
count. Domain dimensions remain explicit. Formatting and editor grammars retain
`_`; checked types and hover expose the concrete count. Malformed input remains
recoverable, and unsupported inference is diagnosed at the marker.

The syntax adds one optional token field to written types. Shape inference reads
one literal per nested dimension, then reuses ordinary element checking. No
whole-program inference table or second runtime array representation is needed.
