# Calling C

A great deal of useful code is written in C: SQLite, compression, image
formats, the operating system's own libraries. This chapter shows how a Linea
program calls it, and what Linea keeps checking when it does.

The compiler cannot read C. When you declare a C function, it believes what you
wrote about its parameters, its result and who owns what, the way Rust believes
an `extern "C"` block inside `unsafe`. Linea's answer is to keep that belief in
one place: a **wrapper module** that your project's manifest trusts with C. The
wrapper declares the C functions and checks what they return. It hands the rest
of the program ordinary Linea values, which every rule from the earlier
chapters still covers. A C object becomes a linear value, so forgetting to
close one is a compile error, and C's text becomes a `String` checked as
UTF-8.

## Only a trusted module declares C

`extern fn` declares a function written in C. Nothing in a program is trusted
with one until its manifest says so:

```linea
extern fn abs(value: Int32) -> Int32

fn main() -> UInt8 {
    UInt8(abs(-7))
}
```

```
error[M-Extern]: an `extern` is declared only in a module its root's manifest grants, and linea.json does not list "."
 --> main.lin:1:11
  |
1 | extern fn abs(value: Int32) -> Int32
  |           ^^^ list this module under "extern" in linea.json to trust it with C, or call a module that is granted
```

The manifest, `linea.json`, lists the modules it trusts under `"extern"`, each
spelled the way an import names it. `"."` is the root module itself. Listing a
small module rather than the whole program keeps the trusted code small enough
to read: a reviewer checks the wrapper's declarations against the C header, and
no other module can declare C at all.

## Calling your own C

A manifest can also name C sources to build with the program, under
`"native"`. This project keeps a little C library in `counter/counter.c`, and
the `counter` module is the one trusted to call it:

`tally/linea.json`:

```json
{ "extern": ["counter"], "native": ["counter/counter.c"] }
```

`tally/counter/counter.c`:

```c
#include <stdint.h>

int32_t counter_square(int32_t value) { return value * value; }

int64_t counter_sum(int64_t left, int64_t right) { return left + right; }

double counter_average(int64_t total, int32_t count) { return (double)total / count; }
```

`tally/counter/counter.lin`:

```linea
// Each declaration says what the C prototype says, in Linea's types: C's
// `int32_t` is `Int32`, its `int64_t` is `Int64` and its `double` is
// `Float64`. The declarations are private to this module.
extern fn counter_square(value: Int32) -> Int32

extern fn counter_sum(left: Int64, right: Int64) -> Int64

extern fn counter_average(total: Int64, count: Int32) -> Float64

// The rest of the program calls these ordinary functions instead.
pub fn square(value: Int32) -> Int32 {
    counter_square(value)
}

pub fn sum(left: Int64, right: Int64) -> Int64 {
    counter_sum(left, right)
}

// C divides by `count` without checking it, so this wrapper does.
pub fn average(total: Int64, count: Int32) -> Option[Float64] {
    if count == 0 {
        return .None
    }
    .Some(counter_average(total, count))
}
```

`tally/main.lin`:

```linea
import std.io
import counter

fn main() -> Result[UInt8, io.IoError] {
    let squared = counter.square(12)
    let total = counter.sum(40, 2)
    let mean = counter.average(total, 4).unwrap_or(0.0)
    io.println("{squared} {total} {mean}")?
    .Ok(0)
}
```

```
144 42 10.5
```

The compiler builds `counter.c` with the same C compiler and optimisation
level as the program, and links the two.

An integer of 8, 16, 32 or 64 bits crosses to C, and so does a `Float64`,
which is C's `double`, as `average` shows. On every platform Linea runs on, C's
`int` is `Int32`, `long` and `int64_t` are `Int64`, and `size_t` is `UInt64`.
`Bool` does not cross, because C has no single answer for which bytes mean
true: pass an integer and compare it.

### An `extern` stays private

An `extern` is never public. If another module could call C directly, it would
be trusted with C too, and the manifest's list would no longer say who is. The
trusted module publishes ordinary functions, as `counter` does above, and those
functions are where it checks what C cannot, such as `average`'s zero count:

`exposed/linea.json`:

```json
{ "extern": ["wrapper"] }
```

`exposed/wrapper/wrapper.lin`:

```linea
pub extern fn labs(value: Int64) -> Int64

pub fn distance(from: Int64, to: Int64) -> Int64 {
    labs(to - from)
}
```

`exposed/main.lin`:

```linea
import wrapper

fn main() -> UInt8 {
    UInt8(wrapper.distance(3, 5))
}
```

```
error[M-Extern]: an `extern` is private to the module trusted with C
 --> exposed/wrapper/wrapper.lin:1:15
  |
1 | pub extern fn labs(value: Int64) -> Int64
  |               ^^^^ drop the visibility, and publish a function that calls it
```

## A C object is a sealed linear newtype

Most C libraries hand out pointers to objects you must later free: SQLite's
`sqlite3 *`, a file's `FILE *`. In Linea that pointer is an address, a
`UInt64`, kept in a newtype the wrapper seals:

- `@opaque` means only the wrapper can make one from an address or take the
  address back out.
- `@linear` means every one must reach the function that frees it.

A newtype crosses to C as the value it wraps, so C receives the pointer
itself. How the `extern` takes the handle says what C does with the object:

