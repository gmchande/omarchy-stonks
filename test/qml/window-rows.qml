import QtQuick
import QtTest
import Quickshell
import Quickshell.Io
import "plugin" as Stonks
import "plugin/Quote.js" as Quote
// The window's rows by hand, through the real App and Service with real Qt
// keys and pointer: removal by click, the sorted view's guards, the help
// sheet, moves by keys and drag, the wheel, the cursor, scrolling, undo,
// and rows held by a close. HOME and curl are scratch fixtures.
ShellRoot {
  id: harness

  property int failures: 0

  function check(label, ok, detail) {
    console.log((ok ? "PASS " : "FAIL ") + label + (!ok && detail !== undefined ? " — " + detail : ""))
    if (!ok) failures++
  }

  function same(got, want) {
    return !!got && got.join("|") === want.join("|")
  }

  function showsPrice(item, text) {
    if (!item || !item.visible) return false
    if (item.text !== undefined && String(item.text) === text) return true
    for (var i = 0; i < item.children.length; i++) if (showsPrice(item.children[i], text)) return true
    return item.contentItem ? showsPrice(item.contentItem, text) : false
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

  // The key column of a help sheet as drawn, groups in order.
  function sheetKeys(item) {
    var keys = []
    var walk = function(node) {
      if (!node) return
      if (node.objectName === "helpKey" && node.visible) keys.push(node.text)
      for (var i = 0; i < node.children.length; i++) walk(node.children[i])
    }
    walk(item)
    return keys
  }

  function sameSymbols(expected) {
    return service.symbols.join(",") === expected.join(",")
  }

  function finish() {
    console.log("WINDOW ROWS DONE")
    done.exitCode = failures ? 1 : 0
    done.start()
  }

  Stonks.Service { id: service }
  Stonks.Updates { id: updates }
  Stonks.App { id: app; service: service; updates: updates }

  readonly property string dataPath: Quickshell.env("HOME") + "/.config/omarchy/grvc.stonks.json"
  readonly property string manifestPath: String(Qt.resolvedUrl("plugin/manifest.json")).replace(/^file:\/\//, "")
  readonly property string fakeState: Quickshell.env("STONKS_FAKE_STATE")
  readonly property string fileNotice: "Couldn't load your lists"
  // A fresh view per read: a FileView that has loaded once can return its
  // old text.
  function readFile(path) {
    var view = Qt.createQmlObject('import Quickshell.Io; FileView { blockLoading: true; printErrors: false }', harness)
    view.path = path
    var text = String(view.text())
    view.destroy()
    return text
  }
  // Through a temporary file moved over it, as an editor's atomic save does.
  Process { id: writer }
  function writeFile(path, body) {
    writer.running = false
    writer.command = ["bash", "-c", "printf '%s' \"$1\" > \"$2.tmp\" && mv -f \"$2.tmp\" \"$2\"", "--", body, path]
    writer.running = true
  }

  TestCase {
    name: "WindowRows"
    when: service.pluginsReady

    // The keys the sheet draws, in order, opened with ? and closed again;
    // null when it did not open.
    function helpKeys(keys, body) {
      keys.forceActiveFocus()
      keyClick(Qt.Key_Question)
      wait(20)
      if (!body.showingHelp) return null
      var listed = harness.sheetKeys(harness.find(body, "helpSheet"))
      keyClick(Qt.Key_Escape)
      return listed
    }

    // Waits up to ms for fn to hold and returns whether it does, so the
    // check that reads it is the one that fails.
    function within(ms, fn) {
      for (var t = 0; t < ms && !fn(); t += 20) wait(20)
      return fn()
    }

    // The wheel session must end before its next input. Waiting for that
    // end prescribes no duration or easing; the oracle is the visible row.
    // A wheel notch is one row of input. Use visible row identities, not
    // a pixel offset or the duration of the glide.
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

    // Every key and click acts on the row you chose, as the rows show it.
    function keysActOnWhatYouChose(body, watchlist, keys) {
      var six = ["AAPL", "MSFT", "NVDA", "FLAT", "DOWN", "STRAY"]
      six.forEach(function(s) { service.addSymbol(s) })
      tryVerify(function() { return service.arriving.length === 0 && service.testFeed.firstRun.length + service.testFeed.refreshRun.length === 0 }, 8000)
      service.persist({ order: "manual", featured: "AAPL" })
      service.setManualOrder(six.concat(service.library.filter(function(s) { return six.indexOf(s) < 0 })))
      mouseMove(body, 1, 1)
      // Tall enough for every row.
      app.close()
      app.testWindow.implicitHeight = body.chromeHeight + 7 * body.rowPitch
      app.open("{}")
      wait(200)

      // Opening search keeps the cursor where you put it, and Escape brings
      // back the rows with it there: a, in All, and a click on the footer,
      // in a named list without the hero. Found in the transition audit
      // (search 2): the cursor jumped to the featured row, and ⏎ acted there.
      var throughSearch = function(open) {
        keys.forceActiveFocus()
        keyClick(Qt.Key_Down)
        keyClick(Qt.Key_Down)
        var chosen = watchlist.cursorRow
        open()
        wait(50)
        var during = watchlist.cursorRow
        keyClick(Qt.Key_Escape)
        wait(50)
        var after = watchlist.cursorRow
        keyClick(Qt.Key_Return)
        wait(50)
        return [chosen, during, after, service.featuredSymbol].join(">")
      }
      var inAll = throughSearch(function() { keyClick(Qt.Key_A) })
      service.createList("Pair")
      ;["NVDA", "FLAT", "DOWN", "STRAY", "MSFT"].forEach(function(s) { service.setMembership(s, "Pair", true) })
      service.feature("AAPL")
      wait(100)
      var inPair = throughSearch(function() {
        var footer = harness.find(body, "footer")
        mouseClick(footer, footer.width / 2, footer.height / 2)
      })
      harness.check("search keeps the cursor you set, and ⏎ after it acts there: a in All, the footer in a list",
        inAll === "NVDA>NVDA>NVDA>NVDA" && inPair === "DOWN>DOWN>DOWN>DOWN", inAll + " | " + inPair)

      // A rename is the same list: its rows keep their scroll and the cursor,
      // with a cursor of its own in manual order, and without one in a sorted
      // order scrolled to its end. Found in the transition audit (lists 6):
      // the rows came back at the top, as if another list had been chosen.
      var heightBefore = app.testWindow.implicitHeight
      app.close()
      app.testWindow.implicitHeight = body.chromeHeight + 3 * body.rowPitch
      app.open("{}")
      wait(200)
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
        wait(50)
        for (var i = 0; i < to.length; i++) keyClick(to.charAt(i))
        keyClick(Qt.Key_Return)
        wait(50)
        keyClick(Qt.Key_Escape)
        wait(100)
        return [service.listName === to, scrolled > 0, firstWhole(watchlist) === scrolled, watchlist.cursorSymbol === cursor].join(",")
          + " " + cursor + "@" + scrolled + "->" + watchlist.cursorSymbol + "@" + firstWhole(watchlist)
      }
      keys.forceActiveFocus()
      for (var d = 0; d < 4; d++) keyClick(Qt.Key_Down)
      tryVerify(function() { return firstWhole(watchlist) > 0 && watchlist.wholeInSight(watchlist.displayedSymbols.indexOf(watchlist.cursorRow), watchlist.contentY) }, 2000)
      var ownCursor = rename("Pairs")
      service.setOrder("symbol")
      wait(50)
      watchlist.cursorSymbol = ""
      watchlist.contentY = watchlist.contentHeight - watchlist.height
      var sortedEnd = rename("Pair")
      harness.check("a rename keeps the rows' scroll and cursor, manual with a cursor and sorted at the end",
        /^true,true,true,true /.test(ownCursor) && /^true,true,true,true /.test(sortedEnd), ownCursor + " | " + sortedEnd)
      app.close()
      app.testWindow.implicitHeight = heightBefore
      app.open("{}")
      wait(200)

      // While the pointer holds rows a refresh has re-ranked, ↓ then Enter
      // and a removal's hand-off read the rows as they are on screen: the
      // first row on All by % change, the second on a list by $ change, and
      // the hero's neighbour after a middle-click and after Delete. Found in
      // the transition audit (lists 5, featured 4): a row key featured the
      // row a refresh ranked first, not the one shown first, and the hero
      // went to the service's neighbour.
      var quotesBefore = service.testFeed.quotes
      var rank = function(changes) {
        var next = Object.assign({}, service.testFeed.quotes)
        for (var s in changes) next[s] = movedBy(s, changes[s])
        service.testFeed.quotes = next
      }
      var hold = function() {
        var first = watchlist.rowItem(watchlist.displayedSymbols[0])
        mouseMove(first, first.width / 2, first.height / 2)
        wait(50)
      }
      var pickHeld = function(index, reranked) {
        hold()
        var onScreen = watchlist.displayedSymbols.slice()
        watchlist.cursorSymbol = onScreen[0]
        rank(reranked)
        wait(50)
        var rearranged = service.view.shown.join() !== onScreen.join() && watchlist.displayedSymbols.join() === onScreen.join()
        keys.forceActiveFocus()
        for (var i = 0; i < index; i++) keyClick(Qt.Key_Down)
        keyClick(Qt.Key_Return)
        wait(50)
        return rearranged + "," + (service.featuredSymbol === onScreen[index]) + " " + onScreen[index] + "->" + service.featuredSymbol
      }
      service.switchList("")
      service.setOrder("pct")
      rank({ AAPL: 6, MSFT: 5, NVDA: 4, FLAT: 3, DOWN: 2, STRAY: 1 })
      wait(100)
      var onePct = pickHeld(0, { STRAY: 10 })
      mouseMove(body, 1, 1)
      service.switchList("Pair")
      service.setOrder("pct")
      service.reverseOrder()
      rank({ MSFT: 5, NVDA: 4, FLAT: 3, DOWN: 2, STRAY: 1 })
      wait(100)
      var twoReversed = pickHeld(1, { DOWN: 50 })
      harness.check("arrows and Enter feature the row shown there while the pointer holds re-ranked rows, by % in All and reversed in a list",
        /^true,true /.test(onePct) && /^true,true /.test(twoReversed), onePct + " | " + twoReversed)
      mouseMove(body, 1, 1)
      service.switchList("")
      service.setOrder("pct")
      var handOff = function(remove) {
        rank({ AAPL: 6, MSFT: 5, NVDA: 4, FLAT: 3, DOWN: 2, STRAY: 1 })
        service.feature("MSFT")
        wait(100)
        hold()
        var onScreen = watchlist.displayedSymbols.slice()
        rank({ FLAT: 4.5 })
        wait(50)
        var next = onScreen[onScreen.indexOf("MSFT") + 1]
        remove()
        wait(100)
        var got = service.featuredSymbol
        mouseMove(body, 1, 1)
        keys.forceActiveFocus()
        keyClick(Qt.Key_Z, Qt.ControlModifier)
        wait(100)
        return (got === next) + " " + next + "->" + got
      }
      // Pair holds MSFT too, so in All the menu's one line, and Delete's,
      // reach both lists.
      var byClick = handOff(function() {
        var row = watchlist.rowItem("MSFT")
        mouseClick(row, row.width / 2, row.height / 2, Qt.RightButton)
        wait(50)
        var line = harness.find(body, "rowMenuLine")
        mouseClick(line, line.width / 2, line.height / 2)
      })
      var byKey = handOff(function() {
        watchlist.cursorSymbol = "MSFT"
        keys.forceActiveFocus()
        keyClick(Qt.Key_Delete)
        wait(50)
        keyClick(Qt.Key_Return)
      })
      harness.check("removing the held hero hands it to its neighbour on screen, by a right-click's menu and by Delete",
        /^true /.test(byClick) && /^true /.test(byKey), byClick + " | " + byKey)
      service.testFeed.quotes = quotesBefore
      service.deleteList("Pair")
      service.setOrder("manual")
      wait(100)
    }

    // Moving a row by Shift+↓ and Shift+↑, and the keys that carry the cursor past the
    // edge: the list gliding along so nothing jumps on screen. Shift and the
    // wheel scroll as the wheel does.
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

      // A move past the edge of the view carries the list along: the moved
      // row keeps its place on screen on every frame, Shift+↓ at the bottom and Shift+↑
      // at the top of a list scrolled to its end; ↓ past the edge glides the
      // list. Found in the transition audit (lists 0, featured 5): the list
      // jumped a row, the moved row a slot the wrong way, and the two crossed
      // back.
      var heightBefore = app.testWindow.implicitHeight
      app.close()
      app.testWindow.implicitHeight = body.chromeHeight + 3 * body.rowPitch
      app.open("{}")
      wait(200)
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
      wait(50)
      var topRow = watchlist.displayedSymbols[3]
      watchlist.cursorSymbol = topRow
      keys.forceActiveFocus()
      var kAtTop = carried(topRow, function() { keyClick(Qt.Key_Up, Qt.ShiftModifier) })
      // Shift and a notch over a row scroll the list a row, as a notch does,
      // and leave the order as it was.
      var notchOver = function(modifiers) {
        reset("", "smooth")
        var before = watchlist.displayedSymbols.join(",")
        var at = watchlist.mapToItem(body, watchlist.width / 2, 2 * watchlist.rowPitch + watchlist.rowHeight / 2)
        mouseMove(body, at.x, at.y)
        wait(50)
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
      app.close()
      app.testWindow.implicitHeight = heightBefore
      app.open("{}")
      wait(200)
      service.persist({ style: "smooth" })
      service.switchList("")
      service.deleteList("Moves")
      wait(50)
    }

    // A drag and the wheel: the lifted row stays under the pointer, a drag or
    // anything else that takes the list from the wheel leaves it on a row, a
    // new order ends a drag, and a close holds a drag where it is.
    function dragsAndTheWheel(body, watchlist, keys) {
      var six = ["AAPL", "MSFT", "NVDA", "FLAT", "DOWN", "STRAY"]
      service.createList("Drags")
      six.forEach(function(s) { service.setMembership(s, "Drags", true) })
      var heightBefore = app.testWindow.implicitHeight
      app.close()
      app.testWindow.implicitHeight = body.chromeHeight + 3 * body.rowPitch
      app.open("{}")
      wait(200)
      // Coordinates for the next gesture belong to rows that have landed.
      var ready = function() { return watchlist.dragSymbol === "" && !watchlist.settling && watchlist.displayedSymbols.every(function(symbol) { return watchlist.rowResting(symbol) }) }
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
        wait(50)
        return Qt.point(at.x, at.y + by)
      }
      var canAct = function() { return watchlist.cursorRow !== "" && watchlist.wholeInSight(watchlist.displayedSymbols.indexOf(watchlist.cursorRow), watchlist.contentY) }

      // Found in the transition audit (lists 3): the wheel scrolled the
      // lifted row away from the pointer, and it snapped back on the next
      // move. Down from the top in smooth, up from the end in retro.
      var underPointer = function(symbol, by, notch) {
        var at = lift(symbol, by)
        var row = watchlist.rowItem(symbol)
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
      wait(50)
      var wheelUp = underPointer(watchlist.displayedSymbols[5], -8, 120)
      harness.check("the wheel during a drag keeps the chosen symbol, down in smooth and up in retro",
        /^true /.test(wheelDown) && /^true /.test(wheelUp), wheelDown + " | " + wheelUp)

      // Found in the transition audit (lists 11): o mid-drag carried the drag
      // into the sorted list, and the release dropped the row into the
      // dragged slot, then snapped it to its sorted place.
      var orderMidDrag = function() {
        var saved = service.symbols.join()
        var at = lift("AAPL", body.rowPitch * 2)
        keys.forceActiveFocus()
        keyClick(Qt.Key_O)
        var ended = watchlist.dragSymbol === ""
        within(2000, ready)
        var shown = watchlist.displayedSymbols.join(",")
        mouseRelease(body, at.x, at.y)
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

      // Found in the transition audit (lists 4, lifecycle 5): a drag or an
      // undo started as the wheel was still settling, or a close mid-glide,
      // left the list part way into a row until the next scroll.
      reset("", "smooth")
      var at = centre("AAPL")
      mouseWheel(body, at.x, at.y, 0, -60)
      wait(40)
      lift("AAPL", 8)
      mouseRelease(body, at.x, at.y + 8)
      within(2000, ready)
      var afterDrag = canAct() + "@" + watchlist.cursorRow
      reset("Drags", "retro")
      watchlist.cursorSymbol = "MSFT"
      keys.forceActiveFocus()
      keyClick(Qt.Key_Delete)
      wait(100)
      at = centre("AAPL")
      mouseWheel(body, at.x, at.y, 0, -60)
      wait(40)
      keyClick(Qt.Key_Z, Qt.ControlModifier)
      within(2000, ready)
      var afterUndo = canAct() + "@" + watchlist.cursorRow
      mouseMove(body, 1, 1)
      reset("", "smooth")
      at = centre("AAPL")
      mouseWheel(body, at.x, at.y, 0, -120)
      wait(60)
      app.close()
      app.open("{}")
      var afterNotch = canAct() + "@" + watchlist.cursorRow
      wait(300)
      reset("Drags", "retro")
      at = centre("AAPL")
      mouseWheel(body, at.x, at.y, 0, -40)
      wait(40)
      app.close()
      app.open("{}")
      var afterTick = canAct() + "@" + watchlist.cursorRow
      wait(300)
      harness.check("a drag, undo and close during wheel input leave an actionable cursor",
        [afterDrag, afterUndo, afterNotch, afterTick].every(function(r) { return /^true@/.test(r) }),
        [afterDrag, afterUndo, afterNotch, afterTick].join(" | "))

      // Found in the transition audit (lists 12, lifecycle 12): a close
      // mid-drag dropped the lifted row back to its slot on the first frame
      // of the fade, and the rows that made room slid back.
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

      app.close()
      app.testWindow.implicitHeight = heightBefore
      app.open("{}")
      wait(200)
      service.persist({ style: "smooth" })
      service.switchList("")
      service.deleteList("Drags")
      wait(50)
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
      app.close()
      app.testWindow.implicitHeight = body.chromeHeight + 3 * body.rowPitch
      app.open("{}")
      wait(200)
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
        wait(50)
        if (body.rowMenu !== null) keyClick(Qt.Key_Return)
        wait(50)
        var took = service.lastRemoval ? service.lastRemoval.symbol : ""
        keyClick(Qt.Key_Z, Qt.ControlModifier)
        wait(100)
        return (shown && took === cursor) + " " + cursor + " " + took
      }

      // Found in the transition audit (lists 7, featured 5): after a list
      // switch, or the hero stepped out of sight by the pill, the cursor sat
      // on the hero's row below the fold, and Delete took a row you never saw.
      service.feature("STRAY")
      wait(100)
      service.switchList("Tall")
      wait(100)
      var afterSwitch = removesInSight()
      service.switchList("")
      wait(100)
      watchlist.contentY = 0
      service.feature("AAPL")
      wait(50)
      service.featureStep(4)
      wait(100)
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

      // ↓ and Enter feature a row below the fold and glide it into view,
      // the cursor with it, so its highlight shows and Delete takes it.
      // Found in the edge-case pass of 15 October: a row key featured a row
      // below the fold unseen.
      watchlist.contentY = 0
      service.feature(watchlist.displayedSymbols[0])
      wait(50)
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

      // A reopened surface brings the featured row into sight, its cursor
      // on it, so Enter and Delete act on the row the hero shows. Found in the
      // walk of dev on 14 October: featured from the pill below the fold,
      // the popup opened with the cursor on its top row, and Enter
      // featured that. Popup and window open through the same reset.
      watchlist.contentY = 0
      wait(50)
      var below = watchlist.displayedSymbols[watchlist.displayedSymbols.length - 1]
      var featuredBefore = service.featuredSymbol
      app.close()
      wait(200)
      service.feature(below)
      app.open("{}")
      wait(200)
      var openedOn = watchlist.cursorRow + " " + sight(below)
      harness.check("a reopened surface brings the featured row into sight with the cursor on it",
        !sight(watchlist.displayedSymbols[0]) && openedOn === below + " true", below + " -> " + openedOn)
      service.feature(featuredBefore)
      wait(50)

      // Removing the row the cursor is on hands the cursor to the row that
      // takes its place, as Mail and Finder do: the next row, or the one
      // before when it was the last; by Delete and Backspace, in a list
      // longer than the view and in a short one. Found in the live run of
      // #26: the cursor went to the first row in sight.
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
        wait(100)
        return ok + " " + removed + "->" + got + " want " + expected
      }
      service.switchList("Tall")
      wait(100)
      var longMiddle = takesPlace(function(rows) { return 3 }, Qt.Key_Delete)
      var longLast = takesPlace(function(rows) { return rows.length - 1 }, Qt.Key_Delete)
      app.close()
      app.testWindow.implicitHeight = heightBefore
      app.open("{}")
      wait(200)
      var shortMiddle = takesPlace(function(rows) { return 2 }, Qt.Key_Backspace)
      var shortLast = takesPlace(function(rows) { return rows.length - 1 }, Qt.Key_Delete)
      service.switchList("")
      wait(100)
      harness.check("removing the cursor's row hands the cursor to the row that takes its place: next, or previous at the end, long and short",
        [longMiddle, longLast, shortMiddle, shortLast].every(function(r) { return /^true /.test(r) }),
        [longMiddle, longLast, shortMiddle, shortLast].join(" | "))

      app.close()
      app.testWindow.implicitHeight = heightBefore
      app.open("{}")
      wait(200)
      service.deleteList("Tall")
      wait(50)
    }

    function test_flows() {
      tryVerify(function() {
        return service.quotes.AAPL && service.quotes.MSFT && service.quotes.NVDA
          && service.testFeed.firstRun.length + service.testFeed.refreshRun.length === 0
      }, 10000)

      // The very first open, which builds the body, brings the
      // featured row into sight too: five rows in the smallest window,
      // which shows three, the last featured from elsewhere.
      var heightAtStart = app.testWindow.implicitHeight
      var featuredAtStart = service.featuredSymbol
      ;["FLAT", "DOWN"].forEach(function(s) { service.addSymbol(s) })
      tryVerify(function() { return service.arriving.length === 0 && service.testFeed.firstRun.length + service.testFeed.refreshRun.length === 0 }, 8000)
      var lastSymbol = service.symbols[service.symbols.length - 1]
      app.testWindow.implicitHeight = 586
      service.feature(lastSymbol)
      app.open("{}")
      wait(200)
      var body = app.testBody
      var watchlist = body.watchlist
      var keys = app.testKeyCatcher
      var lastAt = watchlist.displayedSymbols.indexOf(lastSymbol) * watchlist.rowPitch
      var firstOpen = [watchlist.cursorRow, watchlist.interactive,
        lastAt >= watchlist.contentY - 0.5 && lastAt + watchlist.rowHeight <= watchlist.contentY + watchlist.height + 0.5].join(",")
      harness.check("the first open, which builds the body, brings the featured row into sight with the cursor on it",
        firstOpen === lastSymbol + ",true,true", lastSymbol + " -> " + firstOpen)

      // The window made shorter, its chart giving way, keeps a key cursor
      // on its last row: four rows of five tall, the cursor on the last,
      // then the smallest, three. The body is resized as the window resizes
      // it: an offscreen window takes a new size only as it opens.
      body.height = body.smallestHeight + 3 * 42
      wait(100)
      keys.forceActiveFocus()
      mouseMove(body, 1, 1)
      watchlist.contentY = 0
      service.feature(service.symbols[0])
      wait(100)
      for (var d = 0; d < 6; d++) keyClick(Qt.Key_Down)
      tryVerify(function() { return !watchlist.settling }, 2000)
      var keyedLast = watchlist.cursorSymbol
      body.height = body.smallestHeight
      wait(100)
      var lastIndex = watchlist.displayedSymbols.indexOf(keyedLast)
      var shrunkKeeps = [keyedLast === lastSymbol, watchlist.cursorSymbol === keyedLast,
        watchlist.wholeInSight(lastIndex, watchlist.headedY)].join(",")
      harness.check("the window made shorter, its chart giving way, keeps a key cursor on the last row whole in sight",
        shrunkKeeps === "true,true,true", keyedLast + " -> " + watchlist.cursorSymbol + " " + shrunkKeeps)

      // A window settling through sizes as it opens keeps the featured row
      // the open brought into sight: opened four rows tall on the last row,
      // then tall enough for all five, then four again, as Hyprland sized
      // the window 760, 850, then 800 px. Found in the tophat of 15
      // October: the list stayed at its top, the featured row under the
      // footer, and the cursor on the first row.
      app.close()
      wait(100)
      service.feature(lastSymbol)
      body.height = body.smallestHeight + 3 * 42
      app.open("{}")
      wait(200)
      var openedOn = watchlist.cursorRow
      body.height = body.smallestHeight + 5 * 42
      // Every row fits: the next view the rows show pulls the scroll back
      // within them, to the top (Watchlist.display), as one did then.
      watchlist.display(watchlist.displayedSymbols.slice(), false)
      wait(100)
      var allReachable = watchlist.displayedSymbols.every(function(symbol, index) { return watchlist.wholeInSight(index, watchlist.contentY) })
      body.height = body.smallestHeight + 3 * 42
      wait(100)
      var settledAt = watchlist.displayedSymbols.indexOf(lastSymbol)
      var settled = [openedOn, watchlist.cursorRow, watchlist.cursorSymbol === "", watchlist.wholeInSight(settledAt, watchlist.headedY)].join(",")
      harness.check("a window settling through sizes as it opens keeps the featured row in sight, the cursor resting on it",
        allReachable && settled === [lastSymbol, lastSymbol, true, true].join(","), lastSymbol + " -> " + settled)
      app.close()
      app.testWindow.implicitHeight = heightAtStart
      ;["FLAT", "DOWN"].forEach(function(s) { service.removeSymbol(s) })
      service.feature(featuredAtStart)
      app.open("{}")
      wait(200)

      // A reopened window's cursor rests on the featured row, not where the
      // last visit left it. Found in the live check of #9: the bar stayed on
      // the last visit's row, so Enter, Delete, and the arrows acted on it.
      keys.forceActiveFocus()
      keyClick(Qt.Key_Down)
      wait(50)
      var leftOn = watchlist.cursorRow
      app.close()
      wait(200)
      app.open("{}")
      wait(200)
      // The pointer moved while the window was closed: the compositor
      // reports it where it now rests, over another row, then again a pixel
      // off. Neither is a move. From Grok's review of #19: the second moved
      // the cursor onto that row.
      var restingOn = watchlist.displayedSymbols.filter(function(s) { return s !== service.featuredSymbol })[0]
      var restRow = watchlist.rowItem(restingOn)
      mouseMove(restRow, restRow.width / 2 + 30, restRow.height / 2)
      mouseMove(restRow, restRow.width / 2 + 30, restRow.height / 2 + 1)
      wait(50)
      harness.check("a reopened window's cursor rests on the featured row, not the last visit's, nor under a pointer reported again",
        leftOn !== service.featuredSymbol && watchlist.cursorRow === service.featuredSymbol,
        leftOn + " -> " + watchlist.cursorRow + " for " + service.featuredSymbol + ", pointer on " + restingOn)

      // The key sheet showing and going again under a resting pointer moves
      // no cursor: the rows come back with the cursor the keys left, closed
      // by ? and by Escape. Found in the live check of #9: the cursor came
      // back on the row under the still pointer.
      var sheetRound = function(closeKey) {
        var first = watchlist.rowItem(watchlist.displayedSymbols[0])
        // The pointer comes onto the first row from the second, as a hand's
        // does, which puts the cursor there.
        mouseMove(first, first.width / 2, first.height / 2 + watchlist.rowPitch)
        mouseMove(first, first.width / 2, first.height / 2)
        wait(50)
        keys.forceActiveFocus()
        keyClick(Qt.Key_Down)
        wait(50)
        var keyed = watchlist.cursorRow
        keyClick(Qt.Key_Question, Qt.ShiftModifier)
        wait(100)
        var opened = body.showingHelp
        keyClick(closeKey === "?" ? Qt.Key_Question : Qt.Key_Escape, closeKey === "?" ? Qt.ShiftModifier : Qt.NoModifier)
        wait(200)
        // The compositor reports the resting pointer again as the rows come
        // back, a pixel off its last report: a resting hand, no move.
        mouseMove(first, first.width / 2, first.height / 2 + 1)
        wait(50)
        return (opened && !body.showingHelp && keyed === watchlist.displayedSymbols[1] && watchlist.cursorRow === keyed)
          + " " + keyed + " -> " + watchlist.cursorRow
      }
      var byQuestion = sheetRound("?")
      var byEscape = sheetRound("Escape")
      harness.check("the key sheet closing under a resting pointer leaves the cursor where the keys put it, by ? and by Escape",
        /^true /.test(byQuestion) && /^true /.test(byEscape), byQuestion + " | " + byEscape)

      // A middle-click removes nothing. A right-click opens the row's menu,
      // and its line removes the row, handing the hero on to the next shown
      // row; a row not the hero goes without featuring another.
      var removedRow = watchlist.rowItem("MSFT")
      var heroWas = service.featuredSymbol
      mouseClick(removedRow, removedRow.width / 2, removedRow.height / 2, Qt.MiddleButton)
      wait(100)
      var middleKept = harness.sameSymbols(["AAPL", "MSFT", "NVDA"]) && service.featuredSymbol === heroWas && body.rowMenu === null
      // Past the double-click interval of the middle-click at this place.
      wait(Application.styleHints.mouseDoubleClickInterval)
      var takeLine = function(row) {
        mouseClick(row, row.width / 2, row.height / 2, Qt.RightButton)
        wait(100)
        var line = harness.find(body, "rowMenuLine")
        mouseClick(line, line.width / 2, line.height / 2)
        wait(100)
      }
      takeLine(removedRow)
      harness.check("a middle-click removes nothing, and a right-click's menu removes the row, featuring the next shown row",
        middleKept && heroWas === "MSFT" && harness.sameSymbols(["AAPL", "NVDA"]) && service.featuredSymbol === "NVDA",
        [middleKept, heroWas, service.symbols, service.featuredSymbol].join("|"))

      service.addSymbol("MSFT")
      service.feature("AAPL")
      service.persist({ order: "pct" })
      wait(100)
      var before = service.symbols.join(",")
      wait(Application.styleHints.mouseDoubleClickInterval)
      takeLine(watchlist.rowItem("NVDA"))
      harness.check("a right-click's menu removes a row without featuring it",
        harness.sameSymbols(["AAPL", "MSFT"]) && service.featuredSymbol === "AAPL", service.symbols + "|" + service.featuredSymbol)
      service.persist({ symbols: before.split(","), featured: "AAPL" })
      tryVerify(function() { return service.quotes.NVDA && service.testFeed.firstRun.length + service.testFeed.refreshRun.length === 0 }, 10000)
      wait(50)

      // In a window wider than the body, a click on its margin, past the
      // rows, closes the row's menu too, removing nothing. Found in the walk
      // of 22 October: there it stayed open.
      var widthBefore = app.testWindow.implicitWidth
      app.close()
      app.testWindow.implicitWidth = 1200
      app.open("{}")
      wait(200)
      var menuRow = watchlist.rowItem(watchlist.cursorRow || "AAPL")
      mouseClick(menuRow, menuRow.width / 2, menuRow.height / 2, Qt.RightButton)
      wait(100)
      var openWide = body.rowMenu !== null && app.testWindow.width > body.width + 200
      mouseClick(app.testWindow.contentItem, app.testWindow.width - 40, 200)
      wait(100)
      harness.check("in a wide window, a click on the margin closes the row's menu and removes nothing",
        openWide && body.rowMenu === null && service.symbols.join(",") === before,
        [openWide, body.rowMenu === null, service.symbols].join("|"))
      app.close()
      app.testWindow.implicitWidth = widthBefore
      app.open("{}")
      wait(200)

      watchlist.cursorSymbol = "AAPL"
      keys.forceActiveFocus()
      keyClick(Qt.Key_Down, Qt.ShiftModifier)
      wait(20)
      harness.check("Shift+↓ cannot replace manual order from a sorted view",
        service.order === "pct" && service.symbols.join(",") === before)

      var sortedRow = watchlist.rowItem("NVDA")
      var sortedX = sortedRow.width / 2
      var sortedY = sortedRow.height / 2
      mousePress(sortedRow, sortedX, sortedY, Qt.LeftButton)
      mouseMove(sortedRow, sortedX, sortedY + 8)
      mouseMove(sortedRow, sortedX, sortedY)
      mouseRelease(sortedRow, sortedX, sortedY, Qt.LeftButton)
      wait(200)
      harness.check("drag is inert instead of featuring from a sorted view",
        service.order === "pct" && service.symbols.join(",") === before
          && service.featuredSymbol === "AAPL" && watchlist.dragSymbol === "")

      // The sheet draws the move keys only on manual, where they act.
      var sortedHelp = helpKeys(keys, body)
      service.persist({ order: "manual" })
      var manualHelp = helpKeys(keys, body)
      harness.check("the move keys are shown only where manual order lets them act",
        sortedHelp.indexOf("⇧↑ ⇧↓") < 0 && manualHelp.indexOf("⇧↑ ⇧↓") >= 0 && sortedHelp.indexOf("↑ ↓") >= 0,
        sortedHelp + " | " + manualHelp)

      watchlist.cursorSymbol = "AAPL"
      keys.forceActiveFocus()
      keyClick(Qt.Key_Down, Qt.ControlModifier | Qt.ShiftModifier)
      wait(20)
      harness.check("Ctrl+Shift+↓ does not reorder",
        service.order === "manual" && harness.sameSymbols(["AAPL", "NVDA", "MSFT"]))

      watchlist.cursorSymbol = "AAPL"
      keys.forceActiveFocus()
      keyClick(Qt.Key_Down, Qt.ShiftModifier)
      wait(100)
      harness.check("Shift+↓ still moves and persists in manual order",
        service.order === "manual" && harness.sameSymbols(["NVDA", "AAPL", "MSFT"]))

      // Two slots each way, so a swap of the ends, or a move cut short in
      // either direction, cannot pass.
      var drag = function(symbol, slots) {
        var y = watchlist.displayedSymbols.indexOf(symbol) * watchlist.rowPitch + watchlist.rowHeight / 2
        mousePress(watchlist, 20, y, Qt.LeftButton)
        mouseMove(watchlist, 20, y + slots * watchlist.rowPitch)
        mouseRelease(watchlist, 20, y + slots * watchlist.rowPitch, Qt.LeftButton)
        wait(250)
      }
      drag("NVDA", 2)
      var down = service.symbols.slice()
      drag("NVDA", -2)
      harness.check("drag still moves and persists in manual order, down and up",
        service.order === "manual" && down.join(",") === "AAPL,MSFT,NVDA"
          && harness.sameSymbols(["NVDA", "AAPL", "MSFT"]), down + " then " + service.symbols)

      // These flows start from three rows in this order, MSFT featured on its
      // year, the window one row tall, in manual order, which they go back to.
      var orderBefore = service.order
      service.setManualOrder(["AAPL", "NVDA", "MSFT"])
      service.feature("MSFT")
      service.setRange("1Y")
      app.close()
      // One row tall: the chart kept whole, as the window's own gives way
      // to three rows (StonksBody.minChartHeight).
      body.minChartHeight = 0
      app.testWindow.implicitHeight = body.chromeHeight + body.listRowHeight
      app.open("{}")
      wait(300)

      // A removal near the end of a list scrolled to its end moves only the
      // rows closing the gap: the rows below it stay where they are on
      // screen, the rows above slide down. Found in the code-quality review:
      // the list's scroll was pulled back a row in one frame, so every row
      // jumped, and the ones below slid back.
      service.setOrder("manual")
      ;["DOWN", "FLAT", "STRAY"].forEach(function(s) { service.addSymbol(s) })
      tryVerify(function() { return service.arriving.length === 0 && watchlist.displayedSymbols.length === 6 }, 5000)
      mouseMove(body, 1, 1)
      var heightBefore = app.testWindow.implicitHeight
      app.close()
      app.testWindow.implicitHeight = body.chromeHeight + 3 * body.rowPitch
      app.open("{}")
      wait(300)
      watchlist.contentY = watchlist.contentHeight - watchlist.height
      wait(50)
      var removed = watchlist.displayedSymbols[4]
      var keptRows = watchlist.displayedSymbols.filter(function(symbol) { return symbol !== removed })
      body.removeRow(removed)
      harness.check("removing a row near the end preserves every other row and its order",
        harness.same(watchlist.displayedSymbols, keptRows), watchlist.displayedSymbols.join(","))

      // A new order lays the rows out at once and keeps the list where it is
      // scrolled; only another list starts from the top. Found in the
      // code-quality review: whether o scrolled to the top depended on which
      // of the order and the rows reached the list first.
      watchlist.contentY = watchlist.rowPitch
      keys.forceActiveFocus()
      keyClick(Qt.Key_O)
      harness.check("a new order keeps the list's scroll memory",
        service.order !== "manual" && watchlist.contentY === watchlist.rowPitch,
        service.order + "|" + watchlist.contentY )

      // An undo brings the row back at its sorted place even while the
      // pointer holds the list, and eases the list to it. Found in the
      // code-quality review: it came back at the bottom, the list jumped
      // there, and it slid up once the pointer left.
      service.setOrder("symbol")
      wait(50)
      var first = watchlist.displayedSymbols[0]
      body.removeRow(first)
      wait(50)
      watchlist.contentY = watchlist.contentHeight - watchlist.height
      mouseMove(watchlist, 20, 20)
      wait(50)
      keys.forceActiveFocus()
      keyClick(Qt.Key_Z, Qt.ControlModifier)
      var placedAt = watchlist.displayedSymbols.indexOf(first)
      tryVerify(function() { return watchlist.wholeInSight(placedAt, watchlist.contentY) }, 2000)
      harness.check("an undo under the pointer returns the row at its sorted place and brings it into reach",
        watchlist.sortHeld && placedAt === 0 && watchlist.wholeInSight(placedAt, watchlist.contentY),
        watchlist.sortHeld + "|" + placedAt)
      mouseMove(body, 1, 1)
      ;["DOWN", "STRAY"].forEach(function(s) { service.removeSymbol(s) })
      service.setOrder(orderBefore)
      app.close()
      app.testWindow.implicitHeight = heightBefore
      app.open("{}")
      wait(200)

      // The input still acts across a close/reopen; the rendered slide and
      // fade are already in the window motion harness.
      service.persist({ order: "manual" })
      app.close()
      app.open("{}")
      watchlist.contentY = 0
      keys.forceActiveFocus()
      var moving = watchlist.displayedSymbols[0]
      watchlist.cursorSymbol = moving
      keyClick(Qt.Key_Down, Qt.ShiftModifier)
      var moved = service.symbols.indexOf(moving)
      app.close()
      app.open("{}")
      harness.check("a row moved before close keeps its saved place after reopen", moved === 1 && service.symbols.indexOf(moving) === moved)
      keys.forceActiveFocus()
      watchlist.contentY = 0
      var returning = watchlist.displayedSymbols[0]
      watchlist.cursorSymbol = returning
      keyClick(Qt.Key_Delete)
      keyClick(Qt.Key_Z, Qt.ControlModifier)
      app.close()
      app.open("{}")
      harness.check("an undone removal stays restored after reopen", watchlist.displayedSymbols.indexOf(returning) >= 0 && service.library.indexOf(returning) >= 0)

      keysActOnWhatYouChose(body, watchlist, keys)

      // The moves by wheel and drag start on the day.
      service.setRange("1D")
      wait(300)

      movesByKeys(body, watchlist, keys)
      dragsAndTheWheel(body, watchlist, keys)
      cursorInSight(body, watchlist, keys)
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
      // below failed this step under load.
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

    // The window's footer says both notices, as the popup's does, and a real
    // click acts on each as the footer says: none on the file's, a restart
    // on the update's. Over a short list it sits one gap under the rows,
    // the file's notice too, not at the window's bottom. Found in the edge
    // pass of 15 October: one row, a tall empty space, then the footer. A
    // change while the file can't be read is said unsaved, and why: found in
    // the strain audit, such edits looked kept, and the next restart lost
    // them.
    function noticesInTheWindow(body) {
      app.close()
      app.testWindow.implicitHeight = 760
      app.open("{}")
      service.createList("Short")
      service.setMembership("AAPL", "Short", true)
      service.switchList("Short")
      wait(100)
      var footer = harness.find(body, "footer")
      var text = function() { return String(harness.find(footer, "footerText").text) }
      var watchlist = body.watchlist
      var good = harness.readFile(harness.dataPath)
      harness.writeFile(harness.dataPath, "{\n")
      var said = within(5000, function() { return text() === harness.fileNotice })
      mouseClick(footer, footer.width / 2, footer.height / 2)
      wait(50)
      harness.check("the window's footer says the data file can't be read, and a click on it does nothing",
        said && !body.adding, text() + "|" + body.adding)
      var modeBefore = service.changeMode
      app.testKeyCatcher.forceActiveFocus()
      keyClick("c")
      var action = function() { return String(harness.find(footer, "footerAction").text) }
      var unsaved = within(3000, function() { return text() + action() === "Your changes aren't saved · couldn't load your lists" })
      mouseClick(footer, footer.width / 2, footer.height / 2)
      wait(50)
      harness.check("a change while the data file can't be read applies, the window's footer says it isn't saved and why, a click on it does nothing, and the file is as it was",
        unsaved && service.changeMode !== modeBefore && !body.adding && harness.readFile(harness.dataPath) === "{\n",
        text() + action() + "|" + service.changeMode + "|" + body.adding)
      harness.writeFile(harness.dataPath, good)
      harness.check("fixed, the window's footer is the add again",
        within(5000, function() { return text().indexOf("+  Add a symbol") === 0 }), text())
      service.switchList("")
      service.deleteList("Short")
      wait(50)
      var manifest = JSON.parse(harness.readFile(harness.manifestPath))
      manifest.version = "9.9.9"
      harness.writeFile(harness.manifestPath, JSON.stringify(manifest, null, 2) + "\n")
      // The manifest is read again as it changes, with the window open.
      var updated = within(5000, function() { return text() === "Updated to 9.9.9 · click to restart the shell" })
      mouseClick(footer, footer.width / 2, footer.height / 2)
      harness.check("the open window's footer says an update as it lands, and a click on it restarts the shell",
        updated && within(5000, function() { return harness.readFile(harness.fakeState + "/omarchy.calls") === "restart shell\n" }),
        text() + "|" + harness.readFile(harness.fakeState + "/omarchy.calls"))
    }
  }

  HarnessExit { id: done }
}
