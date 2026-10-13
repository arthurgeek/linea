# 76. A raw access is a declaration lowering replaces

Status: Accepted — 2026-08-07

## Context

A buffer's `store` and `load` trap where the offset is past the length or off
its width's alignment, and only a `check` instruction the compiler emits can
trap. So the checks are lowering's either way — the open question R2's design
recorded was what performs the access they precede: a C function the runtime
provides, or an instruction the compiler emits.

Something underneath the public members must be primitive, because no Linea
body can express a raw memory access, and the library has no way to trap — its
one failure channel, `report`, renders a value that leaves through the entry
point.

## Decision

**`linea_raw_store` and `linea_raw_load` are `extern` declarations no runtime
provides. Lowering recognises a call to either and emits, in its place, the
two checks and the access itself — `store_indirect` or `load_indirect`,
instructions MIR already had.**

The recognition is by module and name, the mechanism
[0072](0072-a-declaration-only-generated-code-calls-is-named-by-its-module.md)
established, and the pair is answered once per program rather than asked per
call site. The declaration's parameters are validated there too — the operand
order is a contract between the library's spelling and what the emission
reads positionally, and a declaration whose shape drifted is not swapped, so
the call survives to the linker and fails naming the symbol.

**No C body exists for either symbol, deliberately.** A call that survives to
the linker is a lowering that missed the swap — or refused it — and it fails
the build there, an undefined symbol naming exactly what was missed, rather
than running a second implementation of the access and letting the two drift.
The `linea_` prefix is part of the tripwire: an undefined symbol only stays
undefined in a namespace nothing else writes, and a bare name is one any
platform library may quietly define.

The `extern` spelling is what makes the declarations checkable without a body:
`[T-Extern]` already says an extern's parameters are integers with a known
representation, which is precisely the shape the emitted sequence consumes —
an address, a length, an offset, and for a store a value, all `UInt64`.

## Consequences

- An access costs no call. The checks and the memory instruction are emitted
  inline where the extern was called, inside the library member's own body.
- A trap's span points into `std/mem/buffer.lin`, where the raw call sits,
  rather than at the program's `b.store(i, v)` site. That is the cost of
  recognising a declaration instead of teaching three passes a member name,
  and it is accepted: the message still names the failure, and the exit status
  is what the corpus asserts. A consequence of the consequence: trap goldens
  record that library line, so an edit above it in `buffer.lin` churns them —
  churn `-Dupdate` regenerates, and behavioural-looking diffs from
  documentation edits are the price.
- The swap is invisible to the checker and the ownership pass. Both see an
  ordinary call to an ordinary extern; only lowering knows the call does not
  survive, which keeps the knowledge in one pass.

## Alternatives considered

**A true extern, with the access in C.** `linea_byte_at`'s shape: lowering
would emit the checks and keep the call. Rejected because every store and load
would pay a C call, and because the access would then exist twice — once in C
and once in whatever a later optimisation inlines — which is the drift this
compiler's own history warns about.

**Compiler-known members.** No declaration at all: the resolver, the checker
and lowering all know `Buffer.store` the way they know a primitive's
conversion. Buys the caller's span for the trap, at the cost of three passes
learning a library type's member and the module/name mechanism of 0072 being
bypassed. Rejected: one lookup in one pass does the same work.

**Checks written in Linea, answering a value.** `Str.byte`'s shape: the bound
tested in the library, the answer an `Option`. Rejected for a buffer because
the design requires a trap — an out-of-range store is a mistake, not an
answer, and [0017](0017-failure-is-a-trap-or-a-value.md) puts a mistake's
outcome beyond the program's choosing.
