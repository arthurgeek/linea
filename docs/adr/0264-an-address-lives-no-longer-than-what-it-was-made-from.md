# 264. An address lives no longer than what it was made from

Status: Accepted — 2026-11-08. Supersedes the clause of
[0255](0255-an-erased-value-is-reached-through-an-address-that-names-its-type.md)
§1 that keeps an `Address` out of the dependency table; extends 0255 §2.

## Context

`std.mem` makes an `Address[T]` in two ways: `address_in(buffer, offset)`, the
address of slots in a buffer, and `slice_address(view)`, the address of a
slice's first element. A certified `Storage` keeps one in its `at` field. 0255
kept the address out of the dependency table: "an address is a number, and the
storage that owns its bytes carries the dependencies of what is kept there".
The certificate for both primitives required them to declare no contract, and
none could have had an effect, because a contract whose result is a scalar
that carries nothing is dropped.

So the checker tied an address to nothing. Inside `mem`, each of these was
accepted and reached freed storage under the checking runtime:

```linea
fn stale_slice_address() -> Int64 {
    var values: Vec[UInt8] = Vec.new()
    &values.push(65).unwrap()
    let at = slice_address(values.as_slice())
    values.release()
    linea_write_some(1, address.raw(at), 1)
}

fn stale_buffer_address() -> Int64 {
    let bytes = system().acquire(8).unwrap()
    let at: Address[UInt8] = address_in(bytes, 0)
    bytes.release()
    linea_write_some(1, address.raw(at), 1)
}

fn stale_vector_address() -> Int64 {
    var values: Vec[UInt8] = Vec.new()
    &values.push(65).unwrap()
    let at = copy(values.storage.at)
    values.release()
    linea_write_some(1, address.raw(at), 1)
}
```

The primitives and `Storage`'s fields are private to `mem`, so no program
outside the library could write any of them. The library is still code the
checker accepts, and a mistake there broke the memory promise exactly as a
program's would.

## Decision

### 1. An address carries dependencies

`Address[T]` seeds dependencies, as a `Slice`, a `Buffer` and `std.ffi`'s
views of C addresses do. A function that answers an address is then held to a
contract like any other function whose result may carry a dependency: one
parameter it could come from is inferred, several need a clause, and a body
that returns one from a source its contract does not name is [O-Escapes]. A
declaration added later that makes or passes on an address is covered without
anyone remembering it.

### 2. The primitives state their contracts, and the certificate requires them

- `address_in(buffer, offset) -> Address[T] where borrows(buffer)`: the
  address observes the buffer, so the buffer cannot be released, moved or
  changed while the address is used.
- `slice_address(view) -> Address[T] where carries(view)`: the address
  carries what the slice carries, which is its observation of the slice's
  owner.
- `owned_address_in(buffer, offset) -> Address[T] where carries(buffer)`, a
  new primitive lowering replaces as it does `address_in`: the address of a
  buffer's bytes for a value that takes the buffer and keeps the address
  beside it. It carries what the buffer carries (an arena's lend, for a
  buffer an arena handed out) and does not observe the buffer, so it outlives
  the buffer's place.

The storage-primitive certificate refuses any of the three whose contract,
written or inferred, is another one, `carries()` included ([T-Extern]).

### 3. A raw type's fields are named only by its own members

`Storage` keeps its address beside the buffer it was made from. If the
dependency table counted that field, every `Vec` would carry a dependency and
none would be `Owned`, so the table skips it, as it already skips the buffer:
the storage's allocator field and element type state what it carries. The
skip is sound only while a storage's address and length always describe bytes
it owns, or none. The same holds for every type whose fields are an address,
an extent of bytes, or what those bytes hold, which the slot primitives, the
runtime or lowering trust: a `Buffer`, a `Slice`, a `View`, a `Closure`, a
`Vec` (whose `len` is how many of its slots are live) and a `Kept` task body.

