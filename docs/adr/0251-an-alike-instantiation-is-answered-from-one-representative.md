# 251. An alike instantiation is answered from one representative

Status: Accepted — 2026-10-26. Partially supersedes
[0248](0248-an-instantiation-holding-a-parameter-is-written-when-read.md):
its rule that writing an instantiation writes every unwritten one among its
parts, so that a written type holds only written types, no longer holds for
an alike instantiation. Extends
[0241](0241-declared-answers-are-settled-when-first-needed.md), whose walk
over what types own steps through one.

## Context

[0248](0248-an-instantiation-holding-a-parameter-is-written-when-read.md)
mints an instantiation holding a type parameter with its parts unwritten,
and writes them when something reads them. It kept one invariant from
writing at mint: a written type holds only written types. Writing an
instantiation wrote every unwritten one among its parts, the cycle and width
walks wrote every unwritten one a written type held, and the capability,
dependency and writer tables, meeting an unwritten part of a recorded type,
had the builder write it before they answered. Every walk over parts could
then read parts without asking whether they existed.

That invariant has a cost 0248 did not measure. Take `n` templates, each
holding the next at its own parameter:

```linea
struct G0[T: Tr] {
    v: G1[T],
}

struct G1[T: Tr] {
    v: G2[T],
}
```

`G0`'s part is `G1[T0]`, an instantiation at `G0`'s parameter. A capability
question about `G0` records it, and the table writes `G1[T0]`, whose part is
`G2[T0]`, which is written in turn, down to `Gn[T0]`. The same happens for
`G1` at `T1`, and for every template: about n²/2 instantiations, each written,
recorded and walked. The "nested templates" sweep dimension read n^2.12, and
`main` pays the same. With each part selecting the next, `v: Pad[G1[T]].Out`,
[0241](0241-declared-answers-are-settled-when-first-needed.md)'s walk over what
types own and `Builder.settleFactsOf` start the same cascade, and "templates
selecting the next" read n^2.63.

Almost none of those copies tells anything its template does not. `G1[T0]` is
`G1` with `T1` renamed `T0`, and `T0` promises exactly what `T1` does. Whether
it can be copied or discarded, whether it may carry a dependency, whether it
holds itself: each is a question about the shape of what it owns, and the
shape is the template's.

Answering only from the template leaves the same cascade wherever the
arguments promise more than the template's parameters. Give the chain above
`n` functions, each taking the first template at a parameter of its own that
promises more:

```linea
fn _f0[S: Source](sink g: G0[S]) -> G0[S]
where S.Item: Owned {
    g
}
```

`G0[S]` under `_f0` is not its template, since `S` promises `S.Item: Owned`
and `G0`'s parameter does not, so it is written, and so is every template it
holds at `S`: the whole chain, once per function, n² instantiations again.
With 1000 templates and 1000 functions the check took 12.1 s, and 46.8 s at
2000 (n^1.90); `[S: Source + Discardable]` in place of the `where` clause,
17.5 s (n^1.71). Yet every function's `G0[S]` is every other's renamed: the
functions promise alike. And `where S.Other: Owned`, on a member no template
holds, cost 12.6 s (n^1.62) although the promise cannot change a single answer
about what a `G0[S]` owns.

## Decision

**An instantiation alike others of its declaration is answered from one
representative of them while its parts are unwritten.** The template is the
representative wherever it is alike them. Parts are written when something
reads them, as 0248 says, and writing another type's parts does not write an
alike one.

### Which instantiations are alike

The candidates of a declaration `D` are its template, with its own parameters
as arguments, and every instantiation `D[A1, ..., An]` whose arguments are
pairwise distinct type parameters, none of them a settled reference such as
`T.Item`, which the pool also interns as a parameter. `Pair[T, T]` is no
candidate: an implementation for `Pair[X, X]` applies to it and not to its
template. Certified storage is no candidate either: its containment reads its
element argument, not its parts.

Each position of a candidate has a **shape**: what its argument there
promises, with every one of the candidate's arguments written as its
position. A shape holds

