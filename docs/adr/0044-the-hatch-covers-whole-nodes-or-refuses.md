# 44. The hatch covers whole nodes, or the formatter refuses

Status: Accepted — 2026-07-28

Supersedes the walk rule stated in
[0038](0038-the-formatter-has-an-escape-hatch-and-no-configuration.md). The
escape hatch, its markers, and the absence of configuration are unchanged; what
the walk must do about a region is not.

## Context

0038 says:

> The walk must step over any node beginning inside one, or it copies the
> region and then formats its contents again after it.

That sentence is the defect. A region is a range of **bytes**, delimited by
whole lines. A syntax tree is a hierarchy of **nodes**. A byte range cuts nodes
at every depth, and "begins inside" describes only one of the ways it can cut
one.

The implementation was faithful to the sentence: `alreadyCopied` asked whether a
node's *start* token fell in the copied range. Three consequences, each found by
a separate adversarial review, each fixed without the rule being restated:

- A node beginning **before** the region and ending inside it is not stepped
  over, so its tail is written twice.
- A node beginning **inside** the region and ending **after** it is stepped over
  *whole*, so everything past the copy — an `impl` member's body, a match arm's
  contents, a function's closing brace — is deleted.
- A node **containing** the region is written in full, including the tokens the
  region already copied.

A sweep of 3130 hatch placements measured the cost: 81% of them formatted
incorrectly before this branch, 19% after the first two rounds of fixes. Of the
failures, a quarter deleted source outright. `fmt` rewrites a file in place, so
every one was work destroyed silently, and destroyed further on each save.

## Decision

**A region is extended until it covers whole nodes, and where it cannot be,
`fmt` refuses to write.**

Two parts, and the second is what makes the first safe to get wrong.

**Extension.** A node that begins inside a region and ends after it is covered
by extending the region to that node's end, to a fixpoint, across declarations,
statements and expressions alike. A node that *contains* the region is left
alone: the region sits within it and ends where it says it does, which is what
stops a marker inside an enum's payload swallowing the enum.

**Refusal.** Before writing *or printing*, the formatter asks whether the
output parses, whether it is the same tree, and whether it is the same tokens,
and refuses when any fails.

The tree is the one that matters and the one that is easy to get wrong. Since
[0041](0041-a-newline-ends-a-statement.md) a newline ends a statement, so the
same tokens in the same order can be a different program — `a` then `-b` is two
statements and `a - b` is one, with identical token text. A guard comparing
only tokens is blind to every reflow that moves one across a statement
boundary.

The check lives in the one function both routes go through. There are two — a
path on the command line, and a buffer on stdin — and stdin is the one an
editor pipes a live buffer through, so a guard at a call site rather than in
the shared function leaves the route where "in place" means someone's open
file.

The escape hatch is line-based and the walk is syntax-directed. A region that
cuts *through* an expression cannot be reconciled with a syntax-directed walk at
all, so the honest answer there is a refusal rather than a rule.

## Consequences

**`fmt` cannot damage a file, by either route.** Across 412 valid sources with
a region at every position: 345 format, 67 are refused, none are damaged.
Refusing is a diagnostic and a non-zero exit, which is recoverable; writing is
not. A review measured the stdin route separately before it was guarded: of
6975 placements, 363 produced source the compiler then rejected and one
produced a different working program, all at exit 0.

**The refusal is where the remaining defect lives.** 51 of 412 is not a
finished walk. It is a bounded, visible, non-destructive amount of unfinished —
which is the difference this record is really about.

**An extension that reaches past a closing marker is reported.** The author
wrote `on`, it did not take effect, and the rest of the declaration stays
unformatted; the output is correct, so this is a remark on stderr rather than a
refusal. Leaving it silent would mean a declaration freezes with nothing to say
why — which is how someone concludes the hatch is broken rather than that their
marker landed inside a node.

**A cost per file.** One extra parse and one token comparison. `fmt --check`
already parses twice; the write path now does too. Measured in the noise beside
the walk itself.

**The properties are asked twice**, by the suite and by the driver. That is
deliberate duplication of the *call*, not of the rule: the comparison behind
both is one function. The suite asks of the corpus; the driver asks of the file
in front of it, which is the only place the answer is expensive to get wrong.

## Alternatives considered

**Snapping the region's start backwards as well as its end forwards.** It would
make every node either wholly inside or wholly outside a region, which is the
complete fix. Rejected for now because the region's start is discovered mid-walk,
when the text before it has already been written — moving it backwards means
retracting output. Reachable if the printer ever buffers a declaration before
emitting it.

**Making an unbalanced or node-cutting marker a diagnostic.** 0038 deliberately
made a stray marker not an error, on the grounds that the hatch must not need a
rule of its own to use. Refusing to *write* preserves that: the marker is still
not an error, and the file is still not damaged.

**Leaving the walk and relying only on the refusal.** Tempting, since the
refusal is what makes the tool safe. Rejected because a hatch that refuses in a
fifth of its uses is not a usable hatch — the extension is what makes the
refusal rare enough to be a bug report rather than a workflow.
