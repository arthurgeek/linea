# 90. The backend is MLIR, printed rather than constructed

Status: Accepted — 2026-08-18; extended by 0116. Proposed 2026-08-17; accepted when everything
*What acceptance requires* names came to hold, recorded there.

## Context

The backend prints text and shells out. `src/backend/qbe.zig` writes QBE IR
through a `*std.Io.Writer`, and `src/driver/toolchain.zig` spawns `qbe` and then
`cc`. That shape is not incidental — it is what lets three invariants hold
across the seam between the compiler and the machine.
[ADR 0012](0012-immutable-representations.md) holds because the output is a
value rather than a structure someone mutates.
[ADR 0016](0016-passes-are-functions.md) holds because emission is a function
from a module to that value.
[ADR 0049](0049-generated-code-is-verified-before-it-is-emitted.md) holds because
the verifier runs inside emission, so a module the backend refuses gets its own
exit status rather than the one a rejected program gets.

QBE is a small scalar SSA backend for CPUs. It has no vector representation and
no target other than a CPU, by design, and that is most of why it was a good
choice: its IR is small enough to treat as an output format rather than as a
data model.

Two things now want what it does not have. A first-class vector type needs a
representation with vectors in it. A second compilation target needs address
spaces and a lowering that ends somewhere other than a host CPU. Neither is
reachable by writing more QBE.

The question is therefore not *whether* the backend moves but *what it moves to*
and — separately, and more consequentially for this compiler — *how the new
output is produced*.

## Decision

**The backend targets MLIR, emitting `func`, `cf`, `arith` and as much of `llvm`
as raw memory requires, as pretty-form textual assembly, and shells out to
`mlir-opt` and `mlir-translate`. It does not construct a module through a
library.**

The `llvm` clause is not a concession. A frame slot is `llvm.alloca` over
`!llvm.ptr`, because what the module says about a local is a size and an
alignment and no dialect above LLVM carries less than that. Emitting *only* the
three higher dialects would mean inventing shape information the module never
had.

Three parts, and the second is the one that matters most here.

### MLIR rather than QBE or LLVM

Recorded plainly, because the record should not claim more than it bought:
**MLIR's entire marginal purchase over textual LLVM IR is a second target, and
the second target meant here is a GPU.** LLVM IR has first-class vector types
and has had them for as long as it has existed, so a vector type reaches machine
vectors through either. This decision is not justified by CPU vectors and does
not claim to be.

**What LLVM lacks is not the concepts but the infrastructure**, and the
distinction matters because the weaker claim is the one that survives a reader
who knows LLVM. Address spaces are first-class in LLVM IR — they are a numeric
attribute on a pointer type — and LLVM has GPU targets with kernel calling
conventions. What it does not carry is a dialect-level abstraction for
*heterogeneous* programs and a conversion ecosystem that lowers one into the
other: expressing a kernel, a launch and a memory space at a level above the
target, and lowering progressively. Through LLVM alone, that structure is
written by hand once per target; through MLIR it is a lowering that already
exists.

If a GPU target is never built, this decision bought a heavier toolchain and
nothing else. That is the honest statement of the bet.

### Printed rather than constructed

MLIR offers a C API, and a Zig compiler can call it. Doing so would mean
emission stops being a function that produces a value and becomes a procedure
that drives a stateful builder over a long-lived mutable module — which is
[0012](0012-immutable-representations.md) and
[0016](0016-passes-are-functions.md) at once, and it would import MLIR's own
type system and verifier as things to reconcile `module.layouts` against.

Printing text keeps all three invariants untouched, keeps the emitted IR
golden-diffable, and keeps the compiler's dependency on MLIR at the level of two
executables rather than a linked library.

**MLIR is an output, not a representation this compiler owns.** MIR remains the
last representation Linea owns, and nothing downstream of the printer is a place
a Linea pass may run. That sentence is the door this record closes: MLIR is
built to *be* a mid-level representation, and a compiler that lets it become one
acquires a second IR that its own passes manipulate, which is
[0015](0015-when-to-introduce-a-representation.md)'s question answered by
accretion rather than by argument. Printing rather than constructing is what
makes the boundary structural instead of a matter of discipline — a text file is
not something a pass can be tempted to walk back into.

### The pipeline

Stated as a shape rather than as a pass list, because the pass list is
implementation and will move:

