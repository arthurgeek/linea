# 155. Transcript cases replace one-line command cases

Status: Accepted — 2026-09-23. Extends [0008](0008-golden-conformance-suite.md).

## Context

A command case under `tests/cmd/` was one line of arguments to `linea`, with
`<name>.out`, `<name>.err` and `<name>.exit` beside it and an optional
`<name>.stdin`. The runner started one `linea` process in the checkout root and
compared its streams against those files.

That form cannot express a second process. An HTTP server example is checked
by starting the server, waiting until it listens, sending it a request with a
client, and reading what came back. That takes several commands, a background
job, and a tool other than `linea`, and a line of arguments to one process
holds none of them. The form also needed its own argument syntax: a quoted run
was one word, and `\xNN` spelled a byte, because a program's arguments are
bytes and a corpus file is text. That syntax was a small shell with its own
reader and its own tests.

## Decision

**A command case is a transcript**, in the format of cram and dune's cram
tests. A line not indented by two spaces is prose; `  $ ` begins a command and
`  > ` continues it; the indented lines after a command are its standard output
and standard error combined in the order written; a command that exits non-zero
is followed by `  [N]`. **The file is its own golden.** The runner renders what
ran over the file's prose and compares the result with the file; `--update`
rewrites the expected lines in place from what ran. Nothing sits beside a case,
so `.cmd` no longer anchors goldens, and a stream golden left beside one is an
orphan.

**Environment.** A case runs under one `/bin/sh` in a fresh `work` directory
inside the runner's scratch directory, with the `linea` under test first on
`PATH`, the checkout root in `LINEA_ROOT`, and the runtime the runner was given
exported to the compiler. Commands share the shell, so a background job one
starts is waited on by a later one. Standard input is empty; a command reads a
fixture with `<`. The checkout's absolute path is replaced by `$LINEA_ROOT` in
the captured output, and nothing else is scrubbed. The runner kills the case's
process group when its last command finishes and after ten minutes, so a hung
server fails its case rather than the suite. The deadline is a backstop for a
hang, set an order of magnitude above the slowest case on a loaded machine,
because a deadline a slow run can reach is a timing assertion inside the suite;
a case that waits on a server bounds its own waits and fails in seconds. A case whose commands run a
subcommand the build hides is passed over, as before.

**No cache.** Transcripts are outside the outcome cache. They run a shell and
external tools the cache does not stamp, so a cached pass could hide a change
in any of them.

**A case pins a stream separately by redirecting it to a file and showing it
with `cat`.** A command's inline output is its two streams merged, so a case
that asserts which stream a line went to runs the command with `> out`, which
leaves standard error and the exit status under that step, then `cat out`,
which shows standard output under its own step. A stream a case does not pin is
sent to `/dev/null`. A `.cmd` without a command line is a failure: a command
case is a transcript.

## Consequences

The 74 one-line cases were converted by a throwaway script to one transcript
each, and each transcript was checked against the goldens it replaced before
they were deleted. The comparison was exact per stream: the same exit status,
and each stream's recorded output equal to its old golden, apart from the
checkout path written as `$LINEA_ROOT`. The 67 cases that pinned both streams
are two steps, `linea … > out` then `cat out`; the rest send the unpinned
stream to `/dev/null`. Commands name repository files as `"$LINEA_ROOT"/…`, so
a checkout path holding a space still works. Two `emit-mlir` cases run from the
checkout in a subshell with relative paths, because the MLIR records each file
name's byte length, which the root scrub cannot restore. `linea test std` keeps
the bare word, because `std` names the embedded library rather than a
directory.

The argument syntax and its reader are gone; a case quotes the shell's way and
splices a byte with `"$(printf '\NNN')"`. A transcript depends on a POSIX
`/bin/sh`, and on `curl` for the HTTP cases, so `curl` joins the development
shell, which CI also uses.

The format has limits: an expected line beginning `$ `, a first line beginning
`> `, or a final line reading `[N]` reads back differently, and a missing final
newline is not recorded. No migrated case hits them.

A transcript's cost is a shell per case on top of the commands it runs, and
every case runs on every pass, since nothing is cached.

## Alternatives considered

**`.request` and `.response` sidecars.** A one-line case could gain files
naming a request to send and the response to expect, and the runner would
start the server, wait, and act as the client. That is a test harness with an
HTTP client of its own, and each new shape of interaction — two requests, a
client that closes early, a second program — needs another sidecar and more
runner code. A shell already composes processes, and `curl` is the client
people use.

**A `.t`, `.session` or `.md` extension.** A new extension would let the two
forms live side by side without the runner telling them apart. `.t` is cram's,
but here it reads as Perl's test files; `.session` is already the language
server's script format; `.md` would make every Markdown file under `tests/` a
candidate case. `.cmd` already names command cases, so it keeps its meaning.

**Keeping both forms.** The one-line form is shorter for a single command. Two
forms would mean two readers, two ways to pin a stream and two ways to quote an
argument, and a reader has to know which one a case uses. Every one-line case
converts to a transcript of one command without losing what it checked, so one
mechanism remains.
