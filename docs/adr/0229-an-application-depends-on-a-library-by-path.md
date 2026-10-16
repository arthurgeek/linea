# 229. An application depends on a library by path

Status: Accepted — 2026-10-15. Extends
[0096](0096-a-root-is-a-program-or-a-library.md),
[0108](0108-an-internal-name-stops-at-its-root.md),
[0111](0111-import-paths-are-root-relative.md) and
[0171](0171-the-standard-library-is-an-ordinary-library.md).

## Context

A root could be a library ([0096](0096-a-root-is-a-program-or-a-library.md)),
but nothing could use one except the standard library. The manifest had four
keys (`source`, `kind`, `name`, `extern`) and none named a dependency. A
library directory placed inside an application with its own
`{ "kind": "library" }` manifest was loaded as a module of the application's
root, so the application could call the library's `internal` functions, which
[0108](0108-an-internal-name-stops-at-its-root.md) reserves to the library's own
root.

The groundwork was already in place. `RootId` was documented as covering "the
primary root, the standard library and, in future, dependency libraries".
0108 separated root identity from the standard library's authority, and
`Program.importRoute` already refused a route into another root unless the
target was the standard library.

The first library meant to be used this way is a `sqlite` wrapper granted
`extern`, which a guest-book program depends on.

## Decision

**A manifest names the libraries its root depends on, each by the name its
imports start with and the directory holding the library's manifest.**

```json
{
  "dependencies": {
    "sqlite": { "path": "../sqlite", "extern": true },
    "shapes": { "path": "libs/shapes" }
  }
}
```

1. **The name is the import's first element.** `import sqlite` reaches the
   library's root module and `import sqlite.statement` a directory beneath its
   source. The library's own manifest says `"kind": "library"` and gives the
   same `"name"`, so one library has one name throughout a compilation. `std`
   is not a dependency name. A directory of the importing root spelled like a
   dependency is not what an import reaches.
2. **`path` is relative to the manifest that writes it.** A library is
   identified by the directory it sits in as the filesystem resolves it, so an
   absolute path, a relative one and one through a symbolic link name one
   library. A load from memory has only the spelling, and uses it. The
   library's `source` key is honoured as any root's is, and names a directory
   inside the one holding the library's manifest that holds no other root.
3. **A dependency is a root of its own.** Its `internal` declarations stay
   inside it, in both directions and between sibling dependencies. It may name
   dependencies of its own, which its consumer reaches only by naming them too,
   so an application never relies on what a library happens to use. An
   import's first element is answered from the importing root's own manifest
   alone, so a library's choice of dependencies never hides a module of its
   consumer, or the other way round. A library
   two manifests name, identified by its directory, is one root, so a type it
   declares is one type wherever it is named.
4. **A directory holding a manifest is never a module of the root above it.**
   The walk that lists a root's files stops there. An import reaching such a
   directory without naming it is [M-Import].
5. **The graph is read before any module is loaded**, since the first import
   may name a dependency. Dependency roots take `RootId`s from 2, depth first
   over each manifest's names in order, so identities do not depend on the
   order a manifest happens to write them in. `Program.roots` records each
   root's name, source directory, root module and dependencies.
6. **A dependency is compiled from source with its consumer**, as the standard
   library is. `linea check` reports errors in a dependency's files, and
   `linea test` runs only the root's own tests.
7. **A refused entry is [M-Dependency], reported in the manifest that writes
   it**, at the entry's name or its `path`, and left out of the compilation.
   An entry is refused for any of these reasons:
   - its path holds no manifest;
   - the manifest there is not a library's;
   - its name is absent or different from the entry's;
   - it is `std`, or is written twice in one manifest;
   - it already names a library in another directory;
   - it closes a cycle;
   - its `source` leaves the library's directory or holds another root;
   - only one side grants `extern`.

   An import naming a refused dependency reports nothing further.

