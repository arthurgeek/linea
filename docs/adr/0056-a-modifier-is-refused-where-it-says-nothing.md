# 56. A modifier is refused where it says nothing

Status: Accepted — 2026-07-31

Extended by [0145](0145-closed-attributes-attach-ordinary-derive-requests.md),
which replaces bare representation-policy prefixes with closed declaration
attributes.

Reads [0033](0033-sealing-is-checked-not-omitted.md) for what `opaque` means and
[0035](0035-representation-and-behaviour-are-declared-apart.md) for why it
reaches a type's braces and nothing else. Applies
[0048](0048-one-question-has-one-answer.md) to the choice of rule name.

## Context

The grammar reads the visibility prefix once, before it chooses which
declaration rule runs — so a form added later cannot forget to accept one. The
cost is that every form accepts every word, and nothing downstream asked whether
the word meant anything there.

`opaque fn helper() -> u8 { 1 }` compiled. So did `linear use`, `pub import`,
`opaque trait` and `pub fn main`. Only `impl` was refused, and only because it
records no declaration for the modifier to sit on: the parser had to report the
word or lose it.

Two of the five are worse than dropped, and in opposite directions.

`opaque fn` **exported the function**, exactly as `pub fn` did — verified
against an importing module, which reached `helper` where a private one gave
`[M-Vis]`. So `opaque` was a second spelling for `pub` on a function, and one
that reads as a seal. Nothing was sealed; a function has no representation to
seal, and `[M-Opaque]`'s six sites are all about values.

`opaque use` exported onward and sealed nothing, which is the only meaning it
could have had. It cannot have that one: a re-export is an alias rather than a
fresh identity, so a value built through either spelling is the same nominal
type and nothing downstream can tell which spelling reached it. Sealing at the
alias would make the seal depend on the route, which is the one thing an alias
promises not to do.

`linear fn`, `linear use` and `pub import` were read and thrown away. `pub
import` is the one a reader is most likely to believe: it looks like the way to
carry an imported module onward, and `mid.inner` named nothing.

`pub fn main` is a fourth case with its own reason. A path descends
([0032](0032-a-module-is-a-directory.md)), so a module reaches only the modules
beneath it and nothing imports the program. The word widens the entry point's
reach to nobody.

## Decision

**A modifier is written where it says something, and refused where it says
nothing.**

`opaque` seals a representation and `linear` says what a type's values owe, so
each reaches a `struct` or an `enum` and nothing else. An `import` takes none of
the three. `pub` reaches everything else that declares a name another module may
reach — a function, a type, a trait, a re-export, an `impl` member — and not the
entry point.

**Under `[S-Entry]`, not a new rule name.** `[S-Entry]` already refuses a
modifier before `impl`, and `opaque impl` and `opaque fn` are one mistake:
a word written where the language gives it no meaning. A second name would make
which diagnostic a programmer sees depend on the keyword that follows the word
rather than on what is wrong with it.

**Checked in the resolver, except before `impl`.** The parser refuses what
leaves no trace: an `impl` has nowhere to record a modifier, so the parser is
the only pass that can see one. Every other form carries its modifier into the
tree faithfully, and the tree is right — a formatter has to reprint what was
written. That the marking means nothing is a judgement about the declaration,
which is the resolver's question; it already answers the other clauses of
`[S-Entry]` for the same reason.

**The entry point's clause is about the entry point, not about the name.** An
imported module's `main` is an ordinary function and exports like any other, so
the refusal is asked of the root alone — the same scope as the rest of the
signature check.

## Consequences

Five spellings that compiled now do not. None appears in the standard library,
the examples or the corpus, and none of them could have been load-bearing: two
were synonyms for `pub` and three were no-ops.

A programmer who wants a function exported writes `pub`, which is what it was
already doing. A programmer who wants an imported module carried onward writes
`pub use`, which is what already worked.

The prefix stays read once, before the declaration rule is chosen. The rule
above is a table over declaration forms rather than a change to how the prefix
parses, so a form added later still cannot forget to accept a modifier — it has
to say which of the three it takes, and until it does, `[S-Entry]` refuses all
three on it. That is the safe direction: a new form starts out refusing words it
has not been given a meaning for.

## Alternatives considered

**Give `opaque fn` a meaning.** There is none available. A function's body is
already unreachable from outside — you call it — and what a caller depends on is
its signature, which `opaque` cannot hide without making the function
uncallable. "Exported but unnameable" is a contradiction.

**Let `opaque use` seal at the alias.** This is the only spelling with a
plausible reading, and it contradicts what a re-export is. Two modules
re-exporting one type under different seals would give one nominal type two
representations depending on the route the name took, and
[0033](0033-sealing-is-checked-not-omitted.md)'s `sealedHere` asks about the
declaring module because that is the only module that decided anything.

**A new rule name, `[M-Modifier]`.** It reads better than `[S-Entry]` for
`opaque fn` in isolation, and worse for the set: `opaque impl` would keep
`[S-Entry]` because the parser is where it is caught, and the same mistake would
carry two names. Renaming the existing clause is not available either — a rule
name is emitted text and a literal index into the semantics document.

**Refuse it in the parser, with the `impl` clause.** One place for the whole
rule, and it is the wrong place: the parser would have to decide that a
faithfully recorded modifier is meaningless before anything has asked what the
declaration is. It also could not answer the entry point's clause, which needs
to know which declaration is `main` — a question about names.

**Leave it, and document that a modifier is ignored where it has no meaning.**
This is what the code did. It fails on `opaque fn`, which was not ignored: it
exported.
