# 84. `test` is a reserved word, not a contextual one

Status: Accepted — 2026-08-16

## Context

`test` became a modifier on a function declaration: `test fn a_thing_holds()`.
It reaches that position only before `fn`, so the parser could recognise it
there and leave it an ordinary identifier everywhere else. That is what a
contextual keyword is, and it is what several languages do with words added
after they had users.

Linea has no users, so nothing is owed compatibility. What decided this instead
is that the word is not spelled once. A reserved word in this compiler is
written in five places, and a conformance property refuses a run where they
disagree: the lexer's keyword table, the grammar block in the semantics
document, the tree-sitter grammar, the Sublime syntax, and the token
classification the language server publishes.

Four of those five are tools that colour text, and none of them resolves names.
A tree-sitter grammar can express "keyword only before `fn`" and a Sublime
syntax essentially cannot; the language server would have to answer from the
parse rather than from the token, which is a second place deciding what the word
is. That is the drift this compiler keeps finding, and it would be introduced
for a word nobody has asked to use as an identifier.

## Decision

`test` is reserved in the lexer's keyword table, like `linear` and `opaque`. It
is a keyword in every position, and a declaration or binding may not be named
`test`.

The agreement property covers it with no exception: the word appears in all five
places, spelled the same way, with no rule about where it is a keyword because
there is no such rule.

## Consequences

A program cannot name anything `test`. Nothing in the corpus did, and the word
is a poor name for a value in any case — but it is a plausible name for a
*function*, and someone writing a testing library in Linea will meet the
refusal. `tests`, `testing` and `test_case` are unreserved.

The five-place property stays a comparison of one table against four lists,
which is what makes it cheap enough to run over every case rather than once.

A future contextual keyword — and `test` is the natural precedent to cite — will
have to answer how a highlighter is supposed to know. This record is that
answer's starting point, not an argument that no keyword may ever be contextual.

## Alternatives considered

**A contextual keyword, recognised only before `fn`.** Keeps `test` an
identifier everywhere else, at the cost of the five places no longer agreeing on
what the word is. A highlighter would colour `test` as a keyword wherever it
appeared, or nowhere; the first is wrong inside `let test = 1`, and the second
is wrong on the declaration the feature exists for. Rejected because the
property that keeps those five in step is worth more than an identifier nobody
has wanted.

**An attribute, `@test fn` or `#[test]`.** Sidesteps the keyword question by
putting the marker in a syntactic space of its own. Rejected because Linea has
no attributes: introducing a whole syntactic category to avoid reserving one
word is a larger change than the one it avoids, and the category would then need
its own rules about what may carry an attribute and what an unknown one means.

**A naming convention, every `fn` beginning `test_`.** No syntax at all.
Rejected because it makes a declaration's meaning depend on its spelling, so
renaming a function silently changes whether it is compiled into the program —
and because the compiler could not then refuse `pub`, parameters or type
parameters on one without guessing at intent.
