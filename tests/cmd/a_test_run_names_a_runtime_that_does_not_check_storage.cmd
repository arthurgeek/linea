`linea test` checks storage, so a runtime named by `LINEA_RUNTIME` that holds
no checking allocator is reported before the tests are built against it.

  $ : > unchecked.a
  $ env -u LINEA_SANITIZE LINEA_RUNTIME=unchecked.a linea test "$LINEA_ROOT"/tests/cmd/fixtures/a_library_with_tests 2>&1 | head -1
  warning: unchecked.a holds no checking allocator, so storage is not checked
