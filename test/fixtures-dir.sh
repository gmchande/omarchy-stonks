#!/usr/bin/env bash
# Prints the folder of saved answers the tests read: this checkout's own
# test/fixtures when it has one, otherwise the main checkout's, so a linked
# worktree reads the main checkout's copy without a link. Without either,
# as on a clone of the public repo, says why and exits 1.
cd "$(dirname "${BASH_SOURCE[0]}")/.."
if [ -d test/fixtures ]; then
  echo "$PWD/test/fixtures"
  exit 0
fi
common=$(git rev-parse --path-format=absolute --git-common-dir 2> /dev/null)
if [ -n "$common" ] && [ -d "${common%/.git}/test/fixtures" ]; then
  echo "${common%/.git}/test/fixtures"
  exit 0
fi
echo "no saved answers: test/fixtures is private and not in this checkout or its main checkout" >&2
exit 1
