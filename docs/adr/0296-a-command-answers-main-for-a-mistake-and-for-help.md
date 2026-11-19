# 296. A command answers `main` for a mistake and for help

Status: Accepted — 2026-11-19.

## Context

Every program that parsed its arguments with `std.cli` wrote the same three
functions: `report`, which printed `error: ` and a `CliError` with the help
of the command the error was about and returned 64; `print_help`, which
printed `format_help` to standard output and returned 0; and in two of them
`usage_error`, which printed the usage and returned 64. Six examples carried
copies, and the copies had already drifted: two printed the usage of a
command called without a subcommand with no `error:` line before it and an
empty line after it, where the others and the `linea` command name the
mistake first.

## Decision

**`Command[A]` answers each case with one call that returns the exit status
for `main`.**

- `report(args: env.Args, error: CliError) -> UInt8` writes `error: ` and the
  error to standard error, then the help `help_for_arguments` finds for the
  same arguments, and answers `cli.usage_status`.
- `usage_error(args: env.Args, message: Str) -> UInt8` reports a mistake the
  parse accepted but the program refuses, as `report` reports
  `CliError.InvalidValue(message)`.
- `print_help(matches: borrow Matches[A]) -> UInt8` writes `format_help` to
  standard output and answers 0.
- Each builds its help in the command's allocator and releases it before it
  returns. A refused allocation, and a failed write of the help, is written
  to standard error and answers 1.
- `cli.usage_status` is 64, `EX_USAGE` of the BSD `sysexits.h` convention,
  the status the `linea` command and every example already answered for a
  command called wrongly.

The calls take `env.Args`, as `parse_args` does, because a program reports
the arguments it was started with; a test reads `help_for_arguments` from an
`ArgCursor` over a slice instead.

## Consequences

- A program's `main` reads `cmd.parse_args(env.args()) else |error| { return
  cmd.report(env.args(), error) }`, and the help it prints is always built
  from the schema it parsed with.
- Every mistake on the command line looks alike: `error: ` and what went
  wrong, then the help of the command it is about.
- The help is printed in full after each mistake. A command whose help runs
  to many screens would want a shorter answer; none in the tree does.

## Alternatives considered

**Exit status 2**, the status of `getopt`-style tools and of several argument
parsers in other languages. The `linea` command, its transcripts and every
example's recorded status already answer 64; changing the library alone
would make it disagree with the compiler that ships it.

**A short message and a pointer, `try 'tool --help'`, in place of the help.**
It hides the options a reader needs to correct the mistake behind a second
run, and the help shown is already the one of the command the mistake is in,
which keeps it short.

**Free functions taking the command, `cli.report(cmd, args, error)`.** Each
needs the schema, so each is a method of the type that holds it, like
`format_help`.

**Writer parameters, so a test can read what is written.** The text is the
`help_for_arguments` help after one line; a writer form would double the API
for what that function's tests already pin.
