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
// answer say nothing and show no "!". A newer one is offered at the footer's
// right end each time the window opens, beside the add, which still adds:
// its click and Shift+U run the update in a terminal, and an undo takes its
// place for the undo's seconds. Once the update is on disk, the restart
// notice takes over, which a click and Shift+U act on.
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

    // What the footer says, its notice's action included, and what its
    // right end offers: the update, an undo, or "".
    function footer() {
      var bar = harness.find(app.testBody, "footer")
      var action = harness.find(bar, "footerAction")
      return String(harness.find(bar, "footerText").text) + (action.visible ? String(action.text) : "")
    }
    function offer() {
      var side = harness.find(harness.find(app.testBody, "footer"), "footerUndo")
      return side.visible ? String(harness.find(side, "footerUndoText").text) : ""
    }
    function clickFooter() {
      var bar = harness.find(app.testBody, "footer")
      mouseClick(bar, bar.width / 2, bar.height / 2)
    }
    function clickOffer() {
      var side = harness.find(harness.find(app.testBody, "footer"), "footerUndo")
      mouseClick(side, side.width / 2, side.height / 2)
    }
    // Shift+U, as a person presses it, in the open window.
    function shiftU() {
      app.testKeyCatcher.forceActiveFocus()
      keyClick("U", Qt.ShiftModifier)
      wait(100)
    }
    function calls() { return harness.readFile(harness.state + "/omarchy.calls") }

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

    // The window opened with the pointer off its footer, which would hold
    // a note.
    function openWindow() {
      app.open("{}")
      tryVerify(function() { return app.opened && service.openSurfaces.length === 1 }, 3000)
      mouseMove(app.testBody, 1, 1)
    }
    function closeWindow() {
      app.close()
      tryVerify(function() { return service.openSurfaces.length === 0 }, 3000)
    }
    // What the footer, its offer, and the marks say as the window opens;
    // then closed.
    function visit() {
      openWindow()
      var said = footer() + " | " + offer() + " | " + marks().join(", ")
      closeWindow()
      return said
    }

    function test_updates() {
      var quoted = within(5000, function() { return ["AAPL", "MSFT", "NVDA"].every(function(s) { return !!service.quotes[s] }) })
      var add = "+  Add a symbol |  | "
      var newer = "+  Add a symbol | Update to 1.0.10 | "

      // As the service starts, main names this build's version. Shift+U,
      // with nothing offered, runs nothing.
      var started = answered(1)
      var first = visit()
      openWindow()
      shiftU()
      var idle = calls()
      closeWindow()
      harness.check("as the service starts, it asks GitHub once for main's version; the same version offers nothing, and Shift+U runs nothing",
        quoted && started && first === add && idle === "", harness.asked() + " asks | " + first + " | " + idle)

      // A second short of a day: nothing. A day on: asked again, older.
      put("MANIFEST.version", "1.0.8")
      service.now = harness.feed.askedAt + 24 * 60 * 60 - 1
      var early = harness.feed.testAsking || harness.asked() !== 1
      nextDay()
      var older = answered(2) && visit()
      harness.check("a day after the last ask, not a second sooner, it asks again, and an older version says nothing",
        !early && older === add, harness.asked() + " asks | " + older)

      // A failed answer, then a refusal, a day apart.
      put("MANIFEST.down", "")
      nextDay()
      var failed = answered(3) && visit()
      remove("MANIFEST.down")
      put("GITHUB.refuse", "")
      nextDay()
      var refused = answered(4) && visit()
      remove("GITHUB.refuse")
      harness.check("a failed answer and a refusal say nothing and show no \"!\"",
        failed === add && refused === add, harness.asked() + " asks | " + failed + " / " + refused)

      // No answer at all, as straight after a wake before the network is
      // back: while Yahoo gets none either, GitHub is not asked again,
      // minutes on; once Yahoo answers again, it is asked at once, not a day
      // later. It was asked again each time GitHub's pause ended, about once
      // a minute for as long as the network was down.
      put("GITHUB.offline", "")
      put("YAHOO.offline", "")
      nextDay()
      var unanswered = answered(5)
      openWindow()
      for (var m = 0; m < 5; m++) {
        service.now += 60
        wait(200)
      }
      var held = harness.asked() === 5 && service.yahooGate.paused
      remove("GITHUB.offline")
      remove("YAHOO.offline")
      service.now += 120
      var retried = answered(6)
      // The quotes the outage held catch up before the window closes.
      for (var s = 0; s < 20 && Object.keys(service.owed).length > 0; s++) {
        service.now += 5
        wait(100)
      }
      closeWindow()
      var said = visit()
      harness.check("an ask that got no answer at all waits while Yahoo gets none either, and goes again once Yahoo answers, saying nothing meanwhile",
        unanswered && held && retried && said === add, [unanswered, held, retried, harness.asked() + " asks", said].join(" | "))

      // Every screen off a day on: nothing is asked. On again, the next
      // word from Hyprland asks the screens, and the look goes.
      put("MANIFEST.version", "1.0.10")
      screenStandIn.on = false
      screenStandIn.lastIpcObject = { dpmsStatus: false }
      plugin.windowHost.monitors = [screenStandIn]
      nextDay()
      tryVerify(function() { return screenStandIn.unanswered === 0 }, 3000)
      var dark = harness.asked() === 6 && !harness.feed.testAsking
      screenStandIn.on = true
      hyprlandStandIn.rawEvent({})
      var lit = answered(7)
      plugin.windowHost.monitors = []
      openWindow()
      var said = footer() + " | " + offer() + " | " + marks().join(", ")
      harness.check("while every screen is off it asks nothing; with one on, it asks, and the next open offers the newer version beside the add",
        dark && lit && said === newer, dark + " " + lit + " | " + harness.asked() + " asks | " + said)

      // A click on the offer runs the update in a terminal, adds nothing,
      // and the offer stays: nothing is on disk yet.
      clickOffer()
      var ran = within(5000, function() { return calls() === harness.updateCall + "\n" })
      harness.check("a click on \"Update to 1.0.10\" runs omarchy plugin update grvc.stonks in a terminal, adds nothing, and stays",
        ran && !app.testBody.adding && offer() === "Update to 1.0.10", calls() + " | " + app.testBody.adding + " | " + offer())
      closeWindow()

      // Opened again before the next answer: offered still, beside the
      // add, which a click starts; Shift+U runs the update again. Found in
      // the 1.0.4 update walk of 26 October: the old note had gone in its 5
      // seconds, and the click meant for it opened search.
      openWindow()
      var again = footer() + " | " + offer()
      clickFooter()
      var adding = within(1000, function() { return app.testBody.adding })
      app.testBody.cancelAdding()
      shiftU()
      var keyed = within(5000, function() { return calls() === harness.updateCall + "\n" + harness.updateCall + "\n" })
      closeWindow()
      harness.check("opened again, the update is still offered; a click on the add starts adding, and Shift+U runs the update",
        again === "+  Add a symbol | Update to 1.0.10" && adding && keyed, again + " | adding " + adding + " | " + calls())

      // A failed answer names nothing new: the version known stays offered.
      put("MANIFEST.down", "")
      nextDay()
      var failedLater = answered(8) && visit()
      remove("MANIFEST.down")
      harness.check("a failed answer once a newer version is known keeps it offered",
        failedLater === newer, harness.asked() + " asks | " + failedLater)

      // A removal's undo takes the offer's place for its seconds, and a
      // click there undoes; then the update is offered again.
      openWindow()
      var gone = app.testBody.watchlist.displayedSymbols[0]
      app.testBody.removeFrom(gone, true)
      var undoing = within(2000, function() { return offer() === "Undo " + gone })
      clickOffer()
      var back = within(2000, function() { return service.symbols.indexOf(gone) >= 0 && offer() === "Update to 1.0.10" })
      closeWindow()
      harness.check("a removal's undo takes the offer's place, its click undoes and runs no update, and the update is offered again",
        undoing && back && calls() === harness.updateCall + "\n" + harness.updateCall + "\n", undoing + " " + back + " | " + offer() + " | " + calls())

      // The update lands on disk as git writes it, the old file removed and
      // a new one made, while the window stays open: the restart's notice
      // takes the add's place at once and the offer goes; Shift+U restarts
      // the shell, and so does a click. A later answer naming a newer
      // version offers nothing over it.
      nextDay()
      var noteDay = answered(9)
      openWindow()
      var offered = offer() === "Update to 1.0.10"
      var manifest = JSON.parse(harness.readFile(harness.manifestPath))
      manifest.version = "1.0.10"
      run(["bash", "-c", "rm -f \"$2\" && printf '%s' \"$1\" > \"$2\"", "--", JSON.stringify(manifest, null, 2) + "\n", harness.manifestPath])
      var restart = "Updated to 1.0.10 · click to restart the shell"
      var tookOver = within(3000, function() { return footer() === restart && offer() === "" })
      var updates = harness.updateCall + "\n" + harness.updateCall + "\n"
      shiftU()
      var keyRestart = within(5000, function() { return calls() === updates + "restart shell\n" })
      clickFooter()
      var restarted = within(5000, function() { return calls() === updates + "restart shell\nrestart shell\n" })
      closeWindow()
      put("MANIFEST.version", "1.0.11")
      nextDay()
      var afterDisk = answered(10) && visit()
      harness.check("once the update is on disk, the open window's restart notice takes over and the offer goes; Shift+U and a click each restart, and no newer version is offered over it",
        noteDay && offered && tookOver && keyRestart && restarted && afterDisk === restart + " |  | ",
        offered + " " + tookOver + " " + keyRestart + " " + restarted + " | " + afterDisk + " | " + calls())

      // "updateCheck": false in the data file, as the README says: a day on,
      // and a day after that, GitHub is asked nothing. Taken out again, the
      // check goes at once.
      var dataFile = Quickshell.env("HOME") + "/.config/omarchy/grvc.stonks.json"
      var edit = function(filter) {
        run(["bash", "-c", "jq \"$1\" \"$2\" > \"$2.tmp\" && mv -f \"$2.tmp\" \"$2\"", "--", filter, dataFile])
      }
      edit(".updateCheck = false")
      var off = within(3000, function() { return service.dataSettings.updateCheck === false })
      // An ask starts as the clock moves (`ReleaseFeed.pump`): none went if
      // none is out at once.
      nextDay()
      var quiet = !harness.feed.testAsking
      service.now += 24 * 60 * 60
      quiet = quiet && !harness.feed.testAsking
      var askedOff = harness.asked()
      edit("del(.updateCheck)")
      var backOn = within(3000, function() { return service.dataSettings.updateCheck === true })
      var askedOn = answered(11)
      harness.check("with \"updateCheck\": false in the data file, GitHub is asked nothing for two days; without it, at once",
        off && quiet && askedOff === 10 && backOn && askedOn, [off, quiet, askedOff + " asks while off", backOn, harness.asked() + " asks"].join(" | "))

      harness.finish()
    }
  }

  HarnessExit { id: done }
}
