# 184. A failure holding an owned value settles to its reason

Status: Accepted — 2026-09-26. Extends
[0104](0104-release-is-optional-and-never-scheduled.md) and
[0162](0162-question-mark-converts-an-error-through-from.md). Its clause that
`http.Error` converts each owning failure by settling it is superseded by
[0218](0218-the-library-gives-up-no-value-at-question-mark.md).

## Context

An operation that consumes a value and then fails hands the value back inside
its failure, so an affine or linear value is never lost to a refusal:
`Vec.push` returns `PushFailure { reason, value }`, `Map.insert` returns the key
and value in `InsertFailure`, `json.Value.insert` returns the member in
`MutationFailure`, `String.from_bytes` returns the bytes in `Utf8Failure`, and
`fs.read_file` returns the bytes it read in `ReadFileFailure`. The design is
right and the call sites paid for it. Two developer-experience reviews named
the release of a refused payload as the largest ceremony left in ordinary
programs. Propagating a push refusal took seven lines:

```linea
match &rules.push(rule) {
    Ok(_) => .Ok({}),
    Err(failure) => {
        let PushFailure { reason, value } = failure
        value.release()
        return .Err(reason)
    },
}
```

and a file read that fed `?` took a closure that copied two fields out, released
the failure and rebuilt the error. `?` could not help: it converts an error
through `From` ([0162](0162-question-mark-converts-an-error-through-from.md)),
and a `From[PushFailure[T]]` implementation must either release the value
itself, which `http.Error` did as a one-off, or keep it in the converted error,
where nobody wants it.

`Release` ([0104](0104-release-is-optional-and-never-scheduled.md)) consumes a
value and returns nothing. It settles the whole failure, reason included, so
it answers "drop this" but not "drop the value and tell me why".

## Decision

**`std.release` declares `trait Settle: Release { type Reason; fn settle(sink
self: Self) -> Self.Reason where carries(self) }`.** `settle` releases the owned
part of a failure and returns the reason. Every standard-library failure that
holds an owned value implements it, with `Release` beside it:

| Failure | Reason |
| --- | --- |
| `mem.PushFailure[T]` | `mem.Oom` |
| `collections.InsertFailure[K, V]` | `mem.Oom` |
| `collections.UpsertFailure[K, V, E]` | `collections.UpsertReason[E]` |
| `json.MutationFailure[A]` | `json.MutationReason` |
| `text.Utf8Failure[A]` | `text.Utf8Error` |
| `io.BufferOpenFailure[R]` | `io.BufferOpenReason[R.CloseError]` |
| `io.FinishFailure[W, A, E]` | `io.FinishReason[E, W.CloseError]` |
| `io.ReadAllFailure[A, E]` | `io.ReadAllError[E]` |
| `iter.CollectFailure[I, A, T]` | `mem.Oom` |
| `fs.ReadFileFailure[A]` | `fs.ReadFileReason` |

**`Result[T, E]` gains `settled(sink self) -> Result[T, E.Reason]` where `E:
Settle`.** A success passes through; a failure is settled. `?` then converts the
reason through `From` like any other error, so the push above is
`&rules.push(rule).settled()?`, and editing a document is
`let previous = &document.insert("summary", summary).settled()?`.

**`Release` stays "consume and return nothing".** A discarded result must never
hide information, so there is no reason-returning release. `Release` may
therefore drop a failed close; `Settle` may not. Where releasing the owned part
can itself fail, the reason carries both failures:

- `ReadFileFailure` is `{ partial, reason: ReadFileReason }`, and
  `ReadFileReason { primary, close }` keeps a failed close beside the read
  error.
- A failure that holds a stream settles by closing it through a new
  `io.Close` trait, `trait Close: Release { type CloseError: Discardable; fn
  close(sink self) -> Result[(), Self.CloseError] }`. `BufferOpenFailure[R:
  Close]` settles to `BufferOpenReason { reason, close: Option[R.CloseError] }`
  and `FinishFailure[W: Close, …]` to `FinishReason { write, close }`.

`io.Close` is implemented by `File`, `Connection` and `Listener`, and by
`Descriptor` with `CloseError = Never`, since a descriptor wrapper owns nothing
to close. Each of the three keeps its own `close` operation, which a postfix
call reaches without an import, and its `io.Close` member only calls that
operation; such a forwarding member draws no [N-Shadowed], because both run the
same code. `net.Acceptor` refines `io.Close` and no longer declares `close` of
its own, so `http.serve` closes its listener with `io.Close.close` and converts
the close error with `L.CloseError: Into[io.IoError]`. The close error is `Discardable` because
`Release` drops it. `Never` gained `Display` and `Debug`, so a reason whose
close error cannot occur still renders.

**`Settle` is not in the prelude.** [0179](0179-the-prelude-holds-the-core-vocabulary-and-yields-to-a-module.md)
admits a name most programs write in signatures and bounds. The idiom is
`.settled()`, an inherent operation of `Result` that needs no name in scope;
the trait is written only where a failure type is declared, which is the
library and the occasional program. A prelude trait is also a visible trait
everywhere, so its operation would join postfix lookup in every module, and
`settle` is an ordinary domain verb — a payment or an invoice is settled — that
a program trait would then make [N-Ambiguous]. A program implements it as
`release.Settle` after `import std.release`.

