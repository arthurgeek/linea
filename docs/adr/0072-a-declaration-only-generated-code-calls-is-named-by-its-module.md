# 72. A declaration only generated code calls is named by its module

Status: Accepted — 2026-08-04; refines 0060

## Context

[0060](0060-a-library-declaration-is-named-through-the-prelude.md) settled how
the compiler names a library declaration: by name, in `Resolution.prelude`, the
list every ambient name in every module resolves against. That is the right
answer for `Option`, `Result`, `Str` and `Display` — the compiler recognises
them, and programs write them too, so being published is what they were for.

`report` is not like those. It exists so that a failure leaving the entry point
([0071](0071-a-failure-may-leave-through-the-entry-point.md)) has somewhere to
be rendered, and **no program should ever call it.** But the only way the
compiler could find it was to publish it, so it sat in every program's namespace
because of a lookup rather than because of a decision.

The same shape is queued behind it: a `panic` the language reaches, derive
templates, allocator hooks. Each would be published for the same non-reason.

## Decision

**A declaration only generated code calls is named by its module and its name:
`text::report`, looked up directly rather than through what the prelude
publishes.**

So there are two lookups, and which one applies is decided by who else writes
the name:

| the compiler names | found by | example |
| --- | --- | --- |
| something programs write too | the prelude's exports, by name — 0060 | `Option`, `Result`, `Str`, `Display` |
| something only generated code calls | its module and name | `report` |

The declaration stays an ordinary `pub fn` in `std/text`. What changes is that
the prelude does not re-export it, so no program can name it — `report(1)` is
`[N-Undefined]` — while lowering finds it regardless.

### What this costs, stated plainly

**The compiler learns one module name.** Moving `report` out of `text` now
touches the compiler, where before only the prelude's export list did.

0060's stated guarantee survives exactly as written: *"a library file may move
without the compiler changing"*. Files inside `text` still move freely; the
module is what is named, not a directory path or a file. What is given up is
narrower than that guarantee, and it is given up knowingly.

### Why not a marker on the declaration

A third visibility — `compiler fn report` — was the first proposal, on the
grounds that it keeps 0060's decoupling whole: the compiler would learn a name
and not a location, so the declaration could move anywhere.

It was rejected because **no language does this, and the decoupling is not worth
inventing grammar for.** Rust reaches its equivalents with an attribute
(`#[lang = "…"]`), Swift with attributes (`@_semantics`, `@_silgen_name`), Go
with a pragma comment (`//go:linkname`), and Zig with a naming convention
(`root.panic`). Three of those four pin a location anyway; Swift's known-decl
tables name the stdlib module.

A keyword for this would be a word in the language that exists to serve the
compiler's own bookkeeping, and [ADR 0056](0056-a-modifier-is-refused-where-it-says-nothing.md)'s
instinct — refuse a modifier that says nothing to the program — points the same
way even though the word would technically say something.

### Why not an unspellable name

`{report}`, on the trick that makes an interpolation's type unnameable, needs a
spelling at the *declaration* too. That means lexer support for a name no
identifier can be, which is more machinery than the module name costs.

## Consequences

**One fewer name in every program's namespace**, and the count stops growing
with each thing the compiler needs to call. `panic`, derive templates and
allocator hooks now have somewhere to go that is not the prelude.

**The lookup is unshadowable.** A qualified identity is not a key in any
module's local scope, so nothing can be declared to intercept it — where the
by-name lookup relies on `[N-Duplicate]` to keep a second `Option` from
existing.

**`pub` stays on the declaration**, and it must: `[N-Unused]` exempts what
another module could have called, and nothing in `text` calls `report`. `pub`
here means *reachable by a module that imports `text`* — which is only the
prelude, and the prelude does not re-export it.

**0060 is refined, not superseded.** Its lookup is still the right one for every
name it was written about, and this record adds the second case rather than
replacing the first.

## Alternatives considered

**A third visibility**, rejected above.

**An unspellable name**, rejected above.

**Leave it published.** What the branch did until now, and the reason to stop is
that the list only grows: every future thing generated code calls would join
`report` in the prelude, and none of them is a name a program should see.

**Resolve it as a path** — `std/text/out.lin` — which is what 0060 refused and
still refuses. A module is named; a directory is not.

## Deliberately open

**Whether a program should be told what it hit.** `report(1)` today is
`[N-Undefined]`, which is true — no binding with that name is in scope — but a
reader who has seen the name in a stack trace or in the library learns nothing
about why. A diagnostic naming it as the compiler's would be friendlier and
needs the resolver to know these declarations exist, which today it does not.

**Whether `intrinsic` belongs beside `extern`.** Three ways a declaration can
have no body written in the program are now visible: the runtime implements it
(`extern`, [0068](0068-a-declaration-may-name-a-symbol-the-runtime-provides.md)),
the library implements it and the compiler calls it (this record), and the
compiler implements it inline per instantiation — which is `intrinsic`, which
nothing needs yet. The trigger is a primitive that is generic over a type, since
no single linkable symbol can implement one, and that arrives with containers.
