A run builds its program in a directory of its own under `TMPDIR`, never
beside the source, and removes it whether the program succeeds, fails, or is
killed while it runs or while it is being built.

  $ mkdir app tmp
  $ cp "$LINEA_ROOT"/examples/bounded_echo.lin app/
  $ printf 'fn main() -> UInt8 {\n    return 3\n}\n' > app/fails.lin
  $ TMPDIR="$PWD/tmp" linea run app/fails.lin
  [3]
  $ : > server.log; TMPDIR="$PWD/tmp" linea run app/bounded_echo.lin -- serve --port 0 > server.log 2>&1 & server=$!
  $ for i in $(seq 2400); do grep -q listening server.log && break; kill -0 $server 2>/dev/null || break; sleep 0.05; done; grep -q listening server.log || cat server.log
  $ { kill $server; wait $server; } 2>/dev/null
  [143]
  $ TMPDIR="$PWD/tmp" linea run app/bounded_echo.lin -- serve --port 0 > building.log 2>&1 & building=$!
  $ for i in $(seq 6000); do ls tmp | grep -q linea-run && break; kill -0 $building 2>/dev/null || break; sleep 0.01; done
  $ { kill $building; wait $building; } 2>/dev/null
  [143]
  $ for i in $(seq 600); do ls tmp | grep -q linea-run || break; sleep 0.05; done
  $ ls app
  bounded_echo.lin
  fails.lin
  $ ls tmp | grep linea-run
  [1]
