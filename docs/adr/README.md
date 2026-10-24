# Architecture Decision Records

Each record captures one decision, the constraints that forced it, and the
alternatives that lost along with the technical reason they lost. That last
section is the point of the exercise: the decision itself is usually visible in
the code, while the reasoning that ruled out the obvious alternative is not.

## Conventions

Records are append-only. A decision that changes gets a **new** record marked
`Supersedes NNNN`, and the original is marked `Superseded by NNNN` and
otherwise left alone.

Supersession applies to decisions that were accepted and built against — where
a reader needs to know the code once worked differently. An option weighed and
discarded during design was never a decision; it belongs under *Alternatives
considered* in the record that rejected it.

The same boundary decides when a record may be corrected in place instead. A
clause describing behaviour nothing ever implemented is a design sketch, not a
decision that shaped code, so refining it is closer to fixing an error than to
rewriting history. Once a clause has shaped code, it is superseded rather than
edited. The test is not how old the record is — it is whether anything was
built against the specific clause being changed.

Format is Nygard-style: Status, Context, Decision, Consequences, Alternatives
considered. Consequences include the costs, not only the benefits.

Every record here describes the compiler as it stands, and a reader is entitled
to read it that way. The one exception is a record whose status begins
**Proposed**: it states a direction taken before the code exists, and says in its status which sentence of an existing
record it would change. A Proposed record states no `extends` or `supersedes`
relation, so the records it would change are not marked and stay true of the
compiler as it stands; building the form turns the status to Accepted and adds
the relations in the same change. Any other decision with no code behind it
is a design sketch: it belongs in the *Alternatives considered* of
whatever record eventually settles it. The test for whether something has
earned a record is whether a constraint forced it — an interesting question
nothing is blocked on is a question, and the place for one is *Open questions*
below.

## How we decide

Records governing how the architecture is allowed to grow.

| # | Decision | Status |
| --- | --- | --- |
| [0001](0001-staged-compiler-evolution.md) | Evolve the compiler in stages rather than building the final architecture | Accepted |
| [0011](0011-zig-is-inspiration-not-template.md) | Zig is an inspiration, not a template | Accepted |

## Language rules

Records about what Linea means, rather than how its compiler is built. They
constrain the compiler because it must implement them, but they would still be
true of a different implementation.

