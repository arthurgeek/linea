# 274. A `From` derive selects its variant by type identity

Status: Accepted — 2026-11-16; supersedes the variant selection of
[0209](0209-a-from-derive-converts-the-variant-the-source-names.md) (the
derive entry "selects the variant by comparing the parameter's written type
... against each one-field variant's written type with the same routine
coherence uses for the arguments of two implementations", and the consequence
"a derive comparing written types reads through aliases"), and the clause of
[0113](0113-structural-derivation-is-library-defined-source.md) that
structural reflection is "erased during source generation", as far as it
speaks of `reflect.wrap`. Extends
[0093](0093-two-implementations-that-could-answer-once-are-refused.md), whose
overlap rule is the identity the selection reads.

## Context

`@derive(From[S])` on an enum wraps the source in the one variant whose only
field has the source's type. 0209 decided that variant during expansion, by
comparing written types with `sameWrittenType`. That comparison reads through
an alias, but a settled reference is still the selection it was written as:
with `impl Measure for Celsius { type Reading = Kelvin }`,
`@derive(From[Celsius.Reading])` on `enum Temp { Hot(Kelvin), Unknown }` was
refused, "no variant of `Temp` wraps exactly `Celsius.Reading`", and so was
the reverse, a source `Kelvin` with the payload written `Celsius.Reading`.
`Hot(Kelvin)` beside `Warm(Celsius.Reading)` was accepted with `From[Kelvin]`,
selecting `Hot`, although both variants hold a `Kelvin`.

Coherence already answers the question the other way. The checker's overlap
rule refuses `impl Tr for W[S.Reading]` beside `impl Tr for W[UInt8]` when
`S.Reading` is `UInt8`, and two heads `Shelf[Read[Celsius]]` and
`Shelf[Kelvin]` with `alias Read[T: Measure] = T.Reading` overlap. The
compiler therefore held two answers to "are these the same type": one for the
derive and one for coherence.

A settled reference is answered only by the checker. What `Celsius.Reading`
is depends on which implementation of `Measure` answers for `Celsius`, which
needs implementation heads, bounds and declared answers (0241), none of which
exist while expansion renders a derive. The variant could not be decided where
0209 decided it without a second routine settling references from written
text.

## Decision

**The checker selects the variant a `From` derive wraps, by type identity.**
Two types are one where the type pool holds them as one: an alias, a settled
reference and the type either names are interned as that type, which is the
identity the overlap rule of 0093 unifies over. The selected variant is the
one variant whose only field's type, at the derive's target as the generated
implementation applies it (its `Self`), is the type of the wrapped parameter.
No such variant, or two, is [T-Derive] at the derive entry, with the existing
messages.

1. **Expansion renders a placeholder.** `reflect.wrap(source)` is rendered as
   the contextual variant reference `.wrap(source)`, which names no variant.
   Expansion records each placeholder's expression, the generated
   implementation it belongs to and the template parameter it wraps
   (`ExpandedProgram.wrap_sites`). The rest of the implementation is ordinary
   source, as before.
2. **The checker decides.** Checking a call whose callee is a recorded
   placeholder (`checkWrap`) reads the wrapped parameter's type and the
   target's one-field payload types, selects the variant whose payload is
   that same type, and records it in the table every contextual variant is
   recorded in. The built value has the target's type wherever the wrap
   stands, and is held to what its position expects as any expression is:
   a template member promising `Option[S]` that returns `reflect.wrap(value)`
   is [T-Mismatch], and `let lifted = reflect.wrap(value)` needs no
   expectation. Ownership, instance discovery and lowering read the
   variant from there, as they read `.Hot(source)`.
3. **The text is written after checking.** The generated file a reader sees
   (`dump-expanded`) and the file derive materialization reloads as ordinary
   source are written from the checked program
   (`generated_text.settledGeneratedTexts`): each placeholder becomes
   `Target.Variant`, the constructor 0209 rendered. 0113's check that a
   derive and its generated text compile alike still compares that text
   against the original program.
4. **A source that names no type generates nothing.** Expansion still asks
   whether the wrapped source's names resolve, and an entry whose source does
   not generates no implementation; that is a question about names, not
   types. A source or payload that resolved but was refused as a type selects
   nothing and adds no [T-Derive], as before.
5. **A payload read through the enum's parameter is no particular type.** In
   `enum Box[T: Measure] { Held(T.Reading) }`, `T.Reading` is settled by each
   instantiation, so the generic conversion finds no variant holding a
   `Kelvin`; the report says so.

Nothing new is a representation in the sense of the compiler's invariants: the
wrap sites are a table of the expanded program keyed by expression, and the
selected variant is a row of the checker's existing contextual-variant table.
The written-text comparison the derive used (`selectWrappedVariants` and its
reading context) is deleted, and the generated text a tool shows is computed
from those two tables rather than stored.

The same reading fixes a defect the cases found: an implementation whose
trait argument applies a generic alias of a settled reference,
`impl Takes[Read[Celsius]] for Temp`, was read before implementation heads
were settled and never read again, so nothing reached it. Applying an alias
whose written type reads a settled reference now counts as the selection it
performs, and such a head is read again once heads are settled, as one
writing the selection directly is.

## Consequences

- `@derive(From[Celsius.Reading])` selects `Hot(Kelvin)`, and so do the
  payload written `Celsius.Reading` with source `Kelvin`, an alias of the
  settled reference, and the generic alias `Read[Celsius]`.
- Behaviour change: `Hot(Kelvin)` beside `Warm(Celsius.Reading)` with
  `From[Kelvin]` is refused, "`Temp` has two variants wrapping `Kelvin`",
  where 0209 accepted it and selected `Hot`. Both variants hold one type, and
  0209's own rule refuses two.
- A refused `From` derive still generates its implementation, with a body the
  checker refused. A call of `Temp.from(...)` therefore reaches it and adds no
  [N-Undefined] "declares no `from`" beside the [T-Derive]. The same holds
  where the derive's source names a settled type no implementation supplies:
  the implementation's refused trait argument is the report, and a call of
  an operation its trait declares is not a second one; and an enum whose
  only use is a refused `From` derive is not reported unused, as an enum with
  any other derive is not.
- The [T-Derive] report for a wrap moves from expansion's selection to the
  checker, after every written type's bounds are checked, so a source refused
  as a type is still its only report.
- Selection costs one pass over the target's variants per wrap, as before;
  writing the text after checking costs one copy of each generated file, and
  only for the tools that print or reload it.

## Alternatives considered

**Keep comparing spellings.** The derive and coherence would keep disagreeing
about whether `Celsius.Reading` and `Kelvin` are one type: the overlap rule
refuses two implementations at those arguments, and the derive refused to
treat them as one. One question would keep two answers.

**Settle references from written text during expansion.** Find the
implementation for the reference's base and read its `type Reading = …`
text, substituting a generic implementation's parameters. That is a second
place answering what a settled reference names beside the checker's, which
also reads bounds, trait arguments and ambiguity; the two would drift.

**Select in the checker but keep 0113's text before checking.** The generated
text would have to name a variant before anything chose one, so the
materialization check would compile a program other than the one that ran.

Rust normalizes `<Celsius as Measure>::Reading` to `Kelvin` before comparing
types for the same reason: a projection whose implementation is known is the
type that implementation names.
