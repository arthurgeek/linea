# 49. Generated code is verified before it is emitted

Status: Accepted — 2026-07-29

Discharges [0013](0013-no-undefined-behaviour.md) below MIR, where nothing was
discharging it. Reads [0015](0015-when-to-introduce-a-representation.md) to say
what the pass does *not* introduce, and
[0016](0016-passes-are-functions.md) for how it allocates.

## Context

Linea states that no operation has undefined behaviour. That is a claim about
the language, and until now the compiler has discharged it above MIR: the
checker refuses what cannot be given a meaning, and the ownership pass refuses
what cannot be given a lifetime. Below MIR nothing asks anything. No pass, no
test and no tool in this repository asks whether an emitted load, store or blit
lands inside the object it names.

The gap is not theoretical, and it is not narrow. A twenty-line well-typed
program returns 99 where 1 is correct, because a function returning an
aggregate through `return` takes its QBE return type from the body block rather
than from the declaration, so the caller is handed the address of a frame that
has ended. A `Maybe[()]` stores eight bytes at offset eight of an eight-byte
object, because a zero-width part takes the scalar path and every width outside
one, two and four is written as a word. Both programs compile, both link, and
both are accepted by a green suite. A program whose meaning the language
defines was given a different one by the code that emitted it.

What carries those invariants today is `std.debug.assert` — every block has a
terminator, a terminator is the last instruction in its block, an aggregate's
alignment is at most sixteen. `build.zig` makes ReleaseFast the distributed
mode, and ReleaseFast deletes every one of them, along with the slice bounds
checks that would otherwise catch what follows: with the terminator assertion
gone, the emitter indexes an instruction array at `0xFFFFFFFF`. The invariants
are enforced in the build nobody ships and unenforced in the build everybody
runs. The conformance corpus does not close that, because it is built at the
ordinary optimisation level rather than under ReleaseSafe, so those assertions
are exercised in Debug only.

Every runtime answer to this was measured, and every one is worse:

| approach | why not |
| --- | --- |
| a sanitizer on the link | Provably vacuous. ASan's stack checking is emitted *into* the function by the compiler: a C frame-overflow translation unit carries fifteen `__asan_*` symbols and QBE's `_main` carries none, so there is nothing for the runtime to consult. The same law covers `-fstack-protector-all`, `-fsanitize=undefined`, `-fsanitize=bounds` and `-D_FORTIFY_SOURCE=3` — every `-f*` hardening option is translation-unit code generation, and QBE's assembly is not a translation unit `cc` compiles. All four return the wrong answer undetected on the reference defect, and ASan additionally deadlocks before `main` on the platform the compiler is developed on. |
| ARM MTE | `FEAT_MTE` reads zero; no Apple silicon implements it. |
| `DYLD_INSERT_LIBRARIES` | A Linea binary imports four symbols and has no heap. Frame accesses are raw loads and stores with no call to interpose. |
| valgrind under emulation | Memcheck's model is addressability, and two slots in one frame are both addressable stack. It would catch a store past the whole stack and nothing else, for the price of an emulated lane. |
| differential execution against the evaluator | There is no evaluator. It was deleted in Stage 2b. |

The measurement that decides the shape: the language has no arrays, and
lowering emits every field offset as a constant read from the layout table, so
**every address in a Linea program is the address of a local plus a
compile-time constant.** Bounds checking is therefore a forward dataflow with
an exact abstract domain, not an approximation of one. A prototype proved 92.5%
of 1808 memory operations across 153 compiled programs in bounds in 0.069
seconds, with no false positives, and reported every injected wrong-offset,
wrong-width and wrong-blit-size fault.

## Decision

**A module is verified before any backend may emit it, on every compile, and
the backend is what performs the verification.**

`src/mir/verify.zig` consumes a `*const Module` and a diagnostic sink and
answers whether the module satisfies what emission assumes:

```zig
pub fn verify(gpa, module: *const Module, sink: *Sink) std.mem.Allocator.Error!bool;
```

**`src/backend/qbe.zig`'s `emit` calls it, first, itself.** Not a build mode,
not a `-D` flag, not an assertion a release build deletes, and not a call in
the driver. Emitting is the thing that must not happen unverified, so the check
lives inside the function that emits: a precondition placed in the function it
is a precondition of cannot be skipped by anyone who does not edit that
function. `emit` pays a `gpa` and a `*Sink` for it, and gains a way to write
nothing and say why. Its three callers — the driver's build path, the driver's
`emit-ir` dump, and the conformance runner — already hold both. It still
allocates only from the allocator it is handed and installs nothing, so
[0016](0016-passes-are-functions.md) is undisturbed.

