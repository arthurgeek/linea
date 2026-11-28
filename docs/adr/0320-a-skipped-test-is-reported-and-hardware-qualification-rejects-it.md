# 320. A skipped test is reported, and hardware qualification rejects it

Status: Accepted — 2026-11-27. Extends [0277](0277-a-test-is-named-by-a-string.md).

## Context

GPU tests returned `Ok(())` when opening a device failed. Their report claimed
passes on machines where no computation ran, and also hid allocation and native
runtime errors. Ordinary development needs to run on machines without a GPU;
hardware qualification must establish actual execution.

## Decision

`testing.skip(reason)` constructs a canonical `testing.Failure` with a private
skipped kind. A test returns `Err(testing.skip(reason))`; normal deferred cleanup
runs. `Failure.is_skip` distinguishes skips from assertions and allocation
refusals. Custom Display error types keep their ordinary failure meaning.

Generated test dispatch selects the canonical Failure reporter by the trusted
library declaration's identity. That reporter writes the original skip reason
to standard error and returns subprocess status 77. No displayed string decides
the outcome. Other errors retain their existing reporting and settlement.

The driver reports `SKIP` and a separate skipped count, never a pass. Ordinary
`linea test` succeeds when its selected tests all pass or skip. Generic
`--deny-skips` fails when any selected test skips. A trap-expected test still
requires a source-located runtime abort; returning a skip fails it.

GPU tests skip only `GpuError.Unavailable`. Other opening failures and operation
failures fail. Hardware qualification runs the authored Linea tests with
`--deny-skips` in addition to its existing main-program execution checks.
Application tests exercise missing capability through an explicit opener
argument returning `Err(Unavailable)`, verifying computation is never called.
No process-wide provider override or fabricated device is needed.

## Consequences

An ordinary test report distinguishes absent hardware from executed computation.
Strict qualification cannot pass by skipping. Example test totals include every
reported test, while benchmark measurement counts remain independent. The new
outcome adds one private kind and one dedicated subprocess status; it adds no
GPU language or scheduling facility.

## Alternatives considered

**Return success when hardware is absent.** This says a computation passed when
it never ran, and hides unrelated initialization failures.

**Recognize an error's displayed text.** Any custom error can display the same
text; messages are explanations, not a typed outcome contract.

**Globally mock discovery.** Shared state changes unrelated calls and hides the
application's dependency. An explicit opener exposes the branch being tested.
