# 75. A program root is a directory holding a manifest

Status: Accepted — 2026-08-07. The command-line-file clause ("Naming a file on the command line keeps meaning what it means today") is superseded by [0171](0171-the-standard-library-is-an-ordinary-library.md): a named file inside a program's source selects its own module as that program's entry.

## Context

A module is a directory. Which directory is a *program* was never written down,
because until now only a command line ever asked: `linea check vault` names the
program, `linea check vault/main.lin` names a file to compile on its own, and
both are unambiguous because the caller said which they meant.

An editor cannot say which. It has a file and nothing else, and it must decide
what that file means. The two available answers are both wrong:

```
$ linea check examples/vault/ledger/account.lin
error[S-Entry]: a program declares exactly one `main`
```

`account.lin` is a member of `ledger`, which is a submodule of `vault`. It has
no `main` and is not supposed to have one. Resolving the file to itself asks it
to be a program. Resolving it to its directory asks `ledger` to be one, which
reports the same thing. Resolving it to *its directory's* parent works here and
fails on the first program that is not exactly two levels deep.

The same gap has a second face. `linea check examples/vault/ledger` reports
`[S-Entry]` for a submodule that no more declares `main` than a header file
declares one — the command line, too, has no way to say "check this module as
part of its program" because nothing records which program that is.

So the question is not *what is a module* — a directory is. It is **which
module is the program**, and nothing in a Linea tree answers it.

Every comparable toolchain reached this and answered it the same way. Go has
`go.mod`, Rust `Cargo.toml`, Zig `build.zig`. Odin is the instructive exception:
its compiler has no project file at all, because `odin build ./vault` always
names the package — and its language server had to invent `ols.json` the moment
an editor needed the answer. C and C++ tell the same story through
`compile_commands.json`.

A marker is not avoidable. What is avoidable is inventing one twice, once for
the compiler and once for the editor.

## Decision

**A program root is a directory holding `linea.json`. A file belongs to the
nearest ancestor directory that holds one; a file with no such ancestor is a
program on its own.**

One manifest per program, in the program's own directory, rather than one at
the workspace listing them. A program then carries its own mark: moving it
somewhere else keeps it valid, and copying it into another tree needs nothing
added.

The file may be empty — `{}` — because its presence is the fact being
recorded. It is JSON because that is what the standard library parses, and
because the alternative was a hand-written parser for a format nothing else in
the tree reads.

**One key is defined: `source`, naming the directory the root module sits in,
relative to the manifest.** Absent, it is the manifest's own directory, which
is what makes `{}` complete and a flat layout the default.

```json
{ "source": "src" }
```

The key is spelled so that it cannot be read the wrong way round. A key whose
name coincides with its usual value — `{"src": "src"}` — leaves a reader no way
to tell which side is fixed, and the first thing anyone wanting `lib` has to
guess is whether to write `{"src": "lib"}` or `{"lib": "lib"}`. `source` never
collides with a directory anyone names, so one example teaches the format.

Nothing downstream learns that a source root was involved. A named directory is
a directory like any other and its subdirectories are submodules exactly as
they would be one level up, so this decides one thing and no pass after it
knows the difference.

`linea init` writes the manifest, and an entry point under `src/` where the
directory holds no source at all. It refuses a directory that already holds a
manifest rather than rewriting one: running a command twice is not consent to
replace a project's configuration. Where source already exists it marks the
tree and leaves it alone, since a second `main` beside the one already written
is the shape the manifest exists to prevent.

**The whole toolchain reads it, not just the language server.** This is the
part that makes it worth a language decision rather than an editor setting: one
function answers *which program is this file in*, and the driver and the server
both call it. A marker only the server understood would be a second answer to
the question this record exists to give one answer to
([ADR 0048](0048-one-question-has-one-answer.md)).

Naming a file on the command line keeps meaning what it means today — that file
is the program, as `go run x.go` does. The manifest changes what *a file inside
a program* resolves to, which is the question only the editor was asking.

The search is bounded by the workspace: the command line does not look above
the directory it was run in, and the server does not look above the root the
client sent. Unbounded, a manifest in a home directory would capture every
project beneath it.

## Consequences

`examples/vault/linea.json` makes `account.lin` resolve to `vault`, and the
squiggle that prompted this record disappears. `linea check
examples/vault/ledger` resolves the same way, so the two agree without either
being taught about the other.

A file under no manifest is unchanged: `examples/measure.lin` and every bare
case under `tests/` is still a program on its own, which is what a directory of
separate programs is made of. This is the property that lets `tests/` keep its
shape — 732 files, most of them standalone, sharing directories — where a rule
making the directory the unit unconditionally would have required splitting
roughly five hundred of them.

Every module case in the corpus gains a manifest: those are the directories
where a file resolving to itself is wrong, and adding one is what makes the
rule exercised rather than asserted.

Cost is one `stat` per ancestor, once per check, against a depth that is the
path's own and not the program's.

## Alternatives considered

**`main.lin` marks the root.** The corpus convention already privileges that
name, and the conformance runner already groups cases by it, so the rule was
available at no cost. Rejected because it makes a filename load-bearing in the
language: `main.lin` is a program's entry point, and giving it a second job
means a file cannot be renamed without changing what its neighbours mean. A
marker's only job should be marking.

**A directory is always a module, as in Go and Odin.** Both make the directory
the unit unconditionally, so two `main`s in a directory is an error and many
programs is many directories. It is the simplest rule to state and it answers a
different question than the one being asked: it says what a module is, not
which module is the program, so an editor still cannot resolve `account.lin`.
It also requires splitting the roughly five hundred standalone cases that share
directories under `tests/`.

**Each file declares its module, as Odin's `package` clause does.** Explicit,
local, and needs no walk. Rejected as much larger than the problem: it puts the
same name in every file of a module, which the directory already carries, and
it makes the clause authoritative over the directory — which touches imports
and visibility to answer a question about resolution.

**A server-only config, as `ols.json` is.** The smallest change, and precedent
exists. Rejected because the command line has the same gap: `linea check` on a
submodule is wrong today for exactly the same reason, and a marker the compiler
could not read would leave that wrong while fixing only the editor — two rules
for one question.

**One manifest at the workspace listing every root.** Fewer files, and it suits
a repository that holds many small programs. Rejected because a program then
only means something in the tree that lists it: moving one, or copying it into
another project, silently changes what it is.
