# 111. Import paths are root-relative

Status: Accepted - 2026-09-03. The reserved-root sentence is superseded by [0171](0171-the-standard-library-is-an-ordinary-library.md).

Supersedes ADR 0032's implemented descending-path clause.

## Context

A descending import can only reach a child of the module that writes it. That
made the primary import graph acyclic, but it also made sibling modules unable
to cooperate directly and made an import ring possible only through the
reserved standard-library root. Structural implementations generated in a
target module could not reproducibly import a sibling trait module.

Falling back from a missing child to a root-relative path was considered, but
would make an existing import change meaning when a new child directory was
added.

## Decision

An ordinary non-`std` import path is relative to its independently loaded source
root, not to the importing module. `std` remains a reserved root naming the
standard library. The loader registers a module before following its imports,
so rings terminate at the already loaded module.

The immutable `Program` retains one canonical source spelling per loaded module
and exposes `importRoute(from, to)`. Resolver-integrated generation consumes
that answer; it does not inspect filesystem paths or implement import semantics
a second time.

## Consequences

Every module in one root writes the same route to a target module. Sibling and
ring imports are ordinary, and generated files can be materialized and reparsed
without hidden loader state. Existing nested-module imports migrate from a leaf
spelling such as `import b` to its root-relative spelling `import a.b`.

## Alternatives considered

**Keep descending imports and add `..`.** Rejected because path normalization,
root escape and canonical spelling would become source-language concerns solely
for generated code.

**Try root-relative resolution only after a descending path fails.** Rejected
because adding a child directory would silently retarget accepted source.
