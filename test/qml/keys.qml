import QtQuick
import QtTest
import Quickshell
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "plugin" as Stonks

// Every key the key sheet draws and the README's table lists acts, on the
// surface it is listed for: pressed with real Qt keys through the real popup
// (Panel.qml, its card in CardWindow.qml) and the real window (App.qml), it
// changes what that surface shows. The sheet and the table list the same
// keys, and a key either lists for one surface alone, or one Stonks no
// longer answers, changes nothing. A key a handler lost, or one renamed in
// the sheet or the README but not in the handlers, fails here. And the sheet
// says the same on both surfaces, but for the popup's Tab, and in both
// looks. HOME and curl are scratch fixtures.
ShellRoot {
  id: harness

  property int failures: 0
  // Tab's requests to the bar for its next panel.
  property int tabs: 0
  property int tabDirection: 0

  function check(label, ok, detail) {
    console.log((ok ? "PASS " : "FAIL ") + label + (!ok && detail !== undefined ? " — " + detail : ""))
    if (!ok) failures++
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

  function finish() {
    console.log("KEYS DONE")
    done.exitCode = failures ? 1 : 0
    done.start()
  }

  readonly property string readmePath: String(Qt.resolvedUrl("README.md")).replace(/^file:\/\//, "")
  readonly property string manifestPath: String(Qt.resolvedUrl("plugin/manifest.json")).replace(/^file:\/\//, "")
  function readFile(path) {
    var view = Qt.createQmlObject('import Quickshell.Io; FileView { blockLoading: true; printErrors: false }', harness)
    view.path = path
    var text = String(view.text())
    view.destroy()
    return text
  }

  // The keys a label names, in one spelling: a capital as Shift and it ("O"
  // and "`Shift+O`"), ⇧ as Shift ("⇧↑" and "`Shift+↑`"), and the sheet's
  // "Del ⌫" as the table's Delete and Backspace.
  function tokens(label) {
    var named = { "Del": "Delete", "⌫": "Backspace" }
    return label.replace(/`/g, "").split(/\s+/)
      .filter(function(t) { return t !== "" && t !== "or" })
      .map(function(t) { return named[t] || t.replace(/^⇧/, "Shift+") })
      .map(function(t) { return /^[A-Z]$/.test(t) ? "Shift+" + t : t })
  }

  // The keys the README's table lists for `surface`: a row ending "(popup)"
  // or "(window)" is that surface's alone. With `elsewhere`, the keys listed
  // for the other surface alone instead. Null with no table.
  function readmeKeys(surface, elsewhere) {
    var lines = readFile(readmePath).split("\n")
    var start = lines.indexOf("| Key | Does |")
    if (start < 0) return null
    var keys = []
    for (var i = start + 2; i < lines.length && lines[i].charAt(0) === "|"; i++) {
      var cells = lines[i].split("|")
      var only = /\((popup|window)\)$/.exec(cells[2].trim())
      var listed = elsewhere ? !!only && only[1] !== surface : !only || only[1] === surface
      if (listed) keys = keys.concat(tokens(cells[1].trim()))
    }
    return keys
  }

  // Keys Stonks answered before the 25 October key set, which now do nothing
  // in the window, and in the popup but for Omarchy's own; Shift+P never did.
  readonly property var dropped: ["j", "k", "h", "Space", "1", "2", "3", "4", "5", "6", "7", "8", "9", "+",
    "x", "Shift+X", "u", "Shift+J", "Shift+K", "w", "Shift+W", ",", ".", "y", "Shift+S", "Shift+P"]
  // What Omarchy's panel keys mean in every panel on the bar, the popup
  // among them, as one of the listed keys (Ui/PanelKeyCatcher.qml): the
  // sheet and the README never list them. l is Stonks' list menu there.
  readonly property var omarchy: ({ "j": "↓", "k": "↑", "h": "←", "Space": "⏎", "x": "Delete", "Shift+X": "Delete" })

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
  // Its keys go where the surface puts them: the popup's to the item that
  // reads letters before the shell's catcher.
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

  TestCase {
    name: "Keys"
    when: service.pluginsReady

    function quiet() {
      tryVerify(function() { return service.arriving.length === 0 && service.testFeed.firstRun.length + service.testFeed.refreshRun.length === 0 }, 8000)
    }

    // What a surface shows that a key can change.
    function shown(s) {
      var b = s.body
      return JSON.stringify([b.surfaceOpen, b.watchlist.cursorRow, service.featuredSymbol, b.scrubT, b.motion.replayRunning,
        service.range, b.adding, b.listMenuOpen, b.managingLists, b.listsSymbol, service.order, service.reversed,
        service.listName, service.symbols.join(","), service.retro, service.soundsOn, service.changeMode, b.showingHelp,
        service.testRefreshes, harness.tabs, b.cameraLit, b.rowMenu ? b.rowMenu.symbol : ""])
    }

    // Every key starts from here: the surface open on All, manual order, the
    // day, nothing open over the rows, the last of the ten rows featured, so
    // each of 1 to 9 has another to feature, and the cursor on the second.
    function base(s) {
      if (!s.body || !s.body.surfaceOpen) s.open()
      var b = s.body
      b.undoRemoval()
      b.closeViews()
      // As a surface opens: the camera out, so y lights it again.
      b.cameraLit = false
      b.endScrub()
      if (service.listName !== "") service.switchList("")
      if (service.order !== "manual") service.setOrder("manual")
      if (service.range !== "1D") service.setRange("1D")
      if (!service.soundsOn) service.persist({ sounds: true })
      var rows = b.watchlist.displayedSymbols
      service.feature(rows[rows.length - 1])
      // The second row in sight: an open brings the featured last row into
      // sight, and a cursor of your own is one in sight.
      b.watchlist.takeOver()
      b.watchlist.contentY = 0
      b.watchlist.cursorSymbol = rows[1]
      wait(50)
      s.focusKeys()
      wait(50)
    }

    // What a key needs to have something to do, past the base.
    readonly property var setups: ({
      "→": function(s) { s.body.nudgeScrub(-2) },
      "Ctrl+Z": function(s) { s.body.removeFrom(s.body.watchlist.cursorRow, true) },
      // These keys remove directly on a row held only by All. deleteAsks
      // below covers the menu for a row held by another list too.
      "Delete": function(s) { s.body.watchlist.cursorSymbol = "LONG1" },
      "Backspace": function(s) { s.body.watchlist.cursorSymbol = "LONG1" },
      "Shift+O": function(s) { service.setOrder("pct") },
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

    // A key that should do nothing here changes nothing the surface shows.
    function idle(s, token) {
      base(s)
      var unchanged = shown(s)
      if (!press(token)) return false
      wait(150)
      return shown(s) === unchanged
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
      var before = { featured: service.featuredSymbol, range: service.range,
        order: service.order, reversed: service.reversed, list: service.listName,
        symbols: service.symbols.join(","), retro: service.retro, mode: service.changeMode,
        cursor: b.watchlist.cursorRow, scrub: b.scrubT, replay: b.motion.replayRunning,
        adding: b.adding, menu: b.listMenuOpen, managing: b.managingLists, listsSymbol: b.listsSymbol,
        help: b.showingHelp, open: b.surfaceOpen, refreshes: service.testRefreshes, tabs: harness.tabs, direction: harness.tabDirection,
        sounds: service.soundsOn, camera: b.cameraLit, rowMenu: b.rowMenu ? b.rowMenu.symbol : "" }
      var refreshes = service.testRefreshes, tabs = harness.tabs
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
        var points = b.featuredDay.points
        var nextTime = b.featuredDay.axis && b.featuredDay.axis.byPrint
          ? points[points.length - 2].t
          : (b.scrubT || b.motion.scrubEnd) + (token === "→" ? 300 : -300)
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
      } else if (token === "l") { changed = ["menu"]; effect = function() { return b.listMenuOpen } }
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
      } else if (token === "r") { changed = ["refreshes"]; effect = function() { return service.testRefreshes === refreshes + 1 } }
      else if (token === "Tab" || token === "Shift+Tab") {
        changed = ["tabs", "direction"]
        effect = function() { return harness.tabs === tabs + 1 && harness.tabDirection === (token === "Tab" ? 1 : -1) }
      } else if (token === "?") { changed = ["help"]; effect = function() { return b.showingHelp } }
      else if (token === "Esc") { changed = ["open"]; effect = function() { return !b.surfaceOpen } }
      if (!effect) return false
      if (!press(pressed)) return false
      var acted = function() {
        var after = { featured: service.featuredSymbol, range: service.range,
          order: service.order, reversed: service.reversed, list: service.listName,
          symbols: service.symbols.join(","), retro: service.retro, mode: service.changeMode,
        cursor: b.watchlist.cursorRow, scrub: b.scrubT, replay: b.motion.replayRunning,
        adding: b.adding, menu: b.listMenuOpen, managing: b.managingLists, listsSymbol: b.listsSymbol,
        help: b.showingHelp, open: b.surfaceOpen, refreshes: service.testRefreshes, tabs: harness.tabs, direction: harness.tabDirection,
        sounds: service.soundsOn, camera: b.cameraLit, rowMenu: b.rowMenu ? b.rowMenu.symbol : "" }
        return effect() && Object.keys(before).every(function(k) { return changed.indexOf(k) >= 0 || before[k] === after[k] })
      }
      var ok = within(token === "Ctrl+C" ? 3000 : 1500, acted)
      if (!ok) console.log("KEY EFFECT " + s.name + " " + token + " " + shown(s))
      return ok
    }

    function within(ms, predicate) {
      for (var t = 0; t < ms && !predicate(); t += 20) wait(20)
      return predicate()
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

    // The sheet as drawn on `s`, opened with ? and closed again.
    function drawnSheet(s, order) {
      base(s)
      if (order) service.setOrder(order)
      press("?")
      wait(50)
      var sheet = harness.find(s.body, "helpSheet")
      var drawn = { keys: harness.texts(sheet, "helpKey"), all: harness.texts(sheet),
        credit: harness.texts(sheet, "helpCredit").join("") }
      press("?")
      return drawn
    }

    // A label's keys, all of a sheet's or a table's, in one order.
    function keysOf(labels) {
      var keys = []
      labels.map(harness.tokens).forEach(function(group) { keys = keys.concat(group) })
      return keys.sort()
    }

    function walk(s) {
      var sheet = drawnSheet(s)
      var sortedSheet = drawnSheet(s, "symbol")
      var readme = harness.readmeKeys(s.name)
      var listed = readme || []
      var manualKeys = keysOf(sheet.keys).join(" ")
      var sortedKeys = keysOf(sortedSheet.keys).join(" ")
      var expectedSorted = keysOf(listed.filter(function(t) { return t !== "Shift+↑" && t !== "Shift+↓" })).join(" ")
      harness.check("in the " + s.name + ", the sheet lists exactly the README's keys, the row's move only in manual order",
        readme !== null && manualKeys === keysOf(listed).join(" ") && sortedKeys === expectedSorted,
        "manual: " + manualKeys + " | sorted: " + sortedKeys + " | README: " + keysOf(listed).join(" "))
      var dead = listed.filter(function(t) { return !acts(s, t) })
      harness.check("in the " + s.name + ", every README key does its documented action (" + listed.length + " keys)",
        readme !== null && dead.length === 0, readme === null ? "no key table in the README" : "wrong: " + dead.join(" "))
      escapeOrder(s)
      if (s.name === "popup") {
        var wrong = Object.keys(harness.omarchy).filter(function(t) { return !acts(s, t, harness.omarchy[t]) })
        harness.check("in the popup, Omarchy's panel keys do what Omarchy defines: j k ↓ ↑, h ←, Space Enter, x and X Delete",
          wrong.length === 0, "wrong: " + wrong.join(" "))
      }
      var still = harness.dropped.filter(function(t) { return s.name !== "popup" || !(t in harness.omarchy) })
        .concat(harness.readmeKeys(s.name, true) || [])
      var acting = still.filter(function(t) { return !idle(s, t) })
      harness.check("in the " + s.name + ", the keys Stonks no longer answers" + (s.name === "popup" ? ", but for Omarchy's," : "")
        + " and the other surface's own change nothing (" + still.length + " keys)",
        acting.length === 0, "acting: " + acting.join(" "))
      var version = JSON.parse(harness.readFile(harness.manifestPath)).version
      harness.check("in the " + s.name + ", the sheet credits Stonks " + version + ", Yahoo, and Robinhood",
        sheet.credit.split("\n").indexOf("Stonks " + version) >= 0 && sheet.credit.indexOf("Yahoo") >= 0
          && sheet.credit.indexOf("Robinhood") >= 0, sheet.credit)
      return sheet
    }

    // With Caps Lock on, a letter acts as itself: o changes the order and
    // never reverses it, l opens the list menu, m turns sounds off or on.
    // Caps Lock sends "O" with no Shift. Found in the 1.0.0 review: Caps
    // Lock's J and K saved a reorder.
    function capsLock(s) {
      var wrong = []
      ;["o", "l", "m"].forEach(function(letter) {
        var caps = letter.toUpperCase()
        var setup = function() {
          base(s)
          if (letter === "o") service.setOrder("pct")
          wait(50)
        }
        setup()
        keyClick(letter)
        wait(100)
        var plain = shown(s)
        setup()
        keyClick(caps)
        wait(100)
        var locked = shown(s)
        if (locked !== plain) wrong.push(caps + " with Caps Lock: " + locked + " vs " + letter + ": " + plain)
      })
      base(s)
      harness.check("in the " + s.name + ", with Caps Lock on, o l m act as themselves",
        wrong.length === 0, wrong.join(" | "))
    }

    // In All, Delete on a row another list holds too asks first: the row's
    // menu, on its first line, the one line that reaches both lists, in
    // both surfaces alike; Escape closes it, removing nothing.
    function deleteAsks(s) {
      base(s)
      s.body.watchlist.cursorSymbol = "AAPL"
      wait(50)
      press("Delete")
      wait(100)
      var menu = s.body.rowMenu
      var drawn = harness.find(s.body, "rowMenu")
      var seen = [menu ? menu.symbol + ":" + drawn.cursor + ":" + menu.lines.map(function(l) { return l.label }).join("/") : "shut"]
      press("Esc")
      wait(100)
      seen.push((s.body.rowMenu === null) + ":" + (service.library.indexOf("AAPL") >= 0))
      harness.check("in the " + s.name + ", Delete on a row another list holds asks on the row's menu, and Escape closes it removing nothing",
        seen.join(" | ") === "AAPL:0:Remove from all 2 lists | true:true", seen.join(" | "))
    }

    function test_keys() {
      // Ten rows to move through, and a list that holds AAPL too.
      for (var n = 1; n <= 7; n++) service.addSymbol("LONG" + n)
      quiet()
      service.createList("Walk")
      service.setMembership("AAPL", "Walk", true)
      service.switchList("")
      wait(100)

      // The popup first: the window, shown, would take the keys.
      var popupSheet = walk(harness.popup)
      capsLock(harness.popup)
      deleteAsks(harness.popup)
      // The look changes its drawing, not the keys and words the reader gets.
      var looks = [false, true].map(function(retro) {
        service.persist({ style: retro ? "retro" : "smooth" })
        wait(50)
        return drawnSheet(harness.popup).all.join("|") === popupSheet.all.join("|")
      })
      harness.check("the key sheet says the same in smooth and retro", looks[0] && looks[1], looks.join(","))
      panel.close()
      wait(300)

      var windowSheet = walk(harness.window)
      capsLock(harness.window)
      deleteAsks(harness.window)
      // The window has no bar to step through: its sheet lacks the Tab and
      // ⇧Tab rows, each a key and what it does.
      var tab = popupSheet.all.indexOf("Tab")
      var tabRows = tab >= 0 && popupSheet.all[tab + 2] === "⇧Tab"
      var popupWords = popupSheet.all.filter(function(text, i) { return !tabRows || i < tab || i > tab + 3 })
      harness.check("the window's sheet is the popup's but for Tab and ⇧Tab", tabRows && popupWords.join("|") === windowSheet.all.join("|"),
        popupWords.join("|") + " vs " + windowSheet.all.join("|"))
      app.close()
      harness.finish()
    }
  }

  HarnessExit { id: done; interval: 100 }
}
