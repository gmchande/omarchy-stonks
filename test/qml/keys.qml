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
// changes what that surface shows. A key a handler lost, or one renamed in
// the sheet or the README but not in the handlers, fails here. And the sheet
// is the same on both surfaces, and whole in the popup in both looks. A
// replay has one speed, `p`'s, so Shift+P does nothing. HOME and curl are
// scratch fixtures.
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

  // The keys a label names: "1–9" and "`1` to `9`" each digit between, "J K"
  // and "`Shift+J`" alike as Shift+J.
  function tokens(label) {
    var range = /^`?(\d)`?\s*(?:–|to)\s*`?(\d)`?$/.exec(label)
    if (range) {
      var digits = []
      for (var d = Number(range[1]); d <= Number(range[2]); d++) digits.push(String(d))
      return digits
    }
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
      "l": function(s) { s.body.nudgeScrub(-2) },
      "u": function(s) { s.body.removeFrom(s.body.watchlist.cursorRow, true) },
      // These keys remove directly on a row held only by All. Shift+X below
      // covers the menu for a row held by another list too.
      "x": function(s) { s.body.watchlist.cursorSymbol = s.body.watchlist.displayedSymbols[2] },
      "Delete": function(s) { s.body.watchlist.cursorSymbol = s.body.watchlist.displayedSymbols[2] },
      "Backspace": function(s) { s.body.watchlist.cursorSymbol = s.body.watchlist.displayedSymbols[2] },
      "Shift+O": function(s) { service.setOrder("pct") },
      // The day is the first range.
      "[": function(s) { service.setRange("1W") }
    })

    // One key, as a person presses it; false for a key it can't name.
    function press(token) {
      var named = { "↑": Qt.Key_Up, "↓": Qt.Key_Down, "←": Qt.Key_Left, "→": Qt.Key_Right, "⏎": Qt.Key_Return,
        "Space": Qt.Key_Space, "Delete": Qt.Key_Delete, "Backspace": Qt.Key_Backspace, "Tab": Qt.Key_Tab,
        "Esc": Qt.Key_Escape }
      if (named[token] !== undefined) keyClick(named[token])
      else if (token === "Shift+Tab") keyClick(Qt.Key_Backtab, Qt.ShiftModifier)
      else if (/^Shift\+[A-Z]$/.test(token)) keyClick(token.charAt(6), Qt.ShiftModifier)
      else if (token.length === 1) keyClick(token)
      else return false
      return true
    }

    // Expected effects are independent of the handlers and of README prose.
    // A documented key without a case fails; changing some unrelated state
    // cannot satisfy the expected target or excuse another settings change.
    function acts(s, token) {
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
      var target = selected
      if (/^[1-9]$/.test(token)) target = rows[Number(token) - 1]
      if (/^[1-9]$/.test(token) || token === "⏎" || token === "Space") {
        changed = ["featured", "cursor"]
        effect = function() { return service.featuredSymbol === target && b.watchlist.cursorRow === target }
      } else if (["↑", "k", "↓", "j"].indexOf(token) >= 0) {
        changed = ["cursor"]
        var cursor = rows[rows.indexOf(selected) + (["↑", "k"].indexOf(token) >= 0 ? -1 : 1)]
        effect = function() { return b.watchlist.cursorRow === cursor }
      } else if (["←", "h", "→", "l"].indexOf(token) >= 0) {
        changed = ["scrub"]
        var points = b.featuredDay.points
        var right = token === "→" || token === "l"
        var nextTime = b.featuredDay.axis && b.featuredDay.axis.byPrint
          ? points[points.length - 2].t
          : (b.scrubT || b.motion.scrubEnd) + (right ? 300 : -300)
        effect = function() { return b.scrubT === nextTime }
      } else if (token === "[" || token === "]") {
        changed = ["range"]
        effect = function() { return service.range === (token === "[" ? "1D" : "1W") }
      } else if (token === "p") { changed = ["scrub", "replay"]; effect = function() { return b.motion.replayRunning } }
      else if (token === "a" || token === "+") { changed = ["adding"]; effect = function() { return b.adding && b.search.active } }
      else if (["x", "Delete", "Backspace"].indexOf(token) >= 0) {
        changed = ["symbols", "cursor"]
        effect = function() { return service.symbols.join(",") === rows.filter(function(r) { return r !== selected }).join(",") }
      } else if (token === "u") {
        changed = ["symbols", "cursor"]
        var removed = b.offered.symbol
        effect = function() { return service.symbols.indexOf(removed) >= 0 && service.symbols.length === rows.length + 1 }
      } else if (token === "Shift+J" || token === "Shift+K") {
        changed = ["symbols"]
        var reordered = rows.slice(), at = rows.indexOf(selected), to = at + (token === "Shift+J" ? 1 : -1)
        reordered.splice(at, 1); reordered.splice(to, 0, selected)
        effect = function() { return service.symbols.join(",") === reordered.join(",") && b.watchlist.cursorRow === selected }
      } else if (token === "o") {
        changed = ["order", "cursor"]
        effect = function() { return service.order === "symbol" }
      } else if (token === "Shift+O") {
        changed = ["reversed", "cursor"]
        effect = function() { return service.reversed === !before.reversed }
      } else if (token === "w") { changed = ["menu"]; effect = function() { return b.listMenuOpen } }
      else if (token === "Shift+W") { changed = ["managing"]; effect = function() { return b.managingLists } }
      else if (token === "m") { changed = ["listsSymbol"]; effect = function() { return b.listsSymbol === selected } }
      else if (token === "," || token === ".") {
        changed = ["list", "symbols", "featured", "order", "reversed", "cursor"]
        effect = function() { return service.listName === (token === "," ? "Back" : "Walk") && service.symbols.join(",") === (token === "," ? "MSFT" : "AAPL") }
      } else if (token === "c") {
        changed = ["mode"]
        var mode = {pct:"abs", abs:"open", open:"pct"}[before.mode]
        effect = function() { return service.changeMode === mode }
      } else if (token === "s") {
        changed = ["retro"]
        effect = function() { return service.retro === !before.retro }
      } else if (token === "Shift+S") {
        changed = ["sounds"]
        effect = function() { return service.soundsOn === !before.sounds }
      } else if (token === "y") {
        changed = ["camera"]
        effect = function() { return b.cameraLit }
      } else if (token === "Shift+X") {
        changed = ["rowMenu"]
        effect = function() { return !!b.rowMenu && b.rowMenu.symbol === selected
          && b.rowMenu.lines.length === 1 && b.rowMenu.lines[0].label === "Remove from all 2 lists" }
      } else if (token === "r") { changed = ["refreshes"]; effect = function() { return service.testRefreshes === refreshes + 1 } }
      else if (token === "Tab" || token === "Shift+Tab") {
        changed = ["tabs", "direction"]
        effect = function() { return harness.tabs === tabs + 1 && harness.tabDirection === (token === "Tab" ? 1 : -1) }
      } else if (token === "?") { changed = ["help"]; effect = function() { return b.showingHelp } }
      else if (token === "Esc") { changed = ["open"]; effect = function() { return !b.surfaceOpen } }
      if (!effect) {
        if (token !== "Shift+P") return false
        var unchanged = shown(s)
        press(token)
        return shown(s) !== unchanged
      }
      if (!press(token)) return false
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
      var ok = within(token === "y" ? 3000 : 1500, acted)
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
    function drawnSheet(s) {
      base(s)
      press("?")
      wait(50)
      var sheet = harness.find(s.body, "helpSheet")
      var drawn = { keys: harness.texts(sheet, "helpKey"), all: harness.texts(sheet), whole: !sheet.interactive,
        credit: harness.texts(sheet, "helpCredit").join("") }
      press("?")
      return drawn
    }

    function walk(s) {
      var sheet = drawnSheet(s)
      var readme = harness.readmeKeys(s.name)
      var sheetKeys = []
      sheet.keys.map(harness.tokens).forEach(function(group) { sheetKeys = sheetKeys.concat(group) })
      var absent = sheetKeys.filter(function(t) { return !readme || readme.indexOf(t) < 0 })
      harness.check("in the " + s.name + ", every everyday sheet key is documented in the complete README",
        !!readme && absent.length === 0, absent.join(" "))
      var listed = readme || []
      var dead = listed.filter(function(t) { return !acts(s, t) })
      harness.check("in the " + s.name + ", every README key does its documented action (" + listed.length + " keys)",
        readme !== null && dead.length === 0, readme === null ? "no key table in the README" : "wrong: " + dead.join(" "))
      escapeOrder(s)
      harness.check("in the " + s.name + ", Shift+P changes nothing", !acts(s, "Shift+P"))
      var version = JSON.parse(harness.readFile(harness.manifestPath)).version
      harness.check("in the " + s.name + ", the sheet's foot credits Stonks " + version + ", Yahoo, and Robinhood",
        sheet.credit.indexOf("Stonks " + version + " ") >= 0 && sheet.credit.indexOf("Yahoo") >= 0
          && sheet.credit.indexOf("Robinhood") >= 0, sheet.credit)
      return sheet
    }

    // With Caps Lock on, a letter acts as itself: j does what j does (in
    // the popup it moves the selection) and never moves a row, o changes
    // the order and never reverses it, w opens the list menu and never
    // Manage lists, x removes and never opens the row's menu, and in Manage
    // lists J moves no list. Caps Lock sends "J" with no Shift. Found in the
    // 1.0.0 review: Caps Lock's J and K saved a reorder.
    function capsLock(s) {
      var wrong = []
      ;["j", "k", "o", "w", "x"].forEach(function(letter) {
        var caps = letter.toUpperCase()
        // x on a row Walk lacks, which it removes at once.
        var setup = function() {
          base(s)
          if (letter === "o") service.setOrder("pct")
          if (letter === "x") s.body.watchlist.cursorSymbol = s.body.watchlist.displayedSymbols[2]
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
      service.createList("Caps")
      service.switchList("Walk")
      s.body.openManageLists()
      wait(100)
      var lists = function() { return service.lists.map(function(l) { return l.name }).join(",") }
      var listsBefore = lists()
      keyClick("J")
      wait(100)
      if (lists() !== listsBefore) wrong.push("J with Caps Lock in Manage lists moved the list: " + listsBefore + " -> " + lists())
      s.body.closeListViews()
      service.deleteList("Caps")
      wait(50)
      harness.check("in the " + s.name + ", with Caps Lock on, j k o w x act as themselves, and J in Manage lists moves no list",
        wrong.length === 0, wrong.join(" | "))
    }

    // Shift+X opens the selected row's menu, on its first line, in both
    // surfaces alike, and Escape closes it, removing nothing. In All, for
    // AAPL, which Walk holds too, the menu is the one line that reaches
    // both lists; in Walk, that list by its name, then both.
    function shiftX(s) {
      var seen = []
      ;["", "Walk"].forEach(function(list) {
        base(s)
        if (list !== "") service.switchList(list)
        s.body.watchlist.cursorSymbol = "AAPL"
        wait(50)
        press("Shift+X")
        wait(100)
        var menu = s.body.rowMenu
        var drawn = harness.find(s.body, "rowMenu")
        seen.push(menu ? menu.symbol + ":" + drawn.cursor + ":" + menu.lines.map(function(l) { return l.label }).join("/") : "shut")
        press("Esc")
        wait(100)
        seen.push((s.body.rowMenu === null) + ":" + (service.library.indexOf("AAPL") >= 0))
      })
      harness.check("in the " + s.name + ", Shift+X opens the selected row's menu on its first line, and Escape closes it removing nothing",
        seen.join(" | ") === "AAPL:0:Remove from all 2 lists | true:true | AAPL:0:Remove from Walk/Remove from all 2 lists | true:true",
        seen.join(" | "))
    }

    function test_keys() {
      // Ten rows, so 9 has a row, and a second list for , and .
      for (var n = 1; n <= 7; n++) service.addSymbol("LONG" + n)
      quiet()
      service.createList("Walk")
      service.setMembership("AAPL", "Walk", true)
      service.createList("Back")
      service.setMembership("MSFT", "Back", true)
      service.switchList("")
      wait(100)

      // The popup first: the window, shown, would take the keys.
      var popupSheet = walk(harness.popup)
      capsLock(harness.popup)
      shiftX(harness.popup)
      // Whole in both looks: the popup's height takes the sheet's, under its cap.
      var looks = [false, true].map(function(retro) {
        service.persist({ style: retro ? "retro" : "smooth" })
        wait(50)
        return drawnSheet(harness.popup).whole
      })
      harness.check("the key sheet fits the popup without scrolling, smooth and retro", looks[0] && looks[1], looks.join(","))
      panel.close()
      wait(300)

      var windowSheet = walk(harness.window)
      capsLock(harness.window)
      shiftX(harness.window)
      harness.check("the window's sheet is the popup's", popupSheet.all.join("|") === windowSheet.all.join("|"),
        popupSheet.all.join("|") + " vs " + windowSheet.all.join("|"))
      app.close()
      harness.finish()
    }
  }

  HarnessExit { id: done; interval: 100 }
}