**A token type was priced first and does not work in this language.** A
`Verified = struct { module: *const Module }` returned by `verify` and taken by
`emit` reads like a proof obligation, but Zig has no private fields:
`emit(w, .{ .module = &m }, &t)` compiles, and it is *shorter* than calling
`verify` first. Such a signature documents the obligation without enforcing it,
which is precisely the failure this record exists to prevent — a check everyone
believes is running. See *Alternatives considered*.

Nothing new is introduced under 0015 either way. The verifier holds no data
between calls, discards nothing, adds no node a side table could not key, and
answers no question `Module` does not already answer. It is a precondition, not
a representation.

What it checks, all relative to the layout table the module already carries:
an access lies within the object it names; an offset is a member offset of the
type it is taken from and the consuming width is that member's size; every type
reaching the backend has a layout entry; no frame address escapes as a value;
every block has a terminator and terminators are where they belong; every local
is written on every path that reads it; and an access is aligned as
[0031](0031-fields-are-packed-at-their-natural-alignment.md) requires.

**It reports without a rule code.** `src/diagnostics/diagnostic.zig` carries a
test that fails for any code the semantics document does not define, and a user
cannot provoke one of these — every input reaching the verifier has already
been accepted by every rule the document states. A violation is an uncoded
error naming the function, the instruction and the span, said plainly to be a
compiler defect, under a driver exit status reserved for it.

## Consequences

**A pass that can be skipped eventually is, which is why this one is not
skippable by omission.** Every path that emits runs it, because emitting is
what runs it. What the placement does *not* buy is a compile error for a
future backend that never calls `verify` at all — no arrangement available in
this language buys that, and the record says so rather than implying otherwise.
What it buys instead is that the omission cannot be accidental: a new backend
that emits unverified code is a diff with no `verify` call in it, and an
existing one is made unsafe only by deleting a line from the function that
would be wrong without it.

**The corpus verifies every case for free**, including the ones with no golden.
The conformance runner drives the emitter for every case it accepts, so the
verifier also runs over every metamorphic rewrite and every generated program,
where a violation is a failure by the rule that already governs those.

**The emitter's arithmetic must have one home first.** A verifier that restates
how a slot is sized or how a width is picked is a second copy of the emitter,
and the two drift silently — which is the failure this pass exists to prevent,
one level down. So slot sizing and access widths move into `src/mir/` beside
the verifier and the backend calls them
([0052](0052-a-slot-is-as-wide-as-the-widest-access-to-it.md)). That
prerequisite is why the pass lives under `src/mir/` rather than under
`src/backend/`.

**Three silent fallbacks become errors.** The emitter answers "a scalar in a
register" for a type index outside the layout table in three places. For a
24-byte structure that means an eight-byte slot and sixteen bytes written past
it: a guard that converts a crash into a miscompile is the wrong guard. The
layout-cover check is what makes deleting them safe, and the cover is complete
today by ordering rather than by construction, which
[0047](0047-instantiation-is-a-backend-concern.md) makes fragile — a pass
interning a type after lowering has allocated the table is the natural next
change.

**Cost.** One linear pass over instructions plus a bitset fixpoint over blocks.
Two arrays per function from the caller's allocator, freed on the way out.
Measured at 0.069 seconds for 153 programs over emitted IR, and strictly
cheaper over MIR, where addresses are typed. **Nothing reaches a shipped
binary.** `build.zig` requires that no sanitizer runtime end up inside a binary
a user ships; this respects that by having no runtime component at all.

**What remains undetected, stated so the record does not claim more than the
mechanism delivers:**

- **QBE's own code generation.** This verifies the IR the compiler wrote, not
  the machine code QBE produced. A register-allocation or frame-layout bug in
  QBE is out of reach of every option weighed here.
- **Whether an address arriving through a parameter points at a live object.**
  That is the caller's obligation, discharged by the call-argument check
  transitively over the module and by `[O-Move]` above MIR.
- **Byte-level initialisation within an aggregate.** A slot counts as written
  the moment its address is taken. Filling one variant's payload and blitting
  the whole width is in bounds and not tracked byte-wise. A different analysis,
  and not needed for the bounds property.
- **The layout table itself**, which every check here is relative to. That is
  the one input with no second opinion, and it is why
  [0050](0050-the-layout-rule-has-a-second-implementation.md) exists.
- **Stack exhaustion.** A whole-program property, not a per-access one, and
  today an undiagnosed abort.
- **A trap status colliding with a status the entry point may return.** Above
  this pass entirely.
