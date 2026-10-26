import QtQuick
import QtTest
import Quickshell
import Quickshell.Io
import "plugin" as Stonks

// Adds through the real App and Service: accepted previews, arriving rows,
// chosen charts, list membership, removal and undo, including the immediate
// refresh when put back. The review kit keeps their ink and motion.
// HOME and curl are scratch fixtures.
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

  // The fake curl's calls for a symbol, read through a fresh view: a
  // FileView that has loaded once returns its old text straight after
  // reload().
  function calls(name) {
    var view = Qt.createQmlObject('import Quickshell.Io; FileView { blockLoading: true; printErrors: false }', harness)
    view.path = Quickshell.env("STONKS_FAKE_STATE") + "/" + name + ".calls"
    var n = Number(String(view.text()).trim() || "0")
    view.destroy()
    return n
  }
  Stonks.Service { id: service }
  Stonks.App { id: app; service: service }
  Process { id: quoteFile }

  TestCase {
    name: "WindowAdds"
    when: service.pluginsReady

    // Waits up to ms for fn to hold and returns whether it does, so the
    // check that reads it is the one that fails.
    function within(ms, fn) {
      for (var t = 0; t < ms && !fn(); t += 20) wait(20)
      return fn()
    }

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

    // A stock put back asks for its quote at once, as an add does, not at
    // its next refresh on the schedule, and shows the quote it had until
    // the new one lands; the header says nothing of it: by u, and by
    // search's PUT BACK, clicked. MSFT is answered just before each
    // removal, so its put-back comes well before its next scheduled
    // refresh, and its answer is held back while out. The owner (22
    // October): a stock put back refreshes at once; it kept the price it
    // had until that refresh.
    function putsBack(body, watchlist, keys) {
      service.setRange("1D")
      service.feature("AAPL")
      var quiet = function() { return service.testFeed.firstRun.length + service.testFeed.refreshRun.length === 0 && !("MSFT" in service.testFeed.asked) }
      tryVerify(quiet, 5000)
      var putBack = function(how) {
        var answered = service.entries.MSFT
        service.testFeed.ask(["MSFT"], service.wallSecond())
        tryVerify(function() { return quiet() && service.entries.MSFT !== answered }, 5000)
        watchlist.cursorSymbol = "MSFT"
        keys.forceActiveFocus()
        keyClick(Qt.Key_Delete)
        wait(100)
        var kept = service.lastRemoval ? service.lastRemoval.quote : null
        holdQuote("MSFT", true)
        var before = harness.calls("MSFT")
        var said = [body.headerText]
        var heard = function() { if (said[said.length - 1] !== body.headerText) said.push(body.headerText) }
        body.headerTextChanged.connect(heard)
        how()
        var asked = within(2000, function() { return harness.calls("MSFT") > before })
        var row = watchlist.rowItem("MSFT")
        var meanwhile = service.library.indexOf("MSFT") >= 0 && !!kept && service.quotes.MSFT === kept && !!row
        holdQuote("MSFT", false)
        tryVerify(function() { return service.testFeed.firstRun.length + service.testFeed.refreshRun.length === 0 }, 5000)
        wait(50)
        body.headerTextChanged.disconnect(heard)
        return [asked, meanwhile, harness.calls("MSFT") - before, said.indexOf("Refreshing") < 0].join(",")
      }
      var byU = putBack(function() { keyClick(Qt.Key_Z, Qt.ControlModifier) })
      var byClick = putBack(function() {
        keyClick(Qt.Key_A)
        tryVerify(function() { return body.adding }, 2000)
        wait(100)
        var button = harness.find(findAll(body.search, "searchResult")[0], "searchAdd")
        if (body.search.actionFor(body.search.results[0].symbol) === "PUT BACK")
          mouseClick(button, button.width / 2, button.height / 2)
      })
      harness.check("a stock put back by Ctrl+Z, and by PUT BACK clicked, asks for its quote at once, once, showing the quote it had until the new one lands, and the header says nothing of it",
        byU === "true,true,1,true" && byClick === "true,true,1,true" && !body.adding,
        "Ctrl+Z " + byU + " | PUT BACK " + byClick + " | adding " + body.adding)
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

    function pickSymbol(body, keys, symbol) {
      keys.forceActiveFocus()
      keyClick(Qt.Key_A)
      tryVerify(function() { return body.adding && body.search.active }, 2000)
      keyClick(Qt.Key_A, Qt.ControlModifier)
      var field = harness.find(body.search, "searchField")
      field.forceActiveFocus()
      keyClick(Qt.Key_A, Qt.ControlModifier)
      for (var c = 0; c < symbol.length; c++) keyClick(symbol.charAt(c))
      tryVerify(function() { return body.search.resultsQuery === symbol && body.search.results.length === 1 }, 3000)
      keyClick(Qt.Key_Return)
      tryVerify(function() { return !body.adding }, 2000)
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

      // A result already in All joins a list that lacks it once, and becomes
      // its selected symbol, in both looks. Review keeps the joining poses.
      var joins = function(name, members, look) {
        service.persist({ style: look })
        service.createList(name)
        members.forEach(function(s) { service.setMembership(s, name, true) })
        service.setOrder("symbol")
        wait(100)
        searchShop(body, keys)
        var result = findAll(body.search, "searchResult")[1]
        mouseClick(result, result.width / 4, result.height / 2)
        tryVerify(function() { return watchlist.displayedSymbols.indexOf("SHOP.TO") >= 0 }, 3000)
        var joined = service.symbols.filter(function(symbol) { return symbol === "SHOP.TO" }).length === 1
          && service.featuredSymbol === "SHOP.TO"
        service.switchList("")
        service.deleteList(name)
        wait(50)
        return look + ":" + joined
      }
      var smoothJoin = joins("Mid", ["AAPL", "NVDA", "STRAY"], "smooth")
      var retroJoin = joins("Mid2", ["DOWN", "FLAT", "STRAY"], "retro")
      service.persist({ style: "smooth" })
      harness.check("a result already in All joins the named list once and is selected, smooth and retro",
        smoothJoin === "smooth:true" && retroJoin === "retro:true", smoothJoin + " | " + retroJoin)

      // A list with an accepted member never says it is empty while waiting
      // for that member's quote, from New list… and from a list emptied by x.
      var emptyLine = harness.find(body, "emptyList")
      var arrive = function(open) {
        open()
        tryVerify(function() { return body.adding && service.symbols.length === 0 }, 2000)
        var said = false
        // Read on frames: what a frame shows, not the steps within one turn.
        var watch = function() {
          if (emptyLine.visible && !body.adding) said = true
        }
        var frames = Qt.createQmlObject('import QtQuick; FrameAnimation { running: true }', harness)
        frames.triggered.connect(watch)
        pickSymbol(body, keys, "SLOW")
        wait(50)
        watch()
        tryVerify(function() { return watchlist.displayedSymbols.indexOf("SLOW") >= 0 }, 5000)
        frames.destroy()
        var joined = service.symbols.length === 1 && service.symbols[0] === "SLOW"
        var list = service.listName
        service.switchList("")
        service.deleteList(list)
        service.removeSymbol("SLOW")
        tryVerify(function() { return service.testFeed.firstRun.length + service.testFeed.refreshRun.length === 0 }, 5000)
        return [!said, joined].join(",")
      }
      var fromMenu = arrive(function() {
        keys.forceActiveFocus()
        keyClick(Qt.Key_L)
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
        keyClick(Qt.Key_Delete)
        wait(50)
        keyClick(Qt.Key_A)
        wait(50)
      })
      harness.check("a list whose only member is arriving never says it is empty, and that member joins",
        fromMenu === "true,true" && fromEmptied === "true,true", fromMenu + " | " + fromEmptied)

      // A double-click on a result is one pick: its second click does not
      // feature the row that takes the result's place, for a symbol new to
      // All, which is the hero at once as it arrives (SHOP, whose answer
      // fails), and for one already in it, the keyboard's choice on another
      // result. Found in the transition audit (search 4): the row under the
      // pointer took the hero.
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
        newPick === "SHOP:SHOP" && knownPick === "SHOP.TO:SHOP.TO",
        newPick + " | " + knownPick)
      service.switchList("")
      service.deleteList("Mid3")
      service.removeSymbol("SHOP.TO")
      wait(100)
      // After a removal the footer is the add. A click on it opens search,
      // whose one result before any typing is what went, chosen, with PUT
      // BACK, the hero showing it; a double-click on it puts it back once,
      // in its lists at its place, the hero back as it was, its second
      // click featuring no row under it.
      service.feature("AAPL")
      wait(100)
      var listsBefore = JSON.stringify(service.lists)
      watchlist.cursorSymbol = "NVDA"
      keys.forceActiveFocus()
      keyClick(Qt.Key_Delete)
      wait(50)
      var gone = service.library.indexOf("NVDA") < 0
      var footer = harness.find(body, "footer")
      var footerAt = footer.mapToItem(body, footer.width / 2, footer.height / 2)
      mouseClick(body, footerAt.x, footerAt.y)
      tryVerify(function() { return body.adding }, 2000)
      wait(100)
      var offers = findAll(body.search, "searchResult")
      var offered = body.search.results.map(function(r) { return r.symbol + " " + body.search.actionFor(r.symbol) }).join(",")
        + " chosen " + offers[0].chosen + " hero " + body.previewSymbol
      var putAt = offers[0].mapToItem(body, offers[0].width / 4, offers[0].height / 2)
      mouseDoubleClickSequence(body, putAt.x, putAt.y)
      wait(300)
      harness.check("after a removal, the footer's search offers it back first, chosen, with PUT BACK, and a double-click puts it back once in its lists at its place, the hero as it was",
        gone && offered === "NVDA PUT BACK chosen true hero NVDA" && !body.adding && JSON.stringify(service.lists) === listsBefore
          && service.featuredSymbol === "AAPL" && service.lastRemoval === null,
        [gone, offered, body.adding, JSON.stringify(service.lists), service.featuredSymbol, JSON.stringify(service.lastRemoval)].join(" | "))
      mouseMove(body, 1, 1)
      // The offer is the empty field's answer: a query typed over it leaves
      // it dimmed, and Enter before that query's answer puts nothing back.
      // Found in review: Enter there put the removal back and closed search.
      watchlist.cursorSymbol = "NVDA"
      keys.forceActiveFocus()
      keyClick(Qt.Key_Delete)
      wait(50)
      keyClick(Qt.Key_A)
      tryVerify(function() { return body.adding }, 2000)
      wait(100)
      keyClick(Qt.Key_S)
      keyClick(Qt.Key_H)
      keyClick(Qt.Key_Return)
      wait(50)
      var early = [body.adding, body.search.stale, service.library.indexOf("NVDA") < 0].join(",")
      keyClick(Qt.Key_Escape)
      wait(50)
      keys.forceActiveFocus()
      keyClick(Qt.Key_Z, Qt.ControlModifier)
      wait(100)
      harness.check("Enter on a query typed over the offer, before its answer, puts nothing back",
        early === "true,true,true" && service.library.indexOf("NVDA") >= 0, early)

      // A member still arriving says Show too, and Enter on it features it at
      // once, named as on its way, and its row once its first answer is in,
      // a failed one included. Found in the branch's review: accepted before
      // its first fetch failed, it featured nothing.
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
      within(12000, function() {
        return !!service.entries["SHHI.NE"] && service.entries["SHHI.NE"].status === "failed" && watchlist.cursorRow === "SHHI.NE"
      })
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
      pickSymbol(body, keys, "FLAKY")
      var waiting = [body.landing, service.arriving.indexOf("FLAKY") >= 0].join(",")
      searchShop(body, keys)
      var shownWord = harness.find(findAll(body.search, "searchResult")[0], "searchAdd").children[0].text
      keyClick(Qt.Key_Return)
      wait(300)
      var shownFirst = [shownWord, service.featuredSymbol, body.adding].join(",")
      tryVerify(function() { return watchlist.displayedSymbols.indexOf("FLAKY") >= 0 }, 15000)
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

    // Adds, undo and reopen retain their membership/data in either look.
    // The line's rendered draw-in is already in window-motion.
    function joiningLines(body, watchlist, keys) {
      service.createList("Lines")
      ;["AAPL", "NVDA", "STRAY"].forEach(function(symbol) { service.setMembership(symbol, "Lines", true) })
      service.switchList("Lines")
      service.setOrder("manual")
      ;["smooth", "retro"].forEach(function(look) {
        service.persist({ style: look })
        pickSymbol(body, keys, "SLOW")
        tryVerify(function() { return watchlist.displayedSymbols.indexOf("SLOW") >= 0 }, 5000)
        var addedQuote = JSON.stringify(service.quotes.SLOW)
        keys.forceActiveFocus()
        watchlist.cursorSymbol = "SLOW"
        keyClick(Qt.Key_Delete)
        tryVerify(function() { return watchlist.displayedSymbols.indexOf("SLOW") < 0 }, 2000)
        keyClick(Qt.Key_Z, Qt.ControlModifier)
        tryVerify(function() { return watchlist.displayedSymbols.indexOf("SLOW") >= 0 }, 2000)
        app.close()
        app.open("{}")
        harness.check(look + ": an added and undone row keeps its quote and membership after reopen",
          service.symbols.indexOf("SLOW") >= 0 && JSON.stringify(service.quotes.SLOW) === addedQuote && watchlist.displayedSymbols.indexOf("SLOW") >= 0)
        service.switchList("")
        var all = watchlist.displayedSymbols.slice()
        service.switchList("Lines")
        service.setOrder("symbol")
        harness.check(look + ": switching and sorting retain each list's members",
          all.indexOf("SLOW") >= 0 && watchlist.displayedSymbols.slice().sort().join(",") === "AAPL,NVDA,SLOW,STRAY")
        service.setOrder("manual")
        removeForGood("SLOW")
      })
      service.persist({ style: "smooth" })
      service.switchList("")
      service.deleteList("Lines")
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

      var chapter = Quickshell.env("STONKS_ADD_FLOW")
      if (chapter === "search" || chapter === "restored" || chapter === "putback") {
        sixRows(body, "MSFT", "1Y")
        if (chapter === "search") addsFromSearch(body, watchlist, keys)
        else if (chapter === "restored") joiningLines(body, watchlist, keys)
        else putsBack(body, watchlist, keys)
        app.close()
        harness.finish()
        return
      }

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
      pickSymbol(body, keys, "MSFT")
      // The list eases the row in, then the chart changes.
      wait(300)
      harness.check("adding an existing symbol features, selects, and scrolls",
        outOfView && harness.sameSymbols(["NVDA", "AAPL", "MSFT"])
          && service.featuredSymbol === "MSFT" && watchlist.cursorSymbol === "MSFT"
          && existingRow.y >= watchlist.contentY
          && existingRow.y + existingRow.height <= watchlist.contentY + watchlist.height)

      // Accepting a pending preview names it at once. Its row is not a
      // number-key target until it has an answer; a later choice wins.
      mouseMove(body, 1, 1)
      var rangeBefore = service.range
      // The add steps below sort by % change; the order goes back after them.
      var orderBefore = service.order
      service.setRange("1D")
      service.setOrder("pct")
      service.addSymbol("DOWN")
      tryVerify(function() { return !!service.quotes.DOWN }, 3000)
      wait(50)
      holdQuote("SLOW", true)
      pickSymbol(body, keys, "SLOW")
      wait(20)
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
      wait(200)
      harness.check("an accepted pending add is named, ↓ past the last row cannot reach it, and its price joins at the sorted place",
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
        wait(50)
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
        within(3000, function() { return !watchlist.settling && body.landing === "" })
        service.quotesChanged.disconnect(beforeArrival)
        var kept = service.featuredSymbol === "SLOW" && watchlist.displayedSymbols.indexOf("SLOW") === 3
          && (wheel === "" || wheeled) && firstWholeSymbol() === destination
        return kept ? "true" : [service.featuredSymbol, wheeled, firstWholeSymbol(), destination].join("/")
      }
      var landings = [landWith(""), landWith("before"), landWith("during")]
      harness.check("an arrival respects the wheel's chosen row after another quote, and its own row is reachable without a wheel override",
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
        pickSymbol(body, keys, "SLOW")
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
        removeForGood("SLOW")
        wait(50)
        return kept.join(",")
      }
      var whileClosed = lateAdd(false)
      var afterReopen = lateAdd(true)
      harness.check("an add still out at a close moves nothing, while closed or after a reopen",
        whileClosed === "true,true,true" && afterReopen === "true,true,true", whileClosed + " / " + afterReopen)

      // An add still out when you switch to a list without it is done
      // there. The charted stock is global; choosing a row in the new
      // list must win over the old list's pending add. Found in the review of the untangle: the new list's
      // hero jumped to the old list's add.
      var heroBeforeSwitch = service.featuredSymbol
      holdQuote("SLOW", true)
      pickSymbol(body, keys, "SLOW")
      wait(20)
      service.createList("Elsewhere")
      service.addSymbol(heroBeforeSwitch)
      var switchedHero = service.featuredSymbol
      var switchedHeader = body.headerText
      keys.forceActiveFocus()
      keyClick(Qt.Key_Return)
      holdQuote("SLOW", false)
      wait(50)
      watchlist.contentY = 0
      tryVerify(function() { return !!service.quotes.SLOW }, 5000)
      wait(300)
      harness.check("a list switch keeps the global hero, and a row chosen there wins over the pending add",
        switchedHero === "SLOW" && switchedHeader === "Loading SLOW" + (rangeBefore === "1D" ? "" : " " + rangeBefore)
          && service.listName === "Elsewhere" && service.featuredSymbol === heroBeforeSwitch
          && watchlist.contentY === 0 && body.landing === "",
        switchedHero + "|" + switchedHeader + "|" + service.listName + "|" + service.featuredSymbol + "|" + watchlist.contentY + "|" + body.landing)
      service.deleteList("Elsewhere")
      removeForGood("SLOW")
      wait(50)

      // A symbol that leaves All before its first answer leaves arriving: it
      // is not held back if it is added again. Found in cubic's review of #24.
      // The window offers no row to remove it by; this is the file changing
      // under the service, as another surface or an edit would.
      pickSymbol(body, keys, "SLOW")
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
      pickSymbol(body, keys, "SLOW")
      tryVerify(function() { return !!service.quotes.SLOW }, 5000)
      var featuredOnAnswer = within(2000, function() { return service.featuredSymbol === "SLOW" })
      harness.check("picking a symbol in All whose first quote is out features it once the quote lands",
        slowWasOut && featuredOnAnswer, slowWasOut + "|" + service.featuredSymbol)
      removeForGood("SLOW")
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
        holdQuote("SLOW", true)
        pickSymbol(body, keys, "SLOW")
        if (when === "before") {
          chosen = true
          keys.forceActiveFocus()
          watchlist.cursorSymbol = target
          keyClick(Qt.Key_Return)
        }
        holdQuote("SLOW", false)
        tryVerify(function() { return !!service.quotes.SLOW }, 5000)
        if (when === "joining") {
          chosen = body.landing === "SLOW" && body.landingJoined
          // In the one-row view the target is out of sight as the list
          // eases, so no key reaches it; choose it as Enter would.
          body.featureSymbol(target)
        }
        tryVerify(function() { return !watchlist.settling }, 2000)
        wait(400)
        var kept = [chosen, service.featuredSymbol === target, watchlist.displayedSymbols.indexOf("SLOW") === 3].join(",")
        removeForGood("SLOW")
        wait(50)
        return kept
      }
      var chosenBefore = chooseDuring("before")
      var chosenInGlide = chooseDuring("joining")
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
      holdQuote("SLOW", true)
      pickSymbol(body, keys, "SLOW")
      wait(20)
      var waitedAt = watchlist.displayedSymbols.indexOf("SLOW")
      pickSymbol(body, keys, "FLAT")
      holdQuote("SLOW", false)
      tryVerify(function() { return !!service.quotes.SLOW && !!service.quotes.FLAT }, 5000)
      wait(100)
      tryVerify(function() { return !watchlist.settling }, 2000)
      wait(300)
      harness.check("two adds in a row each join at their own place, and the chart goes to the latest",
        service.featuredSymbol === "FLAT" && waitedAt === -1 && service.arriving.length === 0
          && watchlist.displayedSymbols.indexOf("SLOW") === 3,
        [service.featuredSymbol, waitedAt, service.arriving, watchlist.displayedSymbols.join(",")].join("|"))
      service.removeSymbol("SLOW")
      service.removeSymbol("FLAT")
      service.removeSymbol("DOWN")
      service.setOrder(orderBefore)
      wait(50)

      // A manual reorder while an add is out saves every member: the add
      // keeps its place in the list, out of sight until its price lands.
      service.setOrder("manual")
      wait(50)
      holdQuote("SLOW", true)
      pickSymbol(body, keys, "SLOW")
      wait(20)
      keys.forceActiveFocus()
      // A cursor of your own is one in sight.
      watchlist.contentY = 0
      watchlist.cursorSymbol = watchlist.displayedSymbols[0]
      var movedSymbol = watchlist.cursorSymbol
      var membersBefore = service.symbols.slice()
      keyClick(Qt.Key_Down, Qt.ShiftModifier)
      wait(50)
      var membersAfter = service.symbols.slice()
      harness.check("a manual reorder with an add still out saves every member",
        membersBefore.indexOf("SLOW") >= 0 && watchlist.displayedSymbols.indexOf("SLOW") < 0
          && membersAfter.length === membersBefore.length && membersAfter.indexOf("SLOW") >= 0
          && membersAfter.indexOf(movedSymbol) === membersBefore.indexOf(movedSymbol) + 1,
        membersBefore + " -> " + membersAfter)
      holdQuote("SLOW", false)
      tryVerify(function() { return !!service.quotes.SLOW }, 5000)
      wait(400)
      service.removeSymbol("SLOW")
      service.setOrder(orderBefore)
      wait(50)

      // A listing Yahoo answers with no currency says its exchange alone on
      // the hero's line, and one it names keeps its code: NOCUR answers the
      // FTSE 100's day with none, as Yahoo answered ^STOXX50E. Found in the
      // 1.0.0 review: ^STOXX50E read "ZURICH · USD".
      // On the day, whose chart is in the quote, so the hero turns to it as
      // its price lands.
      service.setRange("1D")
      var hero = harness.find(body, "hero")
      var listingSaid = function(symbol) {
        tryVerify(function() { return !!hero.quote && hero.quote.symbol === symbol }, 5000)
        wait(50)
        return harness.find(hero, "listingMeta").text
      }
      pickSymbol(body, keys, "NOCUR")
      var noneNamed = listingSaid("NOCUR")
      service.feature("AAPL")
      var named = listingSaid("AAPL")
      harness.check("a listing Yahoo names no currency for says its exchange alone, never USD; one it names keeps its code",
        noneNamed === " · FTSE INDEX" && named === " · NASDAQ · USD", noneNamed + " | " + named)
      service.removeSymbol("NOCUR")
      wait(50)

      app.close()
      harness.finish()
    }
  }

  HarnessExit { id: done }
}
