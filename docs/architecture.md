# Compiler architecture

This document describes each compiler pass, the decisions it owns, and the data
it produces. Later passes read those recorded decisions instead of deriving
them again. This keeps language rules consistent across checking, code
generation, and tooling.

Module layering controls which components may import one another. The pass
boundaries described here also control which component is responsible for each
semantic fact.

## Ownership capabilities

Declaration policy is recorded by the parser as affine, copyable, or linear.
Typing computes `mayCopy`, `mustConsume`, and `mayDiscard` once over owned
parts, including certified out-of-line Storage contents and excluding borrowed
referents. Generic constraints grant Copyable or Discardable independently.
The baseline type-domain table and sparse `(scope, type)` capability facts cross
the boundary into ownership and lowering. The builder propagates constrained
capabilities through the same owned edges as baseline capabilities, including
cycles. Frozen queries read the prepared answers instead of walking
representations or guessing a lexical scope from a type argument. Neither
ownership nor lowering reconstructs capabilities from declaration modifiers.

Method applicability is prepared while the type pool can substitute constructed
predicate subjects. A receiver-head index selects candidate implementations;
the existing implementation checker supplies sparse `(scope, receiver,
implementation)` answers. Frozen compiler views and editor lookup read those
answers, including for borrowed referents. Predicate substitution has no second
implementation for immutable views, and lookup dependencies do not become
owned parts. Preparation visits reached receiver/candidate pairs plus the
canonical bound-solving work those candidates require.

Ownership decides whether a source expression is read, moved, or discarded.
The closed scalar snapshot classification supplies its value-position exception
and the authored-type redundant-copy diagnostic. Monomorphization does not
invalidate a checked symbolic generic copy. Observation projection and receiver
adjustment are likewise settled by typing and consumed by contracts, ownership,
MIR, and editor tooling.

## Numeric constraints and conversions

Closed Integer membership is recorded separately from the ownership capability
ordering. Normalized Integer evidence entails the existing Copyable capability,
which also permits discard, while authored symbolic parameters retain explicit
copy syntax. Inline, trailing and inherited bounds feed the same contextual
evidence queries.

The type checker records a conversion target against its call expression,
including symbolic targets and calls whose operands are subsequently rejected.
Ownership reads that record to classify the operand as an observation. MIR reads
the record and the instantiated expression type to emit the appropriate numeric
conversion and range check. These passes do not classify the callee again.

Symbolic numeric arithmetic and conversions retain runtime checks. Their
nonconstant classification is shared with the constant memo so defaults cannot
reuse an earlier syntax-only fold, including through grouped expressions.

A name written after a type's name that some trait declares, and that the
type's namespace holds as an operation or not at all, is not resolved by the
resolver: whether the type's own operation or a trait's answers depends on
what the call's module may name and what the type implements, which the
checker knows. The resolver records the selection in `Resolution.trait_selections`,
with every name selected after a type parameter, and the checker answers it
through `Reach.namespaced`, which lists the type's own operations the module
may name before the traits', read through `keepReached`, the rule the postfix
form reads. The traits are the ones the module sees and then, for a type
parameter, the ones its bounds and the `where` clauses in force name that the
module does not see, which `Reach` reads from the typing's bounds rather than
from the resolver's scope tables. The call is then an ordinary call of the trait's
signature whose `Self` is the type, recorded in `call_impls` as a call written
through the trait is; completion after the dot and the language server's
definition, references and rename read the same records.

Resolution records integer range selections as a namespace binding and endpoint,
without inventing a declaration for the property. Constant folding receives
concrete endpoint values through its name-provider interface, so array lengths
and coherence use the same TypeId bounds before typing. Typing validates Integer
evidence and records the receiver type and endpoint. Symbolic properties stay
nonconstant; MIR substitutes the recorded type and evaluates its endpoint.
Editor tooling uses the checked property and normalized Integer evidence rather
than a library declaration or a separate numeric type list.

## Array literal length inference

The parser records `_` in an array length as `TypeRef.inferred_length`, a
TokenId mutually exclusive with the explicit length ExprId. It is not an
expression or a name use. Formatting and syntax dumps retain the token; typed
ID relocation carries it with the rest of the written type. Resolution walks
only explicit length expressions. Written-type textual hashing and spelling
share `Ast.arrayLengthText`.

`Checker.bindingTypeCountingLiteral` resolves the array annotation dimensions
of a local binding or constant from its literal initializer, through grouping
parentheses. It reads each dimension's item count and first row without checking or evaluating elements. The ordinary
array literal checker receives the resulting concrete array TypeId and checks
every element and row. `arrayTypeWithElement` remains the single validator for
explicit constant lengths; an inference marker outside a supported local
literal is diagnosed at its token. No wildcard or runtime array representation
crosses the typing boundary. Ownership, instantiation, MIR, backend layout and
hover consume the ordinary concrete type. Shape inference adds O(d) work for d
nested array dimensions, with no table sized by the program or repeated walk
of sibling elements.

## Literals settled by use

An integer literal checked with no expected type gets an `open_integer` pool
entry naming a variable in the checker's `OpenTypes` table
(`sema/open_types.zig`), a union-find with one entry per such literal. A float
literal gets an `open_float` entry in the same table. Each variable carries a
family -- integer, float, or any for a function value's parameter -- which
decides what it may settle on and what it falls back to: `Int64` for an
integer, `Float64` for a float. Two variables of different literal families
never join. The
open type flows through expression, binding and instantiated types like any
other `TypeId`. `Checker.meet`, reached from `expect`, is the one routine that
settles or joins variables; parameter settling, callable bounds and index keys
call it rather than comparing types. `Builder.visitParts` is the one list of the
types each kind is built from, shared by `mentionsOpen`, forcing and structural
meeting. Operations that need a type immediately (receivers, `match`,
conversions, a generic argument nothing settled, an implementation query that
found nothing) fall back through `forceInteger`; each body falls back what it
left open when it finishes. A float literal converted to a float type settles
on the target instead, so it is rounded once.

`resolveAllOpen` runs after every body is checked and before the obligations
zone. It checks each value folded while open (literals, negations, arithmetic
results) against the type it settled to, rounds each open float literal at its
final width with `roundFloatLiteral` -- the one routine that rounds a float
literal -- and refuses one that rounds to an infinity or a nonzero one that
rounds to zero, resolves closure environment fields in
place, and rewrites the checker's `TypeId`-bearing tables and the builder's
recorded tables through `rewriteTypeIds`, which refuses at compile time any
storage it cannot follow. It then asserts that no expression type mentions an
open integer. Nothing downstream of the checker sees an open type through a
recorded table. The open entries themselves stay in the pool: passes that walk
every pool type lay them out as their fallback's size, and MIR represents them
as invalid, so a use that escaped would fail verification rather than lower.
The table and the pending list are sized by literal sites, each body's list by
that body's literals, and the finishing pass is linear in the tables it
rewrites.

## Function values settled by use

A function named as a value with no structural callable type flowing in gets
its declaration signature, with each type parameter it is written over -- its
own, a generic inherent head's, a trait operation's `Self` and its trait's --
replaced by an `open_type` pool entry. An open type is a variable in the same
`OpenTypes` table, marked as free to settle on any type rather than only an
integer; joined with an open integer it must be one. `Checker.meet` settles and
joins both kinds, so a call through the value, the parameter it is passed to
and an annotation settle it exactly as they settle a literal. `check` lets an
expected open type flow in as what it settled to, or checks the expression on
its own and meets the two while it is still open.

`selectFunctionValue` records the value in `function_values` at once, with its
type arguments and its `CallImpl` still open, and appends a `PendingValue`
naming it and its open types. Each body opens an `OpenScope` over both lists
and closes it when it finishes: open integers fall back, then each pending
value of the body reads its types through the table. One still open is
[T-Infer]; a settled one has its bounds, and a trait operation's
implementation, checked through the routines a call uses. `resolveAllOpen`
rewrites the recorded value like every other table, so discovery and lowering
see only concrete types. The pending list holds only the open bodies' values,
and each is visited once when its body closes.

A value's `CallImpl` is the record a call to the same declaration makes: the
receiver of a generic inherent member, or a trait operation's trait, trait
arguments and `Self`. Discovery's `implementedBody` and lowering's
`calleeThrough` read it for calls and values alike, so a converted operation
and a called one name one instance. Both choose the body through
`valueMember`, which also names a `BodyOrigin.built_in` for an operation the
compiler provides; lowering fills that body with `builtInOperation`, the
routine a direct call to the operation lowers through.

A callable type's identity leaves out parameter names, so the pool interns
one entry per signature and spells it without them. A named call through a
value reads its labels from the syntax that declared the callee, through
`Checker.calleeLabels`: a written `fn` type, a callable bound, a kept closure's
signature argument, or the function or lambda a local was bound to, recorded
per binding in `binding_labels`. `CallParameters.labelled` carries them into
the one argument matcher.

## Type arguments named at a call

Brackets directly before a call's arguments, after a name or a selection, are
read twice by the parser: as the index expression, and through
`parseWrittenType` as a list of types. Each reading runs as an `Attempt` that
is kept only if it reads the brackets whole without a diagnostic; a failed
one is rolled back through `Ast.Builder.checkpoint` and `rollback`, including
its diagnostics. The type reading lives in `Ast.bracket_types`, keyed by the
index node; where only types were read, the index is an unreported `.err`.

The resolver records what each such bracket holds in
`Resolution.bracket_readings`. A head naming a function, or a trait's
operation through a type, takes the type reading, resolved with the
`type_argument` context. A selection from a value
is a method or a field, so both readings are resolved and what each would
report is kept in the `member` entry. Every other head is indexed.
`Checker.checkBracketCall` is the one decision after that: for a selection it
runs `postfixCall`, the lookup every postfix call uses, emits the chosen
reading's deferred reports, and passes the written types to `checkCallOf`,
where they seed `inferCall` for the function's own parameters. The call record
carries `written_type_arguments`; `calleeName` and `postfixSelection` give later
passes and the language server the name in front of the brackets.

## The pipeline

```text
                              +-------+
                              | Start |  linea <command> <path>
                              +-------+
                                  |
                                  v
                      +-----------------------+
                      | Read the command line |   one table describes
                      +-----------------------+   every command
                                  |
              fmt / dump-tokens---+---everything else
                      |                       |
                      v                       v
             +-----------------+   +-------------------------+
             | Lex / parse,    |   |  Load                   |<------+
             | and stop        |   |  a module is a          |       |
             +-----------------+   |  directory of files     |       |
                      |            |  +-----+    +-------+   |       |
                      v            |  | Lex |--->| Parse |   |       |
             +-----------------+   |  +-----+    +-------+   |       |
             | Rewrite / print |   +-------------------------+       |
             +-----------------+                |                    |
                      |                   ------------------    Yes  |
                      v                  / another file, or  \------+
                   +-----+               \ an import to follow? /
                   | End |                ------------------
                   +-----+                         | No
                                                   v
                                    Program: every source module reached,
                                    one source Ast for tools and expansion
                                                    |
                                                    v
                                         +------------------------+
                                         | Resolve names; expand  | every module
                                         | admitted derives       | before any is
                                         +------------------------+ typed
                                                    |
                                    ExpandedProgram + Resolution
                                                    |
                                                    v
                                        +---------------------+
                                        | Type check          |
                                        +---------------------+
                                                   |
                                                   v
                                        +---------------------+
                                        | Ownership           |  always, even
                                        +---------------------+  if the checker
                                                   |             reported errors
                                                   v
                                          ------------------
                                         / errors in the    \  Yes  +-----+
                                         \ diagnostic sink? /------>| End |
                                          ------------------        +-----+
                                                   | No              exit 1
                                                   v
                                        +------------------------+
                                        | Discover concrete      |
                                        | instances; check their |
                                        | limits                 |
                                        +------------------------+
                                                   |
                                                   v
                                          ------------------
                                         / discovery errors? \  Yes  +-----+
                                         \                  /------>| End |
                                          ------------------        +-----+
                                                   | No              exit 1
                        check ---------------------+
                          |                        |
                          v                        v
                       +-----+          +------------------------+
                       | End |          | Lower to MIR           |
                       +-----+          | one function per       |
                        exit 0          | concrete instance      |
                                        +------------------------+
                                                   |
                                                   v
                                        +------------------------+
                                        | Emit MLIR              |
                                        |  +------------------+  |
                                        |  | Verify the module|  | refuses ->
                                        |  | before writing   |  | exit 70
                                        |  +------------------+  |
                                        +------------------------+
                                                   |
                            emit-mlir -------------+
                              |                    |
                              v                    v
                           +-----+       +--------------------+
                           | End |       | mlir-opt           |  MLIR bytecode
                           +-----+       | mlir-translate     |  textual LLVM IR
                                         | cc -> native file  |
                                         +--------------------+
                                                   |
                                    build ---------+--------- run
                                      |                        |
                                      v                        v
                                   +-----+          +---------------------+
                                   | End |          | Execute; return its |
                                   +-----+          | exit status         |
                                                    +---------------------+
```

Commands stop at the stage that supplies their result:

| Command | Result |
| --- | --- |
| `dump-tokens` | Tokens from the input file; no semantic checking |
| `fmt` | Formatted source after parsing; no semantic checking |
| `check` | Diagnostics through instance discovery; exit 0 on success |
| `emit-mlir` | Verified MLIR text |
| `build` | Compiled executable or library object |
| `run` | Executes the compiled program and returns its exit status |

Loading follows imports until all reachable modules have been read. A module
is a directory of source files. Source-only tools retain the original syntax
tree; semantic passes use the expanded tree described below.

## The representations

There is one additional syntax representation between the source tree and MIR:
`ExpandedProgram`. Per ADR 0015 one is introduced only when it discards
information, adds nodes no side table could key, simplifies invariants or
passes in aggregate, or improves backend independence.
Derivation adds ordinary implementation and function nodes which do not exist
in the source `Ast`, so no side table over that tree can hold them. There is no
normalised HIR or typed tree. Per ADR 0012 later passes annotate the expanded
tree through **side tables** keyed by its own IDs; types and names key cleanly
onto those IDs, so they remain tables.

Resolution appends generated syntax during expansion, then records name
bindings in side tables. Type checking adds its own side tables. Neither pass
lowers the expanded tree into a different semantic representation.

