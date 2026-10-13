# 220. A route pattern matches its own path

Status: Accepted — 2026-10-13. Supersedes the subtree clause of
[0154](0154-sockets-and-http-follow-go.md).

## Context

0154 followed Go's `ServeMux`: a pattern ending in `/` was a subtree and
matched every path beneath it, after every more specific pattern. The root
pattern `/` was therefore a catch-all. A program registering `GET /` for its
home page and `POST /reply` for a form answered `GET /nowhere/deep` with the
home page and `DELETE /nowhere/deep` with 405 naming `GET` and `HEAD`, so a
mistyped link never answered 404. The pattern language had no way to name the
root alone; Go added `/{$}` for that.

The same rule duplicated `{name...}`. A remainder already matches the rest of
the path, an empty rest included, so `/static/{file...}` matches everything
`/static/` did, and it names what it matched.

## Decision

**A pattern matches its own path and no other.** A path ending in `/` ends in
an empty segment, as the path of a request does: `/` is one empty segment and
matches only the root, and `/static/` is `static` and an empty segment and
matches only `/static/`. A pattern answers every path beneath one by ending in
`{name...}`. The precedence at the first differing segment is a literal, then
`{name}`, then `{name...}`; there is no fourth kind.

The router holds the empty segment as a literal child of the trie, so a
pattern ending in `/` is registered and found by the code that handles every
other literal, and a trie node holds one table of handlers.

## Consequences

- A request no pattern names answers 404 even when `/` is registered.
- A program that served a directory with `GET /static/` writes
  `GET /static/{file...}` and reads `file`.
- Duplicate detection is unchanged: `/a/` twice is `Duplicate`, and `/a/` and
  `/a` are two shapes.

## Alternatives considered

- **Keep subtrees and add an exact-root form**, as Go's `/{$}`. Rejected: it
  keeps two spellings for "everything beneath" and makes the plain spelling of
  the root the surprising one.
- **Make only `/` exact and keep other subtrees.** Rejected: the rule would
  depend on which path a pattern names, and `{name...}` already covers every
  subtree.
