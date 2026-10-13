# 168. Multi-line text is a run of `\\` lines

Status: Accepted — 2026-09-24.

Builds on [0163](0163-a-raw-string-literal-holds-its-bytes.md), which left
multi-line text as a separate question, and on
[0041](0041-a-newline-ends-a-statement.md), which ends a statement at a line
break by reading the token before it.

## Context

Every string literal ends at its line ([S-String]). Text of several lines — a
letter template, a pretty-printed JSON fixture, a usage message, a table — is
therefore written as one line with `\n` escapes, which also doubles its braces
and escapes its quotes, or as lines joined at run time. Either way the reader
sees something other than the text. A raw literal fixes braces and quotes but,
having no escapes, cannot hold a line break at all.

## Decision

**A multi-line literal is a run of lines that each begin with `\\`**, after any
indentation, as in Zig:

```linea
let template =
    \\Dear {name},
    \\your order {order} has shipped.
```

**Each line holds the text after its `\\` to the end of the line, raw**: no
escape is read and no interpolation is opened, so `{`, `}`, `\`, `"` and `//`
are text. **The lines are joined with `\n`, and no line break follows the
last.** An empty `\\` line is an empty line of text, so text that ends with a
line break ends with a bare `\\` line. The indentation before `\\` is layout;
every byte after it is text, trailing spaces included. A `\r` directly before a
line break belongs to the break, so a file saved with `\r\n` holds the same
text.

**Each line is its own token**, a `string_line` running from its `\\` to the
end of its line. The parser makes one `str_literal` of a line and every
`string_line` token directly below it; its token range runs from the first line
to the last, and the one text decoder reads that source and joins the lines.
Everything after the parser reaches the literal through the paths it already
uses for string literals, through one accessor that hands the decoder the
literal's source.

The statement rules follow from the tokens without restating them:

- The first line may share a line with the token before it (`let one =
  \\text`), or begin the next line after a token that cannot end a statement —
  `=`, `(`, `,`, an operator.
- A `string_line` can end a statement, so the line break after the last line
  ends the statement as it does after any literal. Joining the next line is
  not a look ahead across a statement boundary: a `\\` line can only follow
  another when both are one literal.
- Whatever follows the literal starts on a later line, because its last line
  runs to its end: a call's `)` or the next argument's `,` goes on the next
  line.
- **A blank line or a comment between two lines is refused** under [S-String].
  The line after it could only be a second literal standing alone, which is
  never what was meant, and the literal carries on through the gap so that one
  mistake is one report. Any other line ends the literal.

A multi-line literal is a string literal in every other respect: type `Str`, a
constant expression, a parameter default. It is not a pattern, because the
`=>` after it would be text; the parser says so and names the quoted spelling.

**The formatter keeps every line and re-indents the block.** A literal that is
the first thing on its line is written at that line's depth; otherwise its
lines are written one level deeper than the line holding what precedes it. The
first line stays where it was written — beside the token before it or on a
line of its own — because it cannot always move: a line break after `return`
ends the statement. Each line is written byte for byte.

## Consequences

- Templates, fixtures and messages are written as they read.
- The token stream stays lossless and line-based: no token contains a line
  break, the whitespace between two lines is the gap between their spans, and a
  language server sends one string token per line, which is what clients
  without multi-line token support need.
- Recovery is unchanged in kind: a line cannot run past its own end, so no
  mistake in a multi-line literal takes the rest of the file with it.
- The tree-sitter grammar joins lines separated by blank lines or comments too,
  since it sees no line breaks; it accepts more than the language, the
  direction a highlighter may err.
- A multi-line literal as the last argument of a call reads well; one followed
  by another argument puts that argument's `,` at the start of a line. Binding
  the text with `let` first avoids that.
- A match arm whose body is a multi-line literal writes the body as a block,
  `=> {`, the lines, then `},`, because a comma after the last line is text.
  The parser names that form when an arm's comma is missing after a `\\`
  line.
- A `\\` inside an interpolation is refused on its own, so the interpolation
  still closes at its `}` rather than running to the end of the line.

## Interpolation

**A `\\` line does not interpolate.** Multi-line text is overwhelmingly text
that is a notation — JSON, templates filled in later, code samples, tables —
and these are full of braces. Interpolating would bring back the doubled `{{`
on exactly the text this form exists for, which is the cost
[0163](0163-a-raw-string-literal-holds-its-bytes.md) removed for single-line
text. Text that needs a value joins a multi-line literal and an
interpolated one, or fills the template at run time, which is what a template
is for. Zig's lines, which this follows, have no interpolation either.

## Alternatives considered

**Raw literals that span lines, as Rust's do.** One `r#"…"#` token holding line
breaks is the classic multi-line form. It lost on the reasons
[0163](0163-a-raw-string-literal-holds-its-bytes.md) gives: it would be the one
token that crosses lines, so an unclosed one runs to the end of the file and
takes every declaration after it into one invalid token, and the newline rule,
which reads the token before a break, would need restating around a token that
contains breaks. Its indentation is also text, so a literal inside a function
either starts its lines at column zero or carries the function's indentation
into its text.

**Triple-quoted text with indentation stripping**, as in Swift, Kotlin's
`trimIndent`, Python's `textwrap.dedent` or Java's text blocks. It reads well,
but the text a literal holds then depends on a rule about the least-indented
line, the position of the closing delimiter, and what counts as a blank line —
a rule every reader of source, including both editor grammars, must implement
identically — and it is still one token across lines, with the recovery cost
above. A `\\` line says where its text starts on every line by itself.

**No multi-line text.** Lines joined at run time, or `\n` escapes, keep the
language smaller. They are the state that made fixtures and templates
unreadable, and the cost falls on text a reader most needs to see as written.

**A different line prefix, such as `|` or `>`.** Both are operators or begin
tokens already, so a line beginning with one would be ambiguous with an
expression continuing from the previous line. `\\` began no token — a lone
backslash was invalid source, and still is — so it takes nothing from the
language.
