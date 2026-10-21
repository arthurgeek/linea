# 232. A cookie value is percent-encoded text

Status: Accepted — 2026-10-17.

## Context

`Response.set_cookie` refused a value holding a space, `"`, `,`, `;`, `\`, a
control byte or anything outside ASCII, because RFC 6265 lets a cookie value
carry only some visible ASCII bytes and a `;` or a line break would end the
cookie early or add a header. The refusal was the handler's own mistake, so
`?` answered 500. Any value a person types hits it: `Ada Lovelace`, `Zoë` and
`Ada <b>` each made a guest-book handler store an entry and then fail. The
guide told the reader to "encode such text, for example in hexadecimal", and
the library had no public way to do that. `Request.cookie` returned the bytes
as sent, so the encoding and the decoding were the program's to pair.

## Decision

**`set_cookie` takes any text as the value and writes it with
`http.percent_encoded`.** Percent-encoding leaves only ASCII letters, digits,
`-`, `.`, `_` and `~` and writes every other byte as `%XX`, all within the
cookie octets, so no value is refused and `CookieError.InvalidValue` is gone.
The name stays an HTTP token, refused with `NotAToken` and a message that
lists what a token may hold.

**`Request.cookie(name)` decodes the value into the request's arena** and
returns `Result[Option[String[mem.Handle[P]]], mem.Oom]`, so a value reads back
as it was set. **A value that does not decode reads as `None`.**
`set_cookie` never writes one, so another program on the domain or the client
wrote it, and a browser keeps sending it until it expires: refusing the request
would lock the visitor out, while reading it as absent sends the handler down
the path a first visit takes, and its next `set_cookie` replaces it.

**`Request.cookies()` still walks the pairs as sent**, borrowing the request and
allocating nothing; `http.percent_decode_in(request.allocator(), pair.value)`
decodes one.

## Consequences

- A handler stores a person's text in a cookie with one call and reads it
  back with one, and the guide shows it.
- A value that was already a token, such as `dark` or `42`, is written
  unchanged; one holding `=` or `+` grows by two bytes for each.
- `cookie` allocates, so it can fail for memory; `?` in a handler answers 500,
  as for any full arena.
- A malformed cookie is indistinguishable from an absent one through
  `cookie`; `cookies()` and `percent_decode` tell them apart for a program
  that cares.

## Alternatives considered

**Keep refusing and leave encoding to the caller.** That is the defect: the
common case fails at run time with a 500, and every program must pair an
encoder with a decoder itself.

**Hexadecimal or base64 values.** Either fits the cookie octets, but doubles
or inflates every value, ASCII included, and neither is what browsers, other
servers or `document.cookie` code expect; percent-encoding keeps a token
value as it is and is what a URL already uses.

**Quote the value, as RFC 6265 allows.** A quoted value still cannot hold `"`,
`\`, a control byte or non-ASCII text, so it narrows the refusal without
removing it.

**Refuse a cookie that does not decode with 400.** The browser would send it
again on every request until it expired, so the visitor could not reach the
page at all.

**Decode `cookies()` too.** The walk would have to allocate per pair or fail
mid-iteration; it stays the raw view, and the one-name lookup a handler
usually wants decodes.
