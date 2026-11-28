Stopping `linea test` stops the test binary it is running. Wait for compilation,
then require the named test to be this runner's child, so a missing child cannot
pass and no other run's test is mistaken for it. A survivor is killed after it
is reported. An exited child may remain as a zombie until its new parent reaps
it; existence alone is not evidence that it is still running.

  $ process_running() { kill -0 "$1" 2>/dev/null || return 1; state=$(ps -p "$1" -o stat= 2>/dev/null) || { kill -0 "$1" 2>/dev/null; return; }; case "$state" in *Z*|*X*) return 1;; esac; kill -0 "$1" 2>/dev/null; }
  $ cc -std=c99 -Wall -Wextra -Werror "$LINEA_ROOT/tests/cmd/fixtures/stopped_process_state.c" -o process-state
  $ ./process-state > exited.pid & state_parent=$!
  $ for i in $(seq 200); do [ -s exited.pid ] && break; kill -0 "$state_parent" 2>/dev/null || break; sleep 0.01; done; test -s exited.pid
  $ exited_pid=$(cat exited.pid); kill -0 "$exited_pid"
  $ process_running "$state_parent"
  $ if process_running "$exited_pid"; then echo "an exited child is still running"; fi
  $ kill -TERM "$state_parent"; wait "$state_parent"
  $ linea test "$LINEA_ROOT"/tests/cmd/fixtures/a_test_that_runs_until_it_is_stopped > out 2>&1 & runner=$!
  $ compiled() { ps -A -o ppid=,pid=,args= | awk -v p="$runner" '$1 == p && $3 ~ /(^|\/)linea-test-/ { print $2 }'; }
  $ running() { ps -A -o ppid=,pid=,args= | awk -v p="$runner" '$1 == p && $3 ~ /(^|\/)linea-test-/ && /counts until it is stopped/ { print $2 }'; }
  $ for i in $(seq 2400); do compiled_pid=$(compiled); [ -n "$compiled_pid" ] && break; kill -0 $runner 2>/dev/null || break; sleep 0.05; done; [ -n "$compiled_pid" ] || cat out
  $ test -n "$compiled_pid"
  $ test_pid=$(running); test -n "$test_pid"
  $ test "$test_pid" = "$compiled_pid"
  $ { kill -TERM $runner; wait $runner; } 2>/dev/null; echo "the run ended with status $?"
  the run ended with status 143
  $ for i in $(seq 600); do process_running "$test_pid" || break; sleep 0.05; done; if process_running "$test_pid"; then echo "the test is still running"; ps -p "$test_pid" -o pid=,ppid=,pgid=,stat=,args=; kill -KILL $test_pid; fi
