# 273. One generator reaches every rule and limit, and many oracles judge its programs

Status: Accepted — 2026-11-15; extends 0027, 0029 and 0057. The generator's
hostile shapes, the limit table, the work bound, the position rewrite and
the rule floor are built. The other oracles under *Order* are the direction
this record sets, and each is built by the change that lands it.

## Context

An audit of the compiler found about seventy defects, and most of them fall
into seven classes:

1. **Work that follows a type's spelling instead of its declarations.** A
   generic alias that names the one before it twice,
   `alias A1[T] = P[A0[T], A0[T]]`, spells a billion names at thirty levels
   and adds thirty entries to the type pool. Symbol spelling, type display,
   settlement and derive checks each walked the names.
2. **One type, two answers by position.** A chain of 1001 aliases is refused
   under [T-AnswerDepth] in `let r: A0 = 3` and accepted in
   `impl From[A0] for T` and in `@derive(From[A0])`.
3. **One mistake reported more than once**, or reported and then followed by
   an error that exists only because of the first.
4. **The parser, the formatter and the tree-sitter grammar disagreeing** on
   forms that are rarely written.
5. **The language server's state after a sequence of edits** differing from
   what `linea check` says of the same buffers.
6. **A program answering differently across optimisation levels**, in the
   backend or at the C entry point.
7. **An allocation failure leaving state half built.**

What already exists finds none of them. The generator of
[0027](0027-generated-programs-are-well-typed-by-construction.md) writes small
programs that are well typed by construction, so every one is far from every
limit, shares no type graph, and reaches a rule only through the mutations of
[0057](0057-a-mutation-answers-for-the-rules-it-declares.md), which name
sixteen of the hundred and fifty-one rules the compiler can emit. The sweep
dimensions grow one hand-written shape each, and a shape nobody thought of has
no dimension. The corpus floor of
[0029](0029-a-suite-must-be-able-to-fail-for-what-it-omits.md) says every rule
is provoked by some case, and a case is one program in one position.

Each class is a property of *every* program, which is why a case does not find
it: class 2 is not about alias chains, it is about a written type meaning the
same wherever it is written. A property needs programs to be asked of, and the
programs that expose these properties are the ones nobody writes by hand.

## Decision

**There is one program generator, and its programs are judged by many
oracles.** The generator is responsible for reach: which programs exist. An
oracle is responsible for one property that every generated program must
have. Neither knows the other's work, so a new shape is judged by every oracle
and a new oracle judges every shape.

### What the generator reaches

The generator is `src/conformance/generate.zig` and the files beside it, and a
seed selects everything about a program. It reaches four things.

**Every syntax form.** The well-typed programs of 0027, held by the coverage
floors that already fail when a production is never generated.

**Every named rule.** Each part of the generator that writes a refused program
states the rule that must refuse it, and is held to that rule where it runs. A
floor (`src/conformance/reach.zig`) compares those statements with the rules
the compiler can emit, as the test beside `Code` compares the same enum with
the semantics document: a rule is stated by some part, or it is on
`not_yet_generated` with the reason nothing reaches it. A statement counts
only where a check is compared against it: a shape whose recorded finding no
longer includes a report under the rule it states does not reach that rule.
The list is exact. A rule on it that a part now reaches fails, as a guide
marker that is no longer needed fails, so the list shrinks whenever reach
grows and cannot be stale.

**Hostile shapes** (`src/conformance/hostile.zig`):

- shared type graphs: a doubling generic alias chain of seeded depth, used
  once;
- each limit, at exactly the limit and one past it;
- and, as later parts, very wide and very deep declarations.

**Near-valid programs with exactly one planted mistake.** The mutations of
0057 are this for well-typed programs. A hostile shape carries one too: a
`UInt8` given where a doubling chain's type is wanted, at depths shallow
enough that the report is all the check is held to and at depths where the
type's name is the cost.

Every generated program states what the compiler must say of it: accepted, or
refused with so many reports under one rule and none under another. The runner
holds the compiler to the statement. This is the change to 0027, whose
generator could only state "accepted".

A limit on a written type is written in a seeded position: a `let`
annotation, a function parameter, a struct field, an enum payload, the trait
argument of an `impl`, a derive argument, or the head of an `impl`. A type is
the same type wherever it is written, so a chain of declared answers, a tuple
or an array that is refused in one position is refused in each. Two limits
count something a position adds to, and the generator writes that down
instead of fitting the compiler. [S-Nesting] counts depth from the type's
place in the tree, and a trait's argument stands one level below the written
type that names the trait, so the nesting limit is reached one level sooner
there. An enum is its payload behind a tag word, rounded up to a word, so the
widest payload within [L-Size] is fifteen bytes short of the limit and the
payload one byte wider is the one past it. A limit on an expression, the `#`
of a raw literal, the depth of interpolation and a format's width, is written
as the initialiser of a `let`.

### Limits come from one table the compiler reads

