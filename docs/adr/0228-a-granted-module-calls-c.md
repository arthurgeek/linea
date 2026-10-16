# 228. A granted module calls C

Status: Accepted — 2026-10-15. Supersedes the boolean `"extern": true` grant
of [0171](0171-the-standard-library-is-an-ordinary-library.md); the
integer-only clause of [T-Extern], the clause refusing linear values and
callables, and "Not an FFI" in
[0068](0068-a-declaration-may-name-a-symbol-the-runtime-provides.md); and
"general Float64 foreign calls remain unsupported" in
[0150](0150-float-math-crosses-a-checked-scalar-boundary.md). Extends
[0013](0013-no-undefined-behaviour.md), which left the C boundary to a record of
its own, and [0101](0101-a-library-publishes-what-it-exports.md), whose thunk
and boundary predicate it shares.

## Context

[0068](0068-a-declaration-may-name-a-symbol-the-runtime-provides.md) let a
declaration name a symbol the runtime provides, and nothing else. It admitted
integers only, because only an integer's representation was the language's to
fix, and it refused a linear value because ownership cannot read a path through
C. [0171](0171-the-standard-library-is-an-ordinary-library.md) moved the grant
into a root's manifest as `"extern": true`, which any root could write, and
left open who should be allowed to.

The first program that needed more was a guest book that stores its entries in
SQLite, through the system's or Nix's `libsqlite3`. It needs to:

- link a C library and build a small C shim;
- hold `sqlite3 *` and `sqlite3_stmt *` objects that must be closed;
- pass text in and copy text out;
- read result codes;
- run `sqlite3_exec`, which calls back once per row.

Probing the existing boundary for this found a defect: an `Int8` or `UInt16`
crossed without the sign or zero extension both supported C ABIs leave to the
producer, so `-3` reached C as `253`.

## Decision

**A manifest grants `extern` to named modules.** `"extern"` in `linea.json` is
a list of modules, each spelled as an import inside the root names it (`"store"`,
`"io.core"`), with `"."` for the root module. Only a listed module may declare
an `extern` ([M-Extern]). A grant of another shape, or one naming a directory of
the root that holds no source, stops the command. The standard library lists
its seven modules that call the runtime. A program may grant its own modules:
an application keeps C in one small wrapper module that a reviewer reads against
the C header, and the rest of the program never declares C. An `extern` is
private to its module, so the rest of the program never calls C either: the
granted module publishes ordinary functions that call it and check what C
cannot.

**A manifest names the C it builds and links.** `"native"` lists C sources
relative to the manifest, compiled with the same `cc` at the build's level and
with the runtime's sanitizer flags. `"link"` lists libraries passed as
`-l<name>` after the runtime archive. A link entry must be a library name, so a
manifest cannot pass the linker a flag. C named without a grant, or by a
library, is refused. Libraries are found where the toolchain looks: in the
development shell, Nix puts SQLite and its header on the compiler's paths. No
header is read: declarations are written by hand.

**What crosses is what both sides agree a value's bits mean** ([T-Extern],
[T-Export]): an integer of 8, 16, 32 or 64 bits, a `Float64`, or an unrefined
newtype over one, which crosses as its base. Every bit pattern of these is a
value on both sides, so nothing C returns is a value Linea does not define. An
8- or 16-bit integer carries `signext` or `zeroext` on the declaration and the
export thunk. `Bool` and a refined newtype are refused. An `inout` parameter
crosses as the address of its slot, C's `T *`.

**A C object is a sealed linear newtype over `UInt64`.** A pointer is a 64-bit
integer on every supported target, and both ABIs pass one as they pass a
`uint64_t`. `@opaque` lets only the wrapper make a handle from an address, and
`@linear` makes forgetting its release [O-Leak] wherever the wrapper's own
linear type travels. A linear newtype crosses, because the parameter convention
is the path ownership could not read: a plain parameter lends the object to C
for the call, and `sink` hands it to C. The wrapper compares an address with
zero before it builds a handle; there is no null-checking lowering.

**Text and bytes are `std.ffi` types that carry what they view.**

- `ffi.Bytes` is a view's address, at a non-null address even when the view is
  empty.
- `ffi.CText` is NUL-terminated text, and `ffi.CTextList` is C's `char **`.
- `ffi.CString` owns text with a NUL after it, refuses text holding a NUL of its
  own, and lends a `CText`.

`Bytes`, `CText` and `CTextList` are copyable newtypes over the address whose
dependencies originate at the value, as a `mem.Slice`'s do, so a contract ties
each to what it views. `ffi.bytes(text)` carries `text`, and an `extern`
answering a pointer into an object declares `borrows(handle)`. Freeing or
changing the owner while one is alive is then [O-Borrow]. A `CText` is read
only by copying it: `to_owned` checks UTF-8 and reports a null pointer as an
error, and `copy_bytes` copies a length C gave. Only a granted module may
import `std.ffi` or call any of its operations, whatever `std.ffi` value
reaches another module through inference, a bound, an associated type or a
field ([M-Foreign]). That is what lets `copy_bytes` trust a length. A granted
module that names one of the types in a function signature, a field or
payload a module can reach, a `pub use` or an alias is told so where it
writes it; one that hands a view out some other way, inside a newtype or as an
iterator's item, is caught only where another module would read it.

