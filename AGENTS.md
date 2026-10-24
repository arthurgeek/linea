# Contributing to Linea

This guide applies to the whole repository and to every contributor, human or
automated. `CLAUDE.md` is a symlink to this file. It states the rules a change
must satisfy; the reasoning behind each lives in the ADRs and the documents
linked below.

## Start here

Read `docs/adr/README.md` before changing code. The ADRs are binding: code that
violates a standing invariant is wrong even if it works. Then read the document
that owns the area being changed:

- `docs/linea-semantics.md` defines the language rule by rule. Every rule has a
  bracketed name that a diagnostic emits, so `error[T-Mismatch]` indexes the
  prose. A test fails if the compiler can emit a name the document does not
  define, so a new rule lands there or not at all.
- `docs/adr/README.md` indexes the decisions, each with the alternatives that
  lost and the technical reason they lost.
- `docs/architecture.md` records what each pass decides, where each decision is
  recorded, and what crosses every seam. Read it before adding a pass or moving
  a responsibility.
- `docs/learn/` is the user guide; `std/README.md` documents the standard
  library; `docs/formatting.md` defines the formatter's output.

When the semantics document and an ADR disagree, correct the semantics
document: an ADR records a decision, the semantics document defines the
resulting language.

## Toolchain and commands

Use the Nix development shell; it supplies Zig 0.16.0, ZLS, MLIR and the C
toolchain. Backend-dependent results are not meaningful outside it.

```sh
nix develop                    # Zig 0.16.0 and zls
zig build                      # build the compiler
zig build test -Dtest-filter=<substring>  # development checks
zig build test                 # the unfiltered run, only at the end
zig build run -- <cmd> <file>  # run a subcommand
zig fmt --check build.zig build src runtime  # what CI checks first
zig build sweep -Drelease      # every cost dimension
zig build sweep -Drelease -Dsweep-filter=<substring>  # one cost dimension
zig build guide                # check the guide's programs and fragments, compare pasted output
zig build example-tests        # linea test on every root under examples/, nested libraries included
```

`zig build test` does not check formatting, so run `zig fmt --check` as well
before pushing and before declaring a code change ready.

**Run the suite inside `nix develop`.** Recorded exit statuses are cached under
a key made of the emitted IR and a stamp of every tool a build runs. Outside
the shell `mlir-opt` is absent, no key matches, and the run fails at the first
case that needs a backend. That says something about the shell, not the corpus.

### Test runs

During development run filtered tests. Run the unfiltered `zig build test` once,
after all implementation, golden updates, measurements, focused checks and
review fixes are finished. An unfiltered `-Dupdate` run counts as a whole-graph
run. If the final run fails, fix with filtered runs and run the suite again
until it is green.

- `zig build test -Dtest-filter=<substring>` runs matching `test` blocks from
  the joined Debug compiler/conformance root and the build-source binary. It
  skips every integration gate: corpus and example walks, sweeps, and
  tree-sitter checks. The unit tests run once, in the mode the build selects;
  the `optimised` CI lane runs them again under ReleaseFast.
- `zig build sweep -Drelease -Dsweep-filter=<substring>` runs only the cost
  dimensions whose names contain the text. Use the narrowest match while
  iterating; run the unfiltered sweep before declaring a performance-sensitive
  change ready.
- The conformance runner has no single-case filter; it walks `tests/`. Narrow
  it with `zig build conformance -- <dir>` (for example `tests/decl`), or run
  `zig-out/bin/conformance <dir>` with `--compiler` and `--runtime`.
  Intermediates go to `.zig-cache/conformance-scratch` unless `--scratch` names
  another directory. Pass
  `--runtime zig-out/lib/liblinea_rt_checked.a`, the runtime `zig build
  conformance` uses: it checks storage, and a case recording one of its reports
  is not run against `liblinea_rt.a`. Run narrowed walks serially. A narrowed
  walk runs that directory's cases and every transcript beneath it, without
  coverage floors, generated programs or examples. A root that is one case (a
  `.lin` file, a `.cmd` transcript, or a directory holding `main.lin`) runs that
  case alone. A walk that selects nothing fails, and so does one holding
  transcripts without `--compiler`.