The compiler's table of the library's raw declarations (`RawAccesses`) lists
these raw types, and [T-RawAddress] holds each one's fields, all of them, to
one rule at the node that names the field: a field of a raw type is named --
read, written, lent, used as a method's receiver, passed, bound by a pattern
or given in a literal -- only in a member of an implementation for that type,
and in the declarations its row lists. A field added later, or a raw type
added to the table, is covered without anyone listing the ways a field can be
reached. A rule that listed write forms (assignment, `&`, literals) left every
form it did not list open: a method taking `inout self` on a field's type wrote
through the field without assigning it.

The rows list the declarations that work below a type's own operations:

- a `Storage`'s fields are named where a task body is kept (`keep_body`,
  `take_kept_body`, `release_kept_bytes`) and where `Closure.erase` keeps its
  storage's address as the closure's `at`; a literal with no buffer,
  `address.nowhere()` and a length of zero names no bytes and is written
  anywhere;
- a `Buffer`'s fields are named by the members of an implementation of
  `mem.Allocator` for a `Buffer` of that allocator itself (`Buffer[Self]`,
  arguments included),
  which they hand out and take back; by the test allocators that hand out a
  buffer of their backing allocator on its behalf (`RefusingAllocator`,
  `SharedRefusingAllocator` and `VecTestAllocator`'s `acquire` and `dispose`)
  and the arena handle's `dispose`, each named in the table; by
  `Storage.from_buffer`, which takes it into slot storage; and by the
  declarations that hand a buffer's bytes out as numbers: an arena's
  bookkeeping (`Arena.rewind`, `arena_reserve`) and the logs the library's
  tests write through (`AllocationLog.refuse_attempt`, `ReleaseLog.words`,
  `vec_test_log_at`, `vec_test_log_len`);
- a `Slice`'s by `foreign_address`, which `std.ffi` lends to C;
- a `View`'s by `Vec.split_inout`, which lends a vector's two sides;
- a `Vec`'s by `vector_from_buffer` and `vector_into_buffer`;
- a `Kept` body's by `keep_body` and `task.Slot.start`.

A test written inside an implementation for the type is judged as its
members are. Whether a field node is a method's name is the checker's own
record of what the call resolved to, not the call's shape: `(held.settle)(..)`
calls through the field `Closure.settle`, so it names the field. Outside the library these types are opaque, which [M-Opaque]
already refuses, so the rule judges library code.

`Storage.address` (`where borrows(self)`) is how everything else reaches a
storage's address, and `Storage.address_at`, `capacity`, `allocator` and
`into_buffer` are the operations `Vec` and the task payloads use in place of
the fields.

Names are confined the same way, each to declarations the table names, however
the name is written (`mem.owned_address_in` as `owned_address_in`):
`owned_address_in` to `Storage.from_buffer` and `keep_body`; `closure_entry`,
`closure_settle` and `closure_size` to `Closure.erase`; `keep_body` and
`release_kept_bytes` to `task.Slot.start`; `take_kept_body` to `task.run_body`;
and `task.run_body`, the entry of the thread `Slot.start` starts, to
`Slot.start`.

The slot primitives (`slot_take`, `slot_put`, `slot_place`, `slot_span`) and
`Storage.dispose` and `Storage.into_buffer`, which give a storage's slots up
without settling them, are confined the same way: to the members of
`Storage`, `Vec` and `Drain` and to the declarations the table names, each of
which takes or hands on every value it puts before it gives the storage up:
`keep_body`, `take_kept_body` and `release_kept_bytes`, which move a task
body in, out, and free its bytes once taken; `Closure.erase`, whose closure
then owns what it put; `send_payload`, whose runtime call moves the value to
the peer, and `receive_payload` and `receive_payload_until`, which take what
the peer sent or dispose of nothing; `call_owner` and `next_owner_request`,
likewise; `release_from`, which releases a vector's elements; and
`vector_into_buffer`, whose bytes need no settling. A `Vec` releases its live
elements before its storage, and a `Drain` takes or releases the ones it has
not handed out. A double `slot_take`, or a storage disposed with a live slot,
is then written only where the table says it is not. `release_from`, which
releases the slots between two counts it trusts, is named only by `Vec`'s and
`Drain`'s members, which know how many slots are live. A member of these types
that takes an index checks it against the live length: `Vec.swap_elements`
traps on an index at or past it, as indexing does.

`Allocator.dispose` for the system allocator frees through an address it makes
from the buffer with `address_in` and takes the buffer apart after the call.

### 4. Bytes are read and written only at an address

The raw loads and stores (`linea_raw_load`, `linea_raw_store` and their byte
forms) read and write at a number lowering checks only against the extent
passed beside it, and `std.ffi`'s views of C memory (`Bytes`, `CText`,
`CTextList`) are numbers too. A number carries nothing, so a number kept past
what owned its bytes -- a slice's address turned into a `UInt64`, or a view
rebuilt from one -- read freed storage, and nothing refused it.

