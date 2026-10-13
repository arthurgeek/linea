# 171. The standard library is an ordinary library

Status: Accepted — 2026-09-24. Supersedes the `std/` clause of
[M-Extern] in [0068](0068-a-declaration-may-name-a-symbol-the-runtime-provides.md),
the command-line-file clause of [0075](0075-a-program-root-is-a-directory-holding-a-manifest.md),
the reserved-path-root clause of [0085](0085-the-library-is-imported.md) and
the reserved-root sentence of [0111](0111-import-paths-are-root-relative.md).
Extends [0096](0096-a-root-is-a-program-or-a-library.md) with two manifest
keys.

## Context

The compiler decided whether code was the standard library from how its
directory was spelled. A module whose directory string was `std` or began
with `std/` was the library; a root named `std` on the command line swapped in
the embedded copy for `linea test`; the resolver found the library's root
module as the library module whose directory held no `/`.

Every one of those rules answered differently for one directory reached two
ways. `linea test std` worked from the checkout, because the driver substituted
the embedded copy. `linea test ./std`, `linea test "$PWD"/std` and
`linea test /checkout/std` from another directory loaded the same directory as
an ordinary program beside the embedded copy, and every name the prelude
publishes was declared twice ([N-Duplicate]). `linea check std` failed with
261 errors for the same reason. In the other direction, a program whose own
root directory was named `std` had its tests replaced by the library's.

[M-Extern] was stated over the same spelling: an `extern` was admitted where
the module's directory was the library's.

## Decision

**A root says what it is in its manifest, and nothing else says it.** Two keys
join `kind`:

```json
{ "kind": "library", "name": "std", "extern": true }
```

- `"name"` names a library. The name `std` makes the root the library every
  program depends on.
- `"extern": true` grants the root [M-Extern]'s capability, whether the root is
  a program or a library: its modules may declare `extern` functions. Without
  it, an `extern` is refused.

`std/linea.json` is that manifest, and the embedded copy carries it with the
sources, so the copy and the directory say the same thing. Only a library may
take the name `std`; a program's manifest giving it is refused, because the
program would be loaded as the library and lose its prelude. The loader reads
the root's manifest before loading its first module (`loader.Declared`), for a
root read from disk and one assembled in memory alike, and records the answer
on each module (`Module.library`, `Module.externs`). No pass decides either
from a path.

**One routine finds a root and the manifest that identified it.**
`loader.rootOf` returns both from a single walk, for a directory or a file,
and both readers of a root from disk -- the command line and the editor --
take its files, manifest included, from `loader.pathsOfRoot`.

**A file named on the command line selects its own module** as the entry of
the program whose source holds it, and import paths still resolve from that
program's source root. This supersedes 0075's clause that a named file is
the program on its own, which compiled a module of a program without the
program around it: its imports and the library it belongs to were lost, so
`linea check std/mem/allocator.lin` could not be checked at all. Now:

- `linea check app/util/u.lin` checks `app/util` and everything it reaches,
  whether or not `app`'s `main` imports it, and needs no `main` there;
- `linea run app/tools/gen.lin` runs `app/tools`'s own `main`, and a module
  that declares none is refused as nothing to run;
- `linea check std/mem/allocator.lin` checks `std.mem` as part of the library
  `std`, whose root module stays the prelude;
- a file no program's source holds is still a program on its own, and a
  directory named on the command line still names the program it sits in.

**A module's symbols are spelled from its import route**, which the loader
records (`Program.modulePath`), never from its directory. The library compiled
from any directory names its symbols `lin.std.mem.…`, as its embedded copy
does, so the emitted code does not depend on where the checkout sits.

**The `linea_` symbol namespace is the runtime's ([T-ExternRuntime]).** An
`extern` naming a `linea_` symbol must have the signature the runtime declares
for it, in whatever root declares it, and a `linea_` symbol the runtime does
not declare is refused. The signatures are one table,
`support/runtime_symbols.zig`, which a build-source test holds to `runtime/`'s
C and Zig sources so the two cannot drift. The standard library's declarations
are checked against the table like any other root's. The symbols the compiler
owns outright (traps, argument setup, the float-math operations) remain
[T-Extern]'s in every root, and the typed storage primitives, which lowering
replaces only where the standard library's `mem` declares them, are refused
everywhere else.

**A package is never its own dependency.** When the root being compiled is the
library named `std`, its own modules are the library: the embedded copy is not
also loaded, the root module is the prelude, and an import starting with `std`
names the root's own modules. `linea check std`, `linea test std`,
`linea test ./std` and `linea test /anywhere/std` all go through this one rule,
and the driver has no special case for any of them.

**The embedded copy is the default location of the `std` dependency**, and
nothing more. Every other root loads it beside itself, under its own directory
namespace, exactly as before.

**`std` at the start of an import path names the dependency.** A program's own
directory named `std` is part of that program (its tests run, its files
compile) but no import reaches it, because `std` always means the dependency.
Where an import through `std` finds no library module and the program has a
directory of that spelling, [M-Import] says that the program's directory
cannot be imported, so the programmer learns why the file they can see was not
found.

## Consequences

The library can be checked and tested from its directory with any spelling
from any working directory, and a program's directory named `std` is an
ordinary program. `linea test std` from a directory with no `std` beside it
now reports that no such directory exists, like any other missing root; the
library's own transcript names it by its path.

[M-Extern]'s trust boundary moves from a directory to a declaration in a
manifest, and any root can grant itself `extern` with one line. What a granted
root can declare is bounded by [T-ExternRuntime]: it can name only functions
the runtime provides, with the runtime's own signatures, so a grant cannot
declare `linea_close` with a second signature or reach a symbol that does not
exist. It can still call those functions directly, bypassing the ownership the
standard library wraps around them, which is the trust the grant expresses.
Which declaration *is* a recognised compiler primitive stays the standard
library's role, recorded as `Module.library`; the rules refusing a
compiler-owned symbol apply by symbol, in every root.

Diagnostics inside the library compiled from its directory quote the paths of
that directory; the embedded copy's diagnostics quote `std/…`.

## Alternatives considered

**Recognise the library directory by its path.** Embedding the absolute path
of the directory the compiler was built from and comparing a root's canonical
path with it cannot misfire on a user's directory, but it makes the library a
special location rather than a library, ties the binary to the checkout it was
built in, and answers "no" for every other worktree of the same sources.

**Canonicalise command-line spellings relative to the working directory**, so
that `./std` and `"$PWD"/std` read as `std`. It fixes those spellings from the
checkout and nowhere else, and keeps the directory-name rule it spells toward.

**Refuse a program directory named `std`.** Detecting it needs every
program's file list walked for that name on every compilation, and the
directory does no harm unless something imports it — which is where the
diagnostic now fires.

**Leave [M-Extern] keyed on the library.** The rule would then need the
directory rule this record removes, or a second marker meaning "this is the
library" beside `name`. Granting the capability in the manifest states the
trust where it is given.

## Open question

**Who may grant `extern` to a root.** Today any manifest, a program's or a
library's, can write `"extern": true`; the repository's only such manifest is
the standard library's. A package registry, a signature, or an allow-list in
the program that depends on a library are each possible answers, and none is
needed until a root other than `std` is distributed.
