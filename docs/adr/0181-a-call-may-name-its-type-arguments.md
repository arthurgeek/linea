# 181. A call may name its type arguments

Status: Accepted — 2026-09-26. Replaces the bracket clause of
[0062](0062-an-indexed-place-is-a-place-and-every-index-is-checked.md), which
was never implemented; extends
[0161](0161-a-postfix-call-reaches-an-operation-never-a-field.md); refines
[0176](0176-a-function-name-is-a-value-its-uses-instantiate.md).

## Context

`text.Parse` gives `Str` one generic operation, `parse[T: Parse](self: Str) ->
Result[T, ParseError]`. Nothing among its arguments mentions `T`, so a call
learns `T` only from the type it is expected to produce:

```linea
let port: UInt16 = arg.parse()?
```

Where nothing is expected — an argument to a generic function, a value
matched at once, a chain — the call cannot be written at all without a
binding introduced only to carry the annotation. The request was for
`arg.parse[UInt64]()`.

That spelling did not parse as a call with type arguments. A bracket after a
value always indexed it, so `arg.parse[UInt16]()` read as the field `parse`,
indexed by the value `UInt16`, then called. Free functions were no better:
ADR 0062 said `f[x]` is an instantiation where `f` names a declaration, but
nothing implemented the clause, and the corpus recorded `id[UInt8](7)` as
[N-NotAValue]. No call form could name a type argument.

What the bracket means depends on what the name in front of it reaches, and
for a postfix call that is known only once the receiver's type is: whether
`x.name` reaches an operation is ADR 0160's lookup, which the checker runs.
The parser sees neither.

## Decision

**Brackets written directly before a call's arguments name the callee's type
arguments where the name in front of them reaches a function, and index what
is in front of them otherwise.** A function named alone or through a path, a
trait's operation named through its trait, and an operation a postfix call
reaches take type arguments: `id[UInt8](7)`, `Shelf.empty[Str](shelf)`,
`"8080".parse[UInt16]()`. A field is indexed: `rack.steps[0](5)` calls the
element `steps` holds. Because a postfix call reaches an operation and never a
field (ADR 0161), `x.name[…](…)` names type arguments exactly where
`x.name(…)` would call an operation, and one routine answers both.

A call names every type parameter its function declares, in declaration
order, or none. Naming is optional: inference remains the default. A named
argument must be a type ([N-NotAType]), must satisfy its parameter's bounds,
and the count must match ([T-Bound], the rule a written type's arguments answer
to). Named arguments settle their parameters before any argument is read, so a
disagreeing argument is [T-Mismatch]. The parameters of a generic
implementation's head and a trait operation's `Self` are not named here; the
receiver or the path settles them as before.

**The parser keeps both readings and decides nothing.** A bracket after a path
of names, or after a name or a selection whose `]` is followed on the same
line by `(`, is read twice:
as the index expression it always was, and as a list of written types through
the one type grammar. A reading is kept only where it reads the brackets whole
without a diagnostic; a failed reading leaves no rows and no diagnostics. The
type reading is a side table, `Ast.bracket_types`, keyed by the index node.
Where the contents are only types (`[A, B]`, `[[T; 2]]`), the index is an error
node nothing reports.

**ADR 0062's bracket clause no longer holds.** It said `f[x]` is an
instantiation wherever `f` names a declaration, and that the resolver
classifies every such bracket. Nothing implemented it. Here a bracket
instantiates where its head names a function, called or not, and a called
selection's brackets are classified by the checker; any other bracket is an
index.

**The name in front of type-argument brackets is not a value.** ADR 0176 makes
a function's name a value wherever an expression is written; `id[UInt8](7)`
calls `id` directly, and `id` there is the callee's name, as it is in `id(7)`,
rather than a function value indexed by a type.

**Without a call, the brackets name the instance a function value holds.**
`let make = create[UInt8]` is `create`'s function value with `P` settled to
`UInt8` before any use: the written arguments fill the function's own list of
the value's type parameters, and the value's uses settle only what is left, by
ADR 0176's rule. The count and bounds are checked as a call's are, and a bound
is reported at the type written. A selection from a value without a call is a
field, and its brackets index it.

