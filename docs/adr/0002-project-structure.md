# 2. Compiler lives under `src/`, one directory per pass

Status: Accepted — 2026-07-24

## Context

The target layout names a directory per compiler phase: driver, diagnostics,
lexer, parser, syntax, resolver, hir, typeck, ownership, mir, optimize,
backend/qbe, support. Alongside the compiler the repository will eventually
hold a runtime, a standard library, examples, tests and documentation.

Zig's build system and `build.zig.zon` conventionally root a package at `src/`,
and `build.zig.zon` already declares `src` in its `paths`.

## Decision

The compiler occupies `src/`, with the phase directories nested directly
inside it. `runtime/`, `std/`, `examples/`, `tests/` and `docs/` are siblings
of `src/` at the repository root.

Directories are created when they hold code. Empty placeholder directories for
future passes are not created.

Rules that hold across all phases:

- A phase directory depends only on `support/`, `diagnostics/`, and the
  representation it consumes.
- No phase imports a phase that runs after it.
- A representation (`lexer/token.zig`, `syntax/`) does not import the pass that
  produces it.
- `support/` imports nothing from the compiler.

## Consequences

- Import direction encodes pipeline order, so a cycle in the module graph is a
  design error that Zig reports at compile time.
- The layout matches Zig package conventions, so `build.zig` stays
  unremarkable.
- Nesting phases under `src/` rather than a top-level `compiler/` adds one path
  component relative to the reference layout. The naming is otherwise
  identical.

## Alternatives considered

**Top-level `compiler/` directory as a sibling of `runtime/` and `std/`.**
Matches the reference layout exactly and reads well once self-hosting makes the
three peers. Rejected for now: it fights Zig's `src/` convention for no present
benefit, since neither `runtime/` nor `std/` exists.

**Flat `src/` with prefixed filenames — `lexer_token.zig`, `parser.zig`.**
Rejected: prefixes are directories with worse ergonomics, and the dependency
rules above become conventions in filenames rather than structure.

**Group by representation rather than by pass** — a directory per IR holding
both the data and the passes that produce it. Rejected: passes that read two
representations have no natural home, and the pass boundary is the unit that
needs isolating.
