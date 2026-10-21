#!/usr/bin/env bash
# Tophat Stonks in a sandboxed nested Hyprland on the laptop screen, while
# the owner keeps working on the other screen.
#
#   start [--fresh] [--zone ZONE] [--slow SECONDS] REF
#                                  sandbox the committed REF and start the session;
#                                  --fresh: as a new user's machine, Stonks not
#                                  installed, a terminal open with REF's clone at ~/stonks;
#                                  --zone: the session's clocks in ZONE (Asia/Kolkata);
#                                  --slow: every curl in the session answers SECONDS
#                                  late (3), as on a weak hotspot
#   stop                           end it and report the isolation evidence
#   key KEY...                     keysym names; shift+j, ctrl+a, or J hold a modifier
#   type TEXT                      type text
#   move X Y                       move the pointer, in nested logical pixels
#   click X Y [BUTTON] [--mod M]…  left, right, or middle; M is shift, ctrl, alt, super
#   drag X1 Y1 X2 Y2               hold the left button through the motion
#   scroll X Y NOTCHES [--mod M]…  whole wheel notches; positive scrolls down
#   shot FILE                      screenshot the nested output
#   record start FILE | record stop
#   shell CMD…                     omarchy-shell inside the session
#   log                            the nested shell's log
#   sounds                         what the stand-in pw-play was asked to play
#   self-check                     the guards, without a screen
#
# Two identities, never mixed. The nested one (socket, instance, runtime
# folder), saved at start, is the only one input, grim, shell, and the nested
# shutdown use; a missing or dead session fails the command. The host one is
# used only for the preflight, the launch, the parent window's rectangle, and
# the recorder. Never ydotool: it writes to the kernel, which is the owner's
# seat.
set -uo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
checkout=$(cd "$here/.." && pwd)
host_runtime=${XDG_RUNTIME_DIR:-/run/user/$UID}
# The one slot, shared by every Stonks worktree: the laptop screen.
base=${TOPHAT_BASE:-$HOME/Work/temporary/tophat}
runtime=${TOPHAT_RUNTIME:-$host_runtime/tophat}
lock=${TOPHAT_LOCK:-$host_runtime/tophat.lock}
laptop=eDP-1
# System Python, standard library only: a version manager's shim on PATH
# reads config from the sandbox home and refuses to run.
python=${TOPHAT_PYTHON:-/usr/bin/python3}
# First-party services a second shell must not run: they reach the owner's
# clipboard watchers, lock, idle, brightness, polkit agent, and power profile.
services=(omarchy.clipboard omarchy.idle omarchy.lock omarchy.polkit omarchy.nightlight omarchy.battery)
# Known routes into the owner's session, logged and answered with success.
# They guard PATH lookups only: accident containment, not a security sandbox.
standins=(pkill pgrep killall pidwait uwsm uwsm-app systemctl systemd-run loginctl
  hyprlock 1password brightnessctl powerprofilesctl omarchy-powerprofiles-set
  omarchy-system-lock omarchy-system-wake omarchy-launch-screensaver
  omarchy-brightness-display omarchy-brightness-keyboard omarchy-hook
  omarchy-hyprland-monitor-clamshell)
# Stand-in calls a run may make, each with the shell source line that makes
# it. Any other call fails stop.
allowed=(
  # The menu's "when" for its stop-recording entry: default/omarchy/omarchy-menu.jsonc:55
  "pgrep -f ^gpu-screen-recorder"
  # The menu's "when" for its remove-SSHD entry: default/omarchy/omarchy-menu.jsonc:294
  "systemctl is-enabled --quiet sshd"
)

die() { echo "tophat: $*" >&2; exit 1; }

# within SECONDS CMD…: retry CMD until it succeeds or time runs out.
within() {
  local end=$((SECONDS + $1))
  shift
  until "$@"; do (( SECONDS < end )) || return 1; sleep 0.2; done
}

# stat_of, pgid_of, start_of, leader_is, group_ours, signal_group, marked.
source "$here/procs.sh"

