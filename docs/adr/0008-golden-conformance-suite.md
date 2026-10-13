# 8. Correctness is defined by a golden-file conformance suite

Status: Accepted — 2026-07-24

## Context

A compiler is a pipeline of transformations over structured data. Its outputs —
token streams, trees, diagnostics, results — are large and structural, and the
interesting assertions are about their whole shape rather than about individual
fields.

Expressing such assertions inline is verbose enough that in practice fewer and
weaker ones get written. Rendered diagnostics, which this project invests in
heavily, are especially awkward to assert on in code.

## Decision

The conformance suite under `tests/` is the primary correctness artifact.

Each case is a `.lin` input beside checked-in expectations. The expectation
extensions present next to an input determine which stages run:

```
tests/lexer/comments.lin        tests/lexer/comments.tokens
tests/parser/precedence.lin     tests/parser/precedence.ast
tests/diag/undefined_name.lin   tests/diag/undefined_name.stderr
tests/recovery/missing_semi.lin tests/recovery/missing_semi.ast
                                tests/recovery/missing_semi.stderr
tests/eval/arithmetic.lin       tests/eval/arithmetic.out
```

- The runner walks `tests/` at runtime and calls the compiler in-process
  through the same entry points the `dump-tokens`, `dump-ast`, `check` and
  `run` subcommands use.
- Mismatches print a diff. `zig build test -Dupdate` rewrites
  expectations.
- Diagnostic goldens are captured with `--color=never`.

Two properties run over every input in the corpus:

- **Lossless reconstruction** — emitting each token's preceding gap followed by
  its own text reproduces the source byte for byte
  ([ADR 0005](0005-lossless-token-stream.md)).
- **Total parsing** — parsing any input returns a well-formed tree without
  panicking or looping ([ADR 0003](0003-infallible-frontend.md)).

Inline `test` blocks are reserved for logic intricate enough to warrant direct
assertions: precedence climbing, the `SourceMap` binary search, and span
arithmetic.

## Consequences

- Adding a test is adding a file, so the corpus grows in the course of ordinary
  work.
- Diagnostic output is asserted exactly as users see it, which makes rendering
  regressions visible.
- The properties turn two architectural guarantees into executable checks
  rather than intentions.
- The corpus is a specification of observed behaviour, and survives the rewrites
  that Stages 2–9 will do to the passes beneath it.
- `-Dupdate` makes accepting wrong output easy. Golden diffs must be read
  before being accepted; this is a review discipline, not something the tooling
  enforces.
- The dump formats become an interface. Changing one churns many expectation
  files at once.

## Alternatives considered

**Inline Zig `test` blocks only.** Zero infrastructure, idiomatic, and the
tests live where the code is edited. Rejected: asserting a full token stream or
tree shape inline runs to dozens of lines per case, so coverage suffers, and
rendered diagnostics are impractical to assert this way.

**Golden files without the properties.** Covers the pipeline and is most of the
value. Rejected: the lossless-token guarantee would go unverified, so trivia
bugs would surface in the formatter rather than in the lexer where they are
cheap to find.

**Compare against a reference implementation.** Not applicable; none exists.