`src/support/limits.zig` lists the counts the language bounds: each limit
that a rule states as a number and that a diagnostic under the rule enforces.
There are ten: tree height, tuple components (with the fewest a tuple
has), the links of a chain of declared answers, the cells of a coverage check, the
length of an array, the bytes of a type, the `#` that open a raw literal, the
interpolations open at once, a format's width or precision, and the bytes of
an embedded file. The pass that enforces a limit reads it from the table, and
a diagnostic that writes the number as a numeral formats it from the table.

Two bounds the compiler holds are not in it, because neither is a rule of
the language: the largest source a position can address
(`source.max_bytes`), which is reported with no rule name, and the ranges of
the numeric types, which are values and not counts of what a program writes.

The compiler and the generator read one table, so a wrong number in it would
be accepted by both. The semantics document is the third statement of each
limit, and a test writes the sentence that states each one from the table's
number and fails when the document does not hold it. Stating the
interpolation limit there was part of this change; the document had not.

The generator switches over the table exhaustively. A limit added to it does
not compile into the generator until it is given a shape, written at N and at
N+1, or a reason no shape reaches it. Two have a reason today: the cells of a
coverage check, which no part writes a `match` wide enough for, and the bytes
of an embedded file, which is a second file.

### The oracles

Each is a property of every generated program, checked without a recorded
answer.

**(a) Work bound.** The check of a program adds allocation work that grows no
faster than linearly in what the program writes. Work is the sum of the
sizes a check asks its allocator for, counted above a fresh arena with growth
in place refused; no clock is read. Three programs are checked: the shape,
the same shape at half its size, and the shape's position with a plain
`UInt8` in it. The plain program's work is everything the library and the
position cost, so the differences are what the hostile thing adds. The shape
may add three times what its half adds, where linear work adds twice and
quadratic work four times, and above that an allowance of one sixty-fourth of
the plain program's work.

The allowance is what the count's own error needs. A check appends to tables
that already hold the library, a table that grows is charged its whole new
size, and which of the three programs crosses a capacity is an accident. The
error is a few tenths of a percent of the plain work and grows with the
library, so the allowance is a share of the plain work and not a number of
bytes. It sets what the bound can see: added work under it is not held to the
ratio. Measured with a cost planted in the compiler, a pass that spells out a
doubling chain's name is fifty-nine times its bound at depth twenty, the
shallowest generated; a pass that allocates thirty-two bytes for each
enclosing level at each level of a type nested a thousand deep, sixteen
megabytes, is over its bound, and one that allocates four bytes, two
megabytes, is not. A check that passes its bound runs on, so its reports are still
compared, and is stopped a gibibyte later.

The count is the same for two checks of one program in one build. It is not
claimed to be the same number across builds or targets, and nothing compares
it against a recorded number.

**(b) Rewrite invariance.** The rewrites of 0026 and 0134 hold a program to
the same answer under changes that cannot alter its meaning. Moving a written
type between positions is one of them. For a hostile shape the generator
writes the type in each position and states one expectation. For every other
program a rewrite moves a binding's annotation to the parameter and result of
a function the initialiser passes through; the rewritten program must be
accepted, build, and answer alike. It applies to a binding that is not a
constant, a `var` or a `let` whose initialiser no constant expression has the
form of, because a call is not a constant expression and a constant may be
read as an array length, a pattern's bound or a default.

**(c) One mistake, one report, and its fixes apply.** A program with one
planted mistake earns exactly the reports its statement counts, all under its
rule. A consequence reported after the mistake, or the mistake reported again
from a second pass, fails. Each fix the report carries is applied and checked
as the corpus holds a rejected case to its helps.

**(d) Formatter and grammar agreement.** A generated program formats to a
fixed point that parses to the same tree, and the tree-sitter grammar accepts
what the parser accepts and marks an error where the parser reports one.

**(e) Language server against `linea check`.** A seeded sequence of edits is
applied to open buffers through the server, and after each edit the
diagnostics the server publishes equal what `linea check` says of the same
text.

**(f) Optimisation levels.** A program that builds answers with the same exit
status and output at every optimisation level.

**(g) Allocation failure.** Each allocation of a check is refused in turn. The
check fails with `error.OutOfMemory` and nothing else, never with a different
verdict, and checking again with the allocation allowed gives the answer an
undisturbed check gives.

### Known findings

An oracle that finds a defect in the compiler does not wait for the fix and is
not weakened to pass. `hostile.known_findings` records each defect with a seed
that shows it, every report the compiler makes of the programs it covers, in
order, whether their check is over its bound, and what the language requires
instead. A program a finding covers must be answered exactly as recorded: one
more report, or one under another rule, fails as it does for a program with no
finding. When the program is answered as it states, the finding fails as no
longer reproducing and its entry is removed with the fix. The walk is green
while a recorded defect stands, and red for a new defect, a recorded one that
changed, and a recorded one that was fixed.

### What this does not cover

**Standard-library and runtime logic.** A `Map`, a parser in `std`, the
runtime's scheduler and its simulator are programs with their own state
spaces. The oracle for one is a model of that module, which is a test written
per module, as the storage generator's model is. A generator of compiler
inputs reaches the library only as far as a program calls it.

