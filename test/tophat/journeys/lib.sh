# The journeys' shared steps: sourced by each journey in this folder, never
# run. A journey drives Stonks in the tophat's nested session through its
# commands (test/tophat.sh) alone, so every key and click takes the real
# input path, and keeps its evidence in a folder of its own:
#
#   steps.log           each step, what it did, and PASS or FAIL per check
#   NN-NAME.png         the nested output after a step, and NN-NAME.popup.png,
#                       the popup's part of it
#   NN-NAME.json        the data file Stonks wrote, after a step that saves
#   sounds.log          every sound Stonks asked the stand-in pw-play for
#   shell.log, stop.log the nested shell's log and the session's stop
#   result              PASS, or FAIL and the count
#
# A journey's arguments: [--slow SECONDS] [--zone ZONE] REF. It starts the
# session on REF, drives it, and stops it however it ends. The folder is
# JOURNEY_OUT, or else ~/Work/temporary/tophat/journeys/NAME/TIME-COMMIT,
# outside any cleanup.
#
# Pointer steps find their control through Stonks' locator (Locator.qml),
# which a commit from before it lacks: there a pointer step fails as
# unreachable and the key steps still run.
set -uo pipefail
journeys=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
checkout=$(cd "$journeys/../../.." && pwd)
tophat=$checkout/test/tophat.sh
tophat_base=${TOPHAT_BASE:-$HOME/Work/temporary/tophat}

failures=0
skipped=0
step_no=0
started=0
locator=0

say() { echo "$*" | tee -a "$out/steps.log"; }
pass() { say "PASS $*"; }
fail() { say "FAIL $*"; failures=$((failures + 1)); }
# check WHAT CMD…: CMD's success is WHAT holding.
check() { local what=$1; shift; if "$@"; then pass "$what"; else fail "$what"; fi; }
# need WHAT CMD…: as check, but the journey can't go on without it.
need() { local what=$1; shift; "$@" && { pass "$what"; return 0; }; fail "$what"; say "the journey can't go on"; exit 1; }
# within SECONDS CMD…: retry CMD until it succeeds or time runs out.
within() { local end=$((SECONDS + $1)); shift; until "$@"; do (( SECONDS < end )) || return 1; sleep 0.2; done; }
# soon WHAT SECONDS CMD…: as check, CMD given SECONDS to come true.
soon() { local what=$1 secs=$2; shift 2; if within "$secs" "$@"; then pass "$what"; else fail "$what"; fi; }

# step TEXT: a new step; its sounds and shots are numbered by it.
step() {
  step_no=$((step_no + 1))
  step_sounds=$(sound_count)
  say ""
  say "== $(printf %02d "$step_no") $*"
}

# journey_begin NAME ARGS…: the evidence folder, and the session on REF.
journey_begin() {
  journey=$1
  shift
  local opts=() ref
  while (( $# )); do
    case $1 in
      --slow|--zone) opts+=("$1" "${2:?$1 takes a value}"); shift 2 ;;
      -*) echo "journey: unknown option $1" >&2; exit 2 ;;
      *) break ;;
    esac
  done
  ref=${1:?usage: $journey.sh [--slow SECONDS] [--zone ZONE] REF}
  commit=$(git -C "$checkout" rev-parse --verify --quiet "$ref^{commit}") || { echo "journey: no such commit: $ref" >&2; exit 2; }
  out=${JOURNEY_OUT:-$tophat_base/journeys/$journey/$(date +%Y%m%d-%H%M%S)-${commit:0:7}}
  mkdir -p "$out" || exit 2
  : > "$out/steps.log"
  say "journey $journey on $ref ($commit)"
  say "evidence: $out"
  trap journey_end EXIT
  "$tophat" start "${opts[@]}" "$ref" > "$out/start.log" 2>&1 || { fail "the session started: $(tail -n 1 "$out/start.log")"; exit 1; }
  started=1
  run=$(sed -n 's/^run folder: //p' "$out/start.log")
  # shellcheck source=/dev/null
  [ -f "$run/identity" ] && source "$run/identity"
  need "the session runs $ref, from this checkout" ours
  data=$run/home/.config/omarchy/grvc.stonks.json
  step_sounds=$(sound_count)
  say "data file: $data"
  start_notice_gone || say "Hyprland's start notice was still moving after 25 s"
  if "$tophat" shell grvc.stonks.tophat where heroChart > /dev/null 2>&1; then
    locator=1
  else
    say "this commit has no locator (Locator.qml): its pointer steps are unreachable"
  fi
}

ours() { [ "${COMMIT:-}" = "$commit" ] && [ "${CHECKOUT:-}" = "$checkout" ]; }