- The runtime table marks the raw loads' and stores' address parameter as the
  address of bytes, so [T-RawAddress] accepts only `address.raw(at)` there:
  every raw access is at an `Address`, which carries what its source carries.
  The marks are the runtime table's, so a primitive added later that reads or
  writes bytes is held to the same rule by its row.
- `foreign_address(view)` answers an `Address[UInt8]` that carries what the
  view carries, and `foreign_byte` and `foreign_word` read at an `Address`.
- A number becomes an address only through `number_address`, a primitive
  lowering replaces, named only by `foreign_at`, through which `std.ffi` reads
  memory C handed over, and `record_release`. The library's other test logs
  hold a borrow of their buffer, so they have no number to forge. `foreign_at`
  is named only by the members of `CText` and `CTextList`, whose `at` declares
  `where carries(self)`, and by its own test.
- An address proves the bytes exist, not that an offset is inside them, so
  every runtime symbol or lowered primitive whose table row marks an address
  is named only by `Buffer`'s, `Storage`'s and `Chan`'s members and the
  declarations the table lists, each passing an extent it read from what owns
  the bytes. A symbol added to the runtime table is held to this by its row.
  `foreign_byte` and `foreign_word` read C's memory, which has no extent to
  check, so only `CText`'s and `CTextList`'s members, `copied_in` and their
  own tests name them. `CTextList.get` traps on a null list.
- The runtime checks only a payload's size, so an endpoint and an owning
  task's queue are trusted to carry the type asked of them. `Chan` and
  `task.Owner` are raw types; `send_payload`, `receive_payload` and
  `receive_payload_until` are named only by `Chan`'s members; `Chan.opened`
  also by `task.Slot.start` and `task.run_body`; `call_owner` only by
  `task.Client.call`, and `next_owner_request` only by `task.run_owner`.
- A C view is built from a number only in its own members, in the
  declarations the table lists (`bytes_of`, `CString.text`, `CTextList.get`),
  each from `address.raw` of an address its contract names or from a number C
  handed over, and anywhere from the literal `0`, a null view. Taking a view
  apart into its number stays free: a number is only a number until something
  reads at it.

### 5. An address does not cross beside `errno`

[T-RawAddress] refuses an `extern` whose answer reaches an address, since C
could hand back a number where an address belongs. An `extern` answering
`ffi.Errno[R]` returns `R` from C, so the rule reads that `R`, as the rest of
the foreign-signature check does; `ffi.Errno[address.Address[UInt8]]` was
accepted before.

## Consequences

- An address kept past its slice's owner, past the buffer it was made from
  with `address_in`, past the storage it was read from, or past the arena a
  buffer came from, is [O-Borrow].
- What stays trusted to the library is narrower than 0255 left it, and each
  part is a declaration the compiler's table names: a raw type's own
  members, the declarations each raw type's row lists, and the confined names'
  callers.
- `keep_body` states `where carries(storage, body)`: the addresses it answers
  own both.
- A unit test checks the library with functions added to `mem`, `task` and
  `ffi`,
  each held to the one rule that refuses it by the function its diagnostics
  fall in: an address kept past its source is [O-Borrow]; a raw type's field
  named outside its places, in a literal, an assignment, a pattern or through a
  method's `inout` receiver, and a confined name named outside its places, are
  [T-RawAddress]; and those that use their address first, or build a storage
  of nothing, are accepted. The declarations are private to the library, so
  the corpus cannot hold the case.

