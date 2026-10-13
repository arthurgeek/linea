# 16. A pass is a function, and its arena is its caller's

Status: Superseded by [0120](0120-pass-results-and-scratch-have-distinct-caller-owned-lifetimes.md) — 2026-07-25

## Context

[ADR 0012](0012-immutable-representations.md) makes representations immutable
once produced, which settles what a pass may do to its *input*. It does not say
what a pass may read besides its input, what it may keep between runs, or who
frees what it allocates.

Left unstated, those gaps fill themselves in the usual way. A pass caches
something in a module-level variable. Another consults a global for a flag. A
third frees a representation its caller still holds, or does not free one
nobody else will. Each is locally reasonable and collectively they make the
pipeline impossible to run twice, test in isolation, or execute concurrently.

## Decision

**A pass is a function from representations to representations.**

```
pass(allocator, inputs...) -> output + diagnostics + side tables
```

Its result depends only on its arguments. Specifically:

- No global or module-level mutable state. No caches that outlive a call, no
  counters, no configuration read from anywhere but a parameter.
- Everything a pass needs is an argument, including the diagnostic sink and the
  allocator.
- Everything a pass produces is returned: a representation, side tables keyed
  by the ids of a representation, and diagnostics appended to the sink it was
  given.
- Running a pass twice on the same inputs produces the same outputs, so a
  failure reproduces and a dump is stable.

**Allocation is the caller's.** A pass allocates from the allocator it is
handed and never installs its own. The driver owns one arena per compilation
unit and frees it in one operation; a pass frees nothing it returns, and does
free its own scratch.

A representation borrows what it does not own and says so. `Ast` holds
`source` as a borrowed slice with the same lifetime as the `Source` it came
from, and owns its node arrays.

**A builder is a pass's private scaffolding.** Construction goes through a
builder that the producing pass owns; `finish` transfers the arrays into the
representation and leaves the builder invalid. No builder escapes the pass that
made it, which is what makes immutability structural rather than a convention.

Current pipeline, stated so a reader need not infer it:

| Pass | Consumes | Produces |
| --- | --- | --- |
| `tokenize` | `Source` | `TokenList`, diagnostics |
| `parse` | `Source`, `TokenList` | `Ast`, diagnostics |
| `evaluate` | `Ast` | value, diagnostics |

Every future pass extends this table, and a pass whose row cannot be written is
not a pass.

## Consequences

- A pass can be tested by calling it, because there is no state to arrange
  first and none left behind.
- Passes can run concurrently over a shared const view, and can be re-run for
  incremental compilation, because neither depends on ordering beyond the data
  flow the table describes.
- Teardown is one arena reset, and no pass owns a lifetime question.
- The parameter lists grow as passes accumulate side-table dependencies. This
  is a visible dependency rather than a hidden one and is treated as a benefit:
  a pass reaching for something it was not given must ask for it, in public.
- Reusing an allocation across compilations is not available. Where that
  matters the arena is reset and reused as a whole, not held by a pass.
- A pass that must memoise does so in a side table it returns, which makes the
  cache an output that can be inspected rather than hidden state.

## Alternatives considered

**A compiler context object threaded through every pass**, holding the
allocator, sink, options and interners. Common, and it shortens signatures.
Rejected: it becomes the place mutable state hides, since adding a field is
easier than adding a parameter, and it makes every pass's dependencies
indistinguishable from every other's.

**Let each pass own its allocations and free them when done.** Precise, and it
bounds peak memory. Rejected: the outputs outlive the pass by definition, so
ownership would have to transfer at every boundary — reintroducing the lifetime
questions the arena exists to delete.

**Allow module-level caches for expensive derived data**, such as a source line
index. Rejected: `SourceMap` shows the alternative, which is to construct the
derived structure where it is needed and let the caller decide whether to keep
it. A clean compile never builds one at all.
