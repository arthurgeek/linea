# 228. A granted module calls C

Status: Proposed — 2026-10-15. Would supersede the boolean `"extern": true`
grant of [0171](0171-the-standard-library-is-an-ordinary-library.md), the
integer-only clause of [T-Extern] and "Not an FFI" in
[0068](0068-a-declaration-may-name-a-symbol-the-runtime-provides.md), and
"general Float64 foreign calls remain unsupported" in
[0150](0150-float-math-crosses-a-checked-scalar-boundary.md).

## Context

[0013](0013-no-undefined-behaviour.md) says that calling C needs a record of its
own when it arrives. It has arrived: the first program that needs it reads and
writes a SQLite database through the system's or Nix's `libsqlite3`.

## Decision

**A manifest grants `extern` to named modules.** `"extern"` in `linea.json`
lists module paths (`["store"]`, `["."]` for the root module). Only a listed
module may declare an `extern`.
