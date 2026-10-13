# 85. The library is imported, and the prelude is what the syntax obliges

Status: Accepted — 2026-08-17. The reserved-path-root clause is superseded by [0171](0171-the-standard-library-is-an-ordinary-library.md): `std` names the dependency whose manifest names it. The clauses that a name is in the prelude only when the syntax obliges it, and that a prelude name shadows nothing and is shadowed by nothing, are superseded by [0179](0179-the-prelude-holds-the-core-vocabulary-and-yields-to-a-module.md).

Supersedes the clause of **[M-Import]** that refused `std` as a path root.

## Context

The library was reachable only one way: the prelude published a name and every
module could write it. Nothing above the library could import a module of it, so
a declaration the library wanted any program to reach had to be ambient in
every program.

That has one consequence and it compounds. Whenever the library gained something
worth using, the only way to make it usable was to publish it, so the prelude
grew with the library rather than with the language. It had reached twenty-eight
names — `stdout`, `descriptor`, `Buffer`, `Oom`, `Args` — each of which was
added because something needed to reach it, and none of which any program is
obliged to write. A name in the prelude is in the scope of every module ever
written, so the cost is paid by programs that never use it: it shadows nothing
and is shadowed by nothing, and a program declaring `Writer` for its own
purposes collides with a library type it never asked for.

The library's own modules had the same problem from the other side. `std/option`
needs `Equivalent` from `std/cmp`, and the mechanism it used to get it was the
prelude — the library was publishing names to itself. So the prelude was
simultaneously the language's vocabulary and the library's internal linkage, and
the second kept enlarging the first.

## Decision

**`std` is a reserved path root, and a program reaches a library module by
importing it.** `import std.text` names the module; what it holds is written
`text.println`, or bound by `use text.println` where the program prefers a bare
name.

**A name is in the prelude if and only if the language's own syntax obliges a
program to write it.**

Ten names qualify today:

| Name | What obliges it |
| --- | --- |
| `Str` | a string literal has this type |
| `Range` | `lo..hi` builds one |
| `Option` | `?` answers with one |
| `Result` | `?` answers with one, and an entry point returns one |
| `Display` | `{}` renders through it, and an entry point's failure is held to it |
| `Equatable` | `==` is a call on it |
| `Comparable` | `<` is a call on it |
| `Steppable` | `..` steps through it |
| `Index` | `a[i]` is a call on it |
| `FromEnd` | an index counted from the end is one |

The test is the program's text, not the compiler's convenience. A programmer who
writes `"hello"` has named `Str` whether or not they know it, and a signature
holding the value has to spell a type the program never wrote. That is what
makes a name ambient rather than merely useful: `println` is useful, and a
program that wants it can say so.

**The rule is a gate, in both directions.** A name the syntax obliges is a name
the compiler has to look up by prelude identity — that is how `?` finds `Option`
([0060](0060-a-library-declaration-is-named-through-the-prelude.md)) — and a
name nothing obliges is one it never asks for. So the set the compiler looks up
and the set `std/std.lin` publishes must be equal, and `build.zig` reads both out
of their own sources and refuses a build where they differ.

Each direction catches its own mistake. A name looked up and not published is a
lookup that fails: a program refused over a name it never wrote. A name
published and never looked up is the one that matters here, because nothing
fails — every program simply gets a little more ambient scope, and the prelude
grows one convenience at a time back to twenty-eight.

The gate is also why the rule survives contact with a new feature. A from-end
index landed while this decision was being written
([0089](0089-a-from-end-index-is-a-value-the-container-interprets.md)); `Index`
and `FromEnd` went into the prelude because `a[i]` obliges them, and the count
went from eight to ten with nothing to argue about.

**A library module may write `std.` too.** `std/option` reaches `std/cmp` by
importing it, exactly as a program does. The alternative was a rule saying the
library reaches its siblings some other way, which is a second mechanism for
one question.

**The prelude stops being the compiler's index of the library.** It was serving
two jobs at once: the names a program may write without importing anything, and
the names *the compiler* looks up when it needs a library declaration. Those are
different questions, and only the first is what this record decides.

