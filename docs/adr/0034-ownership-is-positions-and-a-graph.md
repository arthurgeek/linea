# 34. Ownership is positions and a graph, not a type system feature

Status: Accepted — 2026-07-27; refined by
[0046](0046-the-universe-of-an-instantiation-is-computed.md), which draws a
distinction this record did not have to: a concrete type's universe is declared
and an instantiation's is computed. Extended by
[0063](0063-disposal-is-scheduled-never-inserted.md), which schedules a written
disposal at scope exit and inserts none. Extended by
[0246](0246-a-call-holds-what-it-lends-until-it-runs.md), under which a call
holds what it lends until it runs, so a take in a later argument is [O-Move].

The two-universe default is superseded by [0124](0124-copyability-and-settlement-are-independent-capabilities.md); the universal explicit-copy clause is superseded by [0125](0125-scalar-value-positions-take-snapshots.md).

Builds on [0032](0032-a-module-is-a-directory.md) and
[0033](0033-sealing-is-checked-not-omitted.md), which together give the
boundary this rests on, and on
[0015](0015-when-to-introduce-a-representation.md), which is
what the graph below has to justify itself against.

## Context

A type may declare that its values must be disposed of. The compiler has to
prove that every one of them is, exactly once, on every path — and say which
value and which path when it is not.

Three families of answer exist. Borrow checking with lifetimes proves
non-aliasing and gets disposal as a consequence; affine types with implicit
drop insert the disposal; dynamic checks move the question to run time. Each
buys the guarantee with something: a lifetime language a reader must learn, a
destructor the programmer did not write, or a cost the program pays forever.

## Decision

**Ownership is its own pass, over its own graph.** Not the type checker: what a
value's type is and what has happened to it are different questions, and a
checker that answers both is one that cannot be told which it got wrong.

**Whether a value moves is decided by position, not by syntax.** A consuming
position takes the value — the right-hand side of a `let`, an argument to a
`sink` parameter, a body's trailing value, a variant payload, a field
initialiser, the scrutinee of a plain `match`. Everything else observes it.
Nothing about the operator decides it, so a form added later inherits the rule
by sitting somewhere.

**A move is universal, and `copy` is the only duplication.** A consuming
position takes the value in both universes: `let b = a` moves `a` whether or
not anything must be disposed of, and a part cannot be taken out of the whole
that still holds it. Nothing is duplicated implicitly, so the one place bytes
are copied is the one place a programmer wrote `copy`. That is what keeps the
cost of a copy visible as the values a program moves grow, and it is why the
rule is stated once rather than twice — a universe adds an obligation, not a
different meaning for the same position.

**A branch is the expression's value, so it sits where the expression sits.**
The branches of an `if`, the arms of a `match`, a block's trailing value and a
`break`'s operand are all what the construct evaluates to, so each inherits the
position the construct is in. `record(if c { p.x } else { p.y })` observes what
it names, exactly as `record(p.x)` would.

**The graph is a representation, and it adds.** Under [0015] a new one must
discard, add or simplify. This adds control-flow edges over nodes that still
carry names. Neither existing representation has both: the syntax tree has
names and no edges — a loop is a subtree, and a fixpoint needs a back edge —
and MIR has edges and no names, because by the time a binding is a slot the
message "`k` was already moved" cannot be written.

**A place is a root and a path, never a list of field indices.** An index, a
range and a dereference are steps this path does not have. Every rule is
written against "a place has a root and a path" so that adding one is a change
to the path and to layout and to nothing here.

**Two rules, three headline bugs.** Use-after-free and double-free are the same
check — the root is moved and something reads it — so `O-Move` covers both, and
`O-Leak` covers the third. The diagnostics do not invent a second code for what
is not a second question.

## Consequences

**`copy` is a word every program that reuses a value must write.** A Free value
used twice needs one, and so does a part read out of a structure the program
keeps. That is a lot of `copy`, and the alternative — copying Free values
implicitly — was weighed and rejected: it makes the expensive operation the
invisible one, and it makes the cost of adding a field to a type something no
reader of a call site can see. Two rules exist to keep the word honest.
`O-CopyRead` refuses a copy nothing takes, and `O-CopyDead` refuses one whose
source is never read again, where the move was what the programmer meant. The
second needs a backward liveness pass over the graph, which exists for it
alone.

**Control flow is built twice.** The ownership graph and MIR are constructed
from one tree by two pieces of code that must agree about what a loop is. This
was chosen over lowering MIR from the graph, which would have built it once and
reached every lowering site in the compiler. The cost is real and this is where
it is written down.

**The loop rule rejects safe programs.** A move in a loop body is refused even
where a `break` makes the back edge unreachable. Reporting only what a fixpoint
proves would accept that program and reject a neighbour for reasons depending
on whether a `break` is unconditional — a rule whose answer a reader cannot
predict without simulating the compiler. Relaxing it later invalidates no
program, which is the direction that matters when choosing which way to err.

**`_` is exempt from the unused rule and not from linearity.** The prefix says
the programmer will not use the value. That is not the claim that it may be
discarded, and treating the two alike is the last hole in the sealed-type
argument.

**The suite can fail for what ownership omits.** A fourth coverage axis
classifies parameter conventions, and `sink` is recorded as waiting on the
generator learning linear types — the classification the table refused to
accept for `inout`, which it turned out to generate already. A mutation deletes
the statement that disposes of a linear value: every accepting case shows that
a program which disposes of its values compiles, and only a program that stops
can show that the compiler noticed.

## Alternatives considered

**Borrow checking with lifetimes.** Rust's answer, and the one that proves the
most. It needs a sublanguage of lifetimes in signatures, an inference algorithm
whose failures are famously hard to explain, and a story for every generic
abstraction over them. Linea has no generics yet, so adopting it would mean
designing the lifetime language before the thing it qualifies. What is bought
is aliasing safety, which [N-Aliased] already gives per call site from the
argument list alone.

**Affine types with an implicit drop.** Values may be used at most once and a
destructor runs for the ones that are not. Removes `O-Leak` entirely, and with
it the guarantee: disposal becomes something the compiler inserted rather than
something the programmer wrote. Principle 5 of the design is that explicit
disposal is preferred, and the reason is that a destructor is code that runs
where no one wrote any — which is where the surprises are.

**Dynamic checks.** A flag per value, checked at run time. Catches double-free
and use-after-free, cannot catch a leak, and costs every program that never had
the bug. It also moves the failure from a message about a name to a crash in a
process, which is a worse thing to be handed.

**Free values copied implicitly.** A consuming position over a Free value could
have taken a copy and left the original where it was, which would delete `copy`
from most programs and both of the rules that keep it honest. Rejected because
it makes the expensive operation the invisible one: what a program duplicates
is what decides how it scales, and a language whose duplication is inferred
gives a reader nothing to look at. It also makes adding a field to a type a
change no call site shows — the copy that was a register becomes a blit, and
nothing in the source moved. The explicit word is the cost of that, paid once
per reuse and visible where it is paid.

**Ownership inside the type checker.** Would have avoided a second traversal
and a second representation. Rejected because the two answer different
questions: a type is a property of an expression and a state is a property of a
path, and a pass that carries both cannot report which of them it got wrong.
The graph's back edge is the concrete form of that — the type checker walks a
tree and never needed one.

**Universes inferred from the representation.** A type holding something linear
could have been made linear automatically rather than diagnosed by
[O-Universe]. Rejected because a type is linear when its author decided it
stands for something that must be disposed of, and no analysis can find that
intent in a `u8`. Inferring it would also make a type's universe change when a
field is added, which is a silent break of every caller.
