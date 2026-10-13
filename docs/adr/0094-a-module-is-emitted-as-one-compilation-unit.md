# 94. A module is emitted as one compilation unit

Status: Accepted — 2026-08-18

Supersedes [0074](0074-a-module-is-emitted-as-several-compilation-units.md),
which split a module's emitted IR into several units so `qbe` and the
assembler could run concurrently on each.

## Context

0074 bought its speedup from the shape of the retired toolchain: `qbe` and
`cc -c` were serial, per-function work with no dependency between functions,
so splitting one `.ssa` stream eight ways cut 4.29s to 1.34s on a module of
30,001 functions. The partition was never observable — it existed between the
emitter and the toolchain and nowhere else.

The toolchain those numbers were measured on is gone
([0090](0090-the-backend-is-mlir-printed-rather-than-constructed.md)). What
replaced it changes both halves of the trade:

- There is no assembler step to parallelise. `cc` takes the translated LLVM
  IR as an input language and goes to an executable in one invocation.
- The stage that does per-function work — `mlir-opt` — runs its passes over a
  module's functions on a thread pool of its own. The concurrency 0074 built
  by splitting files and spawning processes is the tools' default behaviour,
  inside one process, with no visibility mechanics to get right.

What remained of 0074 in the tree was `src/backend/partition.zig`: the
exported-set computation, reachable only from its own tests. A mechanism whose
tests are its only caller is a mechanism the tests keep green against nothing
— the code could be wrong about the current backend in every way that matters
and no case could say so.

## Decision

**A module is emitted as one MLIR unit, and the partitioner is deleted.** The
emitter writes one stream; the toolchain runs each tool once over it; the
tools own whatever concurrency the work admits.

The visibility scheme 0074 needed — export what crosses a unit, hide it in
the final image — goes with it. With one unit there is no crossing reference,
so a symbol's visibility is what the source implies and nothing more.

## Consequences

- The build has one fewer decision in it: no unit count to choose, no
  exported set to compute, no platform visibility directive to spell.
- If per-unit parallelism is ever worth reopening, it is a new record argued
  against what the tools already parallelise, measured on this toolchain —
  0074's numbers say nothing about it. The measurement that would open it is
  0074's own, rerun: one many-function module (the sweep's declarations
  generator emits the shape) through the whole pipeline, one module against
  the same IR split, because a single enormous module also concentrates
  parsing, symbol-table and memory costs that many small ones spread.

## Alternatives considered

**Keep `partition.zig` for the day emission is split again.** Rejected: the
unit-crossing question it answers is defined by the backend that asks it, and
the backend that asked is deleted. Code kept for a future decision encodes
the old decision's assumptions into the new one before it is made.

**Partition the MLIR stream the way the `.ssa` stream was partitioned.**
Rejected on 0074's own measurement discipline: the serial stages that made
splitting pay do not exist in this toolchain, and `mlir-opt` already walks
functions concurrently, so the speedup would have to be demonstrated before
the mechanism is rebuilt — and no measurement has asked for it.
