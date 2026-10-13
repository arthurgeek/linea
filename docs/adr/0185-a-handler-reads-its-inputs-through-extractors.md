# 185. A handler reads its inputs through extractors

Status: Accepted — 2026-09-27. Extends
[0154](0154-sockets-and-http-follow-go.md) and
[0180](0180-state-is-lent-down-through-every-handler.md).
Refined by [0214](0214-a-route-takes-a-function-whose-parameters-name-its-inputs.md):
the signature extractors that *Alternatives considered* declined are how
`route` registers a handler, and `request.extract[T]()` remains the explicit
form for a handler that owns what it reads or acts on a refusal.

## Context

A handler reads a few typed inputs from its request: a number from the path,
a page from the query, a JSON body, who is calling. Before this record each
was spelled by hand. A path value was `request.path_value("year")?.parse()`
followed by a refusal the handler wrote itself, and a JSON body took a dozen
lines: read the text, decode it, tell running out of memory from the
client's mistake, render the decode error into a 400, release it. Each
example wrote those lines again, and each wrote its own message for the same
failure.

axum answers this with extractors: a type that knows how to read itself out
of a request and how to refuse it. axum names them in the handler's
signature and calls them before the handler runs. Linea's handler has one
shape, `fn(inout state: S, request: Request[P])`
([0180](0180-state-is-lent-down-through-every-handler.md)), and a router
registers any function of that shape, so the inputs are read in the body, by
name, one line each.

## Decision

**`http.Extract[P]` is a type a handler reads out of a request.**

```linea
pub trait Extract[P: mem.Allocator] {
    fn extract(request: Request[P]) -> Result[Self, Error[P]] where carries(request)
}
```

`request.extract[T]()` calls it, naming `T` in brackets
([0181](0181-a-call-may-name-its-type-arguments.md)), and `?` answers the
request with the refusal. The value may view the request, which lives until
the response is written. Any type becomes an extractor by implementing
`Extract` for every `P`.

**An extractor hands over what it read.** A second trait says what the
handler receives:

```linea
pub trait Extracted {
    type Output
    fn output(sink self: Self) -> Output where carries(self)
}
default impl[T] Extracted for T { type Output = T ... }
```

`request.extract[T: Extract[P] + Extracted]()` returns `T.Output`. A custom
extractor such as `Caller` takes the identity default and writes nothing
more; `Path[T]`, `Query[T]` and `Json[T]` are wrappers that implement
`Extracted` with `Output = T`, so `request.extract[http.Json[Order]]()?` is an
`Order`. The projection is a trait of its own because `Extract` must return
`Self`: a call settles an implementation's `Self` from its arguments or its
expected result, and `Extract.extract` has no argument of type `Self`.

**`http.Path[T]`, `http.Query[T]` and `http.Json[T]` are the built-in
extractors.** The statuses are fixed by who made the mistake:

- `Path`: a value its field cannot be read from is 400, naming the value, the
  text and the parse error. A field the route has no `{name}` for, or a
  single value read from a route with several, is the program's mistake and
  500.
- `Query`: a query that is not percent-encoded UTF-8, a missing value, a
  value named more than once and an unreadable value are 400.
- `Json`: a body not sent as `application/json` or an `application/*+json`
  type is 415; the rest is decided by `decode_status`, which `?` on a
  `json.DecodeError` uses too: a body that is not JSON (or not UTF-8) is 400,
  a document that does not decode into `T` is 422, with the decode error
  naming the problem and where it is, and an arena too small for the value is
  500. `Status` names 415 and 422.

**A struct is filled by field name through a derivable trait.**
`derive(http.Params)` makes a struct an `http.Params`, whose
`from_params(values)` reads each field from the value of its own name. The
template is ordinary library source: one `reflect.construct` over the
struct's fields, each field read through `values.field(component.name)?`.
A field's type is an `http.ParamValue`:

- every `text.Parse` type, through one `default impl[T: text.Parse]`, read by
  parsing its value, and required;
- `Str`, the value as sent, borrowed from the request;
- `Option[T]` of one, `None` when the request does not name it.

A value named twice is refused rather than resolved to either, since which
one the client meant is ambiguous. `ParamValues.get` answers this, and every
by-name reading, `field` and the template included, goes through it, so a
hand-written `Params` cannot take the first of a repeated name. A
hand-written `Params` refuses a value for its own reason, such as a range
that ends before it starts, with `ParamProblem.Refused(reason)`, which
`Path` and `Query` answer with 400.

