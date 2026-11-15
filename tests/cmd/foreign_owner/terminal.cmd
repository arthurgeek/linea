Native blocking and terminal failure are observed in an externally bounded subprocess.

  $ cp -R "$LINEA_ROOT"/tests/ffi/thread_bound_owner/cleanup_retry app
  $ cp "$LINEA_ROOT"/tests/cmd/foreign_owner/fixtures/terminal.fixture app/main.lin
  $ linea build app --check-storage -o owner
  $ zig build-exe "$LINEA_ROOT"/tests/cmd/foreign_owner/watchdog.zig -lc -femit-bin=watchdog
  $ ./watchdog ./owner terminal
  terminal policy observed; no normal settlement claimed
