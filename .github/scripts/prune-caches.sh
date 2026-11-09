#!/usr/bin/env bash
# Deletes a lane's older caches on this run's ref, after the lane saved one.
#
#   prune-caches.sh KEY SUFFIX
#
# KEY is the key the lane just saved, and SUFFIX the part of it that names
# this run: `$GITHUB_SHA-$GITHUB_RUN_ID-$GITHUB_RUN_ATTEMPT` for an outcome
# cache, `$GITHUB_RUN_ID-$GITHUB_RUN_ATTEMPT` for the fuzz inputs. The lane's
# prefix is KEY without SUFFIX, and the prefix a lane's last `restore-keys`
# line names.
#
# Every run and every attempt saves under a key of its own, and a cache stays
# until the repository's 10 GB are spent and the least recently used go. Left
# alone, the entries of every run of a pull request push out main's, which
# are the only ones a new pull request can restore. So once a lane has saved,
# the script deletes each cache that
#
#   - is stored under this run's ref ($GITHUB_REF), and no other: a pull
#     request's run never touches main's caches, nor main's run a pull
#     request's;
#   - has a key that starts with the lane's prefix, so another lane's caches
#     and this lane's under another `flake.lock` stay;
#   - is older than the cache KEY names, by id, which GitHub assigns in the
#     order caches are created, so a cache a concurrent run saved after this
#     one is kept, and the newest of a lane is never deleted.
#
# When KEY is not listed under the ref (its save was refused or failed), the
# script deletes nothing. A failure to list or to delete is printed as a
# warning and leaves the run green: a cache left behind is evicted later
# anyway.
# Wrong arguments exit 2 without calling `gh`.
set -u -o pipefail

if [ $# -ne 2 ] || [ -z "$1" ] || [ -z "$2" ]; then
  echo "usage: prune-caches.sh KEY SUFFIX" >&2
  exit 2
fi
key=$1
suffix=$2
case "$key" in
  ?*-"$suffix") ;;
  *)
    echo "the key $key does not end in -$suffix, so it names no lane prefix" >&2
    exit 2 ;;
esac
prefix=${key%"$suffix"}
if [ -z "${GITHUB_REF:-}" ] || [ -z "${GITHUB_REPOSITORY:-}" ]; then
  echo "GITHUB_REF and GITHUB_REPOSITORY name the ref and the repository to prune" >&2
  exit 2
fi
ref=$GITHUB_REF

# `--limit` past one page makes `gh` follow every page.
if ! listing=$(gh cache list --repo "$GITHUB_REPOSITORY" --ref "$ref" --key "$prefix" --limit 1000 \
  --json id,ref,key --jq '.[] | "\(.id)\t\(.ref)\t\(.key)"'); then
  echo "::warning title=cache prune::could not list the caches of $prefix on $ref; none deleted"
  exit 0
fi

kept=
while IFS=$'\t' read -r id entry_ref entry_key; do
  [ -n "$id" ] || continue
  if [ "$entry_ref" = "$ref" ] && [ "$entry_key" = "$key" ] && { [ -z "$kept" ] || [ "$id" -gt "$kept" ]; }; then
    kept=$id
  fi
done <<< "$listing"
if [ -z "$kept" ]; then
  echo "$key is not stored under $ref; no cache deleted"
  exit 0
fi
echo "keeping $key ($kept) on $ref"

while IFS=$'\t' read -r id entry_ref entry_key; do
  [ -n "$id" ] || continue
  [ "$entry_ref" = "$ref" ] || continue
  case "$entry_key" in "$prefix"*) ;; *) continue ;; esac
  [ "$id" -lt "$kept" ] || continue
  if gh cache delete --repo "$GITHUB_REPOSITORY" "$id"; then
    echo "deleted $entry_key ($id)"
  else
    echo "::warning title=cache prune::could not delete $entry_key ($id) on $ref"
  fi
done <<< "$listing"