| Representation | Produced by | Shape | Holds |
| --- | --- | --- | --- |
| Source text | the loader | bytes per file | — |
| `TokenList` | `lexer.tokenize` | structure-of-arrays | every token, losslessly: comments are tokens, whitespace is the gap between spans |
| `Ast` | `parser.parse` | typed per category | declarations, statements, expressions, written trailing constraints — abstract, but keeping what tooling needs (parentheses are a node) |
| `Program` | `driver/loader.zig` | source modules + canonical import routes + one source `Ast` + embedded files | every source module the entry reached, its independently loaded root and root-relative source spelling, the single source tree used by expansion and source-only tools, and the bytes of every file an `embed` or `embed_bytes` read with the expression that read each (`Program.embeds`) |
| `ExpandedProgram` | `sema/resolve.zig` | source `Program` + expanded `Ast` + flat tables | the source IDs as an exact prefix, the expanded interner and owned generated sources, immutable active declarations and generated import targets per module, constant-time declaration ownership, generated-to-derive origins, resolver-paired template member plans, and immutable generated-implementation descriptors with component-requirement rows |
| `Resolution` | `sema/resolve.zig` | side table over the expanded `Ast` | `targets`, `written`, `kinds`, `decls`, `type_names` with the trait rows indexed by module and by member name, `prelude`, qualified variant ordinals, references in constraint subjects and requirements, binding and lexical-scope tables, and both directions of `ExprId` ↔ `ClosureId` |
| `Typing` | `sema/typecheck.zig` | side table over the expanded `Ast` | the type `pool`, expression and binding types including `Never`, checked literal and named constant values, interpolation value formats, normalised declaration constraints, capability and implementation-applicability answers, closure descriptors, function values, normalised call targets and arguments with their shared `call_index`, private storage declaration identities, context-dependent variant selections, implicit test-success sites, and match payload-disposal facts, implementations, instantiations, layouts, and generated member bodies suppressed during semantic recovery |
| `Cfg` | `ownership/build.zig` | blocks, ops, and ordered schedule placements | separate control flow *for the ownership rules* for each declaration body and accepted lambda body, built and discarded within `check` |
| `mir.Module` | `mir/lower.zig` | explicit control flow | `functions`, `names`, `origins`, the byte pool, read-only `statics`, `layouts`, type `representations`, instruction result roles, local slot roles, normal and noreturn call forms, message-bearing traps, the optional `zeroed_allocator` identity, `entry` — and a copy of the `Typing` it was lowered against |
| MLIR | `backend/mlir.zig` | text | — |

The source `Program` supplies formatting and editable source locations. After
resolution, semantic, ownership, instantiation and lowering tables refer to the
expanded tree. Source IDs retain their numeric values because each source ID
domain is an exact prefix of its expanded domain. Later passes can therefore
look up name and type decisions directly from expanded IDs. `mir.Module` also
carries `Typing`, so the verifier and backend can read the same type facts.

## What each pass decides

Each entry identifies the pass responsible for a decision, where it records
the result, and how later passes use it.

### Lexer — `src/lexer/`

Owns: what a token is, where it starts and ends, and which words are reserved
(`token.zig` `reserved_words`, public so the editor grammars are gated against
it). Comments are tokens; whitespace is the gap between adjacent spans, so the
token array reconstructs the file byte for byte and a conformance property
asserts it.

Unrecognised bytes become `.invalid` tokens rather than stopping lexing.

Inside an interpolation the lexer keeps the brace, parenthesis and bracket
depth of each open level. A colon where all three are zero is the value's
format separator, and the text after it up to the closing brace, less the
spaces around it, is one `format_spec` token.

### Parser — `src/parser/`

Owns: tree shape. What is a declaration and of what kind, what a statement is
and where it ends (ADR 0196: a newline ends a statement after a token that
can end one, unless the next line opens with `.` and a lowercase name, which
`Tag.continuesTheLine` states and `finishedAtALineBreak` asks), what nests inside what, and how deep nesting
may go (ADR 0042, ADR 0054).

`defer let x = e` (ADR 0208) is expanded here, the one place, into the pair it
is defined as: a `let_decl` whose tokens begin at `defer`, then a
`defer_release` statement holding a call on the binding's name. The call has no
written operation, so its callee is a `name_ref` at the `defer` token that
resolves to nothing, and its tokens stop at the name so the initialiser is not
inside the schedule. Resolution resolves the receiver; the checker finds
`Release.release` through `postfixOperation`, the lookup `x.release()` is
answered by; ownership and lowering read the pair as two statements. The
formatter prints the pair as the one form and skips the second statement.
Conformance writes a `defer let` out as the two statements and holds the
rewrite to the same code (ADR 0045).

A tuple has three node shapes: `tuple_literal` and `tuple_pattern`, both
call-shaped, and a `.tuple` written type whose components are its arguments.
The parser refuses a component count outside `node.isTupleArity` as
`[S-Tuple]` and keeps `(x)` a parenthesised node.

A named structure literal stores the canonical written type in
`Ast.struct_literal_heads`, a `TypeRefId` side table keyed by its expression;
contextual literals store `.none`. The parser uses the same `TypeRef` grammar
as every annotation. Its syntactic brace decision uses a delimiter-end cache
sized to the current file's token range; each balanced region records all
nested endpoints it crosses, so nested generic lookahead is linear in that
file rather than rescanning each suffix.
A structure literal's `..base` occupies the callee slot of its call payload,
read through `Ast.structLiteralBase` (ADR 0183); its field/value pairs keep
their alternating layout.

Panic is its own expression node because no existing node can retain its
message subtree and written location. An interpolation has a dedicated
two-index payload: one run of alternating text/value expressions and one
compact run of fixed-size formats, one per value: `Debug` or `Display` and the
layout its format spec asks for. The parser reads each `format_spec` token
through `syntax/format_spec.zig`, the only reader of spec text; later passes
never re-read the spec. A trailing
`where` clause remains written
declaration data: formatting and tools need its subject and requirements in
their source shape even though type checking later normalises their meaning.

Nesting is bounded at `node.max_tree_height` (1000) levels of expression,
pattern or written type ([S-Nesting]). The bound is on tree height, not parser recursion:
a left-leaning chain such as `a + b + c + ...` or a run of `.` selections parses
in a loop but yields a tree as tall as the chain, and every later pass recurses
over it. Acceptance is the same in every build because the passes run on a
thread with a 256 MiB stack (`support/stack.zig`), sized for the bound in the
largest Debug frames.

Returns a complete, recoverable tree even for malformed input. The parser
inserts error nodes and resumes at statement boundaries so tools can inspect
incomplete source while the programmer edits it.

### Loader — `src/driver/loader.zig`

Owns: which files form a module (ADR 0032 — a module is a directory), which
modules the entry reaches, how an import path resolves, and where the standard
library sits. It assigns every module the typed identity of the independently
loaded root that owns it; primary, standard-library and dependency roots remain
distinct even inside one compilation. Root identity does not replace the
separate standard-library authority bit. Loops until no import is left to
follow; primary imports are root-relative, an import starting with `std` reaches
the `std` dependency, and early module registration makes import rings finite.
Which root is the standard library, and which roots may declare `extern`, is read
from each root's manifest (`Declared`) and recorded on its modules (`library`,
`externs`); no pass decides it from a directory's spelling. A root whose manifest
names it `std` is loaded as the library itself, with no embedded copy beside it.
`rootOf` finds a root and the manifest that identified it in one walk, and
`pathsOfRoot` gives the command line and the language server the same files,
manifest included. A module's symbols are spelled from its import route
(`Program.modulePath`), never from its directory. A function's symbol ends
that route with `;`, the root's empty route included, and brackets the
arguments an implementation supplies its trait, so no two declarations share
one whatever their names are spelled (`instantiate.symbolFor`).
`Program.importRoute` is the only later-pass API for reproducing a loaded source
route.

Before the first module is loaded, the loader reads the dependency graph: the
root's manifest names libraries under `dependencies`, each library's manifest
may name more, and `dependencies.zig` reads each entry with the span it is
written at. A library is identified by its directory, spelled by `joinedDir`
for disk and memory alike, so a library two manifests name is one root.
Dependency roots take `RootId`s from 2, depth first over each manifest's names
in order. A refused entry is [M-Dependency], reported against the manifest's
text, which only then enters the file table. The result is `Program.roots`,
one `RootFacts` row per root: its name, its source directory, its root module
and the roots it depends on. `Program.importRoute` reads the edges.
`Program.inLibraryRoot` reads the module's `RootId` and `library` bit and the
primary root's `kind`, which the loader records beside the table rather than in
it. On disk a library is identified by its real path, so one library spelled
two ways is one root. An import whose first element names a dependency of the
importing root resolves beneath that library's source directory, and only the
importing root's own manifest is consulted; a directory holding a
manifest is never a module of the root above it (`pathsOfModule` lists its
manifest and stops there), and `pathsOfRoot` adds every dependency's files, so
the command line, the language server and the conformance runner load the same
graph.

The loader also reads every file an `embed` or `embed_bytes` names, as each
module is parsed (ADR 0227). A path is relative to the writing file's directory
and bounded by its root: the directory of the root's manifest, the standard
library's own directory for the library, or the file's directory where no
manifest marks one. `driver/embedded.zig` resolves the spelling for every input
and reads a path on disk one component at a time, so each is found by its
exact spelling and no symbolic link is followed. In-memory input finds the
file among the supplied files; an editor's input copies its buffers and reads
embedded files from disk. Each file is read once per compilation, its bytes
have the sources' lifetime, and [M-Embed] or [M-EmbedText] is reported against
the literal naming it. No pass after the loader reads a file: the checker, the
constant folder and lowering read `Program.embeds` through `Resolution.embeds`.

Disk loading indexes source paths beneath the root, then reads source bytes
only when their module is reached. Test discovery reaches every module in the
requested directory root; ordinary compilation follows imports. In-memory and
embedded library sources retain their supplied bytes and share the same module
index and reachability traversal.

The standard-library manifest ships separate ownership modules: `std.text` for
`Str` and text operations, `std.io.core` for I/O protocols, failures, descriptors
and output, and `std.fmt` for rendering traits and implementations. `std.io`
publicly re-exports the core declarations and defines buffered I/O, whole-input
reading and prompts. `std.fmt` publicly forwards `core.Writer`; the prelude
forwards `text.Str`, `fmt.Display` and `fmt.Debug` because string literals and
interpolation depend on them, and `fmt.Writer` as part of the core vocabulary.
Its text, formatting and testing dependencies reach the I/O core without
loading the full I/O module. Opaque text crosses from
text to I/O through one root-internal operation, and generated test and
entry-point calls identify their private targets as `core.report` and
`core.ran`.

The prelude imports every library module, so their implementations are loaded
and available to lookup even when a module exports no name the prelude could
reference; the prelude's imports are therefore exempt from unused-import checks.
A directory identifies one module however many import routes reach it, and the
loader keeps one canonical route per module for generated source.

The loader owns module-loading decisions; the rest of the driver coordinates
passes. Passes must consume the loader's recorded results without importing
`driver/`. The driver imports every pass, so a reverse import would create a
dependency cycle even though Zig permits such cycles between files.

### Resolver — `src/sema/resolve.zig`

Owns: **which declaration each name refers to**, whether found locally, through
an import or re-export, or in the prelude. A module's scope holds its own
declarations first and then each prelude binding whose name it does not
declare, so a module's own declaration or `use` shadows a prelude name. Syntax
that needs a prelude declaration reads `Resolution.prelude` by identity rather
than a module's scope. It also records binding kinds and uses, the visibility of each exported name, and whether a bound names a
capability or a trait (`boundNames`). Qualified lookup, re-exports and tool-facing
member lists use the same stored visibility and the same predicate to check
access from the requesting module or root.

A re-export binds the original declaration, so following a chain of re-exports
costs no more than following one alias, and visibility is checked at each `use`.
Unused bindings are reported by the resolver ([N-Unused], [M-Unused]) with two
deferrals. A `use` that binds a trait is never reported, because methods reach
the trait without naming it and which calls did is the checker's answer, made
after this pass. A function or import named only by postfix calls is left to the
checker (`reportDeferredUnused`), which knows whether each call reached an
operation or was refused as naming a free function.

Also owns lambda source identity and lexical parameter scope. It allocates one
`ClosureId` per lambda expression, records both directions of that relation,
resolves capture sources and defaults at the outer site, then opens the lambda's
capture and parameter scope. Explicit capture rows retain the alias binding,
source expression and convention. A separate reference record identifies a body
name that crosses the callable boundary without a declared capture.
No later pass infers a closure identity or decides whether an outer spelling is
a capture.

Also owns what an `alias` name is: it binds under the kind `type_alias`, which
the type tables and qualified lookup accept. After the annotation walk it
refuses every alias reaching itself through the type it names ([N-TypeAlias])
or reaching further than what it names ([M-Vis]), reading each alias's tokens
once, and records in `Resolution.alias_heads` the type name each alias is
headed by. A path, a call, a constant fold and completion after a dot read
that table through `throughAlias`; an `impl` head through an alias is refused.
A generic alias heading a path is read by the checker, which settles its
parameters from the call (`settleAliasHeading`).

Also owns the answers other passes would otherwise rework. `Resolution.refused_impls`
records every `impl` it refused. The overlap check does not report a pair holding
one a second time, and a call to an operation such a block declares is not
reported as an unknown operation: the refused `impl` is the one mistake, and the
call to what it declared is not a second. Whether two written types name one type
is `sameWrittenArgs`, the one comparison coherence reads for the trait arguments
of two implementations and bounds read for the arguments of two bounds on one
parameter, so a repeated bound and a duplicate implementation are decided alike.
It compares by the type each written name reached, bare or qualified by the
module that declares it or by one that re-exports it, and by spelling only for a
name that reached no type, such as a header's own parameter. An alias is the
type it names: its parameters stand for the arguments written at the use, so
`Swap[UInt8, Bool]` with `alias Swap[A, B] = Pair[B, A]` is `Pair[Bool, UInt8]`,
and an alias reached again inside its own text is read as spelled instead of
expanded. Array lengths and callable defaults compare by the value they fold to,
and a pair that does not fold compares as spelled. The one place the answer is
undecided is a name that has not been resolved yet, which the resolver reads
while it builds scopes: such a name compares as spelled. A bound is paired
with the earlier bounds on its parameter through a table keyed by the trait and
the hash of its written arguments (`hashBoundArgs`, which reads the text as the
comparison does), so pairing allocates linearly in the bounds on one parameter. A type written with
aliases stands for the tree of their expansion, which nesting alias uses
doubles at each level, so neither the comparison nor the hash expands what it
can avoid: two uses of one alias with the same arguments are one type without
being expanded, the hash reads at most its first 256 nodes (a coarser key,
which costs a comparison and never an answer), and the comparison reads at
most 65536 nodes before it answers that the two are not provably one type. The
walk that settles array lengths reads each alias's text once for the run.
Time on a nested alias chain is therefore linear in the aliases written when
they take no parameters; an alias with parameters still substitutes its
arguments through everything it names at each level, which the checker pays per
level and which a sweep does not cover.
`Resolution.aliasReachedBy` is the one test of whether a written name reached an
alias.

