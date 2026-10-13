# 197. A checking runtime makes a use of freed storage abort

Status: Accepted — 2026-09-29

Builds on [0013](0013-no-undefined-behaviour.md), which rules out undefined
behaviour, [0017](0017-failure-is-a-trap-or-a-value.md), which makes a logic
failure abort, and [0095](0095-the-system-allocator-is-named-rather-than-received.md),
which names the allocator every buffer comes from.

## Context

The ownership rules and the checked storage accesses are what keep an
accepted program from reading storage it no longer owns, disposing of an
allocation twice, or reaching outside one. When a rule has a hole, the program
is accepted and nothing at run time notices. The runtime allocator is `calloc`
and `free`, which reuse freed memory at once, so a stale view reads whatever
the next owner stored there and the program goes on with it.

That has happened. `v.push(x)` inside `for _ in v.as_slice() { ... }` was
accepted while the walk's ownership path did not count the next pass's
`next()` as a use of the view; growing the vector freed the storage the view
still named, and the walk read it. The sanitizer lanes would report such a
read, but only on Linux CI: a sanitized program hangs on macOS, where the
compiler is developed, so locally the bug reads as a program that works.

What is wanted is a mode that turns every such access into a deterministic
abort, on every platform, without a sanitizer. Four questions settle it: where
the check lives and what it costs, what it may change about a program, when it
is on and how a run selects it, and what it says.

## Decision

### The check lives in the allocator, as page protection

**Under the checking allocator every allocation gets pages of its own, is
followed by an inaccessible guard page, and gives its pages back as
inaccessible pages when it is freed; no address is ever handed out twice.**

The allocator reserves address space in 16 GiB regions of inaccessible pages
and carves allocations from them in address order. An allocation's bytes sit
against the end of its pages, rounded up to eight bytes, and the guard page
follows:

```
| guard | zeros ... bytes canary | guard | zeros ... bytes canary | ...
```

Disposal maps fresh inaccessible pages over the allocation. That returns its
memory to the system and keeps its addresses reserved, so a stale address can
never come to name a later allocation. Any load or store through it then
faults in the hardware, whatever instruction makes it: an access in generated
code, or a read by the runtime's C (the decimal parser, `linea_panic`'s write
of its message). A fault handler for `SIGSEGV` and `SIGBUS` looks the address
up and aborts with what the address names.

A system call does not fault: the kernel answers `EFAULT`, or copies up to the
inaccessible page and answers a short count, and which one depends on the
kernel and the kind of descriptor. So the I/O entries hand every extent a
program gives them to the allocator before the call, and the allocator aborts
unless the extent lies within one live allocation's requested bytes or outside
every region.

Each detection, and how exact it is:

| Access | Detected | How |
| --- | --- | --- |
| load or store of freed storage | always, at the access | the pages are inaccessible |
| a second disposal | always | the record of the allocation says it is freed |
| disposal of an address that is not an allocation's start | always | no record starts there |
| disposal naming another size than was allocated | always | the record holds the size |
| access past the eight-byte-rounded end | always, at the access | the guard page |
| system call handed freed bytes, or bytes past or before an allocation's requested extent | always, before the call | the extent is looked up first |
| store between the requested and the rounded end, or before the start | at disposal | the canary bytes after the end, or the zero bytes before the start, have changed |
| read between the requested and the rounded end, or before the start | no | those bytes are mapped |

The last two rows are the gap between a page and an allocation. Generated
code bounds-checks every indexed access against the requested extent, so they
matter only for an access that check does not guard.

The bookkeeping is one record per allocation: its pages' start, the address
answered, the size and whether it is freed, 32 bytes kept for the life of the
process so that a later disposal or fault can be classified. Records are sorted
by address within a region, so disposal and the fault handler find one by
binary search.

**Costs.** Allocation makes one `mprotect` call, plus a `calloc` and `free` of
the same size (below), and disposal one `mmap` call.
A live allocation holds at least one page of memory — 4 KiB on Linux x86-64,
16 KiB on Apple silicon — and one more of address space for its guard. Address
space is never reclaimed, so it grows with the number of allocations a process
has ever made, a region at a time. The measured cost on the corpus is recorded
under Consequences.

**A bound keeps that within memory and within the kernel's mapping limit.** At
most 16,384 allocations hold pages of their own at once: at most 256 MiB with
16 KiB pages. Retired pages add no mappings: the inaccessible pages mapped over
a freed allocation match the guard pages on either side in protection, flags
and backing, so the kernel merges the three into one mapping, and a region
holds at most two mappings per live allocation plus one. That is at most about
32,768, half Linux's default `vm.max_map_count`; a native test on Linux holds
the mapping count of a process churning 100,000 allocations under a bound set
by its live ones.

Past the bound, and wherever the kernel refuses a reservation or a mapping or
the records cannot grow, an allocation comes from `calloc` and is kept in a
table of live addresses. A disposal of an address that table does not hold
aborts, whether it was never allocated or was already disposed of, so a second
disposal of such an allocation is reported as `not allocated`, and it is
caught only while `calloc` has not handed the address out again; the table
cannot tell the two apart. A stale read or store of such an allocation is not
detected.

**Not covered.** An arena's allocations are pieces of one system buffer, so a
stale piece inside a live arena is invisible to the system allocator; only the
arena's own buffer is checked. Storage that never came from the runtime
allocator — constants, the stack — is not checked. Leaks are outside this
record: a buffer that is never disposed of keeps its pages.

### Alternatives considered

**A generation stamp carried by every view.** Each allocation holds a
generation, and every view, slice, text, iterator and element borrow carries
the generation of the storage it names, compared on every access. It is exact
in the same way the page scheme is, and it is what a language without a memory
management unit would need. It lost because it is exact only where the
comparison is made and costs everywhere: every view widens by a word, every
element access gains a load and a compare, every layout and every emission
path that builds or reads a view changes, and so does the ABI of every runtime
call that takes an address. The runtime's C and the kernel would still need a
check of their own. Pages give the same exactness with the program unchanged,
which is also what lets a checked and an unchecked run differ only at the
link.

**Poison and quarantine.** Freed bytes are overwritten with a pattern and held
back from reuse for a while. A read of freed storage then yields the pattern,
which is a value like any other: the program goes on with it unless something
happens to notice. A use after the quarantine lets go reads the next owner's
data again. Detection is a matter of chance, which is the property this
decision exists to remove.

**Only `free`'s own checks.** A C library aborts on some double frees, in its
own words and on its own schedule, and on none of the other accesses above.

### A checked run means what an unchecked one means

The language rules out undefined behaviour, and it rules out behaviour that
depends on optimisation level. A checking mode may therefore change nothing an
accepted program can observe, **except to abort where the program would
otherwise have done something the language says cannot happen**: read or
write storage it no longer owns, dispose of storage twice or at another size,
or reach outside an allocation.

So the checking allocator answers what the ordinary one answers. Storage
arrives zeroed and eight-byte aligned. A request past 2^47 bytes is refused
before either allocator sees it. Any other request is first made of `calloc`,
and released at once: the checking allocator refuses exactly the requests
`calloc` refuses, so a large request such as 2^46 bytes gets the same answer
under both runtimes (on macOS both refuse it). Without that probe the reserved
pages would grant requests far past memory that `calloc` refuses, and
`match a.acquire(1 << 40)` would take a different arm under `linea test` than
under `linea run`. Addresses differ, but no
accepted program can observe an address: a buffer is opaque, and only a root
granted `extern` can hold one. A fault outside the allocator's regions — a
stack overflow, say — is left to the default action, which the handler
restores before it returns, so the process ends as it would without it.

The generated code is the same bytes in both modes, compiled at the same
level. The check is in the runtime, so it cannot depend on optimisation level
either.

### It is on for tests and the corpus, and off for a shipped build

- **`linea test`** always links the checking runtime. A test binary is where a
  program is exercised for correctness, and it is run on the machine where
  sanitizers do not.
- **The conformance runner** is handed the checking runtime by `build.zig` for
  every walk: the corpus, the examples, the recompilation properties and a
  narrowed walk. The CI scripts that call the runner directly name the same
  archive.
- **`linea run` and `linea build`** link the ordinary runtime unless given
  `--check-storage`. The driver has no debug build to tie this to: `-O` is its
  only optimisation setting, and every level preserves the language's
  contracts, so a level cannot mean "checked". A built program is what ships,
  and shipping a system call per allocation is a cost to opt into. A library
  build refuses the flag: it stops at an object and links no runtime.

**Selection is by archive.** The build installs `liblinea_rt.a` and
`liblinea_rt_checked.a`, which hold the same objects except the allocator's,
compiled with `LINEA_CHECK_STORAGE`, and only the checking one defines the
symbol `linea_storage_checked`. The driver chooses the archive by command and
flag. `LINEA_RUNTIME` names the runtime every build links, whichever allocator
it holds; a build that should check and links a runtime not naming that
symbol says so on standard error, unless a sanitizer is named, which does the
checking there.

**The outcome cache needs no new input.** Every key is salted with the bytes
of the runtime archive a run links, so a checked and an unchecked run file
their outcomes under different keys already.

**A sanitized runtime is not checked.** A sanitizer is a checking allocator of
its own: its shadow memory cannot describe pages the runtime maps itself, and
its leak check covers only its own heap. So a build with `-Dsanitize` compiles
the "checked" archive without the checking allocator.

