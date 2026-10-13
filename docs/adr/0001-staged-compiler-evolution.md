# 1. Evolve the compiler in stages rather than building the final architecture

Status: Accepted — 2026-07-24

## Context

Linea's target architecture is a conventional multi-pass pipeline: lexer,
parser, resolver, HIR, type checker, ownership checker, typed HIR, MIR,
optimisation, QBE backend. Each representation has a defined purpose.

Building that pipeline before there is a language to run through it means
designing every intermediate representation against guesses. Intermediate
representations are expensive to design well and expensive to change once
passes depend on them, and an IR designed for a hypothetical language tends to
encode the wrong distinctions.

## Decision

Build the pipeline in stages, introducing each representation only when a
concrete problem demands it.

1. Calculator — lexer, parser, AST, tree-walking evaluator
2. Basic compiler — replace the evaluator with QBE code generation
3. Semantic analysis — resolver, symbol tables, type checker
4. HIR — when the AST becomes cumbersome to analyse
5. Ownership — a dedicated pass, separate from the type checker
6. Typed HIR — semantic representation with types, symbols and drop points
7. MIR — when optimisation, ownership lowering or backend independence demands it
8. Optimiser — operating exclusively on MIR
9. Self-hosting

A representation is introduced when it solves a named problem, not because the
reference architecture lists it.

Stage boundaries constrain scope, not quality. Data structures and module
boundaries introduced at any stage are expected to survive to Stage 9; the
tree-walking evaluator is the sole component scheduled for deletion.

## Consequences

- Each stage produces a working compiler, so the project is never in a state
  where nothing runs.
- Foundational choices are made under real pressure from working code rather
  than from speculation.
- Some work is knowingly repeated: the evaluator is discarded at Stage 2, and
  passes are rewritten against HIR when it arrives.
- Deferring an IR risks accumulating workarounds in its absence. The trigger
  for introducing one is a concrete difficulty in optimisation, ownership
  lowering, code generation, diagnostics or backend independence — recorded in
  a new ADR when it fires.

## Alternatives considered

**Build the full pipeline up front.** Rejected: every IR would be designed
against a language that does not exist yet, and the first working program would
be months away with no intermediate feedback.

**Skip intermediate representations entirely and lower the AST to QBE.**
Viable through Stage 3 and adopted for Stages 1–3. Rejected as an end state:
ownership analysis and optimisation both need explicit control flow and
explicit temporaries that an AST does not provide.
