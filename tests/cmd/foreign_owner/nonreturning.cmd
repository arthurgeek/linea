Native blocking and terminal failure are observed in an externally bounded subprocess.

  $ cp -R "$LINEA_ROOT"/tests/ffi/thread_bound_owner/hundred_clients app
  $ cp "$LINEA_ROOT"/tests/cmd/foreign_owner/fixtures/nonreturning.fixture app/main.lin
  $ linea build app --check-storage -o owner
  $ python3 "$LINEA_ROOT"/tests/cmd/foreign_owner/watchdog.py ./owner nonreturning
  unrelated fiber progressed; native call and join remain blocked
