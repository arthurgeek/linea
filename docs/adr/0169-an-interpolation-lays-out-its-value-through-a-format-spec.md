# 169. An interpolation lays out its value through a format spec

Status: Accepted — 2026-09-25.

## Context

An interpolation could choose between two renderings of a value, `Display` and
`Debug` with `:?`, and nothing about where the text lands. Programs that print
a table, a price or a date wrote the layout by hand. `loyalty_points` and
`shipping_quotes` computed `if remainder < 10 { "0" } else { "" }` to print
`$12.05`, and a calendar export needs a padding helper for two-digit months
and hours. Each of these restates the same rule in the program that needs it,
beside the line it lays out rather than in it.

Rust's `format!` and Python's format specs answer this with a short
mini-language after a colon, and the colon is already where Linea's `:?`
sits.

## Decision

**A colon inside an interpolation begins a format spec**, written
`[[fill]align][+][0][width][.precision][?]` with every part optional and in
that order:

```linea
"{day:02}"        // 07
"{count:>4}"      // "  42"
"{price:.2}"      // 3.50
"{name:<10}|"     // "Ada       |"
"{name:*^9?}"     // **"Ada"**
```

- `?` renders through `Debug`, as before, and combines with every other part.
- `<`, `>` and `^` align within the width. Without an alignment a number sits
  on the right and any other value on the left. A fill is the one character
  before an alignment and is written for each column of padding.
- `+` signs a number that is not negative. `0` pads a number with zeros after
  its sign, so `-5` in `:04` is `-005`; it replaces fill and alignment, so the
  two together are refused.
- The width counts Unicode scalars. A wider value is written whole.
- `.precision` counts a Float64's digits after the point, rounding the
  shortest round-trip digits that `Display` prints half away from zero:
  `2.675` becomes `2.68`, which is what the source says, where rounding the
  exact binary value gives `2.67`.

**The spec is checked against the value's type ([T-Format]).** A sign and zero
padding need an integer or a `Float64`; a precision needs a `Float64`. A
generic value is a number when it has `Integer` evidence. Everything else
takes fill, alignment and width. A malformed spec is [S-Format].

**The layout is the library's.** `std.fmt.Spec` holds the parts, and
`write_display`, `write_debug`, `write_integer` and `write_float` apply one to
a value and a writer. An interpolation whose spec asks for layout calls one of
four private adapters in `std.fmt` with the parts as constants, and each
adapter builds a `Spec` and calls the public function. The compiler parses the
spec, checks it, records it with the interpolation's type, and chooses the
function by the value's concrete type; it formats nothing itself. A value with
no spec, or only `?`, still renders through its trait directly.

## Consequences

- Programs lay out tables, money and dates in the literal that prints them,
  and a program that decides the layout at run time calls the same functions
  with a `Spec` it builds.
- A spec is part of the interpolation's type, as `:?` already was, so two
  literals differing only in a spec are two types. The type's name spells the
  spec in its canonical form: `{interpolation UInt8:>4}`.
- `?` stays where it was, so every existing interpolation means what it did.
- The token stream gains a `format_spec` token after the colon. The formatter
  writes it back as spelled, dropping only the spaces around it. The language
  server colours it as an instruction, and both editor grammars know its
  shape.
- A value laid out in a width is rendered twice: once into a writer that only
  counts scalars, then into the real writer. An integer is measured by
  counting its digits instead, and a value without a width renders once.
- A `Writer` whose `Error` is `Never` — the counting writer is one — needed `?`
  to treat the failing edge of `Result[T, Never]` as unreachable, which
  lowering now does.

## Open questions

- **Widths and precisions chosen at run time**, Rust's `{x:width$}`. Not in
  scope: `Spec` covers the need through a function call, and a named width
  would be an expression inside the spec that the lexer, the formatter and the
  editor grammars would each have to delimit.
- **Other radixes and notations** (`x`, `b`, `e`). The type slot is `?` alone;
  another letter is refused, so adding one later changes no accepted program.
- **Display columns.** A wide CJK character or an emoji occupies two columns
  in most terminals and counts as one scalar here. Measuring columns needs a
  width table the library does not carry and a terminal the program may not
  have.

## Alternatives considered

**Library functions only.** `fmt.write_integer(day, Spec { … }, &out)` works
without new syntax, and it is what a program uses for a layout chosen at run
time. As the only way, it moves every layout out of the literal that states
the rest of the line, so `"{dollars}.{cents}"` becomes three statements and
the reader reassembles the line. The literal form and the library share one
implementation, so the syntax adds no second formatter.

**Python's full mini-language.** Python adds `=` alignment, `,` and `_`
grouping, `#` alternate forms, the `z` flag, and eleven presentation types.
Each is a rule to learn and to check against a type, and none was needed by
the programs that motivated this. Keeping Rust's subset leaves room to add
parts later without changing what an accepted spec means.

**C's `printf` conversions.** `%5.2f` names the type in the spec, which a
checked language already knows, and a mismatch between the conversion and the
value is the classic `printf` defect. A spec here states only layout, and the
checker holds it to the value's type.

**Precision truncates text, as Rust's does.** `{name:.3}` would print the
first three scalars of a `Str`. A precision on a `Float64` that became a `Str`
after a refactor would then silently change from rounding to truncation.
Refusing it keeps one meaning per part; truncation is a `Str` operation.

**Precision rounds the exact binary value, as C and Rust do.** `2.675` is
stored as `2.67499999…`, so exact rounding prints `2.67` for a literal that
reads `2.675`. Rounding the digits `Display` shows agrees with the source and
with what `Display` already prints, and it needs only the shortest digits the
runtime already computes rather than an arbitrary-precision expansion.
