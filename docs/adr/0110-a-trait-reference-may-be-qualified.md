# 110. A trait reference may be qualified

Status: Accepted - 2026-09-03

Supersedes ADR 0080's implemented bare trait-slot clause.

## Context

Traits were nameable through imports and re-exports, but every position that
specifically expected a trait stored a bare token. Cross-module structural
derivation therefore required either a `use` at each site or generated-only
syntax that ordinary source and tools could not reproduce.

The affected positions had also drifted into parallel parser and AST shapes:
implementation headers, template targets, derive entries, supertraits, generic
bounds and trailing predicates each retained different pieces of the same
written name.

## Decision

Every trait position accepts one form:

```text
trait_ref ::= name ("." name)* type_arguments?
```

One source `TraitRef` stores the complete path, final name and arguments. The
resolver walks imported module namespaces and records every component at the
binding it reaches. All semantic consumers use the canonical final trait
`DeclId`; formatters and editors use the retained source path.

The form is ordinary source syntax. Generated implementations use it without a
hidden namespace or a generated-only parser branch.

## Consequences

Definition, references and rename follow the final trait component through the
resolver's existing indexes. Completion after a module dot in a trait position
offers the visible traits of that module. Existing argument restrictions remain
properties of their positions rather than of the shared grammar.

## Alternatives considered

**Require `use` before every trait reference.** Rejected because modules already
qualify types and values, and generated source would still need an invisible
exception or injected alias binding.

**Add qualified syntax only to derives and generated files.** Rejected because
one semantic name would have two grammars and tools could not treat materialized
generated source as ordinary Linea.
