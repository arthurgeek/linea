# 71. A failure may leave through the entry point

Status: Accepted — 2026-08-04

## Context

A program's work can fail. Writing to standard output can fail, and
[0070](0070-explicit-failure-is-acknowledged.md) makes the report of it
impossible to drop — so `println` answers a `Result` and something has to
receive it.

`main` answered `UInt8` and has no `?`. So there was **nowhere for a failure to
go**, and every call site had to terminate one by hand:

```linea
match println("hello") { _ => {} }
```

One answer is Rust's: `println!` panics, and the call site costs nothing. It
fixes the ceremony and throws away what
[0017](0017-failure-is-a-trap-or-a-value.md) already decided, that a failure is
a value. A write failure *is* a value by the time the library holds it; trapping
on it discards the information at exactly the point the program was about to be
told.

Zig answers it by letting `main` return an error union, and that is what makes
`try stdout.print(…)` a single line there. We had two-thirds of Zig's shape
already — a swallowing debug tier on standard error, a fallible transport on
standard output — and were missing the third.

## Decision

**The entry point may answer `Result[UInt8, E]`.**

```linea
fn main() -> Result[UInt8, IoError] {
    println("hello, Olá")?
    .Ok(0)
}
```

Where the answer is `Ok`, its payload is the exit status and nothing is
rendered — the program is indistinguishable from one that answered a bare
`UInt8`, so the spelling costs nothing until something fails. Where it is
`Err`, the failure is rendered to standard error and the process exits `1`.

### What the alternatives must carry, and who checks it

**The success carries `UInt8`**, for the same reason the plain spelling does:
it is the exit status.

**The failure implements `Display`**, because it is rendered on the way out.
Nothing else could render it — a compiler spelling the message would be a
second place deciding what a program says, and there would be nothing to say
about a type that never described itself.

The spelling is [S-Entry]'s and the resolver settles it. What the alternatives
hold is a question about types, so the checker settles that. Lowering assumed
both before either was checked, and the assumptions failed in the two ways
assumptions do: a success of another type read a byte out of a payload that had
none and surfaced as a *compiler defect* rather than a diagnosis, and a failure
with no implementation rendered nothing at all.

### The status is fixed, and is not the failure's contents

An exit code is a handful of bits that every shell reads as a category. A
failure has a whole line of standard error to describe itself on. Encoding one
in the other loses most of it and misleads about the rest.

### The reporting is the library's

Generated code calls `report[E: Display]`, which the prelude publishes.
Rendering is what `Display` is for, and the choice of `error: ` and of the
status belongs where a reader can see and change it.

The callee is found by prelude identity — the mechanism `?` uses for `Result`
and [0070](0070-explicit-failure-is-acknowledged.md) uses again. No expression
names this call, and it needs none: a call is a declaration, its settled type
arguments, and a symbol, and lowering has all three without an AST node.

### One return, three ways out

Lowering built its terminator at three places — a body's tail, a `?`, and a
written `return`. What a return *does* is one question, and three answers to it
is three chances for the entry point to keep only two. They are now one helper,
which is [0048](0048-one-question-has-one-answer.md) applied to a question that
had quietly grown a second answer.

### What is written and what is returned part company

The body still builds the `Result` — a `?` inside `main` has to build the
failing variant of the type that was *written* — while the function returns a
byte. Lowering therefore keeps both: the declared answer, which `?` reads, and
the return type, which the backend reads. Overwriting the second alone made a
`?` in `main` build its failure out of `UInt8`.

## Consequences

**`println` answers `Result[(), IoError]`.** Nothing on success, because "print
this" is the operation and how many bytes it took is not what was asked — the
count belongs to `finish`. It is also what lets `println(x)?` stand as a
statement rather than leaving a number behind for [T-Discard].

**`()` became a type wherever a type is written**, because `Result[(), E]` had
no spelling. That is [its own change](../linea-semantics.md) and it was forced
by this one.

**The shortest program that prints is one line per print**, with no panic, no
swallowing and no `match`.

**A program that ignores the possibility still can.** `eprintln` is the debug
tier and swallows; `match r { _ => {} }` remains a legitimate written act of
ignoring under [T-DiscardFailure]. What is gone is doing it silently.

## Alternatives considered

**Panic inside `println`**, as Rust does. One line at the call site, and it
discards a value the program was holding. Rejected on
[0017](0017-failure-is-a-trap-or-a-value.md): the trap is for a failure that has
no value, and this one has one.

**Swallow on standard output**, as Go and C do. Rejected in
[0070](0070-explicit-failure-is-acknowledged.md): standard output is what the
program is *for*.

**A `catch`-style inline form**, as Zig has for error unions. It would shorten
the ignoring rather than give the failure somewhere to go, and the second is the
actual problem. Worth revisiting on its own merits, and not for this.

## Deliberately open

**Whether the status should be settable.** `1` is fixed here. A program wanting
another one answers `Ok` with it, having dealt with the failure itself, so
nothing is unreachable — but a project with a status convention would want to
say so once rather than at every exit.

**Whether anything other than `main` is an entry point.** The rule is written
about the entry point rather than about the name, so a test runner or an
alternate runtime would inherit it without reopening the question. Nothing
declares a second one today.