- **Everything the backend decides that no instruction stands for.** This
  verifies instructions, so what the emitter writes on its own authority is
  outside it, and a fault injected into any of the three below builds cleanly
  and answers wrongly:
  - the QBE aggregate type definition, whose width is what a caller copies a
    returned aggregate out by;
  - the function prologue -- slot allocation, the per-parameter store or blit,
    and the jump to the entry block -- emitted from the local list rather than
    from instructions;
  - a by-value aggregate argument, which is passed as an address and blitted by
    the callee though the parameter is not one the call-argument check reaches.

  The first two are held right by reading the same table and the same slot rule
  the checks read, so there is no second decision to drift -- which is a weaker
  guarantee than a check and is worth naming as one.

## Alternatives considered

**A sanitizer on the link.** The first thing anyone reaches for, and it is
provably vacuous rather than merely weak — see the table above. It also reaches
further than expected: the flag is appended to the link of every generated
program, so it is not inert-and-harmless but inert-and-hanging.

**Emit C for a checking build.** A second backend over the same
already-monomorphised MIR would give real ASan — reads and writes, adjacent and
far, through pointer parameters — for roughly 860 lines plus a second toolchain
path, and it would double as 0050's oracle. Rejected as a first move on the
permanent cost: a second backend must stay behaviourally identical to the QBE
one forever, or the checking build stops speaking for the shipping build. It
also cannot run on the development machine. Revisit only if this record and
0050 leave a demonstrated gap.

**A checked interpreter over the QBE IR.** Adds only the roughly 7.5% of
accesses a static pass skips, costs an order of magnitude more to build, and
introduces a *third* definition of what a program means — QBE, the interpreter,
and the machine — which someone must then adjudicate.

**Backend-emitted redzones.** Prototyped, and they work: a magic word after
each aggregate slot, verified before every return, routed to the existing trap.
They caught the reference defect that ASan, stack-protector, UBSan and FORTIFY
all missed, and they add no new runtime symbol, so unlike a sanitizer they are
not barred from being always-on. Rejected as the primary answer because they
provably miss far stores and every read, and because a static pass proves the
same class rather than sampling it. Kept as a fallback if the interprocedural
parameter contract proves harder than expected.

**Assertions, kept, and a debug-only build that runs them.** The cheapest
option and the one already in place. It fails on the mode: the assertions exist
in the build that is never distributed and are deleted from the one that is,
which inverts where checking is wanted. Making the release build keep them is
the same decision as this record with worse ergonomics — an assertion aborts
with a Zig panic rather than naming a function and an instruction, and it
cannot be a precondition of anything.

**Platform tools** — MTE, library interposition, guard pages per slot,
debugger watchpoints, emulated valgrind. Measured, and each is impossible,
wrong-granularity, or a debugging aid for after something else has named the
slot.

Two further alternatives are about *where* the check goes rather than what it
checks, and both were priced against the placement above.

**A token type: `verify` returns `Verified`, `emit` takes one.** The prettiest
answer, and the one this record carried in draft. It fails on a language fact:
Zig has no private fields, so `Verified` is a struct anyone can build. Measured
directly — a three-line program with `const Verified = struct { module: *const
Module };` and `emit(.{ .module = &m })` compiles and runs. Worse than
useless: forging the token is *shorter* than calling `verify`, so the shortcut
is also the path of least effort, and the type's presence in the signature is
what would stop anyone from noticing. A type can carry an obligation in a
language with a private constructor. This is not one, and pretending otherwise
retires the guarantee while looking like it establishes it.

**A call in the driver, between lowering and the backend.** Where a pipeline
stage naturally goes, and it is not what this record decides. Two reasons.
The driver is not the only caller: `emit-ir` and the conformance runner reach
the emitter directly, so a driver call would verify the path a user compiles
and skip the path 418 corpus cases and every generated program exercise —
exactly backwards, since the corpus is where a violation is *found*. And a
precondition in the caller is a convention: it is discharged correctly by
everyone who remembers, which over time is not everyone. Inside `emit` there is
nobody to remember.

**Leave it to the corpus: a verifier on every compile taxes every user for a
bug class a test suite could catch.** This is the strongest counter and it
fails on three counts.

First, the corpus demonstrably did not catch it, and for one class it *cannot*.
An assignment whose copy width is taken from the right-hand side rather than
from the destination has no repro writable in the source language, because the
checker guarantees the two types are equal. It becomes reachable the moment a
compiler change breaks that guarantee — which is precisely when nobody is
looking for it. A suite can only fail for a program someone can write.

Second, the tax is not on the user. Zero at run time, nothing in the binary,
and a fraction of a lexer pass at compile time.

Third, and decisively, a check that runs only in the corpus is a check the
shipped compiler does not make. The corpus establishes that the compiler was
right about 418 files on the day it ran. A precondition establishes that it is
right about the file in front of it. Those are different claims, and the second
is the one a user needs. Where a corpus is genuinely stronger is at *finding*
defects in what the verifier takes on faith — which is why 0050 and the
metamorphic properties are not replaced by this record but pointed at the gap
it names.