- the argument's capability requirement, and its `Integer`, `Owned` and
  `Shareable` promises;
- each trait it is bounded by, with the trait's arguments renamed, so
  `T: Tr2[U]` in `struct G[T: Tr2[U], U]` and `T: Tr2[V]` in `G[T, V]` have
  one shape; and each callable signature it is bounded by, renamed alike;
- each settled reference read through it that a `where` clause promised
  `Owned` or `Shareable` (or `Integer`, which promises both), renamed and
  with which of the two it was promised, as a set, but only those whose
  member `D`'s parts read through that position.

Two candidates of `D` are **alike** when their shapes are equal position for
position. A type the renaming does not take apart, a callable signature say,
is equal only to itself, which at worst keeps two alike candidates apart.

`D`'s parts **read** a member `m` through its parameter at position `i` when
a part is that parameter's `m`, or a settled reference read through it whose
first member is `m` (`S.Item.Inner` reads `Item`), or an instantiation `E`
holding the parameter at position `j` whose template's parts read `m`
through `j` in turn, through any number of templates. A part holding the
parameter in a form this does not take apart reads every member: a settled
reference read through an instantiation holding it, `Pad[S].Out`, which an
implementation may settle to `S.Item`, or a trait argument naming it. And
until every template's parts are complete, every member is read
(`Builder.templatesComplete`): a template's part may still be a reference an
implementation settles later.

`Desk[L]` in `fn pass[L: Ledger]` and `struct Desk[L: Ledger]` is alike its
template. `Crate[T]` in `fn ship[T: Discardable]` and `Crate[U]` in `fn
scrap[U: Discardable]` are alike each other and not the template, whose `T`
promises nothing; `Crate[V]` in `fn hoard[V: Owned]` is alike neither.
`Shelf[S]` in two functions writing `where S.Item: Owned` are alike each
other, and `Shelf[T]` under `where T.Other: Owned` is alike its template,
since no part of `Shelf` reads `Other`.

### Why the representative's answer is the instantiation's

`D[A]`'s parts, once written, are `D`'s parts with each parameter `Pi`
replaced by `Ai`, and `D[B]`'s are the same with `Bi`. So `D[B]`'s parts are
`D[A]`'s with each `Ai` renamed `Bi`. Every question the representative
answers for it -- whether it can be copied or discarded, whether it may carry
a dependency or a view, whether it holds storage, whether it holds itself,
whether taking it apart discharges what it owes, which part a dependency path
or a contract's target selects and of what kind -- is answered from those
parts and from what the parameters and settled references among them promise.
None of these answers tells one parameter from another except through what
each promises: a parameter's capability seed is its requirement, it seeds a
dependency unless it is promised `Owned`, it seeds an unshareable part
unless it is promised `Shareable` or `Integer`, and an implementation selected
inside a part, for `Pad[S].Out`, is selected by the traits the parameter is
bounded by. The shape holds each of those promises, and so does each settled
reference read through the argument that a part names: a promise on `S.Item`
counts wherever `S.Item` is in the parts. A promise on a member no part
reads names nothing in the parts, and changes no answer. So alike
candidates' parts are renamings of one another under which every promise
that an answer reads is the same, and so is every answer.

Ownership, instance discovery and lowering never need more than that:

- ownership asks what a type owes or may carry through the finished tables,
  which recorded an alike instantiation against its representative, and
  walks parts through `partsSource`; the finished pool's `readsFacts` admits
  such a type where `readsParts` admits no unwritten one;
- instance discovery substitutes concrete arguments, and a ground
  instantiation is written as it is minted and is no candidate, so it never
  reads one;
- lowering lays an unwritten instantiation out empty, as 0248 already did,
  since no lowered value has a type holding a parameter, and the layout
  oracle gives one no C form.

### Deciding, and deciding again

A shape is an encoding (`Builder.shapeOf`), interned so two equal shapes have
one number. Each candidate keeps its positions' shapes and a key, the sum of
each shape mixed with its position. Candidates of one declaration with equal
keys are compared shape by shape and share a class when equal
(`joinAlikeClass`). A class's representative is the template where the
template is a member and otherwise any member, and `Typing.alike_sources`
holds it by class, so the builder and the finished pool read one answer
(`Typing.sourceOf`).

