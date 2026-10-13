# 199. Tuple syntax denotes a positional aggregate whose identity is a prelude declaration

Status: Accepted — 2026-10-04

Builds on [0060](0060-a-library-declaration-is-named-through-the-prelude.md),
[0129](0129-struct-destructuring-may-infer-its-type.md),
[0151](0151-a-named-structure-literal-carries-a-written-type.md),
[0179](0179-the-prelude-holds-the-core-vocabulary-and-yields-to-a-module.md)
and [0188](0188-the-unit-value-is-written-as-its-type.md).

## Context

Adapters that pair values, functions with two results and loops over pairs
need a value with positional parts and no declaration written by the program.
The compiler represents a type as a pool entry, and every pass switches over
the pool's kinds. Ranges are typed as a construction of a prelude declaration
rather than as a kind of their own, and the same route is open to tuples.

## Decision

**`(A, B)` denotes a positional aggregate. After syntax resolution it is an
ordinary struct instantiation of the prelude's `Tuple2[A, B]`**, a
`@copyable` struct with fields `_0` and `_1`, and likewise through `Tuple8`.

- The resolver reaches the declaration through `Resolution.tuple_decls`, the
  one table from arity to declaration, filled from the prelude's
  `Tuple2`..`Tuple8`; `node.isTupleArity` is the one statement of the arity
  bound. The checker, the type pool and the prelude gate read the table; the
  resolver, the checker's builder and the type pool hold copies filled from
  that one source, and none derives the table another way.
- The parser produces `tuple_literal`, `tuple_pattern` and a `.tuple` written
  type. The checker types them as a construction, a pattern and an
  instantiation of the arity's declaration. `Builder.instantiate` spells the
  instance `(A, B)`, and `writeTypeName`, the routine every report names a
  type through, writes the same spelling.
- A tuple of an arity the parser admits but whose prelude declares no type is
  [T-Literal], as text is where no `Str` is declared. A tuple of an
  arity the parser refused was reported by [S-Tuple] and is poisoned without a
  second report.
- A component is the field `_n`, which the declaration names and which every
  pass reads from it: `t._0` selects a component, and `Tuple2[A, B] { _0 = ..,
  _1 = .. }` is the long form of the literal, since a tuple is an ordinary
  struct. Programs write positions through the literal and the pattern, and
  reach a field by name only to select one.
- Capabilities are the declaration's under [O-Universe]: `@copyable` is
  conditional on every component. `std/tuple/tuple.lin` supplies `Equatable`,
  `Equivalent`, `Comparable`, `Ordered`, `Hash`, `Default` and `Release` as
  derives, and `Debug` and `Display` by hand.
- `()` remains the unit type, the tuple of no components. `Tuple2` may be
  named as a type. A module's own `Tuple2` shadows the name and not the
  syntax.
- Coherence compares written type names by the declaration they reached, not
  by their spelling: `(A, B)`, `Tuple2[A, B]` and `tuple.Tuple2[A, B]` key one
  implementation, a module's own `Tuple2` keys another, and two type
  parameters are two names whatever declaration holds them
  (`sameNameWritten`).
- A tuple literal determines its own type only where every component does
  (`determinesItsOwnType`). Components are independent, so a literal with one
  open component waits for the expected type to flow in, as a lambda with an
  unwritten parameter does; otherwise `first((3, true))` would settle `3` to
  `Int64` before the result met `UInt8`. A component of a literal checked
  under an expected tuple carries the outer expectation's reason and position,
  so a mismatch names the annotation or parameter that gave the tuple its
  type.

## Consequences

- No semantic representation kind is added downstream of the AST and the type
  pool; the AST gains three node shapes.
- A declaration head admits one implementation per trait program-wide
  ([0081](0081-an-implementation-is-generic-over-its-head.md)), so a tuple
  has one generic implementation per trait per arity. The standard library
  supplies `Display`, `Debug` and the derived seven, so no other library takes
  a slot from another.
- The declaration's name shows in `[T-Bound]` reports about the declaration
  itself, in symbols, in go-to-definition and to reflection templates.
  Diagnostics that spell the type, hover and dumps say `(A, B)`.
- A derive on a tuple copies a field's written type by token range, so
  reflection needs no tuple arm.
- A program checked without the library has no `Tuple2`, so a tuple there is
  [T-Literal].

## Alternatives considered

**A `tuple` kind in the type pool.** Every exhaustive switch over `Type` gains
an arm, a derive cannot target it, and component access needs a spelling the
field grammar lacks. Its one gain, a head keyed by component types admitting a
different implementation per shape, is not worth the arm in every pass.

**A `Tuple0` for the unit type.** Unit is a reserved handle every pass reads;
a declaration beside it would be a second answer to what the unit type is
([0188](0188-the-unit-value-is-written-as-its-type.md)).

**Refusing `Tuple2` by name.** It is a resolver rule against one spelling,
and a module's own `Tuple2` would then need a carve-out. A range's long form
is the precedent for leaving the declaration nameable.
