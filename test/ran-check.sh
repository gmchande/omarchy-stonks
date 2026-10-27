#!/usr/bin/env bash
# Proves test/ran.sh --passed on made-up run records in a scratch git
# repository, never this one's: a well-formed pass counts, and a record
# whose time taken isn't whole seconds and an s counts as no record, its
# text never run as a command. Prints FAILED per miss.
set -uo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$here/scratch.sh"
repo=$(mktemp -d)
trap 'rm -rf -- "$repo"' EXIT
failed=0
fail() { echo "FAILED $*"; failed=1; }

git init --quiet "$repo"
mkdir "$repo/test"
cp "$here/ran.sh" "$repo/test/ran.sh"
tree=$(git -C "$repo" mktree < /dev/null)
marker=$repo/ran
# passed TOOK: whether ran.sh --passed counts a pass that ended now and took
# TOOK.
passed() {
  echo "$tree $(printf '0%.0s' {1..40}) test/all.sh $(date -Iseconds) $1 ALL PASS" > "$repo/.git/stonks-runs"
  bash "$repo/test/ran.sh" --passed test/all.sh "$tree" 2> /dev/null
}

passed 5s || fail "a pass that took 5s isn't counted"
passed "BASH_VERSINFO[\$(printf\${IFS}ran>$marker)]s" && fail "a pass with a command for its time is counted"
[ -e "$marker" ] && fail "the time in a run record ran as a command"
exit "$failed"