Promises are completed after instantiations are minted: a bound's traits and
callable signatures are read in a later sweep, and a `where` clause adds
`Owned` or `Shareable` to a parameter or to a settled reference read
through one. So the
decision is not taken once. `Builder.watchAlike` makes a minted
instantiation a candidate, making its template one first, and lists each
position under the parameter there. `setBoundTraits`, `setCallableBounds` and
`promiseContained` decide again each position listed under the parameter whose
promise changed (`decideAlikeAgain`); `promiseContained` on a settled reference
lists it under the parameter it is read through (`promised_through`), and
under that parameter and the member it reads first there
(`promised_members`), and decides that parameter's positions. A
declaration's promises are recorded once all its `where` clauses are read,
under one hold (`holdAlikeDecisions`), so they decide each parameter they
name once, when the hold is released, rather than once per clause, and no
type question is asked while a decision waits. A candidate whose shape changed leaves
its class, and only once every such candidate has left does any join the
class its shapes now name, so no class is joined by comparing against a
member about to leave it. Where the representative leaves, the template, or
else another member, takes its place. Where what an unwritten instantiation
is answered from changes, the capability, dependency and `unshareable`
tables are rebuilt.
`templatesComplete`, called once every template is complete and every
settled type known, decides again every position whose argument has a
settled reference promised `Owned` or `Shareable`, now that `membersRead`
may answer that
its member is not read.

`Builder.reopen` makes every instantiation of the pool it reopens a
candidate again, written ones included, since any may represent its class,
and lists each settled reference promised `Owned` or `Shareable` as
`promiseContained` did, so
a pool reopened to check further declarations decides them as the first did.
It carries whether templates were complete; a check of further declarations
sets it false until its own templates are. Only `Owned` and `Shareable` are
promised of a settled reference outside a scope: a trait, callable or capability clause on
one is a contextual constraint, read in its scope's lookups and scoped
capabilities, and writes no part.

### What is answered from the representative, and where

`Typing.partsSource` is the one routine: it returns the representative of an
alike instantiation whose parts are unwritten, and the type itself
otherwise. Every walk over what a type owns steps through it instead of
writing parts:

- the capability table records such an instantiation, seeded from its
  policy, with one owned edge, to its representative; the dependency table,
  in its `raw_carriers` mode, records the same edge, and so does the
  `unshareable` table, whose answer reads every argument as well as every
  part, so the representative's arguments, which promise what the
  instantiation's do, answer for them; the writer table records its
  arguments, which are parameters and so settle it, as 0248 already did;
- the cycle walk (`firstCycleIn`) walks it as its representative, and where
  that is the template a path names the declarations a reader edits:
  `A contains B contains A`;
- [0241](0241-declared-answers-are-settled-when-first-needed.md)'s walk over
  what types own lists its representative as its one edge;
- a scoped capability steps to the representative with the scope's caps
  renamed onto its arguments (see *Scoped capabilities*);
- the finished pool's walks over parts -- whether a type holds storage or a
  view, whether taking a value apart discharges what it owes, which part a
  dependency path or a contract's target selects, and which paths cover a
  type's dependencies -- read the representative's parts.

A representative that is an instantiation is not alike another, so a reader
needing its answer writes its parts as any other's. None of these copies the
representative's answer into a table of its own; each reads the
representative where the type would have been read. A question that needs
the type's actual parts -- a field read, a pattern, a variant's payload --
writes them as before, and the tables then record those parts in place of
the edge. The representative's answer is the one those parts give, so
nothing recorded is invalidated.

### Scoped capabilities

A declaration's contextual constraints may cap a capability:
`fn tally[L: Ledger](sink desk: Desk[L], count: UInt8) -> UInt8 where
L.Entry: Discardable` caps `L.Entry` at discardable inside `tally`. The cap
is keyed by the subject it names, at `tally`'s own parameter. `Desk[L]`
answered from its representative reaches the representative's arguments
instead -- `L.Entry` at the template's `L`, or at another function's -- which
`tally`'s clause does not name, so the cap as written would reach nothing
and refuse to drop a desk that may be dropped.

