An example says what it must do.

  $ linea test "$LINEA_ROOT"/examples/accounts > out
  $ cat out
  ok    ledger.a large fee is declined without overflow
  ok    ledger.an empty account can be opened and closed
  ok    ledger.declined withdrawals leave the balance unchanged
  ok    ledger.withdrawal deducts the amount and fee
  ok    ledger.withdrawing the full balance leaves zero
  
  5 passed, 0 failed
