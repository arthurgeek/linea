# 109. Text, I/O and formatting have separate modules

Status: Accepted - 2026-09-02

## Context

The first output implementation placed `Str`, writers, descriptors, rendering
traits and decimal conversion in one `text` module. That made the module name
describe storage, transport and presentation at once. It also made a private
raw write possible only because output happened to share the module that seals
`Str`; keeping that arrangement would turn an implementation accident into the
public library structure.

The split must not enlarge the prelude. String syntax obliges `Str`, and
interpolation and failing entry points oblige `Display`; syntax does not oblige
`Writer`, `Debug`, descriptors or output conveniences. Compiler-generated test
and entry-point calls also need stable module ownership without making their
targets public.

## Decision

**Text representation, I/O transport and formatting policy are separate
standard-library modules.** `std.text` owns `Str`, UTF-8 operations and text
comparison. `std.io` owns `Writer`, `Descriptor`, `IoError`, standard streams
and output operations. `std.fmt` owns `Display`, `Debug`, decimal conversion and
rendering implementations.

`std.fmt` publicly re-exports `io.Writer`, so public rendering declarations can
name the writer capability through their own module's public surface. The
prelude remains the ordinary `std/std.lin` manifest and publishes only
`text.Str` and `fmt.Display` from these modules; `Debug` and `Writer` remain
explicit imports.

The runtime write declaration remains private to `std.text`. That module
exposes one `internal` `write_raw` operation so `std.io` can pass an opaque
`Str` to the runtime without exposing its address or length to another root.
Argument construction is likewise internal to `std.text` and reached explicitly
by `std.env`.

Generated entry-point calls name `io.report` and `io.ran`. These declarations
remain private: generated calls resolve by centralized module-and-name identity,
not by source visibility. The former `std.text` paths are removed rather than
re-exported.

## Consequences

Each public module has one subject: text values, transport, or presentation.
Moving or extending one does not make unrelated capabilities appear under its
name, and the prelude's semantic membership is unchanged.

Formatting and I/O form an allowed import ring: formatting is generic over
`Writer`, while output renders values through `Display`. Modules are registered
before imports are followed, so the ring adds no declaration-order exception.

Raw `Str` storage remains inaccessible outside its declaring module. The sole
cross-module operation is root-bounded, and program roots receive [M-Vis] if
they attempt to call it.

Qualified symbols and generated goldens change module identity. This is an
intentional source break in the unreleased library; callers import the new
owner rather than relying on compatibility aliases.

## Alternatives considered

**Keep one `std.text` module.** Rejected because a representation module would
continue owning descriptors, operating-system failures and presentation policy
for no semantic reason.

**Re-export every old path.** Rejected because compatibility aliases would keep
the accidental surface alive and give declarations two public owners before
the library has been released.

**Put `Writer` in `std.fmt`.** Rejected because a writer is a transport
capability implemented by descriptors and recorders. Formatting depends on it
but does not own it; the narrow public re-export is enough for formatting APIs.

**Expose raw `Str` accessors publicly.** Rejected because `Str` is opaque
precisely so a program cannot forge or inspect the address behind a view. One
root-internal write operation grants the needed cooperation without weakening
that invariant.
