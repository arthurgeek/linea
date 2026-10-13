# 7. Build the complete diagnostics engine in Stage 1

Status: Accepted — 2026-07-24

## Context

Excellent diagnostics are a stated goal of the language rather than a quality
of its implementation. Diagnostics are also unusually viral: the span carried
by a token, the shape of a diagnostic record, and whether errors accumulate or
abort are decisions visible at every reporting site in every pass.

Retrofitting them means revisiting all of those sites. Rendering, by contrast,
is a leaf that depends on the diagnostic record and the source and is depended
on by nothing.

## Decision

Build the full engine at Stage 1, including presentation.

```zig
pub const Label = struct { span: Span, message: []const u8, style: LabelStyle };
pub const Diagnostic = struct {
    severity: Severity,
    code: ?Code,
    message: []const u8,
    labels: []const Label,
    notes: []const []const u8,
};
```

- `Sink` accumulates into the compilation arena and counts errors and warnings.
- Codes occupy reserved per-pass ranges (`LIN0xxx` lexer, `LIN1xxx` parser,
  `LIN2xxx` resolver, `LIN3xxx` type checker, `LIN4xxx` ownership, `LIN9xxx`
  driver) so they remain stable as passes land.
- The terminal renderer produces code, message, `--> path:line:col`, a numbered
  source gutter, primary carets and secondary underlines on a single snippet,
  and trailing note and help lines. Colour follows TTY detection and
  `--color=auto|always|never`.
- A JSON renderer behind `--error-format=json` serves editors.
- Rendering depends on `Diagnostic`, `Source` and `SourceMap`; nothing depends
  on rendering.

## Consequences

- Every pass reports against a record that already supports multiple labels,
  notes and codes, so no reporting site is revisited when diagnostics grow more
  ambitious.
- Error codes are stable and documentable from the start.
- Editor integration exists before there is an editor plugin to consume it.
- Stage 1 carries several hundred lines of rendering that the calculator itself
  does not need, competing with parser work. This is accepted deliberately.
- Diagnostic goldens must be captured with `--color=never` to stay diffable.
- Column computation counts Unicode scalar values. Grapheme clusters and wide
  characters will misalign carets on some non-ASCII source; deferred until the
  renderer must handle it.

## Alternatives considered

**Keep single-line `path:line:col: error: message` output and abort on the
first error.** Fastest to a working calculator. Rejected: aborting contradicts
the infallible frontend, and the accumulating sink and multi-label record are
precisely the viral parts, so deferring them means revisiting every reporting
site later.

**Build the record and sink now, defer rendering polish.** Separates viral
structure from leaf work correctly, and would have been the cheaper path.
Rejected because diagnostics are a language goal rather than an implementation
detail: the rendered output is the artifact users judge, and having it working
early sets the standard that later passes are written against.
