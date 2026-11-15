# Fiber migration safety

Fibers currently remain pinned to their original carrier. The scheduler metadata
mutex protects dispatch, notification, queue membership and retirement while
that behavior remains unchanged.

Migration eligibility will be determined by compiler-generated native-boundary
guards and the runtime state of the saved continuation. Unknown foreign behavior
must establish persistent affinity before native execution. Native contracts live
in `src/support/runtime_symbols.zig`; all currently default to Unknown.

No audit or validation JSON is embedded in the compiler, installed with runtime
archives, or read by applications. Review reports and platform test results are
development evidence, not executable authorization records.

Actual cross-thread transfer remains disabled until continuation safety, source
resource retirement, lifetime protection and platform context restoration have
been implemented and verified. Object-only compilation requires no runtime
archive or external approval record.
