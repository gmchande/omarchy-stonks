pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Hyprland

// Hosts the window, whatever is on the bar, and decides what a request for
// it does with the popup and Hyprland's workspaces, and whether a screen
// shows it. The window itself is App's. It also asks Hyprland, for the
// service, whether every screen is off.
Item {
  id: root

  property var shell: null
  property var service: null
  property var updates: null
  property var trendColors: null

  readonly property alias app: app
  readonly property bool opened: app.opened
  // The window as Hyprland lists it, once it is mapped.
  readonly property var toplevel: app.opened ? Hyprland.toplevels.values.find(root.isWindow) || null : null
  // Hyprland has it on a workspace other than the focused one.
  readonly property bool elsewhere: !!toplevel && !!toplevel.workspace && toplevel.workspace !== Hyprland.focusedWorkspace
  // A screen shows it: a monitor that is on (as `screensOff` reads it) has
  // the window's workspace active, or the special workspace over it. Until
  // Hyprland lists it, and with no screens to ask, as in a harness, it
  // counts as shown. Out of sight it is open as it was left, and the
  // service asks for what a closed surface asks, so a window left on
  // another workspace, or on a screen switched off, costs nothing a closed
  // one doesn't.
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
    return t.title === "Stonks" && !!t.wayland && t.wayland.appId === "org.quickshell"
  }

  function popupOpen() {
    return !!shell && typeof shell.isPluginOpen === "function" && shell.isPluginOpen("grvc.stonks")
  }

  // The pill's right-click and IPC toggleWindow: the window open on this
  // workspace, with no popup over it, closes; otherwise it comes forward.
  function toggle() {
    if (app.opened && !elsewhere && !popupOpen()) app.close()
    else open("{}")
  }

  // Opens the window, or brings it forward where it is, closing the popup.
  // The payload may name a symbol and a range.
  function open(payloadJson) {
    var shown = app.opened
    if (popupOpen()) shell.hide("grvc.stonks")
    app.open(payloadJson)
    if (shown) focusWindow()
  }

  // Omarchy 4 configures Hyprland in Lua, where the classic dispatcher
  // syntax fails.
  function focusWindow() {
    if (!toplevel || !toplevel.address) return
    Hyprland.dispatch("hl.dsp.focus({ window = \"address:0x" + toplevel.address + "\" })")
  }

  // Hyprland's screens. Every one off (DPMS) as Hyprland last answered
  // holds the service's quote runs. `askScreens` asks afresh, before each
  // run; each screen's answer says so (`screensAnswered`). With no screens
  // to ask, it asks nothing and says so. While every screen is off, or the
  // window is open with one off, any word from Hyprland asks again, so a
  // run waits no longer than it must and a screen back on shows the window
  // at once; so does a special workspace shown or hidden, which is in the
  // screens' answer alone.
  readonly property var monitors: Hyprland.monitors.values
  readonly property bool screensOff: monitors.length > 0 && monitors.every(function(m) {
    return !!m.lastIpcObject && m.lastIpcObject.dpmsStatus === false
  })
  readonly property bool screenOff: monitors.some(function(m) {
    return !!m.lastIpcObject && m.lastIpcObject.dpmsStatus === false
  })
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

  App {
    id: app
    service: root.service
    updates: root.updates
    trendColors: root.trendColors
    onScreen: root.onScreen
  }
}
