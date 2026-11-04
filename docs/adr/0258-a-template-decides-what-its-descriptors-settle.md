# 258. A template decides what its descriptors settle

Status: Accepted - 2026-11-03

Extends [0113](0113-structural-derivation-is-library-defined-source.md).

## Context

A derived `Display` writes `Point { x: 1, y: 2 }`. The template that writes it
reads descriptors (`reflect.case.name`, `component.ordinal`,
`reflect.case.components_named`) whose values expansion knows, but expansion
wrote each one as a literal inside ordinary code: `if UInt64(0) == 0 { … }`
and `if true { … } else { … }`, with every piece of fixed text a separate
`write_str` call followed by its `?`. Every type deriving `Display` or `Debug`
carried both arms of each branch and one fallible call per piece into MLIR.
`examples/hello.lin`, which derives nothing itself, emitted 8,325 lines of MLIR,
most of it the derived formatting of the standard library's error types; the C
compiler's time grows with that module.

Writing each piece once needs the text before a component (`Point { x: `,
`, y: `) and after the last (` }`) as single literals. Descriptors that spell
those strings in the compiler would put `Display`'s syntax there, which 0113
forbids: standard traits receive no expansion privilege, and a user trait must
be able to do whatever `Display` does.

## Decision

Two forms in a template member are settled during expansion, for each case and
component, from the descriptors alone.

An interpolated literal whose every value is a descriptor written without a
format spec is the plain `Str` literal it spells. Each value is written as
`Display` writes it, and the text around the values is kept as written.

An `if` whose condition reads at least one descriptor and is built only from
`Bool` and `UInt64` descriptors, integer and `Bool` literals, `!`, `&&`, `||`,
comparisons and parentheses is decided during expansion. Only the selected
branch is written, as a block.

`reflect.case.component_count` joins the case descriptors, so a template can
tell a case with no components from one with some.

`std/fmt/traits.lin` spells the derived form with these, and expansion writes
`Writer.write_str(&w, "Point {{ x: ")?` for the first field of `Point`.

## Consequences

The format of derived `Display` and `Debug` lives in the library, and any
template gets the same single writes. `examples/hello.lin` emits 3,723 lines of
MLIR, `json_inventory` 36,238 and `http-json-echo` 158,905.

A branch expansion does not select is not part of that case's generated code,
so it is neither type-checked nor run there; a declaration only that branch
used is unused there and refused as any unused declaration is. A template
author sees an error in a branch only for a target that selects it.

Neither form changes what a program computes: the decided `if` selects the
branch the runtime one would have, and the folded literal holds the text the
interpolation would have rendered. The generated source still replaces the
derive exactly, as 0113 requires.

## Alternatives considered

**Descriptors that spell the derived text.** `component.text_before` and
`reflect.case.text_after` would give the same size, but spell `(`, `, `, ` { `
and ` }` in the compiler for one trait's output, which 0113 rejects.

**Fold `if true` and constant comparisons during lowering.** That would reach
every program, not only templates, but both branches would still be checked
and their moves merged by ownership, so a dead branch would still constrain the
live one; lowering would have to drop code ownership had already accounted for.

**Keep the branches and writes at run time.** The C compiler's work stays
proportional to every derived type's fixed text times its branches, which is
the cost this record removes.
