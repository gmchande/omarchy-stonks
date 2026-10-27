import QtQuick
import QtQuick.Controls
import QtTest
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import "plugin/Chart.js" as Chart
import "plugin/Quote.js" as Quote
import "plugin/Settings.js" as Settings
import "plugin"

// StonksBody under a real offscreen pointer and wheel, on a stub service:
// the cases real data cannot set up. Nothing is mapped into the running shell.
Harness {
  id: root
  marker: "POINTER DONE"

  FileView {
    id: watchlistFixture
    path: Quickshell.env("STONKS_WATCHLIST_FIXTURE")
    blockLoading: true
  }

  function quote(symbol, price, previous) {
    return {
      symbol: symbol,
      name: "Sample " + symbol,
      currency: "USD",
      exchange: "NASDAQ",
      timezoneName: "America/New_York",
      gmtoffset: -14400,
      instrumentType: "EQUITY",
      crypto: false,
      price: price,
      prevClose: previous,
      marketTime: stub.now,
      dayHigh: Math.max(price, previous) + 1,
      dayLow: Math.min(price, previous) - 1,
      volume: 100,
      session: {
        pre: { start: stub.now - 25200, end: stub.now - 19800 },
        regular: { start: stub.now - 19800, end: stub.now + 3600 },
        post: { start: stub.now + 3600, end: stub.now + 18000 }
      },
      points: [
        { t: stub.now - 19800, p: previous },
        { t: stub.now - 300, p: price }
      ]
    }
  }

  function symbols(count) {
    var result = []
    for (var i = 0; i < count; i++) result.push("S" + String(i).padStart(2, "0"))
    return result
  }

  function setQuotes(symbols, values) {
    var nextQuotes = {}
    var nextEntries = {}
    for (var i = 0; i < symbols.length; i++) {
      nextQuotes[symbols[i]] = root.quote(symbols[i], values[i], 100)
      nextEntries[symbols[i]] = { status: "ok", receivedAt: stub.now }
    }
    stub.symbols = symbols.slice()
    stub.quotes = nextQuotes
    stub.entries = nextEntries
    stub.shown = Settings.sortedSymbols(stub.symbols, stub.quotes, stub.order, stub.reversed)
    stub.featuredSymbol = symbols[0]
  }

  function setFixtureWatchlist() {
    var fixture = JSON.parse(watchlistFixture.text())
    var nextSymbols = []
    var nextQuotes = {}
    var nextEntries = {}
    for (var i = 0; i < fixture.quotes.length; i++) {
      var item = fixture.quotes[i]
      var parsed = item.response ? Quote.parseChart(item.response) : null
      var symbol = parsed ? parsed.symbol : item.symbol
      nextSymbols.push(symbol)
      if (parsed) nextQuotes[symbol] = parsed
      nextEntries[symbol] = { status: item.status, receivedAt: item.status === "ok" ? fixture.now : 0 }
    }
    stub.now = fixture.now
    stub.order = "manual"
    stub.reversed = false
    stub.symbols = nextSymbols
    stub.quotes = nextQuotes
    stub.entries = nextEntries
    stub.shown = nextSymbols.slice()
    stub.featuredSymbol = "MZ"
  }

  QtObject {
    id: stub
    property var symbols: []
    property var shown: []
    property var library: symbols
    property string listName: ""
    property var lists: [{ name: "", label: "All", count: symbols.length, symbols: symbols }]
    property var quotes: ({})
    property var entries: ({})
    property var calendars: null
    property string featuredSymbol: ""
    property string order: "pct"
    property bool reversed: false
    property string changeMode: "pct"
    property int now: 1789669200
    property var owed: ({})
    property string range: "1D"
    property var histories: ({})
    property var fundamentals: ({})
    property var arriving: []
    property var lastRemoval: null
    readonly property var view: ({ featured: featuredSymbol, range: range, list: listName, listKey: "=" + listName,
      order: order, reversed: reversed, rows: symbols.filter(function(s) { return arriving.indexOf(s) < 0 }),
      shown: shown.filter(function(s) { return arriving.indexOf(s) < 0 }), library: library,
      chart: Chart.viewChart(featuredSymbol, range, quotes, entries, histories) })
    property bool retro: false
    property color foreground: "#cacccc"
    property color upColor: "#7aa2f7"
    property color downColor: "#a55555"
    property string fontFamily: Style.font.family
    property var lastSettings: null
    function persist(values) { lastSettings = values }
    function setRange(value) { range = value }
    function screensClear() { return true }
    function surfaceShown(surface, open) {}
    function rowsSeen(surface, symbols) {}
    // A search's choice shown on the hero; this stub's hero never changes.
    readonly property var previewView: view
    readonly property var previewEntries: ({})
    property var previewSurface: null
    function preview(surface, symbol) {}
    function feature(symbol) { featuredSymbol = symbol }
    function removeSymbol(symbol) {
      var before = { symbols: symbols, lists: [] }
      var next = symbols.filter(function(value) { return value !== symbol })
      symbols = next
      shown = Settings.sortedSymbols(next, quotes, order, reversed)
      if (featuredSymbol === symbol) featuredSymbol = next[0] || ""
      lastRemoval = { symbol: symbol, before: before }
    }
    function setManualOrder(next) { symbols = next.slice(); shown = next.slice(); order = "manual" }
    function addSymbol(symbol) {
      var upper = String(symbol || "").toUpperCase()
      var next = symbols.slice()
      if (next.indexOf(upper) < 0) {
        next.push(upper)
        arriving = arriving.concat([upper])
      }
      symbols = next
      shown = Settings.sortedSymbols(next, quotes, order, reversed)
    }
    function setOrder(value) {
      order = value
      shown = Settings.sortedSymbols(symbols, quotes, order, reversed)
      lastSettings = { order: value }
    }
    function reverseOrder() {
      reversed = !reversed
      shown = Settings.sortedSymbols(symbols, quotes, order, reversed)
      lastSettings = { reversed: reversed }
    }
    property var memberships: []
    function setMembership(symbol, name, member) { memberships = memberships.concat([symbol + "|" + name + "|" + member]) }
    function switchList(name) {}
    function createList(name) { return "" }
  }

  FloatingWindow {
    id: window
    visible: true
    color: "#101315"
    implicitWidth: 480
    implicitHeight: 788

    StonksBody {
      id: body
      anchors.fill: parent
      anchors.margins: Style.space(16)
      service: stub
      foreground: stub.foreground
      upColor: stub.upColor
      downColor: stub.downColor
      fontFamily: stub.fontFamily
      surfaceOpen: true
      chartHeight: Style.space(190)
      rangeOptions: ["1D", "1Y"]
    }

    Steps {
      name: "Pointer"
      when: window.visible

      // A click on the open row menu's line `index`, where its words are.
      function takeMenuLine(index) {
        var line = root.findAll(body, "rowMenuLine")[index]
        if (line) mouseClick(line, Style.space(20), line.height / 2)
      }

      function firstWhole(watchlist) {
        for (var i = 0; i < watchlist.displayedSymbols.length; i++)
          if (watchlist.wholeInSight(i, watchlist.contentY)) return i
        return -1
      }

      function test_owner_flows() {
        // The rows have stopped: no glide, no drag, every row in its place.
        var rowsAtRest = function() {
          var list = body.watchlist
          return !list.settling && list.dragSymbol === ""
            && list.displayedSymbols.every(function(s) { return list.rowResting(s) })
        }
        // The fixture's rows, laid out and resting.
        var fixture = function() {
          root.setFixtureWatchlist()
          within(3000, function() {
            return (body.watchlist.sortHeld || body.watchlist.displayedSymbols.join() === stub.shown.join()) && rowsAtRest()
          })
        }
        stub.setOrder("pct")
        root.setQuotes(["UP", "DOWN", "DEEP"], [110, 95, 90])

        // The wheel over a token walks the ranges, the way it does between
        // them: a notch down is the next, longer range. The pointer rests on
        // the token first, the way a hand reaches for it.
        var rangeRow = root.find(body, "rangeRow")
        var tokens = root.findAll(rangeRow, "rangeToken")
        var second = tokens[1].mapToItem(body, tokens[1].width / 2, tokens[1].height / 2)
        mouseMove(body, second.x, second.y)
        var first = tokens[0].mapToItem(body, tokens[0].width / 2, tokens[0].height / 2)
        mouseMove(body, first.x, first.y)
        mouseWheel(body, first.x, first.y, 0, -120, Qt.NoModifier)
        root.check("a wheel notch down over a hovered range token steps to the next range",
          within(1000, function() { return body.range === "1Y" }))
        mouseWheel(body, first.x, first.y, 0, 120, Qt.NoModifier)
        root.check("a wheel notch up over a hovered range token steps back",
          within(1000, function() { return body.range === "1D" }))
        mouseMove(body, body.width / 2, body.height - 4)

        // The header's marks are as easy to hit as the row they sit in.
        var helpMark = root.find(body, "helpMark")
        var beside = helpMark.mapToItem(body, helpMark.width + 8, helpMark.height / 2)
        mouseClick(body, beside.x, beside.y)
        root.check("a click beside the help mark opens the sheet", within(1000, function() { return body.showingHelp }))
        mouseClick(body, beside.x, beside.y)
        root.check("and closes it again", within(1000, function() { return !body.showingHelp }))
        var icon = root.find(body, "lookIcon")
        var toggle = root.find(body, "lookToggle")
        var onIcon = icon.mapToItem(body, icon.width / 2, icon.height / 2)
        var underIcon = toggle.mapToItem(body, toggle.width / 2, toggle.height - 2)
        stub.lastSettings = null
        mouseClick(body, underIcon.x, underIcon.y)
        var picked = stub.lastSettings ? stub.lastSettings.style : ""
        stub.retro = true
        stub.lastSettings = null
        mouseClick(body, onIcon.x, onIcon.y)
        var back = stub.lastSettings ? stub.lastSettings.style : ""
        stub.retro = false
        root.check("a click on or under the look icon changes the look", picked === "retro" && back === "smooth")
        mouseMove(body, body.width / 2, body.height - 4)

        // The fixture's last print is five minutes old; the axis runs on to
        // the bell, an hour off.
        var lastPrint = stub.now - 300
        body.motion.scrubTo(1)
        root.check("hover scrubbing stops at the last print", body.scrubT === lastPrint)
        body.motion.scrubT = 0

        // Rows under the pointer hold their order as quotes re-sort them;
        // leaving applies the newest sort.
        mouseMove(body.watchlist, 12, 12)
        within(1000, function() { return body.watchlist.sortHeld })
        root.setQuotes(["UP", "DOWN", "DEEP"], [90, 95, 120])
        mouseMove(body, body.width / 2, 20)
        root.check("leaving applies the newest sort once", within(2000, function() {
          return !body.watchlist.sortHeld && body.watchlist.displayedSymbols.join(",") === "DEEP,DOWN,UP"
        }))

        var fifteen = root.symbols(15)
        var values = []
        for (var i = 0; i < fifteen.length; i++) values.push(100 + i)
        stub.order = "pct"
        root.setQuotes(fifteen, values)
        within(2000, function() { return body.watchlist.displayedSymbols.length === 15 && rowsAtRest() })

        body.watchlist.contentY = 0
        // The pointer comes in as a hand's does, over more than one place:
        // the first place it is seen at in a list is where it starts.
        mouseMove(body.watchlist, 12, body.watchlist.rowPitch + 6)
        mouseMove(body.watchlist, 12, body.watchlist.rowPitch + 12)
        within(1000, function() { return body.watchlist.sortHeld })
        // A search's choice, accepted through the same pointer path as a
        // real search, then its first answer, as the service's fetch would
        // bring it, up 100%, which sorts it first. With the pointer still
        // over the rows it joins there, is selected there, and stays when
        // the pointer leaves.
        body.startAdding()
        body.search.results = [{ symbol: "NEW", name: "New result", exchange: "NASDAQ" }]
        body.search.answer = "results"
        within(1000, function() { return root.findAll(body.search, "searchResult").length === 1 })
        var newResult = root.findAll(body.search, "searchResult")[0]
        mouseClick(newResult, newResult.width / 2, newResult.height / 2)
        mouseMove(body.watchlist, 12, body.watchlist.rowPitch + 6)
        mouseMove(body.watchlist, 12, body.watchlist.rowPitch + 12)
        tryVerify(function() { return body.watchlist.rowItem("NEW") !== null }, 1000)
        var addedRow = body.watchlist.rowItem("NEW")
        stub.quotes = Object.assign({}, stub.quotes, { NEW: root.quote("NEW", 200, 100) })
        stub.entries = Object.assign({}, stub.entries, { NEW: { status: "ok", receivedAt: stub.now } })
        stub.shown = Settings.sortedSymbols(stub.symbols, stub.quotes, stub.order, stub.reversed)
        stub.arriving = []
        within(2000, function() { return body.watchlist.cursorSymbol === "NEW" && rowsAtRest() })
        var landedAt = body.watchlist.displayedSymbols.indexOf("NEW")
        root.check("pointer-held sorted add joins at its sorted place, selected and in view",
          body.watchlist.sortHeld && landedAt === stub.shown.indexOf("NEW") && landedAt < 14
            && body.watchlist.cursorSymbol === "NEW"
            && addedRow.y >= body.watchlist.contentY
            && addedRow.y + addedRow.height <= body.watchlist.contentY + body.watchlist.height)

        mouseMove(body, body.width / 2, 20)
        within(2000, function() { return !body.watchlist.sortHeld && rowsAtRest() })
        root.check("and the added row stays there once the pointer leaves",
          !body.watchlist.sortHeld && body.watchlist.displayedSymbols.indexOf("NEW") === landedAt)

        fixture()
        body.watchlist.contentY = 0
        var wheelRow = body.watchlist.rowItem(body.watchlist.displayedSymbols[2])

        // A high-resolution wheel sends many small ticks per notch. Each
        // moves its fraction of a row, and the list settles on a boundary
        // once they stop, not on every tick; a short touchpad stroke settles
        // the same way.
        var pitch = body.watchlist.rowPitch
        within(2000, rowsAtRest)
        mouseWheel(wheelRow, wheelRow.width / 2, wheelRow.height / 2,
          0, -30, Qt.NoModifier)
        within(2000, function() { return !body.watchlist.settling })
        var tickInReach = firstWhole(body.watchlist) === 0
        body.watchlist.contentY = 0
        body.watchlist.followBy(15)
        within(2000, function() { return !body.watchlist.settling })
        root.check("a high-resolution tick leaves the first row in reach", tickInReach && firstWhole(body.watchlist) === 0)
        body.watchlist.contentY = 0
        within(2000, rowsAtRest)
        for (var tick = 0; tick < 4; tick++) {
          mouseWheel(wheelRow, wheelRow.width / 2, wheelRow.height / 2,
            0, -30, Qt.NoModifier)
          wait(30) // ticks a hand's wheel apart
        }
        within(2000, function() { return !body.watchlist.settling })
        root.check("four high-resolution ticks add up to one row",
          firstWhole(body.watchlist) === 1)

        // A row lifted mid-glide takes the list over: neither the glide nor
        // the wheel's pending settle moves the list under it.
        body.watchlist.wheelBy(0.3)
        wait(40) // into the glide
        var lifted = body.watchlist.displayedSymbols[2]
        body.watchlist.beginDrag(lifted, 2 * pitch + 10)
        var heldAt = firstWhole(body.watchlist)
        wait(500) // the glide and the settle's quiet, which must not move it
        root.check("lifting a row stops the wheel's glide and its settle",
          body.watchlist.dragSymbol === lifted && firstWhole(body.watchlist) === heldAt)
        body.watchlist.cancelDrag()
        body.watchlist.snapToRow()

        // A held row keeps the cursor while the wheel scrolls the list under
        // it, and once it drops: it rides the pointer wherever its old place
        // went.
        body.watchlist.contentY = 0
        within(2000, rowsAtRest)
        var held = body.watchlist.displayedSymbols[1]
        body.watchlist.beginDrag(held, pitch + 10)
        mouseWheel(body.watchlist, 12, pitch + 10, 0, -600, Qt.NoModifier)
        within(2000, function() { return body.watchlist.contentY >= 4 * pitch && !body.watchlist.settling })
        var heldScrolled = [body.watchlist.cursorRow === held, body.watchlist.contentY >= 4 * pitch].join(",")
        body.watchlist.endDrag()
        within(2000, function() { return body.watchlist.dragSymbol === "" && !body.watchlist.settling })
        root.check("a held row keeps the cursor while the wheel scrolls the list under it, and once it drops",
          heldScrolled === "true,true" && body.watchlist.dragSymbol === "" && body.watchlist.cursorRow === held,
          heldScrolled + " | " + body.watchlist.cursorRow + " for " + held)
        fixture()

        // A click mid-glide puts the cursor on the row it acts on, so x then
        // removes that row.
        var clickedThenX = function() {
          body.watchlist.contentY = 0
          within(2000, rowsAtRest)
          var target = body.watchlist.displayedSymbols[0]
          mouseMove(body.watchlist, 12, 10)
          mouseMove(body.watchlist, 12, 12)
          mouseWheel(body.watchlist, 12, 12, 0, -120, Qt.NoModifier)
          mouseClick(body.watchlist, 12, 12)
          var acted = stub.featuredSymbol === target
          within(2000, function() { return !body.watchlist.settling })
          var cursor = body.watchlist.cursorRow
          body.removeRow(cursor)
          within(2000, rowsAtRest)
          var removedIt = body.watchlist.displayedSymbols.indexOf(target) < 0
          fixture()
          return (acted && cursor === target && removedIt) + " " + target + " cursor " + cursor
        }
        var byClick = clickedThenX()
        root.check("a click or a Ctrl-click mid-glide puts the cursor on its row, and x then removes that row",
          /^true /.test(byClick), byClick)

        // A double-click is one click for the list, not only for a row: its
        // second press, at the first one's place, does nothing, whichever
        // row is under it by then. And a click stops the list where it is,
        // so its row stays under the pointer.
        body.watchlist.contentY = 0
        within(2000, rowsAtRest)
        var featuredSeen = []
        var noteFeatured = function() { featuredSeen.push(stub.featuredSymbol) }
        stub.featuredSymbolChanged.connect(noteFeatured)
        body.watchlist.followBy(17)
        var partRow = body.watchlist.displayedSymbols[1]
        var partY = pitch + 2 - 17
        mouseMove(body.watchlist, 12, partY - 6)
        mouseMove(body.watchlist, 12, partY)
        mouseClick(body.watchlist, 12, partY)
        wait(200) // inside the double-click interval
        mouseClick(body.watchlist, 12, partY)
        within(2000, function() { return !body.watchlist.settling })
        stub.featuredSymbolChanged.disconnect(noteFeatured)
        var featuredOnce = featuredSeen.length > 0 && featuredSeen.every(function(s) { return s === partRow })
          && stub.featuredSymbol === partRow && body.watchlist.cursorRow === partRow
        var stayedFeatured = body.watchlist.contentY === 17
        fixture()
        body.watchlist.contentY = 0
        within(2000, rowsAtRest)
        // Off a row boundary too: a right double-click opens the row's menu
        // once, its second press no click off it, and the removal it takes
        // hands the cursor on, the list staying where the click stopped it.
        body.watchlist.followBy(17)
        var shownBefore = body.watchlist.displayedSymbols.slice()
        var thirdY = 2 * pitch + 20 - 17
        mouseMove(body.watchlist, 12, thirdY - 6)
        mouseMove(body.watchlist, 12, thirdY)
        mouseClick(body.watchlist, 12, thirdY, Qt.RightButton)
        wait(200) // inside the double-click interval
        mouseClick(body.watchlist, 12, thirdY, Qt.RightButton)
        within(1000, function() { return body.rowMenu !== null })
        var menuStayed = body.rowMenu !== null && body.rowMenu.symbol === shownBefore[2]
        takeMenuLine(0)
        within(2000, function() { return body.rowMenu === null && rowsAtRest() })
        var shownAfter = body.watchlist.displayedSymbols
        var removedOnce = shownAfter.length === shownBefore.length - 1
          && shownAfter.indexOf(shownBefore[2]) < 0 && shownAfter.indexOf(shownBefore[3]) >= 0
          && body.watchlist.cursorRow === shownBefore[3]
        var stayedRemoved = body.watchlist.contentY === 17
        root.check("a double-click on a part-scrolled row features only that row, and a right double-click opens its menu once, which removes one row, the list staying where the click stopped it",
          featuredOnce && menuStayed && removedOnce && stayedFeatured && stayedRemoved,
          featuredSeen.join(",") + " for " + partRow + " | menu " + menuStayed + " | " + shownBefore.length + " -> " + shownAfter.length
            + " cursor " + body.watchlist.cursorRow + " | stayed " + stayedFeatured + "," + stayedRemoved)
        fixture()

        // The wheel or a key between two clicks at one place makes them two
        // clicks, even when Qt takes the second for a double-click's: the
        // second stops the list and acts, and x then removes its row. So does
        // a row's move by Shift+J.
        var between = function(interrupt) {
          body.watchlist.contentY = 0
          within(2000, rowsAtRest)
          stub.featuredSymbol = body.watchlist.displayedSymbols[5]
          var target = body.watchlist.displayedSymbols[2]
          var y = 2 * pitch + 20
          mouseMove(body.watchlist, 12, y - 6)
          mouseMove(body.watchlist, 12, y)
          var once = function() {
            stub.featuredSymbolChanged.disconnect(once)
            interrupt(y)
          }
          stub.featuredSymbolChanged.connect(once)
          mouseDoubleClickSequence(body.watchlist, 12, y)
          within(2000, function() { return !body.watchlist.settling })
          var cursor = body.watchlist.cursorRow
          body.removeRow(cursor)
          within(2000, rowsAtRest)
          var removedIt = body.watchlist.displayedSymbols.indexOf(target) < 0
          fixture()
          return (cursor === target && removedIt) + " " + cursor + " for " + target
        }
        var afterWheel = between(function(y) { mouseWheel(body.watchlist, 12, y, 0, -120, Qt.NoModifier) })
        var afterKey = between(function() { body.moveCursor(1) })
        body.watchlist.contentY = 0
        within(2000, rowsAtRest)
        stub.featuredSymbol = body.watchlist.displayedSymbols[5]
        var takenPlace = body.watchlist.displayedSymbols[3]
        var moveY = 2 * pitch + 20
        mouseMove(body.watchlist, 12, moveY - 6)
        mouseMove(body.watchlist, 12, moveY)
        mouseClick(body.watchlist, 12, moveY)
        body.moveSelected(1)
        wait(180) // inside the double-click interval
        mouseClick(body.watchlist, 12, moveY)
        within(2000, function() { return !body.watchlist.settling })
        var afterMove = (body.watchlist.displayedSymbols[2] === takenPlace && stub.featuredSymbol === takenPlace
          && body.watchlist.cursorRow === takenPlace) + " " + stub.featuredSymbol + "/" + body.watchlist.cursorRow + " for " + takenPlace
        fixture()
        root.check("the wheel, a key, or Shift+J between two clicks at one place makes the second act, a double-click's too",
          [afterWheel, afterKey, afterMove].every(function(r) { return /^true /.test(r) }),
          [afterWheel, afterKey, afterMove].join(" | "))

        // A double-click whose first press is a view's, its second landing on
        // a row, does nothing there, even soon after a row click and the
        // wheel, or with the wheel between its presses: on Manage lists' DONE
        // as the rows come back, and outside the list menu, which dismisses
        // it over rows that stay. Each press waits for the rows it aims at to
        // rest, so it lands where it reads them.
        var throughView = function(open, pressAt, closedSignal, wheelBetween) {
          body.watchlist.contentY = 0
          within(3000, rowsAtRest)
          stub.featuredSymbol = body.watchlist.displayedSymbols[5]
          var row = body.watchlist.displayedSymbols[4]
          var rowY = 4 * pitch + 20
          mouseMove(body.watchlist, 12, rowY - 6)
          mouseMove(body.watchlist, 12, rowY)
          mouseClick(body.watchlist, 12, rowY)
          if (!wheelBetween) mouseWheel(body.watchlist, 12, rowY, 0, -120, Qt.NoModifier)
          open()
          // The view is open over rows that have stopped moving, so the
          // press lands where pressAt reads it.
          within(1000, function() {
            return (body.managingLists || body.listMenuOpen)
              && body.watchlist.displayedSymbols.every(function(s) { return body.watchlist.rowResting(s) })
          })
          var at = pressAt()
          var once = function() {
            closedSignal.disconnect(once)
            mouseWheel(body, at.x, at.y, 0, -120, Qt.NoModifier)
          }
          if (wheelBetween) closedSignal.connect(once)
          mouseDoubleClickSequence(body, at.x, at.y)
          within(1000, function() { return !body.managingLists && !body.listMenuOpen })
          // Nothing under the second press acted: no row featured, and the
          // order word above the rows kept its order.
          var result = (stub.featuredSymbol === row && !body.managingLists && !body.listMenuOpen && stub.order === "manual")
            + " " + stub.featuredSymbol + " for " + row + ", " + stub.order
          fixture()
          return result
        }
        var onDone = function() {
          var done = root.find(body, "manageDone")
          return done.mapToItem(body, done.width / 2, done.height / 2)
        }
        var offMenu = function() {
          var first = body.watchlist.rowItem(body.watchlist.displayedSymbols[0])
          return first.mapToItem(body, first.width - 30, first.height / 2)
        }
        var views = [
          throughView(function() { body.openManageLists() }, onDone, body.managingListsChanged, false),
          throughView(function() { body.openManageLists() }, onDone, body.managingListsChanged, true),
          throughView(function() { body.openListMenu() }, offMenu, body.listMenuOpenChanged, false),
          throughView(function() { body.openListMenu() }, offMenu, body.listMenuOpenChanged, true)
        ]
        root.check("a double-click that begins on a view, Manage lists' DONE or off the list menu, features no row under its second press",
          views.every(function(v) { return /^true /.test(v) }), views.join(" | "))

        // The rows coming back from behind a view, under a pointer that
        // moved while the view was open: the first report is where it rests,
        // and one a pixel off is no move.
        body.watchlist.contentY = 0
        within(2000, rowsAtRest)
        var sheetFirst = body.watchlist.rowItem(body.watchlist.displayedSymbols[0])
        mouseMove(sheetFirst, sheetFirst.width / 2, sheetFirst.height / 2 + pitch)
        mouseMove(sheetFirst, sheetFirst.width / 2, sheetFirst.height / 2)
        within(1000, function() { return body.watchlist.cursorRow === body.watchlist.displayedSymbols[0] })
        body.moveCursor(1)
        within(1000, function() { return body.watchlist.cursorRow === body.watchlist.displayedSymbols[1] })
        var viewKeyed = body.watchlist.cursorRow
        body.openManageLists()
        within(1000, function() { return body.managingLists })
        waitForRendering(body)
        mouseMove(sheetFirst, sheetFirst.width / 2 - 20, sheetFirst.height / 2 + 3 * pitch)
        mouseMove(sheetFirst, sheetFirst.width / 2, sheetFirst.height / 2 + 3 * pitch)
        body.closeListViews()
        within(2000, function() { return !body.managingLists && rowsAtRest() })
        // Drawn, so Qt has reported the still pointer to the rows again.
        waitForRendering(body)
        mouseMove(sheetFirst, sheetFirst.width / 2, sheetFirst.height / 2 + 3 * pitch + 1)
        var viewKept = body.watchlist.cursorRow
        // And a small real move after the rows come back counts: from the
        // last few pixels of a row, a few pixels onto the next one take the
        // cursor.
        mouseMove(sheetFirst, sheetFirst.width / 2, sheetFirst.height + 20)
        mouseMove(sheetFirst, sheetFirst.width / 2, sheetFirst.height - 3)
        body.moveCursor(1)
        body.moveCursor(1)
        within(1000, function() { return body.watchlist.cursorRow === body.watchlist.displayedSymbols[2] })
        var smallKeyed = body.watchlist.cursorRow
        body.toggleHelp()
        within(1000, function() { return body.showingHelp })
        // Drawn over the rows, so Qt takes the pointer off them.
        waitForRendering(body)
        body.toggleHelp()
        within(2000, function() { return !body.showingHelp && rowsAtRest() })
        waitForRendering(body)
        mouseMove(sheetFirst, sheetFirst.width / 2, sheetFirst.height + 3)
        within(1000, function() { return body.watchlist.cursorRow === body.watchlist.displayedSymbols[1] })
        root.check("rows back from behind a view keep the cursor under a pointer moved meanwhile, and a few pixels onto the next row take it",
          viewKept === viewKeyed && viewKeyed === body.watchlist.displayedSymbols[1]
            && smallKeyed === body.watchlist.displayedSymbols[2] && body.watchlist.cursorRow === body.watchlist.displayedSymbols[1],
          viewKeyed + " -> " + viewKept + " | " + smallKeyed + " -> " + body.watchlist.cursorRow)

        // The surface made shorter until the cursor's row would be below the
        // fold keeps a cursor of your own: the list scrolls to keep its row
        // whole in sight, under the key sheet, and mid a key's glide toward
        // a row below the fold.
        mouseMove(body, body.width / 2, 20)
        var rowsInView = Math.floor((body.watchlist.height + body.watchlist.rowGap) / pitch)
        var bodyHeight = body.height
        var shrinkKeeps = function(row, underSheet, midGlide) {
          body.watchlist.contentY = 0
          within(2000, rowsAtRest)
          body.watchlist.select(row)
          var gliding = body.watchlist.settling
          if (underSheet) body.toggleHelp()
          if (!midGlide) within(2000, function() { return !body.watchlist.settling })
          body.anchors.fill = undefined
          body.height = body.chromeHeight + pitch - body.watchlist.rowGap
          var w = body.watchlist
          var said = function() {
            return w.cursorSymbol + "," + w.cursorRow + "," + w.wholeInSight(w.displayedSymbols.indexOf(row), w.headedY)
              + (midGlide && !gliding ? ",no glide" : "")
          }
          within(1000, function() { return said() === row + "," + row + ",true" })
          var result = said()
          body.anchors.fill = body.parent
          within(2000, function() { return body.height === bodyHeight && !body.watchlist.settling })
          if (underSheet) body.toggleHelp()
          return result
        }
        var lowRow = body.watchlist.displayedSymbols[rowsInView - 1]
        var pastRow = body.watchlist.displayedSymbols[rowsInView]
        var shrunk = [shrinkKeeps(lowRow, true, false), shrinkKeeps(pastRow, false, true)]
        root.check("the surface made shorter keeps a cursor of your own whole in sight, the rows showing, under the key sheet, and mid a key's glide",
          rowsInView > 1 && shrunk[0] === lowRow + "," + lowRow + ",true"
            && shrunk[1] === pastRow + "," + pastRow + ",true",
          shrunk.join(" | "))
        // And when the sight shrinks a moment before the list's own height
        // does: the scroll is bounded by the sight.
        var w2 = body.watchlist
        var lastRow = w2.displayedSymbols[w2.displayedSymbols.length - 1]
        w2.select(lastRow)
        tryVerify(function() { return !w2.settling }, 2000)
        w2.sightHeight = pitch - w2.rowGap
        var sightFirst = w2.cursorSymbol + "," + w2.wholeInSight(w2.displayedSymbols.indexOf(lastRow), w2.headedY)
        w2.sightHeight = Qt.binding(function() { return body.rowsSightHeight })
        w2.contentY = 0
        within(2000, rowsAtRest)
        root.check("a sight that shrinks before the list's height still keeps a cursor of your own on the last row whole in sight",
          sightFirst === lastRow + ",true", lastRow + " -> " + sightFirst)

        body.watchlist.cursorSymbol = ""
        mouseMove(body, body.width / 2, 20)

        // One cursor, as the shell's own panels have it: the pointer puts it
        // on the row under it; a wheel notch with the pointer still leaves
        // it, once the glide rests, on the row then under the pointer, never
        // the first row in sight; ↓ moves it on from there; the pointer
        // leaving the list leaves it.
        var wl = body.watchlist
        wl.contentY = 0
        within(2000, rowsAtRest)
        var third = wl.rowItem(wl.displayedSymbols[2])
        mouseMove(third, third.width / 2, third.height / 2 - 6)
        mouseMove(third, third.width / 2, third.height / 2)
        within(1000, function() { return wl.cursorRow === wl.displayedSymbols[2] })
        var onThird = [wl.cursorRow === wl.displayedSymbols[2]]
        mouseWheel(third, third.width / 2, third.height / 2, 0, -120, Qt.NoModifier)
        // At once, before the glide: the row that will rest under the pointer.
        var atOnce = wl.cursorRow === wl.displayedSymbols[3]
        within(2000, function() { return !wl.settling })
        var afterWheel = [atOnce, firstWhole(wl) === 1, wl.cursorRow === wl.displayedSymbols[3], wl.cursorRow !== wl.displayedSymbols[1]]
        body.moveCursor(1)
        within(2000, function() { return wl.cursorRow === wl.displayedSymbols[4] && !wl.settling })
        var afterDown = [wl.cursorRow === wl.displayedSymbols[4]]
        mouseMove(body, body.width / 2, 20)
        var afterLeaving = [wl.cursorRow === wl.displayedSymbols[4]]
        var steps = [onThird, afterWheel, afterDown, afterLeaving]
        root.check("one cursor: the pointer puts it on row 3, the wheel on the row under the still pointer once it rests, ↓ one row on, and leaving keeps it",
          steps.every(function(step) { return step.every(function(part) { return part === true }) }),
          steps.map(function(step) { return step.join(",") }).join(" | "))

        // Search: the keyboard's choice (the top result) is what Enter adds,
        // wherever the pointer rests.
        body.startAdding()
        within(1000, function() { return body.adding })
        body.search.results = [
          { symbol: "TOPR", name: "Top Result Inc.", exchange: "NASDAQ" },
          { symbol: "SECR", name: "Second Result Inc.", exchange: "NYSE" },
          { symbol: "THRD", name: "Third Result Inc.", exchange: "NYSE" }
        ]
        body.search.answer = "results"
        within(1000, function() { return root.findAll(body.search, "searchResult").length === 3 })
        var third = root.findAll(body.search, "searchResult")[2]
        var overThird = third.mapToItem(body, third.width / 2, third.height / 2)
        mouseMove(body, overThird.x, overThird.y)
        wait(200) // time for a hover to choose the result, if it did
        root.check("the pointer only tints a result", body.search.resultIndex === 0)
        keyClick(Qt.Key_Down)
        keyClick(Qt.Key_Up)
        keyClick(Qt.Key_Return)
        within(1000, function() { return !body.adding })
        root.check("Enter adds the keyboard's choice, not the result under the pointer",
          stub.symbols.indexOf("TOPR") >= 0 && stub.symbols.indexOf("THRD") < 0 && !body.adding)
        mouseMove(body, body.width / 2, 20)

        // A view still showing as its surface closes takes nothing: a click
        // on a result or a checklist box acts on nothing and takes no focus.
        // The surface's closing is surfaceOpen going false, as the popup's
        // fade begins.
        body.startAdding()
        within(1000, function() { return body.adding })
        body.search.results = [{ symbol: "LATE", name: "Late Inc.", exchange: "NYSE" }]
        body.search.answer = "results"
        within(1000, function() { return root.findAll(body.search, "searchResult").length === 1 })
        body.surfaceOpen = false
        var lateRow = root.findAll(body.search, "searchResult")[0]
        var overLate = lateRow.mapToItem(body, lateRow.width / 2, lateRow.height / 2)
        mouseClick(body, overLate.x, overLate.y)
        var searchInert = stub.symbols.indexOf("LATE") < 0 && body.adding && !body.search.activeFocus
        body.surfaceOpen = true
        body.cancelAdding()
        body.openSymbolLists(stub.symbols[0])
        within(1000, function() { var b = root.find(body, "symbolLists"); return b && b.visible })
        body.surfaceOpen = false
        var box = root.find(body, "symbolLists")
        var overBox = box.mapToItem(body, box.width / 2, Style.space(45))
        mouseClick(body, overBox.x, overBox.y)
        var listsInert = stub.memberships.length === 0 && !box.activeFocus
        body.surfaceOpen = true
        body.closeListViews()
        within(1000, function() { return body.listsSymbol === "" })
        root.check("a view showing through its surface's close takes no click and no focus",
          searchInert && listsInert, searchInert + "|" + listsInert + "|" + stub.memberships)

        // Nothing else on a closing surface acts either: a click, a right-click,
        // or the wheel on a row, a click on the footer or the header's look,
        // and the pointer over the chart. The shield doesn't depend on the
        // look, so smooth alone.
        var inert = function() {
          mouseMove(body, 1, 1)
          var rows = body.watchlist.displayedSymbols.slice()
          var target = rows[1]
          var hero = stub.featuredSymbol
          var settings = stub.lastSettings
          var scrolled = body.watchlist.contentY
          var cursor = body.watchlist.cursorRow
          body.surfaceOpen = false
          var row = body.watchlist.rowItem(target)
          var overRow = row.mapToItem(body, row.width / 2, row.height / 2)
          mouseClick(body, overRow.x, overRow.y)
          mouseClick(body, overRow.x, overRow.y, Qt.RightButton)
          mouseWheel(body, overRow.x, overRow.y, 0, -120)
          var footer = root.find(body, "footer")
          var overFooter = footer.mapToItem(body, footer.width / 2, footer.height / 2)
          mouseClick(body, overFooter.x, overFooter.y)
          var look = root.find(body, "lookIcon")
          var overLook = look.mapToItem(body, look.width / 2, look.height / 2)
          mouseClick(body, overLook.x, overLook.y)
          var chart = body.chartItem
          var overChart = chart.mapToItem(body, chart.width / 3, chart.height / 2)
          mouseMove(body, overChart.x, overChart.y)
          mouseMove(body, overChart.x + 20, overChart.y)
          wait(300) // time for a scrub to follow the pointer, if it did
          var still = [stub.featuredSymbol === hero, body.watchlist.displayedSymbols.join() === rows.join(),
            body.watchlist.contentY === scrolled, !body.adding, stub.lastSettings === settings,
            body.scrubT === 0, body.watchlist.cursorRow === cursor, body.rowMenu === null].join(",")
          body.surfaceOpen = true
          mouseMove(body, 1, 1)
          return still
        }
        var smoothInert = inert()
        root.check("a closing surface takes no click, right-click, wheel, or scrub, smooth and retro",
          smoothInert === "true,true,true,true,true,true,true,true", smoothInert)

        var orderWord = root.find(body, "orderLabel")
        var orderWas = stub.order
        var edgeFaults = []
        var arrowGlyph = Qt.createQmlObject('import QtQuick; TextMetrics {}', root)
        arrowGlyph.font = orderWord.font
        arrowGlyph.text = orderWord.text.charAt(0)
        ;[false, true].forEach(function(retro) {
          stub.retro = retro
          stub.order = "pct"
          wait(20) // a frame for the look's font
          ;[arrowGlyph.boundingRect.x + 1, arrowGlyph.boundingRect.x + arrowGlyph.boundingRect.width - 1].forEach(function(x) {
            stub.lastSettings = null
            var at = orderWord.mapToItem(body, x, orderWord.height / 2)
            mouseClick(body, at.x, at.y)
            if (!stub.lastSettings || stub.lastSettings.reversed === undefined) edgeFaults.push(retro + " at " + x)
          })
        })
        arrowGlyph.destroy()
        stub.retro = false
        stub.order = orderWas
        root.check("both visible edges of a sorted order's arrow act in both looks", edgeFaults.length === 0, edgeFaults.join(" | "))

        // Since the open, the hero's caption names it, in the slot AT CLOSE
        // would take, and the figure is bare; a row says "open" inline.
        stub.featuredSymbol = "MZ"
        stub.changeMode = "open"
        var heroCaption = root.find(body, "changeCaption")
        var heroChange = root.find(body, "changeText")
        var firstShown = body.watchlist.rowItem(body.watchlist.displayedSymbols[0])
        var sinceOpen = function() {
          return heroCaption.text === "SINCE OPEN" && heroChange.text.indexOf("open") < 0
            && firstShown.view.changeLine.indexOf(" open") > 0
        }
        root.check("a change since the open is captioned SINCE OPEN, never AT CLOSE", within(1000, sinceOpen))
        stub.changeMode = "pct"

        root.setQuotes(["FIT1", "FIT2"], [101, 102])
        within(2000, function() { return body.watchlist.rowItem("FIT2") !== null && rowsAtRest() })
        // The row's menu removes a row from All; the last one stays, and the
        // footer says why for a moment.
        var fit2 = body.watchlist.rowItem("FIT2")
        mouseClick(fit2, fit2.width / 2, fit2.height / 2, Qt.RightButton)
        takeMenuLine(0)
        within(2000, function() { return stub.symbols.join(",") === "FIT1" && rowsAtRest() })
        var fit1 = body.watchlist.rowItem("FIT1")
        mouseClick(fit1, fit1.width / 2, fit1.height / 2, Qt.RightButton)
        takeMenuLine(0)
        within(1000, function() { return body.note !== "" })
        root.check("the last row stays and the footer says why",
          stub.symbols.join(",") === "FIT1" && body.note === "Keep at least one symbol", stub.symbols + "|" + body.note)
        root.check("the note clears on its own", within(4000, function() { return body.note === "" }))
        stub.order = "manual"
        // A cursor you put on a row, by pointer or key, shows its remove
        // button; the cursor resting on the featured row shows none.
        root.setQuotes(["FIT1", "FIT2", "FIT3", "FIT4"], [101, 102, 103, 104])
        mouseMove(body, body.width / 2, body.height - 4)
        body.watchlist.cursorSymbol = ""
        within(2000, rowsAtRest)
        var removeOf = function(symbol) {
          var r = body.watchlist.rowItem(symbol)
          return r ? root.find(r, "rowRemove") : null
        }
        var removesShown = function() {
          return stub.symbols.filter(function(s) { var b = removeOf(s); return b && b.visible }).join(",") || "none"
        }
        var removeSteps = ["rest " + removesShown()]
        var fit2 = body.watchlist.rowItem("FIT2")
        // The first place a pointer is seen at is no move (RowPointer).
        mouseMove(fit2, fit2.width / 2, fit2.height / 2 - 6)
        mouseMove(fit2, fit2.width / 2, fit2.height / 2)
        within(1000, function() { return removesShown() === "FIT2" })
        removeSteps.push("pointer " + removesShown())
        var fit2Remove = removeOf("FIT2")
        // A slip removes nothing: a press beside the button released on it,
        // or a press on it released beside it. Both places are read before
        // either slip: a slip that removed the row would take its button.
        var slips = fit2Remove && fit2Remove.visible ? [[-1, 2], [1, -2]].map(function(s) {
          return [fit2Remove.mapToItem(body, s[0], fit2Remove.height / 2), fit2Remove.mapToItem(body, s[1], fit2Remove.height / 2)]
        }) : []
        slips.forEach(function(s) {
          mousePress(body, s[0].x, s[0].y)
          mouseMove(body, s[1].x, s[1].y)
          mouseRelease(body, s[1].x, s[1].y)
          wait(Application.styleHints.mouseDoubleClickInterval + 50)
        })
        removeSteps.push("slips " + stub.symbols.join(","))
        fit2Remove = removeOf("FIT2")
        var slidAt = fit2Remove ? fit2Remove.mapToItem(body, fit2Remove.width / 2, fit2Remove.height / 2) : Qt.point(-1, -1)
        if (fit2Remove && fit2Remove.visible) mouseClick(fit2Remove, fit2Remove.width / 2, fit2Remove.height / 2)
        within(2000, rowsAtRest)
        removeSteps.push("click " + stub.symbols.join(","))
        // The row that slid into its place, under the still pointer, shows
        // no remove button, so another click there features it; a move of
        // the pointer shows it.
        removeSteps.push("slid " + body.watchlist.cursorRow + " " + removesShown())
        wait(Application.styleHints.mouseDoubleClickInterval + 50)
        mouseClick(body, slidAt.x, slidAt.y)
        within(2000, rowsAtRest)
        removeSteps.push("again " + stub.symbols.join(",") + " " + stub.featuredSymbol)
        wait(Application.styleHints.mouseDoubleClickInterval + 50)
        mouseMove(body, slidAt.x + 3, slidAt.y)
        within(1000, function() { return removesShown() !== "none" })
        removeSteps.push("moved " + removesShown())
        var nextRemove = removeOf("FIT3")
        if (nextRemove && nextRemove.visible) mouseDoubleClickSequence(nextRemove, nextRemove.width / 2, nextRemove.height / 2)
        within(2000, rowsAtRest)
        removeSteps.push("double " + stub.symbols.join(","))
        mouseMove(body, body.width / 2, body.height - 4)
        body.watchlist.cursorSymbol = ""
        body.moveCursor(1)
        within(1000, function() { return body.watchlist.cursorRow !== "" && removesShown() !== "none" })
        var keyed = body.watchlist.cursorRow
        removeSteps.push("key " + removesShown())
        // A press on the button and a move still lift the row: the button
        // takes only a click.
        var keyedRemove = removeOf(keyed)
        if (keyedRemove && keyedRemove.visible) {
          var grip = keyedRemove.mapToItem(body, keyedRemove.width / 2, keyedRemove.height / 2)
          var toward = (keyed === "FIT1" ? 1 : -1) * body.watchlist.rowPitch
          mousePress(body, grip.x, grip.y)
          mouseMove(body, grip.x, grip.y + toward / 4)
          mouseMove(body, grip.x, grip.y + toward)
          mouseRelease(body, grip.x, grip.y + toward)
          within(2000, rowsAtRest)
        }
        removeSteps.push("lift " + stub.symbols.join(","))
        root.check("a cursor you put on a row shows its remove button, the resting one none; a click on it removes that row, a slip nothing, and the row sliding under the still pointer shows none until it moves; a double-click removes one, a press and move lifts the row",
          keyed !== "" && removeSteps.join(" | ") === "rest none | pointer FIT2 | slips FIT1,FIT2,FIT3,FIT4 | click FIT1,FIT3,FIT4 | slid FIT3 none"
            + " | again FIT1,FIT3,FIT4 FIT3 | moved FIT3 | double FIT1,FIT4 | key " + keyed + " | lift FIT4,FIT1",
          removeSteps.join(" | "))

        // A removal by the button is decided at its press and done at a
        // release on it, even a double-click's second press, which Qt acts
        // on at mouse-down. The events one by one, as Qt sends a
        // double-click: press, release, press, double-click, release.
        var secondPress = function(release) {
          root.setQuotes(["FIT1", "FIT2", "FIT3"], [101, 102, 103])
          within(2000, function() { return body.watchlist.rowItem("FIT1") !== null && rowsAtRest() })
          var firstRow = body.watchlist.rowItem("FIT1")
          mouseMove(firstRow, firstRow.width / 2, firstRow.height / 2 - 6)
          mouseMove(firstRow, firstRow.width / 2, firstRow.height / 2)
          within(1000, function() { var b = removeOf("FIT1"); return b && b.visible })
          var firstRemove = removeOf("FIT1")
          var onButton = firstRemove && firstRemove.visible ? firstRemove.mapToItem(body, firstRemove.width / 2, firstRemove.height / 2) : null
          // Each removal, in order.
          var removals = []
          var symbolsBefore = stub.symbols.slice()
          var watchRemovals = function() {
            symbolsBefore.forEach(function(s) { if (stub.symbols.indexOf(s) < 0) removals.push(s) })
            symbolsBefore = stub.symbols.slice()
          }
          stub.symbolsChanged.connect(watchRemovals)
          if (onButton) {
            mousePress(body, onButton.x, onButton.y)
            mouseRelease(body, onButton.x, onButton.y)
            wait(120) // the second press comes inside the double-click interval
            mouseWheel(body, onButton.x, onButton.y, 0, -120, Qt.NoButton, Qt.NoModifier)
            var moved = Qt.point(onButton.x + 1, onButton.y)
            mouseMove(body, moved.x, moved.y)
            mousePress(body, moved.x, moved.y)
            // TestCase has no lone double-click event in Qt 6; its sender does.
            qtest_events.mouseDoubleClick(body, moved.x, moved.y, Qt.LeftButton, Qt.NoModifier, -1)
            release(moved)
          }
          within(2000, rowsAtRest)
          stub.symbolsChanged.disconnect(watchRemovals)
          return removals.join(",") + " -> " + stub.symbols.join(",")
        }
        var slidOff = secondPress(function(at) {
          mouseMove(body, at.x - Style.space(30), at.y)
          mouseRelease(body, at.x - Style.space(30), at.y)
        })
        var heldLong = secondPress(function(at) {
          wait(Application.styleHints.mouseDoubleClickInterval + 100)
          mouseRelease(body, at.x, at.y)
        })
        root.check("a double-click's second press on a remove button, after the wheel, removes nothing let go off it, and its row let go on it however late",
          slidOff === "FIT1 -> FIT2,FIT3" && heldLong === "FIT1,FIT2 -> FIT3", slidOff + " | " + heldLong)

        // A row the wheel scrolls under a still pointer takes the cursor but
        // shows no remove button, so a click there features it; the button
        // shows once the pointer really moves, or a key moves the cursor. A
        // tick that moves the list less than a row hides it too. Every symbol
        // here is as long as the next, so each row's button sits where the
        // one above it sat.
        var even = root.symbols(20)
        root.setQuotes(even, even.map(function(s, i) { return 100 + i }))
        body.watchlist.contentY = 0
        within(2000, rowsAtRest)
        var secondRow = body.watchlist.rowItem(even[1])
        mouseMove(secondRow, secondRow.width / 2, secondRow.height / 2 - 6)
        mouseMove(secondRow, secondRow.width / 2, secondRow.height / 2)
        within(1000, function() { return removesShown() === even[1] })
        var secondRemove = removeOf(even[1])
        var waits = ["pointer " + removesShown()]
        if (secondRemove && secondRemove.visible) {
          var onSecond = secondRemove.mapToItem(body, secondRemove.width / 2, secondRemove.height / 2)
          mouseMove(body, onSecond.x, onSecond.y)
          mouseWheel(body, onSecond.x, onSecond.y, 0, -120, Qt.NoButton, Qt.NoModifier)
          within(2000, function() { return !body.watchlist.settling })
          waits.push("wheel " + body.watchlist.cursorRow + " " + removesShown())
          mouseClick(body, onSecond.x, onSecond.y)
          within(2000, function() { return !body.watchlist.settling })
          waits.push("click " + stub.featuredSymbol + " " + stub.symbols.length + " " + removesShown())
          wait(Application.styleHints.mouseDoubleClickInterval + 50)
          mouseMove(body, onSecond.x + 3, onSecond.y)
          within(1000, function() { return removesShown() !== "none" })
          waits.push("move " + removesShown())
          mouseWheel(body, onSecond.x + 3, onSecond.y, 0, -120, Qt.NoButton, Qt.NoModifier)
          within(2000, function() { return !body.watchlist.settling })
          body.moveCursor(1)
          within(2000, function() { return !body.watchlist.settling })
          waits.push("key " + body.watchlist.cursorRow + " " + removesShown())
          mouseMove(body, onSecond.x, onSecond.y)
          within(1000, function() { return removesShown() !== "none" })
          var before = body.watchlist.cursorRow + " " + removesShown()
          mouseWheel(body, onSecond.x, onSecond.y, 0, -30, Qt.NoButton, Qt.NoModifier)
          within(2000, function() { return !body.watchlist.settling })
          waits.push("tick " + before + " " + body.watchlist.cursorRow + " " + removesShown())
          // A click during a glide stops the list on a row on the way, which
          // waits too.
          mouseMove(body, onSecond.x + 3, onSecond.y)
          within(1000, function() { return removesShown() !== "none" })
          for (var notch = 0; notch < 4; notch++) mouseWheel(body, onSecond.x + 3, onSecond.y, 0, -120, Qt.NoButton, Qt.NoModifier)
          wait(30) // into the four notches' glide
          mouseClick(body, onSecond.x + 3, onSecond.y)
          within(2000, function() { return !body.watchlist.settling })
          waits.push("glide " + (stub.featuredSymbol === body.watchlist.cursorRow) + " " + stub.symbols.length + " " + removesShown())
        }
        root.check("a row the wheel scrolls under a still pointer shows no remove button, a click there features it, mid-glide too, and a move or a key shows it",
          waits.join(" | ") === ["pointer " + even[1], "wheel " + even[2] + " none", "click " + even[2] + " 20 none",
            "move " + even[2], "key " + even[4] + " " + even[4], "tick " + even[3] + " " + even[3] + " " + even[3] + " none",
            "glide true 20 none"].join(" | "),
          waits.join(" | "))
        body.closeListViews()
        stub.range = "1D"
        stub.order = "pct"

        var many = [{ name: "", label: "All", count: 1, symbols: ["FIT1"] }]
        for (var n = 1; n < 15; n++) many.push({ name: "L" + n, label: "List " + n, count: 0, symbols: [] })
        stub.lists = many
        // Opens a view at its top with the pointer on its second row and
        // wheels two notches under it; `interrupt`, if any, acts 30 ms in,
        // while the wheel's motion runs. Says the cursor then and at rest.
        var wheeled = function(open, close, viewName, rowName, interrupt) {
          open()
          var view = null
          var rows = []
          within(1000, function() {
            view = root.find(body, viewName)
            return view && view.visible && viewAtRest(view)
          })
          // Laid out and drawn, so the rows sit where they're read and the
          // pointer's hover reaches them.
          waitForRendering(view)
          // Harness.findAll walks a Flickable's contentItem twice: one of each.
          rows = root.findAll(view, rowName).filter(function(r, i, all) { return all.indexOf(r) === i })
          var at = rows[1].mapToItem(body, rows[1].width / 2, rows[1].height / 2)
          mouseMove(body, at.x, at.y - 6)
          mouseMove(body, at.x, at.y)
          var pointed = view.cursor
          mouseWheel(body, at.x, at.y, 0, -240, Qt.NoModifier)
          var stopped = -1
          if (interrupt) {
            // Into the wheel's motion, so the interrupt lands while it runs.
            wait(30)
            interrupt()
            stopped = view.cursor
          }
          within(2000, function() { return viewAtRest(view) })
          var under = -1
          rows.forEach(function(row, i) { if (row.contains(row.mapFromItem(body, at.x, at.y))) under = i })
          var rested = view.cursor
          close()
          within(1000, function() { return !body.listMenuOpen && !body.managingLists && body.listsSymbol === "" })
          return { pointed: pointed, under: under, stopped: stopped, rested: rested }
        }
        // A key, or the surface closing with the view showing through its
        // fade, while the wheel's motion runs stops it: the cursor moves no
        // further.
        var wheels = [
          [function() { body.openListMenu() }, function() { body.closeListMenu() }, "listMenu", "listChoice"],
          [function() { body.openSymbolLists("FIT1") }, function() { body.closeListViews() }, "symbolLists", "symbolListRow"],
          [function() { body.openManageLists() }, function() { body.closeListViews() }, "manageLists", "manageRow"]
        ].map(function(v) {
          var free = wheeled(v[0], v[1], v[2], v[3], null)
          var keyed = wheeled(v[0], v[1], v[2], v[3], function() { keyClick(Qt.Key_Down) })
          var closed = wheeled(v[0], v[1], v[2], v[3], function() { body.surfaceOpen = false })
          body.surfaceOpen = true
          return [free.pointed === 1 && free.under > 1 && free.rested === free.under,
            keyed.rested === keyed.stopped, closed.rested === closed.stopped].join(",")
            + " " + v[2] + " " + JSON.stringify([free, keyed, closed])
        })
        root.check("in the list menu, a symbol's lists, and Manage lists, the wheel under a still pointer moves the cursor to the row then under it, until a key or a close stops it",
          wheels.every(function(w) { return w.indexOf("true,true,true ") === 0 }), wheels.join(" | "))

        finish()
      }
    }
  }

  // A list view's rows stopped: no hand's scroll moving them, resting on a
  // row's edge or the end, its settle (which hands the cursor on) done.
  function viewAtRest(view) {
    var flick = flickIn(view)
    if (!flick) return false
    var y = flick.contentY
    var end = Math.max(0, flick.contentHeight - flick.height)
    return !flick.moving && (Math.abs(y - Math.round(y / view.itemHeight) * view.itemHeight) < 0.5 || Math.abs(y - end) < 0.5)
  }
  function flickIn(item) {
    if (!item) return null
    if (item.flickableDirection !== undefined) return item
    for (var i = 0; i < item.children.length; i++) {
      var found = flickIn(item.children[i])
      if (found) return found
    }
    return null
  }
}
