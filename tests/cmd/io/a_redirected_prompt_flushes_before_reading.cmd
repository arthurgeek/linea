A redirected prompt flushes before reading.

  $ linea run "$LINEA_ROOT"/tests/cmd/fixtures/a_prompt_reads_after_flushing.lin < "$LINEA_ROOT"/tests/cmd/io/a_redirected_prompt_flushes_before_reading.stdin > out
  name: 
  $ cat out
  Ada
