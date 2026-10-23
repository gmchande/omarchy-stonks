#!/usr/bin/env bash
# The owner-session facts, one per line: a tophat session's stop compares
# them with its start's (test/tophat.sh), and test/live.sh records them on
# each side of a restart, which explains a change to the first three, the
# shell's services (tophat.sh's shell_facts names them).
#
#   test/host-facts.sh
echo "clipboard watchers: $(pgrep -f 'wl-paste .*--watch' | sort -n | tr '\n' ' ')"
echo "notifications owner: $(busctl --user status org.freedesktop.Notifications 2>/dev/null | grep -E '^(PID|Comm)=' | tr '\n' ' ')"
echo "tray owner: $(busctl --user status org.kde.StatusNotifierWatcher 2>/dev/null | grep -E '^(PID|Comm)=' | tr '\n' ' ')"
systemctl --user show-environment | grep -E '^(DISPLAY|WAYLAND_DISPLAY|HYPRLAND_INSTANCE_SIGNATURE|XDG_RUNTIME_DIR|PATH)=' | sed 's/^/systemd /'
echo "screen brightness: $(brightnessctl -m -c backlight 2>/dev/null | cut -d, -f1,3)"
echo "keyboard brightness: $(brightnessctl -m -d '*kbd_backlight' 2>/dev/null | cut -d, -f1,3)"
echo "power profile: $(powerprofilesctl get 2>/dev/null)"
