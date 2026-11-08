#!/usr/bin/env bash
# Decides which CI lanes a run needs, lane by lane.
#
#   changes.sh ci                          the `changes` job: decide every lane
#                                          and write the decisions to
#                                          $GITHUB_OUTPUT
#   changes.sh decide LANE SINCE_GREEN SINCE_BASE
#                                          print `run`, `inherit` or `skip` for
#                                          one lane, given two changed-file
#                                          lists (`-` where there is none)
#   changes.sh classify LIST               print the class of a changed-file
#                                          list: `a`, `b` or `c`
#   changes.sh dry-run PR HEAD             print what `ci` decides for the pull
#                                          request's run at HEAD, from the check
#                                          runs that had finished before it
#
# A lane is one of check, sanitize-address, sanitize-thread, optimised, sweep
# and fuzz-mir. Its decision is
#
#   run      the lane runs, and `merge-ready` requires it to pass;
#   inherit  a commit of this history passed the lane against the same base,
#            and nothing the lane reads changed since, so it does not run;
#   skip     the lane has nothing to check on this event or this change.
#
# A lane is green at a commit when any attempt of its check run there
# concluded success, in a run whose `changes` job recorded the same event and
# base as this one. Each run records them as a `tested base` annotation
# (`pull_request SHA` or `push SHA`): for a pull request, the base-branch
# commit it was merged into; for a push, the commit itself.
#
# The changed paths fall into three classes:
#
#   a  Markdown no gate reads;
#   b  Markdown a gate reads: the guide (`docs/learn/`), the decision index
#      (`docs/adr/`) and the semantics (`docs/linea-semantics.md`), which only
#      `check` and `optimised` read, through the documentation gates, the
#      guide and the unit tests;
#   c  anything else, the corpus under `tests/` included, Markdown or not:
#      every walk reads it.
#
# A list's class is the highest class of any path in it. A build-source test
# refuses a build step or embed that reads Markdown outside class b's paths
# and `tests/`, so class a stays unread.
#
# Where the lane has a green commit, the diff from that commit to the head
# decides: class a inherits every lane, class b runs `check` and `optimised`
# and inherits the rest, class c runs every lane. `fuzz-mir` runs when that
# diff touches what it guards, or when it is class c and the pull request's
# change touches what it guards or is unknown, and inherits otherwise, so
# every head of a pull request touching what it guards is fuzzed. Where the
# lane has no green commit, the diff against the pull request's base decides:
# a change of class a skips the lane, any other runs it, and `fuzz-mir` runs
# only when the change touches what it guards. Where neither diff exists, the
# lane runs.
#
# When the check runs cannot be read, no lane has a green commit, and each is
# decided by the base diff alone.
set -u -o pipefail

lanes="check sanitize-address sanitize-thread optimised sweep fuzz-mir"
gated_docs='^docs/learn/.*\.md$|^docs/adr/.*\.md$|^docs/linea-semantics\.md$'
mir_paths='^src/(mir|ownership|sema)/|^src/driver/loader\.zig$|^src/conformance/(generate|storage)\.zig$'
# How many commits of the history are searched for a green one, newest first.
depth=50

# Set by `dry-run` alone: the base it assumes, whether it accepts a run that
# recorded none, and the time after which a check run is not yet known.
dry_tested_base=
dry_accept_unrecorded=
dry_as_of=

# The name GitHub gives a lane's check run.
check_name() {
  case "$1" in
    sanitize-address) echo "sanitize (address)" ;;
    sanitize-thread) echo "sanitize (thread)" ;;
    *) echo "$1" ;;
  esac
}

classify() {
  if grep -qvE '\.md$' "$1" || grep -qE '^tests/' "$1"; then
    echo c
  elif grep -qE "$gated_docs" "$1"; then
    echo b
  else
    echo a
  fi
}

touches_mir() {
  grep -qE "$mir_paths" "$1"
}

decide() {
  local lane=$1 since_green=$2 since_base=$3
  case " $lanes " in
    *" $lane "*) ;;
    *) echo "unknown lane: $lane" >&2; return 2 ;;
  esac
  if [ "$since_green" != - ]; then
    if [ "$lane" = fuzz-mir ]; then
      if touches_mir "$since_green"; then
        echo run
      elif [ "$(classify "$since_green")" = c ] && { [ "$since_base" = - ] || touches_mir "$since_base"; }; then
        echo run
      else
        echo inherit
      fi
      return
    fi
    case "$(classify "$since_green")" in
      a) echo inherit ;;
      b) case "$lane" in check|optimised) echo run ;; *) echo inherit ;; esac ;;
      c) echo run ;;
    esac
  elif [ "$since_base" = - ]; then
    echo run
  elif [ "$lane" = fuzz-mir ]; then
    if touches_mir "$since_base"; then echo run; else echo skip; fi
  elif [ "$(classify "$since_base")" = a ]; then
    echo skip
  else
    echo run
  fi
}