```
MIR ─→ [Linea prints]  func / cf / arith / (memref)
    ─→ [mlir-opt]      dialect conversion to the LLVM dialect
    ─→ [mlir-translate] textual LLVM IR
    ─→ [cc]            assembly, linking against runtime/linea_rt.c
```

`cc` remains what it is today — the driver that produces the executable and
links the runtime — so `src/driver/toolchain.zig` gains two tool invocations
ahead of it rather than a different final step.

**Verification is Linea's, and it stays where 0049 put it.**
[ADR 0049](0049-generated-code-is-verified-before-it-is-emitted.md) is about
Linea verifying its own module *inside* emission, so that a module the backend
refuses gets its own exit status rather than the one a rejected program gets.
That is unchanged and does not become `mlir-opt`'s job: a verifier running in
another process, after emission, cannot give a distinct exit status to a module
this compiler should have refused. `mlir-opt`'s verifier is a second net over
the printer's own correctness, and a failure there is a compiler bug rather than
a diagnosis.

### `func`, `cf`, `arith` — and pretty form

MIR's control flow is already explicit
([ADR 0022](0022-mir-is-explicit-control-flow.md)): blocks with terminators, and
an edge table in `src/mir/edges.zig`. The `cf` dialect is that same shape —
basic blocks with successors — so the mapping needs no restructuring pass.

Emitting above the LLVM dialect is what makes the conversion passes do work and
what leaves a second target a lowering rather than a rewrite. Emitting the LLVM
dialect directly would reduce `mlir-translate` to a near-identity and give up
the only thing MLIR was chosen for.

Assembly is emitted in **pretty form**, not generic form. Generic form is more
stable across releases because it does not route through per-dialect printers;
pretty form is legible. Legibility wins because a generated golden is evidence
only if someone read it, and this project's whole method is that a claim about
behaviour is worth what a case says about it. The stability cost is bounded by
the toolchain being pinned in `flake.nix`, so a format change is an event
someone scheduled.

**Pretty where a pretty form exists, generic where none does.** Not every
operation has a custom assembly form: an `llvm.intr.*` intrinsic is spelled
`"llvm.intr.uadd.with.overflow"(%a, %b) : (i8, i8) -> !llvm.struct<(i8, i1)>`
and is refused in any other spelling. So the decision above is a preference the
emitter applies where it can rather than a property the output has everywhere,
and a module mixes both forms. This was found by running the pipeline rather
than by reading about it, which is why it is recorded here instead of being
discovered by whoever writes the emitter.

**An MLIR golden is a representation golden, not a semantic contract.** A
toolchain bump may change every one of them without any program's meaning
changing, which is why such a bump obeys the standing rule that a commit
changing a dump format changes nothing else. What guards behaviour across that
bump is the recorded exit statuses, not the shape of the IR beside them.

**`memref` is provisional, and the test is stated rather than left to
judgement.** It carries a layout map — strides, offsets, identity and otherwise
— built for buffer and tensor work, and Linea's memory is a linear handle over a
flat integer address.

> `memref` is emitted only where its representation carries information a
> lowering requires and MIR does not already express. Where it does not, the
> backend emits a pointer and explicit offset arithmetic.

That is [0015](0015-when-to-introduce-a-representation.md)'s test applied to a
dialect rather than to a representation of our own, and it is phrased so the
eventual answer is decidable by inspection rather than by taste. Dropping
`memref` supersedes nothing, because this clause says so in advance.

**The test splits along a seam, and half of it is permanent.** For the interior
of an aggregate the answer is no at any date, for two reasons that do not age:
a variant's payloads share bytes
([ADR 0030](0030-a-variant-carries-several-values.md)), which is type punning by
design and the thing `memref`'s type discipline exists to forbid; and `memref`'s
lowering computes address arithmetic by its own rules, which would make it a
second computer of the layout table's one answer
([0031](0031-fields-are-packed-at-their-natural-alignment.md),
[0048](0048-one-question-has-one-answer.md), [0052](0052-a-slot-is-as-wide-as-the-widest-access-to-it.md))
— disagreeing, if ever, exactly on the program nobody wrote. For a buffer of one
scalar element type both objections vanish, because the stride of a scalar is
its size under any computer of it, and that is the one place the test may
someday pass — a target whose lowering requires shaped, address-spaced buffers,
scoped to the functions it compiles.