- `zig build guide` checks every `linea` block on every page
  `docs/learn/README.md` links, the appendices included, and compares the
  output pasted beside it with what the compiler prints; a Markdown page in
  `docs/learn` the index does not link fails the gate. Run it after changing
  a chapter, a diagnostic's wording, or the library a chapter shows. A `linea`
  block with `fn main`, a `test fn` or a `` `path.lin`: `` label is a program;
  the bare or `text` block after it (past an optional `sh` block holding
  `linea run|check|test PATH`) is its output, and is all of what the compiler
  prints. A fenced block labelled `` `path/linea.json`: ``, `` `path.c`: `` or
  `` `path.h`: `` is a file of the labelled project around it, so a program
  that builds and calls C runs; a labelled file no `main.lin` of its project
  follows fails. `<!-- guide: check REASON -->` above a program that cannot
  run (it needs arguments, or serves until stopped) compiles it with
  `linea check` and never runs it; the output after it is compared when it
  shows diagnostics, and is otherwise what a run prints, held to the wording
  rule below. Every other `linea` block is a fragment, checked one of three
  ways. `<!-- guide: edit [PATH] N TEXT | N-M TEXT … TEXT | after N TEXT | fn NAME | end -->`
  above it replaces line N or lines N-M of the nearest program above, or
  inserts after line N, counting lines as that program is pasted; with PATH it
  edits that file of the nearest program above that has one, which a project
  needs. Each TEXT is the whole line it names, trimmed: line N, and for a
  range also line M after ` … `, and it must match that line alone in the
  file, so a number that names another line fails and a `}` that closes two
  blocks names neither. A line too long to write out may be given by its
  start followed by `…`, at least eight characters and not only punctuation.
  Where the line to name is not distinctive, the edit names a neighbouring
  line that is, or `<!-- guide: edit [PATH] fn NAME -->` replaces the
  function `fn NAME`, from its line to the `}` that ends it at the start of a
  line, and `<!-- guide: edit [PATH] end -->` appends to the file. `after 0`,
  the top of the file, names no line and takes no text. Consecutive
  edit blocks apply together, and the output after the last is what the
  edited program prints; an edit of a `check` program is only checked too.
  An edit that writes back the lines it replaces, or whose nearest program
  is excluded, fails, and a failure names the block whose lines the compiler
  reports. `<!-- guide: excerpt PATH -->` holds it to consecutive lines of
  `PATH` relative to the repository root, less an indentation those lines
  share, and compiles nothing; when `PATH` is a guide page it must be one the
  index links, and the lines must come from a program that page compiles. An
  unmarked fragment is checked alone with `linea check`, as the root file of
  a library so it needs no `main`; an `[N-Unused]` naming one of its own
  top-level declarations is allowed, since the code that would call it is not
  shown, and output pasted after it is compared like a program's.
  `<!-- guide: unchecked REASON -->` above a block excludes it and the output
  after it, for a sketch, a signature or a program missing what it needs; a
  `linea` block it excludes is still checked alone, and must fail, so a
  marker that is no longer needed fails the gate. A block showing only the
  first diagnostics carries `<!-- guide: first N diagnostics -->` on the line
  above it and must be exactly those N with at least one more after them.
  Output that follows no program carries `<!-- guide: unchecked REASON -->`
  above its block; its diagnostic headers, `= help:`/`= note:` lines and
  underline labels, like those of output a program does not run to print,
  must still read like ones the compiler prints (wording found in the gate's
  own runs or in the `.stderr` goldens under `tests/`), so a new message shown
  only there needs a corpus case that prints it. A marker may sit between a
  label and its block. A fenced block that is neither compiled, excerpted nor
  marked fails the gate. A location inside `std/` is compared by file alone.