| # | Rule | Status |
| --- | --- | --- |
| [0013](0013-no-undefined-behaviour.md) | No operation has undefined behaviour | Accepted; extended by 0091 and 0228 |
| [0014](0014-unused-declarations-are-errors.md) | An unused declaration is an error | Accepted |
| [0189](0189-a-names-case-is-part-of-its-kind.md) | A name's case is part of its kind | Accepted; extended by 0190 |
| [0194](0194-an-alias-names-a-type-that-exists.md) | An alias names a type that exists | Accepted; extended by 0206 and 0215; path clause for a generic alias superseded by 0211 |
| [0211](0211-a-generic-alias-heads-a-path-and-the-call-settles-its-parameters.md) | A generic alias heads a path, and the call settles its parameters | Accepted; supersedes the path clause of 0194; extends 0206 |
| [0215](0215-a-type-parameter-may-default-its-argument.md) | A type parameter may default its argument | Accepted; supersedes 0206; extends 0098 and 0194; extended by 0217, 0219 and 0225 |
| [0217](0217-a-call-leaves-an-undetermined-parameter-to-its-types-default.md) | A call leaves an undetermined parameter to its type's default | Accepted; extends 0215; extended by 0219 |
| [0219](0219-a-function-type-parameter-and-its-parameter-may-default.md) | A function type parameter and its parameter may default | Accepted; extends 0077, 0215 and 0217; extended by 0225 |
| [0199](0199-tuple-syntax-denotes-a-positional-aggregate-with-a-prelude-identity.md) | Tuple syntax denotes a positional aggregate whose identity is a prelude declaration | Accepted; builds on 0060, 0129, 0151, 0179 and 0188; extended by 0200 |
| [0200](0200-a-tuples-arity-is-a-readability-policy-the-parser-enforces.md) | A tuple's arity is a readability policy the parser enforces | Accepted; extends 0199 |
| [0201](0201-a-tuple-pattern-binds-by-position-and-does-not-nest.md) | A tuple pattern binds by position wherever a struct pattern binds by name, and does not nest | Accepted; extends 0129 and 0147; nesting clause and lending-walk place superseded by 0224 |
| [0224](0224-a-pattern-nests-wherever-a-binder-stands.md) | A pattern nests wherever a binder stands | Accepted; supersedes the nesting clause and lending-walk place of 0201; extends 0129, 0147 and 0167 |
| [0207](0207-linea-converts-nothing-implicitly.md) | Linea converts nothing implicitly | Accepted; extends 0018 and 0061 |
| [0208](0208-defer-let-binds-and-schedules-its-release.md) | `defer let` binds a value and schedules its release | Accepted; extends 0063 and narrows 0104's no-scheduling sentence to "never without a written `defer`" |
| [0203](0203-zip-and-skip-require-discardable-items-and-zip-is-left-biased.md) | `zip` and `skip` require the items they dispose of to be Discardable, and `zip` is left-biased | Accepted; extends 0192 |
| [0245](0245-iterator-adapters-are-lazy.md) | Iterator adapters are lazy, reversal needs a double-ended source, and only a terminal allocates | Proposed; would extend 0192 and 0203 |
| [0017](0017-failure-is-a-trap-or-a-value.md) | Failure is either a trap or a value, never both | Accepted; refined by 0106 |
| [0018](0018-the-integer-model.md) | Fixed-width integers, literals typed by context, conversions explicit | Accepted; extended by 0092, 0152, 0207 and 0226 |
| [0019](0019-entry-point-is-main-returning-u8.md) | A program is `fn main() -> u8` | Superseded by 0024 |
| [0020](0020-a-constant-expression-is-defined.md) | A constant expression is defined by the language, not discovered by a pass | Accepted; extended by 0059, 0078, 0083, 0127, 0140, 0146 and 0157 |
| [0058](0058-a-constant-declaration-is-a-binding-the-definition-covers.md) | A constant declaration is a binding the definition already covers | Superseded by 0059 |
| [0059](0059-one-table-answers-both-questions-about-a-constant-expression.md) | One table answers both questions about a constant expression | Accepted; supersedes 0058, extends 0020; extended by 0127, 0140 and 0146 |
| [0024](0024-a-program-is-a-list-of-declarations.md) | A program is a list of declarations | Accepted; supersedes 0019, extended by 0071 |
| [0025](0025-mutation-through-a-parameter-is-marked.md) | Mutation through a parameter is a convention, marked at the call | Accepted; exclusivity clause superseded by 0053; reference and ABI clauses superseded by 0123 |
| [0040](0040-conditional-control-flow-has-one-form.md) | Conditional control flow has one form | Accepted |
| [0041](0041-a-newline-ends-a-statement.md) | A newline ends a statement, decided by the token before it | Superseded by 0196; refined by 0151, 0167 and 0190 |
| [0042](0042-nesting-is-bounded-by-a-stated-number.md) | Nesting is bounded by a stated number | Superseded by 0054 |
| [0043](0043-a-separator-that-answers-a-note-is-kept.md) | A separator that answers a note is kept | Accepted; refined by 0190 and 0202 |
| [0190](0190-a-variant-line-is-not-a-continuation.md) | A variant line is not a continuation | Accepted; refines 0041 and 0043; extends 0189; lowercase-selection clause superseded by 0196; refined by 0202 |
| [0196](0196-a-selection-line-continues-the-line-above.md) | A newline ends a statement, unless the next line selects from it | Accepted; supersedes 0041 and the lowercase-selection clause of 0190; refined by 0202 |
| [0202](0202-a-line-beginning-with-a-parenthesis-is-noted-only-as-an-empty-call.md) | A line beginning with `(` is noted only as an empty call | Accepted; refines 0043, 0190 and 0196 |
| [0046](0046-the-universe-of-an-instantiation-is-computed.md) | The universe of an instantiation is computed | Accepted; refines 0034, refined by 0051 and 0123; classification superseded by 0124 |
| [0047](0047-instantiation-is-a-backend-concern.md) | Instantiation is a backend concern | Accepted; extended by 0142 |
| [0051](0051-a-part-obliges-when-no-argument-can-remove-it.md) | A part obliges when it is Linear for a reason no argument can remove | Accepted; refines 0046; superseded by 0124 |
| [0053](0053-exclusivity-is-triggered-by-mutation.md) | Exclusivity is triggered by mutation, not by the marker | Accepted; supersedes the exclusivity clause of 0025 |
| [0054](0054-the-bound-is-on-height-and-covers-written-types.md) | The nesting bound is on height, and a written type answers to it | Accepted; supersedes 0042 |
| [0056](0056-a-modifier-is-refused-where-it-says-nothing.md) | A modifier is refused where it says nothing | Accepted; extended by 0145 |
| [0065](0065-a-phantom-type-parameter-is-declared.md) | A phantom type parameter is declared, not inferred from disuse | Accepted; its bound clause superseded by 0099 |
| [0066](0066-a-blocks-state-is-its-dominators-plus-what-it-changed.md) | A block's state is its dominator's, plus what it changed | Accepted; refined by 0073 |
| [0067](0067-a-place-is-updated-through-itself.md) | A compound assignment updates a place through itself | Accepted |
| [0068](0068-a-declaration-may-name-a-symbol-the-runtime-provides.md) | A declaration may name a symbol the runtime provides | Accepted; extended by 0150 and 0156; `std/` clause superseded by 0171; integer-only, linear and callable clauses superseded by 0228 |
| [0150](0150-float-math-crosses-a-checked-scalar-boundary.md) | Float math crosses a checked scalar boundary | Accepted; extends 0068; general-Float64 clause superseded by 0228 |
| [0226](0226-float32-is-a-second-binary-floating-point-width.md) | Float32 is a second binary floating-point width | Accepted; extends 0018 and 0152 |
| [0156](0156-every-declaration-of-an-extern-symbol-is-one-function.md) | Every declaration of an extern symbol is one function | Accepted; extends 0068 |
| [0228](0228-a-granted-module-calls-c.md) | A granted module calls C | Accepted; supersedes clauses of 0068, 0150 and 0171; extends 0013, 0101 and 0229 |
| [0151](0151-a-named-structure-literal-carries-a-written-type.md) | A named structure literal carries a written type | Accepted; refines 0041; extended by 0183 |
| [0183](0183-a-structure-literal-may-take-its-other-fields-from-a-base.md) | A structure literal may take its other fields from a base | Accepted; extends 0151 and 0140 |
| [0152](0152-an-integer-literals-type-is-settled-by-its-uses.md) | An integer literal's type is settled by its uses | Accepted; extends 0018, partially supersedes 0092; extended by 0176 and 0226; method-call fallback refined by 0192 |
| [0144](0144-context-selects-single-payload-enum-constructor-values.md) | Context selects single-payload enum constructor values | Accepted; extends 0128 and 0132 |
| [0069](0069-a-view-is-a-value-rooted-at-a-place.md) | A view is a value rooted at a place | Superseded by 0123 |
| [0070](0070-explicit-failure-is-acknowledged.md) | Explicit failure is acknowledged | Accepted |
| [0071](0071-a-failure-may-leave-through-the-entry-point.md) | A failure may leave through the entry point | Accepted; extends 0024 |
| [0072](0072-a-declaration-only-generated-code-calls-is-named-by-its-module.md) | A declaration only generated code calls is named by its module | Accepted; refines 0060, refined by 0106 |
| [0073](0073-a-scope-exit-names-a-stretch-of-the-live-stack.md) | A scope exit names a stretch of the live stack | Accepted; refines 0066 |
| [0074](0074-a-module-is-emitted-as-several-compilation-units.md) | A module is emitted as several compilation units | Superseded by 0094 |
| [0075](0075-a-program-root-is-a-directory-holding-a-manifest.md) | A program root is a directory holding a manifest | Accepted; command-line-file clause superseded by 0171; extended by 0227 |
| [0061](0061-an-array-is-a-value-of-a-fixed-size-type.md) | An array is a value of a fixed-size type | Accepted; extended by 0083, 0137, 0149, 0166, 0172, 0198 and 0207 |
| [0062](0062-an-indexed-place-is-a-place-and-every-index-is-checked.md) | An indexed place is a place, and every index is checked | Accepted; bracket clause, never implemented, replaced by 0181 |
| [0063](0063-disposal-is-scheduled-never-inserted.md) | Disposal is scheduled, never inserted | Accepted; extends 0034, extended by 0104 and 0208, refined by 0114 |
| [0103](0103-linear-constrains-consumption-release-grants-one-way.md) | Linear constrains consumption; Release grants one way to consume | Accepted; extends 0104 with container decisions; extended by 0124 and 0138 |
| [0064](0064-heap-memory-is-a-linear-value-from-an-explicit-allocator.md) | Heap memory is a linear value obtained from an explicit allocator | Superseded by 0095 |
| [0077](0077-arguments-match-by-name-and-evaluate-by-declaration.md) | Arguments match by name and evaluate by declaration order | Accepted; refined by 0136 and 0146; extended by 0219 |
| [0078](0078-a-truth-value-is-a-constant-expression.md) | A truth value is a constant expression | Accepted; extends 0020; representation superseded by 0127 |
| [0079](0079-a-projection-is-one-structural-step.md) | A projection is one structural step for the termination measure | Accepted |
| [0080](0080-a-dotted-type-name-resolves-through-its-module.md) | A dotted type name resolves through its module | Accepted; trait-slot clause superseded by 0110 |
| [0081](0081-an-implementation-is-generic-over-its-head.md) | An implementation is generic over its head, and coherence keys on the constructor | Accepted; extended by 0087, 0093, 0139 and 0213; head restriction superseded by 0148; partially superseded by 0142 and 0182 |
| [0182](0182-a-types-own-implementation-may-fix-its-type-arguments.md) | A type's own implementation may fix its type arguments | Accepted; partially supersedes 0081 |
| [0082](0082-a-comparison-is-a-trait-call.md) | A comparison is a call on the trait it names | Accepted; extended by 0112 and 0138 |
| [0083](0083-an-arrays-length-is-part-of-its-type-everywhere-it-is-written.md) | An array's length is part of its type, everywhere it is written | Accepted; extends 0061 and 0020; extended by 0149, 0172 and 0198 |
| [0084](0084-test-is-a-reserved-word-not-a-contextual-one.md) | `test` is a reserved word, not a contextual one | Accepted |
| [0085](0085-the-library-is-imported.md) | The library is imported, and the prelude is what the syntax obliges | Accepted; reserved-root clause superseded by 0171; minimal-prelude and no-shadowing clauses superseded by 0179 |
| [0171](0171-the-standard-library-is-an-ordinary-library.md) | The standard library is an ordinary library, known by its manifest | Accepted; supersedes clauses of 0068, 0075, 0085 and 0111; extends 0096; extended by 0229; boolean grant superseded by 0228 |
| [0179](0179-the-prelude-holds-the-core-vocabulary-and-yields-to-a-module.md) | The prelude holds the core vocabulary, and yields to a module's own names | Accepted; supersedes the minimal-prelude and no-shadowing clauses of 0085 |
| [0087](0087-an-associated-type-is-a-function-of-the-coherence-key.md) | An associated type is a function of the coherence key | Accepted; extends 0081; extended by 0088 and 0142 |
| [0088](0088-a-projecting-member-is-a-place-not-a-function.md) | A projecting member is a place, not a function | Accepted; extends 0087; extended by 0089, 0121 and 0126; partially superseded by 0135 |
| [0135](0135-field-delegation-uses-checked-projection-plans.md) | Field delegation and bound indexing share checked projection plans; traversal is explicit | Accepted; partially supersedes 0088; extends 0122 |
| [0089](0089-a-from-end-index-is-a-value-the-container-interprets.md) | A from-end index is a value the container interprets | Accepted; extends 0088 |
| [0093](0093-two-implementations-that-could-answer-once-are-refused.md) | Two implementations that could answer for one instantiation are refused | Accepted; extends 0081; extended by 0113 and 0213; default tier superseded by 0139; coherence partition superseded by 0148 |
| [0096](0096-a-root-is-a-program-or-a-library.md) | A root is a program or a library, and its manifest says which | Accepted; builds on 0075 and 0024; extended by 0101, 0171, 0227 and 0229 |
| [0101](0101-a-library-publishes-what-it-exports.md) | A library publishes what it exports, under the name its source spells | Accepted; extends 0096; extended by 0228 |
| [0106](0106-a-non-completing-expression-has-type-never.md) | A non-completing expression has type `Never` | Accepted; refines 0072, preserves 0017 |
| [0107](0107-a-trailing-where-predicate-constrains-any-open-type-expression.md) | A trailing `where` predicate constrains any open type expression | Accepted |
| [0108](0108-an-internal-name-stops-at-its-root.md) | An internal name stops at its loaded root | Accepted; extended by 0229 |
| [0229](0229-an-application-depends-on-a-library-by-path.md) | An application depends on a library by path | Accepted; extends 0096, 0108, 0111 and 0171; extended by 0228 |
| [0109](0109-text-io-and-formatting-have-separate-modules.md) | Text, I/O and formatting have separate modules | Accepted |
| [0110](0110-a-trait-reference-may-be-qualified.md) | A trait reference may be qualified | Accepted; supersedes ADR 0080's bare trait-slot clause |
| [0112](0112-comparable-carries-equality-compatible-order.md) | Comparable carries an equality-compatible order | Accepted; extends 0082 |
| [0113](0113-structural-derivation-is-library-defined-source.md) | Structural derivation is library-defined source | Accepted; extends 0035, 0045, 0049 and 0093; extended by 0138, 0145 and 0209; partially superseded by 0142 |
| [0145](0145-closed-attributes-attach-ordinary-derive-requests.md) | Closed attributes attach ordinary derive requests | Accepted; extends 0056 and 0113; extended by 0209; generic constraint clause superseded by 0165 |
| [0165](0165-an-attached-derive-requires-each-field-type.md) | An attached derive requires each field type | Accepted; partially supersedes 0142, 0145 and 0148 |
| [0122](0122-a-traversal-may-read-its-receiver.md) | A traversal may read its receiver | Accepted; extended by 0135 |
| [0123](0123-observations-carry-owner-dependencies-through-callable-contracts.md) | Observations carry owner dependencies through callable contracts | Accepted; supersedes 0069 and parts of 0025 and 0121; refines 0046; refined by 0124 and 0175; projection syntax superseded by 0126; extended by 0128, 0131, 0137, 0178, 0193 and 0221; source-clause spelling superseded by 0132; mandatory backing-buffer shape superseded by 0133 |
| [0124](0124-copyability-and-settlement-are-independent-capabilities.md) | Copyability and settlement are independent capabilities | Accepted; supersedes classification in 0034, 0046, and 0051; extends 0103; refines 0123; extended by 0125, 0131, 0193 and 0221 |
| [0125](0125-scalar-value-positions-take-snapshots.md) | Scalar value positions take snapshots | Accepted; supersedes universal explicit-copy clause of 0034; extends 0124 |
| [0221](0221-owned-admits-a-type-that-can-carry-no-borrow.md) | `Owned` admits a type that can carry no borrow | Accepted; extends 0123 and 0124 |
| [0126](0126-observations-project-referent-places-transparently.md) | Observations project referent places transparently | Accepted; supersedes projection syntax of 0123; extends 0088 |
| [0127](0127-constants-retain-distinct-values-and-infer-their-types.md) | Constants infer initializer types and retain distinct integer, boolean and text values | Accepted; extends 0020 and 0059, supersedes the representation decision in 0078; extended by 0140, 0146 and 0157 |
| [0140](0140-aggregate-constants-retain-checked-construction-plans.md) | Aggregate constants retain shared data and checked construction plans | Accepted; extends 0020, 0059 and 0127; extended by 0157, 0183 and 0227; materialization clause superseded by 0178; unit-expression clause superseded by 0188 |
| [0188](0188-the-unit-value-is-written-as-its-type.md) | The unit value is written as its type is, `()` | Accepted; supersedes the unit-expression clause of 0140 |
| [0223](0223-a-function-returning-nothing-writes-no-result.md) | A function returning nothing writes no result | Accepted |
| [0178](0178-a-constant-is-a-static-place.md) | A constant is a static place | Accepted; supersedes the materialization clause of 0140; extends 0123 and 0147; extended by 0227 |
| [0141](0141-json-documents-own-bounded-trees-and-number-tokens.md) | JSON documents own bounded trees and validated number tokens | Accepted |
| [0154](0154-sockets-and-http-follow-go.md) | Sockets and HTTP follow Go's shape where ownership allows | Accepted; extended by 0174, 0180 and 0185; subtree clause superseded by 0222 |
| [0174](0174-logging-is-a-leveled-structured-logger-and-http-logs-through-middleware.md) | Logging is a leveled, structured logger, and HTTP logs through middleware | Accepted; extends 0154; extended by 0180 |
| [0180](0180-state-is-lent-down-through-every-handler.md) | The application's state is lent down through every handler | Accepted; extends 0154, 0173 and 0174; extended by 0185 and 0214 |
| [0185](0185-a-handler-reads-its-inputs-through-extractors.md) | A handler reads its inputs through extractors | Accepted; extends 0154 and 0180; refined by 0214 |
| [0222](0222-a-route-pattern-matches-its-own-path.md) | A route pattern matches its own path | Accepted; supersedes the subtree clause of 0154 |
| [0232](0232-a-cookie-value-is-percent-encoded-text.md) | A cookie value is percent-encoded text: `set_cookie` takes any text and `Request.cookie` decodes it, reading a value that does not decode as absent | Accepted |
| [0142](0142-construction-derives-expand-to-ordinary-source.md) | Construction derives expand to ordinary source | Accepted; partially supersedes 0081 and 0113; extends 0047 and 0087; attached-derive predicate clause superseded by 0165 |
| [0143](0143-checked-decimal-conversion-uses-integer-rounding.md) | Checked decimal conversion uses bounded integer rounding | Accepted |
| [0146](0146-payload-free-variants-are-constant-expressions.md) | Payload-free variants are constant expressions | Accepted; extends 0020, 0059 and 0127; refines 0033 and 0077 |
| [0157](0157-a-newtype-built-from-a-constant-is-a-constant-expression.md) | A newtype built from a constant is a constant expression | Accepted; extends 0020, 0127 and 0140 |
| [0160](0160-a-postfix-call-reaches-the-types-own-operation-first.md) | A postfix call reaches the type's own operation before a trait's | Accepted; extended by 0186 and 0187 |
| [0186](0186-a-type-reaches-the-operations-of-the-traits-it-implements.md) | A type reaches the operations of the traits it implements | Accepted; extends 0160; extended by 0187 |
| [0187](0187-a-bound-brings-its-traits-operations-into-reach.md) | A bound brings its trait's operations into reach | Accepted; extends 0160 and 0186 |
| [0161](0161-a-postfix-call-reaches-an-operation-never-a-field.md) | A postfix call reaches an operation, never a field | Accepted; replaces the field-precedence sentence of the semantics; extended by 0181 |
| [0181](0181-a-call-may-name-its-type-arguments.md) | A call may name its type arguments | Accepted; replaces the unimplemented bracket clause of 0062; extends 0161; refines 0176 |
| [0162](0162-question-mark-converts-an-error-through-from.md) | `?` converts a different error through `From` | Accepted; extended by 0184 and 0218 |
| [0163](0163-a-raw-string-literal-holds-its-bytes.md) | A raw string literal holds its bytes: `r"…"`, with hashes for embedded quotes | Accepted |
| [0167](0167-a-binding-handles-its-failure-with-else.md) | A binding handles its failure with `else` | Accepted; builds on 0070 and 0106; refines 0041; extended by 0224 |
| [0168](0168-multi-line-text-is-a-run-of-backslash-lines.md) | Multi-line text is a run of `\\` lines, raw, joined with line breaks | Accepted |
| [0227](0227-a-program-embeds-a-files-bytes.md) | A program embeds a file's text or bytes, read when it is compiled: `embed` and `embed_bytes` | Accepted; extends 0075, 0096, 0140 and 0178 |
| [0169](0169-an-interpolation-lays-out-its-value-through-a-format-spec.md) | An interpolation lays out its value through a format spec checked against its type and applied by `std.fmt` | Accepted; extended by 0231 |
| [0231](0231-a-format-spec-writes-an-integer-in-hexadecimal.md) | A format spec writes an integer in hexadecimal with `x` or `X`, and the library has one hexadecimal alphabet: `text.hex_encoded`, `hex_decode` | Accepted; extends 0169 |
| [0170](0170-a-marked-postfix-call-lends-its-receiver.md) | A marked postfix call lends its receiver | Accepted; extended by 0195 |
| [0195](0195-a-walk-may-borrow-the-iterator-it-advances.md) | A walk may borrow the iterator it advances | Accepted; extends 0170 |
| [0175](0175-a-borrowed-temporary-lives-until-the-end-of-its-statement.md) | A borrowed temporary lives until the end of its statement, and an interpolation borrows what it renders | Accepted; refines 0123 |

