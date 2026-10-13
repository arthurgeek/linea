# 83. An array's length is part of its type, everywhere it is written

Status: Accepted — 2026-08-13. Extended by
[0149](0149-local-array-literals-infer-written-lengths.md),
[0198](0198-array-literal-bindings-infer-written-lengths.md) and
[0172](0172-an-array-reports-its-length.md).

## Context

[0061](0061-an-array-is-a-value-of-a-fixed-size-type.md) says `N` is part of
`[T; N]`, and the pool keeps it: an array is interned as element plus length,
layout reads both, and `[UInt8; 2]` and `[UInt8; 3]` are two `TypeId`s. The rule
stopped at the pool. Identity over *written* types — the comparison coherence
makes when it decides whether two implementations are one — never learned it.

Two reproductions, both on `main` and both on the generic-implementations branch
[0081](0081-an-implementation-is-generic-over-its-head.md) shipped:

1. `impl Give[[UInt8; 2]] for Holder` beside `impl Give[[UInt8; 3]] for Holder`
   crashed the resolver — `index out of bounds: index 4294967295` — because the
   comparison read a type reference's name token and an array reference has
   none.
2. Guarded naïvely, the two compared alike. Two implementations
   [T-ArraySize] calls distinct keyed as duplicates, and a duplicate it calls
   one keyed as two — one symbol over two types, which the emission verifier
   refuses at `exit 70` after `check` accepted the program.

