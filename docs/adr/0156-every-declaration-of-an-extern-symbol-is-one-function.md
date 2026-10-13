# 156. Every declaration of an extern symbol is one function

Status: Accepted — 2026-09-23. Extends 0068.

## Context

[ADR 0068](0068-a-declaration-may-name-a-symbol-the-runtime-provides.md) lets a
standard-library declaration name a symbol the runtime provides. It said
nothing about two declarations naming the same symbol.

Two modules met that case as soon as both needed the same runtime entry point.
`std.fs` closes file descriptors and `std.net` closes sockets, and each declared
`extern fn linea_close(fd: Int32) -> Int64`. Instance discovery keyed a body by
its declaration, so the two declarations became two instances. Both were
spelled `linea_close`, and MIR verification refused the module with exit 70:
"function N and function M are both named `linea_close`". Any program reaching
both closes failed to compile.

## Decision

**Every `extern` declaration of one symbol names the one function the runtime
provides under it.** The checker groups extern declarations by symbol. The
first declaration of a symbol, in module and declaration order, stands for the
symbol. Each later declaration is recorded against it in
`Typing.extern_symbols`. Instance discovery keys an extern body through that
table, so every declaration of a symbol reaches one instance and emits one
function declaration.

**[T-ExternAgreement] — the declarations agree.** One function has one
signature. The declarations must agree on arity, on each parameter's type and
convention, and on the result. Parameter names and defaults belong to each
declaration, because they shape the calls written against it and not the
function called. A declaration that already violates [T-Extern] is not compared
as well: its signature says nothing a comparison could check.

## Consequences

- A library module declares the runtime entry points it calls, next to the code
  that calls them. Two modules need no shared dependency to reach one symbol.
- The trusted surface stays countable by symbol. A symbol declared twice is
  still one entry in the runtime's ABI, and one wrong signature among its
  declarations is refused in the checker. Otherwise it would be a call reaching
  the right body with the wrong arguments.
- Instance discovery has one more table to read, in the single routine that
  both interning and lookup call.

## Alternatives considered

**Refuse duplicate extern names across modules.** This is simpler to check, but
it makes where a declaration lives a global question. A module could not
declare the entry point it uses when another module already did, and adding a
declaration to one module could break an unrelated one. The C model, where a
repeated compatible declaration names one symbol, answers the actual need.

**One shared standard-library module holding every extern.** Each consumer
would call through a helper in a common module (for example `io.Descriptor`).
This was the workaround the defect first forced. It couples otherwise
independent modules to a helper that only exists to dodge the symbol clash. It
also needs a leading-underscore `internal` function to escape the unused rule in
programs that import neither consumer. That shape is dictated by a compiler
defect, not by the library's design.
