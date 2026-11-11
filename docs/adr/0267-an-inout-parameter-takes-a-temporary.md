# 267. An `inout` parameter takes a temporary

Status: Accepted — 2026-11-10. Extends
[0175](0175-a-borrowed-temporary-lives-until-the-end-of-its-statement.md) and
[0025](0025-mutation-through-a-parameter-is-marked.md). Supersedes the
`_inout` naming clause of
[0131](0131-closure-invocation-and-capture-ownership-are-independent.md), the
`_inout` forms of
[0192](0192-iterator-operations-belong-to-every-sequence.md) and the clause of
[0170](0170-a-marked-postfix-call-lends-its-receiver.md) that binds a receiver
that is not a place to a `var`.

## Context

The standard library declared seventeen operations twice. `fold` took its
callback `sink` and `fold_inout` lent it; so did `map`, `map_err`, `and_then`,
`unwrap_or_else`, `find`, `find_map`, `find_counted`, `for_each`, `any`, `all`,
`upsert` and `from_fn`, with `from_fn_inout_in` beside `from_fn_in`.
`Vec.split_inout` and the private `fold_one_inout` carried the suffix with no
`sink` form beside them. Every `sink` form was the same three lines:

```linea
fn any[F: inout fn(sink item: Self.Iter.Item) -> Bool](sink self: Self, sink predicate: F) -> Bool where F: Discardable {
    var checking = predicate
    self.any_inout(&checking)
}
```

The body lived in the `_inout` form. The `sink` form existed for one reason:
an `inout` parameter required a place, so `xs.any_inout(|x| x > 3)` was
[S-Mutation], and the closure had to be bound to a `var` and lent. A `read`
parameter had no such requirement: since ADR 0175 an argument that is not a
place is evaluated into a temporary that lives until the end of the call's
statement.

The pair cost more than the wrapper. A reader chose between two names for one
operation and had to know which callbacks needed the longer one. The `sink`
form consumed a named callback, so passing it to two operations was [O-Move],
and a callback owning something to release went to the `_inout` form. An
operation with no `_inout` form (`merge`, `update`) could not take such a
callback at all.

## Decision

**An argument to an `inout` parameter may be a value that is not a place.**
It is evaluated into a temporary, the parameter is lent that temporary, and
the temporary lives until the end of the statement that evaluates it, the
rule [O-Temporary] already states for `read`. A value borrowing the temporary
may be used within the statement and not after it, and may not be returned.
What a place is does not change: a local, a parameter, a capture, a binder, a
constant, a field, element or projection of one, and whatever an observation
reaches.

**The temporary owns what the argument yields.** The callee may write it, so
it cannot be a copy of bytes another place still owns: the argument sits in a
consuming position. A branch that names a place, as in
`bump(if first { a } else { b })`, moves that place into the temporary, and a
later use of it is [O-Move]. A `read` temporary is unchanged; it is only
observed.

Two holes that predate this record sat under that sentence, and each is closed
here because lending a temporary for writing reaches them. A part taken out
of a value no place names, `(if first { near } else { far }).first`, walked
its subject as a read, so the part was copied out of a place that kept it;
the subject is now consumed, and what is left of it must owe nothing. And a
closure written in a call that is lent a place `inout` writes that place when
the callee calls it, so it counts as a mutation under [N-Aliased]:
`observe(total, inout [inout total] || …)` is refused, as
`observe(total, &total)` is.

**A temporary is discarded where it ends and runs no cleanup**, as every
temporary is. One that must be settled is refused by [O-Leak] at the argument:
a linear value, a closure owning one, a `Vec`. Such a value is bound to a
`var`, lent with `&` and settled afterwards. The lend adds nothing that was not
writable before: a closure's `inout` capture is still a lend of its source
place, checked by [O-Borrow] and [O-Escapes] as it is when the closure is given
to a `sink` parameter.

**A temporary takes no `&`; a place still requires it.** `&` marks a place of
the caller's that the call may change and that is exclusive during the call
([S-Mutation]). A temporary has no other reader and nothing to be exclusive
with, so there is nothing for the marker to say:

```linea
let found = arrivals.any(|parcel| parcel.weight > limit)
let seen = arrivals.any(&counting)
```

The first closure ends with the statement. The second is the caller's, and the
`&` says it may have changed. A place written without `&` is still
[S-Mutation], so forgetting the marker never silently changes a copy. `&`
before a value that is not a place stays refused: `&make()` already means
invoking a callable for mutation, and `&Counter { … }` names no place.

**A receiver is a parameter.** `fresh().advance()` lends the temporary
`fresh()` returns to an `inout self` and takes no marker, where ADR 0170 asked
for a `var`. `values.iterate().next()` and `values.iterate().find_counted(p)`
are therefore written as chains. `&fresh().advance()` is still refused, since
the marker binds to the first call after it.

