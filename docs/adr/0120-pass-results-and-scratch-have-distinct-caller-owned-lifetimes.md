# 120. Pass results and scratch have distinct caller-owned lifetimes

Status: Accepted — 2026-09-08

Supersedes [0016](0016-passes-are-functions.md).

## Context

ADR 0016 makes passes functions with explicit inputs and caller-owned allocation.
Its single-arena requirement also keeps temporary allocations until compilation
ends. Individual frees in an arena need not reclaim storage. An editor retains
its semantic result between requests, so a temporary ownership graph can enlarge
the retained arena even though no graph data crosses the pass boundary.

The ownership checker already distinguishes those lifetimes semantically: the
CFG, flow state and cancellation bookkeeping are temporary; `DisposalPlan` is the
returned answer. Diagnostics belong to the supplied sink. Giving those values
one allocator obscures a distinction the representation already makes.

## Decision

**A pass remains a function of its explicit inputs.** It has no mutable global
state, configuration read outside its arguments, or cache outliving the call.
Representations remain immutable after construction. Private builders transfer
finished arrays into returned representations and do not escape.

**Allocation and lifetime remain the caller's, with distinct retained and scratch
allocators where their lifetimes differ.** A pass allocates returned data from
the retained allocator and temporary scaffolding from the scratch allocator.
It frees its temporary allocations and never frees a returned result. Diagnostic
messages and labels use the supplied sink's storage, whose lifetime covers their
consumers. A result may not borrow from scratch after the call returns.

The driver owns an ownership-pass scratch arena backed by the caller's scratch
allocator. The canonical ownership check receives both allocators explicitly;
only construction of the returned `DisposalPlan` uses retained storage. The
driver releases the temporary arena before continuing the pipeline. The editor
supplies its parent allocator for this temporary region and retains its semantic
and reached-source regions until the cached analysis is replaced.

**Retained region backing is also supplied explicitly.** The LSP entry point
passes the process's existing compilation-region backing through the server to
Analysis. Semantic and reached-source arenas use that backing; general scratch,
message buffers, documents and workspace indexes continue to use the general
allocator. On native targets the process supplies page-backed regions, so ending
an Analysis releases its mappings without depending on the general allocator
returning freed arena pages immediately. Analysis does not select a
global allocator or install a custom growth policy. Tests can inject independent
failing allocators into both domains.

This choice trades request cost for bounded region residency: measured dependency
edits add roughly 0.5–0.6 ms versus PR1 while reducing process peak RSS on both
observed path layouts. It changes the LSP's retained-region policy, not CLI
compilation allocation or semantic behavior. Platform-specific effects still
require measurement; freeing a general allocation alone does not promise an
immediate reduction in process RSS.

A caller may supply the same allocator for both domains when they share a
compilation lifetime. Actual reclamation then follows that allocator's contract;
an arena-backed scratch parent may retain released storage until its own reset.
No pass installs a global allocator or chooses a lifetime hidden from its caller.

## Consequences

- Temporary CFG and flow storage cannot escape through a disposal plan or
  diagnostic. Permanent tests release scratch before reading both outputs and
  check allocation failures independently in the two domains.
- Teardown can release several caller-owned regions. The former requirement for
  exactly one compilation arena and one reset no longer applies.
- Parameter lists expose a real lifetime dependency. Existing semantic decisions,
  pass ordering, and the authority of the ownership disposal plan are unchanged.
- A short-lived arena amortizes temporary allocations without tying them to the
  retained result. Memory and request-latency effects still require measurement;
  separating lifetimes alone does not establish a performance improvement.

## Alternatives considered

**Tune an arena's initial size to a measured fixture.** Rejected: a small source
change can move the next growth boundary, and temporary storage still has the
wrong retained lifetime.

**Let ownership use a global allocator.** Rejected: allocation failures, lifetime
and accounting must remain under caller control.

**Build the result in scratch and copy it afterward.** Rejected: the existing
plan constructor can allocate the retained answer directly. A second copying
path adds work and another ownership transfer without changing the representation.
