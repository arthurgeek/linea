# 24. A program is a list of declarations

Status: Accepted — 2026-07-26
Supersedes [0019](0019-entry-point-is-main-returning-u8.md)

## Context

[ADR 0019](0019-entry-point-is-main-returning-u8.md) settled two things
together: that a program's entry point is `fn main() -> u8` whose value is the
exit status, and that a program declares *that and nothing else*.

The first has held. The second was a statement about how much language existed,
not about what a program should be, and it shaped code: the parser had a
`parseEntryPoint` routine rather than a declaration loop, and reported anything
following the entry point.

Functions make the second false. A record is superseded rather than edited when
the clause being changed has shaped code, and this one did.

## Decision

A program is a list of function declarations, exactly one of which is
`main() -> u8`.

Everything ADR 0019 decided about the entry point is carried forward unchanged:

- The name is `main`, matched by spelling.
- It returns `u8`, and that value is the process's exit status.
- The runtime calls it, so nothing in the program has to.

What changes is only that it is now one declaration among others rather than
the whole program.

## Consequences

**Which declaration is the entry point is a question about names**, so the
parser no longer asks it. The parser reads declarations; the resolver reports a
program with no `main` or with more than one. This is why `S-Entry` moved from
the parser to the resolver, and why an empty file is no longer a parse error.

**`main` is exempt from the unused rule** because the runtime calls it. Every
other function must be called or named with a leading `_`, which is
[ADR 0014](0014-unused-declarations-are-errors.md) reaching a declaration kind
it had not previously met.

**Only `main` is exported.** Nothing outside the compilation unit calls
anything else, and there is no linkage to declare until modules exist. Other
functions are emitted under a prefix so that a program declaring a function
named `linea_trap` cannot emit calls that link against the runtime's symbol —
a failure that would appear at run time as a trap that does not trap.

**`main` alone narrows its result to `w`**, because that is what a C runtime
expects; every other function returns the width every value is computed in.

## Alternatives considered

**Amend 0019 in place.** Rejected by this repository's own rule: the clause
being changed had shaped code, so a reader needs to know the compiler once
worked differently. That the substance of the entry point is unchanged is not
the test — the test is whether anything was built against the specific clause.

**Let any function be the entry point, named by a flag or an attribute.**
Rejected for the same reason 0019 chose a fixed name: a program's starting
point should be findable by reading it, and one spelling is the simplest rule
that achieves that. This becomes worth revisiting when a build produces
something other than an executable.

**Allow several `main`s and pick by signature.** Rejected: overload resolution
is a large mechanism, and the first thing it would be used for should not be
deciding where a program starts.
