import QtQuick
import QtTest
import Quickshell
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "plugin" as Stonks

// Every key the README's table lists acts, on the surface it is listed for:
// pressed with real Qt keys through the real popup (Panel.qml, its card in
// CardWindow.qml) and the real window (App.qml), it changes what it should
// and nothing else. A key a handler lost, or one renamed in the README but
// not in the handlers, fails here. HOME and curl are scratch fixtures.
Harness {
  id: harness
  marker: "KEYS DONE"

  // Tab's requests to the bar for its next panel.
  property int tabs: 0
  property int tabDirection: 0

  // The texts an item draws, in order, those with `name` only when given.
  function texts(item, name) {
    var out = []
    var walk = function(node) {
      if (!node) return
      if (node.visible === false) return
      if (node.text !== undefined && (!name || node.objectName === name)) out.push(String(node.text))
      for (var i = 0; i < node.children.length; i++) walk(node.children[i])
    }
    walk(item)
    return out
  }

  readonly property string readmePath: String(Qt.resolvedUrl("README.md")).replace(/^file:\/\//, "")
  readonly property string manifestPath: String(Qt.resolvedUrl("plugin/manifest.json")).replace(/^file:\/\//, "")

  // The keys a label names, in one spelling: a capital as Shift and it, and
  // "Delete or Backspace" as the two.
  function tokens(label) {
    return label.replace(/`/g, "").split(/\s+/)
      .filter(function(t) { return t !== "" && t !== "or" })
      .map(function(t) { return /^[A-Z]$/.test(t) ? "Shift+" + t : t })
  }

  // The keys the README's table lists for `surface`: a row ending "(popup)"
  // or "(window)" is that surface's alone. Null with no table.
  function readmeKeys(surface) {
    var lines = readFile(readmePath).split("\n")
    var start = lines.indexOf("| Key | Does |")
    if (start < 0) return null
    var keys = []
    for (var i = start + 2; i < lines.length && lines[i].charAt(0) === "|"; i++) {
      var cells = lines[i].split("|")
      var only = /\((popup|window)\)$/.exec(cells[2].trim())
      if (!only || only[1] === surface) keys = keys.concat(tokens(cells[1].trim()))
    }
    return keys
  }

  // What Omarchy's panel keys mean in every panel on the bar, the popup
  // among them, as one of the listed keys (Ui/PanelKeyCatcher.qml).
  readonly property var omarchy: ({ "j": "↓", "k": "↑", "h": "←", "l": "→", "Space": "⏎", "x": "Delete", "Shift+X": "Delete" })

  Stonks.Service { id: service }
  Stonks.Updates { id: updates }
  // The camera hands its shots to the stand-ins on PATH (bin/).
  Stonks.Camera { id: camera }
  QtObject {
    id: shellApi
    function serviceFor(id) { return { service: service, updates: updates, camera: camera } }
  }
  PluginBarApi {
    id: api
    pluginId: "grvc.stonks"
    moduleName: "grvc.stonks"
    shell: shellApi
    foreground: Commons.Color.foreground
    fontFamily: Style.font.family
    _switchPanelFrom: function(owner, direction) { harness.tabs++; harness.tabDirection = direction; return true }
  }
  Stonks.Panel { id: panel; bar: api; settings: ({}) }
  Stonks.App { id: app; service: service; updates: updates; camera: camera }

  // Each surface's body is built as it first opens: read it as it is now.
  // The popup's keys go to the item that reads letters before the shell's
  // catcher.
  readonly property var popup: ({
    name: "popup",
    get body() { return panel.testBody },
    focusKeys: function() { panel.refocusKeys() },
    open: function() { panel.open() }
  })
  readonly property var window: ({
    name: "window",
    get body() { return app.testBody },
    focusKeys: function() { app.testKeyCatcher.forceActiveFocus() },
    open: function() { app.open("{}") }
  })

  Steps {
    name: "Keys"
    when: service.pluginsReady

    function quiet() {
      tryVerify(function() { return service.arriving.length === 0 && service.testFeed.firstRun.length + service.testFeed.refreshRun.length === 0 }, 8000)
    }

    // Everything a key can change.
    function state(b) {
      return { featured: service.featuredSymbol, range: service.range,
        order: service.order, reversed: service.reversed, list: service.listName,
        symbols: service.symbols.join(","), retro: service.retro, mode: service.changeMode,
        cursor: b.watchlist.cursorRow, scrub: b.scrubT, replay: b.motion.replayRunning,
        adding: b.adding, menu: b.listMenuOpen, managing: b.managingLists, listsSymbol: b.listsSymbol,
        help: b.showingHelp, open: b.surfaceOpen, refreshes: service.testRefreshes, tabs: harness.tabs, direction: harness.tabDirection,
        sounds: service.soundsOn, camera: b.cameraLit, rowMenu: b.rowMenu ? b.rowMenu.symbol : "", updates: updates.testUpdates }
    }

    // Every key starts from here: the surface open on All, manual order, the
    // day, nothing open over the rows, the last of the ten rows featured,
    // and the cursor on the second.
    function base(s) {
      if (!s.body || !s.body.surfaceOpen) s.open()
      var b = s.body
      b.undoRemoval()
      b.closeViews()
      // As a surface opens: the camera out, so Ctrl+C lights it again.
      b.cameraLit = false
      b.endScrub()
      if (service.listName !== "") service.switchList("")
      if (service.order !== "manual") service.setOrder("manual")
      if (service.range !== "1D") service.setRange("1D")
      if (!service.soundsOn) service.persist({ sounds: true })
      // No newer Stonks out, so Shift+U has nothing to run.
      updates.mainVersion = ""
      var rows = b.watchlist.displayedSymbols
      service.feature(rows[rows.length - 1])
      // The second row in sight: an open brings the featured last row into
      // sight, and a cursor of your own is one in sight.
      b.watchlist.takeOver()
      b.watchlist.contentY = 0
      b.watchlist.cursorSymbol = rows[1]
      tryVerify(function() { return b.watchlist.cursorRow === rows[1] }, 1000)
      s.focusKeys()
      // The popup refocuses on the next turn of the event loop.
      wait(0)
    }

    // What a key needs to have something to do, past the base.
    readonly property var setups: ({
      "→": function(s) { s.body.nudgeScrub(-2) },
      "Ctrl+Z": function(s) { s.body.removeFrom(s.body.watchlist.cursorRow, true) },
      // A row held only by All, which these keys remove directly.
      "Delete": function(s) { s.body.watchlist.cursorSymbol = "LONG1" },
      "Backspace": function(s) { s.body.watchlist.cursorSymbol = "LONG1" },
      "Shift+O": function(s) { service.setOrder("pct") },
      // A newer Stonks on main, which the footer offers.
      "Shift+U": function(s) { updates.mainVersion = "99.0.0" },
      // The day is the first range.
      "[": function(s) { service.setRange("1W") }
    })

    // One key, as a person presses it; false for a key it can't name. A
    // shifted letter carries its capital as its text, as a keyboard sends it.
    function press(token) {
      var named = { "↑": Qt.Key_Up, "↓": Qt.Key_Down, "←": Qt.Key_Left, "→": Qt.Key_Right, "⏎": Qt.Key_Return,
        "Space": Qt.Key_Space, "Delete": Qt.Key_Delete, "Backspace": Qt.Key_Backspace, "Tab": Qt.Key_Tab,
        "Esc": Qt.Key_Escape }
      var held = /^(Shift|Ctrl)\+(.+)$/.exec(token)
      var modifier = held ? (held[1] === "Shift" ? Qt.ShiftModifier : Qt.ControlModifier) : Qt.NoModifier
      var key = held ? held[2] : token
      if (token === "Shift+Tab") keyClick(Qt.Key_Backtab, Qt.ShiftModifier)
      else if (named[key] !== undefined) keyClick(named[key], modifier)
      else if (/^[A-Z]$/.test(key) && held) keyClick(held[1] === "Shift" ? key : Qt["Key_" + key], modifier)
      else if (key.length === 1 && !held) keyClick(key)
      else return false
      return true
    }

    // Expected effects are independent of the handlers and of README prose.
    // A documented key without a case fails; changing some unrelated state
    // cannot satisfy the expected target or excuse another settings change.
    // `pressed` acts as the listed key `meaning`, itself when not given.
    function acts(s, pressed, meaning) {
      var token = meaning || pressed
      base(s)
      if (setups[token]) setups[token](s)
      var b = s.body
      var rows = b.watchlist.displayedSymbols.slice()
      var selected = b.watchlist.cursorRow
      var before = state(b)
      var changed = [], effect = null
      if (token === "⏎") {
        changed = ["featured", "cursor"]
        effect = function() { return service.featuredSymbol === selected && b.watchlist.cursorRow === selected }
      } else if (token === "↑" || token === "↓") {
        changed = ["cursor"]
        var cursor = rows[rows.indexOf(selected) + (token === "↑" ? -1 : 1)]
        effect = function() { return b.watchlist.cursorRow === cursor }
      } else if (token === "←" || token === "→") {
        changed = ["scrub"]
        var nextTime = (b.scrubT || b.motion.scrubEnd) + (token === "→" ? 300 : -300)
        effect = function() { return b.scrubT === nextTime }
      } else if (token === "[" || token === "]") {
        changed = ["range"]
        effect = function() { return service.range === (token === "[" ? "1D" : "1W") }
      } else if (token === "p") { changed = ["scrub", "replay"]; effect = function() { return b.motion.replayRunning } }
      else if (token === "a") { changed = ["adding"]; effect = function() { return b.adding && b.search.active } }
      else if (token === "Delete" || token === "Backspace") {
        changed = ["symbols", "cursor"]
        effect = function() { return service.symbols.join(",") === rows.filter(function(r) { return r !== selected }).join(",") }
      } else if (token === "Ctrl+Z") {
        changed = ["symbols", "cursor"]
        var removed = b.removal.symbol
        effect = function() { return service.symbols.indexOf(removed) >= 0 && service.symbols.length === rows.length + 1 }
      } else if (token === "Shift+↑" || token === "Shift+↓") {
        changed = ["symbols"]
        var reordered = rows.slice(), at = rows.indexOf(selected), to = at + (token === "Shift+↓" ? 1 : -1)
        reordered.splice(at, 1); reordered.splice(to, 0, selected)
        effect = function() { return service.symbols.join(",") === reordered.join(",") && b.watchlist.cursorRow === selected }
      } else if (token === "o") {
        changed = ["order", "cursor"]
        effect = function() { return service.order === "symbol" }
      } else if (token === "Shift+O") {
        changed = ["reversed", "cursor"]
        effect = function() { return service.reversed === !before.reversed }
      } else if (token === "w") { changed = ["menu"]; effect = function() { return b.listMenuOpen } }
      else if (token === "Ctrl+⏎") { changed = ["listsSymbol"]; effect = function() { return b.listsSymbol === selected } }
      else if (token === "Shift+U") { changed = ["updates"]; effect = function() { return updates.testUpdates === before.updates + 1 } }
      else if (token === "c") {
        changed = ["mode"]
        var mode = {pct:"abs", abs:"open", open:"pct"}[before.mode]
        effect = function() { return service.changeMode === mode }
      } else if (token === "s") {
        changed = ["retro"]
        effect = function() { return service.retro === !before.retro }
      } else if (token === "m") {
        changed = ["sounds"]
        effect = function() { return service.soundsOn === !before.sounds }
      } else if (token === "Ctrl+C") {
        changed = ["camera"]
        effect = function() { return b.cameraLit }
      } else if (token === "r") { changed = ["refreshes"]; effect = function() { return service.testRefreshes === before.refreshes + 1 } }
      else if (token === "Tab" || token === "Shift+Tab") {
        changed = ["tabs", "direction"]
        effect = function() { return harness.tabs === before.tabs + 1 && harness.tabDirection === (token === "Tab" ? 1 : -1) }
      } else if (token === "?") { changed = ["help"]; effect = function() { return b.showingHelp } }
      else if (token === "Esc") { changed = ["open"]; effect = function() { return !b.surfaceOpen } }
      if (!effect || !press(pressed)) return false
      return within(token === "Ctrl+C" ? 3000 : 1500, function() {
        var after = state(b)
        return effect() && Object.keys(before).every(function(k) { return changed.indexOf(k) >= 0 || before[k] === after[k] })
      })
    }

    function escapeOrder(s) {
      base(s)
      s.body.nudgeScrub(-2)
      var scrub = s.body.scrubT
      press("?")
      press("Esc")
      harness.check(s.name + " Esc closes the sheet before the scrub", !s.body.showingHelp && s.body.scrubT === scrub && s.body.surfaceOpen)
      press("Esc")
      harness.check(s.name + " Esc ends the scrub before the surface", !s.body.scrubT && s.body.surfaceOpen)
      press("Esc")
      harness.check(s.name + " Esc then closes the surface", !s.body.surfaceOpen)
    }

    function walk(s) {
      var listed = harness.readmeKeys(s.name)
      var dead = (listed || []).filter(function(t) { return !acts(s, t) })
      harness.check("in the " + s.name + ", every README key does its documented action (" + (listed || []).length + " keys)",
        listed !== null && dead.length === 0, listed === null ? "no key table in the README" : "wrong: " + dead.join(" "))
      escapeOrder(s)
    }

    function test_keys() {
      // Ten rows to move through.
      for (var n = 1; n <= 7; n++) service.addSymbol("LONG" + n)
      quiet()

      // The popup first: the window, shown, would take the keys.
      walk(harness.popup)
      var wrong = Object.keys(harness.omarchy).filter(function(t) { return !acts(harness.popup, t, harness.omarchy[t]) })
      harness.check("in the popup, Omarchy's panel keys do what Omarchy defines: j k ↓ ↑, h ← and l →, Space Enter, x and X Delete",
        wrong.length === 0, "wrong: " + wrong.join(" "))
      // Both surfaces draw one StonksBody's sheet: the popup's stands for both.
      base(harness.popup)
      press("?")
      var credit = harness.texts(harness.find(harness.popup.body, "helpSheet"), "helpCredit").join("")
      press("?")
      var version = JSON.parse(harness.readFile(harness.manifestPath)).version
      harness.check("in the popup, the sheet credits Stonks " + version + ", Yahoo, and Robinhood",
        credit.split("\n").indexOf("Stonks " + version) >= 0 && credit.indexOf("Yahoo") >= 0
          && credit.indexOf("Robinhood") >= 0, credit)
      panel.close()
      tryVerify(function() { return !harness.popup.body.surfaceOpen }, 1000)

      walk(harness.window)
      // The window has no bar to step through; a Tab there must leave the
      // keys with the window.
      base(harness.window)
      press("Tab")
      press("o")
      harness.check("in the window, after Tab a key still does its action",
        within(1500, function() { return service.order === "symbol" }), service.order)
      app.close()
      harness.finish()
    }
  }
}
