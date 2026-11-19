# 292. JSON Lines are read lazily, one bounded line at a time, and a failed line is an item

Status: Accepted — 2026-11-19. Extends
[0141](0141-json-documents-own-bounded-trees-and-number-tokens.md), whose
parse limits bound each line.

## Context

JSON Lines (also called NDJSON) holds one JSON text on each line. Logs, event
streams and exports are written this way because a writer can append a record
without rewriting the file and a reader can process a record without holding
the rest. `std.json` parsed whole documents only: a program reading a log had
to collect lines from an `io.BufferedReader` by hand, choose a line limit,
parse each line, keep its own line count for messages, and decide what a
malformed line, a blank line, an overlong line or a line that is not UTF-8
means. Each of those is a policy, and two programs choosing differently
disagree about the same file.

A reader that is an `Iterator` composes with `for`, `map`, `filter` and the
rest. Its `next` lends the buffered reader it holds to each read, and since
[0291](0291-a-place-lent-inout-comes-back-with-its-parts-merged.md) a callee
may move what a place lent `inout` holds between its parts without a clause,
so `next` needs no contract beyond the trait's `carries(.Some: self)`.

## Decision

**The reader is an iterator over a byte reader.** `json.Lines.open(reader)`
and `json.Lines.open_in(allocator, reader)` take any `io.Reader` and buffer it
through a 4 KiB read-ahead. `Lines[R, A]` is an `Iterator` whose items are
`Result[Value[A], LinesError[R.Error, A]]`. `lines.decoded[T]()` turns it into
a `DecodedLines[T, R, A]` whose items are `Result[T, LinesError[R.Error, A]]`,
decoding each document with `T.decode` in the reader's allocator and releasing
the document. Bytes are read only when an item is asked for. Both are linear
and `abandon()` returns the reader, so a file is closed and a descriptor kept
by the caller who owns it. Opening allocates the read-ahead buffer, so it is
`open`, and its failure is the buffered reader's `BufferOpenFailure`, which
hands the reader back.

**The document limit is the line limit.** A line is one document, so
`limits.max_input_bytes` (8 MiB by default) bounds it, and there is no second
limit to keep consistent with the first. The line record grows only to the
longest line read. A longer line is discarded to its end without being
stored, a bounded budget at a time, and reported; the reader's memory is
bounded by one line and its document whatever the stream's length.

**A failed line is an item, and reading continues.** A line that does not
parse, does not decode into `T`, exceeds the limit, is not UTF-8, or whose
record the allocator refuses yields `Err` and the next item comes from the
following line, because a line feed ends a record whatever the record held. A
failure of the stream itself (an input error of the byte reader, a reader
reporting more bytes than it was given, or a stream past 2^64 bytes) yields one
`Err` and then `None`: nothing after it can be framed. A caller that wants the
first error to end the walk breaks out of it.

**An error says which line and what went wrong, in the words `decode` uses.**
`LinesError` holds `line`, counted from one with blank lines included, and a
`LineProblem`: `Document(DecodeError[A])` with exactly what `decode` would say
of that line alone, or `Input(io.LineError[E])` for the stream. A line past
the limit is `Parse` of kind `InputLimit` at offset `max_input_bytes`, as the
parser reports input too long, and bytes that are not UTF-8 are `Parse` of
kind `InvalidUtf8` at the offending byte of the line, as `parse_bytes` reports
them. It displays as `line 3: missing field at $["units"]`.

**Framing follows the buffered reader.** A line ends at LF or CRLF; the final
line needs no terminator, and a file ending in a line feed has no empty last
record. A line holding only JSON whitespace is blank: it yields no item, since
it holds no document, but it is counted, so line numbers match an editor's. A
byte-order mark is not skipped; the first line then fails to parse, as a
document beginning with one does.

**Writing is a function, not a type.** `json.write_line(&writer, document)`
and `json.encode_line(&writer, value)` write compact JSON and a line feed.
Compact JSON escapes every line feed inside a string, so a value takes exactly
one line. They neither buffer nor flush: `io.BufferedWriter` already owns
buffering, `flush` and the `finish`/`abort` settlement, and a program flushes
when the reader at the other end should see what was written.

## Consequences

`std.json` gains `Lines`, `DecodedLines`, `LinesError`, `LineProblem`,
`write_line` and `encode_line`. The JSON settings and inventory examples write
their output with `encode_line` and `write_line` instead of a helper of their
own, and the uptime report example reads a log of health checks.

A stream whose input fails transiently ends the walk; a program that retries
reads the reader back with `abandon` and opens a new `Lines` over it, losing
the read-ahead. A line that is longer than the limit is still read to its end,
so a stream with no line feed is read to its end before the error is
reported, in bounded memory but unbounded time; a deadline on the source,
such as `net.Connection.set_deadline`, bounds the wait.

A writer that fails partway through `write_line` or `encode_line` holds part of
a line, and a later line would be appended to it, so the stream is no longer
JSON Lines. The functions do not recover it: a caller abandons the writer after
a failure, as with any writer whose output is framed.

## Alternatives considered

**A separate `max_line_bytes`.** It would let a caller accept a line longer
than any document it accepts, which only fails later, or a line shorter than
the document limit, which `limits` already expresses. Two limits for one
quantity can disagree; one cannot.

**Ending the walk at the first failed line.** That makes one corrupt record
hide the rest of a log, which is the failure JSON Lines exists to avoid.
Reporting and continuing loses nothing: `break` gives the stricter policy.

**Skipping failed lines silently, or yielding only values.** The program could
not count or report what it lost, and ADR 0017 forbids hiding a failure.

**Treating a blank line as an error.** The JSON Lines description requires a
value on each line, but files end with an extra line feed or carry blank
separators in practice, and a blank line cannot be a partial record. Not
counting blank lines would make reported numbers disagree with an editor.

**A `LineWriter` type wrapping a writer.** It would duplicate the buffered
writer's flush and settlement, or forward to them, and every program that
already holds a writer would have to wrap it.

**Making `json.Value` implement `Decode` so one reader type serves both.**
Decoding a document into a `Value` would copy every line's tree to produce what
parsing already produced.

**Reading lines with `read_line` and parsing them in the caller.** That is what
programs did, and it is where the policies above diverged. A loop over an
inherent `next` instead of `Iterator` would leave the reader outside `for` and
every adapter.
