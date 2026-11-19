# 294. A directory walk is a lazy, linear iterator with bounded open directories

Status: Accepted — 2026-11-18.

## Context

`std.fs` could read, write, replace and remove one file at a time, and had no
way to list a directory. A disk-usage report, a file finder or a tool that
processes every source file of a project had to be told each path. The
standard library needed one way to visit a tree that fits the language's
existing shapes: a `for` walks an `Iterator`, a value holding operating-system
resources is linear and settled explicitly, an allocating function has an
`_in` form, and a failure is a value the caller sees.

Seven choices shape such a walk, and each has an answer that common libraries
disagree on: the order of entries, what happens at a symbolic link, what an
error in the middle does, how a caller limits or prunes the walk, which
metadata an entry carries and at what cost, how long an entry's path lives, and
how many directories the walk keeps open on a deep tree.

## Decision

### 1. `fs.Walk` is an `Iterator` and is linear

`fs.Walk.open(root, max_depth:, follow_symlinks:, max_open:)` and
`Walk.open_in(allocator, root, ...)` open the root and answer a `Walk[A]`, or
an `FsError` when the root cannot be opened. The walk implements `Iterator`
with `Item = Result[Entry[A], WalkError[A]]`, so a program walks it with
`for found in &walk` and settles it afterwards with `close()`, which reports
the first directory that failed to close, or `release()`, which drops that
failure. It is linear because it holds directory streams: a walk abandoned
without settlement would leak descriptors. `io.Close` is implemented for
generic code.

The walk is lazy: building it reads nothing beyond the root's open, each
`next` reads one directory entry, and a directory it reports is entered at the
following `next`. A walk is pre-order, a directory before what it holds, and
the root itself is not reported: the caller named it.

### 2. Entries come in directory order

Entries come in the order the file system lists them. A caller that needs an
order collects what it wants and sorts it, as the guide's and the example's
programs do.

### 3. Symbolic links are reported, not followed, unless asked

By default a symbolic link is an entry of kind `Symlink` and is never
entered, and metadata describes the link itself (`AT_SYMLINK_NOFOLLOW`).
A child directory is opened with `O_NOFOLLOW` relative to its parent's open
stream, so a directory swapped for a link between the listing and the open is
refused rather than followed out of the tree. With `follow_symlinks: true`
metadata describes what a link names, a link to a directory is entered, and a
dangling link is a per-entry error. The root is followed either way.

Every directory entered is compared, by device and inode, with each directory
the walk is inside; a match is reported as `WalkCause.Loop` and not entered.
The identity compared is read from the directory opened (one `fstat` of its
stream), not from the listing, so a link swapped between the two cannot lead
the walk back unseen. The check costs one `fstat` and one comparison per level
of depth for each directory entered.
It applies without following links too, where only a bind mount can make a
directory its own descendant.

### 4. An error is reported for its entry and the walk goes on

An entry whose metadata cannot be read, a directory that cannot be opened or
read, a directory whose close fails, a loop, and a refused allocation are each
yielded as one `Err(WalkError)` naming the path (owned, empty only when the
path's own storage was refused) and a `WalkCause` (`Io(io.IoError)` with the
operation `Open`, `Read`, `Metadata` or `Close`; `Loop`; `Changed`, for a
directory the walk had to find again by its name and found replaced or
gone; or `Allocation`).
The entry or the directory's remaining entries are skipped and the next `next`
continues with the rest of the tree. A caller that wants to stop at the first
error stops its `for` there and settles the walk.

### 5. Depth is a limit; pruning is a call between steps

