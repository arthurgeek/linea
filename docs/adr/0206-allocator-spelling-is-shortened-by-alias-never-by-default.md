# 206. Allocator spelling is shortened by an alias, never by a default type argument

Status: Superseded by
[0215](0215-a-type-parameter-may-default-its-argument.md) - 2026-10-07.
Accepted 2026-10-05; records a decision taken on 2026-09-29. The
application-facing alias module was Proposed and never built.
Extends [0098](0098-a-container-names-its-allocator-in-its-type.md) and
[0194](0194-an-alias-names-a-type-that-exists.md).
Extended by
[0211](0211-a-generic-alias-heads-a-path-and-the-call-settles-its-parameters.md),
which lets a generic alias head a path.

## Context

[0098](0098-a-container-names-its-allocator-in-its-type.md) made the allocator
a type parameter of every container that allocates, and accepted the
propagation cost "rather than argued away". Its alternatives list the concrete
`Vec[T]` over the system allocator and "leave it open". It never weighs a
default type argument, so the rule that Linea has none was, until this record,
written down nowhere: it existed as a ruling on 2026-09-29, when the
promise of default type arguments (an undefined item in the HTTP design and
in [0154](0154-sockets-and-http-follow-go.md)) was removed from both with the
reason "don't spend language complexity to eliminate ceremony that carries an
ownership proof".

The cost is real. A program that uses one allocator writes
`Vec[Str, mem.SystemAllocator]` in fields, parameters and annotations, and
22 of the 43 examples mention an allocator. The alternatives for shortening it
are a default (`Vec[T, A = SystemAllocator]`, as Rust ships), a standard-library
alias, and a file-local alias.

## Decision

**No type parameter has a default argument. A program shortens a written
allocator with an alias.**

```linea
alias Basket = Vec[Str, mem.SystemAllocator]
alias SysVec[T] = Vec[T, mem.SystemAllocator]
```

An alias is the same type under another name
([0194](0194-an-alias-names-a-type-that-exists.md)), so nothing converts and
nothing is new in a diagnostic except that it prints the expanded type.
Construction through the alias (`SysVec.open(...)`) is part of the idiom; it works because
a generic alias may be the head of a call.

The proof an allocator argument carries is already visible at the value:
construction names it (`Vec.open(mem.system())`), and
[0095](0095-the-system-allocator-is-named-rather-than-received.md) says
restricting who names the system allocator buys auditability, not memory
safety. The decision is not that the type-level repetition is a proof; it is
that what a default would hide is a choice a library should not make quietly.

## Consequences

- No resolver, checker, formatter, completion or diagnostic work for defaults;
  `T-Default` keeps meaning a parameter default of a function.
- A library signature that means "any allocator" writes the parameter, and one
  that means "the system allocator" says so with an alias or the full name. A
  signature never means the second by omission.
- Applications repeat an alias block of three to five lines.
- Std's own public signatures stay generic. [0191](0191-the-caller-chooses-every-allocator.md)'s
  survey rule keeps `mem.system()` and `SystemAllocator` out of non-test
  library code.

## Alternatives considered

**Default type arguments (`Vec[T, A = SystemAllocator]`).** Not rejected for
inference: a default changes no identity, and `Vec[T]` would be the same type as
`Vec[T, SystemAllocator]`. Rejected because:

1. A default hardens into the ecosystem's de facto signature. Libraries write
   `fn f(v: Vec[T])` and silently exclude arena-backed vectors, the
   request-arena case 0154 is built on, and the caller meets [T-Mismatch] far
   from the author.
2. The impl-head hazard. `impl Trait for Vec[T]` would mean "system allocator
   only" by accident. 0194 already refuses an alias head in `impl` for the
   reason that it is a second spelling of one coherence key; defaults would
   need the same exception and a second diagnostic path.
3. Defaults do not drive inference, so the benefit is confined to written
   types, which is what an alias already covers.
