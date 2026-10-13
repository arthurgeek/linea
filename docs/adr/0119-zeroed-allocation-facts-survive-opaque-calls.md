# 119. Zeroed allocation facts survive opaque calls

Status: Accepted — 2026-09-08.

## Context

The system allocator returns zeroed storage, but its ordinary C call hides that
fact from LLVM. A later read of an untouched word can survive even after
inlining all Linea wrappers. Marking the call as an eliminable allocator would
also permit removing observable allocation failure; replacing calloc would
change large-allocation behavior. Neither is the required optimization.

A checked raw access also loses its pointer relationship when emission converts
the sum of two integers into a pointer. Genuine zero facts and a structured
base-plus-offset pointer are both needed by the measured allocation loop.

## Decision

Discovery retains the exact trusted `std.mem.linea_alloc` declaration identity,
using the complete checked extern signature. The instance table passes that
identity to lowering, which records the corresponding FunctionId in MIR only
when the declaration was discovered. Verification checks that the marker names
an external function with two read UInt64 parameters and a UInt64 result.

The backend keeps the ordinary opaque allocation call, its nullable result, and
all runtime behavior. Immediately after the call it can expose zero facts for
at most eight complete eight-byte words. The path requires a nonzero answer and
an LLVM-constant proof that the requested extent is at most 512 bytes. Each word
also requires an LLVM-constant proof that its complete extent was requested.
These predicates may settle after ordinary LLVM inlining; unknown predicates
remove the corresponding proof paths before machine code. No allocation-kind,
elision, nonnull, or noalias permission is added to the call.

For verified RawAccess instructions, emission constructs a non-inbounds byte
GEP from the recorded base and offset. RawAccess verification already establishes
the address operation and its overflow, bounds, and alignment witnesses. Those
checks remain unchanged. Ordinary arithmetic and managed addresses keep their
existing emission.

## Consequences

The facts describe the successful calloc contract, including zero and partial
extents, without touching refusal or alignment behavior. The proof budget is
constant per canonical call, independent of the requested allocation size.
It adds backend text and optimization work; this is not a free compilation-time
transformation. A measured eight-word control retained identical allocation-loop
machine code to a larger control, with materially less compilation work.

MIR carries one additional optional FunctionId; the backend does not rediscover
library identity from a user-visible symbol spelling. The exact extern matcher
is shared with raw access discovery. The C runtime and ABI remain unchanged.

## Alternatives considered

**Allocator-elision attributes.** Rejected because failure and allocation remain
observable. Zeroed contents justify a value fact, not permission to remove the
call.

**Replace calloc with allocation plus explicit clearing.** Rejected because it
can forfeit lazy zero-page behavior for large allocations and adds runtime work
when no downstream read benefits.

**Thirty-two proof words.** Native controls produced the intended machine code,
but increased backend compilation cost enough to reject that budget. Eight
words retain a general bounded prefix while reducing proof machinery.

**A new pointer or heap-provenance pass.** Unnecessary for this bounded fact. The
canonical producer and verified raw access already carry the required answers;
existing lowering and emission can preserve them without another analysis.