**`extern` needs the library's grant and the program's consent.** The library's
own manifest grants it, as [M-Extern] requires of any root, and every manifest
naming the library consents with `"extern": true` in its entry. The primary
root's manifest consents too, however deep in the graph the library sits: the
program links every root's `extern` declarations, so it names each such
library under `dependencies` with `"extern": true`, and the entry through which
it reaches an unconsented one is refused. A grant without consent is refused,
since trust would otherwise be granted by the code being trusted, or by a
library on the program's behalf. Consent to a library whose manifest grants
nothing is refused as well, since it says nothing.

**`export` publishes the root being built.** In a dependency an `export`
function is an ordinary `pub` function to the program that depends on it. It
is not published from that program's artefact, and [M-Export]'s rules are not
asked of it, so a library with a C interface can still be a dependency.

### A dependency's `export` is not exported

Only the program's own `export`s reach C. A library author who writes
`pub export fn square(...)` and expects the symbol `square` in every program
that uses the library gets none: the library's `export` is published when the
library itself is built (`linea build` on the library makes an object that
exports it), and a program that depends on the library calls it as a Linea
function.

The reason is that the artefact a program builds has one owner of its C
interface, and that owner is the program. If every dependency's `export`
reached C, two libraries exporting the same name would collide in one
artefact, and a program would carry a C interface it never wrote and cannot
see in its own source. A library that wants to offer C symbols through a
program says so in the program, which writes its own `export` wrapping the
library's function. This is written down here, in the semantics beside
[M-Export], and in the guide, because nothing in the compiler's output says
it: the program compiles and runs, and the symbol is simply absent.

**[M-Entry] holds for every library root**, a dependency's root module
included.

## Consequences

- An application imports a library beside it or inside it, and the library's
  `internal` boundary holds.
- `Program.inLibraryRoot` answers whether a module belongs to a library root
  (the standard library, a dependency, or a primary root built as a library)
  for the rules a library is held to.
- The language server reads a dependency's files through `pathsOfRoot` as the
  command line does. Editing a file inside a dependency analyses that library's
  own root, its nearest manifest.
- The conformance runner keeps every manifest beneath a case, so a case holds
  its libraries in subdirectories.
- Two corpus cases carried a `{}` manifest inside a module directory. They are
  deleted, since such a directory is now a root.

## Alternatives considered

**A list of paths, named by each library's `name`.** One fewer place to write
the name, but nothing in the consumer's manifest would say which import name a
path provides. The keyed object reads like the imports it enables and leaves
room for the consent flag.

**Name a dependency by its directory.** Renaming a directory would rename every
import, and 0171 already gave a library its `name`.

**Identify a library by its spelled path.** A load from memory and one from
disk would agree, but one library named by an absolute path in one manifest
and a relative one in another would be two libraries with one name, and a
cycle back to the program would be found or missed depending on the directory
the command ran in.

**Consent to `extern` only where a library is named.** A library could consent
on the program's behalf to a dependency of its own, and the program would link
`extern` declarations nothing it wrote agreed to.

**Let the consumer choose its own name for a library.** Two names for one
library would print two spellings of one type in diagnostics. It can be added
if a need appears.

**Discover any nested manifest as a dependency.** An import's meaning would
change when a directory gained a manifest, and there would be nowhere to
consent to `extern`.

**Keep a nested library in its consumer's root.** That is the leak described
above, and 0108 already rejected it: a program and its dependencies share a
compilation while remaining separate publication boundaries.

**Reach a dependency's dependencies transitively.** It couples an application
to choices its dependencies are free to change.

**Per-library objects linked together.** A generic function has no symbol until
something instantiates it ([0096](0096-a-root-is-a-program-or-a-library.md)),
so a library would ship its source anyway; one compilation is what the standard
library already gets.

## Open

Linking a C library and passing anything but integers through `extern` belong to
ADR 0228. A dependency granted `extern` is subject to whatever 0228 admits, as a
primary root is. 0228's `"link"` key sits on the manifest of the root that
declares the externs, which is the library's own. The graph read here already
visits that manifest, and every root in it is linked into one artefact. 0228
therefore records the key on the root's `RootFacts` row, and its link step
collects the lists over `Program.roots` into the program that links them.

Versions, a lock file and a registry are not decided: paths only, with entry
objects that leave room for more keys.
