# 35. Representation and behaviour are declared apart

Status: Accepted — 2026-07-27

Builds on [0032](0032-a-module-is-a-directory.md), which made a module a
directory of files, and on [0033](0033-sealing-is-checked-not-omitted.md),
which is what `opaque` seals.

## Context

A type's braces held both its parts and its functions:

```
struct Account {
    id: u8,
    pub fn open(id: u8) -> Account { .{ .id = id } }
}
```

That was unremarkable while a module was a file. Everything a type could do was
written in one place because there was nowhere else to write it.

Then a module became a directory. A program of several files is a directory of
them, and any of them may declare functions the others call — except that a
type declared in `account.lin` could gain nothing in `withdrawal.lin` without
moving its declaration. The rule "a module may be split into several files" was
true of every construct but the one people most want to split, and the reason
was that a function's home was a pair of braces rather than a module.

There is a second problem underneath, and it is the one that decides the shape
of the answer. **`opaque` had no answer to give.** A modifier written on a
declaration reaches what that declaration holds, and this one held two kinds of
member:

```
opaque struct Account {
    id: u8,
    pub fn open(id: u8) -> Account { .{ .id = id } }
}
```

What does `opaque` seal here? The field, certainly. The function, which is
already marked `pub` — so either the modifier reaches it and contradicts the
`pub` beside it, or it does not reach it and a reader has to know that the
modifier applies to some members of the braces and not others. Neither reading
is derivable from the syntax, and both are defensible, which is what makes it
an ambiguity rather than a rule someone forgot to write down.

The two are separate decisions and each has its own answer already. A field is
part of what a value **is**, and sealing that is what `opaque` was introduced
for. A function is part of what a value can **do**, and its visibility is
written on it. An opaque type exists to be used through what it can do, so a
modifier that sealed both would seal a type against the only thing that makes
it usable.

Splitting the declarations settles it by construction: a modifier reaches the
braces it precedes, and those braces hold one kind of member.

## Decision

**A type's braces hold its representation and nothing else** — a struct's
fields, an enum's variants. A function written among them is [S-Struct], and
the diagnostic names `impl`.

**A modifier reaches exactly the braces it precedes.** `opaque` and `linear`
are written on the type, so they say what the representation is and what its
values owe; neither can reach a function, because no function is in scope of
either. That is the whole of what the split buys, and it holds for any modifier
added later without the question being reopened.

**`impl T { … }` holds behaviour.** It may appear anywhere in the module that
declares `T`, in any file of it, and any number of times. Nothing orders it
against the type's own declaration, because nothing orders any two declarations
of a module.

**An `impl` is a namespace and not a visibility level.** Each function inside
carries its own `pub`, and [M-Vis] applies to it as to anything else. Exporting
a type and exporting what it can do stay separate decisions, made in separate
places.

**An `impl` declares no name; its header names one.** [N-NotAType] reports a
header naming something that is not a type, and [N-Undefined] one naming
nothing at all — reported at the header, because the members are reached
through the type's name and a header that names no type leaves every one of
them unreachable.

**Enums have `impl` on the same terms.** What a type can do is not a property
of how it is represented, so the two declarations do not differ here.

## Consequences

**A type's behaviour is as splittable as a module's.** `impl Account` in
`account.lin` and another in `withdrawal.lin` are one namespace, which is what
lets a module grow past one file without its types being the thing that pins it
there. The vault example is built on exactly this and would not otherwise be
writable as more than one file.

**The unused rule reaches further than it did.** A member is a declaration, so
a private one nothing calls is [N-Unused]. That is what caught `fits` in the
example being written as a free function when it belonged to the type.

**There is still no receiver.** `impl` attaches functions to a type; it does
not introduce `self`. A member sees its module's declarations and its own
parameters, and nothing else. Adding a receiver later is a question about what
it binds to, and this record does not answer it.

**A member declaration is resolved by name, not by handle.** An `impl` may sit
in a different file from the type, so which type a member belongs to is settled
when the type's own name is. That is a scan rather than a table, which is
cheap while types and their members are few and is the thing to revisit if they
stop being.

## Alternatives considered

**Leave functions in the type's braces and allow the braces to reopen.** The
smallest change: `struct Account { … }` twice, merged. Rejected because it
makes a type's representation something that can be added to from another file,
which is exactly what `opaque` promises cannot happen — and because a reader of
the first declaration could no longer tell what a value is made of. It also
leaves the ambiguity untouched: the second block would carry the modifier or
not, and either answer is a new rule to learn.

**Keep both kinds of member and write down what `opaque` reaches.** A rule
saying the modifier seals fields and never functions would have settled the
question without moving anything. Rejected because the rule exists only to
patch a form that asks it: a reader would have to carry "this modifier applies
to some of what follows" for every modifier the language ever gains, and each
new one would have to answer the question again in its own record. Splitting
the declarations makes the answer readable off the syntax, which is what a rule
nobody has to memorise looks like.

**A separate `extend T { … }` for later additions, with the first block still
holding both.** Two forms for one idea, differing only in which came first.
Rejected on the same grounds every "one shape for one idea" decision here rests
on: a reader would have to know which file was written first to know which form
to expect, and a formatter would have to preserve the distinction.

**Traits or interfaces, with `impl Trait for T`.** The form most languages that
have `impl` also have. Not rejected — deferred. There is nothing to abstract
over yet: Linea has no generics, so a trait would be a name for a set of
signatures with no way to write a function generic in what satisfies it. The
syntax is chosen so that `impl Trait for T` can be added without respelling
anything written today.

**Free functions only, with no namespace.** `ledger.account_open(7)` rather
than `ledger.Account.open(7)`. Rejected because the namespace is what makes the
sealed-type argument legible: `Account.close` is visibly the only way to
dispose of an account, where a free function beside forty others is not. It
also puts every type's vocabulary into one flat module scope, where two types
cannot both have `open`.