**An `inout` parameter still takes no default.** A default is a constant
([T-Default]), and a constant is a place that cannot be written. Evaluating it
into a temporary on every call would declare a parameter whose omitted argument
the callee writes and no caller can read; a `read` parameter says that
already.

**An `inout` capture still requires a place.** `inout [inout count = start()]`
is [T-Lend]. A capture is held by the closure for as long as the closure is
used, which is not bounded by a statement; a value to own for that long is a
`sink` capture.

**Each operation has one form.** `map`, `map_err`, `and_then`,
`unwrap_or_else`, `fold`, `find`, `find_map`, `find_counted`, `for_each`,
`any`, `all`, `upsert`, `from_fn`, `from_fn_in` and `split` take their
callbacks `inout` under the short name; the `_inout` names and the `sink`
wrappers are removed, and `F: Discardable` leaves their signatures, since the
operation no longer drops a callback. A closure written in the call is a
temporary; a named callback is lent with `&` and stays with its caller, so one
callback serves several operations and one owning a resource is recovered
afterwards. The lazy adapters (`map`, `filter` and `filter_map` on a
sequence) keep their callbacks `sink`, because the adapter stores
the callback past the call. `Map.merge`, `Map.update` and
`testing.each_allocation_failure`, which had no `_inout` form and consumed
their callbacks, are lent them too, so the library has one convention for a
callback an operation calls without keeping. A build gate refuses a declaration in `std/` or
`examples/` whose name ends in `_inout`.

The checker records which arguments are temporaries in
`Typing.borrowed_temporaries`, now with the convention each is lent under.
Lowering gives a temporary a slot and passes its address; the ownership
builder walks an `inout` temporary's argument as consuming and then yields it
where nothing can take it, which is the position [O-Leak] already asks about.
No pass decides again whether an argument is a place.

## Consequences

- One name per operation. A reader no longer chooses a form, and std loses
  seventeen declarations and their documentation.
- A named callback is no longer consumed by the operation it is passed to. It
  is lent, `xs.fold(0, &add)`, and usable again; `copy(heavy)` for a second use
  is no longer needed. A named callback passed without `&` is [S-Mutation],
  where it was accepted and moved, and a closure bound with `let` to be passed
  by name is bound with `var`, since only a place that may change is lent. A
  function's name is not a place and is passed as before, `xs.map(double)`.
- A callback owning something that must be settled cannot be written in the
  call. This is what the `sink` forms' `F: Discardable` already refused, now
  reported at the argument by [O-Leak] instead of at a bound.
- A write to a temporary is lost when the statement ends.
  `settings().raise(5)` is accepted and changes nothing a later statement
  reads. The marker rule keeps the common slip out: any place needs `&`, so
  only a value the caller could not have read again is lent this way.
- A place a branch of the argument names is moved, where under `read` it is
  observed. `bump(if c { a } else { b })` ends `a` and `b`.
- `Typing.borrowed_temporaries` holds one more entry per such argument; each
  costs a stack slot, as a `read` temporary does.

## Alternatives considered

**Keep the `_inout` pairs.** The library stays as it was: two names per
operation, a wrapper per pair, and a rule ("a temporary may be read but not
written") that exists only because the temporary's lifetime was first defined
for `read`. Nothing about a temporary makes writing it unsound; it has one
owner and one user.

**Implement the callable trait for a lent callable**, as Rust does with
`impl<F: FnMut> FnMut for &mut F`. One `sink` form would then accept both a
closure and `&mut counting`. Linea has no reference values: `&` is a marker at
a call site, not an expression with a type, so there is no `inout F` type to
implement a trait for, and adding one would bring a second kind of value whose
lifetime must be tracked through fields, results and generic arguments. That
is the machinery `borrow T` has for reads and that ADR 0193 deliberately kept
out of writes.

**A `sink`-only form that hands the callback back.** `fold` would return
`(total, combine)`, and a caller wanting the state would destructure it. Every
call that does not want it would discard a component, a linear callback would
make every such call a settlement, and results that today read as values
(`Option[U]`, `Bool`) would become tuples.

**Require `&` on a temporary too.** `xs.any(&|x| x > 3)` would keep "every
`inout` argument is marked" exact. The marker would then say nothing about the
caller's state, which is all it is for, and `&f()` already means a mutable
invocation, so a marked call result would be ambiguous with it.

**Let a temporary be settled by a `Release` it implements.** Discard never
runs cleanup anywhere else in the language, and a call that released its
argument would be a `sink` parameter under another name.

**Exempt receivers.** `fresh().advance()` would stay refused to guard against
a lost write. The same write is lost in `advance(fresh())`, which the rule
accepts, and the receiver is where the rule is most useful: an iterator built
in a chain is advanced without a `var`.
