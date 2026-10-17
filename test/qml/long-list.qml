import QtQuick
import QtTest
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "plugin" as Stonks

// A power user's list: 154 busy US stocks through the real Plugin, Service,
// App, and a pill, on a clock this harness sets, from Wednesday 7 October
// 2026 at 15:00 New York, with the window open. The fake curl answers every
// LONG<n> with NEST's saved day at 14:55, counts every request in
// requests.log and every curl call in runs.log.
ShellRoot {
  id: harness

  property int failures: 0
  readonly property string state: Quickshell.env("STONKS_FAKE_STATE")

  function check(label, ok, detail) {
    console.log((ok ? "PASS " : "FAIL ") + label + (detail !== undefined ? " — " + detail : ""))
    if (!ok) failures++
  }

  // A fake curl record, read through a fresh view: a FileView that has
  // loaded once returns its old text straight after reload().
  function record(name) {
    var view = Qt.createQmlObject('import Quickshell.Io; FileView { blockLoading: true; printErrors: false }', harness)
    view.path = harness.state + "/" + name
    var text = String(view.text() || "")
    view.destroy()
    return text
  }
  function lines(name) {
    return record(name).split("\n").filter(function(line) { return line !== "" })
  }

  Stonks.Plugin { id: plugin; shell: shellApi }
  readonly property var service: plugin.service
  readonly property var app: plugin.windowHost.app

  QtObject { id: workspaceHere }
  QtObject {
    id: hyprlandStandIn
    property var toplevels: ({ values: [] })
    property var focusedWorkspace: workspaceHere
    function dispatch(request) {}
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

  readonly property var pill: pillLoader.item
  FloatingWindow {
    id: pillWindow
    visible: true
    color: "#101315"
    implicitWidth: 320
    implicitHeight: 52
    Loader {
      id: pillLoader
      y: 10
      sourceComponent: Stonks.BarWidget {
        width: implicitWidth
        height: 32
        bar: barApi
        settings: ({ id: "grvc.stonks", barStyle: "text" })
      }
    }
  }

  Process { id: fileProc }

  TestCase {
    name: "LongList"
    when: service.pluginsReady && pillWindow.visible

    function runCommand(command) {
      fileProc.command = command
      fileProc.running = true
      tryVerify(function() { return !fileProc.running }, 2000)
    }
    function touch(name) { runCommand(["touch", harness.state + "/" + name]) }
    function remove(name) { runCommand(["rm", "-f", harness.state + "/" + name]) }

    // No quote run is out: the clock moves on only once each run has
    // landed, as it would in the seconds a run takes.
    function idle() {
      return service.testFeed.firstRun.length === 0 && service.testFeed.refreshRun.length === 0
    }
    function settle() {
      if (!idle()) tryVerify(idle, 30000)
    }
    function tick(seconds, step, each) {
      for (var t = 0; t < seconds; t += step) {
        service.now += step
        settle()
        if (each) each()
      }
    }

    // The rows, and the pill, that say "!" now.
    function warned() {
      var body = app.testBody
      var out = service.library.filter(function(s) {
        var row = body.watchlist.rowItem(s)
        return !!row && /^!/.test(row.detail)
      })
      if (pill.warns) out.push("pill")
      return out
    }

    function test_longList() {
      var start = service.now
      app.open("{}")
      tryVerify(function() { return app.opened && service.openSurfaces.length === 1 }, 3000)

      // Loading: the budget lets only part of the list go at once, and the
      // rest waits its turn. No row says "No data" for that wait.
      var loadWarned = []
      var answered = 0
      for (var t = 0; t < 300 && !answered; t++) {
        service.now += 1
        settle()
        var w = warned()
        if (w.length) loadWarned.push((service.now - start) + " s: " + w.length)
        if (service.library.every(function(s) { return !!service.quotes[s] })) answered = service.now - start
      }
      harness.check("154 symbols load with no row warning while they wait on the budget",
        answered > 0 && loadWarned.length === 0,
        "all answered at " + (answered || "never") + " s; warned " + loadWarned.slice(0, 3).join(", ") + (loadWarned.length > 3 ? " …" : ""))

      // Ten minutes of trading: every row is due each minute, past the
      // budget. A refresh waiting its turn is not overdue.
      var steadyWarned = 0
      tick(600, 5, function() { if (warned().length) steadyWarned++ })
      harness.check("ten minutes of trading on a long list: no row or pill warns while refreshes wait their turn",
        steadyWarned === 0, steadyWarned + " of 120 steps warned")

      // Yahoo refusing: nothing more goes for the pause. Each row says its
      // update is overdue 90 s after its wait on Yahoo began: at once for
      // those waiting at the refusal, and as each falls due after it.
      touch("YAHOO.refuse")
      var refusedAt = 0
      tick(70, 1, function() { if (!refusedAt && service.testYahooGate.pause === "refused") refusedAt = service.now })
      var firstWarnAt = 0
      var allWarnAt = 0
      tick(170, 1, function() {
        var count = warned().length
        if (!firstWarnAt && count > 0) firstWarnAt = service.now - refusedAt
        if (!allWarnAt && count === service.library.length + 1) allWarnAt = service.now - refusedAt
      })
      harness.check("Yahoo refusing: nothing warns for 85 s, then the pill and every row say their update is overdue within 90 s of falling due",
        refusedAt > 0 && firstWarnAt >= 85 && allWarnAt > 0 && allWarnAt <= 155,
        "refused at " + (refusedAt - start) + " s; first warning " + firstWarnAt + " s after, all " + allWarnAt + " s after; " + warned().length + " warn now")
      remove("YAHOO.refuse")
      // The pause has doubled twice by now: the next probe is up to five
      // minutes away, and its answer reopens Yahoo.
      var clearedAt = 0
      tick(480, 5, function() { if (!clearedAt && warned().length === 0) clearedAt = service.now - refusedAt })
      harness.check("Yahoo back: the next probe reopens it, and every warning clears", clearedAt > 0, (clearedAt || "never") + " s after the refusal")

      console.log("LONG LIST DONE")
      done.exitCode = harness.failures ? 1 : 0
      done.start()
    }
  }

  HarnessExit { id: done }
}
