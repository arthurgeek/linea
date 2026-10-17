# 224. A pattern nests wherever a binder stands

Status: Accepted — 2026-10-15.

Supersedes the nesting clause of
[0201](0201-a-tuple-pattern-binds-by-position-and-does-not-nest.md) and its
conservative place for a lending walk's binders. Extends
[0129](0129-struct-destructuring-may-infer-its-type.md),
[0147](0147-a-borrowed-let-pattern-reads-a-stable-place.md) and
[0167](0167-a-binding-handles-its-failure-with-else.md).

## Context

A pattern bound a name to each part one level down, and no deeper. A value
nested two levels deep was taken apart in two steps: a binding of the outer
payload, then a `let` or a second `match` over it.

```
match setting(true) {
    Some(pair) => {
        let (_name, value) = pair
        UInt8(value)
    },
    None => 0,
}
```

The library spelled `Ok(line) => match line { Some(v) => …, None => … }` some
ninety times, and `Err(failure) => { let Failure { reason, value } = failure`
some forty. A lent value was worse: under `match read`, the intermediate binder
is a lend, so `let (a, b) = pair` takes it ([O-Move]) and the program needed a
`copy` or a second `let read` to reach a part it only wanted to read.

[0201](0201-a-tuple-pattern-binds-by-position-and-does-not-nest.md) refused
nesting because it needs a pattern walk in every pass and a binder record that
names a path rather than one step. This record is that design.

## Decision

**A pattern stands wherever a binder stood**: in a variant's or newtype's
payload, a tuple's component, and after a struct field's `:`. `Some((a, b))`,
`(Some(x), None)`, `Ok(Point { x, y })`, `Err(Read(Limit))` and
`Reading { sensor, value: Some(v) }` are patterns. Inside a pattern a bare name
is read by its case ([0189](0189-a-names-case-is-part-of-its-kind.md)): a
lowercase name or `_` binds, a capitalised one is a variant. Integer literals
and ranges may stand at any depth. Each construct keeps the heads it admitted:
a `let` still begins with a name, tuple, struct or newtype, and a `for` or
lambda parameter with a name or tuple.

**The construct decides the mode, at every depth.** A `match`, `let` or
`let … else` consumes the value whole and each binder owns the part its path
selects. A `match read`, `let read` or lending walk lends each binder exactly
that part: nothing is copied, a scalar still snapshots, other duplication still
needs `copy`. There are no partial moves and no per-binder modes.

**One usefulness pass answers every coverage question.** A `match` is checked
with the usefulness algorithm over its arms' pattern rows, answered for every
arm in one pass: an arm no value
reaches is [T-Unreachable], a `match` some value escapes is [T-Cover] and names
that value as a pattern, and a pattern in a `let`, `let read`, `let … else`,
`for` or lambda parameter must match every value of its type ([T-Refutable]).
The check counts the matrix cells it builds and refuses a `match` past
2^20 of them ([T-CoverLimit]).

**An enum declares any number of variants.** The limit of 64 ([T-Variants])
existed because coverage kept one bit per variant in a machine word. The
usefulness pass records the variants a column names in a set sized by the enum,
so the rule and its diagnostic are removed.

**`let … else` stays a test of its initializer.** Its pattern binds the success
payload and must be irrefutable; `else` still means only that the `Option` or
`Result` failed.

**A lending walk's tuple binders lend their components.** A walk's element is
still every position of the container, but its binders now name the element's
components, so writing one while another is in use is accepted.

One recursive routine checks every pattern and records each part's answer in
the tables the outermost pattern's always went to: its type, its variant's
ordinal, its field's identity. Ownership and lowering walk a pattern top-down
and compose those answers into the path from the scrutinee to each part, so no
pass selects a part a second way; the checker's place relation and ownership's
paths each keep a one-step record per nested pattern node, so a binder's place
is a chain ending at the value the construct took apart. Lowering tests an
arm's pattern outer part first, so a payload is read only after its tag is
tested, then binds.

## Consequences

`Some((name, value))`, `Err(Read(Limit))` and `Err(Failure { reason, value })`
are written in one step, and a lent value's parts are lent in one step. The
three coverage mechanisms of one `match` (the variant word, the closing product
arm and the integer intervals) become one. `let Some(n) = found` is reported as
refutable rather than as naming a different type. An enum with more than 64
variants, refused before, is accepted.

Struct patterns as a `for` head stay out: a `for` takes a name or a tuple.

## Alternatives considered

**Tuple-in-payload only.** It needs the same path-valued place, nested lowering
and product-aware coverage as general nesting, and leaves the far more common
variant-in-variant and struct-in-payload sites in two steps.

**Rust's default binding modes.** A plain `match` on a lent place would quietly
lend. A move is decided by position, and `match` and `match read` stay
distinct tags so every consumer decides.

**Per-binder modes and partial moves.** A moved binder beside a lent one needs
per-path initialisation state in the ownership checker, and discard runs no
cleanup, so a part left behind would still need settling through a place the
program believes consumed.

**A refutable `let … else`.** `else` would mean either "the initializer failed",
with an error to bind, or "the pattern failed", with none. One construct would
answer two questions.

**A decision tree in lowering.** It never repeats a test but can grow
exponentially and needs a second matrix walk; a chain of arm tests is linear in
the pattern and repeated tag loads are a common-subexpression target.

**No budget.** Exhaustiveness of nested patterns is NP-complete, so the check's
worst case is exponential in a pattern's width; without a ceiling the cost of
one `match` has no stated bound.

**Keeping the conservative walk place.** Two answers to which place a binder
lends, one for walks and one for every other pattern.