**`http.Error` converts each owning failure a handler meets by settling it.**
`From[mem.PushFailure[T]]`, `From[collections.InsertFailure[K, V]]`,
`From[collections.UpsertFailure[K, V, E]]` and
`From[json.MutationFailure[A]]` each have the body
`release.Settle.settle(source).into()`: the release goes through `Settle`, no
conversion releases anything itself, and the reason converts through the
conversion that answers it (`From[mem.Oom]`, and the new
`From[collections.UpsertReason[E]]` and `From[json.MutationReason]`). A handler
writes `&items.push(item)?` and `&map.insert(key, value)?`. These are per-failure
conversions because the one generic conversion is refused (see Alternatives
considered); they are the chosen shape until coherence can read `where`
bounds, which is a separate future design. Every match that released a
refused payload in `std/`, `examples/`, `tests/` and the documentation to keep
only its reason now calls `settled()`.

## Consequences

The ceremony is gone where it was ceremony. A push, insert, conversion or read
that propagates its refusal is one line, and `?` does the conversion the
function already declares. The config editor lost three closures and the
inventory example its two insertion matches.

One rule decides the form at every site. Code that goes on with the reason —
propagating it with `?`, printing it, or mapping it with `map_err` — calls
`settled()`. A match arm that drops the failure whole, reason included, calls
`failure.release()`, which says exactly that. Sites that still destructure use
the value: a test that inspects it, an internal function that moves it into a
failure of its own (as `json.Value.insert` does with a map's
`InsertFailure`), and a server that answers on the connection a refused buffer
returned.

Closing a file, connection or listener needs no import: `file.close()` reaches
the type's own operation. Only generic code names `io.Close`.

`iter.Collected` names its element type as a third parameter,
`Collected[I, A, T]`, instead of reading it as `I.Item`. A projection is an
opaque structural step in [T-PolyRec]'s measure, so releasing a
`Vec[I.Item, A]` from an implementation generic over `I` was refused as
polymorphic recursion. `collect` returns `Collected[I, A, I.Item]`, so no call
site changed.

`Result.settled` declares `carries(.Ok: self), carries(.Err: self)`, as
`map_err` does: a contract source names a parameter or a field, never a
variant, so the reason is assumed to carry whatever the whole result carried.
A non-generic reason in the table holds nothing that could carry a dependency,
so the difference is invisible there; a generic reason, such as
`ReadAllError[E]`, is conservatively taken to carry what the whole result did.

`json.MutationReason` gained the `Display` it lacked, so a settled mutation
reason can reach `main`; it reads as the problem, like `ParseError`.

## Alternatives considered

**A reason-returning `Release`.** Making `release` return the failure's reason
would reuse one name. Rejected: `Release` is called for its effect and its
result discarded everywhere, so a reason returned there would be dropped
silently at exactly the sites that ignore it.

**`From` implementations that release.** A conversion whose body destructures
the failure and releases the value re-implements the release in every
destination error, and its signature says nothing about the value it
discards. The conversions `http.Error` keeps call `Settle.settle` instead, so
the one teardown each failure defines is the one that runs.

**A `settled` per failure type.** `failure.settled()` on each failure would
work without a trait, but `?` needs the call on the `Result`, and a generic
`Result` method needs a bound to name. The trait is that bound.

**A blanket `From[F: Settle] for http.Error[P]`.** A handler could then write
`&items.push(item)?` and have the conversion settle the failure before
converting its reason: `impl[P: Allocator, F: release.Settle] From[F] for
Error[P] where F.Reason: Into[Error[P]]`. The language refuses it. Coherence
decides overlap from the implementation heads alone, and `From[F]` unifies with
each of `http.Error`'s other conversions, so every one is [T-Impl]: "these two
both answer `From[IoError]` for `http.Error[P]`", and likewise for
`WriteFailure[IoError]`, `Oom`, `Utf8Error`, `ParseError`, `DecodeError[A]`,
`EncodeError[Oom]`, `HeaderError` and `RequestError`. The body's
`Into.into(Settle.settle(source))` is also [T-PolyRec]. The per-failure
conversions in the decision are what compiles; one generic conversion needs
coherence that reads `where` bounds, so that `F: Settle` excludes the concrete
heads that do not implement `Settle`, which is a separate design.

**Settle without `Release` as its supertrait.** A failure could settle without
being releasable. Rejected: a program that wants neither the value nor the
reason should still have the one-call `release()`, and requiring both keeps
the two operations side by side on every failure.

## Open questions

**A contract source that names a variant.** `settled` declares
`carries(.Err: self)`, so a reason is taken to carry whatever the whole result
carried. For a generic reason instantiated with a view, a probe of the review
showed [O-Escapes] and [O-Borrow] where only the success side borrowed a local.
Writing the settlement out as a `match` with `Settle.settle` is accepted. The
fix is a contract source that names a variant, `carries(.Err: self.Err)`, which
`map_err` needs as well. No standard-library reason is generic over a view, so
nothing depends on it yet.
