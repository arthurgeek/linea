# 163. A raw string literal holds its bytes

Status: Accepted — 2026-09-24.

## Context

A string literal reads two kinds of syntax inside its quotes. A backslash
begins an escape ([S-Escape]) and a `{` opens an interpolation
([S-Interpolation]), so a literal `{` is written `{{` and a literal backslash
`\\`.

Both are the right default for text a program composes, and both get in the
way of text that is itself a notation. `std.http` routes are written
`GET /items/{id}`, and every route in a program, a test or the library's own
documentation had to be spelled `"GET /items/{{id}}"`. A JSON fixture is worse:
`"{{\"ok\":true}}"` doubles every brace and escapes every quote, and a reader
has to undo both to see the document. Windows paths and regular-expression-like
patterns pay the same tax with backslashes. In each case the doubled spelling
is the one that gets copied into a real program, and a missed doubling is
either an interpolation of a name that does not exist or, worse, one that does.

## Decision

**A literal written `r"…"` holds the bytes between its quotes exactly.** No
escape is read and no interpolation is opened, so `r"GET /echo/{name}"` holds
the braces and `r"C:\temp"` the backslash. **Hashes between the `r` and the
opening quote let the text contain a quote**: the literal closes at the first
quote followed by as many hashes as opened it, so `r#"{"ok":true}"#` holds
`{"ok":true}`, and `r##"a "# b"##` holds a quote followed by one hash. **At most
eight hashes may open one**; a literal opened with more is refused under
[S-String].

A raw literal is a string literal in every other respect. It has type `Str`, it
is a constant expression, it can be a parameter default, and one naming a
single scalar denotes that scalar at a range end. Like every string literal it
ends at its line: an unclosed one is [S-String], reported with the closing
sequence it needs. **It cannot hold a line break**: it has no escapes, so
there is no way to write one inside it. An `r` followed by anything other
than a quote, or hashes and a quote, is a name, so `let r = 1` and `rr"x"`
read as they always have.

The lexer produces the ordinary `string_literal` token for one, from its `r` to
its last hash. Nothing after the lexer tells the two spellings apart except the
routine that decodes a literal's text, which already answers what bytes every
literal holds; a raw literal is the case where it copies them. The parser,
constant folding, the range-end conversion, lowering, the formatter and the
language server's highlighting all reach raw literals through the paths they
already use for string literals, rather than through a second token kind each
would have to learn.

## Consequences

- Route patterns, JSON fixtures and paths are written as they read, and the
  library's route tests and documentation use them.
- The token stream stays lossless: a raw literal is one token whose span is its
  spelling, and the formatter prints it back byte for byte.
- `r` is not reserved. A name `r` directly followed by a quote is the one
  spelling whose reading changes, and before this it was a name followed by a
  literal with nothing between them, which no construct accepted.
- A raw literal cannot interpolate. Text that needs both a literal brace and a
  value keeps the doubled spelling, or joins a raw literal to an interpolated
  one.
- The language bounds the count so that every reader of source can agree on
  the closing rule. Matching a count of hashes is not regular, and the
  tree-sitter grammar keeps `grammar.js` as its only source, with no
  hand-written external scanner that would be a third implementation of the
  rule. Up to eight, each count is its own expression there, and the Sublime
  syntax matches the same range through a back-reference. A gate holds both
  editor grammars to the lexer's bound, and the corpus holds a nine-hash
  literal that the compiler and the grammar both refuse. Text needing `n`
  hashes contains a quote followed by `n - 1` of them, so eight costs no real
  text anything.
- Multi-line text cannot be a raw literal. A template or a pretty-printed JSON
  fixture of several lines is an ordinary literal with `\n` — with doubled
  braces and escaped quotes again — or lines joined at run time. This is the
  largest cost of the decision; how Linea writes multi-line text is a separate
  question.

## Alternatives considered

**Keep doubled braces and escapes only.** This was the state before. It needs
no new syntax, and it is why every route in the HTTP library read
`{{id}}`: the cost falls on exactly the text that is a notation, where a
reader most needs to see the notation, and a missed doubling compiles when the
name inside happens to be in scope.

**Go's backtick strings.** `` `GET /echo/{name}` `` needs no count and is short.
It adds a delimiter the language has no other use for, and a backtick string
still cannot contain a backtick, so text that contains one needs a second
mechanism anyway. The hash count solves embedded quotes, and the same problem
one level up, without a new delimiter: the quote stays the string delimiter
everywhere.

**Raw literals span lines, as Rust's do.** Multi-line templates and fixtures are
the classic use of a raw string, and a raw literal crossing lines would serve
them. It lost, for now, on three counts. [S-String] ends every string literal at
its line, and raw literals would be the one token that crosses lines. An
unclosed raw literal would then run to the end of the file, taking every
declaration after it into one invalid token, where today recovery resumes at the
next line. And a statement ends at a line break, a rule that reads the token
before the break; a token spanning breaks needs that rule restated around it.

**Any number of hashes, as the compiler first read them.** Unbounded counts
leave editor grammars unable to agree with the compiler: tree-sitter's
tokens are regular, so it either stops at some count, making a valid program an
error there, or grows a hand-written external scanner that restates the closing
rule a third time. Rust bounds the count as well, at 255.

**Change the route syntax to `:name`.** `GET /echo/:name` would avoid braces for
routes alone. It moves the cost to one library's notation instead of removing
it, leaves JSON, paths and patterns exactly as awkward as before, and the brace
form is the one HTTP routers and URI templates already share.
