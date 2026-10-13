# 50. The layout rule has a second implementation, and it lives in the test

Status: Accepted — 2026-07-29

Answers the gap
[0049](0049-generated-code-is-verified-before-it-is-emitted.md) names as the
one it structurally cannot see, against the rule
[0031](0031-fields-are-packed-at-their-natural-alignment.md) states. Argued
under [0026](0026-the-corpus-checks-properties-a-golden-cannot.md) and
[0029](0029-a-suite-must-be-able-to-fail-for-what-it-omits.md), and against
[0048](0048-one-question-has-one-answer.md), which is the rule this record
takes its one bounded exception to.

## Context

0049 verifies the backend against `module.layouts`. Every check it makes is
relative to that table. If the checker computes the wrong size for a type, the
table, the emitter, the verifier and the running program all agree, every check
passes, and the program corrupts memory in a way nothing in this repository can
see. The layout table is the one input to code generation with no second
opinion.

The corpus does not reach it either, and the reason is structural rather than a
gap someone closes by writing more cases. The metamorphic rewrites are a
differential oracle, but of a program against rewrites of *itself* through the
same compiler. Reordering a structure's fields is the closest thing to a layout
property, and the reordering is driven by the compiler's own table: a wrong
offset moves consistently on both sides and the answer does not change. What
contradicts a computed fact is a second source for it, not a rewrite that
consumes it.

`cc` is a second source, already installed and already on the critical path —
every generated program is linked with it. 0031 states Linea's rule as a part
occupying its own width at the next offset its alignment allows, a type's
alignment being the greatest of its parts', its size rounding up to that, and
parts staying in declaration order. For a structure that sentence is also C's
rule, and the checker and a C compiler are two implementations of it sharing no
code and no author. Measured by hand on the smallest case where padding bites,
`struct Q { a: u8, b: u64, c: u16 }`: both answer size 24, alignment 8, offsets
0, 8 and 16.

Which raises the objection this record exists to answer, and
[0048](0048-one-question-has-one-answer.md) states it as a standing rule. A
second implementation of one rule is the defect this repository hunts
everywhere else — two functions one sentence describes, disagreeing silently,
with the program taking whichever it reached. Proposing one deliberately needs
an argument, not an assumption.

## Decision

**The layout rule may have a second implementation, and it must be `cc`, in the
test, under three conditions.** A conformance property emits the equivalent C
declaration for every concrete aggregate type reaching the backend and diffs
`sizeof`, `_Alignof` and `offsetof` against `module.layouts`.

The conditions are what separate an oracle from drift:

1. **The oracle is unreachable from the compiler.** Nothing under `src/` reads
   it, and no layout is ever derived from `cc`'s answer. The compiler keeps one
   implementation of the rule and one authority for it; the oracle has no
   consumer but the property. Drift is two answers that both reach a program.
   These never both reach one: when they disagree, no program is miscompiled by
   the disagreement — the suite fails and a person adjudicates.

2. **The oracle is an independent derivation of the rule, never a transcription
   of the code.** Porting the checker's offset arithmetic into the test would
   produce a property that agrees by construction and buys nothing — and *that*
   would be the drift, two copies of one function with the silent copy deciding
   nothing. The entire value is that `cc` was written by people who never read
   `src/sema/types.zig`.

   Operationally: **the emitted C is generated from the type's structure —
   its members, their order, and their types — and never from
   `module.layouts`.** A member's C type comes from what the Linea type says
   the member is; it does not come from looking the member's size up in the
   table. The table appears in this property exactly once, on the other side of
   the comparison. The moment a size, an alignment or an offset flows from the
   table into the C the oracle emits, `cc` is being asked to confirm a number
   it was handed, and the property checks nothing while still passing.

3. **Divergences are enumerated in advance.** Where the two rules genuinely
   differ, the difference is written down here and encoded in what the oracle
   emits. A divergence discovered as a failure and then patched into the oracle
   turns it into a transcription one exception at a time, which is condition 2
   failing slowly. **That is the mechanism by which this becomes drift, and it
   is the thing to watch for.**

**The first documented divergence is the enum.** C has no tagged union, so an
enum has no C form that corresponds by accident. 0031 gives the tag a full word
and overlays every variant's run after it, so the oracle's form is

```c
struct { uint64_t tag; union { struct { … } v0; struct { … } v1; } payload; };
```

and it corresponds only *because* the tag is a word: a union's alignment is at
most eight, so the payload begins at eight on both sides. **If the tag is ever
narrowed — the option 0028 priced at seven bytes per value — this C form stops
corresponding, and the oracle is re-derived rather than adjusted.**

**The second divergence is the host's ABI, and the oracle checks its own
premise.** `cc` implements its target's ABI, not 0031. The two coincide where
every builtin's alignment equals its size, which is true of every 64-bit target
in use and false of some 32-bit ones, where an eight-byte scalar aligns at
four. So the emitted C carries static assertions that
`_Alignof(T) == sizeof(T)` for each type standing for a Linea builtin. A host
that does not satisfy the premise fails at the premise, rather than reporting a
Linea defect that is a C ABI difference.

