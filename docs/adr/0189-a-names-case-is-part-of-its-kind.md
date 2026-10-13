# 189. A name's case is part of its kind

Status: Accepted — 2026-09-27. Extended by
[0190](0190-a-variant-line-is-not-a-continuation.md).

## Context

Linea's code followed one naming convention without the compiler holding it
to one: types, traits, variants and type parameters were capitalised, and
functions, fields, bindings, constants and modules were lowercase. Nothing
refused `enum Shade { light }` or `fn Make(self: Shade)`, so the convention was
a habit of the standard library rather than a property of the language.

Two things now read a name's case. A reader does: `.Ok(0)`, `Shade.Light` and
`point.x` differ in what the name after the dot is, and the case is what says
so before any lookup. And the parser wants to: a line opening with `.` after a
completed statement draws [S-Continuation] because `.x` could continue the
line above, but `.Ok(0)` -- the idiomatic way to end a function returning a
`Result` -- cannot, since no operation or field is capitalised. A note that
fires on every such tail is a note nobody reads, and telling the two apart
from the token alone needs the convention to be a rule.

What the code actually did, counted before the rule was written, by the
diagnostic the rule now emits:

| Kind | `std/` | `examples/` | `tests/` |
| --- | --- | --- | --- |
| Constants | 0 | 0 | 20,037, of which 20,001 in one generated chain; the other 36 in 21 cases |
| Functions | 0 | 0 | 3, in 2 cases colliding a function with a type or a variant |
| Modules | 0 | 0 | 3, in 3 cases colliding a module with a type parameter or `Self` |
| Types | 0 | 0 | 2, in 2 cases colliding a type with a generated or module name |
| Bindings | 0 | 0 | 2, one a local spelled like a type parameter, one a recovered parse |
| Type parameters | 0 | 0 | 1, spelled like the import it shadows |
| Variants, fields, traits, associated types, parameters, captures | 0 | 0 | 0 |

The standard library declares 72 module constants and every one is lowercase;
the examples declare 26, all lowercase. The conformance generator wrote two
capitalised constants of its own. Every miscased name outside the constants
was written to collide with a name of the other case.

## Decision

**A declared name starts in the case its kind requires, checked once where it
is declared, under [N-Case].**

- Capitalised: types (`struct`, `enum`, a newtype), traits, associated types,
  variants and type parameters.
- Lowercase: functions, projections, traversals, fields, parameters, module
  and `impl` constants, modules -- every element of an import's path and the
  name the import binds -- and every name a body binds: locals, pattern
  binders, loop and `else` binders, closure parameters and capture aliases.

The case is the name's first letter's. A leading `_` still marks a name
deliberately unused ([ADR 0014](0014-unused-declarations-are-errors.md)) and
says nothing about its case, and neither does a digit, so `_1light` is a
lowercase name. A name with no letter, such as `_1`, has no case and is
accepted in every kind: the rule makes the case a name has reliable, and a
caseless name claims none, so no reader and no rule of the parser reads a kind
from it.

The kind-to-case mapping has one home, `name_case.Kind`. Resolution records
the kind it checked each declaring token as, and a rename reads that record
to refuse a new name in the wrong case, naming the kind and offering the same
respelling the diagnostic does. A name restating another is checked where the
original is declared, so one mistake is one diagnostic: a trait
implementation's members, a `use`, a struct pattern's shorthand binder and a
capture without `=`.

Module constants are lowercase. The corpus held both spellings -- `let LIMIT`
beside `let limit` -- while the standard library wrote every one of its
constants in lowercase, so the library's spelling is the rule. A constant is a
value, and the rule is then simply that a value's name is lowercase.

The diagnostic names the kind and respells the name: `not_found` as a variant
becomes `NotFound`, `x86_64` becomes `X86_64`, `MakeThing` as a function
becomes `make_thing`, `IPv4Addr` becomes `ipv4_addr`, and `MAX_SIZE` as a
constant becomes `max_size`. A respelling no program can declare -- a
reserved word, or `Self` -- is named but not offered, and so is one that
would be declared twice where the name is, asked of the tables [N-Duplicate]
is decided by.

Module paths are held to the rule for consistency: a module is lowercase
wherever it is named, and its directory is how an import names it. No
symbol depends on it. A function's symbol ends its module route with a
separator no name holds, the root's empty route included, and brackets the
arguments an implementation supplies its trait, so two declarations have two
symbols whatever their names are spelled.

The check is resolution's, run once its bodies are walked. What declarations
write -- their names, type parameters, fields, variants, parameters of
functions, signatures, closures and callable types, and capture aliases -- is
read from the source tree's own tables, a row at a time. What a body binds by
a statement or a pattern is read from the bindings resolution made, because
which arguments of a pattern bind names is resolution's answer; reading the
tree for it would be a second answer to that question.

## Consequences

**The parser may decide by case.** A name's case now says whether it can be
an operation or a field, which is what lets [S-Continuation] stay quiet for a
line opening `.Ok(0)`; [0190](0190-a-variant-line-is-not-a-continuation.md)
records that refinement.

**The rule is an error, not a lint.** Like an unused declaration, a miscased
name is a mistake the language refuses, so no configuration can disagree with
another reader of the code about what `.Name` is.

**The formatter is unaffected.** The check runs in resolution, so `fmt`
formats a file that breaks the rule; a rule in the parser would have made the
formatter refuse it, because the formatter refuses a file the parser reports.

**Every primitive already conforms.** The compiler names `UInt8`, `Bool` and
the others rather than a declaration, so there is nothing to exempt; no
declaration a runtime boundary names was capitalised. The one member the
compiler provides, a structural template's component descriptor's `Type`,
names a type and is capitalised, and is read only where a type is written.

**The corpus was swept.** The standard library and the examples needed
nothing. The corpus's constants were respelled in lowercase, as were names
whose case only served to reach an unrelated question. The cases whose point
was a collision between a name and one of the other case -- an operation
spelled like a variant, a module spelled like a type parameter or `Self`, a
type parameter spelled like an import -- keep the collision and now report
[N-Case] for it, beside whatever else they reported, because the resolution
they exercise still runs on a program that breaks the rule.

## Alternatives considered

**A warning, or a lint the formatter reports.** Rejected because the case has
to be dependable to be read: a convention that may be broken cannot tell the
parser that `.Name` is not a field, and a warning is a convention with a
message attached.

**Checking in the parser.** Every declaration site is syntactic, so the parser
could report it. Rejected for two reasons: a bare pattern argument is a binder
or not according to resolution, and the formatter refuses any file carrying a
parser error, so formatting a file would depend on the names it spells.

**`SCREAMING_CASE` constants.** A third case for one kind makes the rule say
what a constant is before it can say anything, and the standard library never
wrote one. A constant is a value like a local, and reads like one.

**Case by the whole name, not the first letter** -- requiring `snake_case` or
`PascalCase` throughout. Rejected as more than the parser needs and more than
a reader relies on. The first letter is what separates the two classes of
name, and a mixed spelling such as `utf8Len` harms nobody's reading of what
it is.
