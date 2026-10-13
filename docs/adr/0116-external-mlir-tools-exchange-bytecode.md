# 116. External MLIR tools exchange bytecode

Status: Accepted — 2026-09-08; extends 0090

## Context

Linea emits textual MLIR, which conformance checks and people inspect. The
external conversion tool then serializes another MLIR module solely for the
external translator to parse. The tools belong to the same pinned toolchain.

An identical-input paired experiment measured conversion plus translation at
82.190→72.879 ms for hello and 79.160→70.815 ms for knight when that intermediate
used MLIR bytecode. Both exceed the measured dispersion threshold. The smaller
kernel observation did not. Translated LLVM IR is identical apart from its
input-filename comment. The intermediate files shrink by approximately 76–78%
for hello and knight, retaining commands, input identities, samples, and the
negative small-input result.

## Decision

`mlir-opt` writes its converted output with `--emit-bytecode`; `mlir-translate`
reads it directly. Linea's emitted MLIR and translated LLVM IR remain textual.
The intermediate remains a real file, including when a failed build keeps its
artifacts. No tool process, verification boundary, or conversion pass is removed.

## Consequences

The tools avoid text serialization and reparsing between conversion and
translation. Inspecting the converted intermediate requires decoding it with
`mlir-opt`. Its format is private to the pinned tools, not a persisted compiler
interface or a format Linea implements.

ADR 0090's rejection of a handwritten bytecode emitter still applies: Linea
neither implements versioned encodings nor replaces its textual goldens, and it
does not link MLIR into the compiler. The MLIR tool writes its own format.

## Alternatives considered

Keeping text between tools preserves direct readability of that intermediate,
but retains the measured serialization cost. Piping text changes storage without
removing parsing or formatting. Combining tools through a linked MLIR library
would change the compiler boundary and packaging; the measured improvement does
not require it.
