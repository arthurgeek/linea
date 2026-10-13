# 137. Arrays expose checked borrowed slices

Status: Accepted — 2026-09-17

Extends [0061](0061-an-array-is-a-value-of-a-fixed-size-type.md) and
[0123](0123-observations-carry-owner-dependencies-through-callable-contracts.md).
Extended by [0166](0166-an-array-compares-through-its-slice-view.md): arrays
compare, hash and print through this view.
Extended by [0172](0172-an-array-reports-its-length.md): an array reports its
length without a view.

## Context

Arrays support consuming and lending loops, while iterator algorithms consume
values implementing `Iterator`. Vec already exposes a certified `Slice[T]`, but
arrays cannot construct one in library code: their implementation heads and
lengths cannot be expressed generically, and Slice's backing address is sealed.
Duplicating iterator algorithms for arrays would create a second composition
path. Copying arrays into allocated vectors would add ownership and allocation
costs to observation.

## Decision

An array place `values: [T; N]` provides the explicit call
`values.as_slice() -> mem.Slice[T]`. It observes all N initialized elements in
index order without copying or consuming them and without allocating. The call
accepts no arguments and no mutable invocation marker. Observed array receivers
use their referent's storage. Temporary array values cannot supply escaping
storage; ordinary borrowing contracts govern arrays passed to functions.

Typing recognizes this operation only for arrays and the certified library
Slice declaration. It records a `NormalizedCall` with target `.array_view`, the
exact array type, receiver observation adjustments, and a read parameter with
`stable_address` and `borrows(source)`. Ownership consumes the usual normalized
call contracts; it has no array-view name lookup or separate lifetime analysis.
The editor uses the same receiver-eligibility query for completion.

Lowering reads the recorded source type and address and constructs the existing
Slice descriptor with the array's static element count. MIR `address_bits`
converts a managed storage address to the descriptor's UInt64 address field.
Verification checks that operand role, result role and result type, and checks
the source storage extent. MLIR emission renders `llvm.ptrtoint`. This operation
does not expose an arbitrary-address constructor to Linea programs.

Contiguous Slice addressing uses the element layout's byte size, including
zero. A Slice of zero-sized elements preserves its element count and index
checks, with each element at the same stable address. Allocated typed slots
continue to reserve at least one byte per element; allocation extent and the
width of an element access are separate facts.

The library implements `Sequence` for Slice and returns `SliceIter[T]`, whose
`Iterator.Item` is `borrow T`. Vec's `as_slice()` and array views enter that same
iterator. It owns a descriptor and position, yields observations in order, and
remains exhausted after returning None. Discarding or releasing it leaves the
source elements and storage with their owner, regardless of whether T is
Copyable or Release. A yielded observation carries the backing dependencies,
so it can remain live after the iterator descriptor is consumed.

## Consequences

Borrowing pipelines over arrays, Vecs and Slice subspans share one allocation-free
iterator with O(n) traversal time and O(1) additional storage. Source mutation,
movement, disposal and escape remain subject to the existing observation rules.
Scalar reads through a Slice index still require a live backing owner at the
read; producing an independent scalar does not exempt that access from checking
its source.

Arrays retain their existing consuming-loop semantics. They do not acquire an
owning iterator or a `Sequence` implementation. Const generic authoring, stored
mutable views and cleanup policies for owning iterators remain separate work.

## Alternatives considered

A library-only array adapter cannot obtain an arbitrary array length or form
a checked Slice address under the existing type language. A new const generic
system would exceed the scope needed to connect borrowing pipelines.

A generic intrinsic accepting arbitrary Index implementations would claim that
noncontiguous containers have contiguous storage. A public pointer-and-length
constructor would bypass Slice certification. A new contiguous-container trait
would still require compiler support for arrays and would add another public
contract without removing this construction step.

Implicit array-to-Slice conversion would obscure when a source begins to be
observed. Copying into a temporary Vec would introduce allocation and reject
noncopyable elements. The explicit call preserves the source and connects it to
the existing representation.
