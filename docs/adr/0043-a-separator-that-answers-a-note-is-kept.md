# 43. A separator that answers a note is kept

Status: Accepted — 2026-07-28. Refined by
[0190](0190-a-variant-line-is-not-a-continuation.md) and
[0202](0202-a-line-beginning-with-a-parenthesis-is-noted-only-as-an-empty-call.md).

Refines [0041](0041-a-newline-ends-a-statement.md), whose stated consequence
that "`fmt` never produces a file that triggers `[S-Continuation]`" was too
strong. The decision in 0041 stands; this records what the formatter does about
the note, which 0041 got wrong.

## Context

A newline ends a statement, and three tokens begin a statement while also
continuing an expression: `-`, `(` and `.`. Where a statement ends at a newline
and the next line opens with one, the parser emits `[S-Continuation]`.

The note fires only when no `;` separated the two, because a separator is the
author saying which reading was meant. So a `;` written there is not
decoration: it is the one answer to the note.

The formatter deleted every semicolon that ended a line. On this shape that
meant deleting the answer — the note came back, its advice ("end the previous
line with it if that was meant") did not apply, and the `;` the author added to
silence it was removed again on the next save.

0041 claimed the opposite would happen. That claim was never true, and nothing
checked it: `tests/newline` had no case where a formatted statement was
followed by a line opening with one of the three.

## Decision

**`fmt` keeps a `;` the author wrote where the line after it opens with `-`,
`(` or `.`. Everywhere else it still deletes one that ends a line.**

Both halves of the condition are load-bearing. The separator must already be
there, because the formatter deletes a token but never invents one — inserting
a `;` to silence a note would be a rewrite, and the token-preservation property
allows deletion in one direction only. And the next line must open with one of
the three, because that is exactly when the note fires.

A note already in the source therefore stays. That is the sense in which 0041's
consequence was wrong: the formatter cannot remove a note without adding a
token, so the most it can promise is not to *introduce* one.

## Consequences

**Formatted code is not entirely free of semicolons.** 0041 says "a body is one
statement per line, so formatted code has no semicolons at all". That holds
except here, where the separator is carrying meaning a line break cannot.

**The note stays answerable.** Silencing it is a thing an author can do once,
rather than a thing they redo on every save.

**The set of three tokens is stated once**, as `Tag.continuesAnExpression`. The
parser reads it to decide whether to note, and the printer reads it to decide
whether the separator is answering one.

They were nearly left apart, on the argument that a token missing from one and
present in the other costs a kept separator rather than a wrong program. That
argument is only half true, and the wrong half is the likely one. A token the
*printer* knows and the parser does not keeps a `;` that answers nothing, which
is harmless. A token the *parser* knows and the printer does not deletes the `;`
that answers a note the parser is still emitting — which is this record's own
defect, reintroduced. The parser owns the rule and the printer follows it, so
that is the direction drift would actually take.

## Alternatives considered

**Inserting a `;` wherever the note would fire.** It would make 0041's
consequence true, and it would make the formatter write a token the source does
not have. Rejected: the one-directional preservation property is what makes
"the formatter never rewrites a token" checkable, and an insertion allowance
that is not a trailing comma would end it.

**Suppressing the note on formatted output.** Rejected because the note is not
about layout. Its value is the case it was written for — the day an expression
whose value is nothing can stand alone as a statement, both halves of a misread
newline are legal and the mistake compiles. A note that stops firing once a
file is tidy would be absent exactly when the hazard is real.

**Dropping the note.** Rejected for the same reason, and because the parser's
rule is one-sided by design: it never reads the next line, so nothing else in
the compiler is in a position to notice.
