# 205. Passes run on a stack sized for the nesting limit

Status: Accepted — 2026-10-04

Refines [0003](0003-infallible-frontend.md): the frontend never fails, and a
tree the parser admits must not overflow the stack of the pass that walks it.

## Context

[S-Nesting] bounds the height of the tree the parser hands on at 1000 levels,
so that every later pass, which recurses over the tree, has a depth the same
in every build. The bound was chosen an order of magnitude below where a stack
runs out, but a Debug frame of the checker is far larger than an optimised
one. A tree within the bound overflowed the 8 MiB main stack at about 815
nested lambdas, 460 chained selections and 975 nested `for` loops, and the
overflow was a segmentation fault instead of a diagnostic.

## Decision

**The driver, the language server and the conformance runner run the passes on
a thread whose stack is `compiler_stack_bytes`, 256 MiB**, in
`src/support/stack.zig`. The reservation is address space the system commits
only as the stack grows. The largest Debug frames the passes use are about
20 KiB per tree level, so the 1000-level bound uses about 20 MiB of the
reservation.

The nesting limit and its rule do not change, and the parser remains the one
place that reports it.

## Consequences

- Acceptance still depends only on the limit. A program within it is checked
  and lowered in every build mode; a program past it is refused once by the
  parser.
- Every entry point that runs passes in process goes through `run` or
  `spawn_config`. A new one that does not, and meets a deep program in Debug,
  can overflow again.
- A unit test runs on the test runner's thread and sees the default stack. A
  test that checks a deep program does so through `run`.

## Alternatives considered

**Lower the limit until Debug fits.** The tightest construct overflows at
about 460 levels on 8 MiB, so a limit with a margin is near 200. Chains of
that length occur in generated code, and the limit would be set by one
construct's Debug frame.

**Make each recursion iterative.** The recursions are the tree's own shape in
the parser, checker, ownership and lowering; rewriting each into an explicit
stack costs far more than the stack does, and gains nothing for the bound.

**Count stack use and refuse at a threshold.** Acceptance would then depend on
the build and the thread, which is what the explicit limit exists to avoid.
