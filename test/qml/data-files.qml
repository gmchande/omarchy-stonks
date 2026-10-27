import QtQuick
import Quickshell
import Quickshell.Io
import "Settings.js" as Settings

// Makes a release's data file through the real Service (data-files.sh
// write): it starts with no file and makes all of it through its own
// functions, as the surfaces call them; the script keeps the file it saved.
// model.test.js reads every file back. Every quote and history ask fails:
// no saved answers.
Harness {
  id: harness
  marker: "DATA FILE WRITTEN"

  // The demo watchlist's symbols: All in an order made by hand, a list in
  // manual order arranged by hand, one sorted, one sorted the other way, and
  // one empty; the current list a named one, a featured symbol off the top,
  // and every view setting off its default. The refresh interval is set only
  // by hand in the file, which every save keeps. model.test.js expects the
  // same.
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
    sounds: true,
    updateCheck: false
  })

  Service { id: service }

  Steps {
    name: "DataFiles"
    when: service.pluginsReady

    function test_make() {
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
      service.persist({ sounds: harness.made.sounds, updateCheck: harness.made.updateCheck })
      var text = ""
      var saved = within(5000, function() {
        text = harness.readFile(service.dataPath)
        try { return Settings.settingsEqual(JSON.parse(text), service.dataSettings) } catch (e) { return false }
      })
      harness.check("the Service saved what was made", saved
        && JSON.stringify(service.lists.map(function(list) { return list.name })) === JSON.stringify(harness.made.lists.map(function(list) { return list.name }))
        && service.changeMode === harness.made.changeMode, text)
      harness.finish()
    }
  }
}
