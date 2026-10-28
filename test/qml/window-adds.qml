import QtQuick
import QtTest
import Quickshell
import Quickshell.Io
import "plugin" as Stonks

// Adds through the real App and Service: accepted previews, arriving rows,
// chosen charts, list membership, and a stock put back asking for its quote
// at once. The review kit keeps their ink and motion. HOME and curl are
// scratch fixtures.
Harness {
  id: harness
  marker: "WINDOW ADDS DONE"

  function sameSymbols(expected) {
    return service.symbols.join(",") === expected.join(",")
  }

  // Nothing in the quote feed in flight or queued.
  function quiet() {
    return service.testFeed.firstRun.length + service.testFeed.refreshRun.length === 0
  }

  Stonks.Service { id: service }
  Stonks.App { id: app; service: service }
  Process { id: quoteFile }

  Steps {
    name: "WindowAdds"
    when: service.pluginsReady

    // Takes `symbol` out of All for good: its offer ends, as the next change
    // to the lists would end it, so picking it again adds it afresh rather
    // than puts it back. That add fetches again what the offer kept, its cap
    // and P/E among them, so Yahoo's budget is left as a minute's pause
    // would leave it: these adds come faster than anyone makes them.
    function removeForGood(symbol) {
      service.removeSymbol(symbol)
      service.lastRemoval = null
      service.yahooGate.tokens = service.yahooGate.capacity
    }

    // The list at rest, no add landing.
    function rested(body) {
      return !body.watchlist.settling && body.landing === ""
    }

    // MSFT is answered just before each removal, so its put-back comes well
    // before its next scheduled refresh, and its answer is held back while
    // out. Ctrl+Z and PUT BACK are both checked: the label names both.
    function putsBack(body, watchlist, keys) {
      service.setRange("1D")
      service.feature("AAPL")
      var still = function() { return quiet() && !("MSFT" in service.testFeed.asked) }
      tryVerify(still, 5000)
      var putBack = function(how) {
        var answered = service.entries.MSFT
        service.testFeed.ask(["MSFT"], service.wallSecond())
        tryVerify(function() { return still() && service.entries.MSFT !== answered }, 5000)
        watchlist.cursorSymbol = "MSFT"
        keys.forceActiveFocus()
        keyClick(Qt.Key_Delete)
        tryVerify(function() { return !!service.lastRemoval && service.library.indexOf("MSFT") < 0 }, 2000)
        var kept = service.lastRemoval.quote
        holdQuote("MSFT", true)
        var before = calls("MSFT")
        var said = [body.headerText]
        var heard = function() { if (said[said.length - 1] !== body.headerText) said.push(body.headerText) }
        body.headerTextChanged.connect(heard)
        how()
        var asked = within(2000, function() { return calls("MSFT") > before })
        var row = watchlist.rowItem("MSFT")
        var meanwhile = service.library.indexOf("MSFT") >= 0 && !!kept && service.quotes.MSFT === kept && !!row
        holdQuote("MSFT", false)
        tryVerify(quiet, 5000)
        body.headerTextChanged.disconnect(heard)
        return [asked, meanwhile, calls("MSFT") - before, said.indexOf("Refreshing") < 0].join(",")
      }
      var byU = putBack(function() { keyClick(Qt.Key_Z, Qt.ControlModifier) })
      var byClick = putBack(function() {
        keyClick(Qt.Key_A)
        var offer = function() { return findAll(body.search, "searchResult")[0] }
        tryVerify(function() {
          return body.adding && body.search.results.length > 0 && !!offer()
            && body.search.actionFor(body.search.results[0].symbol) === "PUT BACK"
        }, 2000)
        var button = find(offer(), "searchAdd")
        mouseClick(button, button.width / 2, button.height / 2)
      })
      check("a stock put back by Ctrl+Z, and by PUT BACK clicked, asks for its quote at once, once, showing the quote it had until the new one lands, and the header says nothing of it",
        byU === "true,true,1,true" && byClick === "true,true,1,true" && !body.adding,
        "Ctrl+Z " + byU + " | PUT BACK " + byClick + " | adding " + body.adding)
    }

    // Search open with its answer (the saved SHOP results) in the rows' place.
    function searchShop(body, keys) {
      keys.forceActiveFocus()
      keyClick(Qt.Key_A)
      tryVerify(function() { return body.adding && body.search.active }, 2000)
      keyClick(Qt.Key_S)
      keyClick(Qt.Key_H)
      tryVerify(function() {
        return body.search.results.length > 1 && shownResults(body).length === body.search.results.length
      }, 3000)
    }

    // The result rows on screen, top first, each showing its place's result.
    // findAll lists rows in the order they were made, which is not their
    // order on screen.
    function shownResults(body) {
      var results = body.search.results
      var rows = []
      findAll(body.search, "searchResult").forEach(function(r) {
        var result = results[r.index]
        if (r.visible && result && result.symbol === r.modelData.symbol) rows[r.index] = r
      })
      return rows.filter(function(r) { return !!r })
    }

    function shownResult(body, symbol) {
      return shownResults(body).filter(function(r) { return r.modelData.symbol === symbol })[0]
    }

    // Picks `symbol` by keys and returns the word its result said.
    function pickSymbol(body, keys, symbol) {
      keys.forceActiveFocus()
      keyClick(Qt.Key_A)
      tryVerify(function() { return body.adding && body.search.active }, 2000)
      keyClick(Qt.Key_A, Qt.ControlModifier)
      var field = find(body.search, "searchField")
      field.forceActiveFocus()
      keyClick(Qt.Key_A, Qt.ControlModifier)
      for (var c = 0; c < symbol.length; c++) keyClick(symbol.charAt(c))
      tryVerify(function() { return body.search.resultsQuery === symbol && body.search.results.length === 1 }, 3000)
      var said = body.search.actionFor(symbol)
      keyClick(Qt.Key_Return)
      tryVerify(function() { return !body.adding }, 2000)
      return said
    }

    function holdQuote(symbol, held) {
      var path = Quickshell.env("STONKS_FAKE_STATE") + "/" + symbol + ".quote.hold"
      quoteFile.command = held ? ["touch", path] : ["rm", "-f", path]
      quoteFile.running = true
      tryVerify(function() { return !quoteFile.running }, 2000)
    }

    // The six symbols these flows start from, in manual order, `featured`
    // on `range`, the window tall enough for every row.
    function sixRows(body, featured, range) {
      var six = ["AAPL", "MSFT", "NVDA", "FLAT", "DOWN", "STRAY"]
      six.forEach(function(s) { service.addSymbol(s) })
      tryVerify(function() { return service.arriving.length === 0 && quiet() }, 8000)
      service.setManualOrder(six.concat(service.library.filter(function(s) { return six.indexOf(s) < 0 })))
      service.persist({ order: "manual", featured: featured })
      service.setRange(range)
      mouseMove(body, 1, 1)
      app.close()
      app.testWindow.implicitHeight = body.chromeHeight + 7 * body.rowPitch
      app.open("{}")
      tryVerify(function() { return !!body.watchlist.rowItem("STRAY") && rested(body) }, 2000)
    }

    // What search hands the rows: a pick lands as any new row does, the list
    // says it is empty only when it is, and a double-click is one click.
    function addsFromSearch(body, watchlist, keys) {
      service.addSymbol("SHOP.TO")
      tryVerify(function() { return !!service.quotes["SHOP.TO"] && quiet() }, 5000)
      service.feature("AAPL")

      // A new list from New list…, its only member still arriving. Read on
      // frames: what a frame shows, not the steps within one turn.
      var emptyLine = find(body, "emptyList")
      keys.forceActiveFocus()
      keyClick(Qt.Key_W)
      var menu = find(body, "listMenu")
      tryVerify(function() { return !!menu && menu.visible }, 2000)
      while (menu.cursor < menu.newIndex) keyClick(Qt.Key_Down)
      keyClick(Qt.Key_Return)
      tryVerify(function() { return menu.naming }, 2000)
      ;["W", "i", "n", "s"].forEach(function(c) { keyClick(c) })
      keyClick(Qt.Key_Return)
      tryVerify(function() { return body.adding && service.symbols.length === 0 }, 2000)
      var said = false
      var watch = function() {
        if (emptyLine.visible && !body.adding) said = true
      }
      var frames = Qt.createQmlObject('import QtQuick; FrameAnimation { running: true }', harness)
      frames.triggered.connect(watch)
      pickSymbol(body, keys, "SLOW")
      watch()
      tryVerify(function() { return watchlist.displayedSymbols.indexOf("SLOW") >= 0 }, 5000)
      frames.destroy()
      var joined = service.symbols.length === 1 && service.symbols[0] === "SLOW"
      var list = service.listName
      service.switchList("")
      service.deleteList(list)
      service.removeSymbol("SLOW")
      tryVerify(quiet, 5000)
      check("a list whose only member is arriving never says it is empty, and that member joins",
        !said && joined, said + " | " + joined)

      // A double-click on a result is one pick: its second click does not
      // feature the row that takes the result's place, for a symbol new to
      // All, which is the hero at once as it arrives (SHOP, whose answer
      // fails), and for one already in it, the keyboard's choice on another
      // result. The 200 ms after the hero lands is the second click's time
      // to do harm.
      var doublePick = function(symbol) {
        service.feature(watchlist.displayedSymbols[3])
        tryVerify(function() { return rested(body) }, 2000)
        var heroes = []
        var watchHero = function() { heroes.push(service.featuredSymbol) }
        service.dataSettingsChanged.connect(watchHero)
        searchShop(body, keys)
        var result = shownResult(body, symbol)
        var at = result.mapToItem(body, result.width / 4, result.height / 2)
        mouseDoubleClickSequence(body, at.x, at.y)
        within(1500, function() { return service.featuredSymbol === symbol })
        wait(200)
        service.dataSettingsChanged.disconnect(watchHero)
        var hero = service.featuredSymbol
        mouseMove(body, 1, 1)
        return hero + ":" + heroes.filter(function(h, i) { return i === 0 || h !== heroes[i - 1] }).join(">")
      }
      var newPick = doublePick("SHOP")
      service.removeSymbol("SHOP")
      service.removeSymbol("SHOP.TO")
      tryVerify(quiet, 5000)
      service.createList("Mid3")
      ;["AAPL", "NVDA", "MSFT", "DOWN"].forEach(function(s) { service.setMembership(s, "Mid3", true) })
      service.addSymbol("SHOP.TO")
      service.switchList("Mid3")
      tryVerify(function() { return !!service.quotes["SHOP.TO"] }, 5000)
      service.setMembership("SHOP.TO", "Mid3", false)
      tryVerify(function() { return watchlist.displayedSymbols.indexOf("SHOP.TO") < 0 && rested(body) }, 2000)
      var knownPick = doublePick("SHOP.TO")
      check("a double-click on a result adds it once and features no row under it, new to All and already in it",
        newPick === "SHOP:SHOP" && knownPick === "SHOP.TO:SHOP.TO",
        newPick + " | " + knownPick)
      service.switchList("")
      service.deleteList("Mid3")
      service.removeSymbol("SHOP.TO")

      // After a removal the footer is the add. A click on it opens search,
      // whose one result before any typing is what went, chosen, with PUT
      // BACK, the hero showing it; a double-click on it puts it back once,
      // in its lists at its place, the hero back as it was, its second
      // click featuring no row under it.
      service.feature("AAPL")
      tryVerify(function() { return rested(body) }, 2000)
      var listsBefore = JSON.stringify(service.lists)
      watchlist.cursorSymbol = "NVDA"
      keys.forceActiveFocus()
      keyClick(Qt.Key_Delete)
      var gone = within(1000, function() { return service.library.indexOf("NVDA") < 0 })
      var footer = find(body, "footer")
      var footerAt = footer.mapToItem(body, footer.width / 2, footer.height / 2)
      mouseClick(body, footerAt.x, footerAt.y)
      var offers = []
      tryVerify(function() {
        offers = findAll(body.search, "searchResult")
        return body.adding && body.search.results.length > 0 && offers.length > 0 && body.previewSymbol === "NVDA"
      }, 2000)
      var offered = body.search.results.map(function(r) { return r.symbol + " " + body.search.actionFor(r.symbol) }).join(",")
        + " chosen " + offers[0].chosen + " hero " + body.previewSymbol
      var putAt = offers[0].mapToItem(body, offers[0].width / 4, offers[0].height / 2)
      mouseDoubleClickSequence(body, putAt.x, putAt.y)
      within(2000, function() { return !body.adding && service.featuredSymbol === "AAPL" && service.lastRemoval === null })
      // Time for the second click to do harm.
      wait(200)
      check("after a removal, the footer's search offers it back first, chosen, with PUT BACK, and a double-click puts it back once in its lists at its place, the hero as it was",
        gone && offered === "NVDA PUT BACK chosen true hero NVDA" && !body.adding && JSON.stringify(service.lists) === listsBefore
          && service.featuredSymbol === "AAPL" && service.lastRemoval === null,
        [gone, offered, body.adding, JSON.stringify(service.lists), service.featuredSymbol, JSON.stringify(service.lastRemoval)].join(" | "))
      mouseMove(body, 1, 1)

      // A member still arriving says Show too, and Enter on it features it at
      // once, named as on its way, and its row once its first answer is in,
      // a failed one included.
      service.feature("AAPL")
      service.addSymbol("SHHI.NE")
      searchShop(body, keys)
      keyClick(Qt.Key_Down)
      keyClick(Qt.Key_Down)
      var arrivingShow = [service.arriving.indexOf("SHHI.NE") >= 0,
        find(shownResult(body, "SHHI.NE"), "searchAdd").children[0].text].join(",")
      keyClick(Qt.Key_Return)
      within(12000, function() {
        return !!service.entries["SHHI.NE"] && service.entries["SHHI.NE"].status === "failed" && watchlist.cursorRow === "SHHI.NE"
      })
      check("Show on a member still arriving features its row once its first fetch fails",
        arrivingShow === "true,SHOW" && service.featuredSymbol === "SHHI.NE" && !!service.entries["SHHI.NE"]
          && service.entries["SHHI.NE"].status === "failed" && watchlist.cursorRow === "SHHI.NE",
        arrivingShow + "|" + service.featuredSymbol + "|" + JSON.stringify(service.entries["SHHI.NE"]) + "|" + watchlist.cursorRow)

      // A result already in the list on screen says Show, and Enter on it
      // features its row and adds nothing, for a member whose first fetch
      // failed too.
      service.addSymbol("SHOP.TO")
      tryVerify(function() {
        return !!service.quotes["SHOP.TO"] && service.arriving.length === 0 && quiet()
      }, 20000)
      service.feature("AAPL")
      tryVerify(function() { return rested(body) }, 2000)
      var library = service.library.join(",")
      searchShop(body, keys)
      var results = shownResults(body)
      var words = results.map(function(r) { return find(r, "searchAdd").children[0].text })
      keyClick(Qt.Key_Down)
      keyClick(Qt.Key_Down)
      keyClick(Qt.Key_Return)
      within(1500, function() { return service.featuredSymbol === "SHHI.NE" && watchlist.cursorRow === "SHHI.NE" })
      var failedMember = [words.join("/"), service.featuredSymbol, !body.adding, service.library.join(",") === library,
        watchlist.cursorRow === "SHHI.NE"].join("|")
      check("Show features a member whose first fetch failed",
        failedMember === "ADD/SHOW/SHOW/ADD/ADD|SHHI.NE|true|true|true", failedMember)

      // Show is a choice of hero: it ends an add still waiting for its quote,
      // and the shown symbol stays featured when that quote lands. Shown here
      // is the top result, SHOP, already the hero, so neither the preview
      // nor the Show changes the featured symbol. FLAKY's first answer comes
      // after two failed tries, about five seconds on.
      service.addSymbol("SHOP")
      tryVerify(function() { return service.arriving.indexOf("SHOP") < 0 && quiet() }, 20000)
      service.feature("SHOP")
      pickSymbol(body, keys, "FLAKY")
      var waiting = [body.landing, service.arriving.indexOf("FLAKY") >= 0].join(",")
      searchShop(body, keys)
      var shownWord = find(shownResults(body)[0], "searchAdd").children[0].text
      keyClick(Qt.Key_Return)
      within(1000, function() { return !body.adding })
      var shownFirst = [shownWord, service.featuredSymbol, body.adding].join(",")
      tryVerify(function() { return watchlist.displayedSymbols.indexOf("FLAKY") >= 0 }, 15000)
      within(2000, function() { return rested(body) })
      check("Show ends an add still waiting for its quote, and the shown symbol stays featured when it lands",
        waiting === "FLAKY,true" && shownFirst === "SHOW,SHOP,false" && service.featuredSymbol === "SHOP" && body.landing === "",
        waiting + "|" + shownFirst + "|" + service.featuredSymbol + "|" + body.landing)
      service.removeSymbol("FLAKY")
      service.removeSymbol("SHOP")
      service.removeSymbol("SHOP.TO")
      service.removeSymbol("SHHI.NE")
      tryVerify(quiet, 5000)
    }

    function test_flows() {
      tryVerify(function() {
        return service.quotes.AAPL && service.quotes.MSFT && service.quotes.NVDA && quiet()
      }, 10000)

      app.open("{}")
      var body = app.testBody
      var watchlist = body.watchlist
      var keys = app.testKeyCatcher
      tryVerify(function() { return !!watchlist.rowItem("AAPL") }, 2000)

      var chapter = Quickshell.env("STONKS_ADD_FLOW")
      if (chapter === "search" || chapter === "putback") {
        sixRows(body, "MSFT", "1Y")
        if (chapter === "search") addsFromSearch(body, watchlist, keys)
        else putsBack(body, watchlist, keys)
        app.close()
        harness.finish()
        return
      }

      // These flows start from three rows in this order, AAPL featured on its
      // year, reopened one row tall: the chart kept whole, as the window's
      // own gives way to three rows (StonksBody.minChartHeight).
      service.setManualOrder(["NVDA", "AAPL", "MSFT"])
      service.feature("AAPL")
      service.setRange("1Y")
      app.close()
      body.minChartHeight = 0
      app.testWindow.implicitHeight = body.chromeHeight + body.listRowHeight
      app.open("{}")
      tryVerify(function() {
        return watchlist.height <= body.listRowHeight && !!watchlist.rowItem("MSFT") && rested(body)
      }, 2000)
      var existingRow = watchlist.rowItem("MSFT")
      var outOfView = existingRow.y >= watchlist.contentY + watchlist.height
      var said = pickSymbol(body, keys, "MSFT")
      var inView = function() {
        return existingRow.y >= watchlist.contentY
          && existingRow.y + existingRow.height <= watchlist.contentY + watchlist.height
      }
      within(2000, function() { return rested(body) && inView() })
      check("adding an existing symbol features, selects, and scrolls",
        outOfView && said === "SHOW" && sameSymbols(["NVDA", "AAPL", "MSFT"])
          && service.featuredSymbol === "MSFT" && watchlist.cursorSymbol === "MSFT" && inView(),
        [outOfView, said, service.symbols, service.featuredSymbol, watchlist.cursorSymbol, inView()].join("|"))

      // Accepting a pending preview names it at once. Its row is not a
      // number-key target until it has an answer; a later choice wins.
      mouseMove(body, 1, 1)
      var rangeBefore = service.range
      // The add steps below sort by % change; the order goes back after them.
      var orderBefore = service.order
      service.setRange("1D")
      service.setOrder("pct")
      service.addSymbol("DOWN")
      tryVerify(function() { return !!service.quotes.DOWN && rested(body) }, 3000)
      holdQuote("SLOW", true)
      pickSymbol(body, keys, "SLOW")
      var pendingNamed = service.featuredSymbol === "SLOW" && body.headerText === "Loading SLOW"
      var heldWhileOut = watchlist.displayedSymbols.indexOf("SLOW") < 0
      // ↓ counts only the rows you can see: past the last row it cannot
      // reach the add still out, sorted last, and Enter there cannot feature
      // a symbol with no price.
      keys.forceActiveFocus()
      watchlist.cursorSymbol = watchlist.displayedSymbols[0]
      keyClick(Qt.Key_Return)
      var chosenHero = service.featuredSymbol
      var lastShown = watchlist.displayedSymbols[watchlist.displayedSymbols.length - 1]
      watchlist.cursorSymbol = lastShown
      keyClick(Qt.Key_Down)
      var keyedPending = watchlist.cursorRow !== lastShown
      holdQuote("SLOW", false)
      tryVerify(function() { return !!service.quotes.SLOW && service.arriving.indexOf("SLOW") < 0 }, 5000)
      within(2000, function() { return rested(body) })
      check("an accepted pending add is named, ↓ past the last row cannot reach it, and its price joins at the sorted place",
        pendingNamed && heldWhileOut && chosenHero !== "SLOW" && !keyedPending && !!body.featuredQuote && service.featuredSymbol === chosenHero
          && watchlist.displayedSymbols.indexOf("SLOW") === 3,
        [pendingNamed, heldWhileOut, keyedPending, !!body.featuredQuote, watchlist.cursorSymbol,
          watchlist.displayedSymbols.join(",")].join("|"))

      // A wheel around the arrival keeps its chosen view even when an
      // unrelated quote changes. Without an override the new row is in reach.
      var firstWholeSymbol = function() {
        return watchlist.displayedSymbols.filter(function(symbol, index) { return watchlist.wholeInSight(index, watchlist.contentY) })[0]
      }
      var landWith = function(wheel) {
        removeForGood("SLOW")
        tryVerify(function() { return watchlist.displayedSymbols.indexOf("SLOW") < 0 && rested(body) }, 2000)
        watchlist.contentY = wheel === "before" ? watchlist.rowPitch : 0
        var wheeled = false
        var destination = "SLOW"
        var beforeArrival = function() {
          if (wheel !== "before" || wheeled || !service.quotes.SLOW) return
          wheeled = true
          watchlist.wheelBy(-1)
        }
        service.quotesChanged.connect(beforeArrival)
        pickSymbol(body, keys, "SLOW")
        tryVerify(function() { return !!service.quotes.SLOW && service.arriving.indexOf("SLOW") < 0 }, 5000)
        if (wheel === "during") {
          wheeled = body.landing === "SLOW" && body.landingJoined
          watchlist.wheelBy(1)
          destination = watchlist.displayedSymbols[Math.round(watchlist.wheelTarget() / watchlist.rowPitch)]
          var next = Object.assign({}, service.testFeed.quotes)
          next.DOWN = Object.assign({}, next.DOWN, { price: next.DOWN.price + 0.01 })
          service.testFeed.quotes = next
        }
        within(3000, function() { return rested(body) })
        service.quotesChanged.disconnect(beforeArrival)
        var kept = service.featuredSymbol === "SLOW" && watchlist.displayedSymbols.indexOf("SLOW") === 3
          && (wheel === "" || wheeled) && firstWholeSymbol() === destination
        return kept ? "true" : [service.featuredSymbol, wheeled, firstWholeSymbol(), destination].join("/")
      }
      var landings = [landWith(""), landWith("before"), landWith("during")]
      check("an arrival respects the wheel's chosen row after another quote, and its own row is reachable without a wheel override",
        landings.join(",") === "true,true,true", landings.join(","))
      service.removeSymbol("SLOW")
      service.removeSymbol("DOWN")
      service.setRange(rangeBefore)

      // An add still out when the window closes goes with that visit: its
      // answer, landing while the window is closed or after it reopens and
      // something else is chosen, neither features the symbol nor moves the
      // cursor or the list (one row tall, so a selection would scroll it).
      // The 100 ms after the answer is the late landing's time to do harm.
      var lateAdd = function(reopenFirst) {
        pickSymbol(body, keys, "SLOW")
        app.close()
        if (reopenFirst) {
          app.open("{}")
          service.feature("NVDA")
        }
        watchlist.contentY = 0
        watchlist.cursorSymbol = ""
        var hero = service.featuredSymbol
        tryVerify(function() { return !!service.quotes.SLOW }, 5000)
        wait(100)
        var kept = [service.featuredSymbol === hero, watchlist.contentY === 0, watchlist.cursorSymbol === ""]
        if (!reopenFirst) app.open("{}")
        removeForGood("SLOW")
        tryVerify(function() { return watchlist.displayedSymbols.indexOf("SLOW") < 0 && rested(body) }, 2000)
        return kept.join(",")
      }
      var whileClosed = lateAdd(false)
      var afterReopen = lateAdd(true)
      check("an add still out at a close moves nothing, while closed or after a reopen",
        whileClosed === "true,true,true" && afterReopen === "true,true,true", whileClosed + " / " + afterReopen)

      // An add still out when you switch to a list without it is done
      // there. The charted stock is global; choosing a row in the new
      // list must win over the old list's pending add.
      var heroBeforeSwitch = service.featuredSymbol
      holdQuote("SLOW", true)
      pickSymbol(body, keys, "SLOW")
      service.createList("Elsewhere")
      service.addSymbol(heroBeforeSwitch)
      var switchedHero = service.featuredSymbol
      var switchedHeader = body.headerText
      keys.forceActiveFocus()
      keyClick(Qt.Key_Return)
      holdQuote("SLOW", false)
      watchlist.contentY = 0
      tryVerify(function() { return !!service.quotes.SLOW }, 5000)
      within(2000, function() { return rested(body) })
      check("a list switch keeps the global hero, and a row chosen there wins over the pending add",
        switchedHero === "SLOW" && switchedHeader === "Loading SLOW" + (rangeBefore === "1D" ? "" : " " + rangeBefore)
          && service.listName === "Elsewhere" && service.featuredSymbol === heroBeforeSwitch
          && watchlist.contentY === 0 && body.landing === "",
        switchedHero + "|" + switchedHeader + "|" + service.listName + "|" + service.featuredSymbol + "|" + watchlist.contentY + "|" + body.landing)
      service.deleteList("Elsewhere")
      removeForGood("SLOW")

      // Picking a symbol already in All whose first quote is still out (as at
      // a cold start) features it once that quote lands. To get there, SLOW
      // leaves All while arriving, through the file as another surface would
      // change it, and must leave arriving, or it would be held back when it
      // comes back.
      pickSymbol(body, keys, "SLOW")
      var wasArriving = service.arriving.indexOf("SLOW") >= 0
      var withoutSlow = Object.assign({}, service.dataSettings)
      withoutSlow.symbols = service.library.filter(function(s) { return s !== "SLOW" })
      service.persist(withoutSlow)
      // The fetch the pick started ends before SLOW is added again.
      tryVerify(function() { return service.testFeed.firstRun.concat(service.testFeed.refreshRun).indexOf("SLOW") < 0 }, 5000)
      var withSlow = Object.assign({}, service.dataSettings)
      withSlow.symbols = service.library.concat(["SLOW"])
      service.persist(withSlow)
      var slowWasOut = wasArriving && !service.quotes.SLOW && service.arriving.indexOf("SLOW") < 0
      pickSymbol(body, keys, "SLOW")
      tryVerify(function() { return !!service.quotes.SLOW }, 5000)
      var featuredOnAnswer = within(2000, function() { return service.featuredSymbol === "SLOW" })
      check("picking a symbol in All whose first quote is out features it once the quote lands",
        slowWasOut && featuredOnAnswer, wasArriving + "|" + slowWasOut + "|" + service.featuredSymbol)
      removeForGood("SLOW")

      // A hero chosen while an add is still coming keeps the chart: chosen
      // before the new price lands, or while the list eases to the new row,
      // it is still the hero once the price is in and the list rests, and the
      // new row joins at its place all the same (SLOW ties its neighbours
      // and sorts fourth, out of the one-row view).
      var chooseDuring = function(when) {
        tryVerify(function() { return watchlist.displayedSymbols.indexOf("SLOW") < 0 && rested(body) }, 2000)
        watchlist.contentY = 0
        var target = watchlist.displayedSymbols.filter(function(s) { return s !== service.featuredSymbol })[0]
        var chosen = false
        // The glide to the joined row lasts 160 ms, less than a poll of a
        // loaded machine may take to come round, so the target is chosen as
        // the glide starts. In the one-row view it is out of sight as the
        // list eases, so no key reaches it; it is chosen as Enter would.
        var chooseInGlide = function() {
          if (chosen || !watchlist.settling || body.landing !== "SLOW" || !body.landingJoined) return
          chosen = true
          body.featureSymbol(target)
        }
        holdQuote("SLOW", true)
        pickSymbol(body, keys, "SLOW")
        if (when === "before") {
          chosen = true
          keys.forceActiveFocus()
          watchlist.cursorSymbol = target
          keyClick(Qt.Key_Return)
        } else watchlist.settlingChanged.connect(chooseInGlide)
        holdQuote("SLOW", false)
        tryVerify(function() { return !!service.quotes.SLOW }, 5000)
        within(2000, function() { return rested(body) })
        if (when !== "before") watchlist.settlingChanged.disconnect(chooseInGlide)
        var kept = [chosen, service.featuredSymbol === target, watchlist.displayedSymbols.indexOf("SLOW") === 3].join(",")
        removeForGood("SLOW")
        return kept
      }
      var chosenBefore = chooseDuring("before")
      var chosenInGlide = chooseDuring("joining")
      check("a hero chosen while an add is still coming keeps the chart; the new row still joins at its place",
        chosenBefore === "true,true,true" && chosenInGlide === "true,true,true", chosenBefore + " / " + chosenInGlide)

      // Two adds in a row, the second before the first's price: each row
      // joins at its own place when its own price lands, and the chart goes
      // to the latest add. DOWN is in the list with its price (down 1.56%);
      // SLOW stays out of the list until it lands above it (up 2.61%); FLAT,
      // queued behind SLOW, lands after it at 0%.
      service.addSymbol("DOWN")
      tryVerify(function() { return !!service.quotes.DOWN && watchlist.displayedSymbols.indexOf("SLOW") < 0 && rested(body) }, 3000)
      watchlist.contentY = 0
      holdQuote("SLOW", true)
      pickSymbol(body, keys, "SLOW")
      var waitedAt = watchlist.displayedSymbols.indexOf("SLOW")
      pickSymbol(body, keys, "FLAT")
      holdQuote("SLOW", false)
      tryVerify(function() { return !!service.quotes.SLOW && !!service.quotes.FLAT }, 5000)
      within(3000, function() { return service.arriving.length === 0 && rested(body) })
      check("two adds in a row each join at their own place, and the chart goes to the latest",
        service.featuredSymbol === "FLAT" && waitedAt === -1 && service.arriving.length === 0
          && watchlist.displayedSymbols.indexOf("SLOW") === 3,
        [service.featuredSymbol, waitedAt, service.arriving, watchlist.displayedSymbols.join(",")].join("|"))
      service.removeSymbol("SLOW")
      service.removeSymbol("FLAT")
      service.removeSymbol("DOWN")

      // A manual reorder while an add is out saves every member: the add
      // keeps its place in the list, out of sight until its price lands.
      service.setOrder("manual")
      tryVerify(function() { return rested(body) }, 2000)
      holdQuote("SLOW", true)
      pickSymbol(body, keys, "SLOW")
      keys.forceActiveFocus()
      // A cursor of your own is one in sight.
      watchlist.contentY = 0
      watchlist.cursorSymbol = watchlist.displayedSymbols[0]
      var movedSymbol = watchlist.cursorSymbol
      var membersBefore = service.symbols.slice()
      keyClick(Qt.Key_Down, Qt.ShiftModifier)
      within(1000, function() { return service.symbols.indexOf(movedSymbol) === membersBefore.indexOf(movedSymbol) + 1 })
      var membersAfter = service.symbols.slice()
      check("a manual reorder with an add still out saves every member",
        membersBefore.indexOf("SLOW") >= 0 && watchlist.displayedSymbols.indexOf("SLOW") < 0
          && membersAfter.length === membersBefore.length && membersAfter.indexOf("SLOW") >= 0
          && membersAfter.indexOf(movedSymbol) === membersBefore.indexOf(movedSymbol) + 1,
        membersBefore + " -> " + membersAfter)
      holdQuote("SLOW", false)
      tryVerify(function() { return !!service.quotes.SLOW }, 5000)
      service.removeSymbol("SLOW")
      service.setOrder(orderBefore)

      app.close()
      harness.finish()
    }
  }
}