**The third divergence is the zero-width part, and it is the one the first run
hits.** `()` is `Layout{ .size = 0, .alignment = 1 }` in `src/sema/types.zig`,
and it is a legal part: a generic instantiated at it puts a zero-width type in
a structure field or a variant payload, and `Maybe[()]` is one of the defects
0049 is written against, so the shape is known to reach the backend rather than
merely being expressible. ISO C has no zero-size member and no empty structure,
so there is no C text that stands for one. Worse, this is not a corner: a
payloadless variant carries an empty run, so `enum { None, Some(T) }` — every
optional in the corpus — makes an arm of the union an empty structure under the
form above. Without a rule stated in advance, the property's first run produces
a diff that is not a Linea defect, and condition 3 fails at time zero.

The rule: **a part of width zero contributes no C member, and offsets after it
are unchanged.** Linea's own arithmetic gives the second half —
`alignUp(at, 1) + 0 == at`, so a zero-width part never moves what follows it
and never raises the enclosing alignment. A variant whose parts are all
zero-width, including one with no parts at all, contributes no union arm; an
enum with no arm left contributes no `payload` member and is a tag alone. So
`Maybe[()]` emits `struct { uint64_t tag; };` and `cc` answers size 8,
alignment 8, which is what the table says.

**Which parts are zero-width is read from the type, not from the table.** A
part is zero-width when it is `()`, or an aggregate every part of which is
zero-width — a structural question, answered structurally. Consulting
`module.layouts` for the member's size would be the transcription condition 2
forbids, in the one place it is most tempting to allow it.

What this gives up is stated rather than hidden: a zero-width part has no C
`offsetof`, so its offset is not diffed. The compiler places it where the next
part begins, and no C declaration can either confirm or contradict that. The
enclosing type's size and alignment and the offsets of every part that has one
are still checked, and it is the enclosing size that the `Maybe[()]` shape
turns on.

The structure correspondence is measured. The enum and zero-width
correspondences are derived here and are tested for the first time by the
property itself.

## Consequences

Nothing under `src/` gains a second implementation of anything. The rule has
one definition — 0031, with this record's three exceptions — and two independent
readings of it: the compiler's, which decides what programs mean, and `cc`'s,
which decides nothing and can only disagree. Comparing two readings of a
specification is what a specification is for.

**A disagreement is a question, not a bug report against either side.** The
property names a type, a member and two numbers. Which of the three is wrong —
the compiler, the oracle, or 0031's prose — is for a person to decide, and if
the answer is that 0031 is wrong then a record settles it and the oracle
changing is a consequence rather than the fix.

**Scope is what the table carries.** Only concrete aggregate types the module
holds a layout for are checked; a type no program builds has no entry and no
oracle. Recomputing the rule from the AST instead would reach every declared
type and would also let the constants baked into each field address be diffed
against it. That is a strictly larger property and this record does not decide
it.

**The suite gains no new tool.** It already requires `cc` and `qbe` to run at
all. It gains a dependency of a different kind, though: the corpus's answer to
a question about Linea now passes through the host's C compiler, which is why
condition 3 and the ABI assertions are part of the decision rather than
implementation detail.

**A floor is needed, or the property is satisfied in letter only.** A run in
which the oracle compared zero types is a run that proved nothing, and it looks
identical to a clean one.

## Alternatives considered

**Recompute the rule in Zig, inside the test.** The obvious way to avoid
depending on a C compiler. Rejected under condition 2: written by copying the
checker it agrees by construction, and written from scratch it is still the
same author reading the same record the same way. The independence is the
whole product, and a second reading by the same reader is not one.

**A second Linea backend emitting C with named fields.** Strictly better as an
oracle — it checks offsets in code rather than numbers in a table, and 0049
prices it as the only thing that would give real ASan over Linea programs.
Rejected here for the reason 0049 rejects it: a second backend must stay
behaviourally identical to the first forever. Revisit if this leaves a
demonstrated gap.

**Hand-written expected layouts, as goldens.** Cheapest, and it contradicts the
rule that a golden is generated and reviewed rather than written. A
hand-written table records what someone expected; the compiler records what
that same someone implemented. Both failure modes have one author, which is the
condition an oracle exists to break.

**Harder reordering rewrites.** Reordering already exists and could be
strengthened — every structure rather than the first, mixed widths rather than
uniform ones. Worth doing, and it cannot close this: both sides of a rewrite
read the same table, so a systematically wrong layout is invisible to any
number of them.

**Nothing — accept that the layout table is unchecked.** The position today,
and it was defensible while nothing else about code generation was checked
either. 0049 removes that defence by checking everything else against the
table, which makes the table the last thing standing on its own word.
