import QtQuick
import QtTest
import Quickshell
import Quickshell.Io
import "plugin" as Stonks

// Named watchlists through the real Service and App with real keys. The data
// file starts as the version-1 fixture (AAPL, MSFT, NVDA; the fake curl
// answers all three) and is read back with cat, never through a FileView.
ShellRoot {
  id: harness

  property int failures: 0
  property var fileRead: null
  readonly property string dataPath: Quickshell.env("HOME") + "/.config/omarchy/grvc.stonks.json"

  function check(label, ok, detail) {
    console.log((ok ? "PASS " : "FAIL ") + label + (!ok && detail !== undefined ? " — " + detail : ""))
    if (!ok) failures++
  }

  function same(got, want) { return (got || []).join(",") === want.join(",") }

  // The fake curl counts its calls per symbol. A fresh view per read: a
  // FileView that has loaded once returns its old text straight after reload().
  function calls(symbol) {
    var view = Qt.createQmlObject('import Quickshell.Io; FileView { blockLoading: true; printErrors: false }', harness)
    view.path = Quickshell.env("STONKS_FAKE_STATE") + "/" + symbol + ".calls"
    var n = Number(String(view.text()).trim() || "0")
    view.destroy()
    return n
  }

  function readFile() {
    harness.fileRead = null
    catProc.running = true
  }

  function find(item, name) {
    if (!item) return null
    if (item.objectName === name) return item
    for (var i = 0; i < item.children.length; i++) {
      var found = find(item.children[i], name)
      if (found) return found
    }
    return null
  }

  function findAll(item, name, into) {
    var out = into || []
    if (!item) return out
    if (item.objectName === name) out.push(item)
    for (var i = 0; i < item.children.length; i++) findAll(item.children[i], name, out)
    return out
  }

  function finish() {
    console.log("LISTS DONE")
    done.exitCode = failures ? 1 : 0
    done.start()
  }

  Stonks.Service { id: service }
  Stonks.App { id: app; service: service }

  Component { id: serviceAgain; Stonks.Service {} }

  Process {
    id: catProc
    command: ["cat", harness.dataPath]
    stdout: StdioCollector {
      id: catOut
      waitForEnd: true
      onStreamFinished: {
        try { harness.fileRead = JSON.parse(String(text || "").trim()) } catch (e) { harness.fileRead = {} }
      }
    }
  }

  // Hashes of saved frames, path to sha1.
  Process {
    id: hashProc
    property var sums: null
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var out = {}
        String(text || "").trim().split("\n").forEach(function(line) {
          // sha1sum prints the hash, two spaces, then the path as given.
          out[line.slice(42)] = line.slice(0, 40)
        })
        hashProc.sums = out
      }
    }
  }

  TestCase {
    name: "NamedWatchlists"
    when: service.pluginsReady

    // Waits up to ms for fn to hold and returns whether it does, so the
    // check that reads it is the one that fails.
    function within(ms, fn) {
      for (var t = 0; t < ms && !fn(); t += 20) wait(20)
      return fn()
    }

    function typeText(text) {
      for (var i = 0; i < text.length; i++) keyClick(text.charAt(i))
    }

    // The body as drawn now, into out/render/lists-flow-<name>.png.
    function grab(name) {
      var saved = false
      var path = Quickshell.env("STONKS_LISTS_OUT") + "/lists-flow-" + name + ".png"
      app.testBody.grabToImage(function(result) { saved = result.saveToFile(path) })
      tryVerify(function() { return saved }, 3000, "grab " + name)
    }

    function center(item) { return item.mapToItem(app.testBody, item.width / 2, item.height / 2) }
    // The cursor's mark on each of `rows`: "bar+fill" on the cursor's row, ""
    // on the rest. A row's first child is its fill.
    function marks(rows) {
      return rows.map(function(row) {
        var bar = harness.find(row, "cursorBar")
        return [bar && bar.visible ? "bar" : "", Qt.colorEqual(row.children[0].color, "transparent") ? "" : "fill"]
          .filter(function(part) { return part !== "" }).join("+")
      }).join(",")
    }

    // The rows' words that show beside the open list menu on `body`: a
    // symbol or name on the menu's band that ends past its right edge.
    function wordsPastMenu(body) {
      var menu = harness.find(body, "listMenu")
      var edge = menu.mapToItem(body, menu.width, menu.height)
      var past = []
      body.watchlist.displayedSymbols.forEach(function(symbol) {
        var row = body.watchlist.rowItem(symbol)
        ;["rowSymbol", "rowDetail"].forEach(function(name) {
          var words = row ? harness.find(row, name) : null
          if (!words || !words.visible || words.text === "") return
          var top = words.mapToItem(body, 0, 0)
          var end = words.mapToItem(body, Math.min(words.width, words.contentWidth), 0)
          if (top.y < edge.y && end.x > edge.x) past.push(symbol + " " + JSON.stringify(words.text))
        })
      })
      return past
    }

    function test_list_flows() {
      tryVerify(function() {
        return service.quotes.AAPL && service.quotes.MSFT && service.quotes.NVDA
          && service.testFeed.firstRun.length + service.testFeed.refreshRun.length === 0
      }, 10000)

      harness.readFile()
      tryVerify(function() { return harness.fileRead !== null }, 3000)
      harness.check("a version-1 file loads as All with no lists and is not rewritten",
        service.listName === "" && service.lists.length === 1 && service.lists[0].label === "All"
          && harness.same(service.symbols, ["AAPL", "MSFT", "NVDA"])
          && harness.fileRead.lists === undefined)

      app.open("{}")
      wait(200)
      var body = app.testBody
      var watchlist = body.watchlist
      var keys = app.testKeyCatcher
      keys.forceActiveFocus()

      // No piece of a row's words shows past the open list menu's edge,
      // opened by key or by click. Found in the 1.0.0 review: the "t" of
      // SPY's long name showed beside the menu, and in the window whole
      // tails of names.
      var plainQuotes = service.testFeed.quotes
      var longNamed = Object.assign({}, plainQuotes)
      longNamed.AAPL = Object.assign({}, plainQuotes.AAPL, { name: "State Street SPDR S&P 500 ETF Trust, a name as long as the window's row" })
      service.testFeed.quotes = longNamed
      wait(50)
      var shutPast = wordsPastMenu(body)
      keyClick(Qt.Key_W)
      wait(50)
      var keyPast = body.listMenuOpen ? wordsPastMenu(body) : ["the menu is shut"]
      keyClick(Qt.Key_Escape)
      wait(50)
      var listControlAt = center(harness.find(body, "listControl"))
      mouseClick(body, listControlAt.x, listControlAt.y)
      wait(100)
      var clickPast = body.listMenuOpen ? wordsPastMenu(body) : ["the menu is shut"]
      mouseClick(body, listControlAt.x, listControlAt.y)
      wait(100)
      service.testFeed.quotes = plainQuotes
      keys.forceActiveFocus()
      wait(50)
      harness.check("no piece of a row's long name shows past the list menu's edge, opened by key or by click",
        shutPast.length > 0 && keyPast.length === 0 && clickPast.length === 0 && !body.listMenuOpen,
        "shut: " + shutPast.join(", ") + " | by key: " + keyPast.join(", ") + " | by click: " + clickPast.join(", "))

      keyClick(Qt.Key_W)
      wait(50)
      var menu = body.children.filter(function(child) { return child.objectName === "listMenu" })[0]
      harness.check("w opens the list menu with the cursor on the current list",
        body.listMenuOpen && menu.visible && menu.cursor === 0 && menu.current === "")
      keyClick(Qt.Key_Down)
      keyClick(Qt.Key_Return)
      wait(50)
      harness.check("Enter on New list… turns it into a name field", menu.naming)
      typeText("Growth")
      keyClick(Qt.Key_Return)
      wait(100)
      harness.check("a new list is made, current, empty, and search opens to fill it",
        service.listName === "Growth" && service.symbols.length === 0
          && !body.listMenuOpen && body.adding
          && body.search.placeholder.indexOf("Growth") >= 0,
        service.listName + "|" + service.symbols + "|" + body.listMenuOpen + "|" + body.adding + "|" + body.search.placeholder)

      // An add whose row joins in view, fresh or already quoted in All, is
      // featured once its join has finished, and its chart draws in. Found
      // in the review of the untangle: it was featured mid-fade.
      var addMotions = []
      var watchAddDraw = function() { if (body.motion.reveal === 0) addMotions.push("draw " + service.featuredSymbol) }
      body.motion.revealChanged.connect(watchAddDraw)
      var nvdaCalls = harness.calls("NVDA")
      body.search.picked("NVDA")
      wait(400)
      keys.forceActiveFocus()
      keyClick(Qt.Key_A)
      wait(50)
      body.search.picked("AAPL")
      wait(400)
      body.motion.revealChanged.disconnect(watchAddDraw)
      harness.check("an add joining in view draws its chart in once its join is done, each time",
        addMotions.join(",") === "draw NVDA,draw AAPL", addMotions.join(","))
      harness.readFile()
      tryVerify(function() { return harness.fileRead !== null }, 3000)
      harness.check("adding on a list puts the symbol in it without a second copy in All, and writes it featured",
        harness.same(service.symbols, ["NVDA", "AAPL"]) && service.lists[1].count === 2 && service.lists[0].count === 3
          && harness.same(harness.fileRead.symbols, ["AAPL", "MSFT", "NVDA"]) && harness.fileRead.featured === "AAPL",
        service.symbols + "|" + service.lists[1].count + "|" + JSON.stringify(harness.fileRead))
      harness.check("a symbol already in All is not fetched again for a list",
        harness.calls("NVDA") === nvdaCalls)

      keys.forceActiveFocus()
      keyClick(Qt.Key_Comma)
      wait(100)
      harness.check(", steps back to All", service.listName === "" && harness.same(service.symbols, ["AAPL", "MSFT", "NVDA"]))

      // Only the current list's rows, in the look on screen, are drawn: a
      // row outside the list is not built and derives nothing, the hidden
      // look is not built at all, and a row shown again draws before the
      // first frame that shows it. A switch still rebuilds no row's place.
      // Found in the code-quality review: every row in All, in both looks,
      // repainted with every quote.
      tryVerify(function() { return service.testFeed.firstRun.length + service.testFeed.refreshRun.length === 0 }, 5000)
      var rowsBefore = service.library.map(function(s) { return watchlist.rowItem(s) })
      var sameRows = function() {
        return service.library.every(function(s, i) { return watchlist.rowItem(s) === rowsBefore[i] })
      }
      // Paints per symbol and look, every layer of each line built.
      var paints = {}
      var hooked = []
      var painted = function(symbol, look) { return paints[symbol + "|" + look] || 0 }
      var hookPaints = function(item, key) {
        if (!item || hooked.indexOf(item) >= 0) return
        hooked.push(item)
        if (typeof item.requestPaint === "function")
          item.painted.connect(function() { paints[key] = (paints[key] || 0) + 1 })
        for (var i = 0; i < item.children.length; i++) hookPaints(item.children[i], key)
      }
      var lineOf = function(symbol, look) { return harness.find(watchlist.rowItem(symbol), look === "retro" ? "rowCells" : "rowLine") }
      var hookAll = function() {
        service.library.forEach(function(s) {
          hookPaints(lineOf(s, "smooth"), s + "|smooth")
          hookPaints(lineOf(s, "retro"), s + "|retro")
        })
      }
      hookAll()
      var total = function() { var n = 0; for (var k in paints) n += paints[k]; return n }
      // What the next frame shows of `item`, saved; its path.
      var shoot = function(item, name) {
        var saved = false
        var path = Quickshell.env("STONKS_LISTS_OUT") + "/lists-first-frame-" + name + ".png"
        item.grabToImage(function(result) { saved = result.saveToFile(path) })
        tryVerify(function() { return saved }, 3000, "grab " + name)
        return path
      }
      var sums = function(paths) {
        hashProc.sums = null
        hashProc.command = ["sha1sum"].concat(paths)
        hashProc.running = true
        tryVerify(function() { return hashProc.sums !== null }, 3000, "sha1sum answered")
        return paths.map(function(path) { return hashProc.sums[path] })
      }
      // A symbol's day turned upside down, so an old line reads apart.
      var turnLine = function(symbol) {
        var next = Object.assign({}, service.testFeed.quotes)
        var quote = next[symbol]
        var prices = quote.points.map(function(point) { return point.p })
        var mid = (Math.max.apply(null, prices) + Math.min.apply(null, prices)) / 2
        next[symbol] = Object.assign({}, quote, {
          points: quote.points.map(function(point) { return { t: point.t, p: 2 * mid - point.p } })
        })
        service.testFeed.quotes = next
      }
      var feedQuote = function(symbol, price) {
        var next = Object.assign({}, service.testFeed.quotes)
        next[symbol] = Object.assign({}, next[symbol], { price: price })
        service.testFeed.quotes = next
      }
      var msft = watchlist.rowItem("MSFT")
      var rowsShot = watchlist
      // The list's first frame after `reveal`, as drawn, must be the frame it
      // settles on, and not `stalePath`, the lines it last showed.
      var firstIsNew = function(name, stalePath, reveal) {
        reveal()
        var first = shoot(rowsShot, name + "-first")
        wait(300)
        var settled = shoot(rowsShot, name + "-settled")
        var hashes = sums([stalePath, first, settled])
        return { ok: hashes[1] === hashes[2] && hashes[1] !== hashes[0], settled: settled,
          detail: hashes.map(function(h) { return String(h).slice(0, 8) }).join(" ") }
      }
      var quotesBefore = service.testFeed.quotes
      var smoothOld = shoot(rowsShot, "smooth-old")
      keyClick(Qt.Key_S)
      wait(100)
      var retroOld = shoot(rowsShot, "retro-old")
      keyClick(Qt.Key_S)
      wait(100)
      keyClick(Qt.Key_Period)
      wait(100)
      paints = {}
      hookAll()
      turnLine("MSFT")
      feedQuote("NVDA", 180.25)
      wait(100)
      var retroBuilt = service.library.filter(function(s) { return !!lineOf(s, "retro") })
      harness.check("off the list a row builds no words and derives nothing, its line draws nothing, and the hidden look is built nowhere",
        service.listName === "Growth" && !harness.find(msft, "rowContent") && painted("MSFT", "smooth") === 0
          && msft.view === null && msft.geometry === null
          && painted("NVDA", "smooth") > 0 && retroBuilt.length === 0,
        JSON.stringify(paints) + "|" + (msft.view === null) + "|retro built " + retroBuilt)
      paints = {}
      var switched = firstIsNew("switch", smoothOld, function() { keyClick(Qt.Key_Comma) })
      // MSFT's day was turned while it was off the list: only its line has
      // something new to draw.
      var unchanged = service.library.filter(function(s) { return s !== "MSFT" && !!lineOf(s, "smooth") })
      harness.check("a list switch rebuilds no row's place, a line whose day did not change repaints nothing, and the rows show their new lines in the first frame",
        service.listName === "" && sameRows() && switched.ok && unchanged.length > 0
          && unchanged.every(function(s) { return painted(s, "smooth") === 0 }),
        sameRows() + "|" + switched.detail + "|unchanged " + unchanged + "|" + JSON.stringify(paints))
      var toRetro = firstIsNew("retro", retroOld, function() { keyClick(Qt.Key_S) })
      turnLine("MSFT")
      var toSmooth = firstIsNew("smooth", switched.settled, function() { keyClick(Qt.Key_S) })
      harness.check("s shows the row's current line in its first frame, both ways",
        toRetro.ok && toSmooth.ok && !service.retro, toRetro.detail + " / " + toSmooth.detail)
      // Turned back to the line the switch showed; an open refetches every
      // quote, so the frame to match is that line's, not a later one.
      app.close()
      turnLine("MSFT")
      app.open("{}")
      var reopenFirst = shoot(rowsShot, "reopen-first")
      keys.forceActiveFocus()
      var reopenHashes = sums([toSmooth.settled, reopenFirst, switched.settled])
      harness.check("a window reopened after the line changed shows the new line in its first frame",
        reopenHashes[1] === reopenHashes[2] && reopenHashes[1] !== reopenHashes[0],
        reopenHashes.map(function(h) { return String(h).slice(0, 8) }).join(" "))
      service.testFeed.quotes = quotesBefore
      wait(100)
      hookAll()
      paints = {}
      wait(1100)
      harness.check("a clock tick redraws no line", total() === 0, JSON.stringify(paints))
      keyClick(Qt.Key_C)
      wait(100)
      harness.check("the change mode redraws no line", service.changeMode === "abs" && total() === 0,
        service.changeMode + "|" + JSON.stringify(paints))
      keyClick(Qt.Key_C)
      keyClick(Qt.Key_C)
      wait(50)
      keyClick(Qt.Key_Period)
      wait(100)
      harness.check(". steps forward to Growth", service.listName === "Growth",
        service.listName + "|" + JSON.stringify(service.lists))

      // A switch with the pointer resting on the rows still lays out the new
      // list, which a resort under the pointer would hold back.
      var row = watchlist.rowItem("NVDA")
      mouseMove(row, row.width / 2, row.height / 2)
      wait(50)
      keyClick(Qt.Key_Comma)
      wait(100)
      harness.check("a list switch under the pointer shows the new list's rows",
        watchlist.sortHeld && harness.same(watchlist.displayedSymbols, service.shown)
          && watchlist.contentY === 0,
        watchlist.sortHeld + "|" + watchlist.displayedSymbols + "|" + service.shown + "|" + watchlist.contentY)
      mouseMove(body, body.width / 2, 10)
      keyClick(Qt.Key_Period)
      wait(100)

      keyClick(Qt.Key_O)
      wait(50)
      harness.check("each list keeps its own order",
        service.order === "symbol" && service.dataSettings.order === "manual")
      // The order as the control names it, and as the service keeps it: the
      // arrow says which way the values run down the list.
      var label = harness.find(body, "orderLabel")
      var ring = [label.text]
      for (var i = 0; i < 3; i++) { keyClick(Qt.Key_O); ring.push(service.order, label.text) }
      // No order by the amount: it would rank yen against dollars.
      harness.check("o runs the ring back to manual through % change alone, names each order, and leaves the change mode alone",
        harness.same(ring, ["↑  SYMBOL", "name", "↑  NAME", "pct", "↓  % CHANGE",
          "manual", "↕  MANUAL"]) && service.changeMode === "pct",
        ring + "|" + service.changeMode)

      // Shift+O and a Shift-click on the order word run a sorted order the
      // other way, kept in the list's own entry in the file; manual has no
      // direction, and o starts the next order in its own.
      keyClick("O", Qt.ShiftModifier)
      wait(50)
      var manualStays = !service.reversed && label.text === "↕  MANUAL" && service.order === "manual"
      keyClick(Qt.Key_O)
      wait(50)
      var ahead = watchlist.displayedSymbols.slice()
      keyClick("O", Qt.ShiftModifier)
      wait(50)
      var byKey = [service.reversed, label.text, watchlist.displayedSymbols.join(",")]
      harness.readFile()
      tryVerify(function() { return harness.fileRead !== null }, 3000)
      var growthEntry = (harness.fileRead.lists || []).filter(function(l) { return l.name === "Growth" })[0] || {}
      mouseClick(label, label.width / 2, label.height / 2, Qt.LeftButton, Qt.ShiftModifier)
      wait(50)
      var byClick = [service.reversed, label.text, watchlist.displayedSymbols.join(",")]
      keyClick("O", Qt.ShiftModifier)
      keyClick(Qt.Key_O)
      wait(50)
      var nextOrder = [service.order, service.reversed, label.text]
      for (var back = 0; back < 2; back++) keyClick(Qt.Key_O)
      wait(50)
      harness.check("Shift+O and a Shift-click on the order word reverse a sorted order, kept for the list alone; o and manual have no reversal",
        manualStays && ahead.length === 2
          && harness.same(byKey, [true, "↓  SYMBOL", ahead.slice().reverse().join(",")])
          && growthEntry.order === "symbol" && growthEntry.reversed === true && harness.fileRead.reversed === false
          && harness.same(byClick, [false, "↑  SYMBOL", ahead.join(",")])
          && harness.same(nextOrder, ["name", false, "↑  NAME"]) && service.order === "manual",
        [manualStays, ahead, byKey, JSON.stringify(growthEntry), harness.fileRead.reversed, byClick, nextOrder, service.order].join(" | "))

      // By mouse alone, with no key held: a click on a sorted order's arrow
      // reverses it, kept for the list as Shift+O keeps it, and a click on
      // the word steps to the next; on manual a click on ↕ steps, as the word
      // does. Found reviewing the README for 1.0.0: only a held Shift
      // reversed a sort.
      var clickArrow = function() { mouseClick(label, 3, label.height / 2); wait(50) }
      var clickWord = function() { mouseClick(label, label.width - 3, label.height / 2); wait(50) }
      clickArrow()
      var fromManual = [service.order, service.reversed, label.text]
      var sortedRows = watchlist.displayedSymbols.slice()
      clickArrow()
      var arrowFlip = [service.reversed, label.text, watchlist.displayedSymbols.join(",")]
      harness.readFile()
      tryVerify(function() { return harness.fileRead !== null }, 3000)
      var arrowEntry = (harness.fileRead.lists || []).filter(function(l) { return l.name === "Growth" })[0] || {}
      clickArrow()
      var arrowBack = [service.reversed, label.text, watchlist.displayedSymbols.join(",")]
      clickWord()
      var wordStep = [service.order, service.reversed, label.text]
      clickWord()
      clickWord()
      harness.check("a click on a sorted order's arrow reverses it and a click on its word steps; on manual a click on ↕ steps",
        harness.same(fromManual, ["symbol", false, "↑  SYMBOL"]) && sortedRows.length === 2
          && harness.same(arrowFlip, [true, "↓  SYMBOL", sortedRows.slice().reverse().join(",")])
          && arrowEntry.order === "symbol" && arrowEntry.reversed === true
          && harness.same(arrowBack, [false, "↑  SYMBOL", sortedRows.join(",")])
          && harness.same(wordStep, ["name", false, "↑  NAME"]) && service.order === "manual",
        [fromManual, sortedRows, arrowFlip, JSON.stringify(arrowEntry), arrowBack, wordStep, service.order].join(" | "))

      watchlist.cursorSymbol = "AAPL"
      keyClick(Qt.Key_X)
      wait(100)
      harness.check("x on a named list removes that membership only, and the hero stays",
        harness.same(service.symbols, ["NVDA"]) && service.library.indexOf("AAPL") >= 0
          && service.featuredSymbol === "AAPL")
      harness.check("with the hero outside the list, the cursor sits on the first row",
        watchlist.cursorRow === "NVDA")
      keyClick(Qt.Key_X)
      wait(100)
      var empty = body.children.filter(function(child) { return child.objectName === "emptyList" })[0]
      harness.check("a named list may empty, and says so, with no refusal",
        service.symbols.length === 0 && body.note === "Removed NVDA from Growth" && empty.visible
          && empty.text === "No symbols in Growth yet"
          && body.wholeListHeight === watchlist.rowHeight,
        service.symbols.length + "|" + body.note + "|" + empty.visible + "|" + empty.text + "|" + body.wholeListHeight + "|" + watchlist.rowHeight)

      service.addSymbol("MSFT")
      wait(50)
      keyClick(Qt.Key_Comma)
      wait(100)
      watchlist.cursorSymbol = "MSFT"
      keyClick(Qt.Key_X)
      wait(100)
      var growth = service.dataSettings.lists[0]
      harness.check("x on All removes the symbol from every list",
        harness.same(service.library, ["AAPL", "NVDA"]) && harness.same(growth.symbols, []))
      // A removal is instant and needs no confirm, so it can be taken back:
      // the footer names what went, and u puts it back where it was.
      harness.check("the footer names the removed symbol and offers undo by click",
        body.note === "Removed MSFT" && harness.find(body, "footerAction").text === " · click to undo",
        body.note + "|" + harness.find(body, "footerAction").text)
      keyClick(Qt.Key_U)
      // It used to slide down from above the list, over every row between.
      // Read on its first frame part way into the fade.
      var back = watchlist.rowItem("MSFT")
      var firstFrame = null
      var readFade = function() {
        if (firstFrame === null && back.opacity > 0 && back.opacity < 1)
          firstFrame = { visible: back.visible, y: back.y, opacity: back.opacity }
      }
      back.opacityChanged.connect(readFade)
      within(2000, function() { return firstFrame !== null })
      back.opacityChanged.disconnect(readFade)
      harness.check("the returned row starts at its own place and fades in",
        !!firstFrame && firstFrame.visible && firstFrame.y === watchlist.rowPitch,
        firstFrame ? JSON.stringify(firstFrame) : "no frame part way into a fade")
      wait(80)
      harness.check("u puts it back in its place in All and in every list it was in",
        harness.same(service.library, ["AAPL", "MSFT", "NVDA"])
          && harness.same(service.dataSettings.lists[0].symbols, ["MSFT"]) && body.note === "",
        service.library + "|" + service.dataSettings.lists[0].symbols + "|" + body.note)
      wait(200)
      // A row that passes others rides on top, on the window's own ground,
      // so their text never shows through it.
      // Read on a frame part way along the slide.
      var climber = watchlist.rowItem("NVDA")
      var riding = null
      var readRide = function() {
        if (riding !== null || climber.shift === 0 || Math.abs(climber.shift) >= 2 * watchlist.rowPitch) return
        var ground = harness.find(climber, "rowGround")
        riding = {
          over: climber.z > watchlist.rowItem("AAPL").z && climber.z > watchlist.rowItem("MSFT").z,
          ground: ground !== null && ground.visible && ground.color.a === 1,
          detail: climber.z + "|" + watchlist.rowItem("AAPL").z + "|" + (ground ? ground.visible + "|" + ground.color : "no ground")
        }
      }
      climber.shiftChanged.connect(readRide)
      service.setManualOrder(["NVDA", "AAPL", "MSFT"])
      within(2000, function() { return riding !== null })
      climber.shiftChanged.disconnect(readRide)
      harness.check("a row passing two others rides over them on the window's ground",
        !!riding && riding.over && riding.ground, riding ? riding.detail : "no frame part way along a slide")
      wait(200)
      harness.check("once still, no row carries a ground",
        !harness.find(climber, "rowGround").visible && climber.z === 0)
      service.setManualOrder(["AAPL", "MSFT", "NVDA"])
      wait(200)
      watchlist.cursorSymbol = "MSFT"
      keyClick(Qt.Key_X)
      wait(100)

      keyClick(Qt.Key_W)
      wait(50)
      keyClick(Qt.Key_Down)
      keyClick(Qt.Key_Down)
      keyClick(Qt.Key_Return)
      wait(50)
      keyClick(Qt.Key_Return)
      harness.check("an empty name is refused, and the menu asks for one",
        body.listMenuOpen && menu.naming && menu.problem === "Name the list", menu.problem)
      typeText(" growth ")
      keyClick(Qt.Key_Return)
      wait(50)
      harness.check("a taken name is refused whatever its case and padding, and the menu stays open",
        body.listMenuOpen && menu.naming && menu.problem === "growth already exists"
          && service.dataSettings.lists.length === 1)
      keyClick(Qt.Key_Escape)
      wait(20)
      harness.check("Escape leaves the name field for the menu", body.listMenuOpen && !menu.naming && menu.activeFocus,
        body.listMenuOpen + "|" + menu.naming + "|" + menu.activeFocus + "|" + app.testKeyCatcher.activeFocus)
      keyClick(Qt.Key_2)
      wait(100)
      harness.check("a number key in the menu picks that list",
        !body.listMenuOpen && service.listName === "Growth",
        body.listMenuOpen + "|" + service.listName)

      // Found live: once the menu closed, the window took no keys at all.
      keyClick(Qt.Key_Period)
      wait(100)
      harness.check("keys work again after a list is picked from the menu", service.listName === "",
        service.listName)
      var beforeEscape = service.listName
      keyClick(Qt.Key_W)
      wait(50)
      keyClick(Qt.Key_Escape)
      wait(100)
      keyClick(Qt.Key_Comma)
      wait(100)
      harness.check("keys work again after Escape closes the menu",
        !body.listMenuOpen && service.listName === "Growth", beforeEscape + " -> " + service.listName)

      harness.readFile()
      tryVerify(function() { return harness.fileRead !== null }, 3000)
      harness.check("the file keeps All in the version-1 keys and adds the lists",
        harness.same(harness.fileRead.symbols, ["AAPL", "NVDA"]) && harness.fileRead.list === "Growth"
          && harness.fileRead.lists.length === 1 && harness.fileRead.lists[0].name === "Growth",
        JSON.stringify(harness.fileRead))

      var again = serviceAgain.createObject(harness)
      tryVerify(function() { return again.pluginsReady }, 5000)
      harness.check("a restarted service comes back on the same list and library",
        again.listName === "Growth" && again.lists.length === 2
          && harness.same(again.library, ["AAPL", "NVDA"]) && again.symbols.length === 0,
        again.listName + "|" + again.lists.length + "|" + again.library + "|" + again.symbols)
      again.destroy()

      // The pointer: the same flows by hand, with an image at each state.
      var body2 = app.testBody
      var wl = body2.watchlist
      mouseMove(body2, 5, body2.height - 2)
      wait(50)
      grab("empty")
      var control = harness.find(body2, "listControl")
      var at = center(control)
      mouseMove(body2, at.x, at.y)
      wait(260)
      harness.check("the list name takes the hover fill", !Qt.colorEqual(control.color, "transparent"))
      mouseClick(body2, at.x, at.y)
      wait(100)
      harness.check("a click on the list name opens the menu", body2.listMenuOpen)
      grab("menu")
      // One cursor, as on the rows: the pointer puts it on the list under
      // it, a key moves it on from there, and the pointer leaving the menu
      // leaves it. One mark, the rows' bar and fill, and only on that row.
      // It used to keep the keyboard's choice and tint the pointer's row.
      var choices = harness.findAll(body2, "listChoice")
      var menuRows = choices.concat([harness.find(body2, "newListRow"), harness.find(body2, "manageListsRow")])
      var opened = menu.cursor + " " + marks(menuRows)
      var allAt = center(choices[0])
      // The pointer comes in as a hand's does, over more than one place: the
      // first place it is seen at in the menu is where it starts.
      mouseMove(body2, allAt.x, allAt.y - 6)
      mouseMove(body2, allAt.x, allAt.y)
      wait(100)
      grab("menu-hover")
      var pointed = menu.cursor + " " + marks(menuRows)
      keyClick(Qt.Key_Down)
      wait(100)
      var keyed = menu.cursor + " " + marks(menuRows)
      mouseMove(body2, 5, body2.height - 2)
      wait(100)
      var left = menu.cursor + " " + marks(menuRows)
      harness.check("in the list menu the pointer puts the one cursor on the list under it, a key moves it on, and leaving keeps it",
        opened === "1 ,bar+fill,," && pointed === "0 bar+fill,,," && keyed === "1 ,bar+fill,," && left === keyed,
        [opened, pointed, keyed, left].join(" | "))
      mouseClick(body2, allAt.x, allAt.y)
      wait(150)
      harness.check("a click on a list switches to it and closes the menu",
        service.listName === "" && !body2.listMenuOpen)
      mouseMove(body2, 5, body2.height - 2)

      mouseClick(body2, at.x, at.y)
      wait(100)
      var newRow = harness.find(body2, "newListRow")
      var newAt = center(newRow)
      mouseClick(body2, newAt.x, newAt.y)
      wait(100)
      harness.check("a click on New list… opens the name field", menu.naming)
      typeText(" Wins ")
      wait(50)
      grab("naming")
      // MAKE does what Enter does in the field, and is marked as the button
      // Enter takes. Found by the owner on 14 October: the field said "⏎ to
      // make it", and nothing a mouse could press made the list.
      var makeAt = center(harness.find(menu, "makeList"))
      mouseClick(body2, makeAt.x, makeAt.y)
      wait(150)
      harness.check("a click on MAKE makes the list and opens search to fill it, and MAKE is marked for Enter",
        service.listName === "Wins" && !body2.listMenuOpen && body2.adding && harness.find(menu, "makeList").enterTakes,
        service.listName + "|" + body2.adding)
      grab("search-empty-list")
      keyClick(Qt.Key_Escape)
      wait(100)
      harness.check("Escape leaves search on the new, empty list, its name trimmed",
        !body2.adding && service.listName === "Wins" && service.symbols.length === 0)

      // A click off the open menu closes it and does nothing else; the
      // pointer resting there does nothing either (found live: it scrubbed).
      mouseClick(body2, at.x, at.y)
      wait(100)
      var chart = body2.chartItem
      var chartAt = center(chart)
      mouseMove(body2, chartAt.x, chartAt.y)
      wait(100)
      harness.check("the pointer over the chart does not scrub while the menu is open",
        body2.listMenuOpen && body2.scrubT === 0)
      var rangeBefore = app.range
      mouseClick(body2, chartAt.x, chartAt.y)
      wait(100)
      harness.check("a click off the menu closes it and reaches nothing under it",
        !body2.listMenuOpen && app.range === rangeBefore && service.listName === "Wins")
      mouseMove(body2, 5, body2.height - 2)
      wait(50)

      mouseClick(body2, at.x, at.y)
      wait(100)
      mouseClick(body2, at.x, at.y)
      wait(100)
      harness.check("a second click on the list name closes the menu", !body2.listMenuOpen)

      mouseClick(body2, at.x, at.y)
      wait(100)
      // Wins pushed "New list…" down a row.
      newAt = center(harness.find(body2, "newListRow"))
      mouseClick(body2, newAt.x, newAt.y)
      wait(100)
      typeText("all")
      keyClick(Qt.Key_Return)
      wait(100)
      harness.check("All is refused as a name, and the menu says why",
        body2.listMenuOpen && menu.problem === "All already exists",
        body2.listMenuOpen + "|" + menu.naming + "|" + menu.problem + "|" + service.listName + "|" + JSON.stringify(service.lists))
      grab("refused")
      keyClick(Qt.Key_Escape)
      keyClick(Qt.Key_Escape)
      wait(100)
      harness.check("Escape twice leaves the name field, then the menu", !body2.listMenuOpen)

      // A click away from the name field keeps what was typed, as Enter
      // does: on a list in the menu, which is not switched to, and off
      // the menu. Found in the mouse-only audit (14 October, 4): a click
      // away threw the typing away without a word.
      var nameThenClick = function(name, place) {
        mouseClick(body2, at.x, at.y)
        wait(100)
        newAt = center(harness.find(body2, "newListRow"))
        mouseClick(body2, newAt.x, newAt.y)
        wait(100)
        typeText(name)
        wait(50)
        var p = place()
        mouseClick(body2, p.x, p.y)
        wait(150)
        var kept = [service.listName, !body2.listMenuOpen, body2.adding].join(",")
        keyClick(Qt.Key_Escape)
        wait(100)
        return kept
      }
      var onRow = nameThenClick("Later", function() { return center(harness.findAll(menu, "listChoice")[0]) })
      var offMenu = nameThenClick("Later2", function() { return chartAt })
      harness.check("a click away from a new list's name makes it, on a list in the menu or off the menu",
        onRow === "Later,true,true" && offMenu === "Later2,true,true", onRow + " | " + offMenu)
      service.switchList("Wins")
      service.deleteList("Later")
      service.deleteList("Later2")
      wait(100)

      service.addSymbol("AAPL")
      service.addSymbol("NVDA")
      wait(150)
      var nvdaRow = wl.rowItem("NVDA")
      mouseClick(nvdaRow, nvdaRow.width / 2, nvdaRow.height / 2)
      wait(150)
      harness.check("a click on a row of a named list features it", service.featuredSymbol === "NVDA")
      grab("named")

      // A view that opens under a resting pointer keeps the cursor it opens
      // on until the pointer really moves, so Enter or Space acts on that
      // row, never on the one the pointer happens to rest on. From the
      // review of #9: the first hover at the resting pointer counted as a
      // move, put a symbol's lists on All, and Space removed the symbol from
      // every list. Growth and Wins, Wins current.
      // A symbol's lists, opened by m with the pointer resting on a row that
      // All's tick will lie under: Space ticks the first named list, as the
      // view opened.
      var listsAll = harness.findAll(body2, "symbolListRow")[0]
      var allTop = listsAll.mapToItem(body2, 0, 0).y
      var spot = null
      var spotSymbol = ""
      ;["AAPL", "NVDA"].forEach(function(symbol) {
        var row = wl.rowItem(symbol)
        var top = Math.max(allTop, row.mapToItem(body2, 0, 0).y)
        var bottom = Math.min(allTop + listsAll.height, row.mapToItem(body2, 0, row.height).y)
        if (spot || bottom - top < 4) return
        spot = Qt.point(row.mapToItem(body2, row.width / 2, 0).x, (top + bottom) / 2)
        spotSymbol = symbol
      })
      // The pointer comes to the row by moving, as a hand's does.
      mouseMove(body2, spot.x, spot.y - 6)
      mouseMove(body2, spot.x, spot.y)
      wait(50)
      keys.forceActiveFocus()
      keyClick(Qt.Key_M)
      wait(150)
      // The compositor reports the resting pointer again, a pixel off: still
      // no move. From Grok's review of #19: a list view's pointer had never
      // seen the pointer, so that report moved its cursor onto All.
      mouseMove(body2, spot.x, spot.y + 1)
      wait(50)
      var growth = function() {
        return service.dataSettings.lists.filter(function(l) { return l.name === "Growth" })[0].symbols
      }
      var checklistView = harness.find(body2, "symbolLists")
      var allUnder = listsAll.contains(listsAll.mapFromItem(body2, spot.x, spot.y))
      var listsOpenedOn = checklistView.cursor
      keyClick(Qt.Key_Space)
      wait(100)
      var spaced = [allUnder, listsOpenedOn === 1, service.library.indexOf(spotSymbol) >= 0,
        body2.listsSymbol === spotSymbol, growth().indexOf(spotSymbol) >= 0].join(",")
      keyClick(Qt.Key_Space)
      wait(100)
      keyClick(Qt.Key_Escape)
      wait(100)
      // The list menu, opened by its key with the pointer resting on All:
      // Enter takes the current list.
      // Off the middle, where the pointer rested the last time the menu was
      // open, so this is a new place to its pointer.
      var menuAllAt = center(harness.findAll(body2, "listChoice")[0])
      menuAllAt.x += 20
      mouseMove(body2, menuAllAt.x, menuAllAt.y)
      wait(50)
      keys.forceActiveFocus()
      keyClick(Qt.Key_W)
      wait(100)
      mouseMove(body2, menuAllAt.x, menuAllAt.y + 1)
      wait(50)
      var menuOpenedOn = menu.cursor
      keyClick(Qt.Key_Return)
      wait(100)
      var entered = [menuOpenedOn === 2, service.listName === "Wins", !body2.listMenuOpen].join(",")
      // Manage lists, opened by its key with the pointer resting on All:
      // Enter renames the first named list.
      var manageView = harness.find(body2, "manageLists")
      var manageAllAt = center(harness.findAll(body2, "manageRow")[0])
      mouseMove(body2, manageAllAt.x, manageAllAt.y)
      wait(50)
      keys.forceActiveFocus()
      keyClick("W", Qt.ShiftModifier)
      wait(100)
      mouseMove(body2, manageAllAt.x, manageAllAt.y + 1)
      wait(50)
      var manageOpenedOn = manageView.cursor
      keyClick(Qt.Key_Return)
      wait(50)
      var renamed = [manageOpenedOn === 1, manageView.renaming && manageView.cursor === 1].join(",")
      keyClick(Qt.Key_Escape)
      keyClick(Qt.Key_Escape)
      wait(100)
      harness.check("a view opening under a resting pointer keeps the cursor it opens on: a symbol's lists over All, the list menu, and Manage lists",
        spaced === "true,true,true,true,true" && entered === "true,true,true" && renamed === "true,true" && !body2.managingLists,
        [spaced, entered, renamed, body2.managingLists].join(" | "))

      // A double-click is one click, Ctrl-click's too: the lists it opens
      // under the pointer take no click within the double-click interval, so
      // a Ctrl-double-click, or a click at once after a Ctrl-click, never
      // unticks All under it. From rows-review: either removed the symbol
      // from every list.
      var ctrlThen = function(second) {
        second()
        wait(150)
        var kept = [body2.listsSymbol === spotSymbol, service.library.indexOf(spotSymbol) >= 0,
          harness.same(service.symbols, ["AAPL", "NVDA"])].join(",")
        keyClick(Qt.Key_Escape)
        wait(100)
        return kept
      }
      var ctrlDouble = ctrlThen(function() {
        mouseDoubleClickSequence(body2, spot.x, spot.y, Qt.LeftButton, Qt.ControlModifier)
      })
      // Past the double-click interval of the last click at this place:
      // another click there within it would be the same click.
      wait(Application.styleHints.mouseDoubleClickInterval)
      var ctrlThenClick = ctrlThen(function() {
        mouseClick(body2, spot.x, spot.y, Qt.LeftButton, Qt.ControlModifier)
        mouseClick(body2, spot.x, spot.y)
      })
      harness.check("a Ctrl-double-click, or a click at once after a Ctrl-click, over All's tick leaves the symbol in All",
        ctrlDouble === "true,true,true" && ctrlThenClick === "true,true,true", ctrlDouble + " | " + ctrlThenClick)

      wait(Application.styleHints.mouseDoubleClickInterval)
      var aaplRow = wl.rowItem("AAPL")
      mouseClick(aaplRow, aaplRow.width / 2, aaplRow.height / 2, Qt.RightButton)
      wait(150)
      harness.check("right-clicking a row on a named list takes it out of that list only",
        harness.same(service.symbols, ["NVDA"]) && service.library.indexOf("AAPL") >= 0)

      // Manage lists by keyboard: Growth and Wins, Wins current.
      var names = function() { return service.dataSettings.lists.map(function(l) { return l.name }) }
      var manage = harness.find(body2, "manageLists")
      keys.forceActiveFocus()
      keyClick("W", Qt.ShiftModifier)
      wait(100)
      harness.check("W opens Manage lists in the rows' place, on the first named list",
        body2.managingLists && manage.visible && manage.activeFocus && manage.cursor === 1
          && !wl.visible && !harness.find(body2, "footer").visible,
        body2.managingLists + "|" + manage.activeFocus + "|" + manage.cursor)
      grab("manage")
      keyClick(Qt.Key_Return)
      wait(50)
      typeText("wins")
      keyClick(Qt.Key_Return)
      wait(50)
      harness.check("a rename to a taken name is refused under the field",
        manage.renaming && manage.problem === "wins already exists" && harness.same(names(), ["Growth", "Wins"]),
        manage.renaming + "|" + manage.problem + "|" + names())
      keyClick(Qt.Key_Escape)
      wait(50)
      harness.check("Escape leaves the field and keeps the name",
        !manage.renaming && body2.managingLists && manage.activeFocus && harness.same(names(), ["Growth", "Wins"]))
      keyClick(Qt.Key_Return)
      wait(50)
      typeText("GROWTH")
      keyClick(Qt.Key_Return)
      wait(100)
      harness.check("a change of case alone renames",
        !manage.renaming && harness.same(names(), ["GROWTH", "Wins"]), names())
      keyClick("J", Qt.ShiftModifier)
      wait(100)
      harness.check("J moves the list down, and the cursor goes with it",
        harness.same(names(), ["Wins", "GROWTH"]) && manage.cursor === 2, names() + "|" + manage.cursor)
      keyClick(Qt.Key_X)
      wait(50)
      harness.check("x asks before deleting", manage.confirming && harness.same(names(), ["Wins", "GROWTH"]))
      keyClick(Qt.Key_Escape)
      wait(50)
      harness.check("Escape keeps the list and the view",
        !manage.confirming && body2.managingLists && harness.same(names(), ["Wins", "GROWTH"]))
      keyClick(Qt.Key_K)
      keyClick(Qt.Key_X)
      wait(50)
      grab("manage-confirm")
      keyClick(Qt.Key_Return)
      wait(100)
      harness.check("deleting the current list switches to All and leaves All untouched",
        harness.same(names(), ["GROWTH"]) && service.listName === ""
          && harness.same(service.library, ["AAPL", "NVDA"]),
        names() + "|" + service.listName + "|" + service.library)
      keyClick(Qt.Key_K)
      keyClick(Qt.Key_Return)
      keyClick("J", Qt.ShiftModifier)
      keyClick(Qt.Key_X)
      wait(50)
      harness.check("All cannot be renamed, moved, or deleted",
        manage.cursor === 0 && !manage.renaming && !manage.confirming && harness.same(names(), ["GROWTH"]))
      keyClick(Qt.Key_Escape)
      wait(100)
      keyClick(Qt.Key_Period)
      wait(100)
      harness.check("Escape closes Manage lists and the keys come back",
        !body2.managingLists && wl.visible && service.listName === "GROWTH", service.listName)
      keyClick(Qt.Key_Comma)
      wait(100)

      // Manage lists by hand, from the menu.
      service.createList("Wins")
      wait(100)
      mouseClick(body2, at.x, at.y)
      wait(100)
      var manageAt = center(harness.find(body2, "manageListsRow"))
      mouseClick(body2, manageAt.x, manageAt.y)
      wait(100)
      harness.check("Manage lists… in the menu opens the view", body2.managingLists && !body2.listMenuOpen)
      var manageRows = harness.findAll(body2, "manageRow")
      var winsRow = manageRows[2]
      var winsAt = center(winsRow)
      mouseMove(body2, winsAt.x, winsAt.y)
      wait(100)
      harness.check("in Manage lists the pointer puts the one cursor, with the rows' mark, on the list under it",
        manage.cursor === 2 && marks(manageRows) === ",,bar+fill", manage.cursor + " " + marks(manageRows))
      // The pointer travels to the control it clicks, as a hand's does.
      var upAt = center(harness.find(winsRow, "moveUp"))
      mouseMove(body2, upAt.x, upAt.y)
      mouseClick(body2, upAt.x, upAt.y)
      wait(100)
      harness.check("↑ on a hovered row moves that list up", harness.same(names(), ["Wins", "GROWTH"]), names())
      var growthRow = harness.findAll(body2, "manageRow")[2]
      var growthAt = center(growthRow)
      mouseMove(body2, growthAt.x, growthAt.y)
      wait(50)
      var renameAt = center(harness.find(growthRow, "renameAction"))
      mouseClick(body2, renameAt.x, renameAt.y)
      wait(100)
      typeText("Nope")
      // The rename's own SAVE and CANCEL do what Enter and Escape do in its
      // field; SAVE, which Enter takes, is the one marked. Found by the owner
      // on 14 October: "esc cancel" was words under the rows, and a rename
      // could not be saved by mouse.
      var renaming = [manage.renaming, harness.find(manage, "saveName").enterTakes, harness.find(manage, "cancelRename").enterTakes].join(",")
      var cancelAt = center(harness.find(manage, "cancelRename"))
      mouseClick(body2, cancelAt.x, cancelAt.y)
      wait(100)
      harness.check("CANCEL leaves the field and keeps the name, and SAVE is the button marked for Enter",
        renaming === "true,true,false" && !manage.renaming && harness.same(names(), ["Wins", "GROWTH"]),
        renaming + "|" + manage.renaming + "|" + names())
      // A click away from the field, anywhere in the view, keeps what was
      // typed, as Enter does. Found in the mouse-only audit (14 October, 4):
      // it, and DONE, threw the typed name away without a word.
      mouseClick(body2, renameAt.x, renameAt.y)
      wait(100)
      typeText("Pow")
      var awayAt = center(harness.findAll(body2, "manageRow")[1])
      mouseClick(body2, awayAt.x, awayAt.y)
      wait(100)
      harness.check("a click away from the field keeps the typed name",
        harness.same(names(), ["Wins", "Pow"]) && !manage.renaming, names() + "|" + manage.renaming)
      mouseMove(body2, growthAt.x, growthAt.y)
      wait(50)
      mouseClick(body2, renameAt.x, renameAt.y)
      wait(100)
      typeText("Power")
      var saveAt = center(harness.find(manage, "saveName"))
      mouseClick(body2, saveAt.x, saveAt.y)
      wait(100)
      harness.check("RENAME opens the field on that row, and SAVE saves",
        harness.same(names(), ["Wins", "Power"]) && !manage.renaming, names())
      var winsRowNow = harness.findAll(body2, "manageRow")[1]
      var winsNowAt = center(winsRowNow)
      mouseMove(body2, winsNowAt.x, winsNowAt.y)
      wait(50)
      var deleteAt = center(harness.find(winsRowNow, "deleteAction"))
      mouseClick(body2, deleteAt.x, deleteAt.y)
      wait(50)
      // The question's DELETE, which Enter takes, is marked; CANCEL,
      // Escape's, is not, and is called Cancel, as every way out is. Found
      // in the polish board: a line under the rows repeated "⏎ delete · esc
      // keep"; the owner's call of 15 October: the way out is Cancel.
      var cancelButton = harness.find(winsRowNow, "cancelDelete")
      var asked = [harness.find(winsRowNow, "confirmDelete").visible && harness.find(winsRowNow, "confirmDelete").enterTakes,
        !!cancelButton && cancelButton.visible && !cancelButton.enterTakes && cancelButton.text === "CANCEL"].join(",")
      harness.check("deleting asks on the row's own choices, DELETE marked as the button Enter takes, the way out called CANCEL",
        asked === "true,true", asked)
      var powerRowAt = center(harness.findAll(body2, "manageRow")[2])
      mouseMove(body2, powerRowAt.x, powerRowAt.y)
      wait(50)
      harness.check("the delete question stays on its list as the pointer passes another",
        manage.confirming && manage.cursor === 1, manage.confirming + "|" + manage.cursor)
      var cancelAt = center(cancelButton || harness.find(winsRowNow, "keepList"))
      mouseClick(body2, cancelAt.x, cancelAt.y)
      wait(50)
      harness.check("DELETE asks, and CANCEL keeps the list", !manage.confirming && harness.same(names(), ["Wins", "Power"]))
      // A double-click on DELETE asks, and never answers its own question:
      // the second click lands where the question's DELETE now sits. Found
      // in the 1.0.0 review: a quick double-click on DELETE's first letters
      // deleted the list without asking. Escape takes the question back.
      mouseMove(body2, winsNowAt.x, winsNowAt.y)
      wait(50)
      var deleteAction = harness.find(winsRowNow, "deleteAction")
      var deleteFirst = deleteAction.mapToItem(body2, 3, deleteAction.height / 2)
      var confirmAction = harness.find(winsRowNow, "confirmDelete")
      mouseDoubleClickSequence(body2, deleteFirst.x, deleteFirst.y)
      wait(50)
      var confirmUnder = false
      try { confirmUnder = confirmAction.contains(confirmAction.mapFromItem(body2, deleteFirst.x, deleteFirst.y)) } catch (e) {}
      var afterDouble = [confirmUnder, manage.confirming, names().join(",")].join("|")
      keyClick(Qt.Key_Escape)
      wait(50)
      harness.check("a double-click on DELETE, its second click on the question's DELETE, asks and deletes nothing; Escape takes the question back",
        afterDouble === "true|true|Wins,Power" && !manage.confirming && harness.same(names(), ["Wins", "Power"]),
        afterDouble + " then " + manage.confirming)
      // A second press inside the interval, held until after it ends, is
      // still that double-click's: Qt counts a double-click from the presses,
      // and its release answers nothing. Found in the stand-in review of #17:
      // the guard was read on release, so this release deleted the list.
      var interval = Application.styleHints.mouseDoubleClickInterval
      wait(interval + 50)
      mouseMove(body2, winsNowAt.x, winsNowAt.y)
      wait(50)
      mouseClick(body2, deleteFirst.x, deleteFirst.y)
      wait(interval - 150)
      mousePress(body2, deleteFirst.x, deleteFirst.y)
      wait(250)
      mouseRelease(body2, deleteFirst.x, deleteFirst.y)
      wait(50)
      var afterHeld = [manage.confirming, names().join(",")].join("|")
      keyClick(Qt.Key_Escape)
      wait(50)
      harness.check("a second press on the question's DELETE inside the double-click interval, released after it, deletes nothing",
        afterHeld === "true|Wins,Power" && !manage.confirming && harness.same(names(), ["Wins", "Power"]),
        afterHeld + " then " + manage.confirming + "|" + names())
      wait(Application.styleHints.mouseDoubleClickInterval)
      mouseMove(body2, winsNowAt.x, winsNowAt.y)
      wait(50)
      mouseClick(body2, deleteAt.x, deleteAt.y)
      // The answer is a click of its own, after the double-click interval.
      wait(Application.styleHints.mouseDoubleClickInterval + 50)
      var confirmAt = center(harness.find(winsRowNow, "confirmDelete"))
      mouseClick(body2, confirmAt.x, confirmAt.y)
      wait(100)
      harness.check("the confirmed DELETE removes the current list and goes to All",
        harness.same(names(), ["Power"]) && service.listName === "", names() + "|" + service.listName)
      // DONE over a rename keeps the typed name, then closes.
      var powerOnly = harness.findAll(body2, "manageRow")[1]
      var powerOnlyAt = center(powerOnly)
      mouseMove(body2, powerOnlyAt.x, powerOnlyAt.y)
      wait(50)
      var renameOnlyAt = center(harness.find(powerOnly, "renameAction"))
      mouseClick(body2, renameOnlyAt.x, renameOnlyAt.y)
      wait(100)
      typeText("Powr")
      var doneAt = center(harness.find(body2, "manageDone"))
      mouseClick(body2, doneAt.x, doneAt.y)
      wait(100)
      harness.check("DONE over a rename keeps the typed name and closes Manage lists",
        !body2.managingLists && wl.visible && harness.same(names(), ["Powr"]), body2.managingLists + "|" + names())
      service.renameList("Powr", "Power")
      wait(50)
      // A click on the header's ? keeps a rename being typed, as DONE does,
      // and a refused one keeps the view, saying why. Found in the branch's
      // review: the ? opened the sheet and the typing was lost.
      var renameThenHelp = function(typed) {
        body2.openManageLists()
        wait(100)
        var row = harness.findAll(body2, "manageRow")[1]
        var rowAt = center(row)
        mouseMove(body2, rowAt.x, rowAt.y)
        wait(50)
        var renameRowAt = center(harness.find(row, "renameAction"))
        mouseClick(body2, renameRowAt.x, renameRowAt.y)
        wait(100)
        typeText(typed)
        var help = center(harness.find(body2, "helpMark"))
        mouseClick(body2, help.x, help.y)
        wait(100)
        return [body2.showingHelp, body2.managingLists, manage.renaming, manage.problem !== "", names().join("/")].join(",")
      }
      var helpKeeps = renameThenHelp("Pwr")
      body2.showingHelp = false
      wait(Qt.styleHints.mouseDoubleClickInterval)
      var helpRefused = renameThenHelp("all")
      keyClick(Qt.Key_Escape)
      wait(50)
      body2.closeListViews()
      wait(50)
      harness.check("a click on ? keeps a rename being typed, and a refused one keeps the view saying why",
        helpKeeps === "true,false,false,false,Pwr" && helpRefused === "false,true,true,true,Pwr", helpKeeps + " | " + helpRefused)
      service.renameList("Pwr", "Power")
      wait(50)

      // A symbol's lists: m on the cursor row, then Ctrl-click.
      var checklist = harness.find(body2, "symbolLists")
      var power = function() { return service.dataSettings.lists[0].symbols }
      keys.forceActiveFocus()
      wl.cursorSymbol = "NVDA"
      keyClick(Qt.Key_M)
      wait(100)
      harness.check("m opens the cursor row's lists on the first named list",
        body2.listsSymbol === "NVDA" && checklist.visible && checklist.activeFocus && checklist.cursor === 1
          && !wl.visible)
      keyClick(Qt.Key_Return)
      wait(100)
      harness.check("Enter ticks a list, which gains the symbol", harness.same(power(), ["NVDA"]), power())
      grab("symbol-lists")
      keyClick(Qt.Key_2)
      wait(100)
      harness.check("a number key unticks that list, and All keeps the symbol",
        harness.same(power(), []) && harness.same(service.library, ["AAPL", "NVDA"]), power())
      keyClick(Qt.Key_Space)
      wait(100)
      keyClick(Qt.Key_Escape)
      wait(100)
      keyClick(Qt.Key_Period)
      wait(100)
      harness.check("Escape closes the checklist and the keys come back",
        body2.listsSymbol === "" && harness.same(power(), ["NVDA"]) && service.listName === "Power")
      keyClick(Qt.Key_Comma)
      wait(100)

      var aaplRowAgain = wl.rowItem("AAPL")
      mouseClick(aaplRowAgain, aaplRowAgain.width / 2, aaplRowAgain.height / 2, Qt.LeftButton, Qt.ControlModifier)
      wait(100)
      harness.check("Ctrl-click opens that row's lists without featuring it",
        body2.listsSymbol === "AAPL" && service.featuredSymbol === "NVDA", body2.listsSymbol + "|" + service.featuredSymbol)
      var listRows = harness.findAll(body2, "symbolListRow")
      var listsAllAt = center(listRows[0])
      mouseMove(body2, listsAllAt.x, listsAllAt.y)
      wait(100)
      var listsPointed = checklist.cursor + " " + marks(listRows)
      keyClick(Qt.Key_Down)
      wait(100)
      harness.check("in a symbol's lists the pointer puts the one cursor, with the rows' mark, on the list under it, and a key moves it on",
        listsPointed === "0 bar+fill," && checklist.cursor === 1 && marks(listRows) === ",bar+fill",
        listsPointed + " | " + checklist.cursor + " " + marks(listRows))
      var powerAt = center(listRows[1])
      mouseMove(body2, powerAt.x, powerAt.y)
      // Past the double-click interval of the Ctrl-click that opened them.
      wait(Application.styleHints.mouseDoubleClickInterval + 50)
      mouseClick(body2, powerAt.x, powerAt.y)
      wait(100)
      harness.check("a click ticks that row's list", harness.same(power(), ["NVDA", "AAPL"]), power())
      keyClick(Qt.Key_1)
      wait(100)
      harness.check("unticking All removes the symbol everywhere and closes the checklist",
        harness.same(service.library, ["NVDA"]) && harness.same(power(), ["NVDA"]) && body2.listsSymbol === "",
        service.library + "|" + power() + "|" + body2.listsSymbol)
      harness.check("unticking All names the symbol in the footer, like any removal",
        body2.note === "Removed AAPL", body2.note)
      var noteAt = center(harness.find(body2, "footer"))
      mouseClick(body2, noteAt.x, noteAt.y)
      wait(100)
      harness.check("a click on the note undoes it, and does not open search",
        harness.same(service.library, ["AAPL", "NVDA"]) && harness.same(power(), ["NVDA", "AAPL"])
          && !body2.adding && body2.note === "",
        service.library + "|" + power() + "|" + body2.adding + "|" + body2.note)
      service.removeSymbol("AAPL")
      wait(100)

      // Undo puts back what the removal took and nothing more: a hero chosen
      // after a removal from a named list stays chosen.
      service.switchList("Power")
      service.addSymbol("AAPL")
      wait(100)
      keys.forceActiveFocus()
      wl.cursorSymbol = "AAPL"
      keyClick(Qt.Key_X)
      wait(100)
      service.feature("NVDA")
      wait(50)
      keyClick(Qt.Key_U)
      wait(100)
      harness.check("undo restores the membership and leaves a hero chosen since",
        harness.same(power(), ["NVDA", "AAPL"]) && service.featuredSymbol === "NVDA",
        power() + "|" + service.featuredSymbol)

      // An offer stands only while it is the service's last removal: one made
      // on another surface replaces it, and this footer lets it go. u then
      // takes back that newer one, the service's last removal, wherever it
      // was made: AAPL returns to All, and stays out of Power, which the
      // first removal took it from.
      wl.cursorSymbol = "AAPL"
      keyClick(Qt.Key_X)
      wait(100)
      service.setMembership("AAPL", "", false)
      wait(100)
      harness.check("a removal made elsewhere drops this surface's offer", body2.note === "", body2.note)
      keyClick(Qt.Key_U)
      wait(100)
      harness.check("and u then takes back that removal, made on the other surface",
        harness.same(power(), ["NVDA"]) && harness.same(service.library, ["NVDA", "AAPL"]),
        power() + "|" + service.library)
      service.setMembership("AAPL", "", false)
      wait(100)
      service.switchList("")
      wait(100)

      keys.forceActiveFocus()
      keyClick(Qt.Key_M)
      wait(100)
      keyClick(Qt.Key_1)
      wait(100)
      harness.check("All's last symbol cannot be unticked, and the checklist says why",
        harness.same(service.library, ["NVDA"]) && body2.listsSymbol === "NVDA"
          && checklist.note === "Keep at least one symbol")
      // Past the double-click interval of the open, which takes any click.
      wait(Application.styleHints.mouseDoubleClickInterval)
      var listsDoneAt = center(harness.find(body2, "symbolListsDone"))
      mouseClick(body2, listsDoneAt.x, listsDoneAt.y)
      wait(100)
      harness.check("DONE closes the checklist", body2.listsSymbol === "" && wl.visible)

      harness.readFile()
      tryVerify(function() { return harness.fileRead !== null }, 3000)
      harness.check("the file holds the renamed, reordered, and ticked lists",
        harness.same(harness.fileRead.symbols, ["NVDA"]) && harness.fileRead.list === ""
          && harness.fileRead.lists.length === 1 && harness.fileRead.lists[0].name === "Power"
          && harness.same(harness.fileRead.lists[0].symbols, ["NVDA"]),
        JSON.stringify(harness.fileRead))

      // With no named lists the checklist has only All; the default cursor
      // must not sit on it, or one Enter removes the symbol everywhere.
      service.deleteList("Power")
      service.addSymbol("AAPL")
      wait(100)
      keys.forceActiveFocus()
      wl.cursorSymbol = "AAPL"
      keyClick(Qt.Key_M)
      wait(100)
      keyClick(Qt.Key_Return)
      keyClick(Qt.Key_Space)
      wait(100)
      harness.check("with no named lists, m then Enter or Space leaves the symbol in All",
        body2.listsSymbol === "AAPL" && harness.same(service.library, ["NVDA", "AAPL"]),
        body2.listsSymbol + "|" + service.library)
      keyClick(Qt.Key_Escape)
      wait(50)

      // A removal that moves the hero draws its chart in, as any change of
      // the chart does, and undo brings the symbol back as it was, quote and
      // all: no fetch, and the hero on its chart at once, drawing in. Found
      // in motion pass 3: the hero swapped in one frame, and undo showed "No
      // quote" until a refetch landed.
      tryVerify(function() { return !!service.quotes.AAPL && service.testFeed.firstRun.length + service.testFeed.refreshRun.length === 0 }, 3000)
      service.feature("AAPL")
      wait(500)
      var aaplCalls = harness.calls("AAPL")
      keys.forceActiveFocus()
      wl.cursorSymbol = "AAPL"
      keyClick(Qt.Key_X)
      var removal = [service.featuredSymbol, body2.motion.reveal < 1]
      wait(100)
      keyClick(Qt.Key_U)
      var undone = [service.featuredSymbol, !!body2.featuredQuote, body2.motion.reveal < 1]
      wait(400)
      harness.check("a removal that moves the hero draws it in, and undo draws it back with its quote and no fetch",
        removal.join("|") === "NVDA|true" && undone.join("|") === "AAPL|true|true"
          && harness.calls("AAPL") === aaplCalls,
        removal.join("|") + " / " + undone.join("|") + " / calls " + aaplCalls + " -> " + harness.calls("AAPL"))

      // The rule under the list name is the list's breadth: the rows' own
      // ups, flats, and downs, counted. DOWN answers a day that fell, FLAT
      // one that closed at its previous close, so a rule that swapped or
      // dropped a tone would miscount.
      service.addSymbol("DOWN")
      service.addSymbol("FLAT")
      tryVerify(function() { return !!service.quotes.DOWN && !!service.quotes.FLAT }, 5000)
      wait(150)
      var rule = harness.find(body2, "breadthRule")
      var tones = function() {
        var count = { up: 0, flat: 0, down: 0 }
        wl.displayedSymbols.forEach(function(s) {
          var r = wl.rowItem(s)
          if (r && r.view) count[r.view.tone]++
        })
        return count
      }
      var reads = function(up, flat, down) {
        var t = tones()
        return !!rule && rule.breadth.up === up && rule.breadth.flat === flat && rule.breadth.down === down
          && t.up === up && t.flat === flat && t.down === down
      }
      harness.check("the rule under All counts two up, one flat, and one down, as the rows read",
        service.listName === "" && reads(2, 1, 1), rule ? JSON.stringify(rule.breadth) + " rows " + JSON.stringify(tones()) : "no rule")
      service.createList("Losers")
      service.addSymbol("DOWN")
      wait(100)
      keys.forceActiveFocus()
      keyClick(Qt.Key_Comma)
      wait(150)
      keyClick(Qt.Key_Period)
      wait(150)
      harness.check("the rule follows , and . to a list with one row, which is down",
        service.listName === "Losers" && reads(0, 0, 1), rule ? JSON.stringify(rule.breadth) : "no rule")
      var ruleAt = rule ? rule.mapToItem(body2, rule.width / 2, rule.height / 2) : { x: 0, y: 0 }
      mouseMove(body2, ruleAt.x, ruleAt.y)
      var counts = null
      within(2000, function() {
        counts = harness.find(body2, "breadthCounts")
        return !!counts && counts.opacity === 1
      })
      harness.check("hovering the rule says its counts in its place",
        !!counts && counts.opacity === 1 && counts.text === "1 DOWN", counts ? counts.opacity + "|" + counts.text : "no counts")
      mouseMove(body2, 5, body2.height - 2)
      wait(50)

      // Covered by a list view, the rule rests: a change of the list's
      // breadth meanwhile moves nothing, and as the rows show again the
      // rule shows the new breadth at once, not easing from the old one out
      // of sight. Found in design pass 3's review: hidden, it would still
      // ease, and show mid-way if the rows came back within 160 ms.
      keys.forceActiveFocus()
      keyClick("W", Qt.ShiftModifier)
      wait(50)
      var coveredDown = rule.downShare
      service.setMembership("FLAT", "Losers", true)
      wait(60)
      var restedAt = rule.downShare
      body2.closeListViews()
      var shownAt = rule.downShare
      harness.check("a breadth change under a list view waits, and shows settled as the rows come back",
        coveredDown === 1 && restedAt === 1 && shownAt === 0.5 && rule.visible,
        coveredDown + " -> " + restedAt + " -> " + shownAt)
      service.setMembership("FLAT", "Losers", false)
      wait(300)

      // Every view opens at its own start, not at last time's: search empty,
      // the menu on the current list, and each list view on its first named
      // list, in the turn it appears, which is the frame first drawn. Found
      // in motion pass 3: each showed last time's state for a frame (search
      // the last query and its results) until its open() reset it a turn later.
      // Each is first left off its start, then opened again.
      keys.forceActiveFocus()
      keyClick(Qt.Key_A)
      wait(50)
      harness.find(body2.search, "searchField").text = "SH"
      tryVerify(function() { return body2.search.results.length > 0 }, 3000)
      keyClick(Qt.Key_Escape)
      wait(50)
      var menu2 = harness.find(body2, "listMenu")
      var manage2 = harness.find(body2, "manageLists")
      var checklist2 = harness.find(body2, "symbolLists")
      keyClick(Qt.Key_W)
      wait(50)
      keyClick(Qt.Key_Down)
      keyClick(Qt.Key_Escape)
      wait(50)
      keyClick("W", Qt.ShiftModifier)
      wait(50)
      keyClick(Qt.Key_Up)
      keyClick(Qt.Key_Escape)
      wait(50)
      wl.cursorSymbol = "DOWN"
      keyClick(Qt.Key_M)
      wait(50)
      keyClick(Qt.Key_Up)
      keyClick(Qt.Key_Escape)
      wait(50)
      // Read as each view turns on, in that same turn: what its first frame
      // will show.
      var firstFrames = []
      var onSearch = function() { if (body2.search.active) firstFrames.push(body2.search.results.length + "'" + body2.search.searchText + "'") }
      var onMenu = function() { if (menu2.active) firstFrames.push(menu2.cursor) }
      var onManage = function() { if (manage2.active) firstFrames.push(manage2.cursor) }
      var onChecklist = function() { if (checklist2.active) firstFrames.push(checklist2.cursor) }
      body2.search.activeChanged.connect(onSearch)
      menu2.activeChanged.connect(onMenu)
      manage2.activeChanged.connect(onManage)
      checklist2.activeChanged.connect(onChecklist)
      keyClick(Qt.Key_A)
      wait(50)
      keyClick(Qt.Key_Escape)
      wait(50)
      keyClick(Qt.Key_W)
      wait(50)
      keyClick(Qt.Key_Escape)
      wait(50)
      keyClick("W", Qt.ShiftModifier)
      wait(50)
      keyClick(Qt.Key_Escape)
      wait(50)
      wl.cursorSymbol = "DOWN"
      keyClick(Qt.Key_M)
      wait(50)
      keyClick(Qt.Key_Escape)
      wait(50)
      body2.search.activeChanged.disconnect(onSearch)
      menu2.activeChanged.disconnect(onMenu)
      manage2.activeChanged.disconnect(onManage)
      checklist2.activeChanged.disconnect(onChecklist)
      harness.check("search, the list menu, and both list views open at their start in their first frame",
        firstFrames.join("|") === "0''|1|1|1", firstFrames.join("|"))

      // Every view gives up the keys however it closes, the window's closing
      // included, its name field too, and a view closed before it took them
      // never takes them later: afterwards the window's own keys act. Found
      // in the garden review: closed with the menu open and reopened, the
      // hidden menu kept the keys and s did nothing.
      var keysAfter = function(open) {
        keys.forceActiveFocus()
        open()
        wait(50)
        app.close()
        app.open("{}")
        wait(100)
        var retro = service.retro
        keyClick(Qt.Key_S)
        wait(50)
        var acted = service.retro !== retro
        if (acted) keyClick(Qt.Key_S)
        wait(50)
        return acted
      }
      var closings = [
        keysAfter(function() { keyClick(Qt.Key_W) }),
        keysAfter(function() { keyClick(Qt.Key_W); wait(50); keyClick(Qt.Key_Up); keyClick(Qt.Key_Up); keyClick(Qt.Key_Return) }),
        keysAfter(function() { keyClick("W", Qt.ShiftModifier) }),
        keysAfter(function() { keyClick("W", Qt.ShiftModifier); wait(50); keyClick(Qt.Key_Return) }),
        keysAfter(function() { keyClick(Qt.Key_M) }),
        keysAfter(function() { keyClick(Qt.Key_A) })
      ]
      harness.check("closing the window with any view open, or its field, hands the keys back",
        closings.every(function(acted) { return acted }), closings.join(","))
      body2.openListMenu()
      body2.closeListMenu()
      wait(50)
      var retroBefore = service.retro
      keyClick(Qt.Key_S)
      wait(50)
      harness.check("a view closed before it took the keys never takes them",
        service.retro !== retroBefore && !menu2.activeFocus, service.retro + "|" + menu2.activeFocus)
      keyClick(Qt.Key_S)
      wait(50)

      // Opening a view, or acting on the rows, shows what it acts on: the key
      // sheet closes first, in the window as in the popup. Found in the
      // garden review: ? then a left the sheet drawn under search.
      keyClick(Qt.Key_Question)
      wait(50)
      var sheetUp = body2.showingHelp
      keyClick(Qt.Key_A)
      wait(50)
      var searchOnly = !body2.showingHelp && body2.adding
      keyClick(Qt.Key_Escape)
      wait(50)
      keyClick(Qt.Key_Question)
      wait(50)
      keyClick(Qt.Key_Down)
      wait(50)
      var rowsAgain = !body2.showingHelp
      harness.check("? then a opens search alone, and ? then a row key shows the rows",
        sheetUp && searchOnly && rowsAgain, sheetUp + "|" + searchOnly + "|" + rowsAgain)
      // So does a click on the header's look, as s does. Found in the review
      // of the untangle: the click changed the look behind the sheet.
      keyClick(Qt.Key_Question)
      wait(50)
      var lookBefore = service.retro
      var clickLook = function() {
        var icon = harness.find(body2, "lookIcon")
        var over = icon.mapToItem(body2, icon.width / 2, icon.height / 2)
        mouseClick(body2, over.x, over.y)
        wait(50)
      }
      clickLook()
      harness.check("a click on the header's look over the key sheet closes it and changes the look once",
        !body2.showingHelp && service.retro !== lookBefore, body2.showingHelp + "|" + service.retro)
      clickLook()
      // The sheet's CLOSE does what Escape does there. Found by the
      // owner on 14 October: the sheet said "esc closes" in plain words.
      keyClick(Qt.Key_Question)
      wait(Qt.styleHints.mouseDoubleClickInterval + 50)
      var closeAt = center(harness.find(body2, "helpClose"))
      mouseClick(body2, closeAt.x, closeAt.y)
      wait(50)
      harness.check("CLOSE closes the key sheet and shows the rows", !body2.showingHelp && wl.visible,
        body2.showingHelp + "|" + wl.visible)

      // The list menu opens scrolled to its own start, the current list in
      // view, however far the last visit scrolled it. Found in the review of
      // the untangle: it reopened at the last visit's offset.
      var extra = []
      for (var n = 1; n <= 12; n++) { extra.push("Probe " + n); service.createList("Probe " + n) }
      service.switchList("")
      app.close()
      var tallBefore = app.testWindow.implicitHeight
      // One row tall: the chart kept whole, as the window's own gives way
      // to three rows (StonksBody.minChartHeight).
      body2.minChartHeight = 0
      app.testWindow.implicitHeight = body2.chromeHeight + body2.listRowHeight
      app.open("{}")
      wait(200)
      keys.forceActiveFocus()
      var menuScroll = harness.find(menu2, "menuScroll")
      // "New list…" and "Manage lists…" are pinned under the lists, always
      // in sight.
      var cursorShown = function() {
        if (menu2.cursor >= menu2.newIndex) return true
        var top = menu2.cursor * menu2.itemHeight
        return top >= menuScroll.contentY && top + menu2.itemHeight <= menuScroll.contentY + menuScroll.height
      }
      keyClick(Qt.Key_W)
      wait(50)
      var scrolls = menuScroll.contentHeight > menuScroll.height
      menuScroll.contentY = menuScroll.contentHeight - menuScroll.height
      keyClick(Qt.Key_Escape)
      wait(50)
      var reopenedAt = []
      var readMenu = function() { if (menu2.active) reopenedAt.push(menuScroll.contentY + ":" + menu2.cursor + ":" + cursorShown()) }
      menu2.activeChanged.connect(readMenu)
      keyClick(Qt.Key_W)
      wait(50)
      keyClick(Qt.Key_Escape)
      wait(50)
      service.switchList("Probe 12")
      wait(50)
      keyClick(Qt.Key_W)
      wait(50)
      keyClick(Qt.Key_Escape)
      wait(50)
      menu2.activeChanged.disconnect(readMenu)
      var lastProbe = service.lists.map(function(l) { return l.name }).indexOf("Probe 12")
      harness.check("the list menu opens at its start with the current list in view",
        scrolls && reopenedAt.length === 2 && reopenedAt[0] === "0:0:true"
          && new RegExp(":" + lastProbe + ":true$").test(reopenedAt[1]),
        scrolls + "|" + reopenedAt.join(" "))
      // A refused name is in view though the list holds still while it is
      // typed: in the list menu its note is pinned under the field, in Manage
      // lists it is brought into view. Found in the branch's review: it sat
      // under the view's edge. And the moment its line goes, as you type
      // again or leave the field, the view rests within its rows: in Manage
      // lists, typing on after a refusal left a row's gap for a frame before
      // the list sprang back.
      var problemShown = function(scroll, top) {
        return top >= scroll.contentY - 0.5 && top + menu2.itemHeight <= scroll.contentY + scroll.height + 0.5
      }
      // Where the view stands as the key lands, against the rows once laid out.
      var settlesAt = function(scroll, press) {
        press()
        var at = scroll.contentY
        wait(50)
        return at + scroll.height <= scroll.contentHeight + 0.5 ? "settled" : "gap " + Math.round(at + scroll.height - scroll.contentHeight)
      }
      // Refused, then typed on, then refused again and left by Escape.
      var refuseTwice = function(scroll, shown, view) {
        keyClick(Qt.Key_Return)
        wait(100)
        var refused = [view.problem !== "", scroll.contentHeight > scroll.height, shown()].join(",")
        var typing = settlesAt(scroll, function() { typeText("x") })
        keyClick(Qt.Key_Backspace)
        keyClick(Qt.Key_Return)
        wait(100)
        var leaving = settlesAt(scroll, function() { keyClick(Qt.Key_Escape) })
        return [refused, typing, leaving].join(",")
      }
      keyClick(Qt.Key_W)
      wait(50)
      menu2.startNaming()
      wait(50)
      typeText("Probe 1")
      var menuRefusal = refuseTwice(menuScroll, function() {
        var note = harness.find(menu2, "listProblem")
        var at = note.mapToItem(menu2, 0, 0)
        return note.visible && at.y >= 0 && at.y + note.height <= menu2.height + 0.5
      }, menu2)
      keyClick(Qt.Key_Escape)
      wait(50)
      var manage2 = harness.find(body2, "manageLists")
      var manageScroll = harness.find(manage2, "manageScroll")
      body2.openManageLists()
      wait(100)
      manage2.cursor = manage2.choices.length - 1
      manage2.showCursor()
      wait(50)
      keyClick(Qt.Key_Return)
      wait(100)
      keyClick(Qt.Key_A, Qt.ControlModifier)
      typeText("Probe 1")
      var manageRefusal = refuseTwice(manageScroll, function() { return problemShown(manageScroll, (manage2.cursor + 1) * manage2.itemHeight) }, manage2)
      body2.closeListViews()
      wait(50)
      harness.check("a refused name at the foot of a long list is in view, and once its line goes the view settles at once, in the list menu and Manage lists",
        menuRefusal === "true,true,true,settled,settled" && manageRefusal === "true,true,true,settled,settled",
        menuRefusal + " | " + manageRefusal)

      // A rename or a delete question pending in this window is about its
      // list, not its row: the popup moving that list meanwhile changes
      // nothing about which list DONE renames or Enter deletes. Found in
      // Codex's review of #30: they acted on whichever list then sat there.
      var listNames = function() { return service.lists.map(function(l) { return l.name }) }
      body2.openManageLists()
      wait(100)
      manage2.startRenaming(listNames().indexOf("Probe 1"))
      wait(50)
      keyClick(Qt.Key_A, Qt.ControlModifier)
      typeText("Chips")
      // Moved far, past the bottom of this short view: the field follows it
      // into view.
      var rowInView = function() {
        var top = manage2.cursor * manage2.itemHeight
        return top >= manageScroll.contentY - 0.5 && top + manage2.itemHeight <= manageScroll.contentY + manageScroll.height + 0.5
      }
      service.moveList("Probe 1", 6)
      wait(50)
      var renameInView = rowInView()
      var doneAt2 = center(harness.find(body2, "manageDone"))
      mouseClick(body2, doneAt2.x, doneAt2.y)
      wait(100)
      var renamedRight = [renameInView, listNames().indexOf("Chips") === listNames().indexOf("Probe 7") + 1, listNames().indexOf("Probe 1") < 0].join(",")
      body2.openManageLists()
      wait(100)
      manage2.askDelete(listNames().indexOf("Probe 3"))
      service.moveList("Probe 3", 6)
      wait(50)
      var askInView = rowInView()
      keyClick(Qt.Key_Return)
      wait(100)
      var deletedRight = [askInView, listNames().indexOf("Probe 3") < 0, listNames().indexOf("Probe 4") > 0].join(",")
      body2.closeListViews()
      wait(50)
      harness.check("a pending rename or delete follows its own list into view after another surface moves it, and acts on it",
        renamedRight === "true,true,true" && deletedRight === "true,true,true", renamedRight + " | " + deletedRight)

      // Closing the surface keeps what was typed, as a click away does: a
      // rename is saved and a new list made; a refused one comes back, saying
      // why, as the surface opens again. Only Escape or CANCEL throws it away.
      // Found in Codex's review of #30: a close lost the typing.
      var closeAndOpen = function() { app.close(); wait(50); app.open("{}"); wait(200) }
      body2.openManageLists()
      wait(100)
      manage2.startRenaming(listNames().indexOf("Probe 5"))
      wait(50)
      keyClick(Qt.Key_A, Qt.ControlModifier)
      typeText("Fives")
      closeAndOpen()
      var renameKept = [listNames().indexOf("Fives") > 0, listNames().indexOf("Probe 5") < 0, body2.managingLists].join(",")
      body2.openManageLists()
      wait(100)
      manage2.startRenaming(listNames().indexOf("Probe 6"))
      wait(50)
      keyClick(Qt.Key_A, Qt.ControlModifier)
      typeText("Probe 7")
      closeAndOpen()
      var renameBack = [body2.managingLists, manage2.renaming, manage2.typedName, manage2.problem, listNames().indexOf("Probe 6") > 0].join(",")
      keyClick(Qt.Key_Escape)
      wait(50)
      body2.closeListViews()
      // A refused rename kept by a close comes back only to its own list:
      // deleted and made again under its name elsewhere, it is another list,
      // and the rename has nothing to act on. Found in the branch's review.
      body2.openManageLists()
      wait(100)
      manage2.startRenaming(listNames().indexOf("Probe 8"))
      wait(50)
      keyClick(Qt.Key_A, Qt.ControlModifier)
      typeText("Probe 9")
      app.close()
      wait(50)
      service.deleteList("Probe 8")
      service.createList("Probe 8")
      app.open("{}")
      wait(200)
      var replacedDropped = [body2.managingLists, listNames().indexOf("Probe 8") > 0, listNames().indexOf("Probe 9") > 0].join(",")
      service.switchList("")
      wait(50)
      keys.forceActiveFocus()
      keyClick(Qt.Key_W)
      wait(50)
      menu2.startNaming()
      wait(50)
      typeText("Fresh")
      closeAndOpen()
      var newKept = [service.listName, body2.listMenuOpen, body2.adding].join(",")
      keys.forceActiveFocus()
      keyClick(Qt.Key_W)
      wait(50)
      menu2.startNaming()
      wait(50)
      typeText("all")
      closeAndOpen()
      var newBack = [body2.listMenuOpen, menu2.naming, menu2.typedName, menu2.problem].join(",")
      keyClick(Qt.Key_Escape)
      keyClick(Qt.Key_Escape)
      wait(50)
      harness.check("closing the window keeps a rename or a new list's name, a refused one comes back saying why, and only to its own list",
        renameKept === "true,true,false" && renameBack === "true,true,Probe 7,Probe 7 already exists,true"
          && replacedDropped === "false,true,true"
          && newKept === "Fresh,false,false" && newBack === "true,true,all,All already exists",
        [renameKept, renameBack, replacedDropped, newKept, newBack].join(" | "))
      service.switchList("")
      extra.concat(["Chips", "Fives", "Fresh"]).forEach(function(name) { service.deleteList(name) })

      // Each list comes back where this surface left it, at once and with no
      // slide; a list it has not shown yet starts at the top, and a rename
      // keeps the place. One row in sight, so three rows scroll.
      app.close()
      service.createList("Deep")
      service.library.slice(0, 3).forEach(function(s) { service.setMembership(s, "Deep", true) })
      service.switchList("")
      app.open("{}")
      wait(200)
      keys.forceActiveFocus()
      var rows = body2.watchlist
      var still = function() { return !rows.settling }
      // All from its top: the open brought the featured row into sight.
      rows.contentY = 0
      wait(50)
      keyClick(Qt.Key_Down)
      within(2000, still)
      var allAt = rows.contentY
      keyClick(Qt.Key_Comma)
      wait(50)
      var deepFirst = [service.listName, rows.contentY].join(":")
      keyClick(Qt.Key_Down)
      keyClick(Qt.Key_Down)
      within(2000, still)
      var deepAt = rows.contentY
      var comeBack = function(key) {
        var seen = []
        var watch = function() { seen.push(rows.contentY) }
        rows.contentYChanged.connect(watch)
        keyClick(key)
        var resting = rows.displayedSymbols.every(function(s) { return rows.rowResting(s) })
        wait(200)
        rows.contentYChanged.disconnect(watch)
        return [service.listName, rows.contentY, seen.join("/"), resting].join(":")
      }
      var backToAll = comeBack(Qt.Key_Period)
      service.renameList("Deep", "Deeper")
      wait(50)
      var backToDeep = comeBack(Qt.Key_Comma)
      harness.check("each list comes back where it was left, at once with no slide, a renamed one too; a first visit starts at the top",
        allAt === rows.rowPitch && deepAt === 2 * rows.rowPitch && deepFirst === "Deep:0"
          && backToAll === ":" + allAt + ":" + allAt + ":true"
          && backToDeep === "Deeper:" + deepAt + ":" + deepAt + ":true",
        [allAt, deepAt, deepFirst, backToAll, backToDeep].join(" | "))

      // Lists renamed, and a freed name taken by a new list, while the
      // surface is closed: two renames keep both places, and the new list is
      // a first visit. Found in review: names compared across the close
      // carried a deleted list's place to a new one and dropped two renamed.
      service.createList("Mid")
      service.library.slice(0, 3).forEach(function(s) { service.setMembership(s, "Mid", true) })
      wait(50)
      keys.forceActiveFocus()
      keyClick(Qt.Key_Down)
      within(2000, still)
      var midAt = rows.contentY
      keyClick(Qt.Key_Period)
      wait(50)
      app.close()
      service.renameList("Deeper", "Deep A")
      service.renameList("Mid", "Mid B")
      service.createList("Deeper")
      service.library.slice(0, 3).forEach(function(s) { service.setMembership(s, "Deeper", true) })
      service.switchList("")
      app.open("{}")
      wait(200)
      keys.forceActiveFocus()
      var landed = []
      for (var step = 0; step < 3; step++) {
        keyClick(Qt.Key_Comma)
        wait(100)
        landed.push(service.listName + ":" + rows.contentY)
      }
      harness.check("lists renamed while the surface was closed keep their places, and a new list under a freed name starts at the top",
        midAt === rows.rowPitch && harness.same(landed, ["Deeper:0", "Mid B:" + midAt, "Deep A:" + deepAt]),
        midAt + " | " + landed.join(" "))
      service.switchList("")
      service.deleteList("Deep A")
      service.deleteList("Mid B")
      service.deleteList("Deeper")
      app.close()
      app.testWindow.implicitHeight = tallBefore
      app.open("{}")
      wait(100)
      keys.forceActiveFocus()

      // Switching lists, or orders, changes the chrome at once: the breadth
      // rule's ends follow its new length on every frame, whether the next
      // list's breadth is the same or not, and the order word takes its
      // brightness with its text. On , and . between a short and a long
      // name, one manual and one sorted, between lists of different breadth,
      // and on o; only the same list's breadth changing eases. Found in the
      // transition audit (lists 9, lists 13): the rule's ends eased from
      // their old lengths and met; the new order word showed in the old one's
      // colour. And in the review of the fix: the ends eased between lists
      // whose breadth differed.
      var members = service.library.slice(0, 3)
      var hadDown = service.library.indexOf("DOWN") >= 0
      var hadFlat = service.library.indexOf("FLAT") >= 0
      service.addSymbol("DOWN")
      service.addSymbol("FLAT")
      tryVerify(function() { return !!service.quotes.DOWN && !!service.quotes.FLAT && service.arriving.length === 0 }, 5000)
      service.createList("Xy")
      members.forEach(function(s) { service.setMembership(s, "Xy", true) })
      service.createList("A much longer list name")
      members.forEach(function(s) { service.setMembership(s, "A much longer list name", true) })
      service.setOrder("symbol")
      service.createList("Mixed")
      service.setMembership("DOWN", "Mixed", true)
      service.switchList("Xy")
      wait(300)
      var upEnd = harness.find(body2, "breadthUp")
      var downEnd = harness.find(body2, "breadthDown")
      var orderWord = harness.find(body2, "orderLabel")
      var chrome = function(change) {
        var faults = []
        var frames = Qt.createQmlObject('import QtQuick; FrameAnimation { running: true }', harness)
        var ruleWidth = upEnd.parent.width
        var read = function() {
          var total = body2.breadth.up + body2.breadth.flat + body2.breadth.down + body2.breadth.none
          var wantUp = Math.floor(upEnd.parent.width * body2.breadth.up / total)
          var wantDown = Math.floor(downEnd.parent.width * body2.breadth.down / total)
          if (upEnd.width !== wantUp || downEnd.width !== wantDown) faults.push("ends " + upEnd.width + "/" + wantUp)
          var bright = body2.order !== "manual"
          if (String(orderWord.color) !== String(bright ? body2.foreground : body2.dim)) faults.push("word " + orderWord.color)
        }
        frames.triggered.connect(read)
        keys.forceActiveFocus()
        change()
        read()
        wait(300)
        frames.destroy()
        return faults.length === 0 ? "ok" : faults.slice(0, 3).join(";")
      }
      mouseMove(body2, 1, 1)
      var toLong = chrome(function() { keyClick(Qt.Key_Period) })
      var toShort = chrome(function() { keyClick(Qt.Key_Comma) })
      var byO = chrome(function() { keyClick(Qt.Key_O) })
      service.switchList("A much longer list name")
      wait(300)
      var toMixed = chrome(function() { keyClick(Qt.Key_Period) })
      var fromMixed = chrome(function() { keyClick(Qt.Key_Comma) })
      harness.check("a list or order switch changes the rule's ends and the order word at once, on every frame, same breadth or not",
        [toLong, toShort, byO, toMixed, fromMixed].every(function(r) { return r === "ok" }),
        [toLong, toShort, byO, toMixed, fromMixed].join(" | "))
      // The same list's breadth changing eases: FLAT joins Mixed, all down,
      // and the down end eases from the whole rule to half of it.
      service.switchList("Mixed")
      wait(300)
      var downFrom = downEnd.width
      var downSeen = []
      var downFrames = Qt.createQmlObject('import QtQuick; FrameAnimation { running: true }', harness)
      downFrames.triggered.connect(function() { downSeen.push(downEnd.width) })
      service.setMembership("FLAT", "Mixed", true)
      wait(300)
      downFrames.destroy()
      var downTo = downEnd.width
      var eased = downFrom > downTo && downTo > 0 && downSeen.some(function(w) { return w > downTo && w < downFrom })
      harness.check("the same list's breadth changing eases the rule's ends",
        eased, downFrom + " -> " + downSeen.join(","))
      service.switchList("")
      service.deleteList("Xy")
      service.deleteList("A much longer list name")
      service.deleteList("Mixed")
      if (!hadDown) service.removeSymbol("DOWN")
      if (!hadFlat) service.removeSymbol("FLAT")
      wait(50)

      app.close()
      harness.finish()
    }
  }

  HarnessExit { id: done }
}
