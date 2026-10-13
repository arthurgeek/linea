# Formatting

`linea fmt` rewrites source in canonical form. One source has one formatting,
and the compiler is the authority on what it is.

There is nothing to configure. There is one escape hatch.

## The command

```
linea fmt PATH...        rewrite in place; a directory is walked for .lin files
linea fmt --stdin        read one file from stdin, write the result to stdout
linea fmt --check PATH…  write nothing; report what would change
```

`--stdin` is what an editor uses for format-on-save. `--check` prints a unified
diff of every file that would change, and exits non-zero if any would — so it
works as a CI gate. Both honour `--color=auto|always|never` and
`--error-format=human|json`.

A bare `linea fmt` is an error rather than an implicit `.`: the shortest
possible command should not be a recursive rewrite of everything below the
working directory.

Exit codes are `0` when nothing would change and nothing was refused, `1`
otherwise, and `64` for a usage error.

### It formats what it can parse

`fmt` runs the lexer and the parser and stops. A file that does not typecheck
still formats — which is what makes format-on-save usable while a program is
being written.

A file that does not *parse* is refused, and reported. The parser recovers by
planting an error node, and an error node has no faithful printing; writing one
anyway would destroy source. Other files in the same invocation still format.

## How layout is decided

### The trailing comma

A delimited list — parameters, arguments, fields, variants, match arms, a
tuple's components — is laid out by whether it ends with a comma.

```linea
// no trailing comma: one line
enum Step { Half, Whole, Exactly(UInt8) }

// trailing comma: one element per line
struct Plan {
    remaining: UInt8,
    step: Step,
}
```

You choose which; the formatter does the rest. **Nothing is measured.** There is
no line-width limit, so a wide flat list stays flat until you add a comma, and
renaming something can never reshape code elsewhere.

A list you broke across lines but did not give a trailing comma is collapsed:

```linea
foo(
    a,
    b
)
// becomes
foo(a, b)
```

The comma is the marker, not the newline. A newline is invisible history; a
comma is a character anyone can see.

### A broken chain breaks at every link

A chain of selections you broke across lines -- at any `.` -- is written one
selection per line, each line indented once and opening with its `.`. The
first selection stays beside the name it selects from if you wrote it there,
so `fs.read_file(path)` stays whole. A chain written on one line stays on one
line. A blank line between two links stays, as one, as it does between the
arguments of a broken call.

```linea
// written
let total = scores.as_slice().map(|sink score| *score)
    .fold(0, |sink sum, sink score| sum + score)

// formatted
let total = scores.as_slice()
    .map(|sink score| *score)
    .fold(0, |sink sum, sink score| sum + score)
```

A line opening with `.` and a lowercase name continues the line above, so the
leading dot is the language's own reading of the chain, not a layout the
parser has to be told about.

### Blocks always break

A `{ … }` holding statements is always multi-line, one statement per line. Only
an empty block stays flat, which is what lets a match arm do nothing on one
line.

```linea
// written
if c { 1 } else { 2 }

// formatted
if c {
    1
} else {
    2
}
```

An empty brace group stays on one line wherever it is written — a structure with
no fields, a trait that promises something and declares nothing, an
implementation of such a trait:

```linea
struct Empty {}
trait Equivalent: Equatable {}
impl Equivalent for Mark {}
```

A brace opening a line of its own says something follows it. A comment written
inside is something, so a group holding one breaks around it.

### When a list cannot be flat

The comma decides only among layouts that are possible. Two things cannot share
a line: a `//` comment, which runs to end of line, and a non-empty block. Either
one forces its list to break, whatever the commas say.

When a list breaks for that reason, the trailing comma is written for you, so
running `fmt` again reads an ordinary broken list and changes nothing:

```linea
// written
enum Step { Half, // the cheap one
            Whole }

// formatted
enum Step {
    Half, // the cheap one
    Whole,
}
```

### Blank lines and comments

A run of two or more blank lines becomes one. A blank line straight after `{` or
straight before `}` is dropped. Every other blank line stays where you put it —
grouping statements is the one place vertical space carries meaning no rule
could reconstruct.

Top-level declarations are separated by a blank line, with one exception: a run
of imports sits together, and so does a run of re-exports. Each is one line and
each reads as an entry in a list, and a list is one piece of structure rather
than several — spacing one out makes the head of a file mostly empty.

```linea
import alpha
import beta

pub use alpha.Thing
pub use beta.Other
```

Of its own kind, so the blank line between the two runs stays: what a module
imports and what it publishes are two lists. An entry you wrote a comment above
takes the blank line too — the comment describes the declaration below it, and
run against the entry above it would read as describing that one.

A comment beginning on the same line as the code before it stays on that line.
Every other comment takes a line of its own, indented to the code around it. The
column you wrote it at is not preserved: a comment describes the code beside it,
and that code has moved.

