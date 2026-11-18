# 279. An `extern` naming a C `ifunc` is held to the type C declares for it

Status: Accepted — 2026-11-17. Supersedes the clause of
[0262](0262-a-hand-written-c-declaration-is-held-to-the-c-compilers-prototype.md)
that refuses every symbol the IR of a root's C makes an `ifunc`.

## Context

0262 holds every `extern` to the prototype its root's C declarations give the
function, and reads the symbol C calls it by from the LLVM IR `cc` writes for
a global that keeps the function's address. Where that IR made the symbol
anything but a function it declares or defines, 0262 refused the `extern`, an
`ifunc` among them, "which the loader resolves to a function no declaration
describes".

That reason does not hold for an `ifunc` C declares. GCC and Clang accept
`__attribute__((ifunc("resolver")))` only on a function declaration, so the
declaration states the function's type, and every C caller calls the symbol
through that type, whatever the resolver answers when the program loads. A
resolver answering a function of another type is a lie in C itself, the same
lie a header declaring a function wrongly tells, which 0262 already believes.
Refusing the `ifunc` left a project with a C wrapper around it whose own type
was held to nothing more than the `ifunc`'s declaration.

What 0262 reads from the IR besides the symbol is how C passes an enumeration:
its width, and for one narrower than 32 bits whether C extends it by sign or by
zero. A `declare` or `define` line carries `signext` or `zeroext` where C
extends a value. An `ifunc` line states only the function's type,
`@twice_of = ifunc i64 (i64), ptr @twice_resolve`, so it gives an
enumeration's width and nothing about its extension.

## Decision

**An `extern` naming a symbol C makes an `ifunc` is held to the function type
C declares for it ([T-ExternPrototype]).** The declaration is compared position
by position with the prototype the `extern` implies, as for any function: a
declaration without a prototype, `long long twice_of()`, states no parameter
types and is refused as any unprototyped declaration is, and so is one of
another width, another arity or another calling convention. The symbol, its
label and its reservations are read as for a function.

**An enumeration narrower than 32 bits is not compared through an `ifunc`.**
The `ifunc` line gives the enumeration's width, which settles a 32- or 64-bit
one, since C passes those alike whatever their signedness. A narrower one is
passed extended by its signedness on targets whose convention extends it, and
the line does not say which, so such a parameter or result matches nothing and
is refused, as an enumeration behind a pointer is.

An alias, a variable and every other global that is not a function stay
refused, as 0262 decided.

## Consequences

- A project's own C may define an `ifunc` and a Linea declaration may call it
  directly; the conformance corpus runs one.
- What the resolver answers is believed, as the rest of a C declaration is.
  An `ifunc` whose resolver answers a function of another type is undefined
  behaviour in C, and stays outside what the compiler checks, beside a lying
  header, a weak definition another object replaces and a `.symver` binding.
- An `ifunc` taking or answering an enumeration narrower than 32 bits is still
  called through a C wrapper that takes an integer.

## Alternatives considered

**Keeping every `ifunc` refused.** Sound, but the refusal protected nothing
the declaration does not already: the `extern` is held to the type every C
caller uses, and the wrapper 0262 recommended is held to the same declaration.

**Reading an enumeration's extension from a call.** Compiling a call to the
`ifunc` in the probe would make `cc` write the extension at the call site. It
lost because it adds a third probe shape for one narrow case, while a C wrapper
taking an integer already reaches it.

**Comparing the resolver's answer.** The resolver is a C function returning
`void *` or a function pointer chosen at load time; what it answers is a value,
not a type `cc` can describe, so no comparison is available short of running
it.
