# 4. Tokens are stored SoA as `{ tag, span }`

Status: Accepted — 2026-07-24

## Context

Fast compilation is a stated goal of the language, and the token array is the
largest per-file data structure the frontend builds. The initial `Token` was:

```zig
struct {
    kind: TokenKind,     //  1 byte
    lexeme: []const u8,  // 16 bytes
    start: usize,        //  8
    end: usize,          //  8
    line: usize,         //  8
    column: usize,       //  8
}                        // 49 bytes, padded to 56
```

Two of those fields are derivable. `lexeme` is always
`source.text[start..end]`. `line` and `column` are recoverable from `start` by
scanning, and are needed only when a diagnostic is rendered — which is rare,
and never on a clean compile. Maintaining them cost a branch and two increments
per byte lexed.

The parser's hottest loop reads tags and nothing else.

## Decision

```zig
pub const Token = struct { tag: Tag, span: Span };  // Span = { start: u32, end: u32 }
pub const TokenList = std.MultiArrayList(Token);
```

Nine bytes per token, held as one `[]Tag` column and one `[]Span` column.

- The lexeme is computed from the span at the point of use.
- Line and column come from `SourceMap`, which builds a `line_starts: []u32`
  index lazily on first request and binary-searches it.
- Offsets are `u32`, capping a single source file at 4 GiB.

## Consequences

- Roughly six times denser than the struct it replaces. A pass that reads only
  tags streams a dense byte array instead of striding 56 bytes to consume one.
- The lexer's inner loop no longer tracks line and column.
- Obtaining a line and column is a `SourceMap` lookup rather than a field
  access. Diagnostic construction is marginally more involved; everything else
  is unaffected.
- Adding a per-token field means adding a column, which is cheap for passes
  that do not read it.
- `MultiArrayList.Slice` is passed around rather than the list itself, so
  column pointers are resolved once instead of per access.

## Alternatives considered

**Store `start` only and re-lex to find the end**, as the Zig compiler does.
Saves four bytes per token. Rejected: the formatter needs exact extents for
comment tokens, and recovering them by re-lexing puts a second, subtly
different lexer inside the formatter. Four bytes is not worth that.

**Keep AoS and merely shrink the fields.** Gets most of the size win with none
of the layout win. Rejected: tag-only scans are the frontend's dominant access
pattern and are exactly what SoA optimises.

**Retain `line` and `column` for diagnostic simplicity.** Rejected: it is
per-token cost paid for information needed on a vanishing fraction of tokens,
and only on failing compiles.
