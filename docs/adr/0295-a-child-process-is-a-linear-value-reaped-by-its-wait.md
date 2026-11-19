# 295. A child process is a linear value, reaped by its wait

Status: Accepted — 2026-11-19. Extends
[0265](0265-waits-go-through-the-runtimes-poller-and-a-loop-runs-tasks-as-fibers.md)
§1 and §5 with two more waits (a child's end and its pipes), and §4.5 with
what `SIGCHLD` is left to; extends
[0171](0171-the-standard-library-is-an-ordinary-library.md) and
[0255](0255-an-erased-value-is-reached-through-an-address-that-names-its-type.md)
with a fifth kind of number the runtime trusts, a child's process ID.

## Context

A Linea program could not start another program. Build runners, test
drivers, a deployment script, a tool that shells out to `git`: each needs to
start a child, give it arguments and an environment, feed its input, read
its output and learn how it ended. The C library offers all of it, through a
`fork` that is unsafe in a threaded process, descriptors that leak into the
child unless every one was opened close-on-exec, a pair of pipes that
deadlock a parent reading one while the child fills the other, and a process
table entry, the zombie, that stays until someone calls `waitpid`.

Each of those is a promise the language already makes elsewhere: no
descriptor a library holds is reachable by another owner (an open
`fs.File` is linear and closed once), no task waits forever on another
(0265 §5), and a resource is settled on every path (a linear value cannot be
dropped). A child process is one more resource with all three properties, and
the decision is how to give it them.

## Decision

### 1. A `process.Command` describes a child; building one never fails

```linea
let output = process.Command.new("git").arg("status").arg("--short").directory(repo).output(max_bytes: 1048576)?
```

`Command.new(program)` and `Command.new_in(allocator, program)` start a
description; `arg`, `env`, `env_remove`, `env_clear`, `directory`, `stdin`,
`stdout` and `stderr` each take the command and answer it changed, so a
command reads as one expression. Each copies its text into storage from the
command's allocator, and none fails: a refused allocation, an argument
holding a NUL byte (which would end the C string early), or a variable name
that is empty or holds `=` is kept as the command's first refusal and
answered by `spawn`, `status` or `output` as a `ProcessError`. The failure
stays visible in the type of the call that can act on it, and a builder
chain needs no `?` after every step.

`spawn`, `status` and `output` take the command and release it. A command is
affine and owns vectors, so a call that only read it would leave every chained
command for the program to release; consuming it is what makes the chain
`Command.new(...).arg(...).status()` settle everything it built.

A program name with no `/` is looked up in this process's `PATH`, as
`posix_spawnp` does; a path is used as written, relative to the directory the
child starts in. With no environment change the child receives this process's
environment as the system holds it; with any change, or after `env_clear`,
the runtime is handed a complete environment built from the variables the
process was started with (`env`'s entries, bytes and all), less the names
changed, plus the last value set for each name set.

Each standard stream is `Stdio.Inherit` (the default), `Null` (`/dev/null`)
or `Pipe`.

### 2. The runtime starts a child with `posix_spawn`, and nothing else leaks into it

`linea_process_spawn` takes the argument and environment blocks
(NUL-terminated strings), the directory, a scratch table the caller's
allocator provides for the pointer arrays `posix_spawn` takes, and a setup
byte (two bits per stream and one for "the environment is given"). It
answers the process ID or a negated errno, and writes the parent's end of
each pipe through an `inout` descriptor.

- `posix_spawn`, never `fork`: the C library creates the child without
  running atfork handlers or copying a threaded address space, and reports a
  program that cannot be executed (`ENOENT`, `EACCES`, `ENOEXEC`) as the
  call's error, so `spawn` fails with category `NotFound` or
  `PermissionDenied` rather than starting a child that exits 127.
- Every descriptor but the three streams is closed in the child. On macOS,
  `POSIX_SPAWN_CLOEXEC_DEFAULT` closes all of them and
  `posix_spawn_file_actions_addinherit_np` names the inherited streams. On
  Linux, glibc's `posix_spawn_file_actions_addclosefrom_np` (2.34) closes
  every descriptor from 3; it is declared weak, since the runtime is compiled
  against an older glibc than a program is linked with, and where it is absent
  the runtime lists `/proc/self/fd` and adds a close for each descriptor not
  marked close-on-exec. Every descriptor the runtime opens is close-on-exec
  already; the close action covers descriptors C code opened.
- Pipes are made close-on-exec (`pipe2` on Linux; `pipe` and `F_SETFD` on
  macOS, where the spawn's close-everything flag covers the instant between),
  moved above descriptor 2 so a `dup2` onto a standard stream never names its
  own source (which would leave close-on-exec set), and the parent's end is
  made nonblocking.
- The child starts with an empty signal mask (`POSIX_SPAWN_SETSIGMASK`): the
  runtime blocks `SIGPIPE` on its threads (`runtime/pipe_signal.h`), and a
  blocked signal survives `exec`. Dispositions are left as `exec` sets them:
  a caught signal returns to its default, and a signal the process was
  started ignoring (`nohup`'s `SIGHUP`) stays ignored in the child, as a
  shell would leave it.
- The directory change is `posix_spawn_file_actions_addchdir_np`, weak on
  Linux for the same reason; where it is absent a command with a directory
  fails with `Unsupported`.
- A standard stream this process has closed stays closed in the child, on
  both systems: on macOS only an open stream is named for inheritance.
- On any failure every descriptor the call opened is closed before it
  answers. The native test `runtime/process_test.c` counts the parent's
  descriptors around a spawn, failed and successful, and has a child look for
  a descriptor the parent left open without close-on-exec.

### 3. A `process.Child` is linear, and only `wait` settles it

`spawn` answers a `Child`: the process ID and the parent's end of each piped
stream. `Child` is `linear` and implements no `Release`, so the ownership
checker refuses any path that drops one ([O-Leak]). Its settlements are
`wait` and `wait_with_output` (and `wait_with_output_in`), each of which reaps
the child with `waitpid`. Every child a program starts is therefore reaped,
and no zombie outlives the path that made it; a test runs
`ps` to show none is left after the allocation-failure walks and after a
child killed for its output.

A wait fails only where `waitpid` itself does, when the child is not this
process's to reap (`ECHILD`). Every other failure on its way, such as no
descriptor left for the pidfd or kqueue of §7, or a parking that could not be
armed, falls back to the blocking `waitpid`, which still reaps the child; a
native test fills the descriptor table on a fiber and waits. A wait also goes
on past a child that a tracer reports stopped, since it has not ended.

`kill` takes the child `inout` and sends `SIGKILL`; it does not settle it, so
a killed child is still waited for, and `wait` answers
`Signalled(9)`. Because the process ID belongs to a child not yet reaped, the
kernel cannot give the number to another process, so `kill` never signals a
stranger. That holds only while the program reaps its own children: when
`SIGCHLD` is ignored, or caught with `SA_NOCLDWAIT`, the kernel reaps each
child as it ends and the number is free at once. In that state `spawn`
starts nothing and `kill` signals nothing; both fail with `ECHILD`
(§8). `take_stdin`, `take_stdout` and `take_stderr` move a pipe's end
out of the child.

`wait` closes every pipe the child still holds before it waits: the child
then reads the end of its input and gets `EPIPE` (or dies of `SIGPIPE`) writing
output nobody reads, so a wait cannot hang on a pipe the parent holds and
does not read. A pipe the program took is its own to close.

### 4. A pipe is an owned reader or writer

`process.PipeReader` and `process.PipeWriter` are linear owners of the
parent's end, with `close` and `Release` as `fs.File` has them, and the
existing traits: `io.Reader`, `io.ByteWriter`, `Writer`, `io.Close` and
`io.Pollable`, so `io.read_all`, a `BufferedReader`, formatted writes and a
wait set all work on them unchanged. Their transfers are
`linea_pipe_read` and `linea_pipe_write`: the ordinary descriptor transfer
(which retries `EINTR` and turns a write's `SIGPIPE` into `EPIPE`), and on
`EAGAIN` a wait for readiness, then again.

### 5. `output` reads both pipes at once through a wait set

`Command.output_in(allocator, max_bytes)` pipes standard output and error,
and `Child.wait_with_output_in` reads them: it registers each pipe in a
`task.WaitSet` as readable, and each delivery reads once (64 KiB at most),
appends to that stream's vector and registers the pipe again, until both have
ended; then it reaps the child. A child that fills its error pipe while the
parent waits on output is read from as soon as it writes, so neither side
waits on the other; a test has a child write three megabytes to standard error
and then five to standard output. Each stream may hold `max_bytes`, as
`io.read_all` takes a limit, because a child's output is input the program did
not write. When a stream passes it, or a read or an allocation fails, the
child is killed and reaped and the error answered: stopping the reads would
otherwise leave a child blocked on a full pipe.

Standard input is as the command set it; a piped one is closed at once, so a
child that reads its input sees it end. A stream ends when every process holding the pipe has
closed it, so a program the child leaves running in the background with its
pipes keeps `output` reading until that program closes them or ends; the
child's own exit does not end the read.

### 6. How a child ended, and why an operation failed

`ExitStatus` is `Exited(UInt8)` or `Signalled(Int32)`, with `success()`
(exited with 0), `code()` and `signal()`, and `Display` (`exited with code 3`,
`killed by signal 9`).

`ProcessError` is `Allocation(mem.Oom)`, `InvalidArgument`, `TooLong(limit)`
or `Io(io.IoError)`. An operating-system failure is an `io.IoError`, so its
`IoCategory` is the portable reason (`NotFound`, `PermissionDenied`,
`ResourceExhausted` when the process table or descriptors run out) beside the
native errno, as every other I/O failure reports it. `io.IoOperation` gains
`Spawn`, `Wait` and `Kill` for them; a pipe's read, write and close are
`Read`, `Write` and `Close`.

### 7. On a fiber, a wait parks the fiber

A wait for a child, and a pipe transfer, follow the rule 0265 §1 sets for
every wait: an operation is performed on the calling task's substrate. A task
on its own thread blocks in `waitpid` or `poll` in place. A fiber does not
hold its carrier:

- A pipe transfer that answers `EAGAIN` waits for the descriptor through
  `linea_fiber_wait_descriptor`, the carrier's poller, which leaves the
  carrier to other fibers.
- A wait first tries `waitpid(WNOHANG)`. While the child runs it takes a
  descriptor that becomes readable when the child ends, a pidfd
  (`pidfd_open`, Linux 5.3) or a kqueue holding an `EVFILT_PROC`/`NOTE_EXIT`
  registration (macOS), parks on it the same way, closes it, and reaps. A
  child that ended between the two steps answers `ESRCH` to the
  registration; on macOS the exit is reported a moment before the child can
  be reaped, so the fiber sleeps a millisecond, parked, and tries again. Any
  other failure to make or park on the descriptor, a Linux kernel without
  pidfds (`ENOSYS`) or a full descriptor table included, leaves the blocking
  `waitpid`, which then holds the carrier until the child ends (§3).

The native test runs both on a one-carrier loop beside a fiber that sleeps
and notes that it ran: the note is made before the wait returns only if the
wait left the carrier free.

Neither wait involves another task, so 0265 §5's deadlock argument is
unchanged: a child is the world, as a timer or a socket's peer is. What a
parent could wait on forever is the child itself, which `wait` bounds as far
as pipes go (§3); a child that never ends on its own is the program's to
`kill`.

### 8. `SIGCHLD` stays the system's; each child is waited for by its ID

The runtime installs no `SIGCHLD` handler, and the signal router of 0265 §4.5
does not offer it as a source. Each wait names its child's process ID, with
`waitpid(pid)` and a per-child pidfd or kqueue. A `SIGCHLD`-driven reaper would
have to own the signal's disposition process-wide, and its handler would have
to reap with `waitpid(-1)` or walk every outstanding child, which takes the
exit status of children it did not start: a C library, or a host embedding
Linea, that waits for its own children would find them gone (`ECHILD`). A
wait by ID touches only the child the `Child` owns. If `SIGCHLD` is
ignored, which Linux keeps across `exec` so a program can be started that
way, or a host catches it with `SA_NOCLDWAIT`, the kernel reaps every child
itself; `spawn` then refuses with `ECHILD` rather than start a child it could
neither wait for nor safely signal, and `kill` refuses the same way should
the disposition change after a spawn.

### 9. A simulation starts no process

A child is a real process with real timing, so inside a simulation (0265
§12) `spawn` fails with `Unsupported`, and a child or pipe from outside that is
used inside one traps, as a real socket does.

### 10. Who may reach a child's number

The process ID is a fifth number the runtime trusts, beside an allocation, a
descriptor, an address of bytes and a task's records: the table in
`src/support/runtime_symbols.zig` marks it `Held.child`. `linea_process_wait`
and `linea_process_kill` take one and are declared only by the standard
library's `process`, whose `Child` keeps it; `linea_process_spawn` answers one
and takes addresses of bytes, and `linea_pipe_read` and `linea_pipe_write`
take a descriptor and an address, so those three are declared only by `mem`,
which hands them through `_spawn`, `read_pipe` and `write_slice_pipe`. A
declaration anywhere else is refused by [T-ExternRuntime]: a program could
otherwise reap a child the standard library still waits for, or reap one
twice and signal whatever process took its number.

## Consequences

- Starting a program, feeding it and capturing its output are a few lines,
  with no `fork`, no descriptor bookkeeping and no possibility of a zombie or
  of the two-pipe deadlock.
- A `Child` cannot be put in a container that drops its elements, and a
  program that starts children must wait for each, early returns included.
  `?` after `spawn` in a function that then fails holds the child on that
  path, and the checker says so; the program waits, or kills and waits.
- A command is consumed by the call that starts its child; starting the same
  program twice builds the command twice.
- `output` uses a wait set, whose registrations take a little memory from the
  system allocator, and a duplicate descriptor per registration; the bytes
  read come from the caller's allocator.
- A wait set's `next` on a fiber that cannot park on its kernel queue, because
  the descriptor table is full or the carrier's storage is refused, now waits
  on that queue in place, holding the carrier, instead of ending the process;
  a full table while registering a pipe is the registration's error, which
  `output` answers after killing and reaping the child. Every wait set user
  gets the same.
- `io.IoOperation` has three more cases, which every exhaustive match on it
  and every derived rendering of it carries.
- On Linux without glibc's `addclosefrom`, a descriptor another thread opens
  without close-on-exec while a spawn lists `/proc/self/fd` can reach the
  child; with it, and on macOS, none can.
- A Linux kernel older than 5.3, or a descriptor table that is full, makes a
  fiber's wait for a child hold its carrier.
- A program whose `SIGCHLD` is ignored cannot start children; it fails with
  `ECHILD` and can restore the default disposition first.

## Alternatives considered

**`fork` and `exec` in the runtime.** It gives full control between the two
calls (closing descriptors with `close_range`, changing directory), but in a
threaded process the child may run only async-signal-safe code until `exec`,
it must report an `exec` failure back through a pipe, and `fork` copies page
tables of a large address space before `exec` discards them. `posix_spawn`
does all of this in the C library, with `vfork`-like cost on both platforms,
and has file actions for every step this design needs.

**Releasing a `Child` by killing and reaping it.** `Release` would let a child
be dropped in a container or at an early return. But a release that kills
hides a decision (the child may have been meant to finish), and one that waits
blocks at a point the program never wrote. Requiring `wait` keeps the end of a
child where the program says it.

**A `SIGCHLD` handler that reaps.** See §8: it owns a process-wide
disposition and takes other code's children.

**Reading the two pipes on two tasks.** Two tasks each reading one pipe also
avoid the deadlock, but cost a thread or a fiber each, and need the vectors
sent back through sessions. A wait set is the runtime's one way to wait on
several sources (0265 §4) and does it on the calling task.

**A builder whose steps answer `Result`.** Every `arg` would need a `?`, and a
command built in one expression would not read as one. The first refusal
kept and answered by the call that starts the child reports the same errors
at the one point where the program can act on them.

**No output limit.** A captured stream grows with whatever the child writes;
`io.read_all` already requires a limit for input the program did not write,
and `output` follows it.
