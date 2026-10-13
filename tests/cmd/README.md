# Command tests

Each case is `<name>.cmd`, a transcript of shell commands with their expected
output inline, in the format of cram and dune's cram tests:

```
Check reports a rule.

  $ linea check "$LINEA_ROOT"/tests/diag/undefined_name.lin > out
  error[N-Undefined]: undefined name `y`
   --> $LINEA_ROOT/tests/diag/undefined_name.lin:2:5
    |
  2 |     y + 1
    |     ^ no binding with this name is in scope
  [1]
  $ cat out
```

- A line not indented by two spaces is prose.
- `  $ ` begins a command; `  > ` continues the one above it.
- The indented lines after a command are its combined standard output and
  standard error, in the order they were written.
- A command that exits non-zero is followed by `  [N]`.

The file is its own golden. The runner renders what ran over the same prose and
compares the result with the file; `--update` rewrites the expected lines in
place. Expected output is never written by hand: write the prose and the
commands, run the runner with `--update`, and read what it recorded.

## Environment

Each case runs under one `/bin/sh`, so commands share variables, functions and
background jobs, and a later command can wait for a job an earlier one started.

- The shell starts in a fresh directory, `work`, inside the case's scratch
  directory, so a file a command writes is gone when the case ends.
- The `linea` being tested is first on `PATH`.
- `LINEA_ROOT` is the checkout root. Name repository files through it, quoted
  so a path holding a space works, as `"$LINEA_ROOT"/tests/...`. The checkout's absolute path is replaced by
  `$LINEA_ROOT` in the captured output, so a diagnostic quoting a file reads the
  same on every machine.
- The shell's standard input is empty. A command that reads input takes a
  fixture with `<`, as `< "$LINEA_ROOT"/tests/cmd/stdin/formats_supplied_source.stdin`.
- A case has ten minutes. The runner then kills the case's process group and
  reports the output each command had written. The deadline only catches a
  hang: it sits an order of magnitude above the slowest case on a busy
  machine, so no case depends on how loaded the machine is. The process group is also
  killed when the last command finishes, so no background job outlives its
  case.

A case whose commands run `linea` with a subcommand this build hides (the
`dump-*` commands, in a release build) is passed over and counted as such.
Transcripts are outside the outcome cache, because they run a shell and tools
the cache does not stamp.

## Waiting on a server

A case that starts a server in the background bounds every wait itself, so a
server that never starts or never stops fails its case in seconds and says why,
rather than at the deadline. `tests/cmd/http_json_echo/` shows the pattern:

- Build the program once with `linea build … -o NAME` and run `./NAME` for
  every server and client in the case. Each `linea run` compiles the program
  again, which is most of what a case like this costs, so the scenarios one
  program answers share one case rather than one each.
- Create the log, then start the server with both streams in it and keep its
  process id: `: > server.log; ./echo … > server.log 2>&1 & server=$!`.
  The shell opens a background command's redirection in the child, after the
  line has returned, so without the empty log the wait below can read a file
  that does not exist yet, and `grep`'s complaint becomes part of the output.
- Wait a counted number of times for it to report its address, stop early if
  it exits, and print its log if it never reported:
  `for i in $(seq 2400); do grep -q listening server.log && break; kill -0 $server 2>/dev/null || break; sleep 0.05; done; grep -q listening server.log || cat server.log`.
- Give every client a limit, such as `curl --max-time 30`.
- Wait a counted number of times for the server to stop, stop it if it has
  not, and wait for its status:
  `for i in $(seq 600); do kill -0 $server 2>/dev/null || break; sleep 0.05; done; kill $server 2>/dev/null && echo "the server did not stop"; wait $server`.
  A server that exits non-zero, or has to be stopped, records `[N]`.

## Pinning each stream

A command's inline output is its standard output and standard error merged, so
it does not say which stream a line went to. To pin the streams separately,
redirect standard output to a file and show it with `cat`, as the example above
does: the lines under `linea … > out` are standard error, followed by the exit
status, and the lines under `cat out` are standard output. An empty `cat out`
step asserts that nothing reached standard output.

To pin only one stream, send the other to `/dev/null`. `help_succeeds` drops the help
text with `> /dev/null`, so it checks that standard error stays empty and the
command succeeds, whichever commands this build lists. `usage_no_command` drops
both streams and checks only the exit status, because the full command list
includes the `dump-*` commands in a debug build and omits them in a release
one. `usage_bare_fmt` covers the usage text itself, since one command's own
help does not vary that way.

## Arguments

Commands are shell text, so an argument is quoted the shell's way: `''` is an
empty argument and `'two words'` is one. A byte that is not text is spliced in
with `printf` and an octal escape: `'a'"$(printf '\303')"'z'` is the three bytes
`a`, `0xC3`, `z`.

## Limits of the format

- An expected output line beginning `$ `, or a first output line beginning
  `> `, reads back as a command or a continuation.
- An output line that is exactly `[N]` and ends a command's output reads back as
  the exit status.
- Output that does not end in a newline is recorded with one.
- Line endings are `\n`; a `\r` stays part of its line.