- `read` lends it to C for the call, and promises C only reads it.
- A parameter written without a convention lends it too, and C may change
  it. The call then lends the handle's place as an `inout` argument would,
  although C receives the handle by value: the place must be one that may
  change, such as a `var` or a field of an `inout self`, and nothing read
  from the object earlier can still be in use after the call. A handle C may
  change cannot be `copyable`, since a copy would still name the object.
- `sink` gives it to C for good, which is how the function that frees it is
  declared.

`ledger/linea.json`:

```json
{ "extern": ["counter"], "native": ["counter/counter.c"] }
```

`ledger/counter/counter.c`:

```c
#include <stdint.h>
#include <stdlib.h>

struct counter {
    int64_t total;
};

struct counter *counter_open(void) { return calloc(1, sizeof(struct counter)); }

void counter_add(struct counter *counter, int8_t amount) { counter->total += amount; }

int64_t counter_total(const struct counter *counter) { return counter->total; }

void counter_close(struct counter *counter) { free(counter); }
```

`ledger/counter/counter.lin`:

```linea
@(opaque, linear)
type Handle = UInt64

// C answers a null pointer when it cannot allocate, so the address comes back
// as a plain `UInt64` and becomes a `Handle` only once it is known not to be
// zero.
extern fn counter_open() -> UInt64

extern fn counter_add(counter: Handle, amount: Int8)

extern fn counter_total(read counter: Handle) -> Int64

extern fn counter_close(sink counter: Handle)

// A running total kept by the C library. It must be closed.
@(opaque, linear)
struct Counter { handle: Handle }

pub enum OpenError { OutOfMemory }

impl Counter {
    pub fn open() -> Result[Counter, OpenError] {
        let address = counter_open()
        if address == 0 {
            return .Err(.OutOfMemory)
        }
        .Ok(.{ handle = Handle(address) })
    }

    pub fn add(inout self: Self, amount: Int8) {
        counter_add(self.handle, amount)
    }

    pub fn total(self: Self) -> Int64 {
        counter_total(self.handle)
    }

    pub fn close(sink self: Self) {
        let Counter { handle: handle } = self
        counter_close(handle)
    }
}
```

`ledger/main.lin`:

```linea
import std.io
import counter

use counter.Counter

fn main() -> Result[UInt8, io.IoError] {
    var tally = Counter.open() else |_| {
        return .Ok(1)
    }
    &tally.add(-3)
    &tally.add(100)
    let total = tally.total()
    tally.close()
    io.println("{total}")?
    .Ok(0)
}
```

```
97
```

`Counter` holds a linear `Handle`, so it is linear too, and a program that
drops one without closing it is refused, just as it would be for a file. This
is the same program without its `tally.close()`:

`forgotten/linea.json`:

```json
{ "extern": ["counter"], "native": ["counter/counter.c"] }
```

`forgotten/counter/counter.c`:

```c
#include <stdint.h>
#include <stdlib.h>

struct counter {
    int64_t total;
};

struct counter *counter_open(void) { return calloc(1, sizeof(struct counter)); }

int64_t counter_total(const struct counter *counter) { return counter->total; }

void counter_close(struct counter *counter) { free(counter); }
```

`forgotten/counter/counter.lin`:

```linea
@(opaque, linear)
type Handle = UInt64

extern fn counter_open() -> UInt64

extern fn counter_total(read counter: Handle) -> Int64

extern fn counter_close(sink counter: Handle)

@(opaque, linear)
struct Counter { handle: Handle }

impl Counter {
    pub fn open() -> Option[Counter] {
        let address = counter_open()
        if address == 0 {
            return .None
        }
        .Some(.{ handle = Handle(address) })
    }

    pub fn total(self: Self) -> Int64 {
        counter_total(self.handle)
    }

    pub fn close(sink self: Self) {
        let Counter { handle: handle } = self
        counter_close(handle)
    }
}
```

`forgotten/main.lin`:

```linea
import counter

use counter.Counter

fn main() -> UInt8 {
    let tally = Counter.open() else {
        return 1
    }
    UInt8(tally.total())
}
```

```
error[O-Leak]: `tally` (a linear `Counter`) is still owned when this path leaves
  --> forgotten/main.lin:6:9
   |
6  |     let tally = Counter.open() else {
   |         ^^^^^ never settled on the path that reaches the end of this block
10 | }
   | - the block ends here
   |
   = help: settle it first with `tally.close()`
```

### `inout` passes the address of a value

A parameter declared `inout` crosses as the address of the place it lends,
which is C's `T *`. C reads the value there and may write another, as an
out-parameter does. Many C libraries open an object by writing its address
through a `T **` and answering a status code. This one even writes an object
when it reports a failure, as SQLite's `sqlite3_open_v2` does, so the wrapper
lends a `UInt64` for C to fill in and closes what it gets on every path:

`books/linea.json`:

```json
{ "extern": ["ledger"], "native": ["ledger/ledger.c"] }
```

`books/ledger/ledger.c`:

```c
#include <stdint.h>
#include <stdlib.h>

struct ledger {
    int64_t opening;
};

/* Writes a ledger through `out` even when it reports a failure, and the
 * caller must close it either way. */
int32_t ledger_open(struct ledger **out, int64_t opening) {
    *out = malloc(sizeof(struct ledger));
    if (*out == NULL) return 2;
    (*out)->opening = opening;
    return opening < 0 ? 1 : 0;
}

int64_t ledger_opening(const struct ledger *ledger) { return ledger->opening; }

void ledger_close(struct ledger *ledger) { free(ledger); }
```