The second job was load-bearing in a place nothing pointed at. The compiler
implements `Equatable`, `Equivalent`, `Comparable`, `Ordered` and `Steppable`
for the primitives itself — a primitive cannot implement them in Linea, since a
body written with `<` is `Comparable.less` calling itself — and it found each
trait by asking the prelude for the name. So removing `Equivalent` and `Ordered`
from the prelude did not merely stop programs writing them: it stopped every
integer implementing them, and `Bool` stopped being an equivalence. Nothing
about the removal said so.

These are now found by module and name, which is how a library declaration the
compiler must name is already found when no program wrote a reference to it
([0072](0072-a-declaration-only-generated-code-calls-is-named-by-its-module.md)).
The lookup is one routine both passes call, on `Program`, rather than one copy
in resolution and one in lowering. A library with no such module seeds nothing,
which is what a compilation without a library gets and what the previous
arrangement gave for the same reason.

**Rings resolve.** `std.text` and `std.cmp` may import each other. Nothing
prevents it and nothing needs to: a module is loaded once and the second import
finds it, and the case a ring would make dangerous — a type containing itself —
is already refused by `[T-InfiniteLayout]`. A cycle check was designed and not
built, because it would refuse programs that work.

## Consequences

The four traits are effectively a closed set. Adding one changes what a method
call resolves to in every module ever written, so it can break a program that
compiled yesterday. Languages that add to a prelude have an edition mechanism to
absorb that; this one has none, so a fifth trait is a breaking change and is
priced as one. Removing the other eighteen names is what makes this affordable:
the surface that can collide is now small enough to reason about.

A program is longer. `println` becomes `text.println`, or a line of `use`. That
cost is paid by the programs that use the name, which is the point — the
previous arrangement charged it to every program that did not.

`[M-Unused]`'s exemption for the prelude's imports stays, and for the same
reason: the prelude imports every library module so that implementations ship
even where no name is re-exported. It now exempts nothing else, because a library
module's imports are reached for a name like any other.

The migration touched 91 files under `tests/` and `examples/`, driven by the
compiler's own diagnostics rather than by a search over the text: every one was
an `[N-Undefined]` naming the file and the name, which is precise where a regex
over source is not.

## Alternatives considered

**Keep the prelude as it was.** Rejected on the compounding: the prelude grew
with the library because publishing was the only way to make anything reachable,
and nothing about that stops. The twenty-eight would have become forty.

**A four-name prelude — the carriers and nothing else.** `Option`, `Result`,
`Str`, `Range`, with the traits imported. Rejected because `==` is syntax: a
program implementing `Equatable` for its own type is implementing what the
operator already refers to, and requiring an import to write an operator's trait
makes the operator's meaning depend on a line at the top of the file. The four
carriers and the four traits are obliged by the same test and there is no
principled line between them.

**A wider line — publish what most programs turn out to want.** Austral's
`Pervasive` carries sixteen typeclasses and a hundred and seventy-six instances
on this reasoning, and the survey in the design note shows the range is real:
Rust and Swift publish broadly, Zig and Odin publish almost nothing. Rejected
because "what most programs want" is not a property anyone can check, so it
degrades to whatever was added last — which is the state this record is
replacing. The obligation test is checkable, and a gate checks it.

**Curate by hand and write the list down.** A documented list, reviewed when it
changes. Rejected because a list a human maintains beside a compiler that
maintains its own is two implementations of one rule, which is the defect this
compiler keeps finding ([0048](0048-one-question-has-one-answer.md)). The two
sets are already written in two languages in two files; the gate is what makes
that safe.

**Import the name rather than the module — `use std.text.println`.** Rejected
because it puts the module's contents into the program's namespace one name at a
time, so a program that wants six declarations writes six lines and a reader
cannot tell which module any of them came from. `import` plus a qualified use
says where every name lives; `use` remains available for the program that wants
a bare name and is willing to say so.