# start_notice_gone: Hyprland's "started without start-hyprland" notice,
# whose bar shrinks for about 15 s in the output's top-right corner, has
# gone: two shots of that corner a second apart are the same.
start_notice_gone() {
  local tmp last="" now end=$((SECONDS + 25)) code=1
  tmp=$(mktemp -d)
  while (( SECONDS < end )); do
    "$tophat" shot "$tmp/corner.png" > /dev/null 2>&1 || break
    now=$(magick "$tmp/corner.png" -gravity northeast -crop 600x80+0+0 +repage rgba:- 2> /dev/null | md5sum)
    [ "$now" = "$last" ] && { code=0; break; }
    last=$now
    sleep 1
  done
  rm -rf "$tmp"
  return "$code"
}

journey_end() {
  local code=$?
  trap - EXIT
  # A journey's own undoing, such as a folder it made read-only.
  declare -F journey_cleanup > /dev/null && journey_cleanup
  "$tophat" sounds > "$out/sounds.log" 2> /dev/null
  "$tophat" log > "$out/shell.log" 2> /dev/null
  [ -f "${data:-}" ] && cp "$data" "$out/data.final.json"
  if (( started )); then
    "$tophat" stop > "$out/stop.log" 2>&1 || fail "the session stopped clean (stop.log)"
  fi
  if (( failures || code )); then echo "FAIL $failures" > "$out/result"
  elif (( skipped )); then echo "INCOMPLETE: $skipped steps unreachable" > "$out/result"
  else echo PASS > "$out/result"; fi
  say ""
  say "result: $(cat "$out/result")"
  say "evidence: $out"
  [ "$(cat "$out/result")" = PASS ]
  exit $?
}

# ---- the locator -------------------------------------------------------------

# matches NAME [--text T] [--has T] [--word W] [--symbol S]: the shown items
# named NAME, one JSON object a line, those whose words are T, hold T, start
# with the word W, or whose symbol is S.
matches() {
  local name=$1 text="" has="" word="" symbol=""
  shift
  while (( $# )); do
    case $1 in
      --text) text=$2 ;; --has) has=$2 ;; --word) word=$2 ;; --symbol) symbol=$2 ;;
      *) echo "journey: matches takes --text, --has, --word, or --symbol, not $1" >&2; return 2 ;;
    esac
    shift 2
  done
  (( locator )) || return 1
  "$tophat" shell grvc.stonks.tophat where "$name" 2> /dev/null \
    | jq -c --arg t "$text" --arg h "$has" --arg w "$word" --arg s "$symbol" \
    '.[] | select(.shown and .surface != "window" and ($t == "" or .text == $t)
      and ($h == "" or (.text | contains($h))) and ($w == "" or (.text | split(" ")[0]) == $w)
      and ($s == "" or .symbol == $s))'
}

# shown NAME [FILTERS]: at least one such item is on screen.
shown() { [ -n "$(matches "$@")" ]; }

# at NAME [FILTERS]: the centre of the one such item on screen, "X Y" on the
# nested output.
at() {
  local found count
  found=$(matches "$@") || { say "no locator: can't find $1"; return 1; }
  count=$(grep -c . <<< "$found")
  (( count == 1 )) || { say "$count shown items match $*"; return 1; }
  jq -r '"\((.x + .width / 2) | floor) \((.y + .height / 2) | floor)"' <<< "$found"
}

# words NAME [FILTERS]: what the shown items say, a line each, top to bottom.
words() { matches "$@" | jq -rs 'sort_by(.y, .x)[] | .text'; }

# readout NAME…: each shown item's words into the log, as evidence.
readout() {
  local name line
  (( locator )) || { say "  (no locator: no words read)"; return 0; }
  for name; do
    while IFS= read -r line; do say "  $name: $line"; done < <(words "$name")
  done
}

# ---- input -------------------------------------------------------------------

key() { "$tophat" key "$@" || fail "key $*"; sleep 0.25; }
typed() { "$tophat" type "$1" || fail "type $1"; }