**`Path` also reads a single value; `Query` does not.** `Path[T]` reads an
`http.FromPath`: every `Params`, through a `default impl`, and each type `std`
reads one text value as -- the integer types, `Float64` and `Str` -- through
`values.only()`, which reads the only value a route has. A program's own
`ParamValue` becomes one with a short `impl` whose `from_path` returns
`values.only()`. A query's values all have
names, so `Query[T]` reads only a `Params`; a single value there would read a
pair whatever its name.

**The by-name reading is public.** `request.path_params()` and
`request.query_params()` return the `http.ParamValues` that `Path` and
`Query` read, and `values.field[T](name)` reads one value as the template
does. A program implements `Params` by hand, with a query name that differs
from its field's or a check across fields, or builds an extractor of its own
on the path or the query.

**A body read by name is `http.Form[T]`.** Reading an HTML form's body into a
`Params` needs its decoded names and values in storage the request owns, for
the same reason the query does: a `Str` field borrows what it reads, and
nothing a program allocates in `extract` outlives it. A program cannot
construct `http.ParamValues` itself, its fields sealed by `opaque`, so an
extractor of its own cannot build one from the body; `request.form_params()`,
returning the same type `path_params()` and `query_params()` do, is what
`std` adds. `Form[T]` reads a `T` from it exactly as `Query[T]` reads one from
the query: a struct deriving `http.Params`, filled by field name, with the
same `Missing`, `Repeated` and `Invalid` refusals. A body sent as anything
but `application/x-www-form-urlencoded` answers 415, checked against
`Content-Type` the same way `Json` checks it; one that is not
percent-encoded UTF-8 answers 400, as a query that is not is read by `Query`;
and a value missing, named twice, or unreadable as its field's type answers
400, naming the value, as the query's does.

**A request decodes its query, and a form body, when it is read.** `+`
becomes a space and `%XX` its byte, as an HTML form encodes both, and the
decoded names and values are stored in the request's own storage through one
routine, `decode_encoded_pairs`, so a query and a form body are read the same
way and cannot drift. A `Str` field can then borrow a decoded value from the
request. The decoded text is appended in place by the routine that decodes
path values, and it and the pair table are each reserved once at their final
size, since decoding never lengthens text and the pairs are counted first.
`Limits.max_query_pairs` and `Limits.max_form_pairs`, 100 by default as
`max_headers` is, bound the pairs: a query holding more is refused with 414
URI Too Long, and a form body with more with 413 Content Too Large, as a body
past `max_body_bytes` is, when the request is read, as the other read limits
refuse, and before anything is decoded. `smallest_arena` counts one line of
text and `max_query_pairs` ranges for the query, and a form's body again at
its length and `max_form_pairs` ranges, so a route never answers 500 for
either it does not read. A body is decoded as a form only when
`Content-Type` names one, checked once when the request is read, so a body of
another type is never scanned as pairs; a query or a form body that is not
percent-encoded UTF-8 is recorded as such rather than refused, since a
handler that never reads it should not fail. `Query` and `Form` each refuse
what their own body was not.

**`request.path_as[T](name)` is not added.** `Path[T]` is the one-value
form, and a named single value is `request.path_value(name)` followed by
`parse`, or a one-field struct. A third spelling would be a second parse path
with its own refusal message.

**An `http.Error` can carry headers.** `error.set_header(request, name, value)`
stores a header in the request's arena and the server writes it with the
error's status. A 401 must name the scheme its client should authenticate
with in `WWW-Authenticate`, and an extractor answers only with an `Error`.
`Message.add_header` gives a test request its headers, so a test can send a
body as JSON or name its caller.

**The examples show a custom extractor.** `Caller` in the JSON echo server
reads `Authorization: Bearer <name>`, compared without regard to case, and
refuses a request without one with 401 and `WWW-Authenticate: Bearer`. The
standard header teaches the standard answer, including the challenge; a
real service would check a token where the example trusts a name. The same
server adds `POST /signup`, reading `http.Form[Signup]` from a real HTML
form post, so a built-in extractor is exercised the way a browser sends one,
not only through a test request.

## Alternatives considered

**Extractors named in the handler's signature, as axum does.** A handler
would declare `fn echo(inout app: App, caller: Caller, message: Json[Message])`
and the router would read each parameter before calling it. A spike
built it: with one language addition, a
structural callable type as a trait implementation's head, one `Endpoint`
implementation per arity routes handlers of one to three extractors, reads them
in parameter order, answers the first refusal and releases what it had already
read, with output identical to the explicit form. Overlap between arities is
already decided by 0093's unification. It was not adopted, for four costs the
spike measured:

- A handler still takes the request, because every `Response` and `Error` is
  allocated in the request's arena, and its body reads `order.value` rather
  than an `Order`, because the parameter's type is the extractor.
