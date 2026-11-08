# 263. An arena grows in chunks up to its size, and a rewind returns them

Status: Accepted — 2026-11-08. Supersedes the arena-memory clause of
[0154](0154-sockets-and-http-follow-go.md): that `serve` opens one
`mem.Arena` of `limits.request_arena_bytes` ("5 MiB by default") whose whole
slab is acquired once, and that `Arena.rewind` keeps the slab, zeroing the
bytes the exchange used. Builds on
[0191](0191-the-caller-chooses-every-allocator.md), which has every
allocation come from an allocator the caller chooses.

## Context

`mem.Arena.open(parent, size)` acquired `size` bytes from `parent` in one
buffer and handed out pieces of it by advancing a cursor. `Arena.rewind`
zeroed the bytes that had been handed out and moved the cursor back, so the
buffer stayed zero beyond the cursor and every reservation was handed out
zeroed without clearing anything as it was bumped.

`http.serve` keeps one such arena per serving task for the task's whole life,
of `limits.request_arena_bytes`, which is now 48 MiB by default (0154 says
5 MiB; the default grew when JSON bodies were decoded into the arena), and
serves 128 tasks by default. Over the system allocator the buffer is
`calloc`'s, whose pages the kernel supplies as they are first touched, so an
idle server was small: 6 to 17 MB on Linux. But a rewind writes zero over
every byte a request used, which keeps those pages, and the next rewind
keeps them again. A task's arena therefore holds its high-water mark for the
life of the server:

- After 1,000 echoes of 1 MiB JSON bodies to `examples/http-json-echo`, a
  128-task server held about 906 MB on Linux and 911 MB on macOS, and still
  held it after 10,000 small requests that followed.
- Under the thread sanitizer, whose `calloc` touches every page it answers
  on a serving task's thread, each 128-task server held about
  6.3 GB from the start, which is why the conformance runner lets only one
  serving transcript run at a time under that sanitizer.

The arena's size does two jobs. It bounds what one request may make the
server hold, which `serve` checks against the other limits
(`smallest_arena`, `ArenaTooSmall`), and it was the memory acquired. Only the
first job needs the number.

## Decision

**An arena's size is a limit on what it hands out, not memory it takes when it
opens.** An arena of at most `arena_first_chunk_bytes` (64 KiB) acquires its
whole size when it opens and is unchanged: one buffer, a cursor in its first
eight bytes. A larger arena acquires a first chunk of 64 KiB when it opens
and further chunks from its parent only as reservations need them:

- A reservation that does not fit in the current chunk acquires a chunk of at
  least the reservation and at least twice the current chunk, or, when twice
  the current chunk is more than the arena can still hand out, exactly what it
  can. A reservation never spans two chunks; a caller that grows a buffer
  already reserves a larger one and copies into it.
- The arena hands out at most its size less eight bytes, counted as one buffer
  of that size would count it, whatever the chunks. So `smallest_arena`, which
  adds up reservations rounded to eight, and `ArenaTooSmall` stay checked
  against the size, and a test that serves a request in the smallest arena the
  limits admit is still answered.
- `rewind` zeroes the bytes of the first chunk that were used and gives every
  later chunk back to the parent. The parent hands out zeroed buffers, so
  every reservation is still handed out zeroed, and the arena between
  requests holds 64 KiB, whatever the largest request was.
- A parent refusing a later chunk refuses the reservation that needed it with
  `Oom.Exhausted`, the answer an exhausted arena always gave; a request whose
  handler runs out of arena is answered 500. Opening still acquires the first
  chunk, so a parent that refuses it leaves an arena that refuses everything,
  which `serve` answers 503, as before.
- Every chunk comes from the arena's parent, so an arena over a test log or a
  shared log grows through it as one over the system allocator does. An arena
  over another arena's handle takes its whole size at open, as before: a
  buffer disposed into an arena is not handed out again until that arena is
  rewound, so chunks given back to it would only use it up, and a loop that
  rewinds the inner arena would drain the outer one. `Allocator.reclaims()`
  says which: it answers true by default, false for an arena's handle, and a
  log answers what its backing does.

The first chunk keeps the arena's words (bytes handed out, the current
chunk's address, length and cursor, how many later chunks it holds) and a
table of the later chunks' buffers, written as typed storage, so a chunk is
given back through its own `Buffer[H]` and its parent's obligation. Every
chunk before the last is at least twice the one before it and at most the
arena's size, so an arena holds at most `log2((size - 8) / 64 KiB) + 1` later
chunks; a 48 MiB arena has room for ten. `dispose` checks that a buffer lies
within one of those chunks, so its extent check reads at most that many.