4. The resolver, checker, formatter, language server and diagnostics all grow.

What would reopen it: a census of non-std code showing no allocator-generic
function is ever instantiated at two allocators (the abstraction goes unused)
together with programs that keep generic signatures out of habit; or a cheap
answer to the impl-head hazard, such as defaults being illegal in `impl` heads
as aliases are.

**A standard-library alias (`SysVec[T]` in std).** Chosen, as an
**application-facing module**: a std module labelled for programs and not
libraries, holding allocator aliases fixed to the system allocator
(`Vec[T]`, `String`, `Map[K, V]`, `http.Request`, `http.Response`,
`http.Answer`, and a `Memory` handle alias). Proposed until built.

It is aliases, not defaults: each name is the same type as its expansion
([0194](0194-an-alias-names-a-type-that-exists.md)), no type parameter gains a
default, and a library signature still never means the system allocator by
omission. It adds no type, no coherence question and no layout question.

The census of 2026-10-05 is the evidence: 22 of 43 examples mention an
allocator, and every program that wants a short spelling copies the same three
to five alias lines, which is one sentence describing many files. The earlier
reasons for refusing it were that std naming `SystemAllocator` in a public
declaration breaks its own survey rule
([0191](0191-the-caller-chooses-every-allocator.md)) and that file-local
aliases had not been tried. The survey rule takes an explicit exception for
this one module, whose purpose is the named choice, and the user's decision is
that waiting for file-local programs is not required.

Order of work. The module is spelled with generic aliases, and
`SysVec.open(..)` is refused today for a generic alias (probe p10, [T-Bound]),
so **generic alias heads land first**. Without them
`Vec[T]` in the module could be written as a type but not constructed through.

Risks, stated plainly:

- A library author who imports the module locks the library to the system
  allocator, the failure this record refuses to default into. The mitigation is
  documentation and naming: the module's name and its first line say "for
  programs; libraries take `A`", and `std/README.md` says the same. A lint-like
  rule that rejects the import in library code is out of scope.
- Errors print the expanded form (`Vec[UInt64, mem.SystemAllocator]`) after the
  code said `Vec[UInt64]`, so the alias is learned twice.
- Programs that mix allocators (parsers, serializers, request-local code) step
  outside the vocabulary and write the parameter, which is the generic form
  this record keeps.

Open questions, settled by convention in `std/README.md` when it is built: the
module's name, its exact contents, and where it sits in the std tree.

**An allocator-inferring facade at API boundaries (`request.json[Message]()`).**
Not expressible. It needs the callee to apply a type constructor to a type it
chooses, which is a higher-kinded type, and the language has no `_` hole in a
written type (`Message[_]` is [N-Undefined]), so the partial type cannot be
inferred from context. The need is met without it: with three file-local
aliases and a `Message` whose allocator is fixed, a handler names no allocator
at all and its test passes with a request built in an arena.

```linea
alias Memory = mem.Handle[mem.SystemAllocator]
alias Request = http.Request[mem.SystemAllocator]
alias Answer = Result[http.Response[mem.SystemAllocator], http.Error[mem.SystemAllocator]]

@derive(Release, json.Decode[Memory])
struct Message {
    text: String[Memory],
}

fn echo(inout _: (), request: Request) -> Answer {
    let message = request.extract[http.Json[Message]]()?
    defer message.release()
    http.text(request, message.text.view())
}
```

The generic form (`[P: Allocator]`) stays for tests that deliberately use
another parent, such as an allocator that refuses on purpose. Partial type
application would be a large language feature for three alias lines, and no
program here shows demand for it.

**Leave it to a convention that applications alias and libraries stay
generic, with no record.** The status before this one, and the reason for the
record: the principle lived in a ruling, and the record that should have
weighed it never mentioned it.

## Open

The application-facing module's name, contents and placement, as above. Whether
a library-import guard is ever wanted is not decided here and not planned.
