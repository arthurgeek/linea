# 106. A non-completing expression has type Never

Status: Accepted - 2026-08-28

Refines [0072](0072-a-declaration-only-generated-code-calls-is-named-by-its-module.md):
panic is syntax rather than a declaration generated code calls.

## Context

Linea had control transfers and an infinite loop, but no type that said their
local continuation was unreachable. The special case for a `loop` with no
`break` refused it where a value was required, while `return`, `break`,
`continue`, traps and calls to functions that never return had no one type-level
answer downstream passes could share.

`Option.unwrap` and `Result.unwrap` also need a deliberate logic-failure
operation. An ordinary function can abort, but it cannot retain the source
location of each written invocation without a hidden location argument. Making
that function a callable value would extend the callable ABI solely for failure
reporting.

The answer must preserve [0017](0017-failure-is-a-trap-or-a-value.md): a logic
failure aborts, cannot be caught and performs no unwind.

## Decision

**`Never` is a primitive type with no values.** It may be written in every type
position. Its representation is zero-sized and it is vacuously Free, but no
instruction produces a value of it.

**Every expression whose local continuation is unreachable has type `Never`.**
This includes `return`, `break`, `continue`, a loop with no reachable `break`, a
panic, a direct or indirect call whose settled result is `Never`, and a
conditional, match or block whose every path fails to reach its continuation.
Transfers keep their destinations: a `break` still reaches its loop join and a
`return` still reaches its caller.

`Never` is compatible with every known expected type and no type is compatible
with `Never`. That bottom compatibility emits no conversion and no value. It
does not settle an open generic parameter. Branch agreement ignores
non-completing alternatives; if every alternative is non-completing, the result
is `Never`.

A function declared `-> Never` has no normal path to its end. Calling it through
either a direct target or a structural callable ends the caller's current
block.

**`panic(message)` is a dedicated expression.** `panic` is reserved, cannot be
shadowed or used as a callable, takes exactly one `Str` expression and answers
`Never`. The message is evaluated once. If it does not complete, its completion
wins; otherwise panic writes
`linea: panic: <message> at <file>:<line>:<column>`, flushes standard error and
aborts. The bytes are written by their recorded length, and the location is the
written panic expression's location.

Panic has no unwind path. Live Linear values need not be consumed because there
is no successor ownership state and the process is ending.

`Option.unwrap` and `Result.unwrap` use fixed messages naming the failed
alternative. The result operation does not render its error payload and
therefore requires no display bound; the payload is abandoned only on the
aborting path.

## Consequences

The type checker owns one bottom-compatibility operation and records `Never` on
every non-completing expression. Ownership and lowering read that type rather
than maintaining lists of syntax that happens not to return.

MIR has explicit direct and indirect noreturn-call terminators, and panic uses a
message-bearing trap terminator. Lowering emits no value for `Never`; a read of a
named `Never` value traps rather than materialising one. Verification refuses a
`Never`-producing value instruction, a call in the wrong return form, a normal
return from a `Never` function and a malformed message-bearing trap.

A `Never`-returning MLIR function has no result and is marked noreturn. Panic
requires a runtime entry point receiving the `Str` bytes and the source
location; ordinary checked-operation traps keep their existing entry point.

Types containing `Never` retain their ordinary meaning. A required `Never`
field cannot be initialised, while an enum may have other inhabited variants.
Exhaustiveness remains syntactic over the variants declared rather than gaining
an inhabitance analysis.

## Alternatives considered

**Keep one special no-value rule per construct.** Rejected because each later
pass would need the same growing list and would disagree on compound expressions
whose every path diverges.

**Type non-completing expressions as Unit.** Rejected because Unit has a value.
It would say that a binding after an infinite loop or noreturn call receives a
value even though its continuation is unreachable.

**Let `Never` infer any generic argument.** Rejected because bottom is evidence
that no value arrives, not evidence selecting one type among every possible
type. Another argument or contextual fact must settle the parameter first.

**Make panic an ordinary function.** Rejected because preserving the written
call site's location would require hidden arguments or a special callable ABI,
and because the operation must not be stored or passed as a value.

**Unwind from panic.** Rejected by 0017. Running cleanup code after a logic
failure would require unwind paths through every frame and every live Linear
value.
