# A guest book

The chapters so far have introduced Linea's parts one at a time: linear values
that must be settled, modules and manifests, HTTP handlers and extractors,
files embedded with `embed`, and libraries that wrap C. The
[guest book](../../examples/guest-book/) in `examples/guest-book/` puts all of
them together into one small web application.

## What it does

Visitors read the fifty newest signatures on `GET /` and add their own with
`POST /sign`. Each signature is stored in a SQLite database file, the visitor's
name is remembered in a cookie for next time, and every piece of text a visitor
supplied is HTML-escaped when the page is rendered.

The project sits in `examples/guest-book/`:

<!-- guide: unchecked a directory listing, not program output -->
```text
examples/guest-book/
├── linea.json
├── main.lin
├── schema.sql
├── book/
│   └── book.lin
├── page/
│   └── page.lin
├── store/
│   └── store.lin
├── sqlite/
│   ├── linea.json
│   ├── shim.c
│   └── sqlite.lin
└── templates/
    ├── entry.html
    └── page.html
```

It is split into five layers:

- `sqlite/` is a standalone library project that wraps SQLite's C API in linear
  `Database` and `Statement` handles and a value error `sqlite.Error`.
- `book/book.lin` is the application's storage module: it embeds `schema.sql`,
  opens the guest book, inserts signatures, and reads the newest entries.
- `page/page.lin` embeds the HTML templates and streams `Page` through
  `Display`, escaping untrusted text while expanding the entry list in a single
  pass.
- `store/store.lin` confines database creation, queries and closure to a system-thread owner and lends restricted clients to HTTP fibers.
- `main.lin` gives each serving fiber a client of that owner, checks
  and records signatures, and serves the router on a loopback TCP port.

## The library trusted with C

Only `examples/guest-book/sqlite/` talks to C. Its manifest in
`examples/guest-book/sqlite/linea.json` declares a library named `sqlite`,
grants `extern` to its root module, compiles `shim.c` beside it, and links the
system's `libsqlite3`:

```json
{
    "kind": "library",
    "name": "sqlite",
    "extern": ["."],
    "native": ["shim.c"],
    "link": ["sqlite3"]
}
```

The application's own manifest in `examples/guest-book/linea.json` grants no
module `extern`. Instead, it depends on `sqlite` and writes `"extern": true` on
that dependency to consent to the C declarations inside the library:

```json
{
    "dependencies": {
        "sqlite": { "path": "sqlite", "extern": true }
    }
}
```

If an application leaves `"extern": true` out of its dependency entry, the
compiler refuses the manifest before compiling any source:

<!-- guide: unchecked diagnostic shown for a manifest without extern consent -->
```text
error[M-Dependency]: the manifest of `sqlite` grants it `extern`, and this entry does not consent to it
 --> app/linea.json:1:21
  |
1 | { "dependencies": { "sqlite": { "path": "$LINEA_ROOT/examples/guest-book ...
  |                     ^^^^^^^^ write `"extern": true` in this entry to trust the signatures it declares
```

Two small helpers in `examples/guest-book/sqlite/shim.c` bridge C idioms that
do not cross an `extern fn` signature directly: `SQLITE_TRANSIENT` is `(void
(*)(void *))-1`, a sentinel function pointer that asks SQLite to copy bound
text before returning; and `sqlite3_prepare_v2` reports uncompiled trailing SQL
through a `const char **` tail pointer, which the shim turns into a byte count.

Inside `examples/guest-book/sqlite/sqlite.lin`, the C pointers `sqlite3 *` and
`sqlite3_stmt *` are wrapped in `@(opaque, linear)` handle types and private
`extern fn` declarations:

<!-- guide: excerpt examples/guest-book/sqlite/sqlite.lin -->
```linea
// A `sqlite3 *` connection pointer C allocated. `@opaque` keeps the address
// inside this module, and `@linear` makes every connection reach
// `sqlite3_close_v2`. A handle is not `Shareable`, and this one is not marked
// `@shareable`: SQLite rewrites a connection's error message on every call,
// so two threads reading one connection would race on it. A program keeps its
// `Database` in one task, or in an owning task its other tasks call.
@(opaque, linear)
type DatabaseHandle = UInt64

// A `sqlite3_stmt *` statement pointer C allocated. Every prepared statement
// must reach `sqlite3_finalize`.
@(opaque, linear)
type StatementHandle = UInt64

// `sqlite3_open_v2` writes the new `sqlite3 *` into `database` even when
// opening fails, so the address arrives as a `UInt64` and is wrapped in
// `DatabaseHandle` once checked against zero.
extern fn sqlite3_open_v2(filename: ffi.CText, inout database: UInt64, flags: Int32, vfs: UInt64) -> Int32

// `sink` hands the connection handle to C for good. `sqlite3_close_v2` closes
// the connection, or marks it to close as soon as its last statement finishes.
extern fn sqlite3_close_v2(sink database: DatabaseHandle) -> Int32

// `read` promises C only reads the connection, and `where borrows(database)`
// ties the returned `CText` to the connection's lifetime. SQLite rewrites the
// sentence on the next call on the connection, so `message` copies it at once.
extern fn sqlite3_errmsg(read database: DatabaseHandle) -> ffi.CText where borrows(database)
```

