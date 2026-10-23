#!/usr/bin/env bash
# The batch the lead runs after merges, from a clean checkout on dev. It
# brings dev up to date with origin, runs test/all.sh and then
# test/review.sh on it, and puts it live (test/live.sh) when they pass.
#
# When they fail, it finds the commit that broke them on dev's first-parent
# line since the live commit. It first runs the suites on the live commit,
# and stops if that fails too: the break came from outside dev, such as a
# package. Then it runs them on the commit halfway between the newest that
# passed and the oldest that failed until the two are neighbours. It
# reverts that commit on dev with a new commit, pushes dev, puts the last
# commit that passed live, says which pull request it reverted and which
# checks failed, and exits 1. A suite that exits 0 without ALL PASS on
# record (test/ran.sh --passed), as when checks skip, proves nothing either
# way, so the batch stops there, having reverted nothing.
#
# It pushes only dev, and never with force. It refuses while a tophat
# session holds the slot (test/tophat.sh), and holds the slot itself until
# it ends, so no walk starts that the shell's restart would fail. It refuses
# when the live commit isn't on dev: a branch build may be live for the
# owner to try. Each run's output is in out/batch/COMMIT.log.
#
#   test/batch.sh
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
live="$HOME/.config/omarchy/plugins/grvc.stonks"
say() { echo "batch: $*"; }
refuse() { echo "batch: refusing: $*" >&2; exit 1; }

# Fd 8 holds the slot; every command below runs without it (8>&-), so
# nothing it starts holds the slot past the batch.
exec 8>> "${TOPHAT_LOCK:-${XDG_RUNTIME_DIR:-/run/user/$UID}/tophat.lock}" || exit 1
flock -n 8 || refuse "a tophat session is running (test/tophat.sh holds its slot)"

[ "$(git symbolic-ref --quiet --short HEAD)" = dev ] || refuse "this checkout isn't on dev"
[ -z "$(git status --porcelain)" ] || refuse "this checkout has uncommitted edits or untracked files"
git fetch --quiet origin 8>&- || refuse "can't fetch origin"
git merge --ff-only --quiet origin/dev 8>&- || refuse "dev and origin/dev have diverged"
[ "$(git rev-list --count origin/dev..dev)" -eq 0 ] || refuse "dev has commits origin/dev doesn't"
was=$(git -C "$live" rev-parse HEAD)
git merge-base --is-ancestor "$was" dev || refuse "the live commit ${was:0:7} isn't on dev: a branch build may be live for the owner to try"
[ "$was" != "$(git rev-parse dev)" ] || { say "dev (${was:0:7}) is already live"; exit 0; }
mkdir -p out/batch

# suites DIR: runs both suites on DIR's checkout, into its commit's log,
# stopping at the first that fails. On a failure, why says what failed.
why=""
suites() {
  local commit runner log
  commit=$(git -C "$1" rev-parse HEAD)
  log=$PWD/out/batch/${commit:0:7}.log
  say "running the suites on $(git log -1 --format='%h %s' "$commit")"
  : > "$log"
  for runner in test/all.sh test/review.sh; do
    if (cd "$1" && "$runner") >> "$log" 2>&1 8>&-; then
      test/ran.sh --passed "$runner" "$commit" 2> /dev/null && continue
      say "$runner ended without ALL PASS on record for ${commit:0:7} (out/batch/${commit:0:7}.log): stopping, nothing reverted"
      exit 1
    fi
    why="$runner failed: $(awk '/^== / { label = substr($0, 4) } /^   FAILED/ { printf "%s%s", sep, label; sep = "; " }' "$log") (out/batch/${commit:0:7}.log)"
    say "$why"
    return 1
  done
  say "passed"
}

if suites .; then
  test/live.sh dev 8>&-
  exit
fi

# The first-parent line since the live commit, oldest first: the live
# commit stands at -1, once it passes again; the last one failed.
mapfile -t line < <(git rev-list --first-parent --reverse "$was..dev")
good=-1 bad=$((${#line[@]} - 1))
probe=$(mktemp -d)
trap 'git worktree remove --force "$probe/tree" 8>&- 2> /dev/null; rmdir "$probe"' EXIT
git worktree add --quiet --detach "$probe/tree" "$was" 8>&- || exit 1
suites "$probe/tree" || { say "the live commit ${was:0:7} fails too, so no merge since it broke dev: stopping, nothing reverted"; exit 1; }
while [ $((bad - good)) -gt 1 ]; do
  mid=$(((good + bad) / 2))
  git -C "$probe/tree" checkout --quiet --detach "${line[$mid]}" 8>&- || exit 1
  if suites "$probe/tree"; then good=$mid; else bad=$mid; fi
done
culprit=${line[$bad]}
if [ "$good" -ge 0 ]; then last=${line[$good]}; else last=$was; fi

subject=$(git log -1 --format=%s "$culprit")
pr=$(sed -nE 's/^Merge pull request (#[0-9]+) from (.+)$/\1 (\2)/p' <<< "$subject")
if [ -n "$pr" ]; then what="pull request ${pr%)}, merge ${culprit:0:7})"; else what="commit ${culprit:0:7} ($subject)"; fi
mainline=()
git rev-parse --quiet --verify "$culprit^2" > /dev/null && mainline=(-m 1)
if ! git revert --no-edit "${mainline[@]}" "$culprit" > /dev/null 8>&-; then
  git revert --abort 8>&-
  say "can't revert $what: it conflicts with a later commit; revert it by hand"
elif ! git push --quiet origin dev 8>&-; then
  say "reverted $what on dev, but the push was refused (dev moved on origin?): dev holds the revert, unpushed"
else
  say "reverted $what on dev and pushed $(git log -1 --format='%h' dev)"
fi
if [ "$last" = "$was" ]; then say "the last version that passed, ${last:0:7}, is already live"
else test/live.sh "$last" 8>&-; fi
say "$what broke dev: $why"
exit 1
