# 298. A refused allocation is answered by the test or the `main` that needed it

Status: Accepted — 2026-11-19. Extends
[0287](0287-tests-allocate-through-a-test-allocator.md) and
[0293](0293-a-test-allocator-counts-and-the-compiler-decides-what-must-be-disposed.md).

## Context

An allocation answers `Result[T, mem.Oom]`, and `?` hands the refusal up to a
caller whose error type converts it. Two places cannot hand it further and
wrote the same three lines each time.

A test that needs an allocation to proceed wrote
`let x = f() else |_| { return testing.assert(false, "x was refused") }`,
which reports the refusal as a failed assertion, or
`else |_| { return .Err(testing.refused("…")) }`, which reports it as a
refusal so that `each_allocation_failure` with `Failure.is_refusal` accepts
it. The standard library's tests held about eighty of the first, with the
match form `Err(_) => testing.assert(false, …)?, Ok(b) => { … }` beside
them, and the guide taught the second. The two spellings disagreed about what
a refusal is, and only the second could be used in a walked body.

A `main` wrote `else |_| { io.eprintln("…"); return 1 }` (or `.Ok(1)`) for
each allocation it made. Eleven examples and four guide programs did, each in
its own words for the same fact: "out of memory", "Unable to allocate the
shipping manifest", "could not rank the teams: Exhausted", and `|_|` threw
away the `Oom` the message described.

## Decision

**`testing.allocated(got: Result[T, mem.Oom], said: Str) -> Result[T,
testing.Failure]`** answers the value, or a refusal `Failure` carrying `said`.
A test writes `let x = testing.allocated(f(), "x was refused")?`. Outside a
walk the refusal fails the test with the message; inside one,
`Failure.is_refusal` accepts it, and a failed assertion in the same body still
fails the walk.

**`mem.Oom.report(self, what: T: Display) -> UInt8`** writes
`error: not enough memory for {what}` to standard error and answers 1. A
`main` writes `else |refusal| { return refusal.report("the manifest") }`.

Both take only `mem.Oom`. An error that hands a value back is settled first
with `.settled()` where settling is safe; one where it is not keeps its own
`let … else`.

## Consequences

- A refused allocation in a test has one meaning, a refusal, wherever the test
  runs, and the message names what was not built. A test that needs the walk
  to reject a refusal, to show that it does, still writes
  `testing.assert(false, …)` for it.
- `testing.refused` stays for a refusal that arrives as another type, such as
  a `BufferOpenFailure` over a reader that cannot be closed and so cannot be
  settled.
- A `main` names the `Oom` it answers, every refusal it reports reads alike,
  and the status is the one `main` returning an `Err` gives.
- `BufferedReader.open` and `BufferedWriter.open` answer `BufferOpenFailure`,
  which hands the stream back; settling it closes the stream, so a test or a
  `main` over a borrowed descriptor such as standard input keeps its own
  handler. Forty-seven of the library's test sites are of this kind.

## Alternatives considered

**`testing.assert_ok(got, said)` over any `Result[T, E]`.** It would replace
more sites, parse results among them, but it cannot tell a refused allocation
from a wrong answer: every failure it makes is an assertion, and a walked body
using it would fail on the refusal the walk exists to inject. The narrow type
is what lets one helper serve both kinds of test.

**Make the failure an assertion, as the library's tests wrote it.** It keeps
those sites' wording but forbids the helper in a walked body, which is where a
test most often allocates under refusal.

**`unwrap()` in tests.** It stops the whole test program at the first refusal,
so the tests after it never report, and the location it names is inside
`unwrap`.

**Exit status 71 (`EX_OSERR`) for a refused allocation.** No status is
conventional for running out of memory; 71 describes a failed system call.
Status 1 is what `main` returning an error answers, so a program answers the
same whether it hands the `Oom` up through `Result[UInt8, E]` or reports it
here.

**Change `Oom`'s `Display` from `Exhausted` to `out of memory`, and have
programs return the `Oom` from `main`.** A `main` that also prints answers
`Result[UInt8, io.IoError]`, so returning an `Oom` needs an error type of the
program's own for every such `main`; the report would still not say what the
memory was for.

**A free function `io.report_refused(what)`.** It takes no `Oom`, so a `main`
could call it for a failure that was not one, and `|_|` would go on discarding
the value the report describes.