# The event and base the runs of check suite $1 recorded; empty where none
# did, and where a run recorded two or the runs disagree, since a second
# annotation can only come from text the run printed and does not vouch for.
# Answered once per suite. Fails when the API does.
suite_base() {
  local suite=$1 id memo=$tmp/suite-$1 found=$tmp/found-$1
  if [ ! -e "$memo" ]; then
    : > "$found"
    for id in $(awk -F'\t' -v s="$suite" '$1 == s && $2 == "changes" { print $4 }' "$runs"); do
      gh api "repos/$GITHUB_REPOSITORY/check-runs/$id/annotations" \
        --jq '.[] | select(.title == "tested base") | .message' > "$tmp/annotations" || return 1
      if [ "$(wc -l < "$tmp/annotations")" -gt 1 ]; then
        echo refused >> "$found"
      else
        cat "$tmp/annotations" >> "$found"
      fi
    done
    if [ "$(sort -u "$found" | wc -l)" -eq 1 ] && ! grep -qx refused "$found"; then
      head -n 1 "$found" > "$memo"
    else
      : > "$memo"
    fi
  fi
  cat "$memo"
}

# Writes `LANE SHA` to $greens for each lane that passed at a commit of the
# history, newest first, against the base the commit is held to, and `LANE
# SHA assumed` where dry-run accepted a run that recorded no base. Fails when
# the API does, leaving no green commit for any lane.
find_greens() {
  local commit expected lane name suite recorded
  : > "$greens"
  for commit in $(git rev-list "${walk[@]}"); do
    case "$EVENT" in
      pull_request) expected="$EVENT $tested_base" ;;
      *) expected="$EVENT $commit" ;;
    esac
    gh api --paginate "repos/$GITHUB_REPOSITORY/commits/$commit/check-runs?filter=all&per_page=100" \
      --jq '.check_runs[] | select(.app.slug == "github-actions") | [.check_suite.id, .name, (.conclusion // "pending"), .id, (.completed_at // "")] | @tsv' \
      > "$runs" || { : > "$greens"; return 1; }
    for lane in $lanes; do
      grep -q "^$lane " "$greens" && continue
      name=$(check_name "$lane")
      for suite in $(awk -F'\t' -v n="$name" -v t="$dry_as_of" \
        '$2 == n && $3 == "success" && (t == "" || $5 < t) { print $1 }' "$runs" | sort -u); do
        recorded=$(suite_base "$suite") || { : > "$greens"; return 1; }
        if [ "$recorded" = "$expected" ]; then
          echo "$lane $commit" >> "$greens"
          break
        elif [ -z "$recorded" ] && [ "$dry_accept_unrecorded" = 1 ]; then
          echo "$lane $commit assumed" >> "$greens"
          break
        fi
      done
    done
    [ "$(wc -l < "$greens")" -eq "$(echo "$lanes" | wc -w)" ] && break
  done
  return 0
}

