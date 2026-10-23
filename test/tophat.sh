#!/usr/bin/env bash
# Tophat Stonks in a sandboxed nested Hyprland that shows nothing on the
# owner's desktop: its own output, the window it would open on the host, is
# off from the start, and the session runs on a headless output inside it,
# drawn through the host's GPU. Each checkout runs one session at a time, and
# sessions from different checkouts run side by side.
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
#   shot FILE                      screenshot the session's output (1416x850)
#   paste FILE                     the nested clipboard: its types printed,
#                                  its PNG, if it holds one, saved to FILE
#   record start FILE | record stop  wf-recorder; it writes a frame only when
#                                  the output changes, so its timing is not the screen's
#   shell CMD…                     omarchy-shell inside the session
#   log                            the nested shell's log
#   sounds                         what the stand-in pw-play was asked to play
#   folder                         the session's run folder: identity names its COMMIT,
#                                  CHECKOUT, WIDTH and HEIGHT; home/ is its home, with
#                                  Stonks' data file at .config/omarchy/grvc.stonks.json
#   self-check                     the guards, without a screen
#
# Two identities, never mixed. The nested one (socket, instance, runtime
# folder), saved at start, is the only one input, grim, wf-recorder, shell,
# and the nested shutdown use; a missing or dead session fails the command.
# The host one is used only for the launch (the nested Hyprland's GPU comes
# through the host's Wayland socket), the host values the shell reads, and
# the checks that nothing maps on the host and the owner's session is
# unchanged. Never ydotool: it writes to the kernel, which is the owner's
# seat.
set -uo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
checkout=$(cd "$here/.." && pwd)
source "$here/scratch.sh"
host_runtime=${XDG_RUNTIME_DIR:-/run/user/$UID}
base=${TOPHAT_BASE:-$HOME/Work/temporary/tophat}
# This checkout's session: its key, runtime folder, slot, and current run.
# The key is short so the nested sockets fit a Unix socket path.
key=$(printf %s "$checkout" | sha1sum | cut -c1-6)
runtime=${TOPHAT_RUNTIME:-$host_runtime/th-$key}
slot=${TOPHAT_SLOT:-$host_runtime/th-$key.lock}
current=$base/current-$key
# test/live.sh holds this alone while it restarts the shell, from the facts
# it reads before to those it reads once the services are back, and leaves a
# record of each restart in tophat.restarts beside it (its header). A
# session reads the owner's facts under a share, so never mid-restart, and
# its stop takes a change those records explain as the restart's.
lock=${TOPHAT_LOCK:-$host_runtime/tophat.lock}
restarts=${lock%.lock}.restarts
# The session's output. A fixed size, so every run's shots compare.
output=TOPHAT-1
output_size=1416x850
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

# slot_free: this checkout runs no session. Advisory: the launcher takes the
# slot, and a launcher that loses the race starts nothing.
slot_free() {
  flock -n "$slot" true 2>/dev/null || { echo "tophat: this checkout's session is running ($slot); test/tophat.sh stop ends it" >&2; return 1; }
}

# read_facts FILE: the owner-session facts into FILE, and read_at the time
# they were read (date +%s%N), under a share of the tophat lock: a restart
# that holds it is waited for, up to 5 minutes.
read_facts() {
  exec 6>> "$lock" || return 1
  if ! flock -s -n 6; then
    echo "tophat: test/live.sh is restarting the shell for a deploy; waiting for its services to come back"
    flock -s -w 300 6 || { exec 6>&-; echo "tophat: the shell's restart held the tophat lock ($lock) for 5 minutes" >&2; return 1; }
  fi
  "$here/host-facts.sh" 6>&- > "$1"
  read_at=$(date +%s%N)
  exec 6>&-
}

