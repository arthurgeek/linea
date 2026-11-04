# 257. The driver keeps the checked standard library on disk

Status: Accepted — 2026-11-03.

## Context

Every `linea check`, `run`, `build` and `test` loads, resolves, type-checks
and ownership-checks the whole standard library before the program: about
0.19 s in a ReleaseFast compiler and 1.3 s in a Debug one, which is all of
`linea check` on a program that only returns zero. The answer depends on
nothing but the compiler, because the library is carried in the binary
(ADR 0171).

`loader.CheckedLibrary` already holds that answer in memory, and the
conformance runner and the language server resume programs from it
(`canResume` decides when one can). The command line started a fresh
compilation every time, so each command paid for the library again.

Keeping the answer between processes needs two things the in-memory session
did not: a byte form of everything a resumed compilation reads, and a place
to keep it with a key that changes whenever the answer could.

## Decision

**An encoding.** `driver/library_encoding.zig` writes a `CheckedLibrary` as
bytes and reads it back: the parsed library program, its file table and
interner, the expanded program and resolution, the resolver's continuation
rows and expanded interner, the typing and the checker's continuation rows,
and ownership's disposal plan. The encoding is `support/serial.zig`'s, derived
from the types: fields in declaration order with no padding, integers as
LEB128, slices as a length and their elements, and a hash map's entries in the
order of their encoded keys. It is therefore a function of the values alone,
and two checks of the library encode to the same bytes, which a test holds.
What the encoding cannot follow alone is named in one place, the encoding's
hooks: an interner's lookup map is rebuilt from its texts, the expanded
program's pointer to its source is the library's own program, and a typing's
fields that `retained_typing.attach` never reads are not written. Those
fields are listed once, as `retained_typing.unread_fields`, and both `attach`
and the encoding read the list, so a field the resumed check starts reading is
written by the encoding without a second edit.

**A key.** An entry is keyed by the SHA-256 of the running compiler's own
read-only image as it is mapped in memory, its code and constant data (the
standard library it carries included), and by
`library_encoding.format_version`. Those bytes change whenever the compiler's
code or its library does, and they are what decides the answer, so nothing
that changes the answer can leave the key alone. They are read from the
process, not from the file at the executable's path: a compiler installed
over that path while an older one starts would otherwise have the older one
write its library under the newer one's key. On a platform whose loaded image
the compiler does not read (it reads macOS's `__TEXT` and Linux's read-only
`PT_LOAD` segments) there is no key and the cache is not used. The entry
records its key in its header as well as its name.

**A place.** The cache is a directory beneath the user's home,
`$HOME/.linea-cache`, or the directory `LINEA_CACHE_DIR` names; set to the
empty string, `LINEA_CACHE_DIR` turns the cache off. Without `HOME` or with
the cache off, a command compiles exactly as it did before. The cache is on for every
compiler, a Debug one included, where it pays most: on a Debug compiler
`linea check` of `hello.lin` takes 1.77 s with the cache off, 2.49 s cold
and 0.73 s warm, and of `json_inventory.lin` 5.34 s, 7.61 s and 2.55 s. The
build points `LINEA_CACHE_DIR` at one directory in its own cache
(`.zig-cache/linea-cache`, or `-Dlibrary-cache=PATH`, `off` for none) for
every `linea` its steps run and for the conformance runner, whose own checked
library is read from and written to the same entries; transcripts share it
too. Repeated `zig build test`, `guide` and `example-tests` runs, and their
parallel workers, read what the first wrote, and nothing is written to the
user's home.

**One writer per entry.** A command missing an entry takes an advisory lock
on the entry's `NAME.lock` before it checks the library; another missing the
same entry says once that it is waiting, where standard error is a terminal, reads the entry
when it appears, and after a minute checks the library itself without the
cache. The system releases the lock when its holder exits however it exits,
so no identifier is read and no lock is taken over: a lock file left behind
holds no command.

**Damage is a miss.** An entry that is missing, cut short, written by another
compiler or format, or whose encoding does not hash to the XxHash3 its header
records, is checked again and rewritten. The encoding's hash is read on every
command and only detects damage, so it is a fast checksum: the entry is
trusted because only its user writes the directory, not because of its hash.
A decoder never reads past its input and never builds an enum value from a
number naming none. A write goes to `NAME.PID.tmp`, renamed over the entry,
so concurrent commands each see a whole entry or none. Writing an entry
keeps the sixty-four most recently read or written, an entry's time being
touched when it is read, and removes the rest, so rebuilding the compiler
does not grow the directory without bound; the corpus's cases import some
fifty-five sets of modules, about 21 MB each. It also removes the temporary
file an interrupted write left an hour on, and the lock of an entry that is
gone where no command holds it; it removes nothing else in the directory.

**A cache that cannot be written is not used.** The entry's lock is created
before the library is checked; where it cannot be, the command compiles as it
would without a cache rather than checking every library module only to keep
nothing.