`books/ledger/ledger.lin`:

```linea
@(opaque, linear)
type Handle = UInt64

// `inout` passes the address of `out`, so C's `struct ledger **` writes the
// new ledger's address into it.
extern fn ledger_open(inout out: UInt64, opening: Int64) -> Int32

extern fn ledger_opening(read ledger: Handle) -> Int64

extern fn ledger_close(sink ledger: Handle)

@(opaque, linear)
struct Ledger { handle: Handle }

pub enum OpenError { OutOfMemory, NegativeOpening }

impl Ledger {
    pub fn open(opening: Int64) -> Result[Ledger, OpenError] {
        var address: UInt64 = 0
        let status = ledger_open(&address, opening)
        if address == 0 {
            return .Err(.OutOfMemory)
        }
        // A ledger exists whatever the status, so it is closed on failure.
        let ledger = Ledger { handle = Handle(address) }
        if status != 0 {
            ledger.close()
            return .Err(.NegativeOpening)
        }
        .Ok(ledger)
    }

    pub fn opening(self: Self) -> Int64 {
        ledger_opening(self.handle)
    }

    pub fn close(sink self: Self) {
        let Ledger { handle: handle } = self
        ledger_close(handle)
    }
}
```

`books/main.lin`:

```linea
import std.io
import ledger

use ledger.Ledger

fn main() -> Result[UInt8, io.IoError] {
    let opened = Ledger.open(250) else |_| {
        return .Ok(1)
    }
    let opening = opened.opening()
    opened.close()
    io.println("opened with {opening}")?
    match Ledger.open(-1) {
        Ok(refused) => {
            refused.close()
            return .Ok(2)
        },
        Err(reason) => match reason {
            NegativeOpening => io.println("a negative opening is refused")?,
            OutOfMemory => return .Ok(3),
        },
    }
    .Ok(0)
}
```

```
opened with 250
a negative opening is refused
```

Do not write `inout` for a handle you mean to pass by value: `inout handle:
Handle` hands C the address of the handle, a `T **`, where a function taking
the object wants the `T *` itself.

## Text and bytes: `std.ffi`

C has two common ways to take text: a pointer and a length, or a pointer to
bytes ending in a NUL. `std.ffi` has a type for each, and one for text that C
hands back. A Rust programmer will recognise `CString` and `CStr`.

- `ffi.bytes(text)` lends the bytes of a `Str` as an `ffi.Bytes`, which C
  receives as a `const uint8_t *`, and `ffi.bytes_of(view)` lends a
  `mem.Slice[UInt8]`'s. Pass the length beside it.
- `ffi.CString.open(text)` copies text and a NUL into storage of its own, and
  `text()` lends it to C as an `ffi.CText`, a `const char *`. It refuses text
  that holds a NUL of its own, which would end the string early in C.
- An `ffi.CText` that C returns points at text C owns. You read it only by
  copying it: `to_owned()` measures it to its NUL and checks it is UTF-8, and
  `copy_bytes(length:)` copies a length C gave you, NULs included.

Each of these is a value that **borrows** what it points into, as a `Str`
borrows a `String` ([Borrowing](06-borrowing.md)). Linea refuses a program
that frees or changes a Linea owner while one of these still points into it.
Here a checksum written in C reads a `Str`'s bytes and a vector's:

`sums/linea.json`:

```json
{ "extern": ["checksum"], "native": ["checksum/checksum.c"] }
```

`sums/checksum/checksum.c`:

```c
#include <stdint.h>

uint64_t checksum_sum(const uint8_t *bytes, uint64_t length) {
    uint64_t total = 0;
    for (uint64_t i = 0; i < length; i++) total += bytes[i];
    return total;
}
```

`sums/checksum/checksum.lin`:

```linea
import std.ffi
import std.mem

// C reads `length` bytes from the address a `Bytes` holds.
extern fn checksum_sum(bytes: ffi.Bytes, length: UInt64) -> UInt64

// Add up the bytes of `text`.
pub fn of(text: Str) -> UInt64 {
    checksum_sum(ffi.bytes(text), text.length())
}

// Add up `bytes`.
pub fn of_bytes(bytes: mem.Slice[UInt8]) -> UInt64 {
    checksum_sum(ffi.bytes_of(bytes), bytes.length())
}
```

`sums/main.lin`:

```linea
import std.io
import std.mem
import checksum

fn main() -> Result[UInt8, io.IoError] {
    defer var bytes: mem.Vec[UInt8] = mem.Vec.new()
    &bytes.push(1).unwrap()
    &bytes.push(2).unwrap()
    let guest = checksum.of("guest")
    let counted = checksum.of_bytes(bytes.as_slice())
    io.println("{guest} {counted}")?
    .Ok(0)
}
```

```
552 3
```

A `CText` that points inside a C object borrows the handle it was read from,
and the declaration says so with `borrows`. An `extern` answering a `CText`
must say where it points: `borrows(handle)` when the text lives in an object a
parameter holds, or `carries()` when C keeps it for as long as the program
runs. Leaving the contract out is refused, because the compiler cannot read C
to find out.

