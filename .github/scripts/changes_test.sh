#!/usr/bin/env bash
# Runs `changes.sh ci` against a scratch repository and a `gh` that answers
# from files, and checks what it decides for each lane. Prints each mismatch
# and exits non-zero when there is one.
#
# The repository holds a base commit B, a pull request of a code commit C
# (touching `src/mir/`) and a documentation commit D on top of it, a
# `--no-ff` merge of D into B as the commit a pull request run tests, the
# same pull request with a guide commit G on top of C instead, a
# pull request of a documentation commit E alone on B, and two commits pushed
# to main after B: code P1 and documentation P2.
#
# The fake `gh` reads `$FAKE/runs-SHA`, lines of `suite name conclusion id
# completed_at` as the real call's `--jq` prints them, and
# `$FAKE/annotations-ID`, the messages of a check run's `tested base`
# annotations. It fails every call while `$FAKE/fail` exists, and appends
# each annotations call to `$FAKE/calls`.
set -u -o pipefail

# The scratch repository is its own: a hook or a caller's environment that
# points git at another repository, or a global hook, must not reach it.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY

script=$(cd "$(dirname "$0")" && pwd)/changes.sh
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
repo=$work/repo
export FAKE=$work/fake
mkdir -p "$repo" "$FAKE/bin"
failures=0