So **within a scope that caps a capability, a step to a representative
renames the scope's caps with it**, and the scoped answer past the step is
shared by every scope whose caps rename alike
(`Builder.prepareScopedCapability`).

A *context* is a set of ceilings, each a subject type and the capability it
is capped at. A scope's own context holds, for each subject its
constraints and its parent's name, the lowest ceiling they put on it. The
scoped answer of a type `X` in a context `C` is the least capability, no
weaker than `X`'s seed and than the answer of each part `X` owns in `C`,
that `C`'s ceiling on `X` allows -- what the pool answers, with each
ceiling applied where its subject is reached. An alike instantiation
`X = D[A1, ..., An]` with its parts unwritten owns one part in `C`: its
representative `R = D[B1, ..., Bn]` in the context `C'` that renames each
`Ai` to `Bi` in every subject of `C` and keeps only

- the ceilings whose subject holds no type parameter but `A1` to `An`, and
- of those on a settled reference read through some `Ai`, the ones whose
  member `D`'s parts read through position `i` (`membersRead`, as for a
  shape).

`C'` is interned by its ceilings. Two questions share the answer past a
step when they reach one representative in one renamed context: the same
alike class, and caps that rename to the same ceilings on the same
subjects. A scope that caps `L.Entry` at copyable and one that caps it at
discardable rename to different ceilings; one that caps `L.Note`, which no
part reads, renames to no ceiling where the other keeps one; and a scope
whose `L` promises more is in another class, with another representative.
The converse does not hold: the filter above keeps a ceiling on any subject
holding no parameter but the instantiation's arguments, whether or not a
part holds that subject, so two contexts that differ only in such a ceiling
answer alike and are still prepared apart (see Cost).

Why `X`'s answer in `C` is `R`'s in `C'`: `X`'s parts, written, would be
`R`'s with each `Bi` renamed `Ai`, and so would every type they own, down
through every representative, with each seed the same, since alike
arguments promise alike. Every such type holds no parameter but `A1` to
`An`, so a ceiling on a type holding another applies to none of them, and
a settled reference whose member no part reads is none of them. The
renaming is one to one, since the `Ai` are distinct and so are the `Bi`, and
a type is interned by its structure, so the renamed ceiling on `Y` is the
ceiling `C` puts on `Y`'s renamed form and on nothing else. The equations
the two answers solve are then the same, one renamed into the other, and so
is their least solution.

The type a question is asked about is still written where it is alike, and
its own parts reached in the scope's own context. A later pass taking a
value of that type apart asks what each part owes within the scope, and the
finished pool answers that by scope and type, from what was prepared; what
lies past a part is never asked of the finished pool.

Rebuilding the capability facts, which a replaced part or a changed
decision forces, drops every scoped answer, since each was solved over the
facts being replaced. The questions prepared before are listed as lost, not
forgotten, and the builder prepares each again before it hands the pool on
(`restoreScopedCapabilities`), so a question prepared once is answered by
the finished pool however late the rebuild came. A builder reopened over a
finished pool lists each of that pool's scoped answers as prepared, so a
part replaced after reopening drops and prepares them again too.

A scope caps a capability only where one of its constraints puts
a ceiling below what its subject is seeded with (`capsBeyondPromise`). A
bound written on the parameter, `[T: Discardable]`, is a constraint whose
subject's seed is already its requirement, so it caps nothing: such a scope
answers every capability as the pool does, from the representative, and
prepares no scoped answer at all. `where L.Entry: Discardable` caps a
settled reference whose seed promises nothing, and does.

### Hand-off

Before the checker hands the pool on, `fillMinted` writes every
instantiation the checker minted, alike or not, and follows the parts of
each only where they are not answered from another. So every type an
expression, a binding, a signature or a written type has is written, and an
editor offering the fields of a `Desk[L]` names each at `L`. What those
writes mint is held only as a part, and an alike instantiation among it
stays unwritten. Ownership, instance discovery and lowering may therefore
meet an unwritten alike instantiation as a part of a written type, and never
as the type of a value. A read of an unwritten instantiation's parts in the
finished pool is still a compiler defect.