## Compiler invariants

Records that constrain every pass and every representation, including ones not
yet written. A new representation is expected to satisfy all of these, and to
say so.

| # | Invariant | Status |
| --- | --- | --- |
| [0003](0003-infallible-frontend.md) | The lexer and parser never fail | Accepted; refined by 0205 |
| [0009](0009-stable-ids-across-passes.md) | All cross-pass references are stable typed IDs | Accepted; extended by 0100 |
| [0100](0100-a-per-element-table-is-keyed-and-sized-by-its-domain.md) | A per-element table is keyed and sized by the domain it holds | Accepted; extends 0009 |
| [0010](0010-data-oriented-not-soa-everywhere.md) | Data-oriented design is the principle; SoA is one technique | Accepted |
| [0012](0012-immutable-representations.md) | Representations are immutable once produced | Accepted |
| [0015](0015-when-to-introduce-a-representation.md) | A new representation must discard, add, or simplify | Accepted |
| [0016](0016-passes-are-functions.md) | A pass is a function, and its arena is its caller's | Superseded by 0120 |
| [0120](0120-pass-results-and-scratch-have-distinct-caller-owned-lifetimes.md) | Pass results and scratch have distinct caller-owned lifetimes | Accepted; supersedes 0016 |
| [0048](0048-one-question-has-one-answer.md) | One question has one answer, and one place that computes it | Accepted; extended by 0115 |
| [0049](0049-generated-code-is-verified-before-it-is-emitted.md) | Generated code is verified before it is emitted | Accepted; extended by 0113 and 0204 |
| [0205](0205-passes-run-on-a-stack-sized-for-the-nesting-limit.md) | Passes run on a stack sized for the nesting limit | Accepted; refines 0003 |
| [0091](0091-the-optimiser-is-given-proofs-not-premises.md) | The optimiser is given proofs, not premises | Accepted; extends 0013 |
| [0092](0092-a-settled-type-parameter-flows-inward.md) | A settled type parameter flows inward | Accepted; extends 0018; partially superseded by 0152 |