# click_on NAME [FILTERS] [-- BUTTON]: click the item's centre.
click_on() {
  local args=() button=left xy
  while (( $# )); do [ "$1" = -- ] && { button=$2; break; }; args+=("$1"); shift; done
  xy=$(at "${args[@]}") || { fail "click ${args[*]}: not found"; return 1; }
  # shellcheck disable=SC2086
  "$tophat" click $xy "$button" > /dev/null || { fail "click ${args[*]} at $xy"; return 1; }
  sleep 0.25
}

# hover_on NAME [FILTERS]: two moves into the item, a row's first point being
# no move of its own (RowPointer.qml).
hover_on() {
  local xy x y
  xy=$(at "$@") || { fail "hover $*: not found"; return 1; }
  read -r x y <<< "$xy"
  "$tophat" move "$((x - 3))" "$y" > /dev/null && "$tophat" move "$x" "$y" > /dev/null || { fail "hover $* at $xy"; return 1; }
  sleep 0.2
}

# move_to X Y: one pointer move.
move_to() { "$tophat" move "$1" "$2" > /dev/null || fail "move to $1 $2"; sleep 0.15; }

# scroll_on NAME [FILTERS] -- NOTCHES: wheel notches over the item; positive
# scrolls down.
scroll_on() {
  local args=() notches xy
  while [ "$1" != -- ]; do args+=("$1"); shift; done
  notches=$2
  xy=$(at "${args[@]}") || { fail "scroll ${args[*]}: not found"; return 1; }
  # shellcheck disable=SC2086
  "$tophat" scroll $xy "$notches" > /dev/null || { fail "scroll ${args[*]} at $xy"; return 1; }
  sleep 0.25
}

# reachable WHAT: the locator is here for a pointer step; without it the step
# is reported unreachable, never passed.
reachable() {
  (( locator )) && return 0
  say "SKIP $*: this commit has no locator, so its pointer can't find the control"
  skipped=$((skipped + 1))
  return 1
}

# open_popup: the user's click on the pill, or, on a commit without the
# locator, the popup's IPC open, which a key binding sends.
open_popup() {
  if (( locator )); then
    click_on pillSymbol || click_on pillChange || return 1
    within 5 shown heroChart || { fail "the popup opened"; return 1; }
  else
    say "opening by IPC (omarchy-shell grvc.stonks open): no locator to find the pill"
    "$tophat" shell grvc.stonks open > /dev/null || { fail "the popup opened"; return 1; }
  fi
  # The popup takes the keyboard 75 ms after it maps (KeyboardPanel.qml).
  sleep 0.6
  pass "the popup opened"
}

# ---- evidence ----------------------------------------------------------------

# popup_rect: the popup's columns of the output, as magick's WxH+X+Y: the
# chart's, padded past the body's gutters, or else the output's middle 640
# pixels, where the popup hangs from the centred pill.
popup_rect() {
  local found h=${HEIGHT:-1000} w=${WIDTH:-1600}
  found=$(matches heroChart | head -n 1)
  if [ -n "$found" ]; then
    jq -r --argjson h "$h" '"\(.width + 80 | floor)x\($h)+\(.x - 40 | floor)+0"' <<< "$found"
  else
    echo "640x$h+$((w / 2 - 320))+0"
  fi
}

# shot NAME: the nested output, and the popup's part of it.
shot() {
  local file
  file=$(printf '%s/%02d-%s.png' "$out" "$step_no" "$1")
  "$tophat" shot "$file" > /dev/null || { fail "shot $1"; return 1; }
  magick "$file" -crop "$(popup_rect)" +repage "${file%.png}.popup.png" 2> /dev/null
  say "  shot $(basename "$file")"
}

# settle [SECONDS]: wait until the popup stops changing (fetched data in,
# motion done), or SECONDS (6) pass; a pulsing live dot never settles.
settle() {
  local end=$((SECONDS + ${1:-6})) last="" now tmp rect
  tmp=$(mktemp -d)
  rect=$(popup_rect)
  sleep 0.4
  while (( SECONDS < end )); do
    "$tophat" shot "$tmp/s.png" > /dev/null 2>&1 || break
    now=$(magick "$tmp/s.png" -crop "$rect" +repage rgba:- 2> /dev/null | md5sum)
    [ "$now" = "$last" ] && break
    last=$now
    sleep 0.4
  done
  rm -rf "$tmp"
}

# loaded: the chart's data is in: no "Loading" over it, then settled.
loaded() {
  if (( locator )); then
    sleep 0.5
    within 30 loading_gone || fail "the chart loaded"
  fi
  settle
}
loading_gone() { ! shown loadingLabel; }

# keep_data NAME: the data file as Stonks wrote it now.
keep_data() {
  local file
  file=$(printf '%s/%02d-%s.json' "$out" "$step_no" "$1")
  cp "$data" "$file" && say "  data file $(basename "$file")"
}

# saved JQ: the data file holds what the jq test JQ says.
saved() { jq -e "$1" "$data" > /dev/null 2>&1; }

# sound_count: how many sounds Stonks has asked for so far.
sound_count() { "$tophat" sounds 2> /dev/null | grep -c '^start '; }

# sounds_here: this step's sounds, into the log; heard PATTERN: one of them
# matches PATTERN.
step_sound_lines() { "$tophat" sounds 2> /dev/null | grep '^start ' | tail -n +"$((step_sounds + 1))"; }
sounds_here() {
  local line
  while IFS= read -r line; do say "  sound: ${line##*/}"; done < <(step_sound_lines)
}
heard() { step_sound_lines | grep -q -- "$1"; }
