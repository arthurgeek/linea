# Linea

Linea is a systems programming language with **mutable value semantics** and
**linear types**. Functions take arguments by value, by `inout` to mutate them
in place, or by `sink` to take ownership, and there are no aliased references.
Resources such as files, sockets and heap memory are linear, so forgetting to
close or free one is a compile error. Every heap allocation goes through an
allocator you pass in, and no operation has undefined behaviour.

A function changes its caller's value only through an `inout` parameter, and the
call marks it with `&`:

```linea
import std.io

fn add_tip(inout bill: UInt64) {
    bill += bill / 10
}

fn main() -> Result[UInt8, io.IoError] {
    var bill = UInt64(40)
    add_tip(&bill)
    io.println("{bill}")?
    .Ok(0)
}
```

```text
44
```

Heap memory is a linear value: it is freed exactly once, on every path, so
memory leaks, double frees and use after free are compile errors. This program
frees `scores` at the end:

```linea
import std.io

fn main() -> Result[UInt8, io.IoError] {
    let scores: Vec[UInt64] = Vec.new()
    io.println("{scores.length()} scores")?
    scores.release()
    .Ok(0)
}
```

A memory leak: `?` returns early when printing fails, and `scores` is never
freed.

```text
error[O-Leak]: `scores` (a linear `Vec[UInt64, mem.SystemAllocator]`) is still owned when this path leaves
 --> scores.lin:5:43
  |
4 |     let scores: Vec[UInt64] = Vec.new()
  |         ------ acquired here
5 |     io.println("{scores.length()} scores")?
  |                                           ^ still owned here
  |
  = help: settle it first with `scores.release()`
```

`defer scores.release()` frees it on every path, the early return included:

```linea
    let scores: Vec[UInt64] = Vec.new()
    defer scores.release()
    io.println("{scores.length()} scores")?
```

A double free:

```linea
    let scores: Vec[UInt64] = Vec.new()
    scores.release()
    scores.release()
```

```text
error[O-Move]: `scores` has already been moved
 --> scores.lin:6:5
  |
5 |     scores.release()
  |     ------ it was taken here
6 |     scores.release()
  |     ^^^^^^ it was already taken, and a value is taken once
```

A use after free:

```linea
    let scores: Vec[UInt64] = Vec.new()
    scores.release()
    io.println("{scores.length()} scores")?
```

```text
error[O-Move]: `scores` has already been moved
 --> scores.lin:6:18
  |
5 |     scores.release()
  |     ------ it was taken here
6 |     io.println("{scores.length()} scores")?
  |                  ^^^^^^ it was already taken, and a value is taken once
```

Files, sockets and connections follow the same rule with `close()`.

Linea is unreleased and changes without notice.

## Get started

The Nix shell supplies Zig 0.16.0, MLIR and a C toolchain:

```sh
nix develop
zig build

linea init hello
linea run hello
linea test hello
```

## Learn

- [Learn Linea](docs/learn/README.md): the guide, one chapter per topic.
- [Examples](examples/README.md): complete programs in reading order, from a greeting to an HTTP JSON
  service.
- [Standard library](std/README.md): common tasks and the APIs that do them.
- [Language definition](docs/linea-semantics.md): every rule, by the name its
  diagnostics print.

## Contribute

Read [AGENTS.md](AGENTS.md) for how changes are made and verified, and the
[decision records](docs/adr/README.md) for why the language is the way it is.

## Licence

[Apache License 2.0](LICENSE).
