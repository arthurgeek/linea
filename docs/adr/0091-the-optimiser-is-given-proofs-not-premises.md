# 91. The optimiser is given proofs, not premises

Status: Accepted — 2026-08-17. Extends
[0013](0013-no-undefined-behaviour.md).

## Context

[0013](0013-no-undefined-behaviour.md) says every operation produces a defined
result or is a diagnosed error, that which of the two does not depend on the
optimisation level, and that the compiler may not treat the absence of undefined
behaviour as a premise for optimisation. It states the rule and does not defend
its cost, because until now nothing asked it to.

QBE has no no-signed-wrap flag, no aliasing metadata, no poison and no fast-math.
The question of whether to assert any of them could not arise, so the rule was
free.

[0090](0090-the-backend-is-mlir-printed-rather-than-constructed.md) moves the
backend to a toolchain where every one of those exists, is opt-in, and is the
conventional thing to emit. The question arrives with a claim attached — that a
language forbidding undefined behaviour gives up the optimisations undefined
behaviour licenses — and it will be put to this project by readers who know
compilers. A rule whose cost is undefended is a rule that gets relaxed the first
time someone measures something.

## Decision

**Nothing is asserted to the optimiser that the compiler has not proven.
Performance forgone by 0013 is recovered by proof, never by premise.**

**This is not a rule against telling the optimiser things.** It is a rule about
what justifies telling it. *These accesses do not alias*, *this value is in this
range*, *this branch is unreachable* are all facts a backend may assert, and
should, when this compiler established them for this program. What is refused is
an assertion whose only justification is a language-level premise — *signed
overflow cannot happen because the standard says it is undefined* — that nothing
established here. Read as "emit maximally conservative IR", this record would be
saying something it does not say and something 0013 does not require.

What is therefore not emitted:

- **No no-signed-wrap or no-unsigned-wrap flags.** Arithmetic is emitted with
  its overflow check, because the check is what makes the result defined.
- **No type-based aliasing metadata.** Two accesses may be reordered when
  something proved they do not overlap, never because their types differ.
- **No fast-math, in any form.** This is not a new clause: the float design
  already forbids reassociation, contraction of a multiply and an add,
  reciprocal substitution, and any assumption that `x == x`.
- **No reliance on poison or on an undefined value.** Memory arrives zeroed, so
  a read of what nothing wrote is defined.

What is permitted, because 0013 permits eliding a check *proven* unnecessary:

- **A no-alias assertion where ownership proved exclusivity.**
  [0053](0053-exclusivity-is-triggered-by-mutation.md) decides that exclusivity
  is triggered by mutation, and the fact it establishes is exactly the fact the
  annotation asserts. Emitting it is reporting a proof, not making an
  assumption.
- **Overflow-check elision where a bound is proven**, in a counted loop or
  anywhere else the range is known.

The distinction is the whole of this record: **an assertion the compiler proved
is an optimisation; an assertion the language mandated and the compiler assumed
is a premise.** The first is allowed and wanted. The second is what 0013 forbids.

## Consequences

**The majority of an optimiser is unaffected**, because it is proof-based
already: value numbering, loop-invariant motion, scalar replacement, inlining,
dead-code elimination, register allocation.

**What is genuinely forgone is narrow, and two of the four remove no premise
Linea ever had.** Signed and unsigned overflow as a premise for loop reasoning
is the one with a real price — `[T-Overflow]` requires an operation's result to
lie in its type's range whatever that type's signedness, so neither wrap flag is
available. Type-based aliasing is the second, and it is also the most notorious
defect source in the languages that offer it. Null-derived assumptions do not
apply, because there is no null. Uninitialised reads are already defined,
because memory arrives zeroed.

The last two are listed for completeness, not as savings. Zeroing memory has a
cost, and it is paid; what it does not do is forfeit an optimisation this
language could otherwise have licensed.

**A trapping add is not information lost — it is the same information made
explicit.** A wrapping language asserts *this did not overflow* with a flag; a
trapping one branches on whether it did. On the edge that continues, no overflow
occurred, and that is precisely what the flag claimed. An optimiser that
propagates facts along edges can therefore recover the range it would have been
handed. Whether a given toolchain release does so well is a measurement rather
than a claim, and it is the measurement worth taking before anyone proposes
relaxing this.

**The residual is loops whose overflow cannot be proven impossible**, where a
language with undefined behaviour would have assumed it away. That is also where
that assumption's security defects live.

## What this does not license

**An opt-in fast mode**, per module, per build or per operation. Any such switch
reintroduces build-dependent meaning, which is 0013's second clause and not its
first.

**That second clause is the one doing the work, and it is worth being precise
about why.** A language can forbid undefined behaviour in its safe subset and
*still* have a debug build that means something different from a release build,
by defining one operation two ways — a panic under one setting and a wrap under
another. Both results are defined; neither is undefined behaviour; and the
program still means two things. Forbidding undefined behaviour is necessary and
not sufficient, which is why 0013 has two clauses, and why a fast-math flag, a
settable rounding mode and an optimisation-level-dependent overflow rule are all
refused by the same sentence rather than by three.

## Alternatives considered

**Relax the second clause: check overflow in one build mode and wrap in
another.** The conventional answer, and the one with a large language behind it.
Rejected because it makes a program's meaning a property of how it was compiled,
which is the property 0013 exists to establish. It also has the specific failure
that a program tested under one setting is not the program that ships.

**Add an opt-in fast mode for measured hot code.** Rejected as the same failure
with a smaller blast radius. If a measured case ever needs the overflow
assumption, the sound move is an annotation carrying a *proof* — a stated bound
the compiler checks once and then relies on — which buys back that case without
changing what any other code means. That is a feature nothing has needed yet,
and it is named here so that its shape is settled before it is wanted.

**Emit the toolchain's conventional flags and rely on the language's safety
elsewhere.** Rejected because it is not a trade, it is a contradiction: a
no-signed-wrap flag on an operation the language defines to trap tells the
optimiser it may assume what the language guarantees to detect, and the two
cannot both hold.

**Use proven facts aggressively.** Not an alternative — 0013 already permits it,
and this record's decision is that it is the *only* permitted route.
