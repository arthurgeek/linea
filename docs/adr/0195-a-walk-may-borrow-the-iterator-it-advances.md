# 195. A walk may borrow the iterator it advances

Status: Accepted — 2026-09-28. Extends
[0170](0170-a-marked-postfix-call-lends-its-receiver.md); keeps
[0034](0034-ownership-is-positions-and-a-graph.md),
[0104](0104-release-is-optional-and-never-scheduled.md) and
[0131](0131-closure-invocation-and-capture-ownership-are-independent.md) as they
stand.

## Context

A `for` over a `Sequence` builds an iterator and abandons it where the loop
ends, so [O-LinearWalk] refuses a linear iterator. `Vec.drain()` and
`collections.Map.drain()` return iterators that own their container's storage,
and the elements they have not yet handed over. Such an iterator is linear
whenever the storage came from `mem.system()` or the elements are linear,
which is nearly every drain. Consuming a vector of linear payments therefore
needed a hand-written loop:

```linea
var pending = payments.drain()
loop {
    let payment = &pending.next() else { break }
    commit(payment)
}
match pending.finish() { Ok(_) => {}, Err(_) => panic("payments remain") }
```

The loop is correct, but it spells out by hand what `for` exists to say.

## Decision

**A walk may borrow the iterator it advances: `for x in &it`.** The head
`&place` names an `Iterator` rather than a `Sequence`. The loop lends the
place writably for its whole extent and calls `next` through the lend once per
element. The binder receives the iterator's `Item`.

- The loop takes and abandons nothing, so [O-LinearWalk] does not apply. The
  body may leave through `break`, `return` or `?`.
- The iterator stays with its owner. [O-Leak] checks the owner's remaining
  obligations at every exit. So a linear drain is settled after the loop, by
  `finish` (which returns an unfinished drain as `Err`), by `release`, or by a
  written `defer`. The program states in code what happens to elements the
  walk did not reach.
- The `&` means what it means on an argument and on a marked receiver: this
  site changes the place. The walk changes `it` at the head of every
  iteration. Ownership records that change against the mark on each step, as
  it records `&it.next()`. So an observation of `it`, or a closure that reads
  it, made before the loop cannot be used once the walk begins, inside the
  loop or after it ([O-Borrow]). Under
  [O-Lent], the body may neither read nor write `it` by its name while the
  walk holds it.
- A plain `for` over a linear iterator stays refused. [O-LinearWalk] now says
  what is owed: linear items not yet handed over, or storage from an
  allocator, read through the iterator's type arguments so an opaque type's
  fields stay unnamed. It teaches the lent walk and the settling that follows
  it.

## Consequences

- `for payment in &pending { … }` followed by `pending.finish()` is the
  library's and the examples' way to consume a drain of linear values.
  `examples/payment_batch.lin` uses it.
- No MIR or backend construct is added. A lent walk calls `next` through the
  place's address instead of through a local of its own.
- The `for` head accepts a marked place. It already parsed as a marked
  expression, and the tree-sitter grammar already accepted it, so the change
  is in checking, ownership and lowering. A tree-sitter corpus case pins the
  parse.
- A settle after the loop is always written, even when the body cannot leave
  early. That is the cost of every disposal being visible in the program.

## Alternatives considered

**(a) An `Exhausts` trait: an iterator that promises that running it dry
settles it.** A `for` could then end holding a linear iterator implementing
`Exhausts` when its body cannot leave early, and `next` would release the
storage on the path that answers `None`. The trait was built and removed.

- The promise is unchecked, because an iterator's field types do not change
  when it runs dry.
- Restricting the implementation to the iterator's declaring module does not
  bound it. That module cannot already discard its type: taking a type apart
  hands back its fields, and linear fields must still be settled.
- Any module could therefore wrap a value it does not own, linear or generic,
  in a type it declares, promise `Exhausts`, and walk it. That is a safe
  `forget` for every type. A foreign `Payment` or a system-backed `Vec` was
  dropped unsettled and the program ran. [O-Leak] would stop meaning anything
  across module boundaries.

**(b) `for` calls a declared terminal where the loop ends.**

- (b1) At the normal end only. `finish` answers `Result[(), Self]`, so the
  loop would need a hidden panic for an `Err` that cannot arise, or a second,
  infallible terminal.
- (b2) At every exit. That is disposal the compiler schedules where nobody
  wrote it. [0034](0034-ownership-is-positions-and-a-graph.md) rejected
  destructors for that reason, and
  [0097](0097-release-is-named-never-scheduled.md) and
  [0104](0104-release-is-optional-and-never-scheduled.md) rule that the
  compiler never creates a release invocation.
  [0131](0131-closure-invocation-and-capture-ownership-are-independent.md)
  rejected releasing an adapter's callback at exhaustion on the same ground.
  For linear payments it would also silently commit or roll back the payments
  the program never decided about.

**Making `Vec` itself a consuming `Sequence`.** A plain `for x in v` would
consume a vector one keyword away from the lending `for read x in v`. And the
iterator it built would still be linear for nearly every vector. An explicit
`drain()` names the consuming operation, and returns a value that can be lent,
resumed or finished. Map already has the same shape.