64 KiB holds the three 4 KiB buffers of an HTTP exchange and what a small
request and its answer reserve, so a server answering small requests acquires
nothing past the first chunk; a test serves `GET /health` after a request
that filled the arena and checks that the parent was asked for nothing more.
Built with first chunks of 16, 32 and 64 KiB, `http-json-echo` measured the
same idle footprint on macOS (11 to 13 MB for 128 tasks, since untouched
pages cost nothing), and after 20,000 small echoes and 2,000 echoes of
64 KiB bodies 29 to 30 MB, 27 to 30 MB and 25 to 26 MB. A smaller first
chunk grows on more requests, and each growth is an acquisition and a
release per request, for no saving at idle.

## Consequences

Re-measured on macOS with the same program and load, a 128-task
`http-json-echo` built with `linea build`, as physical footprint:

| | Before | After | After, `MallocLargeCache=0` |
| --- | --- | --- | --- |
| Idle | 13 MB | 11 MB | 11 MB |
| After 1,000 echoes of 1 MiB bodies | 917 MB | 643 MB | 14 MB |
| After 10,000 small requests that followed | 917 MB | 645 MB | 16 MB |

The arenas no longer hold what the large requests used: every chunk past the
first is back with the system allocator once its request is answered. What
the second column still shows is that allocator's own cache. macOS's
`malloc` keeps freed regions mapped and dirty for reuse (`vmmap` lists about
300 MB of them as "Malloc Large (empty)" and 320 MB as "Malloc Small
(empty)"), and with its large-allocation cache turned off it marks them
reusable instead, which the third column shows. Before this change that
setting made no difference, because the memory was live in the arenas. That
cache is the runtime's choice of C allocator, which this record leaves as it
is; whether the runtime hands large buffers back to the kernel itself is a
separate decision.

An exchange that grows past 64 KiB acquires and gives back its chunks once per
request: an acquisition and a release from the parent for each doubling, at
most ten for a request that fills a 48 MiB arena. A large request now pays the
parent's zeroing of what it used when the chunk is acquired, where it paid the
rewind's zeroing before.

What an arena holds from its parent while a request runs is bounded by the
first chunk and three times its size, not by its size: the bytes a chunk was
left with when a reservation did not fit are not handed out again until a
rewind. The chunks before the last sum to less than twice the largest of
them, which is at most the size, and the last is at most the size. In the worst case that
is more than one buffer of the size held; in the common case it is what the
request used, rounded up to a doubling.

An arena larger than 64 KiB opened over a parent that cannot supply its whole
size now opens and hands out storage until the parent refuses. A test that
needs an arena that refuses everything refuses its first acquisition through
`testing.AllocationLog`. `AllocationLog` and `SharedAllocationLog` answer
`live_bytes()`, what is acquired and not yet disposed, so a test can check
that a rewind gave its chunks back.

Under the thread sanitizer a serving task holds its first chunk and what its
request is using, not 48 MiB, so the conformance runner no longer runs the
transcripts that leave a server running one at a time under it.

## Alternatives considered

**Commit pages on demand with `mmap` and give them back with `madvise`.** The
arena would reserve its whole size as address space and let the kernel supply
pages; a rewind would tell the kernel to drop the used pages
(`MADV_DONTNEED` or `MADV_FREE`). It keeps one contiguous buffer and a
reservation could span what would here be two chunks. It goes around the
arena's parent: every chunk would come from the kernel, not from the
allocator the caller chose, so an arena over a test log, a shared log or
another arena could no longer be counted or refused, which
[0191](0191-the-caller-chooses-every-allocator.md) makes a requirement of
every allocating API. It also differs by platform in what a dropped page reads
as and when its memory is returned, and the sanitizers intercept neither call
the way they intercept the allocator.

**Keep one slab and `madvise` the used part on rewind.** The same loss of the
parent, applied after the fact, and the parent's buffer is not the arena's to
give back to the kernel: a buffer from another arena or from `calloc` may
share pages with other allocations.

**A smaller default limit.** The 48 MiB is what the default limits need: about
5.2 MiB to read the largest request they admit, up to 31 MiB to decode the
JSON body they admit, and room for the response. A smaller arena answers 500
to requests the limits accept, and still holds its high-water mark after a
large request. The limit stays an honest bound on one request; what is held
between requests no longer depends on it.

**Release chunks only when the arena is released, not on rewind.** It holds
what the largest request used for the life of the task, the problem this
record removes.

**Let a reservation span chunks, or reuse the tail of an earlier chunk.** A
reservation is a `Buffer`, one extent, and every caller reads it as one.
Tracking free tails to fill later would make reservation a search instead of
a bump, for memory a rewind recovers anyway.
