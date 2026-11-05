#!/usr/bin/env bash
# Prints the folder of Omarchy 4.0.6's shell, the oldest Stonks works on,
# for test/review.sh to run harnesses on (STONKS_SHELL, test/qml/lib.sh).
# The first run takes it from omacom/omarchy's v4.0.6 tag into the git
# folder every worktree shares, and later runs read it there. The tag must
# still name the commit it named when Stonks first ran on it, so a moved tag
# can't change the shell under the same version. Without the network on
# that first run, or with the tag moved, it says why and exits 1.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
version=4.0.6
commit=237f1b4071a0bff2296c6d740ba2b9fd695ebfa0
shells="$(git rev-parse --path-format=absolute --git-common-dir)/stonks-shells"
dir="$shells/$version"
if [ ! -f "$dir/shell/Ui/KeyboardPanel.qml" ] || [ "$(cat "$dir/commit" 2> /dev/null)" != "$commit" ]; then
  mkdir -p "$shells"
  tmp=$(mktemp -d "$shells/.fetch.XXXXXX")
  trap 'rm -rf "$tmp"' EXIT
  git -C "$tmp" init -q
  if ! git -C "$tmp" fetch -q --depth 1 https://github.com/omacom/omarchy "refs/tags/v$version" 2> "$tmp/error"; then
    echo "no Omarchy $version shell: fetching omacom/omarchy's v$version failed: $(head -1 "$tmp/error")" >&2
    exit 1
  fi
  fetched=$(git -C "$tmp" rev-parse 'FETCH_HEAD^{commit}')
  if [ "$fetched" != "$commit" ]; then
    echo "no Omarchy $version shell: omacom/omarchy's v$version names $fetched, not $commit" >&2
    exit 1
  fi
  mkdir "$tmp/tree"
  git -C "$tmp" archive "$commit" shell | tar -x -C "$tmp/tree"
  echo "$commit" > "$tmp/tree/commit"
  rm -rf "$dir"
  mv "$tmp/tree" "$dir"
fi
echo "$dir/shell"