`max_depth` bounds how far below the root entries are reported (1 reports the
root's own entries, and 0 reports nothing); a directory at the limit is
reported and not entered.
`skip_children()`, called after `next` answers a directory and before the next
call, leaves that directory out. Because the body of a lent `for` cannot name
the walk, a program that prunes drives the walk with `next` in a `loop`.

### 6. One `stat` per entry gives kind, size, permissions and modified time

Each entry carries its kind, size in bytes, permission bits (`mode & 07777`),
modification time as `Option[time.Timestamp]` (None outside the years a
timestamp holds), and its depth. The runtime reads them with one `fstatat`
relative to the open directory for every entry, in the same call that reads
the entry, so an entry's metadata is a snapshot taken when it was listed.

### 7. An entry owns its path

An entry's path, the root joined to each name below it, is a
`Vec[UInt8, A]` the entry owns, from the walk's allocator, so it outlives the
step that found it: a program can keep the largest files it has seen, or sort
paths after the walk. `entry.path()` and `entry.name()` borrow it as an
`fs.Path`. Over an arena an entry owes nothing and is dropped; over the system
allocator it is released.

### 8. At most `max_open` directories stay open between steps

A walk holds its root and the directories nearest the current one open, at
most `max_open` of them between steps (16 by default; 0 and 1 are taken as 2,
the root and the current directory). Entering a directory when that many are
open makes room: the shallowest open directory below the root has the rest of
its entries read into memory, with their metadata, and is closed. So the open
directories slide down with the walk, every directory is opened by its own
name with `openat` inside its parent, which is open, and going down a chain
costs one open per level however deep it is.

Coming back up, the walk leaves an open directory whose parent was read into
memory. Before closing it, it opens `..` of it, which no link can stand in
for, and keeps that descriptor as the parent's when it has the device and
inode the walk recorded for the parent; the parent's entries still come from
memory, and the directories it holds are opened inside it. The count of open
descriptors does not change, and making room closes such a descriptor first
when it is the shallowest.

Only when that is not possible, because the directory left was moved out of
its parent, does the walk find a directory by name: one runtime call,
`linea_dir_reopen`, opens each directory from the deepest one still open down
to the parent again, one name at a time with `openat` relative to the one
above (`O_NOFOLLOW` unless links are followed), as a bare descriptor held to
the device and inode the walk recorded when it entered that directory, and
makes a stream only of the directory being entered. A directory found missing,
not a directory, a link, or another directory under the same name has changed
under the walk: it is reported once, by its own path, as `WalkCause.Changed`,
and the walk leaves it and everything below it, so none of its remaining
entries is reported. A failure to open the directory being entered is that
directory's own `Io` error.

Below the root the walk therefore opens no path of more than one name: nothing
above can redirect it, and no path is too long for the system to open. A walk
follows the directories it entered, not their names: a directory moved while
the walk is inside it is walked where it went. During a step at most two
descriptors beyond `max_open` are open; a walk of a 500-deep chain needs
`max_open` plus one beyond the three standard descriptors. A walk costs one
`openat` per directory entered and one more per directory left whose parent
was read into memory: a 500-deep chain takes about 0.1 s and a 500-deep chain
with a second directory at every level about 0.2 s, at `max_open` 2 or 16, on
an Apple-silicon Mac (a whole-chain reopen per directory took 9 s and 17 s).
A listing is kept until the walk leaves its directory, so memory past the
bound grows with the listings of the directories read into memory that the
walk is inside.

### 9. The runtime exposes directory streams; the walk is Linea

The runtime gains `linea_dir_open`, `linea_dir_open_at`, `linea_dir_next`,
`linea_dir_reopen`, `linea_dir_open_up`, `linea_dir_identity` and
`linea_dir_close` over
`opendir`-style streams
(`openat` with `O_DIRECTORY` and `fdopendir`), and `linea_make_dir_at`,
`linea_remove_dir_at` and `linea_symlink_at`, which `fs.create_dir`,
`fs.remove_dir` and `fs.create_symlink` call. A stream's handle crosses as a
number a linear `mem.DirStream` keeps (`Held.stream` in the symbol table), and
a record crosses as six 64-bit words and the name written into a buffer the
walk owns. Order, depth, pruning, loops, errors and the open bound are Linea
code in `std/fs/walk.lin`, held to the language's checks.

A walk inside `io.Simulation.run` reads the real file system: the simulation
simulates clocks and sockets, not files, and a walk makes the same blocking
calls there as `fs.File` does.

## Consequences

- A tree is visited in a `for`, with each failure handled where it occurs and
  no callback.
- An entry costs one allocation for its path and a directory entered one more
  for the copy the walk keeps, plus one `stat` per entry whether or not the
  caller reads the metadata.
- Output that depends on order needs a sort, which a program writes
  explicitly.
- A tree deeper than `max_open` costs the memory of the listings of the
  directories read into memory that the walk is inside, and nothing more per
  level than a shallow one.
- A directory removed, renamed or added to during a walk may be reported or
  missed; the walk answers what each read saw.

## Alternatives considered

**Sorted entries.** Sorting needs a directory's whole listing before its first
entry, so memory grows with the largest directory and the first entry waits
for it, which is what laziness is for. A sorted walk is a collect and a sort
the caller writes.

**Following links by default, as Python's `os.walk(followlinks=True)` or
`find -L` do.** A followed link can lead out of the tree the caller named and
into a cycle; reporting it costs nothing and following it is one argument.

**Stopping at the first error, as Go's `filepath.WalkDir` does by default.**
A single unreadable directory in a home directory would end every report;
yielding the error lets the caller choose either behaviour with no option.

**Lazy metadata, as Rust's `walkdir::DirEntry::metadata`.** It needs the
parent directory's stream when the caller asks, so the entry would borrow the
walk, which an `Iterator`'s item cannot (`carries(.Some: self)` keeps the
walk's dependencies, not an observation of the walk). Reading the kind from
`d_type` alone does not avoid the `stat` either: some file systems answer
`DT_UNKNOWN`, and a size is what the common tasks ask for.

**A borrowed path, reused between steps, as Zig's `Dir.Walker` does.** It
saves an allocation per entry, but the same rule refuses an item that observes
the walk's buffer, and a program that keeps an entry would copy it anyway.

**A callback walk (`walk(root, |entry| ...)`).** It cannot be composed with
iterator adapters, and a callback that fails or stops early needs a protocol
of its own; an `Iterator` already has both.

**An unbounded stack of open directories.** A tree a few thousand directories
deep exhausts the descriptor limit; bounding it follows Rust's `walkdir`
(`max_open`, 10 there), which also reads the overflowing directory into
memory.

**Reading the directory being entered into memory at the bound, and opening
what it holds again by name from the deepest open directory.** It keeps the
directories near the root open, which the walk no longer needs, and makes
every directory entered past the bound cost one open per level between it and
the deepest open one: a 500-deep chain took 9 s and the same chain with a
second directory at every level 17 s, against 0.1 s and 0.2 s when the open
directories slide down with the walk.

**Opening a directory below the bound by its whole path.** It is one call,
but `O_NOFOLLOW` covers only the last name, so a directory above swapped for a
link during the walk would be followed out of the tree, and a path longer than
`PATH_MAX` cannot be opened at all. `openat2` with `RESOLVE_BENEATH` and
`RESOLVE_NO_SYMLINKS` would close the first on Linux alone, and neither
platform lifts the second.

**Reopening a closed directory and seeking back with `telldir`/`seekdir`.**
POSIX leaves a cookie's meaning after reopening unspecified, and a directory
changed in between would repeat or skip entries silently.

**Reporting the root as the first entry, as `walkdir` and `find` do.** The
caller already has the root's path; reporting it would need a `stat` of its
own and an entry every report filters out.