### Multi-line literals

Every `\\` line of a multi-line literal is kept, byte for byte after its `\\`,
trailing spaces included. Only the indentation before `\\` changes. A literal
that opens its line, as a statement does, keeps that line's depth. Otherwise
its lines move one level deeper than the line holding what comes before the
literal, so the block reads as one unit however it was indented. A comment
between the `=` and the literal does not change that depth; the comment itself
keeps the statement's depth, as a comment before any expression does.

```linea
let header =
    \\name   | total
    \\-------+------
let greeting = \\Dear reader,
    \\thank you.
```

The first line stays where you wrote it, beside the `=` or on a line of its
own. It cannot always move, because after `return` a line break ends the
statement. Whatever follows the literal — a call's `)`, the next argument's `,`,
a struct literal's `}` — starts the next line at the depth of the line the list
opened on, since the last line of text runs to the end of its line.

A match arm whose body is a multi-line literal is written as a block, so that
the comma separating it from the next arm follows the block's `}`:

```linea
match kind {
    Short => {
        \\brief
    },
    Long => {
        \\at
        \\length
    },
}
```

### What it never does

- **It does not measure anything.** No width, no reflow.
- **It does not reorder anything**, imports included. Order that cannot affect
  meaning carries only intent.
- **It does not rewrite a token.** Literal casing, leading zeros, and the bytes
  between a string's quotes or after a `\\` are yours. `007` stays `007`.
- **It does not drop a word you wrote.** `read` is a parameter's default, so
  removing it would still compile — which is exactly why removing it would be
  the wrong kind of change.
- **It does not remove parentheses**, even redundant ones.

Two tokens do move, and both because the language leaves no choice. A trailing
comma is written into a list that breaks, as above. A semicolon written before a
closing brace is dropped: the parser accepts it without recording it, so `{ e; }`
and `{ e }` are the same program and there is nothing to write back.

## Fixed, and not configurable

Four spaces per level. LF endings. Exactly one newline at the end of a file. No
trailing whitespace on any line. Indentation is spaces, never tabs.

## The escape hatch

Some things a formatter cannot improve — a hand-aligned table, a match whose
arrows you lined up on purpose. Wrap them:

```linea
// linea fmt: off
match read s {
    Half       => 5,
    Whole      => 10,
    Exactly(n) => copy(n),
}
// linea fmt: on
```

Everything between the markers is copied byte for byte, including the marker
lines.

The markers must sit on lines of their own, at a place a statement could begin.
Anywhere else — trailing code, inside a list — the words are an ordinary
comment and formatting carries on around them.

An `off` with no matching `on` runs to the end of the file, which is how a file
laid out entirely by hand opts out. A stray `on` is just a comment. Neither is
an error, so the hatch adds no diagnostic to the language.

**Regions do not nest.** A region ends at the first `on`, and an `off` written
inside one is text like everything else there — it does not open a second
region needing a second `on` to close. There is nothing to forbid, because
there is nothing to nest.

## Why you can trust it

Every file the compiler parses is checked, on every test run, against five
properties:

1. The output parses.
2. Its tokens are the input's, save the two the language leaves no choice about.
3. Formatting it again changes nothing.
4. No comment is dropped, duplicated or reworded.
5. Formatting reaches the same bytes however the input was spaced.

The fifth is the strongest, and it is the reason the others are worth stating.
Formatting is checked as a *normal form*, not merely as something that settles:
a formatter that preserved your indentation width would settle immediately and
still be wrong.

Separately, the test suite mangles each program's whitespace, formats it, then
compiles and runs it — so formatting is also known not to change what a program
computes.

The tree formats itself. `tests/` and `examples/` are held to it by the suite,
and the only files exempt are the handful whose exact bytes are what they exist
to test.

## Files that record their own formatting

A file with a `.fmt` golden beside it is the input half of a case recording what
formatting does to it — written badly on purpose. `fmt` skips such a file, by
the walk and when named directly, because formatting it would destroy the
record. The test suite exempts the same files from the check that every other
file is already formatted; this is that rule, applied by the command.

## Limits

Expression nesting is bounded by stack, somewhere above ten thousand levels.
The bound belongs to the frontend rather than to the formatter: the parser and
the printer both recurse, and the parser reaches it first, so the formatter is
never handed a tree it cannot print. No program written by a person comes near
this; a generator might.

## Editors

Point your editor's formatter at `linea fmt --stdin`. For Helix:

```toml
[[language]]
name = "linea"
auto-format = true
formatter = { command = "linea", args = ["fmt", "--stdin"] }
```

The binary must be on `PATH`; this repository's dev shell puts its own build
output there. Keeping that build current is yours to do — format-on-save uses
whatever was last built.
