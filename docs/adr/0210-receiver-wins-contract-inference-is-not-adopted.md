# 210. Receiver-wins borrow-contract inference is not adopted

Status: Accepted — 2026-10-05.
Applies [0123](0123-observations-carry-owner-dependencies-through-callable-contracts.md).

## Context

When a signature writes no borrow clause, the checker infers one if exactly one
parameter is an eligible source, and reports [T-BorrowContract] when several
are. A proposal would break the tie by picking the receiver (`self`) whenever
it is one of the candidates, so a method such as `get(self, key: Str) -> Option[Str]`
needs no clause.

A census measured it by stripping each signature's clauses and running the
checker with the current compiler and with a copy patched to prefer `self`.
Method and data: the census of 2026-10-05.

## Decision

**Inference does not choose among several candidate sources. A signature with
more than one eligible source names its contract.** The diagnostic changes
instead: [T-BorrowContract] names the candidate sources and the clause shapes
that would settle it, without suggesting one, since which is right depends on
the body. That change is made separately.

Evidence:

- 708 clauses in 586 signature groups carry a borrow clause. Of the 65 clauses
  the compiler refuses to infer, receiver-wins deletes **7, which is 1.0% of
  all clauses**, and **0 in the examples and the guide's snippets**, where
  every signature is a free function.
- It turns **27 signatures** (23 where `self` is one of several sources, 4
  where it is not a source at all) from a correct [T-BorrowContract] into an
  [O-Escapes] at the return expression, which does not mention the contract.
  The cost is message quality for the programmer who wrote the wrong guess.
- Where there is a body the wrong pick is loud, not unsound. It is **silently
  wrong only on bodyless signatures** (a trait method declaration, an
  extern), which would take the receiver's contract unchecked, and on bodies
  returning nothing dependent, which get a conservative contract that
  over-constrains callers.
- It never fires for `borrows(self)` owner accessors, which stay written.

## Consequences

- A method with several candidate sources writes `carries(..)` or
  `borrows(..)`, as today.
- The roughly 126 plain single-source clauses and 116 empty `carries()`
  clauses that are redundant today are a style sweep, not a language change.

## Alternatives considered

**Receiver-wins.** Rejected on the numbers above: 1.0% saved, nothing in
examples, 27 worse diagnostics, and a silent contract on bodyless signatures.

**Receiver-wins limited to methods with bodies and `carries`-shaped results.**
Removes the silent case and keeps the misleading one. Not adopted; it is the
candidate if the evidence below moves.

**Name the candidates in the diagnostic.** Chosen, as above.

## What would reopen it

Receiver-only clauses growing past about 10% of clauses, for example a new
receiver-centred iterator or slice API; or a receiver-wins limited to bodies
and `carries`-shaped results that produces no misleading diagnostic.