## Current decisions

Records about representations and machinery that exist today. These are the
ones most likely to be superseded as the compiler grows.

| # | Decision | Status |
| --- | --- | --- |
| [0002](0002-project-structure.md) | Compiler lives under `src/`, one directory per pass | Accepted |
| [0004](0004-soa-token-representation.md) | Tokens are stored SoA as `{ tag, span }` | Accepted |
| [0005](0005-lossless-token-stream.md) | The token stream is lossless; the syntax tree is abstract | Accepted |
| [0006](0006-typed-per-category-ast.md) | Syntax nodes are typed SoA arrays per category, storing token ranges | Accepted |
| [0007](0007-full-diagnostics-engine.md) | Build the complete diagnostics engine in Stage 1 | Accepted |
| [0008](0008-golden-conformance-suite.md) | Correctness is defined by a golden-file conformance suite | Accepted; extended by 0155 |
| [0021](0021-identifiers-are-interned.md) | Identifiers are interned; a token carries the handle | Accepted |
| [0022](0022-mir-is-explicit-control-flow.md) | MIR is the first representation whose control flow is explicit | Accepted |
| [0023](0023-one-symbol-space-and-two-phase-resolution.md) | One symbol space, resolved in two phases | Accepted |
| [0026](0026-the-corpus-checks-properties-a-golden-cannot.md) | The corpus checks metamorphic properties, not only recorded outputs | Superseded by 0134 |
| [0134](0134-conformance-compiles-ordinary-cases-once.md) | Ordinary conformance cases compile once; recompilation properties use focused witnesses | Accepted; supersedes 0026 |
| [0155](0155-transcript-cases-replace-one-line-command-cases.md) | A command case is a transcript of shell commands with their output inline | Accepted; extends 0008 |
| [0027](0027-generated-programs-are-well-typed-by-construction.md) | Generated programs are well-typed by construction | Accepted |
| [0028](0028-a-type-is-a-pool-handle-and-layout-is-a-table.md) | A type is a pool handle, and layout is a table the module carries | Accepted; payload clause superseded by 0030; extended by 0102 |
| [0029](0029-a-suite-must-be-able-to-fail-for-what-it-omits.md) | A suite must be able to fail for what it omits | Accepted; extended by 0055 and 0057 |
| [0055](0055-a-rule-name-is-not-the-unit-of-enforcement.md) | A rule name is not the unit of enforcement | Accepted; extends 0029, extended by 0057 |
| [0057](0057-a-mutation-answers-for-the-rules-it-declares.md) | A mutation answers for the rules it declares | Accepted; extends 0029 and 0055 |
| [0030](0030-a-variant-carries-several-values.md) | A variant carries several values; what stops a layout is a cycle | Accepted; supersedes the payload clause of 0028 |
| [0031](0031-fields-are-packed-at-their-natural-alignment.md) | Fields are packed at their natural alignment, in declaration order | Accepted; slot clause clarified by 0052; scalar-word consequence superseded by 0102 |
| [0032](0032-a-module-is-a-directory.md) | A module is a directory, and the entry may be a file | Accepted; import-path clause superseded by 0111 |
| [0033](0033-sealing-is-checked-not-omitted.md) | Sealing is checked, not omitted | Accepted; refined by 0146 |
| [0034](0034-ownership-is-positions-and-a-graph.md) | Ownership is positions and a graph, not a type system feature | Accepted; refined by 0046 and 0114, extended by 0063; classification and copying clauses superseded by 0124 and 0125 |
| [0035](0035-representation-and-behaviour-are-declared-apart.md) | Representation and behaviour are declared apart | Accepted; extended by 0113 |
| [0036](0036-formatting-is-comma-driven.md) | Formatting is comma-driven, and never rewrites a token | Accepted |
| [0037](0037-comments-are-placed-by-a-token-cursor.md) | Comments are placed by a token cursor, not an attachment pass | Accepted |
| [0038](0038-the-formatter-has-an-escape-hatch-and-no-configuration.md) | The formatter has an escape hatch and no configuration | Accepted |
| [0039](0039-formatting-is-a-normal-form.md) | Formatting is a normal form, checked by perturbation | Accepted |
| [0044](0044-the-hatch-covers-whole-nodes-or-refuses.md) | The hatch covers whole nodes, or the formatter refuses | Accepted |
| [0045](0045-sugar-is-expanded-by-one-renderer.md) | Sugar is expanded by one renderer, and it is compiled | Accepted; extended by 0113 |
| [0050](0050-the-layout-rule-has-a-second-implementation.md) | The layout rule has a second implementation, and it lives in the test | Accepted; extended by 0204 |
| [0052](0052-a-slot-is-as-wide-as-the-widest-access-to-it.md) | A slot is as wide as the widest access to it | Accepted; clarifies 0031; scalar-word consequence superseded by 0102 |
| [0060](0060-a-library-declaration-is-named-through-the-prelude.md) | A library declaration the compiler must name is named through the prelude | Accepted; refined by 0072 |
| [0076](0076-a-raw-access-is-a-declaration-lowering-replaces.md) | A raw access is a declaration lowering replaces | Accepted; uses 0072's mechanism; extended by 0121 |
| [0090](0090-the-backend-is-mlir-printed-rather-than-constructed.md) | The backend is MLIR, printed rather than constructed | Accepted; extended by 0116 |
| [0094](0094-a-module-is-emitted-as-one-compilation-unit.md) | A module is emitted as one compilation unit | Accepted; supersedes 0074 |
| [0095](0095-the-system-allocator-is-named-rather-than-received.md) | The system allocator is named rather than received | Accepted; supersedes 0064; extended by 0191 |
| [0097](0097-release-is-named-never-scheduled.md) | Release is named, never scheduled | Superseded by 0104 |
| [0098](0098-a-container-names-its-allocator-in-its-type.md) | A container names its allocator in its type | Accepted; extended by 0133, 0173, 0191, 0206 and 0215 |
| [0191](0191-the-caller-chooses-every-allocator.md) | The caller chooses every allocator, a test instrument's included | Accepted; extends 0095 and 0098; every-allocating-API clause superseded by 0220 |
| [0220](0220-a-constructor-or-function-that-allocates-pairs-a-system-form-with-an-in-form.md) | A constructor or function that allocates pairs a system form with an `_in` form | Accepted; supersedes the every-allocating-API clause of 0191; server-parent clause superseded by 0225 |
| [0225](0225-a-library-signature-states-its-allocator.md) | A library's public signature states its allocator | Accepted; extends 0215 and 0219; supersedes the server-parent clause of 0220 |
| [0206](0206-allocator-spelling-is-shortened-by-alias-never-by-default.md) | Allocator spelling is shortened by an alias, never by a default type argument | Superseded by 0215; extends 0098 and 0194; extended by 0211 |
| [0209](0209-a-from-derive-converts-the-variant-the-source-names.md) | A `From` derive converts the variant its source type names | Accepted; extends 0113 and 0145 |
| [0213](0213-a-trait-may-be-implemented-for-a-callable-type.md) | A trait may be implemented for a callable type, keyed by its shape | Accepted; extends 0081, 0093 and 0148 |
| [0214](0214-a-route-takes-a-function-whose-parameters-name-its-inputs.md) | A route is a function whose parameters name its inputs | Accepted; refines 0185; extends 0180; `where carries(request)` clause superseded by 0216 |
| [0216](0216-a-carrier-type-supplies-its-signatures-default-contract.md) | A carrier type supplies its signatures' default contract | Accepted; supersedes the `where carries(request)` clause of 0214 |
| [0099](0099-a-phantom-parameter-carries-its-bound.md) | A phantom parameter carries its bound | Accepted; supersedes the bound clause of 0065 |
| [0102](0102-computation-and-storage-representations-are-separate.md) | Computation and storage representations are separate | Accepted; extends 0028; partially supersedes 0031 and 0052 |
| [0104](0104-release-is-optional-and-never-scheduled.md) | Release is optional and never scheduled | Accepted; supersedes 0097, extends 0063; extended by 0103, 0158, 0184 and 0208 |
| [0184](0184-a-failure-holding-an-owned-value-settles-to-its-reason.md) | A failure holding an owned value settles to its reason | Accepted; extends 0104 and 0162; `http.Error` settling clause superseded by 0218 |
| [0218](0218-the-library-gives-up-no-value-at-question-mark.md) | The library gives up no value at `?`; `.settled()` says so | Accepted; extends 0162; supersedes the `http.Error` settling clause of 0184 |
| [0128](0128-qualified-enum-constructors-are-contextual-callables.md) | Qualified enum constructors are contextual callables | Accepted; extends 0105 and 0123; extended by 0144 |
| [0129](0129-struct-destructuring-may-infer-its-type.md) | Struct destructuring may infer its type | Accepted; extended by 0147, 0201 and 0224 |
| [0147](0147-a-borrowed-let-pattern-reads-a-stable-place.md) | A borrowed let pattern reads a stable place | Accepted; extends 0129; extended by 0178, 0201 and 0224 |
| [0130](0130-explicit-captures-use-inline-environments.md) | Explicit captures use inline environments | Accepted; supersedes the capture exclusion in 0105; read-only restriction superseded by 0131; extended by 0173 and 0193 |
| [0131](0131-closure-invocation-and-capture-ownership-are-independent.md) | Closure invocation and capture ownership are independent | Accepted; supersedes the read-only restriction in 0130; extends 0123 and 0124; extended by 0132, 0158 and 0173; stored inout capture clause superseded by 0193 |
| [0193](0193-a-closure-may-hold-a-place-lent-inout.md) | A closure may hold a place lent `inout` | Accepted; supersedes the stored inout capture clause of 0131; extends 0123, 0124, 0130 and 0173 |
| [0132](0132-callable-results-separate-types-from-dependencies.md) | Callable results separate types from dependencies | Accepted; supersedes source-clause spelling in 0123; extends 0131; extended by 0144, 0164 and 0173 |
| [0158](0158-a-function-value-implements-release.md) | A function value implements Release | Accepted; extends 0104 and 0131; extended by 0173 |
| [0173](0173-a-capturing-closure-is-erased-into-allocator-owned-storage.md) | A capturing closure is erased into allocator-owned storage | Accepted; extends 0098, 0105, 0130, 0131, 0132 and 0158; extended by 0176, 0180 and 0193 |
| [0105](0105-callable-values-have-static-call-targets.md) | Callable values have static call targets | Accepted; extended by 0117, 0128, 0153, 0173, 0176 and 0177; capture exclusion superseded by 0130; conversion name equality superseded by 0136 |
| [0153](0153-an-inherent-impl-function-is-a-function-value.md) | An inherent implementation's function is a function value | Accepted; extends 0105; extended by 0176 |
| [0176](0176-a-function-name-is-a-value-its-uses-instantiate.md) | A function name is a value, and its uses instantiate it | Accepted; extends 0105, 0152, 0153 and 0173; extended by 0177; refined by 0181 |
| [0177](0177-a-parameter-name-is-a-label-not-part-of-a-function-type.md) | A parameter's name is a label, not part of a function type | Accepted; supersedes labels in callable identity from 0136; extends 0105 and 0176 |
| [0114](0114-ownership-records-the-disposal-plan.md) | Ownership records the disposal plan that lowering emits | Accepted; refines 0034 and 0063 |
| [0115](0115-emission-reads-settled-semantic-answers.md) | Emission reads settled semantic answers | Accepted; extends 0048 |
| [0116](0116-external-mlir-tools-exchange-bytecode.md) | External MLIR tools exchange bytecode | Accepted; extends 0090 |
| [0117](0117-local-callable-selections-preserve-their-targets.md) | Local callable selections preserve their targets | Accepted; extends 0105 |
| [0118](0118-unobserved-array-initializers-are-omitted-during-lowering.md) | Unobserved array initializers are omitted during lowering | Accepted |
| [0119](0119-zeroed-allocation-facts-survive-opaque-calls.md) | Zeroed allocation facts survive opaque calls | Accepted |
| [0197](0197-a-checking-runtime-makes-a-use-of-freed-storage-abort.md) | A checking runtime makes a use of freed storage abort | Accepted |
| [0121](0121-typed-storage-is-private-and-checked.md) | Typed storage is private and checked | Accepted; extends 0076 and 0088; storage lifetime clauses superseded by 0123 |
| [0111](0111-import-paths-are-root-relative.md) | Import paths are root-relative | Accepted; supersedes ADR 0032's descending-path clause; reserved-root sentence superseded by 0171; extended by 0229 |
| [0133](0133-empty-typed-storage-needs-no-allocation.md) | Empty typed storage needs no allocation | Accepted; supersedes mandatory backing-buffer shape in 0123; extends 0098 |
| [0136](0136-callback-binders-are-local-to-the-implementation.md) | Callback implementations choose local binders while contextual interfaces retain labels | Accepted; supersedes conversion name equality in 0105; refines 0077; extended by 0159; conversion contract equality superseded by 0159; labels in callable identity superseded by 0177 |
| [0159](0159-a-converted-function-fits-its-carries-bound.md) | A converted function fits its `carries` bound | Accepted; extends 0136; supersedes conversion contract equality in 0136; extended by 0164 |
| [0164](0164-a-trait-implementation-adopts-its-traits-contract.md) | A trait implementation adopts its trait's contract | Accepted; extends 0132 and 0159 |
| [0210](0210-receiver-wins-contract-inference-is-not-adopted.md) | Receiver-wins borrow-contract inference is not adopted | Accepted |
| [0137](0137-arrays-expose-checked-borrowed-slices.md) | Arrays expose checked borrowed slices | Accepted; extends 0061 and 0123; extended by 0166 and 0172 |
| [0138](0138-hash-maps-preserve-entry-ownership.md) | Hash maps preserve complete entry ownership | Accepted; extends 0082, 0103 and 0113; extended by 0139 |
| [0139](0139-default-implementations-follow-ordinary-selection.md) | Default implementations follow ordinary selection | Accepted; supersedes 0093 for defaults; extends 0081 and 0138 |
| [0148](0148-parameter-heads-match-complete-trait-keys.md) | Parameter-headed implementations match complete trait keys | Accepted; supersedes head/partition clauses in 0081 and 0093; derived-cycle clause superseded by 0165; disjointness refined by 0192; extended by 0213 |
| [0149](0149-local-array-literals-infer-written-lengths.md) | Local array literals infer written lengths | Accepted; extends 0061 and 0083; extended by 0198 |
| [0198](0198-array-literal-bindings-infer-written-lengths.md) | Array literal bindings infer written lengths | Accepted; extends 0061, 0083 and 0149 |
| [0166](0166-an-array-compares-through-its-slice-view.md) | An array compares, hashes and prints through its slice view | Accepted; extends 0061 and 0137 |
| [0172](0172-an-array-reports-its-length.md) | An array reports its length | Accepted; extends 0061, 0083 and 0137 |
| [0192](0192-iterator-operations-belong-to-every-sequence.md) | Iterator operations belong to every sequence, and every iterator is a sequence | Accepted; builds on 0186 and 0187; refines 0148 and 0152; extended by 0203 |
| [0204](0204-mir-verification-re-derives-storage-safety.md) | MIR verification re-derives the storage safety ownership promised | Accepted; extends 0049 and 0050 |