cat > "$FAKE/bin/gh" <<'EOF'
#!/usr/bin/env bash
[ -e "$FAKE/fail" ] && exit 1
call="$*"
case "$call" in
  *"/commits/"*)
    sha=${call#*/commits/}
    cat "$FAKE/runs-${sha%%/*}" 2>/dev/null ;;
  *"/check-runs/"*"/annotations"*)
    id=${call#*/check-runs/}
    id=${id%%/*}
    echo "$id" >> "$FAKE/calls"
    cat "$FAKE/annotations-$id" 2>/dev/null ;;
  *) exit 1 ;;
esac
exit 0
EOF
chmod +x "$FAKE/bin/gh"

git() { command git -C "$repo" -c user.name=test -c user.email=test@example.com -c commit.gpgsign=false -c core.hooksPath=/dev/null "$@"; }
commit() {
  mkdir -p "$repo/$(dirname "$1")"
  echo "$2" > "$repo/$1"
  git add "$1" && git commit -q -m "$2" && git rev-parse HEAD
}

git init -q -b main
B=$(commit src/main.zig base)
git checkout -q -b pr
C=$(commit src/mir/lower.zig code)
D=$(commit AGENTS.md docs)
git checkout -q --detach "$B"
git merge -q --no-ff -m merge "$D"
merge=$(git rev-parse HEAD)
git checkout -q --detach "$C"
G=$(commit docs/learn/01-basics.md guide)
git checkout -q --detach "$B"
git merge -q --no-ff -m merge-guide "$G"
merge_guide=$(git rev-parse HEAD)
git checkout -q --detach "$B"
E=$(commit AGENTS.md docs-alone)
git checkout -q --detach "$B"
git merge -q --no-ff -m merge-alone "$E"
merge_alone=$(git rev-parse HEAD)
git checkout -q --detach "$D"
H=$(commit runtime/task.c changed-code)
git checkout -q --detach "$B"
git merge -q --no-ff -m merge-code "$H"
merge_code=$(git rev-parse HEAD)
git checkout -q main
P1=$(commit src/other.zig pushed-code)
P2=$(commit README.md pushed-docs)

lanes=(check "sanitize (address)" "sanitize (thread)" "optimised (unit)" "optimised (corpus)" "optimised (soundness)" sweep fuzz-mir "fibers (ubuntu-24.04)" "fibers (ubuntu-24.04-arm)")

# Records at commit $1 a run, suite $2, whose `changes` run $3 recorded the
# annotations given after it, and in which every lane passed except those
# named in $FAILED.
record() {
  local sha=$1 suite=$2 id=$3 lane conclusion n=0
  shift 3
  : > "$FAKE/annotations-$id"
  for message in "$@"; do echo "$message" >> "$FAKE/annotations-$id"; done
  printf '%s\tchanges\tsuccess\t%s\t2026-01-01T00:00:00Z\n' "$suite" "$id" >> "$FAKE/runs-$sha"
  for lane in "${lanes[@]}"; do
    n=$((n + 1))
    conclusion=success
    case " ${FAILED:-} " in *" $lane "*) conclusion=failure ;; esac
    printf '%s\t%s\t%s\t%s\t2026-01-01T00:00:00Z\n' "$suite" "$lane" "$conclusion" "$id$n" >> "$FAKE/runs-$sha"
  done
}

reset() { rm -f "$FAKE"/runs-* "$FAKE"/annotations-* "$FAKE/calls" "$FAKE/fail"; }

# Runs `ci` for a pull request at head $2 tested as merge $3, as case $1,
# with any further VAR=value pairs in its environment.
run_pr() {
  local name=$1 head=$2 tested=$3
  shift 3
  run "$name" EVENT=pull_request PR_BASE="$B" HEAD_SHA="$head" GITHUB_SHA="$tested" "$@"
}

run() {
  local name=$1
  shift
  case_name=$name
  : > "$work/output"
  (cd "$repo" && env PATH="$FAKE/bin:$PATH" GITHUB_REPOSITORY=owner/repo \
    GITHUB_OUTPUT="$work/output" RUNNER_TEMP="$work" "$@" bash "$script" ci > "$work/log" 2>&1)
}

expect() {
  local key=$1 want=$2 got
  got=$(awk -F= -v k="$key" '$1 == k { sub(/^[^=]*=/, ""); print }' "$work/output")
  if [ "$got" != "$want" ]; then
    echo "$case_name: $key wanted $want, got ${got:-nothing}"
    sed 's/^/    /' "$work/log"
    failures=$((failures + 1))
  fi
}

expect_lanes() {
  expect check "$1"
  expect sanitize "$2"
  expect optimised-unit "$3"
  expect optimised-corpus "$3"
  expect optimised-soundness "$3"
  expect sweep "$4"
  expect fuzz-mir "$5"
  expect fibers "${6:-$3}"
}

# Every lane passed at C against the base the run at D tests: D changed
# Markdown alone, so every lane inherits.
reset
record "$C" 1 10 "pull_request $B"
run_pr "a green commit against the same base" "$D" "$merge"
expect_lanes inherit inherit inherit inherit inherit
expect sanitize-exclude '[{"sanitizer":"address"},{"sanitizer":"thread"}]'
expect fibers-exclude '[{"runner":"ubuntu-24.04"},{"runner":"ubuntu-24.04-arm"}]'
grep -q "^::notice title=tested base::pull_request $B$" "$work/log" ||
  { echo "$case_name: no tested base annotation for $B"; failures=$((failures + 1)); }
# One suite is read once, however many lanes passed in it.
calls=$(cat "$FAKE/calls" 2>/dev/null | wc -l | tr -d ' ')
[ "$calls" -eq 1 ] ||
  { echo "$case_name: read the suite's annotations $calls times"; failures=$((failures + 1)); }

# A ready-for-review event with the same head and base reuses both ABI runs.
reset
record "$D" 1 10 "pull_request $B"
run_pr "the same head becomes ready again" "$D" "$merge"
expect fibers inherit
expect fibers-exclude '[{"runner":"ubuntu-24.04"},{"runner":"ubuntu-24.04-arm"}]'

# A pass on one ABI never substitutes for a failed or missing other ABI.
for failed in 'fibers (ubuntu-24.04)' 'fibers (ubuntu-24.04-arm)'; do
  reset
  FAILED="$failed" record "$D" 1 10 "pull_request $B"
  run_pr "only $failed failed" "$D" "$merge"
  expect fibers run
  if [ "$failed" = 'fibers (ubuntu-24.04)' ]; then
    expect fibers-exclude '[{"runner":"ubuntu-24.04-arm"}]'
  else
    expect fibers-exclude '[{"runner":"ubuntu-24.04"}]'
  fi
done
for conclusion in missing cancelled pending skipped; do
  reset
  record "$D" 1 10 "pull_request $B"
  awk -F '\t' -v OFS='\t' -v c="$conclusion" '
    $2 == "fibers (ubuntu-24.04-arm)" { if (c == "missing") next; $3 = c }
    { print }
  ' "$FAKE/runs-$D" > "$work/modified-runs"
  mv "$work/modified-runs" "$FAKE/runs-$D"
  run_pr "ARM evidence is $conclusion" "$D" "$merge"
  expect fibers run
  expect fibers-exclude '[{"runner":"ubuntu-24.04"}]'
done

reset
record "$C" 1 10 "pull_request $B"
run_pr "code changed after both ABIs passed" "$H" "$merge_code"
expect fibers run
expect fibers-exclude '[]'

# The lane that failed at C reruns; the rest inherit.
reset
FAILED="check" record "$C" 1 10 "pull_request $B"
run_pr "a lane that failed at the green commit" "$D" "$merge"
expect_lanes run inherit inherit inherit inherit
FAILED="sanitize (thread)" record "$C" 2 20 "pull_request $B"
run_pr "a lane that failed in one attempt and passed in another" "$D" "$merge"
expect_lanes inherit inherit inherit inherit inherit

# Each optimised job is a lane of its own: the one that failed reruns, and
# the two that passed inherit.
reset
FAILED="optimised (corpus)" record "$C" 1 10 "pull_request $B"
run_pr "one optimised job failed at the green commit" "$D" "$merge"
expect optimised-unit inherit
expect optimised-corpus run
expect optimised-soundness inherit

# The guide is read by `check` and `optimised-unit` alone, so an edit to it
# reruns those two and the rest inherit.
reset
record "$C" 1 10 "pull_request $B"
run_pr "a guide edit after a green commit" "$G" "$merge_guide"
expect check run
expect sanitize inherit
expect optimised-unit run
expect optimised-corpus inherit
expect optimised-soundness inherit
expect sweep inherit
expect fuzz-mir inherit

# A pass against another base proves nothing about this one; the diff
# against the base decides, and it holds code under `src/mir/`.
reset
record "$C" 1 10 "pull_request $P1"
run_pr "a green commit against another base" "$D" "$merge"
expect_lanes run run run run run
expect sanitize-exclude '[]'

reset
record "$C" 1 10 "push $B"
run_pr "a green commit of another event" "$D" "$merge"
expect_lanes run run run run run

reset
record "$C" 1 10
run_pr "a green commit that recorded no base" "$D" "$merge"
expect_lanes run run run run run
run_pr "the dry-run's variables have no effect on ci" "$D" "$merge" \
  TESTED_BASE="$B" ACCEPT_UNRECORDED_BASE=1 AS_OF=2000-01-01T00:00:00Z \
  dry_tested_base="$P1" dry_accept_unrecorded=1
expect_lanes run run run run run

# A file name printed as a workflow command is a second annotation; a suite
# holding two vouches for neither.
reset
record "$C" 1 10 "pull_request $P1" "pull_request $B"
run_pr "a suite with two tested bases" "$D" "$merge"
expect_lanes run run run run run
grep -q '^::stop-commands::' "$work/log" ||
  { echo "$case_name: the changed files are listed without stop-commands"; failures=$((failures + 1)); }

# A run whose own annotations name its base twice, the same both times,
# printed one of them from text it does not vouch for.
reset
record "$C" 1 10 "pull_request $B" "pull_request $B"
run_pr "a run recording the same tested base twice" "$D" "$merge"
expect_lanes run run run run run

# When the check runs cannot be read, each lane is decided by the base diff.
reset
record "$C" 1 10 "pull_request $B"
touch "$FAKE/fail"
run_pr "the API failing" "$D" "$merge"
expect_lanes run run run run run
run_pr "the API failing on a pull request of documentation alone" "$E" "$merge_alone"
expect_lanes skip skip skip skip skip

# A run on the base itself is not a commit of the pull request: E's pull
# request has no green commit, so its documentation alone skips every lane.
reset
record "$B" 1 10 "pull_request $B"
run_pr "a green run at the base" "$E" "$merge_alone"
expect_lanes skip skip skip skip skip

# A push inherits `check` from a commit whose push run passed it.
reset
record "$P1" 1 10 "push $P1"
run "a push after a green commit" EVENT=push GITHUB_SHA="$P2"
expect_lanes inherit skip skip skip skip inherit
reset
FAILED="check" record "$P1" 1 10 "push $P1"
run "a push after a red commit" EVENT=push GITHUB_SHA="$P2"
expect_lanes run skip skip skip skip inherit
reset
record "$P1" 1 10 "schedule $P1"
run "a push after a scheduled run" EVENT=push GITHUB_SHA="$P2"
expect_lanes run skip skip skip skip run
touch "$FAKE/fail"
run "a push with the API failing" EVENT=push GITHUB_SHA="$P2"
expect_lanes run skip skip skip skip run

# A scheduled or manual run runs every lane but `fuzz-mir`, which `fuzz`
# covers there.
reset
run "a scheduled run" EVENT=schedule GITHUB_SHA="$P2"
expect_lanes run run run run skip
expect fibers-exclude '[]'
run "a manual run" EVENT=workflow_dispatch GITHUB_SHA="$P2"
expect fibers run
expect fibers-exclude '[]'

# Execute the workflow's actual merge gate with controlled job results.
# An inherited fiber matrix must be skipped; a partially rerun one must pass.
awk '
  /^  merge-ready:/ { job = 1; next }
  job && /^  [^ ]/ { exit }
  job && /^        run: \|$/ { body = 1; next }
  body && /^          / { sub(/^          /, ""); print; next }
  body { exit }
' "$(dirname "$script")/../workflows/ci.yml" > "$work/gate"
gate() {
  local name=$1 want=$2 got=0
  shift 2
  env EVENT=pull_request DRAFT=false CHANGES=success \
    WANT_CHECK=inherit WANT_SANITIZE=inherit WANT_OPTIMISED_UNIT=inherit \
    WANT_OPTIMISED_CORPUS=inherit WANT_OPTIMISED_SOUNDNESS=inherit WANT_FUZZ_MIR=inherit \
    CHECK=skipped SANITIZE=skipped OPTIMISED_UNIT=skipped OPTIMISED_CORPUS=skipped \
    OPTIMISED_SOUNDNESS=skipped FUZZ=skipped FUZZ_MIR=skipped \
    "$@" bash "$work/gate" > "$work/gate-log" 2>&1 || got=$?
  if [ "$got" != "$want" ]; then
    echo "$name: gate wanted exit $want, got $got"
    cat "$work/gate-log"
    failures=$((failures + 1))
  fi
}
gate 'both ABI passes inherited' 0 WANT_FIBERS=inherit FIBERS=skipped
gate 'one or both ABIs rerun successfully' 0 WANT_FIBERS=run FIBERS=success
gate 'required ABI failed' 1 WANT_FIBERS=run FIBERS=failure
gate 'required ABI cancelled' 1 WANT_FIBERS=run FIBERS=cancelled
gate 'required ABI skipped' 1 WANT_FIBERS=run FIBERS=skipped
gate 'inherited ABI unexpectedly ran' 1 WANT_FIBERS=inherit FIBERS=success
gate 'missing fiber decision' 1 WANT_FIBERS= FIBERS=skipped
gate 'draft cannot merge' 1 WANT_FIBERS=inherit FIBERS=skipped DRAFT=true

if [ "$failures" -gt 0 ]; then
  echo "$failures mismatches"
  exit 1
fi
echo "every case decided as expected"
