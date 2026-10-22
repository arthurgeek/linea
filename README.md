# Linea

What if memory bugs and resource leaks were impossible to express?

In Linea, resources are values with owners. When you release a resource, that value is consumed. You can't release it twice, and you can't keep using it afterwards:

#### Double free?

```linea
scores.release()
scores.release() // error[O-Move]: `scores` has already been moved
```

#### Use-after-free?

```linea
scores.release()
io.println("{scores.length()}")? // error[O-Move]: `scores` has already been moved
```

#### Resource leak?

```linea
fn worker() -> Result[(), io.IoError] {
    let scores: Vec[UInt64] = Vec.new()
    io.println("{scores.length()}")?
    .Ok(()) // error[O-Leak]: `scores` is still owned when this path leaves
}
```

These aren't runtime checks, address sanitizer warnings, or garbage collector sweeps. The compiler rejects these programs outright before emitting native code.

Because the first call consumes `scores`, it no longer exists in that scope. And because `scores` is a linear resource, abandoning it without settlement is a compile error. You can settle it explicitly on every path, or ensure clean exit with `defer scores.release()`.

---

## Two ideas: Linear Types & Mutable Value Semantics

Linea is a systems programming language built in Zig. It combines two foundational ideas from programming language research:

### 1. Linear Types (used exactly once)
Most values in Linea are ordinary—you copy and pass them freely. But types that manage resources can declare themselves `@linear`.

A linear value **must be consumed exactly once on every execution path**. You cannot duplicate it, you cannot reuse it after transfer, and you cannot silently forget to clean it up.

This principle extends beyond memory:
- **Buffers and collections** must be released.
- **Files and sockets** must be closed.
- **Database connections** must be returned to the pool.
- **Transactions** must be explicitly committed or rolled back.

If any branch exits without settling an owned resource, the compiler refuses the program.

### 2. Mutable Value Semantics (no pointer aliasing)
Shared mutable pointers make code notoriously difficult to reason about and parallelize.

Linea adopts **Mutable Value Semantics (MVS)**:
- Variables own their data. There are no implicit shared mutable references.
- In-place mutation is explicit at the signature with `inout`, and marked with `&` at the call site.
- Ownership transfer is explicit with `sink`.

```linea
import std.io

fn add_tip(inout bill: UInt64) {
    bill += bill / 10
}

fn main() -> Result[UInt8, io.IoError] {
    var bill = UInt64(40)
    add_tip(&bill)
    io.println("Total: {bill}")?
    .Ok(0)
}
```

You get the performance of in-place mutation without pointer aliasing bugs.

---

## What Linea promises

- **No undefined behaviour**: Every operation produces a defined result or is a diagnosed compile error. The compiler never optimises on the assumption of absent UB.
- **Explicit memory**: No garbage collector and no hidden allocations. Containers state their allocators, and memory comes from an allocator the caller chooses.
- **Zero-cost static enforcement**: Ownership and mutation rules are proven at compile time, compiling down to lean machine code via MLIR and LLVM.

Linea is unreleased and changes without notice.

## Get started

The Nix development shell supplies Zig 0.16.0, MLIR, and a C toolchain:

```sh
nix develop
zig build

linea init hello
linea run hello
linea test hello
```

## Featured examples

- [notes](examples/notes/main.lin): CLI note-taking app with subcommands, tabular rendering, and atomic JSON persistence.
- [guest-book](examples/guest-book/main.lin): full-stack web application combining SQLite, C FFI, HTTP routing, cookies, and HTML templating.
- [All examples](examples/README.md): complete programs from introductory scripts to network services.

## Learn

- [Learn Linea](docs/learn/README.md): the guide, one chapter per topic.
- [Standard library](std/README.md): modules, collections, I/O, and allocators.
- [Language definition](docs/linea-semantics.md): every rule by its diagnostic name.

## Contribute

Read [AGENTS.md](AGENTS.md) for how changes are made and verified, and the [ADRs](docs/adr/README.md) for the technical decisions behind the language.

## Licence

[Apache License 2.0](LICENSE).
