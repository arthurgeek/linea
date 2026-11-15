# Runtime migration evidence

Fibers still run pinned. Artifact identity is available; migration-capable
lowering, runtime registration, per-entry provenance and cross-thread dispatch
are not implemented by this change. The driver keeps runtime availability
false and the backend refuses an enabled request before writing IR.

A normal build installs `<archive>.migration.json` beside each runtime archive.
The sidecar identifies the exact archive bytes, source/configuration fingerprint,
canonical runtime registry, ABI, target, storage allocator and sanitizer variant.
The generator hashes the runtime source inventory, generated formatter C and
build configuration. Rebuilding an archive can update identity; it cannot issue
an approval or validation. Checked and regular archives have separate identities.
Thin archives are not snapshotted because their member paths are relative.

`migration-audit.json` and `migration-validation.json` are separate reviewed
compiler inputs. They currently contain no approvals or validation. Their records
are embedded in the compiler, not read from a neighboring archive. Behavioral
approval binds implementation and registry identities to an entry-manifest and
suspension-path scope. Target validation binds accepted evidence to that approval
and the exact archive/platform/variant, within that scope. Normal selection
rejects candidate-only records. Tests use synthetic positive tuples; they do not
approve a real runtime or create a candidate activation mechanism.

`src/support/runtime_symbols.zig` owns native contract classifications. Every
current entry defaults to Unknown. The classification field does not yet add
foreign guards or establish affinity. Neutrality of a native symbol will not by
itself authorize every suspension path or callback target it can reach.

Unavailable runtime support returns pinned without optional allocation or I/O.
For supported contexts, selection checks metadata identity, authorities and the
requested entry/path scope before reading the archive. The enabled result carries
the checked requested scope, owned by the compilation for the entire emission;
it is not blanket permission for other entries or suspension paths.

Selection occurs afresh before compilation emits IR. Missing, malformed, stale,
unsupported or unapproved optional evidence uses ordinary pinned emission and
the original link path, with no optional helper references. Valid native
signature, ABI and sanitizer requirements still apply. Object-only compilation
needs no archive and remains unproven; linking an object against an identified
runtime does not certify that object's entry or native-call paths.

For an approved identity, the selection helper retains a unique archive snapshot
and rechecks its digest before linking. It does not reopen the original archive
for the link. The production driver cannot select that path until runtime
availability and approved authorities exist. Synthetic tests exercise snapshot
replacement and metadata invalidation without enabling migration. Linking assumes
that the private build directory and retained snapshot are not concurrently
modified during the build. The pathname plus hash check is not an OS-enforced
immutable-file capability and does not eliminate a hostile mutation between the
check and the linker's open.

Expected missing/malformed evidence and unsupported representations remain
ordinary disabled decisions. Operational failures retain their preparation stage
and original error internally, including archive-read and snapshot failures.
They currently select pinned fallback without introducing mandatory warnings.

No emitted-call-site manifest, scheduler callback audit or cross-thread platform
result is supplied here. Those remain prerequisites for any actual migration.