An `extern` whose result can carry a dependency writes a contract saying what
it points into, `borrows(handle)` or `carries()`. No body is read to infer
one, and a handle parameter carries none by default, so an omitted contract
would mean the answer depends on nothing.

A newtype holds what its operand holds: constructing one keeps the operand's
dependencies, and taking one apart hands them to the binding. Before this
record the construction dropped them, which for a view of C memory was a read
after free.

**A callback is a plain `fn` with an optional context** ([T-ExternCallback]).
Its parameters and result cross, apart from a leading `inout` parameter whose
type the `extern` also takes as its one `inout` parameter of that type. C
receives that parameter as a `void *` and hands it back on every call. A call's
argument names a function or is a lambda that captures nothing. Lowering passes
the address of a C-callable entry to that function (`foreign_function_addr`).
The backend writes the entry with the routine that writes an export's thunk.
The verifier refuses the address anywhere but as an argument of an `extern`
call.

**What a wrapper vouches for.** The compiler believes these, as it believes
every `extern` signature:

- each declaration matches the C prototype;
- conventions tell the truth about ownership;
- C keeps no pointer into Linea memory after a call returns;
- text living inside a C object is declared `borrows`, and a C function that
  changes or frees the object is called only from a wrapper method taking the
  wrapper `inout` or `sink`, never directly while text read from it is in use:
  the `extern` takes the handle as a plain parameter, which the compiler cannot
  tell from a read;
- C calls a callback only during the call that passed it, on the calling thread;
- every length given to C or to `copy_bytes` is the length of its memory.

## Consequences

- An application calls SQLite through a wrapper module of about two hundred
  lines. Nothing outside the wrapper sees a pointer, and forgetting to close a
  connection or statement is a compile error.
- The trusted surface is the granted modules' source. A module that is not
  granted can neither declare nor call C, and cannot call `std.ffi`'s
  operations, so it cannot break the wrapper's promises.
- A wrapper still writes the C prototypes by hand, and a wrong one is undefined
  behaviour in C. `inout` against a C function that takes the object by value is
  the easiest mistake, and the guide's checklist names it.
- `std.ffi`'s views are dependency seeds by declaration, as `mem.Slice` is, and
  a seeded newtype is no longer a dependency-free scalar. Other newtypes over
  scalars are unchanged.
- A library root cannot yet name C to link, because nothing carries its link
  line to the program that links it. The `sqlite` library the guest book will
  depend on waits for library dependencies.
- **Future work, designed and not built:**
  - `extern struct` would pin [L-Layout] for a struct crossing by pointer. By
    value, the C ABI's per-target classification of aggregates would have to be
    implemented first.
  - `ffi.Errno[R]` would read `errno` immediately after a call.
  - A callback context of a type parameter would need one instance per symbol
    across instantiations.
  - A convention that lends a handle exclusively by value, so an `extern` that
    changes its object ends what was borrowed from it at the declaration
    rather than through the wrapper's discipline. One shape is to treat a plain
    lend of a linear newtype to an `extern` as exclusive, which would also end
    the borrows of read-only calls.

## Alternatives considered

**Header import, as Zig's `@cImport`.** It needs a C frontend and a model of the
preprocessor in the compiler. It imports every declaration a header holds, so
the believed surface becomes the header rather than what a reviewer read.
Headers do not say who owns what: `sqlite3_column_text` and `sqlite3_errmsg`
both answer `const char *` with different lifetimes, and only a hand-written
`borrows` states the difference.

**A bindgen tool** that writes `.lin` declarations from a header once. It has
the same ownership gap and adds a maintained tool whose output a person must
still annotate. It remains possible as a convenience that writes a starting
file.

**An `extern type` declaration** for C objects, with the compiler checking
`NULL` and mapping it to `Option`. A sealed linear newtype already is an opaque
linear handle. The declaration form would need parser, formatter, editor and
language-server support for no capability the newtype lacks, and the null check
belongs to the trusted wrapper either way.

**Lowering `read text: Str` as a pointer argument.** One parameter would become
an address with a hidden extent, and lowering would need a new argument
conversion. A function whose result carries the view's dependencies gives the
same borrow with no lowering at all.

**Keeping the whole-root grant.** Every module of an application could then
declare `free`, and the trusted surface would be the whole program.

**A per-declaration attribute such as `@trusted`.** It makes trust a property of
the source being compiled, which 0068 rejected for the same reason.
