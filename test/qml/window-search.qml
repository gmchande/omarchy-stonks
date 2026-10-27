import QtQuick
import QtTest
import Quickshell
import Quickshell.Io
import "plugin" as Stonks

// Search in the window, through the real App and Service with real Qt keys
// and pointer: results that belong to their query, a search out at a close,
// looking a result up on the hero before adding it, and one preview across
// two surfaces. HOME and curl are scratch fixtures.
Harness {
  id: harness
  marker: "WINDOW SEARCH DONE"

  function same(got, want) {
    return !!got && got.join("|") === want.join("|")
  }

  Stonks.Service { id: service }
  readonly property string fakeState: Quickshell.env("STONKS_FAKE_STATE")
  Process { id: fileProc }
  Stonks.App { id: app; service: service }
  // A second surface on the same service, as a popup beside the window.
  Component { id: otherSurface; Stonks.StonksBody {} }

  Steps {
    name: "WindowSearch"
    when: service.pluginsReady

    // Puts down (on) or takes away the fake curl's file `name` in its state:
    // a `.hold` holds that request back, SEARCH.down fails search.
    function hold(name, on) {
      fileProc.command = on ? ["touch", harness.fakeState + "/" + name] : ["rm", "-f", harness.fakeState + "/" + name]
      fileProc.running = true
      tryVerify(function() { return !fileProc.running }, 2000)
    }

    // Search open with its answer (the saved SHOP results) in the rows' place.
    function searchShop(body, keys) {
      keys.forceActiveFocus()
      keyClick(Qt.Key_A)
      tryVerify(function() { return body.adding }, 2000)
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
      tryVerify(function() { return app.opened }, 2000)
    }

    // Search shows its choice on the hero, unadded, before Enter adds it:
    // the arrows move the choice and the hero follows; a result's quote is
    // asked for only once the choice rests on it; while it is out the chart
    // on show holds under "Loading"; Enter adds the result the hero shows
    // with the quote it has, and the chart stays; Escape puts the featured
    // symbol back; a failed lookup can still be added; a click adds. The fake curl
    // answers SHOP.TO from its saved day and fails SHOP and SHHI.NE.
    function looksUpBeforeAdding(body, watchlist, keys) {
      service.switchList("")
      service.setRange("1D")
      wait(400)
      var hero = service.featuredSymbol
      // Fetches from here on: earlier flows fetched these too.
      var calls = function(symbol, from) { return harness.calls(symbol) - (from || 0) }
      var before = { to: harness.calls("SHOP.TO"), shop: harness.calls("SHOP"), shhi: harness.calls("SHHI.NE") }

      searchShop(body, keys)
      var topHeld = [body.headerText, body.chartSymbol].join(",")
      harness.check("the top result names what is loading while keeping the previous chart's data",
        topHeld === "Loading SHOP," + hero, topHeld)

      // Past SHOP and SHHI.NE before the choice rests: neither is fetched.
      keyClick(Qt.Key_Down)
      keyClick(Qt.Key_Down)
      keyClick(Qt.Key_Up)
      var previewed = within(3000, function() { return body.chartSymbol === "SHOP.TO" && !body.chartLoading })
      wait(100)
      var shown = [previewed, body.featured.priceText, body.search.resultIndex, service.featuredSymbol === hero,
        service.library.indexOf("SHOP.TO") < 0].join(",")
      harness.check("↓ shows the chosen result's price on the hero, unadded, the featured symbol kept",
        shown === "true,194.60,1,true,true", shown)
      var fetched = [calls("SHOP.TO", before.to), calls("SHOP", before.shop), calls("SHHI.NE", before.shhi)].join(",")
      var stats = within(3000, function() { return !!body.yearLine && body.yearLine.facts.length > 0 && body.yearLine.facts[0].value !== "" })
      harness.check("the preview's info lines are its own: its day and its cap",
        stats && !!body.periodLine && body.periodLine.range.lowText + "–" + body.periodLine.range.highText === "192.88–196.46",
        JSON.stringify(body.periodLine) + " / " + JSON.stringify(body.yearLine))
      // An hour on the schedule's clock, and a user's refresh. The fetch
      // must not come, so time passes: a fetch answers in 0.4 s.
      service.now += 3600
      service.askDue()
      service.refresh()
      wait(600)
      harness.check("neither the schedule nor r refreshes a preview", calls("SHOP.TO", before.to) === 1, calls("SHOP.TO", before.to))
      // From a choice that has rested, arrowing on past results asks for
      // none of them either: each new choice waits its own rest, which the
      // 400 ms must let pass.
      var further = { shhi: harness.calls("SHHI.NE"), f: harness.calls("307.F") }
      keyClick(Qt.Key_Down)
      keyClick(Qt.Key_Down)
      keyClick(Qt.Key_Up)
      keyClick(Qt.Key_Up)
      wait(400)
      var passed = [calls("SHHI.NE", further.shhi), calls("307.F", further.f), body.chartSymbol].join(",")
      harness.check("only the result the choice rests on is fetched", fetched === "1,0,0" && passed === "0,0,SHOP.TO",
        fetched + " / " + passed)

      // Enter adds what the hero shows, with the quote already fetched.
      // The result returned to above is asked for again once it rests.
      tryVerify(function() { return calls("SHOP.TO", before.to) === 2 && !!service.previewView.chart }, 3000)
      var beforeEnter = harness.calls("SHOP.TO")
      keyClick(Qt.Key_Return)
      tryVerify(function() { return watchlist.displayedSymbols.indexOf("SHOP.TO") >= 0 }, 2000)
      var added = [service.featuredSymbol, body.adding, body.chartSymbol, calls("SHOP.TO", beforeEnter)].join(",")
      harness.check("Enter adds the result on the hero with its quote: featured, the chart kept, nothing fetched again",
        added === "SHOP.TO,false,SHOP.TO,0", added)
      service.removeSymbol("SHOP.TO")
      service.feature(hero)
      tryVerify(function() { return body.chartSymbol === hero }, 3000)

      // Escape puts the featured symbol back and adds nothing.
      searchShop(body, keys)
      keyClick(Qt.Key_Down)
      tryVerify(function() { return body.chartSymbol === "SHOP.TO" && !body.chartLoading }, 3000)
      keyClick(Qt.Key_Escape)
      within(2000, function() { return !body.adding && body.chartSymbol === hero })
      var back = [body.adding, body.chartSymbol, service.library.indexOf("SHOP.TO") < 0].join(",")
      harness.check("Escape puts the featured symbol back on the hero and adds nothing",
        back === "false," + hero + ",true", back)

      // A lookup that fails says so on the hero; Enter adds it anyway, and
      // the hero goes back to what it showed. Its failed fetch was the add's
      // first: the add is done there, its row joining at once saying so,
      // with nothing fetched again; an answer then would have taken the hero.
      searchShop(body, keys)
      var failed = within(9000, function() {
        return body.chartSymbol === "SHOP" && body.featuredFreshness.state === "failed"
      })
      var shopCalls = harness.calls("SHOP")
      keyClick(Qt.Key_Return)
      within(3000, function() { return service.library.indexOf("SHOP") >= 0 && body.chartSymbol === hero })
      var failedAdd = [service.library.indexOf("SHOP") >= 0, service.featuredSymbol === hero, body.chartSymbol].join(",")
      var failedRow = [service.arriving.indexOf("SHOP") < 0, watchlist.displayedSymbols.indexOf("SHOP") >= 0,
        service.entries.SHOP ? service.entries.SHOP.status : "none", calls("SHOP", shopCalls)].join(",")
      harness.check("an add of a failed lookup is done there: its row joins saying so, nothing fetched again",
        failed && failedAdd === "true,true," + hero && failedRow === "true,true,failed,0",
        [failed, failedAdd, failedRow].join(" / "))
      service.removeSymbol("SHOP")

      // The pointer: a click on a result takes it as Enter does, chosen and
      // then added, the hero landing on it, though the keyboard's choice was
      // the top result.
      searchShop(body, keys)
      var second = findAll(body.search, "searchResult")[1]
      mouseClick(second, second.width / 4, second.height / 2)
      within(3000, function() { return service.featuredSymbol === "SHOP.TO" })
      var byPointer = [service.library.indexOf("SHOP.TO") >= 0, service.featuredSymbol, body.adding].join(",")
      harness.check("a click on a result adds it, as Enter does, and the hero lands on it", byPointer === "true,SHOP.TO,false", byPointer)
      service.removeSymbol("SHOP.TO")
      service.feature(hero)
      tryVerify(function() { return body.chartSymbol === hero }, 3000)
      // CANCEL does what Escape does: the hero goes back, nothing added. The
      // pause keeps the click from pairing with the keys' into a double-click.
      searchShop(body, keys)
      wait(Qt.styleHints.mouseDoubleClickInterval + 50)
      var cancel = harness.find(body.search, "searchCancel")
      mouseClick(cancel, cancel.width / 2, cancel.height / 2)
      within(2000, function() { return !body.adding && body.chartSymbol === hero })
      var cancelled = [body.adding, body.chartSymbol, service.library.indexOf("SHOP") < 0].join(",")
      harness.check("CANCEL closes search as Escape does, the hero back and nothing added",
        cancelled === "false," + hero + ",true", cancelled)
      tryVerify(function() { return service.testFeed.firstRun.length + service.testFeed.refreshRun.length === 0 }, 5000)
    }

    // A second surface beside the window, on the same service, as the
    // popup is: its search taking the preview closes the window's search,
    // so neither hero shows one result while Enter would add another; the
    // window's hero, back on the featured symbol, gets its range's history
    // while the other previews; and a surface that goes while previewing
    // takes its preview with it.
    function twoSurfacesPreview(body, keys) {
      service.feature("MSFT")
      service.setRange("1Y")
      wait(400)
      var other = otherSurface.createObject(null, { service: service, width: 480, height: 760 })
      // The other surface previews, and history for MSFT's year is gone.
      other.surfaceOpen = true
      other.startAdding()
      wait(50)
      harness.find(other.search, "searchField").text = "SH"
      tryVerify(function() { return other.search.results.length > 1 }, 3000)
      other.search.showResult(1)
      tryVerify(function() { return other.chartSymbol === "SHOP.TO" && !other.chartLoading }, 5000)
      // r on the window, while the other previews, fetches every chart the
      // heroes show fresh: the window's own, here failed (the fake curl
      // answers no year for FLAT) and saying "unavailable", with R RETRY,
      // and the preview's.
      service.addSymbol("FLAT")
      tryVerify(function() { return !!service.quotes.FLAT }, 5000)
      service.feature("FLAT")
      tryVerify(function() {
        return body.headerText.indexOf("unavailable") >= 0 && !!service.testHistoryFeed.entries["SHOP.TO|1Y"]
      }, 12000)
      var histories = { flat: harness.calls("FLAT.history"), to: harness.calls("SHOP.TO.history") }
      keys.forceActiveFocus()
      keyClick(Qt.Key_R)
      var refreshed = within(12000, function() {
        return harness.calls("FLAT.history") > histories.flat && harness.calls("SHOP.TO.history") > histories.to
      })
      harness.check("r fetches every chart the heroes show fresh, the window's failed year and the preview's",
        refreshed, (harness.calls("FLAT.history") - histories.flat) + "," + (harness.calls("SHOP.TO.history") - histories.to))
      service.feature("MSFT")
      wait(100)
      service.testHistoryFeed.entries = ({})
      // The window opens search and takes the preview.
      searchShop(body, keys)
      keyClick(Qt.Key_Down)
      tryVerify(function() { return body.chartSymbol === "SHOP.TO" && !body.chartLoading }, 5000)
      var taken = [other.adding, other.previewSymbol, service.previewSurface === app.testBody].join(",")
      harness.check("a search that takes the preview closes the other surface's search", taken === "false,,true", taken)
      var otherChart = within(4000, function() { return other.chartSymbol === "MSFT" && !other.chartLoading && other.historyShown })
      harness.check("the other surface's hero, back on the featured symbol, gets its range's history meanwhile",
        otherChart, other.chartSymbol + "|" + other.headerText)
      // The window goes while it previews: its preview goes with it.
      app.close()
      wait(50)
      var closed = service.previewSymbol + "," + service.previewSurface
      other.startAdding()
      wait(50)
      harness.find(other.search, "searchField").text = "SH"
      tryVerify(function() { return other.search.results.length > 1 }, 3000)
      other.search.showResult(1)
      tryVerify(function() { return other.chartSymbol === "SHOP.TO" }, 3000)
      other.destroy()
      wait(50)
      var gone = service.previewSymbol + "," + service.previewSurface
      harness.check("a surface closing or going while it previews ends its preview", closed === ",null" && gone === ",null",
        closed + " / " + gone)
      // The window's search, kept through its close, opens again with it;
      // the next flow starts with search closed.
      app.open("{}")
      tryVerify(function() { return body.adding }, 2000)
      body.cancelAdding()
      service.setRange("1D")
      wait(400)
    }

    // A search's preview, made while the hero's first quote is still out,
    // leaves the hero its cap and P/E: they are asked for once its quote is
    // in, not taken by the preview.
    function previewKeepsHeroFigures(body, keys) {
      var hero = service.featuredSymbol
      hold("SLID.quote.hold", true)
      service.persist({ symbols: service.library.concat(["SLID"]), featured: "SLID" })
      tryVerify(function() { return service.featuredSymbol === "SLID" && !service.quotes.SLID }, 3000)
      var before = harness.calls("SLID.fundamentals")
      searchShop(body, keys)
      keyClick(Qt.Key_Down)
      var previewed = within(6000, function() {
        return service.previewSymbol !== "" && !!service.previewEntries[service.previewSymbol]
      })
      hold("SLID.quote.hold", false)
      tryVerify(function() { return !!service.quotes.SLID }, 8000)
      var asked = within(3000, function() { return harness.calls("SLID.fundamentals") > before })
      keyClick(Qt.Key_Escape)
      harness.check("a preview made before the hero's first quote leaves the hero its cap and P/E, asked for as its quote lands",
        previewed && asked, "previewed " + previewed + ", SLID's asked " + (harness.calls("SLID.fundamentals") - before))
      service.removeSymbol("SLID")
      service.feature(hero)
      service.lastRemoval = null
      wait(300)
    }

    // The other way: a preview made while its own quote is out keeps its ask
    // for its cap and P/E through the stock's, which a surface makes as it
    // opens or refreshes, and the service each minute.
    function previewKeepsItsFigures(body, keys) {
      // SHOP.TO as if never seen: no quote held for it, no figures.
      var forget = function(feed, key) {
        var next = Object.assign({}, feed[key])
        delete next["SHOP.TO"]
        feed[key] = next
      }
      forget(service.testPreviewFeed, "quotes")
      forget(service.testPreviewFeed, "entries")
      forget(service.testFundamentalsFeed, "entries")
      hold("SHOP.TO.quote.hold", true)
      var before = harness.calls("SHOP.TO.fundamentals")
      searchShop(body, keys)
      keyClick(Qt.Key_Down)
      var waiting = within(6000, function() {
        return service.previewSymbol === "SHOP.TO" && service.previewShown && !service.testPreviewFeed.quotes["SHOP.TO"]
      })
      // The stock's own ask, its quote in, as a refresh makes it.
      app.requestFundamentals()
      hold("SHOP.TO.quote.hold", false)
      tryVerify(function() { return !!service.testPreviewFeed.quotes["SHOP.TO"] }, 8000)
      var asked = within(3000, function() { return harness.calls("SHOP.TO.fundamentals") > before })
      keyClick(Qt.Key_Escape)
      body.resetInteraction()
      harness.check("a preview made before its own quote keeps its ask for its cap and P/E through the stock's, asked for as its quote lands",
        waiting && asked, "waiting " + waiting + ", SHOP.TO's asked " + (harness.calls("SHOP.TO.fundamentals") - before))
      wait(300)
    }

    // An add from search on a range, before the result's first answer,
    // takes over the history fetch its preview has out instead of asking
    // again: SHOP.TO's day and year held back, Enter on it, the add the
    // hero at once, then its day let through, and its row lands while the
    // year is still out, asked for once, though the hero before it has lost
    // its own year meanwhile. And the fetch it takes over is still the
    // add's own: let through before the row lands, it fails, is tried again
    // as any is, and keeps its failure.
    function addTakesOverHistory(body, keys) {
      var forget = function(key) {
        var entries = Object.assign({}, service.testHistoryFeed.entries)
        delete entries[key]
        service.testHistoryFeed.entries = entries
      }
      // Enter on SHOP.TO with its day and year out and held; the hero's own
      // year forgotten first when `heroYearGone`.
      var addHeld = function(heroYearGone) {
        service.feature("MSFT")
        service.setRange("1Y")
        tryVerify(function() { return body.chartSymbol === "MSFT" && !body.chartLoading && !service.testHistoryFeed.busy }, 8000)
        // Two adds in seconds, each asking its day, year, cap and P/E twice
        // over, after every flow before: no user's minute. The budget is
        // topped up so none of it is held back.
        service.testYahooGate.tokens = service.testYahooGate.capacity
        // No removal on offer, as after the next change to the lists: search
        // opens with no result to put back, and Enter adds.
        service.lastRemoval = null
        hold("SHOP.TO.quote.hold", true)
        hold("SHOP.TO.history.hold", true)
        // An earlier step's failed year for it goes: this add is its first.
        forget("SHOP.TO|1Y")
        var from = harness.calls("SHOP.TO.history")
        searchShop(body, keys)
        keyClick(Qt.Key_Down)
        tryVerify(function() { return harness.calls("SHOP.TO.history") === from + 1 }, 3000)
        if (heroYearGone) forget("MSFT|1Y")
        keyClick(Qt.Key_Return)
        wait(50)
        return { from: from, arriving: service.arriving.indexOf("SHOP.TO") >= 0 }
      }
      var done = function() {
        hold("SHOP.TO.quote.hold", false)
        hold("SHOP.TO.history.hold", false)
        tryVerify(function() { return service.featuredSymbol === "SHOP.TO" && !service.testHistoryFeed.busy }, 12000)
        service.removeSymbol("SHOP.TO")
        service.feature("MSFT")
        wait(300)
      }

      // The add is the hero at once: its row has joined once its day is in
      // and it has left arriving, which is when a second ask would come.
      var joined = function() {
        return !!service.quotes["SHOP.TO"] && service.arriving.indexOf("SHOP.TO") < 0
          && body.watchlist.displayedSymbols.indexOf("SHOP.TO") >= 0
      }

      var first = addHeld(true)
      hold("SHOP.TO.quote.hold", false)
      tryVerify(joined, 8000)
      wait(300)
      var taken = [first.arriving, body.chartLoading, harness.calls("SHOP.TO.history") - first.from].join(",")
      done()
      harness.check("an add from search on a range, before its first answer, takes over its preview's history fetch, asked for once, though the hero it leaves has lost its own",
        taken === "true,true,1", taken)

      var second = addHeld(false)
      hold("SHOP.TO.history.hold", false)
      var failedOwn = within(8000, function() {
        var entry = service.histories["SHOP.TO|1Y"]
        return !!entry && entry.status === "failed"
      })
      var kept = [second.arriving, failedOwn, harness.calls("SHOP.TO.history") - second.from].join(",")
      done()
      harness.check("the fetch an add takes over is still its own: failing before the row lands, it is tried again and keeps its failure",
        kept === "true,true,2", kept)

      // An add on its way leaves the next preview its own year: asked for
      // while the add's is still out.
      var release = function() {
        hold("SHOP.TO.quote.hold", false)
        hold("SHOP.TO.history.hold", false)
        tryVerify(function() { return service.arriving.length === 0 && !service.testHistoryFeed.busy }, 12000)
        service.removeSymbol("SHOP.TO")
        service.feature("MSFT")
        wait(300)
      }
      addHeld(false)
      var otherYear = harness.calls("307.F.history")
      searchShop(body, keys)
      keyClick(Qt.Key_Down)
      keyClick(Qt.Key_Down)
      keyClick(Qt.Key_Down)
      var othersOwn = within(3000, function() { return harness.calls("307.F.history") > otherYear })
      keyClick(Qt.Key_Escape)
      release()
      harness.check("an add on its way leaves the next preview its own year, asked for while the add's is out",
        othersOwn, othersOwn)

      // Another surface open beside the window, as the popup is, closes
      // while the add is out, and the added row's year is still asked for
      // once.
      var beside = otherSurface.createObject(null, { service: service, width: 480, height: 760 })
      beside.surfaceOpen = true
      wait(100)
      var besideAdd = addHeld(false)
      beside.surfaceOpen = false
      wait(50)
      hold("SHOP.TO.quote.hold", false)
      tryVerify(joined, 8000)
      wait(300)
      var besideAsked = harness.calls("SHOP.TO.history") - besideAdd.from
      beside.destroy()
      release()
      harness.check("another surface closing leaves the add its preview's fetch: asked for once",
        besideAdd.arriving && besideAsked === 1, besideAdd.arriving + "," + besideAsked)

      // Two adds on their way, SHOP and then SHHI.NE, both failing for good:
      // the hero goes back to the one before both, not to the first add,
      // which has nothing to show.
      service.feature("MSFT")
      tryVerify(function() { return body.chartSymbol === "MSFT" && !body.chartLoading }, 8000)
      searchShop(body, keys)
      tryVerify(function() { return body.previewSymbol === "SHOP" }, 2000)
      keyClick(Qt.Key_Return)
      tryVerify(function() { return service.featuredSymbol === "SHOP" && !body.adding }, 2000)
      searchShop(body, keys)
      keyClick(Qt.Key_Down)
      keyClick(Qt.Key_Down)
      tryVerify(function() { return body.previewSymbol === "SHHI.NE" }, 2000)
      keyClick(Qt.Key_Return)
      var tookBoth = within(2000, function() { return service.featuredSymbol === "SHHI.NE" })
      var settled = within(20000, function() { return service.arriving.length === 0 })
      wait(100)
      var handedBack = service.featuredSymbol
      service.removeSymbol("SHOP")
      service.removeSymbol("SHHI.NE")
      service.feature("MSFT")
      wait(300)
      harness.check("two adds on their way, both failing, hand the hero back to the one before both",
        tookBoth && settled && handedBack === "MSFT", [tookBoth, settled, handedBack].join(","))
      service.setRange("1D")
      wait(300)
    }

    // With search open and text typed, the Stonks keys that are also edit
    // keys or letters go to the field: Ctrl+C, Ctrl+Z, Delete, Backspace,
    // l, m, s and o remove no row, undo nothing, open no list menu, and
    // leave the sound, the look and the order as they were.
    function fieldOwnsKeys(body, watchlist, keys) {
      service.switchList("")
      wait(50)
      watchlist.cursorSymbol = watchlist.displayedSymbols[watchlist.displayedSymbols.length - 1]
      keys.forceActiveFocus()
      keyClick(Qt.Key_Delete)
      wait(50)
      if (body.rowMenu !== null) keyClick(Qt.Key_Return)
      wait(50)
      var removed = service.lastRemoval ? service.lastRemoval.symbol : ""
      var before = [service.library.join(","), service.soundsOn, service.retro, service.order, service.reversed].join("|")
      var noteBefore = body.note
      keys.forceActiveFocus()
      keyClick(Qt.Key_A)
      tryVerify(function() { return body.adding && body.search.active }, 2000)
      var field = harness.find(body.search, "searchField")
      keyClick("S")
      keyClick("H")
      keyClick(Qt.Key_C, Qt.ControlModifier)
      keyClick(Qt.Key_Z, Qt.ControlModifier)
      keyClick(Qt.Key_Delete)
      keyClick(Qt.Key_Backspace)
      ;[Qt.Key_L, Qt.Key_M, Qt.Key_S, Qt.Key_O].forEach(function(k) { keyClick(k) })
      wait(100)
      var typed = String(field.text)
      var after = [service.library.join(","), service.soundsOn, service.retro, service.order, service.reversed].join("|")
      var stayed = [body.adding, !body.listMenuOpen, body.rowMenu === null, !body.cameraLit, body.note === noteBefore,
        !!service.lastRemoval && service.lastRemoval.symbol === removed].join(",")
      keyClick(Qt.Key_Escape)
      wait(50)
      keys.forceActiveFocus()
      keyClick(Qt.Key_Z, Qt.ControlModifier)
      wait(100)
      harness.check("in search, Ctrl+C, Ctrl+Z, Delete, Backspace and l m s o edit the field and act as no Stonks key",
        removed !== "" && after === before && stayed === "true,true,true,true,true,true" && /lmso$/i.test(typed),
        [removed, typed, stayed, before, after].join(" | "))
    }

    // A held answer makes the waiting state observable without prescribing
    // its presentation delay. Editing names the current query; an old result
    // cannot be accepted for that query, and the Enter is kept for it.
    // Returns what #1's and the early Enter's checks read: `held`, an Enter
    // on real results of an earlier query while the current one is out adds
    // nothing; `kept`, that Enter takes the held query's top result once its
    // answer lands.
    function firstSearchSaysSo(body, keys) {
      var message = harness.find(body.search, "searchMessage")
      keys.forceActiveFocus()
      keyClick(Qt.Key_A)
      tryVerify(function() { return body.adding && body.search.active }, 2000)
      hold("SEARCH.hold", true)
      keyClick("S")
      var firstNamed = within(3000, function() { return message.visible && message.text === "Searching for “S”…" })
      var firstSaid = message.text
      keyClick("H")
      var editedNamed = within(3000, function() { return message.visible && message.text === "Searching for “SH”…" })
      harness.check("waiting names the first query", firstNamed && editedNamed, firstSaid + " / " + message.text)
      hold("SEARCH.hold", false)
      tryVerify(function() { return body.search.resultsQuery === "SH" && body.search.results.length > 0 }, 4000)
      // A later query retains real results, so a broken stale-result guard
      // would have an actual unadded symbol to accept.
      hold("SEARCH.hold", true)
      var askedBefore = harness.calls("SEARCH.asked")
      keyClick("X")
      var previousResults = body.search.results.length > 0 && body.search.resultsQuery === "SH"
        && service.library.indexOf(body.search.results[0].symbol) < 0
      var lookupOut = within(3000, function() { return body.search.activeQuery === "SHX" && harness.calls("SEARCH.asked") === askedBefore + 1 })
      var members = service.library.join(",")
      var top = body.search.results.length > 0 ? body.search.results[0].symbol : ""
      keyClick(Qt.Key_Return)
      var stayed = body.adding && body.search.stale && service.library.join(",") === members
      hold("SEARCH.hold", false)
      var held = { ok: lookupOut && previousResults && stayed, detail: [lookupOut, previousResults, stayed].join(",") }
      // The Enter is kept for SHX, and SHX's answer decides: its top result
      // is added once it lands.
      var taken = held.ok && within(4000, function() { return service.library.indexOf(top) >= 0 })
      var kept = { ok: taken && body.search.resultsQuery === "SHX" && !message.visible,
        detail: [taken, body.search.resultsQuery, top].join(",") }
      body.resetInteraction()
      // Back as it was: the add gone, no removal on offer, so the flows after
      // open search empty, and the budget its add spent topped up, as a
      // minute would.
      if (taken) service.removeSymbol(top)
      service.lastRemoval = null
      service.testYahooGate.tokens = service.testYahooGate.capacity
      return { held: held, kept: kept }
    }

    // An Enter pressed before the field's query has its answer is kept for
    // that query, and its first answer decides, by the rules Enter keeps
    // (a typed symbol that exists adds itself); more typing, Escape, or a
    // failed lookup drops it. A changed query stops the lookup still out
    // for the old one rather than waiting behind it. `kept` is
    // firstSearchSaysSo's: an Enter on stale results kept for the held query.
    function earlyEnter(body, keys, kept) {
      var type = function(word) { word.split("").forEach(function(k) { keyClick(k) }) }
      var open = function() {
        keys.forceActiveFocus()
        keyClick(Qt.Key_A)
        tryVerify(function() { return body.adding && body.search.active }, 2000)
      }
      // Typed and Enter at once, the answer held: nothing until it lands,
      // then the typed symbol, one not followed, is added. An add after
      // every flow before: the budget topped up, as addHeld's, and no
      // removal on offer.
      service.testYahooGate.tokens = service.testYahooGate.capacity
      service.lastRemoval = null
      var library = service.library.slice()
      var unfollowed = library.indexOf("SLOW") < 0
      open()
      hold("SEARCH.hold", true)
      var askedSlow = harness.calls("SEARCH.asked")
      type("SLOW")
      keyClick(Qt.Key_Return)
      within(3000, function() { return harness.calls("SEARCH.asked") > askedSlow })
      var waited = [unfollowed, harness.same(service.library, library), body.adding].join(",")
      hold("SEARCH.hold", false)
      var added = within(4000, function() { return service.library.indexOf("SLOW") >= 0 })
      body.resetInteraction()
      if (added) service.removeSymbol("SLOW")
      service.lastRemoval = null
      service.testYahooGate.tokens = service.testYahooGate.capacity
      // A changed query stops the lookup out for the old one: SHX goes out
      // while SH's is still held, and only SHX is answered.
      open()
      hold("SEARCH.hold", true)
      var askedBefore = harness.calls("SEARCH.asked")
      var answeredBefore = harness.calls("SEARCH.answered")
      type("SH")
      var firstOut = within(3000, function() { return body.search.activeQuery === "SH" && harness.calls("SEARCH.asked") === askedBefore + 1 })
      keyClick("X")
      var secondOut = within(3000, function() { return body.search.activeQuery === "SHX" && harness.calls("SEARCH.asked") === askedBefore + 2 })
      hold("SEARCH.hold", false)
      tryVerify(function() { return body.search.resultsQuery === "SHX" }, 4000)
      // Time for SH's answer to land too, had its lookup run on.
      wait(600)
      var changed = [firstOut, secondOut, harness.calls("SEARCH.answered") - answeredBefore].join(",")
      body.resetInteraction()
      // An Enter, then more typing: dropped. ON and Enter, then E: ONE's
      // answer lands and nothing is added.
      library = service.library.slice()
      open()
      hold("SEARCH.hold", true)
      type("ON")
      keyClick(Qt.Key_Return)
      keyClick("E")
      hold("SEARCH.hold", false)
      tryVerify(function() { return body.search.resultsQuery === "ONE" }, 4000)
      // Time for a kept Enter to act on the landed answer.
      wait(300)
      var edited = [harness.same(service.library, library), body.adding, body.search.results.length].join(",")
      body.resetInteraction()
      // An Enter, then a failed lookup: dropped, not asked again.
      open()
      hold("SEARCH.hold", true)
      askedBefore = harness.calls("SEARCH.asked")
      type("OOPS")
      keyClick(Qt.Key_Return)
      hold("SEARCH.hold", false)
      tryVerify(function() { return body.search.answer === "failed" }, 4000)
      // Time for a second ask, had the Enter outlived the failure.
      wait(600)
      var failed = [harness.same(service.library, library), body.adding, harness.calls("SEARCH.asked") - askedBefore].join(",")
      body.resetInteraction()
      harness.check("an Enter before the answer is kept for its query and the answer adds the typed symbol; a changed query stops the old lookup; more typing or a failed lookup drops the Enter",
        kept.ok && waited === "true,true,true" && added && changed === "true,true,1" && edited === "true,true,1" && failed === "true,true,1",
        [kept.detail, waited, added, changed, edited, failed].join(" ; "))
    }

    // A failed lookup is asked again, the same query through the same
    // request and gate as typing it: by Enter, saying it is searching as a
    // first query does, and by a click on RETRY; while Yahoo's gate pauses
    // Stonks for a refusal, a retry fails at once and asks nothing, and
    // while it pauses for no answer, as after the network went, a retry
    // goes at once. SH fails while the fake curl's search is down, then
    // answers. After an edit back to the failed query, a retry still asks
    // it once, before the typing pause ends and once the edit's own lookup
    // is out.
    function failedSearchRetries(body, keys) {
      var message = harness.find(body.search, "searchMessage")
      // Read through guards, so a search without RETRY fails the check
      // rather than throwing.
      var retry = harness.find(body.search, "searchRetry")
      var retryShown = function() { return !!retry && retry.visible }
      var clickRetry = function() { if (retry) mouseClick(retry, retry.width / 2, retry.height / 2) }
      var library = service.library.slice()
      hold("SEARCH.down", true)
      keys.forceActiveFocus()
      keyClick(Qt.Key_A)
      tryVerify(function() { return body.adding }, 2000)
      keyClick("S")
      keyClick("H")
      tryVerify(function() { return body.search.answer === "failed" && body.search.resultsQuery === "SH" }, 3000)
      var offered = [message.text, retryShown()].join(",")
      // An edit and its undo, then Enter before the typing pause ends,
      // Yahoo's search still down: asked once more, the line saying so,
      // frame by frame, until it fails again, and not asked again after.
      keyClick("X")
      keyClick(Qt.Key_Backspace)
      var askedBefore = harness.calls("SEARCH.asked")
      var seen = []
      var watch = function() {
        var said = message.visible ? message.text : "-"
        if (seen[seen.length - 1] !== said) seen.push(said)
      }
      var frames = Qt.createQmlObject('import QtQuick; FrameAnimation { running: true }', harness)
      frames.triggered.connect(watch)
      watch()
      keyClick(Qt.Key_Return)
      within(3000, function() { return seen.length > 1 && body.search.answer === "failed" })
      // Time for a second ask to show (search answers in 0.4 s).
      wait(600)
      frames.destroy()
      var byEnter = [seen.join(" / "), harness.calls("SEARCH.asked") - askedBefore, body.adding].join(",")
      // The same edit, then RETRY once the edit's own lookup is out: that
      // lookup is the retry.
      keyClick("X")
      keyClick(Qt.Key_Backspace)
      askedBefore = harness.calls("SEARCH.asked")
      var editOut = within(2000, function() { return harness.calls("SEARCH.asked") > askedBefore })
      clickRetry()
      within(3000, function() { return body.search.answer === "failed" })
      wait(600)
      var joined = [editOut, harness.calls("SEARCH.asked") - askedBefore, body.search.answer].join(",")
      // RETRY, while the gate pauses Stonks: no request, the failure stays.
      var gate = service.testYahooGate
      gate.begin("refused", 60)
      askedBefore = harness.calls("SEARCH.asked")
      var answeredBefore = harness.calls("SEARCH.answered")
      clickRetry()
      // Time for a request the gate should have held.
      wait(600)
      var paused = [harness.calls("SEARCH.asked") - askedBefore, harness.calls("SEARCH.answered") - answeredBefore,
        body.search.answer, retryShown()].join(",")
      // RETRY, Yahoo's search back while the gate still pauses for no
      // answer: the lookup goes at once, its answer lands, nothing added.
      gate.begin("none", 60)
      hold("SEARCH.down", false)
      clickRetry()
      within(3000, function() { return body.search.results.length > 0 })
      var byClick = [body.search.resultsQuery, body.search.results.length > 0, harness.calls("SEARCH.answered") - answeredBefore,
        retryShown(), body.adding, harness.same(service.library, library)].join(",")
      body.resetInteraction()
      harness.check("a failed lookup offers RETRY; Enter and a click on it ask the same query again, once, through Yahoo's gate, held by a refusal and not by a pause for no answer, and adding nothing",
        offered === "Search didn’t answer,true"
          && byEnter === "Search didn’t answer / - / Searching for “SH”… / Search didn’t answer,1,true"
          && joined === "true,1,failed" && paused === "0,0,failed,true" && byClick === "SH,true,1,false,true,true",
        [offered, byEnter, joined, paused, byClick].join(" ; "))
    }

    function test_flows() {
      tryVerify(function() {
        return service.quotes.AAPL && service.quotes.MSFT && service.quotes.NVDA
          && service.testFeed.firstRun.length + service.testFeed.refreshRun.length === 0
      }, 10000)

      app.open("{}")
      tryVerify(function() { return app.opened }, 2000)
      var body = app.testBody
      var watchlist = body.watchlist
      var keys = app.testKeyCatcher

      // These flows start from three rows in this order, AAPL featured on its
      // year.
      service.setManualOrder(["NVDA", "AAPL", "MSFT"])
      service.feature("AAPL")
      service.setRange("1Y")
      wait(300)

      // Results belong to their query. Search SH and let its answer land,
      // replace the field with NVDA, and act before NVDA's answer (the fake
      // curl answers 0.4 s after the 250 ms debounce): neither Enter nor a
      // click where SHOP was adds anything.
      var beforeSearch = service.dataSettings
      var beforeFeatured = service.featuredSymbol
      var searchFor = function(first, then) {
        keys.forceActiveFocus()
        keyClick(Qt.Key_A)
        tryVerify(function() { return body.adding }, 2000)
        for (var c = 0; c < first.length; c++) keyClick(first[c])
        tryVerify(function() { return body.search.resultsQuery === first && body.search.results.length > 0 }, 3000)
        var top = harness.find(body.search, "searchResult")
        var at = top.mapToItem(body, top.width / 2, top.height / 2)
        keyClick(Qt.Key_A, Qt.ControlModifier)
        for (c = 0; c < then.length; c++) keyClick(then[c])
        return at
      }
      searchFor("SH", "NVDA")
      keyClick(Qt.Key_Return)
      wait(50)
      var early = harness.same(service.library, beforeSearch.symbols) && service.featuredSymbol === beforeFeatured
        && body.adding && body.search.searchText === "NVDA"
      var earlyDetail = service.library + "|" + service.featuredSymbol + "|" + body.adding + "|" + body.search.searchText
      body.resetInteraction()
      service.persist(beforeSearch)
      var oldTop = searchFor("SH", "NVDA")
      mouseClick(body, oldTop.x, oldTop.y)
      wait(50)
      harness.check("a click where an old result was, before the new results, adds nothing",
        harness.same(service.library, beforeSearch.symbols) && service.featuredSymbol !== "SHOP",
        service.library + "|" + service.featuredSymbol)
      service.persist(beforeSearch)
      body.resetInteraction()

      // While a new query is out, the last results stay on screen, dimmed
      // and not takeable; an empty answer says so in place, a failed lookup
      // says so differently, and only an empty field clears them, the rows
      // staying away while search is open.
      searchFor("SH", "SHO")
      var whileOut = [body.search.results.length > 0, body.search.stale, !watchlist.visible].join(",")
      tryVerify(function() { return body.search.resultsQuery === "SHO" }, 3000)
      var freshAgain = !body.search.stale
      keyClick(Qt.Key_A, Qt.ControlModifier)
      ;["Z", "Z", "Z"].forEach(function(k) { keyClick(k) })
      tryVerify(function() { return body.search.resultsQuery === "ZZZ" }, 3000)
      var message = harness.find(body.search, "searchMessage")
      var noMatches = [body.search.results.length === 0, message.visible, message.text].join(",")
      keyClick(Qt.Key_A, Qt.ControlModifier)
      ;["O", "O", "P", "S"].forEach(function(k) { keyClick(k) })
      tryVerify(function() { return body.search.resultsQuery === "OOPS" }, 3000)
      var failed = [message.visible, message.text].join(",")
      // An answer holding only kinds Stonks leaves out says what it found
      // where "No matches" would be; one with results too lists them and
      // says the rest under them, and the arrows stop at the last result.
      var note = harness.find(body.search, "searchNote")
      keyClick(Qt.Key_A, Qt.ControlModifier)
      ;["V", "F", "I", "A", "X"].forEach(function(k) { keyClick(k) })
      tryVerify(function() { return body.search.resultsQuery === "VFIAX" }, 3000)
      // Let the new results finish laying out before reading the note.
      waitForPolish(note.parent)
      var fundAlone = [body.search.results.length, message.visible, note.visible, note.text].join(",")
      keyClick(Qt.Key_A, Qt.ControlModifier)
      ;["E", "U", "R", "U", "S", "D"].forEach(function(k) { keyClick(k) })
      tryVerify(function() { return body.search.resultsQuery === "EURUSD" }, 3000)
      waitForPolish(note.parent)
      // Yahoo's top answer is the currency, which Stonks leaves out, so no
      // result is chosen and Enter adds nothing.
      var libraryBefore = service.library.slice()
      var unchosen = body.search.resultIndex
      keyClick(Qt.Key_Return)
      wait(50)
      var enterOnCurrency = [unchosen, harness.same(service.library, libraryBefore), body.adding, body.search.resultsQuery].join(",")
      keyClick(Qt.Key_Down)
      keyClick(Qt.Key_Down)
      var beside = [body.search.results.map(function(r) { return r.symbol }).join(" "), message.visible, note.visible,
        note.text, body.search.resultIndex].join(",")
      keyClick(Qt.Key_A, Qt.ControlModifier)
      keyClick(Qt.Key_Backspace)
      var cleared = [body.search.results.length === 0, body.adding, watchlist.visible].join(",")
      harness.check("a query out keeps the last results stale and the rows away",
        whileOut === "true,true,true" && freshAgain && cleared === "true,true,false", whileOut + "|" + freshAgain + "|" + cleared)
      harness.check("an empty answer and a failed lookup each say so in place, differently",
        noMatches === "true,true,No matches for “ZZZ”"
          && failed === "true,Search didn’t answer",
        noMatches + " / " + failed)
      harness.check("an answer of kinds Stonks leaves out names them where \"No matches\" would be, and under the results it shows, the arrows stopping at the last result",
        fundAlone === "0,false,true,Stonks doesn’t show mutual funds"
          && beside === "18QQ.Z Q0SF.Z,false,true,Stonks doesn’t show currencies or futures,1",
        fundAlone + " / " + beside)
      harness.check("a search whose top answer is a kind Stonks leaves out chooses no result, and Enter adds nothing",
        enterOnCurrency === "-1,true,true,EURUSD", enterOnCurrency)
      body.resetInteraction()
      var held = firstSearchSaysSo(body, keys)
      harness.check("Enter before the new query's results adds nothing", early && held.held.ok,
        earlyDetail + " / " + held.held.detail)
      failedSearchRetries(body, keys)
      fieldOwnsKeys(body, watchlist, keys)

      // A search still out when the window closes is stopped, not waited
      // out, and brings nothing back: type SH, let it go out (the fake curl
      // answers in 0.4 s), close, and open. The words come back, as a
      // search being typed outlives a close, and are asked again: only that
      // new lookup answers.
      app.close()
      app.open("{}")
      tryVerify(function() { return app.opened }, 2000)
      keys.forceActiveFocus()
      keyClick(Qt.Key_A)
      tryVerify(function() { return body.adding }, 2000)
      var askedFirst = harness.calls("SEARCH.asked")
      harness.find(body.search, "searchField").text = "SH"
      // Out once the fake curl has counted it, before its pause: activeQuery
      // is set before curl starts, so a count read on it alone could miss
      // the first search and count it as the second.
      var searched = within(2000, function() { return body.search.activeQuery === "SH" && harness.calls("SEARCH.asked") === askedFirst + 1 })
      var askedBefore = harness.calls("SEARCH.asked")
      var answeredBefore = harness.calls("SEARCH.answered")
      app.close()
      app.open("{}")
      var reasked = within(3000, function() { return body.search.answer !== "" && body.search.resultsQuery === "SH" })
      // Time for the stopped lookup's answer to land, had it run on.
      wait(600)
      harness.check("a search out at a close is stopped, and the next open asks its words again",
        searched && reasked && body.adding && body.search.searchText === "SH" && body.search.results.length > 0
          && harness.calls("SEARCH.asked") - askedBefore === 1 && harness.calls("SEARCH.answered") - answeredBefore === 1,
        [searched, reasked, body.adding, body.search.searchText, body.search.results.length,
          harness.calls("SEARCH.asked") - askedBefore, harness.calls("SEARCH.answered") - answeredBefore].join("|"))

      keyClick(Qt.Key_Escape)

      sixRows(body, "STRAY", "1Y")

      looksUpBeforeAdding(body, watchlist, keys)
      twoSurfacesPreview(body, keys)
      addTakesOverHistory(body, keys)
      previewKeepsHeroFigures(body, keys)
      previewKeepsItsFigures(body, keys)
      earlyEnter(body, keys, held.kept)
      app.close()
      harness.finish()
    }
  }

}
