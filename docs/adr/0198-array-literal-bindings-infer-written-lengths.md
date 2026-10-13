# Array literal bindings infer written lengths

Status: Accepted — 2026-09-21

Extends [0061](0061-an-array-is-a-value-of-a-fixed-size-type.md),
[0083](0083-an-arrays-length-is-part-of-its-type-everywhere-it-is-written.md)
and [0149](0149-local-array-literals-infer-written-lengths.md).

## Context

An array literal can infer its type without an annotation, but anonymous struct
elements and chosen numeric types need element context. Writing that context as
`[T; N]` also repeats the literal's count. Editing a table then requires two
changes even when the count states no independent requirement.

Lookup tables are most often module constants, such as
`let weekday_names: [Str; _] = ["Sunday", …]`. A table that is legal inside a
function and refused one indentation level out is a rule about where the table
sits, not about what it says.

## Decision

A binding initialized with an array literal, optionally grouped, may write
`[T; _]` in its annotation: a local `let` or `var`, a module constant or an
`impl` constant. The marker requests the literal's item count. It does not
introduce an unsized array, coercion, runtime length or constant generic. Empty
typed literals infer zero. The element annotation still supplies context to
every element.

Directly nested arrays may infer dimensions from the first literal row at each
level. Ordinary element checking then enforces the same concrete array type for
every row. Ragged rows fail. Empty outer literals cannot establish unknown inner
lengths; those inner lengths must be explicit. Signatures, fields, parameter
defaults, nested generic arguments and nonliteral initializers cannot infer
lengths through this rule. Explicit counts and fixed call/return requirements
retain their exact-length checks.

A module or `impl` constant may also omit its annotation entirely, as any
constant may ([T-Const]); `let seasons = ["spring", "summer"]` has type
`[Str; 2]`. The annotation is needed only where the elements need context.

A parameter default does not count its literal. The parameter's type is what
every caller supplies; the default is one value of that type, and letting it
decide the type would make deleting the default change the signature.

The parser stores the marker as a token distinct from the explicit length
expression. Resolution never treats it as a variable. The checker settles a
binding's written type by one routine, which counts the literal before element
checking and interns the same concrete array type as an explicit count. Local
bindings call it when they are checked; constants call it when their written
types are installed, before any default or initializer reads them. All later
passes retain their existing array representation and ownership rules. Counting
elements neither evaluates them nor changes their evaluation order, moves,
borrows or settlement obligations.

## Consequences

Literal tables can preserve element context without maintaining a repeated
count, wherever the table is declared. Domain dimensions remain explicit.
Formatting and editor grammars retain `_`; checked types, the inferred dump and
hover expose the concrete count. Malformed input remains recoverable, and
unsupported inference is diagnosed at the marker.

A constant whose written type fails to resolve is reported once, at the type;
its initializer is still checked but is not also reported as a non-constant.

The syntax adds one optional token field to written types. Shape inference reads
one literal per nested dimension, then reuses ordinary element checking. No
whole-program inference table or second runtime array representation is needed.

## Alternatives considered

**Keep inference local.** Refusing module constants kept constant types
independent of their initializers, but a constant without an annotation already
takes its whole type from its initializer, so an annotation that takes only the
count from it adds no new dependency.

**Let a parameter default supply the count.** Rejected above: a signature would
depend on an optional value, and callers would have to read the default to know
what to pass.