**A backend renders layout; it never decides it.** Layout is consumed upstream
of any backend: lowering bakes the table's offsets into MIR as constants, the
checks that make every access defined are arithmetic over those numbers, and
[0049](0049-generated-code-is-verified-before-it-is-emitted.md)'s verifier
refuses a bad address before emission — none of which is possible over numbers a
backend has not yet chosen. Two targets sharing one buffer's bytes need one
answer: a value the host writes and a device reads is a single layout with two
renderers. And where layout is observable through byte access — an element read
out of raw storage through `std.mem` — a delegated layout would let a toolchain
bump change what a program computes, which is meaning depending on how the
program was compiled, and forbidden as such. This is also every mixed-target
language's position, including the ones that look like they delegate: a C
compiler computes union layout itself because LLVM has no unions, and SPIR-V
requires the frontend to compute every member offset and write it explicitly —
the delegating option does not exist even where it appears to.

## Consequences

**The emitter is replaced, not adapted.** `src/backend/qbe.zig` is 1,982 lines
of QBE-specific printing. What survives the move is its structure — one function
per MIR function, one block per MIR block — and not its output.

**A pure backend change reports nothing new, so there is no case to write. What
stands in for one is differential — but only over behaviour.** The old binary
and the new run over every `.lin` under `tests/`, comparing **exit status,
stdout and stderr**. Emitted IR is deliberately *not* in that comparison: QBE IR
and MLIR are different representations, so equality between them is not a
property that could hold, and demanding it would be demanding the migration not
happen.

The representation is checked separately and by a different mechanism: the MLIR
output gets its own generated goldens, read and accepted the way every golden
is. **Semantic equivalence is differential; representation correctness is
golden.** Conflating them is what makes a migration's acceptance criterion
unsatisfiable.

The differential half needs a corpus nothing else is moving, which is the
argument for this landing before any language work rather than beside it.

**The toolchain grows, and by less than it looked.** QBE is a small C program
that builds in seconds. `llvmPackages.mlir` is 21.1.8 with an **807 MiB
closure**, and it resolves from the binary cache prebuilt, so there is no LLVM
build to wait for — against a shell that already carries LLVM, because
`clangStdenv` is what puts `cc` on `PATH`. The incremental cost is a download.

This still lands on the clean-machine criterion of the bar set for the first
public version (a newcomer can write a program that reads input, holds it in a
container, parses it, produces JSON and serves it over a socket, with every
leak refused at compile time, with the bar's steps numbered as rungs; a machine with none of Linea's toolchain
installed must reach a running program by the documented steps) — but it is not on its own an argument that a prebuilt binary
path becomes required rather than optional. Whether it does is a question about
what a stranger is willing to download, which is answered by the install path
and not here.

**The outcome cache already answers for this.** Recorded exit statuses are keyed
by the emitted IR *and* by a stamp of every tool a build runs, precisely so a
compiler or linker moving under an unchanged program cannot serve a stale
recorded status. A toolchain bump invalidating recorded output is an existing
decision working, not a new cost.

**A golden format change churns the whole corpus**, so it obeys the standing
rule: a commit that changes a dump format changes nothing else.

## What acceptance requires

Three things were required, and each came to hold:

- **The differential passed.** Every case under `tests/` — 1396 of them — and
  every example ran through both backends with exit status, stdout and stderr
  byte-identical, and the full suite ran green with the new backend as the
  default. The emitted MLIR carries the corpus's IR goldens.
- **`backend/qbe.zig` is retired.** The window in which two backends existed
  was the window built to compare them, and once the comparison had passed on
  everything there was to compare, a second backend was a cost buying nothing:
  the differential is not rerun against a backend that no longer moves. The
  `--backend` flag left with it.
- **`memref` did not earn its place**, and the implementation is the evidence:
  every access the corpus exercises is a flat address, an offset the layout
  table computed, and a width it stated. Nothing needed a layout map, so the
  backend emits `!llvm.ptr` and explicit arithmetic, exactly as the provisional
  clause said it would. The clause stands for any future target whose lowering
  requires more.

Two residuals worth recording. The trap paths and check expansions make the
printed form verbose; the renderer-level economies that would tighten it — a
name-alias table for a check's pass-through, a per-function constant cache —
are deliberate follow-ups, each a dump-format commit of its own, because the
migration's acceptance test was faithfulness and a clever emitter is harder to
hold to that. `mlir-opt` runs conversion passes only; `cc` compiles the
translated IR at a stated `-O2`, which
[0091](0091-the-optimiser-is-given-proofs-not-premises.md) makes safe by
construction — the module hands the optimizer no premise to exploit — and
which the differential exercised throughout, because the pinned shell's
compiler wrapper had been injecting the same level silently. So the emitter's
storage shape is an IR-quality question, not a shipped-code one: the
optimizer promotes the slots and drops the identities, and the residual is
what a reader of the emitted module wades through.

