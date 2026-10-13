# 55. A rule name is not the unit of enforcement

Status: Accepted — 2026-07-31

Extends [0029](0029-a-suite-must-be-able-to-fail-for-what-it-omits.md) with the
direction it left open. Reads
[0008](0008-golden-conformance-suite.md) for what a golden establishes and
[0027](0027-generated-programs-are-well-typed-by-construction.md) for what the
generator cannot reach.

## Context

`[S-Entry]` says a program declares exactly one `main`, **and that it is
`main() -> u8`**. The second half was enforced by nothing for four milestones.
A `main` returning a three-field structure compiled, linked, ran, and exited on
the low byte of the address of a frame that had ended.

Every mechanism this repository has was green on it, and each for its own
reason:

- The four fuzz targets make no checker or lowering call. A program the
  compiler wrongly **accepts** never reaches them.
- The generator is well-typed by construction
  ([0027](0027-generated-programs-are-well-typed-by-construction.md)), so it
  cannot emit a program that ought to be refused.
- The metamorphic rewrites preserve meaning
  ([0026](0026-the-corpus-checks-properties-a-golden-cannot.md)), so a wrongly
  accepted program is rewritten into another wrongly accepted program and the
  two agree.
- Rule coverage reported `66 of 66`. It counts the codes the compiler *emits*
  and asserts each has a case. `S-Entry` is emitted — by the clause about the
  count — so it was reached, and the clause about the signature had nothing to
  reach.

The obvious repair is the reverse of the coverage check: **every rule name the
document defines must be one the compiler can emit, and the corpus must provoke
it.** It was built and measured before being rejected. It is unsound, and it
also would not have fired here.

The document defines 74 rule names and the compiler declares 66 codes. Every
code has prose (a test already refuses one that does not). The eight names with
no code were each provoked and the diagnostic read:

| rule | what a violation actually reports |
| --- | --- |
| `[L-Layout]` | nothing — an implementation asserts it, and [0050](0050-the-layout-rule-has-a-second-implementation.md) gives it a second one. No program can violate it. |
| `[S-Literal]` | `T-Infer`, which its own prose names |
| `[T-Logical]` | `T-Condition`, which its own prose names |
| `[T-While]` | `T-Mismatch`, and `T-Discard`, which its own prose names |
| `[T-Bind]` | `T-Arity` — "the arity rule a call already states" |
| `[T-Call]` | `T-Mismatch`, and `T-Arity` for the count |
| `[T-Assign]` | `T-Mismatch` |
| `[T-Loop]` | `T-Mismatch`, break sites meeting like any pair of types |

**All eight are naming artefacts and none is a gap.** A rule is often stated as
prose that other codes enforce, which is what lets the document read as a
description of the language rather than as a list of error messages. A check
demanding a code per paragraph would fire eight times on the day it landed, all
false, and the only way to quiet it would be to mint eight codes nothing emits —
which is worse than no check, because a code nothing emits then satisfies
coverage while enforcing nothing. That is the failure being repaired, reproduced
by the repair.

And it would not have caught `[S-Entry]` anyway. `S-Entry` has a code, and
`tests/decl/no_main.stderr` provokes it. The reverse check reads green.

The reason is the granularity. `[S-Entry]` states four separable things: that
exactly one `main` is declared, what its signature is, that an `impl`'s braces
hold only functions, and that no modifier precedes an `impl`. Three were
enforced and one was not, under one name. **No check keyed by rule name can see
inside a rule**, and clauses are not delimited in prose, so there is nothing
finer to key on.

## Decision

**A documented clause is held by a mutation, not by counting names.**

[0029](0029-a-suite-must-be-able-to-fail-for-what-it-omits.md) already decided
the mechanism: a mutation is a change built to make a program ill-formed, paired
with the rule it must break, run over every accepted program in the corpus and
every generated one, with a floor. This record decides what it is *for* — the
existing four each break a rule about a name the program wrote, and this is the
first that exists because a clause of a rule had no other way to be checked.

`wrong_entry_type` rewrites the entry point's `u8` to `i64` and requires
refusal citing `S-Entry`. It reaches 157 corpus programs against a floor of 140,
where the next highest mutation reaches 47, because every accepted case of one
file declares an entry point.

**The count is the signal, not the pass.** Restoring the defect — leaving the
return-type clause in place and making it report nothing — turns 157 programs
red at once. That is the check this defect needed on the day it was written.

**Rule coverage is kept and its claim is narrowed.** It establishes that every
diagnostic the compiler emits is documented. It does not establish that every
documented rule is enforced, it cannot be made to, and the two are not the same
claim.

## Consequences

**The reconciliation is a one-time result, not a standing check.** Eight names,
all accounted for, recorded above so the next reader does not repeat the count
and reach for the same unsound repair. It goes stale as the document grows, and
that is accepted: it is evidence for a decision, not an invariant.

**Coverage of clauses is not measured, and is not claimed to be.** There is no
number saying what fraction of what the document states is enforced, because
there is no denominator — a clause is a unit of prose. What exists instead is
that a clause someone doubts can be given a mutation, cheaply, and that a
mutation is the only mechanism here able to fail for a check that was never
written.

**A mutation is owed to any clause carrying a soundness claim.** This is the
cost: it is per-clause work that nobody is prompted to do. The floor is what
makes the ones that exist stay done.

## Alternatives considered

**Every rule the document names must have a code.** The proposal above.
Rejected on measurement: eight false positives out of eight, and green on the
defect that prompted it. Quieting it would mean minting codes nothing emits,
which retires the guarantee while appearing to establish it.

**Split `[S-Entry]` into a rule per clause, then check names.** Makes the
granularity problem go away by making the name finer, and it would work — for
`S-Entry`. Rejected because it pushes the judgement into how prose is
paragraphed: the next multi-clause rule is a rule someone declined to split, and
nothing would say so. It also costs the property that a diagnostic's code
indexes a section a reader can find, replacing one findable name with four.

**Assert that the corpus contains a case per clause, listed by hand.** A table
of clauses, each with the case that provokes it, held to like the generator's
coverage tables. Rejected: a clause has no identity a table can key, so the
table's own entries are the only definition of what a clause is — and a clause
nobody listed is invisible exactly as before. The generator's tables work
because their axes are enumerations the compiler already switches over
exhaustively, and prose is not one.

**Leave it to review.** What was in place. The clause was read by everyone who
read the document and enforced by nobody for four milestones, which is the
measurement.
