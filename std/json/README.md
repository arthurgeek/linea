# JSON documents and typed values

Input of a known shape decodes straight into a struct:

```linea
import std.json
import std.io
import std.mem

@derive(Release, json.Decode[A])
struct Stock[A: Allocator] {
    name: String[A],
    units: UInt64,
}

fn main() -> UInt8 {
    let stock: Stock[mem.SystemAllocator] = json.decode(r#"{"name":"tea","units":3}"#) else |error| {
        io.eprintln(error)
        error.release()
        return 1
    }
    defer stock.release()
    let name = stock.name.view()
    let units = stock.units
    io.println("{name}: {units} units").unwrap()
    return 0
}
```

A raw literal, `r#"…"#`, writes a JSON document as it reads: its braces open no
interpolation and its quotes need no escapes. The annotation on `stock` tells
`json.decode` which type to build. A document with a field missing, a field of
the wrong kind or a field `Stock` does not declare is refused, and the error
prints as the problem and where it is, such as `missing field at $["units"]`.
[Typed values](#typed-values) covers decoding in full; the
[settings program](../../examples/json_settings.lin) and the
[HTTP echo server](../../examples/http-json-echo/main.lin) decode their input.

Walk a `json.Value` instead when the shape is not fixed, or when a program
edits a document and writes it back with members it never reads.
`parse(input)` accepts borrowed `Str` and allocates from the system allocator, and
`parse_in(allocator, input)` from the one given; `parse_bytes` and `parse_bytes_in` accept borrowed
`mem.Slice[UInt8]` and validates UTF-8. Both return an owned `Value` that depends
on its allocator, not the source bytes. Release it explicitly. An arena must
remain alive until every value allocated through its handle has finished.
`json.read_file(path)`, or `json.read_file_in(allocator, path)`, reads a file,
parses its bytes as `parse_bytes` does and releases them, so the document never
borrows them. The read stops at the parse limits' `max_input_bytes`, so the
reader and the parser agree on how large a document may be. Its
`ParseFileError` is `Read` with the `fs.ReadFileReason`, or `Parse` with the
`ParseError`, so a caller reports which step failed; bytes that are not UTF-8
are a `Parse` error of kind `InvalidUtf8`. The [inventory program](../../examples/json_inventory.lin)
loads its file this way, calculates a total, attaches it as a summary member
and writes the whole document back, members it never read included.

```sh
linea run examples/json_inventory.lin
linea run examples/json_inventory.lin -- inventory.json
```

## Inspect and construct

`Value.null`, `boolean`, `array` and `object` need no allocation. `string` copies
borrowed text. `number` validates and copies a complete number token; `from_int`
and `from_uint` construct exact decimal integers. All take an explicit allocator.

`kind` identifies a value and `as_bool` returns an independent Boolean snapshot.
`as_str`, `number_text`, `elements`, `members`, `get` and `at` return optional
observations. Literal object names need
no owned string. Observations keep their document live and prevent mutation
while they remain in use. Child access is read-only.

`as_int64` and `as_uint64` report `WrongKind`, `NotInteger` or `OutOfRange`.
Fraction and exponent spellings are not integer access, even `1.0` and `1e0`.
Unsigned access refuses a leading minus, including `-0`. Original tokens such
as `1.00`, `1e400` and integers beyond machine range survive writing unchanged.
`as_float64` rounds to the nearest binary64 value with ties to even, preserves
signed zero and admits subnormals. Overflow and nonzero underflow to zero return
`OutOfRange`; conversion never changes the stored token.

## Mutate and settle

`&array.append(child)` and `&object.insert(key, child)` consume the
incoming value on success. Failure returns a `MutationFailure` containing its
reason and complete incoming value; reuse that value, or release it and keep
the reason with `settled()`, as in
`let previous = &document.insert("summary", summary).settled()?`. Refusal
leaves the destination unchanged. Insertion returns the replaced value, if any,
for the caller to settle. Replacing an existing key requires no allocation.

`remove_element` preserves array order. `remove_member` accepts borrowed text.
Both return the removed owner, or `None` for an absent index/name, and report
`WrongKind` for an incompatible receiver. They require no allocation.

Every value has a checked height: scalars have height zero and containers add
one to the maximum child height. Mutation refuses a tree exceeding 128 nested
containers. Object insertion refuses more than 4,096 members. Removal and
replacement recompute height over remaining siblings; object scans visit
retained map buckets. Release traverses children without allocating.

## Input limits and errors

Write the limits a specific input policy changes and take the rest from
`json.ParseLimits.default()`:

```linea
let limits = json.ParseLimits { max_input_bytes = 65536, max_nodes = 1000, ..json.ParseLimits.default() }
let document = json.parse_in(allocator, input, limits: limits)?
```

| Limit | Default | Meaning |
| --- | ---: | --- |
| `max_input_bytes` | 8,388,608 | Complete encoded input |
| `max_depth` | 128 | Nested containers; scalar roots need zero |
| `max_nodes` | 100,000 | Values, including containers |
| `max_string_bytes` | 1,048,576 | Decoded bytes in each key or string |
| `max_number_bytes` | 1,024 | Bytes in each original number token |
| `max_object_members` | 4,096 | Members in each object |

Zero is a restriction. `max_depth`, `max_number_bytes` and `max_object_members`
are refined types, `json.MaxDepth` (0 to 128), `json.MaxNumberBytes` (0 to
65,536) and `json.MaxMembers` (0 to 4,096), so a limit past what the parser
supports is refused where it is written: `max_depth = json.MaxDepth(64)`
compiles and `json.MaxDepth(500)` does not. Checks run in this order: input
extent, UTF-8, grammar and traversal limits. Errors contain a copyable
kind and absolute byte offset; EOF is input length. Errors outlive input.
Display writes an error as its problem and offset, such as
`invalid syntax at byte 7`.

The parser refuses duplicate decoded keys at the second opening quote, before
reading that member's value. It also refuses comments, trailing commas, trailing
content, a leading BOM, nonfinite numbers and invalid Unicode surrogates.
The deterministic map hash is not collision-resistant; bounds limit admitted
work but do not make hostile object lookup constant-time.

## Write

`json.write(&writer, document)` emits compact JSON through any `Writer`,
preserves the writer's exact error, and neither closes nor flushes it. A failed
write may leave a prefix in the destination. The document remains usable.
Object member order is unspecified; array order and numeric token spelling
are preserved.

`json.render(document)`, or `json.render_in(allocator, document)`, returns independently owned UTF-8 text and
releases partial output on allocation failure. The allocator may differ from
the document's allocator. JSON string escaping is shared with writer output.

## Typed values

`json.encode(&writer, value)` handles Boolean values, every integer width,
Float64, borrowed and owned text, Option, Vec and text-keyed Map values.
`None` encodes as `null`; `Some(value)` encodes its value. Nested Options are
not reversible: both `None` and `Some(None)` encode as `null`.

Floating output refuses NaN and infinity. `EncodeError` preserves the writer's
error in `Writer(error)` and reports `NonFiniteNumber`, `DepthLimit` or
`InvalidState` for encoding failures. `From[E] for EncodeError[E]` wraps a
writer's error, so a function returning `EncodeError[W.Error]` propagates a
direct write with `?`. Output may contain a prefix on failure; the encoder
neither flushes nor closes the writer.

`json.decode(input)`, or `json.decode_in(allocator, input)`, parses a temporary document and constructs an
owning result selected by its expected type:

```linea
let names: Vec[String[mem.SystemAllocator], mem.SystemAllocator] = json.decode(r#"["tea","coffee"]"#).unwrap()
defer names.release()
```

The annotation supplies the schema through `unwrap`, whose result is the
success of the Result `decode` returns; `?`, `else` and a function's return
type supply it the same way. The same
`limits:` override used by `parse` applies to `decode`. Use
`json.from_value(document)`, or `json.from_value_in(allocator, document)`, to
decode an existing document; the allocator and document must use the same
allocator type. Neither successful
values nor decoding errors borrow the document or input. They retain
the supplied allocator's ownership dependencies. There is no owning Decode
implementation for borrowed `Str`.

`json.decode_file(path)`, or `json.decode_file_in(allocator, path)`, does the
same for a typed value: it reads the file, decodes it and releases the bytes. Its
`DecodeFileError` is `Read` with the `fs.ReadFileReason`, or `Decode` with the
`DecodeError`, which keeps the release obligation of a decode error, so a
failing call is settled with `error.release()`.

The temporary document and partially built target coexist during decoding.
This API pays for both representations; release and allocation refusal settle
the temporary document on every outcome. Integer decoding requires an integer
token and the target width's range. Float64 decoding uses `as_float64`.

## Record and custom codecs

Struct-derived Encode emits field names in declaration order. Struct-derived
`Decode[A]` requires an object, decodes each field and refuses unknown fields.
An absent Option field becomes None; other built-in targets report MissingField.
Explicit `null` also becomes None for an Option. Newtypes and enums require
handwritten codecs that choose their JSON representation. See the complete
[settings program](../../examples/json_settings.lin).

```sh
linea run examples/json_settings.lin
linea run examples/json_settings.lin -- settings.json
```

For a handwritten record decoder, `ObjectDecoder.open(document)`, or
`ObjectDecoder.open_in(allocator, document)`,
borrows the object and owns its used-name tracking. Settle it with Release.
Its field helpers accept borrowed names and return independently owned results:

- `field` uses the target's `Decode.missing` policy for absence.
- `required` rejects absence even when the target is an Option.
- `optional` returns None for absence and decodes a present value normally.
- `finish` rejects every field the decoder did not read.

Place a `defer field.release()` after acquiring each owning field. Returning
the completed record moves those fields and cancels their deferred release;
an early error releases the completed prefix. Defaults and domain validation
belong in the handwritten decoder or a separate validation function.

Custom Encode implementations use Encoder's scalar and container operations.
Call `&encoder.value(&writer, child)` for each nested custom value;
it verifies that the child emits exactly one value, balances its containers,
and leaves its caller's container open. A failed child poisons the encoder even
when an outer codec catches its error. Object keys must be followed by values.
Container depth is bounded at 128.

Map encoding requires `EncodeKey.name` to return borrowed text and give unequal
keys distinct member names. Str and String supply it. The streaming encoder
does not retain names to detect duplicates; custom object encoders must also
write distinct names. Map decoding requires `DecodeKey[A].from_name` to construct
an owning key; String supplies it. If distinct member names decode to equal keys, decoding
reports DuplicateKey and settles both entries.

## Typed error paths

`DecodeError[A]` separates `Parse(ParseError)`, `Value(DecodeFailure[A])` and
`Allocation`. Parse errors retain byte offsets. Value errors expose `reason`,
`path_length` and root-first `segment(index)` observations; each segment is an
owned field name or an array index. Debug output reads, for example,
`WrongKind at $["ports"][1]`, and Display output reads
`wrong kind of value at $["ports"][1]`, so the error can be logged as a field
or sent back as a message. A `Parse` error displays as the parse error does.
Typed errors do not invent source offsets.

Custom validation can create `DecodeError.failure_in(allocator, .InvalidValue)`
and add context with consuming `at_field_in(allocator, name)` or `at_index`. The error owns its
path and survives release of input and document. If allocating that path fails,
its partial storage is released and the result is Allocation. Release the final
error after inspecting or formatting it.
