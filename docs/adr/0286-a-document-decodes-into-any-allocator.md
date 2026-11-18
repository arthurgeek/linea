# 286. A JSON document decodes into an allocator of its own

Status: Accepted — 2026-11-18. Supersedes the sentence of
[0141](0141-json-documents-own-bounded-trees-and-number-tokens.md) that
"`from_value` uses the same Decode operation with an existing document and
the same allocator type".

## Context

`json.Decode[A].decode` took the document as a `Value[A]`, in the allocator
it decodes into, and so did `from_value_in`, `from_value` and
`ObjectDecoder[A]`. The decoded value owns everything it holds, copied from
the document into `A`, and its error owns its path in `A`: nothing decoded
borrows the document, which the caller may release first. The shared type
parameter was therefore not what kept a result independent of its source.
It only refused programs: a document parsed into a request's arena could not
be decoded into system `String`s, and one parsed with the system allocator
could not be decoded into an arena, because the two `Value`s differ only in
their allocator.

## Decision

**The document's allocator is a type parameter of its own.**

- `Decode[A].decode[B: Allocator](value: Value[B], allocator: A)`: the trait
  and every implementation the library provides, the derived one included,
  take the document in any allocator. `missing(allocator: A)` and
  `DecodeKey[A].from_name` are unchanged.
- `from_value_in[A, B, T: Decode[A]](allocator: A, value: Value[B])` and
  `from_value[B, T: Decode[mem.SystemAllocator]](value: Value[B])`.
- `ObjectDecoder[A, B]` borrows an object in `B` and decodes its members and
  records the names it read in `A`; `open` and `open_in` take a `Value[B]`.
- `decode_in` and `decode_file_in` still parse their temporary document with
  the allocator they decode into, so a request decoded into its arena takes
  nothing from elsewhere.

The derive is written `json.Decode[A]` as before. A handwritten
implementation adds `[B: Allocator]` to its `decode` and takes a
`json.Value[B]`.

## Consequences

- A document read once into an arena decodes straight into longer-lived
  system values, and the arena is released without copying the document out
  first. A corpus case decodes each way and releases the document before it
  reads the result.
- What the result may depend on is unchanged: `carries(.Ok: allocator)` and
  `carries(.Err: allocator)`, never the value, so a codec that returned a
  view of the document is refused as before.
- Every handwritten `Decode` in the library, the examples and the tests
  migrates by adding the parameter.

## Alternatives considered

**Re-render a document into the target allocator first.** It allocates a
second document and can fail where decoding would not, to get around a type
equality nothing needs.

**Let decoding borrow from the document.** A borrowed decode is a different
contract, with results that end with their document; it is not what
`Decode` promises, and it would need a codec of its own.