# socket_paths_fit DIR [SIGNATURE]: the Wayland socket and both Hyprland
# sockets fit a Unix socket path (107 bytes). Without a signature, the
# longest this Hyprland can make: a 40-character commit, a 10-digit time,
# and a 10-digit random number.
socket_paths_fit() {
  local dir=$1 sig=${2:-$(printf 'x%.0s' {1..40})_1234567890_1234567890} path
  for path in "$dir/wayland-99" "$dir/hypr/$sig/.socket.sock" "$dir/hypr/$sig/.socket2.sock"; do
    if (( ${#path} > 107 )); then
      echo "tophat: socket path is ${#path} bytes, over 107: $path" >&2
      return 1
    fi
  done
}

# slot_free: nobody holds the one slot. Advisory: the launcher takes it
# atomically, and a launcher that loses the race starts nothing.
slot_free() {
  flock -n "$lock" true 2>/dev/null || { echo "tophat: the tophat slot is held ($lock): another session is running" >&2; return 1; }
}

# zone_ok ZONE: the system's time zone data knows ZONE. The C library runs
# a name it doesn't know as UTC, silently.
zone_ok() {
  local file=/usr/share/zoneinfo/$1
  [[ $1 =~ ^[A-Za-z0-9_+-]+(/[A-Za-z0-9_+-]+)*$ ]] && [ -f "$file" ] && [ "$(head -c 4 "$file")" = TZif ] \
    || { echo "tophat: the system knows no time zone ${1:-(none)} (/usr/share/zoneinfo)" >&2; return 1; }
}

# slow_ok SECONDS: a whole number of seconds, one or more.
slow_ok() {
  [[ $1 =~ ^[1-9][0-9]*$ ]] || { echo "tophat: --slow takes whole seconds, one or more, not '${1}'" >&2; return 1; }
}

# bus_ok: a private session bus starts with no display in its environment.
bus_ok() {
  env -i PATH="$PATH" HOME="$HOME" dbus-run-session -- true > /dev/null 2>&1 \
    || { echo "tophat: a private session bus (dbus-run-session) cannot start" >&2; return 1; }
}

# shell_json_ok FILE: the nested shell's config is valid version 1, turns off
# exactly the six services, and holds the pill, or on a fresh start holds
# none. An invalid one falls back to defaults, which turns every service
# back on.
shell_json_ok() {
  local want
  want=$(printf '%s\n' "${services[@]}" | jq -R . | jq -sc 'sort')
  jq -e --argjson want "$want" --argjson fresh "${fresh:-0}" 'type == "object" and .version == 1
    and ((.disabledPlugins // []) | sort) == $want
    and (if $fresh == 1 then all(.bar.layout[][]; .id != "grvc.stonks")
      else any(.bar.layout[][]; .id == "grvc.stonks") end)' "$1" > /dev/null 2>&1 \
    || { echo "tophat: $1 is not a valid isolation config" >&2; return 1; }
}

# nested_lua_ok FILE: Hyprland parses the generated config.
nested_lua_ok() {
  local tmp out
  tmp=$(mktemp -d) || return 1
  out=$(env -i HOME="$tmp" XDG_RUNTIME_DIR="$tmp" PATH="$PATH" Hyprland --verify-config -c "$1" 2>&1)
  local code=$?
  rm -rf "$tmp"
  (( code == 0 )) || { echo "tophat: $1 does not parse: $(tail -n 1 <<< "$out")" >&2; return 1; }
}

# ---- the sandbox ------------------------------------------------------------

# write_shell_json FILE BARSTYLE: a bar with workspaces and the pill only, or
# on a fresh start the workspaces alone.
write_shell_json() {
  printf '%s\n' "${services[@]}" | jq -R . | jq -s --arg style "$2" --argjson fresh "${fresh:-0}" '{
    version: 1,
    disabledPlugins: .,
    plugins: [],
    bar: ({
      position: "top", transparent: false,
      layout: {
        left: [{ id: "omarchy.workspaces" }],
        center: (if $fresh == 1 then [] else [{ id: "grvc.stonks" } + (if $style == "" then {} else { barStyle: $style } end)] end),
        right: []
      }
    } + (if $fresh == 1 then {} else { centerAnchor: "grvc.stonks" } end))
  }' > "$1"
}

# css_table OPTION: a host gap option as a Lua table.
css_table() {
  hyprctl -j getoption "$1" | jq -r '.css | split(" ") | map(tonumber)
    | "{ top = \(.[0]), right = \(.[1]), bottom = \(.[2]), left = \(.[3]) }"'
}

# write_nested_lua RUN: no Omarchy autostart (it imports the environment
# into the owner's systemd), no XWayland, scale 1, and the few compositor
# values the shell reads, taken from the host. A fresh start opens a
# terminal (foot, Omarchy's default config, bash) in the sandbox's home.
write_nested_lua() {
  local run=$1 gaps_in gaps_out border rounding layout terminal=""
  [ "${fresh:-0}" = 1 ] && terminal="hl.exec_cmd(\"foot --working-directory=$run/home bash\")"
  gaps_in=$(css_table general:gaps_in) && gaps_out=$(css_table general:gaps_out) \
    && border=$(hyprctl -j getoption general:border_size | jq -er .int) \
    && rounding=$(hyprctl -j getoption decoration:rounding | jq -er .int) \
    && layout=$(hyprctl -j getoption general:layout | jq -er .str) \
    || { echo "tophat: cannot read the host's gaps, border, rounding, and layout" >&2; return 1; }
  cat > "$run/nested.lua" << EOF
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1 })
hl.env("QT_QPA_PLATFORM", "wayland")
hl.env("XDG_CURRENT_DESKTOP", "Hyprland")
hl.env("XDG_SESSION_TYPE", "wayland")
hl.config({
  xwayland = { enabled = false },
  misc = { disable_hyprland_logo = true, disable_splash_rendering = true },
  ecosystem = { no_update_news = true, no_donation_nag = true },
  -- A warp would read as someone else moving the pointer.
  cursor = { no_warps = true },
  general = { gaps_in = $gaps_in, gaps_out = $gaps_out, border_size = $border, layout = "$layout" },
  decoration = { rounding = $rounding },
})
hl.on("hyprland.start", function()
  hl.exec_cmd("quickshell -n -p /usr/share/omarchy/shell > $run/shell.log 2>&1")
  $terminal
end)
EOF
}

# write_standins RUN: each logs its name and arguments and succeeds. And
# pw-play's, so the session plays no sound: it logs what it was asked to
# play to RUN/sounds.log, "start MS N ARGS", then "ended MS N" or "stopped
# MS N", N counting the starts, since chimes overlap; keeps a copy of the
# file as RUN/sound.N.wav; and stays for the sound's length, or until
# stopped, as a real player does. And pw-dump's, an empty list of nodes, so
# no microphone keeps the market's bell quiet; and pw-cat's, which logs each
# stream of silence that keeps the output awake to RUN/silence.log, "start
# MS ARGS" and "stopped MS", and holds no output.
write_standins() {
  local run=$1 name
  mkdir -p "$run/stubs"
  for name in "${standins[@]}"; do
    printf '#!/bin/sh\nprintf "%%s\\n" "%s $*" >> %q\nexit 0\n' "$name" "$run/stubs.log" > "$run/stubs/$name"
    chmod +x "$run/stubs/$name"
  done
  cat > "$run/stubs/pw-play" << EOF
#!/usr/bin/env bash
log=$(printf %q "$run/sounds.log")
ms() { echo \$(( \$(date +%s%N) / 1000000 )); }
exec 9>> "\$log.lock"
flock 9
n=\$(( \$(grep -c '^start ' "\$log" 2> /dev/null) + 1 ))
echo "start \$(ms) \$n \$*" >> "\$log"
flock -u 9
exec 9>&-
sleeper=""
trap '[ -n "\$sleeper" ] && kill "\$sleeper" 2> /dev/null; echo "stopped \$(ms) \$n" >> "\$log"; exit 0' TERM INT
file="\${!#}"
cp "\$file" $(printf %q "$run")/sound.\$n.wav 2> /dev/null
size=\$(stat -c %s "\$file" 2> /dev/null || echo 44)
rate=\$(od -An -t u4 -j 24 -N 4 "\$file" 2> /dev/null | tr -d ' ')
sleep "\$(awk -v s="\$size" -v r="\${rate:-48000}" 'BEGIN { printf "%.3f", (s - 44) / 2 / (r > 0 ? r : 48000) }')" &
sleeper=\$!
wait "\$sleeper"
echo "ended \$(ms) \$n" >> "\$log"
EOF
  chmod +x "$run/stubs/pw-play"
  printf '#!/bin/sh\necho "[]"\n' > "$run/stubs/pw-dump"
  chmod +x "$run/stubs/pw-dump"
  cat > "$run/stubs/pw-cat" << EOF
#!/usr/bin/env bash
log=$(printf %q "$run/silence.log")
ms() { echo \$(( \$(date +%s%N) / 1000000 )); }
trap 'echo "stopped \$(ms)" >> "\$log"; exit 0' TERM INT
echo "start \$(ms) \$*" >> "\$log"
while :; do sleep 0.2; done
EOF
  chmod +x "$run/stubs/pw-cat"
}

# write_slow_curl RUN SECONDS CURL: the session's curl, ahead of the real one
# on its PATH. Every Stonks request is one curl run (Fetch.js), so each
# answers SECONDS late; the sleep is before curl starts, so curl's own
# timeouts don't count it.
write_slow_curl() {
  mkdir -p "$1/slow" || return 1
  printf '#!/bin/sh\nsleep %s\nexec %q "$@"\n' "$2" "$3" > "$1/slow/curl" && chmod +x "$1/slow/curl"
}

# write_launcher RUN RUN_ID: the host compositor starts it as `setsid
# launch.sh`, so it leads this run's own session and process group. It takes
# the slot atomically and holds it until the session ends; the compositor it
# starts gets a clean environment, keeping only the host's exec-rule token,
# which is how the host places this launch's window, the start's zone, and,
# on a slow start, the slow curl ahead on its PATH.
write_launcher() {
  local run=$1 id=$2 tz="" slow_path=""
  [ -n "${zone:-}" ] && tz="TZ=$(printf %q "$zone") "
  [ -n "${slow:-}" ] && slow_path='$run/slow:'
  cat > "$run/launch.sh" << EOF
#!/usr/bin/env bash
run=$(printf %q "$run")
exec 9> $(printf %q "$lock")
flock -n 9 || { echo busy > "\$run/launch.status"; exit 0; }
# A start that gave up before this ran starts nothing.
[ -e "\$run/cancel" ] && exit 0
s=\$(cat /proc/\$\$/stat); s=\${s##*) }; read -r _ _ pgid sid _ <<< "\$s"
[ "\$pgid" = \$\$ ] && [ "\$sid" = \$\$ ] || { echo "not a session leader" > "\$run/launch.status"; exit 1; }
read -r -a f <<< "\$s"
echo "\$\$ \${f[19]}" > "\$run/leader"
rm -rf $(printf %q "$runtime") && mkdir -m 700 $(printf %q "$runtime") || { echo "no runtime folder" > "\$run/launch.status"; exit 1; }
echo started > "\$run/launch.status"
env -i HOME="\$run/home" XDG_CONFIG_HOME="\$run/home/.config" XDG_DATA_HOME="\$run/home/.local/share" \\
  XDG_STATE_HOME="\$run/home/.local/state" XDG_CACHE_HOME="\$run/home/.cache" \\
  XDG_RUNTIME_DIR=$(printf %q "$runtime") PATH="${slow_path}\$run/stubs:"$(printf %q "$PATH") \\
  OMARCHY_PATH=/usr/share/omarchy LANG=$(printf %q "${LANG:-C.UTF-8}") HYPRLAND_NO_SD_VARS=1 ${tz}\\
  TOPHAT_RUN=$(printf %q "$id") HL_EXEC_RULE_TOKEN="\${HL_EXEC_RULE_TOKEN:-}" \\
  dbus-run-session -- env WAYLAND_DISPLAY=$(printf %q "$host_socket") \\
  Hyprland --config "\$run/nested.lua" > "\$run/hyprland.log" 2>&1 9>&- &
wait \$!
echo "exited \$?" >> "\$run/launch.status"
EOF
  chmod +x "$run/launch.sh"
}

# build_sandbox RUN COMMIT: a minimal home, not a copy of ~/.config/omarchy.
# Its watchlist is the demo one (tophat/demo.json), never the owner's, so a
# screenshot names no one's lists. A fresh start has no plugin folder, data
# file, or cache: COMMIT is a clone at ~/stonks, the URL a new user's
# install is given (a relative path, so the installer's warning shows no
# home path), with a plain prompt and Omarchy's terminal config.
build_sandbox() {
  local run=$1 commit=$2 home=$1/home style
  mkdir -p "$home/.config/omarchy" "$home/.local/state/omarchy/current" \
    "$home/.local/share" "$home/.cache" || return 1
  if [ "${fresh:-0}" = 1 ]; then
    { git init -q -b main "$home/stonks" && git -C "$home/stonks" fetch -q "$checkout" "$commit" \
      && git -C "$home/stonks" reset -q --hard FETCH_HEAD && rm -f "$home/stonks/.git/FETCH_HEAD"; } \
      || { echo "tophat: cannot clone $commit" >&2; return 1; }
    printf '%s\n' "PS1='\\w \\\$ '" > "$home/.bashrc"
    mkdir -p "$home/.config/foot" && cp /usr/share/omarchy/config/foot/foot.ini "$home/.config/foot/" || return 1
  else
    mkdir -p "$home/.config/omarchy/plugins/grvc.stonks" || return 1
    git -C "$checkout" archive --format=tar "$commit" | tar -x -C "$home/.config/omarchy/plugins/grvc.stonks" \
      || { echo "tophat: cannot export $commit" >&2; return 1; }
    cp "$here/tophat/demo.json" "$home/.config/omarchy/grvc.stonks.json" || return 1
  fi
  style=$(jq -r '[.bar.layout[][]? | select(.id == "grvc.stonks") | .barStyle // empty][0] // ""' \
    "$HOME/.config/omarchy/shell.json" 2>/dev/null)
  write_shell_json "$home/.config/omarchy/shell.json" "$style" && shell_json_ok "$home/.config/omarchy/shell.json" || return 1
  # The theme as real files where Color.qml reads it.
  cp -rL "$HOME/.local/state/omarchy/current/theme" "$home/.local/state/omarchy/current/theme" || return 1
  cp -L "$HOME/.local/state/omarchy/current/background" "$home/.local/state/omarchy/current/background" 2>/dev/null
  if [ -d "$HOME/.config/fontconfig" ]; then cp -rL "$HOME/.config/fontconfig" "$home/.config/" || return 1; fi
  if [ -n "$(find "$home" -type l -print -quit)" ]; then
    echo "tophat: the sandbox holds a link back into the owner's home" >&2
    return 1
  fi
  write_standins "$run" && : > "$run/stubs.log"
}

# ---- the host ---------------------------------------------------------------

# host_preflight: prints the laptop's workspace when every precondition
# holds. It switches nothing: the workspace setter releases host buttons and
# can move focus.
host_preflight() {
  local locked mons ws
  omarchy-hyprland-session-locked; locked=$?
  (( locked == 1 )) || { echo "tophat: the session is locked, or its state is unknown ($locked)" >&2; return 1; }
  mons=$(hyprctl -j monitors all) || { echo "tophat: cannot read the host's monitors" >&2; return 1; }
  jq -e --arg m "$laptop" 'any(.[]; .name == $m and (.disabled | not) and .dpmsStatus)' <<< "$mons" > /dev/null \
    || { echo "tophat: the laptop screen ($laptop) is not on" >&2; return 1; }
  jq -e --arg m "$laptop" 'any(.[]; .focused and .name != $m)' <<< "$mons" > /dev/null \
    || { echo "tophat: the owner's focus is not on the other screen" >&2; return 1; }
  jq -e --arg m "$laptop" 'any(.[]; .name == $m and .specialWorkspace.id == 0)' <<< "$mons" > /dev/null \
    || { echo "tophat: the laptop screen shows a special workspace" >&2; return 1; }
  ws=$(jq -r --arg m "$laptop" '.[] | select(.name == $m) | .activeWorkspace.id' <<< "$mons")
  hyprctl -j workspaces | jq -e --argjson ws "$ws" 'any(.[]; .id == $ws and .windows == 0)' > /dev/null \
    || { echo "tophat: the laptop screen's workspace $ws is not empty" >&2; return 1; }
  echo "$ws"
}

# parent_window: the nested session's window on the host as "X Y W H", when
# it is mapped, unfocused, alone and visible on the laptop's shown workspace.
parent_window() {
  local mons clients
  mons=$(hyprctl -j monitors) && clients=$(hyprctl -j clients) || return 1
  jq -er --argjson pid "$HYPR_PID" --arg m "$laptop" --argjson mons "$mons" --argjson clients "$clients" '
    ($mons[] | select(.name == $m and .dpmsStatus and (.disabled | not))) as $lap
    | [.[] | select(.pid == $pid)] as $mine
    | select(($mine | length) == 1) | $mine[0]
    | select(.mapped and (.hidden | not) and .monitor == $lap.id
        and .workspace.id == $lap.activeWorkspace.id and $lap.specialWorkspace.id == 0
        and .focusHistoryID != 0)
    | select(([$clients[] | select(.workspace.id == $lap.activeWorkspace.id)] | length) == 1)
    | "\(.at[0]) \(.at[1]) \(.size[0]) \(.size[1])"' <<< "$clients"
}

# host_facts: the owner-session facts stop compares.
host_facts() {
  echo "clipboard watchers: $(pgrep -f 'wl-paste .*--watch' | sort -n | tr '\n' ' ')"
  echo "notifications owner: $(busctl --user status org.freedesktop.Notifications 2>/dev/null | grep -E '^(PID|Comm)=' | tr '\n' ' ')"
  echo "tray owner: $(busctl --user status org.kde.StatusNotifierWatcher 2>/dev/null | grep -E '^(PID|Comm)=' | tr '\n' ' ')"
  systemctl --user show-environment | grep -E '^(DISPLAY|WAYLAND_DISPLAY|HYPRLAND_INSTANCE_SIGNATURE|XDG_RUNTIME_DIR|PATH)=' | sed 's/^/systemd /'
  echo "screen brightness: $(brightnessctl -m -c backlight 2>/dev/null | cut -d, -f1,3)"
  echo "keyboard brightness: $(brightnessctl -m -d '*kbd_backlight' 2>/dev/null | cut -d, -f1,3)"
  echo "power profile: $(powerprofilesctl get 2>/dev/null)"
}

# ---- the run ----------------------------------------------------------------

# load_run: the current run's saved identity, or fail.
load_run() {
  [ -f "$base/current/identity" ] || die "no nested session: none was started, or it has stopped"
  run=$(readlink -f "$base/current")
  # shellcheck source=/dev/null
  source "$run/identity"
  [ "$CHECKOUT" = "$checkout" ] || die "the nested session belongs to $CHECKOUT"
}

leader_ok() { leader_is "${LEADER:-}" "${LEADER_START:-}"; }

# session_alive: the launcher, the nested compositor in its group, the saved
# socket, and the instance's lock file naming that compositor.
session_alive() {
  leader_ok || { echo "tophat: the run's launcher is gone" >&2; return 1; }
  [ -n "${HYPR_PID:-}" ] && [ "$(pgid_of "$HYPR_PID")" = "$LEADER" ] || { echo "tophat: the nested Hyprland is gone" >&2; return 1; }
  [ -S "$RUNTIME/$WAYLAND" ] || { echo "tophat: the nested socket $RUNTIME/$WAYLAND is gone" >&2; return 1; }
  [ "$(head -n 1 "$RUNTIME/hypr/$SIG/hyprland.lock" 2>/dev/null)" = "$HYPR_PID" ] \
    || { echo "tophat: the nested instance $SIG is not this run's" >&2; return 1; }
}

drive_prelude() {
  load_run
  session_alive || die "no live nested session: nothing was sent"
}

# nested CMD…: CMD sees only the saved nested identity.
nested() {
  env -i HOME="$run/home" XDG_CONFIG_HOME="$run/home/.config" XDG_STATE_HOME="$run/home/.local/state" \
    XDG_RUNTIME_DIR="$RUNTIME" WAYLAND_DISPLAY="$WAYLAND" HYPRLAND_INSTANCE_SIGNATURE="$SIG" \
    OMARCHY_PATH=/usr/share/omarchy PATH="$PATH" LANG="${LANG:-C.UTF-8}" "$@"
}

drive() { nested "$python" -B "$here/tophat/drive.py" "$RUNTIME/$WAYLAND" "$WIDTH" "$HEIGHT" "$@"; }

cursor_at() { nested hyprctl -j cursorpos | jq -r '"\(.x | round) \(.y | round)"'; }
near() { awk -v a="$1" -v b="$2" 'BEGIN { split(a, p, " "); split(b, q, " "); d1 = p[1] - q[1]; d2 = p[2] - q[2]; exit !(d1 * d1 <= 1 && d2 * d2 <= 1) }'; }

# pointer X Y CMD…: CMD moves the pointer to X Y. Before it, the pointer
# must be where this tool left it; a hand on the parent window moves it.
pointer() {
  local x=$1 y=$2 now
  shift 2
  if [ -f "$run/pointer" ]; then
    now=$(cursor_at)
    near "$(cat "$run/pointer")" "$now" \
      || die "the nested pointer is at $now, not $(cat "$run/pointer") where this tool left it: something else moved it; nothing was sent"
  fi
  drive "$@"
  local code=$?
  # Whatever the gesture did, the next pre-check compares against where it left the pointer.
  now=$(cursor_at) && echo "$now" > "$run/pointer"
  (( code == 0 )) || die "the pointer gesture failed"
  near "$now" "$x $y" || die "the pointer ended at $now, not $x $y"
}

# mods_of ARGS…: the --mod values as a comma list, or "-".
mods_of() {
  local mods=()
  while (( $# )); do
    [ "$1" = --mod ] && [ $# -ge 2 ] || die "expected --mod shift|ctrl|alt|super, got: $*"
    mods+=("$2"); shift 2
  done
  (( ${#mods[@]} )) && (IFS=,; echo "${mods[*]}") || echo -
}

cmd_key() {
  local k
  (( $# )) || die "usage: key KEY…"
  drive_prelude
  for k; do
    case $k in
      ?*+?*) drive key "$(tr + , <<< "${k%+*}")" "${k##*+}" || die "key $k failed" ;;
      [A-Z]) drive key shift "${k,,}" || die "key $k failed" ;;
      *) nested wtype -k "$k" || die "key $k failed" ;;
    esac
  done
}

cmd_click() {
  local x=${1:?usage: click X Y [BUTTON] [--mod M]…} y=${2:?usage: click X Y [BUTTON] [--mod M]…} button=left
  shift 2
  case ${1:-} in left|right|middle) button=$1; shift ;; esac
  local mods; mods=$(mods_of "$@") || exit 1
  drive_prelude
  pointer "$x" "$y" click "$x" "$y" "$button" "$mods"
}

cmd_scroll() {
  local x=${1:?usage: scroll X Y NOTCHES [--mod M]…} y=${2:?} notches=${3:?}
  shift 3
  local mods; mods=$(mods_of "$@") || exit 1
  drive_prelude
  pointer "$x" "$y" scroll "$x" "$y" "$notches" "$mods"
}

# ---- start ------------------------------------------------------------------

cmd_start() {
  fresh=0 zone="" slow=""
  while :; do
    case ${1:-} in
      --fresh) fresh=1; shift ;;
      --zone) zone=${2:-}; zone_ok "$zone" || exit 1; shift 2 ;;
      --slow) slow=${2:-}; slow_ok "$slow" || exit 1; shift 2 ;;
      *) break ;;
    esac
  done
  local ref=${1:?usage: start [--fresh] [--zone ZONE] [--slow SECONDS] REF} commit ws id answer tool curl=""
  commit=$(git -C "$checkout" rev-parse --verify --quiet "$ref^{commit}") || die "no such commit: $ref"
  for tool in Hyprland quickshell dbus-run-session python3 wtype grim gpu-screen-recorder setsid flock jq foot; do
    command -v "$tool" > /dev/null || die "$tool is not installed"
  done
  if [ -n "$slow" ]; then curl=$(command -v curl) || die "curl is not installed"; fi
  case ${WAYLAND_DISPLAY:-} in
    "") die "no host display: start runs from the owner's session" ;;
    /*) host_socket=$WAYLAND_DISPLAY ;;
    *) host_socket=$host_runtime/$WAYLAND_DISPLAY ;;
  esac
  slot_free && socket_paths_fit "$runtime" && bus_ok || exit 1
  # The slot is free, so whatever current names has ended.
  rm -f "$base/current"
  ws=$(host_preflight) || exit 1

  id=$(date +%Y%m%d-%H%M%S)-${commit:0:7}
  run=$base/$id
  [[ $run =~ ^[A-Za-z0-9/._-]+$ ]] || die "the run folder $run needs a plain path"
  mkdir -p "$run" || die "cannot make $run"
  echo "run folder: $run"
  build_sandbox "$run" "$commit" && { [ -z "$slow" ] || write_slow_curl "$run" "$slow" "$curl"; } \
    && write_nested_lua "$run" && nested_lua_ok "$run/nested.lua" \
    && write_launcher "$run" "$id" || die "the sandbox is not ready; nothing was launched"
  host_facts > "$run/host-before"
  { printf 'RUN_ID=%q\nCHECKOUT=%q\nCOMMIT=%q\nSTART_EPOCH=%q\nRUNTIME=%q\nZONE=%q\nSLOW=%q\n' "$id" "$checkout" "$commit" "$(date +%s)" "$runtime" "$zone" "$slow"; } > "$run/identity"
  trap 'start_failed "interrupted"' INT TERM

  # One launch-scoped rule: the host places this launch's window on the
  # laptop's shown workspace and never focuses it. It matches the token the
  # host puts in the launch's environment, is dropped once it has placed
  # the window, and survives a host config reload.
  answer=$(hyprctl eval "hl.exec_cmd(\"setsid $run/launch.sh\", { workspace = \"$ws silent\", no_focus = true, no_initial_focus = true })")
  [ "$answer" = ok ] || start_failed "the host did not take the launch: $answer"

  within 15 test -s "$run/launch.status" || start_failed "the launcher never reported"
  [ "$(head -n 1 "$run/launch.status")" = started ] || start_failed "the launcher: $(head -n 1 "$run/launch.status")"
  # This run holds the slot: only now does it become the current one.
  ln -sfn "$run" "$base/current"
  read -r LEADER LEADER_START < "$run/leader"
  printf 'LEADER=%q\nLEADER_START=%q\n' "$LEADER" "$LEADER_START" >> "$run/identity"
  within 30 find_instance || start_failed "the nested Hyprland never came up"
  socket_paths_fit "$runtime" "$SIG" || start_failed "the nested sockets do not fit"
  printf 'HYPR_PID=%q\nSIG=%q\nWAYLAND=%q\n' "$HYPR_PID" "$SIG" "$WAYLAND" >> "$run/identity"
  source "$run/identity"
  within 15 parent_window > /dev/null || start_failed "the session's window is not alone, unfocused, and shown on $laptop's workspace $ws"
  within 60 shell_up || start_failed "the nested shell never answered"
  services_off || start_failed "a service that must be off is running"
  if (( fresh )); then
    within 30 terminal_up || start_failed "the terminal never opened"
  else
    within 30 nested omarchy-shell grvc.stonks close > /dev/null 2>&1 || start_failed "the Stonks pill never loaded"
  fi
  read -r WIDTH HEIGHT < <(nested hyprctl -j monitors | jq -r '.[0] | "\(.width) \(.height)"')
  printf 'WIDTH=%q\nHEIGHT=%q\n' "$WIDTH" "$HEIGHT" >> "$run/identity"
  note_pids
  trap - INT TERM
  echo "commit: $commit"
  echo "nested output: ${WIDTH}x$HEIGHT on $laptop, workspace $ws"
  if (( fresh )); then echo "fresh: Stonks not installed; in the terminal, its clone is ~/stonks"; fi
  if [ -n "$zone" ]; then echo "zone: $zone, $(TZ=$zone date +'%H:%M %Z') there"; fi
  if [ -n "$slow" ]; then echo "slow: every curl in the session answers $slow s late"; fi
}

# find_instance: this run's Hyprland instance, from its lock file.
find_instance() {
  local file pid
  note_pids
  for file in "$runtime"/hypr/*/hyprland.lock; do
    [ -f "$file" ] || continue
    pid=$(head -n 1 "$file")
    [ "$(pgid_of "$pid")" = "$LEADER" ] || continue
    HYPR_PID=$pid
    SIG=$(basename "$(dirname "$file")")
    WAYLAND=$(sed -n 2p "$file")
    [ -S "$runtime/$WAYLAND" ] && return 0
  done
  return 1
}

shell_up() { note_pids; [ "$(nested omarchy-shell shell ping 2>/dev/null)" = ok ]; }
terminal_up() { note_pids; nested hyprctl -j clients | jq -e 'any(.[]; .class == "foot")' > /dev/null; }

# note_pids: the group's members so far, for the core-dump check.
note_pids() { pgrep -g "$LEADER" >> "$run/pids"; }

services_off() {
  local plugins id ok=0
  plugins=$(nested omarchy-shell shell listPlugins) || return 1
  for id in "${services[@]}"; do
    jq -e --arg id "$id" 'any(.[]; .id == $id and .enabled == false)' <<< "$plugins" > /dev/null \
      || { echo "tophat: $id is not off in the nested shell" >&2; ok=1; }
  done
  if (( fresh )); then
    jq -e 'all(.[]; .id != "grvc.stonks")' <<< "$plugins" > /dev/null \
      || { echo "tophat: grvc.stonks is known to the nested shell before its install" >&2; ok=1; }
  else
    jq -e 'any(.[]; .id == "grvc.stonks" and .enabled)' <<< "$plugins" > /dev/null \
      || { echo "tophat: grvc.stonks is not on in the nested shell" >&2; ok=1; }
  fi
  return "$ok"
}

start_failed() {
  trap - INT TERM
  echo "tophat: $*; stopping" >&2
  touch "$run/cancel"
  # A launcher checks for cancel only once it holds the slot. If the slot is
  # held, ours may be past that check: wait for it to report.
  flock -n "$lock" true 2> /dev/null || within 15 test -s "$run/launch.status"
  source "$run/identity"
  stop_run
  exit 1
}

# ---- stop -------------------------------------------------------------------

# The run's mark: everything the nested session starts carries it.
mark() { echo "TOPHAT_RUN=$RUN_ID"; }
ours() { [ -n "${LEADER:-}" ] && group_ours "$LEADER" "${LEADER_START:-}" "$(mark)"; }
group_alive() { pgrep -g "$LEADER" > /dev/null; }
group_gone() { ! group_alive; }

# end_session: ask the nested compositor to exit, then signal what is left
# of the group (the bus's activated services outlive it) until it is empty.
end_session() {
  ours || return 0
  note_pids
  if session_alive 2> /dev/null; then
    nested hyprctl eval 'hl.dispatch(hl.dsp.exit())' > /dev/null 2>&1
    within 10 bash -c "! kill -0 $HYPR_PID 2>/dev/null"
    within 2 group_gone && return 0
  fi
  signal_group TERM "$LEADER" "${LEADER_START:-}" "$(mark)"
  within 5 group_gone && return 0
  signal_group KILL "$LEADER" "${LEADER_START:-}" "$(mark)"
  within 5 group_gone
}

# stop_run: end everything this run started and report what it saw.
# Returns non-zero on anything the run may have caused.
stop_run() {
  local status=0 line blocked dumps errors
  # A start that failed early recorded its group only in the leader file.
  if [ -z "${LEADER:-}" ] && [ -s "$run/leader" ]; then read -r LEADER LEADER_START < "$run/leader"; fi
  [ -f "$run/recorder" ] && { record_stop || status=1; }
  end_session || { echo "FAILED the session's group did not end" >&2; status=1; }
  sleep 0.5
  # Processes that carry the run's mark but left its group: reported, never
  # signalled.
  line=$(marked "$(mark)")
  [ -n "$line" ] && { echo "FAILED processes left the run's group and are still running (not signalled):" >&2; echo "$line" >&2; status=1; }
  if [ -s "$run/stubs.log" ]; then
    while read -r line; do
      blocked=1
      for a in "${allowed[@]}"; do [ "$line" = "$a" ] && blocked=0; done
      (( blocked )) && { echo "FAILED blocked attempt: $line" >&2; status=1; } || echo "allowed stand-in call: $line"
    done < "$run/stubs.log"
  fi
  errors=$(grep -nE 'TypeError|ReferenceError|Error:' "$run/shell.log" 2> /dev/null)
  [ -n "$errors" ] && { echo "FAILED runtime errors in the nested shell's log:" >&2; echo "$errors" >&2; status=1; }
  line=$(grep -in polkit "$run/shell.log" 2> /dev/null)
  [ -n "$line" ] && { echo "FAILED the nested shell's log names polkit:" >&2; echo "$line" >&2; status=1; }
  dumps=$(coredumpctl --no-pager --json=short list --since="@${START_EPOCH:-0}" 2> /dev/null \
    | jq -r --argjson pids "[$(sort -un "$run/pids" 2> /dev/null | paste -sd,)]" '.[] | select(.pid as $p | $pids | index($p)) | "\(.pid) \(.exe)"' 2> /dev/null)
  [ -n "$dumps" ] && { echo "FAILED a process dumped core: $dumps. Use the diagnose-crash skill; do not relaunch." >&2; status=1; }
  if [ -f "$run/host-before" ]; then
    host_facts > "$run/host-after"
    if ! diff -q "$run/host-before" "$run/host-after" > /dev/null; then
      echo "UNEXPLAINED owner-session facts changed during the run (the owner may have changed them):" >&2
      diff "$run/host-before" "$run/host-after" | grep '^[<>]' >&2
      status=1
    fi
  fi
  [ "$(readlink -f "$base/current")" = "$run" ] && rm -f "$base/current"
  echo "artifacts: $run"
  return "$status"
}

cmd_stop() {
  load_run
  stop_run && echo "stopped clean" || { echo "stopped, with the findings above" >&2; exit 1; }
}

# ---- capture ----------------------------------------------------------------

cmd_record() {
  case ${1:-} in
    start) record_start "${2:?usage: record start FILE}" ;;
    stop) load_run; record_stop ;;
    *) die "usage: record start FILE | record stop" ;;
  esac
}

