# 270. A fallible map is `task.map`

Status: Accepted — 2026-11-14. Supersedes the `task.map_results` name in §2 of
[0253](0253-independent-work-runs-through-an-explicit-executor-policy.md).

## Context

ADR 0253 gives independent work two mapping combinators. `task.map(policy,
items, f)` applies `f` to every item and keeps their order.
`task.map_results` does the same for an `f` that answers `Result[R, E]` and
answers a `Vec[Result[R, E]]`, so one failing item drops none of the others'
results.

`task.map` never reads what `f` answers. Its result type is a parameter `R`
bounded `Owned`, and `Result[R, E]` is `Owned` whenever `R` and `E` are, so
`task.map` called with a fallible `f` already answers a `Vec[Result[R, E]]`
holding every item's result in order. The body of `map_results` was the body
of `map` with `R` written `Result[R, E]`: the same policy branches, chunking,
launch failures, joins and ordered flattening.

## Decision

`task.map` is the one mapping combinator. A fallible `f` is passed to it, and
the caller receives every result, successes and failures alike, in item order.
`task.map_results` is removed.

The decision of 0253 that a fallible map keeps every result stands; only the
second name goes.

## Consequences

- One scheduler body maps items, so a change to chunking or to how a launch
  failure is reported is made once.
- A caller who wants the first failure alone folds the answered `Vec`; the
  library does not short-circuit for them.

## Alternatives considered

- **Keeping `map_results` as a forwarding function:** rejected because it
  would name nothing `map` does not: the two calls would differ only in
  spelling, and a reader would look for a difference that is not there.
- **A short-circuiting `Result[Vec[R], E]`:** rejected in 0253, since failing
  early drops outputs other jobs produced, and not reopened here.
