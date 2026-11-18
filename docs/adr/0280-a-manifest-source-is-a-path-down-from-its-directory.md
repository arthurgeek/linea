# 280. A manifest's source is a path down from its directory

Status: Accepted — 2026-11-17; extends 0075 and 0229

## Context

A manifest's `source` names the directory its root's modules sit in, relative
to the manifest (0075), and a library's `source` is honoured as any root's is
(0229). Three readers turned the spelling into a directory, each its own way:

- the loader, for the root a command or an editor names, joined the spelling
  to the manifest's directory and kept every `..`, leaving the filesystem to
  resolve it;
- the loader, for a library a manifest depends on, resolved the spelling,
  removing each `..` with the component before it;
- the build's check of which example files a root reaches resolved it too.

The refusal they shared only stopped a `source` that left the manifest's
directory. One that climbed out and back in, `src/../lib`, was accepted, and
it is where the readings part. Where `src` is a symbolic link, the filesystem
finds `lib` beside the link's target, and the spelling names `lib` beside the
manifest: the same directory loaded as a program and as a library read
different files. Without a link, a file the editor opened is spelled
`p/lib/x.lin`, which the kept spelling `p/src/../lib` does not contain, so the
file was analysed as a program of its own and lost its manifest.

## Decision

**A `source` is a path down from the manifest's directory: not absolute, and
with no `..` component.** Such a path names one directory whether its spelling
or the filesystem resolves it, so the readers cannot disagree.

**One routine spells it.** `manifest_source.directory` joins each component of
the `source` beneath the manifest's directory, `.` and empty components taken
out. The loader's program root, its libraries and the build's example check
all read it, and the build keeps its own membership check over the example
entries, which is what that gate exists to compare against.

A `source` of another shape is refused as before: a command stops before
anything is checked, and a dependency's is [M-Dependency] at the entry naming
it.

## Alternatives considered

**Resolve `..` by spelling everywhere.** The library reading already did this,
and a load from memory has only the spelling. It changes what a path means on
disk wherever a component is a symbolic link, so a program read from disk
would hold files the filesystem does not put in that directory.

**Resolve through the filesystem everywhere.** Real paths would agree on disk,
but a load from memory, which an editor and the conformance runner build, has
no filesystem to ask, so the two kinds of load would name directories
differently.

**Keep `..` and refuse only a path that leaves.** This is the rule that let the
readings part; no reader can say which directory such a path names without
choosing one of the two above.
