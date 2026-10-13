# 80. A dotted type name resolves through its module

Status: Accepted — 2026-08-12; trait-slot clause superseded by 0110

Applies [0048](0048-one-question-has-one-answer.md) to the head of a written
type. Reads [0032](0032-a-module-is-a-directory.md) for what an import binds and
[0033](0033-sealing-is-checked-not-omitted.md) for what a seal covers.

## Context

The grammar has always admitted `type_name ::= name ("." name)*`, and the
resolver answered `[N-Undefined]` for every dotted one. The head was looked up
among the types this module can write, a module is not one of those, and the
message named the module as an undefined type: `pct.Thing` was grammatical and
resolved for nobody.

The gap was language-wide rather than a property of any one kind of type. An
imported struct could not be written in an annotation, an imported newtype could
not be constructed — the callee never reached a type, so `pct.Score(42)` was
`[N-NotCallable]` and `pct.Score?(9)` was a `?` on a call that constructed
nothing. Every other dotted position already read through the module: `pct.f()`
called, `pct.C` read a constant, `pct.Colour.Red` named a variant.

`use pct.Score` worked, so nothing was unreachable. What the language said was
that a type from another module had to be brought into this one before it could
be named — a rule the grammar did not state, no diagnostic explained, and no
other dotted name obeyed.

## Decision

**A type is named through the module that declares it, wherever a type is
written.** `pct.Thing` in a parameter, a return type, a field, a variant's
payload, a binding's annotation, an array's element, a newtype's base, a type
argument or an argument an `impl` supplies its trait is that module's `Thing`.

A trait's own name is outside this. The name after `impl`, the type after
`for` and a bound after `:` are each one token in the tree rather than a
written type, so qualifying one is a change to what the tree holds and to
every pass that reads it, and `use` already names them. What made the
arguments in `impl Holds[pct.Thing]` reachable is that they were written types
already and nothing read them — the resolver walks them now, so the header
resolves them through the same routine every other written type crosses a
module by, and a name the module does not declare is reported on the header's
own line instead of registering an implementation nothing can find.

**Which of the two a dotted head is, is a question about names.** The parser
produces one shape for `pct.Thing` and `Self.Item`; a head that names a module
qualifies, and every other head is a settled reference. The resolver decides,
because it is the pass that knows what an import bound.

**A head is read in the order every written name is read in.** `Self` first,
then a type parameter of the declaration writing it, then a module: an import
is the furthest of the three, so `Iter.Item` inside `fn first[Iter: Carry]` is
that parameter's and a directory called `Self` does not take over the
language's own head. One order, and the resolver settles it once — the checker
reads which head was chosen rather than choosing again.

**Through the routine an expression's qualified name already uses.** The
crossing is one question — what does this name reach in that module, and may it
be reached from here — so `[M-Vis]` and "not declared in that module" answer the
same for `pct.Thing` as for `pct.f`. A name a module declares as something other
than a type is `[N-Undefined]` in a type position, which is what a name reaching
a function has always been there.

**A construction is a call whose callee names a newtype, whichever spelling
names it.** `pct.Score(42)` and `pct.Score?(9)` construct exactly what the bare
forms construct after `use`, and `opaque` seals both: sealing is decided by the
declaring module of the type the call builds, so a qualified head is another
door rather than a way past.

**A qualified run ends at the module's type.** `pct.Holder.Item` reaches
`Holder` through the module, and `Item` is then selected from it by the rule
every other selection obeys: a name is read through the bounds the type before
it carries, and `Holder` carries none. Bounds are written on a declared type,
which is a member of a trait or of an implementation and is reached under that
namespace rather than under a module's — so no module's type carries one, and
the answer is `[T-Impl]` about a type that declares no such name rather than a
rule of its own. `O.Mid.Item` goes further only because `Mid` is a declared
type with a bound written on it.

## Consequences

Programs that were rejected are accepted, and none that was accepted changes
meaning: a head an import could have captured is read as `Self` or as a type
parameter first, so every spelling this admits was a diagnostic before.

Two cases in the corpus said the old rule and now say this one. One recorded
that an annotation could not qualify its head; it now records that a name the
module does not declare is that mistake and not a mistake about `Self`. The
other recorded that only a bare name heads a construction; it now records that
what heads one is a name reaching a newtype — a value's part and a call's result
still head nothing.

An import used only in a type position is a used import. It was reported
`[M-Unused]` before, because nothing in a type position could reach through one.

A type named only as an argument an `impl` supplies its trait is a used type.
It was reported `[N-Unused]` before, because nothing read those arguments at
all — which is the same defect the qualified one made visible, seen from the
side of a name written in this module.

The parser reads `?(` after a path as the fallible construction form, where it
read only a bare name before. The reasoning is the one that was already written
for a name: a call's head is a name or a path to one, so `?` applied to a path
and the result called is a reading nothing in the language can produce.

## Alternatives considered

**Drop the production from the grammar.** The other way to close the gap: make
`pct.Thing` a parse error and leave `use` the only door. It costs a spelling
every other dotted position has, and it makes the annotation grammar the one
place a module name may not appear — which is the rule that had to be discovered
by writing it and reading `[N-Undefined]` about a module. It also does not
follow from anything: a module is a namespace, and the reason `pct.f` reads
through it is the reason `pct.Thing` does.

**Resolve the head in the checker instead.** The checker would have to ask which
imports are in scope, which is the resolver's table, and the answer would then
exist in two places — the shape [0048](0048-one-question-has-one-answer.md)
names as this compiler's defect class. The resolver records what each name of
the run reached, and the checker reads it.

**Give a qualified head its own written-type kind in the parser.** It would let
the checker branch on a tag rather than on what the head names, and the parser
cannot know: `pct` is a module here and could be a type parameter in the next
declaration. A tag would be the parser answering a question about names.

**Leave construction alone and require `use` for it.** Annotations would
resolve and `pct.Score(42)` would still be `[N-NotCallable]`, which is the same
gap one position further in. Construction is a call whose callee names a type,
and which spelling named it is not something any rule about construction reads.
