# 315. Generated index loops carry checked bounds witnesses

Status: Accepted — 2026-11-27.

## Context

Numerical array and matrix operations lower to bounded loops. Their source
semantics use UInt64 lengths, and the resulting MIR uses UInt64 counters and
byte offsets. Requiring shader Int64 for these private loops excludes useful
devices. Truncating counters or addresses would give ordinary functions a
second meaning. Recovering producer knowledge through an unchecked pattern
match would also put compiler mistakes across a trusted device boundary.

## Decision

Retain a witness for each compiler-generated counted index loop in the existing
MIR. It names the zero initialization, header load and constant limit, guarded
body, unit step and exit by typed instruction/block identities. Blocks name
their innermost generated loop; depth-first intervals answer containment.
Functions without these loops retain no scope table.

Independently validate the witnesses before emission. The header must compare
the recorded counter against the recorded limit. The counter must occupy a
private local outside the parameter slots. Initialization and step must enter
that header. The verifier rejects every other counter access and unguarded
entry into the body. All CFG edges must respect the recorded scopes. The counter can equal its limit
in the header; a body use has a strict upper bound, and an empty body has no
reachable use. Instruction-position indexing is shared with MIR verification.

The GPU backend derives function-local integer intervals and allocation-origin
address intervals from verified MIR. Device integer arithmetic is eligible only
when every result is exactly representable in its narrower width. Address
eligibility additionally proves alignment and containment in the originating
allocation. A known branch can be omitted only when these facts prove its
condition. Unsupported values and operations remain explicit admission refusals.
Source UInt64 semantics and CPU lowering are unchanged.

## Consequences

The witness adds proof metadata to MIR, not a second device semantic IR. Its
validation uses tables sized by the function's instructions, locals, blocks and
loops and visits each instruction, block, edge and loop once. Device range facts
are conservative; a valid CPU function can still be outside the device profile.
No host pointer or arbitrary source integer becomes a device address.

## Alternatives considered

- **Require Int64 for every generated loop:** adds an unnecessary hardware
  requirement for fixed-size allocations already bounded by their layouts.
- **Cast indexes or byte offsets to UInt32:** loses source values and permits
  incorrect accesses.
- **Trust generated loop spelling without verification:** fails to catch a bad
  guard, a second counter write, an alias or an edge bypassing the guard.
- **Build a separate device semantic IR:** duplicates the interpretation of
  source functions and disconnects device admission from verified MIR.
