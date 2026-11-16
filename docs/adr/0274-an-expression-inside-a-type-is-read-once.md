# 274. An expression inside a type is read once

Status: Accepted — 2026-11-16; extends
[0181](0181-a-call-may-name-its-type-arguments.md) and replaces its cost
consequence, which stated a bound the parser did not meet.

## Context

ADR 0181 has the parser read a bracket after a path, or before a call, twice:
as a list of types and as an index. A bracket nested inside another is read
again by each enclosing bracket's readings, and 0181 stated the cost as a
chain's contents times its nesting depth, `O(n·d)`.

That bound held for brackets holding only types and indexes. It did not hold
for an expression written inside a type: an array's length, `[UInt8; E]`, and
a callable type parameter's default, `fn(x: UInt8 = E) -> UInt8`. Both
readings of a bracket reach the type, the type holds `E`, and `E` may hold
further brackets, so each bracket around `E` doubled the number of times it
was read. Twenty brackets around a length read it about a million times.

A length was already kept once read and taken by later readings, but only
where its token count plus the depth stayed under the nesting limit of 1000.
The token count stood in for how deep a second reading could go, so a length
longer than about a thousand tokens was never kept, and deep nesting around
one was read exponentially often: about 29 seconds at depth 14 on a 1.4 KB
file. A callable default was never kept at all, and forty brackets around one
did not finish.

## Decision

**An expression written inside a type is read once wherever the same tokens
are reached under the same parser context, and every later reading takes that
expression as it is.** Array lengths and callable type parameter defaults both
go through `parseTypeExpression`. A reading is kept with its reach: how many
levels below where it began any nesting check was asked about, counted through
attempts that were undone. A later reading at another depth takes it where its
depth plus the reach stays inside the limit, because every check the expression
asks then answers as it did. The token count no longer decides anything.

The resolver resolves such an expression once, and replays what it reported to
the second reading that reaches it, as it already did for lengths, so a binding
or closure declared inside one is declared once.

**The parser's cost for brackets is `O(n·d)`**, `n` the tokens and `d` the
depth of nested brackets that may hold types: a bracket's contents are read by
its own two readings and by the type reading of each bracket around it, and an
expression inside a type is read once however many readings reach it. The
depth is at most the nesting limit of 1000.

## Consequences

- A length of any length, or a callable default, inside nested brackets is
  parsed in time linear in the tokens around it. The cases
  `tests/parser/a_long_length_inside_nested_brackets_is_read_once.lin` and
  `tests/parser/a_callable_default_inside_nested_brackets_is_read_once.lin`
  hold it, and the sweep measures both forms by nesting depth.
- Every nesting check records the level it asks about: `atNestingLimit` for a
  frame about to open, and `Measure.wrap` for a level a loop stacks. A check
  written another way would leave a reach short and let a reading be taken at
  a depth where it would read differently.
- A reading that reached a nesting check it failed is never kept: its reach
  puts it past the limit at the depth it was read at.

## Alternatives considered

**Keying a reading by its depth as well as its first token.** A bracket's two
readings reach what is inside it at different depths, so a reading would be
kept per depth reached. The depths along a chain of `d` brackets are `O(d)`,
so the cost would have been `O(n·d)` for the expression alone, and the reach
answers the same question exactly.

**Keeping the token count and raising the limit.** Any limit on the tokens is
one a longer expression passes, and the cost past it is exponential again.
