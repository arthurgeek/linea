# 322. Device allocation domains retain arena observations

Status: Accepted — 2026-11-27. Extends [0309](0309-tensors-separate-storage-from-numerical-operations.md)
and [0310](0310-device-admission-is-sealed-from-public-callables.md).

## Context

An allocator chooses where tensor storage resides. Host addresses cannot name
Vulkan memory, and system device allocations and arena reservations have different
settlement obligations. A native submission may continue using a reservation
after its source-level operation has returned an error. Reset must distinguish
CPU ownership, completion and physical reclamation.

## Decision

`tensor.AllocationDomain` associates one `Storage[Float32]` implementation with a
constructor argument. Existing host allocators return `Cpu[A]`; `gpu.Device`
returns `gpu.Storage`; `gpu.ArenaHandle` returns `gpu.ArenaStorage`. Both shared
constructors, `matrix_in` and `from_slice_in`, validate shape and byte arithmetic
before allocation and adopt storage through `Tensor.from_storage`. Device
convenience constructors remain available. Transfers are explicit. Device
identities never enter the host `Allocator` contract.

An arena is an independent linear resource retaining its device. Its copyable
handle contains a real borrow of the unshareable arena. Each affine arena view
retains that handle, including an empty view, and sibling outputs retain the
allocation domain of their left input. A live observation forbids an exclusive
reset, move or release. The ordinary task rules apply independently to owners
and observations. System buffers retain their device and remain linear.

`Resident[B]` implements tensor storage once for both native buffer families.
The internal buffer contract has no blanket implementation. Its native identity
is an opaque token requiring a mem-owned witness; external code can neither
implement the contract nor inject a native integer through it. Generic jobs own
one submission and one output, preserve the output's observations on success,
and settle it exactly once on error or release. Downloads initialize an exactly
sized host allocation before adopting it as a vector; uploads preserve typed
source extents, with no address selected for zero bytes.

The arena's byte limit charges actual committed `VkDeviceMemory` allocation
sizes, including driver rounding and alignment. Opening commits no blocks.
Blocks grow lazily, stay within the cap, and remain at their high-water size
across resets. Host metadata and independent system buffers are outside the
cap. Empty views reserve four descriptor bytes and therefore require capacity.
A successful reservation followed by failed upload may occupy its range until
reset. Capacity refusal is `GpuError.Allocation`.

Reset takes `inout` access, prevents new native work and parks until all native
pins have detached. Completion destroys Vulkan submission resources before
pin detachment and before signaling reuse. A completed public job can outlive
arena metadata: it retains only independently owned state. Reset then discards
view metadata and rewinds retained blocks. Definite device loss drains pins and
returns a runtime error; indeterminate completion remains fatal. Arena release
drains and frees every block and metadata record.

## Alternatives considered

**Treat device handles as host pointers.** This violates host allocator and
address provenance contracts and would make ordinary host reads unsafe.

**Make every device tensor linear.** An arena view owns no independent native
resource. Requiring its release would add ceremony without reclaiming storage.
The owned buffer field already determines the correct settlement obligation.

**Keep completed job pins until public release.** An idle completed job could
prevent reset forever. Completion must finish Vulkan teardown and detach every
arena pointer before publishing that storage may be reused.

**Return Busy from reset or retire generations.** Neither implements the selected
exclusive, fiber-parking reset contract.

**Expose an integer hook protected only by an opaque argument.** A user-defined
hook could return a forged integer when trusted generic code supplies the
argument. The closed implementation family and opaque identity token protect
both admission and representation.