## Cost

Each instantiation is written at most once, and writing one writes only
those of its parts that are not answered from another. Each fact table
records an alike instantiation as one edge, and the walk over what types own
pushes it once, with one edge. `n` templates each holding the next cost `n`
instantiations recorded through their templates and, at hand-off, `n`
written, each minting the one part it holds. Under `n` functions promising
alike more than the templates do, the first function's `G0[S]` is written
when it is first asked about, and with it the chain at its `S`, `n`
instantiations; every other function's `G0[S]` is one edge to it, and at
hand-off one write minting one `G1[S]`, itself one edge to the first chain's.
Under `n` functions each capping `S.Item` in a `where` clause, each
function's `G0[S]` is written, minting one `G1[S]`, whose step renames the
one cap onto `G1`'s parameter: the same renamed context for every function,
so the chain past it is prepared once. All three are linear. Measured by the
sweep, from n to 4n:

| dimension | exponent | before |
| --- | --- | --- |
| nested templates (1000 to 4000) | n^0.25 | n^2.12 |
| templates selecting the next (250 to 1000) | n^0.15 | n^2.63 |
| nested templates bounded by one another's parameters (500 to 2000) | n^0.20 | n^2.01 |
| a template chain under functions promising a member it reads (16000 to 64000) | n^1.11 | n^1.90 |
| a template chain under functions promising a member it never reads (16000 to 64000) | n^0.99 | n^1.62 |
| a template chain under functions bounding their parameter Discardable (16000 to 64000) | n^0.99 | n^1.71 |
| a template chain under functions capping the member it reads Discardable (16000 to 64000) | n^0.92 | n^2.27 |
| a template chain under functions sharing it (16000 to 64000) | n^0.99 | n^2.13 |
| members promised through templates each reading one (16000 to 64000) | n^1.00 | n^2.23 |
| members promised through one template reading them all (32000 to 128000) | n^0.96 | n^2.14 |
| members promised by a template's own where clause (32000 to 128000) | n^1.00 | n^2.41 |

The sharing chain was measured "before" from 1000, while the `unshareable`
table wrote every alike instantiation whose arguments did not settle it.
The capping chain was measured "before" from 1000, while every alike
instantiation a capping scope reached was written at the scope's own
parameters. The last three were measured "before" from 1000, 4000 and 4000, while each
promise was decided over every earlier one and each member read was its own
search. Sized as shown, they also need the checker to ask whether a trait
declares a member in one lookup (`DeclIndex.ownsNamed`) rather than a walk
over every member the trait declares, which read n^1.7 with no template.

What makes the bound hold:

- A candidate's shapes are computed at mint, in the size of its arguments'
  bounds and promises, and a class is found by its key: shapes are compared
  only against a class with the same declaration and key, which, two keys
  aside that happen to collide, is a class the candidate joins.
- Deciding again computes one shape per position listed under the parameter
  whose promise changed, and moves only candidates whose shape changed. A
  parameter's promises are written by the declaration that owns it, and
  are decided a fixed number of times: once for each of the two sweeps that
  set its bound traits, once for its callable bounds, once when its
  declaration's `where` clauses are all read (their promises are recorded
  under one hold, `holdAlikeDecisions`, so `n` clauses decide once and not
  `n` times, each over every earlier promise), once when the templates are complete, and
  once more where a subject is read again. So a template of `n`
  parameters instantiated at another declaration's `n` costs `n` shapes to
  decide and `n` more for each of those; a comparison of all `n` shapes
  happens only where the key matches a class, which is where the candidate
  joins it.
- A shape walks whichever is shorter: the settled references promised
  through its argument, asking whether the template reads each one's
  member, or the members the template reads at the position, finding each
  one's promises by parameter and member (`promised_members`). So `n`
  templates each reading one member, under a function promising all `n`,
  cost one lookup per shape, not `n`. The promises a shape keeps are sorted,
  which is the size of the shape it interns. A representative leaving its class
  hands its place to another member in constant time, since what each member
  is answered from is read through its class, not written into it.