`greeting/linea.json`:

```json
{ "extern": ["greeter"], "native": ["greeter/greeter.c"] }
```

`greeting/greeter/greeter.c`:

```c
#include <stdlib.h>
#include <string.h>

struct greeter {
    char name[16];
};

struct greeter *greeter_open(void) {
    struct greeter *greeter = calloc(1, sizeof(struct greeter));
    if (greeter != NULL) strcpy(greeter->name, "Ada");
    return greeter;
}

/* The name lives inside the greeter until it is renamed or closed. */
const char *greeter_name(const struct greeter *greeter) { return greeter->name; }

/* Bytes holding a NUL of their own, which only a copy of a known length
 * keeps whole. */
const char *greeter_record(const struct greeter *greeter) {
    (void)greeter;
    return "id\0Ada";
}

void greeter_rename(struct greeter *greeter, const char *name) {
    strncpy(greeter->name, name, sizeof greeter->name - 1);
}

void greeter_close(struct greeter *greeter) { free(greeter); }
```

`greeting/greeter/greeter.lin`:

```linea
import std.ffi

@(opaque, linear)
type Handle = UInt64

extern fn greeter_open() -> UInt64

// The answer points into the greeter, so it borrows the handle.
extern fn greeter_name(read greeter: Handle) -> ffi.CText where borrows(greeter)

extern fn greeter_record(read greeter: Handle) -> ffi.CText where borrows(greeter)

// C reads a NUL-terminated string, which a `CString` holds.
extern fn greeter_rename(greeter: Handle, name: ffi.CText)

extern fn greeter_close(sink greeter: Handle)

// Copy C's text out, or empty text when it is not UTF-8.
fn copied(text: ffi.CText) -> String {
    match text.to_owned() {
        Ok(owned) => owned,
        Err(_) => String.new(),
    }
}

@(opaque, linear)
struct Greeter { handle: Handle }

impl Greeter {
    pub fn open() -> Option[Greeter] {
        let address = greeter_open()
        if address == 0 {
            return .None
        }
        .Some(.{ handle = Handle(address) })
    }

    // Copy the name out of C before anything can change it.
    pub fn name(self: Self) -> String {
        copied(greeter_name(self.handle))
    }

    // The record holds a NUL, so it is copied by the length C documents.
    pub fn record_length(self: Self) -> UInt64 {
        match greeter_record(self.handle).copy_bytes(length: 6) {
            Ok(bytes) => {
                let length = bytes.length()
                bytes.release()
                length
            },
            Err(_) => 0,
        }
    }

    // `greeter_rename` changes the greeter, so it is called only from a
    // method that takes the greeter `inout`: that is what ends a name read
    // before it.
    pub fn rename(inout self: Self, name: Str) {
        let copied = ffi.CString.open(name) else |_| {
            return
        }
        greeter_rename(self.handle, copied.text())
        copied.release()
    }

    pub fn close(sink self: Self) {
        let Greeter { handle: handle } = self
        greeter_close(handle)
    }
}
```

`greeting/main.lin`:

```linea
import std.io
import greeter

use greeter.Greeter

fn main() -> Result[UInt8, io.IoError] {
    var person = Greeter.open() else {
        return .Ok(1)
    }
    defer let before = person.name()
    &person.rename("Grace")
    defer let after = person.name()
    let record = person.record_length()
    person.close()
    io.println("{before}, then {after}; a record of {record} bytes")?
    .Ok(0)
}
```

```
Ada, then Grace; a record of 6 bytes
```

Renaming rewrites the bytes the name points at. A wrapper that held on to the
`CText` across a rename would read whatever C wrote there next. C takes the
handle by value either way, so the declaration says which calls only read:
`greeter_name` marks its parameter `read`, and `greeter_rename` does not. A
call that may change the greeter is allowed only in a method taking the
greeter `inout` or `sink`, as `rename` does. That `inout` is what refuses the
stale read:

```linea
fn stale(inout person: Greeter) -> String {
    let name = greeter_name(person.handle)
    &person.rename("Grace")
    copied(name)
}
```

<!-- guide: unchecked a fragment added to the end of the greeter module above, shown for the error it gets -->
```
error[O-Borrow]: this operation invalidates a place that a later observation still needs
  --> greeting/greeter/greeter.lin:74:5
   |
74 |     &person.rename("Grace")
   |     ^^^^^^^^^^^^^^^^^^^^^^^ keep this place available until the last use of its observation
75 |     copied(name)
   |            ---- the observation is still used here
```

A method that took the greeter as a plain `self` could not call
`greeter_rename` at all, because `self.handle` is then a place that may not
change:

```linea
impl Greeter {
    pub fn rename_quietly(self: Self, name: Str) {
        let copied = ffi.CString.open(name) else |_| {
            return
        }
        greeter_rename(self.handle, copied.text())
        copied.release()
    }
}
```

<!-- guide: unchecked a fragment added to the end of the greeter module above, shown for the error it gets -->
```
error[T-ExternHandle]: `greeter_rename` may change the object this handle holds, so the handle is lent from a place that may change
  --> greeting/greeter/greeter.lin:77:24
   |
77 |         greeter_rename(self.handle, copied.text())
   |                        ^^^^^^^^^^^ pass a handle held in a `var` or an `inout` parameter, or mark `greeter` `read` if C only reads it
```