**A library per set of modules.** A checked library holds the prelude's
closure and the library modules a program's own imports reach, directly or
through one another: exactly what a fresh load of that program loads. A
program resumes only from such a library (`canResume` refuses one holding a
module the program's load would not reach), because a module it does not
load would show it names, members and implementations a fresh check does
not see, and change what the check reports. The entry is keyed by that list
of modules as well as by the compiler, so programs importing the same
modules share one entry. A resumed check holds every declaration of those
modules, and the passes that continue from it do not walk them again:
[T-PolyRec] keeps the library's own verdict for a library call unless a cycle
through it passes through a declaration the program adds, and the
complete-template refill writes only the instantiations the program minted.

**Resuming is decided before reading.** `canResume` refuses an application
holding a closure, a `_linea_trait_` identifier, or a file named as a
generated one (`linea-derive-N.lin`), which `resolve.applicationMayResume`
reads from the application's own syntax. The driver asks it of the
application loaded alone (`loader.resumableLibraryOf`), which also names the
library modules its imports reach, before it hashes the compiler or reads an
entry, so a program that cannot resume pays nothing for the cache.

**The driver owns it.** No pass gains state: the driver reads or builds a
`CheckedLibrary` before loading the program, and resumes from it through the
same `CheckedLibrary.loadFromDisk`, `checkProgram` and `checkWhole` the other
sessions use, so a command line, the runner and the editor resume one way.

## Consequences

- A warm command skips checking the library wherever `canResume` admits the
  program. A program `canResume` refuses still loads and checks the library
  afresh. Of the 51 roots under `examples/`, 32 resume; the other 19 each
  hold a closure of their own.
- Measured on a ReleaseFast compiler, best of seven, `linea check` takes
  0.076 s warm for `hello.lin` against 0.158 s with the cache off, 0.226 s
  against 0.434 s for `json_inventory.lin`, and 0.686 s against 1.103 s for
  `http-json-echo`; `linea build` of `http-json-echo` takes 4.47 s against
  4.92 s. An entry holds 19 to 45 MB, as many modules as the program's
  imports reach. A program that cannot resume reads its own files twice and
  nothing else: `prime_sieve.lin` checks in 0.159 s against 0.157 s with the
  cache off.
- On a Debug compiler, with the build's shared cache: `zig build guide` takes
  181 s with it off, 113 s cold and 112 s warm (its programs share entries
  within one run, so cold already reads most of them); `zig build
  example-tests` 65 s, 63 s and 42 s; and `zig build conformance --
  tests/traits` 99 s, 101 s and 93 s, since the runner already resumes
  every case in its own process and the cache saves it only the library
  checks it makes once per run.
- The first command for a set of modules after the compiler changes pays for
  checking those modules, encoding them and writing the entry: 0.09 s more
  for `hello.lin` and 0.70 s more for `http-json-echo` on a ReleaseFast
  compiler.
- Hashing the loaded image costs a pass over the compiler's code and constant
  data in memory on every command that can resume.
- An entry is read back only by the binary that wrote it, so the encoding
  needs no compatibility across versions and carries none: a change to any
  encoded type raises nothing by hand, because the binary, and so the key,
  changes with it. `format_version` covers a change to the header or the
  encoding's rules that leaves the types alone.
- The cache trusts what it decodes once the digest matches. A directory
  another user can write could hand the compiler a forged library; the
  default lives in the user's own home for that reason, and a
  `LINEA_CACHE_DIR` must name a directory only its user writes.

## Alternatives considered

**Library reachability facts recorded in the entry.** [T-PolyRec] could keep,
per library call, the declarations its cycle query reached, and a resumed
check could walk only from the program's calls into those facts. The rule a
resumed check needs is narrower: a library call's verdict changes only where
the program closes a cycle through it, which two walks over the call graph
the check builds anyway answer, linear in its calls, with nothing more to
encode or keep consistent with the library's typing.

**One library holding every module.** One entry would serve every program,
but a program resumed from it sees modules its fresh load never loads:
`UInt8.from_path` reached `std.fs`'s implementation instead of naming
nothing, and helps offered `import std.http` to programs that cannot see
it. A resumed check must report what a fresh one reports.

**The prelude's closure as the checked library.** A smaller entry, but most
of the roots under `examples/` import a module outside it, `hello` included,
and none of those resumes.

**A project-local `.linea-cache/` beside the program's manifest.** The entry
is the same for every project a compiler builds, so a project-local cache
pays the cold check once per project per compiler, and a loose file with no
manifest has no project root to put one in: the cache would be written beside
whatever directory a file was named in, the corpus's and the examples'
included. A per-project cache earns its place for answers that depend on the
project, such as compiled objects; the standard library's does not.

**A build identifier computed when the compiler is built.** A hash of the
compiler's sources, the library and the build options, embedded through
`build_options`, costs nothing at run time. It is only as complete as the list
of inputs the build script hashes: an input left out, such as the Zig version
or an optimisation flag, leaves a stale entry answering for a compiler it was
not written by. The binary's own bytes have no such list.

**The SHA-256 of the file at the executable's path.** What the compiler
first used. It reads a file that may no longer be the running compiler: moving
another binary over the path while a compiler started wrote that compiler's
library under the other binary's key.

**The executable's size and modification time.** Cheaper than a hash, and
wrong whenever a rebuild keeps the size and a copy keeps the time.

**The platform cache directory** (`~/Library/Caches` on macOS,
`$XDG_CACHE_HOME` on Linux). One more rule per platform for a directory a
person names and deletes by hand; `LINEA_CACHE_DIR` places it anywhere.

**A temporary directory.** Shared between users on most systems, so a
directory another user created first could hold a forged entry.

**Encoding only what a resumed compilation reads, by hand.** A writer and a
reader per table is two statements of each type that drift from the type; a
derived encoding follows the types, and its hooks name the exceptions.
