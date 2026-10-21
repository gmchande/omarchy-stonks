import QtQuick
import QtTest
import Quickshell
import Quickshell.Io
import "Settings.js" as Settings

// A data file a release wrote, through the real Service (data-files.sh).
// What the user made is written out here, not read from the file, so a
// loader that loses something can't lose it from what the check expects
// too. With STONKS_DATA_FILE=write, the Service starts with no file and
// makes all of it through its own functions, as the surfaces call them; the
// script keeps the file it saved. Every quote and history ask fails: no
// saved answers. STONKS_DATA_VERSION names the release.
ShellRoot {
  id: harness

  property int failures: 0
  readonly property bool writing: Quickshell.env("STONKS_DATA_FILE") === "write"
  readonly property string version: Quickshell.env("STONKS_DATA_VERSION")

  // The demo watchlist's symbols: All in an order made by hand, a list in
  // manual order arranged by hand, one sorted, one sorted the other way, and
  // one empty; the current list a named one, a featured symbol off the top,
  // and every view setting off its default. The refresh interval is set only
  // by hand in the file, which every save keeps. 1.0.0 knew no sounds, so
  // its file reads as on, their default; from 1.0.3 the file has them off.
  readonly property var made: ({
    lists: [
      { name: "", symbols: ["SPY", "AAPL", "7203.T", "BTC-USD", "^GSPC", "SHEL.L", "JNJ"], order: "manual", reversed: false },
      { name: "US", symbols: ["SPY", "JNJ", "AAPL", "^GSPC"], order: "manual", reversed: false },
      { name: "World", symbols: ["SHEL.L", "7203.T", "AAPL"], order: "name", reversed: false },
      { name: "Movers", symbols: ["BTC-USD", "JNJ", "7203.T"], order: "pct", reversed: true },
      { name: "Later", symbols: [], order: "manual", reversed: false }
    ],
    list: "World",
    featured: "7203.T",
    range: "1Y",
    style: "retro",
    changeMode: "abs",
    refreshIntervalSec: 300,
    hinted: true,
    sounds: version === "1.0.0"
  })

  function check(label, ok, detail) {
    console.log((ok ? "PASS " : "FAIL ") + label + (!ok && detail !== undefined ? " — got " + detail : ""))
    if (!ok) failures++
  }

  function finish(marker) {
    console.log(failures ? failures + " FAILED" : marker)
    done.exitCode = failures ? 1 : 0
    done.start()
  }

  function label(list) {
    return (list.name || "All") + ": " + (list.symbols.join(", ") || "empty") + ", " + list.order + (list.reversed ? " reversed" : "")
  }

  // What the Service shows of the current list, in the spec's words.
  function shown() {
    return { name: service.listName, symbols: service.symbols, order: service.order, reversed: service.reversed }
  }

  Service { id: service }
  HarnessExit { id: done }

  // A fresh read of the file the Service saved.
  FileView { id: saved; path: service.dataPath; blockLoading: true; printErrors: false }

  TestCase {
    name: "DataFiles"
    when: service.pluginsReady

    function test_file() {
      if (harness.writing) make()
      else load()
    }

    function make() {
      var all = harness.made.lists[0]
      // From the defaults: the demo's symbols in, the rest out, then All
      // arranged by hand.
      all.symbols.forEach(function(s) { if (service.library.indexOf(s) < 0) service.addSymbol(s) })
      service.library.slice().forEach(function(s) { if (all.symbols.indexOf(s) < 0) service.removeSymbol(s) })
      service.setManualOrder(all.symbols)
      harness.made.lists.slice(1).forEach(function(list) {
        service.createList(list.name)
        // A manual list's members go in in All's order, and are then
        // arranged by hand; a sorted one's stay as they went in.
        var members = list.order === "manual" ? all.symbols.filter(function(s) { return list.symbols.indexOf(s) >= 0 }) : list.symbols
        members.forEach(function(s) { service.setMembership(s, list.name, true) })
        if (list.order === "manual") service.setManualOrder(list.symbols)
        else service.setOrder(list.order)
        if (list.reversed) service.reverseOrder()
      })
      service.switchList(harness.made.list)
      service.feature(harness.made.featured)
      service.setRange(harness.made.range)
      service.persist({ style: harness.made.style })
      service.persist({ changeMode: Settings.nextChangeMode(service.changeMode) })
      service.persist({ refreshIntervalSec: harness.made.refreshIntervalSec })
      service.persist({ hinted: harness.made.hinted })
      if (harness.version !== "1.0.0") service.persist({ sounds: harness.made.sounds })
      wait(100)
      saved.reload()
      var file = null
      try { file = JSON.parse(saved.text()) } catch (e) {}
      harness.check("the Service saved what was made", !!file && Settings.settingsEqual(file, service.dataSettings)
        && JSON.stringify(service.lists.map(function(list) { return list.name })) === JSON.stringify(harness.made.lists.map(function(list) { return list.name }))
        && service.changeMode === harness.made.changeMode, saved.text())
      harness.finish("DATA FILE WRITTEN")
    }

    function load() {
      var made = harness.made
      harness.check("the file reads", !service.settingsUnreadable)
      harness.check("All, then " + made.lists.slice(1).map(function(list) { return list.name }).join(", ") + ", in that order",
        JSON.stringify(service.lists.map(function(list) { return list.name })) === JSON.stringify(made.lists.map(function(list) { return list.name })),
        service.lists.map(function(list) { return list.label }).join(", "))
      var current = made.lists.filter(function(list) { return list.name === made.list })[0]
      harness.check("the current list is " + harness.label(current), harness.label(harness.shown()) === harness.label(current),
        harness.label(harness.shown()))
      harness.check("featured " + made.featured, service.featuredSymbol === made.featured, service.featuredSymbol)
      harness.check("on " + made.range, service.range === made.range, service.range)
      harness.check("in " + made.style, service.retro === (made.style === "retro"), service.retro ? "retro" : "smooth")
      harness.check("the change as " + made.changeMode, service.changeMode === made.changeMode, service.changeMode)
      harness.check("refreshed every " + made.refreshIntervalSec + " s", service.refreshIntervalSec === made.refreshIntervalSec, service.refreshIntervalSec)
      harness.check("the first-run hint not shown again", service.hinted === made.hinted, service.hinted)
      harness.check("sounds " + (made.sounds ? "on" : "off"), service.soundsOn === made.sounds, service.soundsOn)
      // Each list as a switch to it shows it.
      made.lists.forEach(function(list) {
        service.switchList(list.name)
        harness.check(harness.label(list), harness.label(harness.shown()) === harness.label(list), harness.label(harness.shown()))
      })
      // A later version's keys, at the top and in a list, outlive this
      // one's writes: after a downgrade, or on a machine sharing the file.
      // Found in the 1.0.0 review: every write dropped them.
      // The other machine's file is on US; once this one has read it, a
      // switch back to World writes it.
      var onFile = function() { saved.reload(); try { return JSON.parse(saved.text()) } catch (e) { return null } }
      tryVerify(function() { var f = onFile(); return !!f && f.list === service.listName }, 5000)
      var later = onFile()
      later.alerts = [{ symbol: "AAPL", above: 400 }]
      later.lists[1].pinned = true
      later.list = "US"
      saved.setText(JSON.stringify(later, null, 2) + "\n")
      tryVerify(function() { return service.listName === "US" }, 3000)
      service.switchList(made.list)
      var kept = null
      tryVerify(function() { kept = onFile(); return !!kept && kept.list === made.list }, 5000)
      harness.check("a later version's keys stay through a write: one at the top, one in a list",
        !!kept && kept.list === made.list && JSON.stringify(kept.alerts) === JSON.stringify(later.alerts) && kept.lists[1].pinned === true,
        saved.text())
      harness.finish("DATA FILE LOADED")
    }
  }
}
