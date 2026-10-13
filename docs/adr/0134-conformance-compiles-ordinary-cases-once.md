# 134. Conformance compiles ordinary cases once

Status: Accepted — 2026-09-16

Supersedes 0026.

## Context

Recompilation-based properties applied to every corpus case repeatedly check
the same imported library. A profiled simple loop triggers ten library-inclusive
semantic analyses; its own body accounts for less than a millisecond of type
checking. Corpus growth multiplies this work without establishing which
additional property shapes it covers.

## Decision

The ordinary corpus compiles each input once. Golden comparisons, execution,
and properties that inspect the resulting semantic tables share that result.

Properties requiring different source inputs or an independent editor analysis
run in a focused suite selected explicitly from the corpus. Selection covers
each property kind and its meaningful language shapes. The suite reports its
own population and enforces coverage; excluded ordinary cases are not counted
as property successes or applicability refusals. Generated property tests keep
their separate accounting.

## Consequences

Adding a golden case does not automatically multiply it into several compiler
invocations. Adding a new property shape requires a focused witness. These
checks remain required before merging, while ordinary corpus timing measures
one compilation per case.

Library-result reuse is complementary. It must preserve complete semantic
answers and invalidate them when their dependencies change; this decision does
not permit skipping library validation or weakening language rules.
