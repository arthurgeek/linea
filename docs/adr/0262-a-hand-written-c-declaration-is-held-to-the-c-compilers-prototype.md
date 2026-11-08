# 262. A hand-written C declaration is held to the C compiler's prototype

Status: Accepted — 2026-11-08. Extends
[0228](0228-a-granted-module-calls-c.md), whose consequence "nothing checks a
hand-written declaration against the real C signature" it answers for every
position lowering fixes, and whose manifest it gains `"headers"` in.

## Context

0228 lets a module its manifest grants declare a C function by hand:

```linea
extern fn counter_add(inout counter: Handle, amount: Int8)
```

The compiler believed the declaration. A wrong width, a missing parameter,
`inout` where C takes the object by value, or a result of the wrong type is
undefined behaviour in C, and the program compiled. The guide's checklist told
a wrapper's author to compare each declaration with the header by eye. An
accepted program with undefined behaviour is a compiler defect, whatever
library code it calls, so a rule must refuse the class of declaration, tied to
how the compiler lowers each declaration rather than to a list of names.

The C side of every such declaration already exists as text the C compiler
reads: a project's own C under `"native"`, or a library's header. What the
compiler did not have was the header's name, and a way to ask the C compiler
what a function's prototype is.

## Decision

**A root's C declarations are its `native` sources and the headers its
manifest names.** `"headers"` in `linea.json` lists headers as `#include <...>`
takes them: a relative path ending in `.h`, without `..`, searched first in
the manifest's directory and then on the C compiler's include path. A library's
manifest names its own. Naming headers needs a grant, as `native` and `link`
do ([M-Extern]).

**Every `extern` naming a C function is held to its prototype
([T-ExternPrototype]).** That is every `extern` of a granted module, the
standard library's included, except two kinds the compiler's own tables
answer for: a symbol in the runtime's `linea_` namespace, which
[T-ExternRuntime] holds to the runtime's signatures, and a storage primitive
named in `RawAccesses`, whose calls lowering replaces. A declaration no C
declaration of its root declares is refused, so the check has no opt-out:
the only way to call C is a granted `extern`, and every one is compared.

**Every C declaration of the function is compared**, the header list and
each `native` source, since C code calling the function may have been built
with any of them. A function C gives no symbol, because it is `static` or
`static inline`, is refused, and so is a name the C declarations define as a
macro, and a symbol C defines as an alias of another function.

**An `extern` calls the symbol C code calling the function calls.** An
`__asm__` label or `overloadable` gives a C function another symbol than its
name: glibc sends `lseek` to `lseek64` where C asks for 64-bit file offsets
and `strtol` to `__isoc23_strtol` under `_GNU_SOURCE`, and macOS sends
`realpath` to `realpath$DARWIN_EXTSN`. The prototype is the labelled
declaration's, so the `extern` links against the labelled symbol, which is
what C itself calls. Every C declaration of the root must give the function
one symbol; two that give it two are refused, and so is a symbol a Linea
declaration cannot be emitted under, such as a Darwin label without the
leading underscore every C symbol there carries.

**An `export` is held to the same table wherever its root's C declares it.**
C code of the root calling an exported function trusts its own declaration of
it as the Linea program trusts an `extern`, so the promise is the same in the
other direction. An export C does not declare is not refused: a library's
caller declares it elsewhere.

**What lowering passes at each position is the implied C type.** The table is
read from the compiler, not restated: `types.foreignScalar` answers what a
type crosses as, the backend writes the C type from that answer, and
`sema/foreign.zig` builds the implied prototype from it:

| Linea position | C accepts |
| --- | --- |
| an `IntN` or `UIntN`, or an unrefined newtype over one | an integer of N bits and the same signedness, or an `enum` the C compiler gives that width and signedness |
| a `UInt64`, or a newtype over one: a handle, `ffi.CText`, `ffi.Bytes`, `ffi.CTextList` | also any pointer, since a pointer crosses as its 64-bit address |
| a `Float64` | `double` |
| `inout` of one of these | a pointer to a type that position would accept by value |
| a callback's context, the `inout` place C hands back | `void *` |
| a callback `fn(...)` | a pointer to a function held to the callback by the same table |
| `ffi.Errno[R]` | what `R` would be |
| no result | `void` |

The comparison is by representation, not by C's type identity. C's `int64_t`
is `long` on Linux and `long long` on macOS, and SQLite's `sqlite3_int64` is
`long long` on both, so C's own compatibility rule would refuse a correct
declaration on one platform and accept it on the other; both are 64-bit signed
integers, passed alike. The widths of C's integer types and the signedness of
plain `char` are the target's. An enumeration's width is the C compiler's
choice from its values or its fixed underlying type, so the compiler reads
how C passes it: its width, and for one narrower than 32 bits whether it is
sign- or zero-extended, which is its signedness; a 32- or 64-bit enumeration
is passed alike either way, so either matches. An enumeration behind a
pointer or in a callback, which nothing passes by itself, matches nothing. A
function C declares with a calling convention other than its own, such as
`preserve_none`, a variadic function, a function declared or defined without
a prototype, `long f();` or `long f(x) short x; {…}`, whose type states no
parameter types a caller passes by, `bool`, a structure by value, `float` and
`long double` match nothing.

**`read` does not require `const`.** A `read` handle promises that C only
reads the object ([T-ExternHandle]), and C's `const` on the pointee says less
than that and more: C casts it away freely, and libraries such as SQLite take
`sqlite3 *` without `const` in functions that only read. The check holds what
the declaration passes, an address, and leaves the promise about what C does
with it to the wrapper, as 0228 does.

**The C compiler describes each prototype.** For each of a root's C
declarations, the header list or one `native` source, the driver writes two C
files that include it. The first takes each function's address and refers to
it from an inline function of external linkage:

