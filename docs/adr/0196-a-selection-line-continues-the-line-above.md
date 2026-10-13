# 196. A newline ends a statement, unless the next line selects from it

Status: Accepted — 2026-09-28. Refined by
[0202](0202-a-line-beginning-with-a-parenthesis-is-noted-only-as-an-empty-call.md).

Supersedes [0041](0041-a-newline-ends-a-statement.md), and the clause of
[0190](0190-a-variant-line-is-not-a-continuation.md) that a lowercase
selection keeps its note. Builds on
[0189](0189-a-names-case-is-part-of-its-kind.md), which makes a name's case
part of its kind, and on [0190](0190-a-variant-line-is-not-a-continuation.md),
which reads that case after a `.`.

## Context

ADR 0041 made a newline end a statement after any token that can end one,
reading only the token before the break. A pipeline written across lines
therefore had to end each line with the `.` that carried it on:

```
let total = scores.as_slice().
    map(|sink score| *score).
    fold(0, |sink sum, sink score| sum + score)
```

ADR 0192 made iterator adapters operations of every sequence, so a pipeline
is now a chain of selections, and a long one is written across lines. Every
language a newcomer brings a chain from -- Rust, Kotlin, Swift, JavaScript --
puts the `.` at the start of the line, and so did every chain the standard
library and the examples wanted to write. Under 0041 that line began a
statement of its own and drew [S-Continuation]: the chain parsed as a binding
followed by a refused variant.

ADR 0041 rejected looking at the next line because the rule would then have
two halves that cannot be stated alone. That was true of the forward rule it
weighed, which let any token that cannot start a statement carry the line.
ADR 0189 has since made a name's case part of its kind, and ADR 0190 already
reads that case after a `.`: an operation and a field start with a lowercase
letter, and a variant, a type and a type's member with a capital. No statement
begins with `.` and a lowercase name -- a variant shorthand is capitalised and
a literal is `.{` -- so such a line has one reading, and it is a selection.

## Decision

**A newline ends a statement after a token that can end one, unless the next
line opens with `.` and a lowercase name.** Such a line selects an operation
or a field from the expression above, and continues it:

```
let total = scores
    .as_slice()
    .map(|sink score| *score)
    .fold(0, |sink sum, sink score| sum + score)
```

The rest of 0041 stands as it was decided. The tokens that can end a
statement are a closed set, which the semantics document lists; the final
expression of a block is its value; `;` separates two statements on one line;
and an expression otherwise written across lines ends each line with the
operator that carries it on.

The one exception reads one token pair after the break, and only its shape:
the `.`, and the case of the name after it. `Tag.continuesTheLine` states it,
and the parser's `finishedAtALineBreak` -- the one place a newline ends an
expression -- asks it. It is a rule about expressions: the path of an
`import`, a `use`, a trait a declaration names, and a written type still end
at the line break, since a declaration's line holds its whole path and a
re-export reaching down a line would export a name the author set apart. A comment or a blank line between the two lines holds
no token, so the line after it is still the next line and still continues.

**A line opening with `.` and any other name begins a statement.** `.Ok(x)`,
`.None` and `.{ x = 1 }` below a statement are the function's result or a
statement of their own, as ADR 0190 decided. A name with no case, such as
`_1`, may name a variant as well as a field, so `._1` begins a statement and
is noted as before.

**[S-Continuation] keeps the tokens that are ambiguous.** A line opening
with `-`, `(`, `.` before a number or a caseless name, is noted where a
newline ended the statement above it. A `.` before a lowercase name no longer
reaches the note inside a body where it continues the line. It is still
noted where the statement above ended anyway: after a declaration's path,
which a line break always ends, such as a `use` followed by a line `.thing`,
and after an expression ending in a block -- a `match`, an `if` or a block --
which takes no selection on its own line either. The note there says to bind
the value first, since ending the line with the `.` would not help.

**`fmt` keeps the dot at the start of the line.** A chain the author broke
across lines -- at any of its links, before the `.` or after it -- is written
one selection per line, each indented one level below the chain's first line
and opening with its `.`; a `?` stays on the line of the selection it
follows. The first selection stays beside the name it selects from where the
author wrote it there, so `fs.read_file(path)` and `values.as_slice()` keep
reading as one name: the formatter does not know whether `fs` is a module or a
value, and a module's member broken from its module would read as a chain. A chain written
on one line stays on one line, since layout follows what the author wrote
(ADR 0036). A chain inside an argument of a broken chain is laid out on its
own terms. A comment between two links stays between them.

## Consequences

- A pipeline reads as a column of selections, which is the spelling every
  example, the standard library and the READMEs now use where a chain spans
  lines. A line ending in `.` still parses, since `.` cannot end a statement,
  and `fmt` moves the dot to the start of the next line.
- The rule costs one token of lookahead where a newline follows a token that
  can end a statement, and a case check of one name; nothing is sized by the
  program.
- The tree-sitter grammar already ignored the line break between tokens, so a
  leading-dot chain reads there as one expression with no change to the
  grammar.
- A line `.x` below a binding, which 0041 read as a refused variant, is now a
  field read of the binding's value. A program relying on the old reading was
  already refused, so no accepted program changes meaning.

## Alternatives considered

**Keep 0041 and end each line with the `.`.** The one-sided rule parses the
trailing-dot chain, but nobody writes a chain that way, and a newcomer's first
multi-line pipeline drew a note and two refusals. The rule was simple to state
and wrong about the program everyone writes.

**Continue at any line opening with a token that cannot begin a statement**,
the forward rule 0041 rejected. It would also carry `+`, `*` and `==` lines,
and each operator added to the language would change where statements end. The
case of a name after a `.` is decided by [N-Case] for every name the program
declares, so the exception here can only grow with that rule, not with the
operator set.

**Continue at every line opening with `.`.** A variant shorthand line,
`.Ok(total)` at the end of a fallible function, would then select `Ok` from the
statement above and be refused. ADR 0190 made that line the idiomatic result,
and case is what tells the two apart.

**Let `fmt` break long chains by width.** The formatter measures nothing
(ADR 0036); a chain is broken where the author broke it, and then broken at
every link.