Also owns **[N-Case]**, once its bodies are walked. Names a declaration writes
are read row by row from the source tree's declaration, import-path,
type-parameter, field, variant, parameter and capture tables; names a body
binds by a statement or a pattern are read from the bindings the walk made, so
which pattern arguments bind names keeps one answer. The kind each declaring
token was checked as is recorded in `Resolution.name_kinds`, keyed by the
token, and the case a kind requires is `name_case.Kind.case`; a rename reads
both rather than classifying a name again. Refusals are reported in source
order. The work is linear in those tables and the bindings. Whether a
respelling would be declared twice is asked of the tables [N-Duplicate] reads
-- a module's run, a type's members -- or of the one list the name was written
in, gathered once per list holding a refusal.

Also owns structural-template expansion. The parser retains closed attribute
groups and normalizes representation policies onto their nominal declaration;
attached trait entries reuse the derive-trait table and the declaration stores
their contiguous range. The resolver registers all source declarations and
resolves source struct/enum bounds and representation annotations before
rendering, so copied component types carry canonical parameter and import
bindings. Fresh resolution skips those annotations in its later expanded-tree
walk; a resumed application resolves its own declarations in that walk while
reading the retained library prefix. Template and derive headers use the same
source module scopes, and immutable template-member plans precede generation.
An admitted template validates each nonambient free reference once against the
trait's reach and retains its canonical declaration and trait-module member
binding. Attached and standalone requests enter one expansion path. An admitted derive is
rendered as an ordinary implementation in the target module. An attached
request on a generic type also renders one trailing predicate per distinct
field type naming a type parameter, bounded by the template's component
requirements at the entry's arguments, so selection reads the condition as it
reads a written one;
a foreign trait adds an ordinary import using `Program.importRoute` and a
collision-free alias. Generated imports, implementations and functions are
parsed into appended IDs, registered and resolved like other active
declarations. Source template declarations, their members and derive requests
stay queryable in the exact source prefix but are not active semantic roots.

Reflection is planned during that same lexical member walk. Per-member case,
same-case, component-loop, component-place, metadata and ordinal rows retain
resolved binding identity and are sorted once by source expression ID. The
renderer consumes them before the expanded tree freezes: structs and newtypes
become one ordinary case, enums become one ordinary arm per variant,
component loops become one ordinary block per component of the active case,
and `component.of(subject)` becomes the binding introduced for that subject.
Metadata becomes ordinary literals and `reflect.ordinal_of` becomes one
ordinary match that evaluates its operand once. An uninhabited enum produces an
ordinary empty match. No reflection descriptor crosses into an active
declaration. Planning is linear in the member tree plus one sort of each
member's rows; rendering is linear in the generated output, including the
deliberate case-by-body and component-by-body products.

Construction plans expand a product recipe once per field, in declaration
order, followed by unit-valued finalization and one complete constructor.
Recipe bindings are renamed by resolved identity; generated fields are moved
into the result. Explicit source defers retain the ordinary failure-cleanup
and move-cancellation rules. Target and template argument mappings are separate:
field types use target arguments, while trait requirements use template
arguments. Recursive written type selections keep substituted composite bases
in ordinary source. No construction descriptor reaches ownership or MIR.

Each admitted derive trait also produces one immutable generated-implementation
descriptor. Component requirement rows are grouped by descriptor in case,
component and template-bound order; each names its source template requirement
and typed case and component ordinals. The descriptor remains even for an empty
product or uninhabited enum, so a poisoned template requirement has explicit
evidence without a fabricated component row. These rows cross only to the
checker and never become generated constraints or a second implementation
relation.

An implementation row records whether its ordinary generated declaration came
from a derive request. After component admission, the checker uses the existing
implementation index to select each direct supertrait at the dependent derive's
normalized head and constraint environment. It requires that row's derive
provenance; ownership sees only the resulting accepted or suppressed generated
body list and never interprets provenance.

The result is `ResolveResult { expanded, resolution }`. `expanded` owns its
expanded `Ast`, expanded interner, generated source buffers, member plans,
declaration origins, fine-grained rendered origins, declaration-to-module table
and flattened active declaration lists. A file-local segment index maps
generated diagnostic spans to their template-expression and component origins;
each origin also names the derive's target, so `generatedComponentName` spells a
generated component binding as its source field and
`collapseGeneratedDiagnostics` points a generated diagnostic at that field. The
renderer records a component origin for every binding a case pattern writes.
`moduleOf` and `declsOf` are the answers later passes read; generated
declarations mean a module is not one contiguous source declaration range. The
source `Program` is retained by reference rather than changed into the semantic
root set.

The conformance harness reads the same immutable generated-source rows as
`dump-expanded`, removes admitted primary-root derive declarations and imports
used only by them, and reloads the generated files as ordinary module source.
It compares checking, ownership, normalized MLIR and runtime streams against the
original program; it never parses dump output.

The resolver registers `Never` as a primitive binding and resolves every name in a trailing
constraint's subject and requirements into the normal reference index. It does
not choose a type for panic; it resolves names in the message expression. It
also does not discharge constraints. Associated members are
resolved against the complete written constraint set, not predicate order.

Resolution has two phases (ADR 0023): it registers declarations in every module
before walking bodies, so declarations can refer to names declared later.

A name is unique only *within* a module. Resolved references therefore store a
`DeclId`, which distinguishes declarations with the same spelling in different
modules.

The signatures the runtime declares for its `linea_` symbols are one table in
`support/runtime_symbols.zig`, checked against the runtime's own sources so the
two cannot drift. `checkRuntimeSymbol` holds every `extern` of a `linea_`
symbol to that table ([T-ExternRuntime]), in the standard library and any other
root alike, which is why such a symbol needs no separate agreement check.

`seedProvidedImplementations` registers compiler-provided primitive and array
implementations in the same relation as written implementations. Coherence
checks and bound lookup therefore use one path for both kinds of implementation.
An array row for `Equatable`, `Equivalent`, `Comparable`, `Ordered`, `Hash` or
`Debug` is viewed: it applies where the implementation for the array's
`mem.Slice` view does, and `implementationChoice` records its selection as that
implementation, keeping the array as the receiver and naming the view the
implementation runs for. Discovery and lowering read that one choice; lowering
passes each whole-`Self` argument as the array's view.

### Type checker — `src/sema/typecheck.zig`

Owns: expression and binding types, generic instantiations, implementation
selection, the meaning of `Self`, and type layouts.
`Resolution.tuple_decls` is the one table from a tuple's arity to the prelude
declaration `Tuple2`..`Tuple8`, read as the `Option` and `Range` declarations
are; a `.tuple` written type is an instantiation of the arity's entry, and
`Builder.instantiate` and `writeTypeName` spell it `(A, B)`.
An instantiation whose arguments hold a type parameter or an unsettled
reference is minted with its parts unwritten (ADR 0248); `Instance.parts`
records which, and `Builder.fillInstance` is the one routine that writes an
instantiation's parts, for a ground one as it is minted, for an unwritten one
on first read, and for every written one in `refillInstances`. An
alike instantiation (ADR 0251) -- one whose arguments are distinct
parameters promising, position for position and once each candidate's
arguments are written as their positions, what another candidate of its
declaration promises -- is answered from its class's representative while
its parts are unwritten, the template wherever the template is alike it.
`Builder.watchAlike` makes each minted instantiation and its template
candidates; `shapeOf` interns what the argument at each position promises,
its requirement, `Integer` and `Owned`, renamed bounds, and the settled
references read through it promised `Owned` whose member the template's
parts read (`membersRead`, which reads every member until
`templatesComplete`); `decideAlikeAgain` recomputes the positions listed
under a parameter whose promise changed, once per declaration whose clauses
changed it, and moves each candidate whose
shape changed to the class its shapes name, and `Instance.class` with
`Typing.alike_sources` is the decision both the builder and the finished
pool read. `Typing.partsSource` is the one routine every walk over what a
type owns steps through: the capability, dependency and `unshareable`
tables record an alike instantiation as one edge to its representative, the cycle walk and
the walk over what types own step to it, and writing a type does not write
such a part. Every other unwritten part is written with its holder, so a
walk over parts meets no unwritten type but an alike one. The builder's part
accessors write what they read, and its capability, dependency, writer and
`Shareable` queries write what they cannot answer from a representative; the
four fact tables record a type's edges once its parts are written and leave
an unwritten part that is not alike for the builder to write before
answering, except that the writer and `unshareable` tables record an
unwritten instantiation that is not alike by its arguments, which usually
settle it. Within a scope whose constraints cap a
capability beyond what their subjects promise (`capsBeyondPromise`),
`prepareScopedCapability` writes the type a question names where it is
alike, and steps from every alike instantiation past it to its
representative with the scope's caps renamed onto the representative's
arguments, sharing the answer with every scope whose caps rename alike.
Rebuilding the capability facts drops every scoped answer and lists each
question prepared so far as lost (`ScopedCapabilityFacts.drop`), and
`finish` prepares each again (`restoreScopedCapabilities`), so the finished
pool answers every scoped question the checker prepared.
`fillMinted` writes every instantiation the
checker minted before the pool is handed on, following only parts that are
not alike, so the type of every recorded expression, binding and signature
is written and an alike instantiation stays unwritten only as a part. The
finished `Typing` answers what such a part owns through its tables and
`partsSource` (`readsFacts`) and refuses a read of any unwritten type's
parts or layout (`readsParts`); lowering's layout table, the layout oracle
and corpus coverage pass over one.
`aliasedType` is the one place an alias becomes the type it names, read in the
alias's module with its parameters in scope; `appliedAlias` answers every
written name that reaches an alias and substitutes its arguments, and a path's
type, a variant's, a callable bound's signature and a call's implementation
head read it. The declared-parts measures, which run before types are minted,
treat an alias as a declaration whose written type is its one part. No alias
type exists in the pool, and `Typing.aliased` records each alias's answer for
tooling.
Declared answers are settled on demand (ADR 0241).
`readPartShapes` reads every part once for callable shapes before
implementation heads exist. `settleDeclaredAnswers` then reads each part,
settled type, field-delegation element and alias once, the first time
something needs it. `readPart`, `AnswerSettling.settle` and `aliasedType` are
the routines that read them, and `AnswerSettling.owned` reads everything a
type owns before the builder asks a capability or an implementation of it.
The builder reaches those last two through `Builder.demand`. A demand that
reaches an answer still being read is a cycle, reported where it closes. A
capability read of a type waiting on its own settled part is caught through
`Typing.CapabilityWatch`. A part replacing one that gives its owner nothing
in a table -- poison, or a type built from it such as `[poison; 2]` -- adds an
edge to that table, and a callable shape gaining its effects changes nothing
a table reads, so the capability and containment tables are not rebuilt as
parts are read (`Builder.partChanged`). `readPartShapes` records in
`unsettled_parts` the parts whose first reading passed over a settled
reference; only those wait on settled answers, and `AnswerSettling.owned`
reads only those, in one depth-first search over owned parts shared by every
nested question (`OwnedWalk`), whose strongly connected components are each
decided once. A chain of answers passes through at most 1000 links, settled
references that read another answer and aliases ([T-AnswerDepth]);
`AnswerSettling.enter` and `leave` record each answer's height in links.
`Typing.Builder.implementationRow` retains concrete implementation selections
for instantiation and emission. A derived `Release` component that is discardable and not proven to implement
`Release` under the derive's own constraints is recorded in the checker's
discarded components while component requirements are checked, and its
generated release call is checked as a call to `release.discard`. Before any of
those choices, the checker withdraws the `Release` field requirement of every
discardable component from every attached derived `Release`, so each choice
reads final predicates whatever the declaration order. Selection holds an exact cycle that passes
through a derived implementation, decided from the lookup's stack of keys, and
records no answer resting on a cycle until the key it closes at is settled. The checker also verifies that a `proj` body
is a place (ADR 0088), using the same path walk as ownership so both passes
recognise the same places.

Ordinary implementation heads are either constructor keys or bare parameters.
The index combines a receiver constructor's chain with a trait-local parameter
bucket. Full-key matching recovers implementation parameters from receiver and
trait arguments through `ImplIndex.matchHeader`, which lookups and the reports
naming a culprit implementation both ask, then the shared constraint solver
decides applicability. `any` and `find` are the two answers of one ladder,
`ImplIndex.selectOnce`.
Coherence keys a constructor-headed implementation by (trait, constructor) and
a callable head by (trait, shape), where the shape is the invocation convention
and each parameter's convention; different keys cannot unify. Parameter heads
are compared with the same trait's other parameter heads and with its ordinary
implementations in every constructor chain, and never against other traits; open predicates do not establish disjointness. Unification
uses an occurs check, so an equation that would make a type contain itself has
no solution. Closed Integer evidence
retains its finite receiver domain.

Receiver-only method discovery can expose a potential parameter-headed member
whose trait arguments still need call context. That result is not applicability
evidence. Call inference settles the complete key before recording the selected
member and implementation arguments. Instantiation consumes those arguments and
does not seed an unbound generic implementation member as a concrete root.

Normal checking prepares exact trait queries and requested method names. Full
method completion facts are requested by editor analysis through the same
checker and canonical matcher. An ordinary struct-field selection does not
require compilation to materialize every blanket implementation for its receiver.
Both modes freeze the facts their consumers need; editor preparation adds query
answers without changing language acceptance or implementation selection.

Default trait implementations occupy a separate trait-indexed candidate tier.
The shared implementation matcher records structural header matches separately
from satisfied bounds, so an ordinary implementation with failed bounds still
blocks a default. Availability and supplier selection use that same evidence.
Defaults follow existing bound and observation suppliers, and cannot normalize
an unknown receiver's associated types. Prepared lookup records include default
candidates before typing freezes; instantiation and MIR consume the recorded
selection rather than performing another fallback search.