### `std.ffi` stays inside the trusted module

A `CText` is only as good as the promise the declaration made about it, and
`copy_bytes` believes the length it is given. So only a module the manifest
trusts may import `std.ffi` or call any of its operations. A wrapper should
copy what C holds into ordinary values before they leave, as the greeter
copies its name into a `String`. Should a `CText` reach another module anyway,
inside a value the wrapper hands out, that module can pass it on but cannot
read it. A module that is not trusted gets [M-Foreign]:

```linea
import std.ffi

fn main() -> UInt8 {
    let _lent = ffi.bytes("guests")
    0
}
```

```
error[M-Foreign]: only a module its root's manifest grants may import `std.ffi`
 --> main.lin:1:8
  |
1 | import std.ffi
  |        ^^^^^^^ call a module that is granted, or list this one under "extern" in linea.json
```

## When C fails: `ffi.Errno`

Many C functions answer a sentinel such as -1 when they fail and leave the
reason in `errno`, a per-thread integer the C library sets. Reading it later is
a trap: freeing memory, writing output or any other call in between may change
it, and a call that succeeds may leave it holding anything at all. So an
`extern` asks for it in its result instead. Declared to answer
`ffi.Errno[Int32]`, POSIX's `unlink` still returns C's `int`, and the compiler
reads `errno` immediately after the call returns, before anything else runs.

What an `Errno` holds is reached only by saying what failure looks like.
`failed_at(-1)` answers `.Err(code)` when C returned -1 and `.Ok(value)`
otherwise; `failed_when(failed)` takes the test as a `Bool`, for a function
whose failure is not one value; `value()` reads what C returned. The code is
reached only after the wrapper has said the call failed. `io.IoError.from_os` turns the
code into a portable category such as `NotFound`, the same one `std.fs`
reports:

`cleanup/linea.json`:

```json
{ "extern": ["posix"] }
```

`cleanup/posix/posix.lin`:

```linea
import std.ffi
import std.io

// `unlink` answers -1 and sets `errno` when it fails. Answering
// `ffi.Errno[Int32]` keeps that `errno` beside the result.
extern fn unlink(path: ffi.CText) -> ffi.Errno[Int32]

// Remove the file at `path`, reporting why C could not.
pub fn remove(path: Str) -> Result[Int32, io.IoError] {
    let named = ffi.CString.open(path) else |_| {
        // `EINVAL` is 22 on Linux and macOS: C cannot be handed text
        // holding a NUL.
        return .Err(io.IoError.from_os(.Remove, 22))
    }
    let answer = unlink(named.text())
    // Releasing the copy frees memory, which may change `errno`; `answer`
    // already holds the value it had when `unlink` returned.
    named.release()
    match answer.failed_at(-1) {
        Ok(value) => .Ok(value),
        Err(code) => .Err(io.IoError.from_os(.Remove, code)),
    }
}
```

`cleanup/main.lin`:

```linea
import std.fs
import std.io
import posix

fn remove_and_report(path: Str) -> Result[(), io.IoError] {
    match posix.remove(path) {
        Ok(_) => io.println("removed {path}"),
        Err(failure) => io.println("could not remove {path}: {failure.category}"),
    }
}

fn main() -> Result[UInt8, io.IoError] {
    let draft = fs.Path.from_str("draft.txt").unwrap()
    let _written = fs.write_file(draft, "first draft".as_bytes(), .Replace) else |_| {
        return .Ok(1)
    }
    remove_and_report("draft.txt")?
    remove_and_report("draft.txt")?
    .Ok(0)
}
```

```
removed draft.txt
could not remove draft.txt: NotFound
```

The second call finds nothing to remove, and the `ENOENT` that `unlink` left
in `errno` arrives as the category `NotFound`. In Rust the same wrapper reads
`std::io::Error::last_os_error()` right after the call, which works only if
nothing runs in between; here the declaration reads it before anything else
can run.

## Linking a library: SQLite

A library the system or Nix provides is named under `"link"`: `"sqlite3"`
links `libsqlite3`, as `-lsqlite3` would. Linea's development shell provides
SQLite, and its header, through Nix.

C libraries report failure with result codes, and the wrapper turns them into
`Result`s. SQLite answers `0` for success, `100` when a row is ready and `101`
when a statement has finished; anything else is an error code, which
`sqlite3_errmsg` explains in words.

Some C interfaces need a value a Linea declaration cannot spell.
`sqlite3_bind_text` takes `SQLITE_TRANSIENT`, a function pointer cast from
`-1`, to say "copy this text now". A three-line C shim in `"native"` passes it:

`guests/linea.json`:

```json
{ "extern": ["sqlite"], "native": ["sqlite/bind.c"], "link": ["sqlite3"] }
```

`guests/sqlite/bind.c`:

```c
#include <sqlite3.h>
#include <stdint.h>

int32_t sqlite_shim_bind_text(sqlite3_stmt *statement, int32_t index, const char *text, int32_t length) {
    return sqlite3_bind_text(statement, index, text, length, SQLITE_TRANSIENT);
}
```

`guests/sqlite/sqlite.lin`:

