#!/usr/bin/env bash
# Every unit-test file in this checkout (*.test.js, tracked or new, never an
# ignored one), each in a bun of its own. The files are found, never named,
# so a new or moved one can't be left out. test/all.sh and CI run this.
#
# A file that needs the saved answers says why and exits 77 without them
# (saved.test.js), which stops its own bun only. This exits 77 when one did
# and none failed.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
source "$PWD/test/scratch.sh"
# A tracked file deleted in this checkout is left out before the count.
files=()
while IFS= read -r -d '' file; do
  [ -e "$file" ] && files+=("$file")
done < <(git ls-files -z --cached --others --exclude-standard '*.test.js')
[ "${#files[@]}" -gt 0 ] || { echo "FAILED no *.test.js found"; exit 1; }
status=0
for file in "${files[@]}"; do
  echo "-- $file"
  # Named with ./: bare, bun takes it as a substring filter and also runs
  # every copy of that file, such as those under the ignored out/.
  bun test "./$file"
  code=$?
  if [ "$code" -eq 77 ]; then
    [ "$status" -eq 0 ] && status=77
  elif [ "$code" -ne 0 ]; then
    status=1
  fi
done
exit "$status"