## Open questions

Decisions deliberately not made yet — pipeline order of normalisation and
resolution, where ownership is represented, and the name of the post-semantic
representation. Each becomes a record here when its stage arrives, and each has **a question
that settles it**:

- Order of normalisation and resolution: does any planned desugaring require
  semantic information?
- Where ownership is represented: do ownership constructs conflict with what
  optimisation passes need from MIR?
- The name of the post-semantic representation: "Typed HIR" understates a
  representation that carries resolved names, inferred types, instantiated
  generics, ownership facts and monomorphisation state; "Semantic IR" is the
  working name.

Nine further questions have been identified but not yet scheduled.

How **incremental compilation** interacts with
[0012](0012-immutable-representations.md), which a rebuild-and-swap model
preserves and in-place patching does not.

What **identifies a declaration across two compilations**, which
[0009](0009-stable-ids-across-passes.md) does not answer: its IDs are positions,
and a position moves when anything is written above it.

Read-only observations and their allocator lifetime model are decided by
[0123](0123-observations-carry-owner-dependencies-through-callable-contracts.md).
Writable stored observations remain outside that decision.

What **records which implementation answered a settled reference at a call**,
which [0048](0048-one-question-has-one-answer.md) leaves with no answer to read.
`Self.Item` written inside an implementation is settled by that implementation
and is recorded against the token that wrote it, so one table says what it
means. Written in a trait's own *signature* it means whatever the call settled
`Self` to, which is a different type per call — so it is deliberately recorded
nowhere, because a table keyed by the token would hold the last call's answer
for a signature every implementation shares. The consequence is that the
signature half is checked by nothing: the conformance property
`settled_refs` compares a recorded settled reference against the text of the
implementation that settles it, and reports the signature half as passed over
on a line of its own. What would settle it is a record keyed by the *call*
rather than by the token, which is the same key `call_impls` already uses to say
which implementation a call reaches; whether one table should answer both, or
whether a settled reference's answer belongs beside the call's implementation
rather than beside it, is the question.

