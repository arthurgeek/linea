#!/usr/bin/env bash
# Runs `changes.sh ci` against a scratch repository and a `gh` that answers
# from files, and checks what it decides for each lane. Prints each mismatch
# and exits non-zero when there is one.
#
# The repository holds a base commit B, a pull request of a code commit C
# (touching `src/mir/`) and a documentation commit D on top of it, a
# `--no-ff` merge of D into B as the commit a pull request run tests, a
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
git checkout -q --detach "$B"
E=$(commit AGENTS.md docs-alone)
git checkout -q --detach "$B"
git merge -q --no-ff -m merge-alone "$E"
merge_alone=$(git rev-parse HEAD)
git checkout -q main
P1=$(commit src/other.zig pushed-code)
P2=$(commit README.md pushed-docs)

lanes=(check "sanitize (address)" "sanitize (thread)" optimised sweep fuzz-mir)

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
  expect optimised "$3"
  expect sweep "$4"
  expect fuzz-mir "$5"
}

# Every lane passed at C against the base the run at D tests: D changed
# Markdown alone, so every lane inherits.
reset
record "$C" 1 10 "pull_request $B"
run_pr "a green commit against the same base" "$D" "$merge"
expect_lanes inherit inherit inherit inherit inherit
expect sanitize-exclude '[{"sanitizer":"address"},{"sanitizer":"thread"}]'
grep -q "^::notice title=tested base::pull_request $B$" "$work/log" ||
  { echo "$case_name: no tested base annotation for $B"; failures=$((failures + 1)); }
# One suite is read once, however many lanes passed in it.
calls=$(cat "$FAKE/calls" 2>/dev/null | wc -l | tr -d ' ')
[ "$calls" -eq 1 ] ||
  { echo "$case_name: read the suite's annotations $calls times"; failures=$((failures + 1)); }

# The lane that failed at C reruns; the rest inherit.
reset
FAILED="check" record "$C" 1 10 "pull_request $B"
run_pr "a lane that failed at the green commit" "$D" "$merge"
expect_lanes run inherit inherit inherit inherit
FAILED="sanitize (thread)" record "$C" 2 20 "pull_request $B"
run_pr "a lane that failed in one attempt and passed in another" "$D" "$merge"
expect_lanes inherit inherit inherit inherit inherit

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
expect_lanes inherit skip skip skip skip
reset
FAILED="check" record "$P1" 1 10 "push $P1"
run "a push after a red commit" EVENT=push GITHUB_SHA="$P2"
expect_lanes run skip skip skip skip
reset
record "$P1" 1 10 "schedule $P1"
run "a push after a scheduled run" EVENT=push GITHUB_SHA="$P2"
expect_lanes run skip skip skip skip
touch "$FAKE/fail"
run "a push with the API failing" EVENT=push GITHUB_SHA="$P2"
expect_lanes run skip skip skip skip

# A scheduled or manual run runs every lane but `fuzz-mir`, which `fuzz`
# covers there.
reset
run "a scheduled run" EVENT=schedule GITHUB_SHA="$P2"
expect_lanes run run run run skip

if [ "$failures" -gt 0 ]; then
  echo "$failures mismatches"
  exit 1
fi
echo "every case decided as expected"
