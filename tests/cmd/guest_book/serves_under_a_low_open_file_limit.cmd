Each of the guest book's 128 serving tasks holds a SQLite connection, which
keeps the database and its write-ahead log open. The program raises its soft
open-file limit toward the hard one before serving, so it serves when started
with a soft limit of 256, the default of a macOS shell.

  $ linea build "$LINEA_ROOT"/examples/guest-book -o book
  $ : > server.log; (ulimit -S -n 256; GUEST_BOOK_DATABASE=guests.db exec ./book 0) > server.log 2>&1 & server=$!
  $ for i in $(seq 2400); do grep -q listening server.log && break; kill -0 $server 2>/dev/null || break; sleep 0.05; done; grep -q listening server.log || cat server.log
  $ port=$(sed -n 's/.* listening address=127.0.0.1://p' server.log)
  $ curl -s --max-time 30 -o /dev/null -w '%{http_code}\n' -X POST --data 'name=Ada&message=hello' "http://127.0.0.1:$port/sign"
  303
  $ curl -s --max-time 30 -o /dev/null -w '%{http_code}\n' "http://127.0.0.1:$port/"
  200
  $ { kill -TERM $server; wait $server; } 2>/dev/null; echo "the server stopped with status $?"
  the server stopped with status 143

When the hard limit is too low for every task's connection, the program says
how many files it needs and exits 1 before it listens.

  $ (ulimit -n 200; GUEST_BOOK_DATABASE=guests.db ./book 0)
  guest-book: serving needs 389 open files, and this process may open 200; raise the hard limit with `ulimit -H -n`
  [1]