ci() {
  local lane decision green assumed since_base=- out token base_label
  tmp=$(mktemp -d "${RUNNER_TEMP:-/tmp}/changes.XXXXXX")
  runs=$tmp/runs
  greens=$tmp/greens
  : > "$greens"
  out=${GITHUB_OUTPUT:-/dev/stdout}

  case "$EVENT" in
    pull_request)
      head=$HEAD_SHA
      # The pull request is tested merged into the base branch: the merge
      # commit's first parent is the base this run tests.
      tested_base=${dry_tested_base:-$(git rev-parse "$GITHUB_SHA^1")}
      walk=(--max-count="$depth" "$head" "^$tested_base")
      # `--no-renames` lists a renamed file under both names, so moving code
      # into a Markdown path still counts as changing code.
      if [ -n "$PR_BASE" ] && git -c core.quotePath=false diff --no-renames --name-only "$PR_BASE...$GITHUB_SHA" > "$tmp/base"; then
        since_base=$tmp/base
      fi
      ;;
    push)
      head=$GITHUB_SHA
      tested_base=$GITHUB_SHA
      walk=(--first-parent --max-count="$depth" "$head")
      ;;
    *)
      head=$GITHUB_SHA
      tested_base=$GITHUB_SHA
      walk=()
      ;;
  esac
  base_label=$tested_base
  [ -n "$dry_tested_base" ] && base_label="$tested_base (assumed: where the head leaves origin/main)"
  # The event is part of what is recorded: a pull request's lanes check what a
  # push's do not, and a push's `check` runs the guide and the library's and
  # the examples' own tests, which a scheduled or manual run's leaves out.
  echo "::notice title=tested base::$EVENT $tested_base"

  if [ "${#walk[@]}" -gt 0 ] && ! find_greens; then
    echo "the check runs could not be read: each lane is decided as if no commit had passed it"
  fi

  local sanitize=skip exclude=""
  for lane in $lanes; do
    case "$EVENT:$lane" in
      pull_request:*) ;;
      push:check) ;;
      push:*) decision=skip ;;
      *:fuzz-mir) decision=skip ;;
      *) decision=run ;;
    esac
    case "$EVENT:$lane" in
      pull_request:*|push:check)
        green=$(awk -v l="$lane" '$1 == l { print $2 }' "$greens")
        assumed=$(awk -v l="$lane" '$1 == l && $3 == "assumed" { print "; no base recorded there, assumed the same" }' "$greens")
        if [ -n "$green" ] && git -c core.quotePath=false diff --no-renames --name-only "$green" "$head" > "$tmp/since-$lane"; then
          decision=$(decide "$lane" "$tmp/since-$lane" "$since_base")
          echo "$lane: passed at $green against $base_label$assumed; changed since: class $(classify "$tmp/since-$lane"): $decision"
        else
          decision=$(decide "$lane" - "$since_base")
          echo "$lane: no commit passed it against $base_label: $decision"
        fi
        ;;
    esac
    case "$lane" in
      sanitize-*)
        if [ "$decision" = run ]; then
          sanitize=run
        else
          [ "$sanitize" = run ] || sanitize=$decision
          exclude="$exclude${exclude:+,}{\"sanitizer\":\"${lane#sanitize-}\"}"
        fi
        ;;
      *) echo "$lane=$decision" >> "$out" ;;
    esac
  done
  if [ "$since_base" != - ]; then
    # The names are the pull request's own, so the runner reads no workflow
    # command among them: a file named like `::notice ...` stays a name.
    token=$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n')
    echo "files changed since $PR_BASE:"
    echo "::stop-commands::$token"
    cat "$since_base"
    echo "::$token::"
  fi
  {
    echo "sanitize=$sanitize"
    echo "sanitize-exclude=[$exclude]"
  } >> "$out"
  rm -rf "$tmp"
}

# What `ci` would have decided for the pull request's run at HEAD, read from
# the check runs that had finished when HEAD's first run started. The base is
# assumed to be where HEAD leaves `origin/main`, and a run that recorded no
# base is accepted against it, so runs from before the record existed can be
# read; the output says where it assumed either.
dry_run() {
  local pr=$1 sha
  sha=$(git rev-parse "$2") || return 1
  export EVENT=pull_request HEAD_SHA=$sha GITHUB_SHA=$sha
  export GITHUB_REPOSITORY=${GITHUB_REPOSITORY:-$(gh repo view --json nameWithOwner --jq .nameWithOwner)}
  PR_BASE=$(git merge-base "$sha" origin/main) || return 1
  export PR_BASE
  dry_tested_base=$PR_BASE
  dry_accept_unrecorded=1
  dry_as_of=$(gh api --paginate "repos/$GITHUB_REPOSITORY/commits/$sha/check-runs?filter=all&per_page=100" \
    --jq '.check_runs[].started_at' | sort | head -n 1)
  # A commit pushed together with a later one has no run; its committer date
  # stands in for when it would have started.
  dry_as_of=${dry_as_of:-$(TZ=UTC git log -1 --date=format-local:%Y-%m-%dT%H:%M:%SZ --format=%cd "$sha")}
  echo "pull request #$pr at $sha, as of ${dry_as_of}:"
  GITHUB_OUTPUT=/dev/stdout ci
}

case "${1:-}" in
  ci) ci ;;
  decide) [ $# -eq 4 ] || { echo "usage: $0 decide LANE SINCE_GREEN SINCE_BASE" >&2; exit 2; }; decide "$2" "$3" "$4" ;;
  classify) [ $# -eq 2 ] || { echo "usage: $0 classify LIST" >&2; exit 2; }; classify "$2" ;;
  dry-run) [ $# -eq 3 ] || { echo "usage: $0 dry-run PR HEAD" >&2; exit 2; }; dry_run "$2" "$3" ;;
  *) echo "usage: $0 ci | decide LANE SINCE_GREEN SINCE_BASE | classify LIST | dry-run PR HEAD" >&2; exit 2 ;;
esac