- A case is a `.lin` file or a directory holding `main.lin`; a module is a
  directory, and its goldens sit beside the directory under its own name.
  Examples keep only what a reader wants: their goldens sit in `tests/examples/`
  under the example's name (`examples/tcp_echo.lin` records
  `tests/examples/tcp_echo.exit`). `support/corpus.zig` is the one place that
  maps an example to its goldens; a golden beside an example, or one in
  `tests/examples/` naming no example, fails.
- `build/` holds what the gates in `build.zig` read from the project's own text,
  with cases of its own, because `zig build` runs no `test` block in a build
  script.
- The focused cases `build/property-cases.txt` lists, and the programs the
  generator supplies, are also run under meaning-preserving rewrites of their
  source (declarations reversed, match arms rotated). There is no golden to update; a failure
  means the compiler disagrees with itself, and `-Dupdate` will not silence it.
  `-Dprograms=N` sets how many generated programs run (32 by default; seeds are
  consecutive from zero, so a failure names a reproducing number). A generated
  program the compiler rejects is a failure: the generator and the compiler
  disagree about the language.
- Every rejected case of one file is also held to its helps: a diagnostic
  carries a `Fix` for each help concrete enough to write, the edits that help
  names applied together, and the conformance runner applies each fix alone and
  checks the case again through `loader.checkWhole`, the passes `linea check`
  runs. The error must be gone from the line it was reported at, and the fix
  must add no error of its own: none that loading the text reports and did not
  before (the fix left it not lexing or parsing), and none with a label on a
  line the fix wrote or removed. An error is the program's own where one under
  the same rule was reported at the line it moved to. Then it follows the fixes
  in turn, one each round, holding each to the same, until no error carries
  one: an error a fix answered must not come back at its line, a new error
  elsewhere is the program's next mistake and is allowed, and fixes still
  offered after eight are reported as helps that undo each other. There is no
  golden, `-Dupdate` cannot silence it, and the run fails where a kind of fix
  (`FixKind`) is carried by no case. Fixes carried: the `where` clause
  [O-Escapes] and [T-BorrowContract] name, on a function, a lambda or a written
  callable type; the owned copy of a returned view and the owner put in place
  of its view at every exit, with the imports they need; the result type
  [T-TryAnswer] names, with every `return` and the tail wrapped; `.settled()`
  before `?` and a discarded failure handed on; the [O-Leak] `defer`, after the
  `let` or `var` that binds the value or first in the body of the function or
  closure whose parameter it is; a member [T-Impl] says to drop; the type a
  concrete implementation names, in place of `Self` written in a test inside
  it; the other
  allocator form of a call, where the program holds one allocator to pass; a
  type parameter for each of two closures; the `import` an [N-Undefined]
  qualifier names, one per module it could mean (a loaded one, the library's
  included, that lets the file reach the name selected from it, or a
  directory of the root's that no import loaded); the `use`
  [T-UnknownOperation] names, with its import; and `copy(value)` passed to a
  call that both lends and takes a copyable value. `linea check
  --error-format=json` writes them under `fixes`, and the language server
  offers each as a quick fix. A help whose edit is fully determined but cannot
  be written says why in its text instead of carrying a fix: a `where` beside
  type predicates or around a comment, the owner in place where another exit
  returns something else, a result `main` cannot answer (only `UInt8` or a
  `Result[UInt8, E]` whose `E` implements `Display`), a closure
  whose result its callable type fixes, a type whose qualifier the module
  binds to something else, and a parameter written as a pattern, which no
  clause can name. Helps that carry none, because the edit is a choice the
  reader makes: the [T-Infer] annotation and defaulted parameters (which
  type), the arguments a test in a generic implementation means, `let … else`
  (what the `else` block does), releasing before a path
  leaves, a `defer` for a pattern's or a loop's binder, and [O-Merge] (where,
  and on which path), the owned copy kept in a field or an `inout` parameter
  (the field's type and the failure path both change, or `append` instead),
  the allocator taken as a parameter (the signature and every caller), and
  which allocator to pass where the program holds none or several,
  implementing a conversion (a body to write) and the import beside it, and
  every help outside this list's rules. A help offering an edit a tool could
  write should carry it.

### CI lanes

CI partitions the work into named steps: `conformance` runs corpus and
examples; `test-unit` runs the compiler, conformance-harness and build-source
tests at the selected optimisation level; `fuzz` runs only compiler tests named
`fuzz:` or `fuzz-slow:`:

```sh
zig build fuzz --release=safe --fuzz=20K -Dfuzz-filter=fuzz:
zig build fuzz --release=safe --fuzz=100 -Dfuzz-filter=fuzz-slow:
```

CI runs the first weekly; the second runs locally when changing what the
storage generator writes. The extra soundness seeds in `optimised` check the
same property: a fixed window on a pull request, and a window that moves with
the run number on the weekly and manual runs.

`check` passes `-Dsafe-runner`, which builds the conformance runner ReleaseSafe
while the compiler under test and the unit tests stay Debug.

Name every test that calls `std.testing.fuzz` with the `fuzz:` prefix, or
`fuzz-slow:` when one input compiles whole programs against the checked library
and twenty thousand runs would take hours.

CI runs on GitHub's hosted runners, from `.github/workflows/ci.yml`. A pull
request merges into `main` once `merge-ready`, the one required status, is
green on its final commit. A draft pull request runs nothing. A ready pull
request runs `check`, `sanitize`, `optimised`, `sweep` and, when the change
touches `src/mir`, `src/ownership`, `src/sema` (which holds the type tables),
`src/driver/loader.zig` or the program generator, `fuzz-mir`, which fuzzes
the MIR verifier. A push to `main` runs `check`. A manual run and the weekly
schedule run every lane and `fuzz`, which runs every `fuzz:` target and keeps
the inputs each clean search reached for the next. `optimised` also
runs soundness, over the default seeds and over sixteen more: a fixed window
on a pull request, and one that moves with the run number on a weekly or
manual run.

A first job, `changes`, diffs the change against the pull request's base or
the commit a push replaced. A change to Markdown alone skips every lane,
except Markdown a gate reads: `docs/learn/`, `docs/linea-semantics.md`,
`docs/adr/` and `tests/`. The run still starts, so `merge-ready` always
reports. `merge-ready` fails when a lane failed or was cancelled, and when a
lane the event requires did not pass: `check`, `sanitize`, `optimised` and,
when it applies, `fuzz-mir` on a pull request; `check` on a push; `check`,
`sanitize`, `optimised` and `fuzz` on a weekly or manual run. A lane skipped
because the change is documentation alone counts as passed. A draft pull
request is never ready. `sweep` reads a clock, so its failure is visible but
does not block.

Outside a push to `main`, `check` passes `-Dguide=false` and leaves the guide,
the library's own tests and the examples' own tests to `optimised`, which runs
them with the Debug compiler; a push to `main` runs them in `check`.
`-Dsequential` runs a test suite's heavy steps (the compiles of the compiler,
the conformance runner and the unit tests, the unit tests and the corpus walks)
one after another, unit tests first, through copies only that suite reaches;
`check` passes it to `test`, and `optimised` runs `test-unit` and
`conformance` as separate builds with it, so no two heavy steps share the
runner's memory. A push to a pull request or to `main` cancels the run it
supersedes. Only the unfiltered `test` verifies the whole graph; a narrowed
conformance directory is the development tool.

### Soundness, sanitizers and optimisation levels

`zig build soundness` holds the language's memory promise to generated
programs. It is its own step: `test`, `test-corpus` and `conformance` do not run
it, and the `optimised` CI lane does. Run it inside `nix develop` when changing
the ownership checker, the MIR verifier or the storage model; a warm run takes
about a minute with an optimised runner and six with a debug one.

The soundness matrix (`src/conformance/matrix.zig`) meets every operation that
may move, grow or free a `Vec`, a `Map`, a fixed array or an `[inout]`-lent
place with every live observation of it, in every statement context. Each cell
is written twice: with the observation used after the operation the program must
be refused by [O-Borrow]; with its last use before the operation it must be
accepted and run clean.

The step also checks `-Dstorage-programs=N` programs from
`src/conformance/storage.zig` (16 by default, seeds from `-Dseed`), built over
heap storage. Each must be accepted, run clean, compute the total its model
says, and answer alike at every optimisation level. Four mutants of each insert
an owner operation where an observation is live and must be refused by
[O-Borrow]. Reproduce a failing seed with `-Dseed=<seed> -Dstorage-programs=1`
and add its choice bytes to `tests/fuzz/corpus.zig` under `storage` with the
fix. The step fails when it built or ran fewer programs than it was given, a
missing tool included.

`-Dsanitize` watches the runtime's C code, every allocation and free through
the intercepted allocator, leaks at exit, and crashes. It does not watch reads
or writes in generated Linea code: the IR carries no `sanitize_address`
attribute, so a stale read in generated code is caught only by
the compiler refusing the program. `address` is the only sanitizer offered, and
its leak checker is the only run-time check that ownership abandoned no value.
A sanitized walk runs what runs -- the cases recording an exit status, the
examples and the transcripts that build or run a program -- and generates no
programs; the corpus-wide frontend and editor properties stay with the
unsanitized walk.

`-Dopt-levels=true` builds every corpus case that runs at every optimisation
level and holds it to the same exit and output. Pass it locally when changing
what the optimiser may see; it assumes a case's output is deterministic.

## Architecture

The compiler is a pipeline of passes over flat, index-addressed data:

```text
Source -> Lexer -> Tokens -> Parser -> AST -> Resolver / expansion
       -> Type Checker -> Ownership -> Instance discovery -> MIR -> MLIR
       -> mlir-opt -> MLIR bytecode -> mlir-translate -> LLVM IR -> cc
```

Resolution expands admitted derives into `ExpandedProgram`, preserving source
IDs and appending generated declarations. Resolution and type checking record
semantic facts in side tables keyed by the expanded tree's IDs; there is no
normalised HIR or typed tree. Ownership is a separate pass. Instance discovery
records the reachable concrete bodies and lowering materialises them as MIR. MIR
verification runs inside emission, so invalid compiler output has a separate
exit status from rejected source.

A representation is introduced when a named problem demands it.
`docs/architecture.md` records what each pass owns and what would have to be
true before another representation earns its place.

Module layout is one directory per pass under `src/`, with imports running
strictly forward: `support/` imports nothing from the compiler, `diagnostics/`
imports `support/`, and each pass imports only `support/`, `diagnostics/` and
the representation it consumes. Nothing imports `driver/`. A cycle in the module
graph is a compile error; `build.zig` gates the rest.

### Compiler invariants

These constrain every pass, including ones not yet written.

- **The frontend never fails.** The lexer has no error path: unrecognised bytes
  become `.invalid` tokens. The parser always returns a complete tree, emitting
  error nodes and recovering at statement boundaries. Problems accumulate in a
  diagnostic sink and only the driver stops, between passes. A formatter and
  language server must get a usable tree from broken source.
- **Cross-pass references are typed IDs.** Every reference crossing a
  representation boundary is a typed `enum(u32)`, never a pointer into another
  pass's arena and never an erased integer index. This keeps representations
  serialisable.
- **Layout follows access pattern.** Use structure-of-arrays where instances are
  numerous, traversals read a subset of fields, and cost scales with program
  size (tokens, syntax nodes, instruction streams). Use plain structs elsewhere;
  diagnostics are deliberately not columnar.
- **Representations are immutable once produced.** A representation is mutable
  only while its producing pass builds it. Later passes annotate through side
  tables keyed by its IDs.
- **A pass is a function from representations to representations.** No global or
  module-level mutable state and no caches outliving a call. A pass allocates
  from caller-supplied allocators, separating retained results from scratch when
  lifetimes differ; results never borrow from released scratch, and diagnostics
  use the supplied sink's storage.
- **A new representation must discard, add, or simplify.** Name which:
  information discarded, nodes added that no side table could key, invariants
  made simpler, passes simplified in aggregate, or backend independence
  improved. Otherwise use a side table.
- **One question has one answer, and one place that computes it.** A pass that
  needs what an earlier pass decided reads it, through a side table if there is
  none; where two passes genuinely ask at different times they call one routine.
  When the same sentence would describe two functions, one of them is the bug.
- **What a pass holds for one thing is sized by that thing.** A table kept per
  function, block or declaration is keyed by what that unit contains, never by
  what the program contains, and a question asked once per element is an index,
  not a scan. Two shapes cause nearly all violations: a table whose length is
  `programCount()` but whose lifetime is one function (quadratic memory before
  quadratic time), and a walk over every X inside a walk over every Y. Corpus
  cases are too small to show either. A comment arguing the cost is fine is not
  evidence: state the actual bound and what makes it hold.

## Language constraints

- **No operation has undefined behaviour.** Every operation produces a defined
  result or is a diagnosed error, independent of optimisation level. The
  compiler may not optimise on the absence of undefined behaviour.
- **An unused declaration is an error**, not a warning. A name beginning with
  `_` declares the value deliberately unused; the prefix marks intent only, so
  such a name can still be referenced.
- **A move is decided by position, not by syntax.** A consuming position takes
  an aggregate value regardless of its capabilities; scalar value positions take
  snapshots. A construct's branches (an `if`'s arms, a `match`'s arms, a block's
  tail) sit where the construct sits.
