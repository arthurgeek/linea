# Running other programs

A program often needs another program's help: a build tool runs the compiler,
a deployment script runs `git`, a test driver runs the program under test.
`std.process` starts such a **child process**, hands it arguments, an
environment and input, reads what it prints, and tells you how it ended.

If you have used Rust's `std::process::Command` or Node's
`child_process.spawn`, the shape is familiar: you describe the command, then
start it. What Linea adds is that a started child is a **linear** value
([Copying, settling and
sealing](04-copying-settling-and-sealing.md#linear-values-you-must-not-forget)):
the compiler makes you wait for every child you start, so none is left behind
as a zombie in the process table.

## Starting a program with `Command`

`process.Command.new` names the program, and `arg` adds one argument each.
`status` starts the child, waits for it to end and answers an `ExitStatus`:

```linea
import std.io
import std.process

fn main() -> Result[UInt8, process.ProcessError] {
    // `status` starts the program, waits for it to end and answers how it
    // ended. Its streams are this program's own, so what it prints appears
    // here directly.
    let listed = process.Command.new("echo").arg("hello from a child").status()?
    io.println("echo {listed}")?
    let failed = process.Command.new("/bin/sh").arg("-c").arg("exit 3").status()?
    io.println("sh {failed}; success: {failed.success()}, code: {failed.code():?}")?
    .Ok(0)
}
```

```text
hello from a child
echo exited with code 0
sh exited with code 3; success: false, code: Some(3)
```

A name without a `/`, such as `echo`, is looked up in `PATH`, as a shell
would; a path such as `/bin/sh` is used as written. By default the child's
standard input, output and error are this program's own, which is why
`hello from a child` appears directly.

`success()` is true only for exit code 0. A child killed by a signal has no
code, and `code()` answers `None` for it. `main` here answers
`Result[UInt8, process.ProcessError]`; a failed `io.println` turns into a
`ProcessError` through `?` as well.

## Arguments, the environment and the directory

Each `arg` reaches the child as exactly one argument: no shell splits it on
spaces or expands `*` in it, unless the child you start is a shell.
`env(name, value)` sets a variable for the child alone, `env_remove(name)`
leaves one out, `env_clear()` starts from no variables at all, and
`directory(path)` sets where the child starts:

```linea
import std.io
import std.process

fn main() -> Result[UInt8, process.ProcessError] {
    // Each argument reaches the child as one word, spaces and all: no shell
    // splits it. Here the shell is the child, and `$1` and `$2` are the
    // arguments after the script and its name.
    let words = process.Command.new("/bin/sh").arg("-c").arg("printf '[%s] [%s]\\n' \"$1\" \"$2\"").arg("sh").arg("two words").arg("one").status()?
    // `env` sets a variable for the child only, `env_remove` leaves one out,
    // and `directory` picks where it starts.
    let setting = process.Command.new("/bin/sh").arg("-c").arg(r"echo $BREW in $(pwd), home ${HOME:-unset}").env("BREW", "oolong").env_remove("HOME").directory("/").status()?
    io.println("{words}, {setting}")?
    .Ok(0)
}
```

```text
[two words] [one]
oolong in /, home unset
exited with code 0, exited with code 0
```

Building a command never fails. An argument the system cannot take, such as
one holding a NUL byte, or memory that runs out while the command is built,
is kept and reported by the call that starts the child, so a command reads as
one expression without a `?` after every step.

## Capturing what a child prints with `output`

`output` connects the child's standard output and error to pipes, reads both
while the child runs, waits for it, and answers a `process.Output`: the status
and every byte of each stream. `max_bytes` caps each stream, because what a
child prints is input your program did not write; a child that prints more is
killed and `output` fails with `TooLong`.

```linea
import std.io
import std.process

fn main() -> Result[UInt8, process.ProcessError] {
    // `output` pipes the child's standard output and error, reads both while
    // the child runs, and waits for it. Each stream may hold at most
    // `max_bytes`.
    let output = process.Command.new("/bin/sh").arg("-c").arg("echo 3 files changed; echo 'warning: detached HEAD' >&2").output(max_bytes: 4096)?
    let printed = Str.from_bytes(output.stdout.as_slice())
    let reported = Str.from_bytes(output.stderr.as_slice())
    let shown = match (printed, reported) {
        (Ok(out), Ok(err)) => io.print("{output.status}\nout: {out}err: {err}"),
        _ => io.println("the child printed bytes that are not UTF-8"),
    }
    output.release()
    shown?
    .Ok(0)
}
```

```text
exited with code 0
out: 3 files changed
err: warning: detached HEAD
```

The captured bytes are a `Vec[UInt8]`, since a program may print anything;
`Str.from_bytes` checks they are UTF-8 text. `Output` owns them, so it is
released once you are done.

`output` reads the two streams at once, not one after the other. A pipe
holds only so much (64 KiB on Linux and macOS); a child that fills its error
pipe stops until someone reads it, and a parent that waited for standard
output to end first would wait forever. Reading whichever pipe has bytes
avoids that, and so does every `output` and `wait_with_output` in Linea.

## A child must be waited for

`spawn` starts the child and hands it back without waiting: a
`process.Child`. A child that has ended still holds an entry in the process
table until its parent waits for it, so `Child` is linear, and `wait` is how
you settle it. Forgetting is a compile error:

```linea
import std.process

fn main() -> Result[UInt8, process.ProcessError] {
    let _child = process.Command.new("sleep").arg("1").spawn()?
    .Ok(0)
}
```

```text
error[O-Leak]: `_child` (a linear `process.Child`) is still owned when this path leaves
 --> forgot.lin:4:9
  |
4 |     let _child = process.Command.new("sleep").arg("1").spawn()?
  |         ^^^^^^ never settled on the path that reaches the end of this block
6 | }
  | - the block ends here
  |
  = help: settle it first with `_child.wait()`
```

The same check covers every path: an early `return` or a `?` that leaves while
a child is running is refused until that path waits too.

## Talking to a child through pipes

`stdin(.Pipe)` and `stdout(.Pipe)` give the parent the other end of each
stream. `take_stdin` and `take_stdout` move those ends out of the child: a
`process.PipeWriter` is a `Writer`, and a `process.PipeReader` is an
`io.Reader`, so the formatting and reading tools of `std.io` work on them.
Closing the writer tells the child its input has ended:

```linea
import std.io
import std.process

fn main() -> Result[UInt8, process.ProcessError] {
    // `sort` reads its input to the end before it writes a line.
    var child = process.Command.new("sort").stdin(.Pipe).stdout(.Pipe).spawn()?
    // `take_stdin` moves the writer out of the child. Closing it ends the
    // child's input, which is what lets `sort` finish.
    var input = &child.take_stdin().unwrap()
    let wrote = "pear\napple\nfig\n".fmt(&input)
    let closed = input.close()
    var output = &child.take_stdout().unwrap()
    defer let sorted = io.read_text(&output, max_bytes: 4096)
    output.release()
    // `wait` is the only way to settle a child, so it runs on every path,
    // whatever the writes and the read answered.
    let status = child.wait()?
    wrote?
    closed?
    match read sorted {
        Ok(text) => io.print("{text.view()}")?,
        Err(_) => io.println("sort printed something that is not text")?,
    }
    io.println("sort {status}")?
    .Ok(0)
}
```

```text
apple
fig
pear
sort exited with code 0
```

`wait` closes any pipe the child still holds before it waits, so a child
cannot wait forever for input you never closed, or for room to write output
you never read. A pipe you took is yours: close the writer you took before
you wait, or a child such as `sort` that reads to the end of its input waits
for it as long as you wait for the child.

### Feeding input and capturing output with `wait_with_output`

When you write input yourself and want the output captured, take the input
end, write and close it, then let `wait_with_output` read the rest:

```linea
import std.io
import std.process

fn main() -> Result[UInt8, process.ProcessError] {
    var child = process.Command.new("tr").arg("a-z").arg("A-Z").stdin(.Pipe).stdout(.Pipe).stderr(.Pipe).spawn()?
    var input = &child.take_stdin().unwrap()
    let wrote = "steep for three minutes\n".fmt(&input)
    input.release()
    // `wait_with_output` reads the pipes the child still holds, both at once,
    // then waits.
    defer let output = child.wait_with_output(max_bytes: 4096)?
    wrote?
    match Str.from_bytes(output.stdout.as_slice()) {
        Ok(text) => io.print("{text}")?,
        Err(_) => io.println("tr printed something that is not text")?,
    }
    .Ok(0)
}
```

```text
STEEP FOR THREE MINUTES
```

## Stopping a child with `kill`

`kill` sends the child `SIGKILL`. It does not settle the child: a killed child
is still waited for, and `wait` reports the signal:

```linea
import std.io
import std.process

fn main() -> Result[UInt8, process.ProcessError] {
    var child = process.Command.new("sleep").arg("60").spawn()?
    // `kill` sends SIGKILL and does not settle the child: it must still be
    // waited for, so the kill's own result is passed on only after the wait.
    let killed = &child.kill()
    let status = child.wait()?
    killed?
    io.println("sleep {status}; signal: {status.signal():?}")?
    .Ok(0)
}
```

```text
sleep killed by signal 9; signal: Some(9)
```

Until it is waited for, a child's process ID cannot be given to another
process, so `kill` always reaches the child you started.

## When a program cannot start

A program that is not there fails at `spawn`, `status` or `output` with a
`ProcessError.Io`, whose `io.IoError` has the operation `Spawn` and a portable
category: `NotFound`, or `PermissionDenied` for a file that may not be run.

```linea
import std.io
import std.process

fn main() -> UInt8 {
    let _shown = match process.Command.new("no-such-tool").arg("--version").status() {
        Ok(status) => io.println("no-such-tool {status}").is_ok(),
        Err(Io(error)) => io.println("cannot run no-such-tool: {error.category}").is_ok(),
        Err(error) => io.println("cannot run no-such-tool: {error}").is_ok(),
    }
    0
}
```

```text
cannot run no-such-tool: NotFound
```

## Children and tasks

A `wait`, and a read or write on a pipe, waits the way a socket does
([Tasks and sessions](13-tasks-and-sessions.md)): a task on a thread of its
own blocks, and a fiber on an `io.Loop` parks, leaving its carrier to run
other fibers until the child ends or the pipe is ready. The runtime waits for
each child by its own process ID and installs no `SIGCHLD` handler, so C code
in the same program that starts and waits for children of its own is not
disturbed.

The [build steps example](../../examples/build_steps.lin) puts this chapter
together: it runs a project's build steps as shell commands, shows what each
printed, and stops at the first that fails.
