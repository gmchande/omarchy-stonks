import QtQuick
import QtTest
import Quickshell
import Quickshell.Io
import "plugin" as Stonks
import "plugin/Quote.js" as Quote

// The window's rows by hand, through the real App and Service with real Qt
// keys and pointer: removal by click, the sorted view's guards, the help
// sheet, moves by keys and drag, the wheel, the cursor, scrolling, undo,
// rows held by a close, the chart's own clicks and keys, and the footer's
// notices. HOME and curl are scratch fixtures.
Harness {
  id: harness
  marker: "WINDOW ROWS DONE"

  function showsPrice(item, text) {
    if (!item || !item.visible) return false
    if (item.text !== undefined && String(item.text) === text) return true
    for (var i = 0; i < item.children.length; i++) if (showsPrice(item.children[i], text)) return true
    return item.contentItem ? showsPrice(item.contentItem, text) : false
  }

  function sameSymbols(expected) {
    return service.symbols.join(",") === expected.join(",")
  }

  Stonks.Service { id: service }
  Stonks.Updates { id: updates }
  Stonks.App { id: app; service: service; updates: updates }

  readonly property string dataPath: Quickshell.env("HOME") + "/.config/omarchy/grvc.stonks.json"
  readonly property string fileNotice: "Couldn't load your lists"
  // Through a temporary file moved over it, as an editor's atomic save does.
  Process { id: writer }
  function writeFile(path, body) {
    writer.running = false
    writer.command = ["bash", "-c", "printf '%s' \"$1\" > \"$2.tmp\" && mv -f \"$2.tmp\" \"$2\"", "--", body, path]
    writer.running = true
  }
  Process { id: fileProc }

  Steps {
    name: "WindowRows"
    when: service.pluginsReady

    // Closed, sized, and open again at that size: an offscreen window takes
    // a new size only as it opens. Keys and the pointer reach it once it has
    // drawn at that size.
    function openAt(height, width) {
      app.close()
      if (width !== undefined) app.testWindow.implicitWidth = width
      app.testWindow.implicitHeight = height
      app.open("{}")
      tryVerify(function() { return app.testWindow.height === app.testWindow.implicitHeight && app.testWindow.width === app.testWindow.implicitWidth }, 2000)
      waitForRendering(app.testBody)
    }

    // Puts down (on) or takes away the fake curl's file `name` in its state.
    function hold(name, on) {
      var path = Quickshell.env("STONKS_FAKE_STATE") + "/" + name
      fileProc.command = on ? ["touch", path] : ["rm", "-f", path]
      fileProc.running = true
      tryVerify(function() { return !fileProc.running }, 2000)
    }

    // The list still and every row in its place.
    function settled(watchlist) {
      return !watchlist.settling && watchlist.displayedSymbols.every(function(symbol) { return watchlist.rowResting(symbol) })
    }

    function firstWhole(watchlist) {
      for (var i = 0; i < watchlist.displayedSymbols.length; i++)
        if (watchlist.wholeInSight(i, watchlist.contentY)) return i
      return -1
    }

    // A copy of `symbol`'s quote whose day change is `pct` percent, for a
    // refresh that re-ranks the rows.
    function movedBy(symbol, pct) {
      var quote = Object.assign({}, service.quotes[symbol])
      quote.prevClose = Quote.regularClose(quote) / (1 + pct / 100)
      return quote
    }

    // `symbol`'s quote as the next session's: every time in it a day later.
    function nextDay(symbol) {
      var shift = function(value, key) {
        if (Array.isArray(value)) return value.map(function(v) { return shift(v, "") })
        if (value && typeof value === "object") {
          var out = {}
          for (var k in value) out[k] = shift(value[k], k)
          return out
        }
        return typeof value === "number" && ["t", "start", "end", "marketTime"].indexOf(key) >= 0 ? value + 86400 : value
      }
      var next = Object.assign({}, service.testFeed.quotes)
      next[symbol] = shift(service.quotes[symbol], "")
      service.testFeed.quotes = next
    }

    // Every key and click acts on the row you chose, as the rows show it.
    function keysActOnWhatYouChose(body, watchlist, keys) {
      var six = ["AAPL", "MSFT", "NVDA", "FLAT", "DOWN", "STRAY"]
      six.forEach(function(s) { service.addSymbol(s) })
      tryVerify(function() { return service.arriving.length === 0 && service.testFeed.firstRun.length + service.testFeed.refreshRun.length === 0 }, 8000)
      service.persist({ order: "manual", featured: "AAPL" })
      service.setManualOrder(six.concat(service.library.filter(function(s) { return six.indexOf(s) < 0 })))
      mouseMove(body, 1, 1)
      // Tall enough for every row.
      openAt(body.chromeHeight + 7 * body.rowPitch)

      // Search opened by a in All, and by a click on the footer in a named
      // list without the hero.
      var throughSearch = function(open) {
        keys.forceActiveFocus()
        keyClick(Qt.Key_Down)
        keyClick(Qt.Key_Down)
        var chosen = watchlist.cursorRow
        open()
        within(1000, function() { var focused = keys.Window.activeFocusItem; return body.adding && !!focused && focused.objectName === "searchField" })
        var during = watchlist.cursorRow
        keyClick(Qt.Key_Escape)
        within(1000, function() { return !body.adding })
        var after = watchlist.cursorRow
        keyClick(Qt.Key_Return)
        within(1000, function() { return service.featuredSymbol === chosen })
        return [chosen, during, after, service.featuredSymbol].join(">")
      }
      var inAll = throughSearch(function() { keyClick(Qt.Key_A) })
      service.createList("Pair")
      ;["NVDA", "FLAT", "DOWN", "STRAY", "MSFT"].forEach(function(s) { service.setMembership(s, "Pair", true) })
      service.feature("AAPL")
      within(2000, function() { return settled(watchlist) })
      var inPair = throughSearch(function() {
        var footer = harness.find(body, "footer")
        mouseClick(footer, footer.width / 2, footer.height / 2)
      })
      harness.check("search keeps the cursor you set, and ⏎ after it acts there: a in All, the footer in a list",
        inAll === "NVDA>NVDA>NVDA>NVDA" && inPair === "DOWN>DOWN>DOWN>DOWN", inAll + " | " + inPair)

      // With a cursor of its own in manual order, and without one in a
      // sorted order scrolled to its end.
      var heightBefore = app.testWindow.implicitHeight
      openAt(body.chromeHeight + 3 * body.rowPitch)
      var rename = function(to) {
        var cursor = watchlist.cursorSymbol
        var scrolled = firstWhole(watchlist)
        keys.forceActiveFocus()
        keyClick(Qt.Key_L)
        tryVerify(function() { return body.listMenuOpen && harness.find(body, "listMenu") !== null }, 2000)
        var menu = harness.find(body, "listMenu")
        while (menu.cursor < menu.manageIndex) keyClick(Qt.Key_Down)
        keyClick(Qt.Key_Return)
        tryVerify(function() { return body.managingLists }, 2000)
        keyClick(Qt.Key_Return)
        tryVerify(function() { var field = harness.find(body, "renameField"); return !!field && field.visible }, 2000)
        for (var i = 0; i < to.length; i++) keyClick(to.charAt(i))
        keyClick(Qt.Key_Return)
        within(1000, function() { return service.listName === to })
        keyClick(Qt.Key_Escape)
        within(1000, function() { return !body.managingLists && settled(watchlist) })
        return [service.listName === to, scrolled > 0, firstWhole(watchlist) === scrolled, watchlist.cursorSymbol === cursor].join(",")
          + " " + cursor + "@" + scrolled + "->" + watchlist.cursorSymbol + "@" + firstWhole(watchlist)
      }
      keys.forceActiveFocus()
      for (var d = 0; d < 4; d++) keyClick(Qt.Key_Down)
      tryVerify(function() { return firstWhole(watchlist) > 0 && watchlist.wholeInSight(watchlist.displayedSymbols.indexOf(watchlist.cursorRow), watchlist.contentY) }, 2000)
      var ownCursor = rename("Pairs")
      service.setOrder("symbol")
      within(2000, function() { return settled(watchlist) })
      watchlist.cursorSymbol = ""
      watchlist.contentY = watchlist.contentHeight - watchlist.height
      var sortedEnd = rename("Pair")
      harness.check("a rename keeps the rows' scroll and cursor, manual with a cursor and sorted at the end",
        /^true,true,true,true /.test(ownCursor) && /^true,true,true,true /.test(sortedEnd), ownCursor + " | " + sortedEnd)
      openAt(heightBefore)

      // The first row on All by % change, the second on a list by $ change,
      // and the hero's neighbour after a middle-click and after Delete.
      var quotesBefore = service.testFeed.quotes
      var rank = function(changes) {
        var next = Object.assign({}, service.testFeed.quotes)
        for (var s in changes) next[s] = movedBy(s, changes[s])
        service.testFeed.quotes = next
      }
      var ranked = function() { return settled(watchlist) && watchlist.displayedSymbols.join() === service.view.shown.join() }
      var hold = function() {
        var first = watchlist.rowItem(watchlist.displayedSymbols[0])
        mouseMove(first, first.width / 2, first.height / 2)
        within(1000, function() { return watchlist.sortHeld })
      }
      var pickHeld = function(index, reranked) {
        hold()
        var onScreen = watchlist.displayedSymbols.slice()
        watchlist.cursorSymbol = onScreen[0]
        rank(reranked)
        within(1000, function() { return service.view.shown.join() !== onScreen.join() })
        var rearranged = service.view.shown.join() !== onScreen.join() && watchlist.displayedSymbols.join() === onScreen.join()
        keys.forceActiveFocus()
        for (var i = 0; i < index; i++) keyClick(Qt.Key_Down)
        keyClick(Qt.Key_Return)
        within(1000, function() { return service.featuredSymbol === onScreen[index] })
        return rearranged + "," + (service.featuredSymbol === onScreen[index]) + " " + onScreen[index] + "->" + service.featuredSymbol
      }
      service.switchList("")
      service.setOrder("pct")
      rank({ AAPL: 6, MSFT: 5, NVDA: 4, FLAT: 3, DOWN: 2, STRAY: 1 })
      within(2000, ranked)
      var onePct = pickHeld(0, { STRAY: 10 })
      mouseMove(body, 1, 1)
      service.switchList("Pair")
      service.setOrder("pct")
      service.reverseOrder()
      rank({ MSFT: 5, NVDA: 4, FLAT: 3, DOWN: 2, STRAY: 1 })
      within(2000, ranked)
      var twoReversed = pickHeld(1, { DOWN: 50 })
      harness.check("arrows and Enter feature the row shown there while the pointer holds re-ranked rows, by % in All and reversed in a list",
        /^true,true /.test(onePct) && /^true,true /.test(twoReversed), onePct + " | " + twoReversed)
      mouseMove(body, 1, 1)
      service.switchList("")
      service.setOrder("pct")
      var handOff = function(remove) {
        rank({ AAPL: 6, MSFT: 5, NVDA: 4, FLAT: 3, DOWN: 2, STRAY: 1 })
        service.feature("MSFT")
        within(2000, ranked)
        hold()
        var onScreen = watchlist.displayedSymbols.slice()
        rank({ FLAT: 4.5 })
        within(1000, function() { return service.view.shown.join() !== onScreen.join() })
        var next = onScreen[onScreen.indexOf("MSFT") + 1]
        remove()
        within(1000, function() { return service.featuredSymbol === next })
        var got = service.featuredSymbol
        mouseMove(body, 1, 1)
        keys.forceActiveFocus()
        keyClick(Qt.Key_Z, Qt.ControlModifier)
        within(1000, function() { return service.symbols.indexOf("MSFT") >= 0 })
        return (got === next) + " " + next + "->" + got
      }
      // Pair holds MSFT too, so in All the menu's one line, and Delete's,
      // reach both lists.
      var byClick = handOff(function() {
        var row = watchlist.rowItem("MSFT")
        mouseClick(row, row.width / 2, row.height / 2, Qt.RightButton)
        tryVerify(function() { return harness.find(body, "rowMenuLine") !== null }, 1000)
        var line = harness.find(body, "rowMenuLine")
        mouseClick(line, line.width / 2, line.height / 2)
      })
      var byKey = handOff(function() {
        watchlist.cursorSymbol = "MSFT"
        keys.forceActiveFocus()
        keyClick(Qt.Key_Delete)
        tryVerify(function() { return body.rowMenu !== null }, 1000)
        keyClick(Qt.Key_Return)
      })
      harness.check("removing the held hero hands it to its neighbour on screen, by a right-click's menu and by Delete",
        /^true /.test(byClick) && /^true /.test(byKey), byClick + " | " + byKey)
      service.testFeed.quotes = quotesBefore
      service.deleteList("Pair")
      service.setOrder("manual")
    }

    // Moving a row by Shift+↓ and Shift+↑, and the keys that carry the cursor
    // past the edge: the list gliding along so nothing jumps on screen.
    // Shift and the wheel scroll as the wheel does.
    function movesByKeys(body, watchlist, keys) {
      var six = ["AAPL", "MSFT", "NVDA", "FLAT", "DOWN", "STRAY"]
      var reset = function(list, look) {
        service.persist({ style: look })
        service.switchList(list)
        service.setOrder("manual")
        service.setManualOrder(six)
        watchlist.contentY = 0
        mouseMove(body, 1, 1)
        tryVerify(function() { return !watchlist.settling }, 2000)
      }
      service.createList("Moves")
      six.forEach(function(s) { service.setMembership(s, "Moves", true) })

      // Shift+↓ at the bottom, and Shift+↑ at the top of a list scrolled to
      // its end; ↓ past the edge glides the list.
      var heightBefore = app.testWindow.implicitHeight
      openAt(body.chromeHeight + 3 * body.rowPitch)
      var carried = function(symbol, move) {
        var before = service.symbols.indexOf(symbol)
        move()
        var after = service.symbols.indexOf(symbol)
        within(2000, function() { return watchlist.wholeInSight(watchlist.displayedSymbols.indexOf(symbol), watchlist.contentY) })
        return (after !== before && watchlist.cursorRow === symbol && watchlist.wholeInSight(watchlist.displayedSymbols.indexOf(symbol), watchlist.contentY)) + " " + symbol + " at " + after
      }
      reset("", "smooth")
      watchlist.cursorSymbol = "NVDA"
      keys.forceActiveFocus()
      var jAtBottom = carried("NVDA", function() { keyClick(Qt.Key_Down, Qt.ShiftModifier) })
      reset("Moves", "retro")
      watchlist.contentY = watchlist.contentHeight - watchlist.height
      var topRow = watchlist.displayedSymbols[3]
      watchlist.cursorSymbol = topRow
      keys.forceActiveFocus()
      var kAtTop = carried(topRow, function() { keyClick(Qt.Key_Up, Qt.ShiftModifier) })
      var notchOver = function(modifiers) {
        reset("", "smooth")
        var before = watchlist.displayedSymbols.join(",")
        var at = watchlist.mapToItem(body, watchlist.width / 2, 2 * watchlist.rowPitch + watchlist.rowHeight / 2)
        mouseMove(body, at.x, at.y)
        mouseWheel(body, at.x, at.y, 0, -120, Qt.NoButton, modifiers)
        tryVerify(function() { return !watchlist.settling }, 2000)
        within(2000, function() { return firstWhole(watchlist) === 1 })
        var seen = (firstWhole(watchlist) === 1) + " " + (watchlist.displayedSymbols.join(",") === before)
        mouseMove(body, 1, 1)
        return seen
      }
      var plainNotch = notchOver(Qt.NoModifier)
      var shiftNotch = notchOver(Qt.ShiftModifier)
      harness.check("Shift and a wheel notch over a row scroll the list a row, as the wheel does, and move no row",
        plainNotch === "true true" && shiftNotch === plainNotch, plainNotch + " | " + shiftNotch)
      reset("", "smooth")
      watchlist.cursorSymbol = "NVDA"
      keys.forceActiveFocus()
      keyClick(Qt.Key_Down)
      var downTarget = watchlist.displayedSymbols[3]
      tryVerify(function() { return watchlist.cursorRow === downTarget }, 2000)
      within(2000, function() { return watchlist.wholeInSight(3, watchlist.contentY) })
      harness.check("Shift+↓ and Shift+↑ move their selected row, and Down selects the next row",
        /^true /.test(jAtBottom) && /^true /.test(kAtTop) && watchlist.cursorRow === downTarget && watchlist.wholeInSight(3, watchlist.contentY),
        [jAtBottom, kAtTop, watchlist.cursorRow].join(" | "))
      openAt(heightBefore)
      service.persist({ style: "smooth" })
      service.switchList("")
      service.deleteList("Moves")
    }

    // A drag and the wheel: the lifted row stays under the pointer, a drag or
    // anything else that takes the list from the wheel leaves it on a row, a
    // new order ends a drag, and a close holds a drag where it is.
    function dragsAndTheWheel(body, watchlist, keys) {
      var six = ["AAPL", "MSFT", "NVDA", "FLAT", "DOWN", "STRAY"]
      service.createList("Drags")
      six.forEach(function(s) { service.setMembership(s, "Drags", true) })
      var heightBefore = app.testWindow.implicitHeight
      openAt(body.chromeHeight + 3 * body.rowPitch)
      // Coordinates for the next gesture belong to rows that have landed.
      var ready = function() { return watchlist.dragSymbol === "" && settled(watchlist) }
      var reset = function(list, look) {
        service.persist({ style: look })
        service.switchList(list)
        service.setOrder("manual")
        service.setManualOrder(six)
        watchlist.contentY = 0
        mouseMove(body, 1, 1)
        within(2000, ready)
      }
      var centre = function(symbol) {
        var row = watchlist.rowItem(symbol)
        return row.mapToItem(body, row.width / 2, row.height / 2)
      }
      var lift = function(symbol, by) {
        var at = centre(symbol)
        mousePress(body, at.x, at.y)
        mouseMove(body, at.x, at.y + by / 2, -1, Qt.LeftButton)
        mouseMove(body, at.x, at.y + by, -1, Qt.LeftButton)
        within(1000, function() { return watchlist.dragSymbol === symbol })
        return Qt.point(at.x, at.y + by)
      }
      var canAct = function() { return watchlist.cursorRow !== "" && watchlist.wholeInSight(watchlist.displayedSymbols.indexOf(watchlist.cursorRow), watchlist.contentY) }

      // Down from the top in smooth, up from the end in retro.
      var underPointer = function(symbol, by, notch) {
        var at = lift(symbol, by)
        var scrollBefore = watchlist.contentY
        mouseWheel(body, at.x, at.y, 0, notch, Qt.LeftButton)
        tryVerify(function() { return !watchlist.settling }, 2000)
        var kept = watchlist.dragSymbol === symbol
        var wheeled = Math.abs(watchlist.contentY - scrollBefore + notch / 120 * watchlist.rowPitch) < 1
        var drop = watchlist.displayedSymbols.slice()
        var from = drop.indexOf(symbol)
        var to = Math.round(from + (by + watchlist.contentY - scrollBefore) / watchlist.rowPitch)
        drop.splice(from, 1)
        drop.splice(Math.max(0, Math.min(drop.length, to)), 0, symbol)
        mouseRelease(body, at.x, at.y)
        within(2000, ready)
        return (kept && wheeled && service.symbols.join() === drop.join()) + " dragged " + symbol + " -> " + service.symbols.join() + " wanted " + drop.join()
      }
      reset("", "smooth")
      var wheelDown = underPointer("AAPL", 8, -120)
      reset("Drags", "retro")
      watchlist.contentY = watchlist.contentHeight - watchlist.height
      var wheelUp = underPointer(watchlist.displayedSymbols[5], -8, 120)
      harness.check("the wheel during a drag keeps the chosen symbol, down in smooth and up in retro",
        /^true /.test(wheelDown) && /^true /.test(wheelUp), wheelDown + " | " + wheelUp)

      var orderMidDrag = function() {
        var saved = service.symbols.join()
        var at = lift("AAPL", body.rowPitch * 2)
        keys.forceActiveFocus()
        keyClick(Qt.Key_O)
        var ended = watchlist.dragSymbol === ""
        within(2000, ready)
        var shown = watchlist.displayedSymbols.join(",")
        mouseRelease(body, at.x, at.y)
        // Longer than a drop's 160 ms, for one that moved rows to show.
        wait(300)
        var still = watchlist.displayedSymbols.join(",") === shown
        return [ended, still, service.symbols.join() === saved].join(",")
      }
      reset("", "smooth")
      var inAll = orderMidDrag()
      reset("Drags", "retro")
      var inList = orderMidDrag()
      harness.check("a new order mid-drag ends the drag: the release moves nothing and saves nothing, All in smooth and a list in retro",
        inAll === "true,true,true" && inList === "true,true,true", inAll + " | " + inList)

      // Each gesture comes while the wheel's glide is still under way. The
      // hero is the second row, which a reopen leaves where it is, so after
      // a close only the open's own snap puts the list on a row.
      var onRow = function() {
        var pitch = watchlist.rowPitch
        return Math.abs(watchlist.contentY - Math.round(watchlist.contentY / pitch) * pitch) < 0.5
      }
      var gliding = function() { return watchlist.contentY > 0.5 && watchlist.contentY < watchlist.rowPitch - 0.5 }
      reset("", "smooth")
      var at = centre("AAPL")
      mouseWheel(body, at.x, at.y, 0, -60)
      within(1000, gliding)
      lift("AAPL", 8)
      mouseRelease(body, at.x, at.y + 8)
      within(2000, ready)
      var afterDrag = canAct() + "@" + watchlist.cursorRow
      reset("Drags", "retro")
      watchlist.cursorSymbol = "MSFT"
      keys.forceActiveFocus()
      keyClick(Qt.Key_Delete)
      within(1000, function() { return watchlist.displayedSymbols.indexOf("MSFT") < 0 && ready() })
      at = centre("AAPL")
      mouseWheel(body, at.x, at.y, 0, -60)
      within(1000, gliding)
      keyClick(Qt.Key_Z, Qt.ControlModifier)
      within(2000, ready)
      var afterUndo = canAct() + "@" + watchlist.cursorRow
      mouseMove(body, 1, 1)
      reset("", "smooth")
      service.feature("MSFT")
      at = centre("AAPL")
      mouseWheel(body, at.x, at.y, 0, -120)
      var notchMid = within(1000, gliding)
      app.close()
      app.open("{}")
      var afterNotch = (notchMid && canAct() && onRow()) + "@" + watchlist.cursorRow + " " + watchlist.contentY
      reset("Drags", "retro")
      service.feature("MSFT")
      at = centre("AAPL")
      mouseWheel(body, at.x, at.y, 0, -40)
      var tickMid = within(1000, gliding)
      app.close()
      app.open("{}")
      var afterTick = (tickMid && canAct() && onRow()) + "@" + watchlist.cursorRow + " " + watchlist.contentY
      harness.check("a drag, undo and close during wheel input leave an actionable cursor",
        [afterDrag, afterUndo, afterNotch, afterTick].every(function(r) { return /^true@/.test(r) }),
        [afterDrag, afterUndo, afterNotch, afterTick].join(" | "))

      var closeMidDrag = function(symbol, by) {
        var saved = service.symbols.join()
        var point = lift(symbol, by)
        app.close()
        app.open("{}")
        mouseRelease(body, point.x, point.y)
        var kept = service.symbols.join() === saved
        return [watchlist.dragSymbol === "", kept].join(",")
      }
      reset("", "smooth")
      var downSmooth = closeMidDrag("AAPL", body.rowPitch + 10)
      reset("Drags", "retro")
      var upRetro = closeMidDrag("NVDA", -body.rowPitch - 10)
      harness.check("a close cancels the drag and its later release cannot reorder All or a named list",
        downSmooth === "true,true" && upRetro === "true,true", downSmooth + " | " + upRetro)

      openAt(heightBefore)
      service.persist({ style: "smooth" })
      service.switchList("")
      service.deleteList("Drags")
    }

    // The keyboard cursor is always on a row in sight.
    function cursorInSight(body, watchlist, keys) {
      var six = ["AAPL", "MSFT", "NVDA", "FLAT", "DOWN", "STRAY"]
      six.forEach(function(s) { service.addSymbol(s) })
      tryVerify(function() { return service.arriving.length === 0 && service.testFeed.firstRun.length + service.testFeed.refreshRun.length === 0 }, 8000)
      service.setRange("1D")
      service.switchList("")
      service.setOrder("manual")
      service.setManualOrder(six.concat(service.library.filter(function(s) { return six.indexOf(s) < 0 })))
      service.createList("Tall")
      six.forEach(function(s) { service.setMembership(s, "Tall", true) })
      service.switchList("")
      var heightBefore = app.testWindow.implicitHeight
      openAt(body.chromeHeight + 3 * body.rowPitch)
      mouseMove(body, 1, 1)
      var sight = function(symbol) {
        var y = watchlist.displayedSymbols.indexOf(symbol) * watchlist.rowPitch
        return y >= 0 && y >= watchlist.contentY - 0.5 && y + watchlist.rowHeight <= watchlist.contentY + watchlist.height + 0.5
      }
      // What Delete takes, and where the cursor went, from the cursor as it
      // is. Tall holds every row, so in All Delete asks, and Enter takes it.
      var removesInSight = function() {
        var cursor = watchlist.cursorRow
        var shown = sight(cursor)
        keys.forceActiveFocus()
        keyClick(Qt.Key_Delete)
        if (body.rowMenu !== null) keyClick(Qt.Key_Return)
        var took = service.lastRemoval ? service.lastRemoval.symbol : ""
        keyClick(Qt.Key_Z, Qt.ControlModifier)
        within(2000, function() { return watchlist.displayedSymbols.indexOf(took) >= 0 && settled(watchlist) })
        return (shown && took === cursor) + " " + cursor + " " + took
      }

      // After a list switch, and the hero stepped out of sight by the pill.
      service.feature("STRAY")
      within(2000, function() { return settled(watchlist) })
      service.switchList("Tall")
      within(2000, function() { return settled(watchlist) })
      var afterSwitch = removesInSight()
      service.switchList("")
      within(2000, function() { return settled(watchlist) })
      watchlist.contentY = 0
      service.feature("AAPL")
      service.featureStep(4)
      within(2000, function() { return settled(watchlist) })
      var afterStep = removesInSight()
      var before = watchlist.contentY
      keyClick(Qt.Key_Down)
      tryVerify(function() { return !watchlist.settling }, 2000)
      var downFromSight = watchlist.contentY === before && sight(watchlist.cursorRow)
      // A cursor of your own that the wheel scrolls out of sight is let go:
      // the cursor moves to a row in sight, and stays there when the wheel
      // brings the old one back.
      watchlist.cursorSymbol = watchlist.displayedSymbols[0]
      var own = watchlist.cursorSymbol
      var first = watchlist.displayedSymbols[0]
      var at = watchlist.rowItem(first).mapToItem(body, 20, 20)
      mouseWheel(body, at.x, at.y, 0, -240)
      tryVerify(function() { return !watchlist.settling }, 2000)
      tryVerify(function() { return watchlist.cursorRow !== own && sight(watchlist.cursorRow) }, 2000)
      var movedOn = watchlist.cursorRow !== own && sight(watchlist.cursorRow)
      mouseWheel(body, at.x, at.y, 0, 240)
      tryVerify(function() { return !watchlist.settling }, 2000)
      var letGo = watchlist.cursorSymbol === ""
      mouseMove(body, 1, 1)
      harness.check("the cursor is always on a row in sight: after a list switch, the hero stepped away, ↓, and the wheel",
        /^true /.test(afterSwitch) && /^true /.test(afterStep) && downFromSight && movedOn && letGo,
        [afterSwitch, afterStep, downFromSight, movedOn, letGo].join(" | "))

      // The row glides into view, the cursor with it, so its highlight shows
      // and Delete takes it.
      watchlist.contentY = 0
      service.feature(watchlist.displayedSymbols[0])
      within(2000, function() { return settled(watchlist) })
      var sixth = watchlist.displayedSymbols[5]
      watchlist.cursorSymbol = watchlist.displayedSymbols[0]
      keys.forceActiveFocus()
      for (var d = 0; d < 5; d++) keyClick(Qt.Key_Down)
      keyClick(Qt.Key_Return)
      within(2000, function() { return sight(sixth) })
      var numbered = [service.featuredSymbol === sixth, sight(sixth)].join(",")
      var numberRemoves = removesInSight()
      harness.check("↓ and Enter reach a row below the fold with the cursor, and Delete takes it",
        numbered === "true,true" && numberRemoves === "true " + sixth + " " + sixth,
        sixth + " " + numbered + " | " + numberRemoves)

      // The next row, or the one before when it was the last; by Delete and
      // Backspace, in a list longer than the view and in a short one.
      var takesPlace = function(pick, key) {
        mouseMove(body, 1, 1)
        keys.forceActiveFocus()
        var rows = watchlist.displayedSymbols.slice()
        service.feature(rows[0])
        var index = pick(rows)
        watchlist.select(rows[index])
        tryVerify(function() { return !watchlist.settling }, 2000)
        var removed = watchlist.cursorRow
        var expected = rows[index + 1] || rows[index - 1]
        keyClick(key)
        tryVerify(function() {
          return watchlist.displayedSymbols.every(function(symbol) { return !!watchlist.rowItem(symbol) })
        }, 2000)
        tryVerify(function() { return watchlist.cursorRow === expected && sight(expected) }, 2000)
        var got = watchlist.cursorRow
        var ok = removed === rows[index] && got === expected && sight(got)
        keyClick(Qt.Key_Z, Qt.ControlModifier)
        within(2000, function() { return watchlist.displayedSymbols.indexOf(removed) >= 0 && settled(watchlist) })
        return ok + " " + removed + "->" + got + " want " + expected
      }
      service.switchList("Tall")
      within(2000, function() { return settled(watchlist) })
      var longMiddle = takesPlace(function(rows) { return 3 }, Qt.Key_Delete)
      var longLast = takesPlace(function(rows) { return rows.length - 1 }, Qt.Key_Delete)
      openAt(heightBefore)
      var shortMiddle = takesPlace(function(rows) { return 2 }, Qt.Key_Backspace)
      var shortLast = takesPlace(function(rows) { return rows.length - 1 }, Qt.Key_Delete)
      service.switchList("")
      harness.check("removing the cursor's row hands the cursor to the row that takes its place: next, or previous at the end, long and short",
        [longMiddle, longLast, shortMiddle, shortLast].every(function(r) { return /^true /.test(r) }),
        [longMiddle, longLast, shortMiddle, shortLast].join(" | "))

      openAt(heightBefore)
      service.deleteList("Tall")
    }

    // The chart's own clicks and keys, and a scrub or a replay ended as the
    // data moves past it.
    function chartActions(body, keys) {
      service.persist({ style: "smooth" })
      service.feature("AAPL")
      body.selectRange("1Y")
      tryVerify(function() {
        return !service.testHistoryFeed.busy && service.histories["AAPL|1Y"]
          && service.histories["AAPL|1Y"].status === "ok" && body.historyShown && !body.chartLoading
      }, 10000)

      var middle = [body.chartItem.width / 2, body.chartItem.height / 2]
      mouseMove(body.chartItem, middle[0], middle[1])
      var scrubbed = within(1000, function() { return body.scrubT !== 0 })
      mouseClick(body.chartItem, middle[0], middle[1], Qt.LeftButton, Qt.ShiftModifier)
      harness.check("a Shift-click on the chart goes back to now, as a click does, and replays nothing",
        scrubbed && body.scrubT === 0 && !body.motion.replayRunning,
        scrubbed + "|" + body.scrubT + "|" + body.motion.replayRunning)
      body.resetInteraction()

      // The replay held at its moment, so this judges who owns the scrub,
      // whatever a pointer command takes.
      keys.forceActiveFocus()
      keyClick(Qt.Key_P)
      var replaying = within(2000, function() { return body.motion.replayRunning && body.scrubT !== 0 })
      body.motion.testReplay.pause()
      var replayT = body.scrubT
      mouseMove(body.chartItem, body.chartItem.width * 3 / 4, body.chartItem.height / 2)
      harness.check("range replay suppresses hover scrubbing",
        replaying && body.motion.replayRunning && body.scrubT === replayT, replaying + " " + replayT + " -> " + body.scrubT)
      body.resetInteraction()
      mouseMove(body, 1, 1)

      // A refresh that brings the next session ends a scrub by keys in smooth
      // and a replay in retro; a refetch whose history no longer covers the
      // bar a replay has reached ends that replay.
      var quotesBefore = service.testFeed.quotes
      service.setRange("1D")
      tryVerify(function() { return !body.chartLoading && body.motion.reveal === 1 }, 5000)
      keys.forceActiveFocus()
      for (var n = 0; n < 3; n++) keyClick(Qt.Key_Left)
      var scrubbedDay = body.scrubT !== 0
      nextDay("AAPL")
      var scrubEnded = scrubbedDay + "," + (body.scrubT === 0)
      service.persist({ style: "retro" })
      keyClick(Qt.Key_P)
      var replayingDay = within(2000, function() { return body.motion.replayRunning && body.scrubT !== 0 })
      nextDay("AAPL")
      var replayEnded = replayingDay + "," + (!body.motion.replayRunning && body.scrubT === 0)
      service.testFeed.quotes = quotesBefore
      service.persist({ style: "smooth" })
      service.setRange("1W")
      within(5000, function() { return body.historyShown && !body.chartLoading })
      body.replay()
      var replayingWeek = within(2000, function() { return body.motion.replayRunning && body.scrubT !== 0 })
      var next = Object.assign({}, service.testHistoryFeed.entries)
      var entry = next["AAPL|1W"]
      var history = Object.assign({}, entry.history)
      history.bars = entry.history.bars.map(function(bar) { return Object.assign({}, bar, { t: bar.t + 30 * 86400 }) })
      next["AAPL|1W"] = Object.assign({}, entry, { history: history })
      service.testHistoryFeed.entries = next
      var weekEnded = replayingWeek + "," + within(2000, function() { return !body.motion.replayRunning && body.scrubT === 0 })
      service.refresh()
      within(5000, function() { return !service.testHistoryFeed.busy && service.histories["AAPL|1W"].status === "ok" })
      harness.check("the next session ends the day's scrub and replay, smooth and retro",
        scrubEnded === "true,true" && replayEnded === "true,true" && weekEnded === "true,true",
        scrubEnded + " | " + replayEnded + " | week " + weekEnded)

      // On 1W in smooth and 1M in retro, then the day.
      var clickChange = function(range, look) {
        service.persist({ style: look })
        service.setRange(range)
        within(5000, function() { return !body.chartLoading && (range === "1D" ? !!body.featuredQuote : body.historyShown) })
        var change = harness.find(body, "changeText")
        var mode = service.changeMode
        mouseClick(change, change.width / 2, change.height / 2)
        var changed = service.changeMode !== mode
        service.persist({ changeMode: "pct" })
        return changed
      }
      var targets = [clickChange("1W", "smooth"), clickChange("1M", "retro"), clickChange("1D", "smooth")].join(",")
      harness.check("the hero's change cycles the mode only on the day: not on 1W or 1M",
        targets === "false,false,true", targets)

      // LATE's first quote fails, then lands after DOWN's close on a retry:
      // its animal comes asleep, the eyes never closing on the way.
      service.feature("DOWN")
      tryVerify(function() { return body.chartSymbol === "DOWN" && !body.chartLoading }, 5000)
      var header = harness.find(body, "animal").parent
      var close = service.quotes.DOWN.session.post.end
      service.testClockHeld = true
      service.now = close
      hold("LATE.down", true)
      service.addSymbol("LATE")
      tryVerify(function() { return service.arriving.indexOf("LATE") < 0 }, 15000)
      service.feature("LATE")
      tryVerify(function() { return body.chartSymbol === "LATE" && !body.featuredQuote && body.animal.kind === "" }, 5000)
      var closings = []
      var note = function() { closings.push(header.closing) }
      header.closingChanged.connect(note)
      hold("LATE.down", false)
      // A refresh asks what was answered over 10 s ago on the held clock.
      service.now = close + 15
      service.refresh()
      tryVerify(function() { return body.animal.kind !== "" }, 8000)
      // Longer than the 320 ms an eye-close would take to show.
      wait(400)
      header.closingChanged.disconnect(note)
      harness.check("a first quote landing on a retry after the close shows its animal asleep at once, no eye-close",
        body.animal.asleep && closings.join(",") === "1", body.animal.asleep + ", closing went " + closings.join(","))
      service.testClockHeld = false
      service.removeSymbol("LATE")
      service.feature("AAPL")
    }

    function test_flows() {
      tryVerify(function() {
        return service.quotes.AAPL && service.quotes.MSFT && service.quotes.NVDA
          && service.testFeed.firstRun.length + service.testFeed.refreshRun.length === 0
      }, 10000)

      // Five rows in the smallest window, which shows three, the last
      // featured from elsewhere.
      var heightAtStart = app.testWindow.implicitHeight
      var featuredAtStart = service.featuredSymbol
      ;["FLAT", "DOWN"].forEach(function(s) { service.addSymbol(s) })
      tryVerify(function() { return service.arriving.length === 0 && service.testFeed.firstRun.length + service.testFeed.refreshRun.length === 0 }, 8000)
      var lastSymbol = service.symbols[service.symbols.length - 1]
      app.testWindow.implicitHeight = 586
      service.feature(lastSymbol)
      app.open("{}")
      tryVerify(function() { return !!app.testBody && app.testWindow.height === 586 }, 2000)
      // Keys and the pointer reach a window once it has drawn.
      waitForRendering(app.testBody)
      var body = app.testBody
      var watchlist = body.watchlist
      var keys = app.testKeyCatcher
      var inSight = function(symbol) {
        var y = watchlist.displayedSymbols.indexOf(symbol) * watchlist.rowPitch
        return y >= watchlist.contentY - 0.5 && y + watchlist.rowHeight <= watchlist.contentY + watchlist.height + 0.5
      }
      within(1000, function() { return inSight(lastSymbol) })
      var firstOpen = [watchlist.cursorRow, watchlist.interactive, inSight(lastSymbol)].join(",")
      harness.check("the first open, which builds the body, brings the featured row into sight with the cursor on it",
        firstOpen === lastSymbol + ",true,true", lastSymbol + " -> " + firstOpen)

      // Four rows of five tall, the cursor on the last, then the smallest,
      // three. The body is resized as the window resizes it.
      body.height = body.smallestHeight + 3 * 42
      keys.forceActiveFocus()
      mouseMove(body, 1, 1)
      watchlist.contentY = 0
      service.feature(service.symbols[0])
      within(2000, function() { return settled(watchlist) })
      for (var d = 0; d < 6; d++) keyClick(Qt.Key_Down)
      tryVerify(function() { return !watchlist.settling }, 2000)
      var keyedLast = watchlist.cursorSymbol
      body.height = body.smallestHeight
      var lastIndex = watchlist.displayedSymbols.indexOf(keyedLast)
      within(1000, function() { return watchlist.wholeInSight(lastIndex, watchlist.headedY) })
      var shrunkKeeps = [keyedLast === lastSymbol, watchlist.cursorSymbol === keyedLast,
        watchlist.wholeInSight(lastIndex, watchlist.headedY)].join(",")
      harness.check("the window made shorter, its chart giving way, keeps a key cursor on the last row whole in sight",
        shrunkKeeps === "true,true,true", keyedLast + " -> " + watchlist.cursorSymbol + " " + shrunkKeeps)

      // Opened four rows tall on the last row, then tall enough for all
      // five, then four again, as Hyprland sizes the window 760, 850, then
      // 800 px.
      app.close()
      service.feature(lastSymbol)
      body.height = body.smallestHeight + 3 * 42
      app.open("{}")
      within(1000, function() { return settled(watchlist) })
      var openedOn = watchlist.cursorRow
      body.height = body.smallestHeight + 5 * 42
      // Every row fits: the next view the rows show pulls the scroll back
      // within them, to the top (Watchlist.display).
      watchlist.display(watchlist.displayedSymbols.slice(), false)
      var everyRow = function() { return watchlist.displayedSymbols.every(function(symbol, index) { return watchlist.wholeInSight(index, watchlist.contentY) }) }
      var allReachable = within(1000, everyRow)
      body.height = body.smallestHeight + 3 * 42
      var settledAt = watchlist.displayedSymbols.indexOf(lastSymbol)
      within(1000, function() { return watchlist.wholeInSight(settledAt, watchlist.headedY) })
      var settledOn = [openedOn, watchlist.cursorRow, watchlist.cursorSymbol === "", watchlist.wholeInSight(settledAt, watchlist.headedY)].join(",")
      harness.check("a window settling through sizes as it opens keeps the featured row in sight, the cursor resting on it",
        allReachable && settledOn === [lastSymbol, lastSymbol, true, true].join(","), lastSymbol + " -> " + settledOn)
      app.close()
      ;["FLAT", "DOWN"].forEach(function(s) { service.removeSymbol(s) })
      service.feature(featuredAtStart)
      openAt(heightAtStart)

      // The pointer moved while the window was closed: the compositor
      // reports it where it now rests, over another row, then again a pixel
      // off. Neither is a move.
      keys.forceActiveFocus()
      keyClick(Qt.Key_Down)
      var leftOn = watchlist.cursorRow
      app.close()
      app.open("{}")
      var restingOn = watchlist.displayedSymbols.filter(function(s) { return s !== service.featuredSymbol })[0]
      var restRow = watchlist.rowItem(restingOn)
      mouseMove(restRow, restRow.width / 2 + 30, restRow.height / 2)
      mouseMove(restRow, restRow.width / 2 + 30, restRow.height / 2 + 1)
      // Time for a move the reports wrongly made to show.
      wait(50)
      harness.check("a reopened window's cursor rests on the featured row, not the last visit's, nor under a pointer reported again",
        leftOn !== service.featuredSymbol && watchlist.cursorRow === service.featuredSymbol,
        leftOn + " -> " + watchlist.cursorRow + " for " + service.featuredSymbol + ", pointer on " + restingOn)

      var sheetRound = function(closeKey) {
        var first = watchlist.rowItem(watchlist.displayedSymbols[0])
        // The pointer comes onto the first row from the second, as a hand's
        // does, which puts the cursor there.
        mouseMove(first, first.width / 2, first.height / 2 + watchlist.rowPitch)
        mouseMove(first, first.width / 2, first.height / 2)
        within(1000, function() { return watchlist.cursorRow === watchlist.displayedSymbols[0] })
        keys.forceActiveFocus()
        keyClick(Qt.Key_Down)
        var keyed = watchlist.cursorRow
        keyClick(Qt.Key_Question, Qt.ShiftModifier)
        var opened = within(1000, function() { return body.showingHelp })
        keyClick(closeKey === "?" ? Qt.Key_Question : Qt.Key_Escape, closeKey === "?" ? Qt.ShiftModifier : Qt.NoModifier)
        within(1000, function() { return !body.showingHelp && !!watchlist.rowItem(watchlist.displayedSymbols[0]).visible })
        // The compositor reports the resting pointer again as the rows come
        // back, a pixel off its last report: a resting hand, no move.
        mouseMove(first, first.width / 2, first.height / 2 + 1)
        // Time for a move the report wrongly made to show.
        wait(50)
        return (opened && !body.showingHelp && keyed === watchlist.displayedSymbols[1] && watchlist.cursorRow === keyed)
          + " " + keyed + " -> " + watchlist.cursorRow
      }
      var byQuestion = sheetRound("?")
      var byEscape = sheetRound("Escape")
      harness.check("the key sheet closing under a resting pointer leaves the cursor where the keys put it, by ? and by Escape",
        /^true /.test(byQuestion) && /^true /.test(byEscape), byQuestion + " | " + byEscape)

      // The hero's row goes, featuring the next shown row; a row not the
      // hero goes without featuring another.
      var removedRow = watchlist.rowItem("MSFT")
      var heroWas = service.featuredSymbol
      mouseClick(removedRow, removedRow.width / 2, removedRow.height / 2, Qt.MiddleButton)
      var middleKept = harness.sameSymbols(["AAPL", "MSFT", "NVDA"]) && service.featuredSymbol === heroWas && body.rowMenu === null
      // Past the double-click interval of the middle-click at this place.
      wait(Application.styleHints.mouseDoubleClickInterval)
      var takeLine = function(row) {
        mouseClick(row, row.width / 2, row.height / 2, Qt.RightButton)
        tryVerify(function() { return harness.find(body, "rowMenuLine") !== null }, 1000)
        var line = harness.find(body, "rowMenuLine")
        mouseClick(line, line.width / 2, line.height / 2)
        within(1000, function() { return body.rowMenu === null && settled(watchlist) })
      }
      takeLine(removedRow)
      var heroHanded = harness.sameSymbols(["AAPL", "NVDA"]) && service.featuredSymbol === "NVDA"
      takeLine(watchlist.rowItem("AAPL"))
      var otherGone = harness.sameSymbols(["NVDA"]) && service.featuredSymbol === "NVDA"
      harness.check("a middle-click removes nothing, and a right-click's menu removes the row, featuring the next shown row",
        middleKept && heroWas === "MSFT" && heroHanded && otherGone,
        [middleKept, heroWas, heroHanded, otherGone, service.symbols, service.featuredSymbol].join("|"))

      ;["AAPL", "MSFT"].forEach(function(s) { service.addSymbol(s) })
      tryVerify(function() { return service.arriving.length === 0 && service.testFeed.firstRun.length + service.testFeed.refreshRun.length === 0 }, 8000)
      service.setManualOrder(["AAPL", "NVDA", "MSFT"])
      service.feature("AAPL")
      service.persist({ order: "pct" })
      within(2000, function() { return settled(watchlist) })
      var before = service.symbols.join(",")

      var widthBefore = app.testWindow.implicitWidth
      openAt(app.testWindow.implicitHeight, 1200)
      var menuRow = watchlist.rowItem(watchlist.cursorRow || "AAPL")
      mouseClick(menuRow, menuRow.width / 2, menuRow.height / 2, Qt.RightButton)
      within(1000, function() { return body.rowMenu !== null })
      var openWide = body.rowMenu !== null && app.testWindow.width > body.width + 200
      mouseClick(app.testWindow.contentItem, app.testWindow.width - 40, 200)
      within(1000, function() { return body.rowMenu === null })
      harness.check("in a wide window, a click on the margin closes the row's menu and removes nothing",
        openWide && body.rowMenu === null && service.symbols.join(",") === before,
        [openWide, body.rowMenu === null, service.symbols].join("|"))
      openAt(app.testWindow.implicitHeight, widthBefore)

      var refused = "Switch to manual order to move rows"
      watchlist.cursorSymbol = "AAPL"
      keys.forceActiveFocus()
      keyClick(Qt.Key_Down, Qt.ShiftModifier)
      harness.check("Shift+↓ cannot replace manual order from a sorted view",
        service.order === "pct" && service.symbols.join(",") === before && body.note === refused,
        [service.order, service.symbols, body.note].join("|"))

      body.clearNote()
      body.note = ""
      var sortedRow = watchlist.rowItem("NVDA")
      var sortedX = sortedRow.width / 2
      var sortedY = sortedRow.height / 2
      mousePress(sortedRow, sortedX, sortedY, Qt.LeftButton)
      mouseMove(sortedRow, sortedX, sortedY + 8)
      mouseMove(sortedRow, sortedX, sortedY)
      mouseRelease(sortedRow, sortedX, sortedY, Qt.LeftButton)
      // Longer than a drop's 160 ms, for one that moved a row to show.
      wait(200)
      harness.check("drag is inert instead of featuring from a sorted view",
        service.order === "pct" && service.symbols.join(",") === before
          && service.featuredSymbol === "AAPL" && watchlist.dragSymbol === "" && body.note === refused,
        [service.symbols, service.featuredSymbol, watchlist.dragSymbol, body.note].join("|"))
      body.clearNote()
      body.note = ""

      // Two slots each way, so a swap of the ends, or a move cut short in
      // either direction, cannot pass.
      service.persist({ order: "manual" })
      within(2000, function() { return settled(watchlist) })
      var drag = function(symbol, slots) {
        var y = watchlist.displayedSymbols.indexOf(symbol) * watchlist.rowPitch + watchlist.rowHeight / 2
        mousePress(watchlist, 20, y, Qt.LeftButton)
        mouseMove(watchlist, 20, y + slots * watchlist.rowPitch)
        mouseRelease(watchlist, 20, y + slots * watchlist.rowPitch, Qt.LeftButton)
        within(2000, function() { return watchlist.dragSymbol === "" && settled(watchlist) })
      }
      drag("AAPL", 2)
      var down = service.symbols.slice()
      drag("AAPL", -2)
      harness.check("drag still moves and persists in manual order, down and up",
        service.order === "manual" && down.join(",") === "NVDA,MSFT,AAPL"
          && harness.sameSymbols(["AAPL", "NVDA", "MSFT"]), down + " then " + service.symbols)

      // Three rows in manual order, MSFT featured on its year, the window
      // one row tall: the chart kept whole, as the window's own gives way
      // to three rows (StonksBody.minChartHeight).
      var orderBefore = service.order
      service.feature("MSFT")
      service.setRange("1Y")
      app.close()
      body.minChartHeight = 0
      openAt(body.chromeHeight + body.listRowHeight)
      mouseMove(body, 1, 1)

      // Only another list starts from the top.
      watchlist.contentY = watchlist.rowPitch
      keys.forceActiveFocus()
      keyClick(Qt.Key_O)
      harness.check("a new order keeps the list's scroll memory",
        service.order !== "manual" && watchlist.contentY === watchlist.rowPitch,
        service.order + "|" + watchlist.contentY)

      service.setOrder("symbol")
      within(2000, function() { return settled(watchlist) })
      var first = watchlist.displayedSymbols[0]
      body.removeRow(first)
      within(2000, function() { return settled(watchlist) })
      watchlist.contentY = watchlist.contentHeight - watchlist.height
      mouseMove(watchlist, 20, 20)
      within(1000, function() { return watchlist.sortHeld })
      keys.forceActiveFocus()
      keyClick(Qt.Key_Z, Qt.ControlModifier)
      var placedAt = watchlist.displayedSymbols.indexOf(first)
      tryVerify(function() { return watchlist.wholeInSight(placedAt, watchlist.contentY) }, 2000)
      harness.check("an undo under the pointer returns the row at its sorted place and brings it into reach",
        watchlist.sortHeld && placedAt === 0 && watchlist.wholeInSight(placedAt, watchlist.contentY),
        watchlist.sortHeld + "|" + placedAt)
      mouseMove(body, 1, 1)
      service.setOrder(orderBefore)

      keysActOnWhatYouChose(body, watchlist, keys)

      // The moves by wheel and drag start on the day.
      service.setRange("1D")
      within(5000, function() { return !body.chartLoading })

      movesByKeys(body, watchlist, keys)
      dragsAndTheWheel(body, watchlist, keys)
      cursorInSight(body, watchlist, keys)
      chartActions(body, keys)
      noticesInTheWindow(body)
      rowsOutOfSightHold(watchlist)
      app.close()
      harness.finish()
    }

    // Rows reached by a scroll show the newest answer, including a quote
    // that arrived while they were out of sight.
    function rowsOutOfSightHold(watchlist) {
      // All, with a dozen more rows than the window has room for. Yahoo's
      // budget is left as a minute's pause would leave it: these steps
      // come faster than anyone makes them, and a spark day waits for the
      // budget's spare half to be judged on its chart. Then nothing is out,
      // queued, or waiting to be judged: a chart judging a day replaces
      // that row's quote as it lands, and one landing between the moves
      // below would replace the price this step sets.
      service.switchList("")
      service.yahooGate.tokens = service.yahooGate.capacity
      for (var n = 1; n <= 12; n++) service.addSymbol("LONG" + n)
      tryVerify(function() {
        var feed = service.testFeed
        return service.arriving.length === 0 && feed.firstRun.length + feed.refreshRun.length === 0
          && feed.toJudge.length === 0 && Object.keys(feed.asked).length === 0
      }, 15000)
      watchlist.contentY = 0
      var shown = watchlist.displayedSymbols.slice()
      var far = shown.filter(function(s) { return watchlist.rowItem(s).y >= watchlist.height + watchlist.rowPitch })
      // Visit the distant rows before their next answer. Returning to them
      // must refresh an already shown price, not only build a new row.
      watchlist.contentY = watchlist.contentHeight - watchlist.height
      waitForRendering(watchlist)
      watchlist.contentY = 0
      waitForRendering(watchlist)
      var feed = service.testFeed
      var before = feed.quotes
      var moved = Object.assign({}, before)
      shown.forEach(function(s) { moved[s] = Object.assign({}, before[s], { price: 187.25 }) })
      feed.quotes = moved
      watchlist.contentY = watchlist.contentHeight - watchlist.height
      var cameIn = far.filter(function(s) {
        var row = watchlist.rowItem(s)
        return row.y + watchlist.rowHeight > watchlist.contentY && row.y < watchlist.contentY + watchlist.height
      })
      var current = function() {
        return cameIn.length > 0 && cameIn.every(function(s) {
          var row = watchlist.rowItem(s)
          return row.visible && harness.find(row, "rowContent") && harness.showsPrice(row, "187.25")
        })
      }
      within(3000, current)
      harness.check("scrolling to rows shows the latest prices that arrived out of sight", current(), cameIn.join(","))
      feed.quotes = before
      watchlist.contentY = 0
    }

    // The window's footer says the file's notice, and a real click on it
    // does nothing. Over a short list it sits one gap under the rows, not at
    // the window's bottom. A change while the file can't be read is said
    // unsaved, and why.
    function noticesInTheWindow(body) {
      openAt(760)
      service.createList("Short")
      service.setMembership("AAPL", "Short", true)
      service.switchList("Short")
      var footer = harness.find(body, "footer")
      var text = function() { return String(harness.find(footer, "footerText").text) }
      var good = harness.readFile(harness.dataPath)
      harness.writeFile(harness.dataPath, "{\n")
      var said = within(5000, function() { return text() === harness.fileNotice })
      mouseClick(footer, footer.width / 2, footer.height / 2)
      harness.check("the window's footer says the data file can't be read, and a click on it does nothing",
        said && !body.adding, text() + "|" + body.adding)
      var modeBefore = service.changeMode
      app.testKeyCatcher.forceActiveFocus()
      keyClick("c")
      var action = function() { return String(harness.find(footer, "footerAction").text) }
      var unsaved = within(3000, function() { return text() + action() === "Your changes aren't saved · couldn't load your lists" })
      mouseClick(footer, footer.width / 2, footer.height / 2)
      harness.check("a change while the data file can't be read applies, the window's footer says it isn't saved and why, a click on it does nothing, and the file is as it was",
        unsaved && service.changeMode !== modeBefore && !body.adding && harness.readFile(harness.dataPath) === "{\n",
        text() + action() + "|" + service.changeMode + "|" + body.adding)
      harness.writeFile(harness.dataPath, good)
      harness.check("fixed, the window's footer is the add again",
        within(5000, function() { return text().indexOf("+  Add a symbol") === 0 }), text())
      service.switchList("")
      service.deleteList("Short")
    }
  }
}
