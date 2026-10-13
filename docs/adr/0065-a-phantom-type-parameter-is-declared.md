# 65. A phantom type parameter is declared, not inferred from disuse

Status: Accepted — 2026-08-02

## Context

A type parameter that appears in none of a declaration's fields still does one
thing: it makes `Handle[DocTag]` and `Handle[AstTag]` different types. That is
the whole of *branding* — giving a family of values a compile-time identity so
that one family's values cannot be used where another's are expected.

The mechanism already works. A probe on `main` @ `dbdbcbb` established three
facts:

- `struct Handle[_Tag]` is accepted, the `_` prefix satisfying
  [0014](0014-unused-declarations-are-errors.md)'s escape hatch;
- the instantiation stays **Free** — a parameter appearing in no *part* obliges
  nothing, which is [0051](0051-a-part-obliges-when-no-argument-can-remove-it.md)
  answering exactly as written;
- one parameter shared across two positions ties them, so
  `at[Tag](read a: Arena[Tag], h: Handle[Tag])` reports
  `` `Tag` was already settled as `DocTag` here, and this is a `AstTag` ``.

So the question is not whether Linea can express a phantom parameter. It is
whether spelling one `_Tag` is the right way to say so.

## Decision

**A type parameter that appears in no field is declared `phantom`. The `_`
prefix does not stand for one.**

```linea
struct Handle[phantom Tag] {
    slot: UInt64,
    gen: UInt64,
}
```

Three rules follow, and each is the existing decision it descends from applied
without exception:

- **`phantom` is required where the parameter appears in no field.** Otherwise
  `[N-Unused]` reports it, unchanged. An accidentally unused parameter is a
  mistake and stays one.
- **`phantom` is refused where the parameter does appear in one.**
  [0056](0056-a-modifier-is-refused-where-it-says-nothing.md): a modifier is
  refused where it says nothing, and here it would be saying something false.
- **A phantom parameter takes no bound.** A bound constrains what an argument
  may be, and nothing about a type that appears nowhere can be constrained —
  a vacuous bound is the same mistake as a vacuous modifier.

### Why not the underscore

`_x` means *"this value exists and I deliberately do not read it."* A phantom
parameter is not that. It is read — by the type system, for identity — and the
program depends on it being read: remove it and `Handle[DocTag]` becomes
assignable to a `Handle[AstTag]`, silently.

**Calling it unused is not a shorthand, it is wrong.** A reader who takes
`_Tag` at its word concludes the parameter can be deleted, and deleting it
compiles and removes a guarantee. That is the failure mode this record exists to
prevent, and it is the same one 0056 exists to prevent one level up: a modifier
that says nothing is deleted by someone who believes it.

### Why the modifier precedes the name

`phantom Tag`, not `Tag: phantom`. Two reasons, and neither is taste.

Every modifier in the language already precedes what it modifies — `pub fn`,
`linear struct`, `opaque struct` — so a modifier that followed would be the only
one, for no gain.

And the position after the colon already means something: it is where a **bound**
goes. `Tag: Free` says what an argument must satisfy. Writing `Tag: phantom`
would put a statement about *how the parameter is used* in the slot reserved for
*what its argument must be* — and this record refuses a bound on a phantom
parameter outright, so the two would be spelled alike and be mutually exclusive.
That is the worst available arrangement.

### What it does not change

Identity, layout and universe are all decided already and none moves:
`Handle[A]` and `Handle[B]` are distinct types; a phantom parameter contributes
no bytes; and it contributes no obligation, per 0051. `phantom` states an
intent so that a reader and `[N-Unused]` can tell it from an error. It gives
the parameter no power it did not have.

## Consequences

**Branding is available at the type level, and only at the type level.** Two
arenas *of different tags* cannot mix, and that is a compile error. Two arenas
*of the same tag* can, and no static mechanism here separates them —
distinguishing two values of one type needs generativity, which needs closures.
The residual is real and is covered dynamically by a generation.

**A phantom parameter is settled by an argument or by an annotation, never by a
call's expectation.** A probe confirmed the limit:

```linea
fn make[Tag]() -> Arena[Tag] { .{ .base = 7 } }
let docs: Arena[DocTag] = make()
// error[T-Infer]: nothing here says what `Tag` is — no argument determines it
```

This is a property of the existing inference and not of `phantom`: no type
parameter is settled from a return-position expectation today. It shapes the
API a phantom parameter can have — construction goes through an annotated
literal, or the tag rides on an argument — and whether inference should flow
from the expectation is a separate question this record deliberately does not
answer.

**Two instantiations differing only in a phantom parameter compile to identical
code.** Whether they share a monomorphised body is a backend question that
[0047](0047-instantiation-is-a-backend-concern.md) already puts in the
backend's hands, and nothing here decides it.

## Alternatives considered

**Keep `_Tag`, and document it.** No new syntax, and it works today. Rejected
because the name asserts something false — the parameter is not unused — and a
reader acting on that assertion silently removes a guarantee. It also leaves no
way to tell a deliberate phantom from a forgotten parameter, which is the one
thing a declaration here has to do.

**Drop `[N-Unused]` for type parameters entirely.** Then an unused one is
simply legal and no marker is needed. Rejected under
[0014](0014-unused-declarations-are-errors.md): an unused declaration is an
error precisely because it is usually a mistake, and type parameters are not an
exception. It would trade a real diagnostic for a syntax saving.

**A bound that means "used only for identity"** — `[Tag: Phantom]`. Rejected as
a category error: a bound says what an argument must satisfy, and this says how
the parameter is used. Overloading the bound position to carry a role is how a
system ends up with bounds that are not requirements.

**A separate declaration form** — a `tag` or `brand` declaration distinct from a
type parameter. Rejected as a larger feature that buys nothing: what makes
branding work is that the tag is an ordinary type argument, so ordinary
inference ties two positions together. A distinct form would need its own
inference.

## Deliberately open

**Whether inference should flow from a return-position expectation.** It does
not today, for any parameter. If it did, `fn make[phantom Tag]() -> Arena[Tag]`
would work and the arena API would be simpler. The question that settles it is
whether the expectation is reliable enough at a call to instantiate from, which
is a question about inference generally and not about phantom parameters.

**Whether a phantom parameter may be declared on a function.**
`fn f[phantom T](x: UInt8)` names a parameter the body cannot use for anything.
Nothing needs it, and it is refused until something does.