```linea
import std.ffi

@(opaque, linear)
type DatabaseHandle = UInt64

@(opaque, linear)
type StatementHandle = UInt64

extern fn sqlite3_open_v2(filename: ffi.CText, inout database: UInt64, flags: Int32, vfs: UInt64) -> Int32

// `close_v2` always releases the connection, even while a statement is open.
extern fn sqlite3_close_v2(sink database: DatabaseHandle) -> Int32

extern fn sqlite3_errmsg(read database: DatabaseHandle) -> ffi.CText where borrows(database)

extern fn sqlite3_prepare_v2(database: DatabaseHandle, sql: ffi.Bytes, length: Int32, inout statement: UInt64, tail: UInt64) -> Int32

extern fn sqlite_shim_bind_text(statement: StatementHandle, index: Int32, text: ffi.Bytes, length: Int32) -> Int32

extern fn sqlite3_step(statement: StatementHandle) -> Int32

extern fn sqlite3_column_text(read statement: StatementHandle, column: Int32) -> ffi.CText where borrows(statement)

extern fn sqlite3_finalize(sink statement: StatementHandle) -> Int32

let ok: Int32 = 0

let row: Int32 = 100

let done: Int32 = 101

let read_write_create: Int32 = 6

let out_of_memory: Int32 = 7

// A result code SQLite refused with.
@copyable
pub struct Error {
    code: Int32,
}

// Copy C's text out, or empty text when it is not UTF-8.
fn copied(text: ffi.CText) -> String {
    match text.to_owned() {
        Ok(owned) => owned,
        Err(_) => String.new(),
    }
}

@(opaque, linear)
struct Database { handle: DatabaseHandle }

@(opaque, linear)
struct Statement { handle: StatementHandle }

impl Database {
    pub fn open(path: Str) -> Result[Database, Error] {
        let filename = ffi.CString.open(path) else |_| {
            return .Err(.{ code = out_of_memory })
        }
        var address: UInt64 = 0
        let code = sqlite3_open_v2(filename.text(), &address, read_write_create, 0)
        filename.release()
        if address == 0 {
            return .Err(.{ code = out_of_memory })
        }
        // SQLite hands back a connection even when it fails to open one, and
        // that connection must be closed too.
        let database = Database { handle = DatabaseHandle(address) }
        if code != ok {
            database.close()
            return .Err(.{ code = code })
        }
        .Ok(database)
    }

    // What SQLite said about the last call on this connection that failed.
    pub fn message(self: Self) -> String {
        copied(sqlite3_errmsg(self.handle))
    }

    // Preparing changes the connection's error state, which `message` reads,
    // so it takes the connection `inout`.
    pub fn prepare(inout self: Self, sql: Str) -> Result[Statement, Error] {
        var address: UInt64 = 0
        let code = sqlite3_prepare_v2(self.handle, ffi.bytes(sql), Int32(sql.length()), &address, 0)
        if code != ok {
            if address != 0 {
                let _finalized = sqlite3_finalize(StatementHandle(address))
            }
            return .Err(.{ code = code })
        }
        .Ok(.{ handle = StatementHandle(address) })
    }

    pub fn close(sink self: Self) {
        let Database { handle: handle } = self
        let _closed = sqlite3_close_v2(handle)
    }
}

impl Release for Database {
    fn release(sink self: Self) {
        self.close()
    }
}

impl Statement {
    pub fn bind_text(inout self: Self, index: Int32, text: Str) -> Result[(), Error] {
        let code = sqlite_shim_bind_text(self.handle, index, ffi.bytes(text), Int32(text.length()))
        if code != ok {
            return .Err(.{ code = code })
        }
        .Ok(())
    }

    // Advance to the next row: true when one is ready, false when there are
    // no more.
    pub fn step(inout self: Self) -> Result[Bool, Error] {
        let code = sqlite3_step(self.handle)
        if code == row {
            return .Ok(true)
        }
        if code == done {
            return .Ok(false)
        }
        .Err(.{ code = code })
    }

    pub fn text(self: Self, column: Int32) -> String {
        copied(sqlite3_column_text(self.handle, column))
    }

    pub fn finish(sink self: Self) {
        let Statement { handle: handle } = self
        let _finalized = sqlite3_finalize(handle)
    }
}

impl Release for Statement {
    fn release(sink self: Self) {
        self.finish()
    }
}
```

`guests/main.lin`:

```linea
import std.io
import sqlite

use sqlite.Database
use sqlite.Error

fn run(inout database: Database, sql: Str) -> Result[(), Error] {
    defer var statement = &database.prepare(sql)?
    let _row = &statement.step()?
    .Ok(())
}

fn add(inout database: Database, name: Str) -> Result[(), Error] {
    defer var insert = &database.prepare("INSERT INTO guests VALUES (?1)")?
    &insert.bind_text(1, name)?
    let _row = &insert.step()?
    .Ok(())
}

fn main() -> Result[UInt8, io.IoError] {
    defer var database = Database.open(":memory:") else |_| {
        return .Ok(1)
    }
    let _created = run(&database, "CREATE TABLE guests (name TEXT)") else |_| {
        return .Ok(2)
    }
    let _first = add(&database, "Grace") else |_| {
        return .Ok(3)
    }
    let _second = add(&database, "Ada") else |_| {
        return .Ok(4)
    }
    defer var names = &database.prepare("SELECT name FROM guests ORDER BY name") else |_| {
        return .Ok(5)
    }
    while true {
        let more = &names.step() else |_| {
            return .Ok(6)
        }
        if !more {
            break
        }
        defer let name = names.text(0)
        io.println("{name}")?
    }
    match &database.prepare("SELEC name FROM guests") {
        Ok(statement) => statement.finish(),
        Err(failure) => {
            defer let said = database.message()
            io.println("SQLite refused code {failure.code}: {said}")?
        },
    }
    .Ok(0)
}
```