record_start() {
  local file rect
  drive_prelude
  [ -f "$run/recorder" ] && die "already recording"
  rect=$(parent_window) || die "the session's window is not alone, unfocused, and shown on $laptop"
  file=$(realpath -m "$1")
  rm -f "$run/record.status"
  echo "$file" > "$run/record.file"
  setsid "$here/tophat.sh" _record-watch "$file" $rect > "$run/record.log" 2>&1 < /dev/null &
  within 10 test -s "$run/record.status" || die "the recorder did not start: $(cat "$run/record.log")"
  echo "recording $rect (host logical x y w h) to $file"
}

# _record-watch FILE X Y W H: leads its own group with the recorder, and
# stops it when the capture conditions are lost. It never wakes a screen or
# moves a window to recover.
record_watch() {
  local file=$1 x=$2 y=$3 w=$4 h=$5 fps rec stopping=0 now
  load_run
  echo "$$ $(start_of $$)" > "$run/recorder"
  fps=$(hyprctl -j monitors | jq -r --arg m "$laptop" '.[] | select(.name == $m) | .refreshRate | round')
  gpu-screen-recorder -w region -region "${w}x$h+$x+$y" -f "$fps" -fm cfr -k h264 -q ultra -o "$file" &
  rec=$!
  # TERM, not INT: a background job starts with INT ignored, and an ignored
  # signal cannot be trapped.
  trap 'stopping=1' TERM
  echo recording > "$run/record.status"
  while kill -0 "$rec" 2> /dev/null; do
    sleep 0.5
    (( stopping )) && break
    omarchy-hyprland-session-locked; [ $? -eq 1 ] || { lost "the session locked, or its state is unknown"; break; }
    now=$(parent_window) || { lost "the window left the laptop's shown workspace, or is focused or not alone"; break; }
    [ "$now" = "$x $y $w $h" ] || { lost "the window moved to $now"; break; }
  done
  kill -INT "$rec" 2> /dev/null
  wait "$rec"
  (( stopping )) && echo saved > "$run/record.status"
}
lost() { echo "interrupted: $1" > "$run/record.status"; }

