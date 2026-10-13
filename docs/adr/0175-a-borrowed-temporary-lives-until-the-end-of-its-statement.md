# 175. A borrowed temporary lives until the end of its statement

Status: Accepted — 2026-09-26

Replaces the interpolation clause "interpolated values are held by copy" of
the original text-writers design
and of the semantics' [T-Interpolation], which no record decided. Refines
[0123](0123-observations-carry-owner-dependencies-through-callable-contracts.md):
a borrowed argument no longer has to be a place.

## Context

Two rules refused programs for the same reason: a value that is borrowed where
it is written had to already live somewhere.

An interpolation held a copy of each value, so every interpolated value had to
be Copyable. `"{error:?}"` on a failure that owns memory, such as
`io.ReadAllFailure`, was refused, and the guide taught rendering through
`Debug.debug` by hand instead. The copy also lost the value's dependencies: a
`Str` view copied into a literal was not tied to the string it viewed.

A call whose result borrows an argument, `log.field("count", 3)`, required that
argument to be a place ([T-BorrowContract]: "an escaping observation requires a
caller place"). A field could therefore not log a literal or a computed value,
and every log line with one needed a `let` before it. `[1, 2].as_slice()` was
refused the same way.

Both want the same thing: a value that is not a place to live long enough to be
borrowed by what is being built from it, and no longer.

## Decision

**One rule serves both.** A value that is borrowed where it is written without
being a place is evaluated into a temporary. The temporary lives until the end
of the statement that evaluates it ([O-Temporary]). A value borrowing it may be
passed, rendered and written within that statement; using it in a later
statement, or returning it, is refused. Binding it with `let` is allowed, and
using the binding after the statement is what is refused, with help to bind
the borrowed value first.

A statement is an expression statement, a `let`, a `defer`'s expression where
it runs, a function's or closure's body, a `while` condition, and a loop body
per iteration. A block's trailing value, conditional branches and `match` arms
belong to the statement around them, so a branch can build a borrowed value
that the call around the conditional uses. A `break` or a `continue` ends
the statements it leaves. A temporary is discarded where it ends and runs no
cleanup; a temporary with a settlement obligation is still refused by
[O-Leak].

**An interpolation holds a Copyable value as a copy, borrows a place it
cannot copy, and holds any other value it can discard.** Copyable is no longer
required; `Display` or `Debug` still is. A Copyable value, place or computed,
is copied into the literal and carries its own dependencies there, so a copy
of a `Str` view keeps the string it views alive. A place that cannot be copied
(a local, a parameter, a binder, or a field or element of one) is borrowed,
and the literal carries that borrow exactly as a view does, under the
ordinary [O-Borrow] and [O-Escapes] rules. A value
computed in the braces (a call, a nested literal, a string literal) has no
other owner, so the literal owns it: it is moved in, and the
literal may be bound and rendered by a later statement. Only a computed value
that must be settled is borrowed as a temporary of the literal's statement,
because the literal has no way to settle what it holds; [O-Leak] then refuses
it unless something takes it. Evaluation stays once, in source order, at the
literal: a snapshot, a held value and a temporary are made there, and a
borrowed place cannot change while the literal borrows it, so rendering later
reads what was there when the literal was written.

**A constant is never a temporary.** It is a place in static storage
([0178](0178-a-constant-is-a-static-place.md)), so a constant passed where a
borrow is taken, or written in an interpolation's braces, is borrowed where it
lives, and a value borrowing it may be kept or returned anywhere.

The checker decides which values are borrowed temporaries and records them in
`Typing.borrowed_temporaries`: an argument that is not a place to a
stable-address `read` parameter, and an interpolated piece that is not a
scalar, not a place and must be settled. That table is the one answer. The
checker likewise decides once per piece whether a literal borrows it or holds
it, and records that only in the literal's type, beside each value's format;
the builder, the dependency analysis and lowering read it from the type where
a literal is built. No pass infers the mode from a field's type, since a held
`borrow T` value and a borrowed `T` place both have a `borrow T` field.
Lowering gives each temporary a slot of its own and borrows the slot.
Ownership's builder assigns each entry to the innermost open statement and
emits a `temporaries_end` operation where the statement ends; the dependency
analysis gives a borrow of the temporary an origin owned by that statement and
invalidates it there. A later use of a
carrier holding the invalidated origin, or a return of one, is [O-Temporary].

## Consequences

- `logger.info("counted", log.field("count", 3))` and
  `println("refused: {error:?}")` are accepted, and the `let`s and `copy`s that
  existed only to satisfy the old rules are gone from the library, examples and
  tests.
- A linear or otherwise noncopyable value renders inside a literal and is
  settled by its owner afterwards.
- A literal holding a copy of a view now depends on what the view observes,
  which the old copy dropped. A literal borrowing a place it cannot copy
  depends on the place, and is refused where it outlives that place or the
  place is replaced while it is held. Such a literal did not compile before.
- Copyable pieces are held whether they are places or computed, so literals
  that render the same types are one type, as they were under the copy rule:
  `var line = "hi {n}"` may be reassigned from `"hi {name()}"`, and `if` and
  `match` arms may mix them.
- A piece that cannot be copied is borrowed when it is a place and held when
  it is computed, so `"hi {name}"` and `"hi {make_name()}"` over an affine
  `Name` are different types. Assigning one where the other is expected, or
  mixing them in arms, is [T-Mismatch], and the report's help says to bind the
  computed value with `let` first. Such literals did not compile under the
  copy rule, so nothing that compiled before is refused.
- Returning an interpolation that borrows a parameter requires the function's
  contract to permit that borrow, as returning a view does.
- The interpolation type's name and symbol show each value's mode:
  `{interpolation borrow Name}` borrows a place, `{interpolation Name}` holds
  a computed `Name`, and `{interpolation copy borrow Name}` holds a copy of a
  `borrow Name` value. These are different types, and a name or symbol that
  dropped the mode would print them alike in a mismatch or give two
  instantiations one symbol.
- A held `borrow T` value and a borrowed `T` variable are different types too,
  and assigning one where the other is expected is [T-Mismatch] with a help
  saying to interpolate the same one in both literals.
- Cost: one side-table entry per borrowed temporary; ownership adds one
  operation per statement that made one, and one map entry per temporary. The
  invalidation at a statement's end reads only the fact sets its temporaries
  reach, through the same owner index a scope exit uses.

## Alternatives considered

**Extend a temporary's lifetime to the enclosing block when its borrower is
bound by `let`**, as Rust extends `let x = &temp()`. That makes whether a
program is accepted depend on the syntactic shape of the initializer, and a
temporary inside a call argument would still end at the statement, so the rule
would have two answers for one question. Binding the value first is one line
and says where the value lives.

**Borrow every place, Copyable or not.** A Copyable place and a computed value
of the same type would then give different literal types, and a variable
reassigned from one to the other, or `if` and `match` arms choosing between
them, were refused where the copy rule had accepted them. A copy now carries
the value's dependencies, which is what the borrow was for.

**Borrow every non-scalar piece, computed ones as statement temporaries.** It
is the call-argument rule applied unchanged, but nothing else can observe a
computed piece, so the literal can own it and needs no statement lifetime.
Borrowing refused `let line = "{name(i)}"` followed by `println(line)`, and a
literal naming a constant, both of which the copy rule accepted. Holding
computed pieces is chosen for every piece the literal may discard. A call
argument cannot be held the same way: the result borrows the parameter, which
the callee does not own, so the temporaries rule stays for arguments.

**Hold a computed piece that must be settled as well.** The literal would then
own an obligation it has no operation to discharge, and discarding it runs no
cleanup, so it stays a temporary of the statement and [O-Leak] asks who takes
it.

**Keep holding interpolated values by copy and require Copyable.** It is what
refused `{error:?}` and taught a workaround for the commonest thing a program
prints; it also dropped the copied value's dependencies.

**Hold every interpolated value by borrow, scalars included.** `"{count + 1}"`
would then borrow a temporary, and a literal naming any computed number could
not be bound for a later statement. A scalar's value position already takes a
snapshot everywhere else in the language, and holding one costs no more than
borrowing it.

**End a block's trailing value's temporaries with the block.** A conditional
whose branches build a borrowed value for the call around it, the natural way
to choose a log field, would then be refused.
