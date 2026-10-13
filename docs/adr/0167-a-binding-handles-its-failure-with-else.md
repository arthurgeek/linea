# 167. A binding handles its failure with `else`

Status: Accepted — 2026-09-24.

Builds on [0070](0070-explicit-failure-is-acknowledged.md), which makes a
`Result` something a program acknowledges, and on
[0106](0106-a-non-completing-expression-has-type-never.md), which gives every
non-completing expression the type `Never`. Refines
[0041](0041-a-newline-ends-a-statement.md) by recording the one exception to
its backwards-only rule, a line that begins with `else`.

## Context

Edge code — a command-line entry point, a server's startup, a loader — calls
several operations that can fail, and handles each failure where it happens:
it reports what went wrong and stops. `?` does not fit there, because the
failure is the function's to handle, not its caller's. What remained was a
`match` per step:

```
let listener = match net.listen(address) {
    Ok(listener) => listener,
    Err(error) => {
        io.eprintln("cannot listen: {error}")
        return 1
    },
}
```

Four lines of every such `match` restate what the language already knows: the
success arm binds the payload to a name the `let` has just written, and the
failure arm is the only one saying anything. A settings loader of five steps
spends twenty lines on arms nobody reads, and the success value's name is
written twice.

## Decision

**`let pattern = e else |error| { … }` unwraps the prelude's `Option` or
`Result`.** On success the pattern binds what `Some` or `Ok` carries. On failure
the block runs. The block either does not complete — it has type `Never`, ending
in `return`, `break`, `continue`, a panic or a call that does not return — or
completes with the success type, and that value is bound instead. Any other
block is [T-Mismatch].

**A failed `Result` carries its error into the block.** `else |error|` names it
and the name owns it; `else |_|` discards it under the ordinary `_` rules, so a
Linear error bound to `_` is [O-Leak]. A `Result`'s `else` must write one of
the two: an error left unnamed without a written `_` is the silent discard
[0070](0070-explicit-failure-is-acknowledged.md) refuses for `let _`. A failed
`Option` carries nothing, so its `else` takes no binder. Both are [T-LetElse],
as is an initializer of any other type.

**The pattern is any binding pattern**: a name, or a struct or newtype pattern
taking the success apart. `let read` observes a place, and the construct is not
one.

**A line that begins with `else` continues the construct above it**, for a
binding exactly as for an `if`. The parser already read an `if`'s `else` across
a line break, which [0041](0041-a-newline-ends-a-statement.md) did not record:
its rule reads only the token before the break, and `}` ends a statement.
`else` is the exception, and it is safe for the reason the forward-looking rule
0041 rejected was not: `else` cannot begin a statement, so a line opening with
it has one reading and no program changes meaning. Both constructs take the
`else` through one parser routine, so the two cannot drift apart. The nearest
construct still able to take the `else` takes it: after an `if` initializer
the first `else` belongs to the `if`, and a further one to the binding.

A binding takes one `else`, and its binder is one name between two bars.
[S-LetElse] reports each malformed binder and each second `else` once.

**The construct is a node, `unwrap_else`, built where a binding's initializer
is read.** Its operand sits where a call's callee does, and its run holds the
binder, where one is written, then the block. It is a node rather than an
expansion into `match` for the reason `?` is one: a tree holding the arms could
not be printed back as what someone wrote. Every pass reads it as the two-arm
consuming `match` it means: the resolver scopes the binder to the block as it
scopes an arm's binders, ownership builds a success path yielding the payload
and a failing path walking the block, and lowering tests the tag through the
routine `?` uses and joins the two paths through a slot, as a conditional's arms
do. The success type's expectation reaches a generic initializer through the
routine that carries one beneath `?`.

## Consequences

Edge code binds a value and handles its failure in one statement. The success
value's name is written once; the block says only what the failure means.

Ownership needs no rule of its own. The operand is consumed where the binding is
written, the error binding owns the error, and a block that leaves does so
through a transfer the ownership graph already models, so [O-Leak] asks about
everything still held at that exit as it does at any `return`.

Everything that reads source learns the form. The formatter prints
`e else |error| {` on the initializer's line, as it prints `} else {`. The
language server scopes, hovers and hints the binder as it does a `for` binder.
The tree-sitter grammar admits an `else` after a binding's or a constant's
initializer, giving an `if` initializer's own `else` to the `if` as the
compiler does.

Adopting the form in the standard library and examples is left to the code that
benefits; this record changes no existing program.

## Alternatives considered

**A `catch` operator, as in Zig: `e catch |err| value`.** An expression, so it
composes anywhere a value does. Rejected because the case it exists for is a
binding, and an expression form invites nesting a failure handler inside an
argument list, where the handler's `return` leaves from the middle of a call.
Restricting the form to a binding keeps the handler at statement level, where a
reader looks for control flow. Zig's value-yielding shape is kept: the block may
supply the value.

**Rust's `let … else` without an error binding.** Rust's form diverges only and
binds nothing from the failure, since it takes any refutable pattern. Rejected
because the error is what edge code reports; a form that drops it sends the
program back to `match` for exactly the case that motivated it. Allowing the
block to yield a value covers defaults, which Rust needs `unwrap_or_else` for.

**Swift's `guard let … else`.** A separate keyword for the same shape. Rejected
because `let` already introduces the binding; a second keyword adds a spelling
without adding meaning.

**`match` only, the state before this record.** Every failure spelled as two
arms. Rejected for the cost described above: the arm that binds the success
repeats the binding, and it is most of what edge code consists of.

**Refusing `else` on the next line.** The binding's `else` would have to sit on
the line the initializer ends, with a diagnostic naming the fix. Rejected
because an `if`'s `else` is already accepted on the next line: one statement
shape, a line opening with `else`, would be legal or an error depending on what
the initializer is, and the rule for where `else` may be written would have
two answers.
