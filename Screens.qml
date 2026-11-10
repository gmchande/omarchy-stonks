pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Hyprland
import Quickshell.Wayland

// Whether the screens are on, for whoever would fetch or draw for them: the
// service before it asks a site, the window for its own screen, and the
// panel for the one it sits on.
Item {
  id: root

  // The window is open: a special workspace's toggle may hide or show it.
  property bool watching: false

  // A screen's DPMS state and its special workspace come only in Hyprland's
  // answer about monitors (`lastIpcObject`), fresh only when asked. While a
  // screen is off, or a special workspace toggles, any event asks again.
  readonly property var monitors: Hyprland.monitors.values
  readonly property bool screensOff: monitors.length > 0 && monitors.every(function(m) {
    return !!m.lastIpcObject && m.lastIpcObject.dpmsStatus === false
  })
  readonly property bool screenOff: monitors.some(function(m) {
    return !!m.lastIpcObject && m.lastIpcObject.dpmsStatus === false
  })
  // Whether one screen is on: off only once Hyprland has said so, as the
  // service asks before each fetch.
  function screenOn(screen) {
    var monitor = screen ? Hyprland.monitorFor(screen) : null
    return !monitor || !monitor.lastIpcObject || monitor.lastIpcObject.dpmsStatus !== false
  }
  signal screensAnswered()
  function askScreens() {
    if (root.monitors.length === 0) return false
    Hyprland.refreshMonitors()
    return true
  }
  Instantiator {
    model: root.monitors
    delegate: Connections {
      required property var modelData
      target: modelData
      function onLastIpcObjectChanged() { root.screensAnswered() }
    }
  }
  Connections {
    target: Hyprland
    enabled: root.screensOff || (root.watching && root.monitors.length > 0)
    function onRawEvent(event) {
      if (root.screensOff || root.screenOff || event.name === "activespecial") Hyprland.refreshMonitors()
    }
  }
  // Hyprland sends no event when a screen wakes, so while all are off the
  // input that wakes them asks again.
  IdleMonitor {
    id: input
    enabled: root.screensOff
    timeout: 1
    respectInhibitors: false
    onIsIdleChanged: if (!isIdle && root.screensOff) Hyprland.refreshMonitors()
  }
}
