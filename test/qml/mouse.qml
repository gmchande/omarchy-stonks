import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "plugin" as Stonks

// What looks clickable acts, by the pointer alone but for the words typed
// into search. The real window (App.qml) and the real pill (BarWidget.qml)
// on the real service, with real Qt pointer events. Each step is judged by
// what the lists, the surface and the stand-in commands then hold: a
// handler that lost its target, or a target that lost its handler, fails
// here. HOME and curl are scratch fixtures.
Harness {
  id: harness
  marker: "MOUSE DONE"

  Stonks.Service { id: service; pluginId: "grvc.stonks" }
  Stonks.Updates { id: updates; pluginId: "grvc.stonks" }
  // The camera hands its shots to the stand-ins on PATH (bin/).
  Stonks.Camera { id: camera }
  Stonks.App { id: app; service: service; updates: updates; camera: camera }
  // The pill on a bar of its own, and its bar entry's saves.
  property int entrySaves: 0
  QtObject {
    id: shellApi
    function serviceFor(id) { return { service: service, updates: updates, camera: camera } }
    function updateEntryInline(id, settings) { harness.entrySaves++; return true }
  }
  PluginBarApi { id: barApi; pluginId: "grvc.stonks"; moduleName: "grvc.stonks"; shell: shellApi }
  FloatingWindow {
    visible: true
    implicitWidth: 320
    implicitHeight: 52
    Stonks.BarWidget {
      id: pill
      y: 10
      width: implicitWidth
      height: 32
      bar: barApi
      moduleName: "grvc.stonks"
      settings: ({ id: "grvc.stonks", barStyle: "sparkline" })
    }
  }
  // The clipboard's owner, as the stand-in wl-paste reads it (bin/wl-paste).
  Process { id: owning }

  Steps {
    name: "Mouse"
    when: service.ready

    readonly property var body: app.body

    function quiet() {
      tryVerify(function() { return service.arriving.length === 0 && service.feeds.quotes.firstRun.length + service.feeds.quotes.refreshRun.length === 0 }, 8000)
    }

    // The middle of the thing named, or of the item given.
    function at(target) {
      var item = typeof target === "string" ? harness.find(body, target) : target
      verify(!!item, "nothing named " + target)
      return item
    }
    function click(target, button) {
      var item = at(target)
      mouseMove(item, item.width / 2, item.height / 2)
      mouseClick(item, item.width / 2, item.height / 2, button || Qt.LeftButton)
    }
    function row(symbol) { return body.watchlist.rowItem(symbol) }
    // The rows have landed: a place read sooner belongs to a row still moving.
    function rest() {
      var list = body.watchlist
      within(2500, function() {
        return list.reorder.lifted === "" && !list.settling && list.displayedSymbols.every(function(symbol) { return list.rowResting(symbol) })
      })
    }
    // The selected row's fill rests on the row of the stock on show, where
    // that row is. Each step that moves rows names itself when it doesn't.
    property var fillOff: []
    function fillFollows(step) {
      var list = body.watchlist
      var fill = harness.find(body, "rowHighlight")
      var on = within(1500, function() {
        var shown = row(service.featuredSymbol)
        return !list.settling && !!fill && !!shown && fill.visible && Math.abs(fill.y - shown.y) < 0.5
      })
      if (!on) fillOff.push(step)
    }

    function test_mouse() {
      app.open("{}")
      tryVerify(function() { return !!body && body.surfaceOpen }, 3000)
      service.createList("Tech")
      service.switchList("")
      // More rows than the window shows, for the wheel.
      for (var n = 1; n <= 12; n++) service.addSymbol("LONG" + n)
      quiet()
      rest()
      var rows = service.symbols.slice()

      // A row the wheel brings into view draws its line in from none, as
      // the list works out its day only once it's in sight.
      var unseen = rows.filter(function(s) { var r = row(s); return !!r && !r.geometry }).pop()
      var arriving = row(unseen)
      var lowest = 1
      var notes = function() { lowest = Math.min(lowest, arriving.reveal) }
      if (arriving) arriving.revealChanged.connect(notes)
      var top = row(rows[0])
      var over = top ? top.mapToItem(body, top.width / 2, top.height / 2) : Qt.point(0, 0)
      for (var turn = 0; turn < 12 && arriving && !arriving.inView; turn++) {
        mouseWheel(body, over.x, over.y, 0, -120)
        within(300, function() { return arriving.inView })
      }
      var drawn = !!arriving && within(2000, function() { return !!arriving.geometry && arriving.reveal >= 1 })
      if (arriving) arriving.revealChanged.disconnect(notes)
      harness.check("a row the wheel brings into view draws its line in, from none",
        !!arriving && drawn && lowest < 1, [unseen, drawn, lowest.toFixed(2)].join(" "))
      for (var back = 0; back < 12; back++) mouseWheel(body, over.x, over.y, 0, 120)
      rest()

      click(row(rows[1]))
      harness.check("a click on a row shows its chart",
        within(1500, function() { return service.featuredSymbol === rows[1] }), service.featuredSymbol)
      fillFollows("a click")

      // Clicking a distant row scrolled far from the featured row puts the
      // highlight straight on it instead of flying it in from off-screen;
      // clicking a neighbour in sight still slides.
      var list = body.watchlist
      list.takeOver()
      list.contentY = 0
      rest()
      click(row(rows[0]))
      within(1500, function() { return service.featuredSymbol === rows[0] && Math.abs(list.highlightShift) < 0.5 })
      list.takeOver()
      list.contentY = Math.max(0, list.contentHeight - list.sightHeight)
      rest()
      var offScreen = !row(rows[0]).inSight
      var farPeak = 0
      var trackFar = function() { farPeak = Math.max(farPeak, Math.abs(list.highlightShift)) }
      list.highlightShiftChanged.connect(trackFar)
      click(row(rows[rows.length - 1]))
      var farPicked = within(1500, function() { return service.featuredSymbol === rows[rows.length - 1] })
      list.highlightShiftChanged.disconnect(trackFar)
      var nearPeak = 0
      var trackNear = function() { nearPeak = Math.max(nearPeak, Math.abs(list.highlightShift)) }
      list.highlightShiftChanged.connect(trackNear)
      click(row(rows[rows.length - 2]))
      var nearPicked = within(1500, function() { return service.featuredSymbol === rows[rows.length - 2] && Math.abs(list.highlightShift) < 0.5 })
      list.highlightShiftChanged.disconnect(trackNear)
      harness.check("switching to a row when the previous featured row is out of sight lands the highlight at once, while a neighbour in sight slides",
        offScreen && farPicked && farPeak < 0.5 && nearPicked && nearPeak > 1,
        [offScreen, farPicked, farPeak.toFixed(1), nearPicked, nearPeak.toFixed(1)].join(" "))
      list.takeOver()
      list.contentY = 0
      rest()

      // Held and carried past the next row, in your own order.
      var held = row(rows[0])
      var grip = held.mapToItem(body, held.width / 2, held.height / 2)
      var down = body.watchlist.rowPitch * 1.2
      mousePress(body, grip.x, grip.y)
      mouseMove(body, grip.x, grip.y + down / 2, -1, Qt.LeftButton)
      mouseMove(body, grip.x, grip.y + down, -1, Qt.LeftButton)
      within(1000, function() { return body.watchlist.reorder.lifted === rows[0] })
      mouseRelease(body, grip.x, grip.y + down)
      var carried = rows.slice(1, 2).concat([rows[0]]).concat(rows.slice(2))
      harness.check("a row dragged past the next takes its place, and the order is the lists' own",
        within(2000, function() { return service.symbols.join(",") === carried.join(",") }), service.symbols.join(","))
      rows = service.symbols.slice()
      rest()
      fillFollows("a row dragged past it")

      // From the top of the rows, a row held and carried `by` down, the
      // button still held: where the pointer is.
      var hold = function(symbol, by) {
        var list = body.watchlist
        var over = list.mapToItem(body, list.width / 2, list.height / 2)
        for (var notch = 0; notch < 6; notch++) mouseWheel(body, over.x, over.y, 0, 120)
        rest()
        var held = row(symbol)
        var grip = held.mapToItem(body, held.width / 2, held.height / 2)
        mousePress(body, grip.x, grip.y)
        mouseMove(body, grip.x, grip.y + by / 2, -1, Qt.LeftButton)
        mouseMove(body, grip.x, grip.y + by, -1, Qt.LeftButton)
        within(1000, function() { return body.watchlist.reorder.lifted === symbol })
        return Qt.point(grip.x, grip.y + by)
      }
      var liftedRow = function() { return body.watchlist.reorder.lifted }
      var order = function() { return service.symbols.join(",") }

      // The wheel under a held row scrolls the rows, and the row stays under
      // the pointer: it drops past rows the pointer never reached.
      var to = hold(rows[0], down)
      mouseWheel(body, to.x, to.y, 0, -120)
      mouseRelease(body, to.x, to.y)
      var landed = within(2000, function() { return service.symbols.indexOf(rows[0]) >= 3 })
      var wheeled = rows.slice(1)
      wheeled.splice(service.symbols.indexOf(rows[0]), 0, rows[0])
      harness.check("a row held as the wheel scrolls stays under the pointer and drops where it is then, past rows the pointer never reached",
        landed && order() === wheeled.join(","), [service.symbols.indexOf(rows[0]), order()].join(" "))
      service.setManualOrder(rows)
      within(1500, function() { return order() === rows.join(",") })

      // Sorted elsewhere while a row is held: the drag ends, and your own
      // order stays as it was.
      to = hold(rows[0], down)
      var wasLifted = liftedRow() === rows[0]
      service.setOrder("symbol")
      var sortedEnds = within(1000, function() { return liftedRow() === "" })
      mouseRelease(body, to.x, to.y)
      service.setOrder("manual")
      harness.check("a row held while the order changes elsewhere drops back, and your own order stays as it was",
        wasLifted && sortedEnds && within(1500, function() { return body.watchlist.displayedSymbols.join(",") === rows.join(",") }) && order() === rows.join(","),
        [wasLifted, sortedEnds, order()].join(" "))
      rest()

      // Removed elsewhere while it's held: the drag ends at once, and the
      // rest keep their order.
      var vanished = rows[3]
      to = hold(vanished, down)
      wasLifted = liftedRow() === vanished
      service.removeSymbol(vanished)
      var goneEnds = within(1000, function() { return liftedRow() === "" })
      mouseRelease(body, to.x, to.y)
      var left = rows.filter(function(s) { return s !== vanished }).join(",")
      harness.check("a row removed elsewhere while it's held ends the drag at once, and the rest keep their order",
        wasLifted && goneEnds && !within(500, function() { return order() !== left }), [wasLifted, goneEnds, order()].join(" "))
      service.undoRemoval(vanished)
      within(1500, function() { return order() === rows.join(",") })
      rest()

      // Held over the last place as the other surface removes another row:
      // no place is left there, so the drag ends at once, and your order
      // stays as it was without that row.
      vanished = rows[2]
      to = hold(rows[0], rows.length * body.watchlist.rowPitch)
      var atEnd = liftedRow() === rows[0] && body.watchlist.reorder.slot === rows.length - 1
      service.removeSymbol(vanished)
      var endEnds = within(1000, function() { return liftedRow() === "" })
      mouseRelease(body, to.x, to.y)
      left = rows.filter(function(s) { return s !== vanished }).join(",")
      harness.check("a row held over the last place as another row is removed elsewhere ends the drag at once, and your order stays as it was",
        atEnd && endEnds && !within(500, function() { return order() !== left }), [atEnd, endEnds, order()].join(" "))
      service.undoRemoval(vanished)
      within(1500, function() { return order() === rows.join(",") })
      rest()

      // Closed while a row is held: it drops back, and the window opens on
      // your order as it was.
      to = hold(rows[0], down)
      wasLifted = liftedRow() === rows[0]
      app.close()
      var closedEnds = liftedRow() === ""
      app.open("{}")
      tryVerify(function() { return body.surfaceOpen }, 3000)
      mouseRelease(body, to.x, to.y)
      rest()
      harness.check("a row held as the window closes drops back, and the window opens on your order as it was",
        wasLifted && closedEnds && body.watchlist.displayedSymbols.join(",") === rows.join(",") && order() === rows.join(","),
        [wasLifted, closedEnds, body.watchlist.displayedSymbols.join(","), order()].join(" "))

      // Held at the bottom edge of the rows, a row scrolls the list to its
      // end and drops last; held at the top edge, it scrolls back, rests
      // while the pointer leaves the edge, and drops first. Each drop shows
      // and saves the order drawn as it was let go.
      var list = body.watchlist
      var saved = function() {
        try { return JSON.parse(harness.readFile(Quickshell.env("HOME") + "/.config/omarchy/grvc.stonks.json")) } catch (e) { return null }
      }
      var savedSymbols = function() { var file = saved(); return file ? file.symbols.join(",") : "" }
      var moved = function(from, to) { var next = rows.slice(); next.splice(to, 0, next.splice(from, 1)[0]); return next.join(",") }
      var edgeAt = function(y) { return list.mapToItem(body, list.width / 2, y) }
      list.takeOver()
      list.contentY = 0
      rest()
      var lift = row(rows[1]).mapToItem(body, list.width / 2, row(rows[1]).height / 2)
      var bottom = edgeAt(list.sightHeight - 2)
      mousePress(body, lift.x, lift.y)
      mouseMove(body, lift.x, lift.y + down / 2, -1, Qt.LeftButton)
      mouseMove(body, lift.x, bottom.y, -1, Qt.LeftButton)
      var reachedEnd = within(6000, function() { return list.atYEnd && list.reorder.slot === rows.length - 1 })
      var drawnAt = list.reorder.slot
      mouseRelease(body, lift.x, bottom.y)
      var wanted = moved(1, drawnAt)
      var droppedLast = within(2000, function() { return list.displayedSymbols.join(",") === wanted && savedSymbols() === wanted })
      harness.check("a row held at the bottom edge of the rows scrolls them to the end, drops last, and the order shown is the order saved",
        reachedEnd && droppedLast, [reachedEnd, drawnAt, list.displayedSymbols.join(","), savedSymbols()].join(" | "))
      rows = service.symbols.slice()
      rest()

      var middle = rows[Math.floor((list.contentY + list.sightHeight / 2) / list.rowPitch)]
      lift = row(middle).mapToItem(body, list.width / 2, row(middle).height / 2)
      var top = edgeAt(2)
      var centre = edgeAt(list.sightHeight / 2)
      var startY = list.contentY
      mousePress(body, lift.x, lift.y)
      mouseMove(body, lift.x, lift.y - down / 2, -1, Qt.LeftButton)
      mouseMove(body, lift.x, top.y, -1, Qt.LeftButton)
      var climbing = within(3000, function() { return list.contentY < startY - 2 * list.rowPitch })
      mouseMove(body, lift.x, centre.y, -1, Qt.LeftButton)
      var restingY = list.contentY
      var rested = climbing && !within(400, function() { return list.contentY !== restingY })
      mouseMove(body, lift.x, top.y, -1, Qt.LeftButton)
      var reachedTop = within(6000, function() { return list.atYBeginning && list.reorder.slot === 0 })
      drawnAt = list.reorder.slot
      mouseRelease(body, lift.x, top.y)
      wanted = moved(rows.indexOf(middle), drawnAt)
      var droppedFirst = within(2000, function() { return list.displayedSymbols.join(",") === wanted && savedSymbols() === wanted })
      harness.check("a row held at the top edge scrolls the rows back, rests while the pointer leaves the edge, drops first, and the order shown is the order saved",
        climbing && rested && reachedTop && droppedFirst,
        [climbing, rested, reachedTop, drawnAt, list.displayedSymbols.join(","), savedSymbols()].join(" | "))
      service.setManualOrder(rows)
      within(1500, function() { return order() === rows.join(",") })
      rest()

      // Lifting a row near the bottom edge: pulling away unlocks the full
      // bottom edge zone on the way back down.
      list.takeOver()
      list.contentY = 0
      rest()
      var edgeSym = list.displayedSymbols.reduce(function(best, s) {
        var r = row(s)
        return r && r.y <= list.sightHeight - 14 && r.y + r.height > list.sightHeight - list.rowPitch ? s : best
      }, "")
      var edgeRow = row(edgeSym)
      var grip = Math.min(edgeRow.height - 2, Math.max(4, list.sightHeight - edgeRow.y - 10))
      var nearBottom = edgeRow.mapToItem(body, edgeRow.width / 2, grip)
      var midEdge = edgeAt(list.sightHeight - list.rowPitch / 2)
      mousePress(body, nearBottom.x, nearBottom.y)
      mouseMove(body, nearBottom.x, nearBottom.y - down / 2, -1, Qt.LeftButton)
      mouseMove(body, nearBottom.x, centre.y, -1, Qt.LeftButton)
      var liftedEdge = within(1000, function() { return list.reorder.lifted === edgeSym })
      mouseMove(body, nearBottom.x, midEdge.y, -1, Qt.LeftButton)
      var unlocked = liftedEdge && within(1500, function() { return list.reorder.edgeHeld && list.contentY >= list.rowPitch })
      mouseRelease(body, nearBottom.x, midEdge.y)
      rest()
      list.commitManualOrder(rows)
      within(1500, function() { return order() === rows.join(",") && list.displayedSymbols.join(",") === rows.join(",") })
      list.takeOver()
      list.contentY = 0
      rest()
      harness.check("lifting near the bottom edge unlocks the full edge zone after pulling away",
        liftedEdge && unlocked, [edgeSym, liftedEdge, unlocked, list.contentY.toFixed(1)].join(" "))

      click(row(rows[0]), Qt.RightButton)
      var menu = within(1500, function() { return harness.findAll(body, "rowMenuLine").length > 0 && harness.inPlace(harness.findAll(body, "rowMenuLine")) })
      var lines = harness.findAll(body, "rowMenuLine")
      click(lines[lines.length - 1])
      harness.check("a right click opens the row's menu, and its last line chooses the row's lists",
        menu && within(1500, function() { return body.listsSymbol === rows[0] }), menu + " " + body.listsSymbol)
      // New list there, a name, MAKE: the list is made holding the row,
      // and All stays on show.
      var shield = harness.find(body, "openingShield")
      within(2000, function() { return !shield.visible })
      click("symbolNewList")
      var listField = function() { return harness.find(body, "symbolListNameField") }
      var namingThere = within(1500, function() { return !!listField() && listField().activeFocus })
      "Fav".split("").forEach(function(c) { keyClick(c) })
      click("symbolListMake")
      var favourite = function() { return service.lists.filter(function(l) { return l.name === "Fav" })[0] }
      harness.check("in a row's lists, New list, a name and MAKE make a list holding the row, and All stays on show",
        namingThere && within(1500, function() { return !!favourite() && favourite().symbols.join(",") === rows[0] && !listField().visible })
          && service.listName === "",
        [namingThere, JSON.stringify(favourite() || null), service.listName].join(" "))
      service.deleteList("Fav")
      body.closeViews()

      // Its first line removes the row, and UNDO puts it back.
      click(row(rows[2]), Qt.RightButton)
      var again = within(1500, function() { return harness.findAll(body, "rowMenuLine").length > 0 && harness.inPlace(harness.findAll(body, "rowMenuLine")) })
      click(harness.findAll(body, "rowMenuLine").sort(function(a, b) { return a.y - b.y })[0])
      var dropped = within(1500, function() { return service.symbols.indexOf(rows[2]) < 0 })
      click("footerUndo")
      harness.check("the row menu's first line removes the row, and UNDO puts it back",
        again && dropped && within(1500, function() { return service.symbols.join(",") === rows.join(",") }), [again, dropped, service.symbols.join(",")].join(" "))
      rest()

      click("listControl")
      var chevron = at("listLabel").parent.children.filter(function(c) { return c.text === "󰅀" })[0]
      var listMenu = at("listMenu")
      var choices = function() { return harness.findAll(body, "listChoice") }
      var listed = within(1500, function() { return body.listMenuOpen && choices().length === 2 && harness.inPlace(choices()) && !!chevron && Math.round(chevron.rotation) === 180 })
      click(choices()[1])
      var droppedInput = within(500, function() { return !body.listMenuOpen && !listMenu.enabled })
      var closedClean = within(1500, function() { return service.listName === "Tech" && !listMenu.visible && !!chevron && Math.round(chevron.rotation) === 0 })
      harness.check("a click on the list's name opens the menu and turns its chevron, and choosing a list switches at once while the menu drops input and closes",
        listed && droppedInput && closedClean, [listed, droppedInput, closedClean, service.listName, chevron ? chevron.rotation : "none", listMenu.visible, listMenu.enabled].join(" "))
      service.switchList("")
      quiet()

      // The menu covers rows: a right-click on it reaches none of them.
      click("listControl")
      var reopened = within(1500, function() { return body.listMenuOpen && harness.inPlace(choices()) })
      click(choices()[0], Qt.RightButton)
      harness.check("a right-click on the list menu opens no row's menu under it",
        reopened && within(500, function() { return !body.listMenuOpen }) && body.rowMenu === null, [reopened, body.listMenuOpen, JSON.stringify(body.rowMenu)].join(" "))
      body.closeViews()

      // New list, a name half typed, CANCEL: no list is made, and the menu
      // is back as it was.
      click("listControl")
      within(1500, function() { return body.listMenuOpen && harness.inPlace(choices()) })
      click("newListLine")
      var nameField = function() { return harness.find(body, "listNameField") }
      var namingStarted = within(1500, function() { return !!nameField() && nameField().activeFocus })
      "Sem".split("").forEach(function(c) { keyClick(c) })
      click("namingCancel")
      var cancelled = within(1500, function() { return body.listMenuOpen && !nameField().visible })
      harness.check("a name half typed in New list, CANCEL makes no list and leaves the menu open",
        namingStarted && cancelled && service.lists.length === 2, [namingStarted, cancelled, service.lists.map(function(l) { return l.name }).join(",")].join(" "))
      body.closeViews()

      // Beside the lists, the scrollbar's gutter points at none of them.
      body.openManageLists()
      var manage = at("manageLists")
      var manageRows = function() { return harness.findAll(body, "manageRow").sort(function(a, b) { return a.y - b.y }) }
      var managed = within(1500, function() { return manageRows().length === 2 && harness.inPlace(manageRows()) && manage.cursor === 1 })
      var top = manageRows()[0]
      // A hand's move, from the row the cursor is on, to the gutter beside
      // the row above it.
      mouseMove(manageRows()[1], top.width / 2, top.height / 2)
      mouseMove(manageRows()[1], top.width / 2, top.height / 3)
      var gutterAt = top.mapToItem(body, top.width + body.gutter / 2, top.height / 2)
      mouseMove(body, gutterAt.x, gutterAt.y)
      var gutterKept = !within(300, function() { return manage.cursor !== 1 })
      mouseMove(top, top.width / 2, top.height / 2)
      harness.check("in Manage lists the scrollbar's gutter moves no cursor, and the row beside it does",
        managed && gutterKept && within(1000, function() { return manage.cursor === 0 }), [managed, gutterKept, manage.cursor].join(" "))
      body.closeViews()

      // Held and carried past the list above it, as a stock's row is, with
      // All first still.
      var wasList = service.listName
      // Your own lists, as Manage lists shows them under All.
      var listNames = function() { return service.lists.filter(function(l) { return l.name !== "" }).map(function(l) { return l.name }).join(",") }
      var first = listNames()
      service.createList("Later")
      service.switchList(wasList)
      body.openManageLists()
      manage = at("manageLists")
      var three = within(1500, function() { return manageRows().length === 3 && harness.inPlace(manageRows()) })
      var later = manageRows()[2]
      var lift = later.mapToItem(body, later.width / 4, later.height / 2)
      var up = manage.itemHeight * 1.2
      mousePress(body, lift.x, lift.y)
      mouseMove(body, lift.x, lift.y - up / 2, -1, Qt.LeftButton)
      mouseMove(body, lift.x, lift.y - up, -1, Qt.LeftButton)
      var lifted = within(1000, function() { return manage.reorder.lifted === "Later" })
      mouseRelease(body, lift.x, lift.y - up)
      var carried = within(2000, function() { return listNames() === "Later," + first })
      // Past All, it stops below it.
      var firstRow = manageRows()[1]
      lift = firstRow.mapToItem(body, firstRow.width / 4, firstRow.height / 2)
      mousePress(body, lift.x, lift.y)
      mouseMove(body, lift.x, lift.y - up / 2, -1, Qt.LeftButton)
      mouseMove(body, lift.x, lift.y - up * 2, -1, Qt.LeftButton)
      mouseRelease(body, lift.x, lift.y - up * 2)
      var kept = !within(500, function() { return listNames() !== "Later," + first }) && within(1500, function() { return manage.reorder.lifted === "" })
      harness.check("in Manage lists a list dragged past the one above takes its place, and none goes above All",
        three && lifted && carried && kept, [three, lifted, carried, kept, listNames()].join(" "))
      // The window deletes the list lifted in the panel: the drag ends, and
      // the lists left keep their places under All.
      var laterRow = manageRows()[1]
      lift = laterRow.mapToItem(body, laterRow.width / 4, laterRow.height / 2)
      mousePress(body, lift.x, lift.y)
      mouseMove(body, lift.x, lift.y + up / 2, -1, Qt.LeftButton)
      mouseMove(body, lift.x, lift.y + up, -1, Qt.LeftButton)
      var liftedAgain = within(1000, function() { return manage.reorder.lifted === "Later" && manage.reorder.slot === 2 })
      service.deleteList("Later")
      var dropped = within(1500, function() {
        var rows = manageRows()
        return manage.reorder.lifted === "" && rows.length === 2 && rows[0].y === 0 && rows[1].y === manage.itemHeight
      })
      mouseRelease(body, lift.x, lift.y + up)
      harness.check("in Manage lists a list deleted elsewhere while lifted ends the drag, and All stays first",
        liftedAgain && dropped, [liftedAgain, dropped, manageRows().map(function(r) { return r.name + "@" + r.y }).join(" ")].join(" "))
      body.closeViews()
      service.deleteList("Later")
      service.switchList(wasList)

      // A list held in Manage lists while the other surface renames it, the
      // window closes, or the wheel scrolls.
      var more = ["One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine", "Ten", "Eleven", "Twelve"]
      more.forEach(function(name) { service.createList(name) })
      service.switchList(wasList)
      var openManage = function() {
        body.openManageLists()
        manage = at("manageLists")
        return within(1500, function() { return manageRows().length === more.length + 2 && harness.inPlace(manageRows()) })
      }
      var carry = function(name, by) {
        var held = manageRows().filter(function(r) { return r.name === name })[0]
        var grip = held.mapToItem(body, held.width / 4, held.height / 2)
        mousePress(body, grip.x, grip.y)
        mouseMove(body, grip.x, grip.y + by / 2, -1, Qt.LeftButton)
        mouseMove(body, grip.x, grip.y + by, -1, Qt.LeftButton)
        within(1000, function() { return manage.reorder.lifted === name })
        return Qt.point(grip.x, grip.y + by)
      }
      var named = listNames()

      var opened = openManage()
      to = carry("One", up)
      wasLifted = manage.reorder.lifted === "One"
      service.renameList("One", "Uno")
      var renamedEnds = within(1000, function() { return manage.reorder.lifted === "" })
      mouseRelease(body, to.x, to.y)
      var renamedOrder = named.split(",").map(function(n) { return n === "One" ? "Uno" : n }).join(",")
      harness.check("in Manage lists a list renamed elsewhere while lifted ends the drag, and the lists keep their order",
        opened && wasLifted && renamedEnds && !within(500, function() { return listNames() !== renamedOrder }),
        [opened, wasLifted, renamedEnds, listNames()].join(" "))
      service.renameList("Uno", "One")
      within(1500, function() { return listNames() === named })

      to = carry("One", up)
      wasLifted = manage.reorder.lifted === "One"
      app.close()
      closedEnds = manage.reorder.lifted === ""
      app.open("{}")
      tryVerify(function() { return body.surfaceOpen }, 3000)
      mouseRelease(body, to.x, to.y)
      harness.check("in Manage lists a list lifted as the window closes drops back where it was",
        wasLifted && closedEnds && !within(500, function() { return listNames() !== named }), [wasLifted, closedEnds, listNames()].join(" "))

      // The wheel under a lifted list scrolls the lists, and the list stays
      // under the pointer: it drops past lists the pointer never reached.
      opened = openManage()
      var scrolls = manage.contentHeight > manage.height
      to = carry("One", up)
      mouseWheel(body, to.x, to.y, 0, -120)
      var carriedOn = within(1500, function() { return manage.reorder.slot > 4 })
      mouseRelease(body, to.x, to.y)
      var oneAt = function() { return listNames().split(",").indexOf("One") }
      var landedOn = within(1500, function() { return oneAt() > 3 })
      var wheeledOrder = named.split(",").filter(function(n) { return n !== "One" })
      wheeledOrder.splice(oneAt(), 0, "One")
      harness.check("in Manage lists a list lifted as the wheel scrolls stays under the pointer and drops where it is then",
        opened && scrolls && carriedOn && landedOn && listNames() === wheeledOrder.join(","),
        [opened, scrolls, carriedOn, landedOn, listNames()].join(" "))

      // Held at the bottom edge of Manage lists, a list scrolls them to the
      // end and drops last; held at the top edge, it scrolls back and drops
      // first, under All. Each drop saves the order drawn.
      var savedLists = function() { var file = saved(); return file ? file.lists.map(function(l) { return l.name }).join(",") : "" }
      var manageAt = function(y) { return manage.mapToItem(body, manage.width / 4, y) }
      opened = openManage()
      var held = manageRows().filter(function(r) { return r.name === "One" })[0]
      lift = held.mapToItem(body, held.width / 4, held.height / 2)
      var listsBottom = manageAt(manage.height - 2)
      mousePress(body, lift.x, lift.y)
      mouseMove(body, lift.x, lift.y + up / 2, -1, Qt.LeftButton)
      mouseMove(body, lift.x, listsBottom.y, -1, Qt.LeftButton)
      var listsEnd = within(6000, function() { return manage.reorder.contentY >= manage.reorder.reach && manage.reorder.slot === manage.choices.length - 1 })
      mouseRelease(body, lift.x, listsBottom.y)
      var lastOrder = listNames().split(",").filter(function(n) { return n !== "One" }).concat(["One"]).join(",")
      var listsLast = within(2000, function() { return listNames() === lastOrder && savedLists() === lastOrder })
      held = manageRows().filter(function(r) { return r.name === "One" })[0]
      lift = held.mapToItem(body, held.width / 4, held.height / 2)
      var listsTop = manageAt(manage.itemHeight + 2)
      mousePress(body, lift.x, lift.y)
      mouseMove(body, lift.x, lift.y - up / 2, -1, Qt.LeftButton)
      mouseMove(body, lift.x, listsTop.y, -1, Qt.LeftButton)
      var listsStart = within(6000, function() { return manage.reorder.contentY === 0 && manage.reorder.slot === 1 })
      mouseRelease(body, lift.x, listsTop.y)
      var firstOrder = ["One"].concat(lastOrder.split(",").filter(function(n) { return n !== "One" })).join(",")
      var listsFirst = within(2000, function() { return listNames() === firstOrder && savedLists() === firstOrder })
      harness.check("in Manage lists a list held at the bottom edge scrolls them to the end and drops last, and at the top edge scrolls back and drops under All, each order saved",
        opened && scrolls && listsEnd && listsLast && listsStart && listsFirst,
        [opened, listsEnd, listsLast, listsStart, listsFirst, listNames(), savedLists()].join(" | "))
      body.closeViews()
      more.forEach(function(name) { service.deleteList(name) })
      service.switchList(wasList)

      // By symbol, A to Z, then Z to A: the rows themselves, not the setting.
      // A featured row that stays in sight glides to its new slot and keeps
      // its highlight on it the whole way.
      var shown = function() { return body.watchlist.displayedSymbols.join(",") }
      var aToZ = service.symbols.slice().sort()
      var list = body.watchlist
      list.takeOver()
      list.contentY = 0
      rest()
      var tracked = list.displayedSymbols.filter(function(s, i) {
        var nextAt = aToZ.indexOf(s)
        return nextAt >= 0 && nextAt !== i && list.wholeInSight(i, 0) && list.wholeInSight(nextAt, 0)
      })[0]
      if (tracked) {
        click(row(tracked))
        within(1500, function() { return service.featuredSymbol === tracked })
        rest()
      }
      var trackedRow = tracked ? row(tracked) : null
      var fill = harness.find(body, "rowHighlight")
      var fromY = trackedRow ? trackedRow.y : 0
      var toY = tracked ? aToZ.indexOf(tracked) * list.rowPitch : 0
      var glided = false
      var rode = true
      var off = ""
      var trackGlide = function() {
        if (!trackedRow || !fill) return
        var y = trackedRow.y
        if (Math.min(fromY, toY) + 1 < y && y < Math.max(fromY, toY) - 1) glided = true
        Qt.callLater(function() {
          if (!trackedRow || !fill) return
          if (!fill.visible || Math.abs(fill.y - trackedRow.y) >= 0.5) {
            rode = false
            off = [fill.visible, fill.y.toFixed(1), trackedRow.y.toFixed(1)].join("/")
          }
        })
      }
      if (trackedRow) trackedRow.yChanged.connect(trackGlide)
      click("orderLabel")
      var ordered = within(1500, function() { return shown() === aToZ.join(",") })
      rest()
      if (trackedRow) trackedRow.yChanged.disconnect(trackGlide)
      if (!glided || !rode) fillOff.push("a sort (" + [glided, rode, off].join(" ") + ")")
      fillFollows("a sort")
      click("orderArrow")
      var reversed = within(1500, function() { return shown() === aToZ.slice().reverse().join(",") })
      rest()
      fillFollows("reversing the order")
      // A percent, then an amount, then since the open.
      var next = ({ pct: "abs", abs: "open", open: "pct" })[service.changeMode]
      click("unitTarget")
      harness.check("the order's word puts the rows in the next order, its arrow reverses them, and the unit steps to the next unit",
        ordered && reversed && within(1500, function() { return service.changeMode === next }), [ordered, reversed, shown(), service.changeMode, "wanted " + next].join(" "))
      service.setOrder("manual")
      rest()
      fillFollows("returning to manual order")

      // The breadth bar fills the room beside the sort label at rest and
      // travels smoothly to its new width when the sort label changes width.
      var breadthBar = at("breadthRule")
      var orderLbl = at("orderLabel")
      var breadthTraveled = false
      var fromW = 0, toW = 0
      var trackBreadth = function() {
        var w = breadthBar.width
        if (Math.min(fromW, toW) + 1 < w && w < Math.max(fromW, toW) - 1) breadthTraveled = true
      }
      breadthBar.widthChanged.connect(trackBreadth)
      var breadthFills = true
      for (var allOrd = 0; allOrd < 4; allOrd++) {
        var wasAllOrd = service.order
        fromW = breadthBar.width
        click("orderLabel")
        within(1500, function() { return service.order !== wasAllOrd })
        toW = orderLbl.x - 10 - breadthBar.x
        var settled = within(1500, function() { return Math.abs(breadthBar.width - (orderLbl.x - 10 - breadthBar.x)) < 1 })
        if (!settled) breadthFills = false
      }
      breadthBar.widthChanged.disconnect(trackBreadth)

      // A long elided list name keeps its chevron in place across every sort order.
      var longList = "Global Semiconductors, Cloud Infrastructure, Energy Transition and Long-Term Compounders Watchlist"
      service.createList(longList)
      service.switchList(longList)
      var listLabelItem = at("listLabel")
      var longOn = within(1500, function() { return service.listName === longList && listLabelItem.truncated })
      var listChevron = at("listChevron")
      var chevronXs = [listChevron.x]
      for (var ord = 0; ord < 4; ord++) {
        var wasOrd = service.order
        click("orderLabel")
        within(1500, function() { return service.order !== wasOrd })
        chevronXs.push(listChevron.x)
      }
      var steadyChevron = chevronXs.every(function(x) { return Math.abs(x - chevronXs[0]) < 0.5 })
      service.switchList("")
      service.deleteList(longList)
      rest()
      harness.check("a long list name keeps the header chevron steady, and the breadth bar travels to fill the room beside each sort label",
        longOn && steadyChevron && breadthTraveled && breadthFills,
        [longOn, listLabelItem.truncated, "traveled:" + breadthTraveled, "fills:" + breadthFills,
          "chevron:" + chevronXs.map(function(x) { return x.toFixed(1) }).join(",")].join(" "))

      // Two of them, so one range for every click can't pass.
      var options = harness.findAll(body, "rangeOption")
      var picked = [options[1], options[3]].map(function(option) {
        click(harness.find(option, "rangeToken"))
        var want = String(option.modelData)
        return within(1500, function() { return service.range === want }) ? "" : want + " gave " + service.range
      })
      harness.check("a click on a range shows that range",
        options.length > 3 && picked.join("") === "", picked.join(", "))
      service.setRange("1D")

      var retro = service.retro, sounds = service.soundsOn
      click("lookToggle")
      var looked = within(1500, function() { return service.retro === !retro })
      click("soundToggle")
      var sounded = within(1500, function() { return service.soundsOn === !sounds })
      click("cameraButton")
      var shot = within(3000, function() { return body.cameraLit })
      click("helpToggle")
      var sheet = within(1500, function() { return body.showingHelp })
      click("helpToggle")
      harness.check("the header's look, sound, camera and ? each act, and ? again closes the sheet",
        looked && sounded && shot && sheet && within(1500, function() { return !body.showingHelp }), [looked, sounded, shot, sheet, body.showingHelp].join(" "))

      // In smooth, a click on another row changes the price and the stock's
      // name at once, where they stand: only the chart and the animal travel.
      // Each is found by what it shows above the chart.
      if (service.retro) body.setStyle("smooth")
      within(1500, function() { return !service.retro })
      var aboveChart = function(text) {
        var top = body.chartItem.mapToItem(body, 0, 0).y
        var found = null
        var look = function(item) {
          if (!item || found) return
          if (item.visible && item.text === text && item.mapToItem(body, 0, 0).y < top) { found = item; return }
          for (var i = 0; i < item.children.length; i++) look(item.children[i])
        }
        look(body)
        return found
      }
      var heroPrice = aboveChart(body.featured.priceText)
      var stockName = aboveChart(body.featured.name)
      var shown = function(item) {
        if (!item) return "missing"
        var o = 1
        for (var p = item; p && p !== body; p = p.parent) o *= p.opacity
        return Math.round(item.mapToItem(body, 0, 0).y) + "@" + o.toFixed(2)
      }
      var standing = shown(heroPrice) + " " + shown(stockName)
      var wavered = []
      var bent = false
      var watches = function() {
        if (body.motion.arrival >= 1) return
        bent = true
        var now = shown(heroPrice) + " " + shown(stockName)
        if (now !== standing) wavered.push(now)
      }
      var smoothTo = body.watchlist.displayedSymbols.filter(function(s) { return !!service.quotes[s] && s !== body.chartSymbol })[0]
      body.motion.arrivalChanged.connect(watches)
      click(row(smoothTo))
      var landed = within(3000, function() { return bent && body.motion.arrival >= 1 && body.chartSymbol === smoothTo })
      body.motion.arrivalChanged.disconnect(watches)
      harness.check("in smooth, a click on another row changes its price and name where they stand, at full strength",
        landed && !!heroPrice && !!stockName && wavered.length === 0, [landed, smoothTo, standing, wavered.slice(0, 3).join(" ")].join(" "))

      // After switching stocks, a live price tick that leaves the % change
      // unchanged rolls only the price, never the previous stock's move.
      var prevMode = service.changeMode
      if (prevMode !== "pct") {
        service.persist({ changeMode: "pct" })
        within(1500, function() { return service.changeMode === "pct" })
      }
      var heroChange = at("changeText")
      var hero = heroChange.parent
      var firstMove = heroChange.text
      var nextStock = body.watchlist.displayedSymbols.filter(function(s) {
        var q = service.quotes[s]
        if (!q || s === body.chartSymbol || !isFinite(q.price) || !isFinite(q.prevClose) || q.prevClose <= 0) return false
        var qCur = service.quotes[body.chartSymbol]
        if (qCur && Math.abs(((q.price - q.prevClose) / q.prevClose) - ((qCur.price - qCur.prevClose) / qCur.prevClose)) < 0.001) return false
        return Math.abs(q.price) >= 20
      })[0]
      if (nextStock) {
        click(row(nextStock))
        within(3000, function() { return body.chartSymbol === nextStock && body.motion.arrival >= 1 && heroChange.text !== firstMove })
      }
      var steadyMove = heroChange.text
      var origQuotes = service.feeds.quotes.quotes
      var q0 = origQuotes[body.chartSymbol]
      // Pick a $0.01 nudge whose rounded % matches the current quote's.
      var pct0 = Math.round(((q0.price - q0.prevClose) / q0.prevClose) * 10000)
      var nudge = Math.round(((q0.price + 0.01 - q0.prevClose) / q0.prevClose) * 10000) === pct0 ? 0.01 : -0.01
      var rolledPrice = false
      var rolledStaleMove = false
      var watchRoll = function() {
        if (hero.roll < 1) {
          rolledPrice = true
          if (heroChange.rolling) rolledStaleMove = true
        }
      }
      hero.rollChanged.connect(watchRoll)
      var ticked = Object.assign({}, origQuotes)
      ticked[body.chartSymbol] = Object.assign({}, q0, { price: q0.price + nudge })
      service.feeds.quotes.quotes = ticked
      var tickDone = within(2000, function() { return rolledPrice && hero.roll >= 1 })
      var moveAfterTick = heroChange.text
      hero.rollChanged.disconnect(watchRoll)
      service.feeds.quotes.quotes = origQuotes
      within(2000, function() { return hero.roll >= 1 })
      if (prevMode !== "pct") {
        service.persist({ changeMode: prevMode })
        within(1500, function() { return service.changeMode === prevMode })
      }
      harness.check("a live tick after a stock switch never rolls the previous stock's move into an unchanged change",
        !!nextStock && steadyMove !== firstMove && tickDone && !rolledStaleMove && moveAfterTick === steadyMove,
        [nextStock, firstMove, steadyMove, tickDone, rolledStaleMove, heroChange.before, moveAfterTick].join(" | "))

      // In smooth, stock switches and both directions of a range change draw
      // with the fast moving pass and hand over to the resting drawing on the
      // frame the motion ends; a held or replayed chart always draws exact.
      var smoothChart = harness.find(body, "smoothChart")
      var smoothInk = harness.find(smoothChart, "ink")
      var watchHandoff = function(trigger) {
        var sawMoving = false
        var endedRest = false
        var endChecked = false
        var onPainted = function() {
          if (body.motion.beat < 1) {
            if (smoothInk.drawnMoving) sawMoving = true
          } else if (!endChecked) {
            endChecked = true
            endedRest = !smoothInk.drawnMoving
          }
        }
        smoothInk.painted.connect(onPainted)
        trigger()
        var done = within(4000, function() { return body.motion.beat >= 1 && !body.motion.drawingIn && endChecked })
        smoothInk.painted.disconnect(onPainted)
        return done && sawMoving && endedRest && !smoothInk.drawnMoving
      }
      var switchBack = body.watchlist.displayedSymbols.filter(function(s) { return !!service.quotes[s] && s !== body.chartSymbol })[0]
      var switchHand = watchHandoff(function() { click(row(switchBack)) })
      var rangeTokens = harness.findAll(harness.find(body, "rangeRow"), "rangeToken")
      var clickRange = function(label) { click(rangeTokens[body.rangeOptions.indexOf(label)]) }
      // Warm 1Y once if not yet cached so 1D -> 1Y bends directly on the second click.
      var to1yHand = watchHandoff(function() { clickRange("1Y") })
      var to1dHand = watchHandoff(function() { clickRange("1D") })
      // A chart held mid-morph repaints exact immediately.
      var heldExact = false
      clickRange("1Y")
      if (within(1500, function() { return smoothChart.moving && smoothInk.drawnMoving })) {
        smoothChart.still = true
        heldExact = within(1000, function() { return !smoothChart.moving && !smoothInk.drawnMoving })
        smoothChart.still = false
      }
      within(3000, function() { return body.motion.beat >= 1 && !body.motion.drawingIn })
      clickRange("1D")
      within(3000, function() { return body.motion.beat >= 1 && !body.motion.drawingIn && body.chartRange === "1D" })
      // A replayed chart stays exact throughout the replay.
      click("animal")
      var replayOn = within(1500, function() { return body.motion.replayRunning })
      waitForRendering(body)
      var replayExact = replayOn && !smoothChart.moving && !smoothInk.drawnMoving
      body.endScrub()
      harness.check("in smooth, moving charts hand over to exact resting drawing on the frame motion ends, and held or replayed charts draw exact",
        switchHand && to1yHand && to1dHand && heldExact && replayExact,
        ["switch=" + switchHand, "1D->1Y=" + to1yHand, "1Y->1D=" + to1dHand, "held=" + heldExact, "replay=" + replayExact].join(" "))

      // In retro, a click on another row changes the price whole: every
      // price the digits take on the way is the one stock's or the other's.
      if (!service.retro) body.setStyle("retro")
      within(1500, function() { return service.retro })
      var digits = harness.find(body, "retroPrice")
      var listed = body.watchlist.displayedSymbols
      // One whose price differs, so a mix would show: the walk's stand-in
      // answers give several stocks one price.
      var other = listed.filter(function(s) { return !!service.quotes[s] && !!body.featured && service.quotes[s].price !== body.featuredQuote.price })[0]
      var fromText = digits.text
      var taken = []
      var moved = false
      var takes = function() { taken.push(digits.text) }
      var moves = function() { if (body.motion.arrival < 1) moved = true }
      digits.textChanged.connect(takes)
      body.motion.arrivalChanged.connect(moves)
      click(row(other))
      var arrived = within(3000, function() { return moved && body.motion.arrival >= 1 && body.chartSymbol === other })
      digits.textChanged.disconnect(takes)
      body.motion.arrivalChanged.disconnect(moves)
      var toText = body.featured.priceText
      var mixed = taken.filter(function(text) { return text !== fromText && text !== toText })
      harness.check("in retro, a click on another row shows its price whole, never a mix of the two",
        arrived && fromText !== toText && digits.text === toText && mixed.length === 0, [arrived, other, fromText, toText, mixed.join(" ")].join(" "))
      body.setStyle(retro ? "retro" : "smooth")

      click("animal")
      harness.check("a click on the bull or the bear replays the chart",
        within(1500, function() { return body.motion.replayRunning }), body.animalKind)
      body.endScrub()

      // A newer Stonks out: the footer offers it, and a click runs the update.
      var runs = function() {
        return harness.readFile(Quickshell.env("STONKS_FAKE_STATE") + "/omarchy.log").split("\n")
          .filter(function(line) { return line.indexOf("plugin update grvc.stonks") >= 0 }).length
      }
      var ran = runs()
      updates.mainVersion = "99.0.0"
      var offered = within(1500, function() { var button = harness.find(body, "footerUndo"); return !!button && button.visible })
      click("footerUndo")
      harness.check("with a newer Stonks out, a click on \"Update to\" runs the update",
        offered && within(2000, function() { return runs() === ran + 1 }), [offered, runs() - ran].join(" "))
      updates.mainVersion = ""

      var form = ({ sparkline: "arrow", arrow: "text", text: "icon", icon: "sparkline" })[pill.barStyle]
      var saves = harness.entrySaves
      click(pill, Qt.RightButton)
      harness.check("a right-click on the pill changes its look and saves it, as on Omarchy's clock",
        within(1500, function() { return pill.barStyle === form && harness.entrySaves === saves + 1 }), pill.barStyle + " " + harness.entrySaves)

      // The words are typed; the rest is the pointer's.
      click("footerText")
      var searching = within(1500, function() { var field = harness.find(body, "searchField"); return body.adding && !!field && field.activeFocus })
      "shop".split("").forEach(function(c) { keyClick(c) })
      // Yahoo's first result, once its rows are placed.
      var results = function() { return harness.findAll(body, "searchResult").filter(function(r) { return r.visible }).sort(function(a, b) { return a.y - b.y }) }
      var found = within(4000, function() { return results().length > 1 && harness.inPlace(results()) })
      click(results()[0])
      harness.check("the footer opens search, and a click on a result adds it",
        searching && found && within(5000, function() { return service.symbols.indexOf("SHOP") >= 0 && !body.adding }), [searching, found, service.symbols.join(",")].join(" "))
      quiet()
      rest()
      fillFollows("an add")

      // A row's × shows once the pointer has put the cursor on it; UNDO
      // stands in the footer after.
      // One a person can see: the added stock may have brought the end of
      // the list into sight.
      var list = body.watchlist
      var doomed = list.displayedSymbols.filter(function(symbol, i) { return list.wholeInSight(i, list.contentY) })[1]
      var gone = row(doomed)
      mouseMove(gone, gone.width / 2, gone.height / 2 - 1)
      mouseMove(gone, gone.width / 2, gone.height / 2)
      var shown = within(1500, function() { var x = harness.find(gone, "rowRemove"); return !!x && x.visible })
      click(harness.find(gone, "rowRemove"))
      var removed = within(1500, function() { return service.symbols.indexOf(doomed) < 0 })
      click("footerUndo")
      harness.check("a row's × removes it, and UNDO puts it back",
        shown && removed && within(1500, function() { return service.symbols.indexOf(doomed) >= 0 }), [shown, removed, service.symbols.join(",")].join(" "))
      rest()
      fillFollows("a removal and its undo")

      var chart = at("heroChart")
      mouseMove(chart, chart.width / 3, chart.height / 2)
      mouseMove(chart, chart.width / 2, chart.height / 2)
      var scrubbed = within(1500, function() { return body.scrubT !== 0 })
      mouseClick(chart, chart.width / 2, chart.height / 2)
      harness.check("the pointer over the chart reads that moment, and a click goes back to now",
        scrubbed && within(1500, function() { return body.scrubT === 0 }), scrubbed + " " + body.scrubT)

      fields()

      var before = service.symbols.join(",")
      var over = list.mapToItem(body, list.width / 2, list.height / 2)
      mouseMove(body, over.x, over.y)
      mouseWheel(body, over.x, over.y, 0, -120)
      harness.check("the wheel scrolls the rows and moves none",
        list.contentHeight > list.height && within(1500, function() { return list.contentY > 0 }) && service.symbols.join(",") === before,
        [list.contentHeight, list.height, list.contentY, service.symbols.join(",")].join(" "))
      fillFollows("the wheel")
      harness.check("the selected row's fill slides to the row clicked and stays on it through a drag, a sort, an add, a removal and the wheel",
        fillOff.length === 0, fillOff.join(", "))

      // QtTest sends no touchpad, so its event goes to the list's handler as
      // the WheelHandler hands it on: a swipe whose pixels Hyprland cut to 0.4.
      var swipeFrom = list.contentY
      list.wheelEvent(Qt.ScrollUpdate, -10, 0)
      harness.check("a touchpad swipe moves the rows three times its pixels, as Omarchy's menu does",
        Math.abs(list.contentY - swipeFrom - 30) < 0.5, swipeFrom + " " + list.contentY)

      // Fault 19c: the open-mode bell tooltip says "since the open", not "today's open".
      var savedUnit = service.changeMode
      service.persist({ changeMode: "open" })
      within(1500, function() { return service.changeMode === "open" })
      var unitArea = at("unitTarget")
      var unitTip = ""
      for (var ut = 0; unitArea && ut < unitArea.data.length; ut++) {
        if (typeof unitArea.data[ut].text === "string" && unitArea.data[ut].text !== "") unitTip = unitArea.data[ut].text
      }
      harness.check("the open-mode unit tooltip says since the open, not today's open",
        unitTip === "% change since the open", unitTip)
      service.persist({ changeMode: savedUnit })
      within(1500, function() { return service.changeMode === savedUnit })

      // Fault 18: wide row figures stay inside priceWidth without crossing onto
      // the sparkline, and long unmapped exchange names in Hero stay inside
      // Hero's right edge with no dangling dot when the lead has no room;
      // normal exchange + currency never elide when the text size grows.
      var heroMeta = at("listingMeta")
      var heroItem = heroMeta ? heroMeta.parent : null
      var edgeSym = body.chartSymbol
      var edgeOrig = service.feeds.quotes.quotes
      var edgeQ = edgeOrig[edgeSym]
      var edgeMode = service.changeMode
      var edgeIdx = body.watchlist.displayedSymbols.indexOf(edgeSym)
      if (edgeIdx >= 0) {
        body.watchlist.contentY = Math.max(0, edgeIdx * body.watchlist.rowPitch)
        within(1500, function() { return body.watchlist.wholeInSight(edgeIdx, body.watchlist.contentY) })
      }
      service.persist({ changeMode: "abs" })
      within(1500, function() { return service.changeMode === "abs" })
      var wideQ = Object.assign({}, edgeOrig)
      wideQ[edgeSym] = Object.assign({}, edgeQ, {
        price: 0.00000000361, prevClose: 0.00000000100, priceDigits: 11,
        exchange: "WARSAW STOCK EXCHANGE VERY LONG UNMAPPED EXCHANGE NAME THAT EXCEEDS EVEN A WIDE DESKTOP WINDOW HERO WIDTH",
        name: "Very Long Unmapped Exchange Company Name International Corporation"
      })
      service.feeds.quotes.quotes = wideQ
      var edgeRow = row(edgeSym)
      var wideReady = within(2000, function() {
        return !!edgeRow && !!edgeRow.view && /0\.00000000261/.test(edgeRow.view.changeLine)
      })
      var rowTexts = []
      var findTexts = function(item) {
        if (!item) return
        if (typeof item.paintedWidth === "number" && typeof item.text === "string" && item.text !== "") rowTexts.push(item)
        for (var i = 0; i < item.children.length; i++) findTexts(item.children[i])
      }
      findTexts(edgeRow)
      var changeItem = rowTexts.filter(function(t) { return /0\.00000000261/.test(t.text) })[0]
      var changeFits = !!changeItem && changeItem.paintedWidth <= changeItem.width + 0.5
      var metaFits = !!heroMeta && !!heroItem && heroMeta.x + heroMeta.paintedWidth <= heroItem.width + 0.5 && heroMeta.text.indexOf(" · ") !== 0
      var edgeDiag = [wideReady, changeFits, changeItem ? changeItem.paintedWidth.toFixed(1) + "/" + changeItem.width.toFixed(1) : "no change",
        metaFits, heroMeta ? (heroMeta.x + heroMeta.paintedWidth).toFixed(1) + "/" + (heroItem ? heroItem.width.toFixed(1) : 0) + " '" + heroMeta.text + "'" : "no meta"].join(" | ")
      service.feeds.quotes.quotes = edgeOrig
      service.persist({ changeMode: edgeMode })
      within(2000, function() { return service.changeMode === edgeMode })
      var savedBaseSize = Style.fontBaseSize
      Style.fontBaseSize = 20
      var bigMetaWhole = within(1500, function() { return !!heroMeta && heroMeta.text !== "" && !heroMeta.truncated })
      Style.fontBaseSize = savedBaseSize
      within(1500, function() { return Style.fontBaseSize === savedBaseSize })
      harness.check("wide row figures stay within priceWidth and Hero exchange names stay whole at bigger text sizes while long ones fit inside Hero without a leading dot",
        bigMetaWhole && wideReady && changeFits && metaFits, "bigMeta:" + bigMetaWhole + " | " + edgeDiag)

      // Fault 9: in SymbolLists with many lists, submitting an invalid New list…
      // name scrolls the error into sight, scroll stays locked while naming,
      // and clicking a list row exits naming cleanly.
      var manyNames = []
      for (var li = 1; li <= 12; li++) {
        var ln = "ManyList " + (li < 10 ? "0" : "") + li
        manyNames.push(ln)
        service.createList(ln)
      }
      body.openSymbolLists(body.chartSymbol)
      var symLists = null
      var symScroll = null
      var listsOpen = within(2000, function() {
        symLists = harness.find(body, "symbolLists")
        return !!symLists && symLists.active && symLists.choices.length >= 13
      })
      for (var sc = 0; symLists && sc < symLists.children.length; sc++) {
        if (typeof symLists.children[sc].contentY === "number") symScroll = symLists.children[sc]
      }
      var scrollableBefore = within(1500, function() { return !!symScroll && symScroll.contentHeight > symScroll.height && symScroll.interactive })
      if (symLists) symLists.startNaming()
      var namingOn = within(1500, function() { return !!symLists && symLists.naming })
      var scrollLocked = !!symScroll && !symScroll.interactive
      if (symLists) symLists.createRequested("")
      var errVisible = within(1500, function() {
        if (!symLists || !symScroll || symLists.problem === "") return false
        var errBottom = (symLists.newIndex + 2) * symLists.itemHeight
        return errBottom <= symScroll.contentY + symScroll.height + 1
      })
      var symDiag = symLists && symScroll ? "contentY=" + symScroll.contentY.toFixed(1) + " h=" + symScroll.height.toFixed(1) + " ch=" + symScroll.contentHeight.toFixed(1) + " errB=" + ((symLists.newIndex + 2) * symLists.itemHeight) : ""
      var firstListRow = symLists ? harness.findAll(symLists, "symbolListRow")[0] : null
      if (symLists && firstListRow) symLists.toggle(0)
      var exitedNaming = within(1500, function() { return !!symLists && !symLists.naming })
      body.closeViews()
      for (var ld = 0; ld < manyNames.length; ld++) service.deleteList(manyNames[ld])
      rest()
      harness.check("SymbolLists locks scroll while naming, scrolls New list validation errors into view, and exits naming when another list is clicked",
        listsOpen && scrollableBefore && namingOn && scrollLocked && errVisible && exitedNaming,
        [listsOpen, "scrollBefore:" + scrollableBefore, namingOn, "locked:" + scrollLocked, "errVis:" + errVisible, "exited:" + exitedNaming, symDiag].join(" | "))

      app.close()
      harness.finish()
    }

    // A text field under the pointer, as Omarchy's own: a click puts the
    // cursor where it lands, in the field's paddings too, a drag selects, a
    // double-click takes a word, and the middle button and the right-click
    // menu's Paste paste, through the stand-in wl-paste: the middle button's
    // where it lands, the menu's at the cursor.
    function fields() {
      body.closeViews()
      click("footerText")
      var field = null
      var searching = within(1500, function() { field = harness.find(body, "searchField"); return body.adding && !!field && field.activeFocus })
      "abc def".split("").forEach(function(c) { keyClick(c) })
      // The middle of position `i`, in the field; `y` in it if given.
      var text = field.children.filter(function(child) { return !!child.positionToRectangle })[0]
      var place = function(i, y) {
        var r = text.positionToRectangle(i)
        return { x: text.x + r.x + 1, y: y === undefined ? field.height / 2 : y }
      }
      var seen = function() { return [field.text, field.cursorPosition, field.selectionStart, field.selectionEnd].join(" ") }
      var p = place(2)
      mouseClick(field, p.x, p.y)
      var clicked = seen()
      p = place(5, 1)
      mouseClick(field, p.x, p.y)
      var padded = seen()
      var a = place(1), z = place(5)
      mousePress(field, a.x, a.y)
      mouseMove(field, (a.x + z.x) / 2, a.y)
      mouseMove(field, z.x, z.y)
      mouseRelease(field, z.x, z.y)
      // What a pointer selection put in the primary selection, through the
      // stand-in wl-copy (bin/wl-copy): the arguments of its last call and
      // what it was given.
      var primary = function() {
        var calls = harness.readFile(Quickshell.env("STONKS_FAKE_STATE") + "/wl-copy.calls").split("\n").filter(function(l) { return l !== "" })
        return calls.length ? calls[calls.length - 1] + ":" + harness.readFile(Quickshell.env("STONKS_FAKE_STATE") + "/wl-copy." + calls.length) : ""
      }
      var dragged = seen()
      var draggedPrimary = within(2000, function() { return primary() === "--primary:bc d" })
      p = place(5)
      mouseDoubleClickSequence(field, p.x, p.y)
      var word = seen()
      var wordPrimary = within(2000, function() { return primary() === "--primary:def" })
      harness.check("in a text field a click puts the cursor where it lands, in its paddings too, a drag selects, a double-click takes a word, and each selection is the primary selection",
        clicked === "abc def 2 2 2" && padded === "abc def 5 5 5" && dragged === "abc def 5 1 5" && word === "abc def 7 4 7" && draggedPrimary && wordPrimary,
        [clicked, padded, dragged, word, draggedPrimary, wordPrimary, primary()].join(" | "))

      var state = Quickshell.env("STONKS_FAKE_STATE")
      owning.command = ["sh", "-c", 'printf text > "$1/wl-paste.owner" && printf MSFT > "$1/wl-paste.text" && printf TSLA > "$1/wl-paste.primary"', "sh", state]
      owning.running = true
      tryVerify(function() { return !owning.running }, 2000)
      p = place(4)
      mouseClick(field, p.x, p.y, Qt.MiddleButton)
      var middle = within(2000, function() { return field.text === "abc TSLAdef" })
      p = place(0)
      mouseClick(field, p.x, p.y, Qt.RightButton)
      // The field's right-click menu, and its Paste.
      var paste = null
      within(1500, function() {
        var menu = text.ContextMenu.menu
        for (var i = 0; menu && menu.opened && i < menu.count; i++) if (menu.itemAt(i).text === "Paste") paste = menu.itemAt(i)
        return !!paste
      })
      if (paste) click(paste)
      var menu = within(2000, function() { return field.text === "abc TSLAMSFTdef" })
      harness.check("the middle button pastes the primary selection where it lands, and the right-click menu's Paste the clipboard at the cursor",
        searching && middle && menu, [searching, middle, !!paste, menu, field.text].join(" | "))
      body.closeViews()
    }
  }
}
