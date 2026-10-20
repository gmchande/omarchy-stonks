import QtQuick
import QtTest
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "plugin" as Stonks

// The look for a newer Stonks, through the real Plugin, Service, Updates,
// App, and a pill, on a clock this harness sets (updates.sh). This build is
// 1.0.9. The service asks GitHub for main's manifest as it starts and a day
// after each ask GitHub answered, within seconds after one it didn't, never
// while every screen is off. An equal, an older, a failed, and a refused
// answer say nothing and show no "!"; a newer one says so in the window's
// footer, whose click runs the update in a terminal, and a later failure
// leaves it; and once the update is on disk, the restart notice takes over.
ShellRoot {
  id: harness

  property int failures: 0
  readonly property string state: Quickshell.env("STONKS_FAKE_STATE")
  readonly property string manifestPath: String(Qt.resolvedUrl("plugin/manifest.json")).replace(/^file:\/\//, "")
  readonly property string updateCall: "launch floating terminal with presentation omarchy plugin update grvc.stonks"

  function check(label, ok, detail) {
    console.log((ok ? "PASS " : "FAIL ") + label + (!ok && detail !== undefined ? " — " + detail : ""))
    if (!ok) failures++
  }

  // A fresh view per read: a FileView that has loaded once can return its
  // old text straight after reload().
  function readFile(path) {
    var view = Qt.createQmlObject('import Quickshell.Io; FileView { blockLoading: true; printErrors: false }', harness)
    view.path = path
    var text = String(view.text() || "")
    view.destroy()
    return text
  }

  // How many times main's manifest was asked for, whatever came back.
  function asked() {
    return harness.readFile(harness.state + "/requests.log").split("\n").filter(function(l) { return /^manifest /.test(l) }).length
  }

  function find(item, name) {
    if (!item) return null
    if (item.objectName === name) return item
    for (var i = 0; i < item.children.length; i++) {
      var found = find(item.children[i], name)
      if (found) return found
    }
    return item.contentItem ? find(item.contentItem, name) : null
  }

  function finish() {
    console.log("UPDATES DONE")
    done.exitCode = failures ? 1 : 0
    done.start()
  }

  // The plugin as the shell composes it, with this harness as its shell.
  Stonks.Plugin { id: plugin; shell: shellApi }
  readonly property var service: plugin.service
  readonly property var app: plugin.windowHost.app
  readonly property var feed: service.testReleaseFeed

  QtObject { id: workspaceHere }
  QtObject {
    id: hyprlandStandIn
    property var toplevels: ({ values: [] })
    property var focusedWorkspace: workspaceHere
    function dispatch(request) {}
    // Hyprland's events, which ask the screens again while every one is
    // off. Only a step sends one.
    signal rawEvent(var event)
  }
  Binding { target: plugin.windowHost; property: "hyprlandStandIn"; value: hyprlandStandIn }

  QtObject {
    id: shellApi
    function serviceFor() { return plugin }
    function isPluginOpen(id) { return false }
    function hide(id) {}
    function updateEntryInline(id, settings) { return true }
  }

  PluginBarApi {
    id: barApi
    pluginId: "grvc.stonks"
    moduleName: "grvc.stonks"
    shell: shellApi
  }

  FloatingWindow {
    id: pillWindow
    visible: true
    color: "#101315"
    implicitWidth: 320
    implicitHeight: 52
    Stonks.BarWidget {
      id: pill
      y: 10
      width: implicitWidth
      height: 32
      bar: barApi
      settings: ({ id: "grvc.stonks", barStyle: "text" })
    }
  }

  // A screen as Hyprland reports it (as fetch.qml's): on or off, as it says
  // when asked again, a turn later. It counts the asks not answered yet.
  QtObject {
    id: screenStandIn
    property bool on: true
    property var lastIpcObject: ({ dpmsStatus: true })
    property int unanswered: 0
    function refresh() {
      unanswered++
      Qt.callLater(function() {
        screenStandIn.lastIpcObject = { dpmsStatus: screenStandIn.on }
        screenStandIn.unanswered--
      })
    }
  }

  Process { id: writer }

  TestCase {
    name: "Updates"
    when: service.pluginsReady && pillWindow.visible

    function within(ms, fn) {
      for (var t = 0; t < ms && !fn(); t += 20) wait(20)
      return fn()
    }

    function run(command) {
      writer.command = command
      writer.running = true
      tryVerify(function() { return !writer.running }, 3000)
    }
    function put(name, text) { run(["bash", "-c", "printf '%s' \"$1\" > \"$2\"", "--", text, harness.state + "/" + name]) }
    function remove(name) { run(["rm", "-f", harness.state + "/" + name]) }

    // The look asked for `count` times in all, and its last answer in.
    function answered(count) {
      return within(5000, function() { return harness.asked() === count && !harness.feed.testAsking })
    }

    // The clock a day on from the last look: everything due there asked.
    function nextDay() {
      service.now = harness.feed.askedAt + 24 * 60 * 60
    }

    function footer() {
      return String(harness.find(harness.find(app.testBody, "footer"), "footerText").text)
    }

    // Every "!" on show: the pill's, and each row's.
    function marks() {
      var out = []
      if (pill.warns) out.push("pill !")
      app.testBody.watchlist.displayedSymbols.forEach(function(s) {
        var row = app.testBody.watchlist.rowItem(s)
        if (row && /^!/.test(row.detail)) out.push(s + ": " + row.detail)
      })
      return out
    }

    function test_updates() {
      app.open("{}")
      tryVerify(function() { return app.opened && service.openSurfaces.length === 1 }, 3000)
      var quoted = within(5000, function() { return ["AAPL", "MSFT", "NVDA"].every(function(s) { return !!service.quotes[s] }) })

      // As the service starts, main names this build's version.
      var started = answered(1)
      harness.check("as the service starts, it asks GitHub once for main's version, and the same version says nothing",
        quoted && started && footer() === "+  Add a symbol" && marks().length === 0,
        harness.asked() + " asks | " + footer() + " | " + marks().join(", "))

      // A second short of a day: nothing. A day on: asked again, older.
      put("MANIFEST.version", "1.0.8")
      service.now = harness.feed.askedAt + 24 * 60 * 60 - 1
      var early = harness.feed.testAsking || harness.asked() !== 1
      nextDay()
      var older = answered(2)
      harness.check("a day after the last ask, not a second sooner, it asks again, and an older version says nothing",
        !early && older && footer() === "+  Add a symbol",
        harness.asked() + " asks | " + footer())

      // A failed answer, then a refusal, a day apart.
      put("MANIFEST.down", "")
      nextDay()
      var failed = answered(3) && footer() === "+  Add a symbol" && marks().length === 0
      remove("MANIFEST.down")
      put("GITHUB.refuse", "")
      nextDay()
      var refused = answered(4) && footer() === "+  Add a symbol" && marks().length === 0
      remove("GITHUB.refuse")
      harness.check("a failed answer and a refusal say nothing and show no \"!\"",
        failed && refused, failed + " " + refused + " | " + harness.asked() + " asks | " + footer() + " | " + marks().join(", "))

      // No answer at all, as straight after a wake before the network is
      // back: it asks again once the gate's pause of a few seconds is over,
      // not a day later.
      put("GITHUB.offline", "")
      nextDay()
      var unanswered = answered(5)
      remove("GITHUB.offline")
      service.now += 5
      var retried = answered(6)
      harness.check("an ask that got no answer at all goes again within seconds, and says nothing meanwhile",
        unanswered && retried && footer() === "+  Add a symbol" && marks().length === 0,
        unanswered + " " + retried + " | " + harness.asked() + " asks | " + footer() + " | " + marks().join(", "))

      // Every screen off a day on: nothing is asked. On again, the next
      // word from Hyprland asks the screens, and the look goes.
      put("MANIFEST.version", "1.0.10")
      screenStandIn.on = false
      screenStandIn.lastIpcObject = { dpmsStatus: false }
      plugin.windowHost.monitors = [screenStandIn]
      nextDay()
      tryVerify(function() { return screenStandIn.unanswered === 0 }, 3000)
      var dark = harness.asked() === 6 && !harness.feed.testAsking && footer() === "+  Add a symbol"
      screenStandIn.on = true
      hyprlandStandIn.rawEvent({})
      var lit = answered(7)
      harness.check("while every screen is off it asks nothing; with one on, it asks, and a newer version says so in the footer",
        dark && lit && within(1000, function() { return footer() === "Stonks 1.0.10 is out · click to update" }),
        dark + " " + lit + " | " + harness.asked() + " asks | " + footer())
      plugin.windowHost.monitors = []

      // The click runs the update in a terminal, and adds nothing.
      var notice = harness.find(app.testBody, "footer")
      mouseClick(notice, notice.width / 2, notice.height / 2)
      var ran = within(5000, function() { return harness.readFile(harness.state + "/omarchy.calls") === harness.updateCall + "\n" })
      harness.check("a click on the notice runs omarchy plugin update grvc.stonks in a terminal, and adds nothing",
        ran && !app.testBody.adding, harness.readFile(harness.state + "/omarchy.calls") + " | " + app.testBody.adding)

      // A failed answer later changes nothing: the notice stays.
      put("MANIFEST.down", "")
      nextDay()
      var kept = answered(8)
      remove("MANIFEST.down")
      harness.check("a failed answer once a newer version is known leaves its notice",
        kept && footer() === "Stonks 1.0.10 is out · click to update", harness.asked() + " asks | " + footer())

      // The update lands on disk as git writes it, the old file removed and
      // a new one made, while the window stays open: its footer says the
      // restart's notice at once.
      var manifest = JSON.parse(harness.readFile(harness.manifestPath))
      manifest.version = "1.0.10"
      run(["bash", "-c", "rm -f \"$2\" && printf '%s' \"$1\" > \"$2\"", "--", JSON.stringify(manifest, null, 2) + "\n", harness.manifestPath])
      harness.check("once the update is on disk, the open window's restart notice takes over",
        within(3000, function() { return footer() === "Updated to 1.0.10 · click to restart the shell" }), footer())

      harness.finish()
    }
  }

  HarnessExit { id: done }
}
