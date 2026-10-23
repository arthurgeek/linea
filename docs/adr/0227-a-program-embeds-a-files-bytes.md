# 227. A program embeds a file's text or bytes: `embed` and `embed_bytes`

Status: Accepted — 2026-10-15

Extends [0075](0075-a-program-root-is-a-directory-holding-a-manifest.md) and
[0096](0096-a-root-is-a-program-or-a-library.md): the directory holding a
root's manifest also bounds the files its code may embed. Extends
[0140](0140-aggregate-constants-retain-checked-construction-plans.md) and
[0178](0178-a-constant-is-a-static-place.md): an embedded file is a constant
expression, and the byte slice `embed_bytes` makes is a constant laid out in
static storage.

## Context

A program that serves a page or creates a database carries text that is not
code: an HTML template, a SQL schema, a JSON fixture. It could hold it two
ways. A `\\` multi-line literal puts the text in the source, where an editor no
longer treats it as HTML or SQL and every line carries two backslashes. Reading
the file at run time makes the program depend on a file beside it, on the
working directory it is started in, and on an allocator for text it never
changes.

Bytes that are not text had no constant form at all. `let logo =
"abc".as_bytes()` at module level is [T-Const]: the only static bytes were a
string literal's, and only through a function whose result `carries()` nothing.

Zig's `@embedFile`, Rust's `include_str!` and `include_bytes!`, and Go's
`//go:embed` read a file when the program is compiled and keep its bytes in the
executable.

## Decision

**Two reserved words, written as calls.** `embed("page.html")` is the file's
text, a `Str`, and the file must be UTF-8 ([M-EmbedText]). `embed_bytes("icon.png")`
is its bytes, a `mem.Slice[UInt8]`, whatever they are. The argument is one
quoted or raw string literal ([S-Embed]), because the loader reads the file
before any name is resolved: a constant cannot stand for the path. The words
are reserved like `copy` and `panic`, so a node the parser built as an embed is
one, and no local `fn embed` can make the loader's search depend on scopes.

**A path is relative to the file that writes it** and may climb with a leading
run of `..` no further than the root of the code writing it: the directory
holding its program's or library's `linea.json`, or the file's own directory
where no manifest marks one ([M-Embed]). A module moves with the files beside
it, and a program whose source sits in `src` embeds `../templates/page.html`.
`..` after a name, `.`, an empty part, a leading `/`, a backslash, a NUL and a
`:` are refused for their spelling. Each name must match a directory entry byte
for byte, so a program that compiles on a case-insensitive filesystem compiles
on Linux. No symbolic link below the root is followed, which is what makes the
check on the spelling true on disk. The standard library embeds from its own
directory, through the copy compiled into the binary, which now carries every
file under `std/` but its Markdown.

**The loader reads the file, once.** One routine, `driver/embedded.zig`
`resolve`, turns a written path into a root-relative one for every input. The
command line reads from disk; the conformance runner finds the file among a
case's supplied files; the language server copies its buffers and reads
embedded files from disk. The bytes are recorded in `Program.embeds` with the
expression that read them, and have the sources' lifetime. No pass after the
loader opens a file.

**An embedded file is a constant.** It folds to the bytes it read, so two
embeds of one file and a literal of the same text are one value and one blob in
the byte pool. It is static storage: its value depends on nothing, needs no
allocator, and may be returned from a function declaring `carries()`, stored or
captured. A refused embed is a constant whose value does not exist, so it is
reported once.

**A file embeds at most 16 MiB**, refused with its size before it is read. The
bytes are emitted as every literal's are, an `llvm.mlir.global` string whose
non-printable bytes are written `\XX`. A 16 MiB file of escaped bytes builds in
about nine seconds.

**The output depends on the bytes and on nothing else about the file.** The
path never reaches the emitted code, so the conformance outcome cache, keyed on
the IR, files a program under the bytes it embeds and never reuses an outcome
recorded for older ones.

## Consequences

- Templates and schemas live in files of their own, edited as what they are,
  and a program needs nothing beside it when it runs.
- `embed` and `embed_bytes` are no longer names a program may use.
- Every embed costs one read of a directory listing per component of its path,
  once per compilation. A file a program embeds is in memory for the whole
  compilation, as its sources are.
- Binary data costs up to three bytes of MLIR text per byte.
- The language server reads embedded files from disk on every check, and a
  change to one is seen when a `.lin` file changes or the client reports the
  file changed.
- A refused argument, such as `embed(name)`, leaves `name` unused, and
  [N-Unused] reports it beside [S-Embed].

## Alternatives considered

**`@embed("x")`.** `@` begins the closed set of declaration attributes
([0145](0145-closed-attributes-attach-ordinary-derive-requests.md)), and the
parser reads it as the start of a declaration. A second meaning in expression
position would make that test depend on context.

**A prelude function `embed`.** A local `fn embed` could shadow it, and the
loader would need name resolution to know which a call names.

**An attribute on a constant.** A modifier reaches only the braces it precedes,
and an expression composes where an attribute cannot: as a parameter default, a
field of a constant record, an argument.

**One `embed` typed by its context.** `let page = embed("x")` and `let page:
mem.Slice[UInt8] = embed("x")` would refuse and accept the same file, and Linea
converts nothing implicitly ([0207](0207-linea-converts-nothing-implicitly.md)).

**A fixed array `[UInt8; N]` for the bytes**, as Zig's `*const [N]u8`. The type
would change with the file's length, so an annotated constant would break on an
edit to the data, and a constant array is laid out one static part per element.

**Paths relative to the source root**, as imports are
([0111](0111-import-paths-are-root-relative.md)). A module could not carry its
data files when it moves, and a module deep in a tree would spell the whole
route to a file beside it.

**No `..`.** Templates kept beside `src/` would be out of reach without moving
them under the source. **`..` anywhere in a path** adds no file a leading run
cannot reach, and gives one file a second spelling from one directory.

**Following symbolic links, with the check on the spelling.** A link inside the
root could name a file outside it while every spelling looked contained.

**Reading the file in the checker or in lowering.** A pass would perform I/O,
and checking and code generation could read different bytes.

**`dense<…>` or `dense_resource` emission.** A dense integer array spells each
byte as two to five characters, and a resource blob as two hexadecimal digits
plus a second kind of global and escaping routine; neither changes what a
16 MiB file costs.

**No size limit.** A mistaken path, a database or a video, would decide how
much memory a compilation takes rather than produce a diagnostic naming the
file.
