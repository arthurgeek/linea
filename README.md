# Linea

Linea is a systems programming language with **mutable value semantics** and
**linear types**. Functions take arguments by value, by `inout` to mutate them
in place, or by `sink` to take ownership, and there are no aliased references.
Resources such as files, sockets and heap memory are linear, so forgetting to
close or free one is a compile error. Every heap allocation goes through an
allocator you pass in, and no operation has undefined behaviour.

```linea
import std.io

fn main() -> Result[UInt8, io.IoError] {
    let name = "Ada"
    io.println("Hello, {name}!")?
    .Ok(0)
}
```

Linea is unreleased and changes without notice.

## Get started

The Nix shell supplies Zig 0.16.0, MLIR and a C toolchain:

```sh
nix develop
zig build
export PATH="$PWD/zig-out/bin:$PATH"

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
