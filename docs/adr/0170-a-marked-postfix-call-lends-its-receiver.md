# 170. A marked postfix call lends its receiver

Status: Accepted — 2026-09-24.

## Context

[ADR 0025](0025-mutation-through-a-parameter-is-marked.md) requires `&` on
every argument a call may mutate, so that a reader sees which arguments can
change without opening the function. A postfix call's receiver is an argument
the source does not spell as one: `list.push(x)` passes `list` as the first
parameter of `push`. When that parameter is `inout self`, the call had nowhere
to put the marker. `list.push(x)` was refused with [S-Mutation], and the only
accepted spelling was the path form, `Vec.push(&list, x)`, which names the
type and moves the receiver into the argument list.

`&list.push(x)` already parsed, as mutable callable invocation: the marker
binds to the first call after it ([S-Mutation]) and asked for `list.push` to
be a callable place. It was refused with a report about callables, and the
operation was also reported unused because the resolver read the callee as a
place and never noted the operation's name. Under
[ADR 0161](0161-a-postfix-call-reaches-an-operation-never-a-field.md) the
postfix form `x.op(args)` always names an operation and never a field, and a
stored callable is invoked `(x.f)(args)`, so `&x.op(args)` no longer has a
callable reading to compete with.

## Decision

**`&x.op(args)` calls the operation `op` with `x` as its `inout` receiver.**
The `&` marks the receiver exactly as `&x` marks an argument: it is required
where the receiver is `inout`, refused where it is `read` or `sink`, and the
receiver must be a writable place held exclusively for the call.

- The receiver is the place written before the operation's name:
  `&a.b.push(x)` lends `a.b`, `&items[i].push(x)` lends `items[i]`, and
  `&(list).push(x)` lends `list`.
- The marker binds to the first call after it, the rule mutable invocation
  already follows. In `&list.first().push(x)` it marks the receiver of
  `first`; `push` takes what `first` returned. A chain lends one receiver,
  the one at its head.
- `x.op(args)` with an `inout` receiver is refused with [S-Mutation], and the
  report spells `&x.op(...)`. `&x.op(args)` with a `read` or `sink` receiver
  is refused with [S-Mutation] as well.
- Exclusivity is [ADR 0053](0053-exclusivity-is-triggered-by-mutation.md)'s,
  unchanged: the lent receiver is a place mutated by the call, so
  `&list.push(list.length())` and `&a.merge(&a)` are [N-Aliased], and a
  marked postfix call inside another call's argument mutates its receiver for
  that call's rule too.
- A callable held in a field is invoked mutably as `&(x.f)(args)`.

`typecheck.lentReceiver` is the one answer to "which place does this marked
call lend as a receiver". The checker reads it to settle the marker against
the receiver's convention and to check exclusivity, and lowering reads it to
pass the receiver's address. The resolver, which runs before any call is
settled, resolves every marked callee as a place rooted at the binding being
lent, which is the receiver's root for a postfix call and the callable's
otherwise, and notes the selected operation's name for a postfix call as it
does for an unmarked one.

## Consequences

- An operation with an `inout self` receiver reads the same as any other
  operation at its call sites, `&v.push(x)` beside `v.length()`, and the
  marker still shows which call changes `v`.
- The path form stays valid and means the same thing; it is the spelling for
  reaching a trait's operation the postfix form does not reach.
- The syntax tree needs no new node: the call's `marked` flag records the
  `&`, and whether it lends a receiver or a callable place depends on whether
  the callee is a postfix selection, which only the checker knows.

## Alternatives considered

**Exempt the receiver, as Swift's `mutating` methods and Rust's `&mut self`
auto-borrow do.** `list.push(x)` would mutate `list` with nothing at the call
site to say so. That gives up the one thing ADR 0025 buys: a reader sees
every argument a call can change. Swift and Rust accept that the call site
does not show a mutating receiver: Swift relies on `var` at the declaration,
and Rust on the `mut` binding and its borrow checker. Linea marks mutation at
the call. An exempt receiver would be the one argument whose mutation is
invisible there, so `&` would stop being evidence.

**Keep the path form as the only spelling.** Every mutating operation call
would name its type, `Writer.write_str(&w, s)`, `Router.route(&r, …)`, and a
reader would meet two shapes for operations depending on the receiver's
convention. The path form is also where a trait's operation is reached when
the type declares one of the same name, so it reads as a disambiguation
where it is only a mutation.

**Bind the marker to the last call of a chain, or refuse a marker on a
chain.** Read as marking the value that changes, `&list.first().push(x)`
looks like it should lend what `push` changes. That value is the result of
`first`, which is no place, so the marker would lend nothing. Binding the
marker to the last call would also give `&` two binding rules: mutable
invocation, `&callback()`, already binds to the first call after the marker,
before `?` and before a later `.name`. Refusing a marker on any chain would
refuse `&counter.advance().doubled()`, which lends exactly the receiver at
its head and reads correctly. The first-call rule keeps one binding for `&`
on every call. A chain that lends the wrong thing is refused either way,
because a `read` receiver refuses the marker and an unmarked `inout`
receiver is refused, and the report says to bind the value to a `var`.

**Mark the receiver in place, `(&x).op(args)`.** It puts the marker on the
receiver, which is what it marks, but it is `&x` in a position where `&`
means nothing anywhere else, and it needs parentheses on every call. The
marker before the call is what mutable invocation already writes, so both
uses of `&` on a call read the same way.
