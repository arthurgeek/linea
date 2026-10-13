# 57. A mutation answers for the rules it declares

Status: Accepted — 2026-07-31

Extends [0029](0029-a-suite-must-be-able-to-fail-for-what-it-omits.md), which
decided that a mutation names the rule it must break, and
[0055](0055-a-rule-name-is-not-the-unit-of-enforcement.md), which decided what
mutations are for.

## Context

[0029](0029-a-suite-must-be-able-to-fail-for-what-it-omits.md) named the failure
mode this record repairs, in the sentence that closes its consequences: *a
mutation that produces a program which is ill-formed for a second reason would
cite the wrong rule and fail. That is why a mutation names one rule rather than
merely asserting rejection.*

The naming was implemented as containment. The runner concatenated the rule
names of a rejection and asked whether the mutation's own name occurred
somewhere in the string. A mutation that broke its rule **and something else**
passed, so the failure mode 0029 wrote down was the one thing the check could
not see.

Tightening it to *the set of error-severity codes is exactly the rule* was run
over the corpus and 200 generated programs. It reported 270 mutated programs
citing more than one rule:

| mutation | cited besides its rule | programs |
| --- | --- | --- |
| `wrong_entry_type` | `T-Mismatch` | 238 |
| `unknown_variant` | `T-Infer`, `T-Mismatch` | 14 |
| `dropped_disposal` | `N-Unused` | 5 |
| `unknown_member` | `T-Infer`, `N-Unused`, `O-Move`, `S-Mutation` | 12 |
| `unknown_field` | `T-Infer` | 3 |
| `dropped_implementation` | `N-Unused` | 1 |

The list does not divide by mutation. It divides by what the second citation
**is**.

Most of it is one mistake reported twice. Renaming a variant to a name no enum
declares leaves an expression with no type, and the type checker says so where
it stands. Rewriting `main`'s return type re-checks the body against it, and a
body that answers with an exit status no longer answers to the signature above
it. Deleting the statement that hands a linear value away deletes the only
reader of the binding that held it. In each, the program is wrong about exactly
one thing, and two passes report that thing from where they stand. Demanding a
single citation would forbid all of it, and the only way to comply would be to
contort the mutations away from consequences the language really has.

The rest is not that. `unknown_member` renaming `Coins.of(coppers)` provoked
`O-Move`, and renaming `E0._f38(&_u38.f2, 9)` provoked `S-Mutation`. Neither is
about the program. A callee nobody declared has no parameter list, so what its
arguments are handed over as is a question with no answer, and the passes that
read conventions answer it out of a fallback — a binding then reads as taken and
used again, a borrow as a write through something that permits none. That is the
compiler's recovery talking, and a mutation that provokes it is evidence about
neither rule.

A third case was reachable and not in the corpus. `repeated_disposal` renames
the binding it repeats, so where the disposal's callee *answers* with a linear
type the copy binds a second value nobody disposes of: `O-Move` beside an
`O-Leak` the mutation invented. Its doc comment claimed it "breaks that rule and
no other, because the original program was accepted", and then argued only about
`[O-Loop]`. The generalisation was false; only the `[O-Loop]` half was ever
established.

Severity had to be part of the answer either way. The verdict was built from
every coded diagnostic, and `[S-Continuation]` is a note — a hazard described
beside a rejection rather than a reason for one. Counting it would make a
mutation answer for a rule it did not break.

## Decision

**A mutation declares the rules it may cite, and answers for exactly those.**

The assertion has two halves and needs both. The rule the mutation names must be
cited, or the mutation is evidence about some rule it did not set out to break —
which is [0029](0029-a-suite-must-be-able-to-fail-for-what-it-omits.md)'s
requirement, unchanged. And every other rule cited must be one the mutation
declared, or the mutated program is wrong twice over and says nothing about
either.

**A citation is an error.** Notes and warnings are not reasons for a rejection
and are not counted.

**A declared rule carries the reason it is a consequence.** The declaration sits
in the code beside the rule it belongs to, with a comment saying why that rule
is the one mistake seen by a second pass rather than a second mistake. Where no
such reason can be written, the mutation is narrowed until the citation does not
arise. A declared cascade nobody justified is the containment check with extra
steps.

**The set bounds the citations; it does not require them.** Which members appear
depends on the program mutated — `T-Infer` where nothing else determines a type,
`T-Mismatch` where the position fixes one — so demanding every member would
forbid the programs that provoke only one.

Two mutations were narrowed rather than granted a declaration. `unknown_member`
now steps over a callee handed a binding, and renames only one whose arguments
are built in the call, where the missing declaration cannot be observed.
`repeated_disposal` now steps over a disposal answering with a linear value, and
repeats one that answers with a number.

## Consequences

**A rule appearing that nobody declared is a failure, including on a corpus case
nobody has written yet.** This is the point and it is also the cost: a new case
can turn the suite red without the compiler having changed, and someone then has
to decide whether the new citation is a consequence to declare or a mutation to
narrow. That decision is the work this record exists to force. The alternative
is the check that could not see the thing it was written to see.

**Narrowing costs reach.** `unknown_member` fell from 11 corpus programs to 7,
against a floor of 5. The floor is unchanged and still met; what a narrowing may
not do is buy silence with a floor.

**A mutation is applied only to a program the compiler accepts.** The unit tests
now establish that before mutating, and the first thing it found was one of
their own: a program whose `match` took a lent parameter, rejected before the
mutation touched it. Under containment the test passed, because the rule the
mutation named was in the list beside the `[O-Move]` the original program had
always provoked.

**The two halves fail differently and both were checked by putting a defect
back.** Removing the guard that keeps `unknown_field` off a name in a namespace
makes it cite `N-Variant` instead of `T-UnknownField` — seven programs, and the
old check caught this one too. Removing the guard that keeps `dropped_disposal`
off a binding something reads makes it cite `N-Undefined N-Unused O-Leak`;
removing the linear-answer guard from `repeated_disposal` makes it cite
`O-Move O-Leak`; removing the argument guard from `unknown_member` makes it cite
`N-Variant O-Move`. The last three are green under containment and red here,
which is the whole of what changed.

## Alternatives considered

**Make each mutation break exactly one rule.** The cleanest assertion, and it
was measured first: 270 programs, most of them cascades the language genuinely
has. Rejected because complying would mean narrowing `unknown_variant` away from
every position where an expression's type is asked for, and `wrong_entry_type`
away from every `main` whose body has a type — which is nearly all of them, and
the reach is what [0055](0055-a-rule-name-is-not-the-unit-of-enforcement.md)
turns on. A mutation contorted to avoid a consequence tests a rarer shape than
the one the rule is about.

**Assert the declared set exactly — every member cited, every citation
declared.** Rejected because the members are conditional on the program.
`T-Infer` and `T-Mismatch` are the same hole in two positions and never appear
together; requiring both would fail every program, and requiring either would be
the rule this record already states.

**Declare `O-Move` and `S-Mutation` for `unknown_member` and keep its reach.**
Rejected because neither is a consequence of the misspelled name. Both are the
compiler's fallback for a declaration it never found, and a mutation that
declares them would still pass after being changed into one that genuinely moves
a value twice — the rule it names would be cited, and the second citation would
be licensed.

**Key the permitted cascade on pass order rather than on a per-mutation set** —
a resolver rule may cascade into type and ownership rules, a later rule into no
earlier one. Rejected on the data: `dropped_disposal` breaks an ownership rule
and cascades into `[N-Unused]`, which the resolver reports, so the model forbids
the clearest consequence in the table. It also permits by position rather than
by reason, which is what makes it cheaper — and cheaper is the property that
made containment fail.
