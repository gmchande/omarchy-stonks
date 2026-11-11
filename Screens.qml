pragma ComponentBehavior: Bound

import QtQuick

// Whether the screens are on, for whoever would fetch or draw for them: the
// service before it asks a site, the window for its own screen, and the
// panel for the one it sits on.
Item {
  id: root

  // Hyprland, handed in (`Plugin`): its monitors, its events and its ask.
  property var hyprland: null
  // The desktop's input, handed in (`Plugin`): `isIdle` turns false as a
  // key or the pointer moves.
  property var input: null
  // The window is open: a special workspace's toggle may hide or show it.
  property bool watching: false

  // A screen's DPMS state and its special workspace come only in Hyprland's
  // answer about monitors (`lastIpcObject`), fresh only when asked. While a
  // screen is off, or a special workspace toggles, any event asks again.
  readonly property var monitors: hyprland.monitors.values
  readonly property bool screensOff: monitors.length > 0 && monitors.every(function(m) {
    return !!m.lastIpcObject && m.lastIpcObject.dpmsStatus === false
  })
  readonly property bool screenOff: monitors.some(function(m) {
    return !!m.lastIpcObject && m.lastIpcObject.dpmsStatus === false
  })
  // Whether one screen is on: off only once Hyprland has said so, as the
  // service asks before each fetch.
  function screenOn(screen) {
    var monitor = screen ? hyprland.monitorFor(screen) : null
    return !monitor || !monitor.lastIpcObject || monitor.lastIpcObject.dpmsStatus !== false
  }
  signal screensAnswered()
  function askScreens() {
    if (root.monitors.length === 0) return false
    hyprland.refreshMonitors()
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
    target: root.hyprland
    enabled: root.screensOff || (root.watching && root.monitors.length > 0)
    function onRawEvent(event) {
      if (root.screensOff || root.screenOff || event.name === "activespecial") root.hyprland.refreshMonitors()
    }
  }
  // Hyprland sends no event when a screen wakes, so while all are off the
  // input that wakes them asks again.
  Connections {
    target: root.input
    function onIsIdleChanged() {
      if (!root.input.isIdle && root.screensOff) root.hyprland.refreshMonitors()
    }
  }
}