```
Ada
Grace
SQLite refused code 1: near "SELEC": syntax error
```

Nothing in `main` can misuse SQLite: it never sees a pointer, every
connection and statement it opens is linear or released by `defer`, and every
error is a value it must handle.

## Callbacks: C calling Linea

Some C functions call back into your code: `qsort` calls a comparison,
`sqlite3_exec` calls a function once per row. In C such a callback usually
takes a `void *` that carries your state between calls.

In Linea a callback parameter is a plain `fn` type. Its first parameter may be
an `inout` context, which the `extern` also takes as an `inout` parameter of
the same type: C receives the context's address as its `void *`, and hands it
back to every call. Every other parameter, and the result, crosses the
boundary like any other value:

`squares/linea.json`:

```json
{ "extern": ["visits"], "native": ["visits/visits.c"] }
```

`squares/visits/visits.c`:

```c
#include <stdint.h>

/* Calls `visit` with each square from 1 to `count` squared, and stops early
 * when `visit` answers nonzero. Answers how many squares it visited. */
int32_t squares_visit(int32_t count, int32_t (*visit)(void *context, int32_t square), void *context) {
    int32_t visited = 0;
    for (int32_t i = 1; i <= count; i++) {
        visited++;
        if (visit(context, i * i) != 0) break;
    }
    return visited;
}
```

`squares/visits/visits.lin`:

```linea
// What the callback keeps between calls.
struct Tally {
    total: Int64,
    limit: Int64,
}

extern fn squares_visit(count: Int32, visit: fn(inout tally: Tally, square: Int32) -> Int32, inout tally: Tally) -> Int32

// Add a square to the total, and ask C to stop once it passes the limit.
fn add_square(inout tally: Tally, square: Int32) -> Int32 {
    tally.total += Int64(square)
    if tally.total > tally.limit {
        1
    } else {
        0
    }
}

pub fn sum_past(limit: Int64) -> (Int64, Int32) {
    var tally = Tally { total = 0, limit = limit }
    let visited = squares_visit(100, add_square, &tally)
    (tally.total, visited)
}

// A lambda that captures nothing is one fixed function, so C can call it too.
pub fn count_squares(count: Int32) -> Int64 {
    var tally = Tally { total = 0, limit = 1000000 }
    let _visited = squares_visit(
        count,
        |inout counted: Tally, _square: Int32| -> Int32 {
            counted.total += 1
            0
        },
        &tally,
    )
    tally.total
}
```

`squares/main.lin`:

```linea
import std.io
import visits

fn main() -> Result[UInt8, io.IoError] {
    let (total, visited) = visits.sum_past(50)
    let counted = visits.count_squares(7)
    io.println("{visited} squares sum to {total}; a lambda counted {counted}")?
    .Ok(0)
}
```

```
5 squares sum to 55; a lambda counted 7
```

C calls the callback through an entry the compiler writes for one fixed
function, so the argument must name a function, or be a lambda that captures
nothing. A function value whose target is known only when the program runs is
refused: put the state the function needs in the context instead.

`anywhere/linea.json`:

```json
{ "extern": ["visits"], "native": ["visits/visits.c"] }
```

`anywhere/visits/visits.c`:

```c
#include <stdint.h>

int32_t squares_visit(int32_t count, int32_t (*visit)(void *context, int32_t square), void *context) {
    int32_t visited = 0;
    for (int32_t i = 1; i <= count; i++) {
        visited++;
        if (visit(context, i * i) != 0) break;
    }
    return visited;
}
```

`anywhere/visits/visits.lin`:

```linea
pub struct Tally {
    total: Int64,
}

extern fn squares_visit(count: Int32, visit: fn(inout tally: Tally, square: Int32) -> Int32, inout tally: Tally) -> Int32

// `visit` could be any function at all, so there is no one entry C could be
// handed for it.
pub fn sum_with(visit: fn(inout tally: Tally, square: Int32) -> Int32) -> Int64 {
    var tally = Tally { total = 0 }
    let _visited = squares_visit(3, visit, &tally)
    tally.total
}
```

`anywhere/main.lin`:

```linea
import visits

fn main() -> UInt8 {
    UInt8(visits.sum_with(|inout tally: visits.Tally, square: Int32| -> Int32 {
        tally.total += Int64(square)
        0
    }))
}
```

```
error[T-ExternCallback]: C calls a callback through an entry made for one function, and this value has none fixed
  --> anywhere/visits/visits.lin:11:37
   |
11 |     let _visited = squares_visit(3, visit, &tally)
   |                                     ^^^^^ pass a function by name, or a lambda that captures nothing
```

### A list of C strings: `ffi.CTextList`

`sqlite3_exec` runs SQL and calls a function once per result row, passing the
row's values and column names as two C arrays of strings, `char **`, with
their length. A callback takes each as an `ffi.CTextList` and reads entry `i`
with `get(i, count:)`, an `ffi.CText`. Reading past the count C gave stops the
program rather than reading past the array. The values live only during the
call, so the callback copies them out:

