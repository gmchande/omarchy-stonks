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

      click(row(rows[1]))
      harness.check("a click on a row shows its chart",
        within(1500, function() { return service.featuredSymbol === rows[1] }), service.featuredSymbol)

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
      var choices = function() { return harness.findAll(body, "listChoice") }
      var listed = within(1500, function() { return body.listMenuOpen && choices().length === 2 && harness.inPlace(choices()) })
      click(choices()[1])
      harness.check("a click on the list's name opens the menu, and a list's line shows that list",
        listed && within(1500, function() { return service.listName === "Tech" && !body.listMenuOpen }), listed + " " + service.listName)
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
      var shown = function() { return body.watchlist.displayedSymbols.join(",") }
      var aToZ = service.symbols.slice().sort()
      click("orderLabel")
      var ordered = within(1500, function() { return shown() === aToZ.join(",") })
      click("orderArrow")
      var reversed = within(1500, function() { return shown() === aToZ.slice().reverse().join(",") })
      // A percent, then an amount, then since the open.
      var next = ({ pct: "abs", abs: "open", open: "pct" })[service.changeMode]
      click("unitTarget")
      harness.check("the order's word puts the rows in the next order, its arrow reverses them, and the unit steps to the next unit",
        ordered && reversed && within(1500, function() { return service.changeMode === next }), [ordered, reversed, shown(), service.changeMode, "wanted " + next].join(" "))
      service.setOrder("manual")

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

      // QtTest sends no touchpad, so its event goes to the list's handler as
      // the WheelHandler hands it on: a swipe whose pixels Hyprland cut to 0.4.
      var swipeFrom = list.contentY
      list.wheelEvent(Qt.ScrollUpdate, -10, 0)
      harness.check("a touchpad swipe moves the rows three times its pixels, as Omarchy's menu does",
        Math.abs(list.contentY - swipeFrom - 30) < 0.5, swipeFrom + " " + list.contentY)

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
