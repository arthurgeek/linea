# 38. The formatter has an escape hatch and no configuration

Status: Accepted — 2026-07-27. The walk rule stated below is superseded by
[0044](0044-the-hatch-covers-whole-nodes-or-refuses.md): a region cuts nodes at
every depth, and \"beginning inside\" describes only one of the ways.

Builds on [0036](0036-formatting-is-comma-driven.md), which decided that layout
follows the trailing comma and nothing is measured.

## Context

A formatter's value is that it ends an argument. Every option it offers is a
piece of that value handed back: two projects with different settings no longer
agree on what Linea looks like, and the settings themselves become the argument.

The pressure to add options is nevertheless real, and it arrives in a
predictable way. Some construct formats badly — a hand-aligned table, a wide
`match` on small literals whose `=>` the author lined up — and the request is
not "please add options", it is "please stop destroying this one thing". A
formatter with no answer to that gets an option, then a second, and the second
is always easier to justify than the first.

So the two questions are one question. What makes zero configuration tenable is
having somewhere for the genuinely exceptional case to go.

## Decision

**The formatter has no configuration.** No file, no flags affecting output.
Four spaces, LF, one trailing newline, no trailing whitespace, and the layout
rules of 0036.

**It has one escape hatch**: `// linea fmt: off` and `// linea fmt: on`, written
as comments on lines of their own. Everything between them, inclusive of the
marker lines, is copied byte for byte.

**A marker is a marker only on a line of its own.** Anywhere else — trailing
code, inside a delimited list — the words are an ordinary comment and formatting
proceeds around them. Whether a marker owns its line is asked of the source text
before it, not of the gap to the previous token, so a marker on a file's first
line works where there is no previous token at all.

**An unclosed `off` runs to end of file, and a stray `on` is an ordinary
comment.** Neither is an error.

## Consequences

The hatch introduces **no diagnostic and no rule name**. Nothing about it can
fail, so `docs/linea-semantics.md` gains nothing and the semantics index stays a
list of rules a diagnostic can cite.

Whole-file opt-out — a real thing to want for a file laid out by hand — falls
out of the unclosed case rather than needing syntax of its own.

Restricting markers to their own line is what makes "copy it unchanged" well
defined: the verbatim span is always a whole number of lines. It also keeps a
marker out of a delimited list, where it would collide with the rule that a
comment forces a list to break.

Everything downstream has to route around a region. The walk must step over any
node beginning inside one, or it copies the region and then formats its contents
again after it. The perturbation that checks the normal form must leave regions
alone, or it mangles text the formatter then copies verbatim and the equality
fails on the first file that uses the feature.

The text inside a region is unvalidated. It is whatever the author wrote, and
the formatter has no opinion about it beyond it having parsed.

A region is a place bad layout can hide indefinitely. That is the trade: the
alternative is bad layout with nowhere to go, which becomes a request for an
option.

## Alternatives considered

**A configurable indent width.** The one style preference with a substantive
argument behind it — tabs are adjustable by readers who need larger text.
Rejected because the second option is always easier to add than the first, and
because the accessibility case is better served by an editor rendering tabs than
by a formatter emitting them into shared source. It stays reopenable on that
evidence rather than on preference.

**No hatch at all.** Purest, and every property holds with no carve-out.
Rejected because it leaves the first genuinely unformattable construct with
nowhere to go, and that is exactly where the pressure for options comes from.
The hatch is what makes "no options" a position that can be held.

**Diagnosing an unclosed `off`.** It would catch a marker left behind after a
deletion, which otherwise silently freezes the rest of a file. Rejected because
it costs a rule name in the semantics document for a formatter that otherwise
emits none, and because it forecloses whole-file opt-out unless that gets syntax
of its own.

**A single-item `// linea fmt: skip`.** Avoids two lines of ceremony for one
declaration and can never be left unbalanced. Rejected as a second mechanism
with a second set of interactions to test, which regions already subsume. It is
recorded as reopenable if the corpus accumulates one-line `off`/`on` pairs.
