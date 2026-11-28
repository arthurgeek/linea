Stopping `linea test` stops the test binary it is running. Wait for compilation,
then require the named test to be this runner's child, so a missing child cannot
pass and no other run's test is mistaken for it. A survivor is killed after it
is reported.

  $ linea test "$LINEA_ROOT"/tests/cmd/fixtures/a_test_that_runs_until_it_is_stopped > out 2>&1 & runner=$!
  $ compiled() { ps -A -o ppid=,pid=,args= | awk -v p="$runner" '$1 == p && $3 ~ /(^|\/)linea-test-/ { print $2 }'; }
  $ running() { ps -A -o ppid=,pid=,args= | awk -v p="$runner" '$1 == p && $3 ~ /(^|\/)linea-test-/ && /counts until it is stopped/ { print $2 }'; }
  $ for i in $(seq 2400); do compiled_pid=$(compiled); [ -n "$compiled_pid" ] && break; kill -0 $runner 2>/dev/null || break; sleep 0.05; done; [ -n "$compiled_pid" ] || cat out
  $ test -n "$compiled_pid"
  $ test_pid=$(running); test -n "$test_pid"
  $ test "$test_pid" = "$compiled_pid"
  $ { kill -TERM $runner; wait $runner; } 2>/dev/null; echo "the run ended with status $?"
  the run ended with status 143
  $ for i in $(seq 600); do kill -0 $test_pid 2>/dev/null || break; sleep 0.05; done; if kill -0 $test_pid 2>/dev/null; then echo "the test is still running"; kill -KILL $test_pid; fi
