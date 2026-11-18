# 283. An arena disposes of a buffer without rechecking where it lies

Status: Accepted — 2026-11-18. Supersedes the disposal clause of
[0263](0263-an-arena-grows-in-chunks-up-to-its-size-and-a-rewind-returns-them.md):
that "`dispose` checks that a buffer lies within one of those chunks, so its
extent check reads at most that many." Builds on
[0264](0264-an-address-lives-no-longer-than-what-it-was-made-from.md), which
confines every field of a `Buffer` to the members of the allocator that made
it.

## Context

`Handle.dispose`, the arena handle's `Allocator.dispose`, takes back nothing:
a disposed reservation's bytes come back only when the arena is rewound or
released. It still checked that the buffer's address and extent lay inside the
arena. 0263 made that check walk the arena's chunks: `arena_holds` tried the
first chunk, then the current one, and then took each later chunk's
`Buffer[H]` out of the arena's table to compare against it, panicking with
"an allocation lies outside its backing arena" when none held it. That walk
needed four grants of its own in the compiler's raw-access tables:
`arena_holds` among the declarations that read a buffer's fields, that read
an arena's, that take slots out of storage, and that may call
`arena_table_of`, and `handle_dispose` among those that read an arena's
fields.

The check was written when nothing kept a buffer's fields from being written
by hand. 0264 confines them: a `Buffer[Handle[H]]` is built only by
`Handle.acquire`, from the reservation `arena_reserve` cut out of one of the
arena's chunks, and its fields are named only by the members of
`Allocator for Handle[H]` and the declarations `RawAccesses` lists. The
buffer names its own handle, so no caller can hand it to another arena, and a
rewind takes the arena `inout`, so no buffer it handed out is live across
one. Every buffer `dispose` can be given therefore already lies where the
walk looked for it, and the panic cannot be reached by any program the
compiler accepts.

## Decision

**`Handle.dispose` takes the buffer apart and does nothing else.**
`arena_holds` and `arena_within` are removed, and with them every grant that
existed only for them: `arena_holds` in `buffer_numbers`, the arena's raw
type, the slot users and the `arena_table_of` confinement, and
`handle_dispose` among the declarations that read an arena's fields.
`handle_dispose` stays among `backing_buffer_builders`, since it still takes
a `Buffer` apart.

What made the check unnecessary is a construction guarantee the compiler
holds, not a check at run time, so the place that guarantee would break is
the confinement 0264 keeps: a declaration added to `RawAccesses` that writes
a buffer's fields is held to that table, and a new way to build a
`Buffer[Handle[H]]` would be one.

## Consequences

Disposing of an arena reservation costs nothing, where it read the arena's
words and up to `log2((size - 8) / 64 KiB) + 1` chunk slots. An HTTP exchange
disposes of its three 4 KiB buffers and of everything its handler reserved,
each once per request.

The arena's private functions that trust the first chunk they are handed are
now three, `arena_give_back`, `arena_reserve` and `arena_table_of`, and
`arena_table_of` is called by two of them.

A buffer from somewhere else cannot reach `dispose` without a compiler
defect. If such a defect let one through, disposal would no longer panic:
nothing is freed by it, so no storage is reused early, but the defect would
show only where the buffer's bytes were used.

## Alternatives considered

**Keep the check as a defensive assertion.** It guards against a buffer the
compiler has no way to produce, at a cost every disposal pays, and it is the
one part of the arena that needs to read the chunk table from a handle. The
confinement it would back up is checked when the program compiles, which is
where a broken construction guarantee belongs.

**Keep only the first-chunk and current-chunk comparisons.** That check is
cheap but no longer complete: a reservation in an earlier later chunk would
fail it, so it would have to panic on valid buffers or answer nothing, and a
check that cannot fail on a valid program and cannot be complete checks
nothing.
