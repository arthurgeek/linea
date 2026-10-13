# 32. A module is a directory, and the entry may be a file

Status: Accepted — 2026-07-27; import-path clause superseded by 0111

## Context

Stage 5 needed a boundary. Not for its own sake: the point of the stage is
sealing a representation, and a seal has to be relative to something. Whatever
that something is decides what "outside" means for every rule built on it
afterwards, so it was worth settling before the rules were written.

The candidates differed in where the fact lives. A file granularity puts it in
the filesystem and needs nothing declared. A package clause puts it in the
source. A manifest puts it in a third file. Each answer is cheap to implement
and expensive to change, because every later rule is phrased in terms of it.

## Decision

**A module is a directory.** Every `.lin` file directly inside it belongs to
it, sees every declaration in every other, and is not ordered relative to them.
Nothing in a file says which module it is in.

**Files are sorted by name before ids are handed out.** A directory listing's
order is the filesystem's business, and a program's meaning may not depend on
it. The conformance suite loads every multi-file case a second time with its
files reversed and compares the trees.

**A module is one syntax tree.** Ids run across a module's files rather than
restarting per file, and — since a compilation is one tree too — across its
modules. A module is a range of declarations within that tree. This is what
keeps every pass a walk over a representation: nothing downstream of the parser
knows that a module held more than one file, because in the language it does
not.

**The entry to a compilation may be a file or a directory.** A file is a module
of one file. This is not a convenience: `tests/enums/` holds roughly a hundred
unrelated single-file programs in one directory, and a directory-only rule
makes one module of them all, declaring a hundred `main`s.

**A path descends.** `import a.b` names the directory `a/b` beneath the
importing module's own; the dots are path separators, not a namespace. What an
import binds is the last element, or the alias where `as` gives one.

## Consequences

**The import graph is acyclic, and nothing checks it.** A path descends, so the
directory strictly lengthens along any chain of imports and no chain can return
to where it began. A cycle check was written, and then removed when a
conformance case built to exercise it turned out to be failing for a different
reason — it named a directory that was not there. The property is stated where
the resolution rule is. A path form that does not descend, of which `std` will
be the first, has to bring the check back with it.

**One directory is one module however many routes reach it.** `import a.b` and
an `import b` written inside `a` name the same module, so a name declared there
does not collide with itself.

**A position lifted out of the tree needs its file.** A `Span` is an offset into
one file's text, and a module holds several. Anything that carries a position
across the tree — a diagnostic's label, a type expectation travelling from the
declaration that imposed it into a body — carries a `Loc` instead. In one file
the difference is invisible; across two, a bare span lands at a plausible
offset in the wrong source, which is a diagnostic that is confidently wrong.

**A signature is read in the module that wrote it.** A callee's return type and
its parameters' types are looked up where they were declared, not where the
call is. Reading them in the caller's module finds nothing, and nothing is
poison — which is not a diagnosis. It spread silently and made every sealed
type look unsealed until a conformance case for the seal exposed it.

**A trap names the file it happened in.** A function's body cannot span files,
so the file is recorded per function rather than per instruction, which keeps a
span four bytes. The backend emits one path blob per file rather than one per
program.

## Alternatives considered

**A file is a module.** The simplest rule, and the one most languages with a
module system smaller than a package chose. What pushed Go and Odin to
directories is that a file boundary forces a choice between long files and
declaring everything mutually visible; associated declarations relieve most of
that pressure, and this language has them. What actually decided it was the
corpus: a hundred unrelated programs in one directory have to stay a hundred
programs, and only the file/directory asymmetry above gives that without a
special case for tests.

**A package clause in each file.** `package foo` at the top, as Go has. Puts
the fact in two places — the clause and the directory — that can disagree, and
the compiler then has to decide which wins and diagnose the other. The
directory already knows.

**A manifest listing a module's files.** Removes the ordering question by
naming an order, and adds a file that must be edited every time one is created.
The ordering question is better answered by making order irrelevant.

**`use`-style selection: `use a.b.{f, g}`.** Brings names in rather than
binding a namespace. Needs aliasing, collision rules between imported names and
local ones, and an unused-alias diagnostic distinct from an unused import.
Qualified access needs none of those: the only collision possible is between
two imports' last elements, and `as` resolves it.

**Modules as values.** `const m = @import("...")`, as Zig has. The most
expressive answer, and it needs compile-time evaluation, which the language
does not have and is not close to having. It was the reason files were briefly
going to be structs; scrapping that is what made a module a directory rather
than a declaration.
