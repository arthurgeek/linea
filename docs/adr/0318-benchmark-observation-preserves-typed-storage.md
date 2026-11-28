# 0318. Benchmark observation preserves typed storage

**Status:** Accepted

## Context

A clock read measures elapsed time, but a pure computation whose result is
unused can disappear before code generation. A checksum can likewise become
a constant when the compiler knows its inputs. Benchmarks need to supply an
unknown input or observe an actual output without converting floats, losing
aggregate fields, or abandoning an owned resource.

## Decision

`std.bench.black_box` takes a value by move and returns it carrying the same
dependencies. Its body owns a mutable local and passes it to one private
compiler-certified generic inout primitive. MIR represents the opaque use
with one managed address, Unit type and no instruction result. The verifier
checks the address role and storage access. Host lowering emits empty
side-effecting assembly with the address as an input and a memory clobber. An instantiated value
of zero size has no bytes to materialize and needs no assembly.

## Consequences

The operation preserves all bits and returns ownership to the caller. The
optimizer must materialize the value and treat its storage as potentially
changed. The barrier has a cost, including spilling or copying some values.
It can observe a descriptor without forcing work that descriptor represents.
Device kernels have no such operation. Callers decide where to obstruct
optimization and which results need waiting for, reading or releasing.

## Alternatives considered

A volatile scalar checksum would require a representation and a reduction for
every value and would lose distinctions such as permuted components. An
external function with a generic value ABI would need different calling
conventions for different instantiations. A runtime helper taking a raw
address would add a call and an external symbol for an operation the host
backend can express directly.