- `membersRead` answers, for a template and position, every member its
  parts read there in one search over the templates they hold at the
  parameter, each visited once, finding the groups of templates that hold
  one another in a cycle and answering each group from its own parts and
  the answers it reaches. Every position the search visits is remembered,
  and a template reading nothing of its own that reaches one answer shares
  it, so a chain of `n` templates reading one member costs one search of
  `n` and one run, whatever the number of functions or promises. The runs
  written are at most the positions answered times the members their trait
  declares: a chain whose every template reads a member of its own writes a
  run per template, each as long as what the chain reads below it.
- No walk follows an alike part into its own parts, so the written
  instantiations are the representatives, each written once.
- Within a scope that caps a capability, each type a question is asked
  about is prepared once, and written once where it is alike. The scope's
  own context visits what that type owns up to the first alike
  instantiation on each path, which a question asked there reaches anyway.
  Past a step, each type is visited once per renamed context, however many
  scopes rename into it, and a step renames each of its context's ceilings
  once, in the size of the subject, with one `membersRead` for each on a
  settled reference. A renamed context holds no more ceilings than the
  context it was renamed from, so a scope's steps cost its own constraints
  each time. A scope whose constraints cap nothing prepares nothing.

These shapes stay quadratic, as they were before this decision:

- `n` functions each promising a different member, over a chain whose
  template `k` reads member `k` and holds template `k + 1`. Function `i`'s
  promise is read by templates `0` to `i`, so each of those instantiations
  at its parameter promises what its template does not and is apart, and
  the ones past `i` stay alike: `n(n + 1)/2` representatives, each written
  once, which is what the equivalence by promises makes distinct. Making
  them alike would need an equivalence by answer -- a promise that changes
  no answer, since the members the other templates read stay unpromised --
  and deciding that is the work the representative saves. Capping a
  different member in each function, in place of promising it, is the
  same shape for scoped capabilities: function `i`'s cap is kept by the
  steps through templates `0` to `i`, which read its member, so its renamed
  contexts are its own until then, and `n(n + 1)/2` nodes are visited.
- `n` functions each capping a type that merely holds the parameter,
  `where W_i[S]: Discardable` with a distinct `W_i` in each function, over
  one chain. The renamed `W_i[...]` holds no parameter but the step's
  arguments, so every step keeps the ceiling although no part of the chain
  holds `W_i`, and each function's renamed context stays its own along the
  whole chain: `n` contexts of `n` nodes each. It measures about n^1.9,
  96.9 s at n = 2000, where the code before this decision takes 129.8 s. A
  ground subject, a cap on a type holding no parameter at all, is kept by
  every step in the same way and is quadratic too. Dropping a ceiling that
  no part holds needs to know what the representative owns past the step,
  which is the walk the renaming saves. Both are tracked in #35.

## Consequences

A written type may hold an unwritten instantiation, so a walk over parts
must not assume a part has parts. Every such walk named above goes through
`partsSource`; a new one must too, and the finished pool's `readsParts`
stops one that does not.

A representative may be an instantiation at another declaration's
parameters. A walk that reports the types it passed through, a cycle say,
names the representative's arguments where it stepped through one; a cycle
among templates is found from the templates themselves first, and names
them.

The tables now know which instantiations are alike, and a promise added late
rebuilds them once per decision that changes what an unwritten instantiation
is answered from. Such a change is rare: it needs a parameter to gain a
promise after an instantiation at it was recorded.

A promise on a settled reference keeps an instantiation apart from its
template until every template is complete, so an instantiation asked about
before then may be written where it would later have been answered from the
template. Its answer is the same either way.

## Alternatives considered

**Keep the invariant and make each write cheaper.** The cost is the number of
instantiations, not the price of each: n²/2 of them are minted, recorded and
walked.

