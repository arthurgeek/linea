# 183. A structure literal may take its other fields from a base

Status: Accepted — 2026-09-26. Extends
[0151](0151-a-named-structure-literal-carries-a-written-type.md), whose "every
field is supplied exactly once" now holds of a literal without a base, and
[0140](0140-aggregate-constants-retain-checked-construction-plans.md), whose
constant domain now admits a literal built from a constant base.

## Context

`Default` gave configuration records such as `http.Limits` and
`json.ParseLimits` a standard value, and adjusting one field of it took three
statements and a mutable binding:

```linea
var limits: http.Limits = Default.default()
limits.connections = .Some(1)
http.serve(listener, &server, mem.system(), limits)
```

The same shape appeared in `std/fmt/spec.lin` (a padded `Spec` built from a
plain one), in the HTTP server's tests, in `std/http/response.lin` (a response
with another status), in `std/fs` (a filesystem outcome with one part
recorded) and in the examples. Each site restated nothing but
the one field it cared about, and paid for it with a `var` whose mutability
outlived the construction. [ADR 0077](0077-arguments-match-by-name-and-evaluate-by-declaration.md)
rejected field defaults and named the evidence that would reopen the question:
construction sites routinely restating the same field values. That is what the
library now shows.

## Decision

**A structure literal may end with `..base`.** Every field the literal does not
write takes its value from `base`, an expression of the literal's own type:

```linea
let limits = http.Limits { connections = .Some(1), ..Default.default() }
let tuned: Window = .{ depth = 2, ..tall }
```

The base is checked against the literal's type, so `Default.default()` there
settles to the literal's type the way it does under an annotation, and
`..http.Limits.default()` reaches the same operation through the type
([ADR 0186](0186-a-type-reaches-the-operations-of-the-traits-it-implements.md)).

Both the named and the contextual literal take a base. The base does not supply
the literal's type: a contextual literal still needs an expected type
([T-Infer]), so the type is always written at the head or given by context.
A trailing comma may follow the base, and nothing else may
([S-BaseLast]). A base that supplies no field, because the literal writes every
field, is refused ([T-UnusedBase]) rather than evaluated and thrown away. A
literal that writes no field and names a base, `Pair { ..pair }`, drops nothing:
it is the base, moved, and is accepted.

**The base evaluates last.** Initializers already evaluate once in written
order ([ADR 0151](0151-a-named-structure-literal-carries-a-written-type.md)),
and the base is written last. This is also the order that makes the common
update expressible: `Counter { hits = counter.hits + 1, ..counter }` reads
`counter.hits` and then takes `counter`. The literal's values and its base form
one [N-Aliased] domain, as a call's arguments do.

**The base is a consuming position.** The literal takes the base whole, moves
every field it does not write into the new value, and drops every field it
does write. A consuming position moves an aggregate regardless of its
capabilities, so a copyable base is taken too; `..copy(defaults)` keeps
`defaults`. A part of a binding is not a base, for the reason it is not
movable anywhere else ([O-Move]).

**A dropped field that owes settlement is [O-Leak].** Dropping a replaced field
is an overwrite of that part of the base, and the overwrite rule already
refuses writing over a Linear part. The check reads the field's declared type
through the same question every other [O-Leak] position asks, so an unbounded
type parameter counts as Linear and `Slot[T] { held = x, ..slot }` is refused
in a generic body. The report names the written field and the base. Discard
never runs cleanup, and nothing here schedules any.

**Visibility is the literal's.** A literal of a sealed type is refused outside
its module whether or not it has a base ([M-Opaque]). A field carries no
visibility of its own, so a literal that may be written may take every field
from its base; there is no case of a hidden field copied implicitly.

**A literal with a constant base is a constant expression.** The shared folder
folds the written fields, then the base, and merges the base's record with the
written fields by name. Construction plans are derived from the folded value
and its type, so nothing downstream learns that a base was written.

### Representation

The base occupies the callee slot of the structure literal's call payload,
which a literal had no use for; `Ast.structLiteralBase` reads it. No payload
shape or side table is added, and walkers that already visit a call-shaped
node's callee visit the base. The literal's field/value pairs keep their
alternating layout, so every reader of pairs is unchanged. Ownership emits one
`replaced` operation per written field of a literal with a base, carrying the
base as its source, and the checker asks the field's type whether it owes.
Dependency analysis carries the base's facts into the new value except those
under a written field. Lowering writes the fields into the destination, then
evaluates the base and copies each unwritten field out of it, tracking written
fields in a table sized by the literal's type.

## Consequences

Configuration updates are one expression with no mutable binding, and the
library and examples were converted: `http.Limits`, `json.ParseLimits`,
`fmt.Spec` and `fs.FsFailure` updates, the HTTP server tests and examples, a
response with another status and a request with its matched path values. A
test that changes a value between checks keeps its `var`, because it changes
the value more than once.

The program generator writes updates too, taking the base from a field of a
binding in scope or from a nested literal, so the rewrites the corpus runs over
generated programs reach bases in structures and enums.

A reader must know the base's value to know every field of the result, which
is the cost of not writing them. The base being evaluated after the fields
means a field initializer may observe the base before it is taken, and this is
the order a reader sees.

A literal whose type gains a field keeps compiling when it has a base: the new
field silently comes from the base. That is the point of the construct for
configuration, and the reason a literal meant to spell every field should not
take a base.

## Alternatives considered

**Field defaults in declarations.** `struct Limits { max_headers: UInt64 = 100 }`
puts the standard value beside the field. Rejected, as
[ADR 0077](0077-arguments-match-by-name-and-evaluate-by-declaration.md) rejected
it, because it is a second mechanism beside `Default`: a type would have a
default for each field and a `Default` implementation, which can disagree, and
the question of what a default expression may see, run and own comes back for
every field. A base reuses `Default`, a constant or any value of the type, and
asks none of those questions.

**Builder functions.** `limits.with_connections(1)` per field needs one function
per field per type, written by the library author, and hides whether the
function does anything else. Rejected as boilerplate that scales with the
number of fields and still leaves callers without a way to change a field the
author did not anticipate.

**Keep full literals and the `var` pattern.** No new syntax, but every
adjustment of a standard value costs a mutable binding and a statement per
field, and the mutability outlives the construction. Rejected on the evidence
above.

**Evaluate the base first.** It would match a reading of `..base` as "start
from base, then apply the fields", but it contradicts written-order evaluation,
and it makes `Counter { hits = counter.hits + 1, ..counter }` a use after move.
Rejected.

**Let a copyable base stay usable.** Treating the base as a read of a copyable
value would duplicate an aggregate implicitly, which the language allows only
through `copy`. Rejected; `..copy(base)` says it.

**Infer a contextual literal's type from its base.** `.{ x = 1, ..base }` with
no context could take `base`'s type. Rejected to keep one rule for where a
literal's type comes from: its head or its context. `T { x = 1, ..base }`
costs the type name once.

**Accept a base that supplies nothing.** Harmless-looking, but the base is then
evaluated only to be dropped, which is the unused-value shape the language
refuses elsewhere.
