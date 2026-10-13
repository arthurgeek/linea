A directory whose name is not an identifier is a module no import can name, but
it is part of the program: its tests run, and its files compile when named.

  $ linea test "$LINEA_ROOT"/tests/cmd/fixtures/a_module_no_import_can_name > out
  $ cat out
  ok    my-lib.ledger.a_ledger_holds_seven_entries
  
  1 passed, 0 failed
  $ linea check "$LINEA_ROOT"/tests/cmd/fixtures/a_module_no_import_can_name/my-lib/ledger/ledger.lin