**Answer every instantiation holding a parameter from its template.**
0248 rejected this for substitution on every read, and it is wrong where the
arguments promise differently: `Crate[T]` at a discardable `T` may be
dropped, and `Crate` at its own unbounded `T` may not. Restricting it to
arguments that promise alike makes the answer a renaming, which needs no
substitution.

**Answer only from the template.** Alikeness to the template alone is a
comparison each instantiation makes with one fixed party, so it needs no
classes. But every instantiation at a parameter that promises more than the
template's is then written, with every template it holds at that parameter:
a chain under `n` functions promising alike more than the chain's templates
was quadratic, n^1.90.

**Compare each candidate with its representative under the renaming, rather
than interning shapes.** A comparison of two argument lists through the
renaming costs their length, and a representative's own promises change
while others are compared against it, so each change would compare every
member of its class again. Re-deciding a whole instantiation on each promise
change made "generic helper width" read n^2.86. An interned shape changes in
one position, and a class needs no comparison until a candidate's key names
it.

**Mark a parameter promising through any settled reference, whatever the
member.** One set per parameter is the simplest record of `where S.Item:
Owned`, but a promise on a member no part reads then keeps every
instantiation at the parameter apart from its template, and from every other
instantiation promising otherwise, for nothing.

**Read only a template's direct parts for the members it reads.** A template
holding the next at its parameter reads nothing directly, but its part reads
what that template reads; a promise on a member the chain's last template
holds would leave every earlier one alike its template while its parts,
written, carry the promise. The search follows the templates a part holds at
the parameter.

**Let an alike instantiation share its representative's run of parts.**
Raw walks would read the representative's parts without any routine. But
the fact tables record a snapshot of a type's parts, and a template's parts
are settled after its instantiations are minted
([0241](0241-declared-answers-are-settled-when-first-needed.md)), so a
shared run's recorded edges would go stale; and a write to the shared run,
breaking a cycle or writing the instantiation's own parts, would write the
representative.

**Compare a bound's arguments by identity.** `[I: Iterator[T], T]` is a
common shape, and its template's `Iterator[T]` names the template's own `T`,
so no instantiation at another declaration's parameters would ever be
alike: templates holding one another at such parameters kept the quadratic
cascade, n^2.0 for `struct Gi[T: Tr2[U], U] { v: Gi+1[T, U], u: U }`.
Writing each argument as its position is the renaming the instantiation's
parts would undergo.

**Decide alikeness once, at mint.** Bounds' traits, callable signatures and
`Owned` promises are completed after instantiations are minted, so the
decision would be read stale.

**In a capping scope, write every alike instantiation a question reaches.**
The scoped answer is then read from parts at the scope's own parameters,
which its caps name as written, and no cap is renamed. But each scope writes
everything it reaches at its own parameters: `n` functions capping
`S.Item` over a chain of `n` templates wrote `n` chains, n^2.27, though
every one answers as the template's chain does under one renaming. Renaming
costs a substitution per cap at each step, and only the preparation renames:
readers ask by scope and type as before.

**Key a scoped answer by the representative and the scope's caps as
written.** A cap names the scope's own parameter, so no two scopes would
share a key; the renaming onto the representative's arguments is what
makes `S.Item` in one function and `K.Item` in another one ceiling.

**Rename every cap on a type held at the arguments.** A cap on a member no
part reads, `where S.Note: Discardable` over a chain reading `S.Item`,
changes no answer, yet kept it makes each function's renamed context its
own, and the chain is visited once per function again. Settled references
are pruned by the members the template reads, as shapes are, and for the
same reason.

**Count every constraint with a capability requirement as a cap.** A bound
written on a parameter is a constraint too, and every function bounding its
parameter `Discardable` then prepared scoped answers for everything its
signature reaches, writing every alike instantiation among it: a chain under
`n` such functions was written once per function, n^1.71. Its ceiling is the
parameter's own seed, so it changes no answer the pool gives.

**Leave alike instantiations unwritten at hand-off.** Ownership and
lowering only ask what they own, but an editor names the type of each field
of a value, which needs the parts at the value's own arguments, and the
finished pool cannot write. Writing what the checker minted, without
following alike parts, is linear.
