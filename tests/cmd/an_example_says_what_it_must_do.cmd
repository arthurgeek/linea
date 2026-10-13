An example says what it must do.

  $ linea test "$LINEA_ROOT"/examples/accounts > out
  $ cat out
  ok    ledger.a_large_fee_is_declined_without_overflow
  ok    ledger.an_empty_account_can_be_opened_and_closed
  ok    ledger.declined_withdrawals_leave_the_balance_unchanged
  ok    ledger.withdrawal_deducts_the_amount_and_fee
  ok    ledger.withdrawing_the_full_balance_leaves_zero
  
  5 passed, 0 failed
