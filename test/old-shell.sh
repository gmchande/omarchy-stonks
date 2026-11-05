#!/usr/bin/env bash
# Prints the folder of Omarchy 4.0.6's shell, the oldest Stonks works on,
# for test/review.sh to run harnesses on (STONKS_SHELL, test/qml/lib.sh).
# The first run takes it from omacom/omarchy's v4.0.6 tag into the git
# folder every worktree shares, and later runs read it there. Without the
# network on that first run, it says why and exits 1.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
version=4.0.6
shells="$(git rev-parse --path-format=absolute --git-common-dir)/stonks-shells"
dir="$shells/$version"
if [ ! -f "$dir/shell/Ui/KeyboardPanel.qml" ]; then
  mkdir -p "$shells"
  tmp=$(mktemp -d "$shells/.fetch.XXXXXX")
  trap 'rm -rf "$tmp"' EXIT
  git -C "$tmp" init -q
  if ! git -C "$tmp" fetch -q --depth 1 https://github.com/omacom/omarchy "refs/tags/v$version" 2> "$tmp/error"; then
    echo "no Omarchy $version shell: fetching omacom/omarchy's v$version failed: $(head -1 "$tmp/error")" >&2
    exit 1
  fi
  mkdir "$tmp/tree"
  git -C "$tmp" archive FETCH_HEAD shell | tar -x -C "$tmp/tree"
  rm -rf "$dir"
  mv "$tmp/tree" "$dir"
fi
echo "$dir/shell"
