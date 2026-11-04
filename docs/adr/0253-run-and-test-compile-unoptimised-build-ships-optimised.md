# 253. `run` and `test` compile unoptimised; `build` ships optimised

Status: Accepted — 2026-11-03. Builds on
[0090](0090-the-backend-is-mlir-printed-rather-than-constructed.md), which
hands `cc` the translated IR at a stated level, and
[0091](0091-the-optimiser-is-given-proofs-not-premises.md), which makes every
level compute the same answer.

## Context

Every command that compiles used one default level, `-O2`. A build is the
frontend, `mlir-opt`, `mlir-translate`, then `cc` compiling the LLVM IR and
linking it, and `cc` is most of the time: `examples/http-json-echo` spends 3.1 s
of its build compiling the IR at `-O2` and 0.43 s at `-O0`, with 0.16 s to
link. `linea run` and `linea test` rebuild on every edit, so the edit-run loop
paid for the optimiser each time it ran a program for a few milliseconds.

The level never changes what a program does. The emitted module carries no
wrap flags, aliasing metadata or fast-math
([0091](0091-the-optimiser-is-given-proofs-not-premises.md)), and the
conformance runner's `-Dopt-levels=true` holds every corpus case to the same
exit and output at every level. Choosing a level is a choice of build time
against run time and nothing else.

Measured with a ReleaseFast compiler on an Apple M-series machine, best of
three builds and five runs, `linea build <example> -O <level>`:

| Program | build `-O0` | build `-O1` | build `-O2` | run `-O0` | run `-O1` | run `-O2` |
| --- | --- | --- | --- | --- | --- | --- |
| `hello.lin` | 0.52 s | 0.57 s | 0.59 s | 4 ms | 4 ms | 4 ms |
| `prime_sieve.lin` | 0.52 s | 0.60 s | 0.61 s | 4 ms | 3 ms | 4 ms |
| `knight_moves.lin` | 0.56 s | 0.65 s | 0.67 s | 4 ms | 5 ms | 5 ms |
| `tournament_board.lin` | 0.54 s | 0.63 s | 0.63 s | 4 ms | 4 ms | 4 ms |
| `frequency_report.lin` | 0.80 s | 1.07 s | 1.17 s | 4 ms | 4 ms | 5 ms |
| `json_inventory.lin` | 1.10 s | 1.52 s | 1.55 s | 5 ms | 4 ms | 5 ms |
| `bounded_echo.lin` | 1.13 s | 1.96 s | 2.14 s | | | |
| `http-json-echo` | 2.60 s | 4.48 s | 5.05 s | | | |
| `prime_sieve.lin`, limit 50 000 000 | | | | 1.50 s | 0.29 s | 0.20 s |

The two servers are built and not timed running. The last row is the sieve
with its largest limit raised, a program that does nothing but compute.

`linea test <example> -O <level>`, building the test binary and running every
test, best of three:

| Program | `-O0` | `-O2` |
| --- | --- | --- |
| `prime_sieve.lin` | 0.62 s | 0.69 s |
| `json_inventory.lin` | 1.34 s | 1.78 s |
| `bounded_echo.lin` | 1.30 s | 1.96 s |
| `http-json-echo` | 3.30 s | 3.69 s |

A test binary holds only what the tests reach, and running the tests is part
of the time, so the saving is smaller than a full build's.

## Decision

**`linea build` compiles at `-O2` when no level is named; `linea run` and
`linea test` compile at `-O0`.** `-O` names a level on each of the three, and
`test` gains the option it lacked. `dump-asm` prints what a build ships, so it
keeps `-O2`.

`-O0` is chosen over `-O1` because `-O1` saves almost none of the time the
split exists to save. On the large programs it compiles in 89 % (`http-json-echo`)
and 92 % (`bounded_echo`) of the `-O2` time; `-O0` takes 52 % and 53 %. What
`-O0` gives up is run time on code that computes: the long sieve runs five
times slower than at `-O1`. A program that runs for milliseconds, which is what
a run after an edit or a test usually is, does not notice.

The toolchain names the two defaults, `build_level` and `run_level`, and the
driver picks one by command. The level is still always stated to `cc`, so a
`CFLAGS` in the environment or a wrapper's own default cannot choose it.

The conformance runner builds every corpus case at `corpus_level`, which is
`build_level`: a recorded outcome is the program `linea build` ships, and the
outcome cache keyed by level keeps every recorded outcome. `-Dopt-levels=true`
covers `-O0` with the other levels.

## Consequences

- A large program reaches its first line of output in about half the time
  under `linea run`, and `linea test` builds its test binary as fast.
- A program run with `linea run` is not the program `linea build` makes. They
  compute the same answer, which `-Dopt-levels=true` checks, but a program
  that computes for a long time runs several times slower under `run`;
  `linea run -O 2` gives the built program's speed.
- A test that times itself, or a benchmark written as a test, measures
  unoptimised code unless it is run with `-O 2`.
- The corpus is built at a level `run` does not use by default. A defect that
  shows only at `-O0` is caught by `-Dopt-levels=true` and the soundness step,
  not by the default walk.

## Alternatives considered

**`-O1` for `run` and `test`.** It keeps nearly all of `-O2`'s run time on
computing code, but it is nearly all of `-O2`'s build time too: the measured
saving is 7 to 11 % on the large programs, against 47 to 48 % for `-O0`. It
would trade almost all of the run time for almost none of the build time
the change is for.

**One default for every command, lowered to `-O0`.** A built program is what
ships, and it is built once and run many times. Making `build` unoptimised by
default would ship slow programs to everyone who did not know to ask.

**Keep `-O2` everywhere and make the toolchain faster.** `cc`'s optimiser is
the cost, and nothing the compiler emits removes it while `cc` is asked to
optimise. Emitting less IR helps every level and is separate work.

**Build the corpus at `run`'s level.** It would make the default walk check
what a developer runs, and it would change every recorded outcome's cache key
at once. The corpus records what ships; `-O0` stays covered by
`-Dopt-levels=true`.