# facts_explained SINCE UNTIL: the owner-session facts at stop (host-after,
# read at UNTIL) are the start's (host-before, read at SINCE), or what the
# restarts test/live.sh began between the two made of them: each restart
# found them as the session last saw them and changed only its services'
# facts (shell_facts), and the session ends with them as the last one's
# services left them. Says each restart, and the first change none
# explains. A restart begins while it holds the tophat lock alone, so never
# between a read and its time.
facts_explained() {
  local since=$1 until=$2 was=$run/host-before after="the session's start" record began at
  for record in "$restarts"/*/; do
    began=$(basename "$record")
    [[ $began =~ ^[0-9]+$ ]] && (( began > since && began < until )) || continue
    at=$(date -d "@$((began / 1000000000))" +%H:%M:%S)
    if [ ! -s "$record/back" ]; then
      echo "UNEXPLAINED the shell restarted for a deploy at $at, and test/live.sh never saw its services back" >&2
      return 1
    fi
    facts_same "$was" "$record/before" "between $after and the shell's restart for a deploy at $at" || return 1
    facts_same <(grep -vE "$shell_facts" "$record/before") <(grep -vE "$shell_facts" "$record/after") \
      "beyond the shell's services, during its restart for a deploy at $at" || return 1
    echo "the shell restarted for a deploy of $(cut -c1-7 "$record/commit") at $at; its services were back at $(date -d "@$(($(cat "$record/back") / 1000000000))" +%H:%M:%S)"
    was=$record/after after="that restart"
  done
  facts_same "$was" "$run/host-after" "between $after and the stop"
}
# The facts a restart changes: its services', which the new shell's own
# processes hold (test/host-facts.sh).
shell_facts='^(clipboard watchers|notifications owner|tray owner): '
# facts_same A B WHEN: the facts in A and B are the same, or says how they
# differ.
facts_same() {
  local changed
  changed=$(diff "$1" "$2") && return 0
  echo "UNEXPLAINED owner-session facts changed $3 (the owner may have changed them):" >&2
  grep '^[<>]' <<< "$changed" >&2
  return 1
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
  trap 'rm -rf -- "$tmp"; exit 130' INT TERM
  out=$(env -i HOME="$tmp" XDG_RUNTIME_DIR="$tmp" PATH="$PATH" Hyprland --verify-config -c "$1" 2>&1)
  local code=$?
  trap - INT TERM
  rm -rf -- "$tmp"
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
# into the owner's systemd), no XWayland, the few compositor values the
# shell reads, taken from the host, and its animations, read from Omarchy's
# look'n'feel files. The Wayland backend's output, the window
# on the host, is off before its first frame, so it never takes a buffer and
# never maps (aquamarine 0.15.1, CWaylandOutput::commit); the session's
# output is a headless one at scale 1, created once Hyprland has started,
# before the shell. A fresh start opens a terminal (foot, Omarchy's default
# config, bash) in the sandbox's home.
write_nested_lua() {
  local run=$1 gaps_in gaps_out border rounding layout terminal=""
  [ "${fresh:-0}" = 1 ] && terminal="hl.exec_cmd(\"foot --working-directory=$run/home bash\")"
  gaps_in=$(css_table general:gaps_in) && gaps_out=$(css_table general:gaps_out) \
    && border=$(hyprctl -j getoption general:border_size | jq -er .int) \
    && rounding=$(hyprctl -j getoption decoration:rounding | jq -er .int) \
    && layout=$(hyprctl -j getoption general:layout | jq -er .str) \
    || { echo "tophat: cannot read the host's gaps, border, rounding, and layout" >&2; return 1; }
  cat > "$run/nested.lua" << EOF
hl.monitor({ output = "WAYLAND-1", disabled = true })
hl.monitor({ output = "$output", mode = "$output_size@60", position = "0x0", scale = 1 })
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
-- The owner's animations, from Omarchy's files (test/tophat/animations.lua).
assert(loadfile("$here/tophat/animations.lua"))("/usr/share/omarchy/default/hypr/looknfeel.lua", "$HOME/.config/hypr/looknfeel.lua")
hl.on("hyprland.start", function()
  hl.exec_cmd("hyprctl output create headless $output > $run/output.log 2>&1; quickshell -n -p /usr/share/omarchy/shell > $run/shell.log 2>&1; echo \$? > $run/shell.exit")
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

# write_launcher RUN RUN_ID: start runs it as `setsid launch.sh`, so it leads
# this run's own session and process group. It takes this checkout's slot
# and holds it until the rest of its group has gone: what the compositor
# leaves behind (the bus's services, a child that outlives it) still
# belongs to the session, and stop's TERM, which reaches the launcher too,
# ends only them. A core limit of one byte, which everything it starts
# inherits and none can raise, makes the kernel skip a crash's dump and its
# helper (fs/coredump.c), so a crash notifies no one. The compositor it
# starts gets a clean environment with the start's zone and, on a slow
# start, the slow curl ahead on its PATH; its exit, a crash's signal among
# them, goes to launch.status.
write_launcher() {
  local run=$1 id=$2 tz="" slow_path=""
  [ -n "${zone:-}" ] && tz="TZ=$(printf %q "$zone") "
  [ -n "${slow:-}" ] && slow_path='$run/slow:'
  cat > "$run/launch.sh" << EOF
#!/usr/bin/env bash
run=$(printf %q "$run")
exec 9> $(printf %q "$slot")
flock -n 9 || { echo busy > "\$run/launch.status"; exit 0; }
# A start that gave up before this ran starts nothing.
[ -e "\$run/cancel" ] && exit 0
s=\$(cat /proc/\$\$/stat); s=\${s##*) }; read -r _ _ pgid sid _ <<< "\$s"
[ "\$pgid" = \$\$ ] && [ "\$sid" = \$\$ ] || { echo "not a session leader" > "\$run/launch.status"; exit 1; }
read -r -a f <<< "\$s"
echo "\$\$ \${f[19]}" > "\$run/leader"
prlimit --pid \$\$ --core=1:1 || { echo "no core limit" > "\$run/launch.status"; exit 1; }
rm -rf $(printf %q "$runtime") && mkdir -m 700 $(printf %q "$runtime") || { echo "no runtime folder" > "\$run/launch.status"; exit 1; }
echo started > "\$run/launch.status"
# A handler, not an ignore: the children start with TERM's default.
trap : TERM
env -i HOME="\$run/home" XDG_CONFIG_HOME="\$run/home/.config" XDG_DATA_HOME="\$run/home/.local/share" \\
  XDG_STATE_HOME="\$run/home/.local/state" XDG_CACHE_HOME="\$run/home/.cache" \\
  XDG_RUNTIME_DIR=$(printf %q "$runtime") PATH="${slow_path}\$run/stubs:"$(printf %q "$PATH") \\
  OMARCHY_PATH=/usr/share/omarchy LANG=$(printf %q "${LANG:-C.UTF-8}") HYPRLAND_NO_SD_VARS=1 ${tz}\\
  TOPHAT_RUN=$(printf %q "$id") \\
  dbus-run-session -- env WAYLAND_DISPLAY=$(printf %q "$host_socket") \\
  Hyprland --config "\$run/nested.lua" > "\$run/hyprland.log" 2>&1 9>&- &
EOF
  cat >> "$run/launch.sh" << 'EOF'
hypr=$!
# A trapped TERM ends a wait early; the compositor's own exit is the one kept.
until wait "$hypr"; code=$?; ! kill -0 "$hypr" 2> /dev/null; do :; done
echo "exited $code" >> "$run/launch.status"
# others: another process is in this group. Builtins only, so the check
# itself adds no member.
others() {
  local f s
  for f in /proc/[0-9]*/stat; do
    [ "$f" = "/proc/$$/stat" ] && continue
    read -r s < "$f" 2> /dev/null || continue
    s=${s##*) }
    set -- $s
    [ "$3" = $$ ] && return 0
  done
  return 1
}
while others; do sleep 0.5; done
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

# host_windows: the host's mapped windows that a process of this run owns,
# workspace 9 left out, one per line; fails when the host can't be read.
host_windows() {
  local pids
  pids=$(pgrep -g "$LEADER" | paste -sd,)
  hyprctl -j clients | jq -r --argjson pids "[$pids]" '.[] | select(.workspace.id != 9)
    | select(.pid as $p | $pids | index($p)) | "\(.class) (\(.title)), pid \(.pid), workspace \(.workspace.id)"'
}

# no_host_window: nothing this run started maps a window on the host.
no_host_window() {
  local mine
  mine=$(host_windows) || { echo "tophat: cannot read the host's windows" >&2; return 1; }
  [ -z "$mine" ] || { echo "tophat: a window of this run mapped on the host: $mine" >&2; return 1; }
}

# outputs_hidden: inside the session, the headless output is on and every
# other output, the host window's among them, is off.
outputs_hidden() {
  nested hyprctl -j monitors all | jq -e --arg o "$output" \
    'any(.[]; .name == $o and (.disabled | not)) and all(.[]; .name == $o or .disabled)' > /dev/null
}

# ---- old runs ---------------------------------------------------------------

# A run folder is named DATE-TIME-COMMIT-KEY by start, which writes its
# RUN_ID, the same name, to the folder's identity file first of all. Nothing
# else in the base is one: the journeys' evidence and the current-* links
# aren't, and a folder that merely has such a name isn't.
run_name_re='^[0-9]{8}-[0-9]{6}-[0-9a-f]{7}-[0-9a-f]{6}$'

# run_in_use DIR: a session still runs from DIR, or a current-* link names it.
run_in_use() {
  local dir=$1 link leader start
  for link in "$base"/current-*; do
    [ "$(readlink -f "$link")" = "$dir" ] && return 0
  done
  [ -s "$dir/leader" ] && read -r leader start < "$dir/leader" \
    && group_ours "$leader" "$start" "TOPHAT_RUN=${dir##*/}"
}

# prune_runs: remove the run folders started more than a day ago, each by its
# exact path, unless a session still uses it. A day is what a pull request's
# check, or a look back at a run, can still need: a run is 28 MB, and a day
# of journeys made 116 of them.
prune_runs() {
  local cutoff dir name removed=0
  cutoff=$(date -d '1 day ago' +%Y%m%d-%H%M%S)
  for dir in "$base"/*/; do
    dir=${dir%/}
    name=${dir##*/}
    [[ $name =~ $run_name_re ]] && [ -d "$dir" ] && [ ! -L "$dir" ] && grep -qx "RUN_ID=$name" "$dir/identity" 2> /dev/null || continue
    [[ ${name:0:15} < $cutoff ]] || continue
    run_in_use "$dir" && continue
    rm -rf -- "$dir" && removed=$((removed + 1))
  done
  if (( removed )); then echo "removed $removed run folders from before $cutoff"; fi
}

