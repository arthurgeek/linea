#!/usr/bin/env bash
# Records what a CI runner has left while a long step runs, so a runner that
# stops answering the server leaves evidence of what it was short of.
#
#   resource-log.sh start    begin sampling in the background and return
#   resource-log.sh follow   print each one-line summary until killed
#
# Every 20 seconds the sampler appends the date, `free -m`, `df -h /var/tmp` and
# the five largest processes to $RUNNER_TEMP/resource.log, and one line to
# $RUNNER_TEMP/resource.summary: available memory, free disk, the memory all
# processes hold together, and the three largest processes by command name with
# how many of each command run.
set -u

log="${RUNNER_TEMP:-/tmp}/resource.log"
summary="${RUNNER_TEMP:-/tmp}/resource.summary"

sample() {
  {
    date -u +%FT%TZ
    free -m
    df -h /var/tmp
    ps aux --sort=-rss | head -5
    echo
  } >>"$log" 2>&1
  local available disk held top
  available=$(free -m | awk '/^Mem:/ { print $7 }')
  disk=$(df -h /var/tmp | awk 'NR == 2 { print $4 }')
  held=$(ps -eo rss= | awk '{ sum += $1 } END { printf "%d", sum / 1024 }')
  top=$(ps -eo rss=,comm= --sort=-rss | awk '
    NR <= 3 { printf "%s%s %d MB", (NR > 1 ? ", " : ""), $2, $1 / 1024 }
    { count[$2] += 1; held[$2] += $1 }
    END {
      printf "; by command:"
      for (name in count) if (held[name] > 262144) printf " %s x%d %d MB", name, count[name], held[name] / 1024
    }')
  echo "$(date -u +%T) available ${available} MB, /var/tmp free ${disk}, processes hold ${held} MB, largest ${top}" >>"$summary"
}

case "${1:-}" in
start)
  : >"$log"
  : >"$summary"
  # A new session, so the sampler outlives the step that started it and is
  # not signalled with that step's process group.
  nohup setsid bash -c '
    while true; do
      "$0" sample
      sleep 20
    done
  ' "$(realpath "$0")" >/dev/null 2>&1 &
  ;;
sample)
  sample
  ;;
follow)
  # Runs until killed. A step starts it in the background and kills it on exit.
  exec tail -n +1 -F "$summary"
  ;;
*)
  echo "usage: $0 start|follow" >&2
  exit 2
  ;;
esac
