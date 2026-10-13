# 0020. A constant expression is defined by the language, not discovered by a pass

Date: 2026-07-25

## Status

Accepted; extended by 0059 and 0078; extended by [0140](0140-aggregate-constants-retain-checked-construction-plans.md)

## Context

A conversion whose operand cannot fit its target is an error
([ADR 0013](0013-no-undefined-behaviour.md)). Where the operand's value is
visible to the compiler, that error can be reported instead of trapping:

```linea
let x = 300;
u8(x)
```

The obvious rule is *reject whatever the compiler can prove is out of range*.
It is the wrong rule.

Under it, the set of valid Linea programs depends on how good the compiler's
analysis is. A program that compiles today stops compiling when constant
propagation improves, and the change arrives through an optimiser release
rather than a language one. Two compilers claiming the same language version
would disagree about which programs exist, and the disagreement would be a
quality-of-implementation difference rather than a bug in either.

That collides directly with [ADR 0013](0013-no-undefined-behaviour.md), which
requires that which result an operation produces does not depend on the
optimisation level. A rule that makes *compilability* depend on analysis
strength breaks the same guarantee one level up.

## Decision

**A constant expression is defined syntactically, and the definition decides
which programs are valid.** It is:

- an integer literal;
- a parenthesised constant expression;
- a negation or conversion of a constant expression;
- an arithmetic operation whose operands are both constant expressions;
- a reference to a binding whose initialiser is a constant expression.

A conversion or operation on constant expressions whose result does not fit
its type is **rejected at compile time**. Everything else is checked when it
runs.

The last clause holds only because a binding cannot be assigned again. A
binding that is written to is not constant however its initialiser looks, and
introducing assignment means saying so.

This is a frontend rule, evaluated by the type checker while it folds. No
later pass may reject a program the frontend accepted, however much it manages
to prove.

## Consequences

Constant folding converts *some* traps into diagnostics. It never removes the
need for a check: once a value can arrive from outside the expression —
a parameter, a read, anything the definition does not cover — the check is what
stands between it and undefined behaviour. The machinery in the backend is
unaffected by this record.

Where the definition stops is visible to the programmer, and that is the point.
`u8(x)` with `x` bound to a literal is an error; the same conversion on a value
the definition does not reach is a trap. A programmer can tell which by reading
the rule, without knowing what the compiler managed to work out.

An optimiser may still fold anything it likes. What it may not do is decide
that a program is invalid.

## Alternatives considered

**Reject whatever the compiler can prove.** Rejected: it makes the valid
programs a function of analysis quality, so improving the optimiser is a
breaking change, and two conforming compilers need not agree.

**Report a warning rather than an error.** Rejected: an unused declaration is
already an error rather than a warning
([ADR 0014](0014-unused-declarations-are-errors.md)), and a conversion that
provably cannot succeed is at least as clear a mistake. A warning would also
leave the trap in place, so the program would carry a check for something
already known to fail.

**Leave it to run time entirely, as it stood before this record.** Rejected:
the information is in the frontend already — the checker folds these
expressions to test literals — and declining to use it reports at run time
something that could have been reported at compile time, for no gain.

**Defer to Stage 8 with constant propagation.** Rejected: that frames the
question as an optimisation. Which programs are valid is a language question,
and answering it in an optimiser is what this record exists to prevent.