- **Copying and settlement are independent.** User-defined types are affine by
  default; `copyable` permits duplication and `linear` imposes settlement. Owned
  obligations propagate through wrappers. Built-in scalars and copyable
  payload-free enums use snapshot reads in scalar value positions; other
  duplication requires explicit `copy(value)` and Copyable. A concrete scalar
  copy is an error, while symbolic generic copying remains valid. Discard never
  runs cleanup.
- **A type's braces hold its representation and nothing else.** Behaviour goes
  in `impl`, which may sit anywhere in the module that declares the type. A
  modifier reaches exactly the braces it precedes.

Two design choices surprise newcomers. The token stream is **lossless** while
the syntax tree is **abstract**: comments are tokens, whitespace is the gap
between adjacent spans, and the token array reconstructs the file byte for byte
(a conformance property asserts it). And the tree keeps structure the
semantics do not need where tooling requires it: parentheses are a node, so a
formatter does not rewrite the programmer's source.

## Change workflow

### A change to accepted behaviour or diagnostics starts with a failing case

1. Add a permanent case that expresses what the language means.
2. Run it and observe the intended failure before implementing the change.
3. Implement the smallest answer consistent with the ADRs and architecture.
4. Run the focused case and the affected filtered checks.

A case written after the fix has never been seen to fail, and a scratch file
outside the repository is not a case. Every commit in `main` is green: the case
and its code land in the same pull request, which is squash merged, so the
branch tip that CI runs must be green.

