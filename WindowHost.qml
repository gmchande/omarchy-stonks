pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Hyprland
import Quickshell.Wayland

// Hosts the window (App), with or without a pill on the bar, and tells the
// service whether every screen is off.
Item {
  id: root

  property var shell: null
  // The plugin's id and name, the manifest's (`Plugin`): the id names the
  // panel to the shell, and the name titles the window, which is how
  // Hyprland's list tells it from another copy's.
  property string pluginId: ""
  property string name: ""
  property var service: null
  property var updates: null
  property var sounds: null
  property var camera: null
  property var trendColors: null

  readonly property alias app: app
  readonly property bool opened: app.opened
  readonly property var toplevel: app.opened ? Hyprland.toplevels.values.find(root.isWindow) || null : null
  readonly property bool elsewhere: !!toplevel && !!toplevel.workspace && toplevel.workspace !== Hyprland.focusedWorkspace
  // Until Hyprland lists the window, or with no monitors (a harness), it
  // counts as shown.
  readonly property bool onScreen: {
    var workspace = toplevel ? toplevel.workspace : null
    if (!workspace || root.monitors.length === 0) return true
    return root.monitors.some(function(m) {
      var answer = m.lastIpcObject
      if (answer && answer.dpmsStatus === false) return false
      var special = answer ? answer.specialWorkspace : null
      return m.activeWorkspace === workspace || (!!special && special.id !== 0 && special.id === workspace.id)
    })
  }

  function isWindow(t) {
    return t.title === root.name && !!t.wayland && t.wayland.appId === "org.quickshell"
  }

  function popupOpen() {
    return !!shell && typeof shell.isPluginOpen === "function" && shell.isPluginOpen(root.pluginId)
  }

  function toggle() {
    if (app.opened && !elsewhere && !popupOpen()) app.close()
    else open("{}")
  }

  function open(payloadJson) {
    var shown = app.opened
    if (popupOpen()) shell.hide(root.pluginId)
    app.open(payloadJson)
    if (shown) focusWindow()
  }

  // Omarchy 4 configures Hyprland in Lua; the classic dispatch syntax fails.
  function focusWindow() {
    if (!toplevel || !toplevel.address) return
    Hyprland.dispatch("hl.dsp.focus({ window = \"address:0x" + toplevel.address + "\" })")
  }

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
    enabled: root.screensOff || (root.opened && root.monitors.length > 0)
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

  Connections {
    target: Hyprland
    enabled: root.popupOpen()
    function onRawEvent(event) {
      if (event.name === "openwindow" && event.parse(4)[2] === "org.omarchy.screensaver") root.shell.hide(root.pluginId)
    }
  }

  App {
    id: app
    name: root.name
    service: root.service
    updates: root.updates
    sounds: root.sounds
    camera: root.camera
    trendColors: root.trendColors
    onScreen: root.onScreen
  }
}
