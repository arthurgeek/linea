# 74. A module is emitted as several compilation units

Status: Superseded by [0094](0094-a-module-is-emitted-as-one-compilation-unit.md) — 2026-08-18

## Context

A module today becomes one file at every step below MIR:

```
Module → one .ssa → one .s → one .o
```

That chain is serial, and it is where a build's time goes. Measured over a
program of 30,001 small functions, the compiler itself is 0.17s of a 5.9s
build — under three percent. `qbe` takes 1.02s and the assembler 4.39s.

Both of those are per-function work with no dependency between functions, so
the chain is serial for no reason that the work requires. Splitting the same
660,009 lines of IR into eight parts and running `qbe` and `cc -c` concurrently
on each:

| | serial | eight ways |
| --- | --- | --- |
| qbe + assemble | 4.29s | 1.34s |

The two executables produce identical output and the same status.

**The gain is bounded by the largest function, not by the core count.** A
program of 2000 interpolations is 18 functions of which one is 2.4MB, and the
same split takes 8.31s to 7.62s — 1.09x. One function is 99.7% of the work and
nothing partitions it. So this decision and the work on emitted volume are
orthogonal: partitioning pays where there are many functions, emitting less
pays where there is one large one, and neither substitutes for the other.

## Decision

**Below MIR, a module is emitted as several compilation units.** The count is
chosen by the driver, each is written, assembled and compiled independently,
and the objects are linked as one.

The partition is not a language concept and is not observable. `emit-ir` writes
one stream, the dumps say nothing about it, and no diagnostic names it. It
exists between the emitter and the toolchain and nowhere else.

### What a symbol's visibility is

QBE emits anything not marked `export` as a file-local symbol, so a reference
that crosses a partition does not link — the first attempt failed on `lin.f0`,
defined locally in one object and undefined in another.

**A definition is exported when something outside its partition references it,
and not otherwise.** The emitter has the edges already: a call carries a
`FuncId`, and a blob or file reference carries its index. Collecting them costs
one pass over MIR before writing, because whether a definition is referenced
from elsewhere is not known until everything has been seen. That pass is a cost
of partitioning and of nothing else.

Exporting every definition instead would work and is rejected. It discards
information the compiler already holds, and it is the kind of
over-approximation that is easy to widen and hard to narrow later, once tools
and tests have accumulated around the wider set.

**An exported definition is also marked hidden in the final image**, through
whatever the platform's visibility mechanism is — `.private_extern` on Mach-O,
`.hidden` on ELF. The symbol is global while the link runs, so a crossing
reference resolves, and local afterwards, so the symbol table does not grow.
Visibility therefore becomes a property of the compilation pipeline rather than
of the generated program: the source never asked for those globals, and they
exist only because compilation was split. This is what makes the size cost nil
rather than small:

| | binary | stripped |
| --- | --- | --- |
| one object | 2845KB | 2029KB |
| eight objects, everything exported | 3168KB | 2352KB |
| eight objects, exported and hidden | **2845KB** | **2029KB** |

The `__TEXT` segment is byte-identical in all three; the whole difference was
`__LINKEDIT`, which is to say symbol names. Marking them hidden returns the
binary to the byte.

### When a module is partitioned at all

**On estimated backend work, not on a function count.** Work is the emitted
instruction count plus data size, because a function count says nothing about
the shape that cannot be helped: one enormous function has a high count of
neither functions nor partitions worth making. Below the threshold a module is
emitted as one unit exactly as today. A three-line program spends 3.4ms of its
4.5ms on process spawn, and eight of them would be the whole cost of the build.

### What the partitioning strategy is

**Deliberately open.** The first implementation is a simple greedy partition by
estimated work — the least that satisfies the decision. Better strategies are
expected once there are representative programs to choose one against.

That openness is load-bearing rather than modest, because strategy determines
the size of the boundary by orders of magnitude. Over the generated chain
above, in eight parts:

| strategy | definitions needing export |
| --- | --- |
| contiguous runs | 7 of 30,001 |
| round-robin | 30,000 of 30,001 |

Over a real program in four parts, contiguous runs, round-robin and
longest-first packing give 66.7%, 84.8% and 90.9% — the strategy that balances
best is the worst for the boundary, because sorting by size scatters callers
away from callees. Clustering the call graph and balancing the clusters would
minimise both at once, and is the obvious direction. It is not built here
because the shape of a large real Linea program is not yet known: the biggest
that exists is 33 functions, and the two measurements available disagree by
three orders of magnitude about how much locality a partition can expect to
find. Choosing a locality strategy now would be fitting it to a generator.

Nothing downstream depends on the strategy, which is what leaves it open:
correctness rests on the exported set being computed from the partition
actually chosen, not on the partition being good.

## Consequences

The back end of a build over many functions is about three times faster on
eight cores, and unchanged over one large function.

**A partition boundary is a place two things can disagree.** The exported set
is derived from the assignment, so both come from one routine and neither is
recomputed — the compiler's standing rule about one question and one answer
applies directly, and a symbol exported against a partition it is no longer in
is a link failure rather than a wrong answer.

**The toolchain step stops being one process each.** `build` spawns up to N
`qbe` and N `cc -c`, which is where a failure now has to say which partition it
came from without making the partition part of the diagnostic's meaning.

**The invariant is that a cross-partition reference resolves; visibility is how
that is achieved today.** Marking a definition global-then-hidden is one
mechanism among several — trampolines, section merging and link-time
compilation are others — and a later one replaces the mechanism without
touching the decision. What the decision fixes is that the set of references
crossing a boundary is computed, not assumed.

**Something in the pipeline gains a platform-conditional step**, because the
visibility mechanism is named differently on Mach-O and on ELF. Which component
carries it is a design question and not this one.

**Incremental compilation is neither helped nor hindered.** A partition looks
like a unit of separate compilation and is not one: it exists only after
monomorphisation, so it is a function of the whole program and nothing about it
survives a change to the program. Reusing work across compilations still needs
what it needed before this record, which is a representation that can be
serialised and keyed.

## Alternatives considered

**Export every definition.** Simpler, links correctly, and costs 11% of the
binary until the hidden-visibility marking is added — after which it costs
nothing measurable, since `__TEXT` is identical either way. Rejected on the
grounds above rather than on size: the information is already held, and the
wider set is the harder one to narrow later.

**Leave the back end serial and keep reducing emitted volume.** This is what
the previous work did, and it remains the only lever for a single large
function. It is not an alternative to this one — over many functions the
emitted volume is already near-minimal and the serial chain is the cost.

**Parallelise inside QBE or the assembler.** Both are separate programs, and
the pipeline treats them as programs deliberately. Threading either one means
vendoring it.

**Partition per source file.** Reads as the natural unit and is not one: a
module is a directory, monomorphisation moves code between files, and the
result would be as unbalanced as the sources happen to be. The partition is a
property of the emitted code, not of where it was written.
