# 17. Failure is either a trap or a value, never both

Status: Accepted — 2026-07-25

## Context

[ADR 0013](0013-no-undefined-behaviour.md) requires every operation to produce a
defined result or be a diagnosed error, but says nothing about what "error"
means once a program is running. Compile time has an answer already: a
diagnostic. Run time does not.

The question is not how to represent errors but which failures deserve a
representation at all. Swift's rationale draws the line: *"A recoverable error
arises from an operation which can fail in complex ways, but whose errors can
be reasonably anticipated in advance… A logic failure arises from a programmer
mistake and should not be recoverable at all."* Zig's guidance rhymes from the
other direction: *"Avoid mixing error-returning functions with those that
panic."*

Mixing them is the failure mode. A language where any operation might either
return an error or abort forces every caller to defend against both, and the
defence for abort is impossible.

## Decision

Every failure is classified once, at the point the operation is designed.

**A logic failure traps.** The program's assumptions were wrong, so continuing
means running code whose premises do not hold. A trap writes what failed and
where to standard error and aborts the process. It cannot be caught, and there
is no unwinding: destructors do not run, because the process is ending and the
alternative is running arbitrary user code inside a broken program.

Integer overflow, division by zero, and a conversion whose value does not fit
are logic failures.

**An anticipated failure is a value.** The operation is expected to fail as
part of normal use, so it returns something the caller must handle:
`Option(T)` when the only information is absence, `Result(T, E)` when the
failure has a reason worth carrying. Handling is `match`; `?` is the shorthand
for the propagate case.

**An operation is one or the other, never both**, and its name says which. The
trapping and the recoverable forms of the same computation are separate
operations with separate names — `u8(x)` traps, and the fallible conversion
will have a different name — because a caller must be able to see which one
they invoked without consulting a signature elsewhere.

Because a trap aborts rather than exits, its failure is distinguishable from
any value a program can return, which matters when the entry point's result
occupies the whole exit-status range
([ADR 0019](0019-entry-point-is-main-returning-u8.md)).

## Consequences

- A caller never defends against both failure modes at once. If it compiles
  without handling an error, the operation cannot fail recoverably.
- No unwinding machinery, no landing pads, no `catch_unwind`. This is a
  significant simplification, and it is worth much more under linear ownership,
  where unwinding would mean dropping every live value on every path out of
  every operation that can trap.
- A trap in a library aborts the program embedding it. A caller that needs to
  survive the failure needs the operation to have been designed as recoverable,
  which is a decision made by the author rather than recoverable after the
  fact.
- The classification is a design obligation on every future operation, and one
  that is expensive to change later: turning a trap into a value changes every
  call site.
- Some operations genuinely need both forms, because whether a failure is
  anticipated depends on where the value came from. Those get two names, and
  the pair is written when a real caller needs the second.

## Alternatives considered

**Exceptions with unwinding, as in C++ or Rust's default panic.** Lets a caller
recover from a logic failure at a chosen boundary, which servers and test
harnesses genuinely want. Rejected: it requires unwinding through every frame,
which under linear ownership means a drop path for every live value at every
trap site, and it makes any call a potential non-local exit.

**Everything is a value; nothing traps.** The most uniform rule, and it never
takes the decision away from the caller. Rejected: it makes every arithmetic
operation return a `Result`, so either the language is unusable or `?` appears
on every line, and a caller forced to handle a case that indicates a bug will
handle it wrongly.

**Everything traps; no recoverable errors.** Also uniform, and it suits a
language that never reads untrusted input. Rejected: Linea is a systems
language, so it will read files and parse input, and a parser that aborts on
malformed input is not a parser.
