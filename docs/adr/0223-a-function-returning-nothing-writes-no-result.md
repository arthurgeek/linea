# 223. A function returning nothing writes no result

Status: Accepted — 2026-10-13.

## Context

Every function declared what it returned. One that returned nothing wrote
`-> ()`, and leaving the arrow out was [S-Type], "a function declares what it
returns". A `test fn` was the one exception: leaving out its result means
`Result[(), testing.Failure]` ([S-Test]).

`-> ()` was the most common result in the tree. About five hundred
declarations wrote it across the standard library, the examples, the guide and
the corpus: every `release`, every `inout` method that updates its receiver,
every callback type a router or iterator takes. It says nothing a reader needs:
a body that ends without a tail already produces `()`, and the call site of a
function returning nothing uses it as a statement. A first program that adds a
tip to a bill wrote `fn add_tip(inout bill: UInt64) -> () {`, which shows a
beginner the unit type before anything has needed it.

The same question arises wherever a result is written: methods in an `impl`,
a trait's bodyless signatures, `extern` declarations, the callable type
`fn(inout value: UInt8) -> ()` and a lambda's optional `-> T`.

## Decision

**A callable that returns nothing writes no result type, and `-> ()` is
refused.** `fn add_tip(inout bill: UInt64) { ... }` returns `()`. The rule is
one rule for every place a result is written:

- a function, `pub` or not, and a method in an inherent or trait `impl`;
- a trait's signature, `fn bump(inout self: Self)`;
- an `extern fn`, which names a runtime symbol returning nothing;
- a callable type, `fn(inout value: UInt8)`, which is the type of
  `add_tip`'s shape;
- a lambda, whose omitted result already took its body's type; `-> ()` on a
  lambda is refused like any other. A lambda writing contracts and no result
  keeps the arrow: `|x| -> where carries() { ... }`.

Writing `-> ()` in any of these places is [S-UnitResult], and so is `()` in
grouping parentheses, `-> (())`. The parser reports it at the `-> ()` with help
to remove it, and reads the declaration as the omitted form, so the rest of the
file is checked as if it had been written correctly. On a top-level `main` the
help is to write `-> UInt8`, since removing the result would leave an entry
point with no exit status. Only the unit type written as such is refused:
`-> Result[(), E]`, `-> ((), T)` and `-> Option[()]` hold a unit and are
unchanged. The parser reads spelling, not names, so an alias of `()` written as
a result is not refused; nothing in the library or the guide declares one.

A `test fn` keeps its own default: no result means
`Result[(), testing.Failure]`. A projection names a place, so it still writes
the place's type. `main` writing no result returns `()`, which has no exit
status, so [S-Entry] refuses it with a message asking for `-> UInt8`.

The checker answers "what does this callable return" in one routine: an
unwritten result reads as Unit for a declaration, a signature and a callable
type alike, and the body of a function writing none is checked against Unit,
with a mismatch pointing at the function's name ("this function writes no
result type, so it returns `()`"). The formatter prints the omitted form.

## Consequences

- One spelling. The formatter needs no rule choosing between two, and code
  review never asks which one a file uses.
- Every `-> ()` in the standard library, examples, guide and corpus is gone,
  along with the source the program generator and compiler tests write.
- A function's signature no longer always shows its result. A reader learns
  that no arrow means `()`, the same convention Rust, Swift and Go use for a
  function that returns nothing.
- `fn(x: UInt8)` as a type is now complete. A callable type missing its
  result by mistake reads as one returning `()`, and the mistake surfaces
  where a value of the wrong shape is passed to it rather than at the type.
- A `test fn` and an ordinary function differ in what an omitted result means.
  The difference was already there; it is now between two defaults rather than
  between a default and an error.

## Alternatives considered

- **Both spellings legal, as in Rust.** Rust accepts `fn f() -> () {}` and
  `fn f() {}` and lints the first. Rejected: two spellings for one signature
  is a choice every author makes and every reader re-checks, and Linea's
  formatter would then have to rewrite one into the other, which is the rule
  this record states, enforced later and less visibly. Refusing `-> ()` puts
  the rule where the code is written.
- **Status quo: every function declares its result.** Rejected: it made the
  most frequent result the noisiest one, taught `()` before a beginner needs
  it, and kept a second meaning of an omitted result (an error) beside the one
  tests already had.
- **Omitting the result infers it from the body, as a lambda does.** Rejected:
  a function's signature is what its callers are checked against, and an
  inferred result would make a body edit change every caller's types. An
  omitted result is a fixed `()`, so the signature is still read without the
  body.