record_stop() {
  local leader start file
  [ -f "$run/recorder" ] || die "not recording"
  read -r leader start < "$run/recorder"
  if [ "$(start_of "$leader")" = "$start" ] && [ "$(pgid_of "$leader")" = "$leader" ]; then
    kill -TERM "$leader"
    within 20 bash -c "! kill -0 $leader 2>/dev/null" || echo "tophat: the recorder did not stop" >&2
  fi
  rm -f "$run/recorder"
  echo "recording: $(cat "$run/record.status")"
  file=$(cat "$run/record.file")
  [ -f "$file" ] && echo "$file: $(ffprobe -v error -count_frames -select_streams v:0 -show_entries stream=nb_read_frames -of csv=p=0 "$file") frames"
  ! grep -q '^interrupted' "$run/record.status"
}

# ---- self-check -------------------------------------------------------------

# Each guard fails where it must, with no screen: nothing here launches a
# compositor or reaches a display. Prints FAILED per miss.
self_check() {
  local failed=0 out
  check_tmp=$(mktemp -d /tmp/tophat-check.XXXXXX) || exit 1
  local tmp=$check_tmp
  # Whatever a failed step left: the stand-in session's group and its escapee.
  trap '[ -f "$check_tmp/base/fake/leader" ] && kill -KILL -- "-$(cut -d" " -f1 "$check_tmp/base/fake/leader")" 2>/dev/null
    [ -f "$check_tmp/escapee" ] && kill "$(cat "$check_tmp/escapee")" 2>/dev/null; rm -rf "$check_tmp"' EXIT
  miss() { echo "FAILED $*"; failed=1; }
  export TOPHAT_BASE=$tmp/base TOPHAT_RUNTIME=$tmp/rt TOPHAT_LOCK=$tmp/lock TOPHAT_PYTHON=$tmp/tools/python3
  base=$TOPHAT_BASE runtime=$TOPHAT_RUNTIME lock=$TOPHAT_LOCK
  # The guards run on these; a missing one is named, not buried in a miss.
  for t in Hyprland dbus-run-session flock setsid pgrep jq; do
    command -v "$t" > /dev/null || { echo "FAILED $t is not installed: the guards cannot run"; return 1; }
  done
  mkdir -p "$tmp/base" "$tmp/tools"
  # Every tool a drive command could reach, logged: a guard that lets one
  # through shows here.
  for t in python3 wtype grim omarchy-shell hyprctl ydotool gpu-screen-recorder; do
    printf '#!/bin/sh\necho "%s $*" >> %q\n' "$t" "$tmp/reached" > "$tmp/tools/$t"; chmod +x "$tmp/tools/$t"
  done
  local drives=("key j" "key shift+j" "type abc" "move 1 1" "click 1 1" "drag 1 1 2 2" "scroll 1 1 1 --mod shift" "shot $tmp/x.png" "shell shell ping" "record start $tmp/x.mp4")
  expect_refused() {  # LABEL: every drive command fails and reaches nothing
    local cmd
    for cmd in "${drives[@]}"; do
      # shellcheck disable=SC2086
      out=$(PATH="$tmp/tools:$PATH" WAYLAND_DISPLAY=wayland-1 HYPRLAND_INSTANCE_SIGNATURE=${HYPRLAND_INSTANCE_SIGNATURE:-host} \
        bash "$here/tophat.sh" $cmd 2>&1) && miss "$1: '$cmd' succeeded"
      [ -s "$tmp/reached" ] && { miss "$1: '$cmd' reached $(cat "$tmp/reached")"; rm -f "$tmp/reached"; }
    done
  }
  expect_refused "no session"

  # A dead session: a saved identity whose launcher has exited.
  local dead=$tmp/base/dead
  mkdir -p "$dead" "$tmp/rt"
  setsid sleep 60 & local gone=$!
  sleep 0.1
  local gone_start; gone_start=$(start_of "$gone")
  kill "$gone"; wait "$gone" 2> /dev/null
  printf 'RUN_ID=dead\nCHECKOUT=%q\nRUNTIME=%q\nLEADER=%s\nLEADER_START=%s\nHYPR_PID=%s\nSIG=x\nWAYLAND=wayland-1\nWIDTH=100\nHEIGHT=100\n' \
    "$checkout" "$tmp/rt" "$gone" "$gone_start" "$gone" > "$dead/identity"
  ln -sfn "$dead" "$tmp/base/current"
  expect_refused "dead session"
  rm -f "$tmp/base/current"

  # Socket paths.
  socket_paths_fit /run/user/1000/tophat 2> /dev/null || miss "the default runtime folder's sockets should fit"
  socket_paths_fit "/tmp/$(printf 'r%.0s' {1..40})" 2> /dev/null && miss "a 45-byte runtime folder's Hyprland sockets should not fit"
  socket_paths_fit /run/user/1000/tophat "$(printf 's%.0s' {1..90})" 2> /dev/null && miss "a long real signature should not fit"

  # The isolation config.
  write_shell_json "$tmp/shell.json" sparkline
  shell_json_ok "$tmp/shell.json" 2> /dev/null || miss "the generated shell.json should pass"
  local bad
  for bad in '.version = 2' '.disabledPlugins -= ["omarchy.battery"]' 'del(.disabledPlugins)' '.bar.layout.center = []'; do
    jq "$bad" "$tmp/shell.json" > "$tmp/bad.json"
    shell_json_ok "$tmp/bad.json" 2> /dev/null && miss "shell.json with '$bad' should fail"
  done
  echo '{ "version": 1,' > "$tmp/bad.json"
  shell_json_ok "$tmp/bad.json" 2> /dev/null && miss "unparseable shell.json should fail"
  # A fresh start's: no pill until the install puts one there.
  local pill=$tmp/shell.json
  fresh=1
  write_shell_json "$tmp/fresh.json" ""
  shell_json_ok "$tmp/fresh.json" 2> /dev/null || miss "the generated fresh shell.json should pass"
  shell_json_ok "$pill" 2> /dev/null && miss "a fresh start's shell.json with the pill should fail"
  jq '.bar.layout.right = [{ id: "grvc.stonks" }]' "$tmp/fresh.json" > "$tmp/bad.json"
  shell_json_ok "$tmp/bad.json" 2> /dev/null && miss "a fresh start's shell.json with the pill on the right should fail"
  fresh=0
  printf 'hl.config({ general = { gaps_in = 5 } })\n' > "$tmp/ok.lua"
  nested_lua_ok "$tmp/ok.lua" 2> /dev/null || miss "a valid nested.lua should pass"
  printf 'hl.config({ general = { gaps_inn = 5 } })\n' > "$tmp/bad.lua"
  nested_lua_ok "$tmp/bad.lua" 2> /dev/null && miss "an invalid nested.lua should fail"

  # The session's zone: one the system doesn't know starts nothing.
  for bad in Nowhere/City ../../etc/passwd Asia ""; do
    zone_ok "$bad" 2> /dev/null && miss "the zone '$bad' should be refused"
  done
  zone_ok Asia/Kolkata 2> /dev/null || miss "Asia/Kolkata should be a known zone"
  local runs; runs=$(ls "$tmp/base" | wc -l)
  out=$(PATH="$tmp/tools:$PATH" WAYLAND_DISPLAY=wayland-1 bash "$here/tophat.sh" start --zone Nowhere/City HEAD 2>&1) \
    && miss "a start in an unknown zone succeeded"
  [ "$(ls "$tmp/base" | wc -l)" = "$runs" ] || miss "a start in an unknown zone made a run folder"
  [ -s "$tmp/reached" ] && { miss "a start in an unknown zone reached $(cat "$tmp/reached")"; rm -f "$tmp/reached"; }

  # The slow curl: a delay that isn't whole seconds starts nothing.
  for bad in 0 -1 1.5 abc ""; do
    slow_ok "$bad" 2> /dev/null && miss "the delay '$bad' should be refused"
  done
  slow_ok 3 2> /dev/null || miss "a delay of 3 should be taken"
  out=$(PATH="$tmp/tools:$PATH" WAYLAND_DISPLAY=wayland-1 bash "$here/tophat.sh" start --slow abc HEAD 2>&1) \
    && miss "a start with the delay 'abc' succeeded"
  [ "$(ls "$tmp/base" | wc -l)" = "$runs" ] || miss "a start with the delay 'abc' made a run folder"
  [ -s "$tmp/reached" ] && { miss "a start with the delay 'abc' reached $(cat "$tmp/reached")"; rm -f "$tmp/reached"; }
  # It hands the real curl its arguments, as given, a second late, and
  # returns its exit.
  printf '#!/bin/sh\nprintf "%%s\\n" "$@" > %q\nexit 7\n' "$tmp/curl-args" > "$tmp/real-curl"; chmod +x "$tmp/real-curl"
  write_slow_curl "$tmp/slow-run" 1 "$tmp/real-curl"
  local began took code
  began=$(date +%s%N)
  "$tmp/slow-run/slow/curl" -sS 'a b' '$HOME' > /dev/null 2>&1; code=$?
  took=$(( ($(date +%s%N) - began) / 1000000 ))
  (( took >= 1000 )) || miss "the slow curl should answer a second late, took $took ms"
  (( code == 7 )) || miss "the slow curl should return the real curl's exit 7, got $code"
  [ "$(cat "$tmp/curl-args" 2> /dev/null)" = "$(printf '%s\n' -sS 'a b' '$HOME')" ] \
    || miss "the slow curl should pass its arguments as given, got: $(cat "$tmp/curl-args" 2> /dev/null)"

  # The private bus.
  bus_ok 2> /dev/null || miss "a private bus should start here"
  mkdir -p "$tmp/nobus"; printf '#!/bin/sh\nexit 1\n' > "$tmp/nobus/dbus-run-session"; chmod +x "$tmp/nobus/dbus-run-session"
  PATH="$tmp/nobus:$PATH" bus_ok 2> /dev/null && miss "a bus that cannot start should fail"

  # The slot, and the launcher's group, on harmless processes: a stand-in
  # compositor that starts a child in the group and one that leaves it.
  local fake=$tmp/fake
  mkdir -p "$fake"
  printf '#!/bin/sh\nshift; exec "$@"\n' > "$fake/dbus-run-session"
  # A child in the group, one that shrugs off TERM, and one that leaves.
  printf '#!/bin/sh\necho "${TZ-unset}" > %q\ncommand -v curl > %q\nsleep 300 &\nsh -c '\''trap "" TERM; exec sleep 300'\'' &\nsetsid sleep 300 & echo $! > %q\nexec sleep 300\n' \
    "$tmp/tz" "$tmp/curl" "$tmp/escapee" > "$fake/Hyprland"
  chmod +x "$fake"/*
  run=$tmp/base/fake; mkdir -p "$run/home"
  # The stand-in session runs in the zone a start names, with its slow curl.
  write_slow_curl "$run" 1 "$tmp/real-curl"
  PATH="$fake:$PATH" host_socket=$tmp/no-display zone=Asia/Kolkata slow=1 write_launcher "$run" fake
  # The holder says when it holds the slot; nothing else takes the lock to
  # find out, since a probe holding it for a moment makes the holder's
  # flock -n give up.
  ( exec 8> "$tmp/lock"; flock -n 8 && { : > "$tmp/held"; exec sleep 30; } ) & local holder=$!
  within 5 test -e "$tmp/held" || miss "the stand-in slot holder never took the lock"
  slot_free 2> /dev/null && miss "a held slot should not read free"
  setsid bash "$run/launch.sh" < /dev/null > /dev/null 2>&1 &
  within 5 test -s "$run/launch.status"
  [ "$(cat "$run/launch.status" 2> /dev/null)" = busy ] || miss "a launcher without the slot should stop at busy, got: $(cat "$run/launch.status" 2> /dev/null)"
  if [ -e "$run/leader" ]; then
    miss "a launcher without the slot should start nothing"
    echo "tophat self-check FAILED"
    return 1
  fi
  kill "$holder"; wait "$holder" 2> /dev/null
  rm -f "$run/launch.status"
  setsid bash "$run/launch.sh" < /dev/null > /dev/null 2>&1 &
  within 5 test -s "$tmp/escapee" && within 5 test -s "$run/leader" \
    || { miss "the stand-in session never started"; echo "tophat self-check FAILED"; return 1; }
  read -r LEADER LEADER_START < "$run/leader"
  RUN_ID=fake
  slot_free 2> /dev/null && miss "a running launcher should hold the slot"
  setsid sleep 300 & local bystander=$!
  local members; members=$(pgrep -g "$LEADER" | wc -l)
  (( members >= 3 )) || miss "the stand-in group should hold the launcher and its children, has $members"
  signal_group TERM "$LEADER" 1 "$(mark)" && miss "a leader whose start time differs should not be signalled"
  kill -0 "$LEADER" 2> /dev/null || miss "the group was signalled despite a changed start time"
  end_session
  pgrep -g "$LEADER" > /dev/null && miss "the run's group outlived teardown"
  kill -0 "$bystander" 2> /dev/null || miss "teardown reached a process outside the run's group"
  kill -0 "$(cat "$tmp/escapee")" 2> /dev/null || miss "teardown signalled a process that left the group"
  kill "$bystander" 2> /dev/null
  slot_free 2> /dev/null || miss "the slot should be free once the session ends"
  [ "$(cat "$tmp/tz" 2> /dev/null)" = Asia/Kolkata ] || miss "the session should run in the zone named, got: $(cat "$tmp/tz" 2> /dev/null)"
  # The stand-in compositor's detached child carries the run's mark.
  marked "$(mark)" | grep "^$(cat "$tmp/escapee") " > /dev/null || miss "a marked process outside the group should be reported"
  [ "$(cat "$tmp/curl" 2> /dev/null)" = "$run/slow/curl" ] || miss "the slow session's curl should be the slow one, got: $(cat "$tmp/curl" 2> /dev/null)"

  # A start without --zone or --slow: the session's clocks and curl are the
  # host's, though the slow curl is in its run folder.
  local plain=$tmp/plain
  mkdir -p "$plain"
  printf '#!/bin/sh\nshift; exec "$@"\n' > "$plain/dbus-run-session"
  printf '#!/bin/sh\necho "${TZ-unset} $(command -v curl)" > %q\nexec sleep 300\n' "$tmp/plain-session" > "$plain/Hyprland"
  chmod +x "$plain"/*
  rm -f "$run/launch.status" "$run/leader"
  PATH="$plain:$PATH" host_socket=$tmp/no-display zone="" slow="" write_launcher "$run" fake
  setsid bash "$run/launch.sh" < /dev/null > /dev/null 2>&1 &
  if within 5 test -s "$tmp/plain-session" && within 5 test -s "$run/leader"; then
    read -r LEADER LEADER_START < "$run/leader"
    [ "$(cat "$tmp/plain-session")" = "unset $(command -v curl)" ] \
      || miss "a plain session should keep the host's clocks and curl, got: $(cat "$tmp/plain-session")"
    end_session
    pgrep -g "$LEADER" > /dev/null && miss "the plain session's group outlived teardown"
  else
    miss "the plain stand-in session never started"
  fi

  (( failed )) && echo "tophat self-check FAILED" || echo "tophat self-check ok"
  return "$failed"
}

case ${1:-} in
  start) shift; cmd_start "$@" ;;
  stop) cmd_stop ;;
  key) shift; cmd_key "$@" ;;
  type) shift; (( $# )) || die "usage: type TEXT"; drive_prelude; nested wtype -- "$*" || die "type failed" ;;
  move) [ $# -eq 3 ] || die "usage: move X Y"; drive_prelude; pointer "$2" "$3" move "$2" "$3" ;;
  click) shift; cmd_click "$@" ;;
  drag) [ $# -eq 5 ] || die "usage: drag X1 Y1 X2 Y2"; drive_prelude; pointer "$4" "$5" drag "$2" "$3" "$4" "$5" ;;
  scroll) shift; cmd_scroll "$@" ;;
  shot) [ $# -eq 2 ] || die "usage: shot FILE"; drive_prelude; nested grim "$2" || die "grim failed" ;;
  record) shift; cmd_record "$@" ;;
  _record-watch) shift; record_watch "$@" ;;
  shell) shift; (( $# )) || die "usage: shell CMD…"; drive_prelude; nested omarchy-shell "$@" ;;
  log) load_run; cat "$run/shell.log" ;;
  sounds) load_run; cat "$run/sounds.log" 2> /dev/null ;;
  self-check) self_check ;;
  *) sed -n '2,24p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac
