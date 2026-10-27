# Editor support

Configure your editor to launch `linea lsp` over stdin/stdout. The repository's
Helix configuration supplies an example. The server supports diagnostics,
completion, hover, definition, rename, formatting, semantic tokens and code
actions; individual corrections depend on the diagnostic. Signature help is not
advertised. A developer-experience session exercising live completion,
navigation and diagnostic repair found the edit/check/run/test loop solid, with
diagnostics usually giving the exact type, location and ownership violation;
the main friction was discovering the library workflow -- the `pub` versus
`export` distinction and the runtime archive required for linking -- rather
than the editor tooling itself.

Syntax highlighting uses two grammars, with four gates that check they stay aligned
with the language.

```
editor-support/
  tree-sitter-linea/
    grammar.js          the only source; src/ is generated and gitignored
    queries/            highlights, indents, textobjects -- read by Helix
  sublime-linea/
    linea.sublime-syntax  read by bat
```

`nix develop` installs both: the tree-sitter grammar is compiled into Helix's
runtime directory and the Sublime syntax copied into bat's, each only when that
editor is on `PATH`.

## Why the gates exist

A grammar is easy to write and easy to forget. Add a reserved word to the lexer
and the grammars are wrong — but nothing breaks, because wrong highlighting is
not an error. It is a word that quietly stopped being coloured, and nobody
notices for months.

The four gates turn that silence into a failing build. They run under
`zig build test` like everything else.

| Gate | Asserts |
| --- | --- |
| Reserved-word parity | every word in the lexer's table is a terminal in both grammars |
| Highlight coverage | every one has a capture in `highlights.scm` |
| Grammar parity | the two grammars carry the same set |
| Corpus sweep | tree-sitter parses every `.lin` the compiler parses, with no `ERROR` or `MISSING` node |

The first three read `token.reserved_words` directly rather than searching
`token.zig` for a pattern. A pattern that stops matching reports success, which
is the failure being guarded against rather than a detail of how.

The fourth exists because the first three only reach the surface. A grammar can
mangle `impl` blocks or match arms entirely while every keyword is present and
every parity gate is green — keywords say nothing about structure.

## Adding a reserved word

1. Add it to `reserved_words` in `src/lexer/token.zig`.
2. Run `zig build test -Dtest-filter='reserved word'` during development; the
   parity and highlight checks name the word and file that has not caught up.
   Reserve `zig build test` for the single
   final unfiltered run required by [AGENTS.md](../AGENTS.md).
3. Add it to `grammar.js`, to `queries/highlights.scm` under the role it plays,
   and to `linea.sublime-syntax` under the matching scope.

Step 2 is the point: you are told what to do rather than expected to remember.

## Changing the grammar

`grammar.js` is the only source. `src/` is generated and gitignored — a
regenerated `parser.c` is a six-figure-line diff that makes a grammar change
unreviewable, and a generated file in the tree can disagree with what produced
it.

To regenerate by hand:

```
cd editor-support/tree-sitter-linea && tree-sitter generate -o src
```

The test suite does this for you; the shellHook does it again when `grammar.js`
differs from the source it last emitted.

Every reserved word must appear in `highlights.scm` as a **bare literal in
quotes**, because that is exactly what the coverage gate checks. Capturing a
word through a named node would need an allowlist, and an allowlist is where
coverage goes to die: adding to it is always easier than adding the capture.

Beware a rule whose body is exactly one string — tree-sitter collapses it and
the token disappears, so the word cannot be captured at all. That is why
`continue` is written where it is used rather than wrapped in a rule of its
own. Policy attributes share a rule with several literal alternatives.

Closed declaration attributes (`@opaque`, `@linear`, `@copyable`, `@carrier`,
`@unshareable`, and `@derive(Traits)`) precede a struct, enum, or newtype and its
ordinary visibility. Grouped `@(items)` and repeated attributes retain their
written order; comments may separate them. The editor grammar preserves these groups for indentation
and highlights derive trait paths as types. The compiler validates duplicate
items, conflicting policies, and derive requirements. Independently constrained
standalone derives retain their own declaration grammar. Bare policy prefixes
are no longer declaration syntax.

## What the tree-sitter grammar is for

Colouring and navigation, over source that is broken most of the time it is
read. It is **not** a second implementation of the parser and must not become
one.

The two survive broken input in opposite ways. The compiler's parser *recovers*:
it knows what is wrong, says so, and resynchronises, because passes downstream
will reject the program anyway. This one *accepts*: it has no diagnostics and no
downstream pass with an opinion, and being approximately right about a construct
beats being unable to say anything about the rest of a file because line 12 is
half-typed.

So where the compiler diagnoses, this accepts. A chained comparison is the
clearest case — the language rejects `a == b == c`; this colours it.

Diagnostics come from the language server instead. `linea lsp` speaks the
protocol over stdin and stdout, and `.helix/languages.toml` launches it through
its `language-servers` key — so a construct this grammar deliberately colours is
still underlined by the compiler that refuses it. Semantic colouring belongs to
the resolver rather than to the grammar, which stays lexical.

## What is deliberately absent

- **No published package.** `tree-sitter.json` supplies the local grammar name,
  scope, and highlight query paths used by the CLI; there is no `package.json`
  or separately published editor package.
- **No capture-coverage gate.** Nothing checks that a query's node names still
  exist in the grammar, so a renamed node silently matches nothing —
  `indents.scm` and `textobjects.scm` are unguarded against it entirely. This
  is the known hole and the likely next gate; it needs no new tooling, since
  `node-types.json` is already emitted.
