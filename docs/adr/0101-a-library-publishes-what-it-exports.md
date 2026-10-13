# 101. A library publishes what it exports

Status: Accepted — 2026-08-22

Extends [0096](0096-a-root-is-a-program-or-a-library.md), which made a manifest
say whether a root is a program or a library, and left every naming decision
about what a library publishes to this record.

## Context

0096 made a library compilable. It did not make one linkable.

What it left was a root that emits code and cannot be called: the emitted
symbol was `@lin.square`, which no C compiler produces and no header can
declare; the calling convention was the one the body is compiled in rather than
the one the declared type names; and nothing in the source said which
declarations were meant to be reached at all. That last gap was filled by a
stand-in — a library emitted the non-private declarations of its root module —
which is a rule about visibility between Linea modules standing in for a rule
about linkage.

The stand-in was load-bearing in a way that was easy to miss. Because it
collected every non-private declaration and then subtracted what should not
ship, it had a set to subtract *from*: the first version of it put every body
the standard library defines, and every `test fn` beside them, into the object
of a library that called four of them.

## Decision

**`export` marks a declaration the linker publishes, and it is orthogonal to
`pub`.** All four combinations mean something, and the third is what justifies
the separation rather than merely permitting it:

| declaration | Linea may name it | the linker publishes it |
| --- | --- | --- |
| `fn f()` | no | no |
| `pub fn f()` | yes | no |
| `export fn f()` | no | yes |
| `pub export fn f()` | yes | yes |

A library may expose a C entry point that is not part of its Linea API, and an
API it does not expose to C. Fusing the two would make each the other's price.

**A library's exports are its lowering roots**, exactly as a program's entry
point is its root, and everything else is reached from them. `pub` does not
participate.

**An export designates exactly one concrete foreign ABI entry point**
([M-Export]). A generic designates none until something instantiates it; a
program has no foreign surface for one to sit on; a `test` is called by the
compiler and ships in nothing. All three are the same rule read at a different
declaration.

**What may cross is decided by the boundary and not by the direction.**
[T-Export] is [T-Extern] read outward, and one predicate answers both — the
rule name is the only thing the two directions do not share, so a programmer
writing an `export` is not sent to a rule about `extern`.

**The exported symbol is the bare source name, and it is always a thunk.** The
thunk takes the declared types' widths, widens to the convention the body was
compiled for, calls it, and narrows the answer back. The body stays internal
behind it.

### Three widths, and which one is a promise

An integer has three widths and they are independent:

| layer | for `Int32` | owned by |
| --- | --- | --- |
| memory representation | 32 bits | the semantic type width |
| computation width | 64-bit SSA values | an implementation choice |
| foreign ABI width | 32 bits | the exported contract |

The middle row exists to make overflow checkable: computing `UInt8`'s
`200 + 100` at the type's own width yields `44` before any check runs, so a
range test against `0..=255` passes and the overflow becomes undetectable by
range test at all. Performed in a width that cannot itself overflow for the
operand domain, one range check answers for every narrow type and every
operator. The 64-bit types have no such width available, which is why they
alone carry per-operation detection.

**The computation width binds nothing.** It is not a language rule and not part
of the ABI. The thunk's contract is stated as adapting the internal calling
convention to *the ABI width of the declared type* — never as converting from a
64-bit value. Pinned to `Int32`, which is a language fact, a narrower internal
convention changes what the thunk emits and nothing else: the ABI it publishes
is unmoved, and the adaptation is the one place that has to be taught the new
convention. What it emits today widens on entry and narrows on exit, because
the convention is the wider of the two; a convention narrower than a declared
type would narrow on entry and widen on exit, and the thunk is where that is
written.

## Consequences

A library object exposes exactly the symbols its source marks, under the names
its source spells, in the widths its declared types name. A C program declaring
`int32_t square(int32_t)` links against it and runs, which the corpus records by
building the object, compiling a `driver.c` beside the case, linking the two
with the runtime, and comparing what the program printed.

Rooting reachability at the exports removed the filter rather than correcting
it. Nothing unreachable is added, so there is no set to subtract from, and the
`std`-and-tests defect cannot recur by a different route.

Every body is now internal, a library's included. What something outside
reaches is the thunk, and the thunk is in the module and references the body —
so a library has the shape a program already has, and neither carries a body the
optimiser must keep on the chance of a caller it cannot see.

A library with no exports is valid and produces an object with no foreign entry
points. Refusing it would be a packaging rule wearing an ABI rule's clothes:
nothing about the type system or the ABI is violated by a module that publishes
nothing.

## Alternatives considered

**`pub` in a library's root is the export.** No new syntax, and it matches how
the stage-1 case was written. Rejected because it permanently fuses two
decisions — a declaration visible to other Linea modules would necessarily be a
C ABI export — and because it leaves a generic nowhere to report. A generic
`pub fn` is legal and must stay legal, so the rule could only fall silent on the
one declaration it most needs to refuse. A dedicated modifier is a site the
compiler can say no at.

**An export list in the manifest.** Keeps the ABI surface in one reviewable
place. Rejected because it splits a declaration from its own promise across two
files, and because a bad export could then only be reported against a manifest
line rather than against the code — which fights the way every other diagnostic
in this compiler points at source.

**Publishing the internal calling convention.** `@square` emitted directly as
`i64 -> i64`, with C callers declaring `int64_t`. No wrapper to generate.
Rejected because the ABI would then contradict the source — the function says
`Int32` and the header says `int64_t` — and because it turns a decision made for
overflow-checking into an FFI compatibility commitment that could never be taken
back.

**Eliding the thunk where the widths coincide.** For `Int64` the conversions are
empty, so the thunk is a bare call. Rejected because a thunk that disappears
when the widths happen to match makes the published ABI a function of whether an
optimisation fired, and the outside world would be linking against whichever
body the module happened to lower. The cost of keeping it is one frequently
trivial call, and the optimiser may still inline through it; what it may not do
is change which name the outside world links against.

**Prefixing the symbol with the package name.** `mathkit_square` rather than
`square`, which is the convention careful C libraries follow by hand. Rejected
because the symbol would no longer match the source name, so an author would
have to know the rule to predict it, and renaming a package would silently break
every linked consumer. An author who wants a prefix can write one, and the
manifest's name stays free for purposes that are not linkage.
