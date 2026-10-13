# 37. Comments are placed by a token cursor, not an attachment pass

Status: Accepted — 2026-07-27

Builds on [0005](0005-lossless-token-stream.md), which made comments tokens and
whitespace the gap between spans, and on
[0006](0006-typed-per-category-ast.md), which gave every node a token range.

## Context

The syntax tree is abstract and holds no comments. The token stream holds them
all. A formatter walks the tree and must put them back.

The usual answer is an attachment pass: a walk over tokens and tree that
produces a side table saying which node each comment belongs to, and whether it
leads or trails. The printer then asks that table as it goes. It is what most
formatters do, and it is what a concrete syntax tree exists to avoid needing.

Attachment has a cost that is easy to underrate. "Which node does this comment
belong to" has no answer in the source — it is a judgement, and the pass has to
invent one. Then the property that actually matters, *no comment is lost*,
becomes a claim about that pass, which means a test has to go looking for
counterexamples rather than the design ruling them out.

There is a fact here that makes the question smaller than it looks. Comments are
already in token order, and every node already knows its token range. The
information an attachment pass would compute is a rearrangement of information
the token array already carries in the right order.

## Decision

**The printer holds a monotonic cursor into the token array.** Before emitting
any node it flushes every comment token preceding that node's first token, and
after emitting one it advances the cursor past that node's range so a comment on
the line just written can still be caught.

**Placement follows one positional rule.** A comment beginning on the same
source line as the token before it trails the current output line. Every other
comment takes its own line at the current indentation. The author's column is
discarded.

**Losslessness is structural.** The cursor only moves forward, so a comment is
emitted at most once, and the walk asserts at the end that no comment remains
past the cursor — so none can be skipped. Neither half is a test looking for
counterexamples; both are properties of how the walk moves.

There is no side table and no attachment pass.

## Consequences

The printer cannot reason about which node a comment "belongs to". It does not
need to: a comment separated from what follows by a blank line keeps that blank
line, which is the distinction attachment would have been reconstructing.

The cursor has to be advanced past what was written, not merely up to what comes
next. A printer that only ever flushed at node starts would have already ended
the line by the time a trailing comment was considered, and every trailing
comment in the corpus would move to a line of its own.

Emitting a trailing comment ends the line, because `//` runs to end of line. Any
code that ends a line afterwards has to notice it is already ended.

A comment in a position the walk does not visit — mid-expression, between an
operator and its operand — is emitted at the next boundary the walk reaches. It
is never lost, because the assertion would fire, but it may move. The corpus
sweep is what says whether that ever happens in practice.

Anything printer-adjacent built later — a documentation extractor, an LSP's
range formatter — inherits the same mechanism, because the mechanism is the
token order itself rather than something this printer owns.

## Alternatives considered

**An attachment pass with a side table.** The conventional design, and the shape
the compiler's own conventions would otherwise suggest — later passes annotate
through side tables keyed by a representation's ids. Rejected because the table
would hold no information the token order does not already give, in the order it
is already needed; it would be a representation that discards nothing, adds no
node, and simplifies no pass. It also converts "no comment is lost" from a fact
into a claim requiring its own tests.

**Comments as nodes in the syntax tree.** The printer would then simply walk
them. Rejected because it contradicts the tree being abstract, and it puts
trivia in front of every pass that walks the tree — the resolver, the type
checker and the lowering would all have to skip nodes that mean nothing to them.

**A concrete syntax tree beside the abstract one.** What rust-analyzer and
Roslyn do. Rejected on the same grounds a CST was rejected for the formatter
generally: the token stream is already lossless and already proves it, so a
second tree holding the same trivia would earn nothing.
