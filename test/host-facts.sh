#!/usr/bin/env bash
# The owner-session facts, one per line: a tophat session's stop compares
# them with its start's (test/tophat.sh), and test/live.sh records them on
# each side of a restart, which explains a change to the first three, the
# shell's services (tophat.sh's shell_facts names them).
#
#   test/host-facts.sh
# A watcher is the wl-paste process itself. Each clipboard change forks a
# child from it that carries its name and command line until it runs the
# capture script, so the child is no watcher: counted, it came and went as
# the owner copied, and failed a session's stop (the check of #74, 23
# October). Only a wl-paste whose parent is no watcher counts.
watchers() {
  ps -ww -eo pid=,ppid=,comm=,args= | awk '
    $3 == "wl-paste" && index($0, "--watch") { watcher[$1] = $2 }
    END { for (pid in watcher) if (!(watcher[pid] in watcher)) print pid }'
}
echo "clipboard watchers: $(watchers | sort -n | tr '\n' ' ')"
echo "notifications owner: $(busctl --user status org.freedesktop.Notifications 2>/dev/null | grep -E '^(PID|Comm)=' | tr '\n' ' ')"
echo "tray owner: $(busctl --user status org.kde.StatusNotifierWatcher 2>/dev/null | grep -E '^(PID|Comm)=' | tr '\n' ' ')"
systemctl --user show-environment | grep -E '^(DISPLAY|WAYLAND_DISPLAY|HYPRLAND_INSTANCE_SIGNATURE|XDG_RUNTIME_DIR|PATH)=' | sed 's/^/systemd /'
echo "screen brightness: $(brightnessctl -m -c backlight 2>/dev/null | cut -d, -f1,3)"
echo "keyboard brightness: $(brightnessctl -m -d '*kbd_backlight' 2>/dev/null | cut -d, -f1,3)"
echo "power profile: $(powerprofilesctl get 2>/dev/null)"
