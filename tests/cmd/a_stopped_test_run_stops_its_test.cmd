Stopping `linea test` stops the test binary it is running. The binary is found
as this runner's child, so no other run's test is mistaken for it, and one that
survives is killed after it is reported.

  $ linea test "$LINEA_ROOT"/tests/cmd/fixtures/a_test_that_runs_until_it_is_stopped > out 2>&1 & runner=$!
  $ running() { ps -A -o ppid=,pid=,args= | awk -v p="$runner" '$1 == p && /counts_until_it_is_stopped/ { print $2 }'; }
  $ for i in $(seq 2400); do test_pid=$(running); [ -n "$test_pid" ] && break; kill -0 $runner 2>/dev/null || break; sleep 0.05; done; [ -n "$test_pid" ] || cat out
  $ { kill -TERM $runner; wait $runner; } 2>/dev/null; echo "the run ended with status $?"
  the run ended with status 143
  $ for i in $(seq 600); do kill -0 $test_pid 2>/dev/null || break; sleep 0.05; done; if kill -0 $test_pid 2>/dev/null; then echo "the test is still running"; kill -KILL $test_pid; fi