```c
#include <sqlite3.h>
static __typeof__(sqlite3_close_v2) *const linea_probe_0_3 = &sqlite3_close_v2;
inline void linea_probe_0_3_linkage(void) { (void)&sqlite3_close_v2; }
```

`cc -fsyntax-only -Wno-everything -Werror=static-in-inline -fno-spell-checking
-ferror-limit=0` reads it and prints each probe's type tree with every typedef
resolved (`-ast-dump -ast-dump-decl-types`, filtered to the probes). The
inline function is refused where the function is `static`. The compiler reads
the tree, discarding sugar and qualifiers, keeps the calling convention each
function type names (`cdecl` is C's own on every supported target), and
compares each position. A probe naming a function nothing declares is an
error at the probe, which reads as undeclared, and spelling correction is off
so no similar name stands in for it; any other error, such as a header `cc`
cannot find, refuses every `extern` of the root with `cc`'s own words.

The second file keeps the address of each function the first found in a used
global, and `cc -S -emit-llvm` compiles it:

```c
void *const linea_symbol_0_3 __attribute__((used)) = (void *)&sqlite3_close_v2;
```

The IR names the symbol the global points at, which is the one C calls, and
the `declare` or `define` of that symbol says how C passes each value: an
enumeration's width, and its extension. Reading these from the code `cc`
generates, rather than asking `cc` about a type by its spelling, cannot be
misled by a macro that renames the spelling after the declaration or by an
enumeration declared inside a parameter list. An `alias` definition of the
symbol is refused.

**When.** `linea check`, `build`, `run`, `test` and `emit-mlir` hold the declarations once
the semantic passes accept the program, before lowering, and so does the
conformance runner, over a case's C files written to its scratch directory.
The language server does not, because it checks on every edit and the check
starts a process.

**What a refusal says.** [T-ExternPrototype] is reported at the declaration:
the message names C's prototype and the one the declaration implies, with C's
spelling kept where they agree, the label points at the first position that
disagrees, a note says which C declaration was read, and the help names the
edit:

```text
error[T-ExternPrototype]: C declares `void counter_add(struct counter *, int8_t)`, and this declaration calls it as `void counter_add(uint64_t *, int8_t)`
```

## Consequences

- A wrong width, a missing or extra parameter, `inout` against a value, a
  plain parameter against an address C writes through, a wrong result, an
  enumeration of another width, another calling convention, a `static`
  function, two symbols for one function and a callback C calls another way
  are refused wherever they are written, in a program's module or a
  library's, and for every C declaration of the function the root names.
- An `extern` of a function C reaches under another symbol calls that
  symbol: `lseek` under `_FILE_OFFSET_BITS=64`, glibc's `__isoc23_` functions
  and macOS's `$DARWIN_EXTSN` variants are called as C calls them.
- An export the root's own C declares with another prototype is refused.
- A project calling the C library writes the header under `"headers"`;
  a project calling its own C has nothing to add, since its `native` sources
  declare what they define. Writing the shim's prototypes in a header the shim
  includes lets `cc` hold the definition to the header too.
- Each command that would build a program reading C starts two `cc` per C
  declaration of each root that declares an `extern`: about a tenth of a
  second each with SQLite's header. The result is not cached. A key covering what
  `cc` read would have to follow every file the headers include and the
  environment that chooses the include path, and a stale entry would accept
  a declaration the current header refuses.
- The check depends on the text of clang's `-ast-dump`, which is a debugging
  format. The backend already requires clang, since `cc` compiles LLVM IR.
  The reading keeps to node kinds, the quoted spelling and the `sugar`,
  `const` and `variadic` words, which have stood for many releases, and a unit
  test reads a recorded dump.
- What stays believed: ownership conventions, `read`, `borrows`, lengths,
  which object a pointer points at, and C the compiler reads no declaration
  of: a symbol defined by top-level `__asm__`, or a library whose header
  does not describe it, is believed as a lying header is. A handle crosses as any pointer, so a
  plain handle where C takes `sqlite3 **` is accepted; `inout` of a handle
  against C's `sqlite3 *` is refused, because the pointee is fixed there.
- Diagnostics carry no machine fix: the corpus property that applies fixes
  checks a case of one file, and a case of one file has no manifest to grant
  C.

## Alternatives considered

**Letting the C compiler compare whole prototypes**, assigning `&f` to a
pointer of the implied type under `-Werror=incompatible-function-pointer-types`.
It lost because the implied type is not one C type. `int64_t` is `long` on
one platform and `long long` on the other, so a declaration matching
`sqlite3_int64` would be refused on Linux alone; a handle's pointee is a type
the Linea declaration does not name, so no implied type could be written for
it; and a `UInt64` passed where C takes a pointer, the way 0228 passes a null
`vfs`, has no single spelling either.

**Requiring `const` for `read`.** Sound, since it refuses more, but it would
refuse every `read` against SQLite, whose read-only functions take
`sqlite3 *`, while a `const` pointer C casts away would still be accepted. It
checks a spelling, not the promise.

**Compiling the probe as C++**, where templates take a function type apart
parameter by parameter in standard C++. A C header need not be valid C++ (an
implicit conversion from `void *` in a `static inline` body is an error
there), and a project's `native` source, the only declaration of its own C,
almost never is.

**Requiring a header for a project's own C.** A `native` source declares what
it defines, and is exactly what the build compiles, so reading it leaves
nothing for a header to drift from.

**Checking only where headers are named.** A declaration whose root names
none would be believed as before, and leaving `"headers"` out would be the way
to skip the check.

**Reading headers with a C frontend in the compiler**, or a bindgen tool.
0228 rejected both as a way to write declarations; as a way to check them
they would put a second C parser beside the one the build already runs.