Callers outside `sqlite` see only `Database` and `Statement`, which wrap those
handles in `@(opaque, linear)` structs in `examples/guest-book/sqlite/sqlite.lin`:

<!-- guide: excerpt examples/guest-book/sqlite/sqlite.lin -->
```linea
// A connection to a SQLite database file, or to one in memory. It must be
// closed.
@(opaque, linear)
struct Database {
    handle: DatabaseHandle,
}

// One compiled SQL statement, stepped a row at a time. It must be finished.
// `database` observes the connection the statement was prepared on, so while
// the statement is open the connection cannot be closed or released, or passed
// to `execute` or `wait_when_busy`.
@(opaque, linear)
struct Statement {
    handle: StatementHandle,
    database: borrow Database,
}
```

`Database.prepare` takes the database as `read` and returns the statement
`where borrows(.Ok: self)`, so `database: borrow Database` holds the connection
in place until the statement finishes. Several statements may be open on one
database at once, as SQLite allows, and a statement reads its connection's error
sentence and error code through that field. Closing the database while a
statement is still open is refused at compile time:

<!-- guide: unchecked diagnostic from tests/cmd/guest_book/a_statement_keeps_its_database_open.cmd -->
```text
error[O-Borrow]: this operation invalidates a place that a later observation still needs
 --> app/main.lin:8:5
  |
8 |     database.close()
  |     ^^^^^^^^ keep this place available until the last use of its observation
9 |     statement.finish()
  |     --------- the observation is still used here
```

Because the compiler refuses that program, `Database.close` never meets an
unfinished statement, `sqlite3_close_v2` closes the connection at once, and
`close` cannot fail. Rust's `rusqlite` reaches the same guarantee with a
lifetime: `Statement<'conn>` borrows `Connection`. It finalizes the statement
in `Drop`, which silently ignores any error from `sqlite3_finalize`. In Linea,
`Statement` is linear, so the compiler also refuses any path that forgets to
settle one:

<!-- guide: unchecked diagnostic from tests/cmd/guest_book/a_forgotten_statement_is_refused.cmd -->
```text
error[O-Leak]: `_statement` (a linear `sqlite.Statement`) is still owned when this path leaves
 --> app/main.lin:6:9
  |
6 |     let _statement = db.prepare("SELECT COUNT(*) FROM entries")?
  |         ^^^^^^^^^^ never settled on the path that reaches the end of this block
8 | }
  | - the block ends here
  |
  = help: settle it first with `_statement.release()` or `_statement.finish()`
```

Because `Statement` also implements `Release` by calling `finish`, a caller in
`examples/guest-book/book/book.lin` can write `defer var insert` or `defer var
select` and let the statement finish on every return path, including early `?`
returns, while `defer let` in `read_entry` and `defer var entries` in `newest`
release partial row or vector allocations if a later step fails:

<!-- guide: excerpt examples/guest-book/book/book.lin -->
```linea
// Read one row's three columns into an `Entry`. `defer let` releases `name` or
// `message` if reading a later column fails, and skips that release when all
// three move into the returned `Entry`. Out-of-range timestamps return
// `BookError.InvalidTimestamp` rather than fabricating a current time.
fn read_entry(select: Statement) -> Result[Entry, BookError] {
    defer let name = select.text(0)?
    defer let message = select.text(1)?
    let seconds = select.integer(2)?
    let signed = time.Timestamp.from_unix(seconds, 0) else {
        return .Err(.InvalidTimestamp(seconds))
    }
    .Ok(Entry { name, message, signed })
}
```

and in `Book.newest`:

<!-- guide: excerpt examples/guest-book/book/book.lin -->
```linea
    // Read up to `limit` entries, newest first. `defer var select` finishes the
    // statement when `newest` returns, and `defer var entries` releases any
    // entries already read if a later row or push fails; `.Ok(entries)` moves
    // the completed vector to the caller.
    pub fn newest(inout self: Self, limit: Int64) -> Result[Vec[Entry], BookError] {
        if limit < 0 {
            return .Err(.NegativeLimit(limit))
        }
        defer var select = self.database.prepare("SELECT name, message, signed_at FROM entries ORDER BY id DESC LIMIT ?1")?
        &select.bind_integer(1, limit)?
        defer var entries: Vec[Entry] = Vec.new()
        while &select.step()? {
            let entry = read_entry(select)?
            &entries.push(entry).settled().map_err(|sink _| BookError.OutOfMemory)?
        }
        .Ok(entries)
    }
```

## Errors as values

When SQLite refuses an operation, `sqlite3_errmsg` points into memory owned by
the connection. `sqlite.Error` copies that sentence into an owned `String` as
soon as the failure happens, in `examples/guest-book/sqlite/sqlite.lin`, so the
error value outlives the statement and connection:

<!-- guide: excerpt examples/guest-book/sqlite/sqlite.lin -->
```linea
// Why SQLite, or this wrapper, refused an operation. `Refused` carries a
// `String` copied from `sqlite3_errmsg` when the failure happened, so the
// sentence outlives the connection or statement that produced it.
@derive(Debug, Release)
pub enum Error {
    Refused(Int32, String[mem.SystemAllocator]),
    NullColumn(UInt32),
    NotUtf8(UInt32),
    InteriorNul(UInt64),
    TooLong,
    InvalidParameter(UInt32),
    InvalidColumn(UInt32),
    OutOfMemory,
    TrailingSql,
    EmptySql,
    SingleThreaded,
    InvalidName,
}
```

In `examples/guest-book/main.lin`, `unavailable` logs the error to
standard error (which the terminal running the server shows), releases the
`BookError`, and answers the visitor with a generic `500 Internal Server
Error`:

<!-- guide: excerpt examples/guest-book/main.lin -->
```linea
// Log the storage error to standard error, which the terminal running the
// server shows, and answer the visitor with a generic 500 message.
fn unavailable(request: http.Request, sink error: BookError) -> http.Error {
    io.eprintln("guest-book: {error}")
    error.release()
    http.error(request, .InternalServerError, "the guest book is unavailable")
}
```

## The schema and the templates, embedded

A server is easiest to deploy when it is a single file with no external
assets to locate at run time. `examples/guest-book/book/book.lin` embeds
`schema.sql` into the executable with `embed` and runs it when opening the
book:

<!-- guide: excerpt examples/guest-book/book/book.lin -->
```linea
// `embed` reads `schema.sql` at compile time and keeps its text in the binary,
// so deploying the program copies one executable and no SQL file beside it.
let schema = embed("../schema.sql")
```

Because `examples/guest-book/schema.sql` uses `CREATE TABLE IF NOT EXISTS`,
running it creates the table on the first run and is a no-op thereafter:

```sql
CREATE TABLE IF NOT EXISTS entries (
    id INTEGER PRIMARY KEY,
    name TEXT NOT NULL,
    message TEXT NOT NULL,
    signed_at INTEGER NOT NULL DEFAULT (unixepoch())
);
```

In `examples/guest-book/page/page.lin`, the HTML templates `templates/page.html`
and `templates/entry.html` are embedded the same way. Placeholders are written
`{{name}}` with double braces so the CSS rules in `page.html` keep their single
braces. Each field passed to `fill` is tagged as `Text`, `Timestamp`, or `Entries`,
and `Page` implements `Display` so `http.html(request, Page { ... })` streams
the entire page and all entries in a single pass:

<!-- guide: excerpt examples/guest-book/page/page.lin -->
```linea
// What replaces a `{{field}}` placeholder in a template:
// - `Text` is text a visitor wrote, a cookie, or a SQLite column; `fill` writes
//   it through `html.escape`, so `<`, `>`, `&`, `"` and `'` become entities.
// - `Timestamp` is a UTC timestamp, formatted directly as RFC 3339.
// - `Entries` is the slice of guest-book signatures; `fill` expands each row
//   through `entry_template` directly into the writer, with every column
//   escaped as `Text` or written as `Timestamp`.
@(copyable, derive(Debug))
enum Value {
    Text(Str),
    Timestamp(time.Timestamp),
    Entries(Slice[Entry]),
}

@(copyable, derive(Debug))
struct Field {
    name: Str,
    value: Value,
}

// Copy `form` to `w`, replacing each `{{name}}` with the first matching field in
// `fields`. Unknown placeholders (`{{unknown}}`) and unclosed delimiters (`{{unclosed`)
// are intentionally preserved as literal text. A test checks that filling each production
// template leaves no `{{` behind.
fn fill[W: Writer](inout w: W, form: Str, fields: [Field; 3]) -> Result[(), W.Error] where carries(.Err: w) {
    var rest = copy(form)
    loop {
        let (before, opened) = rest.split_once(r"{{") else {
            break
        }
        &w.write_str(before)?
        let (name, after) = opened.split_once(r"}}") else {
            &w.write_str(r"{{")?
            rest = opened
            continue
        }
        var found = false
        for read field in fields {
            if field.name == name {
                found = true
                match read field.value {
                    Text(text) => html.escape(&w, text)?,
                    Timestamp(stamp) => stamp.fmt(&w)?,
                    Entries(entries) => for read entry in entries {
                        fill(
                            &w,
                            entry_template,
                            [
                                Field { name = "name", value = .Text(entry.name.view()) },
                                Field { name = "signed", value = .Timestamp(copy(entry.signed)) },
                                Field { name = "message", value = .Text(entry.message.view()) },
                            ],
                        )?
                    },
                }
                break
            }
        }
        if !found {
            &w.write_str(r"{{")?
            &w.write_str(name)?
            &w.write_str(r"}}")?
        }
        rest = after
    }
    &w.write_str(rest)
}
```

The test of `fill` follows it in the file. After the test comes the page
itself:

<!-- guide: excerpt examples/guest-book/page/page.lin -->
```linea
// The complete guest-book page, streamed directly into `http.html` through
// `Display` without building an intermediate `entries` string.
@(copyable, derive(Debug))
pub struct Page {
    action: Str,
    name: Str,
    entries: Slice[Entry],
}

impl Display for Page {
    fn fmt[W: Writer](self: Self, inout w: W) -> Result[(), W.Error] {
        fill(
            &w,
            page_template,
            [
                Field { name = "action", value = .Text(copy(self.action)) },
                Field { name = "name", value = .Text(copy(self.name)) },
                Field { name = "entries", value = .Entries(copy(self.entries)) },
            ],
        )
    }
}
```

Every visitor string — the name, the message, the timestamp read from SQLite,
and the remembered `name` cookie — reaches `fill` as `Text`, so `html.escape`
escapes it.

## One system-thread database owner

HTTP connections wait independently, so the server runs its serving tasks as
fibers on two carriers. SQLite operations can block an OS thread. Running those
operations directly in an HTTP fiber would occupy its carrier while the database
waited for a lock or storage.

The application keeps one database connection in a dedicated system-thread
owner instead. `Store` owns that task; its restricted `Client` only exposes
`sign` and `newest`. A client cannot extract the native connection or submit an
arbitrary owner job:

<!-- guide: excerpt examples/guest-book/store/store.lin -->
```linea
// One system task owns the database for the server's lifetime. Clients only
// submit the operations below; none can extract a connection or submit SQL.
@(opaque, linear)
struct Store {
    owner: task.Owner[Option[Book]],
}

@(opaque, copyable)
struct Client {
    raw: task.Client[Option[Book]],
}
```
Every HTTP task holds a copy of this client. Copies borrow the same `Store`,
so the program must finish their users before closing the owner. They do not
inherit the database's thread affinity. `Ctx` also keeps the proxy policy the
request handlers use:

<!-- guide: excerpt examples/guest-book/main.lin -->
```linea
// Each serving task lends a restricted database client and its proxy policy
// to handlers. The client borrows the Store, so serving must join before the
// database owner can close. SQLite operations run on the owner's OS thread.
@derive(Release)
struct Ctx {
    book: store.Client,
    proxy_trust: http.ProxyTrust,
}
```
A route receives owned entry strings from the database task. It can render them
or wait on a socket without holding the database connection:

<!-- guide: excerpt examples/guest-book/main.lin -->
```linea
fn home(inout ctx: Ctx, request: http.Request, inout _incoming: http.RequestBody) -> Result[http.Response, http.Error] where carries(request), borrows(_incoming), retains(_incoming: _incoming) {
    defer let entries = match ctx.book.newest(newest_shown) {
        Ok(entries) => entries,
        Err(error) => return .Err(unavailable(request, error)),
    }
```
### Creating and closing on the owner thread

Moving a connection into a task after opening it elsewhere does not establish
thread confinement. `open_store` starts with `Option[Book].None` on `io.system()`
and creates the actual connection in an owner job. Startup errors retain their
SQLite detail or the task preparation error. An unsuccessful database open leaves
an empty owner, which is closed before returning the error:

<!-- guide: excerpt examples/guest-book/store/store.lin -->
```linea
fn open_store(name: Str, memory: Bool) -> Result[Store, OpenError] {
    let owned_name = name.to_owned() else |_| {
        return .Err(.Book(.OutOfMemory))
    }
    let initial: Option[Book] = .None
    let owner = task.own(initial, on: io.system()) else |failure| {
        let Unowned { state, reason } = failure
        empty(state)
        owned_name.release()
        return .Err(.Task(reason))
    }
    let opened: Result[(), BookError] = owner.client().call(
        [sink owned_name, sink memory] |inout state: Option[Book]| {
            let connected = if memory {
                Book.open_in_memory(owned_name.view())
            } else {
                Book.initialize(owned_name.view()).and_then([owned_name] |sink _initialized| Book.connect(owned_name.view()))
            }
            match connected {
                Ok(book) => {
                    restore(&state, book)
                    .Ok(())
                },
                Err(error) => .Err(error),
            }
        },
    )
    match opened {
        Ok(_) => .Ok(Store { owner }),
        Err(error) => {
            empty(owner.close())
            .Err(.Book(error))
        },
    }
}
```
The owner state is linear. `exchange` moves the old option out and installs its
replacement while preserving both values' dependency contracts. Even an old
`None` is explicitly matched because `Option[Book]` must be settled:

<!-- guide: excerpt examples/guest-book/store/store.lin -->
```linea
// Preserve the previous value's dependencies while replacing the whole
// linear option. Even an empty option must be matched and settled.
fn exchange(inout slot: Option[Book], sink next: Option[Book]) -> Option[Book] where carries(slot), retains(slot: next) {
    let previous = slot
    slot = next
    previous
}
```
Shutdown requires the clients' users to have finished. The final owner job closes
SQLite on that same system thread; only the empty state returns through
`Owner.close`. Releasing `Store` follows this path too:

<!-- guide: excerpt examples/guest-book/store/store.lin -->
```linea
impl Store {
    pub fn open(path: Str) -> Result[Store, OpenError] {
        open_store(path, memory: false)
    }

    pub fn in_memory(name: Str) -> Result[Store, OpenError] {
        open_store(name, memory: true)
    }

    pub fn client(self: Self) -> Client where borrows(self) {
        .{ raw = self.owner.client() }
    }

    // All client users must be joined before consuming the store. Closing
    // the connection is a final owner job; Owner.close only returns None.
    pub fn close(sink self: Self) {
        let Store { owner } = self
        owner.client().call(
            |inout state: Option[Book]| {
                match exchange(&state, .None) {
                    Some(book) => book.close(),
                    None => (),
                }
            },
        )
        empty(owner.close())
    }
}

impl Release for Store {
    fn release(sink self: Self) {
        self.close()
    }
}
```
### Sending owned requests

The form's `Str` values borrow request storage. An owner job must own what it
captures, so `Client.sign` copies the small name and message into its job. A failed
copy returns `BookError.OutOfMemory`. The owner releases the copied fields after
executing the job. Both operations restore the connection before returning their
result, including when SQLite reports an error:

<!-- guide: excerpt examples/guest-book/store/store.lin -->
```linea
impl Client {
    pub fn newest(self: Self, limit: Int64) -> Result[Vec[Entry], BookError] {
        self.raw.call(
            [sink limit] |inout state: Option[Book]| {
                var book = exchange(&state, .None).unwrap()
                let result = &book.newest(limit)
                restore(&state, book)
                result
            },
        )
    }

    // Request views cannot cross the owner boundary. Copy the small form
    // fields into the job; the owner releases those copies after the call.
    pub fn sign(self: Self, name: Str, message: Str) -> Result[(), BookError] {
        defer let owned_name = name.to_owned() else |_| {
            return .Err(.OutOfMemory)
        }
        let owned_message = message.to_owned() else |_| {
            return .Err(.OutOfMemory)
        }
        self.raw.call(
            [sink owned_name, sink owned_message] |inout state: Option[Book]| {
                var book = exchange(&state, .None).unwrap()
                let result = &book.sign(owned_name.view(), owned_message.view())
                restore(&state, book)
                result
            },
        )
    }
}
```
Calls run serially on this connection. This bounds the database resources and
avoids a native thread per HTTP worker; it does not promise parallel database
queries. A slow database call delays later database jobs, while unrelated HTTP
socket and timer fibers can continue. Applications needing parallel reads can
choose a measured, bounded set of database owners instead.

`Book.initialize` creates the table and enables write-ahead logging before the
owner opens its serving connection. `Book.connect` retains the existing two-second
busy timeout and `synchronous=NORMAL` setting. Other processes may still access
the database. The lower-level `book` tests exercise concurrent connections, while
`store` tests exercise restricted fiber clients and owner startup failure.

### When startup fails

Database startup happens before HTTP serving. An unavailable directory produces
SQLite's owned error message, then the server stops without accepting a client:

<!-- guide: unchecked output from tests/cmd/guest_book/refuses_what_it_should.cmd -->
```text
guest-book: unable to open database file (SQLite code 14)
```

Each HTTP worker then builds its own router around a borrowed client. Registering
a route can fail, so the factory returns a `Result`. The HTTP server accepts
nothing until all its handlers are ready and releases the others if one fails.
Factory errors cross task boundaries: they must be `Owned`, `Shareable`,
`Isolated` and `Release`. A borrowed `Str` error is refused:

`routes_from_a_file.lin`:

```linea
import std.http
import std.net

fn routes() -> Result[http.Router[()], Str] {
    .Err("the routes could not be read")
}

fn main() -> UInt8 {
    let _ = http.listen_and_serve(net.loopback(8080), routes) else |_| {
        return 1
    }
    0
}
```

```text
error[T-Bound]: `R.Error` requires `Owned`, and `Str` can carry a borrow: it holds a view of storage it does not own
   --> routes_from_a_file.lin:9:18
    |
9   |     let _ = http.listen_and_serve(net.loopback(8080), routes) else |_| {
    |                  ^^^^^^^^^^^^^^^^ `Str` is not `Owned`; pass a value whose type owns everything it holds
   ::: std/http/serve.lin
923 | ... ler: Handler[(), mem.SystemAllocator] + Observer + Release, R.Error: Owned + Shareable + Isolated + Release {
    |                                                                 ------- required by this `where` clause
```

An enum of its own reasons, declared `@derive(Release)` (and `Display`, so
`main` can print it), or an owned `String`, is accepted.

### Room for carriers and kept-alive connections

The server uses 128 serving fibers and permits 128 active-or-idle client
connections. They share two carriers and one database owner. A process still
needs a descriptor budget: each client socket can have a readiness duplicate,
and each carrier can hold its poller, wake descriptor and completion queue.

<!-- guide: excerpt examples/guest-book/main.lin -->
```linea
// HTTP fibers share one database connection on a dedicated system-thread owner.
let serving_tasks: UInt64 = 128

let serving_carriers: UInt64 = 2

// Active and idle clients share this connection budget. An idle client's
// readiness registration holds a duplicate of its socket descriptor.
let connection_budget: UInt64 = 128

let database_files: UInt64 = 2

// A Linux carrier can hold epoll, its wake event and an io_uring descriptor.
// The same allowance covers macOS's kqueue backend.
let files_per_carrier: UInt64 = 3

let files_per_connection: UInt64 = 2

// Standard streams take three descriptors; listener and watch take two;
// SQLite's shared-memory index takes one; the dispatcher and signal wake
// take a few more. Rounding up to 32 leaves room for inherited files,
// SQLite temporary files and differences between supported platforms.
let fixed_files: UInt64 = 32
```
| Use | Conservative allowance |
| --- | --- |
| One SQLite connection and its write-ahead log | 2 |
| 128 client sockets, with one readiness duplicate each | 256 |
| Two carriers, up to three descriptors each | 6 |
| Other runtime descriptors and spare room | 32 |
| Total | 296 |

`main` raises the process's soft limit toward its hard limit, then checks this
estimate before opening the database or the loop:

<!-- guide: excerpt examples/guest-book/main.lin -->
```linea
    // One database owner keeps its connection and write-ahead log open.
    // Client sockets and readiness registrations need two descriptors each.
    // SQLite can still need temporary files, so this is an admission estimate,
    // not a guarantee that every later query will succeed.
    let files_needed = database_files + connection_budget * files_per_connection + serving_carriers * files_per_carrier + fixed_files
    let open_files = process.raise_open_file_limit() else |error| {
        io.eprintln("guest-book: cannot raise the open-file limit: {error}")
        return 1
    }
    if open_files < files_needed {
        io.eprintln("guest-book: serving needs {files_needed} open files, and this process may open {open_files}; raise the hard limit with `ulimit -H -n`")
        return 1
    }
```
A hard limit below the estimate stops startup:

<!-- guide: unchecked output from tests/cmd/guest_book/serves_under_a_low_open_file_limit.cmd -->
```text
guest-book: serving needs 296 open files, and this process may open 200; raise the hard limit with `ulimit -H -n`
```

Only a program raises this process-wide limit; a library leaves the choice to
its caller. The estimate includes spare room, but inherited descriptors and
SQLite temporary files can still exhaust it. A later storage failure is logged
and answers the visitor with the generic 500 response.

## Signing

`POST /sign` extracts the URL-encoded form into `Signature` through
`http.Form[Signature]`. Before touching the database, `sign` in
`examples/guest-book/main.lin` checks `http.same_origin`, verifies that the
trimmed name and message fit the scalar limits, and refuses control characters
with `holds_disallowed_character`. A name is one line, so it may hold none; a
message comes from a `<textarea>`, so its line breaks and tabs are kept, and
the page shows them with `white-space: pre-wrap`. Bidirectional controls such
as U+202E, which would make a name display reversed, are refused in both. A
browser sends each line break as CRLF but its `maxlength` counts it once, so
`with_lf_line_breaks` turns every CRLF and lone CR into LF before the message
is counted and stored:

<!-- guide: excerpt examples/guest-book/main.lin -->
```linea
// Whether `text` holds a character that does not belong in a signature. A
// name is one line, so it holds no control character. A message comes from a
// `<textarea>`, whose tabs and line breaks are kept: `\t` and `\n` are allowed
// there, after `with_lf_line_breaks` has turned every CR into LF. Refused in
// both are the C0 controls below U+0020, DEL (U+007F), the C1 controls U+0080
// to U+009F, the line and paragraph separators U+2028 and U+2029, the
// bidirectional controls U+200E, U+200F, U+202A to U+202E and U+2066 to U+2069,
// which can make a name display reversed, and the byte order mark U+FEFF.
fn holds_disallowed_character(text: Str, keeps_line_breaks: Bool) -> Bool {
    for scalar in text.scalars() {
        let value = scalar.value
        if value < 32 {
            if !(keeps_line_breaks && (value == 9 || value == 10)) {
                return true
            }
        } else if value >= 127 && value <= 159 {
            return true
        } else if value == 8206 || value == 8207 || (value >= 8232 && value <= 8238) || (value >= 8294 && value <= 8297) || value == 65279 {
            return true
        }
    }
    false
}

// A browser sends each line break in a `<textarea>` as CRLF, and the form's
// `maxlength` counts it as one character. `with_lf_line_breaks` writes every
// CRLF, and every lone CR, as LF, so a message is counted and stored with one
// character per line break.
fn with_lf_line_breaks[A: Allocator](allocator: A, text: Str) -> Result[String[A], mem.Oom] where carries(.Ok: allocator) {
    defer var written = String.new_in(allocator)
    var start: UInt64 = 0
    var at: UInt64 = 0
    while at < text.length() {
        if text.byte(at).unwrap() == 13 {
            &written.append(text.slice(start, at).unwrap())?
            &written.append("\n")?
            at += 1
            if at < text.length() && text.byte(at).unwrap() == 10 {
                at += 1
            }
            start = at
        } else {
            at += 1
        }
    }
    &written.append(text.slice(start, text.length()).unwrap())?
    .Ok(written)
}
```

`sign` itself reads:

<!-- guide: excerpt examples/guest-book/main.lin -->
```linea
fn sign(inout ctx: Ctx, form: http.Form[Signature], request: http.Request) -> Result[http.Response, http.Error] {
    if !http.same_origin(request, trust: ctx.proxy_trust) {
        return .Err(http.error(request, .Forbidden, "a signature is accepted only from this guest book's own page"))
    }
    let name = form.value.name.trim_ascii()
    let message_text = with_lf_line_breaks(request.allocator(), form.value.message.trim_ascii())?
    let message = message_text.view()
    if name.length() == 0 || message.length() == 0 {
        return .Err(http.error(request, .UnprocessableContent, "a signature needs a name and a message"))
    }
    if name.scalars().count() > longest_name || message.scalars().count() > longest_message {
        return .Err(http.error(request, .UnprocessableContent, "a name holds at most {longest_name} characters and a message {longest_message}"))
    }
    if holds_disallowed_character(name, keeps_line_breaks: false) || holds_disallowed_character(message, keeps_line_breaks: true) {
        return .Err(http.error(request, .UnprocessableContent, "a name holds no control characters, and a message only line breaks and tabs"))
    }
    let _ = ctx.book.sign(name, message) else |error| {
        return .Err(unavailable(request, error))
    }
    // `303 See Other` tells the browser to load the page with `GET /`, so
    // refreshing the page afterwards does not post the signature a second time.
    var answer = http.redirect(request, .SeeOther, "/")?
    &answer.set_cookie("name", name, path: "/", max_age: .Some(31536000), http_only: true, same_site: .Some(.Lax))?
    .Ok(answer)
}
```

## Running it

The form extractor materializes the body before `sign` runs, so the body limit
must admit every form the page can send. `limits` derives it from the field limits: a
browser writes each byte of a non-ASCII character as `%XX`, and a character is
at most four bytes of UTF-8, so the longest form is `name=&message=` and 560
characters of 12 bytes each, 6734 bytes. A line break counts as one character
and is sent as `%0D%0A`, 6 bytes, so it stays within that bound. A client that pads the fields with
spaces past that size is refused with 413, which is safe, because no form the
page produces is that large:

<!-- guide: excerpt examples/guest-book/main.lin -->
```linea
// The server refuses a body longer than the largest form `sign` accepts, a
// name and a message at their longest with every scalar four bytes long. A
// form the page's `maxlength` attributes admit always fits.
fn limits() -> http.Limits {
    let longest_form = "name=&message=".length() + (longest_name + longest_message) * encoded_scalar_bytes
    http.Limits { max_body_bytes = longest_form, open_connections = connection_budget, ..http.Limits.default() }
}
```

`main` budgets its descriptors, opens the system-thread database owner, and
serves the loopback port through HTTP fibers. Each worker builds its own router
and lends it a `Ctx` holding a restricted database client:

<!-- guide: excerpt examples/guest-book/main.lin -->
```linea
fn routes(inout router: http.Router[Ctx]) -> Result[(), http.RouteError] {
    &router.route("GET /", home)?
    &router.route("GET /favicon.ico", favicon)?
    &router.route("POST /sign", sign)
}
```

Registering a route can fail. `start` returns the client and router together,
with a dependency on the client it received. A refusal releases the router and
client while leaving the server's store alive:

<!-- guide: excerpt examples/guest-book/main.lin -->
```linea
// Build a serving task's router around a borrowed database client. A refused
// route releases both router and client, leaving the server's Store intact.
fn start(client: store.Client) -> Result[(Ctx, http.Router[Ctx]), http.RouteError] where carries(.Ok: client) {
    let ctx = Ctx { book = copy(client), proxy_trust = proxy_trust() }
    var router: http.Router[Ctx] = http.Router.new()
    match routes(&router) {
        Ok(_) => .Ok((ctx, router)),
        Err(error) => {
            router.release()
            ctx.release()
            .Err(error)
        },
    }
}
```


The serving factory carries its captured client's dependency into every handler.
`listen_and_serve` joins the workers before `Store` is released:

<!-- guide: excerpt examples/guest-book/main.lin -->
```linea
fn main() -> UInt8 {
    let port_arg = env.args().at(1) else {
        io.eprintln("usage: guest-book PORT")
        return 64
    }
    if env.args().count() > 2 {
        io.eprintln("usage: guest-book PORT")
        return 64
    }
    let port = port_arg.parse[UInt16]() else |_| {
        io.eprintln("usage: guest-book PORT")
        return 64
    }
    let logger = log.to_stderr(minimum: .Info)
    // One database owner keeps its connection and write-ahead log open.
    // Client sockets and readiness registrations need two descriptors each.
    // SQLite can still need temporary files, so this is an admission estimate,
    // not a guarantee that every later query will succeed.
    let files_needed = database_files + connection_budget * files_per_connection + serving_carriers * files_per_carrier + fixed_files
    let open_files = process.raise_open_file_limit() else |error| {
        io.eprintln("guest-book: cannot raise the open-file limit: {error}")
        return 1
    }
    if open_files < files_needed {
        io.eprintln("guest-book: serving needs {files_needed} open files, and this process may open {open_files}; raise the hard limit with `ulimit -H -n`")
        return 1
    }
    let path = database_path()
    // Initialize, use and close SQLite on one system-thread task. Idle HTTP
    // connections park on the fiber loop; a blocking database call occupies
    // the database thread without stopping unrelated socket/timer fibers.
    defer let database = Store.open(path) else |error| {
        io.eprintln("guest-book: {error}")
        error.release()
        return 1
    }
    let client = database.client()
    let execution = io.Loop.open(carriers: serving_carriers) else |error| {
        io.eprintln("guest-book: {error}")
        return 1
    }
    // The factory copies a restricted client for each serving task. The
    // HTTP server joins those tasks before database's deferred close runs.
    let serving = [sink logger, sink client] || -> where carries(client) {
        start(client).map(
            [sink logger = copy(logger)] |sink made: (Ctx, http.Router[Ctx])| -> where carries(made) {
                let (ctx, router) = made
                http.logged(copy(logger), http.with_state(ctx, router))
            },
        )
    }
    let _ = http.listen_and_serve(net.loopback(port), serving, limits: limits(), policy: .Threads(serving_tasks), on: execution) else |error| {
        io.eprintln("guest-book: {error}")
        error.release()
        return 1
    }
    0
}
```


You can build the binary and serve it on a port:

```sh
linea build examples/guest-book -o book
./book 8080
```

Posting a signature to the server redirects back to the home page with `303 See
Other` and sets the `name` cookie:

```sh
curl -i -X POST --data 'name=Grace%3Cb%3E&message=%3Cscript%3Ealert(1)%3C%2Fscript%3E' -c cookie.txt http://127.0.0.1:8080/sign
```

<!-- guide: unchecked HTTP output from tests/cmd/guest_book/serves_the_book.cmd -->
```text
HTTP/1.1 303 See Other
Location: /
Set-Cookie: name=Grace%3Cb%3E; Path=/; Max-Age=31536000; SameSite=Lax; HttpOnly
```

Fetching the page with that cookie renders the entry and pre-fills the `name`
input, both HTML-escaped:

<!-- guide: unchecked HTML output from tests/cmd/guest_book/serves_the_book.cmd -->
```text
<!doctype html>
<meta charset="utf-8">
<title>Guest book</title>
<style>
  body { max-width: 36rem; margin: 2rem auto; padding: 0 1rem; font: 1rem/1.5 system-ui, sans-serif; }
  label, textarea { display: block; width: 100%; margin-top: 0.5rem; }
  ol { padding-left: 1.25rem; }
  li { margin-top: 1rem; }
  time { color: #555; font-size: 0.875rem; }
  li p { white-space: pre-wrap; }
</style>
<h1>Guest book</h1>
<form method="post" action="/sign">
  <label>Name <input name="name" value="Grace&lt;b&gt;" maxlength="60" required></label>
  <label>Message <textarea name="message" maxlength="500" required></textarea></label>
  <button>Sign</button>
</form>
<ol reversed>
<li><b>Grace&lt;b&gt;</b> <time>TIME</time><p>&lt;script&gt;alert(1)&lt;/script&gt;</p></li>
</ol>
```

In SQLite itself the visitor's text is stored as written, and the signed timestamp
is stored as a 64-bit Unix integer:

```sh
sqlite3 guests.db 'SELECT name, message, typeof(signed_at) FROM entries'
```

<!-- guide: unchecked output from tests/cmd/guest_book/serves_the_book.cmd -->
```text
Grace<b>|<script>alert(1)</script>|integer
```

## What it does not do

Both the SQLite wrapper and the guest book stay focused on what the example
needs:

- `sqlite` binds and reads only 64-bit integers and UTF-8 text: no floats,
  blobs, or `NULL` bindings, no named parameters, no statement `reset`, and no
  custom busy handler beyond `wait_when_busy`.
- The guest book has no editing or deleting of entries, no moderation queue, no
  per-address rate limit, and no user accounts.

## What you have seen

- A library project with `"extern"`, `"native"`, and `"link"` in its
  `linea.json` keeps every `extern fn` and C shim inside one reviewed boundary,
  and an application opts in with `"extern": true` on the dependency.
- `@(opaque, linear)` handles make both `Database` and `Statement` resources the
  compiler tracks across every path; a `Statement` borrows its `Database`, so
  closing the database while a statement is open is refused at compile time,
  and `defer var` / `defer let` settle statements and partial row allocations
  on early `?` returns.
- `sqlite.Error` copies SQLite's message before the statement or connection
  closes, and `unavailable` logs that detail to standard error while answering
  the visitor with a generic 500 response.
- `embed` packages `schema.sql` and the HTML templates into the binary, and
  `Page` streams the template and entries directly into `http.html` with every
  visitor string HTML-escaped and timestamps formatted as RFC 3339.
- `limits` derives the body limit from the field limits, so every form the page
  sends fits, and `holds_disallowed_character` keeps control and bidirectional
  characters out of a signature.
- `process.raise_open_file_limit` checks room for client sockets, carrier
  descriptors and one database connection before serving starts.
- HTTP fibers share two carriers. Restricted clients send owned requests to
  a system-thread owner, keeping blocking SQLite work off those carriers.
- The database owner creates and closes its native connection on its thread;
  borrowed clients prevent closing it while serving tasks still use it.
