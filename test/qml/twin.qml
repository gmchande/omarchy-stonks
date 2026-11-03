import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui
import "plugin" as Stonks

// Two copies of Stonks side by side, as the real Plugin (twin.sh): the
// tree's manifest, grvc.stonks, a user's install whose folder is a clone,
// and the same manifest under grvc.stonks-dev, named "Stonks dev", whose
// folder is a worktree. Each reads and writes only its own lists file and
// cache folder, answers only on its own IPC target, asks the shell only for
// its own service and panel, and with both windows open finds its own by
// its title. Only the clone asks GitHub for a newer Stonks, and offers it.
Harness {
  id: harness
  marker: "TWIN DONE"

  readonly property string state: Quickshell.env("STONKS_FAKE_STATE")
  readonly property string config: Quickshell.env("HOME") + "/.config/omarchy/"
  readonly property string cache: Quickshell.env("XDG_CACHE_HOME") + "/"
  readonly property var released: harness.pluginManifest()
  readonly property var dev: Object.assign({}, released, { id: "grvc.stonks-dev", name: "Stonks dev" })

  // The shell as each copy's own scoped API is: it hands a plugin only its
  // own service, and records the panel calls it is asked for.
  component ShellStandIn: QtObject {
    property var plugin: null
    property var asked: []
    function serviceFor(id) { return id === plugin.pluginId ? plugin : null }
    function isPluginOpen(id) { return false }
    function summon(id, payload) { asked = asked.concat(["summon " + id]) }
    function hide(id) { asked = asked.concat(["hide " + id]) }
    function toggle(id, payload) { asked = asked.concat(["toggle " + id]) }
    function updateEntryInline(id, settings) { return true }
  }

  // The shell sets a service's manifest just after making it (shell.qml,
  // createObject then `inst.manifest`), once its parts have completed, so
  // the copies start with none and get theirs a turn later.
  Stonks.Plugin { id: releaseCopy; shell: releaseShell }
  Stonks.Plugin { id: devCopy; shell: devShell }
  Component.onCompleted: Qt.callLater(function() {
    releaseCopy.manifest = harness.released
    devCopy.manifest = harness.dev
  })
  ShellStandIn { id: releaseShell; plugin: releaseCopy }
  ShellStandIn { id: devShell; plugin: devCopy }
  PluginBarApi { id: releaseBar; pluginId: "grvc.stonks"; moduleName: "grvc.stonks"; shell: releaseShell }
  PluginBarApi { id: devBar; pluginId: "grvc.stonks-dev"; moduleName: "grvc.stonks-dev"; shell: devShell }

  // Hyprland with both windows open on the workspace in view: Stonks' and
  // Stonks dev's.
  QtObject { id: workspaceHere }
  QtObject {
    id: releaseToplevel
    property string title: "Stonks"
    property var wayland: ({ appId: "org.quickshell" })
    property string address: "a11"
    property var workspace: workspaceHere
  }
  QtObject {
    id: devToplevel
    property string title: "Stonks dev"
    property var wayland: ({ appId: "org.quickshell" })
    property string address: "de7"
    property var workspace: workspaceHere
  }
  QtObject {
    id: hyprlandStandIn
    property var toplevels: ({ values: [devToplevel, releaseToplevel] })
    property var focusedWorkspace: workspaceHere
    property var dispatched: []
    function dispatch(request) { dispatched = dispatched.concat([request]) }
    signal rawEvent(var event)
  }
  Binding { target: releaseCopy.windowHost; property: "hyprlandStandIn"; value: hyprlandStandIn }
  Binding { target: devCopy.windowHost; property: "hyprlandStandIn"; value: hyprlandStandIn }

  FloatingWindow {
    id: pillWindow
    visible: true
    color: "#101315"
    implicitWidth: 320
    implicitHeight: 104
    Stonks.BarWidget { id: releasePill; y: 10; width: implicitWidth; height: 32; bar: releaseBar; moduleName: "grvc.stonks"; settings: ({ id: "grvc.stonks", barStyle: "text" }) }
    Stonks.BarWidget { id: devPill; y: 62; width: implicitWidth; height: 32; bar: devBar; moduleName: "grvc.stonks-dev"; settings: ({ id: "grvc.stonks-dev", barStyle: "text" }) }
  }

  // Calls the harness's own Quickshell over IPC, as omarchy-shell does.
  Process { id: ipcCall }
  function callIpc(target, fn, arg) {
    ipcCall.command = ["quickshell", "ipc", "--id", Quickshell.instanceId, "call", target, fn].concat(arg === undefined ? [] : [arg])
    ipcCall.running = true
  }

  function lists(id) {
    try { return JSON.parse(harness.readFile(harness.config + id + ".json")).symbols.join(",") } catch (e) { return "unreadable" }
  }
  function cachedSymbols(id) {
    try { return Object.keys(JSON.parse(harness.readFile(harness.cache + id + "/quotes.json")).quotes).sort().join(",") } catch (e) { return "" }
  }
  // How many times main's manifest was asked for.
  function asked() {
    return harness.readFile(harness.state + "/requests.log").split("\n").filter(function(l) { return /^manifest /.test(l) }).length
  }

  Steps {
    name: "Twin"
    when: releaseCopy.service.pluginsReady && devCopy.service.pluginsReady && pillWindow.visible

    function ipc(target, fn, arg) {
      harness.callIpc(target, fn, arg)
      tryVerify(function() { return !ipcCall.running }, 5000)
    }

    function test_twin() {
      var releaseService = releaseCopy.service
      var devService = devCopy.service

      harness.check("each copy reads its own lists file, and its pill shows its own stock",
        releaseService.library.join(",") === "AAPL,MSFT,NVDA" && devService.library.join(",") === "NVDA"
          && releasePill.featuredSymbol === "MSFT" && devPill.featuredSymbol === "NVDA",
        releaseService.library + " | " + devService.library + " | " + releasePill.featuredSymbol + " | " + devPill.featuredSymbol)

      // Each saves the prices of its own list once they have come and the
      // runs that brought them have landed, on its clock's next tick
      // (`Service.flushQuotes`). A run whose end is heard after its answers
      // were read leaves the save to that tick, which with nothing open is up
      // to a minute on: once each feed is quiet, the clocks tick here until
      // the saves land. Before the edits below, whose asks would hold the
      // save again.
      var quiet = within(30000, function() {
        return [releaseService, devService].every(function(s) {
          return !s.testFeed.busy && s.library.every(function(symbol) { return !!s.quotes[symbol] })
        })
      })
      var cached = quiet && within(5000, function() {
        releaseService.tick()
        devService.tick()
        return harness.cachedSymbols("grvc.stonks") === "AAPL,MSFT,NVDA" && harness.cachedSymbols("grvc.stonks-dev") === "NVDA"
      })
      harness.check("each copy keeps the last prices of its own list in its own cache folder",
        cached, (quiet ? "" : "the feeds never went quiet | ") + harness.cachedSymbols("grvc.stonks") + " | " + harness.cachedSymbols("grvc.stonks-dev"))

      // An edit in each lands in its own file alone.
      var releaseText = harness.readFile(harness.config + "grvc.stonks.json")
      devService.addSymbol("AAPL")
      var devSaved = within(3000, function() { return harness.lists("grvc.stonks-dev") === "NVDA,AAPL" })
      var releaseKept = harness.readFile(harness.config + "grvc.stonks.json") === releaseText
      var devText = harness.readFile(harness.config + "grvc.stonks-dev.json")
      releaseService.removeSymbol("NVDA")
      var releaseSaved = within(3000, function() { return harness.lists("grvc.stonks") === "AAPL,MSFT" })
      var devKept = harness.readFile(harness.config + "grvc.stonks-dev.json") === devText
      harness.check("an edit in one copy is saved to its lists file and leaves the other's as it was",
        devSaved && releaseKept && releaseSaved && devKept,
        harness.lists("grvc.stonks") + " | " + harness.lists("grvc.stonks-dev") + " | " + releaseKept + "," + devKept)

      // IPC: each target opens its own window and asks for its own panel.
      ipc("grvc.stonks-dev", "openWindow", "{}")
      var devOnly = devCopy.windowHost.opened && !releaseCopy.windowHost.opened
      ipc("grvc.stonks", "toggleWindow")
      var both = devCopy.windowHost.opened && releaseCopy.windowHost.opened
      ipc("grvc.stonks-dev", "open")
      ipc("grvc.stonks", "close")
      harness.check("each IPC target opens its own copy's window and asks the shell for its own panel",
        devOnly && both && devShell.asked.join(",") === "summon grvc.stonks-dev"
          && releaseShell.asked.join(",") === "hide grvc.stonks",
        devOnly + "," + both + " | " + devShell.asked + " | " + releaseShell.asked)

      harness.check("with both windows open, each is titled with its copy's name and each copy finds its own",
        releaseCopy.windowHost.app.testWindow.title === "Stonks" && devCopy.windowHost.app.testWindow.title === "Stonks dev"
          && releaseCopy.windowHost.toplevel === releaseToplevel && devCopy.windowHost.toplevel === devToplevel,
        releaseCopy.windowHost.app.testWindow.title + " | " + devCopy.windowHost.app.testWindow.title)

      // Only the clone, which `omarchy plugin update` can update, asks
      // GitHub, and offers what main has.
      var offered = within(5000, function() { return releaseCopy.updates.releasedVersion === "99.0.0" })
      harness.check("the clone offers main's newer version; the worktree asks GitHub nothing and offers nothing",
        offered && harness.asked() === 1 && devCopy.updates.releasedVersion === "",
        releaseCopy.updates.releasedVersion + " | " + harness.asked() + " asks | " + devCopy.updates.releasedVersion)

      harness.finish()
    }
  }
}
