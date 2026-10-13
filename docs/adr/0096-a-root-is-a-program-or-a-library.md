# 96. A root is a program or a library, and its manifest says which

Status: Accepted — 2026-08-20. Extended by [0101](0101-a-library-publishes-what-it-exports.md) and by [0171](0171-the-standard-library-is-an-ordinary-library.md), which adds the `name` and `extern` manifest keys.

Builds on [0075](0075-a-program-root-is-a-directory-holding-a-manifest.md),
which made a directory holding a manifest the thing a command is run against,
and on [0024](0024-a-program-is-a-list-of-declarations.md), which made a
program a list of declarations one of which is `main`.

## Context

Every root the compiler accepted was a program. `[S-Entry]` required exactly one
`main`, the driver linked an executable around it, and a file holding one
function was `error[S-Entry]`, reported against that function for being the
first declaration.

So the shape every other language uses to show what its compiler does — a
function, on its own — was not a shape this compiler had an answer for. Neither
was any code meant to be *used* rather than *run*, which is every line of `std`.
The compiler already builds `std`, as part of a program and never on its own
terms.

`[S-Entry]` had one exception already: a root built to run its tests declares no
`main`, because the compiler writes the dispatcher. That exception is what
showed the rule was stated over the wrong thing. There were not programs and an
oddity; there were kinds of root, and only one of them had ever been written
down.

## Decision

**A root is a program or a library, and the manifest names which.**

```json
{ "kind": "library" }
```

`program` is the default, so `{}` stays a complete manifest and every root
written before this keeps its meaning. A `kind` this compiler does not know is
refused rather than read as the default: a value falling back to `program` is a
typo whose only symptom is a library that demands an entry point.

**The kind is a property of the root, recorded by whoever loaded it.** Not of
the command being run, and not of one loading path. A compilation loaded from a
directory, one assembled in memory by the test runner, and one a language server
holds all read the same manifest, because a kind recorded on one path is a
library that is a library to the compiler and a program to everything that
tests it.

**`[S-Entry]` is stated over the kind of root**, rather than over programs with
exceptions attached:

```
Root
├── program   declares exactly one `main`
├── tests     declares none; the compiler writes the dispatcher
└── library   declares none, and may not declare one
```

**`[M-Entry]`, new: a library declares no entry point**, and one written in it
is refused where it is written. Its own rule and not a clause of `[S-Entry]`,
which asks whether a root *must* declare one: a requirement and a prohibition
are different questions, and one name answering both reports "the entry point is
wrong" without saying which way. It reads the declaration's name and role rather
than its visibility, so `pub fn main` is refused too.

**A library is entered through what it publishes.** A program is reached from
its entry point; a library has none, so what is wanted is the `pub` declarations
of its own root and everything those reach. Their bodies keep external linkage,
because the premise internal linkage rests on — that the module in hand holds
every caller — is exactly what a library breaks.

**A library builds to an object.** No entry wrapper, no argument setup, no link:
linking is what turns objects into a program, and there is no program here.
`run` refuses a library as a misuse of the command rather than diagnosing its
source, which is not what is wrong.

## What this deliberately does not decide

Nothing about how anything outside reaches in. Symbols stay spelled as they are
spelled today; there is no export marker, no unmangled name, no rule about which
declarations may cross a foreign boundary, and no answer for a generic function,
which has no symbol until something instantiates it.

So what a library gives you here is an object whose generated code can be read,
and not something another language can link against. That is a separate record,
and it arrives with the case shape that proves it: an object linked against a C
driver and run.

## Consequences

**Kind and purpose are different axes.** A first attempt made a library a third
`Purpose` beside `program` and `tests`. That cannot hold: `linea test` on a
library has to work — `std` is a library with tests, and a root of tests alone is
something the semantics already allows — so a root can be a library *and* be
built to run its tests at the same time. The command says which it is doing; the
manifest says what the root is.

**`[N-Unused]` needed nothing.** A `pub` declaration is already exempt, and a
submodule nothing imports is not loaded at all, so its declarations cannot be
unused. The reachability boundary a library needs was already drawn, one layer
lower, by the loader declining to load what no import reaches.

**The `pub` boundary is the root's, and stage 2 will move it.** Nothing outside
a library can name a module inside it, because an import descends from the
importing module's own directory. But a path may already descend, so a mechanism
that lets a consumer name a library at all makes `mylib.sub` spellable, and what
a library publishes grows to match.

## Alternatives considered

**A flag rather than a manifest key.** `linea build --library` puts the kind in
the invocation, so the same source is a library or not depending on how it was
built — and every tool that reads a project, the language server included, would
have to be told separately. The manifest is what marks a root; what kind of root
it is belongs beside that.

**Ignoring a `main` in a library.** It would be one rule fewer. It also makes the
most likely mistake — a manifest saying `library` where its author meant
`program` — silent, and its only symptom an executable nobody produced.

**Publishing every `pub` declaration, wherever written.** Everything a
compilation holds is lowered into one module, `std` included, and every
declaration `std` exports is public. A library that called four functions of it
would publish the whole standard library and carry every body either of them
ever defined.