A case says what the language means and nothing else. It carries no
"currently", no note about what the compiler does today versus what it should,
and the same ban on narration as code comments.

### Golden files

Goldens are generated, never handwritten:

1. Create the input and an empty expected-output file.
2. Run the filtered tests or the conformance runner on a narrowed directory and
   inspect the actual output.
3. Confirm the output is semantically correct.
4. Accept it with the conformance runner's `--update` mode on the same narrowed
   directory, with the compiler and runtime paths described above. A filtered
   `zig build test` skips the corpus walk, so `-Dupdate` on it updates nothing.

`--update` fills existing goldens, so create the empty file first. A case with
no golden is refused, because what the compiler did with it would be compared
against nothing. Never accept an empty or unread golden. Before a mass update,
check which failing goldens are behaviour (`.exit`, `.out`) rather than
location-bearing (`.stderr`, `.ssa`, `.mono`): the former moving is a behaviour
change. Exit-status properties and semantic source rewrites have no golden and
cannot be updated away.

The dump subcommands are debugging aids with no stability guarantee, exposed on
the command line only in debug builds; the dump functions always compile because
the conformance runner calls them. A format change churns the whole corpus, so
**a commit that changes a dump format changes nothing else**: the code diff then
proves no behaviour moved.

### Testing conventions

