The guest book serves its routes on loopback and stores entries in the SQLite
file `GUEST_BOOK_DATABASE` names.

  $ linea build "$LINEA_ROOT"/examples/guest-book -o book
  $ : > server.log; GUEST_BOOK_DATABASE=guests.db ./book 0 > server.log 2>&1 & server=$!
  $ for i in $(seq 2400); do grep -q listening server.log && break; kill -0 $server 2>/dev/null || break; sleep 0.05; done; grep -q listening server.log || cat server.log
  $ port=$(sed -n 's/.* listening address=127.0.0.1://p' server.log)

A first `GET /` finds no database file, so SQLite creates it and the schema the
program embeds makes the `entries` table.

  $ curl -s --max-time 30 "http://127.0.0.1:$port/"
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
    <label>Name <input name="name" value="" maxlength="60" required></label>
    <label>Message <textarea name="message" maxlength="500" required></textarea></label>
    <button>Sign</button>
  </form>
  <ol reversed>
  </ol>

`POST /sign` stores the signature, remembers the visitor's name in a cookie,
and redirects the browser to `GET /` with `303 See Other`.

  $ curl -s --max-time 30 -i -X POST --data 'name=Grace%3Cb%3E&message=%3Cscript%3Ealert(1)%3C%2Fscript%3E' -c cookie.txt "http://127.0.0.1:$port/sign" | tr -d '\r' | grep -E '^(HTTP/|Location:|Set-Cookie:)'
  HTTP/1.1 303 See Other
  Location: /
  Set-Cookie: name=Grace%3Cb%3E; Path=/; Max-Age=31536000; SameSite=Lax; HttpOnly

The next `GET /` lists the entry with its HTML escaped and fills the name field
from the cookie, also escaped.

  $ curl -s --max-time 30 -b cookie.txt "http://127.0.0.1:$port/" | sed -E 's/[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z/TIME/'
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

After three requests the server exits cleanly, closing the database.

  $ { kill -TERM $server; wait $server; } 2>/dev/null; echo "the server stopped with status $?"
  the server stopped with status 143

In SQLite itself the visitor's text is stored as written, and the signed timestamp
is stored as a 64-bit Unix integer.

  $ sqlite3 guests.db 'SELECT name, message, typeof(signed_at) FROM entries'
  Grace<b>|<script>alert(1)</script>|integer
