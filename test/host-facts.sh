#!/usr/bin/env bash
# The owner-session facts, one per line: a tophat session's stop compares
# them with its start's (test/tophat.sh), and test/live.sh records them on
# each side of a restart, which explains a change to the first three, the
# shell's services (tophat.sh's shell_facts names them).
#
#   test/host-facts.sh
# The owner's clipboard watchers are the wl-paste --watch processes their
# Quickshell (the one running /usr/share/omarchy/shell) started: a watcher
# counts only when that is its parent. Any other program's watcher, Herdr's
# for another agent's pane, comes and goes without the owner changing
# theirs, and failed a session's stop (the check of #77, 23 October). A
# tophat run's own Quickshell is no owner's: every process a run starts has
# TOPHAT_RUN in its environment. The same parent test leaves out the child
# each clipboard change forks from a watcher, which carries its name and
# command line until it runs the capture script (#74). A running shell whose
# environment can't be read can't be told from a run's, so the facts fail
# rather than leave its watchers out, where a change to them would go unseen.
owner_shells() {
  local pid env
  ps -ww -eo pid=,comm=,args= | awk '$2 == "quickshell" && index($0, "/usr/share/omarchy/shell") { print $1 }' |
    while read -r pid; do
      if ! env=$(tr '\0' '\n' < "/proc/$pid/environ" 2> /dev/null); then
        [ -e "/proc/$pid" ] || continue
        echo "host-facts: the environment of the shell running as $pid can't be read, so its watchers can't be told from a run's" >&2
        exit 1
      fi
      grep -q '^TOPHAT_RUN=' <<< "$env" || echo "$pid"
    done
}
shells=$(owner_shells) || exit 1
watchers() {
  ps -ww -eo pid=,ppid=,comm=,args= | awk -v shells=" $(tr '\n' ' ' <<< "$shells")" '
    $3 == "wl-paste" && index($0, "--watch") && index(shells, " " $2 " ") { print $1 }'
}
echo "clipboard watchers: $(watchers | sort -n | tr '\n' ' ')"
echo "notifications owner: $(busctl --user status org.freedesktop.Notifications 2>/dev/null | grep -E '^(PID|Comm)=' | tr '\n' ' ')"
echo "tray owner: $(busctl --user status org.kde.StatusNotifierWatcher 2>/dev/null | grep -E '^(PID|Comm)=' | tr '\n' ' ')"
systemctl --user show-environment | grep -E '^(DISPLAY|WAYLAND_DISPLAY|HYPRLAND_INSTANCE_SIGNATURE|XDG_RUNTIME_DIR|PATH)=' | sed 's/^/systemd /'
echo "screen brightness: $(brightnessctl -m -c backlight 2>/dev/null | cut -d, -f1,3)"
echo "keyboard brightness: $(brightnessctl -m -d '*kbd_backlight' 2>/dev/null | cut -d, -f1,3)"
echo "power profile: $(powerprofilesctl get 2>/dev/null)"