Ordinary implementation parameters come from the complete receiver and trait
argument key. `ImplementationParameters` records recoverable binder origins
through injective key structure; associated projections cannot determine a
binder by inversion. Selection, instantiation and retained queries consume the
same declaration-ordered implementation arguments.

Coverage is one pass in `sema/usefulness.zig`: Maranget's usefulness, answered
for every row at once as rustc does. `checkMatch` hands it the sound arms' rows
and a wildcard row after them; the arms no value reaches are [T-Unreachable],
and the values that reach the wildcard row are [T-Cover]'s witnesses. The
irrefutable positions (`let`, `let read`, `let ... else`, a walk's binder and a
lambda's parameter) hand it their one pattern and a wildcard ([T-Refutable]).
The pass splits each column by the constructors its type has; a row naming a
constructor joins that branch alone and a row with a wildcard joins every
branch, so the cells copied into branches are the cost: the size of the
patterns where no row puts a wildcard beside another row's constructor, plus
one copy of each wildcard row per constructor its column splits into. Integer
rows are bucketed by binary search over the sorted cut points. Exhaustiveness of nested patterns
is NP-complete, so the copies for one construct are capped at
`usefulness.max_cells` (2^20), past which it is [T-CoverLimit]. The matrix is
built in an arena per construct and freed with it. A layout is rejected when its size exceeds `Layout.max_size`
([L-Size]), and an array length is stored in 32 bits ([T-ArraySize]).

`Checker.checkPolyRec` examines constructor-growing normalized calls before
instance discovery. A conservative declaration graph shares dispatch identities
with the weighted walk. Known nominal receiver heads share a candidate node
selected by the canonical implementation index; unknown heads retain every
supplier. Defaults remain candidates without predicate solving. Removing sinks
rules out roots that cannot reach any cycle in O(declarations + calls + distinct
candidate edges) work and storage. Remaining roots use declaration-local
exact-or-unknown dispatch frames and a sparse graph of parameter heights, retaining outer type heads
across joins. Canonical implementation-key origins transfer those heights
through unknown suppliers. A maximum-path analysis refuses unbounded reentry;
finite closed specializations remain bounded. For V reached height vertices
and E weighted edges, that analysis costs O(V * E) time and O(V + E) storage.
Dispatch and type-DAG transfer costs are separate and use reached declarations,
parameter slots and type alternatives. The graph ends with the check; later
passes consume accepted call plans without repeating the proof.

Consumes the expanded `Ast` and active module roots. Generated implementations
and functions are ordinary declarations here; inactive source templates are
checked only through the resolver's recorded template-member plans, using an
open symbolic `Self` rather than becoming implementation rows themselves.

Owns every callable signature and compatibility decision: unique closure types,
exact structural `fn` types and bounds, contextual lambda, named-function and
qualified or context-selected enum-constructor conversions, and the complete normalised target and declaration-order argument
run for every accepted call. `Typing.function_values`, closure descriptors, and
normalised calls are the recorded answers; ownership and lowering do not match
names, recover defaults, or classify a call as direct or indirect again.

Call inference carries success and failure constraints through nested carrier
projections. The worklist waits only for result arguments that constructor
payload unification cannot settle, so sibling callback order does not affect
selection. One constructor selector validates both qualified and contextual
forms and records the exact signature and variant ordinal in
`Typing.function_values`; later passes do not reconstruct the enum identity.

Aggregate parts are resolved first with callable shapes available and source
effects deferred. Once the representation is complete, the same type reader
normalizes callable bounds and associated promises before capability
validation and coherence. A second visit to declaration parts records those final
callable types. Associated stand-ins receive the finalized promises; no
shape-only environment is handed to ownership or lowering. Both visits are
linear in the written parts, in addition to the instance refill, which
rewrites only instantiations whose parts are already written. Certified storage identities are installed before containment is queried.

The parser records contract roots and ordered field/dereference steps while
preserving their written ranges. The checker normalizes these `borrows`,
`carries`, and `retains` paths to tagged parameter indexes or resolved capture
identities, followed by field paths, in `CallableSignature.contracts`. Generic
callable bounds additionally normalize an opaque callee source for external
dependencies carried by the environment; explicit result independence suppresses
that source. Ownership reads the callee value facts without observing its storage.
Concrete closure body contracts retain capture identities. `stable_address`
marks read parameters whose caller storage escapes through a result or retained
observation. These flags belong to the shared callable ABI; MIR does not infer
them from function bodies. Source paths carry typed field or observation
selectors, with explicit dereferences distinct from real fields named `value`.
Result paths retain typed variant/payload selectors and field
names with ordinals. `Typing.contractTargetType` follows those checked selectors
in an instantiated result without repeating field lookup. Source type parentheses remain in the AST, while
`Ast.withoutTypeGroups` provides their common semantic interpretation.
`Typing.contract_parameters` retains each written source or destination root's
matched parameter or capture token. The editor's shared `Uses` index combines that answer
with contextual callable-interface mappings, so references and renames include
contracts without parsing their paths again. The shared root matcher also runs
when signature types are unavailable to isolated source analysis; it preserves
parameter references without claiming field paths or result targets were typed.
Storage follows written roots.
A parameter's written type is resolved once, in its declaration's scope, as
its binding's type, and a function's written result type once, by its first
reader (`declaredResultType`); a source template's member is read with the
template's open `Self`. The declaration's signature, its body's result
expectation, the foreign-boundary and storage-signature checks, and every call
to an ordinary declaration read those answers. Only a trait signature's
parameters and result are read again, at each call, because `Self` and its
projections stand for the call's receiver there.
A member of a trait implementation written without a clause takes its
contracts from the trait signature it supplies, read through the member/signature
pairing (`SupplyIndex`, or the resolver's template plans for a template's source
members) and copied with each root respelled for the member's parameter in the
same position. Signatures are built once per declaration, whichever reader asks
first, so the signature a member adopts from is never built twice.
`Typing.adopted_contracts` records each adopting member with its signature, which
ownership reads to name the signature in [O-Escapes]. Where a clause-less source
is ambiguous, a written clause is dropped as refused, or an adopting member does
not match its signature, `Typing.declined_contracts` (and
`ClosureDescriptor.contract_declined` for a lambda) records that no contract was
decided; ownership then skips the
result's boundary check rather than hold the body to an empty contract. One
routine, `types.inferredSource`, answers which parameter a clause-less signature
carries from, for normalization and for the displayed type name alike.
`Typing.contract_variants` likewise retains the checked enum identity and
variant ordinal for each written variant target. Editor references and rename
consume this sparse answer rather than repeating a variant-name lookup.
The same pairing pass records which callable conversions have a complete
written interface relation. Editor and conformance renames consume that answer;
an unpaired interface cannot be renamed one parameter at a time.
Erased template bodies retain lexical closure identities in resolution. Direct
calls, immutable aliases, copies and captures pair their authored labels with
parameter bindings. A per-member sparse escape audit records closures whose
uses cannot be paired, including unknown generic returns and mutable storage.
Rename consumes that refusal fact instead of offering incomplete edits or
inferring callable identity from unchecked template text.
`Typing.placeProjection` records a selection's base, observation-layer count,
receiver type, and optional field ordinal. Field access, explicit dereference,
ownership paths, and MIR consume this answer. `Typing.field_names` records
settled identities for field tokens in selections, constructions, patterns,
tuple-pattern binders, and contracts. The shared editor `Uses` index maps them to source declarations, so
definition, references, and rename agree across generic instances.
`Typing.type_selections` records a written selection's checked base and selected
declaration by dot token, including the base of an unfinished selection.
Completion reads that base through `Reach.associated`, which shares the
checker's visible-trait and exact-subject-bound selection rules. The editor's
`Uses` index consumes the selected declaration for navigation and rename.

`observations.zig` computes one declaration-domain table for whole-trait
read-only forwarding, including reverse supertrait propagation. Operation
candidate enumeration also follows observation layers for readonly methods,
including methods from mixed traits. Calls and completion share that enumeration;
explicit observation implementations take precedence over referent forwarding.
Normalized calls record checked prefixes in `receiver_adjustments` and mark
trait receiver slots whose adjustment depends on implementation selection.
Ownership follows the checked observation prefixes. Instantiation settles the
remaining generic selection; lowering reads its receiver and observation count
without repeating eligibility or trait lookup.
Implementation lookup first checks explicit implementations, then an existing
generic bound, and only then follows an eligible observation layer. Its retained
choice records the implementation, receiver, type arguments, and forwarding
count. Bound evidence has no concrete body until instantiation.
Lookup considers the declaration's existing contextual bounds at each receiver
before forwarding. Queries with active contextual constraints do not populate
the global concrete selection cache. Associated member substitution uses the
selected concrete receiver; unresolved member identities retain the original
receiver so an explicit observation implementation can define different members.

Canonical substitution answers scalar, parameter and uninstantiated nominal
leaves without allocating. Structural traversal owns a query-local TypeId memo
for one declaration and replacement vector. Recursive structural children share it; another query or
declaration state cannot reuse it. Derived type names (nominal instances,
callables, interpolations, arrays, borrows and associated projections) retain at
most 2,048 UTF-8 bytes of diagnostic display, ending with an ellipsis when
abbreviated.
Display is never an identity key: interning and retained references use structural
TypeIds and declarations. Exact symbols use the nominal declaration head and
complete structural arguments. Unresolved associated projections encode source
declaration identities and complete receiver/trait arguments for exact naming.
Source-rewriting tools decline abbreviated display.

`Typing.containsBorrow` answers nominal observation containment.
`Typing.mayCarryDependencies` also includes private raw backing-buffer carriers,
so a typed storage value cannot erase its logical element dependencies through
an intermediate `Buffer`. These type-domain tables use the same reverse-edge
containment algorithm with different seed sets. Graphs grow incrementally;
replacement of an existing type's fields invalidates their answers before the
next query. Construction and queries take O(types + containment edges) expected
time between invalidations, with O(1) frozen queries.

A type parameter seeds both tables unless its record says it is bounded `Owned`
or `Integer`, which is the whole of what those bounds change in a generic body;
the checker refuses an `Owned` argument by asking `mayCarryDependencies` of it.
The edges come from one walk, `BorrowContainment.eachChild`, which both builds
the tables and finds the path a [T-Bound] refusal names (`dependencyWitness`),
so the explanation cannot disagree with the answer it explains. Storage
lowering's `mayCarry` reads the frozen `dependency_containment`, the same table,
so a type the checker admits as `Owned` is one storage never follows a
dependency through; its `holdsDependencies` adds only values whose
representation is an integer, because the address bits of an array are one.

A third table, the builder's `unshareable_facts`, answers `Shareable` over the
same walk in `unshareable` mode, which follows the edges the writer table
follows: fields, observed referents and every type argument. Its seeds are a
declared type whose record says it is marked `@unshareable`, a callable or open
type, and a type parameter whose record says neither `Shareable` nor `Integer`.
A `Shareable` promise on a parameter or on a settled reference read through
one is part of an alike instantiation's shape, as an `Owned` one is, and an
`Integer` promise on a settled reference makes both. The checker refuses a
`Shareable` argument by asking `isShareable`, and
`unshareableWitness` finds the path the refusal names over those edges. The
mark is copied from a template to each instance, so an instantiation of an
`@unshareable` declaration is unshareable whatever its arguments. No pass after
the checker reads the answer yet, so the table is not kept in the finished
`Typing`.

For an instantiated certified `Storage[T, A]`, containment follows its logical
element T and separate allocator field A instead of following the optional raw
backing Buffer field. This lets a system-allocated scalar Vec remain independent
of an iterator's observed source. Standalone Buffer values and optional Buffer
payloads retain the raw-carrier seed, so extraction and reconstruction still
preserve hidden element dependencies. Ownership's existing `carriedBy` filtering
uses the target type's containment answer to retain applicable ambient contract
facts; no separate collection-specific lifetime path is introduced.

`Typing.hasDirectDependencies` exposes that same seed rule for component
coverage: certified storage cannot lose hidden dependencies merely because its
physical fields contain only scalar addresses. Ownership resolves interned
field names through `Typing.fieldIndexByName`, which delegates to the checked
field lookup and its sorted index. The spelling map contains only declared
field names.

The checker builds `Typing.call_index` once after those records settle, over
all expanded expression IDs. Ownership, discovery, emission, formatting and
editor capabilities borrow it. Source tools still enumerate source IDs; the
index also covers generated bodies. Reopened type pools do not copy or own
this expression index: their consumers retain the original checked `Typing`.

Also owns the normalised constraint model. A generic-list bound becomes a
constraint whose subject is its parameter; a trailing predicate contributes its
written subject and the same requirements. The checker normalises the complete
per-declaration set before settling projected subject types, so predicate order
has no meaning. It records contextual promises for open parameters and
projections, then uses those promises and the existing implementation lookup to
discharge both ordinary bounds and trailing predicates. An instantiation
substitutes the recorded subjects and requirements as part of the declaration's
existing type check; no ownership, reachability or lowering pass checks a bound
again.

Also owns interpolation trait selection. An ordinary value piece requires
`Display`; a `?` piece requires `Debug`. [T-Format] holds a spec's number parts
to the value's type through `Typing.layoutShape`, the routine discovery and
lowering later ask of the concrete type. It interns each minted interpolation
type on both the held value types and their recorded modes, and preserves those
modes through substitution, finishing and reopening the type pool. The compact
mode storage is O(V) for V embedded values, its `TypeId` index makes lookup
O(1), and checking one interpolation is O(P) for P alternating pieces. A
Copyable piece is held as `T`, a `borrow T` value included, a place it cannot
copy as `borrow T`, and a computed value the literal may discard as `T`; a
computed value that must be settled is a borrowed temporary. The checker
records the mode once per piece, only in the literal's type beside each
format. The type's name and symbol spell it, and the builder, the dependency
analysis, discovery and lowering read it through `Typing.interpolationBorrows`
and `Typing.interpolationValue`. No pass infers the mode from a field's type.
A value's formatting trait is checked as a bound is discharged, so a
`borrow T` piece forwards to `T` in a generic body as it does elsewhere.

Also owns which values are borrowed temporaries. An argument that is not a
place, passed to a stable-address `read` parameter, and a borrowed
interpolation piece that is not a place are recorded, without their
parentheses, in `Typing.borrowed_temporaries`; a constant is a place and is
never one
([ADR 0175](adr/0175-a-borrowed-temporary-lives-until-the-end-of-its-statement.md)).
Lowering gives each one a slot, and ownership ends it with its statement; no
later pass asks again whether a borrowed value is a place.

Also owns component requirement validity and discharge. It validates and
interns every source `TemplateRequirementId` once in the template's lexical
scope, then checks each generated descriptor before any generated body through
the ordinary implementation index and that implementation's normalised written
constraints. A failed descriptor keeps its header as poisoned recovery
evidence, but its generated member bodies are not type-checked. The checker
records exactly those member `DeclId`s in shared module/root traversal order as
`Typing.suppressed_generated_bodies`; the requirement cache itself remains
checker-owned and is discarded.

Qualified variant selections retain their declaration-order ordinal in
`Resolution.variant_ordinals`. Checking reads that answer for constructor
payloads and generic argument inference. Context-dependent references and
variant patterns, at any depth of a pattern, are settled by the checker in
`Typing.variant_uses`, keyed by the pattern node; a record also retains whether
the payload is left unnamed. Ownership reads that disposal fact, and MIR reads
the selected ordinal for construction, tag tests and payload loads.

A nested pattern adds no node. The checker checks every pattern with one
recursive routine, `checkPattern`, and records each part's answer where the
outermost pattern's always was: its type by node, a variant pattern's ordinal
in `variant_uses`, a struct field's identity in `field_names`, and a binder's
type by binding. What each part selects from the value its pattern node takes
apart -- a field or component by position and name, a variant's payload
position, a newtype's base -- is `Typing.part_selections`, keyed by the part's
node and written by `checkPart`. Ownership reads it for a part's path step,
lowering for its offset, and coverage for the position of the part's column, so
no pass selects a part a second way. A pattern's argument layout is read only by
`Ast.patternParts`, which also counts a node's parts, and every walk over a
pattern switches on `Ast.PatternForm` with no `else` (a walk's binder through
`Ast.walkBinderIsTuple`), so a new form is a compile error at each walk until it
says what the form does. One walk keeps an answer of its own on purpose: the
conformance runner's `patternsApart` decides from the text whether two arms
share no value, to choose which arms a rotation may reorder. It reads the
layout through `patternParts` and switches on `PatternForm` like the rest, but
does not ask coverage, which answers a different question (whether an arm
takes a value the arms before it leave) and whose answer the rotation exists to
test. The checker's own place relation for
[O-Lent] and [N-Aliased] keeps, beside `binder_places`, a `pattern_places`
entry for each nested pattern node, so a binder's place is a chain of one-step
records ending at the value the construct took apart; ownership keeps the same
chain as `Cfg.pattern_parts`, which `Projection.part` names. Generic substitution preserves variant order, so no later consumer
searches a written variant's name again. Each sparse table follows the uses its
pass settled: O(V) storage for V uses and expected O(1) lookup.

The checker also retains numeric literal values and decoded scalar range ends
in `Typing.literal_values`. MIR reads these values instead of parsing the
source again; floats remain excluded from the constant-expression definition.

Named constants retain one tagged checked value in `Typing.constant_values`,
keyed sparsely by `BindingId`: distinct integer, boolean, string and
payload-free variant values, or a typed ID into an interned aggregate graph.
The shared folder owns membership, value computation, immutable aliases and
cycle detection. The checker discovers each open constant's syntactic
dependencies once and advances a cursor as those bindings finish, preserving
the shared cycle marks without rescanning prefixes. Resolution classifies
constructor names but does not choose contextual aggregate types. A variant
value is a graph node holding the variant's name and payloads, folded before
any type is known: `constfold.Names.variant` says only whether an expression is
a qualified variant, and a contextual `.Name` folds from its spelling. The enum
and a generic enum's instantiation stay in the binding, parameter and callable
parameter types, so every comparison reads the node with its type. The
checker's materialization plan selects the variant's ordinal in that type, and
MIR builds the variant from the plan. Canonical record labels and
ordered array/variant payload edges support early callable comparison; the
checker validates the resulting data against its concrete type when the
ordinary representation and capability answers are available, and refuses a
constant or default whose type owes settlement.

The graph retains shared subvalues. Exact interning compares complete node keys;
hashing never replaces equality. A retained library prefix preserves graph IDs
when checking resumes, and its storage outlives the attached view. Callable
formatting and symbols consume canonical graph content rather than pool insertion
numbers, without expanding shared subgraphs exponentially. Literal text still
uses the shared decoder and retains static decoded bytes.

The checker records aggregate materialization plans by constant and concrete
type, including declaration-order fields and enum ordinals. Instantiation retains
those answers. MIR lays a constant out once per type it is read at, in
`Lowerer.layOutConstant`, which reads the checked graph/plan and ordinary type
layout and yields the scalar parts a store of each would write, with a `Str`'s
address as a part naming a blob of the byte pool. It does not replay an
initializer or look up field and variant names. A constant whose type fits a
register is its one part, emitted as a `constant`. Every other constant, and
every constant used as a place, becomes a `mir.Static` in `Module.statics`,
interned by checked value and erased type, and a `static_addr` names it: a read
by value copies out of it as it copies out of any place, and a borrow observes
it. The backend writes each static as a packed constant global. The verifier
refuses a static whose parts overlap or do not sit where its type places a part
of that width, and any store, copy or `inout` lend into static storage. No
function execution, allocation, user copy or implicit release is introduced by
reading a constant.

A constant is a place in static storage. `Resolution.constantNamed` answers
whether an expression, bare or reached through a module or a type, names one;
the checker's place test, the dependency analysis and lowering all root a place
path there. The dependency analysis gives such a place no origin, so a borrow of
a constant, or of any part of it, carries no dependency.

The checker is the sole authority for bottom compatibility. It records `Never`
as the type of every expression with no local continuation, never uses it to
settle an inference variable, and ignores it when joining completing branch
types. Destination-bearing transfers retain their existing destination facts;
`Never` answers whether the local continuation exists, not where a transfer
went.

The checker decides whether a `?` converts its error. Where the operand's
error type differs from the enclosing function's, it asks the shared
implementation query whether `From[Operand]` answers for the
function's error type, in the current generic scope so a bound counts, and
records the trait, its `from` operation and both error types in
`Typing.try_conversions`, keyed by the `?`. The library trait is found once
per check by module and name. Instance discovery substitutes the recorded
types, selects and interns the implementation, and lowering calls the
selected `from` on the failing edge before the scheduled operations run.
Neither re-asks whether the `?` converts. Ownership and dependency analysis
treat the failing edge as before: the error payload is moved out and returned,
which is what `From.from`'s `carries(source)` contract says of the conversion.

The checker also selects the meaning of a bracket expression. Resolution alone
cannot determine whether `b[i]` is an array access or uses a user-defined
`Index` implementation. For a user-defined projection, the checker selects an
implementation through `Typing.Builder.implementationRow` using the receiver
and index types. Ordinary integer array indexes are checked directly for type
and bounds. Array `FromEnd` and `Range[UInt64]` indexes use the provided
implementation relation before their specialised checks.

For `array.as_slice()`, `Typing.arrayViewReceiver` checks array eligibility and
the certified Slice declaration while retaining observation adjustments. The
type checker records a `NormalizedCall` with target `.array_view`, the exact
array receiver type, and a read parameter whose `stable_address` and
`borrows(source)` contract use the existing caller-storage ABI. The normal
stable-argument check rejects temporary owners. Editor completion consumes the
same eligibility query. No owning array iterator or array `Sequence`
implementation is synthesized; the library's Slice iterator handles arrays,
Vecs and subspans after their explicit view construction.

For a projection, the checker computes one canonical path per implementation
and records its selection at each bracket site. Lowering substitutes that
site's receiver and index into the recorded path. The path is not recomputed
per use, and no projection operation survives into MIR.

Field delegation retains its contextual keyword and target token in the source
AST. The type checker records the stored field in the existing source-reference
table, selects the backing Index operation under generic substitution, and
records its element type and access ceiling in the canonical projection plan. The
authored implementation remains the single coherence candidate: no second
implementation is generated, and the frozen source AST is not mutated.
When only a generic Index bound supplies the backing operation, the plan retains
that trait and its checked key and receiver types. The same forwarding record
handles ordinary indexing through a bound, with no stored-field step.
Instantiation discovery selects
the concrete backing through the shared implementation query and checks its
access ceiling and expansion cycle; sealed lowering reads the prepared choice.
Ownership consumes the checked projection path, including its field identity,
to preserve observations stored inside projected elements.

The private typed-storage place is another checked projection expansion. The
checker recognizes `std.mem.slot_place` by its resolved declaration, admits it
only at a projection's tail, and records the owner-rooted place and mode ceiling
using the same projection facts. It does not encode Vec's fields or occupancy
policy. A traversal's optional `read Self` receiver is an ordinary AST parameter
with ordinary resolver bindings and parameter types; the checker validates the
receiver and the iterator-producing initializer once at the declaration.

Checked traversal records distinguish an authored positions expression from a
constant array range with a checked integer key type and length. Explicit
`trav positions via field` selects the latter after validating the fixed-array
field and sole applicable integer Index key. Both forms share key validation
and loop-head binding. Lowering dispatches on the checked positions source;
it does not infer delegation from syntax or reselect an implementation.
Ownership retains the existing initializer path for authored expressions;
a constant positions range introduces no captures. Cached library typing must
preserve these records and relocate their typed identities when imported.

`sema/intrinsics.zig` identifies private scalar and typed storage declarations
once per compilation. The checker retains those `DeclId`s in
`Typing.raw_accesses` and validates typed storage signatures independently of
the foreign ABI. Instantiation discovery and MIR lowering read that record;
they neither rescan library names nor maintain a second identity cache.

After bodies are checked, `settleExternSymbols` groups every `extern`
declaration, retained library ones included, by the symbol it names. A later
declaration of a symbol whose parameter types, conventions and result agree
with the first is recorded in `Typing.extern_symbols` against that first
declaration; one that disagrees is [T-ExternAgreement]. Instance discovery keys
an extern body through that table in `TableBuilder.intern` and
`InstanceTable.lookupBody` alike, so every declaration of one symbol reaches one
instance and one MIR function.

For Float64 math, `FloatMath.candidates` identifies the ten trusted scalar
extern declarations before their signatures are available. After signatures
are checked, the shared `matchesExternSignature` query validates their complete
parameter/result contract and private visibility. Only accepted declaration
identities enter `Typing.float_math`; candidates remain checker-local so a
malformed trusted declaration cannot fall through the ordinary integer ABI.
Retained typing relocates the accepted DeclIds through the canonical
`Relocation.value` traversal, including fixed arrays. Instantiation omits these
runtime primitives and lowering maps their checked identities to the single
`float_math` MIR family. Its normalized operation selects arity and symbol from
`support/float_math.zig`; operands and results are Float64 value roles. MIR
verification checks type, arity and operand range; MLIR verification checks
SSA dominance alongside other emitted operations. The
backend scans instructions once into a ten-entry used-operation set, declares
only those runtime symbols, and emits direct f64 runtime calls. It does not
recognize source names or implement mathematical special-value rules. The
runtime owns rounding, NaN, signed-zero and platform precision behavior.
Identity checks cost at most ten comparisons; backend declaration discovery
is O(instructions + 10) with constant auxiliary space.
The checker certifies private, move-only `Storage[T, A]` with ordered fields
`buffer: Option[Buffer[A]]`, `allocator: A`, `at: UInt64`, and `len: UInt64`.
Logical element containment survives optional-buffer transfers. The library
keeps the flat address and extent consistent with the optional owner; slot
address lowering consumes those flat fields and retains its checked-access ABI.

These decisions are recorded in `Typing`. Later passes read recorded types,
layouts and callees instead of determining them independently.

Allocator lifetime dependencies are ordinary observation roots. The type checker
records source contracts and representation containment; it does not propagate
dynamic lifetimes through branches or loops.

Explicit captures retain one semantic environment struct per closure source
identity and specialization. Its fields use the ordinary typing field table;
read fields hold observations and sink fields own their values, while capture
alias bindings expose the source types. Closure capability and dependency facts
follow this environment. Invocation conventions belong to callable signatures
and normalized calls; generic bounds admit read invocation where inout is
required without changing structural function-pointer identity.
Instantiation specializes its field types under the same key as the closure.
MIR materializes the fields and passes the environment after explicit call
arguments; a noncapturing body retains its environment-free ABI. Structural
function pointers cannot erase a capturing environment. No AST declaration is
synthesized and no closure-conversion pass is introduced.

### Ownership — `src/ownership/`

Owns: checking that each linear value is consumed exactly once and that no
value is used after a move. It builds a separate `Cfg` because ownership
checks need source binding identities along each control-flow path. MIR does not retain them (ADR 0034).

Its declaration roots and bodies come from `ExpandedProgram`, so generated
functions receive the same ownership CFG and checks as source functions unless
the checker explicitly suppressed that generated body during recovery.

An accepted lambda body is a separate function-like ownership graph. Creating
the lambda does not execute that graph, and the enclosing graph does not contain
its body. Resolution supplies explicit capture bindings and source expressions.
The enclosing graph evaluates capture sources at construction; a read capture
records an observation of its source place, an `inout` capture records an
exclusive lend of it, and a sink capture transfers its value. The lambda graph
lends read captures and treats an `inout` capture as an `inout` parameter.
Owned captures are lent under read invocation, checked for reinitialization
under inout invocation, and settled under sink invocation.

An exclusive lend is an ordinary dependency fact whose origin records the
capture source that lent it (`Origin.lent`). Creating it invalidates every
earlier observation of the place, as a write does. `carries` copies facts, so
the lend travels wherever the closure's dependencies do. A read of a place
invalidates the live lends of it, and the ordinary stale-use check then
reports a later use of whatever holds one ([O-Borrow]); a boundary never
admits one ([O-Escapes]). Where facts land in a value whose type
`Typing.mayHoldWriter` says can hold no closure, function value or type
parameter, `heldAs` turns lends into read facts, in the one routine both an
expression's result and a binding's write pass through. `OwnerIndex` files
each live set by owner and by the observed path's first step, elements
sharing one bucket; `Dependents.owners` and `Dependents.lenders` are two such
indexes, so an access to one field inspects the observations of that field
and of the whole owner, and a read inspects only lends. Normalized calls determine callee consumption and mutable
access. Dependencies are carried by the closure environment through the existing
owner graph.

A task's body crosses to another thread at a call to `task.Slot.start`,
which `RawAccesses.slot_start` names by identity. At that call the dependency
analysis reads the facts the `body` argument carries and holds them to
[O-Cross]: an observation's place must be `Shareable`, which it asks of
`Typing.isShareable`, the table the checker settled for the `Shareable` bound,
and an exclusive lend must be one of the body's own `inout` captures. Which
capture a fact came through is read from `capture_sets`, what each capture
took into its closure, sized by the function's captures; ownership computes
no shareability of its own.

Ownership runs even when type checking reports errors. A place with a poison
type has no usable capability information, so it cannot support meaningful
ownership checks. Other, correctly typed places are still checked; an unrelated
type error must not hide a leaked linear value.
It merge-walks `Typing.suppressed_generated_bodies` with one cursor and omits
only those ordered generated members. It reads no template, descriptor,
component or requirement metadata and never discharges a requirement; every
unrelated source or accepted generated body is still checked.

Ownership uses the checker's recorded argument types, conventions and
normalised calls, including postfix receivers absent from the written argument
list. It determines moves from consuming **positions**. A new expression form
must propagate its enclosing position to the appropriate subexpressions.

A call lends each argument it does not take until the callee has run. After
evaluating such an argument the builder emits a `.held` operation for each
place its value names (through grouping, `&`, and the branches of a
conditional, block or `match`), pending on the call. The move checker carries
held places beside the open transfers and closes both at the call's
`committed`; a held root that is moved where the call is reached is [O-Move],
so a take on a path that leaves first is judged where it goes. A binary
operator is built the same way, as the trait call it is, and the dependency
analysis checks its operands' observations at its `committed`.
That is the one place that decides whether a take and a lend meet in one call,
whatever the take's position: a `sink` argument, a nested call, a `let` in a
block argument, a literal's field. Which arguments mutate a place another names
is the checker's [N-Aliased], answered from the argument list; a view or a
capture passed beside the owner it observes is the dependency analysis's
[O-Borrow].

Traversal initializers are ownership bodies too. The existing CFG builder
starts them with their written parameters and visits the initializer in its
consuming position. The ordinary read-parameter rules prevent a traversal from
moving an owned part out of its receiver; no separate traversal ownership
analysis is needed.

Read-only observation permissions are typing answers: `place_projections`
records explicit and transparent referent steps, `readonly_places` propagates
their authority through selected fields and indexes, and `carried_places` marks certified span element places
whose origins are their backing dependencies rather than their descriptor
storage. Ownership consumes those facts while building its existing CFG.
The dependency analysis retains the recorded `carried_source` when selecting
such an index and checks that source for invalidation before discarding the
dependencies of an independent scalar result. Direct indexing and an observed
element therefore enforce the same backing-owner lifetime.
Observation roots, carried dependency sets, retention updates, boundary escapes,
and last-use invalidation are computed over that CFG; emission does not rebuild
this flow from syntax.

The CFG marks every lending binder in `lends`. A `match read` arm and a lending
walk bound their lends lexically, and the checker's [O-Lent] guards the lent
place for that extent. `let read` binders are also marked in `lasting_lends`:
nothing encloses them, so each use reads the alias cell its `.lent` operation
created and reports [O-Borrow] if the place it names was written, moved or
released since. Liveness keeps that alias only until its last use, so the owner
is free again afterwards. The checker still records `let read` binder places in
its `binder_places` relation, which is what lets [N-Aliased] see a binder and
its owner passed to one call. A binder nested inside a pattern takes the part
its whole path selects: its `.lent` or `.init` operation carries
`Projection.part`, and `Cfg.pattern_parts` holds each nested node's step from
the pattern around it.

Dependency paths and immutable origin sets are interned within each function.
Call-result contracts collect their contributed facts before interning the union,
so growing prefixes do not become retained sets. Boundary checking indexes the
function's contracts by source binding, then applies the existing path, kind and
coverage rules within that source's clauses.
A backward worklist records the last uses of expression and binding carriers;
a forward worklist propagates their reachable origins in reverse-postorder
priority, sharing the CFG traversal used by obligation checking. This lets all
acyclic predecessors contribute before a join is processed. Named record fields keep
separate paths, while an indexed observation protects its containing storage.
Known array slots retain separate dependency paths; adjacent slots with identical
facts share compact ranges. Exact writes split those ranges, while unknown-index
writes preserve potentially untouched elements. Ambient facts record canonical
excluded paths for definitely replaced parts; joins intersect exclusions rather
than enumerate predecessor combinations. Array contract coverage counts the
union of covered intervals. The checker publishes the number each accepted
bracket's index operand folds to, arithmetic over constants included, and
ownership and lowering read it through one typing query rather than folding
the operand again.
Observed projections resolve the carried referent address, including through
normalized source paths, rather than extending a descriptor's lifetime.
A reverse index maps each live owner identity to active interned fact sets, and
each active set to its carriers. Moving an unchanged set between bindings
updates carrier membership without rereading its facts; the first activation
indexes those facts. Mutation updates each affected set once and redirects its
carriers. Scope exits inspect live owner identities through the CFG's
scope-membership answer and then update affected sets. The index is rebuilt
from a block's joined input and has function-local storage. Aggregate literals
collect their field facts before one canonical set union.

Callable result bounds remain compact ambient facts. At a return or inout
boundary, ownership checks whether declared target prefixes collectively cover
every component that typing says may carry dependencies. A value's direct
dependency seed cannot be discharged through its physical fields. The seeds
are an observation, a type parameter, and the declarations the checker
recognises by identity: `mem.Slice`, `mem.Buffer` and `mem.Storage`, and
`std.ffi`'s `Bytes`, `CText` and `CTextList`, newtypes over a C address whose
contracts tie them to what they view. A seeded newtype is not a
dependency-free scalar, so a `carries` contract into one is kept. This permits
an optional payload to be unpacked and restored while preserving distinct
record-field obligations. Target suffixes are grouped by path step; immediate
capable-component counts are cached by mentioned type within the function, so
the number of origins does not multiply scans of record or variant fields.

Whether the checker refused an expression is recorded, not inferred: `record`
and the expression dispatcher add every expression they give poison to
`Typing.refused`, and the mismatch report, which poisons a value that was
built and does not fit its context, does not. Ownership asks `isRefused` where it must decide whether a construct
ran, so a variant built for the wrong type still takes its payload while a
literal whose type was never settled takes nothing.

Selection recovery distinguishes an invalid path from a resolved place whose
surrounding expected type disagrees. Typing retains resolved field and index
expression types in the sparse `selected_places` table. Ownership reads that answer
for every step of the existing place-path walk; it repeats no field or index
lookup. A rejected path still evaluates its indexes and reads its root, while
a contextual mismatch preserves the place's consuming or reading position.
Scalar snapshot selection uses the retained place type, or a name's binding
type, even when a surrounding diagnostic poisons the expression result.
Deferred index validation poisons a rejected bracket and clears its selection
entry, so an invalid inner bracket also prevents a transfer through an outer
selection.

After checking an expression's operands and any destination-bearing transfer,
ownership reads its settled type. `Never` means there is no local successor
state. This one read covers panic, infinite loops, all-diverging compound
expressions and direct or indirect noreturn calls; ownership keeps no parallel
list of diverging syntax. A panic is a trap and schedules no scope-exit work.

Ownership stores one state vector for the function's roots, with a trail of
changes for navigating the graph (ADR 0066). Each block records changes relative
to its immediate dominator's exit. Moving between blocks rolls back to their
shared dominator and applies changes along the destination path. This avoids
copying the whole vector per block. Every reader of `state[slot]` must ensure
the trail is positioned at the graph location it intends to inspect.

The canonical ownership check receives explicit retained and scratch allocators
([ADR 0120](adr/0120-pass-results-and-scratch-have-distinct-caller-owned-lifetimes.md)).
The driver owns a short-lived arena for the CFG and checking buffers; only the
returned disposal plan uses retained storage. Diagnostic strings and labels use
the supplied sink. Releasing ownership scratch cannot invalidate either output.

The LSP separately receives general allocation and retained-region backing from
its caller. Analysis owns semantic and source arenas on the supplied region
backing; its general scratch is released before the result returns. Server
messages, open documents and workspace indexes continue to use general storage.
No semantic pass chooses the process allocator or a region's release policy.

Borrowed temporaries end with their statement. The builder keeps a stack of
open statements (each block statement, a `defer`'s expression where it runs, a
function or closure body, a `while` condition and a loop body per iteration),
assigns every entry of `Typing.borrowed_temporaries` it walks to the innermost
one in `Cfg.temporary_statements`, and emits `temporaries_end` where a
statement that made one closes or where a `break` or a `continue` leaves it. The dependency
analysis gives a borrow of a temporary an origin owned by its statement,
indexes it under that statement in the same owner index bindings use, and
invalidates it at `temporaries_end`; a later use or a return of a carrier
holding it is [O-Temporary]. The map is sized by the program's temporaries and
the stack by statement nesting. An [O-Borrow] whose invalidating site is a scope exit is
reported at the exit's span, from the same `cfg.exitSpan` [O-Leak] uses, and
names the owner through `ExpandedProgram.subjectAt`, the answer [O-Leak] also
reads. Its second labels are the later use and the borrow that value carries,
found by following the binding's write and the arrivals back to the piece or
argument that borrowed the owner. The exits it records are sized by the
function's scope exits.

Ownership also freezes an exit-keyed `DisposalPlan` after checking. The plan
contains surviving deferred expressions in execution order, and the place uses
the program wrote, each as taken (a consuming position) or read (a reading
position, a scalar snapshot, or a constant's static storage). Both instance
discovery and MIR consume it; their own walks decide neither placement nor
cancellation, and lowering blits a place the plan says was read as a copy and
one it says was taken as a move. A use the plan lists as neither names no
place: it is a value computed on the spot, and is moved into whatever receives
it. Lowering never re-derives which of the three a position is from syntax;
`Ast.isSelection` answers only the structural question of whether an address is
walked.

**Adding a decision a later pass needs.** Record it in a side table in the pass
that decides it, keyed by the representation's own IDs, and have every later
pass read the table. Do not give the later pass a predicate that works the
answer out again from syntax or types, even a correct one: two implementations
of one rule drift on the input nobody wrote. Where a decision genuinely has to
be asked before the deciding pass has run, as the resolver asks whether a chain
is walkable before names resolve, both asks go through one routine on the
representation (`Ast.placeSteps`, `Ast.pathRoot`, `Resolution.pathBinding`),
never a second walk. An interpolation piece's position (borrowed, copied or
moved) is the worked example: the checker decides it once into
`Typing.interpolation_positions`, ownership reads it to choose the piece's
position, and lowering reads ownership's plan to choose the blit.

### Instantiation — `src/sema/instantiate.zig`

Owns: which concrete declaration, closure and selected enum-constructor bodies
are reachable from the program's roots. A closure instance is keyed by its resolver-owned `ClosureId`,
its enclosing concrete type arguments, and concrete `Self` where one exists.
A constructor body records its selected expression, enclosing declaration and
variant ordinal. Checking supplies the exact callable signature and validates
its payload carries; discovery specializes that answer, and MIR builds the
ordinary enum payload and return without introducing a callable ABI.
Discovery records the complete instance table, stable symbols, and concrete
implementation selections in the completed type pool. Checking retains settled
concrete queries there; discovery extends them through the same lookup used
for associated types. Lowering looks up those answers and treats an
unrecorded instance or selection key as a compiler defect. CLI and editor
checks stop after discovery, without constructing MIR to discard it. Discovery
reads ownership’s `DisposalPlan` at each exit; it does not reconstruct schedules.
Conditional closure Release uses one semantic supplier for trait availability
and selection. Discovery keys its generated body by concrete closure type and
records the callable signature and reverse-order owned-field call targets.
MIR consumes that prepared plan without synthesizing AST declarations or
selecting implementations again. Read capture slots contribute no release call.
A call to `mem.closure_entry` or `mem.closure_settle` in an instantiated
`Closure.open` keys a generated erased entry by its stored callable type and
closure signature, or an erased release by the stored callable type
([ADR 0173](adr/0173-a-capturing-closure-is-erased-into-allocator-owned-storage.md)).
Discovering the entry reaches the stored closure's body; discovering the
release reaches the closure-release body the supplier above plans. Lowering
builds both from those keys and the pool's `ClosureEntry` signature, and a call
through a `mem.Closure` is an ordinary indirect call through its entry.
Its completed type builder remains sealed and owns the names and layouts it
created. Sealing settles the pool as finishing does, so a scoped capability a
rebuild dropped during discovery is prepared again before anything reads the
sealed pool. Emission consumes that builder and finishes it once into the module;
it neither reopens the pool nor rebuilds its indexes or layout caches.

Reachability walks the expanded active declarations and may therefore select a
generated template member as an ordinary concrete body. For an interpolation it
reads the checker-owned mode run and discovers `Display.fmt` or `Debug.debug`
for each value before MIR exists. A value whose format lays it out instead
reaches one of the `std.fmt` layout adapters that `LayoutDecls.of` names for
its concrete type's `layoutShape`.

Every instance it receives has already satisfied the checker-owned normalised
constraints. Reachability substitutes no constraint subject and discharges no
bound.

Discovery reads private scalar and typed-storage identities from
`Typing.raw_accesses`. It separately identifies `std.mem.linea_alloc` through
the shared matcher, which checks its module, name and complete signature.
`InstanceTable.zeroed_allocator` records that declaration; lowering records
its `FunctionId` in `mir.Module` only if it was discovered. The backend reads
this checked identity rather than recognising the allocator by its emitted
symbol (ADR 0119).

### Lowering — `src/mir/`

Owns: producing MIR for the concrete instances selected by discovery. Each
instance becomes a function with its recorded symbol; MIR contains no generics.
Lowering also defines explicit control flow (ADR 0022), the computation and
storage representation of each type in the sealed pool, instruction result roles, and
local slot roles. `notes.zig` records how source tokens map to lowered entities
for dumps that annotate the source.

Each reachable pair of `ClosureId` and enclosing concrete arguments becomes one
ordinary MIR function whose `Origin.closure` records that source identity
directly. A unique closure call is direct. A contextual conversion emits
`function_addr`, and a structural value is represented as one code pointer.
Structural calls emit `call_indirect` unless lowering proves that an immutable
local selects between two checked declared function values (ADR 0117). That
bounded specialisation retains the condition evaluated at initialisation and
emits two direct alternatives after evaluating the normalised arguments once.
The pointer value remains available to other consumers; target identity and
signature still come from typing. Sparse provenance belongs to the function being lowered and
is released with it. A non-capturing closure has no runtime environment parameter
or value and needs no conversion shim; there is no closure-conversion pass
between typing and MIR.

Lowering may omit a primitive array literal's stores when a bounded structured
proof establishes that an unconditional prefix write precedes every observation
(ADR 0118). The proof uses resolved local bindings and checked types, requires
matching immutable loop bounds, and rejects escaping or otherwise unsupported
uses. Its result is keyed by `ExprId` and belongs to the function being lowered;
the array still receives storage, and all later checked accesses remain.

Generated symbol names encode type structure, which can be deeply nested.
`support/symbol.zig`'s `appendBounded` limits their length by retaining an escaped prefix
and appending a digest of the complete spelling. This avoids assembler
identifier limits while distinguishing types that share a prefix. A digest
collision is a compiler defect detected by the verifier with exit 70.

Reads the checker's types and implementations; it does not re-decide them.
Composed lowering returns no module when checking or discovery reports errors.
MIR materialization accepts only successful semantic results, with assertions
at the boundary; it has no diagnosed-input mode.

`borrow T` has a data-pointer computation and storage representation. MIR
`borrow` turns a managed place address into that observation; `observe` exposes
the managed referent address for read access. These are distinct from code
pointers and integer addresses. The verifier checks their operand/result types
and address roles, and the backend preserves their pointer ABI. String literals
construct the checked `Str.bytes` span representation directly.

Read-match and `let read` binders retain their source addresses in lowering's
existing `lent` table, shared with lending traversals and read captures. Enum
payload and record field addresses use the concrete layout of the field the
checker selected (`Typing.fieldSelection`), not a second lookup by spelling;
scalar newtypes keep the original place or, for a match, materialize an unnamed
temporary once. A `let read` initializer is always a checked place, so it never
takes that temporary path. Match binder entries expire with the arm; `let read`
entries stay for the rest of the function, keyed by their unique `BindingId`.
Consuming patterns still load independent values. A `match` lowers as a chain
of arms: `testPattern` tests each arm's pattern outer part first and branches
to the next arm at the first part that fails, so a payload is read only behind
its variant's tag test, then `bindPattern` binds every binder at any depth from
the same chained field addresses. Ownership determines which
observations may escape before lowering; MIR preserves that identity rather
than copying a read binder into a new local slot.

Array-view lowering consumes the normalized source address, receiver adjustments
and static array count, then constructs the existing Slice descriptor. MIR
`address_bits` converts that managed address to UInt64; verification requires a
managed-address operand and an ordinary UInt64 result and validates the observed
storage extent. MLIR emits `llvm.ptrtoint`. Neither ownership nor lowering
recognizes the source member name again, and no public arbitrary-address
constructor is introduced.

Private typed storage lowers using the concrete element layout. Stride is at
least one byte for allocation. Contiguous Slice offsets and typed access widths
use the element layout size, including zero. Zero-sized elements share a stable
address while the Slice retains its logical count and index checks. Raw scalar
accesses and typed addresses share the same checked
address routine, with independent byte extent and alignment arguments. The
`storage_addr` instruction records the element `TypeId`, a managed-address
result role, and the explicit overflow, bounds, and alignment checks in its
`RawAccess` payload. Existing indirect loads and stores handle scalar values;
aggregate moves copy into independent destination storage. The library decides
which slots are live and when ownership moves between them.

A lending walk evaluates its head once. Its traversal initializer receives
that value through the resolver's recorded receiver binding under the selected
implementation's type substitution. The same evaluated head roots subsequent
projected places.

Interpolation lowering walks each field once, reads its recorded mode in O(1),
and emits `Display.fmt` or `Debug.debug` with the outer writer's settled type.
A borrowed field stores the address of its place, or of the slot a borrowed
temporary is evaluated into, and rendering observes through it.
A laid-out value calls the adapter discovery reached through the same
`LayoutDecls.of`, passing the spec's parts as constants; the layout itself is
`std.fmt`'s.
Static text remains Display, values still evaluate once at construction, and
the existing success branches stop at the first writer failure.

It lowers the expanded `Ast`. Before a generated function becomes MIR, its
file and every instruction span collapse to the written derive's source file
and span through `ExpandedProgram`'s declaration origin. Diagnostics may also
carry a secondary template-expression origin and reflected component ordinal;
collapse is fallible, idempotent and runs at every pass boundary. No generated
virtual `FileId` crosses into the source-only `FileTable` or survives as a MIR
location.

An expression typed `Never` lowers without a result value. Ordinary transfers
retain their return, break or continue edges; panic becomes a message-bearing
trap; an infinite loop retains only its loop edges; and a direct or indirect
call returning `Never` becomes the corresponding noreturn-call terminator.
Reading a named `Never` binding emits an `unreachable_reached` trap rather than
materialising a value. These forms are structural MIR terminators because a
normal call promises a following instruction and no side table can remove that
successor.

### Verifier — `src/mir/verify.zig`

Owns: checking that MIR satisfies the emitter's preconditions. Verification
runs **inside** `emit` (ADR 0049), before code is written. A failure means the
compiler produced invalid MIR for accepted source, so it returns exit 70.
Source diagnostics use a different status to let callers distinguish invalid
programs from compiler defects.

Every layout check it makes is relative to `module.layouts`, and every physical
value check reads the representation and role accessors owned by MIR. It proves
exact table coverage and role consistency before those facts can be indexed.
The external-definition table contains one flag per function, including modules
constructed by tests; an empty table does not stand for a module's local bodies.
ADR 0050's bounded exception remains: the layout rule has a second
implementation, deliberately, and it lives in the test.

Typed heap addresses must carry checks for `offset + layout.size` within
the supplied byte extent, including zero-width elements, and for the offset's
concrete alignment. The verifier
checks the certificates and records provenance for one typed heap element.
Indirect accesses, field addresses, aggregate copies, and call arguments then
use the existing object-extent rules. A 24-byte element aligned to eight bytes
therefore requires separate extent and alignment facts.

The offset-alignment proof relies on Buffer's eight-byte base-alignment
guarantee and the current concrete layout ceiling of eight bytes. A layout with
greater alignment would require an updated allocation contract as well as its
layout-table entry.

For callables it proves that a function address names an existing concrete
function compatible with the recorded pointer interface under the shared
contextual callable predicate (outer labels may differ), that an indirect callee is a code
pointer, that the indirect argument extent and every argument/result
representation match that signature, and that no non-capturing body acquires a
hidden environment parameter. If `module.zeroed_allocator` is present, the
verifier requires it to identify an external function with two `read UInt64`
parameters, no defaults, and a `UInt64` result (ADR 0119).

For no-value control flow it proves that no value-producing instruction has
type `Never`, normal and noreturn calls agree with the callee's settled result,
a `Never`-returning function has no normal return, and only a panic trap carries
one `Str` message.

#### Storage ownership

The verifier's last phase checks, from instructions and signatures alone, that
no path uses an observation after its owner's storage changed and that no path
reads an aggregate after it was moved out (ADR 0204). It reads nothing ownership
produced (not the `Cfg`, the dependency facts or the `DisposalPlan`), because
reading ownership's answer would verify only that lowering copied it. It is a
second reading of the language rule over a different representation, admitted
under ADR 0050's conditions and one more: every refusal it makes is one
ownership would also make on the same program. It reads the same
`CallableSignature.contracts` ownership reads, so a wrong clause passes both.

Its roots are a function's owned aggregate slots (a `sink` parameter's slot
included), its managed-address parameter slots, and each managed-address call
result; scalar slots are snapshots and are not roots. Every instruction value
and slot is a carrier of the dependencies it holds. Per function, over blocks,
it checks:

