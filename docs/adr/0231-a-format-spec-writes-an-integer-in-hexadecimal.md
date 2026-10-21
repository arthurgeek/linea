# 231. A format spec writes an integer in hexadecimal

Status: Accepted — 2026-10-17. Extends
[0169](0169-an-interpolation-lays-out-its-value-through-a-format-spec.md).

## Context

[0169](0169-an-interpolation-lays-out-its-value-through-a-format-spec.md)
left other radixes open: its type slot held `?` alone, and refused every other
letter so that adding one later changes no accepted program.

Eight places in the standard library spelled or read hexadecimal digits by
hand, each with its own alphabet literal or digit-value table: the `\u00XX`
escapes `json` and `log` write, the `\uXXXX` escapes `json` reads, the `\xNN`
escapes a `fs.Path` displays, the random digits of an atomic save's temporary
name, the `%XX` a CGI path is encoded again with, and the router's
percent-decoder. A program had no way to write `#ff6699` or a byte's two
digits without the same loop. A web program that must keep arbitrary text in
a cookie needs exactly that, and the guide's cookie section could only tell the
reader to "encode such text, for example in hexadecimal".

## Decision

**The type slot of a format spec takes `x`, `X` or `?`.** The spec is written
`[[fill]align][+][0][width][.precision][x|X|?]`:

```linea
"{color:06x}"     // ff6699
"{byte:02X}"      // 0A
"{code:>6x}"      // "    ff"
```

- `x` writes an integer's digits in base 16 with `a` to `f`, and `X` with `A`
  to `F`. No `0x` is written; a program writes it in the literal.
- The other parts lay the digits out as they lay out decimal ones: fill,
  alignment and width, a `+` sign, and `0` padding between the sign and the
  digits.
- A negative integer is written as its sign and its magnitude, so `-255` is
  `-ff` whatever its type, and `Int64.min` is `-8000000000000000`.
- A spec holds one of `x`, `X` and `?`; `{n:x?}` is refused by [S-Format] with
  that sentence, rather than as a part out of order.

**[T-Format] refuses `x` and `X` on a value that is not an integer**, a
`Float64` or a `Str` included, and its help names `text.hex_encoded` for
writing the bytes of text or a slice. A generic value takes them when it has
`Integer` evidence, as it takes `0`.

**`fmt.Spec` gains `hex: Option[text.LetterCase]`**, which `write_integer`
reads, so a layout chosen at run time asks for the same digits. `None` writes
decimal. The interpolation adapters take the choice as one more constant part.

**The library has one hexadecimal alphabet and one digit-value table**, in
`std/text/hex.lin`: `text.hex_digit(value, case:)` spells one digit,
`text.hex_digit_value(byte)` reads one, and `text.hex_byte(high, low)` reads
the byte two of them spell. `text.hex_encoded(bytes, case:)` is an
opaque, copyable value that displays bytes as two digits each without
allocating, and `text.hex_decode` and `text.hex_decode_in` read them back,
refusing a byte that is not a digit (`HexError.NotADigit`, with its offset) and
an odd count of digits (`HexError.OddLength`). Every place above now calls
these: an escape is `"\\u{byte:04x}"`, a path's byte is `hex_encoded`, a JSON
`\u` escape is read with `hex_digit_value`, and the percent-decoder reads
`hex_byte`.

## Consequences

- Programs write colours, byte dumps, checksums and escapes in the literal
  that prints them.
- A spec's canonical spelling, and so an interpolation type's name, ends in
  `x` or `X` when it asks for hexadecimal: `{interpolation UInt8:02x}`.
- The `Format` record keeps its 64 bits: the choice takes two of the five
  that were unused.
- Writing a byte through `hex_encoded` costs two table lookups and two writes;
  it does not build a `Spec` per byte.

## Alternatives considered

**Two's complement for a negative integer, as Rust and C write it.**
`{-1:x}` would be `ff` for an `Int8` and `ffffffffffffffff` for an `Int64`, so
the text would depend on the integer's width, which an inferred literal does
not show, and `+` and `0` would have no consistent meaning beside it. Sign and
magnitude agrees with decimal: `-ff` with `:06x` is `-000ff`, as `-5` with
`:04` is `-005`. A program that wants the bits converts to the unsigned type
first.

**`#` for a `0x` prefix, as Rust and Python spell it.** One more part to learn
and to check, for two characters the literal can hold.

**Allowing `x?`, Debug in hexadecimal, as Rust does for collections.** Debug of
an integer is its decimal digits, and nothing in the library renders a
collection's elements through a caller's spec, so the combination would have
no meaning to give.

**Byte encoding through the format spec alone.** `{bytes:x}` on a slice would
need the spec to reach inside a collection, which no other part does, and a
`Str` would be ambiguous between its text and its bytes. A display value,
like `html.escaped`, keeps the spec about one value and makes the bytes
explicit: `text.hex_encoded(name.as_bytes())`.

**A private digit table in each module, as before.** Each was correct, and
each was a place to get the alphabet's case, the nibble order or a digit's
value wrong independently. The library's own rule is one answer computed in
one place.
