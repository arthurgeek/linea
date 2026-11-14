# Foreign work through existing tasks and owners

These cases exercise ADR 0265's library pattern with mock native resources.
They introduce no compiler/runtime feature or public standard-library API.

- `cleanup_retry` creates and destroys an unshareable native resource on its
  explicit system-thread owner. A failed destruction returns linear `Closing`
  authority retaining the actual owner; retry settles it before closing empty
  state. Neither active nor closing authority has ordinary `Release`.
- `initialization_errors` preserves partial state and both errors when
  initialization and cleanup fail, then retries on the original thread. It
  also checks clean initialization failure and recovery from a native
  operation error.
- `hundred_clients` shares opaque, restricted clients across 100 fibers on one
  carrier. A native condition wait blocks the owner until a different fiber
  releases it. The private resource never leaves its owner.
- `lifecycle_stress` repeats creation, native blocking, client calls, failed
  destruction and retry over 24 cycles. Twelve clients per cycle have rotating
  completion order; all 288 results and native resource counts are checked.
  This covers controlled schedules, not every possible interleaving.
- `bounded_admission` prepares at most three system tasks per batch. A refused
  preparation returns the original body/error after joining admitted work;
  the caller retries that captured request explicitly. Cancelled work cannot
  run. Batch barriers are a bounded baseline, not a recommended executor.
- `synchronous_callback` checks the existing native-thread/system-Io contract
  and lent stack context during a synchronous callback, without adding
  callback-side waits or claiming additional deadlock freedom.
- `direct_calls` and `mixed_library` keep cheap calls on the main OS thread;
  the mixed module also runs its blocking function on an explicit system
  task. The native main-thread check avoids interposing sanitizer threading.

The `confined` modules keep raw owner/client/resource access private. Their
`exchange` helpers are local whole-value replacements, not a proposed public
API. `carries(slot)` carries the old value's dependencies into the returned
value; `retains(slot: next)` keeps the replacement in the lent slot. An old
`None` is explicitly matched and settled because `Option[Resource]` is linear.

Cases are self-contained because the conformance loader checks each root
from its own in-memory file set. The command transcripts under
`tests/cmd/foreign_owner/` reuse `cleanup_retry` for external-module refusals
and the fixtures needed for bounded subprocess observations. The watchdog
kills and reaps only its own process group and rejects unexpected output,
including sanitizer/storage reports. Permanent destruction failure observes
an explicit abort, not successful cleanup. The nonreturning mock demonstrates
unrelated-fiber progress while its join remains blocked; it has no in-language
cancellation.

The impossible-stack refusal exercises the public task preparation error
path. It does not inject every allocation, native thread or owner-start
failure. Affinity belongs to this reviewed private wrapper, not every owned
foreign handle. Native destructor failure semantics must be checked for each
real library; retaining `Closing` is valid only when that failure preserves
the native object.

These cases enter the normal conformance walk, including Linux x86-64
optimized-corpus and address/thread sanitizer lanes. The fiber job also runs
both test directories explicitly on Linux x86-64 and arm64.
[CI run 43481888246](https://github.com/arthurgeek/linea/actions/runs/43481888246)
passed all eight runtime cases and nine command transcripts on each Linux
ABI, and both ASan/TSan corpus lanes passed. The sanitizer lanes leave
non-running compile-refusal transcripts to the unsanitized jobs. See
[ADR 0265 §9.5](../../../docs/adr/0265-waits-go-through-the-runtimes-poller-and-a-loop-runs-tasks-as-fibers.md#95-validation-evidence-and-acceptance)
for provenance, counts and coverage limits. Local macOS sanitizer execution
is excluded by the repository's toolchain policy.
