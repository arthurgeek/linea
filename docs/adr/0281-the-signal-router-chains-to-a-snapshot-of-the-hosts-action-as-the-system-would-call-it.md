# 281. The signal router chains to a snapshot of the host's action, as the system would call it

Status: Accepted — 2026-11-18; supersedes the delivery and host-handler
clauses of [0265](0265-waits-go-through-the-runtimes-poller-and-a-loop-runs-tasks-as-fibers.md)
§4.5

## Context

0265 §4.5 makes an operating-system signal a wait-set source. While a share
of a signal lives, the runtime's router has a handler installed for it, and
the action in place before the first share is saved and restored when the
last share goes. Two of its clauses describe the handler:

- *Delivery* says the handler counts the delivery, writes the wake
  descriptor and restores `errno`, and that "nothing else runs in the
  handler".
- *A host's handler* says that when the saved action is a handler a host
  installed, the router calls it after counting and waking, "with the same
  arguments".

Both were incomplete as built, and the gaps broke promises:

1. **The saved action was read while it was rewritten.** The handler read the
   saved `struct sigaction` field by field, without a lock, on whichever
   thread the signal reached. A new first share, taken after the last was
   released, saved the host's action again under the router's lock. A
   delivery the handler began before the release could still be reading
   when the next first share wrote, so the read was a data race. A torn read
   called one host action's handler with another's `SA_SIGINFO` flag, which
   the runtime's undefined-behaviour checks trapped.
2. **The host's handler ran under the router's policy, not its own.** The
   router called the handler directly, under the router's own mask. So the
   host's `sa_mask` was not applied, its own signal stayed blocked under
   `SA_NODEFER`, and an `SA_RESETHAND` handler ran on every delivery instead
   of once. The fault handler, which hands a fault that is not Linea's to
   the action installed before the runtime's, already called the previous
   handler under its `sa_mask` and `SA_NODEFER`, in code of its own.

## Decision

**The handler takes a snapshot of the saved action before it does anything
else, and chains to that snapshot.** The saved action is published with a
sequence count:

- The writer runs under the router's lock, and only while no share of the
  signal exists, so the router's handler is not installed for it. It makes
  the count odd, stores the action word by word with atomic stores, and
  makes the count even again.
- The handler copies the words with atomic loads between two reads of the
  same even count, and retries a copy that overlapped a write.

So a delivery chains to the action saved when the handler began. That holds
even when the last share is released and a new first share saves another
action while the handler runs. The handler takes no lock and allocates
nothing. It cannot wait on a write made on its own thread, since no write
happens while the handler is installed for that signal.

**A host's handler is called as the system would have called it**, through
one routine that the router and the fault handler share
(`runtime/host_action.h`):

- It gets the same arguments.
- It runs with the thread's mask extended by its `sa_mask` and, unless it
  set `SA_NODEFER`, by its own signal. With `SA_NODEFER` and the signal
  outside its `sa_mask`, the signal is unblocked for the call.
- The thread's mask is restored afterwards.

**Each caller answers `SA_RESETHAND` its own way.** After a spent one-shot
handler the system would have reset the signal to its default action:

- A fault then takes the default action.
- The router calls an `SA_RESETHAND` handler for the first delivery after
  its action is saved. While a share lives it only counts later deliveries,
  since a share defers the default action like any other. When the last
  share is released it restores the default action.

  The one call is claimed against the sequence count the action was
  published under. A delivery holding a snapshot of an earlier publication
  therefore cannot spend a later one's call. A release that restores an
  unspent one-shot action claims the call first, so a delivery still in the
  router cannot call the handler beside the restored action. macOS does not
  report `SA_RESETHAND` through `sigaction`, so there the router has no flag
  to honour.

Not reproduced, as with the fault handler:

- The host's handler runs on the stack the router's runs on: the thread's
  alternate signal stack where it has one, whatever the host's `SA_ONSTACK`.
- A system call it interrupts restarts under the router's `SA_RESTART`,
  whatever the host's flags say.

The rest of 0265 §4.5 stands: which signals are offered, the wake
descriptor, coalescing, masking, disposition shares, and an ignored signal
being refused.

## Alternatives considered

- **Take the router's lock in the handler.** A signal that interrupts
  `acquire` or `release` on the thread holding the lock would deadlock, and
  a mutex is not async-signal-safe.
- **Block the signal around the write.** Blocking it on the writing thread
  leaves handlers running on every other thread.
- **Save the host's action once, at the first share the process ever
  takes.** A host that changes its action between two periods of sharing
  would lose the change.
- **Copy only `sa_mask` into the router's installed action.** The router's
  own work would then run under the host's mask, and `SA_NODEFER` and
  `SA_RESETHAND` would still be unanswered.
- **Call the fault handler's `pass_on` from the router.** On a spent
  one-shot it reinstalls the default action, which would remove the router
  while a share still lives.

## Consequences

The race is gone: the handler reads only atomic words, and a delivery
chains to one consistent action. The router and the fault handler answer
"how is a host's handler called" in one place. A native test stops a
delivery's handler before it chains, re-shares under another host action and
lets it go, and checks that it chains to the first action. Another races
deliveries against re-shares. Two more check the mask a chained handler sees
and the one-shot rule. The thread sanitizer runs these tests on Linux in CI.

A host handler that reinstalls itself with `sigaction` while a share lives
replaces the router's handler. This record does not decide that case.
