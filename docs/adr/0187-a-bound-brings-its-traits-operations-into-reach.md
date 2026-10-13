# 187. A bound brings its trait's operations into reach

Status: Accepted — 2026-09-27. Extends
[0186](0186-a-type-reaches-the-operations-of-the-traits-it-implements.md) and
[0160](0160-a-postfix-call-reaches-the-types-own-operation-first.md), whose
single `Reach` routine now reads the traits a bound names as well as the
traits the module sees.

## Context

ADR 0186 let `T.default()` under `T: Default` reach `Default.default()`, and
ADR 0160 let `x.op()` on a `T` value reach a bound's operation. Both asked
only the traits the call's module sees: the prelude's, the module's own, and
the ones a `use` names. A bound written through a module path names a trait
the module does not see, so under `T: text.Parse` both `T.parse(text)` and a
postfix call on a `T` were refused with [T-UnknownField] or
[T-UnknownOperation] until the file also wrote `use text.Parse`. The standard
library wrote `strings.Parse.parse(text)`, `release.Settle.settle(failure)`,
`hash.Hash.hash(self[index])` and `io.Close.close(accepting)` in generic
bodies for that reason alone.

The import rule exists so that importing a library cannot change what an
existing call means: which traits are in play is what the module chose to
see. A bound is also a choice the code wrote down. It names the trait, at the
declaration whose body the call sits in, and it is the evidence that the
parameter implements that trait. Rust calls a bound's methods on the bounded
type without importing the trait for the same reason.

## Decision

**A bound puts its trait's operations in reach for the type it bounds.** A
trait named by a bound on a type parameter, including a trait that bound's
trait requires, or by a `where` clause in force at the declaration, answers
`T.op()`, `x.op()` on a `T` value, and `T.Item`, whether or not the module
sees it. `fn fresh[G: gauge.Gauge]() -> G { G.zero() }` compiles without
`use gauge.Gauge`.

**A concrete type keeps the import rule.** The bound reaches the parameter it
bounds and nothing else: inside `fresh`, `gauge.Tank.zero()` is still
[T-UnknownOperation] with the `use` that brings `Gauge` into scope.

**One routine decides.** `Reach` enumerates the type's own operations, then
the traits the module sees, then the traits a bound on the type names that the
module does not see, each once. `NameReach.reaches` reads the whole
enumeration as before: the type's own operation first, a single trait's
otherwise, and [N-Ambiguous] where two traits answer, whether each was reached
through the module or through a bound. The report for a name only an
out-of-scope trait answers leaves out a trait a bound names, since no `use`
would add it, and the one ambiguity report, for the postfix form and the
written form alike, writes such a trait's spelling through its module,
`gauge.Gauge.zero(…)` or `gauge.Gauge.reading(…)`.

## Consequences

- Generic code calls a bound's operations through the parameter or the value,
  as `T.parse(text)`, `failure.settle()` and `accepting.close()`, without a
  `use` and without the trait's path.
- Adding a bound can make a name ambiguous, as importing a trait can:
  `G: gauge.Gauge + Blank` leaves `G.zero()` [N-Ambiguous] where both declare
  `zero`. It never changes silently which operation runs. A bound was already
  able to do this for a trait in scope, so this adds no new hazard.
- Associated types already read a parameter's bounds directly, so `G.Unit`
  under `G: gauge.Gauge` needed no change. Operations now read them the same
  way.
- The lookup costs the bounds on the receiver within the declaration, and for
  each bound's trait out of scope, its members. Nothing is sized by the
  program.

## Alternatives considered

**Keep the import rule for bounds.** A bound through a module path would then
be the one place where naming a trait does not let the code use it, and every
generic body would repeat the trait's path or add a `use` whose only purpose
is to repeat what the bound says.

**Make a bound's trait visible to the whole declaration.** That would let
`gauge.Tank.zero()` inside `fresh` reach `Gauge`'s operation because some
parameter happens to be bounded on it. The bound is evidence about the
parameter, not a `use`, and Rust also reaches only the bounded type this way.

**A second lookup over the parameter's bounds.** The checker could search the
bounds when `Reach` answers nothing. That would be a second reading of which
traits are in play, and it would disagree with `Reach` on ambiguity: a bound
trait and a trait in scope that both declare the name would pick the one in
scope instead of reporting both.
