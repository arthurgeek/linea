# 153. An inherent implementation's function is a function value

Status: Accepted — 2026-09-23. Extends
[0105](0105-callable-values-have-static-call-targets.md).
Extended by [0176](0176-a-function-name-is-a-value-its-uses-instantiate.md).

## Context

[N-NotAValue] admitted a top-level function, including a public function reached
through a module, as a value where one exact structural callable type flows
inward. A member of any implementation was refused. An application that groups
its handlers by the resource they serve therefore could not register them:

```linea
impl Inventory {
    fn list[P: mem.Allocator](request: http.Request[P]) -> Result[http.Response[P], http.Error[P]] { … }
}

&router.route("GET /items", Inventory.list)?   // [N-NotAValue]
```

The workaround was a top-level forwarding function per handler, which is the
grouping the `impl` block was written to express, spelled a second time.

A member of an inherent implementation names one body. The qualified path
`Inventory.list` already says which declaration is meant, exactly as `stock.list`
does for a module function. A member of `impl Trait for T` is different: which
implementation a trait member names is not known until a type is chosen, so its
path does not name a body at all.

## Decision

**A function with a body declared in an inherent implementation is a function
value** on the same terms as a top-level function, reached through its qualified
path (`Inventory.list`, `stock.Inventory.list`).

- An associated function (no `self`) converts exactly as a top-level function.
- A method converts with its receiver as the first parameter, carrying the
  receiver's convention: `inout self: Inventory` becomes an `inout` first
  parameter, and `sink self` a `sink` one. This is Go's method expression.
- A member of a generic implementation, `impl[T] Holder[T]`, is written over the
  implementation's parameters as well as its own. The contextual callable type
  must select both lists, each argument must satisfy its bound, and an
  unselected implementation parameter is [T-Infer], as an unselected function
  parameter is. Selection is the routine that selects a generic function's
  arguments, walked once per list; there is no second matcher.

Trait signatures, members of `impl Trait for T`, tests and `extern` declarations
remain refused.

The checker records the selected receiver type on the function value beside the
member's own type arguments. Discovery and lowering derive the instance key from
it through the same reading a direct call to the member uses — the receiver
keying and the implementation arguments — so a converted member and a called one
name one instance.

## Consequences

- `FunctionValue` carries `self_ty`: the implementation's head read through its
  settled parameters, poison for every other target. It is the same value a
  direct call records for its settled head, and it is substituted through the
  enclosing instantiation where the conversion sits inside a generic body.
- A named callback argument to a generic function pre-selects a generic
  implementation's parameters together with its own, so `open(holder, Holder.take)`
  settles `T` from the callback parameter's type.
- A call to a member remains a direct call to its declaration. Only a conversion
  produces a code pointer.

## Alternatives considered

**Owned callbacks.** Registering a closure that captures a receiver, or an owned
callback type, would let a handler carry state. It needs a callback
representation the router does not otherwise use, and it answers a different
question: grouping stateless handlers needs no environment. Rejected for this
purpose; it remains open as its own decision.

**Method values bound to a receiver.** `inventory.list` as a value would close
over `inventory`, which is a capture with an ownership decision attached — is
the receiver copied, borrowed or moved into the value? The method expression
`Inventory.list` takes the receiver as an ordinary first parameter, so every
convention stays visible at the call and no capture is created. Rejected.

**A separate matcher for implementation parameters.** Settling the head by
matching the receiver parameter alone would miss an associated function whose
head parameter appears only in its result, and would be a second implementation
of what the signature walk already does. Rejected.