**Structural findings.** A responsibility computed in two places, a table
sized by the program and held per function, a dead path: these are properties
of the compiler's source, not of any program's behaviour, until some input
makes the two places disagree. They are found by review and by the build
gates. The work bound finds the second kind only once a generated shape is
large enough to show it.

**Pure computation with no allocation.** The bound counts allocation. A loop
that is exponential in time and allocates nothing passes it; the sweep's
timed dimensions and the per-case timeout remain the checks for that.

**Superlinear work under the allowance.** A quadratic pass whose cost at a
limit is under a sixty-fourth of the plain program's work passes the bound.
The sweep's dimensions, which grow a shape until its slope shows, remain the
check for a small constant.

### Order

Each line is its own change, with the generator parts it needs.

1. Built with this record: the limit table and its tie to the semantics
   document; hostile shapes for shared type graphs and for every limit one
   file reaches by a written type or an expression; the statement each
   generated program makes; oracle (a); the position rewrite of oracle (b);
   the rule floor and its list; the findings list. The report half of oracle
   (c) is held for hostile shapes, because a statement that counts reports is
   what "refused under one rule" means.
2. Oracle (c) for every refused program, with fixes applied, and generator
   parts that plant one mistake per rule family, which is what shortens
   `not_yet_generated`.
3. Oracle (g), which needs only the counting allocator, to which this record
   adds a point past which it refuses.
4. Oracle (d), over generated programs and the rarely written forms the
   coverage floors name.
5. Oracle (f), in the soundness step, where programs are already built.
6. Oracle (e), which needs a generator of edit sequences and is the largest.

## Consequences

The generator found defects on the day it ran, and they are recorded in
`known_findings` and not fixed here: a chain of 1001 aliases accepted in an
`impl`'s trait argument, in a derive argument and inside an `impl`'s head; a
type nested past the limit reported and then reported again as a consequence;
a nine-component tuple and an over-long array written twice, in a derive and
its payload, and reported three times; a raw literal opened with nine `#` and
a literal that interpolates seventeen deep each followed by reports of the
code around them; and a mismatch against a doubling chain whose work doubles
with each alias.

`not_yet_generated` holds 127 of the 151 rules. That is the measure of how
little of the language's refusals a generated program reaches, written where a
build fails if it is wrong. It is a list of work, grouped by what reaching
each group takes.

Every seed now checks the well-typed program and a hostile one. A hostile
program is checked, not built or run, and its bound takes two more checks, so
the walk grows by three checks per seed.

The bound is relative on both sides, a ratio against the half size and an
allowance against the plain program, so it holds no number that was right
for one library. The cost is sensitivity: it sees work that is a visible
share of a check, not a small superlinear term.

The eight positions are written by hand. A position the language adds is not
generated until it is added to `Position`.

A limit's count is a number in the table, and the words of a diagnostic that
spell it ("two to eight components") are still written in the message.

## Alternatives considered

**Separate single-purpose fuzzers, one per defect class.** Each would be
small and could be tuned to its class. Rejected because reach is the
expensive half and they would not share it: an alias-chain fuzzer, a
formatter fuzzer and a language-server fuzzer each need programs with deep
types, wide declarations and rare forms, and each would grow its own
generator that knows a different subset of the language. A shape added to one
would be judged by one property. The defects found here show the cost
directly: the chain past the limit and the mismatch against a doubling chain
came from the same few shapes judged by two oracles.

**Coverage-guided fuzzing of source bytes as the main tool**
(`std.testing.fuzz` over raw text). It needs no generator and finds crashes in
the lexer and the parser's recovery, which is why the `fuzz:` tests keep it
for those. Rejected as the main tool for three reasons. Almost every byte
string is refused by the parser, so the checker, ownership and the backend
see almost none of the inputs. A byte string carries no statement of what the
compiler must answer, so the only oracle is "did not crash", and none of the
seven classes is a crash. And coverage does not reward the shapes that
matter: an alias chain at 1000 links and one at 1001 execute the same code,
and a doubling chain at depth thirty covers nothing depth three did not.

**Rely on the hand-written sweep dimensions and the corpus.** Both are
precise and both stay. Rejected as sufficient because each is a list of
shapes someone thought of, in the one position they wrote it in. Class 2
existed beside a corpus case for the chain of 1001 aliases, which is written
in a `let`. A sweep dimension grows one shape and reads its slope; it says
nothing about a shape with no dimension, and nothing fails when a limit is
added and no dimension reaches it.

**A filter in place of statements: generate freely and keep what the compiler
accepts.** Rejected for the reason 0027 gives, and for one more: a program
kept because the compiler accepted it cannot show that the compiler wrongly
accepted it. Every class-2 defect is a wrong acceptance.

**Fix each finding in the change that finds it.** Rejected because it couples
the generator's review to the compiler's. A findings list lets an oracle land
with the defects it found visible and held, and makes the fix a change whose
proof is an entry removed.
