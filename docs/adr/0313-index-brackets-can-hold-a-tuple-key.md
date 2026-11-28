# 313. Index brackets can hold a tuple key

Status: Accepted — 2026-11-27. Extends
[0199](0199-tuple-syntax-denotes-a-positional-aggregate-with-a-prelude-identity.md)
and [0200](0200-a-tuples-arity-is-a-readability-policy-the-parser-enforces.md).

## Context

A matrix element has a row and column. The existing Index protocol already
accepts a tuple key; requiring a second pair of parentheses for every element
adds no distinction in meaning. Brackets also carry a generic function's type
and length arguments, so the parser cannot decide every bracket's purpose.

## Decision

`value[row, column]` indexes with the tuple `(row, column)`. It uses the existing
tuple literal identity and Index lookup. Explicit tuple parentheses remain
valid and are preserved. Nested arrays retain integer indexing and their
existing contiguous inner-array representation.

Record the bracket delimiter on the tuple's syntax node; formatting retains
comments and trailing-comma layout. Tuple keys have the same two-through-eight
arity policy as parenthesized tuples. Check their arity only when the bracket
has been selected as an index, so a function's one or nine type arguments do
not become tuple syntax errors. Parenthesized tuple arity remains a parser
check. Both checks use the shared syntax arity bound.

Keep the index and type-argument readings separate. Several tuple-key
components cannot share one length-argument expression: `make[2, 3]()` still
supplies two arguments. Read and check tuple components under ordinary tuple
rules, in their written order. The projection determines the selected place.

## Consequences

Matrix indexing uses the ordinary library protocol without a new indexing
backend or a matrix-specific syntax node. A tuple key adds one level to syntax
height, and parser recovery remains bounded by the existing nesting limit.
The editor grammar retains syntactically ambiguous type-argument readings and
accepts unambiguous tuple keys without requiring semantic resolution.

## Alternatives considered

**Keep mandatory inner parentheses.** It expresses the same tuple twice through
delimiters and makes matrix element access needlessly cumbersome.

**Give matrices a separate indexing primitive.** The existing Index protocol
already defines the checked element place and its borrow contract.

**Treat every comma in a bracket as a tuple immediately.** Generic functions
also use commas between independent type and length arguments. Choosing that
meaning before resolving the head breaks those calls.
