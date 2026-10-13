# 190. A variant line is not a continuation

Status: Accepted — 2026-09-27. The clause that a lowercase selection keeps
its note is superseded by
[0196](0196-a-selection-line-continues-the-line-above.md). Refined by
[0202](0202-a-line-beginning-with-a-parenthesis-is-noted-only-as-an-empty-call.md).

Refines [0041](0041-a-newline-ends-a-statement.md) and
[0043](0043-a-separator-that-answers-a-note-is-kept.md), whose set of tokens
that open a noted line is refined here for `.`. Extends
[0189](0189-a-names-case-is-part-of-its-kind.md), which makes a name's case
part of its kind, to what the parser reads from it.

## Context

ADR 0041 notes a line that opens with `-`, `(` or `.` after a statement a
newline ended, because each could continue the expression above as well as
begin a statement of its own. ADR 0043 keeps a `;` the author wrote there,
since that separator answers the note.

A function returning a `Result` or an `Option` ends, idiomatically, with a
line such as `.Ok(total)` or `.None` below a statement, and a function
building a structure ends with `.{ x = x }`. Each of those lines drew the
note, so the note fired on ordinary code at the end of most fallible
functions, and the separator that silenced it was a `;` nobody wanted to
write. A note that is usually wrong is one nobody reads -- the argument ADR
0041 made for leaving `{` out of the set.

After a newline, `.` continues the line above only as a selection: an
operation called on the value above, or a field read from it. Both start
with a lowercase letter under [N-Case]. A capitalised name after `.` is a
variant or a type's member, which no value above can select, and `.{`
builds a literal, which nothing continues into.

## Decision

**A line opening with `.` is noted unless a capitalised name or `{` follows
the dot.** A line opening `.Ok(0)`, `.None`, `.Red` or `.{ x = 1 }` is not
noted; `.map(f)`, `.x`, `.0` and a `.` before anything else still are. `-`
and `(` are noted as before.

The rule is still read from tokens alone: the `.`, and the case of the name
after it. The set is stated once, as `Tag.opensAContinuation`, which takes
the token after the opening one; the parser reads it to decide whether to
note, and the formatter to decide whether a `;` answers a note, as ADR 0043
requires. A `;` before a variant line therefore answers nothing, and `fmt`
removes it like any separator ending a line.

## Consequences

**Fallible functions end without a note or a separator.** `.Ok(value)` on
its own line after a statement is the whole spelling, with nothing to
silence.

**A lowercase selection keeps its note.** `.map(f)` or `.count` below a
statement may still be a chain the author broke by accident, and is noted.

**A result type broken across lines is refused once, where it breaks.**
`-> Self` followed by a line `.Item` could only have meant `Self.Item`, and
no note fires on a capitalised selection. Left alone, the line read as no
declaration and the function as one without a body, a cascade of refusals
none of which named the break. Nothing in a declaration's position opens with
`.`, so the parser reads the line with the type and reports [S-Separator]
once at the break. Which type was meant only the author knows, so the
declaration is read with none; nothing that uses it is refused again for a
mistake already reported.

## Alternatives considered

**Noting by what the line above produces** -- staying quiet when it is a
statement that yields no value. Rejected for the reason ADR 0041 rejected
noting by type: the note is about token shape, and a rule that depends on
types stops firing exactly when both readings become legal.

**Dropping `.` from the set entirely.** Rejected because `.map(f)` after a
statement is the hazard the note exists for; only the capitalised and
braced forms are safe, and case is what tells them apart.
