# 271. A callable head of any length has a shape

Status: Accepted — 2026-11-14; supersedes the sixty-parameter cap in the Shape
clause of [0213](0213-a-trait-may-be-implemented-for-a-callable-type.md).

## Context

[0213](0213-a-trait-may-be-implemented-for-a-callable-type.md) keys an
implementation headed by a callable type by its shape: the invocation and each
parameter's convention, in order. It packs the shape into 128 bits, which hold
sixty conventions, and refuses a head of more parameters with [T-Impl].

That limit belongs to the key and to nothing in the language. A function of
sixty-one parameters is an ordinary function, a callable bound accepts it, and
only writing `impl Trait for fn(..)` over its type was refused. The refusal is
the one place a representation's width showed in what a program may write.

What the key must stay is exact. Two implementations of one trait at one shape
and one argument list are [N-Duplicate], and implementations at different
shapes sit on different chains and never meet, so two shapes sharing a key
would refuse a valid program or compare implementations that cannot both
answer.

## Decision

**A callable head of any number of parameters has a shape, and the shape is
exact at every length.**

- **Up to sixty parameters** the shape is the packed key of 0213, unchanged.
- **Past sixty** the shape is a number given to that exact sequence of
  invocation and conventions, written into the same key under a parameter
  count no packed shape has, so a numbered shape equals no packed one.
- **Each pass numbers its own.** The resolver numbers a long shape by its
  spelling, one byte for the invocation and one for each convention, in a
  table it keeps beside its implementations; the table goes into a library's
  seed and is numbered again first and in the same order when a program
  resumes from that library. The checker numbers a long shape by the callable
  type that stands for it in the type pool: the same invocation and
  conventions over `Unit`, answering `Unit`. Every callable type of more than
  sixty parameters records that type when it is interned, so looking a type's
  implementations up reads the number and searches nothing. The pool is
  already exact, kept and reopened, so no second table is carried there.
- **No key crosses passes.** The resolver compares the shapes it numbered and
  the checker the ones it did, as each already compared only its own rows.

Everything else 0213 decides stands: one implementation per shape, the
ownership rule, exact matching of a function's signature against the written
head, and closures matching no callable head.

## Alternatives considered

- **A digest of the conventions.** Constant size and no table, but two shapes
  could share a key, and a shared key is a refused program or a wrong
  comparison. The key decides [N-Duplicate], so it cannot be probable.
- **A wider packed key.** It moves the limit and keeps it, and every head and
  every lookup would carry the width whether or not a program has a long
  callable.
- **One chain for every long callable, compared by signature.** It is what
  0213 rejected for all callables, for the reason given there: each
  implementation would be compared against every other.
- **The string interner for the spelling.** Its numbers do survive a resume,
  but the resolver holds it read-only and a resume checks that the library's
  strings are a prefix of the program's; interning during resolution would
  break that check.

## Consequences

- `impl Trait for fn(..)` is accepted at any arity, and [T-Impl] no longer has
  a case for a head's length.
- A program with no callable of more than sixty parameters builds no table
  and interns no extra type.
- A callable type of more than sixty parameters interns one more type, the
  one standing for its shape, shared by every type of that shape.
