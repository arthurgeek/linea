# 304. `template` is a contextual word

Status: Accepted — 2026-11-22. Builds on
[0084](0084-test-is-a-reserved-word-not-a-contextual-one.md) and
[0179](0179-the-prelude-holds-the-core-vocabulary-and-yields-to-a-module.md).

## Context

`template` was reserved for one position: `template impl Trait where
reflect.target: struct { … }`, a structural template, at the start of a
declaration. Everywhere else the reservation only refused names. A program that
fills text from a template is the ordinary place to meet it: the guest book's
`fill` took its form as `form` because `template` could not be a parameter, and
a field, a local or a function called `template` was refused with "`template`
is a keyword, and a keyword cannot be a name".

[0084](0084-test-is-a-reserved-word-not-a-contextual-one.md) kept `test`
reserved and asked the next contextual word to say how a highlighter knows what
it is. [0277](0277-a-test-is-named-by-a-string.md) replaced 0084's premise that
a test is a modified function, and `test` stays reserved: it begins a
declaration followed by a string, and no program has asked for it as a name.
[0179](0179-the-prelude-holds-the-core-vocabulary-and-yields-to-a-module.md)
made `default` contextual for the reason `template` is now asked for: a program
wants the noun.

## Decision

**`template` is a keyword only immediately before `impl` at the start of a
declaration**, as `default` is. Anywhere else it is a name: a parameter, a
local, a field, a function, a pattern binder or an import alias may be called
`template`. A field named `template` is a field like any other to the traits
`@derive` writes and to a structural template's reflection.

**A highlighter knows by the next word.** The Sublime grammar colours
`template` as a keyword only when `impl` follows it, as it does `default`; the
tree-sitter grammar spells it only inside a template declaration, so anywhere
else it parses as an identifier; the language server publishes it as a name,
as it does every contextual word. The gates that hold the lexer, the parser
and the editor grammars to one list read `template` from the contextual words.

**A template missing its `impl` is still one mistake.** At the start of a
declaration a name followed by another name on the same line begins nothing,
so `template Label` and `template imp Label` are read as a template whose
`impl` is missing, and refused once with "expected `impl` after `template`";
the trait, the requirement and the body are then read as the template's, so a
test written in that body is refused as one in a template is. A `template`
alone on its line is one misplaced word, and the declaration on the next line
is read whole.

## Consequences

- The guest book's `fill` takes its form as `template`.
- `template` is no longer a reserved word, so the case showing a keyword in a
  name's position uses `phantom`, which stays reserved.
- The other words used in one position only, among them `test`, `trap`,
  `phantom`, `extern` and `opaque`, stay reserved. This record answers for
  `template` alone.

## Alternatives considered

**Keep `template` reserved.** Costs every program that fills text from a
template the noun, for one declaration form that is rare and already marked by
the `impl` after it.

**Rename the declaration form.** A form spelled `impl … for template` or with an
attribute would free the word without a contextual rule, but it moves every
existing template and its documentation for no gain over a position the parser
already tells apart.
