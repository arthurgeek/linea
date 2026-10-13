# 18. Fixed-width integers, literals typed by context, conversions explicit

Status: Accepted — 2026-07-25

Extended by [0207](0207-linea-converts-nothing-implicitly.md), which collects
the rule that no conversion is implicit.

## Context

[ADR 0013](0013-no-undefined-behaviour.md) forbids undefined behaviour and
Stage 1 computed in a single placeholder type. An entry point returning `u8`
([ADR 0019](0019-entry-point-is-main-returning-u8.md)) forces a second type,
and two types force every question a numeric tower raises: what a literal's
type is, whether values convert implicitly, and what happens when a conversion
cannot succeed.

The references split on the first question and agree on the rest. Rust infers a
literal's type from use and falls back to `i32`; Go and Odin treat literals as
untyped constants with a default; Hylo's default is `Int`, *"which represents a
64-bit signed integer"*; Swift takes the type from context and defaults to
`Int`. Only Zig refuses a default. On implicit conversion the agreement is
near-total: Austral has *"no implicit type conversions"*, and Rust and Zig
require every width change to be written.

## Decision

**Eight fixed-width types**: `i8`, `i16`, `i32`, `i64`, `u8`, `u16`, `u32`,
`u64`. `Int` names `i64` and is what an unconstrained literal becomes.

Pointer-sized types are deliberately absent. `isize` and `usize` exist to size
pointers and indices, and Linea has neither, so including them would mean
defining target-dependent widths for types nothing can use — and would make
emitted code and its expectations differ per target for no benefit. They arrive
with the first thing that needs a machine word.

**A literal takes the type its context asks for.** `let x: u8 = 4` makes `4` a
`u8`; `let x = 4` makes it `Int` because nothing asked. A literal outside its
target type's range is ill-formed and reported where it is written.

**No implicit conversions and no mixed-type arithmetic.** Operands must have
the same type; `u8 + i64` is an error rather than a promotion. An implicit
promotion would be a conversion the programmer did not write, and under
[ADR 0017](0017-failure-is-a-trap-or-a-value.md) a conversion can trap — so an
invisible one could abort a program at a point with nothing in the source to
point at.

**Conversion is written `u8(x)`**, and it traps when the value does not fit.
The syntax is a built-in form for now, spelled so that it can become an
ordinary call once generics can express it, and the source will not change when
it does. Odin, Go and Swift all spell conversion this way.

A fallible conversion — returning `Option(u8)` rather than trapping — is a
separate operation with a separate name, and is written when something can
produce a value the programmer did not choose. Nothing in Linea reads input
yet, so every out-of-range conversion today is a programmer mistake by
definition.

Wrapping arithmetic is deferred on the same grounds. It is genuinely wanted for
hashing and bit manipulation, none of which Linea can express, and both Austral
and Swift show it is uncontroversial to add later as distinctly-spelled
operations.

## Consequences

- Arithmetic across types is verbose, which is the intent: every width change
  is visible, and every one of them can trap.
- A literal's meaning depends on its context, so moving an expression can
  change what its literals mean. The compensating property is that annotations
  read naturally and no conversion is written for a value the programmer
  spelled out.
- `Int` being `i64` rather than the machine word means a program computes the
  same thing on every target. It also means the default type is not the
  fastest one on a 32-bit machine, which is a trade taken deliberately.
- Eight types multiply the overflow bounds, conversion pairs and diagnostics
  that must be tested. The bounds are a table rather than a special case, so
  the cost is in the corpus rather than the code.
- Every conversion costs a check unless the compiler can prove otherwise, since
  [ADR 0013](0013-no-undefined-behaviour.md) forbids removing one on faith.

## Alternatives considered

**Keep a single integer type until Stage 3.** Smallest change, and it defers
the whole tower. Rejected: the entry point returns `u8`, so a second type
exists whether or not the language admits it, and a boundary check standing in
for a type system is a worse version of the same work.

**Untyped literals with arbitrary precision, as Zig's `comptime_int`.** Lets
intermediate results exceed any machine type as long as the final value fits,
which is genuinely more expressive for constant expressions. Rejected for now:
it needs big-integer arithmetic in the compiler and puts two kinds of integer
in the language, which is a large feature to adopt for constant folding.

**Implicit widening, explicit narrowing.** Removes the noise from the safe
direction, which is most conversions. Rejected: it makes the type of an
expression unreadable from its operands, needs promotion rules for mixed signs
where neither type contains the other, and reintroduces the invisible
conversion that no-UB makes dangerous.

**Rust's default of `i32` for unconstrained literals.** Rejected only on
target: a systems language whose arithmetic defaults to a 32-bit type on
64-bit hardware is choosing the narrower default, and the systems languages
among the references — Go, Hylo, Swift — all default to the wider one.
