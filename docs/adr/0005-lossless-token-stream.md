# 5. The token stream is lossless; the syntax tree is abstract

Status: Accepted — 2026-07-24

## Context

A formatter must preserve comments and reproduce source it does not change. A
language server needs to map any byte offset to syntax. Neither is possible if
the frontend discards information.

Semantic passes want the opposite. A type checker has no use for comments or
whitespace, and a tree that represents them makes every traversal step past
nodes it must ignore.

The two requirements apply to different layers, so they need not be resolved in
the same structure.

## Decision

Fidelity lives in the token stream. Abstraction lives in the tree.

- The lexer emits `.comment` tokens rather than discarding them.
- Whitespace is not tokenised. It is exactly the gap between
  `tokens[i].span.end` and `tokens[i+1].span.start`.
- The token array therefore reconstructs the file exactly: for each token, emit
  the gap preceding it, then its own text.
- The syntax tree stays abstract. It skips trivia, and every node records the
  token range it spans, so a consumer can ask which trivia falls inside or
  between nodes.
- A conformance property asserts byte-for-byte reconstruction across the whole
  test corpus.

The tree retains syntax the semantics do not need where a formatter requires
it. `grouped` is the Stage 1 instance: parentheses are redundant once
precedence is encoded in tree shape, but a formatter that drops them rewrites
the programmer's source.

Such nodes are syntactic, not semantic. `grouped` carries no meaning of its
own — it does not affect evaluation, typing or ownership, and every semantic
pass sees through it to its operand. It exists to record what the programmer
wrote, and a later HIR lowering is the correct place for it to disappear.

## Consequences

- Lossless reconstruction is guaranteed by a test rather than assumed.
- Whitespace costs no tokens and no nodes.
- Semantic passes never encounter trivia.
- Consumers that walk tokens directly must skip `.comment`. This is a helper on
  `TokenList`, not a decision at each call site.
- Trivia attachment — whether a comment belongs to the node before or after it
  — is deferred to the formatter, which is where the answer depends on
  intent rather than on structure.

## Alternatives considered

**A full concrete syntax tree**, as in rust-analyzer and Roslyn, where every
byte including whitespace is a node with a typed abstract layer above it. The
strongest foundation for tooling, and the natural fit for incremental
reparsing. Rejected: it roughly doubles node count, requires every semantic
pass to traverse through an abstraction layer, and buys fidelity that the token
stream already provides at a fraction of the cost.

**Discard comments and re-scan the source between token positions when the
formatter needs them**, as the Zig compiler does. Smallest token array, and
demonstrably workable. Rejected: comment recovery logic ends up duplicated in
every tool that wants trivia, and attachment is inferred from raw offsets
rather than read from a token stream.

**Tokenise whitespace as well as comments.** Makes reconstruction a plain
concatenation. Rejected: it inflates the token array substantially for
information already implied by adjacent spans, and every consumer then filters
two trivia kinds instead of one.
