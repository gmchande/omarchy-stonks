import QtQuick
import QtTest
import Quickshell
import Quickshell.Io
import "plugin" as Stonks

// Search in the window, through the real App and Service with real Qt keys
// and pointer: results that belong to their query, a search out at a close,
// looking a result up on the hero before adding it, and one preview across
// two surfaces. HOME and curl are scratch fixtures.
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

  function find(item, name) {
    if (!item) return null
    if (item.objectName === name) return item
    for (var i = 0; i < item.children.length; i++) {
      var found = find(item.children[i], name)
      if (found) return found
    }
    return item.contentItem ? find(item.contentItem, name) : null
  }

  // The fake curl counts its calls per name in STONKS_FAKE_STATE. A fresh
  // view per read: a FileView that has loaded once returns its old text
  // straight after reload().
  function calls(name) {
    var view = Qt.createQmlObject('import Quickshell.Io; FileView { blockLoading: true; printErrors: false }', harness)
    view.path = Quickshell.env("STONKS_FAKE_STATE") + "/" + name + ".calls"
    var n = Number(String(view.text()).trim() || "0")
    view.destroy()
    return n
  }

  function finish() {
    console.log("WINDOW SEARCH DONE")
    done.exitCode = failures ? 1 : 0
    done.start()
  }

  Stonks.Service { id: service }
  readonly property string fakeState: Quickshell.env("STONKS_FAKE_STATE")
  Process { id: fileProc }
  Stonks.App { id: app; service: service }
  // A second surface on the same service, as a popup beside the window.
  Component { id: otherSurface; Stonks.StonksBody {} }

  TestCase {
    name: "WindowSearch"
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

    // Search shows its choice on the hero, unadded, before Enter adds it:
    // the arrows move the choice and the hero follows; a result's quote is
    // asked for only once the choice rests on it, never again by the quote
    // timer; while it is out the chart on show holds under "Loading"; Enter
    // adds the result the hero shows with the quote it has, and the chart
    // stays; Escape puts the featured symbol back; a failed lookup can still
    // be added; a click chooses and the chosen row's Add adds. The fake curl
    // answers SHOP.TO from its saved day and fails SHOP and SHHI.NE.
    function looksUpBeforeAdding(body, watchlist, keys) {
      service.switchList("")
      service.setRange("1D")
      wait(400)
      var hero = service.featuredSymbol
      var library = service.library.slice()
      var field = harness.find(body.search, "searchField")
      var draws = 0
      var onReveal = function() { if (body.motion.reveal === 0) draws++ }
      body.motion.revealChanged.connect(onReveal)
      // Fetches from here on: earlier flows fetched these too.
      var calls = function(symbol, from) { return harness.calls(symbol) - (from || 0) }
      var before = { to: harness.calls("SHOP.TO"), shop: harness.calls("SHOP"), shhi: harness.calls("SHHI.NE") }

      searchShop(body, keys)
      var fieldAt = field.mapToItem(body, 0, 0).y
      var topHeld = [body.headerText, body.chartSymbol, body.motion.drawn].join(",")
      harness.check("the top result shows on the hero as it loads: named, the chart on show held whole",
        topHeld === "Loading SHOP," + hero + ",1", topHeld)

      // Past SHOP and SHHI.NE before the choice rests: neither is fetched.
      keyClick(Qt.Key_Down)
      keyClick(Qt.Key_Down)
      keyClick(Qt.Key_Up)
      draws = 0
      var previewed = within(3000, function() { return body.chartSymbol === "SHOP.TO" && !body.chartLoading })
      wait(100)
      var shown = [previewed, body.featured.priceText, body.search.resultIndex, service.featuredSymbol === hero,
        service.library.indexOf("SHOP.TO") < 0, draws].join(",")
      harness.check("↓ shows the chosen result on the hero, unadded, drawn in once, the featured symbol kept",
        shown === "true,194.60,1,true,true,1", shown)
      var fetched = [calls("SHOP.TO", before.to), calls("SHOP", before.shop), calls("SHHI.NE", before.shhi)].join(",")
      harness.check("only the result the choice rests on is fetched", fetched === "1,0,0", fetched)
      var stats = within(3000, function() { return !!body.yearLine && body.yearLine.facts.length > 0 && body.yearLine.facts[0].value !== "" })
      harness.check("the preview's info lines are its own: its day and its cap",
        stats && !!body.periodLine && body.periodLine.range.lowText + "–" + body.periodLine.range.highText === "192.88–196.46",
        JSON.stringify(body.periodLine) + " / " + JSON.stringify(body.yearLine))
      // An hour on the schedule's clock, and a user's refresh.
      service.now += 3600
      service.askDue()
      service.refresh()
      wait(600)
      harness.check("neither the schedule nor r refreshes a preview", calls("SHOP.TO", before.to) === 1, calls("SHOP.TO", before.to))
      harness.check("the field stays put as the hero follows the choice",
        field.mapToItem(body, 0, 0).y === fieldAt, fieldAt + " -> " + field.mapToItem(body, 0, 0).y)
      // From a choice that has rested, arrowing on past results asks for
      // none of them either: each new choice waits its own rest. Found in
      // lookup-review's review: the next result was fetched at once.
      var further = { shhi: harness.calls("SHHI.NE"), f: harness.calls("307.F") }
      keyClick(Qt.Key_Down)
      keyClick(Qt.Key_Down)
      keyClick(Qt.Key_Up)
      keyClick(Qt.Key_Up)
      wait(400)
      var passed = [calls("SHHI.NE", further.shhi), calls("307.F", further.f), body.chartSymbol].join(",")
      harness.check("from a rested choice, results arrowed past are not fetched", passed === "0,0,SHOP.TO", passed)

      // Enter adds what the hero shows: its row joins faded in, it is the
      // featured symbol, and the chart on show neither changes nor redraws.
      var faded = false
      draws = 0
      // The result returned to above is asked for again once it rests.
      tryVerify(function() { return calls("SHOP.TO", before.to) === 2 && !!service.previewView.chart }, 3000)
      var beforeEnter = harness.calls("SHOP.TO")
      keyClick(Qt.Key_Return)
      // The row is made as it joins, and fades in on the frames after.
      var row = watchlist.rowItem("SHOP.TO")
      var onFade = function() { if (row.visible && row.opacity < 1) faded = true }
      if (row) {
        onFade()
        row.opacityChanged.connect(onFade)
      }
      tryVerify(function() { return !!row && watchlist.displayedSymbols.indexOf("SHOP.TO") >= 0 && row.resting }, 2000)
      wait(100)
      var added = [service.featuredSymbol, body.adding, body.chartSymbol, draws, calls("SHOP.TO", beforeEnter)].join(",")
      harness.check("Enter adds the result on the hero with its quote: featured, the chart kept, nothing fetched again",
        added === "SHOP.TO,false,SHOP.TO,0,0", added)
      harness.check("its row fades in at its place", faded, faded)
      row.opacityChanged.disconnect(onFade)
      service.removeSymbol("SHOP.TO")
      service.feature(hero)
      wait(400)

      // Escape puts the featured symbol back, drawn in, and adds nothing.
      searchShop(body, keys)
      keyClick(Qt.Key_Down)
      tryVerify(function() { return body.chartSymbol === "SHOP.TO" && !body.chartLoading && body.motion.reveal === 1 }, 3000)
      draws = 0
      keyClick(Qt.Key_Escape)
      wait(100)
      var back = [body.adding, body.chartSymbol, draws, service.library.indexOf("SHOP.TO") < 0].join(",")
      harness.check("Escape puts the featured symbol back on the hero, drawn in, and adds nothing",
        back === "false," + hero + ",1,true", back)

      // A lookup that fails says so on the hero; Enter adds it anyway, and
      // the hero goes back to what it showed. Its failed fetch was the add's
      // first: the add is done there, its row joining at once saying so,
      // with nothing fetched again. Found in the Grok review of #36: it
      // went arriving and was fetched again, and an answer then would have
      // taken the hero.
      searchShop(body, keys)
      var failed = within(9000, function() {
        return body.chartSymbol === "SHOP" && body.featuredFreshness.state === "failed"
      })
      harness.check("a failed lookup shows on the hero as failed", failed,
        body.chartSymbol + "|" + body.featuredFreshness.state + "|" + body.headerText)
      var shopCalls = harness.calls("SHOP")
      keyClick(Qt.Key_Return)
      wait(600)
      var failedAdd = [service.library.indexOf("SHOP") >= 0, service.featuredSymbol === hero, body.chartSymbol].join(",")
      harness.check("Enter adds a failed lookup anyway, and the hero shows the featured symbol",
        failedAdd === "true,true," + hero, failedAdd)
      var failedRow = [service.arriving.indexOf("SHOP") < 0, watchlist.displayedSymbols.indexOf("SHOP") >= 0,
        service.entries.SHOP ? service.entries.SHOP.status : "none", calls("SHOP", shopCalls)].join(",")
      harness.check("an add of a failed lookup is done there: its row joins saying so, nothing fetched again",
        failedRow === "true,true,failed,0", failedRow)
      service.removeSymbol("SHOP")
      wait(100)

      // The pointer: a click on a result takes it as Enter does, chosen and
      // then added, the hero landing on it, though the keyboard's choice was
      // the top result. Found by the owner on 14 October: a click only
      // chose the row, and adding took the chosen row's small Add.
      searchShop(body, keys)
      var second = findAll(body.search, "searchResult")[1]
      mouseClick(second, second.width / 4, second.height / 2)
      within(3000, function() { return service.featuredSymbol === "SHOP.TO" })
      var byPointer = [service.library.indexOf("SHOP.TO") >= 0, service.featuredSymbol, body.adding].join(",")
      harness.check("a click on a result adds it, as Enter does, and the hero lands on it", byPointer === "true,SHOP.TO,false", byPointer)
      service.removeSymbol("SHOP.TO")
      service.feature(hero)
      wait(300)
      // CANCEL does what Escape does: the hero goes back, nothing added.
      searchShop(body, keys)
      wait(Qt.styleHints.mouseDoubleClickInterval + 50)
      var cancel = harness.find(body.search, "searchCancel")
      mouseClick(cancel, cancel.width / 2, cancel.height / 2)
      wait(100)
      var cancelled = [body.adding, body.chartSymbol, service.library.indexOf("SHOP") < 0].join(",")
      harness.check("CANCEL closes search as Escape does, the hero back and nothing added",
        cancelled === "false," + hero + ",true", cancelled)
      body.motion.revealChanged.disconnect(onReveal)
      tryVerify(function() { return service.testFeed.firstRun.length + service.testFeed.refreshRun.length === 0 }, 5000)
      wait(400)
      harness.check("the lookup flow leaves All as it found it", harness.same(service.library, library),
        service.library + " vs " + library)
    }

    // A second surface beside the window, on the same service, as the
    // popup is: its search taking the preview closes the window's search,
    // so neither hero shows one result while Enter would add another; the
    // window's hero, back on the featured symbol, gets its range's history
    // while the other previews; and a surface that goes while previewing
    // takes its preview with it. Found in lookup-review's review.
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
      // and the preview's. Found in the Grok review of #36: only the
      // preview's was fetched again.
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
      app.open("{}")
      service.setRange("1D")
      wait(400)
    }

    // An add from search on a range, before the result's first answer,
    // takes over the history fetch its preview has out instead of asking
    // again: SHOP.TO's day and year held back, Enter on it, then its day let
    // through, and its row lands and is featured while the year is still
    // out, asked for once. The hero it leaves has lost its own year
    // meanwhile, which waits behind it. And the fetch it takes over is
    // still the add's own: let through before the row lands, it fails,
    // is tried again as any is, and keeps its failure. Found in the slow
    // walk of #45: the year was asked for twice, and on a slow network the
    // new row's chart took twice as long; the hero's missing year and the
    // failure in the review of the fix.
    function addTakesOverHistory(body, keys) {
      var hold = function(command, name) {
        fileProc.command = [command].concat(command === "rm" ? ["-f"] : []).concat([harness.fakeState + "/" + name])
        fileProc.running = true
        tryVerify(function() { return !fileProc.running }, 2000)
      }
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
        hold("touch", "SHOP.TO.quote.hold")
        hold("touch", "SHOP.TO.history.hold")
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
        hold("rm", "SHOP.TO.quote.hold")
        hold("rm", "SHOP.TO.history.hold")
        tryVerify(function() { return service.featuredSymbol === "SHOP.TO" && !service.testHistoryFeed.busy }, 12000)
        service.removeSymbol("SHOP.TO")
        service.feature("MSFT")
        wait(300)
      }

      var first = addHeld(true)
      hold("rm", "SHOP.TO.quote.hold")
      tryVerify(function() { return service.featuredSymbol === "SHOP.TO" }, 8000)
      wait(300)
      var taken = [first.arriving, body.chartLoading, harness.calls("SHOP.TO.history") - first.from].join(",")
      done()
      harness.check("an add from search on a range, before its first answer, takes over its preview's history fetch, asked for once, though the hero it leaves has lost its own",
        taken === "true,true,1", taken)

      var second = addHeld(false)
      hold("rm", "SHOP.TO.history.hold")
      var failedOwn = within(8000, function() {
        var entry = service.histories["SHOP.TO|1Y"]
        return !!entry && entry.status === "failed"
      })
      var kept = [second.arriving, failedOwn, harness.calls("SHOP.TO.history") - second.from].join(",")
      done()
      harness.check("the fetch an add takes over is still its own: failing before the row lands, it is tried again and keeps its failure",
        kept === "true,true,2", kept)

      // The hand-over is the add's only while its landing lasts: another
      // preview has its own year asked for, and a close ends it, so the
      // reopened window asks nothing for the add as a hero's. Under half of
      // Yahoo's budget there, so nothing is fetched ahead either. Found in
      // the second review of the fix: it held on, ahead of both.
      var release = function() {
        hold("rm", "SHOP.TO.quote.hold")
        hold("rm", "SHOP.TO.history.hold")
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
      var shut = addHeld(false)
      app.close()
      hold("rm", "SHOP.TO.quote.hold")
      tryVerify(function() { return service.arriving.length === 0 }, 8000)
      service.testYahooGate.tokens = 30
      app.open("{}")
      wait(1500)
      var reopenedAsked = harness.calls("SHOP.TO.history") - shut.from
      release()
      harness.check("the next preview, or a close, ends an add's hold on its preview's fetch",
        othersOwn && reopenedAsked === 1, othersOwn + "," + reopenedAsked)

      // Only its own surface's close ends it: another surface open beside
      // the window, as the popup is, closes while the add is out, and the
      // added row's year is still asked for once. Found in the third review.
      var beside = otherSurface.createObject(null, { service: service, width: 480, height: 760 })
      beside.surfaceOpen = true
      wait(100)
      var besideAdd = addHeld(false)
      beside.surfaceOpen = false
      wait(50)
      hold("rm", "SHOP.TO.quote.hold")
      tryVerify(function() { return service.featuredSymbol === "SHOP.TO" }, 8000)
      wait(300)
      var besideAsked = harness.calls("SHOP.TO.history") - besideAdd.from
      beside.destroy()
      release()
      harness.check("another surface closing leaves the add its preview's fetch: asked for once",
        besideAdd.arriving && besideAsked === 1, besideAdd.arriving + "," + besideAsked)
      service.setRange("1D")
      wait(300)
    }

    // The result rows of the answer on screen, each once: findAll reaches
    // a Flickable's rows through its children and its contentItem both.
    function resultRows(body) {
      return findAll(body.search, "searchResult").filter(function(row, i, all) { return all.indexOf(row) === i })
    }

    // Types `query` over what the field holds and waits for its answer.
    function answer(body, query) {
      keyClick(Qt.Key_A, Qt.ControlModifier)
      for (var c = 0; c < query.length; c++) keyClick(query[c])
      tryVerify(function() { return body.search.resultsQuery === query }, 3000)
      wait(50)
    }

    // Search's field opens where the list's first row was, under its
    // header, and stays there from its open through one answer, five, none,
    // and a lookup with no answer; each answer starts the same gap under
    // it, and Enter is offered, on the chosen result, only while there is a
    // result to take.
    // Found in the first-run review: the field opened at the bottom, and
    // "No matches" sat about 260 px above it, the hint still offering add.
    function fieldInRowsPlace(body, watchlist, keys) {
      var bar = harness.find(body.search, "searchField").parent
      // Whether a result's label offers Enter: the chosen one's, shown.
      var offersEnter = function() {
        return resultRows(body).some(function(row) {
          var add = harness.find(row, "searchAdd")
          return row.visible && add.opacity === 1
        })
      }
      var message = harness.find(body.search, "searchMessage")
      var rowsAt = Math.round(watchlist.mapToItem(body, 0, 0).y)
      var seen = []
      // Where the field's bar stands, how far under it the answer starts,
      // and whether Enter is offered.
      var look = function(label) {
        var first = body.search.results.length ? resultRows(body)[0] : message.visible ? message : null
        var under = first ? Math.round(first.mapToItem(body, 0, 0).y - bar.mapToItem(body, 0, bar.height).y) : "-"
        seen.push([label, Math.round(bar.mapToItem(body, 0, 0).y), under, offersEnter()].join(" "))
      }
      keys.forceActiveFocus()
      keyClick(Qt.Key_A)
      wait(50)
      look("open")
      ;["ONE", "SH", "ZZZ", "OOPS"].forEach(function(query) {
        answer(body, query)
        look(query + "/" + body.search.results.length)
      })
      keyClick(Qt.Key_Escape)
      wait(50)
      var gap = body.search.resultsGap
      var want = ["open " + rowsAt + " - false", "ONE/1 " + rowsAt + " " + gap + " true", "SH/5 " + rowsAt + " " + gap + " true",
        "ZZZ/0 " + rowsAt + " " + gap + " false", "OOPS/0 " + rowsAt + " " + gap + " false"]
      harness.check("search's field opens where the first row was and stays there, each answer starting under it, Enter offered only with results",
        harness.same(seen, want), seen.join(" | ") + " — want " + want.join(" | "))
    }

    // A long symbol shows whole, the name giving way to it, and the
    // exchange codes keep one column. Found in the first-run review:
    // "XBTC39577-…" was cut while its name kept its room.
    function longSymbols(body, keys) {
      keys.forceActiveFocus()
      keyClick(Qt.Key_A)
      wait(50)
      answer(body, "BTC")
      var rows = resultRows(body)
      // The row's symbol: the Text that says it.
      var symbolText = function(item, symbol) {
        if (item.text === symbol && item.implicitWidth !== undefined) return item
        for (var i = 0; i < item.children.length; i++) {
          var found = symbolText(item.children[i], symbol)
          if (found) return found
        }
        return null
      }
      var symbols = rows.map(function(row) { return symbolText(row, row.modelData.symbol) }).filter(function(s) { return !!s })
      var cut = symbols.filter(function(s) { return s.implicitWidth > s.width }).map(function(s) { return s.text })
      var edges = rows.map(function(row) {
        var code = harness.find(row, "searchExchange")
        return Math.round(code.mapToItem(body, code.width, 0).x)
      })
      keyClick(Qt.Key_Escape)
      wait(50)
      harness.check("long symbols show whole in search, the exchange codes in one column",
        symbols.length === 5 && cut.length === 0 && edges.length === 5 && edges.every(function(x) { return x === edges[0] }),
        symbols.length + " symbols, cut: " + cut.join(",") + " | codes " + edges.join(","))
    }

    // The window at its smallest shows search's field and only whole
    // results, one at least. Found in the first-run review: the field cut
    // the second result in half.
    function smallestWindow(body, keys) {
      var height = app.testWindow.implicitHeight
      app.close()
      app.testWindow.implicitHeight = app.testWindow.minimumSize.height
      app.open("{}")
      wait(200)
      keys.forceActiveFocus()
      keyClick(Qt.Key_A)
      wait(50)
      answer(body, "SH")
      var view = harness.find(body.search, "searchResults")
      var tops = resultRows(body).map(function(row) { return Math.round(row.y - view.contentY) })
      var rowHeight = body.search.rowHeight
      var whole = tops.filter(function(top) { return top >= 0 && top + rowHeight <= view.height }).length
      var cut = tops.filter(function(top) { return top + rowHeight > 0 && top < view.height && (top < 0 || top + rowHeight > view.height) }).length
      var atMinimum = Math.round(body.height) === app.testWindow.minimumSize.height
      var at = [Math.round(body.height), Math.round(view.height), whole, cut].join(",")
      // The keys reach the note under the results: the last one brings it
      // into view. Found in review: in the window at its smallest, ↓ stopped
      // on the fifth result and the note stayed clipped under it.
      answer(body, "MIXED")
      for (var d = 0; d < 5; d++) keyClick(Qt.Key_Down)
      var note = harness.find(body.search, "searchNote")
      var noteTop = Math.round(note.y - view.contentY)
      var noteSeen = [body.search.resultIndex, body.search.results.length, noteTop >= 0 && noteTop + note.height <= view.height + 0.5].join(",")
      keyClick(Qt.Key_Escape)
      app.close()
      app.testWindow.implicitHeight = height
      app.open("{}")
      wait(200)
      harness.check("the smallest window shows search's results whole, one at least, none cut, and ↓ to the last brings the note under them into view",
        atMinimum && whole >= 1 && cut === 0 && noteSeen === "4,5,true",
        "body, results' room, whole, cut: " + at + " (minimum " + app.testWindow.minimumSize.height + ") | chosen, results, note seen: " + noteSeen)
    }

    // A first search says it is searching once its lookup has been out a
    // quarter of a second, under the field where its answer will go, and
    // the answer replaces the line: results, no matches, or no answer. One
    // that answers sooner never shows it, and an edit while it shows keeps
    // it up, naming the field's query. Found in the slow walk of 16
    // October: under the field stayed empty for over four seconds.
    function firstSearchSaysSo(body, keys) {
      var message = harness.find(body.search, "searchMessage")
      // Every line under the field, frame by frame ("-" for none), from an
      // empty field until the answer for `query` + `then` lands, and how
      // long after its first lookup went out the line first showed.
      // `then` is typed once a frame has drawn the line.
      var search = function(query, then) {
        keyClick(Qt.Key_A, Qt.ControlModifier)
        keyClick(Qt.Key_Backspace)
        var seen = []
        var outAt = 0
        var shownAfter = -1
        var out = function() { if (body.search.activeQuery !== "" && !outAt) outAt = Date.now() }
        var watch = function() {
          var said = message.visible ? message.text : "-"
          if (said !== "-" && shownAfter < 0) shownAfter = Date.now() - outAt
          if (seen[seen.length - 1] !== said) seen.push(said)
        }
        body.search.activeQueryChanged.connect(out)
        var frames = Qt.createQmlObject('import QtQuick; FrameAnimation { running: true }', harness)
        frames.triggered.connect(watch)
        for (var c = 0; c < query.length; c++) keyClick(query[c])
        if (then) {
          within(2000, function() { return seen.length > 1 })
          for (c = 0; c < then.length; c++) keyClick(then[c])
        }
        tryVerify(function() { return body.search.resultsQuery === query + (then || "") }, 3000)
        wait(100)
        frames.destroy()
        body.search.activeQueryChanged.disconnect(out)
        return seen.join(" / ") + " | " + (shownAfter < 0 ? "never" : shownAfter >= 250 ? "late" : shownAfter + " ms")
      }
      keys.forceActiveFocus()
      keyClick(Qt.Key_A)
      wait(50)
      var late = search("S", "H")
      var none = search("ZZZ")
      var failed = search("OOPS")
      var fast = search("FAST")
      body.resetInteraction()
      harness.check("a first search says it is searching a quarter second after its lookup goes out, through an edit, until its answer replaces the line; one answering sooner never says so",
        late === "- / Searching for “S”… / Searching for “SH”… / - | late"
          && none === "- / Searching for “ZZZ”… / No matches for “ZZZ” | late"
          && failed === "- / Searching for “OOPS”… / Search didn’t answer | late"
          && fast === "- | never",
        [late, none, failed, fast].join(" ; "))
    }

    // A failed lookup is asked again, the same query through the same
    // request and gate as typing it: by Enter, saying it is searching as a
    // first query does, and by a click on RETRY; while Yahoo's gate pauses
    // Stonks, a retry fails at once and asks nothing. SH fails while the
    // fake curl's search is down, then answers. Found in the 1.0.0 review:
    // "Search didn't answer · try again" led nowhere, Enter doing nothing
    // and nothing to click.
    function failedSearchRetries(body, keys) {
      var searchDown = function(down) {
        fileProc.command = down ? ["touch", harness.fakeState + "/SEARCH.down"] : ["rm", "-f", harness.fakeState + "/SEARCH.down"]
        fileProc.running = true
        tryVerify(function() { return !fileProc.running }, 2000)
      }
      var message = harness.find(body.search, "searchMessage")
      // Read through guards, so a search without RETRY fails the check
      // rather than throwing.
      var retry = harness.find(body.search, "searchRetry")
      var retryShown = function() { return !!retry && retry.visible }
      var clickRetry = function() { if (retry) mouseClick(retry, retry.width / 2, retry.height / 2) }
      var library = service.library.slice()
      searchDown(true)
      keys.forceActiveFocus()
      keyClick(Qt.Key_A)
      wait(50)
      keyClick("S")
      keyClick("H")
      tryVerify(function() { return body.search.answer === "failed" && body.search.resultsQuery === "SH" }, 3000)
      var offered = [message.text, retryShown()].join(",")
      // Enter, Yahoo's search still down: asked once more, the line saying
      // so, frame by frame, until it fails again.
      var failedBefore = harness.calls("SEARCH.failed")
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
      wait(100)
      frames.destroy()
      var byEnter = [seen.join(" / "), harness.calls("SEARCH.failed") - failedBefore, body.adding].join(",")
      // RETRY, while the gate pauses Stonks: no request, the failure stays.
      var gate = service.testYahooGate
      gate.begin("refused", 60)
      failedBefore = harness.calls("SEARCH.failed")
      var answeredBefore = harness.calls("SEARCH.answered")
      clickRetry()
      wait(600)
      var paused = [harness.calls("SEARCH.failed") - failedBefore, harness.calls("SEARCH.answered") - answeredBefore,
        body.search.answer, retryShown()].join(",")
      gate.pause = ""
      // RETRY, Yahoo's search back: its answer lands, nothing added.
      searchDown(false)
      clickRetry()
      within(3000, function() { return body.search.results.length > 0 })
      var byClick = [body.search.resultsQuery, body.search.results.length > 0, harness.calls("SEARCH.answered") - answeredBefore,
        retryShown(), body.adding, harness.same(service.library, library)].join(",")
      body.resetInteraction()
      harness.check("a failed lookup offers RETRY; Enter and a click on it ask the same query again, through Yahoo's gate, and adding nothing",
        offered === "Search didn’t answer,true"
          && byEnter === "Search didn’t answer / - / Searching for “SH”… / Search didn’t answer,1,true"
          && paused === "0,0,failed,true" && byClick === "SH,true,1,false,true,true",
        [offered, byEnter, paused, byClick].join(" ; "))
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

      // Results belong to their query. Search SH and let its answer land,
      // replace the field with NVDA, and act before NVDA's answer (the fake
      // curl answers 0.4 s after the 250 ms debounce): neither Enter nor a
      // click where SHOP was adds anything. Once NVDA's answer is in, Enter
      // adds its top result. Found in the garden review: both added SHOP.
      var beforeSearch = service.dataSettings
      var beforeFeatured = service.featuredSymbol
      var searchFor = function(first, then) {
        keys.forceActiveFocus()
        keyClick(Qt.Key_A)
        wait(50)
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
      harness.check("Enter before the new query's results adds nothing",
        harness.same(service.library, beforeSearch.symbols) && service.featuredSymbol === beforeFeatured
          && body.adding && body.search.searchText === "NVDA",
        service.library + "|" + service.featuredSymbol + "|" + body.adding + "|" + body.search.searchText)
      tryVerify(function() { return body.search.resultsQuery === "NVDA" && body.search.results.length > 0 }, 3000)
      keyClick(Qt.Key_Return)
      wait(50)
      harness.check("Enter once the new query's results are in adds its top result",
        service.library.indexOf("SHOP") >= 0 && !body.adding,
        service.library + "|" + service.featuredSymbol + "|" + body.adding)
      service.persist(beforeSearch)
      wait(50)
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
      // staying away while search is open. Found in the code-quality
      // review: every edit brought the watchlist back for up to a second.
      searchFor("SH", "SHO")
      var resultsView = harness.find(body.search, "searchResults")
      var whileOut = [body.search.results.length > 0, body.search.stale, resultsView.opacity < 1,
        !watchlist.visible].join(",")
      tryVerify(function() { return body.search.resultsQuery === "SHO" }, 3000)
      var freshAgain = !body.search.stale && resultsView.opacity === 1
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
      // Found in the edge-case pass of 15 October: "vfiax", a fund Yahoo
      // has, read "No matches", and "eurusd" hid the currency without a word.
      var note = harness.find(body.search, "searchNote")
      keyClick(Qt.Key_A, Qt.ControlModifier)
      ;["V", "F", "I", "A", "X"].forEach(function(k) { keyClick(k) })
      tryVerify(function() { return body.search.resultsQuery === "VFIAX" }, 3000)
      var fundAlone = [body.search.results.length, message.visible, note.visible, note.text,
        Math.round(note.mapToItem(resultsView, 0, 0).y)].join(",")
      keyClick(Qt.Key_A, Qt.ControlModifier)
      ;["E", "U", "R", "U", "S", "D"].forEach(function(k) { keyClick(k) })
      tryVerify(function() { return body.search.resultsQuery === "EURUSD" }, 3000)
      var shownRows = findAll(body.search, "searchResult").filter(function(r) { return r.visible })
      var lastRow = shownRows[shownRows.length - 1]
      var under = Math.round(note.mapToItem(lastRow, 0, 0).y - lastRow.height)
      keyClick(Qt.Key_Down)
      keyClick(Qt.Key_Down)
      var beside = [body.search.results.map(function(r) { return r.symbol }).join(" "), message.visible, note.visible,
        note.text, under === body.search.rowGap, body.search.resultIndex].join(",")
      keyClick(Qt.Key_A, Qt.ControlModifier)
      keyClick(Qt.Key_Backspace)
      var cleared = [body.search.results.length === 0, body.adding, watchlist.visible].join(",")
      harness.check("a query out keeps the last results dimmed and the rows away",
        whileOut === "true,true,true,true" && freshAgain, whileOut + "|" + freshAgain)
      harness.check("an empty answer and a failed lookup each say so in place, differently",
        noMatches === "true,true,No matches for “ZZZ”"
          && failed === "true,Search didn’t answer",
        noMatches + " / " + failed)
      harness.check("an answer of kinds Stonks leaves out names them where \"No matches\" would be, and under the results it shows, the arrows stopping at the last result",
        fundAlone === "0,false,true,Stonks doesn’t show mutual funds,0"
          && beside === "18QQ.Z Q0SF.Z,false,true,Stonks doesn’t show currencies or futures,true,1",
        fundAlone + " / " + beside)
      harness.check("an empty field clears the results, the rows still away while search is open",
        cleared === "true,true,false", cleared)
      // Emptied while a query is out, the field drops it: no answer comes
      // for it. Found in cubic's review of #25.
      ;["S", "H"].forEach(function(k) { keyClick(k) })
      tryVerify(function() { return body.search.activeQuery === "SH" }, 2000)
      var answeredBeforeClear = harness.calls("SEARCH.answered")
      keyClick(Qt.Key_Backspace)
      keyClick(Qt.Key_Backspace)
      wait(600)
      harness.check("emptying the field drops the query still out",
        harness.calls("SEARCH.answered") === answeredBeforeClear && body.search.activeQuery === "",
        (harness.calls("SEARCH.answered") - answeredBeforeClear) + "|" + body.search.activeQuery)
      body.resetInteraction()
      firstSearchSaysSo(body, keys)
      failedSearchRetries(body, keys)

      fieldInRowsPlace(body, watchlist, keys)
      longSymbols(body, keys)
      smallestWindow(body, keys)

      // A search still out when the window closes brings nothing back, and is
      // stopped, not waited out: type SH, let it go out (the fake curl
      // answers in 0.4 s), close, open, and start a new search. Found in
      // cubic's review of #25: the old curl ran on and could hold a new
      // search back for its whole timeout.
      app.close()
      app.open("{}")
      wait(200)
      keys.forceActiveFocus()
      keyClick(Qt.Key_A)
      wait(50)
      harness.find(body.search, "searchField").text = "SH"
      var searched = within(2000, function() { return body.search.activeQuery === "SH" })
      var answeredBefore = harness.calls("SEARCH.answered")
      app.close()
      app.open("{}")
      wait(100)
      keys.forceActiveFocus()
      keyClick(Qt.Key_A)
      wait(600)
      harness.check("a search out at a close is stopped, and a new open shows nothing of it",
        searched && body.adding && body.search.searchText === "" && body.search.results.length === 0
          && harness.calls("SEARCH.answered") === answeredBefore,
        searched + "|" + body.adding + "|" + body.search.searchText + "|" + body.search.results.length
          + "|" + (harness.calls("SEARCH.answered") - answeredBefore))

      keyClick(Qt.Key_Escape)

      sixRows(body, "STRAY", "1Y")

      looksUpBeforeAdding(body, watchlist, keys)
      twoSurfacesPreview(body, keys)
      addTakesOverHistory(body, keys)
      app.close()
      harness.finish()
    }
  }

  HarnessExit { id: done }
}