- Keep assertions general. `testing.assert` checks a boolean (including a
  `match read` expression); `testing.assert_eq` compares complete values,
  including enum payloads, and reports with `Debug` (it requires `Equatable` and
  `Debug`). For a pattern check use `assert(match read value { ... }, message)`.
  Add a specialised assertion only when it serves a common need across
  applications and substantially beats these.
- Examples perform real tasks (a discount example calculates a price, a score
  table reports standings). Keep assertions in tests; remove helpers whose only
  purpose is converting feature checks into exit-status scores or that ignore an
  argument. Such helpers belong in compiler fixtures.
- Keep a standard-library implementation's tests in the same file, immediately
  after the function they test; every `pub fn` gets one.

### Criteria for language, library, diagnostics and examples

A language change migrates affected examples, library callers, documentation
and tests together, and adds a teaching example when the feature deserves one.
Judge changes against these criteria; do not enforce syntax quotas.

- **Concepts compose.** Records describe parts, enums alternatives, `impl`
  behaviour. Matching, optionals, errors, generics, collections and resources
  work together without a separate idiom per pair. Prefer strengthening an
  existing concept or adding a library primitive over new syntax, and test an
  unsupported composition with real code before calling it ergonomic.
- **Common operations have a clear path.** A developer can find an operation,
  predict its error and ownership conventions, and use it without reading
  compiler code. Document missing capabilities plainly; never present a planned
  API as available.
