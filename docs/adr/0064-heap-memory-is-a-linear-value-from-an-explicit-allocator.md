# 64. Heap memory is a linear value obtained from an explicit allocator

Status: Superseded by [0095](0095-the-system-allocator-is-named-rather-than-received.md) — 2026-08-20

## Context

Linea's linear types were chosen over affine ones in
[0034](0034-ownership-is-positions-and-a-graph.md) on the argument that a value
consumed exactly once, explicitly, is the honest model for a resource. Until
now the language has had no resource to demonstrate it on: every Linear type in
the corpus is Linear because someone wrote `linear`, and disposing of one does
nothing.

Heap memory is the first real one. It is also the standard demonstration of a
memory-safety story, and the three failures it must rule out are named:
use-after-free, double-free, and leak.

The claim this record has to make good on is that Linea rules out all three
**with rules it already has**, and that heap memory needs no ownership rule of
its own.

## Decision

**A heap allocation is a `linear` value obtained from an allocator that is
passed explicitly. Its type owns the memory; consuming the value is what frees
it; and nothing about it is reachable after it is consumed.**

### The three failures, and which existing rule refuses each

| Failure | Refused by | How |
| --- | --- | --- |
| **leak** | `[O-Leak]` | A Linear value still owned at a scope end. Unchanged. |
| **double free** | `[O-Move]` | Freeing consumes. A second consume reads a `moved` place. Unchanged. |
| **use after free** | `[O-Move]` | Reading a `moved` place is the same error as consuming one twice. Unchanged. |

That the last two collapse into one rule is not a simplification made for this
record — it is what
[0034](0034-ownership-is-positions-and-a-graph.md) already says, and heap memory
is where it stops being a claim about a toy.

**No new ownership rule.** If R2 finds itself adding one, the linear model did
not in fact cover the case, and that is a result worth having rather than
papering over.

### The allocator is a parameter, not an ambient

An allocator is reached by being passed. There is no global one, no implicit
one, and no way for a library type to acquire memory without its caller
supplying the means. `Vec[T, A: Allocator]` at R4 is a type parameter bounded by
a trait, monomorphised like any other — never a trait object, per the generics
design.

R2 itself does not need the trait. It needs *one* allocator reachable from
Linea source, and the trait that abstracts over allocators is R4's problem.
Taking it now would be designing an interface with one implementation.

### The memory is reached by checked load and store

A buffer is not an array: its length is a value, not part of its type. So an
access at an offset cannot be checked against a constant, and the check is a
comparison against the length the value carries. Out of range traps, exactly as
an array index does, and misalignment traps too —
[0013](0013-no-undefined-behaviour.md) admits no third outcome.

### The runtime gains an allocator

`runtime/linea_rt.c` already exposes `linea_trap`; it gains allocation and
release. That the interface is versioned is engineering rather than
architecture.

## Consequences

**Every container built on this is Linear, transitively.** `[O-Universe]`
forbids a Free type containing a Linear one, and
[0046](0046-the-universe-of-an-instantiation-is-computed.md) computes an
instantiation's universe from its arguments — so a `Vec` owning a buffer is
Linear, and a structure holding a `Vec` is Linear, all the way up. That is
correct and it is the cost: **nothing that transitively owns heap memory can be
copied, and every one of them must be disposed of explicitly on every path.**

**Which makes `defer` a prerequisite rather than a nicety.**
[0063](0063-disposal-is-scheduled-never-inserted.md) is what keeps that cost
payable, and R2 should not land meaningfully ahead of it.

**Allocation can fail, and failure is a value.**
[0017](0017-failure-is-a-trap-or-a-value.md) makes failure a trap or a value and
never both. Out-of-memory is a value: `alloc` answers with a `Result`, so a
program that ignores it does not compile. A trap would make every allocation an
unwritable failure path, and the language has `?` precisely so that a `Result`
is cheap to thread.

**A buffer's contents are bytes, not values.** R2's buffer stores and loads
integers at offsets. It does not know about `T`, does not run element
constructors, and cannot hold a Linear element — because a Linear value stored
into raw memory is one the ownership pass has lost track of, and there is no
rule that would find it again. Typed storage is R4's problem and needs the
element's universe to be part of the buffer's type.

## Alternatives considered

**An ambient allocator.** A global the runtime provides, so `alloc` takes no
parameter. Rejected: it makes every allocation site's source of memory
invisible, which is the property that makes arenas, pools and testing
allocators impossible to introduce later without changing every call. Zig's
choice, taken for Zig's reasons, and they are Linea's reasons too.

**Affine buffers with a `Drop`.** The ergonomic path, and what 0034 rejected.
Not reopened. `defer` is the answer to the ergonomics, and it is explicit.

**A trap on out-of-memory.** Simpler: `alloc` answers with a buffer or does not
return. Rejected under 0017 — a trap is not catchable, so a program could not
choose to degrade, and the decision would be the language's rather than the
program's. It also makes `alloc` the one call whose failure has no written
path, which is exactly the shape `?` exists to make cheap.

**Reference counting or a GC.** Both reintroduce a value that names storage it
does not own, and both make disposal implicit. Against 0025 and 0034
respectively.

**A `Vec` first, with the buffer hidden inside it.** Reaching the useful thing
sooner. Rejected because it bundles four decisions — the allocator interface,
the growth policy, `Index`, and the element's universe — into one milestone, and
a failure in any of them would be diagnosed as a failure of the whole. The
buffer is the smallest thing that demonstrates the memory claim, and the claim
is what R2 is for.

## Deliberately open

**Realloc.** Growing in place where the allocator can is what makes `Vec`'s
amortised growth cheap. R2 does not need it; R4 does, and whether it is a
separate operation or a hint on allocate is open.

**Alignment beyond 8.** Nothing in the language has an alignment above 8 today,
so the buffer's alignment is a constant. A type that needs more would make
alignment a parameter of allocation, and the question that settles it is whether
one ever arrives.

**Typed storage.** A buffer that holds `T` rather than bytes needs the element's
universe in its type, so that storing a Linear element is either tracked or
refused. The question that settles it: whether `Vec[Key]` is expressible at all,
or whether a Linear element is a thing only a fixed-size array may hold.

**Arenas.** Explicitly *not* part of R1–R5. The API is easy; the safety is not.