A reference read through a **bound** is recorded, and is checked as far as the
record goes. What the checker writes against the token there is the key the
instantiation will settle — the trait the bound named, the member, and the
parameter standing for the type — and the property derives that key a second
time from the source: which of the parameter's bounds names a trait declaring
the name. So reading a reference through the wrong bound is caught, and the
counts say how many were checked that way. What each instantiation settles the
key *to* is the half nothing records, which is the same question as above with
the same answer missing.

This no longer blocks generic iteration. A call whose key holds a type parameter
— `fn each[S: Sequence](read s: S)`, whose body calls an operation answering
`Self.Item` with `Self` still a parameter — stands for the key itself while the
body is checked once, and each instantiation settles it through the
implementation the argument names. What is open is what checks the answer, not
whether there is one.

Whether **a contract source may name a variant**, as `carries(.Err: self.Err)`.
`Result.settled` and `map_err` can only write `carries(.Err: self)`, so the
error side is taken to carry whatever the success side borrowed; recorded in
[0184](0184-a-failure-holding-an-owned-value-settles-to-its-reason.md#open-questions).

Whether **the entry wrapper should be a function the compiler builds rather than
text it prints.** The C entry point is written straight to the output after the
module has been emitted, so it is the one function in a program that the
emission verifier, the duplicate-symbol check and `dump-mir`
never see. It is nine lines and it is the same nine lines in every program,
which is why printing it was enough; the cost is that
[0049](0049-generated-code-is-verified-before-it-is-emitted.md) is now true of
everything the compiler emits except one function. What settles it is whether
the wrapper ever varies — a program with no `main`, which the test runner needs,
is the first thing that would make it.

How **one process serves requests concurrently**, and how ownership governs
what concurrent tasks share and send. `http.listen_and_serve` answers one
connection at a time ([0154](0154-sockets-and-http-follow-go.md)), so today
concurrency comes from processes: `http.serve_cgi` runs once per request under
a web server, or several server processes share the load. Threads, asynchronous
I/O and a pre-forked pool of worker processes are the candidates. A worker pool
needs no new rule, since processes share nothing; threads and asynchronous
tasks need one. What settles it is how ownership extends across tasks: whether
a value sent to another task must be owned and moved whole, never an
observation of the sender's storage; what tasks may share read-only; and
whether the state `http.with_state` lends to every request is shared under a
rule or partitioned per task.

Whether **a contract may be gated on a type**, so that `iter.extend` drops
its retention for an instantiation whose `Item` is `Owned`; recorded in
[0221](0221-owned-admits-a-type-that-can-carry-no-borrow.md#open-questions).

None of them is answered here. The third came close: a buffered writer, `slice`, and building text from
computed bytes appeared to reach it together, and on inspection only the last
one does. They are recorded so that whoever reaches them finds the questions
already asked rather than a record implying they were settled.