`rows/linea.json`:

```json
{ "extern": ["sqlite"], "link": ["sqlite3"] }
```

`rows/sqlite/sqlite.lin`:

```linea
import std.ffi

@(opaque, linear)
type DatabaseHandle = UInt64

extern fn sqlite3_open_v2(filename: ffi.CText, inout database: UInt64, flags: Int32, vfs: UInt64) -> Int32

extern fn sqlite3_close_v2(sink database: DatabaseHandle) -> Int32

// What the row callback keeps between rows.
struct Rows {
    lines: String,
}

// The last parameter is SQLite's `char **errmsg`, here a null pointer.
extern fn sqlite3_exec(database: DatabaseHandle, sql: ffi.CText, row: fn(inout rows: Rows, count: Int32, values: ffi.CTextList, names: ffi.CTextList) -> Int32, inout rows: Rows, message: UInt64) -> Int32

let ok: Int32 = 0

let read_write_create: Int32 = 6

// Append `name=value` for each column of a row, and a line break after it.
fn collect(inout rows: Rows, count: Int32, values: ffi.CTextList, names: ffi.CTextList) -> Int32 {
    let columns = UInt64(count)
    for column in 0..columns {
        match names.get(column, count: columns).to_owned() {
            Ok(text) => {
                let _appended = &rows.lines.append(text.view())
                text.release()
            },
            Err(_) => {},
        }
        let _equals = &rows.lines.append("=")
        match values.get(column, count: columns).to_owned() {
            Ok(text) => {
                let _appended = &rows.lines.append(text.view())
                text.release()
            },
            Err(_) => {},
        }
        let _space = &rows.lines.append(if column + 1 == columns { "\n" } else { " " })
    }
    0
}

// A connection to an in-memory database. It must be closed.
@(opaque, linear)
struct Database { handle: DatabaseHandle }

impl Database {
    pub fn open() -> Result[Database, Int32] {
        let path = ffi.CString.open(":memory:") else |_| {
            return .Err(7)
        }
        var address: UInt64 = 0
        let opened = sqlite3_open_v2(path.text(), &address, read_write_create, 0)
        path.release()
        if address == 0 {
            return .Err(7)
        }
        let database = Database { handle = DatabaseHandle(address) }
        if opened != ok {
            database.close()
            return .Err(opened)
        }
        .Ok(database)
    }

    // Run `sql`, one line per row it produced, or the code SQLite refused
    // with. Running statements changes the database, so it is lent `inout`.
    pub fn rows_of(inout self: Self, sql: Str) -> Result[String, Int32] {
        let statements = ffi.CString.open(sql) else |_| {
            return .Err(7)
        }
        var rows = Rows { lines = String.new() }
        let ran = sqlite3_exec(self.handle, statements.text(), collect, &rows, 0)
        statements.release()
        let Rows { lines: lines } = rows
        if ran != ok {
            lines.release()
            return .Err(ran)
        }
        .Ok(lines)
    }

    pub fn close(sink self: Self) {
        let Database { handle: handle } = self
        let _closed = sqlite3_close_v2(handle)
    }
}
```

`rows/main.lin`:

```linea
import std.io
import sqlite

use sqlite.Database

fn main() -> Result[UInt8, io.IoError] {
    let sql = "CREATE TABLE guests (name TEXT, visits INTEGER); INSERT INTO guests VALUES ('Grace', 3), ('Ada', 1); SELECT name, visits FROM guests ORDER BY visits;"
    var database = Database.open() else |_| {
        return .Ok(1)
    }
    let rows = &database.rows_of(sql)
    database.close()
    defer let lines = rows else |_| {
        return .Ok(2)
    }
    io.print(lines.view())?
    .Ok(0)
}
```

```
name=Ada visits=1
name=Grace visits=3
```

## What the compiler believes

A wrapper module is the one place a mistake becomes undefined behaviour,
because the compiler cannot check C. When you write one, check each of these
against the C library's documentation:

1. Each `extern` matches its C prototype: the same number of parameters, the
   same width and signedness, a value or a pointer (`inout`) in the same
   places, and the same result. A handle C takes by value is a plain
   parameter, never `inout`.
2. Conventions tell the truth about ownership. `sink` means C frees or keeps
   the object on every return; a plain parameter means C only uses it during
   the call.
3. C keeps no pointer into Linea memory after the call returns: not a
   `Bytes`, not a `CText` from a `CString`, not a context.
4. A `CText` answer whose text lives inside a C object says so with
   `borrows`, and an `extern` marks its handle `read` only where C truly only
   reads the object. The compiler believes the marker: a `read` written on a
   function that changes or frees the object lets text read from it before
   the call be read after, which is a read of freed memory. Without `read`,
   the compiler treats the call as changing the handle's place, as it treats
   an `inout` argument.
5. C calls a callback only during the call that passed it.
6. Every length you pass to C, or to `copy_bytes`, is the length of the
   memory it describes.

The compiler holds the rest: an `extern` is private to its module, an
`extern` answering a `CText` states what it points into, a module that is not
trusted can neither declare C nor read a `std.ffi` value, and every borrow a
declaration states is checked like any other. Keep the wrapper small and keep
these checks next to the declarations, and the rest of the program gets
Linea's guarantees about C as it does about everything else.
