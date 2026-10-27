import QtQuick
import Quickshell
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "plugin" as Stonks

// Named watchlists through the real Service and App with real keys. The data
// file starts as the version-1 fixture (AAPL, MSFT, NVDA; the fake curl
// answers all three).
Harness {
  id: harness
  marker: "LISTS DONE"

  readonly property string dataPath: Quickshell.env("HOME") + "/.config/omarchy/grvc.stonks.json"

  function same(got, want) { return (got || []).join(",") === want.join(",") }

  // The data file as Stonks last wrote it; {} while it doesn't parse.
  function dataFile() {
    try { return JSON.parse(readFile(dataPath)) } catch (e) { return {} }
  }

  function showsPrice(item, text) {
    if (!item || !item.visible) return false
    if (item.text !== undefined && String(item.text) === text) return true
    for (var i = 0; i < item.children.length; i++) if (showsPrice(item.children[i], text)) return true
    return item.contentItem ? showsPrice(item.contentItem, text) : false
  }

  Stonks.Service { id: service }
  Stonks.App { id: app; service: service }
  QtObject {
    id: shellApi
    function serviceFor(id) { return { service: service } }
  }
  PluginBarApi {
    id: api
    pluginId: "grvc.stonks"
    moduleName: "grvc.stonks"
    shell: shellApi
    foreground: Commons.Color.foreground
    fontFamily: Style.font.family
  }
  Stonks.Panel { id: panel; bar: api; settings: ({}) }
  // The screenshot's hand-off while one step watches Ctrl+C: it counts the
  // shots handed to it and takes none.
  QtObject {
    id: stubCamera
    property bool busy: false
    property int shots: 0
    function shoot(card, name, taken, done) { shots++; return false }
  }

  Steps {
    name: "NamedWatchlists"
    when: service.pluginsReady

    function typeText(text) {
      for (var i = 0; i < text.length; i++) keyClick(text.charAt(i))
    }

    function center(item) { return item.mapToItem(app.testBody, item.width / 2, item.height / 2) }

    function firstWhole(rows) {
      for (var i = 0; i < rows.displayedSymbols.length; i++)
        if (rows.wholeInSight(i, rows.contentY)) return i
      return -1
    }

    // A view, or its field, takes the keys a turn after it opens.
    function focused(item) { return within(1000, function() { return !!item && item.activeFocus }) }

    // A closed view hands the keys back to the window a turn later.
    function keysBack() { return focused(app.testKeyCatcher) }

    // An open hands the keys to the window, or to a view that comes back.
    function openWindow() {
      app.open("{}")
      return within(2000, function() {
        return (app.testBody.ownsKeys || app.testKeyCatcher.activeFocus) && !app.testBody.watchlist.settling
      })
    }

    // The rows take a click within the double-click interval of their last,
    // at its place, as that click's second.
    function clickApart() {
      var interval = Application.styleHints.mouseDoubleClickInterval
      within(interval + 100, function() { return Date.now() - app.testBody.watchlist.lastClickTime > interval })
    }

    // The rows named `name` once their column has placed them: a
    // Repeater's new rows sit at its top until the next frame.
    function placed(name) {
      var items = []
      within(1000, function() {
        items = harness.findAll(app.testBody, name)
        for (var i = 1; i < items.length; i++) if (items[i].y < items[i - 1].y + items[i - 1].height - 0.5) return false
        return true
      })
      return items
    }

    function fileWhen(ok) {
      var file = {}
      within(3000, function() { file = harness.dataFile(); return ok(file) })
      return file
    }

    // By keys alone: search takes the keys, the symbol, Enter.
    function pickSymbol(body, symbol) {
      var field = harness.find(body.search, "searchField")
      focused(field)
      keyClick(Qt.Key_A, Qt.ControlModifier)
      typeText(symbol)
      tryVerify(function() { return body.search.resultsQuery === symbol && body.search.results.length === 1 }, 3000)
      keyClick(Qt.Key_Return)
      tryVerify(function() { return !body.adding }, 2000)
    }

    // A list switch as a hand makes it: l opens the list menu on the
    // current list, the arrows walk to `name` ("" for All), Enter takes it.
    function switchByKeys(name) {
      var menu = harness.find(app.testBody, "listMenu")
      keyClick(Qt.Key_L)
      focused(menu)
      var want = menu.choices.map(function(c) { return c.name }).indexOf(name)
      for (var i = 0; i < 40 && menu.cursor !== want; i++) keyClick(menu.cursor < want ? Qt.Key_Down : Qt.Key_Up)
      keyClick(Qt.Key_Return)
      keysBack()
    }

    // Manage lists as a hand opens it: l, the arrows to "Manage lists…",
    // Enter.
    function manageByKeys() {
      var menu = harness.find(app.testBody, "listMenu")
      keyClick(Qt.Key_L)
      focused(menu)
      for (var i = 0; i < 40 && menu.cursor !== menu.manageIndex; i++) keyClick(Qt.Key_Down)
      keyClick(Qt.Key_Return)
      focused(harness.find(app.testBody, "manageLists"))
    }

    function test_list_flows() {
      tryVerify(function() {
        return service.quotes.AAPL && service.quotes.MSFT && service.quotes.NVDA
          && service.testFeed.firstRun.length + service.testFeed.refreshRun.length === 0
      }, 10000)

      openWindow()
      var body = app.testBody
      var wl = body.watchlist
      var keys = app.testKeyCatcher
      var menu = harness.find(body, "listMenu")
      var manage = harness.find(body, "manageLists")
      var checklist = harness.find(body, "symbolLists")
      var searchField = harness.find(body.search, "searchField")
      var nameField = harness.find(menu, "listNameField")
      var renameField = harness.find(manage, "renameField")

      // l, ↓ to New list…, Enter, the name, Enter.
      keyClick(Qt.Key_L)
      focused(menu)
      keyClick(Qt.Key_Down)
      keyClick(Qt.Key_Return)
      var naming = menu.naming
      focused(nameField)
      typeText("Growth")
      keyClick(Qt.Key_Return)
      harness.check("a new list is made, current, empty, and search opens to fill it",
        naming && service.listName === "Growth" && service.symbols.length === 0
          && !body.listMenuOpen && body.adding
          && body.search.placeholder.indexOf("Growth") >= 0,
        naming + "|" + service.listName + "|" + service.symbols + "|" + body.listMenuOpen + "|" + body.adding + "|" + body.search.placeholder)

      // Two symbols All holds, each by keys alone.
      var nvdaCalls = harness.calls("NVDA")
      pickSymbol(body, "NVDA")
      tryVerify(function() { return service.featuredSymbol === "NVDA" }, 2000)
      keysBack()
      keyClick(Qt.Key_A)
      tryVerify(function() { return body.adding }, 2000)
      pickSymbol(body, "AAPL")
      tryVerify(function() { return service.featuredSymbol === "AAPL" }, 2000)
      var written = fileWhen(function(f) { return f.featured === "AAPL" })
      harness.check("adding on a list puts the symbol in it without a second copy in All, and writes it featured",
        harness.same(service.symbols, ["NVDA", "AAPL"]) && service.lists[1].count === 2 && service.lists[0].count === 3
          && harness.same(written.symbols, ["AAPL", "MSFT", "NVDA"]) && written.featured === "AAPL",
        service.symbols + "|" + service.lists[1].count + "|" + JSON.stringify(written))
      harness.check("a symbol already in All is not fetched again for a list",
        harness.calls("NVDA") === nvdaCalls)

      // l, ↑ to All, Enter; then l, ↓ to Growth, Enter.
      keysBack()
      keyClick(Qt.Key_L)
      focused(menu)
      keyClick(Qt.Key_Up)
      keyClick(Qt.Key_Return)
      keysBack()
      var toAll = [service.listName, body.listMenuOpen, service.symbols].join("|")
      keyClick(Qt.Key_L)
      focused(menu)
      keyClick(Qt.Key_Down)
      keyClick(Qt.Key_Return)
      keysBack()
      harness.check("l, ↑ to All, and Enter switch back to All",
        toAll === "|false|AAPL,MSFT,NVDA" && service.listName === "Growth" && !body.listMenuOpen
          && harness.same(service.symbols, ["NVDA", "AAPL"]),
        toAll + " then " + service.listName + "|" + service.symbols)

      // A quote arriving off the current list is current when its row
      // returns.
      tryVerify(function() { return service.testFeed.firstRun.length + service.testFeed.refreshRun.length === 0 }, 5000)
      var beforeQuotes = service.testFeed.quotes
      service.switchList("Growth")
      var changed = Object.assign({}, beforeQuotes)
      changed.MSFT = Object.assign({}, beforeQuotes.MSFT, { price: 180.25 })
      service.testFeed.quotes = changed
      service.switchList("")
      var currentRow = function() {
        var row = wl.rowItem("MSFT")
        return row && row.visible && harness.find(row, "rowContent") && harness.showsPrice(row, "180.25")
      }
      within(3000, currentRow)
      harness.check("returning to a list shows its latest quote", currentRow())
      service.testFeed.quotes = beforeQuotes
      service.switchList("Growth")

      // A switch with the pointer resting on the rows still lays out the new
      // list, which a resort under the pointer would hold back. Each wait is
      // on the step's own condition, up to 3 s, and says how long it took.
      var row = wl.rowItem("NVDA")
      mouseMove(row, row.width / 2, row.height / 2)
      var restAsked = Date.now()
      within(3000, function() { return wl.sortHeld })
      var restMs = Date.now() - restAsked
      switchByKeys("")
      var switched = function() {
        return wl.sortHeld && harness.same(wl.displayedSymbols, service.shown) && wl.contentY === 0
      }
      var switchAsked = Date.now()
      within(3000, switched)
      var switchMs = Date.now() - switchAsked
      harness.check("a list switch under the pointer shows the new list's rows", switched(),
        wl.sortHeld + "|" + wl.displayedSymbols + "|" + service.shown + "|" + wl.contentY
          + " | held " + restMs + " ms after the move, laid out " + switchMs + " ms after the switch")
      mouseMove(body, body.width / 2, 10)
      switchByKeys("Growth")

      // With no key held, the arrow reverses a sorted order, kept for the
      // list, and the word steps; on manual, ↕ steps as the word does.
      var label = harness.find(body, "orderLabel")
      var clickArrow = function() { mouseClick(label, 3, label.height / 2) }
      var clickWord = function() { mouseClick(label, label.width - 3, label.height / 2) }
      clickArrow()
      var fromManual = [service.order, service.reversed, label.text]
      var sortedRows = wl.displayedSymbols.slice()
      clickArrow()
      var arrowFlip = [service.reversed, label.text, wl.displayedSymbols.join(",")]
      var growthOf = function(file) { return (file.lists || []).filter(function(l) { return l.name === "Growth" })[0] || {} }
      var arrowEntry = growthOf(fileWhen(function(f) { return growthOf(f).reversed === true }))
      clickArrow()
      var arrowBack = [service.reversed, label.text, wl.displayedSymbols.join(",")]
      clickWord()
      var wordStep = [service.order, service.reversed, label.text]
      clickWord()
      clickWord()
      harness.check("a click on a sorted order's arrow reverses it and a click on its word steps; on manual a click on ↕ steps",
        harness.same(fromManual, ["symbol", false, "↑  SYMBOL"]) && sortedRows.length === 2
          && harness.same(arrowFlip, [true, "↓  SYMBOL", sortedRows.slice().reverse().join(",")])
          && arrowEntry.order === "symbol" && arrowEntry.reversed === true
          && harness.same(arrowBack, [false, "↑  SYMBOL", sortedRows.join(",")])
          && harness.same(wordStep, ["name", false, "↑  NAME"]) && service.order === "manual",
        [fromManual, sortedRows, arrowFlip, JSON.stringify(arrowEntry), arrowBack, wordStep, service.order].join(" | "))

      // By keys alone, the arrows to a row and Delete, with another list
      // holding it too.
      var holds = function(list, symbol) {
        return service.dataSettings.lists.filter(function(l) { return l.name === list })[0].symbols.indexOf(symbol) >= 0
      }
      service.createList("Keys")
      service.setMembership("AAPL", "Keys", true)
      service.switchList("Growth")
      keys.forceActiveFocus()
      var walkTo = function(symbol) {
        for (var i = 0; i < 10 && wl.cursorRow !== symbol; i++)
          keyClick(wl.displayedSymbols.indexOf(symbol) > wl.displayedSymbols.indexOf(wl.cursorRow) ? Qt.Key_Down : Qt.Key_Up)
      }
      walkTo("NVDA")
      var onNvda = wl.cursorRow === "NVDA"
      walkTo("AAPL")
      keyClick(Qt.Key_Delete)
      var otherKeeps = holds("Keys", "AAPL")
      harness.check("Delete on a named list removes that membership only, and the hero stays",
        onNvda && otherKeeps && harness.same(service.symbols, ["NVDA"]) && service.library.indexOf("AAPL") >= 0
          && service.featuredSymbol === "AAPL" && body.rowMenu === null,
        [onNvda, otherKeeps, service.symbols, service.library, service.featuredSymbol].join(" | "))
      service.deleteList("Keys")
      service.switchList("Growth")
      keys.forceActiveFocus()
      keyClick(Qt.Key_Delete)
      var empty = body.children.filter(function(child) { return child.objectName === "emptyList" })[0]
      harness.check("a named list may empty, and says so, with no refusal",
        service.symbols.length === 0 && body.note === "" && empty.visible
          && empty.text === "No symbols in Growth yet",
        service.symbols.length + "|" + body.note + "|" + empty.visible + "|" + empty.text)

      service.addSymbol("MSFT")
      switchByKeys("")
      wl.cursorSymbol = "MSFT"
      keyClick(Qt.Key_Delete)
      var rowMenu = harness.find(body, "rowMenu")
      focused(rowMenu)
      var asked = body.rowMenu ? body.rowMenu.lines.map(function(l) { return l.label }).join("/") + ":" + rowMenu.cursor : "shut"
      var keptAsking = service.library.indexOf("MSFT") >= 0
      keyClick(Qt.Key_Return)
      var growth = service.dataSettings.lists[0]
      harness.check("Delete on All, for a symbol a named list holds too, asks first on \"Remove from all 2 lists\", and Enter removes it from every list",
        asked === "Remove from all 2 lists:0" && keptAsking && body.rowMenu === null
          && harness.same(service.library, ["AAPL", "NVDA"]) && harness.same(growth.symbols, []),
        asked + "|" + keptAsking + "|" + service.library + "|" + growth.symbols)

      // The name field's Escape goes back to the menu, which ↑ and Enter
      // then pick from.
      keysBack()
      keyClick(Qt.Key_L)
      focused(menu)
      keyClick(Qt.Key_Down)
      keyClick(Qt.Key_Down)
      keyClick(Qt.Key_Return)
      focused(nameField)
      keyClick(Qt.Key_Escape)
      var leftField = [body.listMenuOpen, menu.naming, menu.activeFocus].join(",")
      keyClick(Qt.Key_Up)
      keyClick(Qt.Key_Return)
      harness.check("Escape leaves the name field for the menu",
        leftField === "true,false,true" && !body.listMenuOpen && service.listName === "Growth",
        leftField + "|" + body.listMenuOpen + "|" + service.listName)

      // However a view closes, the window's keys act after: a list picked
      // from the menu; the name field's Escape, then the menu's, the window
      // staying open; Escape from Manage lists; Escape from a symbol's lists.
      switchByKeys("")
      var afterPick = service.listName === ""
      keyClick(Qt.Key_L)
      focused(menu)
      keyClick(Qt.Key_Down)
      keyClick(Qt.Key_Down)
      keyClick(Qt.Key_Return)
      focused(nameField)
      keyClick(Qt.Key_Escape)
      keyClick(Qt.Key_Escape)
      var menuShut = !body.listMenuOpen && app.testWindow.visible
      switchByKeys("Growth")
      var afterMenu = service.listName === "Growth"
      manageByKeys()
      keyClick(Qt.Key_Escape)
      switchByKeys("")
      var afterManage = service.listName === "" && !body.managingLists
      body.openSymbolLists("AAPL")
      focused(checklist)
      keyClick(Qt.Key_Escape)
      switchByKeys("Growth")
      var afterChecklist = service.listName === "Growth" && body.listsSymbol === ""
      harness.check("keys work again after a list is picked from the menu",
        afterPick && menuShut && afterMenu && afterManage && afterChecklist,
        [afterPick, menuShut, afterMenu, afterManage, afterChecklist].join(" | "))

      // By hand. One cursor, as on the rows: the pointer puts it on the
      // list under it, a key moves it on from there, and the pointer leaving
      // the view leaves it. The pointer comes in as a hand's does, over more
      // than one place: the first place it is seen at is where it starts.
      mouseMove(body, 5, body.height - 2)
      body.openSymbolLists("AAPL")
      focused(checklist)
      var tickAt = center(placed("symbolListRow")[0])
      mouseMove(body, tickAt.x, tickAt.y - 6)
      mouseMove(body, tickAt.x, tickAt.y)
      var listsPointed = checklist.cursor
      keyClick(Qt.Key_Down)
      var listsKeyed = checklist.cursor
      keyClick(Qt.Key_Escape)
      keysBack()
      mouseMove(body, 5, body.height - 2)
      var at = center(harness.find(body, "listControl"))
      mouseMove(body, at.x, at.y)
      mouseClick(body, at.x, at.y)
      var clickOpened = body.listMenuOpen
      mouseClick(body, at.x, at.y)
      harness.check("a click on the list name opens the menu", clickOpened && !body.listMenuOpen)
      mouseClick(body, at.x, at.y)
      focused(menu)
      var choices = placed("listChoice")
      var opened = menu.cursor
      var allAt = center(choices[0])
      mouseMove(body, allAt.x, allAt.y - 6)
      mouseMove(body, allAt.x, allAt.y)
      var pointed = menu.cursor
      keyClick(Qt.Key_Down)
      var keyed = menu.cursor
      mouseMove(body, 5, body.height - 2)
      var left = menu.cursor
      harness.check("in the list menu the pointer puts the one cursor on the list under it, a key moves it on, and leaving keeps it",
        opened === 1 && pointed === 0 && keyed === 1 && left === keyed && listsPointed === 0 && listsKeyed === 1,
        [opened, pointed, keyed, left, listsPointed, listsKeyed].join(" | "))
      mouseClick(body, allAt.x, allAt.y)
      harness.check("a click on a list switches to it and closes the menu",
        service.listName === "" && !body.listMenuOpen)
      mouseMove(body, 5, body.height - 2)

      // MAKE does what Enter does in the field.
      mouseClick(body, at.x, at.y)
      var newAt = center(harness.find(body, "newListRow"))
      mouseClick(body, newAt.x, newAt.y)
      var namingByClick = menu.naming
      focused(nameField)
      typeText(" Wins ")
      var makeAt = center(harness.find(menu, "makeList"))
      mouseClick(body, makeAt.x, makeAt.y)
      harness.check("a click on MAKE makes the list and opens search to fill it",
        namingByClick && service.listName === "Wins" && !body.listMenuOpen && body.adding,
        namingByClick + "|" + service.listName + "|" + body.adding)
      focused(searchField)
      keyClick(Qt.Key_Escape)

      // The pointer resting on the chart under the open menu does nothing.
      mouseClick(body, at.x, at.y)
      var chartAt = center(body.chartItem)
      mouseMove(body, chartAt.x, chartAt.y)
      // Time for a scrub to show.
      wait(100)
      harness.check("the pointer over the chart does not scrub while the menu is open",
        body.listMenuOpen && body.scrubT === 0)
      var rangeBefore = app.range
      mouseClick(body, chartAt.x, chartAt.y)
      harness.check("a click off the menu closes it and reaches nothing under it",
        !body.listMenuOpen && app.range === rangeBefore && service.listName === "Wins")
      mouseMove(body, 5, body.height - 2)

      // A click away from the name field keeps what was typed, as Enter
      // does: on a list in the menu, which is not switched to, and off the
      // menu.
      var nameThenClick = function(name, place) {
        mouseClick(body, at.x, at.y)
        newAt = center(harness.find(body, "newListRow"))
        mouseClick(body, newAt.x, newAt.y)
        focused(nameField)
        typeText(name)
        var p = place()
        mouseClick(body, p.x, p.y)
        within(1000, function() { return service.listName === name && body.adding })
        var kept = [service.listName, !body.listMenuOpen, body.adding].join(",")
        focused(searchField)
        keyClick(Qt.Key_Escape)
        return kept
      }
      var onRow = nameThenClick("Later", function() { return center(placed("listChoice")[0]) })
      var offMenu = nameThenClick("Later2", function() { return chartAt })
      harness.check("a click away from a new list's name makes it, on a list in the menu or off the menu",
        onRow === "Later,true,true" && offMenu === "Later2,true,true", onRow + " | " + offMenu)
      service.switchList("Wins")
      service.deleteList("Later")
      service.deleteList("Later2")

      service.addSymbol("AAPL")
      service.addSymbol("NVDA")
      service.feature("NVDA")
      within(2000, function() { return wl.rowResting("AAPL") && wl.rowResting("NVDA") })

      // A view that opens under a resting pointer keeps the cursor it opens
      // on until the pointer really moves, so Enter acts on that row, never
      // on the one the pointer happens to rest on. Growth and Wins, Wins
      // current. A symbol's lists, opened by a Ctrl-click on a row that
      // All's tick will lie under, the pointer then resting: Enter ticks the
      // first named list, as the view opened.
      var listsAll = placed("symbolListRow")[0]
      var allTop = listsAll.mapToItem(body, 0, 0).y
      var spot = null
      var spotSymbol = ""
      ;["AAPL", "NVDA"].forEach(function(symbol) {
        var row = wl.rowItem(symbol)
        var top = Math.max(allTop, row.mapToItem(body, 0, 0).y)
        var bottom = Math.min(allTop + listsAll.height, row.mapToItem(body, 0, row.height).y)
        if (spot || bottom - top < 4) return
        spot = Qt.point(row.mapToItem(body, row.width / 2, 0).x, (top + bottom) / 2)
        spotSymbol = symbol
      })
      mouseMove(body, spot.x, spot.y - 6)
      mouseMove(body, spot.x, spot.y)
      mouseClick(body, spot.x, spot.y, Qt.LeftButton, Qt.ControlModifier)
      focused(checklist)
      // The compositor reports the resting pointer again, a pixel off: still
      // no move.
      mouseMove(body, spot.x, spot.y + 1)
      var growthHolds = function() {
        return service.dataSettings.lists.filter(function(l) { return l.name === "Growth" })[0].symbols
      }
      var allUnder = listsAll.contains(listsAll.mapFromItem(body, spot.x, spot.y))
      var listsOpenedOn = checklist.cursor
      keyClick(Qt.Key_Return)
      var spaced = [allUnder, listsOpenedOn === 1, service.library.indexOf(spotSymbol) >= 0,
        body.listsSymbol === spotSymbol, growthHolds().indexOf(spotSymbol) >= 0].join(",")
      keyClick(Qt.Key_Return)
      keyClick(Qt.Key_Escape)
      keysBack()
      // The list menu, opened by l with the pointer resting on All: Enter
      // takes the current list. Off the middle, where the pointer rested the
      // last time the menu was open, so this is a new place to its pointer.
      var menuAllAt = center(placed("listChoice")[0])
      menuAllAt.x += 20
      mouseMove(body, menuAllAt.x, menuAllAt.y)
      keyClick(Qt.Key_L)
      focused(menu)
      mouseMove(body, menuAllAt.x, menuAllAt.y + 1)
      var menuOpenedOn = menu.cursor
      keyClick(Qt.Key_Return)
      keysBack()
      var entered = [menuOpenedOn === 2, service.listName === "Wins", !body.listMenuOpen].join(",")
      // Manage lists, opened by keys from the list menu with the pointer
      // resting on All: Enter renames the first named list.
      var manageAllAt = center(placed("manageRow")[0])
      mouseMove(body, manageAllAt.x, manageAllAt.y)
      manageByKeys()
      mouseMove(body, manageAllAt.x, manageAllAt.y + 1)
      var manageOpenedOn = manage.cursor
      keyClick(Qt.Key_Return)
      var renamed = [manageOpenedOn === 1, manage.renaming && manage.cursor === 1].join(",")
      focused(renameField)
      keyClick(Qt.Key_Escape)
      keyClick(Qt.Key_Escape)
      keysBack()
      harness.check("a view opening under a resting pointer keeps the cursor it opens on: a symbol's lists over All, the list menu, and Manage lists",
        spaced === "true,true,true,true,true" && entered === "true,true,true" && renamed === "true,true" && !body.managingLists,
        [spaced, entered, renamed, body.managingLists].join(" | "))

      // A double-click is one click, Ctrl-click's too: the lists it opens
      // under the pointer take no click within the double-click interval, so
      // a Ctrl-double-click, or a click at once after a Ctrl-click, never
      // unticks All under it.
      var ctrlThen = function(second) {
        second()
        focused(checklist)
        var kept = [body.listsSymbol === spotSymbol, service.library.indexOf(spotSymbol) >= 0,
          harness.same(service.symbols, ["AAPL", "NVDA"])].join(",")
        keyClick(Qt.Key_Escape)
        keysBack()
        return kept
      }
      var ctrlDouble = ctrlThen(function() {
        mouseDoubleClickSequence(body, spot.x, spot.y, Qt.LeftButton, Qt.ControlModifier)
      })
      clickApart()
      var ctrlThenClick = ctrlThen(function() {
        mouseClick(body, spot.x, spot.y, Qt.LeftButton, Qt.ControlModifier)
        mouseClick(body, spot.x, spot.y)
      })
      harness.check("a Ctrl-double-click, or a click at once after a Ctrl-click, over All's tick leaves the symbol in All",
        ctrlDouble === "true,true,true" && ctrlThenClick === "true,true,true", ctrlDouble + " | " + ctrlThenClick)

      // A right-click opens the row's menu at the pointer, on no line, and
      // removes nothing, Escape closes it, and its first line takes the row
      // out of this list only.
      clickApart()
      var aaplRow = wl.rowItem("AAPL")
      var held = function(symbol) { return service.lists.filter(function(l) { return l.symbols.indexOf(symbol) >= 0 }).length }
      var menuShown = function() {
        return body.rowMenu ? body.rowMenu.symbol + " " + rowMenu.lines.join("/") + " " + rowMenu.cursor : "shut"
      }
      var both = harness.same(service.symbols, ["AAPL", "NVDA"])
      var aaplLists = held("AAPL")
      // Near the row's left, where the menu has room to open at the pointer.
      var aaplAt = aaplRow.mapToItem(body, 40, aaplRow.height / 2)
      mouseMove(body, aaplAt.x, aaplAt.y - 6)
      mouseMove(body, aaplAt.x, aaplAt.y)
      mouseClick(body, aaplAt.x, aaplAt.y, Qt.RightButton)
      var menuItem = harness.find(body, "rowMenu")
      var openedMenu = [menuShown(), harness.same(service.symbols, ["AAPL", "NVDA"]),
        Math.abs(menuItem.mapToItem(body, 0, 0).x - aaplAt.x) <= 1 && Math.abs(menuItem.mapToItem(body, 0, 0).y - aaplAt.y) <= 1].join(",")
      focused(rowMenu)
      keyClick(Qt.Key_Escape)
      var escaped = menuShown() + "," + harness.same(service.symbols, ["AAPL", "NVDA"])
      clickApart()
      mouseClick(body, aaplAt.x, aaplAt.y, Qt.RightButton)
      var fromWins = placed("rowMenuLine")[0]
      mouseClick(fromWins, fromWins.width / 2, fromWins.height / 2)
      harness.check("a right-click on a row of a named list opens its menu at the pointer, removing nothing; Escape closes it; and \"Remove from Wins\" takes it out of that list only",
        both && openedMenu === "AAPL Remove from Wins/Remove from all " + aaplLists + " lists -1,true,true" && escaped === "shut,true"
          && harness.same(service.symbols, ["NVDA"]) && service.library.indexOf("AAPL") >= 0,
        [both, openedMenu, escaped, service.symbols, service.library].join(" | "))

      // Another surface switching the list closes a menu opened on Wins, so
      // "Remove from Wins" never acts in All. Opened as a key opens it, on
      // its first line.
      var listsBefore = JSON.stringify(service.lists)
      keys.forceActiveFocus()
      body.openRowMenu("NVDA", null)
      focused(rowMenu)
      var openOnWins = menuShown()
      service.switchList("")
      within(1000, function() { return menuShown() === "shut" })
      var afterSwitch = menuShown()
      keysBack()
      keyClick(Qt.Key_Return)
      harness.check("a list switched on another surface closes the row's menu, and Enter then removes nothing",
        openOnWins.indexOf("NVDA Remove from Wins/") === 0 && afterSwitch === "shut" && JSON.stringify(service.lists) === listsBefore,
        [openOnWins, afterSwitch, JSON.stringify(service.lists)].join(" | "))
      service.switchList("Wins")

      // Manage lists by keyboard: Growth and Wins, Wins current.
      var names = function() { return service.dataSettings.lists.map(function(l) { return l.name }) }
      keys.forceActiveFocus()
      manageByKeys()
      harness.check("l, ↓ to Manage lists… and Enter open Manage lists in the rows' place, on the first named list",
        body.managingLists && !body.listMenuOpen && manage.visible && manage.activeFocus && manage.cursor === 1
          && !wl.visible && !harness.find(body, "footer").visible,
        body.managingLists + "|" + manage.activeFocus + "|" + manage.cursor)
      keyClick(Qt.Key_Return)
      focused(renameField)
      typeText("GROWTH")
      keyClick(Qt.Key_Return)
      harness.check("a change of case alone renames",
        !manage.renaming && harness.same(names(), ["GROWTH", "Wins"]), names())
      keyClick(Qt.Key_Down, Qt.ShiftModifier)
      harness.check("Shift+↓ moves the list down, and the cursor goes with it",
        harness.same(names(), ["Wins", "GROWTH"]) && manage.cursor === 2, names() + "|" + manage.cursor)
      keyClick(Qt.Key_Delete)
      var askedFirst = manage.confirming && harness.same(names(), ["Wins", "GROWTH"])
      keyClick(Qt.Key_Escape)
      harness.check("Delete asks before deleting",
        askedFirst && !manage.confirming && body.managingLists && harness.same(names(), ["Wins", "GROWTH"]))
      keyClick(Qt.Key_Up)
      keyClick(Qt.Key_Delete)
      keyClick(Qt.Key_Return)
      harness.check("Delete then Enter deletes the list; deleting the current list switches to All and leaves All untouched",
        harness.same(names(), ["GROWTH"]) && service.listName === ""
          && harness.same(service.library, ["AAPL", "NVDA"]),
        names() + "|" + service.listName + "|" + service.library)
      keyClick(Qt.Key_Escape)
      keysBack()

      // Manage lists by hand, from the menu.
      service.createList("Wins")
      mouseClick(body, at.x, at.y)
      var manageAt = center(harness.find(body, "manageListsRow"))
      mouseClick(body, manageAt.x, manageAt.y)
      harness.check("Manage lists… in the menu opens the view", body.managingLists && !body.listMenuOpen)
      var manageRows = placed("manageRow")
      var winsRow = manageRows[2]
      var winsAt = center(winsRow)
      // The view opens resting the pointer where it is (RowPointer): its
      // first report there is no move, and a loaded machine may send it
      // only with the next move, which it then swallows. So the pointer is
      // seen where it rests first, then moves.
      mouseMove(body, manageAt.x, manageAt.y)
      mouseMove(body, winsAt.x, winsAt.y)
      within(1000, function() { return manage.cursor === 2 })
      // The pointer travels to the control it clicks, as a hand's does.
      var upAt = center(harness.find(winsRow, "moveUp"))
      mouseMove(body, upAt.x, upAt.y)
      mouseClick(body, upAt.x, upAt.y)
      harness.check("↑ on a hovered row moves that list up", harness.same(names(), ["Wins", "GROWTH"]), names())
      var growthRow = placed("manageRow")[2]
      var growthAt = center(growthRow)
      mouseMove(body, growthAt.x, growthAt.y)
      var renameAt = center(harness.find(growthRow, "renameAction"))
      mouseClick(body, renameAt.x, renameAt.y)
      focused(renameField)
      typeText("Nope")
      var renaming = manage.renaming
      var cancelRenameAt = center(harness.find(manage, "cancelRename"))
      mouseClick(body, cancelRenameAt.x, cancelRenameAt.y)
      harness.check("CANCEL leaves the rename field and keeps the name",
        renaming && !manage.renaming && harness.same(names(), ["Wins", "GROWTH"]),
        renaming + "|" + manage.renaming + "|" + names())
      mouseClick(body, renameAt.x, renameAt.y)
      focused(renameField)
      typeText("Pow")
      var awayAt = center(placed("manageRow")[1])
      mouseClick(body, awayAt.x, awayAt.y)
      harness.check("a click away from the field keeps the typed name",
        harness.same(names(), ["Wins", "Pow"]) && !manage.renaming, names() + "|" + manage.renaming)
      mouseMove(body, growthAt.x, growthAt.y)
      mouseClick(body, renameAt.x, renameAt.y)
      focused(renameField)
      typeText("Power")
      var saveAt = center(harness.find(manage, "saveName"))
      mouseClick(body, saveAt.x, saveAt.y)
      harness.check("RENAME opens the field on that row, and SAVE saves",
        harness.same(names(), ["Wins", "Power"]) && !manage.renaming, names())
      var winsRowNow = placed("manageRow")[1]
      var winsNowAt = center(winsRowNow)
      mouseMove(body, winsNowAt.x, winsNowAt.y)
      var deleteAt = center(harness.find(winsRowNow, "deleteAction"))
      mouseClick(body, deleteAt.x, deleteAt.y)
      // The question's DELETE, which Enter takes, and CANCEL, Escape's.
      var confirmAction = harness.find(winsRowNow, "confirmDelete")
      var cancelButton = harness.find(winsRowNow, "cancelDelete")
      var choicesShown = [confirmAction.visible && confirmAction.text === "DELETE",
        !!cancelButton && cancelButton.visible && cancelButton.text === "CANCEL"].join(",")
      var powerRowAt = center(placed("manageRow")[2])
      mouseMove(body, powerRowAt.x, powerRowAt.y)
      harness.check("the delete question stays on its list as the pointer passes another",
        manage.confirming && manage.cursor === 1, manage.confirming + "|" + manage.cursor)
      var cancelAt = center(cancelButton)
      mouseClick(body, cancelAt.x, cancelAt.y)
      harness.check("DELETE asks, and CANCEL keeps the list",
        choicesShown === "true,true" && !manage.confirming && harness.same(names(), ["Wins", "Power"]), choicesShown)
      // A double-click on DELETE asks, and never answers its own question:
      // the second click lands where the question's DELETE now sits.
      mouseMove(body, winsNowAt.x, winsNowAt.y)
      var deleteAction = harness.find(winsRowNow, "deleteAction")
      var deleteFirst = deleteAction.mapToItem(body, 3, deleteAction.height / 2)
      mouseDoubleClickSequence(body, deleteFirst.x, deleteFirst.y)
      var confirmUnder = false
      try { confirmUnder = confirmAction.contains(confirmAction.mapFromItem(body, deleteFirst.x, deleteFirst.y)) } catch (e) {}
      var afterDouble = [confirmUnder, manage.confirming, names().join(",")].join("|")
      keyClick(Qt.Key_Escape)
      harness.check("a double-click on DELETE, its second click on the question's DELETE, asks and deletes nothing; Escape takes the question back",
        afterDouble === "true|true|Wins,Power" && !manage.confirming && harness.same(names(), ["Wins", "Power"]),
        afterDouble + " then " + manage.confirming)
      // A second press inside the interval, held until after it ends, is
      // still that double-click's: Qt counts a double-click from the presses,
      // and its release answers nothing. The question's DELETE takes clicks
      // again once the last ask's interval is over.
      var interval = Application.styleHints.mouseDoubleClickInterval
      var answers = function() { return within(interval + 100, function() { return confirmAction.enabled }) }
      answers()
      mouseMove(body, winsNowAt.x, winsNowAt.y)
      mouseClick(body, deleteFirst.x, deleteFirst.y)
      wait(interval - 150)
      mousePress(body, deleteFirst.x, deleteFirst.y)
      wait(250)
      mouseRelease(body, deleteFirst.x, deleteFirst.y)
      var afterHeld = [manage.confirming, names().join(",")].join("|")
      keyClick(Qt.Key_Escape)
      harness.check("a second press on the question's DELETE inside the double-click interval, released after it, deletes nothing",
        afterHeld === "true|Wins,Power" && !manage.confirming && harness.same(names(), ["Wins", "Power"]),
        afterHeld + " then " + manage.confirming + "|" + names())
      answers()
      mouseMove(body, winsNowAt.x, winsNowAt.y)
      mouseClick(body, deleteAt.x, deleteAt.y)
      answers()
      var confirmAt = center(confirmAction)
      mouseClick(body, confirmAt.x, confirmAt.y)
      harness.check("the confirmed DELETE removes the current list and goes to All",
        harness.same(names(), ["Power"]) && service.listName === "", names() + "|" + service.listName)
      var powerOnly = placed("manageRow")[1]
      var powerOnlyAt = center(powerOnly)
      mouseMove(body, powerOnlyAt.x, powerOnlyAt.y)
      var renameOnlyAt = center(harness.find(powerOnly, "renameAction"))
      mouseClick(body, renameOnlyAt.x, renameOnlyAt.y)
      focused(renameField)
      typeText("Powr")
      var doneAt = center(harness.find(body, "manageDone"))
      mouseClick(body, doneAt.x, doneAt.y)
      harness.check("DONE over a rename keeps the typed name and closes Manage lists",
        !body.managingLists && wl.visible && harness.same(names(), ["Powr"]), body.managingLists + "|" + names())
      service.renameList("Powr", "Power")
      // A click on the header's ? keeps a rename being typed, as DONE does,
      // and a refused one keeps the view, saying why.
      var renameThenHelp = function(typed) {
        body.openManageLists()
        var row = placed("manageRow")[1]
        var rowAt = center(row)
        mouseMove(body, rowAt.x, rowAt.y)
        var renameRowAt = center(harness.find(row, "renameAction"))
        mouseClick(body, renameRowAt.x, renameRowAt.y)
        focused(renameField)
        typeText(typed)
        var help = center(harness.find(body, "helpMark"))
        mouseClick(body, help.x, help.y)
        return [body.showingHelp, body.managingLists, manage.renaming, manage.problem !== "", names().join("/")].join(",")
      }
      var helpKeeps = renameThenHelp("Pwr")
      body.showingHelp = false
      var helpRefused = renameThenHelp("all")
      focused(renameField)
      keyClick(Qt.Key_Escape)
      body.closeListViews()
      harness.check("a click on ? keeps a rename being typed, and a refused one keeps the view saying why",
        helpKeeps === "true,false,false,false,Pwr" && helpRefused === "false,true,true,true,Pwr", helpKeeps + " | " + helpRefused)
      service.renameList("Pwr", "Power")

      // A symbol's lists by keys, then Ctrl-click. Opened as a Ctrl-click
      // opens them, on the cursor row.
      var power = function() { return service.dataSettings.lists[0].symbols }
      keys.forceActiveFocus()
      wl.cursorSymbol = "NVDA"
      body.openSymbolLists("NVDA")
      focused(checklist)
      harness.check("a symbol's lists open on the first named list, with the keys",
        body.listsSymbol === "NVDA" && checklist.visible && checklist.activeFocus && checklist.cursor === 1
          && !wl.visible)
      keyClick(Qt.Key_Return)
      var ticked = power().join(",")
      keyClick(Qt.Key_Return)
      harness.check("Enter ticks a list, which gains the symbol",
        ticked === "NVDA" && harness.same(power(), []) && harness.same(service.library, ["AAPL", "NVDA"]),
        ticked + " then " + power())
      keyClick(Qt.Key_Return)
      keyClick(Qt.Key_Escape)
      keysBack()

      var aaplRowAgain = wl.rowItem("AAPL")
      mouseClick(aaplRowAgain, aaplRowAgain.width / 2, aaplRowAgain.height / 2, Qt.LeftButton, Qt.ControlModifier)
      harness.check("Ctrl-click opens that row's lists without featuring it",
        body.listsSymbol === "AAPL" && service.featuredSymbol === "NVDA", body.listsSymbol + "|" + service.featuredSymbol)
      var openingShield = harness.find(body, "openingShield")
      var listRows = placed("symbolListRow")
      var powerAt = center(listRows[1])
      mouseMove(body, powerAt.x, powerAt.y)
      // The Ctrl-click that opened them takes no second click.
      tryVerify(function() { return !openingShield.visible }, 2000)
      mouseClick(body, powerAt.x, powerAt.y)
      harness.check("a click ticks that row's list", harness.same(power(), ["NVDA", "AAPL"]), power())
      focused(checklist)
      keyClick(Qt.Key_Up)
      keyClick(Qt.Key_Return)
      harness.check("unticking All removes the symbol everywhere and closes the checklist",
        harness.same(service.library, ["NVDA"]) && harness.same(power(), ["NVDA"]) && body.listsSymbol === "",
        service.library + "|" + power() + "|" + body.listsSymbol)

      // Ctrl+Z takes back the service's last removal, wherever it was made:
      // one made on another surface replaces this one's, so AAPL returns to
      // All, and stays out of Power, which the first removal took it from.
      service.switchList("Power")
      service.addSymbol("AAPL")
      within(3000, function() { return wl.displayedSymbols.indexOf("AAPL") >= 0 })
      keysBack()
      wl.cursorSymbol = "AAPL"
      keyClick(Qt.Key_Delete)
      service.setMembership("AAPL", "", false)
      keyClick(Qt.Key_Z, Qt.ControlModifier)
      harness.check("and Ctrl+Z then takes back that removal, made on the other surface",
        harness.same(power(), ["NVDA"]) && harness.same(service.library, ["NVDA", "AAPL"]),
        power() + "|" + service.library)
      service.setMembership("AAPL", "", false)
      service.switchList("")

      keys.forceActiveFocus()
      body.openSymbolLists(wl.cursorRow)
      focused(checklist)
      keyClick(Qt.Key_Up)
      keyClick(Qt.Key_Return)
      harness.check("All's last symbol cannot be unticked, and the checklist says why",
        harness.same(service.library, ["NVDA"]) && body.listsSymbol === "NVDA"
          && checklist.note === "Keep at least one symbol")
      tryVerify(function() { return !openingShield.visible }, 2000)
      var listsDoneAt = center(harness.find(body, "symbolListsDone"))
      mouseClick(body, listsDoneAt.x, listsDoneAt.y)
      harness.check("DONE closes the checklist", body.listsSymbol === "" && wl.visible)

      var savedLists = function(f) {
        return f.version === 1 && harness.same(f.symbols, ["NVDA"]) && f.list === ""
          && (f.lists || []).length === 1 && f.lists[0].name === "Power" && harness.same(f.lists[0].symbols, ["NVDA"])
      }
      var saved = fileWhen(savedLists)
      harness.check("the file holds the renamed, reordered, and ticked lists", savedLists(saved), JSON.stringify(saved))

      // With no named lists the checklist has only All; the default cursor
      // must not sit on it, or one Enter removes the symbol everywhere.
      service.deleteList("Power")
      service.addSymbol("AAPL")
      keys.forceActiveFocus()
      wl.cursorSymbol = "AAPL"
      body.openSymbolLists("AAPL")
      focused(checklist)
      keyClick(Qt.Key_Return)
      keyClick(Qt.Key_Return)
      harness.check("with no named lists, a symbol's lists open off All, and Enter leaves the symbol in All",
        body.listsSymbol === "AAPL" && harness.same(service.library, ["NVDA", "AAPL"]),
        body.listsSymbol + "|" + service.library)
      keyClick(Qt.Key_Escape)
      keysBack()

      // A removal made here offers itself back beside the add for a few
      // seconds, "Undo AAPL": the add beside it opens search at once, and
      // the undo, clicked, puts the row back, and goes. By the mouse alone:
      // the row's ×, the add, the undo.
      tryVerify(function() { return !!service.quotes.AAPL && service.testFeed.firstRun.length + service.testFeed.refreshRun.length === 0 }, 3000)
      clickApart()
      wl.cursorSymbol = "AAPL"
      var aaplCross = harness.find(wl.rowItem("AAPL"), "rowRemove")
      var crossAt = aaplCross && aaplCross.visible ? center(aaplCross) : null
      if (crossAt) mouseClick(body, crossAt.x, crossAt.y)
      var footerUndo = harness.find(body, "footerUndo")
      within(1000, function() { return footerUndo.visible })
      var offered = [harness.same(service.library, ["NVDA"]), footerUndo.visible, harness.find(footerUndo, "footerUndoText").text].join(",")
      var addAt = center(harness.find(body, "footerFill"))
      mouseClick(body, addAt.x, addAt.y)
      var addOpened = body.adding
      focused(searchField)
      keyClick(Qt.Key_Escape)
      var stillOffered = footerUndo.visible
      var undoAt = center(footerUndo)
      mouseClick(body, undoAt.x, undoAt.y)
      within(1000, function() { return !footerUndo.visible })
      harness.check("a removal offers Undo beside the add, which opens search at once; a click on Undo puts the row back, and the offer goes",
        offered === "true,true,Undo AAPL" && addOpened && stillOffered && harness.same(service.library, ["NVDA", "AAPL"]) && !footerUndo.visible,
        [offered, addOpened, stillOffered, service.library, footerUndo.visible].join(" | "))

      // A removal from a symbol's lists hands the cursor on as the × does:
      // the row that comes back as the checklist closes shows no × until
      // the pointer moves. The click comes once the checklist takes clicks.
      wl.cursorSymbol = "NVDA"
      keys.forceActiveFocus()
      body.openSymbolLists("NVDA")
      tryVerify(function() { return !openingShield.visible }, 2000)
      var allTickAt = center(placed("symbolListRow")[0])
      mouseClick(body, allTickAt.x, allTickAt.y)
      // Time for a × under the pointer to show.
      wait(100)
      var handedOn = [harness.same(service.library, ["AAPL"]), wl.cursorRow, harness.find(wl.rowItem("AAPL"), "rowRemove").visible].join(",")
      keysBack()
      keyClick(Qt.Key_Z, Qt.ControlModifier)
      harness.check("a removal from a symbol's lists hands the cursor on, its row showing no × under the still pointer",
        handedOn === "true,AAPL,false" && harness.same(service.library, ["NVDA", "AAPL"]), handedOn + " | " + service.library)

      // The rule under the list name is the list's breadth: the rows' own
      // ups, flats, and downs, counted. It follows the list menu, and so
      // does the order word.
      service.addSymbol("DOWN")
      service.addSymbol("FLAT")
      tryVerify(function() { return !!service.quotes.DOWN && !!service.quotes.FLAT }, 5000)
      var rule = harness.find(body, "breadthRule")
      var tones = function() {
        var count = { up: 0, flat: 0, down: 0 }
        wl.displayedSymbols.forEach(function(s) {
          var r = wl.rowItem(s)
          if (r && r.view) count[r.view.tone]++
        })
        return count
      }
      var reads = function(up, flat, down) {
        var t = tones()
        return !!rule && rule.breadth.up === up && rule.breadth.flat === flat && rule.breadth.down === down
          && t.up === up && t.flat === flat && t.down === down
      }
      service.createList("Losers")
      service.addSymbol("DOWN")
      service.setOrder("symbol")
      keys.forceActiveFocus()
      switchByKeys("")
      var allOrder = label.text
      switchByKeys("Losers")
      var losersOrder = label.text
      keyClick(Qt.Key_O)
      var byO = label.text
      harness.check("the rule follows the list menu to a list with one row, which is down",
        service.listName === "Losers" && reads(0, 0, 1)
          && harness.same([allOrder, losersOrder, byO], ["↕  MANUAL", "↑  SYMBOL", "↑  NAME"]),
        (rule ? JSON.stringify(rule.breadth) : "no rule") + " | " + [allOrder, losersOrder, byO].join(", "))

      // Every view opens at its own start, not at last time's: search empty,
      // the menu on the current list, and each list view on its first named
      // list, in the turn it appears, which is the frame first drawn. Each
      // is first left off its start, then opened again.
      keys.forceActiveFocus()
      keyClick(Qt.Key_A)
      focused(searchField)
      searchField.text = "SH"
      tryVerify(function() { return body.search.results.length > 0 }, 3000)
      keyClick(Qt.Key_Escape)
      keysBack()
      keyClick(Qt.Key_L)
      focused(menu)
      keyClick(Qt.Key_Down)
      keyClick(Qt.Key_Escape)
      keysBack()
      body.openManageLists()
      focused(manage)
      keyClick(Qt.Key_Up)
      keyClick(Qt.Key_Escape)
      keysBack()
      wl.cursorSymbol = "DOWN"
      body.openSymbolLists("DOWN")
      focused(checklist)
      keyClick(Qt.Key_Up)
      keyClick(Qt.Key_Escape)
      keysBack()
      // Read as each view turns on, in that same turn: what its first frame
      // will show.
      var firstFrames = []
      var onSearch = function() { if (body.search.active) firstFrames.push(body.search.results.length + "'" + body.search.searchText + "'") }
      var onMenu = function() { if (menu.active) firstFrames.push(menu.cursor) }
      var onManage = function() { if (manage.active) firstFrames.push(manage.cursor) }
      var onChecklist = function() { if (checklist.active) firstFrames.push(checklist.cursor) }
      body.search.activeChanged.connect(onSearch)
      menu.activeChanged.connect(onMenu)
      manage.activeChanged.connect(onManage)
      checklist.activeChanged.connect(onChecklist)
      keyClick(Qt.Key_A)
      focused(searchField)
      keyClick(Qt.Key_Escape)
      keysBack()
      keyClick(Qt.Key_L)
      focused(menu)
      keyClick(Qt.Key_Escape)
      keysBack()
      body.openManageLists()
      focused(manage)
      keyClick(Qt.Key_Escape)
      keysBack()
      wl.cursorSymbol = "DOWN"
      body.openSymbolLists("DOWN")
      focused(checklist)
      keyClick(Qt.Key_Escape)
      keysBack()
      body.search.activeChanged.disconnect(onSearch)
      menu.activeChanged.disconnect(onMenu)
      manage.activeChanged.disconnect(onManage)
      checklist.activeChanged.disconnect(onChecklist)
      harness.check("search, the list menu, and both list views reset their query and cursor on open",
        firstFrames.join("|") === "0''|1|1|1", firstFrames.join("|"))

      // Every view gives up the keys however it closes, the window's closing
      // included, its name field too, and a view closed before it took them
      // never takes them later: afterwards the window's own keys act.
      var keysAfter = function(open, taker) {
        keys.forceActiveFocus()
        open()
        focused(taker())
        app.close()
        openWindow()
        var retro = service.retro
        keyClick(Qt.Key_S)
        var acted = service.retro !== retro
        if (acted) keyClick(Qt.Key_S)
        return acted
      }
      var closings = [
        keysAfter(function() { keyClick(Qt.Key_L) }, function() { return menu }),
        keysAfter(function() { keyClick(Qt.Key_L); focused(menu); keyClick(Qt.Key_Up); keyClick(Qt.Key_Up); keyClick(Qt.Key_Return) },
          function() { return keys }),
        keysAfter(function() { body.openManageLists() }, function() { return manage }),
        keysAfter(function() { body.openManageLists(); focused(manage); keyClick(Qt.Key_Return) }, function() { return renameField }),
        keysAfter(function() { body.openSymbolLists(wl.cursorRow) }, function() { return checklist }),
        keysAfter(function() { keyClick(Qt.Key_A) }, function() { return searchField })
      ]
      harness.check("closing the window with any view open, or its field, hands the keys back",
        closings.every(function(acted) { return acted }), closings.join(","))
      body.openListMenu()
      body.closeListMenu()
      // Time for a late take of the keys.
      wait(50)
      var retroBefore = service.retro
      keyClick(Qt.Key_S)
      harness.check("a view closed before it took the keys never takes them",
        service.retro !== retroBefore && !menu.activeFocus, service.retro + "|" + menu.activeFocus)
      keyClick(Qt.Key_S)

      // A click on the header's look closes the key sheet first, as s does.
      keyClick(Qt.Key_Question)
      var lookBefore = service.retro
      var clickLook = function() {
        var icon = harness.find(body, "lookIcon")
        var over = icon.mapToItem(body, icon.width / 2, icon.height / 2)
        mouseClick(body, over.x, over.y)
      }
      clickLook()
      harness.check("a click on the header's look over the key sheet closes it and changes the look once",
        !body.showingHelp && service.retro !== lookBefore, body.showingHelp + "|" + service.retro)
      clickLook()
      keyClick(Qt.Key_Question)
      var helpClose = harness.find(body, "helpClose")
      within(1000, function() { return helpClose.visible })
      var closeAt = center(helpClose)
      mouseClick(body, closeAt.x, closeAt.y)
      harness.check("CLOSE closes the key sheet and shows the rows", !body.showingHelp && wl.visible,
        body.showingHelp + "|" + wl.visible)

      // The list menu opens scrolled to its own start, the current list in
      // view, however far the last visit scrolled it.
      var extra = []
      for (var n = 1; n <= 12; n++) { extra.push("Probe " + n); service.createList("Probe " + n) }
      service.switchList("")
      app.close()
      var tallBefore = app.testWindow.implicitHeight
      // One row tall: the chart kept whole, as the window's own gives way
      // to three rows (StonksBody.minChartHeight).
      body.minChartHeight = 0
      app.testWindow.implicitHeight = body.chromeHeight + body.listRowHeight
      openWindow()
      var menuScroll = harness.find(menu, "menuScroll")
      // "New list…" and "Manage lists…" are pinned under the lists, always
      // in sight.
      var cursorShown = function() {
        if (menu.cursor >= menu.newIndex) return true
        var top = menu.cursor * menu.itemHeight
        return top >= menuScroll.contentY && top + menu.itemHeight <= menuScroll.contentY + menuScroll.height
      }
      keyClick(Qt.Key_L)
      focused(menu)
      var scrolls = menuScroll.contentHeight > menuScroll.height
      menuScroll.contentY = menuScroll.contentHeight - menuScroll.height
      keyClick(Qt.Key_Escape)
      keysBack()
      var reopenedAt = []
      var readMenu = function() { if (menu.active) reopenedAt.push(menuScroll.contentY + ":" + menu.cursor + ":" + cursorShown()) }
      menu.activeChanged.connect(readMenu)
      keyClick(Qt.Key_L)
      focused(menu)
      keyClick(Qt.Key_Escape)
      keysBack()
      service.switchList("Probe 12")
      keyClick(Qt.Key_L)
      focused(menu)
      keyClick(Qt.Key_Escape)
      keysBack()
      menu.activeChanged.disconnect(readMenu)
      var lastProbe = service.lists.map(function(l) { return l.name }).indexOf("Probe 12")
      harness.check("the list menu opens at its start with the current list in view",
        scrolls && reopenedAt.length === 2 && reopenedAt[0] === "0:0:true"
          && new RegExp(":" + lastProbe + ":true$").test(reopenedAt[1]),
        scrolls + "|" + reopenedAt.join(" "))
      // A refusal names the problem. Editing clears it; Escape leaves the
      // field. Its fit and the gap left by its line are render specimens.
      var refuseTwice = function(view) {
        keyClick(Qt.Key_Return)
        var refused = within(1000, function() { return view.problem !== "" && harness.showsPrice(view, view.problem) })
        typeText("x")
        var editing = view.problem === "" && (view.naming || view.renaming)
        keyClick(Qt.Key_Backspace)
        keyClick(Qt.Key_Return)
        keyClick(Qt.Key_Escape)
        var left = !view.naming && !view.renaming
        return [refused, editing, left].join(",")
      }
      keyClick(Qt.Key_L)
      focused(menu)
      menu.startNaming()
      focused(nameField)
      typeText("Probe 1")
      var menuRefusal = refuseTwice(menu)
      keyClick(Qt.Key_Escape)
      keysBack()
      var manageScroll = harness.find(manage, "manageScroll")
      body.openManageLists()
      focused(manage)
      manage.cursor = manage.choices.length - 1
      manage.showCursor()
      keyClick(Qt.Key_Return)
      focused(renameField)
      keyClick(Qt.Key_A, Qt.ControlModifier)
      typeText("Probe 1")
      var manageRefusal = refuseTwice(manage)
      body.closeListViews()
      harness.check("a refused name says why, editing clears the problem, and Escape leaves the field, in the list menu and Manage lists",
        menuRefusal === "true,true,true" && manageRefusal === "true,true,true",
        menuRefusal + " | " + manageRefusal)

      // A rename or a delete question pending in this window is about its
      // list, not its row: the popup moving that list meanwhile changes
      // nothing about which list DONE renames or Enter deletes.
      var listNames = function() { return service.lists.map(function(l) { return l.name }) }
      body.openManageLists()
      manage.startRenaming(listNames().indexOf("Probe 1"))
      focused(renameField)
      keyClick(Qt.Key_A, Qt.ControlModifier)
      typeText("Chips")
      // Moved far, past the bottom of this short view: the field follows it
      // into view.
      var rowInView = function() {
        var top = manage.cursor * manage.itemHeight
        return top >= manageScroll.contentY - 0.5 && top + manage.itemHeight <= manageScroll.contentY + manageScroll.height + 0.5
      }
      service.moveList("Probe 1", 6)
      var renameInView = within(1000, rowInView)
      var doneAt2 = center(harness.find(body, "manageDone"))
      mouseClick(body, doneAt2.x, doneAt2.y)
      var renamedRight = [renameInView, listNames().indexOf("Chips") === listNames().indexOf("Probe 7") + 1, listNames().indexOf("Probe 1") < 0].join(",")
      body.openManageLists()
      focused(manage)
      manage.askDelete(listNames().indexOf("Probe 3"))
      service.moveList("Probe 3", 6)
      var askInView = within(1000, rowInView)
      keyClick(Qt.Key_Return)
      var deletedRight = [askInView, listNames().indexOf("Probe 3") < 0, listNames().indexOf("Probe 4") > 0].join(",")
      body.closeListViews()
      harness.check("a pending rename or delete follows its own list into view after another surface moves it, and acts on it",
        renamedRight === "true,true,true" && deletedRight === "true,true,true", renamedRight + " | " + deletedRight)

      // Closing the surface keeps what was typed, as a click away does: a
      // rename is saved and a new list made; a refused one comes back, saying
      // why, as the surface opens again. Only Escape or CANCEL throws it away.
      var closeAndOpen = function() { app.close(); openWindow() }
      body.openManageLists()
      manage.startRenaming(listNames().indexOf("Probe 5"))
      focused(renameField)
      keyClick(Qt.Key_A, Qt.ControlModifier)
      typeText("Fives")
      closeAndOpen()
      var renameKept = [listNames().indexOf("Fives") > 0, listNames().indexOf("Probe 5") < 0, body.managingLists].join(",")
      body.openManageLists()
      manage.startRenaming(listNames().indexOf("Probe 6"))
      focused(renameField)
      keyClick(Qt.Key_A, Qt.ControlModifier)
      typeText("Probe 7")
      closeAndOpen()
      var renameBack = [body.managingLists, manage.renaming, manage.typedName, manage.problem, listNames().indexOf("Probe 6") > 0].join(",")
      focused(renameField)
      keyClick(Qt.Key_Escape)
      body.closeListViews()
      // A refused rename kept by a close comes back only to its own list:
      // deleted and made again under its name elsewhere, it is another list,
      // and the rename has nothing to act on.
      body.openManageLists()
      manage.startRenaming(listNames().indexOf("Probe 8"))
      focused(renameField)
      keyClick(Qt.Key_A, Qt.ControlModifier)
      typeText("Probe 9")
      app.close()
      service.deleteList("Probe 8")
      service.createList("Probe 8")
      openWindow()
      var replacedDropped = [body.managingLists, listNames().indexOf("Probe 8") > 0, listNames().indexOf("Probe 9") > 0].join(",")
      service.switchList("")
      keys.forceActiveFocus()
      keyClick(Qt.Key_L)
      focused(menu)
      menu.startNaming()
      focused(nameField)
      typeText("Fresh")
      closeAndOpen()
      var newKept = [service.listName, body.listMenuOpen, body.adding].join(",")
      keys.forceActiveFocus()
      keyClick(Qt.Key_L)
      focused(menu)
      menu.startNaming()
      focused(nameField)
      typeText("all")
      closeAndOpen()
      var newBack = [body.listMenuOpen, menu.naming, menu.typedName, menu.problem].join(",")
      focused(nameField)
      keyClick(Qt.Key_Escape)
      keyClick(Qt.Key_Escape)
      keysBack()
      harness.check("closing the window keeps a rename or a new list's name, a refused one comes back saying why, and only to its own list",
        renameKept === "true,true,false" && renameBack === "true,true,Probe 7,Probe 7 already exists,true"
          && replacedDropped === "false,true,true"
          && newKept === "Fresh,false,false" && newBack === "true,true,all,All already exists",
        [renameKept, renameBack, replacedDropped, newKept, newBack].join(" | "))
      service.switchList("")
      extra.concat(["Chips", "Fives", "Fresh"]).forEach(function(name) { service.deleteList(name) })

      // Each list comes back where this surface left it, at once and with no
      // slide; a list it has not shown yet starts at the top, and a rename
      // keeps the place. One row in sight, so three rows scroll.
      app.close()
      service.createList("Deep")
      service.library.slice(0, 3).forEach(function(s) { service.setMembership(s, "Deep", true) })
      service.switchList("")
      openWindow()
      var still = function() { return !wl.settling }
      // All from its top: the open brought the featured row into sight.
      wl.contentY = 0
      within(2000, still)
      keyClick(Qt.Key_Down)
      within(2000, still)
      var allRow = firstWhole(wl)
      switchByKeys("Deep")
      var deepFirst = [service.listName, firstWhole(wl)].join(":")
      keyClick(Qt.Key_Down)
      keyClick(Qt.Key_Down)
      within(2000, still)
      var deepAt = firstWhole(wl)
      var comeBack = function(name) {
        switchByKeys(name)
        within(2000, still)
        return [service.listName, firstWhole(wl)].join(":")
      }
      var backToAll = comeBack("")
      service.renameList("Deep", "Deeper")
      var backToDeep = comeBack("Deeper")
      harness.check("each list returns to its saved row, a renamed one too; a first visit starts at the top",
        allRow === 1 && deepAt === 2 && deepFirst === "Deep:0"
          && backToAll === ":" + allRow
          && backToDeep === "Deeper:" + deepAt,
        [allRow, deepAt, deepFirst, backToAll, backToDeep].join(" | "))
      service.switchList("")
      service.deleteList("Deeper")
      app.close()
      app.testWindow.implicitHeight = tallBefore
      openWindow()

      // A name being typed has the keys: Ctrl+Z, Ctrl+C, Delete, Backspace,
      // and l m s o edit it, as in any text field, and do nothing of
      // Stonks': no list switched, no sound, look, or order changed, no
      // scrub, no row removed, the removal before it not undone, no
      // screenshot. In the list menu's name field and Manage lists' rename.
      // Closed, the same Ctrl+Z and Ctrl+C act.
      service.createList("Keys")
      var inKeys = service.library[0]
      service.setMembership(inKeys, "Keys", true)
      service.removeSymbol(inKeys)
      app.camera = stubCamera
      var stonksState = function() {
        return JSON.stringify([service.listName, service.soundsOn, service.retro, service.order, service.reversed,
          body.scrubT, service.library, service.dataSettings.lists, stubCamera.shots])
      }
      var untouched = stonksState()
      var editField = function(field) {
        var seen = []
        typeText("Abc")
        keyClick(Qt.Key_Backspace)
        seen.push(field.text)
        keyClick(Qt.Key_Left)
        keyClick(Qt.Key_Delete)
        seen.push(field.text)
        typeText("lmso")
        seen.push(field.text)
        keyClick(Qt.Key_A, Qt.ControlModifier)
        keyClick(Qt.Key_C, Qt.ControlModifier)
        seen.push(field.text + ":" + field.selectedText)
        keyClick(Qt.Key_End)
        keyClick(Qt.Key_Z, Qt.ControlModifier)
        seen.push(field.text !== "Almso")
        // Time for a key that got past the field to act.
        wait(100)
        return seen.join(",")
      }
      keys.forceActiveFocus()
      keyClick(Qt.Key_L)
      focused(menu)
      for (var down = 0; down < 40 && menu.cursor !== menu.newIndex; down++) keyClick(Qt.Key_Down)
      keyClick(Qt.Key_Return)
      var namingKeys = menu.naming && focused(nameField)
      var inName = editField(nameField)
      var nameState = stonksState()
      keyClick(Qt.Key_Escape)
      keyClick(Qt.Key_Escape)
      keysBack()
      manageByKeys()
      keyClick(Qt.Key_Return)
      var renamingNow = manage.renaming && focused(renameField)
      var inRename = editField(renameField)
      var renameState = stonksState()
      keyClick(Qt.Key_Escape)
      keyClick(Qt.Key_Escape)
      keysBack()
      var closedViews = !body.listMenuOpen && !body.managingLists
      keyClick(Qt.Key_Z, Qt.ControlModifier)
      var undoneAfter = holds("Keys", inKeys)
      keyClick(Qt.Key_C, Qt.ControlModifier)
      within(3000, function() { return stubCamera.shots === 1 })
      harness.check("in the list menu's name field and Manage lists' rename, Ctrl+Z, Ctrl+C, Delete, Backspace, and l m s o edit the text and do nothing of Stonks'; closed, Ctrl+Z and Ctrl+C act",
        namingKeys && renamingNow && inName === "Ab,A,Almso,Almso:Almso,true" && inRename === inName
          && nameState === untouched && renameState === untouched
          && closedViews && undoneAfter && stubCamera.shots === 1,
        [namingKeys, renamingNow, inName, inRename, nameState === untouched ? "same" : untouched + " -> " + nameState,
          renameState === untouched ? "same" : renameState, closedViews, undoneAfter, stubCamera.shots].join(" | "))
      app.camera = null
      service.switchList("")
      service.deleteList("Keys")

      // The sign at the end of the list's header says the rows' unit, and a
      // click on it steps every row to the next, as c does. Sorted by %
      // change, the rows rank by the percent they show, from the open since
      // the open; amounts can't be ranked across currencies, so with amounts
      // showing the rows stay in percent order. Of three rows, the first
      // leads from the close, the second by the amount, and the third from
      // the open. The popup's header is the same StonksBody's.
      var plain = service.testFeed.quotes
      var moved = Object.assign({}, plain)
      var three = service.library.slice(0, 3)
      ;[[100, 110, 109], [1000, 1050, 1000], [100, 102, 95]].forEach(function(m, i) {
        moved[three[i]] = Object.assign({}, plain[three[i]], { prevClose: m[0], price: m[1], dayOpen: m[2] })
      })
      service.testFeed.quotes = moved
      var orderWas = service.order
      service.setOrder("pct")
      tryVerify(function() { return service.order === "pct" && !service.reversed }, 2000)
      var fromClose = three.join(",")
      var wants = {
        abs: { says: function(l) { return l.indexOf("%") < 0 }, order: fromClose },
        open: { says: function(l) { return /% open$/.test(l) }, order: three.slice().reverse().join(",") },
        pct: { says: function(l) { return /%$/.test(l) }, order: fromClose }
      }
      var target = harness.find(body, "unitTarget")
      var faults = []
      mouseMove(body, 1, 1)
      ;["abs", "open", "pct"].forEach(function(mode) {
        mouseClick(target, target.width / 2, target.height / 2)
        within(2000, function() { return service.changeMode === mode })
        var shown = wl.displayedSymbols
        var rows = shown.map(function(s) { return wl.rowItem(s).view })
        var lines = three.map(function(s) { return wl.rowItem(s).view.changeLine })
        // Each row's percent, as it shows it, no greater than the one above.
        var ranked = rows.every(function(v, i) {
          return i === 0 || v.pct === null || rows[i - 1].pct !== null && rows[i - 1].pct >= v.pct
        })
        var threeShown = shown.filter(function(s) { return three.indexOf(s) >= 0 }).join(",")
        if (service.changeMode !== mode || !lines.every(wants[mode].says) || !ranked || threeShown !== wants[mode].order)
          faults.push(service.changeMode + " for " + mode + ": " + lines.join(" ") + " | " + shown.join(","))
      })
      harness.check("a click on the list header's sign steps every row through percent, amount, and since the open, sorted by the percent each shows",
        faults.length === 0, faults.join("; "))
      service.setOrder(orderWas)
      service.testFeed.quotes = plain

      // A stock's lists open in the window, and the stock removed in the
      // popup: the window's lists close, as they do when the window removes
      // it, since nothing is left to tick.
      var away = service.library[service.library.length - 1]
      body.openSymbolLists(away)
      tryVerify(function() { return body.listsSymbol === away }, 2000)
      panel.open()
      tryVerify(function() { return !!panel.testBody && panel.testBody.surfaceOpen }, 3000)
      panel.testBody.removeRow(away)
      panel.close()
      var closedThere = within(2000, function() {
        return body.listsSymbol === "" && !checklist.visible
      })
      harness.check("a stock removed in the popup closes its lists in the window",
        closedThere && service.library.indexOf(away) < 0, away + " | " + JSON.stringify(body.listsSymbol))
      service.undoRemoval(away)
      tryVerify(function() { return service.library.indexOf(away) >= 0 }, 3000)
      app.close()

      harness.finish()
    }
  }
}
