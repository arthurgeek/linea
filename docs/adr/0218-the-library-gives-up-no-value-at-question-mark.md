# 218. The library gives up no value at `?`; `.settled()` says so

Status: Accepted — 2026-10-08. Extends
[0162](0162-question-mark-converts-an-error-through-from.md) and
[0184](0184-a-failure-holding-an-owned-value-settles-to-its-reason.md);
supersedes the clause of 0184 that `http.Error` converts each owning failure
by settling it.

## Context

[0184](0184-a-failure-holding-an-owned-value-settles-to-its-reason.md) gave
every failure that holds an owned value a `Settle` implementation and left one
way to use it in a function: write `.settled()` before `?`. A census of the
call sites found 82 lines naming `settled()`. Of the 27 that are `.settled()?`, the
largest groups were a refused `push`, `insert` or `collect` in a function that
returns `mem.Oom`, and a file read followed by `String.from_bytes`.

[0184](0184-a-failure-holding-an-owned-value-settles-to-its-reason.md) also
made `http.Error` convert a refused push, insertion, upsert or document change
by settling it (`source.settle().into()`), so a handler could write
`&items.push(item)?` and the item was released at the `?`. The same conversion
could be written for `mem.Oom`, `HeaderError`, `RouteError` and
`json.DecodeError`, which would remove about twenty written `settled()` calls.

Such a conversion is a bad trade. A `From` implementation generic over the
refused value releases whatever that value is, and `Release` may do I/O: with
`T: Release`, `&files.push(file)?` closes a file and nothing at the call says
so. Bounding the conversion to values whose disposal runs nothing removes the
I/O but not the hidden decision: the value is still dropped at a `?` that never
mentions it, and the same line starts to mean a different thing when the
element type changes.

## Decision

**The standard library declares no `From` that drops a value a failure hands
back, and `?` calls only the `From` implementations that are declared.** So
giving up an owned value through `?` happens only in a conversion a program
wrote, and the library's way for a caller to say it is `.settled()` before the
`?`:

```linea
&names.push(name).settled()?
```

The written `settled()` is the decision to drop the value, and it is the one
place a reader looks to see cleanup happen. Library conversions read what a
failure *says* (its reason); they do not decide what happens to what a failure
*holds*. A conversion may release the error's own contents, such as the path a
`json.DecodeError` owns, because that error hands no caller value back.

The library therefore declares no `From[PushFailure[T]]`,
`From[InsertFailure[K, V]]`, `From[CollectFailure[I, A, T]]`,
`From[UpsertFailure[K, V, E]]` or `From[MutationFailure[A]]` for `mem.Oom`,
`http.Error`, `http.HeaderError`, `http.RouteError` or `json.DecodeError`. The
`http.Error` conversions of 0184 that settled a refused push, insertion, upsert
or document change are not declared, and their handlers write
`.settled()?`. Conversions that read a *reason* (`From[UpsertReason[E]]`,
`From[MutationReason]`, `From[mem.Oom]`) remain: they hold no value to drop.

**A `?` that converts its error returns it with the dependencies its target can
hold.** `From.from` declares `where carries(source)`, so the converted error
carries the dependencies of the error it was built from. The ownership
analysis drops them when the converted type can carry none (`mem.Oom`, a
payload-free enum), so a `From` the program writes, which releases a
`CollectFailure` that borrows an arena into a payload-free enum, is accepted
under `?` as it is under a written `From.from(error)`.

**Composites own an intermediate failure.** `fs.read_text(path, max_bytes)`
reads a file and decodes it as UTF-8; `io.read_text(&reader, max_bytes)` does
the same for a reader. Each uses the system allocator, and `read_text_in`
takes the allocator first, mirroring `new` and `new_in`. Each settles the
failure of its first step and the failure of its second inside the function, so
the caller sees a precise error that owns nothing: `fs.ReadTextError` is
`Read(ReadFileReason)` or `Encoding(Utf8Error)`, and `io.ReadTextError[E]` is
`Read(ReadAllError[E])` or `Encoding(Utf8Error)`. Settling there is the
library's own written decision about bytes it allocated. A composite is added
where two calls are one operation a reader would name, not wherever
`settled()` appears. `read_file` and `String.from_bytes` remain for a program
that wants the bytes.

## Consequences

- Every refused `push`, `insert` and `collect` in a function that returns an
  error type other than the failure itself writes `.settled()?`, including
  handlers that returned `http.Error` under 0184.
- `config_editor`, `frequency_report`, `json_settings` and `server_settings`
  lose a read-then-decode pair each. `config_editor` reports invalid UTF-8 on
  either path through `ReadTextError`'s `Display`; `json_settings` maps each
  `ReadTextError` case to its own message.
- The diagnostic for a `?` over a failure that has no `From` conversion points
  at `.settled()` when settling would produce a reason the function's error
  type converts from.
- This supersedes the part of 0184 that has `http.Error` settle a refused push,
  insertion, upsert or document change.

## Alternatives considered

**Concrete conversions for `mem.Oom` and the error types that wrap it.**
`impl[T: Release] From[PushFailure[T]] for Oom` and its siblings, with the body
`source.settle()`. Rejected: they release any `T: Release`, so `&files.push(file)?`
closes a file with nothing at the call to say so, which breaks "cleanup runs
only where it is written".

**The same conversions bounded by `T: Discardable`.** Disposal of a
discardable value runs nothing, so no I/O is hidden. Rejected: `?` still drops
a value the source never mentions, the element type decides whether a line
compiles, and the next reader cannot tell a dropped `UInt64` from a dropped
handle without reading the element type. One rule, with no bound to check, is
simpler to teach: `?` never drops a value for you.

**A blanket `From` from any `Settle` failure.**
`impl[F: Settle, E: From[F.Reason]] From[F] for E` would remove every written
`settled()?`. Rejected for two reasons. It is the form
[0184](0184-a-failure-holding-an-owned-value-settles-to-its-reason.md) already
found the language refuses: coherence decides overlap from heads alone, so
`From[F]` collides with every other `From[X]` for the same target, and the body
is [T-PolyRec]. And it would make cleanup implicit for every error type in a
program, including `BufferOpenFailure` closing a connection.

**An opt-in derive on the error type.** Writing `SettledFrom[F]` beside
`From[F]` would let the error's author declare the cleanup in one place.
Rejected: the closed derive grammar names no partial application, so a failure
generic over `T` or `A` needs one entry per instantiation, each longer than the
`.settled()` it replaces; it cannot target `mem.Oom`; and the release would
still hide at the `?` site.

**A settling `read_file`.** Making `read_file` return the reason only would
remove the pair at its call sites, but it would take the partial bytes from a
program that wants them to recover. The composite leaves both operations as
they were.