A third residual, and the sharpest: what this decision was bought for is not
yet reachable from what the emitter prints. The GPU purchase assumes emission
above the LLVM dialect that a `gpu` or `spirv` conversion could consume, and
rung 0's emitter deliberately does the opposite — every value erased to the
word, every slot an `llvm.alloca` of raw bytes, every address an integer
round-tripped at the access. No GPU conversion lowers that. Reaching the
purchase therefore requires a typed-value emission mode — MIR's value model
decided first, which is also what rung 13's lanes need — and until that
decision is made, this record's honesty clause describes the present: the
heavier toolchain is paid for and the dialect ecosystem is not yet consumed.
The GPU or vector rung that starts this work starts with that decision, not
with the emitter.

## Alternatives considered

**Stay on QBE.** The lightest option, and it gives up nothing until something
needs a vector or a second target. It loses because both are now wanted, and
because the cost of moving grows with every rung built on the old backend — a
rung built on one backend and moved to another is verified twice, and the second
time a failure is attributable to either.

**Classic LLVM, printed as textual `.ll`.** This is the closest alternative and
it nearly wins. It keeps the print-and-shell shape exactly as MLIR does, it is a
far smaller dependency, and it delivers CPU vectors, which is the larger half of
what is wanted. It loses on one thing only: a GPU target through LLVM means
targeting NVPTX or AMDGPU directly and writing, per target, the kernel and
launch structure and the address-space discipline that MLIR carries as dialects
and conversions. LLVM can express all of it — this is a question of what has to
be built, not of what can be said. **If the GPU target is ever abandoned, this
is the decision to revisit**, and this paragraph is here so that
revisiting it is a supersession with an argument already written rather than a
rediscovery.

**LLVM through its C library.** Rejected for the reason the decision gives: a
stateful builder over a live module is [0012](0012-immutable-representations.md)
and [0016](0016-passes-are-functions.md) at once. It would also introduce a
representation between MIR and machine code that this compiler neither owns nor
controls, which [ADR 0015](0015-when-to-introduce-a-representation.md) governs.

**A dialect of Linea's own**, with checked arithmetic, addressing and calls as
operations that lower through MLIR to the LLVM dialect. This is the shape the
tiering argument wants, and it is not reachable from this decision. MLIR accepts
an operation only where the tool processing it has that dialect registered, and
stock `mlir-opt` knows the dialects compiled into it. A `linea` dialect
therefore means TableGen definitions, C++ registration and a `linea-opt` binary
linking libMLIR — which is the library this record rejects, reached through a
different door, and a second tool to build and ship besides.

The boundary the tiering wants is real and it already exists: it is MIR. Linea
semantics stay explicit in the output by being spelled out — a range test and a
conditional branch, exactly as the module specifies them — rather than by being
folded into an operation only a custom tool could read.

*(The `linea.unimplemented.*` operations a partial emitter prints use the same
mechanism deliberately in reverse, and it is worth stating precisely why it
holds. MLIR does not refuse an unregistered operation as such — it refuses one
unless it is told to permit them, and `--allow-unregistered-dialect` is how it
is told. Verified: `mlir-opt` exits 1 on such a module and 0 with that flag. So
the tripwire is a property of the invocation contract rather than of MLIR, and
the invariant is therefore **the pipeline never passes that flag**. A build that
did would accept an unlowered instruction, emit nothing for it, and produce a
program missing the work.)*

**MLIR bytecode.** Rejected on three grounds, any one sufficient. Its op, type
and attribute encodings are versioned, so a hand-written writer tracks a moving
target. There is nothing to golden-diff, which removes the conformance suite's
grip on what the backend produces. And producing it properly requires MLIR
in-process — at which point the question is the C API and not the format.

**`scf` rather than `cf`.** Structured control flow would mean re-structurizing
a CFG that lowering has already flattened: a real pass, running against the
direction of the pipeline, to recover a shape MIR deliberately discarded.

**Generic assembly form.** More stable across releases, and rejected because
goldens are read. A corpus nobody can review is a corpus that records what the
code does without anyone having confirmed it should.
