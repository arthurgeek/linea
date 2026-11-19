# 293. A test allocator counts, and the compiler decides what must be disposed

Status: Accepted — 2026-11-18. Supersedes the clause of
[0287](0287-tests-allocate-through-a-test-allocator.md) that releasing a
`TestAllocator` or a `SharedTestAllocator` checks `all_disposed()` and stops
the program when an allocation it handed out is still live, and removes their
`close()`, which existed to avoid that stop.

## Context

0287 made releasing a test allocator check that every buffer its handles
acquired was disposed, and stop the program when one was not. A test holding a
test allocator therefore had two judges of what counts as leaked: the
compiler, which holds every buffer to its backing's obligation, and the
allocator's release.

They disagree where the backing is an arena. A buffer from an arena carries no
obligation: the program may drop it, and the arena takes it back when it is
released. Over an arena, a test that dropped a buffer, or that failed an
assertion with `?` while one was live, reached the release with the buffer
counted live and stopped there: a passing test failed, and a failing test's own
report was replaced by the release's.

Over the system allocator the two cannot disagree. Its buffers owe their
disposal, and [O-Leak] refuses a test that returns, early or not, while one is
live, so the release never sees one an accepted program left.

## Decision

**A test allocator records allocation and disposal; it does not decide what
counts as a leak.** `acquired()`, `disposed()`, `outstanding()` (acquired less
disposed), `live_bytes()`, `peak_bytes()` and `all_disposed()` stay
observable, and a test that wants every buffer given back asserts it:
`testing.assert_eq(log.outstanding(), 0, …)`.

**Releasing one respects its backing's ownership.** Over a backing that takes
back only when it is itself released, an arena's handle, whose `reclaims()`
answers false, a buffer still live is one the program was allowed to drop, and
release ends the counts without a word. Over a backing that reclaims each
buffer disposed into it, the system allocator, every buffer owes its disposal,
so one live at release means the compiler or the runtime broke an invariant;
release stops the program saying so, and asks for a compiler bug report. No
accepted test reaches that stop, so it never stands in front of a test's own
failure.

`close()` is removed: its one use was to end a test allocator without the stop
release made, which release no longer makes for anything an accepted program
can do. `each_allocation_failure` reads `outstanding()` and releases.

## Consequences

- An arena-backed test that fails early reports its own failure only, and one
  that drops a buffer passes unless it asserts that nothing is outstanding.
- A test relying on release to catch a dropped arena buffer must now assert
  `outstanding()` itself.
- `reclaims()` is the property release reads. In the standard library a backing
  answers false exactly when its buffers carry no obligation, the arena's
  handle and a test handle over it.

## Alternatives considered

**Report the leak after the test's own failure instead of panicking.** It keeps
the allocator judging what the compiler already judged, and would fail every
arena-backed test that drops a buffer it may drop.

**Ask the backing's obligation type directly.** Whether `H.Obligation` is
linear is decided by the compiler and cannot be asked by a library body; a
trait member only for this would add a second statement of what `Obligation`
already says.