## The trusted base

The compiler proves that an address carries what its source carries, that a
number is read or written only as an address, and that every declaration below
is the only place its name, field or literal appears. It does not prove what
each of these promises. `RawAccesses` in `src/sema/intrinsics.zig` and
`runtime_symbols.zig` are the authoritative list; a declaration moves in or out
of this base only by changing them.

| Declarations | Promise |
| --- | --- |
| Members of `Storage`, `Buffer`, `Slice`, `View`, `Closure`, `Vec`, `Kept`, `Chan`, `Owner`, `Arena` (`rawTypes`) | Their fields describe bytes they own, a live extent, or an endpoint or queue of the type asked. |
| `Storage.from_buffer`; `owned_address_in`'s callers `Storage.from_buffer`, `keep_body`, `Arena.open` | The value taking the buffer owns the bytes the address names. |
| `keep_body`, `take_kept_body`, `release_kept_bytes`, `task.Slot.start`, `task.run_body` | A kept body's addresses go only to the thread that was started with them. |
| `Closure.erase`, with `closure_entry`, `closure_settle`, `closure_size` | A closure's address holds the callable erased with that entry and release. |
| Members of `mem.Allocator` implementations; `backing_buffer_builders` | A `Buffer` is built only over bytes the allocator handed out. |
| `slot_users`, and members of `Storage`, `Vec`, `Drain` | A slot is taken once, put when empty, and every value put is taken or handed on before the storage is given up. |
| `release_from`, through `Vec` and `Drain` members | The two counts bound live slots. |
| `byte_operations` | The extent passed to a marked runtime symbol is read from what owns the bytes. |
| `send_payload`, `receive_payload`, `receive_payload_until`, `Chan.opened`; `call_owner`, `next_owner_request` | An endpoint or queue carries the type asked of it. |
| `foreign_at`, `foreign_byte`, `foreign_word`, `copied_in`, members of `CText`, `CTextList`; `foreign_view_builders` | A number is one C handed over, within what C promised, or is built from an address its contract names. |
| Members of `Arena`, `Handle.dispose`, `arena_table_of`, `arena_zero`, `arena_give_back`, `arena_reserve`, `arena_holds` | `chunks` addresses the table inside the first chunk, whose `slots` are the chunks `first` owns; a chunk leaves the table once, when the arena gives it back. |
| `buffer_numbers` (the arena's, `AllocationLog.refuse_attempt`, `ReleaseLog.words`) | A number read from a buffer is read at while that buffer lives. |
| `record_release`, from `ReleaseTag.release` and the HTTP test's `ProbeTag.release`; `ProbeTag` built only by `probe_tag` | The number is a live log's. An HTTP extractor sees only its request, so the test's log address crosses as header text; this is test-only code. |

## Alternatives considered

- **`carries` for `address_in` as well.** A buffer from the system allocator
  carries nothing, so the address would be tied to nothing and the second
  function above would stay accepted.
- **`borrows` for every address of a buffer.** `Storage.from_buffer` would
  hold an observation of the buffer it owns, and `keep_body` would move the
  buffer while its addresses observe it; neither can be written. Those two are
  where ownership passes to the address, so they get the primitive that says
  so, and only they may call it.
- **Count a storage's address in the dependency table.** Every `Vec` would
  carry a dependency, so none would be `Owned`, and no vector could be sent to
  another task or kept by an owning task. Confining where the field is built
  and read keeps the skip sound instead.
- **Confine the forms that write a field** (assignment, a place lent `&`, a
  literal). Every form not listed stays open: a method taking `inout self` on
  the field's type writes through it, and so would whatever form comes next.
  Confining the node that names the field covers every form at once.
- **Confine where an address may be bound**, accepting `slice_address` and
  `address_in` only as the operand of `address.raw` at a runtime parameter.
  A position rule repeats what dependencies already decide, needs exemptions
  for each holder, and a function that answers an address would still escape
  it.