# ---- the run ----------------------------------------------------------------

# load_run: this checkout's current run's saved identity, or fail.
load_run() {
  [ -f "$current/identity" ] || die "no nested session: none was started from this checkout, or it has stopped"
  run=$(readlink -f "$current")
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
  note_pids
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
# must be where this tool left it; only something else driving the session
# moves it.
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
  local ref=${1:?usage: start [--fresh] [--zone ZONE] [--slow SECONDS] REF} commit id tool curl=""
  commit=$(git -C "$checkout" rev-parse --verify --quiet "$ref^{commit}") || die "no such commit: $ref"
  for tool in Hyprland quickshell dbus-run-session python3 wtype grim wf-recorder setsid flock prlimit journalctl jq foot; do
    command -v "$tool" > /dev/null || die "$tool is not installed"
  done
  if [ -n "$slow" ]; then curl=$(command -v curl) || die "curl is not installed"; fi
  # The nested Hyprland draws through the host's GPU, over its Wayland socket.
  case ${WAYLAND_DISPLAY:-} in
    "") die "no host display: start runs from the owner's session" ;;
    /*) host_socket=$WAYLAND_DISPLAY ;;
    *) host_socket=$host_runtime/$WAYLAND_DISPLAY ;;
  esac
  slot_free && socket_paths_fit "$runtime" && bus_ok || exit 1
  # The slot is free, so whatever current names has ended.
  rm -f "$current"
  prune_runs

  # The key too: two checkouts may start the same commit in the same second.
  id=$(date +%Y%m%d-%H%M%S)-${commit:0:7}-$key
  run=$base/$id
  [[ $run =~ ^[A-Za-z0-9/._-]+$ ]] || die "the run folder $run needs a plain path"
  mkdir -p "$run" && printf 'RUN_ID=%q\n' "$id" > "$run/identity" || die "cannot make $run"
  echo "run folder: $run"
  build_sandbox "$run" "$commit" && { [ -z "$slow" ] || write_slow_curl "$run" "$slow" "$curl"; } \
    && write_nested_lua "$run" && nested_lua_ok "$run/nested.lua" \
    && write_launcher "$run" "$id" || die "the sandbox is not ready; nothing was launched"
  read_facts "$run/host-before" || die "the owner's facts could not be read; nothing was launched"
  { printf 'RUN_ID=%q\nCHECKOUT=%q\nCOMMIT=%q\nSTART_EPOCH=%q\nFACTS_AT=%q\nRUNTIME=%q\nZONE=%q\nSLOW=%q\n' "$id" "$checkout" "$commit" "$((read_at / 1000000000))" "$read_at" "$runtime" "$zone" "$slow"; } > "$run/identity"
  trap 'start_failed "interrupted"' INT TERM

  setsid "$run/launch.sh" < /dev/null > /dev/null 2>&1 &
  within 15 test -s "$run/launch.status" || start_failed "the launcher never reported"
  [ "$(head -n 1 "$run/launch.status")" = started ] || start_failed "the launcher: $(head -n 1 "$run/launch.status")"
  # This run holds the slot: only now does it become the current one.
  ln -sfn "$run" "$current"
  read -r LEADER LEADER_START < "$run/leader"
  printf 'LEADER=%q\nLEADER_START=%q\n' "$LEADER" "$LEADER_START" >> "$run/identity"
  within 30 find_instance || start_failed "the nested Hyprland never came up"
  socket_paths_fit "$runtime" "$SIG" || start_failed "the nested sockets do not fit"
  printf 'HYPR_PID=%q\nSIG=%q\nWAYLAND=%q\n' "$HYPR_PID" "$SIG" "$WAYLAND" >> "$run/identity"
  source "$run/identity"
  within 15 outputs_hidden || start_failed "the session's output $output is not the only one on: $(nested hyprctl -j monitors all | jq -c 'map({name, disabled})')"
  within 60 shell_up || start_failed "the nested shell never answered"
  services_off || start_failed "a service that must be off is running"
  if (( fresh )); then
    within 30 terminal_up || start_failed "the terminal never opened"
  else
    within 30 nested omarchy-shell grvc.stonks close > /dev/null 2>&1 || start_failed "the Stonks pill never loaded"
  fi
  read -r WIDTH HEIGHT < <(nested hyprctl -j monitors | jq -r --arg o "$output" '.[] | select(.name == $o) | "\(.width) \(.height)"')
  printf 'WIDTH=%q\nHEIGHT=%q\n' "$WIDTH" "$HEIGHT" >> "$run/identity"
  note_pids
  # By now the shell has drawn its bar: had the host window taken a frame,
  # it would show on the host.
  no_host_window || start_failed "nothing may show on the owner's desktop"
  trap - INT TERM
  echo "commit: $commit"
  echo "nested output: ${WIDTH}x$HEIGHT, headless; nothing on the host"
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
  flock -n "$slot" true 2> /dev/null || within 15 test -s "$run/launch.status"
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
    # Hyprland 0.56.2 crashes on exit within half a second of wf-recorder
    # leaving (4 of 4 runs stopped at once; none of 7 stopped 0.5 s later):
    # a second passes after the last recording first.
    if [ -s "$run/record.ended" ]; then
      local wait_ms=$(( $(cat "$run/record.ended") + 1000 - $(date +%s%3N) ))
      (( wait_ms > 0 )) && sleep "$(awk -v ms="$wait_ms" 'BEGIN { printf "%.3f", ms / 1000 }')"
    fi
    nested hyprctl eval 'hl.dispatch(hl.dsp.exit())' > /dev/null 2>&1
    within 10 bash -c "! kill -0 $HYPR_PID 2>/dev/null"
    within 2 group_gone && return 0
  fi
  signal_group TERM "$LEADER" "${LEADER_START:-}" "$(mark)"
  within 5 group_gone && return 0
  signal_group KILL "$LEADER" "${LEADER_START:-}" "$(mark)"
  within 5 group_gone
}

# dumps_core STATUS: STATUS is a shell's exit for a death by a signal that
# dumps core (QUIT ILL TRAP ABRT BUS FPE SEGV XCPU XFSZ SYS).
dumps_core() { case $1 in 131|132|133|134|135|136|139|152|153|159) return 0 ;; esac; return 1; }

# crashes: each process of this run that crashed, one per line; fails when
# the kernel log can't be read. The compositor's and the shell's exits say
# so for them, whenever they die. For the rest, the kernel's log: under the
# launcher's one-byte core limit it writes no dump and logs "coredump:
# PID(COMM): RLIMIT_CORE is set to 1, aborting core" instead, for the
# processes note_pids saw. That message is rate-limited across the machine
# (ten in five seconds) and a process too short-lived to be seen goes
# unnamed, which is why the two that matter are read from their exits.
crashes() {
  local log pids pid rest code
  code=$(sed -n 's/^exited //p' "$run/launch.status" 2> /dev/null)
  dumps_core "$code" && echo "Hyprland (exit $code)"
  code=$(cat "$run/shell.exit" 2> /dev/null)
  dumps_core "$code" && echo "Quickshell (exit $code)"
  [ -n "$(journalctl -k -q -n 1 --no-pager -o cat 2> /dev/null)" ] || return 1
  log=$(journalctl -k -q --no-pager -o cat --since="@${START_EPOCH:-0}") || return 1
  pids=" $(sort -un "$run/pids" 2> /dev/null | tr '\n' ' ')"
  grep -oE '[0-9]+\([^)]*\): RLIMIT_CORE' <<< "$log" | while IFS='(' read -r pid rest; do
    [[ $pids == *" $pid "* ]] && echo "$pid (${rest%%)*})"
  done
  return 0
}

# stop_run: end everything this run started and report what it saw.
# Returns non-zero on anything the run may have caused.
stop_run() {
  local status=0 line blocked errors
  # A start that failed early recorded its group only in the leader file.
  if [ -z "${LEADER:-}" ] && [ -s "$run/leader" ]; then read -r LEADER LEADER_START < "$run/leader"; fi
  [ -f "$run/recorder" ] && { record_stop || status=1; }
  if ours; then
    if ! line=$(host_windows); then echo "FAILED the host's windows could not be read" >&2; status=1
    elif [ -n "$line" ]; then echo "FAILED a window of this run mapped on the host: $line" >&2; status=1; fi
  fi
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
  line=$(crashes) || { echo "FAILED the kernel log could not be read (journalctl -k), so a crash would go unseen" >&2; status=1; }
  [ -n "$line" ] && { echo "FAILED a process crashed: $(paste -sd, <<< "$line" | sed 's/,/, /g'). No core was written (the run's core limit is one byte). Find the cause before relaunching (the diagnose-crash skill)." >&2; status=1; }
  if [ -f "$run/host-before" ]; then
    if ! read_facts "$run/host-after"; then
      echo "FAILED the owner's facts could not be read at stop" >&2; status=1
    elif ! facts_explained "${FACTS_AT:-$((START_EPOCH * 1000000000))}" "$read_at"; then
      status=1
    fi
  fi
  [ "$(readlink -f "$current")" = "$run" ] && rm -f "$current"
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
  local file
  drive_prelude
  [ -f "$run/recorder" ] && die "already recording"
  file=$(realpath -m "$1")
  rm -f "$run/record.status"
  echo "$file" > "$run/record.file"
  setsid "$here/tophat.sh" _record "$file" > "$run/record.log" 2>&1 < /dev/null &
  within 10 test -s "$run/record.status" || die "the recorder did not start: $(cat "$run/record.log")"
  echo "recording $output to $file"
}

# _record FILE: leads its own group with wf-recorder, which captures the
# session's output through the nested screencopy, until record stop.
record_watch() {
  local file=$1 rec stopping=0
  load_run
  echo "$$ $(start_of $$)" > "$run/recorder"
  nested wf-recorder -y -o "$output" -f "$file" &
  rec=$!
  # TERM, not INT: a background job starts with INT ignored, and an ignored
  # signal cannot be trapped.
  trap 'stopping=1' TERM
  echo recording > "$run/record.status"
  while kill -0 "$rec" 2> /dev/null && (( ! stopping )); do sleep 0.5; done
  (( stopping )) || lost "wf-recorder exited"
  # nested is a function, so the job is a subshell with wf-recorder its
  # child; INT is what makes wf-recorder finish its file.
  kill -INT $(pgrep -P "$rec" -x wf-recorder) 2> /dev/null
  wait "$rec"
  # When wf-recorder left the session, for end_session.
  date +%s%3N > "$run/record.ended"
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
  check_tmp=$(mktemp -d "$TMPDIR/tophat-check.XXXXXX") || exit 1
  local tmp=$check_tmp
  # Whatever a failed step left: the stand-in session's group and its escapee.
  trap '[ -f "$check_tmp/base/fake/leader" ] && kill -KILL -- "-$(cut -d" " -f1 "$check_tmp/base/fake/leader")" 2>/dev/null
    [ -f "$check_tmp/escapee" ] && kill "$(cat "$check_tmp/escapee")" 2>/dev/null
    [ -f "$check_tmp/standins" ] && kill -KILL $(cat "$check_tmp/standins") 2>/dev/null; rm -rf "$check_tmp"' EXIT
  miss() { echo "FAILED $*"; failed=1; }
  export TOPHAT_BASE=$tmp/base TOPHAT_RUNTIME=$tmp/rt TOPHAT_SLOT=$tmp/slot TOPHAT_LOCK=$tmp/lock TOPHAT_PYTHON=$tmp/tools/python3
  base=$TOPHAT_BASE runtime=$TOPHAT_RUNTIME slot=$TOPHAT_SLOT lock=$TOPHAT_LOCK restarts=${TOPHAT_LOCK%.lock}.restarts current=$TOPHAT_BASE/current-$key
  # The guards run on these; a missing one is named, not buried in a miss.
  for t in Hyprland dbus-run-session flock setsid pgrep prlimit journalctl jq; do
    command -v "$t" > /dev/null || { echo "FAILED $t is not installed: the guards cannot run"; return 1; }
  done
  mkdir -p "$tmp/base" "$tmp/tools"
  # Every tool a drive command could reach, logged: a guard that lets one
  # through shows here.
  for t in python3 wtype grim omarchy-shell hyprctl ydotool wf-recorder; do
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
  ln -sfn "$dead" "$current"
  expect_refused "dead session"
  rm -f "$current"

  # Socket paths.
  socket_paths_fit "/run/user/1000/th-$key" 2> /dev/null || miss "the default runtime folder's sockets should fit"
  socket_paths_fit "/tmp/$(printf 'r%.0s' {1..40})" 2> /dev/null && miss "a 45-byte runtime folder's Hyprland sockets should not fit"
  socket_paths_fit "/run/user/1000/th-$key" "$(printf 's%.0s' {1..90})" 2> /dev/null && miss "a long real signature should not fit"

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

  # The session's animations: only Omarchy's curves, animations, and
  # `animations` settings reach the compositor, its defaults first and then
  # the owner's file. Each case runs in Hyprland's own Lua with a recording
  # `hl` in its place.
  local anim=$tmp/anim loader=$here/tophat/animations.lua
  mkdir -p "$anim"
  cat > "$anim/defaults.lua" << 'EOF'
hl.config({ general = { gaps_in = 1 }, animations = { enabled = true } })
hl.curve("c1", { type = "bezier", points = { { 0, 0 }, { 1, 1 } } })
hl.animation({ leaf = "a1", enabled = true, speed = 4, bezier = "c1" })
hl.bind("x")
EOF
  cat > "$anim/owner.lua" << 'EOF'
hl.animation({ leaf = "a1", enabled = false })
hl.config({ decoration = { rounding = 3 } })
EOF
  # Settings it cannot filter, because they run elsewhere.
  printf 'dofile("/dev/null")\nhl.animation({ leaf = "a2" })\n' > "$anim/owner-includes.lua"
  anim_loaded() {  # WANT DEFAULTS OWNER: what the loader hands over, in order and in full, is WANT
    cat > "$anim/harness.lua" << EOF
local real, seen = hl, {}
local function show(value)
  if type(value) ~= "table" then return tostring(value) end
  local parts = {}
  for key, inner in pairs(value) do parts[#parts + 1] = tostring(key) .. "=" .. show(inner) end
  table.sort(parts)
  return "{" .. table.concat(parts, ",") .. "}"
end
local function note(...) seen[#seen + 1] = table.concat({ ... }, " ") end
_G.hl = {
  curve = function(name, options) note("curve", name, show(options)) end,
  animation = function(options) note("animation", show(options)) end,
  config = function(options) note("config", show(options)) end,
}
local ok = pcall(assert(loadfile("$loader")), "$2", "$3")
_G.hl = real
if not ok then seen[#seen + 1] = "ERROR" end
local got = table.concat(seen, ";")
if got ~= "$1" then error("got: " .. got) end
EOF
    nested_lua_ok "$anim/harness.lua"
  }
  local animations='config {animations={enabled=true}};curve c1 {points={1={1=0,2=0},2={1=1,2=1}},type=bezier};animation {bezier=c1,enabled=true,leaf=a1,speed=4}'
  anim_loaded "$animations;animation {enabled=false,leaf=a1}" "$anim/defaults.lua" "$anim/owner.lua" 2> /dev/null \
    || miss "the loader should hand over the defaults' animations, then the owner's, in full and nothing else"
  anim_loaded "$animations" "$anim/defaults.lua" "$anim/none.lua" 2> /dev/null \
    || miss "an owner without a look'n'feel file should leave the defaults' animations"
  anim_loaded "$animations;ERROR" "$anim/defaults.lua" "$anim/owner-includes.lua" 2> /dev/null \
    || miss "a file that includes another should be an error, since its settings would bypass the filter"
  anim_loaded ERROR "$anim/none.lua" "$anim/owner.lua" 2> /dev/null \
    || miss "missing defaults should be an error, not the wrong motion"
  anim_loaded "${animations/speed=4/speed=5};animation {enabled=false,leaf=a1}" "$anim/defaults.lua" "$anim/owner.lua" 2> /dev/null \
    && miss "the loader's check should fail on a wrong speed"
  # The installed Omarchy's own file loads, and gives animations and nothing else.
  cat > "$anim/real.lua" << EOF
local real, kinds = hl, {}
_G.hl = {
  curve = function() kinds.curve = true end,
  animation = function() kinds.animation = true end,
  config = function(t) for key in pairs(t) do kinds["config " .. key] = true end end,
}
local ok, err = pcall(assert(loadfile("$loader")), "/usr/share/omarchy/default/hypr/looknfeel.lua", "$anim/none.lua")
_G.hl = real
if not ok then error(err) end
if not (kinds.curve and kinds.animation) then error("Omarchy's look'n'feel gave no animations") end
for kind in pairs(kinds) do
  if kind ~= "curve" and kind ~= "animation" and kind ~= "config animations" then error("let through: " .. kind) end
end
EOF
  nested_lua_ok "$anim/real.lua" || miss "the installed Omarchy's look'n'feel should give animations and nothing else"
  # And the generated nested.lua runs the loader.
  mkdir -p "$tmp/hc"
  printf '#!/bin/sh\necho "{\\"css\\":\\"5 5 5 5\\",\\"int\\":2,\\"str\\":\\"dwindle\\"}"\n' > "$tmp/hc/hyprctl"; chmod +x "$tmp/hc/hyprctl"
  PATH="$tmp/hc:$PATH" fresh=0 write_nested_lua "$anim"
  cat > "$anim/wired.lua" << EOF
local real, seen = hl, {}
_G.hl = setmetatable({}, { __index = function(_, name) return function() seen[name] = true end end })
local ok, err = pcall(dofile, "$anim/nested.lua")
_G.hl = real
if not ok then error(err) end
if not (seen.curve and seen.animation) then error("nested.lua set no animations") end
EOF
  nested_lua_ok "$anim/wired.lua" || miss "the generated nested.lua should set the owner's animations"

  # Old runs: a run folder from before the last day goes, unless a session
  # still uses it; nothing else in the base is touched, by name, by mark, or
  # by link.
  local base_was=$base old=20200101-000000 fresh_name n
  base=$tmp/prune
  fresh_name=$(date +%Y%m%d-%H%M%S)
  # made NAME: a folder as start makes it.
  made() { mkdir -p "$base/$1" && echo "RUN_ID=$1" > "$base/$1/identity"; }
  for n in 111111 222222 333333 444444 555555; do made "$old-abcdef0-$n"; done
  made "$fresh_name-abcdef0-111111"
  mkdir -p "$base/journeys/$old" "$base/$old-notarun" "$base/$old-abcdef0-666666" "$base/$old-abcdef0-888888" "$tmp/prune-victim"
  echo "RUN_ID=another" > "$base/$old-abcdef0-888888/identity"
  : > "$tmp/prune-victim/file"
  ln -s "$tmp/prune-victim" "$base/$old-abcdef0-777777"
  ln -sfn "$base/$old-abcdef0-222222" "$base/current-aaaaaa"
  setsid sleep 60 & local alive=$!
  echo "$alive $(start_of "$alive")" > "$base/$old-abcdef0-333333/leader"
  echo "$gone $gone_start" > "$base/$old-abcdef0-444444/leader"
  echo "$alive 1" > "$base/$old-abcdef0-555555/leader"
  prune_runs > /dev/null
  kill "$alive" 2> /dev/null
  [ -e "$base/$old-abcdef0-111111" ] && miss "an old run folder nothing uses should be removed"
  [ -e "$base/$old-abcdef0-444444" ] && miss "an old run whose session has gone should be removed"
  [ -e "$base/$old-abcdef0-555555" ] && miss "an old run whose recorded leader's process number was reused should be removed"
  [ -d "$base/$old-abcdef0-222222" ] || miss "the run a current-* link names was removed"
  [ -d "$base/$old-abcdef0-333333" ] || miss "an old run whose session still runs was removed"
  [ -d "$base/$fresh_name-abcdef0-111111" ] || miss "a run from the last day was removed"
  [ -d "$base/journeys/$old" ] || miss "the journeys' evidence was removed"
  [ -d "$base/$old-notarun" ] || miss "a folder whose name is not a run's was removed"
  [ -d "$base/$old-abcdef0-666666" ] || miss "a folder with a run's name that start never marked was removed"
  [ -d "$base/$old-abcdef0-888888" ] || miss "a folder marked with another run's name was removed"
  [ -L "$base/$old-abcdef0-777777" ] && [ -e "$tmp/prune-victim/file" ] || miss "pruning touched a link in the base, or what it names"
  base=$base_was

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

  # The session's outputs, from stand-in answers: the host window's output
  # on fails, as does no session output.
  mkdir -p "$tmp/host"
  printf '#!/bin/sh\ncat %q\n' "$tmp/host.json" > "$tmp/host/hyprctl"; chmod +x "$tmp/host/hyprctl"
  answer() { jq -n "$@" > "$tmp/host.json"; }
  local RUNTIME=$tmp/rt WAYLAND=wayland-1 SIG=x
  run=$tmp/base/outputs
  answer --arg o "$output" '[{name: "WAYLAND-1", disabled: true}, {name: $o, disabled: false}]'
  PATH="$tmp/host:$PATH" outputs_hidden || miss "the session's output alone on should pass"
  answer --arg o "$output" '[{name: "WAYLAND-1", disabled: false}, {name: $o, disabled: false}]'
  PATH="$tmp/host:$PATH" outputs_hidden && miss "the host window's output on should fail"
  answer '[{name: "WAYLAND-1", disabled: true}]'
  PATH="$tmp/host:$PATH" outputs_hidden && miss "no session output should fail"

  # The owner's facts at stop: the start's, or what the restarts test/live.sh
  # recorded within the session made of them. The session's facts are read
  # at 1000 and 9000.
  run=$tmp/base/explain; mkdir -p "$run"
  restarted() {  # BEGAN BEFORE [AFTER]: a restart's record; without AFTER, its services never came back
    mkdir -p "$restarts/$1" && echo 0123456789abcdef > "$restarts/$1/commit" && echo "$2" > "$restarts/$1/before"
    [ -z "${3:-}" ] || { echo "$3" > "$restarts/$1/after"; echo $(($1 + 500)) > "$restarts/$1/back"; }
  }
  explained() {  # START STOP: the session's facts, explained
    echo "$1" > "$run/host-before"; echo "$2" > "$run/host-after"
    facts_explained 1000 9000 > "$run/explained" 2>&1
  }
  local t1="tray owner: PID=1" t2="tray owner: PID=2" t3="tray owner: PID=3"
  explained "$t1" "$t1" || miss "unchanged facts should pass: $(cat "$run/explained")"
  explained "$t1" "$t2" && miss "changed facts with no restart should fail"
  restarted 2000 "$t1" "$t2"
  explained "$t1" "$t2" || miss "facts as a restart within the session left them should pass: $(cat "$run/explained")"
  grep -q '^the shell restarted for a deploy of 0123456 at ' "$run/explained" || miss "an explained stop should say the shell restarted for a deploy: $(cat "$run/explained")"
  explained "$t1" "$t3" && miss "facts changed after a restart's services were back should fail"
  explained "$t3" "$t2" && miss "facts changed between the start and a restart should fail"
  restarted 3000 "$t2" "$t3"
  explained "$t1" "$t3" || miss "two restarts in turn should explain their changes: $(cat "$run/explained")"
  rm -rf "$restarts"; restarted 2000 "$t1"
  explained "$t1" "$t2" && miss "a restart whose services never came back should fail"
  rm -rf "$restarts"; restarted 2000 "$t1"$'\npower profile: performance' "$t2"$'\npower profile: power-saver'
  explained "$t1"$'\npower profile: performance' "$t2"$'\npower profile: power-saver' \
    && miss "a fact beyond the shell's services changed during a restart should fail"
  for began in 500 9500; do
    rm -rf "$restarts"; restarted "$began" "$t1" "$t2"
    explained "$t1" "$t2" && miss "a restart at $began, outside the session (1000 to 9000), should explain nothing"
  done
  rm -rf "$restarts"

  # Clipboard watchers, on stand-ins: bash under the name wl-paste, with
  # --watch on its command line, as the real ones have, started by a parent
  # bash under another name. The owner's watchers have the owner's Quickshell
  # as their parent (a stand-in named quickshell, with the shell's folder on
  # its command line and no TOPHAT_RUN); another program's, Herdr's, have any
  # other parent, and a tophat run's own Quickshell has TOPHAT_RUN. Each
  # clipboard change forks a child from a real watcher that keeps its name
  # and command line until it runs the capture script: a stand-in forks a
  # subshell on USR1, which stays in the fork's state. That child, coming
  # and going, is not the owner changing their watchers; an owner's watcher
  # gone, added or replaced is, and another program's is not. The owner's
  # real watchers are left out of the comparison: only the stand-ins' lines
  # are read.
  mkdir -p "$tmp/watch"; mkfifo "$tmp/watch/fifo"
  local name; for name in wl-paste quickshell herdr; do ln -s "$(command -v bash)" "$tmp/watch/$name"; done
  : > "$tmp/standins"
  watcher() {  # KIND: owner, run or other; sets WATCHER and PARENT to the pids of a new stand-in and its parent
    local parent=quickshell shell_args=(-n -p /usr/share/omarchy/shell) in_run=() pidfile; pidfile=$(mktemp -p "$tmp/watch")
    [ "$1" != other ] || { parent=herdr; shell_args=(); }
    [ "$1" != run ] || in_run=(TOPHAT_RUN=check)
    env -u TOPHAT_RUN "${in_run[@]}" FIFO="$tmp/watch/fifo" PIDFILE="$pidfile" WPASTE="$tmp/watch/wl-paste" \
      WSCRIPT='trap "( read -t 120 x <> \"\$FIFO\" ) &" USR1; while :; do read -t 120 x <> "$FIFO"; done' \
      "$tmp/watch/$parent" -c '"$WPASTE" -c "$WSCRIPT" --watch & echo $! > "$PIDFILE"; wait' "${shell_args[@]}" &
    PARENT=$!; echo "$PARENT" >> "$tmp/standins"
    within 5 test -s "$pidfile" || miss "the stand-in parent never started its watcher"
    WATCHER=$(< "$pidfile"); echo "$WATCHER" >> "$tmp/standins"
    # Counted only once both have taken their names: ps would show bash before.
    within 5 eval '[ "$(ps -o comm= -p '"$WATCHER"')" = wl-paste ] && [ "$(ps -o comm= -p '"$PARENT"')" = '"$parent"' ]' \
      || miss "the stand-ins never took their names"
  }
  unwatch() { kill -KILL "$@"; wait "$@" 2> /dev/null; }
  standins_seen() {  # the stand-ins among the clipboard watchers' pids, as the facts name them
    "$here/host-facts.sh" 6>&- | grep '^clipboard watchers:' | tr ' ' '\n' | grep -xFf "$tmp/standins" | paste -sd' '
  }
  seen_is() { [ "$(standins_seen)" = "$1" ]; }
  unchanged() {  # WAS: the clipboard watchers fact now is as WAS, which standins_seen gave
    facts_same <(echo "clipboard watchers: $1") <(echo "clipboard watchers: $(standins_seen)") "in the self-check" 2> /dev/null
  }
  watcher owner; local first=$WATCHER first_parent=$PARENT
  within 5 seen_is "$first" || miss "an owner's clipboard watcher should be named by its pid in the facts, got '$(standins_seen)'"
  local before; before=$(standins_seen)
  # ps cuts its arguments at an exported COLUMNS unless told not to (-ww), and
  # a watcher without its --watch is no watcher.
  [ "$(COLUMNS=30 standins_seen)" = "$before" ] || miss "a narrow COLUMNS should not hide a watcher's --watch, got '$(COLUMNS=30 standins_seen)'"
  has_child() { ps -o stat= --ppid "$1" | grep -qv Z; }  # a zombie is gone, but for its parent's wait
  kill -USR1 "$first"
  within 5 has_child "$first" || miss "the stand-in watcher never forked its child"
  local child; child=$(pgrep -P "$first" | head -n 1); echo "$child" >> "$tmp/standins"
  seen_is "$before" || miss "a watcher's forked child should not count as a watcher, got '$(standins_seen)' for $first and its child $child"
  kill -KILL "$child"; within 5 eval '! has_child '"$first" || miss "the stand-in's child never ended"
  seen_is "$before" || miss "a watcher's forked child ending should change no fact, got '$(standins_seen)'"
  watcher owner; local second=$WATCHER second_parent=$PARENT
  seen_is "$first $second" || miss "a second owner's watcher should be named as well, got '$(standins_seen)'"
  unchanged "$before" && miss "an owner's clipboard watcher started during a session should fail its stop"
  unwatch "$first" "$first_parent"
  unchanged "$before" && miss "an owner's clipboard watcher replaced during a session should fail its stop"

  # Another program's watcher, and a tophat run's own shell's, come and go
  # with no fact changed.
  local mid; mid=$(standins_seen)
  [ "$mid" = "$second" ] || miss "the owner's watchers should be the second alone, got '$mid'"
  watcher other; local other=$WATCHER other_parent=$PARENT
  watcher run; local run_watcher=$WATCHER run_parent=$PARENT
  seen_is "$mid" || miss "another program's, and a tophat run's own, clipboard watchers should not be named, got '$(standins_seen)' for $other and $run_watcher"
  unchanged "$mid" || miss "another program's clipboard watcher started during a session should change no fact"
  unwatch "$other" "$other_parent" "$run_watcher" "$run_parent"
  unchanged "$mid" || miss "another program's clipboard watcher ended during a session should change no fact"

  # The owner's shell restarted for a deploy: its new watchers have the new
  # shell as their parent, and count; the restart's record explains the change.
  unwatch "$second" "$second_parent"; watcher owner; local third=$WATCHER
  seen_is "$third" || miss "the owner's watchers after a shell restart should be named, got '$(standins_seen)'"
  unchanged "$mid" && miss "an owner's clipboard watcher replaced by a shell restart should fail with no record of it"
  restarted 2000 "clipboard watchers: $mid" "clipboard watchers: $third"
  explained "clipboard watchers: $mid" "clipboard watchers: $third" \
    || miss "an owner's watchers replaced by a recorded shell restart should pass: $(cat "$run/explained")"
  rm -rf "$restarts"
  unwatch "$third" "$PARENT"
  [ -z "$(standins_seen)" ] || miss "watchers that ended should leave the facts, got '$(standins_seen)'"
  unchanged "$third" && miss "an owner's clipboard watcher ended during a session should fail its stop"

  # The slot, and the launcher's group, on harmless processes: a stand-in
  # compositor that starts a child in the group, one that shrugs off TERM,
  # one that leaves the group, and one that crashes, only once its core dump
  # is off.
  local fake=$tmp/fake
  mkdir -p "$fake"
  printf '#!/bin/sh\nshift; exec "$@"\n' > "$fake/dbus-run-session"
  cat > "$fake/Hyprland" << EOF
#!/bin/sh
echo "\${TZ-unset}" > $(printf %q "$tmp/tz")
command -v curl > $(printf %q "$tmp/curl")
prlimit --pid \$\$ --core --raw --noheadings -o SOFT,HARD > $(printf %q "$tmp/core-limit")
sh -c 'echo \$\$ > "\$1"; [ "\$(prlimit --pid \$\$ --core --raw --noheadings -o SOFT,HARD)" = "1 1" ] && kill -SEGV \$\$' crash $(printf %q "$tmp/crashed") &
sleep 300 &
sh -c 'trap "" TERM; exec sleep 300' &
setsid sleep 300 & echo \$! > $(printf %q "$tmp/escapee")
exec sleep 300
EOF
  chmod +x "$fake"/*
  run=$tmp/base/fake; mkdir -p "$run/home"
  # The stand-in session runs in the zone a start names, with its slow curl.
  write_slow_curl "$run" 1 "$tmp/real-curl"
  PATH="$fake:$PATH" host_socket=$tmp/no-display zone=Asia/Kolkata slow=1 write_launcher "$run" fake
  # held FILE MODE STATUS WHAT: with FILE's lock held (-x or -s), the slot
  # reads taken and the launcher stops at STATUS, starting nothing. The
  # holder says when it holds the lock; nothing else takes it to find out,
  # since a probe holding it for a moment makes the holder's flock -n give up.
  held() {
    local holder
    rm -f "$tmp/held" "$run/launch.status"
    ( exec 7>> "$1"; flock "$2" -n 7 && { : > "$tmp/held"; exec sleep 30; } ) & holder=$!
    within 5 test -e "$tmp/held" || miss "$4: the stand-in holder never took the lock"
    slot_free 2> /dev/null && miss "$4: the slot should not read free"
    setsid bash "$run/launch.sh" < /dev/null > /dev/null 2>&1 &
    within 5 test -s "$run/launch.status"
    [ "$(cat "$run/launch.status" 2> /dev/null)" = "$3" ] || miss "$4: the launcher should stop at $3, got: $(cat "$run/launch.status" 2> /dev/null)"
    kill "$holder"; wait "$holder" 2> /dev/null
    [ ! -e "$run/leader" ]
  }
  if ! held "$slot" -x busy "this checkout's session running"; then
    miss "a launcher without the slot should start nothing"
    echo "tophat self-check FAILED"
    return 1
  fi
  rm -f "$run/launch.status"
  local START_EPOCH; START_EPOCH=$(date +%s)
  # Not a job of this shell: teardown ends this launcher with KILL, which
  # the shell would report.
  ( setsid bash "$run/launch.sh" < /dev/null > /dev/null 2>&1 & )
  within 5 test -s "$tmp/escapee" && within 5 test -s "$run/leader" \
    || { miss "the stand-in session never started"; echo "tophat self-check FAILED"; return 1; }
  read -r LEADER LEADER_START < "$run/leader"
  RUN_ID=fake
  slot_free 2> /dev/null && miss "a running session should hold this checkout's slot"
  flock -n "$lock" true 2> /dev/null || miss "a running session should leave the tophat lock free: test/live.sh restarts the shell under it"
  slot=$tmp/slot-other slot_free 2> /dev/null || miss "another checkout's session should start beside a running one"
  setsid sleep 300 & local bystander=$!

  # Another checkout's stop finds no session of its own, and ends nothing.
  printf 'RUN_ID=fake\nCHECKOUT=%q\nRUNTIME=%q\nSTART_EPOCH=%s\nLEADER=%s\nLEADER_START=%s\n' \
    "$checkout" "$tmp/rt" "$START_EPOCH" "$LEADER" "$LEADER_START" > "$run/identity"
  ln -sfn "$run" "$current"
  mkdir -p "$tmp/other/test" && cp -r "$here/tophat.sh" "$here/procs.sh" "$here/tophat" "$tmp/other/test/"
  bash "$tmp/other/test/tophat.sh" stop > /dev/null 2>&1 && miss "a stop from another checkout should find no session"
  kill -0 "$LEADER" 2> /dev/null || miss "a stop from another checkout ended this checkout's session"
  rm -f "$current"

  # A window of a process in the run's group fails; another's doesn't.
  answer --argjson pid "$LEADER" '[{pid: $pid, class: "aquamarine", title: "WAYLAND-1", workspace: {id: 1}}]'
  PATH="$tmp/host:$PATH" no_host_window 2> /dev/null && miss "a window of the run's on the host should fail"
  answer --argjson pid "$bystander" '[{pid: $pid, class: "foot", title: "x", workspace: {id: 1}}]'
  PATH="$tmp/host:$PATH" no_host_window 2> /dev/null || miss "another process's window on the host should not fail the run"
  echo 'not json' > "$tmp/host.json"
  PATH="$tmp/host:$PATH" no_host_window 2> /dev/null && miss "a host whose windows can't be read should fail"

  # The crash: no core, and the kernel's word for it names the process.
  [ "$(cat "$tmp/core-limit" 2> /dev/null)" = "1 1" ] \
    || miss "the session should run with a one-byte core limit, got: $(cat "$tmp/core-limit" 2> /dev/null)"
  crash_seen() { crashes | grep -q "^$(cat "$tmp/crashed") "; }
  if [ -s "$tmp/crashed" ] && [ "$(cat "$tmp/core-limit" 2> /dev/null)" = "1 1" ]; then
    cat "$tmp/crashed" > "$run/pids"
    within 5 crash_seen || miss "a crash in the run should be named, got: $(crashes)"
    : > "$run/pids"
    [ -z "$(crashes)" ] || miss "a crash outside the run should not be named, got: $(crashes)"
  fi

  local members; members=$(pgrep -g "$LEADER" | wc -l)
  (( members >= 3 )) || miss "the stand-in group should hold the launcher and its children, has $members"
  signal_group TERM "$LEADER" 1 "$(mark)" && miss "a leader whose start time differs should not be signalled"
  kill -0 "$LEADER" 2> /dev/null || miss "the group was signalled despite a changed start time"
  # TERM leaves the member that shrugs it off: the slot stays taken.
  signal_group TERM "$LEADER" "$LEADER_START" "$(mark)"
  sleep 0.5
  slot_free 2> /dev/null && miss "the slot should stay taken while teardown's TERM leaves a member"
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

  # A compositor that crashes and leaves a child in the group: its crash is
  # named from its exit, and the slot stays taken until the child has gone.
  # It crashes only once its core dump is off.
  local left=$tmp/left
  mkdir -p "$left"
  printf '#!/bin/sh\nshift; exec "$@"\n' > "$left/dbus-run-session"
  printf '#!/bin/sh\nsleep 300 &\necho $! > %q\n[ "$(prlimit --pid $$ --core --raw --noheadings -o SOFT,HARD)" = "1 1" ] && kill -SEGV $$\nexit 0\n' \
    "$tmp/leftover" > "$left/Hyprland"
  chmod +x "$left"/*
  rm -f "$run/launch.status" "$run/leader"
  PATH="$left:$PATH" host_socket=$tmp/no-display zone="" slow="" write_launcher "$run" fake
  setsid bash "$run/launch.sh" < /dev/null > /dev/null 2>&1 &
  if within 5 grep -qs '^exited' "$run/launch.status" && within 5 test -s "$tmp/leftover"; then
    read -r LEADER LEADER_START < "$run/leader"
    crashes 2> /dev/null | grep -qx 'Hyprland (exit 139)' || miss "a compositor's crash should be named from its exit, got: $(crashes 2> /dev/null)"
    slot_free 2> /dev/null && miss "the slot should stay taken while the session's group lives on"
    kill "$(cat "$tmp/leftover")"
    within 3 slot_free 2> /dev/null || miss "the slot should come free once the session's group has gone"
  else
    miss "the crashing stand-in compositor never exited"
  fi
  # The shell's exit: a crash's signal is named, a TERM's isn't.
  echo 134 > "$run/shell.exit"
  crashes 2> /dev/null | grep -qx 'Quickshell (exit 134)' || miss "a shell's crash should be named from its exit"
  echo 143 > "$run/shell.exit"
  crashes 2> /dev/null | grep -q '^Quickshell' && miss "a shell ended by TERM should not read as a crash"

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
  paste) [ $# -eq 2 ] || die "usage: paste FILE"; drive_prelude; nested wl-paste --list-types || die "the clipboard is empty"
    nested wl-paste --no-newline --type image/png > "$2" || { rm -f "$2"; die "the clipboard holds no PNG"; } ;;
  record) shift; cmd_record "$@" ;;
  _record) shift; record_watch "$@" ;;
  shell) shift; (( $# )) || die "usage: shell CMD…"; drive_prelude; nested omarchy-shell "$@" ;;
  log) load_run; cat "$run/shell.log" ;;
  sounds) load_run; cat "$run/sounds.log" 2> /dev/null ;;
  folder) load_run; echo "$run" ;;
  self-check) self_check ;;
  *) sed -n '2,33p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac
