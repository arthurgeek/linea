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
├── sqlite/
│   ├── linea.json
│   ├── shim.c
│   └── sqlite.lin
└── templates/
    ├── entry.html
    └── page.html
```

It is split into four layers:

- `sqlite/` is a standalone library project that wraps SQLite's C API in linear
  `Database` and `Statement` handles and a value error `sqlite.Error`.
- `book/book.lin` is the application's storage module: it embeds `schema.sql`,
  opens the guest book, inserts signatures, and reads the newest entries.
- `page/page.lin` embeds the HTML templates and streams `Page` through
  `Display`, escaping untrusted text while expanding the entry list in a single
  pass.
- `main.lin` holds the shared `App` state, checks and records signatures, and
  serves the router on a loopback TCP port.

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

Three small helpers in `examples/guest-book/sqlite/shim.c` bridge C idioms that
do not cross an `extern fn` signature directly: `SQLITE_TRANSIENT` is `(void
(*)(void *))-1`, a sentinel function pointer that asks SQLite to copy bound
text before returning; `sqlite3_prepare_v2` reports uncompiled trailing SQL
through a `const char **` tail pointer, which the shim turns into a byte count;
and `sqlite3_errmsg(sqlite3_db_handle(statement))` reads a statement's error
sentence without minting a second linear handle for its connection.

Inside `examples/guest-book/sqlite/sqlite.lin`, the C pointers `sqlite3 *` and
`sqlite3_stmt *` are wrapped in `@(opaque, linear)` handle types and private
`extern fn` declarations:

<!-- guide: excerpt examples/guest-book/sqlite/sqlite.lin -->
```linea
// A `sqlite3 *` connection pointer C allocated. `@opaque` keeps the address
// inside this module, and `@linear` makes every connection reach
// `sqlite3_close_v2`.
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

// `sqlite3_next_stmt` returns the next unfinalized statement on `database`
// after `statement`, or 0 when every statement has been finalized.
extern fn sqlite3_next_stmt(read database: DatabaseHandle, statement: UInt64) -> UInt64

// `sqlite3_close` refuses with `SQLITE_BUSY` when an unfinalized statement
// remains on `database`, setting the connection's error message without freeing
// the connection.
extern fn sqlite3_close(database: DatabaseHandle) -> Int32

// `sink` hands the connection handle to C for good. `sqlite3_close_v2` closes
// the connection, or marks it to close as soon as its last statement finishes.
extern fn sqlite3_close_v2(sink database: DatabaseHandle) -> Int32

// `read` promises C only reads the connection, and `where borrows(database)`
// ties the returned `CText` to the connection's lifetime so the text is copied
// before the connection next changes or closes.
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
@(opaque, linear)
struct Statement {
    handle: StatementHandle,
}
```

In Rust's `rusqlite`, `Statement<'conn>` borrows `Connection` for its lifetime
and finalizes itself in `Drop`, which silently ignores any error from
`sqlite3_finalize`. In Linea, `Statement` and `Database` are independent linear
values: `Database.close` checks whether any `Statement` on the connection is
still open and refuses with `SQLITE_BUSY` (code 5) if so, while still handing
the native handle to `sqlite3_close_v2` so SQLite reclaims its memory once the
remaining statement finishes, and the compiler refuses any path that forgets to
settle a `Statement`:

<!-- guide: unchecked diagnostic from tests/cmd/guest_book/a_forgotten_statement_is_refused.cmd -->
```text
error[O-Leak]: `_statement` (a linear `sqlite.Statement`) is still owned when this path leaves
 --> app/main.lin:6:9
  |
6 |     let _statement = &db.prepare("SELECT COUNT(*) FROM entries")?
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
        defer var select = &self.database.prepare("SELECT name, message, signed_at FROM entries ORDER BY id DESC LIMIT ?1")?
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

## Shared state and signing

Both `home` and `sign` take `inout app: App` from `http.Router[App]`. `App.open`
opens `Book` once before accepting connections; because `http.listen_and_serve`
answers one connection at a time, every request shares that connection.

`POST /sign` extracts the URL-encoded form into `Signature` through
`http.Form[Signature]`. Before touching the database, `sign` in
`examples/guest-book/main.lin` checks `http.same_origin` and verifies that the
trimmed name and message fit the scalar limits:

<!-- guide: excerpt examples/guest-book/main.lin -->
```linea
fn sign(inout app: App, form: http.Form[Signature], request: http.Request) -> Result[http.Response, http.Error] {
    if !http.same_origin(request, trust: app.proxy_trust) {
        return .Err(http.error(request, .Forbidden, "a signature is accepted only from this guest book's own page"))
    }
    let name = form.value.name.trim_ascii()
    let message = form.value.message.trim_ascii()
    if name.length() == 0 || message.length() == 0 {
        return .Err(http.error(request, .UnprocessableContent, "a signature needs a name and a message"))
    }
    if name.scalars().count() > longest_name || message.scalars().count() > longest_message {
        return .Err(http.error(request, .UnprocessableContent, "a name holds at most {longest_name} characters and a message {longest_message}"))
    }
    let _ = &app.book.sign(name, message) else |error| {
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

`main` in `examples/guest-book/main.lin` registers the routes on
`http.Router[App]`, caps request bodies at 4096 bytes, serves the loopback port,
and closes `app` when finished:

<!-- guide: excerpt examples/guest-book/main.lin -->
```linea
fn routes(inout router: http.Router[App]) -> Result[(), http.RouteError] {
    &router.route("GET /", home)?
    &router.route("GET /favicon.ico", favicon)?
    &router.route("POST /sign", sign)
}

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
    var router: http.Router[App] = http.Router.new()
    let _ = routes(&router) else |error| {
        logger.error("cannot register a route", log.field("error", error))
        router.release()
        return 2
    }
    let app = App.open(database_path()) else |error| {
        router.release()
        io.eprintln("guest-book: {error}")
        error.release()
        return 1
    }
    let limits = http.Limits { max_body_bytes = 4096, ..http.Limits.default() }
    let app = http.listen_and_serve(net.loopback(port), http.logged(logger, router), state: app, limits: limits) else |error| {
        io.eprintln("guest-book: {error}")
        return 1
    }
    let _ = app.close() else |error| {
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
  compiler tracks across every path; `Database.close` reports `SQLITE_BUSY` if a
  statement is left open, and `defer var` / `defer let` settle statements and
  partial row allocations on early `?` returns.
- `sqlite.Error` copies SQLite's message before the statement or connection
  closes, and `unavailable` logs that detail to standard error while answering
  the visitor with a generic 500 response.
- `embed` packages `schema.sql` and the HTML templates into the binary, and
  `Page` streams the template and entries directly into `http.html` with every
  visitor string HTML-escaped and timestamps formatted as RFC 3339.
- `http.listen_and_serve` runs `http.Router[App]` and its routes, returning
  `App` on completion so `close()` is checked explicitly.