- A handler taking a view-holding extractor, such as `Caller` or a `Str`
  field, must write `where carries(request)`, and the implementation head must
  name that contract exactly, since it is part of the callable type.
- The per-arity implementation cannot be inferred from a bound: a marker type
  argument, as axum's `Handler<T, S>` uses, is settled only when the call
  names every type argument, because Linea settles a key from arguments and
  results and never searches implementations (0081, 0148). A generic handler
  is registered as `create[P]`, which 0181 makes a value.
- A closure never matches a callable head, and the parameter-headed
  implementation that would carry closures overlaps every callable head,
  because 0148 does not treat a callable bound as structure. `route` would
  need a second method for extractor signatures, or coherence would have to
  learn that disjointness.

With those in place, a signature extractor is a second spelling of what one
`request.extract[T]()?` per input already says, the reason `path_as` was
refused; it would move refusals out of the body and remove the single handler
shape 0180 builds on. The explicit form costs one line per input.

**A wrapper the handler unwraps, `request.extract[Json[T]]()?.value`.** It
needs no second trait, but every built-in extractor then costs a field access
at every call, and a wrapper holding an owned value must be taken apart
rather than projected, since a field cannot be moved out of a value alone.

**An associated `Output` on `Extract` itself.** A call through a type
parameter, `T.extract(request)`, does not select an implementation, and
`Extract.extract(request)` cannot settle `Self` from an expected
`Result[T.Output, …]`, so the projection needs a trait whose method takes
`Self`.

**`Query[UInt64]` reading the only pair.** It reads `?x=5` and `?y=5` alike,
and two pairs are an error about a count rather than a name.

**The first of a repeated query value wins.** It is what a lookup returns,
but a client and a server that disagree about which value counts is a known
way to slip one value past a check made on the other.

**Reflection over a struct's fields without a trait.** Structural reflection
exists only inside a `template impl`, which is exactly a derivable trait; a
derive also states in the source which structs are read from a request, and a
field type that cannot be read is refused at the derive, naming the field.

**Parse types as fields directly, `reflect.components: text.Parse`.** `Parse`
returns a value that borrows nothing, so a text field would be impossible, and
an optional field would need a separate rule. `ParamValue` adds both, and
its default implementation makes every `Parse` type one without a line of
code; a blanket `impl[T: Parse]` beside `impl ParamValue for Str` would
overlap, because an open bound does not prove two heads disjoint.

**Decoding the query when `Query` is extracted.** The decoded text would have
to live somewhere that outlives the extraction for a `Str` field to borrow
it, and nothing in the request's arena outlives the function that allocates
it except what the request itself owns.

**Decoding a form body when `Form` is extracted, as `Json` decodes its
body.** A body's `Content-Type` is already known once the request is read,
so nothing waits on the handler for it, and `Form`'s own pair-count limit
would then answer per route rather than refusing the whole request with 413
before a route is chosen, unlike the query's 414. Deciding it once also
means one call to `decode_encoded_pairs`, not one per extraction of a body a
handler might read more than once.

**`X-Caller` for the example's caller.** It is shorter, but a 401 is defined
by an authentication scheme and its challenge, and a made-up header has
neither.

## Consequences

- A handler's inputs read one per line, and a refusal's status and message
  are the library's, the same in every program.
- A test request sent as JSON needs `Content-Type: application/json`, as a
  real client's does; curl's `--data` sends a form and is answered 415.
- A signup form example sends its body as
  `application/x-www-form-urlencoded`, curl's default for `--data`, and
  `Form[Signup]` reads its fields by name.
- A handler that wants to log a refusal reads the input with
  `else |error| { ...; return .Err(error) }` instead of `?`.
- Every request pays for decoding its query and, when `Content-Type` names
  one, its body as a form, each linear in what it decodes and allocated
  twice at most.
- A `Params` struct borrowing `Str` fields is not copyable by default; a
  handler takes it apart with a pattern, as it does any struct whose parts it
  moves.
- The smallest arena grows by one line and a table of `max_query_pairs`
  ranges for the query, about 11 KiB under the standard limits, and by
  `max_body_bytes` again and a table of `max_form_pairs` ranges for a form
  body, about 1 MiB more since a body can be far longer than a line; the
  default arena grows from 5 to 6 MiB to hold it. A table sized by the line
  or the body instead, one pair for every two bytes, would be far larger
  still.
- A client that sends more than `max_query_pairs` pairs is refused with 414
  even by a route that never reads the query, as it is for too many headers,
  and one that sends a form body of more than `max_form_pairs` pairs is
  refused with 413 the same way.