**The resolver decides where it can and defers where it cannot.** A head
naming a function takes the type reading, resolved with type-argument context
so a value written there is [N-NotAType]. A head reaching nothing is the one
mistake reported, and its brackets are read as neither. Any other head that is
not a called selection from a value is indexed. A called selection from a
value is a method or a field, which the checker decides; both readings are
resolved, and what each would report is kept, not reported, in
`Resolution.bracket_readings`.

**The checker decides the rest, once.** `checkBracketCall` reads the
resolver's answer and, for a selection, runs `postfixCall` — the lookup every
postfix call uses. An operation takes the type reading and emits what its
resolution deferred; a field takes the index reading and emits that reading's
reports instead. Written type arguments seed `inferCall`'s settlement for the
function's own parameters. The call record carries `written_type_arguments`,
and `calleeName` and `postfixSelection` give the name in front of the brackets
to every pass after the checker, so ownership, lowering, instance discovery and
the language server read the settled call rather than the shape of its callee.

## Consequences

- `arg.parse[UInt16]()`, `nothing[Bool]()` and `Shelf.empty[Str](shelf)`
  compile. A generic function whose parameters no argument mentions is
  callable without an annotation carrying the type.
- `create[UInt8]` not followed by a call is the function value of that
  instance, which can be bound, stored or passed where a function is
  expected. Brackets holding only types after a value, `values[UInt8, Bool]`,
  are [T-Index].
- `(x.items[0])()` and `rack.steps[i](v)` keep meaning "call the element".
  `&x.name[T](…)` lends `x` to a method, and `&x.steps[i](v)` invokes a
  field's element mutably, as `&(x.steps[i])(v)` does.
- Brackets that read as types before a call or after a path are parsed twice,
  and a bracket nested inside another's is read again by each enclosing
  bracket's attempt. Every `items[i]` after a local is among them: its type
  reading reads the one name `i`, and the resolver indexes it. The cost is a chain's contents times its nesting depth,
  `O(n·d)`, and the depth is at most the parser's nesting limit of 1000 levels;
  a reading that runs past the limit is reported once and not read again. A
  bracket holding an ordinary index fails its type reading at the first token
  that is not a type.
- Brackets holding only types before a field's element are [T-Index]: they
  form no index.
- The formatter prints a type-only bracket through the type printer; every
  other bracket prints through the expression printer as before.
- The tree-sitter grammar has no resolution to consult, so it does not
  guess either way. It reads brackets before a call as type arguments only
  where their contents cannot be an index — two or more types, a type
  followed by a comma, or a type that is no expression such as `[UInt8; 2]`
  or `fn() -> UInt8` — which is exactly where the compiler's parser keeps no
  index reading. Everywhere else the tree holds the index it always did, and
  the highlight queries colour a capitalised name in that index as a type by
  naming convention, so `parse[UInt16]()` shows a type and `steps[at](5)` a
  variable.

## Alternatives considered

**A separate spelling for type arguments**, as Rust's `parse::<u16>()`. It
needs no decision after resolution, but it adds a second bracket syntax for
the one idea `Vec[UInt8]` already spells in types, and a call and a type would
write the same instantiation two ways.

**Methods only.** The request named a method, and methods were where the
question could not be answered by the parser. Leaving `f[T](x)` and
`Type.m[T](x)` out would have made one question — does this call name its type
arguments — have two answers depending on how the call was spelled.

**Deciding in the parser by the bracket's contents.** A bracket holding a
capitalised name before a call could be read as type arguments. That guesses:
`handlers[index](request)` holds a name that reads as a type, and the parser
does not know whether `handlers` is a function. The frontend never guesses;
it records both readings.

**Converting the index expression to a type in the checker.** The expression
reading already holds `UInt16` and `Vec[UInt8]`, so a routine could translate
it. That is a second grammar of types beside `parseWrittenType`, and it cannot
express `[UInt8; 2]`, `fn() -> UInt8` or a list of two types, which are not
expressions.
