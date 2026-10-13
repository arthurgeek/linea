# Linea

Linea is a systems programming language where resources are values the
compiler tracks. A file, a socket or a buffer that is never closed or freed is
a compile error, not a leak; no operation has undefined behaviour; and memory
comes from an allocator the program names.

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
