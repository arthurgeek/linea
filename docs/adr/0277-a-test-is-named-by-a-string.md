# 277. A test is named by a string

Status: Accepted — 2026-11-16; supersedes the function-modifier premise of
0084 and the namespace clauses of 0247 and 0269

## Context

A test was a function carrying the `test` modifier: `test fn
withdrawal_deducts_amount_and_fee()`. Its name was an identifier, so it lived in
the module's one namespace beside every function, type and import. That one
fact produced a run of rules that exist only because a test was a named
function:

- A test and a top-level declaration of one name collided ([N-Duplicate]), and
  so did tests in two implementations of one module, or in a trait and the
  module around it (0247, 0269).
- A test named `main` needed a rule of its own: never the entry point, and in
  the root beside the program's `main` a second declaration of that name.
- An expression naming a test had to be refused ([S-Test]), because the
  compiler writes the only call to one.
- A test's parameter list was always `()`, and a test with parameters or type
  parameters had to be refused after it was parsed as a function's.

Meanwhile the name a reader wants to give a test is a sentence. Every test in the
library was a sentence spelled with underscores, `linea test` printed it that
way, and a reader typing it back as a filter had to retype the underscores.

## Decision

A test is written `test "what it checks" { … }`, and with a written result
`test "what it checks" -> Result[(), E] { … }`. `test trap "…" { … }` marks a
test that must stop the program. The string is the test's name; there is no
parameter list, and `test fn` is not a test.

- A test binds no name. Nothing in the language can write a reference to a
  string, so the rules about a test's name in the namespace are gone: a test
  may read like the function it tests, `main` included, and the refusal of an
  expression naming a test has nothing left to refuse.
- Two tests of one module may not share a name ([N-Duplicate]), wherever in the
  module each is written, since `linea test` reports and selects a test by it.
- The name is a string on one line that interpolates nothing, holds at least
  one character and no control character ([S-Test]): it is fixed where the test
  is written, printed on one line of the report and handed to the test binary as
  an argument.
- A test's reported name is its module's path and its string, each component
  writing `.` and `\` as `\.` and `\\`, so the name stays one spelling of one
  test. `linea test --filter TEXT` runs the tests whose reported names hold
  `TEXT`.
- `test fn name()` is refused under [S-Test] with a help writing the string, and
  a fix that puts it in place of `fn name()`.

Everything else [S-Test] says stands: where a test may sit, no visibility, no
`Self` or implementation parameters, `where` refused, and an omitted result
answering `Result[(), testing.Failure]`.

In the compiler a test stays a function declaration whose name token is the
string literal. The resolver gives it no binding: it collects each module's tests
by the string they decode to, refuses a second of one name, and records the
root's tests for the runner. A test's symbol spells the string as written, which
its closing quote ends, so it stays apart from every other symbol.

## Consequences

The rules removed are the test-named-`main` diagnostic, the refusal of an
expression naming a test, and the resolver's checks of a test's parameters, now
the parser's at the brackets or parentheses written after the name.

Every test in the repository was rewritten mechanically: underscores became
spaces, except inside an identifier the file declares as a function, which keeps
its underscores so a name like `"each_allocation_failure walks every attempt"`
still names the function it tests.

A reported name can hold spaces, so a shell user quotes it when passing it to
`--filter`. A dot in a test's name is written `\.` in the report, which a filter
matches as written.

## Alternatives considered

**Keep identifiers.** The namespace rules above would stay, each a rule about a
declaration nothing can name. And a name a reader writes as a sentence would go
on being spelled with underscores, in source and in every report. Rejected
because every rule it keeps exists only to manage a name nobody uses.

**Accept both forms.** Lets old code keep compiling. Rejected because the
language is unreleased and has nothing to stay compatible with, and two
spellings of one declaration would put the namespace rules back for one of
them: the formatter, the grammar, the language server and the runner would each
answer twice.

**A string beside an identifier, `test fn name() "description"`.** Keeps an
identifier for tools and adds prose for reports. Rejected because it names one
thing twice, and the identifier is the half the namespace rules exist for.