**The runner learns whether a runtime checks from the runtime.** It looks for
`linea_storage_checked` in the archive it is handed, once, and says at the
start of a walk when it is absent. A case whose recorded outcome is one of the
checking allocator's reports -- the runner reads them from the runtime's own
`storage_reports[]` table -- is not built or run against a runtime without
that symbol, whatever the reason: a sanitizer, or the plain archive named by
hand. The walk counts those cases and names the archive that runs them, and
never shows their goldens as a difference `--update` would accept, since
accepting it would record the defect the report is about.

### What it says

A storage check fails the way the allocator's existing checks do: one line on
standard error beginning `linea: `, written with `write(2)` so the fault
handler can use the same routine, then `abort()`. A process ending on
`SIGABRT` is how every observer here already tells a runtime failure from a
status `main` returned.

| Message | Cause |
| --- | --- |
| `linea: storage was used after it was freed` | a load, store or system call reached freed storage |
| `linea: an access reached outside its storage` | an access reached a guard page, or a system call was handed bytes reaching outside their allocation |
| `linea: storage was freed twice` | a second disposal |
| `linea: a disposal named storage that is not allocated` | disposal of an address no live allocation starts at |
| `linea: a disposal named the wrong size: N bytes of a M-byte allocation` | disposal at another size than was allocated |
| `linea: a store reached outside its storage` | the bytes beside an allocation changed before its disposal |

The message carries no source location, because the allocator does not know
which instruction faulted; and so a storage abort never satisfies a test
expecting a trap, whose report must name one. It carries no rule name either,
because no rule of the language was broken by the program: each of these is a
guarantee the ownership rules and the checked accesses make, so a report is a
compiler or runtime defect to fix, not a diagnosis of the program. The
semantics document says so in §6.

## Consequences

- `linea test`, every corpus case and every example run under the checking
  allocator, so a hole in the ownership rules that reaches freed storage fails
  a case at the access on macOS, without a sanitizer, and on Linux once the
  steps below have been run there.
- A corpus case can now show such an access directly:
  `tests/checked_storage/` holds programs, granted `extern`, that dispose of
  an allocation twice, and read it and write it through the runtime after
  disposing of it.
- A program with many live small allocations spills past the bound to
  `calloc`, where only disposal is checked. A program making millions of
  allocations holds 32 bytes of records for each one until it exits.
- Measured on an Apple M-series machine (16 KiB pages), each on a cold
  outcome cache: the whole corpus walk (3,305 cases, 108 transcripts, 32
  generated programs) took 3,807 s of user CPU checked against 3,708 s
  unchecked, about 3% more; wall-clock time was dominated by linking and by
  other load on the machine, and did not separate the two. `linea test std`
  (1,058 tests) took 36–40 s either way. The corpus keeps the checking
  allocator on by default: a case's program allocates little beside the link
  it already pays for.
- One allocation and disposal of 32 bytes costs about 14 ns unchecked and
  6–14 µs checked on macOS. Two measurements on the same machine model
  disagree on whether it grows over a process: one read a flat 6–7 µs from
  25,000 to 1,000,000 iterations, another 9.6 µs rising to 13.7 µs. A program
  that allocates millions of times runs far slower checked either way, which
  is why `run` and `build` leave it off.
- No corpus case, example program or standard-library test aborted under the
  checking allocator on macOS: nothing in the suite reaches freed storage,
  disposes twice or at another size, or stores outside an allocation.

## Not yet run on Linux

**The checked runtime has not been run on Linux.** It was written and measured
on macOS; for Linux it has only been cross-compiled, with
`zig cc -target x86_64-linux-gnu` and `aarch64-linux-gnu`, and linked into
native test executables that were never executed. Yet this record makes it the
default for every conformance walk and for `linea test`, on Linux CI as
elsewhere. Three behaviours it rests on differ by kernel: whether retired
pages merge with the guard pages beside them, which keeps the bound under
`vm.max_map_count`; whether a fault on an inaccessible page delivers its
address in `si_addr`; and how a system call meets such a page, which the
up-front extent check is meant to make irrelevant.

Before the checking runtime is the default on a Linux lane, run there, inside
`nix develop`, on x86-64 at least:

1. `zig build test-native-runtime test-native-io test-native-net`, which
   includes the Linux-only test holding the mapping count of a churning
   process to a bound set by its live allocations;
2. `zig build conformance -- tests/checked_storage` against the checking
   runtime, expecting all three cases to abort with their recorded reports;
3. the whole `zig build conformance`, and `linea test std`, expecting no
   storage abort;
4. `zig build conformance -Dsanitize=address`, expecting the three cases to be
   counted as not run and nothing else to change.