- **Names and defaults explain roles.** Use named arguments where literals or
  similarly typed values conceal a role, and defaults where an API has an
  honest, stable common choice. Prefer inference where the initializer settles
  the type. Never hide allocation size, error policy or resource lifetime, and
  use positional calls where the intent is already clear.
- **Diagnostics enable the next edit.** Report the source problem, location and
  expected versus actual; show the declaration or earlier resource operation
  that explains it. Suppress consequences of an invalid construct but not
  independent mistakes. Suggest a correction only if it addresses the reported
  problem. A rule identifier alone is not enough.
- **Examples demonstrate solutions, not compiler mechanisms.** A substantial
  example explains a problem, shows how Linea reduces the work and keeps its
  limits visible; a small one teaches one useful operation. Both compile and run
  in the verification workflow.

## Before declaring completion

After implementation and focused verification:

1. Review the final work adversarially, including committed, staged, unstaged
   and untracked changes, with each reviewer in an isolated worktree (a
   reviewer proving a check can fail may edit tracked files). Fix in-scope
   findings and review the affected work again.
2. Audit the result against the original request: completeness, correctness,
   solution quality and scope left behind. Implementing part of a request
   correctly is as much a failure as implementing it incorrectly.
3. For compiler work, trace every touched semantic responsibility through the
   pipeline. Find duplicated semantics and obsolete predecessor paths, migrate
   remaining callers to the canonical path, and prove the old responsibility is
   gone when consolidation was the goal.
4. Run formatting verification and the final unfiltered `zig build test`,
   repeating after fixes until green.

## Cleanup policies

### Dead code is removed

Delete code that is no longer needed: unreachable code, unused functions,
types, fields and variants; obsolete passes, lowering paths, flags and
experiments; diagnostics and IR constructs carried without a consumer; branches
for states that cannot occur; infrastructure for hypothetical futures.

"Used by tests" is a reason to investigate. If a production API exists only
because a test calls it and is not a real compiler contract, delete both or
rewrite the test: tests justify production behaviour, not the reverse. Debug
dumps and malformed-input recovery are real contracts; evaluate their consumers
before calling them dead.

### No backwards-compatibility burden

Linea is unreleased. Do not preserve old behaviour because it existed, and do
not treat a persisted format or external consumer as an implicit compatibility
requirement. Remove superseded mechanisms (deprecated APIs, aliases, wrappers
around renamed APIs, legacy syntax, old options and formats, transitional IR
forms, shims, fallbacks, dual old/new implementations, and tests that only
preserve obsolete behaviour). Migrate callers and tests to the current model
and keep one canonical representation.

Ask: would we design this into the compiler today? If not, and nothing current
depends on it, remove it, within the change's scope.

## Zig 0.16 conventions

