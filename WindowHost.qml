pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Hyprland

// Hosts the window (App), with or without a pill on the bar.
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
  // The screens (`Screens`): which are on, and what each one shows.
  property var screens: null
  readonly property var monitors: screens ? screens.monitors : []

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
