# 242. A parameter may carry a label and a pattern

Status: Accepted — 2026-10-18.

Supersedes the declaration-parameter clause of
[0201](0201-a-tuple-pattern-binds-by-position-and-does-not-nest.md). Extends
[0177](0177-a-parameter-name-is-a-label-not-part-of-a-function-type.md) and
[0224](0224-a-pattern-nests-wherever-a-binder-stands.md).

## Context

A lambda parameter may be a tuple pattern, `|sink (i, x)|`, whose binders are
locals of the lambda. A declaration parameter could not, because its name is
the label a call writes
([0177](0177-a-parameter-name-is-a-label-not-part-of-a-function-type.md)) and a
pattern has no name. A function that wants only the parts of what it receives
names the whole and opens it on the first line:

```
fn commit(sink transaction: Transaction) -> Result[(), io.IoError] {
    let { recipient, amount } = transaction
    io.println("Paid {recipient}: {amount} cents.")
}
```

The library and the examples did this at about twenty-five sites with a
parameter other than the receiver. The name is used once, and lambdas and
declarations took arguments apart in two different ways.

A pattern written in a declaration was refused with [S-Params], and the parser
skipped it, so every name it would have bound was also [N-Undefined] in the
body.

## Decision

**A parameter is a name, or a label followed by a pattern.** The label is the
parameter's name for everything outside the body; the pattern takes the
argument apart where the body begins.

```
fn show(entry (position, name): (UInt64, Str)) -> Result[(), io.IoError] {
    io.println("{position}. {name}")
}
```

The order is convention, label, pattern, `:` and type, `=` and default:
`sink entry (a, b): (A, B)`. The pattern is a tuple, struct or newtype pattern,
the heads a destructuring `let` takes, with parts of the full pattern grammar
at any depth. Whether a name before `(` or `{` is a label or a pattern's type
is decided by its case, as inside every pattern
([0189](0189-a-names-case-is-part-of-its-kind.md)). A bare name after the label
is refused: a parameter has one name.

**A lambda reads the same parameter.** One routine reads a parameter for a
declaration and a lambda; a lambda's label is optional and is what a direct
call of the closure writes. A lambda therefore takes the struct and newtype
heads too. A declaration's label is required: a pattern with none is refused
with [S-Params], whose help shows the label to write, and is otherwise read as
written, so its binders are declared and the body reports only independent
mistakes.

**A pattern stands only where a body begins.** A structural callable type, a
trait operation without a body, the receiver `self`, and a projection's or
traversal's parameter refuse it with [S-Params].

**The label stands for the parameter wherever a caller sees one.** A named
argument writes it and a positional argument fills it; the argument-mapping
diagnostics name it; a borrow contract names it (`where carries(entry)`); a
hover, an inlay hint and call completion spell the parameter as
`entry: (UInt64, Str)`. The pattern never appears outside the declaration. The
label declares nothing in the body: naming it there is [N-Undefined], with a
help naming the binders.

**The pattern is held to what a `let`'s is.** It is checked against the
parameter's type as `let pattern: Type = argument` is; it must match every
value of that type ([T-Refutable]); a generic body is checked once over its
symbolic parameters, so a pattern needs the shape of its type there (a tuple,
struct or newtype whose arguments may be type parameters), and one against a
bare type parameter is refused as a `let`'s would be. Each binder is a local
held to [N-Unused]; `_` discards a part and `_name` marks one unused.

**The convention decides the mode, at every depth**, as
[0224](0224-a-pattern-nests-wherever-a-binder-stands.md) decides it for `let`
and `let read`: `sink` moves each part into its binder; `read` lends each part
from the caller's argument, which stays whole; `inout` lends each part
writably. A default is a constant argument, taken apart like any other.

Every pass reads a declaration's pattern parameter with the routine it already
used for a lambda's: the resolver binds the argument as a parameter and the
pattern's binders as locals, the checker checks the pattern with the routine
`let` uses, ownership takes the argument apart where the body begins, and
lowering binds the pattern before the body runs.

## Consequences

`fn commit(sink transaction { recipient, amount }: Transaction)` is one line,
and the library's first-line `let`s over a parameter are gone. A declaration
and a lambda take an argument apart the same way. A misplaced bare pattern
costs one diagnostic instead of one per binder.

A reader of a signature sees a label and a pattern; the formatter prints them
with one space between, and the editor grammar reads the pattern as an
optional field of a parameter. Renaming the label renames the parameter at
every call; renaming a binder renames a local.

The receiver stays a name: `let Listener { fd } = self` remains how a method
opens its receiver.

## Alternatives considered

**Keep the rule.** A line and a single-use name per site, and two ways to take
an argument apart.

**Positional-only patterns, as Rust has them.** Rust has no named arguments,
so its pattern parameter loses nothing. Here every declaration parameter is a
label a call may write and a contract may name. An unlabelled one would be the
only parameter a named call cannot reach, a contract would need a position to
name it, and a hover would show the pattern, which belongs to the body, as the
signature: renaming a binder would change what callers read.

**A label and a separate name, as Swift has them** (`entry e: T`). Two names for
one value, and the existing `entry: T` already says it.

**The label in scope beside the binders.** Under `sink` the whole and its parts
would both be owned, a partial move; under `read`, two names for one place.

**The pattern after the type** (`entry: (A, B) as (a, b)`). New syntax for the
order a `let` already reads in.