The standard library changed substantially; do not write code against older
APIs.

- `std.ArrayList` is unmanaged. Initialise with `.empty` and pass the allocator
  per call: `list.append(gpa, item)`.
- `std.MultiArrayList(T)`: `append(gpa, elem)`, `slice()`, `items(.field)`.
- `std.Io.File.stdout()` / `.stderr()`; `file.writer(io, buffer)` returns a
  struct whose `.interface` is the `*std.Io.Writer`. Flush writers.
- `dir.walk(gpa)` returns a walker whose `next(io)` takes the `Io`.
- Custom formatting is
  `pub fn format(self: T, writer: *std.Io.Writer) std.Io.Writer.Error!void`,
  invoked with `{f}`.
- `main` takes `std.process.Init`, which carries `minimal.args`, `arena`, `gpa`
  and `io`.

## Repository conventions

- ADRs are append-only. A decision that changes gets a new record marked
  `Supersedes NNNN`, and the original is marked superseded and otherwise left
  alone. Supersede only decisions that were built against; an option weighed and
  discarded belongs under *Alternatives considered* in the record that rejected
  it. Records still on an unmerged branch are rewritten, not superseded.
- A constructor or function that allocates has a system form and an `_in`
  form: `x(...)` uses the system allocator and `x_in(allocator, ...)` takes
  one, first after the receiver for a method. A constructor's base name says what it does: `new` builds and cannot
  fail, and `open` can fail or acquires a resource. An allocator built over a
  backing (`mem.Arena.open`) keeps its backing argument.
- A library states its allocator. In a library root, std included, every
  public signature writes the allocator of each type that takes one: a
  parameter `A: Allocator` where the caller chooses, `mem.SystemAllocator`
  written out where the restriction is intended, and no default on a public
  function's allocator parameter ([T-DefaultedAllocator]). Bodies, private
  helpers and programs keep the short form.
- Branch names are semantic and describe the code, never a milestone or plan.
- PR titles and commits use one semantic form, for example `feat(sema): ...`,
  `fix(mir): ...` or `refactor(support): ...`. A merge lands one squashed commit
  on `main`, so the title is what history reads as. Commit messages describe the
  code that landed, in present tense. Quote identifiers in commit messages from a
  file (`git commit -F`), since a backtick in `-m` runs as a command.
- Comments explain the code directly, concretely and without metaphor. Write
  "Use `env.args()` to access command-line arguments," not "A program reads the
  command line it was started with." A comment stands on its own: state the
  reason rather than citing where it is written down, and omit decision-log
  references, process bookkeeping, person names and narration of what the code
  used to do. Diagnostic rule codes are emitted names and are kept. Compiler
  comments may state internal invariants and architectural reasons. Markdown may
  cite ADR numbers freely.
- Example programs teach Linea. Explain what a construct does in that program
  ("`copy(step)` keeps the original step in the checklist"); omit compiler
  layout, pass mechanics and test-design commentary unless they are the subject.
  Plain teaching sentences about the construct, not verbless labels. Name files
  for the program's subject (`tournament_board.lin`), not implementation
  vocabulary.
- Hold the standard library to the same clarity. Write "NaN is the only
  floating-point value unequal to itself," not "What a float can say about
  itself." Name non-obvious numeric constants (`quiet_nan_bits`) and explain the
  representation, layout or units.
- User documentation teaches a beginner: a program per concept, real compiler
  errors, Rust parallels where they help. Learn chapters do not hand off to
  `std/README.md`, and every construct named in a section title gets its own
  example.
- Prefer inferred local types when the initializer determines the intended type:
  `let account = Account.open(100)`, not `: Account`. Keep annotations that
  supply context for `.Some`, `.None` or struct literals, constrain generic
  inference, select a non-default numeric type, or teach explicit typing; show an
  optional annotation once in introductory examples.
- A directory opened without `.iterate` walks on macOS and is refused on Linux;
  a green local run is Darwin evidence only. Sanitized programs hang on macOS
  (a toolchain issue), so verify sanitizer links locally and run them on Linux.
