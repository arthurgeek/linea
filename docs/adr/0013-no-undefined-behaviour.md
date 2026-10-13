# 13. No operation has undefined behaviour

Status: Accepted — 2026-07-25

## Context

Linea targets systems programming, which is the domain where undefined
behaviour is most entrenched and most costly. In C and C++ a long list of
operations — signed overflow, out-of-bounds access, use after free, data races
— have no defined meaning, and optimisers are permitted to assume they never
occur. The consequences are familiar: a program's meaning depends on the
optimisation level, a bug reproduces in one build and not another, and a
security fix can be optimised away because the compiler deduced the check was
unnecessary from the very undefined behaviour it was guarding against.

Nearby languages take intermediate positions. Zig has *illegal behaviour*,
detected in safe build modes and undefined in unsafe ones. Rust defines integer
overflow but differently per profile: it panics in debug and wraps in release.
Both leave the same source text meaning different things depending on how it
was built.

Predictable performance is a stated goal of Linea, and it is usually invoked to
justify exactly the opposite of this decision.

## Decision

No operation in Linea has undefined behaviour. Every operation either produces
a defined result or is a diagnosed error, and which of the two it is does not
depend on the optimisation level.

- A program's meaning is a property of its source, not of how it was compiled.
  The same input produces the same result in every build mode.
- "Defined" includes "defined to be an error". Division by zero is not given a
  value; it is specified to fail. What is forbidden is leaving the outcome
  unspecified.
- The compiler may not treat the absence of undefined behaviour as a premise
  for optimisation. A transformation must be justified by proof that it
  preserves behaviour, never by assuming a program would be undefined if it
  did not.
- Eliding a check that can be proven unnecessary is an optimisation, because it
  changes performance and not meaning. Removing a check that has not been
  proven unnecessary is a semantic change and is not permitted.
- An operation whose behaviour has not been specified is not finished. This
  applies to language constructs and to standard library operations alike.

Where the specified behaviour is a failure, the stage that detects it decides
its form: at compile time it is a diagnostic, and at run time it is whatever
the eventual error model provides. That model is not yet designed, and this
record does not decide it.

## Consequences

- Some checks cannot be proven unnecessary and cost real cycles. This is
  accepted: predictable performance means performance that can be reasoned
  about, not performance maximised by making incorrect programs meaningless.
- Optimisation becomes harder in a specific way. Many classical optimisations
  are licensed by undefined behaviour rather than by proof, and those are
  unavailable. The optimiser must derive its facts, which is more work and
  produces results that hold.
- Every new operation carries a specification obligation, and reviewing one
  means asking what it does at its boundaries.
- Testing gets stronger: a failure reproduces in every build mode, so a bug
  found in a release build can be debugged in a debug build.
- This interacts directly with ownership. Use after move, the canonical
  undefined behaviour of a linear type system, must be a compile-time error
  rather than an unspecified read. Ownership checking is therefore not only a
  safety feature but part of how this invariant is upheld.
- Interoperating with C will eventually require a boundary where these
  guarantees stop. That boundary needs its own record when it arrives; it does
  not weaken the rule inside Linea.

## Alternatives considered

**Undefined behaviour as an optimisation licence, as in C and C++.** The
established approach, and the source of a large fraction of the performance
those compilers achieve. Rejected: it makes a program's meaning depend on the
optimiser, which contradicts predictable performance in the sense that matters
— being able to reason about what a program does.

**Illegal behaviour detected only in safe builds, as in Zig.** Preserves the
optimisation licence while making violations findable during development.
Rejected: the same source has different meanings in different build modes, so
a test suite passing in a safe build says less than it appears to about the
binary that ships.

**Defined but profile-dependent, as with Rust's integer overflow.** No
undefined behaviour, and the debug profile catches mistakes. Rejected on the
narrower version of the same objection: a program that wraps in release and
panics in debug has two meanings, and the one users encounter is the one
tested least.