- **No use of an observation after its owner changed.** A carrier's dependencies
  are `(owner root, owner range, held range)` triples, created by `borrow` and
  `address_bits` of a rooted address and by a call whose signature says
  `borrows(p)` or `carries(p)` with a parameter root. They travel through loads,
  stores, blits and `retains(d: s)`. A write, an `inout` lend, a `sink` or a
  `move_value` invalidates the owner bytes it covers, marking that dependency
  stale in every carrier holding it. A use on any path of a part of a carrier
  holding a stale dependency is a defect naming both instructions. A scalar
  payload read out of a stale result is not a use, and a read of a sibling part
  is not a use of the stale one.
- **No read after a move.** A whole-root `sink` argument (convention from the
  callee's `CallableSignature`) or a whole-root `move_value` source moves an
  owned slot or a returned temporary out; a later read of it on any path is a
  defect, and a `sink` of it is the double settlement. A part move has no state,
  and a lent root is never moved. A call's arguments are read before the call
  and its moves applied after, but the callee reads a lent argument after a
  `sink` argument of the same call was moved, so an address a lent argument
  passes may not point into a root a `sink` argument of that call moves.
- **Kills.** Any write to a root kills `moved` and `stale`: a whole write
  replaces the slot's set, an exact part write replaces the dependencies held in
  the written range, a write through a computed address replaces none, and
  defining an instruction value kills its state, so a view re-created on each
  pass of a loop is fresh.

A dependency is held by a carrier or is a pointer value's own view of the place
it points into. A read through a pointer carries what the bytes hold and drops
the view, so a copy made through a borrow does not observe the place it was
copied from.

Which root an address points into, at what offset, and which carrier it reads
through is the verifier's one attribution walk (`attribute`), which `accesses`
and `escapes` also read. The dataflow is one walk of the dominator tree to a
fixpoint, with state kept as one vector and a trail of changes (ADR 0066). An
edge into a loop at a block that does not dominate its source is refused as a
defect before the walk. A build with runtime safety also computes the fixpoint
densely and asserts it equal at every block entry. Dependency sets and marks
are interned, so equal content is one handle. Time is linear in the
instructions plus the work of joins, unions and invalidations, and memory is
`O((I + R + U + entries + marks) log marks + trail)` for `I` instructions, `R`
roots and `U` unions. Three sweep dimensions hold the phase to the clock, and a
unit property bounds its allocation. Two shapes are quadratic in memory and are
declared limits (ADR 0204): a holder retaining a view at each of `n` stages with
a carry taken at each stage, and a literal copying a wide struct into two
fields.

MIR carries one fact for it. `move_value` sits beside `copy_value` with the same
payload and the same rendering (a blit) and says the source is consumed.
Lowering emits `copy_value` only at `copy(e)` and wherever a blit's source is a
place ownership's disposal plan records as read: a Copyable interpolation piece
the literal holds as a copy, a join's arm written in a reading position, a
constant's static storage. The backend's return peephole recognises either
before a `ret`. `storage_addr` gains no owner: the integer address a view holds
is the snapshot the language says it is, and the phase holds the carriers
(`Slice`, `Storage`, an iterator) to their owners instead.

It runs on every emission, for every non-external function, after `escapes`, and
refuses with an uncoded `compiler defect:` error under exit 70; `check` and the
editor never emit, so the refusal is met at `build` or `run`. Its misses are
enumerated in ADR 0204, each with the reason it is a miss and not a refusal. A
refusal is triaged one of three ways and no fourth: a defect in ownership (write
the case ownership should refuse, fix ownership), in lowering (a `copy_value`
where the source is consumed, a missing scheduled release; fix lowering, case
first), or in this phase (a refusal of a program ownership accepts; fix the rule
with a hand-built MIR test that fails first, and enumerate the difference if it
is new). Never a suppression list, a flag, or a read of ownership's tables.

### Backend — `src/backend/mlir.zig`

Owns: the MLIR text. Reads `module.layouts` for every size, alignment, and
offset, and renders computation, storage, and managed-address types through the
MIR representation accessors. It does not reconstruct a physical type from a
semantic type or instruction tag.

It renders the recorded direct call, function address, or indirect call. It
does not reconstruct callable signatures, select generated bodies, add a
runtime environment, or renormalise arguments.

An internal aggregate call in final return position can write directly into the
caller's fresh return destination when its exact type agrees. The emitter
recognizes either a direct return or a final copy into an owned result slot
followed by an empty return join; it does not move observable work across the
call. This removes a temporary and copy without changing MIR. Emission computes
reachability over this resulting graph, whose terminal calls can bypass joins
that remain reachable in the verifier's MIR graph.

`storage_addr` becomes an integer-to-pointer conversion and performs no load.
The backend reads its managed-address role and renders ordinary indirect
accesses and aggregate copies; it knows neither Vec's layout nor its live-slot
invariant.

For the recorded zeroed allocator, emission preserves the ordinary nullable
call and exposes zero facts for at most eight complete eight-byte words
(ADR 0119). Each proof path requires a nonzero result and LLVM-constant proof
that the allocation is at most 512 bytes and contains the complete word.
Inlining may establish those predicates; unresolved predicates remove the
proof paths before machine code. These facts permit no allocation elision,
`nonnull` or `noalias` assumptions. Verified raw accesses use non-inbounds
byte GEPs over their recorded base and offset, preserving pointer relationships
and the existing overflow, bounds and alignment checks.

A callback an `extern` takes lowers to `foreign_function_addr`, the address of
a C-callable entry to one concrete function; the verifier refuses the value
anywhere but as an argument of a direct call to an `extern`. The backend writes
one private entry per function so passed, with the routine that writes an
export's thunk: both take the declared types' C widths, widen them, call the
body and narrow its answer. A crossing value is rendered from its storage
representation, and a callback crosses as `!llvm.ptr`.

An `extern` answering `ffi.Errno[R]` is lowered with a signature answering `R`,
interned by discovery through `RawAccesses.errnoSignature` before the pool
closes. Each call to it lowers to that call, then a call to the runtime's
`linea_errno`, which discovery reaches with it, and then the `Errno` built from
the two values. Lowering emits the two calls next to each other, so no
instruction between them can change `errno`.

An `extern` declaration and an export thunk mark every 8- or 16-bit integer
parameter and result `llvm.signext` or `llvm.zeroext`, by the declared type's
signedness. Both supported C ABIs leave the bits above a narrow value to its
producer, and C compiled by Clang reads the whole register.

A `Never`-returning function has no MLIR result and is marked noreturn. A
noreturn call is followed by `llvm.unreachable`, and no conversion or storage
operation is emitted for `Never`. Panic passes the recorded `Str` address and
length plus the source file, line and column to its noreturn runtime entry point;
ordinary checked-operation traps keep their existing path. The runtime writes
the message by length, flushes standard error and aborts; it neither interprets
the bytes as a format string nor unwinds.

### Toolchain — `src/driver/toolchain.zig`

Runs `mlir-opt` and `mlir-translate` to produce LLVM IR and `cc` to compile
and link it with the runtime. Linea emits textual MLIR. `mlir-opt` writes its
converted intermediate with `--emit-bytecode`, and `mlir-translate` reads that
file directly and produces textual LLVM IR (ADR 0116). The intermediate remains
a real file, including when build artefacts are kept after a failure. Decode it
with `mlir-opt` to inspect it. Linea implements no bytecode format, and the tool
and verification boundaries are unchanged.

A program's manifest may name C sources (`"native"`) and libraries
(`"link"`). The loader records both on `Program` (`native`, `link`), with each
source joined to the manifest's directory. `toolchain.build` compiles each
source to an object beside the LLVM IR at the build's level, with the
sanitizer flags when the runtime has them, and links the objects before the
runtime archive and `-l<name>` after it. The conformance runner carries a
case's C files with its source and writes them under the build's scratch
directory, and the outcome cache keys on their bytes.

A build links one of two runtime archives that differ only in the allocator.
`liblinea_rt_checked.a` compiles `runtime/linea_rt.c` with
`LINEA_CHECK_STORAGE`, which gives every allocation pages of its own followed
by a guard page, retires freed pages as inaccessible and never reuses an
address, so a use of freed storage faults and the runtime's fault handler
aborts naming it. `Storage` in `toolchain.zig` names the choice: `test` always
links the checking archive, `run` and `build` link it with `--check-storage`,
and `LINEA_RUNTIME` overrides both. Only the checking archive defines
`linea_storage_checked`, which is how the driver and the conformance runner
tell the two apart; the I/O entries hand every extent to
`linea_storage_extent` before a system call. The generated code is the same
in both modes (ADR 0197).

Floating-point Debug formatting uses the pinned Zig standard library's Ryu
algorithm in `runtime/float.zig`. `std/fmt/float.lin` reads the IEEE bits with
`to_bits` and passes them through the integer foreign interface.
A `Float32` crosses as the bits of the `Float64` holding the same value, which
widening gives exactly; `linea_float32_debug` and `linea_float32_shortest`
narrow it back and render it at binary32, so both widths share one writer.
The runtime returns at most 32 ASCII bytes packed numerically into four integers;
the Linea adapter writes immutable character slices through the caller's Writer.
No temporary runtime buffer becomes a Str, and both sides use bounded storage.

`to_bits` and `from_bits` are methods over four `std.mem` externs
(`linea_float64_to_bits` and its kin) whose provider is lowering: the checker
holds them to the runtime table, `RawAccesses.float_bits` records the checked
declarations, and lowering replaces each call with one `bit_cast`
instruction, emitted as `arith.bitcast`. Emission writes every NaN-producing
float result (`addf`, `subf`, `mulf`, `divf`, `extf`, `truncf`, math calls) as
`%nr`, then defines the value with `canonicalNan`: a select of the positive
quiet NaN where the result is unordered with itself (ADR 0249). A `Float64`
from C passes through the same writer, `writeCanonicalNan`, where it crosses:
an extern call's result, a value C left behind an `inout` argument, and each
float parameter of an export or callback entry. Negation, loads, stores and
bit casts keep every bit.

Checked decimal input uses the same integer foreign interface. The private
`std.mem` adapter passes a certified byte address and extent to
`linea_float64_parse`; status, IEEE bits and syntax offset return as integers.
`std.text.parse_float64` builds the result from those bits with `from_bits`. `linea_float32_parse` shares the scanner and rounds
once to binary32 with the same provider; `std.text.parse_float32` builds the
binary64 value it returns and narrows it, exactly. The runtime validates the complete decimal token and
uses the pinned Zig toolchain's integer-only conversion provider, so rounding
is nearest-even independently of the ambient floating mode. The build copies
four unchanged provider files into a generated module and installs their MIT
notice. No runtime pointer or temporary view escapes this boundary (ADR 0143).

The build emits the Zig formatter as C and compiles it with the runtime's C
sanitizer flags. This lets Clang instrument its memory accesses. Zig's generated
unsigned wrapping helpers require disabling unsigned-overflow instrumentation
for the generated formatter C file; the other runtime checks remain enabled.

### Formatter and dumps — `src/fmt/`, `src/*/dump.zig`

Own: rendering source and recorded compiler data as text. Dumps read decisions
from their producing passes. For example, `noteCallees` reads `module.names`
instead of generating symbol names independently.

`fmt` only parses the input; type errors do not prevent formatting. It refuses
syntax errors because it cannot faithfully print error nodes.

Formatting and editable LSP indices traverse `Program.ast`, not the expanded
tree. Semantic lookup may reach generated declarations, but references omit
their nonexistent source locations and rename refuses an operation with a
generated supplier. This source-ID filter prevents generated tokens from being
offered as workspace edits while retaining their semantic effect.

## The seams

Each row identifies a pass boundary, the information passed across it, and the
record that consumers must read.

| Seam | What crosses it | Recorded as |
| --- | --- | --- |
| Lexer → Parser | tokens, spans, reserved words | the `TokenList` itself |
| Parser → Resolver | source tree shape, declaration kinds including template and standalone derive forms, ordered closed attribute groups and attached derive entries, normalized visibility and ownership policy, panic expressions, written trailing constraints | source `Ast` accessors — `declTokens`, `declName`, `declOwner`, `declAttributeGroups`, `attachedDeriveTraitRange`, `deriveRequestTraitRange`, `declTraitRef`, `boundsOf`, constraint subject and requirement accessors |
| Loader → Resolver | which source modules exist, which independently loaded root owns each, what each imports, canonical routes between loaded modules, the source interner and source tree, and the bytes each embed read | `Program.modules` including typed `Module.root`, `Program.importRoute`, `Program.ast`, `Interner`, `Program.embeds` (borrowed into `Resolution.embeds` for the checker, the constant folder and lowering) |
| Resolver → Checker | immutable expanded syntax and active roots; generated declaration modules and import targets, declaration and rendered origins, template plans, generated-implementation descriptors and ordered component-requirement rows; which declaration each name reaches, each binding's kind, bound classification, references and open scopes for written constraints, the implementations the compiler provides, lambda source identity and parameter scopes | `ExpandedProgram` plus `Resolution` — `declsOf`, `moduleOf`, `importedBy`, declaration origins, generated span origins, `template_members`, `generatedImplementation`, `componentRequirements`, `targets`, `written`, `variant_ordinals`, `ambient_impls`, `closures`, scope tables; `boundNames` for the bounds |
| Checker → Ownership | expanded roots; types including `Never`, universes, which expressions the checker refused, accepted source or generated bodies, generated bodies suppressed during semantic recovery, and each call's normalised target and arguments | `ExpandedProgram` plus `Typing` — binding/expression types, `refused`, `selected_places`, `folded_indices`, closure descriptors, `variant_uses`, `suppressed_generated_bodies` in shared module/root order, normalised calls and `call_index`; contract destinations remain keyed to the expanded AST transfer. Ownership decides consuming positions itself, from where each expression sits |
| Checker → Instantiation | expanded roots; admitted generic call selections and their satisfied normalised constraints, callable conversions, normalised targets, implementations, `Self`, layouts, checked named constants | `ExpandedProgram` plus `Typing` — `constant_values`, declaration constraints, `function_values`, closure descriptors, normalised calls and `call_index`, `implementations`, `implementation_selections`, `laid_out`, `raw_accesses` |
| Instantiation → Lowering | every reachable concrete source or generated declaration and closure body, its type arguments, `Self`, stable symbol, concrete implementation selections and derive-primary source origin | `ExpandedProgram` plus `InstanceTable` — ordered instances, lookup by `BodyOrigin` plus concrete arguments, and `selectedImplementation`/`selectedReceiver` by concrete trait key; `Typing.raw_accesses` and the exact `InstanceTable.zeroed_allocator` declaration identity; `primaryFileOfDecl` and `primarySpanOfDecl` |
| Ownership → Instantiation / Lowering | ordered deferred expressions that run at each scope exit, after cancellations | `DisposalPlan.schedulesAt(exit)` — keyed by expanded exit `ExprId`. Ownership alone places, orders, and cancels schedules; Discovery visits and MIR emits that answer without maintaining schedule stacks. |
| Lowering → Verifier/Backend | symbols, blocks, generated origins, layouts, computation/storage representations including code pointers and no `Never` value, direct/indirect normal and noreturn call operations, message-bearing traps, instruction result roles, local slot roles, normal/no-value return conventions | `mir.Module` — `names`, `origins`, `layouts`, `representations`, call and trap payloads, optional `zeroed_allocator`, `resultRepresentationOf`, `slotRepresentationOf`, `entry`, `arrivesByAddress`, `returnsIndirectly` |
| Every pass → Dumps | what each pass settled | `Typing`, `mir.Module.names`, `mir/notes.zig` |
| Every pass → Diagnostics | source file, span, label, rule code; generated labels collapse to their derive before the next pass and may retain a secondary template/component origin | the `Sink` plus `ExpandedProgram` declaration and rendered-origin indexes; rule names in `diagnostics/diagnostic.zig`, gated against `docs/linea-semantics.md` |

## Reusing a checked library

The driver can own an immutable `CheckedLibrary` session containing parsed and
expanded syntax, resolver continuation state, typing answers, and a successful
ownership disposal plan. Conformance workers share that snapshot and own their
mutable continuation tables. The language server checks the library once when
it starts and resumes every module it analyses from it, with the method lists
an editor's completions read prepared on the continued typing as well. The
ordinary command-line compiler still performs a fresh compilation.

Library source IDs remain a prefix. Generated syntax moves after application
source through typed, domain-specific relocation; semantic tables relocate their
syntax references while retaining library binding and type identities. The
existing passes continue from these answers. Combined-program coherence,
application-dependent lookups, and obligations still run; ownership omits only
the exact declarations already checked in the snapshot.

Reuse eligibility belongs to the resolver. Incompatible graphs, application
expansions, generated-name collisions, and application closures use ordinary
loading and checking. Closures require that fallback because generated names
still depend on allocation order. Returned typing uses the retained allocator,
not the temporary scratch allocator. The snapshot outlives its continuations;
no pass owns a global cache or mutates the shared snapshot.

## Diagnostics, and where the compiler stops

Malformed source does not abort a frontend pass. Passes accumulate diagnostics
in a `Sink`; **only the driver stops compilation, between passes**. Ownership
can therefore check valid parts of a program after type errors, and source or
token dumps can describe rejected input. Mono and MIR dumps require successful
instance discovery and produce no partial module.

A rule name in a diagnostic is a literal index into `docs/linea-semantics.md`,
and a gate fails the build if the compiler can emit a name the document does
not define. Every emitted rule must have a definition in the language reference.

Exit statuses: `0` accepted, `1` diagnostics, `64` usage, `70` the backend
refused to emit, `74` I/O.

## Representations the compiler does not have

ADR 0001 names an HIR, a typed tree and an optimiser as representations the
compiler could grow; none exists. ADR 0015 permits a new representation only
when it discards information, adds nodes no side table could key, simplifies
invariants or passes in aggregate, or improves backend independence, and the
record introducing it names which condition it meets.

### No HIR

`ExpandedProgram` is an expanded syntax tree, not an HIR: it keeps the source
tree as an exact prefix and appends parsed ordinary declarations rather than
normalising syntax. Parentheses are a node, deliberately, because a formatter
that drops them rewrites the programmer's source; resolution, checking,
ownership, discovery and MIR lowering therefore all call the AST's shared
`withoutGroups` helper. Logical operators have three readers that establish
different facts: `typecheck.checkLogical` checks Boolean operands and propagates
a non-returning left operand without creating a conditional; ownership's
`logical` records taken and skipped paths; MIR's `logical` alone selects which
Boolean value short-circuits. They are representation-specific consequences of
one language rule, and conformance compares the operators against explicit
conditionals to check their agreement. An HIR proposal must identify the problem
it solves and show that it removes more machinery than its construction and
source mapping add.

### No optimiser

LLVM optimises the generated code. `mlir-opt` runs conversion passes only, then
`cc` compiles the translated IR at the selected optimisation level, `-O2` by
default and overridden by the CLI's `-O`. The emitted IR carries no no-wrap
flags, aliasing metadata or fast-math flags, so it grants none of the
assumptions those annotations permit (ADR 0013: the compiler may not treat the
absence of undefined behaviour as a premise for optimisation). Monomorphisation
is required to materialise generic code; it is not an optional optimisation. A
Linea optimiser would need a benchmark showing a transformation LLVM cannot
derive from the emitted IR, such as eliminating a copy using ownership's
last-use knowledge; improving the storage-oriented IR the emitter produces is
separate work (ADR 0090).

### No typed tree

Types and symbols are recorded in `Typing` and `Resolution`, keyed by expanded
tree IDs as ADR 0015 requires for annotations. Ownership's `Cfg` and MIR's
explicit operations represent disposal points. Generated declarations needed a
new representation because source IDs could not key nodes absent from the source
tree; `ExpandedProgram` answers that need without becoming a typed tree.

## Adding a pass

Before adding a pass, specify **what it decides, where it records the result,
and which later passes consume it**. If another pass already owns that decision,
use its recorded answer. If a new decision is needed, provide a record that
prevents consumers from having to derive it again.

Binding records: ADR 0002 (project structure), ADR 0009 (stable IDs across
passes), ADR 0012 (immutable representations), ADR 0015 (when to introduce a
representation), ADR 0120 (caller-owned result and scratch lifetimes), ADR 0022
(MIR is explicit control flow), ADR 0023 (one symbol space, two-phase resolution), ADR 0032 (a
module is a directory), ADR 0034 (ownership is positions and a graph), ADR 0048
(one question has one answer), ADR 0049 (generated code is verified before it
is emitted), ADR 0106 (non-completion is `Never`), ADR 0107 (one normalised
constraint model), ADR 0116 (MLIR bytecode between tools), ADR 0117 (bounded
callable specialisation), ADR 0118 (unobserved array initialisers), and ADR 0119
(verified zeroed-allocation facts).

### Command conformance input

A command case is a transcript (`src/conformance/transcript.zig`) run by one
`/bin/sh` through `src/conformance/process.zig`, whose standard input is
empty. A command that reads input names a fixture with the shell's own `<`,
such as `< $LINEA_ROOT/tests/cmd/stdin/formats_supplied_source.stdin`, so the
file reaches the command directly and no pipe is fed while the command writes
output. The runner drains standard output and standard error together, so a
child filling one pipe cannot deadlock against the other.
