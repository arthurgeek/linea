#!/usr/bin/env bash
# Runs `prune-caches.sh` against a `gh` that answers from files, and checks
# which caches it deletes. Prints each mismatch and exits non-zero when there
# is one.
#
# The fake `gh` answers `cache list` with `$FAKE/caches`, lines of `id ref key`
# as the real call's `--jq` prints them, whatever filters the call names, so
# the script's own ref and prefix checks are what keep other entries. It
# appends each `cache list` call to `$FAKE/lists`, and each `cache delete`
# call to `$FAKE/deletes` and its id to `$FAKE/deleted`. Every call fails
# while `$FAKE/fail` exists, and a delete of id N fails while `$FAKE/fail-N`
# exists.
set -u -o pipefail

script=$(cd "$(dirname "$0")" && pwd)/prune-caches.sh
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
export FAKE=$work/fake
mkdir -p "$FAKE/bin"
failures=0

cat > "$FAKE/bin/gh" <<'EOF'
#!/usr/bin/env bash
[ -e "$FAKE/fail" ] && exit 1
case "$1 $2" in
  "cache list")
    echo "$*" >> "$FAKE/lists"
    cat "$FAKE/caches" 2>/dev/null ;;
  "cache delete")
    id=${*: -1}
    [ -e "$FAKE/fail-$id" ] && exit 1
    echo "$id" >> "$FAKE/deleted"
    echo "$*" >> "$FAKE/deletes" ;;
  *) exit 1 ;;
esac
exit 0
EOF
chmod +x "$FAKE/bin/gh"

pr=refs/pull/7/merge
main=refs/heads/main
lock=675bb9b1f1eb519845d9442de2dbdad0bd2ca1c4ee3004e5e338702cbe331177
check="outcomes-check-Linux-$lock-"
corpus="outcomes-optimised-corpus-Linux-$lock-"
a=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
b=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb

reset() { rm -f "$FAKE/caches" "$FAKE/lists" "$FAKE/deletes" "$FAKE/deleted" "$FAKE"/fail*; }
cache() { printf '%s\t%s\t%s\n' "$1" "$2" "$3" >> "$FAKE/caches"; }

# Runs the script as case $1 on ref $2 with the arguments after it.
run() {
  case_name=$1
  local ref=$2
  shift 2
  env PATH="$FAKE/bin:$PATH" GITHUB_REF="$ref" GITHUB_REPOSITORY=owner/repo \
    bash "$script" "$@" > "$work/log" 2>&1
  status=$?
}

fail() {
  echo "$case_name: $1"
  sed 's/^/    /' "$work/log"
  failures=$((failures + 1))
}

expect_status() { [ "$status" -eq "$1" ] || fail "exited $status, wanted $1"; }

# The ids deleted, in order, space-separated; nothing for none.
expect_deleted() {
  local got
  got=$(cat "$FAKE/deleted" 2>/dev/null | tr '\n' ' ' | sed 's/ $//')
  [ "$got" = "$1" ] || fail "deleted '${got}', wanted '$1'"
}

# Every older attempt and commit of the lane on the ref goes, the one just
# saved stays, and the one listing asked for every page of this ref.
reset
cache 30 "$pr" "${check}$b-200-1"
cache 20 "$pr" "${check}$a-100-2"
cache 10 "$pr" "${check}$a-100-1"
run "older entries of the lane on the ref" "$pr" "${check}$b-200-1" "$b-200-1"
expect_status 0
expect_deleted "20 10"
grep -q -- "^cache list --repo owner/repo --ref $pr --limit 1000 " "$FAKE/lists" ||
  fail "the listing was not scoped to the repository and the ref, or stopped short of every page"
grep -qx -- "cache delete --repo owner/repo 20" "$FAKE/deletes" || fail "the delete named no repository"

# Main's caches are never a pull request run's to delete, even where the
# listing returns them, and another lane's caches on the same ref stay.
reset
cache 30 "$pr" "${check}$b-200-1"
cache 5 "$main" "${check}$a-90-1"
cache 6 "$pr" "${corpus}$a-100-1"
run "another ref and another lane" "$pr" "${check}$b-200-1" "$b-200-1"
expect_status 0
expect_deleted ""

# On main the newest entry of a lane is the one kept.
reset
cache 3 "$main" "${check}$b-300-1"
cache 2 "$main" "${check}$a-200-1"
cache 1 "$main" "${check}$a-100-1"
run "main keeps the newest" "$main" "${check}$b-300-1" "$b-300-1"
expect_status 0
expect_deleted "2 1"

