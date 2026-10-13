# 41. A newline ends a statement, decided by the token before it

Status: Superseded by [0196](0196-a-selection-line-continues-the-line-above.md)
— 2026-09-28. Accepted 2026-07-28. Refined by
[0043](0043-a-separator-that-answers-a-note-is-kept.md),
[0151](0151-a-named-structure-literal-carries-a-written-type.md),
[0167](0167-a-binding-handles-its-failure-with-else.md) and
[0190](0190-a-variant-line-is-not-a-continuation.md).

Builds on [0005](0005-lossless-token-stream.md), which makes whitespace the gap
between adjacent spans and so lets the parser see a line break without one
becoming a token, and on [0036](0036-formatting-is-comma-driven.md), which
already decides layout from what the author wrote rather than from a width.

## Context

Statement termination had three rules and a reader had to know all three. A
binding was terminated by `;`. A construct ending in a brace took no separator,
and one written anyway was accepted and discarded. The last expression of a
block took none either, and a `;` written before the closing brace was eaten
without being recorded — so `{ e; }` and `{ e }` were one tree and one program.

That last one is the evidence the semicolon was not carrying meaning: two
spellings, no way to tell them apart afterwards, and a formatter that had to be
told to drop one because there was nothing to write back.

## Decision

**A newline ends a statement, unless the token before it cannot end one —
except the last expression of a block, which is that block's value.**

The exception is a language rule and not a parser detail: a block's value is
its final expression, decided by position rather than by what separates it from
the brace.

Which tokens can end a statement is a closed set — a name, a literal, `true`,
`false`, `)`, `}`, and a bare `break`, `continue` or `return`. It is stated as
what *can* end rather than what cannot, which keeps the list short and makes a
token added later default to continuing the line. That is the safe direction: a
wrapped expression keeps working, and the mistake is a parse error rather than
a silent second statement.

**The rule looks only backwards.** It reads the token before the break and
never the one after. An expression written across lines therefore ends each
line with the operator that carries it on.

`;` stays in the language, separating two statements that share a line.

### The hazard, and what is done about it

Three tokens begin a statement and also continue an expression: `-`, `(` and
`.`. A newline before one decides between two readings that are both programs.
Where that happens the parser emits `[S-Continuation]`, a note naming the token
and saying to end the previous line with it if that was meant.

A note rather than an error, because only the author knows which was intended.
It fires on the shape of the tokens rather than on the type of what they
produce. Relying on a discarded value being reported would hold only until an
expression whose value is nothing can stand alone as a statement, at which
point both halves of a misread newline become legal and the mistake compiles.

A brace is not among the three. A struct literal is always written `.{ ... }`,
so no completed expression takes a `{` as a continuation and a brace on the
next line can only open a block. Noting it would fire on every ordinary one,
and a note that is usually wrong is one nobody reads.

## Consequences

**No lexer change, and no new token.** The cursor already holds the spans and
the source, so a line break is a scan of the gap between two spans. Whitespace
remains the gap between adjacent spans and [0005](0005-lossless-token-stream.md)
is untouched.

**The formatter drops every semicolon that ends a line**, which subsumes the
special case it carried for one before a closing brace. The token-preservation
property stays one-directional: a deletion is allowed, an insertion is not.

**A body is one statement per line, so formatted code has no semicolons at
all** — two that shared a line are given a line each, and the separator that
remains is the break. `;` survives in the language for what someone types, not
for what the formatter writes.

**The formatter and the note are complements.** `fmt` never produces a file
that triggers `[S-Continuation]`, because the layout it writes puts nothing
after a line break that could have continued the line. Neither rule was derived
from the other; both come from the same three tokens.

**The tree-sitter grammar makes the separator optional and lets the block tail
be an ordinary statement.** It highlights rather than parses and has no line
break to see between tokens, so it accepts more than the language does — the
direction a highlighter is allowed to err.

## Alternatives considered

**Continuation by looking forward** — treating a newline as a continuation when
the *next* line begins with a token that cannot start a statement, so a leading
`+` carries the line. This is what Swift and Kotlin do, and it is what the
parser did by accident before this record: the expression loop simply ran on
whenever the next token could continue it. It makes more programs parse and it
removes the hazard above entirely, since the ambiguous cases resolve towards
continuation.

Rejected because the rule then has two halves that cannot be stated alone, and
because the one-sided rule already answers the program it would rescue: end the
line with the operator. The accidental version also had a cost that was not
theoretical — a struct literal followed by a line opening `(` became a call on
that literal, and the corpus case that recorded an exit status is what said so.

**Keeping a semicolon ahead of `-`, `(` and `.`.** The formatter did this while
the parser was still greedy, because the separator was load-bearing there.
Rejected once the parser stopped at the break: the semicolon then says what the
line break already says, and preserving it would have made the formatter insert
a token in one direction and delete it in the other.

**Removing `;` from the language.** Rejected because two statements on one line
is genuinely wanted in a short block or a match arm, and nothing else separates
them.

**Noting the hazard by type rather than by shape** — reporting only where the
misread produces a discarded value. Rejected because it is a property of what
the language can express this month rather than of the design: the day a call
returning nothing can stand as a statement, the note stops firing on the case
that most needs it.
