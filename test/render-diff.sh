#!/usr/bin/env bash
# What a change did to the pictures: compares the base's renders with the
# head's, state by state, and lists every one that changed, appeared, or went,
# each changed one beside its base in OUT/<state>.png (base left, head
# right). Nothing here judges a change: a changed picture is either meant,
# and the pull request says why, or a regression. test/review.sh runs it once
# both sets are rendered. Pixels compare exactly: two renders of one tree
# match, so any difference is the change's. A picture it can't read or write
# fails the run, since the list would then miss what it couldn't compare.
#
#   test/render-diff.sh BASE-FOLDER HEAD-FOLDER OUT-FOLDER
set -uo pipefail
base=$1 head=$2 out=$3
rm -rf "$out"
mkdir -p "$out"
names() { find "$1" -maxdepth 1 -name '*.png' -printf '%f\n' | sort; }
[ -n "$(names "$base")" ] || { echo "FAILED no base renders in $base"; exit 1; }
[ -n "$(names "$head")" ] || { echo "FAILED no head renders in $head"; exit 1; }

# One line per pair, four at a time: "changed STATE", or "unreadable STATE".
# Sizes compare first: compare pads a smaller picture with its edge pixels,
# so a surface grown by plain ground would pass as unchanged. Then compare
# exits 1 on a difference and 2 when it can't read a picture.
export base head
pairs=$(comm -12 <(names "$base") <(names "$head") | xargs -P 4 -I{} bash -c '
  sizes=$(magick identify -format "%wx%h " "$base/$1" "$head/$1" 2> /dev/null) || { echo "unreadable ${1%.png}"; exit 0; }
  read -r was now <<< "$sizes"
  if [ "$was" != "$now" ]; then echo "changed ${1%.png} ($was to $now)"; exit 0; fi
  magick compare -metric AE "$base/$1" "$head/$1" null: 2> /dev/null
  case $? in
    0) ;;
    1) echo "changed ${1%.png}" ;;
    *) echo "unreadable ${1%.png}" ;;
  esac' _ {} | sort)
changed=$(sed -n 's/^changed //p' <<< "$pairs")
unreadable=$(sed -n 's/^unreadable //p' <<< "$pairs")
new=$(comm -13 <(names "$base") <(names "$head") | sed 's/\.png$//')
gone=$(comm -23 <(names "$base") <(names "$head") | sed 's/\.png$//')

failed=0
while read -r state _; do
  [ -n "$state" ] || continue
  magick "$base/$state.png" "$head/$state.png" -background '#ff00ff' -splice 4x0 +append "$out/$state.png" \
    || { echo "FAILED could not write $out/$state.png"; failed=1; }
done <<< "$changed"
total=$(names "$head" | wc -l)
count() { [ -n "$1" ] && wc -l <<< "$1" || echo 0; }
echo "$(count "$changed") of $total pictures changed, $(count "$new") new, $(count "$gone") gone; side by side in $out"
[ -z "$changed" ] || sed 's/^/  changed /' <<< "$changed"
[ -z "$new" ] || sed 's/^/  new /' <<< "$new"
[ -z "$gone" ] || sed 's/^/  gone /' <<< "$gone"
[ -z "$unreadable" ] || { sed 's/^/FAILED could not compare /' <<< "$unreadable"; failed=1; }
exit "$failed"
