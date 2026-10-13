# 21. Identifiers are interned, and a token carries the handle

Status: Accepted — 2026-07-26

Amends [ADR 0004](0004-soa-token-representation.md), which is otherwise
unchanged.

## Context

[ADR 0004](0004-soa-token-representation.md) settled that a token is
`{ tag, span }` and that **a derivable field is not stored**. The lexeme is
derivable — `source.text[span.start..span.end]` — so it is computed at the
point of use.

Name resolution compared those slices byte by byte. A lookup walked the visible
scope chain backwards calling `std.mem.eql` at each step, which costs the length
of the name times the depth of the scope, per reference. Every construct that
introduces names multiplies the number of such comparisons: functions add a
declaration table and call sites, and methods, fields and module paths each add
another.

The Stage 1 design deferred interning "until a resolver exists to consume
symbols". One has existed since Stage 2a.

## Decision

Identifier text is hash-consed into an `Interner`, which issues a
`StringId = enum(u32)`. A token carries the handle:

```zig
pub const Token = struct {
    tag: Tag,
    span: Span,
    name: StringId = .none,
};
```

Two identifiers spell the same name exactly when their handles are equal, so a
scope lookup compares integers. The cost of hashing is paid once per occurrence
at lexing, rather than once per comparison during resolution.

Only an identifier carries a handle. A reserved word is told from an identifier
by its tag, so interning one would put `let` in the table for nothing.

The interner is an argument to the pass, not state inside it, because handles
are comparable only within the interner that issued them and resolution across
files will compare names from different files. One interner per compilation
unit, owned where the arena is.

Text is borrowed from the source rather than copied. A source outlives the
compilation that reads it, and a second buffer would double the bytes to no
purpose.

## Why this does not contradict ADR 0004

ADR 0004's rule is that a derivable field is not stored. `name` is derivable in
exactly the sense `lexeme` is — but the derivation is not free. A lexeme is a
slice, produced by two additions; a handle requires hashing the bytes. Storing
the result of a free derivation buys nothing and costs memory; storing the
result of one that is not free is the entire point of a handle.

The layout argument in ADR 0004 also survives, because the representation is
structure-of-arrays. The parser's hottest loop reads `items(.tag)` and touches
neither the span column nor the name column, so a third column adds no cache
pressure to it. That is a property of the SoA decision rather than a
coincidence: it is what makes adding a column to serve one pass affordable.

## Consequences

The corpus is unchanged. Interning is invisible in every output the compiler
produces — tokens, trees, diagnostics, IR — so the conformance goldens are
byte-identical across this change, which is what shows no behaviour moved.

A diagnostic still reads a name's text from the token it underlines, which it
has to hand anyway, so no message needs the interner.

One comparison remains by text: the parser checks that the entry point is
spelled `main`. The parser has no interner, the check happens once per program,
and giving the parser one to save it would be the wrong trade.

## Alternatives considered

**Intern in the resolver instead of the lexer.** Tokens stay two columns and
ADR 0004 is untouched. Rejected: the hash is then paid per *lookup* rather than
per occurrence, which is most of the cost the change exists to remove, and the
parser and checker keep their own byte comparisons.

**Copy the text into the interner.** Rejected: the source outlives the
compilation, so the slice is already stable, and copying doubles the bytes held
for no gain.

**Leave it until it measures badly.** Rejected on cost of change rather than
cost of running: the number of sites that compare names grows with every
name-bearing construct, and the corpus can only prove the refactor
behaviour-preserving while it is done alone.
