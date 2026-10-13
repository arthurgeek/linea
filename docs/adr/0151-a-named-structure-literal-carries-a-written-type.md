# 143. A named structure literal carries a written type

Status: Accepted — 2026-09-21. Refines [0041](0041-a-newline-ends-a-statement.md).

Builds on [0054](0054-the-bound-is-on-height-and-covers-written-types.md),
which gives written types one grammar and one nesting bound.

## Context

Contextual structure literals made the surrounding expression state their
type, but application code often had to add an annotation only to construct a
nominal value. Dots before every field also made construction unlike named
arguments and unlike structure patterns.

Allowing `Type { ... }` introduces one syntactic ambiguity: the brace after an
outer control header already opens that control's body. Reinterpreting an
ordinary expression after type checking would make parsing depend on names and
would duplicate the written-type grammar for generic, array, borrow, callable,
grouped, and projected types.

## Decision

**A structure literal is written `Type { field = value, shorthand }`, or
contextually as `.{ field = value, shorthand }`.** Its field labels have no
leading dots. A named literal constructs exactly its written nominal type; a
contextual literal receives its type from its expression context.

The named head starts with a nominal path and optional type arguments, parsed
through the ordinary written-type grammar. The AST stores a `TypeRefId` for a
named literal and `.none` for every other expression. Resolution and type
checking therefore use the existing written-type paths, including generic
arity, bounds, module qualification, `Self`, and nested type forms.

The parser decides the brace syntactically. An unparenthesized named literal is
disabled only in the outer expression of an `if`, `while`, `for`, or `match`
header. Parentheses, call arguments, indexes, arrays, lambdas, and nested block
expressions reset that restriction. The opening brace stays on the same line
as the type head; otherwise ADR 0041 ends the expression and the brace opens a
block.

Field initializers evaluate once in written order. Every field is supplied
exactly once, and ownership follows the consuming position of its initializer.
Structure patterns keep their colon-based binder syntax.

## Consequences

There is one field-checking and construction path for named and contextual
literals. Named literals determine their own type during generic argument
inference; contextual literals still wait for a type to flow inward.

The old dotted field-label spelling is removed rather than retained as a
compatibility form. Field access and enum variant syntax are unchanged.

Editor grammars, formatting, navigation, rename, syntax dumps, cached AST
relocation, and source generators must visit the written head as type syntax.
The dense head table costs four bytes per expression. Syntactic lookahead uses
a delimiter-end table scoped to the current file, costing four bytes per token;
it avoids rescanning nested type arguments at each possible head.

## Alternatives considered

**Require an annotation and keep construction contextual.** This preserves one
literal form, but makes a local repeat its type solely to construct it and does
not help an argument or branch that has no annotation site. Rejected because
the nominal type is useful information at the expression itself.

**Parse the head as an expression and reconstruct a type later.** This reuses
the old path and index nodes, but creates a second grammar that must reinterpret
arrays, borrows, callable types, grouping, projections, `Self`, and every future
type form. It also risks accepting value syntax such as a multi-index operation
while trying to represent multiple type arguments. Rejected in favour of one
canonical `TypeRef` producer.

**Resolve the brace after name lookup.** This would allow the parser to treat
every head as a value expression until semantic analysis identifies a type.
Rejected because tree shape and control-body boundaries must be recoverable
before resolution, including in incomplete editor input.

**Keep dotted field labels as a compatibility spelling.** Supporting both
spellings would preserve duplicate parser and formatter paths in an unreleased
language and leave shorthand unlike named arguments. Rejected; callers migrate
atomically and the old spelling remains only in a deliberate rejection case.
