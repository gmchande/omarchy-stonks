import QtQuick
import QtTest
import Quickshell
import Quickshell.Io
import "plugin" as Stonks

// Adding symbols in the window, through the real App and Service with real
// Qt keys and pointer: an add held until its price is in, its row joining
// at its place, the list easing to it, adds out at a close or a list
// switch, two adds in a row, adds from search, and a joining row's day line
// drawn in, whole once drawn. HOME and curl are scratch fixtures.
ShellRoot {
  id: harness

  property int failures: 0

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

  function sameSymbols(expected) {
    return service.symbols.join(",") === expected.join(",")
  }

  function finish() {
    console.log("WINDOW ADDS DONE")
    done.exitCode = failures ? 1 : 0
    done.start()
  }

  Stonks.Service { id: service }
  Stonks.App { id: app; service: service }

  TestCase {
    name: "WindowAdds"
    when: service.pluginsReady

    // Waits up to ms for fn to hold and returns whether it does, so the
    // check that reads it is the one that fails.
    function within(ms, fn) {
      for (var t = 0; t < ms && !fn(); t += 20) wait(20)
      return fn()
    }

    function findAll(item, name, into) {
      var out = into || []
      if (!item) return out
      if (item.objectName === name) out.push(item)
      for (var i = 0; i < item.children.length; i++) findAll(item.children[i], name, out)
      if (item.contentItem) findAll(item.contentItem, name, out)
      return out
    }

    // Search open with its answer (the saved SHOP results) in the rows' place.
    function searchShop(body, keys) {
      keys.forceActiveFocus()
      keyClick(Qt.Key_A)
      wait(50)
      keyClick(Qt.Key_S)
      keyClick(Qt.Key_H)
      tryVerify(function() { return body.adding && body.search.results.length > 1 }, 3000)
      wait(50)
    }

    // The six symbols these flows start from, in manual order, `featured`
    // on `range`, the window tall enough for every row.
    function sixRows(body, featured, range) {
      var six = ["AAPL", "MSFT", "NVDA", "FLAT", "DOWN", "STRAY"]
      six.forEach(function(s) { service.addSymbol(s) })
      tryVerify(function() { return service.arriving.length === 0 && service.testFeed.firstRun.length + service.testFeed.refreshRun.length === 0 }, 8000)
      service.setManualOrder(six.concat(service.library.filter(function(s) { return six.indexOf(s) < 0 })))
      service.persist({ order: "manual", featured: featured })
      service.setRange(range)
      mouseMove(body, 1, 1)
      app.close()
      app.testWindow.implicitHeight = body.chromeHeight + 7 * body.rowPitch
      app.open("{}")
      wait(200)
    }

    // What search hands the rows: a pick lands as any new row does, the list
    // says it is empty only when it is, and a double-click is one click.
    function addsFromSearch(body, watchlist, keys) {
      service.addSymbol("SHOP.TO")
      tryVerify(function() { return !!service.quotes["SHOP.TO"] && service.testFeed.firstRun.length + service.testFeed.refreshRun.length === 0 }, 5000)
      service.feature("AAPL")

      // A result already in All joins a list that lacks it the way a new
      // symbol does: faded in at its place, the rows below sliding, in smooth
      // on one list and retro on another. Found in the transition audit
      // (search 3): it was already in place at full opacity, the rows below
      // already moved, because it joined while the results hid the rows.
      var joins = function(name, members, look) {
        service.persist({ style: look })
        service.createList(name)
        members.forEach(function(s) { service.setMembership(s, name, true) })
        service.setOrder("symbol")
        wait(100)
        searchShop(body, keys)
        var row = watchlist.rowItem("SHOP.TO")
        var below = watchlist.rowItem("STRAY")
        var faded = false
        var slid = false
        var onFade = function() { if (row.visible && row.opacity < 1) faded = true }
        var onSlide = function() { if (below.shift !== 0) slid = true }
        row.opacityChanged.connect(onFade)
        below.shiftChanged.connect(onSlide)
        // A click on the result takes it.
        var result = findAll(body.search, "searchResult")[1]
        mouseClick(result, result.width / 4, result.height / 2)
        tryVerify(function() {
          return watchlist.displayedSymbols.indexOf("SHOP.TO") >= 0 && !watchlist.settling
            && watchlist.displayedSymbols.every(function(s) { return watchlist.rowItem(s).resting })
        }, 3000)
        row.opacityChanged.disconnect(onFade)
        below.shiftChanged.disconnect(onSlide)
        service.switchList("")
        service.deleteList(name)
        wait(50)
        return look + ":" + faded + "," + slid
      }
      var smoothJoin = joins("Mid", ["AAPL", "NVDA", "STRAY"], "smooth")
      var retroJoin = joins("Mid2", ["DOWN", "FLAT", "STRAY"], "retro")
      service.persist({ style: "smooth" })
      harness.check("a result already in All fades in at its place and the rows below slide, smooth and retro",
        smoothJoin === "smooth:true,true" && retroJoin === "retro:true,true", smoothJoin + " | " + retroJoin)

      // A named list whose only member is still arriving is not empty: it
      // never says so, and the popup's height counts only answered rows,
      // so it holds the empty list's one row while the add is out and the
      // row joins in that row's place. From New list… in the menu and from
      // a list emptied by x. Found in the transition audit (lists 8, lists
      // 15): "No symbols in Wins yet" stood until the quote landed, and the
      // popup kept an empty row's gap above its footer.
      var emptyLine = harness.find(body, "emptyList")
      var arrive = function(open) {
        open()
        tryVerify(function() { return body.adding && service.symbols.length === 0 }, 2000)
        var said = false
        var heights = []
        // Read on frames: what a frame shows, not the steps within one turn.
        var watch = function() {
          if (emptyLine.visible && !body.adding) said = true
          if (service.arriving.indexOf("SLOW") >= 0) heights.push(body.fittedHeight(100000))
        }
        var frames = Qt.createQmlObject('import QtQuick; FrameAnimation { running: true }', harness)
        frames.triggered.connect(watch)
        body.search.picked("SLOW")
        wait(50)
        watch()
        tryVerify(function() { return watchlist.displayedSymbols.indexOf("SLOW") >= 0 }, 5000)
        frames.destroy()
        var joined = body.fittedHeight(100000)
        var held = heights.length > 0 && heights.every(function(h) { return h === joined })
        var list = service.listName
        service.switchList("")
        service.deleteList(list)
        service.removeSymbol("SLOW")
        tryVerify(function() { return service.testFeed.firstRun.length + service.testFeed.refreshRun.length === 0 }, 5000)
        return [!said, held, joined === body.chromeHeight + body.listRowHeight].join(",")
      }
      var fromMenu = arrive(function() {
        keys.forceActiveFocus()
        keyClick(Qt.Key_W)
        wait(50)
        var menu = harness.find(body, "listMenu")
        while (menu.cursor < menu.newIndex) keyClick(Qt.Key_Down)
        keyClick(Qt.Key_Return)
        wait(50)
        ;["W", "i", "n", "s"].forEach(function(c) { keyClick(c) })
        keyClick(Qt.Key_Return)
        wait(100)
      })
      var fromEmptied = arrive(function() {
        service.createList("Solo")
        service.setMembership("FLAT", "Solo", true)
        wait(100)
        keys.forceActiveFocus()
        keyClick(Qt.Key_X)
        wait(50)
        keyClick(Qt.Key_A)
        wait(50)
      })
      harness.check("a list whose only member is arriving never says it is empty, and holds its one row until the row joins there",
        fromMenu === "true,true,true" && fromEmptied === "true,true,true", fromMenu + " | " + fromEmptied)

      // A double-click on a result is one pick: its second click does not
      // feature the row that takes the result's place, for a symbol new to
      // All and for one already in it, the keyboard's choice on another
      // result. On the footer's undo note it is one undo, not an undo and
      // then a search. Found in the transition audit (search 4): the row
      // under the pointer took the hero.
      var doublePick = function(index, symbol) {
        service.feature(watchlist.displayedSymbols[3])
        wait(400)
        var heroes = []
        var watch = function() { heroes.push(service.featuredSymbol) }
        service.dataSettingsChanged.connect(watch)
        searchShop(body, keys)
        var result = findAll(body.search, "searchResult")[index]
        var at = result.mapToItem(body, result.width / 4, result.height / 2)
        mouseDoubleClickSequence(body, at.x, at.y)
        within(1500, function() { return service.featuredSymbol === symbol })
        wait(200)
        service.dataSettingsChanged.disconnect(watch)
        var hero = service.featuredSymbol
        mouseMove(body, 1, 1)
        return hero + ":" + heroes.filter(function(h, i) { return i === 0 || h !== heroes[i - 1] }).join(">")
      }
      var heroBefore = watchlist.displayedSymbols[3]
      var newPick = doublePick(0, "SHOP")
      service.removeSymbol("SHOP")
      service.removeSymbol("SHOP.TO")
      tryVerify(function() { return service.testFeed.firstRun.length + service.testFeed.refreshRun.length === 0 }, 5000)
      service.createList("Mid3")
      ;["AAPL", "NVDA", "MSFT", "DOWN"].forEach(function(s) { service.setMembership(s, "Mid3", true) })
      service.addSymbol("SHOP.TO")
      service.switchList("Mid3")
      tryVerify(function() { return !!service.quotes["SHOP.TO"] }, 5000)
      service.setMembership("SHOP.TO", "Mid3", false)
      wait(100)
      var knownPick = doublePick(1, "SHOP.TO")
      harness.check("a double-click on a result adds it once and features no row under it, new to All and already in it",
        newPick === heroBefore + ":" + heroBefore && knownPick === "SHOP.TO:SHOP.TO",
        newPick + " | " + knownPick)
      service.switchList("")
      service.deleteList("Mid3")
      service.removeSymbol("SHOP.TO")
      wait(100)
      watchlist.cursorSymbol = "NVDA"
      keys.forceActiveFocus()
      keyClick(Qt.Key_X)
      wait(50)
      var footer = harness.find(body, "footer")
      var footerAt = footer.mapToItem(body, footer.width / 2, footer.height / 2)
      mouseDoubleClickSequence(body, footerAt.x, footerAt.y)
      wait(100)
      var undone = service.library.indexOf("NVDA") >= 0
      var searching = body.adding
      if (searching) keyClick(Qt.Key_Escape)
      wait(50)
      harness.check("a double-click on the undo note undoes once and opens no search",
        undone && !searching, undone + "|" + searching)

      // A member still arriving says Show too, and Enter on it features its
      // row once its first answer is in, a failed one included. Found in the
      // branch's review: accepted before its first fetch failed, it featured
      // nothing.
      service.feature("AAPL")
      wait(300)
      service.addSymbol("SHHI.NE")
      searchShop(body, keys)
      keyClick(Qt.Key_Down)
      keyClick(Qt.Key_Down)
      wait(50)
      var arrivingShow = [service.arriving.indexOf("SHHI.NE") >= 0,
        harness.find(findAll(body.search, "searchResult")[2], "searchAdd").children[0].text].join(",")
      keyClick(Qt.Key_Return)
      within(12000, function() { return service.featuredSymbol === "SHHI.NE" })
      wait(300)
      harness.check("Show on a member still arriving features its row once its first fetch fails",
        arrivingShow === "true,SHOW" && service.featuredSymbol === "SHHI.NE" && !!service.entries["SHHI.NE"]
          && service.entries["SHHI.NE"].status === "failed" && watchlist.cursorRow === "SHHI.NE",
        arrivingShow + "|" + service.featuredSymbol + "|" + JSON.stringify(service.entries["SHHI.NE"]) + "|" + watchlist.cursorRow)

      // A result already in the list on screen says Show, with Enter's key,
      // in the slot Add takes, so the codes keep their column; Enter, or a
      // click on it, features its row and adds nothing. So for a member
      // whose first fetch failed. Found in design pass 3: it said Add, and
      // for a failed member Enter did nothing at all.
      service.addSymbol("SHOP.TO")
      tryVerify(function() {
        return !!service.quotes["SHOP.TO"] && service.arriving.length === 0 && service.testFeed.firstRun.length + service.testFeed.refreshRun.length === 0
      }, 20000)
      var shows = function(index, symbol, byClick) {
        service.feature("AAPL")
        wait(300)
        var library = service.library.join(",")
        searchShop(body, keys)
        var results = findAll(body.search, "searchResult").filter(function(r, i, all) { return all.indexOf(r) === i })
        var words = results.map(function(r) { return harness.find(r, "searchAdd").children[0].text })
        var widths = results.map(function(r) { return harness.find(r, "searchAdd").width })
        if (byClick) {
          mouseClick(results[index], results[index].width / 4, results[index].height / 2)
        } else {
          for (var down = 0; down < index; down++) keyClick(Qt.Key_Down)
          wait(50)
          keyClick(Qt.Key_Return)
        }
        within(1500, function() { return service.featuredSymbol === symbol })
        wait(300)
        return [words.join("/"), widths.every(function(w) { return w === widths[0] }),
          service.featuredSymbol, !body.adding, service.library.join(",") === library,
          watchlist.cursorRow === symbol].join("|")
      }
      var labels = "ADD/SHOW/SHOW/ADD/ADD|true|"
      var answered = shows(1, "SHOP.TO")
      var failedMember = shows(2, "SHHI.NE")
      var clicked = shows(1, "SHOP.TO", true)
      harness.check("search says Show for a member and Enter features its row, adding nothing",
        answered === labels + "SHOP.TO|true|true|true", answered)
      harness.check("Show features a member whose first fetch failed",
        failedMember === labels + "SHHI.NE|true|true|true", failedMember)
      harness.check("a click on a member's result shows it as Enter does, adding nothing",
        clicked === labels + "SHOP.TO|true|true|true", clicked)

      // Show is a choice of hero: it ends an add still waiting for its quote,
      // and the shown symbol stays featured when that quote lands. Shown here
      // is the top result, SHOP, already the hero, so neither the preview
      // nor the Show changes the featured symbol. FLAKY's first answer comes
      // after two failed tries, about five seconds on. Found in an AI
      // review: the hero jumped to the add.
      service.addSymbol("SHOP")
      tryVerify(function() { return service.arriving.indexOf("SHOP") < 0 && service.testFeed.firstRun.length + service.testFeed.refreshRun.length === 0 }, 20000)
      service.feature("SHOP")
      wait(300)
      keys.forceActiveFocus()
      keyClick(Qt.Key_A)
      wait(50)
      body.search.picked("FLAKY")
      var waiting = [body.landing, service.arriving.indexOf("FLAKY") >= 0].join(",")
      searchShop(body, keys)
      var shownWord = harness.find(findAll(body.search, "searchResult")[0], "searchAdd").children[0].text
      keyClick(Qt.Key_Return)
      wait(300)
      var shownFirst = [shownWord, service.featuredSymbol, body.adding].join(",")
      tryVerify(function() { return watchlist.displayedSymbols.indexOf("FLAKY") >= 0 && !watchlist.settling }, 15000)
      wait(1000)
      harness.check("Show ends an add still waiting for its quote, and the shown symbol stays featured when it lands",
        waiting === "FLAKY,true" && shownFirst === "SHOW,SHOP,false" && service.featuredSymbol === "SHOP" && body.landing === "",
        waiting + "|" + shownFirst + "|" + service.featuredSymbol + "|" + body.landing)
      service.removeSymbol("FLAKY")
      service.removeSymbol("SHOP")
      service.removeSymbol("SHOP.TO")
      service.removeSymbol("SHHI.NE")
      tryVerify(function() { return service.testFeed.firstRun.length + service.testFeed.refreshRun.length === 0 }, 5000)
      wait(100)
    }

    // A row that joins draws its day line in, and is whole once drawn:
    // after an add lands and after an undo, in smooth and retro. A list
    // switch and a sort show every row whole at once. Read on frames, what
    // a frame shows: each frame's least of the joining row's line, and of
    // every row's on a switch. No timing is judged here (window-motion
    // judges the motion on its pictures).
    function joiningLines(body, watchlist, keys) {
      service.createList("Lines")
      ;["AAPL", "NVDA", "STRAY"].forEach(function(s) { service.setMembership(s, "Lines", true) })
      service.switchList("Lines")
      service.setOrder("manual")
      wait(100)
      var lineOf = function(symbol) {
        var row = watchlist.rowItem(symbol)
        return row ? harness.find(row, watchlist.retro ? "rowCells" : "rowLine") : null
      }
      // The least reveal any frame showed of `symbols`' lines while `act`
      // runs, until `done` holds, and whether each is whole at the end.
      var watchLines = function(symbols, act, done) {
        var least = 1
        var watch = function() {
          symbols().forEach(function(s) {
            var line = lineOf(s)
            if (line && watchlist.rowItem(s).visible) least = Math.min(least, line.reveal)
          })
        }
        var frames = Qt.createQmlObject('import QtQuick; FrameAnimation { running: true }', harness)
        frames.triggered.connect(watch)
        act()
        tryVerify(done, 5000)
        tryVerify(function() { return symbols().every(function(s) { var l = lineOf(s); return !!l && l.reveal === 1 }) }, 3000)
        watch()
        frames.destroy()
        var whole = symbols().every(function(s) { return lineOf(s).reveal === 1 })
        var drawable = symbols().every(function(s) { return lineOf(s).drawable })
        return { drew: least < 1, whole: whole, drawable: drawable, least: least }
      }
      var joined = []
      ;["smooth", "retro"].forEach(function(look) {
        service.persist({ style: look })
        wait(50)
        var slow = function() { return ["SLOW"] }
        var shown = function() { return watchlist.displayedSymbols.indexOf("SLOW") >= 0 }
        var added = watchLines(slow, function() { body.search.picked("SLOW") }, shown)
        tryVerify(function() { return !watchlist.settling && watchlist.rowResting("SLOW") }, 3000)
        keys.forceActiveFocus()
        watchlist.cursorSymbol = "SLOW"
        keyClick(Qt.Key_X)
        tryVerify(function() { return !shown() }, 2000)
        var undone = watchLines(slow, function() { keyClick(Qt.Key_U) }, shown)
        // Closed mid draw-in, the line holds where it is; the next open
        // shows it whole, not half drawn.
        keys.forceActiveFocus()
        watchlist.cursorSymbol = "SLOW"
        keyClick(Qt.Key_X)
        tryVerify(function() { return !shown() }, 2000)
        keyClick(Qt.Key_U)
        var drawing = lineOf("SLOW").reveal
        app.close()
        wait(100)
        var held = lineOf("SLOW").reveal
        app.open("{}")
        var reopened = lineOf("SLOW").reveal
        wait(200)
        var closing = { drawing: drawing, held: held, reopened: reopened }
        joined.push(look + " add " + JSON.stringify(added) + " undo " + JSON.stringify(undone) + " closed " + JSON.stringify(closing))
        joined.push(added.drew && added.whole && added.drawable && undone.drew && undone.whole && undone.drawable
          && drawing < 1 && held === drawing && reopened === 1 ? "ok" : "FAILED")
        service.removeSymbol("SLOW")
        tryVerify(function() { return !shown() }, 2000)
      })
      harness.check("a row that joins, by an add that lands or an undo, draws its day line in and shows it whole once drawn, smooth and retro; closed mid draw-in, it opens whole",
        joined.every(function(r) { return r !== "FAILED" }), joined.join(" | "))

      var atOnce = []
      ;["smooth", "retro"].forEach(function(look) {
        service.persist({ style: look })
        wait(50)
        var rows = function() { return watchlist.displayedSymbols }
        var toAll = watchLines(rows, function() { service.switchList("") }, function() { return service.listName === "" })
        var back = watchLines(rows, function() { service.switchList("Lines") }, function() { return service.listName === "Lines" })
        var sorted = watchLines(rows, function() { service.setOrder("symbol") }, function() { return service.order === "symbol" })
        service.setOrder("manual")
        atOnce.push(look + " " + [toAll, back, sorted].map(function(r) { return !r.drew && r.whole ? "ok" : "FAILED " + JSON.stringify(r) }).join(","))
      })
      harness.check("a list switch and a sort show every row's day line whole at once, smooth and retro",
        atOnce.every(function(r) { return r.indexOf("FAILED") < 0 }), atOnce.join(" | "))
      service.persist({ style: "smooth" })
      service.switchList("")
      service.deleteList("Lines")
      // Taken off Lines only, it is still in All.
      service.removeSymbol("SLOW")
      wait(100)
    }

    function test_flows() {
      tryVerify(function() {
        return service.quotes.AAPL && service.quotes.MSFT && service.quotes.NVDA
          && service.testFeed.firstRun.length + service.testFeed.refreshRun.length === 0
      }, 10000)

      app.open("{}")
      wait(200)
      var body = app.testBody
      var watchlist = body.watchlist
      var keys = app.testKeyCatcher

      // These flows start from three rows in this order, AAPL featured on its
      // year.
      service.setManualOrder(["NVDA", "AAPL", "MSFT"])
      service.feature("AAPL")
      service.setRange("1Y")
      wait(300)

      // Reopened one row tall. Picking a symbol the list already holds, out
      // of view, features it and brings its row into view.
      app.close()
      // One row tall: the chart kept whole, as the window's own gives way
      // to three rows (StonksBody.minChartHeight).
      body.minChartHeight = 0
      app.testWindow.implicitHeight = body.chromeHeight + body.listRowHeight
      app.open("{}")
      wait(300)
      var existingRow = watchlist.rowItem("MSFT")
      var outOfView = existingRow.y >= watchlist.contentY + watchlist.height
      body.search.picked("MSFT")
      // The list eases the row in, then the chart changes.
      wait(300)
      harness.check("adding an existing symbol features, selects, and scrolls",
        outOfView && harness.sameSymbols(["NVDA", "AAPL", "MSFT"])
          && service.featuredSymbol === "MSFT" && watchlist.cursorSymbol === "MSFT"
          && existingRow.y >= watchlist.contentY
          && existingRow.y + existingRow.height <= watchlist.contentY + watchlist.height)

      // An add keeps the hero on what you were looking at until the new
      // symbol's price is in (the fake curl answers SLOW after a second, as
      // AAPL, up 2.61%), then features it, and its row joins at its sorted
      // place, above DOWN's fall. Found in motion pass 3: the hero emptied
      // ("No data") for as long as the fetch took, and the row slid up from
      // the end of the list over the others.
      mouseMove(body, 1, 1)
      var rangeBefore = service.range
      // The add steps below sort by % change; the order goes back after them.
      var orderBefore = service.order
      service.setRange("1D")
      service.setOrder("pct")
      service.addSymbol("DOWN")
      tryVerify(function() { return !!service.quotes.DOWN }, 3000)
      wait(50)
      var heroBefore = service.featuredSymbol
      var heroEmptied = false
      var watchHero = function() { if (!body.featuredQuote) heroEmptied = true }
      body.featuredQuoteChanged.connect(watchHero)
      body.search.picked("SLOW")
      wait(20)
      var slowRow = watchlist.rowItem("SLOW")
      var slowSlid = 0
      var watchSlide = function() { slowSlid = Math.max(slowSlid, Math.abs(slowRow.shift)) }
      slowRow.shiftChanged.connect(watchSlide)
      var heldWhileOut = service.featuredSymbol === heroBefore && watchlist.displayedSymbols.indexOf("SLOW") < 0
      // A number key counts only the rows you can see. It used to count the
      // add still out, sorted last, and feature a symbol with no price.
      keys.forceActiveFocus()
      keyClick(String(watchlist.displayedSymbols.length + 1))
      var keyedPending = service.featuredSymbol !== heroBefore
      tryVerify(function() { return service.featuredSymbol === "SLOW" }, 5000)
      wait(200)
      body.featuredQuoteChanged.disconnect(watchHero)
      slowRow.shiftChanged.disconnect(watchSlide)
      harness.check("an add keeps the hero until the new price is in, then features it, its row joining at its place",
        heldWhileOut && !keyedPending && !heroEmptied && !!body.featuredQuote && watchlist.cursorSymbol === "SLOW"
          && watchlist.displayedSymbols.indexOf("SLOW") === 3 && slowSlid === 0 && slowRow.y === 3 * watchlist.rowPitch,
        [heldWhileOut, keyedPending, heroEmptied, !!body.featuredQuote, watchlist.cursorSymbol,
          watchlist.displayedSymbols.join(","), slowSlid].join("|"))
      // Its place is out of view (the window is one row tall), so the list
      // eases there over several frames, and the chart draws in once the
      // list is at rest, from the row where it ended up; a wheel already
      // gliding when the price lands, or turned during the ease, only moves
      // where that rest is. Found in motion pass 3: the list jumped to the
      // new row in one frame, and then (review) a stopped or restarted wheel
      // glide featured the row from the old or a passing position.
      var landWith = function(wheel) {
        service.removeSymbol("SLOW")
        wait(50)
        watchlist.contentY = wheel === "before" ? watchlist.rowPitch : 0
        var scrolls = []
        var watchScroll = function() { scrolls.push(Math.round(watchlist.contentY)) }
        var at = null
        // The draw-in starts as the service's change reaches the body, which
        // may be after it reaches this handler.
        var drew = false
        var watchDraw = function() { if (body.motion.reveal === 0 && service.featuredSymbol === "SLOW") drew = true }
        var watchFeature = function() {
          if (service.featuredSymbol !== "SLOW" || at !== null) return
          var y = watchlist.rowItem("SLOW").y
          at = { contentY: watchlist.contentY,
            inView: y >= watchlist.contentY && y + watchlist.rowHeight <= watchlist.contentY + watchlist.height }
        }
        var wheeled = false
        var wheelBefore = function() {
          if (wheel !== "before" || wheeled || !service.quotes.SLOW) return
          wheeled = true
          watchlist.wheelBy(-1)
        }
        // During: on a frame of the selection's own glide, once the price is
        // in and the arrival done, and SLOW is still the hero to come.
        // Then another symbol's answer lands before the list rests: it must
        // not take the list back from the wheel. Found in the review of the
        // untangle: every view change selected the add again.
        var wheelDest = -1
        var wheelDuring = function() {
          if (wheel !== "during" || wheeled || !service.quotes.SLOW || service.arriving.indexOf("SLOW") >= 0
              || body.landing !== "SLOW" || !watchlist.settling) return
          wheeled = true
          watchlist.wheelBy(1)
          wheelDest = watchlist.snappedY(watchlist.wheelTarget())
          Qt.callLater(function() {
            var next = Object.assign({}, service.testFeed.quotes)
            next.DOWN = Object.assign({}, next.DOWN, { price: next.DOWN.price + 0.01 })
            service.testFeed.quotes = next
          })
        }
        watchlist.contentYChanged.connect(watchScroll)
        body.motion.revealChanged.connect(watchDraw)
        service.featuredSymbolChanged.connect(watchFeature)
        service.quotesChanged.connect(wheelBefore)
        watchlist.contentYChanged.connect(wheelDuring)
        body.search.picked("SLOW")
        tryVerify(function() { return at !== null }, 5000)
        wait(700)
        watchlist.contentYChanged.disconnect(watchScroll)
        body.motion.revealChanged.disconnect(watchDraw)
        service.featuredSymbolChanged.disconnect(watchFeature)
        service.quotesChanged.disconnect(wheelBefore)
        watchlist.contentYChanged.disconnect(wheelDuring)
        var restedFirst = at !== null && at.contentY === watchlist.contentY
        var ok = wheel === "" ? restedFirst && scrolls.length >= 4 && drew && at.inView
          : restedFirst && wheeled && (wheel !== "during" || watchlist.contentY === wheelDest)
        return ok ? "true" : [restedFirst, scrolls.length, drew, JSON.stringify(at), wheeled, wheelDest, watchlist.contentY].join(":")
      }
      var landings = [landWith(""), landWith("before"), landWith("during")]
      harness.check("the list eases to a new row out of view, and the chart changes only once it is at rest",
        landings.join(",") === "true,true,true", landings.join(","))
      service.removeSymbol("SLOW")
      service.removeSymbol("DOWN")
      service.setRange(rangeBefore)
      wait(50)

      // An add still out when the window closes goes with that visit: its
      // answer, landing while the window is closed or after it reopens and
      // something else is chosen, neither features the symbol nor moves the
      // cursor or the list (one row tall, so a selection would scroll it).
      // Found in motion pass 3 review: a late answer featured the old add
      // over the choice made since, and moved the cursor and the scroll
      // while the window was closed.
      var lateAdd = function(reopenFirst) {
        body.search.picked("SLOW")
        wait(20)
        app.close()
        if (reopenFirst) {
          app.open("{}")
          wait(50)
          service.feature("NVDA")
        }
        watchlist.contentY = 0
        watchlist.cursorSymbol = ""
        var hero = service.featuredSymbol
        tryVerify(function() { return !!service.quotes.SLOW }, 5000)
        wait(100)
        var kept = [service.featuredSymbol === hero, watchlist.contentY === 0, watchlist.cursorSymbol === ""]
        if (!reopenFirst) app.open("{}")
        wait(50)
        service.removeSymbol("SLOW")
        wait(50)
        return kept.join(",")
      }
      var whileClosed = lateAdd(false)
      var afterReopen = lateAdd(true)
      harness.check("an add still out at a close moves nothing, while closed or after a reopen",
        whileClosed === "true,true,true" && afterReopen === "true,true,true", whileClosed + " / " + afterReopen)

      // An add still out when you switch to a list without it is done
      // there: its answer lands without featuring it or moving the list you
      // switched to. Found in the review of the untangle: the new list's
      // hero jumped to the old list's add.
      var heroBeforeSwitch = service.featuredSymbol
      body.search.picked("SLOW")
      wait(20)
      service.createList("Elsewhere")
      service.addSymbol(heroBeforeSwitch)
      wait(50)
      watchlist.contentY = 0
      tryVerify(function() { return !!service.quotes.SLOW }, 5000)
      wait(300)
      harness.check("an add out when the list switches to one without it features nothing there",
        service.listName === "Elsewhere" && service.featuredSymbol === heroBeforeSwitch
          && watchlist.contentY === 0 && body.landing === "",
        service.listName + "|" + service.featuredSymbol + "|" + watchlist.contentY + "|" + body.landing)
      service.deleteList("Elsewhere")
      service.removeSymbol("SLOW")
      wait(50)

      // A symbol that leaves All before its first answer leaves arriving: it
      // is not held back if it is added again. Found in cubic's review of #24.
      // The window offers no row to remove it by; this is the file changing
      // under the service, as another surface or an edit would.
      body.search.picked("SLOW")
      wait(20)
      var wasArriving = service.arriving.indexOf("SLOW") >= 0
      var withoutSlow = Object.assign({}, service.dataSettings)
      withoutSlow.symbols = service.library.filter(function(s) { return s !== "SLOW" })
      service.persist(withoutSlow)
      wait(20)
      harness.check("a symbol leaving All before its first answer leaves arriving",
        wasArriving && service.arriving.indexOf("SLOW") < 0, wasArriving + "|" + service.arriving)
      // The fetch the pick started ends before SLOW is added again below.
      tryVerify(function() { return service.testFeed.firstRun.concat(service.testFeed.refreshRun).indexOf("SLOW") < 0 }, 5000)

      // Picking a symbol already in All whose first quote is still out (as at
      // a cold start) features it once that quote lands. Found in cubic's
      // review of #24: the landing was dropped for want of a quote.
      var withSlow = Object.assign({}, service.dataSettings)
      withSlow.symbols = service.library.concat(["SLOW"])
      service.persist(withSlow)
      wait(20)
      var slowWasOut = !service.quotes.SLOW && service.arriving.indexOf("SLOW") < 0
      body.search.picked("SLOW")
      tryVerify(function() { return !!service.quotes.SLOW }, 5000)
      var featuredOnAnswer = within(2000, function() { return service.featuredSymbol === "SLOW" })
      harness.check("picking a symbol in All whose first quote is out features it once the quote lands",
        slowWasOut && featuredOnAnswer, slowWasOut + "|" + service.featuredSymbol)
      service.removeSymbol("SLOW")
      wait(50)

      // A hero chosen while an add is still coming keeps the chart: chosen
      // before the new price lands, or while the list eases to the new row,
      // it is still the hero once the price is in and the list rests, and the
      // new row joins at its place all the same (SLOW ties its neighbours
      // and sorts fourth, out of the one-row view). Found in the review of
      // #21: the add's pending feature took the hero back.
      var chooseDuring = function(when) {
        watchlist.contentY = 0
        var target = watchlist.displayedSymbols.filter(function(s) { return s !== service.featuredSymbol })[0]
        var chosen = false
        var chooseInGlide = function() {
          if (chosen || service.arriving.length > 0 || body.landing !== "SLOW" || !watchlist.settling) return
          chosen = true
          app.testBody.featureSymbol(target)
        }
        if (when === "glide") {
          watchlist.settlingChanged.connect(chooseInGlide)
          body.landingChanged.connect(chooseInGlide)
        }
        body.search.picked("SLOW")
        wait(20)
        if (when === "before") {
          chosen = true
          app.testBody.featureSymbol(target)
        }
        tryVerify(function() { return !!service.quotes.SLOW }, 5000)
        wait(100)
        tryVerify(function() { return !watchlist.settling }, 2000)
        wait(400)
        if (when === "glide") {
          watchlist.settlingChanged.disconnect(chooseInGlide)
          body.landingChanged.disconnect(chooseInGlide)
        }
        var kept = [chosen, service.featuredSymbol === target, watchlist.displayedSymbols.indexOf("SLOW") === 3].join(",")
        service.removeSymbol("SLOW")
        wait(50)
        return kept
      }
      var chosenBefore = chooseDuring("before")
      var chosenInGlide = chooseDuring("glide")
      harness.check("a hero chosen while an add is still coming keeps the chart; the new row still joins at its place",
        chosenBefore === "true,true,true" && chosenInGlide === "true,true,true", chosenBefore + " / " + chosenInGlide)

      // Two adds in a row, the second before the first's price: each row
      // joins at its own place when its own price lands, and the chart goes
      // to the latest add. DOWN is in the list with its price (down 1.56%);
      // SLOW stays out of the list until, a second later, it lands above it (up 2.61%);
      // FLAT, queued behind SLOW, lands after it at 0%. Found in cubic's
      // review of #21: the second add took over the first's arrival, whose
      // row then slid up from the end of the list.
      service.addSymbol("DOWN")
      tryVerify(function() { return !!service.quotes.DOWN }, 3000)
      wait(50)
      watchlist.contentY = 0
      body.search.picked("SLOW")
      wait(20)
      var firstRow = watchlist.rowItem("SLOW")
      var firstSlid = 0
      var watchFirst = function() { firstSlid = Math.max(firstSlid, Math.abs(firstRow.shift)) }
      firstRow.shiftChanged.connect(watchFirst)
      var waitedAt = watchlist.displayedSymbols.indexOf("SLOW")
      body.search.picked("FLAT")
      tryVerify(function() { return !!service.quotes.SLOW && !!service.quotes.FLAT }, 5000)
      wait(100)
      tryVerify(function() { return !watchlist.settling }, 2000)
      wait(300)
      firstRow.shiftChanged.disconnect(watchFirst)
      harness.check("two adds in a row each join at their own place, and the chart goes to the latest",
        service.featuredSymbol === "FLAT" && waitedAt === -1 && firstSlid === 0 && service.arriving.length === 0
          && watchlist.displayedSymbols.indexOf("SLOW") === 3,
        [service.featuredSymbol, waitedAt, firstSlid, service.arriving, watchlist.displayedSymbols.join(",")].join("|"))
      service.removeSymbol("SLOW")
      service.removeSymbol("FLAT")
      service.removeSymbol("DOWN")
      service.setOrder(orderBefore)
      wait(50)

      // A manual reorder while an add is out saves every member: the add
      // keeps its place in the list, out of sight until its price lands.
      service.setOrder("manual")
      wait(50)
      body.search.picked("SLOW")
      wait(20)
      keys.forceActiveFocus()
      // A cursor of your own is one in sight.
      watchlist.contentY = 0
      watchlist.cursorSymbol = watchlist.displayedSymbols[0]
      var movedSymbol = watchlist.cursorSymbol
      var membersBefore = service.symbols.slice()
      keyClick(Qt.Key_J, Qt.ShiftModifier)
      wait(50)
      var membersAfter = service.symbols.slice()
      harness.check("a manual reorder with an add still out saves every member",
        membersBefore.indexOf("SLOW") >= 0 && watchlist.displayedSymbols.indexOf("SLOW") < 0
          && membersAfter.length === membersBefore.length && membersAfter.indexOf("SLOW") >= 0
          && membersAfter.indexOf(movedSymbol) === membersBefore.indexOf(movedSymbol) + 1,
        membersBefore + " -> " + membersAfter)
      tryVerify(function() { return !!service.quotes.SLOW }, 5000)
      wait(400)
      service.removeSymbol("SLOW")
      service.setOrder(orderBefore)
      wait(50)

      sixRows(body, "MSFT", "1Y")

      addsFromSearch(body, watchlist, keys)
      joiningLines(body, watchlist, keys)
      app.close()
      harness.finish()
    }
  }

  HarnessExit { id: done }
}
