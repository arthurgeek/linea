# 68. A declaration may name a symbol the runtime provides

Status: Accepted — 2026-08-04. Extended by [0150](0150-float-math-crosses-a-checked-scalar-boundary.md) and [0156](0156-every-declaration-of-an-extern-symbol-is-one-function.md). The `std/` clause of [M-Extern] is superseded by [0171](0171-the-standard-library-is-an-ordinary-library.md), which grants the capability through a root's manifest.

## Context

Everything this language proves rests on a body it has read. The checker types
one, ownership walks one, the verifier refuses a module built from ones it
cannot account for. There is exactly one thing no Linea program can express: a
call to code the compiler did not compile.

Two features need it, and neither can be written in Linea at any price.
Text and writers need bytes to reach a file descriptor. Heap allocation (R2)
needs memory from an allocator. Both bottom out in a C symbol.

The compiler already emits one call it was not given — `linea_trap` — but
lowering writes that itself, from a trap it decided to insert. Nothing lets a
*declaration* name a symbol, and so nothing lets library code be the thing that
calls out.

## Decision

A declaration may name a symbol the runtime provides, and has no body:

```linea
extern fn linea_write(fd: Int32, at: UInt64, len: UInt64) -> Int64
```

**`[M-Extern]` — an `extern` declaration is only in the library.** Outside
`std/` it is refused. A rule and not a convention, because a convention the
compiler does not check is one that will be broken, and the thing it is
protecting is the only place the language stops checking.

**`[T-Extern]` — what crosses is what the language fixes the representation
of.** A scalar crosses; an aggregate does not, and neither does a linear value.
A body written for one anyway is the same rule: an `extern` with a body is not
an `extern`.

**The hole is the point, and it is not closed.** An `extern` is a signature the
compiler believes. Nothing here makes that safe; what it does is make the
believed surface small, enumerable, and shipped with the compiler rather than
written by a program. The mitigation is the size of the boundary, not a proof
about what is across it.

## Why those three

**Why only in `std/`.** The trusted surface should be a handful of declarations
in one directory that arrives with the compiler and is reviewed with it. Any
other boundary — an attribute, an allow-list, a capability — makes the surface a
property of the program being compiled, which is the thing that must not vary.
A program that could declare its own `extern` could declare `free` and call it
twice, and every guarantee the ownership pass makes would be decoration.

**Why an aggregate may not cross.** Where a structure's fields sit is the
compiler's to decide ([ADR 0031](0031-fields-are-packed-at-their-natural-alignment.md)),
and the suite reorders declarations to prove nothing observes it. Handing one to
C fixes that layout at the boundary and makes it observable, so the rule the
corpus checks and the rule the library relies on would disagree. A scalar has no
such freedom: its width and signedness are the whole of its representation.

**Why a linear value may not cross.** Ownership proves a value is consumed
exactly once by reading every path it takes. A path into C is not a path it can
read, so a linear value handed across is one the pass would have to assume
about — and it is precisely the pass that must not assume.

## What this is not

**Not an FFI.** There is no header to import, no calling convention to select,
no struct to marshal, no callback to register. It is one declaration form that
names a symbol with scalar arguments, and the C on the other side is written in
this repository.

**Not a version bump.** Adding a symbol is caught by the linker: a compiler
emitting `linea_write` against a runtime without it fails to link, on that name.
The runtime's ABI stamp exists for the changes a linker cannot see — a signature
that changed under a symbol that still resolves, or a trap kind whose meaning
moved — and adding a declaration is not one of them.

## Consequences

- `extern` stops being part of the allocator. It had been bundled with R2 only
  because memory was the first thing that needed a call; the first one is now
  a single write to a file descriptor, which is a much smaller thing to get
  wrong, and R2 inherits the form already exercised.
- The library gains a floor it did not have. Everything above `linea_write` —
  the writer, the traits, decimal rendering — is ordinary Linea, and this is the
  declaration that lets it be.
- Every `extern` is a line in a review. There will be few, they will all be in
  one directory, and the count is a number worth watching: it going up is the
  trusted surface growing.
- A sanitizer can now say something the type system cannot, because there is
  now code the type system did not check. That is a new kind of test job and
  not a new kind of rule.

## Alternatives considered

**An intrinsic.** The compiler knows the name and lowers a call to it specially,
as it already does for `linea_trap`. Rejected: it makes every runtime entry
point compiler knowledge, so adding one is a compiler change and the list lives
in Zig rather than in the library it serves. `linea_trap` is an intrinsic
because lowering *decides* to insert it, with no declaration anywhere to hang it
on; a call the library writes has a declaration, and the declaration is the
better place for it.

**A general foreign-function interface.** Headers, layouts, conventions,
callbacks. Rejected as answering a question nobody has asked: the only C this
language calls is the runtime it ships with, and a general mechanism would buy
generality at the cost of the one property that makes this tolerable, which is
that the surface is small enough to read.

**`extern` anywhere, with a convention that it belongs in `std/`.** Rejected for
the reason above: the boundary is the whole mitigation, and an unchecked
boundary is not one.

**A capability, so that a function's signature says it can reach the runtime.**
Rejected as the wrong axis. A capability bounds what a *program* may do at
runtime; the danger here is what a *declaration* asserts at compile time, and no
value threaded through a call fixes that. It is also a much larger decision than
this one, and taking it here would settle it by accident.
