A library builds an object and links no runtime, so asking its build to check
storage is refused rather than ignored.

  $ linea build --check-storage "$LINEA_ROOT"/tests/cmd/fixtures/a_library_with_tests -o lib.o; echo "status $?"
  error: a library links no runtime, so `--check-storage` has nothing to check
    link the object against liblinea_rt_checked.a instead
  status 64
  $ test -e lib.o; echo "built $?"
  built 1