# A run on the same ref that saved after this one keeps its newer entry;
# only what is older than the cache just saved goes.
reset
cache 40 "$main" "${check}$b-400-1"
cache 30 "$main" "${check}$a-300-1"
cache 20 "$main" "${check}$a-200-1"
run "a newer save by a concurrent run" "$main" "${check}$a-300-1" "$a-300-1"
expect_status 0
expect_deleted "20"

# The lane under another `flake.lock` has another prefix and stays.
reset
cache 2 "$pr" "${check}$b-200-1"
cache 1 "$pr" "outcomes-check-Linux-0000-$a-100-1"
run "another flake.lock" "$pr" "${check}$b-200-1" "$b-200-1"
expect_status 0
expect_deleted ""

# Every lane named in one call is pruned from one listing, each by its own
# prefix and its own kept cache; a lane whose key was not saved loses
# nothing, and the others are still pruned.
reset
cache 31 "$pr" "${check}$b-200-1"
cache 21 "$pr" "${check}$a-100-1"
cache 32 "$pr" "${corpus}$b-200-1"
cache 22 "$pr" "${corpus}$a-100-1"
cache 12 "$pr" "${corpus}$a-90-1"
cache 23 "$pr" "fuzz-inputs-Linux-100-1"
run "every lane from one listing" "$pr" \
  "${check}$b-200-1" "$b-200-1" \
  "${corpus}$b-200-1" "$b-200-1" \
  "fuzz-inputs-Linux-200-1" "200-1"
expect_status 0
expect_deleted "21 22 12"
[ "$(wc -l < "$FAKE/lists" | tr -d ' ')" = 1 ] || fail "listed the caches more than once"

# The fuzz inputs name the run without a commit.
reset
cache 9 "$main" "fuzz-inputs-Linux-500-1"
cache 8 "$main" "fuzz-inputs-Linux-400-2"
run "the fuzz inputs" "$main" "fuzz-inputs-Linux-500-1" "500-1"
expect_status 0
expect_deleted "8"

# A key the listing does not hold under the ref was not saved there, so
# nothing is known to be older than it.
reset
cache 2 "$pr" "${check}$a-100-1"
cache 3 "$main" "${check}$b-200-1"
run "the saved key not listed under the ref" "$pr" "${check}$b-200-1" "$b-200-1"
expect_status 0
expect_deleted ""

reset
run "no caches at all" "$pr" "${check}$b-200-1" "$b-200-1"
expect_status 0
expect_deleted ""

# A listing that fails deletes nothing and leaves the lane green.
reset
cache 2 "$pr" "${check}$b-200-1"
cache 1 "$pr" "${check}$a-100-1"
touch "$FAKE/fail"
run "the listing failing" "$pr" "${check}$b-200-1" "$b-200-1"
expect_status 0
grep -q '^::warning ' "$work/log" || fail "no warning"

# A delete that fails is reported, and the rest still go.
reset
cache 3 "$pr" "${check}$b-200-1"
cache 2 "$pr" "${check}$a-100-2"
cache 1 "$pr" "${check}$a-100-1"
touch "$FAKE/fail-2"
run "one delete failing" "$pr" "${check}$b-200-1" "$b-200-1"
expect_status 0
expect_deleted "1"
grep -q '^::warning .*(2)' "$work/log" || fail "no warning for the failed delete"

# Arguments that name no lane prefix exit 2 before calling `gh`.
reset
cache 2 "$pr" "${check}$b-200-1"
cache 1 "$pr" "${check}$a-100-1"
run "a suffix the key does not end in" "$pr" "${check}$b-200-1" "$a-100-1"
expect_status 2
run "a suffix that is the whole key" "$pr" "$b-200-1" "$b-200-1"
expect_status 2
run "one argument" "$pr" "${check}$b-200-1"
expect_status 2
run "a key without its suffix after another lane" "$pr" "${check}$b-200-1" "$b-200-1" "${corpus}$b-200-1"
expect_status 2
run "a later lane naming no prefix" "$pr" "${check}$b-200-1" "$b-200-1" "${corpus}$b-200-1" "$a-100-1"
expect_status 2
run "no arguments" "$pr"
expect_status 2
run "no ref" "" "${check}$b-200-1" "$b-200-1"
expect_status 2
[ ! -e "$FAKE/lists" ] || { case_name="arguments"; fail "called gh"; }

if [ "$failures" -gt 0 ]; then
  echo "$failures mismatches"
  exit 1
fi
echo "every case pruned as expected"