A third gap came out of the reproduction, of the document-versus-code kind.
[T-ArraySize] says a length is a constant expression and
[§4.1](../linea-semantics.md#41-constant-expressions) admits "a reference to an
immutable binding whose initialiser is a constant expression" — but `let N:
UInt8 = 3` followed by `[UInt8; N]` was refused with "this is not a constant".
Literal arithmetic folded; a named constant did not. The document promised more
than the compiler kept, and the reason was an omission rather than a decision:
the resolver walked a written type's element and never its length, so the name
was never resolved at all.

## Decision

**A written array type's identity is (the element's identity, the length's
folded value).** The value, not the spelling. `[UInt8; 4]` and `[UInt8; 2 + 2]`
are one type wherever the pool would intern them as one, so they key as one
wherever coherence compares them. The comparison an array joins is recursive and
switches on the reference's `kind` — `.array` compares structure, `.named`
compares name — so a form added later says what its identity is or does not
compile, rather than reading a token it does not have.

**One routine folds a constant expression, wherever one is read.** Identity by
value forces the fold to be callable where coherence runs, which is the resolver;
it was the checker's. Both call one routine over §4.1's list, and the checker's
own membership rule, its own ring detector and its own table of what each
binding is worth are gone with it. The routine is syntax-only: what a name
reaches and what a conversion's target admits are answered by whichever pass is
asking, from the tables it already has.

**A length the fold cannot settle never reaches a key.** Where coherence would
have to compare an array whose length has no count, the implementation is left
out of the keying entirely and the program is refused at the length's own token
— [T-ArraySize]'s settled-where-written rule. Neither guess is sound: calling
two unsettled lengths one type merges possibly-distinct types into one key and
one symbol, and calling them two admits a pair of implementations whose winner
declaration order decides — the residue 0081 records as not intended, arriving
on ordinary code.

**This is a rule of the language, not a transition.** The case shrank when names
became legal in length position, but it does not vanish: a ring of constants has
no value ([T-Const]) and an initialiser that does not fold defeats the fold
whenever it runs. Being a constant expression is a syntactic property and having
a value is not, which is exactly what
[0020](0020-a-constant-expression-is-defined.md) keeps apart.

**A length is any §4.1 constant expression, locals included.** `let n: UInt8 =
3` followed by `[UInt8; n]` is a type; a `var`, and a binding whose initialiser
reads a parameter, are not. §4.1's binding clause says the binding is immutable
and says nothing about which scope declared it, so the length rule says nothing
either. A name written as a length is read where every other name is read, so
one reaching no declaration is [N-Undefined] and not a report about lengths.

Two orderings follow and are part of the decision. Coherence runs after module
constants are bound but before their initialisers are walked, so the
constant-initialiser walk moves ahead of coherence — resolved against module
scope only, which is complete by then. And [T-ArraySize]'s prose called a
binding-length ill-formed; that is now false, and the semantics document states
the new rule in its own voice.

## Consequences

**A symbol spells the folded length.** A monomorphised symbol already spells an
array component digit-led, and the digits are what the length is worth:
`[UInt8; 2 + 2]` and `[UInt8; 4]` spell one symbol because they are one type.
The emission verifier's `exit 70` on a symbol collision stays the property that
proves it, and no case asserts uniqueness by grepping.

**A chain of constants is followed by walking down it and back.** §4.1 bounds a
chain only by the ring rule, so both walks over one — the checker's, which takes
an initialiser for its type, and the fold's, which takes it for its value —
follow it with a list rather than by asking one frame deeper per link. A walk
that recursed answered "how long may a chain be" with a stack.

**One memo per run holds what has been folded, and it is where a ring is
found.** A site being worked out is a site a name may not reach. Both walks mark
and test that one row, so there is one ring detector rather than one apiece, and
a constant is folded once however many lengths read it. Coherence compares every
implementation carrying a key against the others, and folding per comparison
cost the square of what a module implements times the square of how far its
constants chain.

**A truth value is told from a number.** §4.1 folds both and a length reads only
one: `true` is worth 1 exactly as a literal `1` is, so `[UInt8; true]` keyed as
an array of one element and was reported a duplicate of `[UInt8; 1]` beside the
[T-ArraySize] refusal it had already earned. The fold's answer carries which of
the two it is, and every reader of a count refuses the one that counts nothing.

**Coherence never reads declaration order.** The duplicate value-identity
creates is refused whichever implementation is written first, and the accepted
pair is accepted in either order. The declarations-reversed rewrite over the
milestone's cases is what holds it.

**An array as an implementation head is still out of scope**, and with it array
`Display`, equality and iteration. The question that settles it — is a length a
parameter an implementation can bind — is const-generics territory: 0081's key
(trait declaration × arguments × head constructor) has no slot where a length
parameter appears "exactly once and in order", because a length is not a type.
Nothing here forecloses either answer.

**A length is bounded at `maxInt(u32)`.** The pool stores one in a `u32`, so a
count past it is refused where it is written rather than truncated into a type
nobody wrote. No machine could allocate such an array either, but that is not
the reason: the reason is that the type would not be the one the program spelled.

## Alternatives considered

**Guard the panic and compare array lengths by token text.** The cheapest patch,
and wrong twice. `[UInt8; 2 + 2]` and `[UInt8; 4]` would key as two
implementations while the pool interns one type — accepted programs whose two
"implementations" collide into one symbol, which the verifier refuses at
`exit 70`, turning a program the resolver accepted into an emission failure. And
the panic-guard shape — test for `.none`, skip — leaves the next nameless form
to the same crash.

**A resolver-private mini-fold for lengths.** Keeps the passes untangled at the
cost of the fold existing twice. The two start identical and drift on the first
form §4.1 gains, which is the bug class
[0048](0048-one-question-has-one-answer.md) exists for and which this repository
has demonstrated with a name computed two ways, a namespace decided two ways and
a symbol keyed two ways. Lost to the shared routine — and the shared routine
found the drift that was already there: `let N: UInt32 = UInt32(3)` was a
constant expression to the checker and not one to a length, because the second
fold had no conversion clause.

**Move array-bearing coherence to the checker.** Coherence would be decided in
two passes — arrays there, everything else in the resolver — so "is this
implementation a duplicate" would have two answers with a pass boundary between
them. Lost outright.

**Refuse named lengths and narrow the document.** Smaller, and it leaves the
language admitting less than §4.1's own list for no reason the code could name.
The refusal in place turned out to be an omission — the name is never resolved —
rather than a decision anyone had made. Put to the project owner with the
feasibility facts; lost to accepting §4.1 as written, locals included.

**Accept module constants only.** The middle: a smaller resolver change, and no
existing case moves. Lost because §4.1's binding clause does not distinguish
module from local, and a length rule that did would be a second, narrower
constant-expression list to keep in sync with the first.

**Guess at an unsettled length rather than refusing it.** Two shapes, both
rejected above: calling two of them one type puts one symbol over what may be
two, and calling them two admits a pair whose winner is declaration order. A
refusal is recoverable — write a literal, or make the name foldable — and it is
the only answer that decides nothing the compiler does not know.

**Bound a chain of constants at a stated depth.** It would make the recursion
safe by making the program illegal, and §4.1 states no such bound: a program's
validity would depend on which compiler read it. Lost to following the chain
with a list, which costs one allocation and bounds nothing.
