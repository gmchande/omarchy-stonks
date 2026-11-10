import QtQuick
import qs.Commons
import "plugin" as Stonks

// What looks clickable acts, by the pointer alone but for the words typed
// into search. The real window (App.qml) on the real service, with real Qt
// pointer events. Each step is judged by what the lists and the surface
// then hold: a handler that lost its target, or a target that lost its
// handler, fails here. HOME and curl are scratch fixtures.
Harness {
  id: harness
  marker: "MOUSE DONE"

  Stonks.Service { id: service; pluginId: "grvc.stonks" }
  Stonks.Updates { id: updates; pluginId: "grvc.stonks" }
  // The camera hands its shots to the stand-ins on PATH (bin/).
  Stonks.Camera { id: camera }
  Stonks.App { id: app; service: service; updates: updates; camera: camera }

  Steps {
    name: "Mouse"
    when: service.ready

    readonly property var body: app.testBody

    function quiet() {
      tryVerify(function() { return service.arriving.length === 0 && service.testFeed.firstRun.length + service.testFeed.refreshRun.length === 0 }, 8000)
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
        return list.dragSymbol === "" && !list.settling && list.displayedSymbols.every(function(symbol) { return list.rowResting(symbol) })
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
      within(1000, function() { return body.watchlist.dragSymbol === rows[0] })
      mouseRelease(body, grip.x, grip.y + down)
      var carried = rows.slice(1, 2).concat([rows[0]]).concat(rows.slice(2))
      harness.check("a row dragged past the next takes its place, and the order is the lists' own",
        within(2000, function() { return service.symbols.join(",") === carried.join(",") }), service.symbols.join(","))
      rows = service.symbols.slice()
      rest()

      click(row(rows[0]), Qt.RightButton)
      var menu = within(1500, function() { return harness.findAll(body, "rowMenuLine").length > 0 && harness.inPlace(harness.findAll(body, "rowMenuLine")) })
      var lines = harness.findAll(body, "rowMenuLine")
      click(lines[lines.length - 1])
      harness.check("a right click opens the row's menu, and its last line chooses the row's lists",
        menu && within(1500, function() { return body.listsSymbol === rows[0] }), menu + " " + body.listsSymbol)
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

      click("orderLabel")
      var ordered = within(1500, function() { return service.order === "symbol" })
      click("orderArrow")
      var reversed = within(1500, function() { return service.reversed })
      // A percent, then an amount, then since the open.
      var next = ({ pct: "abs", abs: "open", open: "pct" })[service.changeMode]
      click("unitTarget")
      harness.check("the order's word steps the order, its arrow reverses it, and the unit steps to the next unit",
        ordered && reversed && within(1500, function() { return service.changeMode === next }), [service.order, service.reversed, service.changeMode, "wanted " + next].join(" "))
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
      var rowsList = body.watchlist
      var doomed = rowsList.displayedSymbols.filter(function(symbol, i) { return rowsList.wholeInSight(i, rowsList.contentY) })[1]
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

      var before = service.symbols.join(",")
      var list = body.watchlist
      var over = list.mapToItem(body, list.width / 2, list.height / 2)
      mouseMove(body, over.x, over.y)
      mouseWheel(body, over.x, over.y, 0, -120)
      harness.check("the wheel scrolls the rows and moves none",
        list.contentHeight > list.height && within(1500, function() { return list.contentY > 0 }) && service.symbols.join(",") === before,
        [list.contentHeight, list.height, list.contentY, service.symbols.join(",")].join(" "))

      app.close()
      harness.finish()
    }
  }
}
