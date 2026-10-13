# 178. A constant is a static place

Status: Accepted — 2026-09-26

Supersedes the materialization clause of
[0140](0140-aggregate-constants-retain-checked-construction-plans.md): the one
MIR materializer now lays a constant out once as read-only module data instead
of emitting stores at every reference. Extends
[0123](0123-observations-carry-owner-dependencies-through-callable-contracts.md):
an observation of a constant carries no owner dependency. Extends
[0147](0147-a-borrowed-let-pattern-reads-a-stable-place.md): a constant is a
stable place.

## Context

A constant was not a place. Each read built its value again in the reading
function's frame, so there was no storage a borrow of it could observe beyond
the expression that built it. Sound programs were refused:

- `fn primes() -> mem.Slice[UInt64] where carries() { PRIMES.as_slice() }`
  was [T-BorrowContract] ("an escaping observation requires a caller place")
  and [O-Escapes];
- a closure returning `log.field("service", SERVICE)` could not be written,
  because the field borrows its value;
- `let limit = reading(CONFIG.limit)` and `reading(LIMITS[i])` could not be
  kept after their statement;
- `borrow LIMIT` was [T-Lend].

Binding the constant to a local first made each of these compile only where the
local lived, so none of them could be returned.

A constant never changes and nothing owns it. The only thing missing was
storage that lasts as long as the program.

## Decision

**A constant's value lives in static storage.** Lowering lays a constant out
once for each type it is read at, as a `mir.Static`: the scalar parts a store of
each would write, at the offsets the type's layout gives them, with a `Str`'s
address as a part naming a blob of the byte pool. `static_addr` names one. The
backend writes it as a packed constant global. The verifier refuses a static
whose parts overlap or do not sit where the type places a part of that width,
and refuses any store, copy or `inout` lend into static storage, because the
global is read-only.

**A constant is a place, however it is named.** A constant named bare, through
its module (`settings.LIMIT`) or through a type (`Limits.MAX`) is one place.
`Resolution.constantNamed` answers whether an expression names one, and the
checker's place test, the dependency analysis and lowering each root a place
path there. A borrow of a constant, or of a field or element of it, observes
the static storage directly: `LIMITS[i]` is an address inside `LIMITS`'s
static, never a copy in a slot.

**A static place has no owner.** The dependency analysis gives it no origin:
nothing ends, replaces or releases it. An observation of a constant therefore
depends on nothing, and may be returned from a function declaring
`carries()`, stored through an `inout` parameter, or kept across statements and
loop iterations.

**A read by value copies.** A constant whose type fits a register reads as its
one part, an immediate. Any other constant is read by copying out of its static,
as any place is read. Each read still yields an independent value, so
[T-Const] still requires a constant built from a type's parts to be Copyable;
its report now says a constant is copied wherever it is read.

## Consequences

- The refused shapes above compile. `borrow LIMIT`, `let read` and `match read`
  over a constant, and a view of a constant array returned from a function
  taking nothing are ordinary.
- Constants of the same type and value share one static. No program can tell,
  because an observation's address cannot be compared.
- Reading an aggregate constant by value is one copy out of module data rather
  than a store per part at each reference. A constant read at many sites is laid
  out once per type.
- A constant read only by value at a type that fits a register emits no data.
  Only constants read as a place or at an aggregate type are emitted.
- Each static's type is declared once as an MLIR type alias, so the operations
  building it name the type in a word and the emitted text is linear in the
  static's parts.
- Cost: one hash lookup by checked value per constant read in lowering, and one
  layout walk per constant and type, sized by the constant.

## Alternatives considered

**Give a borrowed constant a slot in the borrowing function's frame.** The
borrow could then be kept for the rest of the function but never returned. It
is also unsound where the slot is reused: one slot for `reading(LIMITS[i])`
inside a loop holds the current iteration's element, so a borrow kept from an
earlier iteration reads a later element.

**Keep building a constant at each reference and add static data only for
borrows.** A constant's bytes would then have two producers, one emitting
stores and one writing data, and the two would have to agree about every
layout. One layout walk serves both a read and a borrow.

**Write a static as an array of bytes.** Each scalar's encoding, byte order
included, would then be the compiler's to state. Typed parts leave the encoding
to the backend, exactly as a store of the same type does.

**Make only bare module constants places.** A constant named through its module
or a type is the same value in the same storage, and a rule that depended on the
spelling would refuse `settings.LIMIT` where it accepts `LIMIT`.
