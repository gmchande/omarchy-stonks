import QtQuick
import QtTest
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "plugin/Chart.js" as Chart
import "plugin/Figures.js" as Figures
import "plugin/Format.js" as Format
import "plugin/History.js" as History
import "plugin" as Stonks

// One shared range through the real Service, App, and BarWidget, with real
// keys in the window. The popup cannot load offscreen; the popup harness
// covers its side of the shared range. The data file starts as the version-1
// fixture (AAPL, MSFT, NVDA, MSFT featured); the fake curl answers AAPL and
// MSFT history with a saved year, fails NVDA's, and fails every FAIL quote.
// The file is read back with cat. Later Services read what the first wrote,
// each with a window summoned before it was ready.
ShellRoot {
  id: harness

  property int failures: 0
  property var fileRead: null
  // What the pills asked the shell to write to their bar entry.
  property var entryWrites: []
  property int middleClicks: 0
  readonly property string dataPath: Quickshell.env("HOME") + "/.config/omarchy/grvc.stonks.json"
  // The current theme's folder, which the flow switches themes in.
  readonly property string themeDir: Quickshell.env("HOME") + "/.local/state/omarchy/current/theme"
  property bool themeCopied: false
  Process { id: themeCopy; onExited: harness.themeCopied = true }

  function check(label, ok, detail) {
    console.log((ok ? "PASS " : "FAIL ") + label + (!ok && detail !== undefined ? " — " + detail : ""))
    if (!ok) failures++
  }

  function readFile() {
    harness.fileRead = null
    catProc.running = true
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

  // `key`'s history answer is in and no fetch for it is on its way: the
  // feed's entries hold answers only, so a refetch keeps the last one there.
  function answered(key, from) {
    var source = from || service
    var entry = source.histories[key]
    var feed = source.testHistoryFeed
    return !!entry && entry.status === "ok" && !feed.holds(feed.wanted, key)
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

  // What the pill says, as drawn: its change.
  function pillText() {
    var change = find(pill, "pillChange")
    return change ? change.text : ""
  }

  // The icon's semantic state; rendered cells and turning are review.
  function iconDrawn() {
    var words = []
    var animal = find(pill, "pillAnimal")
    if (animal.visible && animal.kind) {
      // During a reversed turn the current kind is the right-hand layer;
      // read that layer's actual colour, without judging the turn's ink.
      var layer = animal.children.filter(function(item) { return item.shows === animal.kind })[0]
        || animal.children.filter(function(item) { return item.shows === undefined })[0]
      words.push(animal.kind + " in " + find(layer, "animalCells").color)
    }
    if (find(pill, "pillLevel").visible) words.push("level")
    if (find(pill, "pillWaiting").visible) words.push("…")
    if (find(pill, "pillWarning").visible) words.push("!")
    return words.join(", ") || "nothing"
  }

  // A window's chart: its range, with the range's high and low marked once
  // its history is in.
  function chartShown(window) {
    return window.testBody.chartRange + " " + JSON.stringify(window.testBody.rangeMarks)
  }
  function showsRange(window, range) {
    var body = window.testBody
    return body.chartRange === range && body.historyShown && !!body.rangeMarks
  }
  // A window's first info line as drawn, word by word from the left.
  function firstLineDrawn(window) {
    var row = find(window.testBody, "periodLine")
    var words = []
    var collect = function(item) {
      if (!item.visible) return
      if (typeof item.text === "string" && item.text !== "") words.push({ x: item.mapToItem(row, 0, 0).x, text: item.text })
      for (var i = 0; i < item.children.length; i++) collect(item.children[i])
    }
    if (row) collect(row)
    return words.sort(function(a, b) { return a.x - b.x }).map(function(w) { return w.text }).join(" ")
  }
  // What the first line starts with on `range`: its name, then the low
  // and high its chart's marks have.
  function rangeLineWanted(symbol, range) {
    var history = service.histories[symbol + "|" + range].history
    var quote = service.quotes[symbol]
    var ends = History.rangeEnds(history, null, quote)
    return [range.toUpperCase(), Format.money(ends.low.p, quote.priceDigits), Format.money(ends.high.p, quote.priceDigits)].join(" ")
  }
  // A window's range button for `range`: its word, under its mouse area.
  function rangeToken(window, range) {
    var found = null
    var walk = function(item) {
      if (item.text === range.toUpperCase()) found = item
      for (var i = 0; !found && i < item.children.length; i++) walk(item.children[i])
    }
    walk(find(window.testBody, "rangeRow"))
    return found
  }

  function finish() {
    console.log("RANGE DONE")
    done.exitCode = failures ? 1 : 0
    done.start()
  }

  // The plugin as the shell composes it, with this harness as its shell.
  Stonks.Plugin { id: plugin; shell: shellApi }
  readonly property var service: plugin.service
  readonly property var windowHost: plugin.windowHost
  readonly property var app: plugin.windowHost.app

  // Hyprland as the window host reads it: the window on a workspace, and a
  // browser tab titled Stonks that is not it. Records what it is asked to
  // dispatch.
  QtObject { id: workspaceHere }
  QtObject { id: workspaceThere }
  QtObject {
    id: stonksToplevel
    property string title: "Stonks"
    property var wayland: ({ appId: "org.quickshell" })
    property string address: "5ab1e"
    property var workspace: workspaceHere
  }
  QtObject {
    id: browserToplevel
    property string title: "Stonks"
    property var wayland: ({ appId: "chromium" })
    property string address: "b0b"
    property var workspace: workspaceThere
  }
  QtObject {
    id: hyprlandStandIn
    property var toplevels: ({ values: [browserToplevel, stonksToplevel] })
    property var focusedWorkspace: workspaceHere
    property var dispatched: []
    function dispatch(request) { dispatched = dispatched.concat([request]) }
  }
  Binding { target: plugin.windowHost; property: "hyprlandStandIn"; value: hyprlandStandIn }

  Component { id: serviceAgain; Stonks.Service {} }
  Component { id: appAgain; Stonks.App {} }

  QtObject {
    id: shellApi
    // Whether the popup is open, as the shell would say: the pills here
    // load none.
    property bool popupOpen: false
    function serviceFor() { return plugin }
    function isPluginOpen(id) { return id === "grvc.stonks" && popupOpen }
    function hide(id) { if (id === "grvc.stonks") popupOpen = false }
    // The shell's replace-entry API: records what a pill asks it to write.
    function updateEntryInline(id, settings) {
      harness.entryWrites = harness.entryWrites.concat([{ id: id, settings: settings }])
      return true
    }
  }

  PluginBarApi {
    id: barApi
    pluginId: "grvc.stonks"
    moduleName: "grvc.stonks"
    shell: shellApi
  }

  // The two pills, each in a Loader, so a flow can take one away as an
  // unplugged screen does.
  readonly property var pill: pillLoader.item
  readonly property var otherPill: otherPillLoader.item
  Component {
    id: pillComponent
    Stonks.BarWidget {
      width: implicitWidth
      height: 32
      bar: barApi
      settings: ({ id: "grvc.stonks", barStyle: "sparkline", host: "kept" })
    }
  }

  FloatingWindow {
    id: pillWindow
    visible: true
    color: "#101315"
    implicitWidth: 320
    implicitHeight: 104

    Loader { id: pillLoader; y: 10; sourceComponent: pillComponent }
    Loader { id: otherPillLoader; y: 62; sourceComponent: pillComponent }
  }

  // Calls the harness's own Quickshell over IPC, as omarchy-shell does.
  Process { id: ipcCall }
  function callIpc(fn, arg) {
    ipcCall.command = ["quickshell", "ipc", "--id", Quickshell.instanceId, "call", "grvc.stonks", fn].concat(arg === undefined ? [] : [arg])
    ipcCall.running = true
  }

  // Hold MSFT's history answer back, and let it go (see the fake curl).
  Process { id: holdMsft; command: ["touch", Quickshell.env("STONKS_FAKE_STATE") + "/MSFT.history.hold"] }
  Process { id: releaseMsft; command: ["rm", "-f", Quickshell.env("STONKS_FAKE_STATE") + "/MSFT.history.hold"] }
  // LATE's quotes fail and answer again (see the fake curl).
  Process { id: lateDown; command: ["touch", Quickshell.env("STONKS_FAKE_STATE") + "/LATE.down"] }
  Process { id: lateUp; command: ["rm", "-f", Quickshell.env("STONKS_FAKE_STATE") + "/LATE.down"] }
  // TURN's day goes down and back up (see the fake curl).
  Process { id: turnDown; command: ["touch", Quickshell.env("STONKS_FAKE_STATE") + "/TURN.down"] }
  Process { id: turnUp; command: ["rm", "-f", Quickshell.env("STONKS_FAKE_STATE") + "/TURN.down"] }

  Process {
    id: catProc
    command: ["cat", harness.dataPath]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try { harness.fileRead = JSON.parse(String(text || "").trim()) } catch (e) { harness.fileRead = {} }
      }
    }
  }

  TestCase {
    name: "SharedRange"
    when: service.pluginsReady && pillWindow.visible

    // Waits up to ms for fn to hold and returns whether it does, so the
    // check that reads it is the one that fails.
    function within(ms, fn) {
      for (var t = 0; t < ms && !fn(); t += 50) wait(50)
      return fn()
    }

    // What hovering the pill hands the bar to show, as the shell's bar
    // receives it, "" for nothing: the pointer comes in from off the pill,
    // and leaves again. A test middle-click leaves this window's pointer
    // stuck over the pill, so every hover here comes before the first.
    function hoverTip() {
      var shown = null
      mouseMove(pill, pill.width / 2, -5)
      wait(20)
      barApi._showTooltip = function(target, text) { shown = text }
      mouseMove(pill, pill.width / 2, pill.height / 2)
      wait(20)
      barApi._showTooltip = null
      mouseMove(pill, pill.width / 2, -5)
      wait(20)
      return shown
    }

    // The hover of each form, as "form tip", the form set as a
    // middle-click sets it.
    function hoverEveryForm() {
      var before = pill.settings
      var tips = ["text", "sparkline", "arrow", "icon"].map(function(form) {
        pill.settings = Object.assign({}, before, { barStyle: form })
        wait(20)
        return form + " " + JSON.stringify(hoverTip())
      })
      pill.settings = before
      return tips
    }

    // The pill in every bar style, cycled by middle-clicks until it comes
    // round, in both looks: what it says and the change's colour against
    // `expected(retro)` and `tone`, and for the icon form the bear alone in
    // `tone`. Each middle-click hands the shell the entry's other keys with
    // the next style, and writes no data file. Returns what was wrong.
    function pillInEveryStyle(expected, tone) {
      var wrong = []
      var startLook = service.retro
      for (var look = 0; look < 2; look++) {
        service.persist({ style: look === 0 ? "smooth" : "retro" })
        harness.readFile()
        tryVerify(function() { return harness.fileRead !== null }, 2000)
        var fileBefore = JSON.stringify(harness.fileRead)
        var writesBefore = harness.entryWrites.length
        var first = pill.barStyle
        var seen = []
        do {
          seen.push(pill.barStyle)
          var change = harness.find(pill, "pillChange")
          var arrow = harness.find(pill, "pillArrow")
          var symbolShown = harness.find(pill, "pillSymbol").visible
          var want = expected(service.retro)
          var where = pill.barStyle + " " + (service.retro ? "retro" : "smooth")
          if (pill.barStyle === "icon") {
            if (harness.iconDrawn() !== "bear in " + tone || arrow.visible || change.visible || symbolShown)
              wrong.push(where + ": " + harness.iconDrawn() + ", arrow " + arrow.visible + ", symbol " + symbolShown
                + ", change " + change.visible + "; want the bear alone in " + tone)
          } else if (harness.pillText() !== want || !Qt.colorEqual(change.color, tone) || !symbolShown || !change.visible) {
            wrong.push(where + ": " + harness.pillText() + " in " + change.color + ", want " + want + " in " + tone)
          }
          // The text form alone says the price, the row's, between the
          // symbol and the change: "DOWN 95.00 −5.00%".
          var price = harness.find(pill, "pillPrice")
          var priceShown = price && price.visible ? price.text : ""
          var priceWant = pill.barStyle === "text"
            ? Figures.rowModel(service.quotes[service.featuredSymbol], 0, service.changeMode).priceText : ""
          if (priceShown !== priceWant)
            wrong.push(where + ": price " + JSON.stringify(priceShown) + ", want " + JSON.stringify(priceWant) + " after the symbol")
          mouseClick(pill, pill.width / 2, pill.height / 2, Qt.MiddleButton)
          harness.middleClicks++
        } while (pill.barStyle !== first && seen.length < 10)
        var writes = harness.entryWrites.slice(writesBefore)
        if (seen.slice().sort().join(",") !== "arrow,icon,sparkline,text" || writes.length !== seen.length || !writes.every(function(w, i) {
              return w.id === "grvc.stonks" && w.settings.id === "grvc.stonks" && w.settings.host === "kept"
                && Object.keys(w.settings).length === 3 && w.settings.barStyle === seen[(i + 1) % seen.length]
            }))
          wrong.push("entry writes " + JSON.stringify(writes) + " for styles " + seen.join(","))
        harness.readFile()
        tryVerify(function() { return harness.fileRead !== null }, 2000)
        if (JSON.stringify(harness.fileRead) !== fileBefore) wrong.push("the data file changed: " + JSON.stringify(harness.fileRead))
      }
      service.persist({ style: startLook ? "retro" : "smooth" })
      return wrong
    }

    // What the surfaces show while a chart is on its way, from any trigger
    // and with the window shut or open; a refetch or a retry that fails;
    // and the chart kept on show, frozen as it was.
    function chartOnShow(body) {
      var dropEntry = function(key) {
        var next = Object.assign({}, service.testHistoryFeed.entries)
        delete next[key]
        service.testHistoryFeed.entries = next
      }
      var settle = function(key) {
        tryVerify(function() { return harness.answered(key) && !body.chartLoading }, 5000)
      }
      var hero = function() {
        return body.chartSymbol + " " + (body.featured ? body.featured.priceText : "") + " " + JSON.stringify(body.periodLine)
          + " " + JSON.stringify(body.rangeMarks)
      }
      app.open("{}")
      service.summon("AAPL", "1W")
      settle("AAPL|1W")

      service.setOrder("manual")
      service.setManualOrder(["AAPL", "SLOW"].concat(service.symbols.filter(function(s) { return s !== "AAPL" && s !== "SLOW" })))

      // An open while the chart is on its way shows the last one whole, the
      // header naming what is coming, undimmed until a quarter second after
      // the open, and draws the new one in as it lands: a symbol stepped to
      // with the window shut, and a summon that opens it on a symbol and
      // range. Found in the transition audit (lifecycle 0, ranges 5, ranges
      // 6): the day's figures over an empty chart.
      var opensHeld = function(before, change, key, coming) {
        service.summon(before, "1W")
        settle(before + "|1W")
        var shown = hero()
        app.close()
        dropEntry(key)
        change()
        var held = [hero() === shown, body.headerText === coming].join(",")
        body.replay()
        var noReplay = !body.motion.replayRunning
        settle(key)
        return held + "," + noReplay + " " + hero() + " " + body.headerText
      }
      var stepped = opensHeld("AAPL", function() { service.feature("SLOW"); app.open("{}") }, "SLOW|1W", "Loading SLOW 1W")
      var summoned = opensHeld("AAPL", function() { app.open(JSON.stringify({ symbol: "SLOW", range: "1M" })) }, "SLOW|1M", "Loading SLOW 1M")
      harness.check("an open while the chart is on its way keeps the last data, names what is coming, and shows the new data once answered",
        /^true,true,true /.test(stepped) && /^true,true,true /.test(summoned), stepped + " | " + summoned)

      // The chart kept on show is kept as it was: its symbol's next quote, or
      // its removal on another surface, changes nothing of it while the next
      // one loads. Found in cubic's review of #24: the held chart followed its
      // symbol's live quote, and blanked when it left All.
      service.summon("AAPL", "1W")
      settle("AAPL|1W")
      dropEntry("SLOW|1W")
      service.feature("SLOW")
      var kept = hero()
      var quotesBefore = service.testFeed.quotes
      var moved = Object.assign({}, service.testFeed.quotes)
      moved.AAPL = Object.assign({}, moved.AAPL, { price: moved.AAPL.price + 10 })
      service.testFeed.quotes = moved
      var afterQuote = hero() === kept
      service.removeSymbol("AAPL")
      var afterRemoval = hero() === kept && body.chartLoading
      settle("SLOW|1W")
      service.undoRemoval("AAPL")
      service.testFeed.quotes = quotesBefore
      harness.check("the chart kept on show stays as it was through its symbol's next quote and its removal",
        afterQuote && afterRemoval, afterQuote + "|" + afterRemoval + " " + kept + " -> " + hero())

      // A refetch that fails with the chart in hand keeps it and the header
      // on the market, in the window open and shut, and so does the retry
      // after it. Found in the transition audit (ranges 3, data 0, data 1,
      // lifecycle 3, featured 6): the day took the range's place, then came
      // back at every retry.
      service.summon("AAPL", "1W")
      settle("AAPL|1W")
      var weekHero = hero()
      var markets = body.headerText
      var read = function() {
        return [hero() === weekHero, body.headerText === markets].join(",")
      }
      // Its retry changes no answer: the failed one stays until another lands.
      var next = Object.assign({}, service.testHistoryFeed.entries)
      next["AAPL|1W"] = Object.assign({}, next["AAPL|1W"], { status: "failed" })
      service.testHistoryFeed.entries = next
      var failedOpen = read()
      app.close()
      var failedShut = read()
      app.open("{}")
      harness.check("a refetch that fails with the chart in hand keeps it and the market header, open and shut",
        failedOpen === "true,true" && failedShut === "true,true", failedOpen + " | " + failedShut + " " + hero() + " " + body.headerText)
      service.refresh()
      settle("AAPL|1W")

      // A retry of a range whose first fetch failed keeps the day, and the
      // header says it is unavailable until an answer lands: by an open,
      // and by r in the window, the header's RETRY, and RETRY under search,
      // which the reader asked for, saying "Refreshing" while it is out.
      // NVDA's history always fails. Found in the transition audit (ranges
      // 7, lifecycle 4, ranges 4, data 4): "Loading" and no AT CLOSE for the
      // length of every retry, or an empty chart on the popup's open. The
      // RETRY was plain words, "· R to retry", until the owner clicked one
      // hint like it (14 October); the owner asked for "Refreshing" on r (21
      // October).
      // Whatever an earlier step left of NVDA's week goes first.
      var nvdaHeld = false
      var withoutWeek = Object.assign({}, service.testHistoryFeed.entries)
      delete withoutWeek["NVDA|1W"]
      service.testHistoryFeed.entries = withoutWeek
      service.summon("NVDA", "1W")
      nvdaHeld = body.chartLoading
      tryVerify(function() { return body.headerText === "1W unavailable" && !service.testHistoryFeed.busy }, 10000)
      var failedLifted = nvdaHeld
      var retryButton = harness.find(body, "retryRange")
      var offered = !!retryButton && retryButton.visible
      // Read the header on its own change: a frame can miss the answer.
      var retry = function(start) {
        var said = []
        var heard = function() { if (said[said.length - 1] !== body.headerText) said.push(body.headerText) }
        body.headerTextChanged.connect(heard)
        heard()
        start()
        var retried = within(3000, function() { return service.testHistoryFeed.busy })
        tryVerify(function() { return !service.testHistoryFeed.busy && !service.refreshing }, 10000)
        wait(50)
        body.headerTextChanged.disconnect(heard)
        return [retried, body.headerText === "1W unavailable", !!body.featuredGeometry].join(",") + " " + said.join("/")
      }
      app.testKeyCatcher.forceActiveFocus()
      var byR = retry(function() { keyClick(Qt.Key_R) })
      var byClick = retry(function() { mouseClick(retryButton, retryButton.width / 2, retryButton.height / 2) })
      var byOpen = retry(function() { app.close(); app.open("{}") })
      // With search open, r types into its field: a click still retries.
      var inSearch = retry(function() {
        app.testKeyCatcher.forceActiveFocus()
        keyClick(Qt.Key_A)
        wait(50)
        mouseClick(retryButton, retryButton.width / 2, retryButton.height / 2)
      })
      var searchWord = [body.adding, retryButton.text].join(",")
      keyClick(Qt.Key_Escape)
      wait(50)
      var asked = "true,true,true 1W unavailable/Refreshing/1W unavailable"
      harness.check("a first failed fetch and every retry keep the day, with Refreshing while a manual retry is out and the unavailable header after, by r, by RETRY, by an open, and by RETRY under search",
        failedLifted && offered && byR === asked && byClick === asked
          && byOpen === "true,true,true 1W unavailable" && inSearch === asked && searchWord === "true,RETRY",
        [failedLifted, offered, byR, byClick, byOpen, inSearch, searchWord].join(" | "))
      service.summon("AAPL", "1D")
      wait(100)
      app.close()
    }

    function test_shared_range() {
      tryVerify(function() {
        return service.quotes.AAPL && service.quotes.MSFT && service.quotes.NVDA
          && service.testFeed.firstRun.length + service.testFeed.refreshRun.length === 0
      }, 10000)
      var dayLine = Format.lookSigns(pill.featured.changeLine, false)
      harness.check("on the day the pill reads its day",
        service.range === "1D" && harness.pillText() === dayLine, harness.pillText())

      // Only an open surface asks for a cap and P/E, so a window that was
      // never shown has asked for nothing, whatever symbol is featured.
      service.feature("AAPL")
      wait(300)
      harness.check("a hidden window fetches no cap or P/E when the symbol changes",
        harness.calls("FUNDAMENTALS") === 0, harness.calls("FUNDAMENTALS"))
      service.feature("MSFT")

      // A window never shown has built no body: it is built as the window
      // first opens, and kept.
      harness.check("a window never shown holds no body", app.testBody === null, String(app.testBody))

      // The pill's right-click opens the window, and another closes it. It
      // used to refresh.
      var rightClick = function() { mouseClick(pill, pill.width / 2, pill.height / 2, Qt.RightButton) }
      rightClick()
      var openedByClick = app.opened
      rightClick()
      harness.check("a right-click on the pill opens the window, and another closes it",
        openedByClick && !app.opened, openedByClick + " -> " + app.opened)

      // With the popup open, a request for the window closes the popup and
      // opens the window, or leaves it open when it already is.
      shellApi.popupOpen = true
      rightClick()
      var fromPopup = [shellApi.popupOpen, app.opened].join(",")
      shellApi.popupOpen = true
      rightClick()
      var overWindow = [shellApi.popupOpen, app.opened].join(",")
      harness.check("with the popup open, a right-click closes it and opens the window, or keeps the window open",
        fromPopup === "false,true" && overWindow === "false,true", fromPopup + " | " + overWindow)

      // On another workspace the window comes forward there and stays open;
      // on this one it closes.
      stonksToplevel.workspace = workspaceThere
      var dispatchedBefore = hyprlandStandIn.dispatched.length
      rightClick()
      var dispatched = hyprlandStandIn.dispatched.slice(dispatchedBefore).join(" ")
      var stillOpen = app.opened
      stonksToplevel.workspace = workspaceHere
      rightClick()
      harness.check("a right-click with the window on another workspace focuses it there, and on this one closes it",
        dispatched === "hl.dsp.focus({ window = \"address:0x5ab1e\" })" && stillOpen && !app.opened,
        dispatched + "|" + stillOpen + " -> " + app.opened)

      var body = app.testBody
      app.open("{}")
      waitForRendering(body)
      app.testKeyCatcher.forceActiveFocus()
      harness.check("the window opens on the featured chart", body.chartSymbol === service.featuredSymbol)
      keyClick(Qt.Key_1)
      harness.check("a row key features its row", service.featuredSymbol === "AAPL")
      keyClick(Qt.Key_2)
      var heroBeforeWheel = service.featuredSymbol
      mouseWheel(pill, pill.width / 2, pill.height / 2, 0, -120)
      var wheeledTo = service.featuredSymbol
      service.featureStep(-1)
      var steppedTo = service.featuredSymbol
      app.open(JSON.stringify({ symbol: "NVDA" }))
      harness.check("the pill wheel, IPC step and summon select their symbols",
        wheeledTo !== heroBeforeWheel && steppedTo === heroBeforeWheel && service.featuredSymbol === "NVDA")
      app.open(JSON.stringify({ symbol: "AAPL", range: "1Y" }))
      tryVerify(function() { return harness.answered("AAPL|1Y") }, 5000)
      var rangeSelected = body.chartSymbol === "AAPL" && body.chartRange === "1Y"
      app.open(JSON.stringify({ symbol: "MSFT", range: "1D" }))
      harness.check("a summon selects its symbol and shared range in either direction",
        rangeSelected && body.chartSymbol === "MSFT" && body.chartRange === "1D" && service.range === "1D")
      service.setRange("1D")
      service.feature("MSFT")

      // A replay belongs to the chart it started on. Found offscreen: after
      // ], the day's replay went on scrubbing the week's chart for its 2 s.
      keyClick(Qt.Key_P)
      wait(300)
      var replaying = body.motion.replayRunning && body.scrubT !== 0
      keyClick(Qt.Key_BracketRight)
      wait(50)
      harness.check("] in the window sets the one shared range",
        service.range === "1W" && app.range === "1W", service.range + "|" + app.range)
      harness.check("] ends the day's replay at once, and the scrub with it",
        replaying && !body.motion.replayRunning && body.scrubT === 0,
        replaying + "|" + body.motion.replayRunning + "|" + body.scrubT + "|" + body.headerText)

      // On a range the pill still shows the day: the featured symbol's
      // change and line, as its row shows them, with no range named.
      tryVerify(function() { return harness.answered("MSFT|1W") }, 5000)
      wait(50)
      var week = History.historyRowModel(service.histories["MSFT|1W"].history, service.quotes.MSFT, 0)
      var msftDay = Figures.rowModel(service.quotes.MSFT, 0, service.changeMode)
      var row = body.watchlist.rowItem("MSFT")
      harness.check("on 1W the pill shows the day, as the row does, and its line",
        harness.pillText() === Format.lookSigns(msftDay.changeLine, false) && msftDay.changeLine !== week.changeLine
          && row.view.changeLine === msftDay.changeLine
          && JSON.stringify(harness.find(pill, "pillLine").geometry) === JSON.stringify(Chart.chartGeometry(service.quotes.MSFT)),
        harness.pillText() + " vs day " + msftDay.changeLine + " / week " + week.changeLine)

      // The first info line follows the range, by keys and by mouse, in
      // both looks: ] to 1W, a click on 1M in retro, and [ back to 1W, each
      // drawing that range's name and its low and high, as its marks have
      // them. Until 22 October it stayed the day's on every range.
      var followed = []
      var follows = function(how, range) {
        tryVerify(function() { return harness.answered("MSFT|" + range) && body.chartRange === range && body.historyShown }, 5000)
        wait(50)
        var drawn = harness.firstLineDrawn(app)
        var want = harness.rangeLineWanted("MSFT", range)
        if (drawn.indexOf(want + " START ") !== 0) followed.push(how + ": " + drawn + ", want " + want + " START …")
      }
      follows("] in smooth", "1W")
      service.persist({ style: "retro" })
      wait(50)
      var month = harness.rangeToken(app, "1M")
      mouseClick(month, month.width / 2, month.height / 2)
      follows("a click on 1M in retro", "1M")
      keyClick(Qt.Key_BracketLeft)
      follows("[ in retro", "1W")
      service.persist({ style: "smooth" })
      wait(50)
      harness.check("the first info line says the range's name, low, and high as the range changes by keys and by mouse, in both looks",
        followed.length === 0, followed.join(" | "))

      // r with the week in hand says "Refreshing" in the header while what it
      // asked for is out, MSFT's week held back here, and the market again
      // once it lands; the service asking again by itself for the week grown
      // old keeps the market. The header said "LOADING 1W" every fifteen
      // minutes, when the service refetched the pill's range, and on every r;
      // the owner asked for "Refreshing" on r alone (21 October).
      // Read on the header's own change, as the retries above are.
      var said = []
      var watch = function() { if (said[said.length - 1] !== body.headerText) said.push(body.headerText) }
      body.headerTextChanged.connect(watch)
      // Only the market, its minute free to turn meanwhile.
      var market = function(texts) {
        return texts.length > 0 && texts.every(function(t) { return t !== "Refreshing" && t.indexOf("Loading") !== 0 })
      }
      holdMsft.running = true
      tryVerify(function() { return !holdMsft.running }, 2000)
      watch()
      keyClick(Qt.Key_R)
      within(3000, function() { return body.headerText === "Refreshing" })
      wait(300)
      releaseMsft.running = true
      tryVerify(function() { return harness.answered("MSFT|1W") && !service.refreshing }, 5000)
      wait(50)
      var at = said.indexOf("Refreshing")
      var byR = said.slice()
      said = []
      watch()
      var aged = Object.assign({}, service.testHistoryFeed.entries)
      aged["MSFT|1W"] = Object.assign({}, aged["MSFT|1W"], { receivedAt: aged["MSFT|1W"].receivedAt - 16 * 60 })
      service.testHistoryFeed.entries = aged
      holdMsft.running = true
      tryVerify(function() { return !holdMsft.running }, 2000)
      service.showHistory(false)
      var out = within(3000, function() { return service.testHistoryFeed.holds(service.testHistoryFeed.wanted, "MSFT|1W") })
      wait(300)
      releaseMsft.running = true
      tryVerify(function() { return harness.answered("MSFT|1W") }, 5000)
      wait(50)
      body.headerTextChanged.disconnect(watch)
      harness.check("r with the week in hand says Refreshing while it is out, then the market once it lands; the service asking again for the week by itself keeps the market",
        at > 0 && market(byR.slice(0, at)) && market(byR.slice(at + 1)) && byR.lastIndexOf("Refreshing") === at
          && out && market(said),
        byR.join("/") + " | " + out + " " + said.join("/"))

      // Replay unfolds: on a range too it is a scrub that drives itself, bar
      // by bar, with the chart drawing in behind it. It used to be a slow
      // draw-in with the header and the price left on today.
      var marketHeader = body.headerText
      var headline = body.featured.priceText
      keyClick(Qt.Key_P)
      wait(1000)
      harness.check("a replay on a range walks its bars: a date in the header, the price at that bar",
        body.motion.replayRunning && body.headerText !== marketHeader && body.featured.priceText !== headline,
        body.headerText + "|" + body.featured.priceText + " vs " + headline)
      tryVerify(function() { return !body.motion.replayRunning }, 3000)
      // The market's header counts down by the minute, and the minute can turn
      // during the replay (it failed so on 23 October): it must be the market
      // as of now, not as it was before the key. A scrub's date or a held
      // "Loading" is still not the market.
      harness.check("the replay ends back on the market",
        body.marketText !== "" && body.headerText === body.marketText && body.featured.priceText === headline,
        body.headerText + " vs " + body.marketText + "|" + body.featured.priceText)

      // NVDA's history never comes. Read straight after the key, before any
      // answer can land: the window names what is coming, and once the
      // fetch has failed says the range is unavailable.
      keyClick(Qt.Key_3)
      var header = harness.find(body, "statusText")
      harness.check("while a range's first fetch is out the window names what is coming",
        service.featuredSymbol === "NVDA" && header.text === "LOADING NVDA 1W",
        service.featuredSymbol + "|" + header.text)
      // The chart a feature waits for arrives once it lands; until then the
      // last one, MSFT's week, stays whole, and nothing of NVDA's day shows.
      harness.check("a feature on a range keeps the last chart, not the day, while its range is out",
        body.chartSymbol === "MSFT"
          && JSON.stringify(body.featuredGeometry) === JSON.stringify(History.historyGeometry(service.histories["MSFT|1W"].history)),
        body.chartSymbol)
      harness.check("after it fails the window says the range is unavailable, with RETRY beside it",
        within(8000, function() { return header.text === "1W UNAVAILABLE" && harness.find(body, "retryRange").visible }), header.text)

      // Back to a symbol with history: the window draws its range once in.
      keyClick(Qt.Key_1)
      harness.check("a symbol change in the window brings that symbol's range",
        service.featuredSymbol === "AAPL"
          && within(5000, function() { return harness.showsRange(app, "1W") }),
        service.featuredSymbol + "|" + harness.chartShown(app))

      // A range's first fetch keeps the day's chart and info lines, as the
      // hero keeps the day's figures, until the range's response lands.
      // Found in motion pass 3: the chart went blank and the info line to
      // dashes for the length of the fetch, on every first visit to a range.
      var blanked = []
      var watchLoad = function() {
        var entry = service.histories["AAPL|1M"]
        if (service.range !== "1M" || (entry && entry.history)) return
        if (!body.featuredGeometry) blanked.push("chart")
        if (!body.periodLine || body.periodLine.range.highText === "") blanked.push("info")
      }
      body.featuredGeometryChanged.connect(watchLoad)
      body.periodLineChanged.connect(watchLoad)
      keyClick(Qt.Key_BracketRight)
      watchLoad()
      tryVerify(function() { return harness.answered("AAPL|1M") }, 5000)
      body.featuredGeometryChanged.disconnect(watchLoad)
      body.periodLineChanged.disconnect(watchLoad)
      harness.check("a range's first fetch keeps the day's chart and info lines until it lands",
        blanked.length === 0 && !!body.featuredGeometry, blanked.join(","))

      // A range whose cache has run out still has its chart: featured, it
      // draws in at once while the refetch is out. It opened blank until
      // the refetch landed, the first time after the laptop woke.
      keyClick(Qt.Key_2)
      tryVerify(function() { return harness.answered("MSFT|1M") }, 5000)
      keyClick(Qt.Key_1)
      var aged = Object.assign({}, service.testHistoryFeed.entries)
      aged["MSFT|1M"] = Object.assign({}, aged["MSFT|1M"], { receivedAt: aged["MSFT|1M"].receivedAt - 16 * 60 })
      service.testHistoryFeed.entries = aged
      // The refetch's answer is held back until the check has read the
      // state it is out in: the fake curl could answer before the check.
      holdMsft.running = true
      tryVerify(function() { return !holdMsft.running }, 2000)
      keyClick(Qt.Key_2)
      var stale = service.histories["MSFT|1M"]
      var out = service.testHistoryFeed.holds(service.testHistoryFeed.wanted, "MSFT|1M")
      var loadingAtOnce = body.chartLoading
      harness.check("expired history stays usable while its refetch is out",
        out && !!stale.history && !loadingAtOnce && body.chartSymbol === "MSFT",
        out + "|" + loadingAtOnce)
      releaseMsft.running = true
      tryVerify(function() { return !releaseMsft.running && harness.answered("MSFT|1M") && !service.testHistoryFeed.busy }, 5000)
      keyClick(Qt.Key_1)
      tryVerify(function() { return service.featuredSymbol === "AAPL" && !service.testHistoryFeed.busy && !service.testFeed.busy }, 5000)

      // r fetches every quote again, and the range on show, which the cache
      // would otherwise have kept: AAPL's quote and its history.
      // These answers are older than refresh's ten-second floor. The
      // preceding inputs may now finish before that much wall time passes.
      var refreshable = {}
      for (var symbol in service.testFeed.entries)
        refreshable[symbol] = Object.assign({}, service.testFeed.entries[symbol], { answeredAt: service.testFeed.entries[symbol].answeredAt - 20 })
      service.testFeed.entries = refreshable
      var aapl = harness.calls("AAPL")
      var aaplHistory = harness.calls("AAPL.history")
      var msft = harness.calls("MSFT")
      var nvda = harness.calls("NVDA")
      keyClick("r")
      within(5000, function() { return harness.calls("NVDA") > nvda && harness.calls("AAPL") >= aapl + 2 })
      harness.check("refresh includes quotes",
        harness.calls("MSFT") === msft + 1 && harness.calls("NVDA") === nvda + 1,
        (harness.calls("MSFT") - msft) + "|" + (harness.calls("NVDA") - nvda))
      // One quote and one history request for AAPL, counted apart: the two
      // run at once.
      var histories = harness.calls("AAPL.history") - aaplHistory
      harness.check("refresh forces selected history",
        histories === 1 && harness.calls("AAPL") - aapl - histories === 1,
        histories + "|" + (harness.calls("AAPL") - aapl))

      // r in an open surface asks for the cap and P/E too, which are kept
      // for a day: day-old ones are fetched again, fresh ones are not.
      tryVerify(function() { return service.fundamentals.AAPL && service.fundamentals.AAPL.status === "ok" }, 5000)
      var asksBefore = harness.calls("AAPL.fundamentals")
      keyClick("r")
      tryVerify(function() { return !service.testFeed.busy && !service.testHistoryFeed.busy }, 10000)
      var freshAsks = harness.calls("AAPL.fundamentals") - asksBefore
      var aged = Object.assign({}, service.testFundamentalsFeed.entries)
      aged.AAPL = Object.assign({}, aged.AAPL, { checkedAt: aged.AAPL.checkedAt - 25 * 60 * 60 })
      service.testFundamentalsFeed.entries = aged
      keyClick("r")
      var asked = within(5000, function() { return harness.calls("AAPL.fundamentals") > asksBefore })
      tryVerify(function() { return service.fundamentals.AAPL.checkedAt > aged.AAPL.checkedAt }, 5000)
      harness.check("r fetches a day-old cap and P/E again, not fresh ones",
        freshAsks === 0 && asked && harness.calls("AAPL.fundamentals") === asksBefore + 1
          && service.fundamentals.AAPL.status === "ok",
        freshAsks + "|" + (harness.calls("AAPL.fundamentals") - asksBefore))
      tryVerify(function() { return !service.testFeed.busy && !service.testHistoryFeed.busy }, 10000)

      // IPC refreshes once, and every pill acknowledges it: dimmed, then
      // eased back. With a pill per screen, each one refreshed it, and the
      // second queued a second sweep. The answers are aged past the
      // refresh's 10 s floor first: r already fetched them just now.
      var agedEntries = {}
      for (var s in service.testFeed.entries)
        agedEntries[s] = Object.assign({}, service.testFeed.entries[s], { answeredAt: service.testFeed.entries[s].answeredAt - 20 })
      service.testFeed.entries = agedEntries
      aapl = harness.calls("AAPL")
      aaplHistory = harness.calls("AAPL.history")
      msft = harness.calls("MSFT")
      nvda = harness.calls("NVDA")
      harness.callIpc("refresh")
      tryVerify(function() { return !ipcCall.running }, 5000)
      tryVerify(function() { return !service.testFeed.busy && !service.testHistoryFeed.busy }, 10000)
      histories = harness.calls("AAPL.history") - aaplHistory
      harness.check("IPC refresh sends one refresh with multiple pills",
        histories === 1 && harness.calls("AAPL") - aapl - histories === 1
          && harness.calls("MSFT") === msft + 1 && harness.calls("NVDA") === nvda + 1,
        histories + "|" + (harness.calls("AAPL") - aapl) + "|"
          + (harness.calls("MSFT") - msft) + "|" + (harness.calls("NVDA") - nvda))

      // IPC reaches the plugin with no pill on the bar, as with the pill
      // taken off: the hero steps, toggleWindow (a key binding's command) opens the
      // window and closes it, and openWindow (the launcher) opens it on the
      // symbol it names. IPC used to live in the pills.
      app.close()
      pillLoader.active = false
      otherPillLoader.active = false
      var ipcDone = function() { tryVerify(function() { return !ipcCall.running }, 5000) }
      var heroBefore = service.featuredSymbol
      harness.callIpc("next")
      ipcDone()
      var stepped = service.featuredSymbol !== heroBefore
      harness.callIpc("toggleWindow")
      ipcDone()
      var toggledOpen = app.opened
      harness.callIpc("toggleWindow")
      ipcDone()
      var toggledShut = !app.opened
      harness.callIpc("openWindow", JSON.stringify({ symbol: heroBefore }))
      ipcDone()
      var openedOn = app.opened && service.featuredSymbol === heroBefore
      pillLoader.active = true
      otherPillLoader.active = true
      app.testKeyCatcher.forceActiveFocus()
      tryVerify(function() { return !service.testFeed.busy && !service.testHistoryFeed.busy }, 10000)
      harness.check("IPC reaches the plugin with no pill: next, toggleWindow open and shut, openWindow on a symbol",
        stepped && toggledOpen && toggledShut && openedOn,
        stepped + "|" + toggledOpen + "|" + toggledShut + "|" + openedOn + " " + service.featuredSymbol)

      // The service asks for the one chart on show. A range left behind is
      // dropped with its retry: NVDA's history fails, and in its retry pause
      // the day comes back, and then another range. The window's own request
      // used to outlive it and retry NVDA first. What the feed wants after
      // is read, not NVDA's calls: the rows in sight are fetched ahead on
      // the next range, NVDA's among them.
      var nvdaHistory = harness.calls("NVDA.history")
      keyClick(Qt.Key_3)
      var leftKey = "NVDA|" + service.range
      tryVerify(function() { return service.testHistoryFeed.testRetrying }, 5000)
      var wantedSince = []
      var noteWant = function() { var w = service.testHistoryFeed.wanted; if (w) wantedSince.push(w.charts.map(function(c) { return c.key }).join("+")) }
      service.testHistoryFeed.wantedChanged.connect(noteWant)
      service.setRange("1D")
      service.feature("AAPL")
      var askedAt = Date.now()
      service.setRange("5Y")
      tryVerify(function() { return harness.answered("AAPL|5Y") }, 10000)
      var waited = Date.now() - askedAt
      tryVerify(function() { return !service.testHistoryFeed.busy }, 10000)
      service.testHistoryFeed.wantedChanged.disconnect(noteWant)
      harness.check("a chart left behind never retries ahead of the one on show",
        wantedSince.indexOf(leftKey) < 0 && wantedSince[0] === "AAPL|5Y" && harness.calls("NVDA.history") >= nvdaHistory + 1 && waited < 2000,
        leftKey + " | wanted " + wantedSince.join(",") + " | " + waited + " ms")

      // With no surface open the service asks for no history: the pill shows
      // the day, and nothing else shows a range. Not as the window closes
      // on a pending retry, nor for a range change or the pill's wheel; an
      // open asks again. Found in design round 2: after a look at 5Y the bar
      // read the range all day, fetching it for itself.
      var historyCalls = function() {
        return ["AAPL", "MSFT", "NVDA"].reduce(function(sum, s) { return sum + harness.calls(s + ".history") }, 0)
      }
      service.feature("NVDA")
      tryVerify(function() { return service.testHistoryFeed.testRetrying }, 5000)
      var closedFrom = historyCalls()
      app.close()
      service.setRange("6M")
      mouseWheel(pill, pill.width / 2, pill.height / 2, 0, -120)
      // Past the retry's pause.
      wait(3000)
      var closedCalls = historyCalls() - closedFrom
      var idle = !service.testHistoryFeed.busy
      app.open("{}")
      var reopened = within(5000, function() { return historyCalls() > closedFrom })
      harness.check("with no surface open the service fetches no history: not a pending retry, a range change, or the pill's wheel; an open asks again",
        closedCalls === 0 && idle && reopened, closedCalls + "|" + idle + "|" + reopened)
      tryVerify(function() { return !service.testFeed.busy && !service.testHistoryFeed.busy }, 10000)
      service.feature("AAPL")
      service.setRange("1M")

      app.close()
      app.open("{}")
      harness.check("a summon without a range keeps the shared one",
        service.range === "1M" && app.range === "1M", service.range + "|" + app.range)
      app.close()

      harness.readFile()
      tryVerify(function() { return harness.fileRead !== null }, 3000)
      harness.check("the file saves the range", harness.fileRead.range === "1M", JSON.stringify(harness.fileRead))

      // A restarted service, with no surface open, comes back on the range
      // and fetches no history for it. A summon whose window closed before
      // the service was ready leaves with the window.
      var closedHistory = historyCalls()
      var again = serviceAgain.createObject(harness)
      var dropped = appAgain.createObject(harness, { service: again })
      dropped.open(JSON.stringify({ symbol: "MSFT", range: "5Y" }))
      dropped.close()
      tryVerify(function() { return again.pluginsReady }, 5000)
      wait(50)
      harness.check("a restarted service comes back on the saved range", again.range === "1M", again.range)
      harness.check("a payload dropped with its window never features or sets the range",
        again.featuredSymbol === "AAPL" && again.range === "1M", again.featuredSymbol + "|" + again.range)
      wait(500)
      harness.check("a restarted service with no surface open fetches no history",
        historyCalls() === closedHistory && !again.testHistoryFeed.busy, (historyCalls() - closedHistory) + "|" + again.testHistoryFeed.busy)
      dropped.destroy()
      again.destroy()

      // A window summoned while its service starts waits for it, then shows
      // the symbol and range it asked for. Its history is held back a while.
      holdMsft.running = true
      tryVerify(function() { return !holdMsft.running }, 2000)
      again = serviceAgain.createObject(harness)
      var summoned = appAgain.createObject(harness, { service: again })
      // It draws its chart in once there is one: it used to open drawn. Its
      // body is built as it opens.
      summoned.open(JSON.stringify({ symbol: "MSFT", range: "1Y" }))
      harness.check("payload waits while the service starts",
        !again.pluginsReady && again.featuredSymbol !== "MSFT" && again.range !== "1Y",
        again.pluginsReady + "|" + again.featuredSymbol + "|" + again.range)
      // The header and the empty hero's label, each as it reads while the
      // window waits: Loading is said once, by the label. Both said it.
      var coldLabel = harness.find(summoned.testBody, "loadingLabel")
      var coldWords = harness.find(summoned.testBody, "statusText")
      var loadingSaid = []
      var countLoading = function() {
        var said = [coldWords.visible ? coldWords.text : "", coldLabel.visible ? coldLabel.text : ""]
          .filter(function(t) { return /loading/i.test(t) }).length
        if (loadingSaid.indexOf(said) < 0) loadingSaid.push(said)
      }
      coldWords.textChanged.connect(countLoading)
      coldLabel.visibleChanged.connect(countLoading)
      coldLabel.textChanged.connect(countLoading)
      tryVerify(function() { return again.pluginsReady }, 5000)
      // The window applies its summon a turn after the service is ready
      // (`App.onReadyChanged`): a ready seen at the end of a wait can come
      // before that turn.
      wait(0)
      // Before any chart has been in, the hero is empty, naming what is
      // coming: never the day, nor "No data". Found in the transition audit
      // (lifecycle 6, data 7, featured 9). Its symbol is the one coming, not
      // a dash: the design check of 16 October.
      var cold = summoned.testBody
      var coldSymbol = harness.find(cold, "heroSymbol").text
      harness.check("a cold start shows an empty hero, naming what is coming",
        cold.chart === null && cold.dayLine === null && cold.yearLine === null
          && cold.featured === null && coldSymbol === "MSFT",
        coldSymbol + "|" + JSON.stringify(cold.dayLine) + "|" + JSON.stringify(cold.yearLine) + "|" + JSON.stringify(cold.featured))
      // A quarter second on, the label over the empty hero says Loading,
      // and the header doesn't: it's said once, where a reader looks.
      harness.check("a cold start's empty hero label alone says Loading, naming what is coming",
        within(2000, function() { return coldLabel.visible }) && coldLabel.text === "Loading MSFT 1Y…"
          && cold.chart === null && coldWords.text === "",
        coldLabel.visible + "|" + coldLabel.text + "|" + coldWords.text)
      releaseMsft.running = true
      wait(50)
      harness.check("payload features its symbol",
        again.featuredSymbol === "MSFT" && summoned.featuredSymbol === "MSFT", again.featuredSymbol)
      harness.check("payload sets the shared range",
        again.range === "1Y" && summoned.range === "1Y", again.range + "|" + summoned.range)
      harness.check("the summoned window draws the range it asked for",
        within(5000, function() { return harness.showsRange(summoned, "1Y") }),
        harness.chartShown(summoned))
      coldWords.textChanged.disconnect(countLoading)
      coldLabel.visibleChanged.disconnect(countLoading)
      coldLabel.textChanged.disconnect(countLoading)
      harness.check("from the summon until its chart lands, Loading is never said twice, and the header then names the market",
        loadingSaid.indexOf(2) < 0 && loadingSaid.indexOf(1) >= 0 && coldWords.text !== "" && !/loading/i.test(coldWords.text),
        "said at once " + loadingSaid.join(",") + " | header " + coldWords.text)
      // The first service reads the summon back from the file before its own
      // window writes the next range.
      tryVerify(function() { return service.featuredSymbol === "MSFT" && service.range === "1Y" }, 5000,
        "the running service follows the file the summon wrote")
      summoned.destroy()
      again.destroy()

      app.open(JSON.stringify({ range: "1D" }))
      wait(100)
      harness.check("a summon's range sets the shared range",
        service.range === "1D" && app.range === "1D", service.range + "|" + app.range)
      app.close()

      // An add whose first fetch fails keeps the view: the hero stays on what
      // you were looking at, never "No data", and the pending add is done.
      // NOPE fails every request, like curl -f on an HTTP error. Found in
      // cubic's review of #21: the failure landed as an arrival and featured
      // a symbol with nothing to show.
      app.open("{}")
      wait(100)
      var heroBeforeFail = service.featuredSymbol
      app.testKeyCatcher.forceActiveFocus()
      keyClick(Qt.Key_A)
      tryVerify(function() { return body.adding && body.search.active }, 2000)
      var failField = harness.find(body.search, "searchField")
      failField.forceActiveFocus()
      keyClick(Qt.Key_A, Qt.ControlModifier)
      for (var letter = 0; letter < 4; letter++) keyClick("NOPE".charAt(letter))
      tryVerify(function() { return body.search.resultsQuery === "NOPE" && body.search.results.length === 1 }, 3000)
      keyClick(Qt.Key_Return)
      var failedOut = within(10000, function() { return !!service.entries.NOPE && service.entries.NOPE.status === "failed" })
      wait(200)
      harness.check("an add whose first fetch fails leaves the hero where it was",
        failedOut && service.featuredSymbol === heroBeforeFail && !!body.featuredQuote
          && service.arriving.length === 0 && body.landing === "",
        failedOut + "|" + heroBeforeFail + "->" + service.featuredSymbol + "|" + service.arriving + "|" + body.landing)
      service.removeSymbol("NOPE")
      app.close()

      // A hover only where the pill can't say it: the text, the line, and
      // the arrow show their symbol and change, so theirs is quiet; the
      // icon's says the symbol and its change, which the animal can't show.
      // The owner's rule of 15 October: tooltips sparingly.
      var quietSymbol = service.featuredSymbol
      var quietTips = hoverEveryForm()
      harness.check("only the icon pill's hover says anything, the symbol and its change; the text's, the line's, and the arrow's are quiet",
        quietTips.slice(0, 3).join(" | ") === 'text "" | sparkline "" | arrow ""'
          && quietTips[3].indexOf('icon "' + quietSymbol + " ") === 0 && quietTips[3].indexOf(" · ") < 0,
        quietTips.join(" | "))

      // A featured symbol whose first fetch is out is only on its way; once
      // that fetch has failed, the pill says so.
      service.addSymbol("FAIL")
      service.feature("FAIL")
      var pillChange = harness.find(pill, "pillChange")
      // The icon form has no animal to show yet: it says "…" as the text does.
      var waitingSettings = pill.settings
      pill.settings = Object.assign({}, waitingSettings, { barStyle: "icon" })
      var waitingIcon = harness.iconDrawn()
      pill.settings = waitingSettings
      harness.check("the pill waits quietly while the first fetch is out, the icon form with no animal",
        service.featuredSymbol === "FAIL" && pillChange.text === "…" && waitingIcon === "…",
        service.featuredSymbol + "|" + pillChange.text + "|" + waitingIcon)
      harness.check("the pill says no data when the first fetch failed",
        within(10000, function() { return pillChange.text === "! No data" }), pillChange.text)
      // The "!" names itself on hover on every form, the text's included,
      // in the popup's words; the text's says nothing else.
      var warningTips = hoverEveryForm()
      harness.check("hovering a pill with a failed first fetch says so on every form, and the text form says only that",
        warningTips.slice(0, 3).join(" | ") === 'text "NO DATA FOR THIS SYMBOL" | sparkline "NO DATA FOR THIS SYMBOL" | arrow "NO DATA FOR THIS SYMBOL"'
          && /^icon "FAIL .* · NO DATA FOR THIS SYMBOL"$/.test(warningTips[3]),
        warningTips.join(" | "))
      // The icon form, on the top bar and a side bar, and the side bar's
      // stacked form show the "!" too, the stacked one naming its symbol;
      // the icon form's stands alone, with no animal to stand beside.
      // Found in the 1.0.0 review: they looked healthy, the stacked form
      // saying "ST …" as if still loading.
      var formsWarn = function() {
        var settingsWas = pill.settings
        var said = []
        ;[false, true].forEach(function(vertical) {
          barApi.vertical = vertical
          barApi.barSize = vertical ? Style.bar.sizeVertical : 0
          pill.settings = Object.assign({}, settingsWas, vertical ? { barStyleVertical: "icon" } : { barStyle: "icon" })
          said.push((vertical ? "side icon " : "icon ") + harness.iconDrawn())
        })
        pill.settings = Object.assign({}, settingsWas, { barStyleVertical: "stacked" })
        said.push("stacked " + harness.find(pill, "pillStack").children.filter(function(c) { return c.objectName === "pillStackLine" })
          .map(function(l) { return l.text }).join("/"))
        barApi.vertical = false
        barApi.barSize = 0
        pill.settings = settingsWas
        return said.join(", ")
      }
      var failedForms = formsWarn()
      harness.check("after a failed first fetch the icon form, on either bar, shows the \"!\" alone, and the stacked form shows it naming its symbol",
        failedForms === "icon !, side icon !, stacked FAIL/!", failedForms)
      // The window says the same where it says it: the header "No data",
      // the hero's line "! NO DATA FOR THIS SYMBOL", as the row says it.
      // Found in the design pass of 14 October: "NO QUOTE", "! REFRESH
      // FAILED · NO DATA", and "! No data for this symbol" for one fact, and
      // nothing was ever there to refresh.
      app.open("{}")
      wait(100)
      var failedWords = [body.headerText, harness.find(body, "hero").listingLead,
        body.watchlist.rowItem("FAIL") ? body.watchlist.rowItem("FAIL").detail : ""].join(" | ")
      app.close()
      harness.check("a symbol whose first fetch failed is said one way: No data, for this symbol",
        failedWords === "No data | ! NO DATA FOR THIS SYMBOL | ! No data for this symbol", failedWords)

      // A warning that ends while the pointer stays on the pill leaves no
      // bubble naming it: the text pill's goes, and the icon's loses the
      // warning's words. The bar keeps one bubble, as the shell's does: a
      // show replaces it, an empty one clears it, a hide takes it away. LATE
      // fails while LATE.down exists (the fake curl).
      var bubble = ""
      var lateEntryAged = function() {
        var entries = Object.assign({}, service.testFeed.entries)
        entries.LATE = Object.assign({}, entries.LATE, { answeredAt: entries.LATE.answeredAt - 20 })
        service.testFeed.entries = entries
      }
      var settingsBeforeLate = pill.settings
      var warnsThenLands = function(form) {
        if (!pill.warns) {
          lateDown.running = true
          tryVerify(function() { return !lateDown.running }, 2000)
          lateEntryAged()
          service.refresh()
          tryVerify(function() { return pill.warns }, 10000)
        }
        pill.settings = Object.assign({}, settingsBeforeLate, { barStyle: form })
        mouseMove(pill, pill.width / 2, -5)
        wait(20)
        barApi._showTooltip = function(target, text) { bubble = text }
        barApi._hideTooltip = function(target) { bubble = "" }
        mouseMove(pill, pill.width / 2, pill.height / 2)
        wait(20)
        var warned = bubble
        lateUp.running = true
        tryVerify(function() { return !lateUp.running }, 2000)
        lateEntryAged()
        service.refresh()
        tryVerify(function() { return !pill.warns }, 10000)
        wait(20)
        var landed = bubble
        mouseMove(pill, pill.width / 2, -5)
        wait(20)
        barApi._showTooltip = null
        barApi._hideTooltip = null
        return [form, JSON.stringify(warned), JSON.stringify(landed)]
      }
      lateDown.running = true
      tryVerify(function() { return !lateDown.running }, 2000)
      service.addSymbol("LATE")
      service.feature("LATE")
      tryVerify(function() { return pill.warns }, 10000)
      var textLanding = warnsThenLands("text")
      var iconLanding = warnsThenLands("icon")
      // A quote landing under a resting pointer, with no warning involved,
      // leaves the bubble as it opened: its figures stay, and it never
      // blinks, though the pill's words have moved on.
      pill.settings = Object.assign({}, settingsBeforeLate, { barStyle: "icon" })
      var widget = null
      for (var wc = 0; wc < pill.children.length; wc++) if (pill.children[wc].tooltipText !== undefined) widget = pill.children[wc]
      var shows = 0
      mouseMove(pill, pill.width / 2, -5)
      wait(20)
      barApi._showTooltip = function(target, text) { shows++; bubble = text }
      barApi._hideTooltip = function(target) { bubble = "" }
      mouseMove(pill, pill.width / 2, pill.height / 2)
      wait(20)
      var opened = bubble
      var quotesBeforeRest = service.testFeed.quotes
      var risen = Object.assign({}, quotesBeforeRest)
      risen.LATE = Object.assign({}, risen.LATE, { price: risen.LATE.price + 10 })
      service.testFeed.quotes = risen
      wait(100)
      var resting = [shows, JSON.stringify(opened), JSON.stringify(bubble), JSON.stringify(widget.tooltipText), pill.warns]
      // A wheel step under the resting pointer puts another symbol on the
      // pill: the bubble names that one, once. Found in the mouse audit: it
      // kept the old company until the pointer left and came back.
      service.testFeed.quotes = quotesBeforeRest
      wait(100)
      var showsBeforeWheel = shows
      mouseWheel(pill, pill.width / 2, pill.height / 2, 0, -120)
      tryVerify(function() { return service.featuredSymbol !== "LATE" }, 2000)
      wait(100)
      var wheeled = [shows - showsBeforeWheel, service.featuredSymbol, JSON.stringify(bubble)]
      mouseMove(pill, pill.width / 2, -5)
      wait(20)
      barApi._showTooltip = null
      barApi._hideTooltip = null
      service.testFeed.quotes = quotesBeforeRest
      harness.check("a quote landing under a resting pointer, with no warning, leaves the bubble as it opened",
        resting[0] === 1 && /^"LATE /.test(resting[1]) && resting[2] === resting[1] && resting[3] !== resting[1] && resting[4] === false,
        resting.join(" | "))
      harness.check("a wheel step under a resting pointer shows the bubble again, naming the symbol now on the pill",
        wheeled[0] === 1 && wheeled[1] !== "LATE" && wheeled[2].indexOf('"' + wheeled[1] + " ") === 0,
        wheeled.join(" | "))
      pill.settings = settingsBeforeLate
      service.feature("FAIL")
      service.removeSymbol("LATE")
      harness.check("an answer landing under the pointer takes the warning out of the bubble: the text pill's goes, the icon's keeps the rest",
        textLanding[1] === '"NO DATA FOR THIS SYMBOL"' && textLanding[2] === '""'
          && /^"LATE .* · REFRESH FAILED · AS OF /.test(iconLanding[1]) && /^"LATE /.test(iconLanding[2]) && iconLanding[2].indexOf("REFRESH") < 0,
        textLanding.join(" ") + " | " + iconLanding.join(" "))

      // While a chart loads, the hero keeps what was on screen, chart,
      // figures, and info lines alike, under "Loading", and the new chart
      // draws in once it lands: from a range to another, cached or not, and
      // on a symbol change on a range. Found by the owner on main: 1W to an
      // uncached 6M showed the day's chart for a moment first. Every state
      // the hero ends a turn in is recorded, the states a frame can show;
      // SLOW's history answers after a second.
      app.open("{}")
      wait(100)
      service.addSymbol("SLOW")
      // FAIL, added above, may still be in its retries ahead of SLOW.
      tryVerify(function() { return !!service.quotes.SLOW && service.arriving.length === 0 }, 15000)
      service.summon("SLOW", "1W")
      tryVerify(function() { return harness.answered("SLOW|1W") }, 5000)
      var sig = function() {
        return JSON.stringify([body.featuredGeometry, body.featured ? body.featured.priceText + " " + body.featured.changeLine : "",
          JSON.stringify(body.periodLine), JSON.stringify(body.rangeMarks), body.chartSymbol])
      }
      var dropEntry = function(key) {
        var next = Object.assign({}, service.testHistoryFeed.entries)
        delete next[key]
        service.testHistoryFeed.entries = next
      }
      // Switches with `change`, runs `during` while the new chart is out,
      // waits for `key` to land, and returns the states the hero took, "A"
      // for the one before, "B" for the one it settles on, "?" for any other,
      // run-length collapsed; how many held-A states said Loading and how many
      // did not; once the new chart is up, whether it drew in and whether a
      // replay or scrub ran on it; and the dim: the most it reached in the
      // first 200 ms, whether it reached whole while held, what the label
      // said then, and what was left of it a moment after the landing.
      var switchChart = function(change, key, during) {
        var a = sig()
        var seen = [a]
        var changed = false
        var loadingUnderA = 0
        var quietUnderA = 0
        var record = function() {
          var s = sig()
          if (s !== seen[seen.length - 1]) seen.push(s)
          if (changed && s === a) {
            if (body.headerText.indexOf("Loading") === 0) loadingUnderA++
            else quietUnderA++
          }
        }
        // At the end of the turn, when the change is whole and a frame can draw it.
        var later = function() { Qt.callLater(record) }
        body.featuredGeometryChanged.connect(later)
        body.featuredChanged.connect(later)
        body.periodLineChanged.connect(later)
        body.rangeMarksChanged.connect(later)
        change()
        changed = true
        Qt.callLater(record)
        if (during) during()
        tryVerify(function() { return harness.answered(key) }, 5000)
        wait(20)
        record()
        body.featuredGeometryChanged.disconnect(later)
        body.featuredChanged.disconnect(later)
        body.periodLineChanged.disconnect(later)
        body.rangeMarksChanged.disconnect(later)
        var b = sig()
        return { states: seen.map(function(s) { return s === a ? "A" : s === b ? "B" : "?" }).join(""),
          loading: loadingUnderA > 0 && quietUnderA === 0, carried: body.motion.replayRunning || body.scrubT !== 0 }
      }
      var toSixMonths = switchChart(function() { service.setRange("6M") }, "SLOW|6M")
      harness.check("1W to an uncached 6M keeps 1W under Loading until 6M lands",
        toSixMonths.states === "AB" && toSixMonths.loading && !toSixMonths.carried,
        JSON.stringify(toSixMonths))
      var toCachedWeek = switchChart(function() { service.setRange("1W") }, "SLOW|1W")
      harness.check("6M to a cached 1W goes straight to 1W", toCachedWeek.states === "AB",
        JSON.stringify(toCachedWeek))
      service.setRange("6M")
      tryVerify(function() { return harness.answered("SLOW|6M") }, 5000)
      dropEntry("SLOW|1W")
      // A held chart takes no replay: 1W draws in clean.
      var toUncachedWeek = switchChart(function() { service.setRange("1W") }, "SLOW|1W", function() {
        wait(50)
        body.replay()
      })
      harness.check("6M to an uncached 1W keeps 6M under Loading until 1W lands, with no replay on the held chart",
        toUncachedWeek.states === "AB" && toUncachedWeek.loading && !toUncachedWeek.carried
          && !body.motion.replayRunning && body.scrubT === 0, JSON.stringify(toUncachedWeek))
      service.feature("AAPL")
      tryVerify(function() { return harness.answered("AAPL|1W") }, 5000)
      dropEntry("SLOW|1W")
      var toSlowWeek = switchChart(function() { service.feature("SLOW") }, "SLOW|1W")
      harness.check("a symbol change on a range keeps the last symbol's chart and figures until the new one lands",
        toSlowWeek.states === "AB" && toSlowWeek.loading && !toSlowWeek.carried,
        JSON.stringify(toSlowWeek))
      // A second request supersedes the first; the selected data wins.
      dropEntry("AAPL|1W")
      service.feature("AAPL")
      tryVerify(function() { return !body.chartLoading }, 5000)
      service.feature("SLOW")
      tryVerify(function() { return !body.chartLoading }, 5000)
      dropEntry("SLOW|1M")
      dropEntry("SLOW|3M")
      var selectedRanges = []
      var latestRange = function() {
        var said = body.chartSymbol + "|" + body.chartRange
        if (selectedRanges[selectedRanges.length - 1] !== said) selectedRanges.push(said)
      }
      body.chartChanged.connect(latestRange)
      latestRange()
      service.setRange("1M")
      service.setRange("3M")
      tryVerify(function() { return harness.answered("SLOW|3M") && !service.testHistoryFeed.busy }, 5000)
      waitForRendering(body)
      latestRange()
      body.chartChanged.disconnect(latestRange)
      harness.check("a second range requested while another is out shows only the latest answer",
        selectedRanges.every(function(range) { return range === "SLOW|1W" || range === "SLOW|3M" }) && body.chartRange === "3M" && body.chartSymbol === "SLOW",
        selectedRanges.join(" -> "))
      service.setRange("1D")

      // On the day, a symbol whose first fetch failed is an answer too: the
      // hero shows it, with no quote, and holds nothing, whether it failed
      // before the choice (FAIL, added above) or while it was held (NOPEB).
      service.feature("AAPL")
      wait(100)
      service.feature("FAIL")
      var failedAtOnce = !body.chartLoading && body.chartSymbol === "FAIL"
      service.feature("AAPL")
      wait(100)
      service.addSymbol("NOPEB")
      service.feature("NOPEB")
      var heldWhileOut = body.chartLoading && body.chartSymbol === "AAPL"
      tryVerify(function() { return service.entries.NOPEB && service.entries.NOPEB.status === "failed" }, 15000)
      wait(50)
      harness.check("a symbol whose first quote failed is shown at once, or once it fails, never held behind the last",
        failedAtOnce && heldWhileOut && !body.chartLoading && body.chartSymbol === "NOPEB",
        failedAtOnce + "|" + heldWhileOut + "|" + body.chartLoading + "|" + body.chartSymbol)
      service.removeSymbol("NOPEB")
      app.close()
      chartOnShow(body)
      service.removeSymbol("SLOW")

      // On 6M every bar style, in both looks, shows the featured symbol's
      // day, as its row does, and names no range; so does the vertical bar.
      // DOWN's day fell and its history rose, so a figure or a colour from
      // the range shows. FAIL, added above, would keep DOWN's first fetch
      // behind its retries.
      service.removeSymbol("FAIL")
      service.addSymbol("DOWN")
      tryVerify(function() { return !!service.quotes.DOWN && service.arriving.length === 0 }, 10000)
      app.open(JSON.stringify({ symbol: "DOWN", range: "6M" }))
      tryVerify(function() { return harness.answered("DOWN|6M") }, 5000)
      app.close()
      var downDay = Figures.rowModel(service.quotes.DOWN, 0, service.changeMode)
      var downRange = History.historyRowModel(service.histories["DOWN|6M"].history, service.quotes.DOWN, 0)
      var dayWrong = pillInEveryStyle(function(retro) { return Format.lookSigns(downDay.changeLine, retro) }, Commons.Color.urgent)
      harness.check("on 6M every bar style in both looks shows the day in its colour, and a middle-click keeps the entry's other keys",
        service.range === "6M" && downDay.tone === "down" && downRange.tone === "up" && dayWrong.length === 0,
        service.range + " " + downDay.tone + "/" + downRange.tone + " " + dayWrong.join(" | "))

      // A vertical bar is as wide as the shell's bar makes it (Bar.qml's
      // barSize), and the pill takes that width. There it is its icon, as
      // Omarchy's text widgets fall back to theirs, until a middle-click
      // there picks the symbol over its change.
      barApi.vertical = true
      barApi.barSize = Style.bar.sizeVertical
      var verticalWrong = []
      var stackWarned = []
      var settingsBefore = pill.settings
      // The stacked form's lines as drawn: text, ink width, size, colour.
      var stackLines = function() {
        return harness.find(pill, "pillStack").children.filter(function(c) { return c.objectName === "pillStackLine" })
      }
      for (var vlook = 0; vlook < 2; vlook++) {
        service.persist({ style: vlook === 0 ? "smooth" : "retro" })
        var stack = harness.find(pill, "pillStack")
        pill.settings = Object.assign({}, settingsBefore, {barStyleVertical: "icon"})
        if (harness.iconDrawn() !== "bear in " + Commons.Color.urgent) verticalWrong.push("icon " + harness.iconDrawn())
        // The icon form, whatever the top bar's: the bear alone, in one
        // slot.
        // Stacked, as Omarchy's clock stacks a vertical bar's lines: DOWN
        // over its move, a percent over its %, or in money split at its
        // point, one line to an icon slot, each inside the bar at the bar's
        // size or 90% of it, never smaller. Its five-character change ran a
        // pixel past each side. Between them, the warning's short line, empty.
        pill.settings = Object.assign({}, settingsBefore, { barStyleVertical: "stacked" })
        ;["pct", "abs"].forEach(function(mode) {
          service.persist({ changeMode: mode })
          var day = Figures.rowModel(service.quotes.DOWN, 0, service.changeMode)
          var move = mode === "abs" ? Format.stackedMoney(day.abs, service.quotes.DOWN.priceDigits) : Format.stackedPct(day.pct)
          var want = [["DOWN", barApi.barForeground], ["", barApi.barForeground]].concat(move.lines.map(function(t) {
            return [Format.lookSigns(t, service.retro), Commons.Color.urgent]
          }))
          var lines = stackLines()
          if (lines.length !== want.length || lines.some(function(line, i) { return line.text !== want[i][0] || !Qt.colorEqual(line.color, want[i][1]) }))
            verticalWrong.push(mode + ": " + lines.map(function(line) { return line.text }).join("/"))
        })
        service.persist({ changeMode: "pct" })
        // A failed refresh puts its "!" on the warning's line, and the pill
        // keeps its height and its move where they were. Found in the 1.0.2
        // visual review: the "!" took a line of its own, 81 px to 108.
        var freshEntries = service.testFeed.entries
        service.testFeed.entries = Object.assign({}, freshEntries, { DOWN: Object.assign({}, freshEntries.DOWN, { status: "failed" }) })
        if (!stackLines().some(function(line) { return line.text === "!" })) stackWarned.push("missing failed-refresh warning")
        service.testFeed.entries = freshEntries
        pill.settings = settingsBefore
      }
      var entriesBeforeFail = service.testFeed.entries
      var sideWrong = false
      ;["left", "right"].forEach(function(side) {
        barApi.position = side
        service.testFeed.entries = Object.assign({}, entriesBeforeFail, { DOWN: Object.assign({}, entriesBeforeFail.DOWN, { status: "failed" }) })
        if (!pill.warns || !harness.find(pill, "pillWarning").visible) sideWrong = true
      })
      service.testFeed.entries = entriesBeforeFail
      barApi.position = "top"
      harness.check("a failed refresh warns on either side bar", !sideWrong)
      // Each bar keeps its own form: a saved arrow stays the arrow on a
      // horizontal bar while a vertical one shows the icon, and a
      // middle-click there steps between the icon and the symbol over its
      // change without touching the arrow. The arrow, the line, and the text
      // used to share one setting with the vertical bar, so a middle-click
      // there lost the arrow.
      pill.settings = Object.assign({}, settingsBefore, { barStyle: "arrow" })
      var drawn = function() {
        return pill.barStyle + " " + (harness.find(pill, "pillIcon").visible ? "icon" : harness.find(pill, "pillStack").visible ? "stacked"
          : harness.find(pill, "pillArrow").visible ? "arrow" : "nothing")
      }
      var walk = [drawn()]
      barApi.vertical = false
      barApi.barSize = 0
      walk.push(drawn())
      barApi.vertical = true
      barApi.barSize = Style.bar.sizeVertical
      for (var vclick = 0; vclick < 3; vclick++) {
        mouseClick(pill, pill.width / 2, pill.height / 2, Qt.MiddleButton)
        harness.middleClicks++
        walk.push(drawn())
      }
      barApi.vertical = false
      barApi.barSize = 0
      walk.push(drawn())
      pill.settings = settingsBefore
      service.persist({ style: "smooth" })
      harness.check("the vertical stacked form names the day's symbol and change in both modes and looks",
        verticalWrong.length === 0, verticalWrong.join(" | "))
      harness.check("a failed refresh warns on the stacked form in both looks",
        stackWarned.length === 0, stackWarned.join(" | "))
      harness.check("a horizontal bar's arrow and a vertical bar's form are kept apart, and on a vertical bar every middle-click changes what shows",
        walk.join(",") === "icon icon,arrow arrow,stacked stacked,icon icon,stacked stacked,arrow arrow", walk.join(","))

      // In the bar's right section, among its bare icons, the pill shows its
      // icon until a middle-click there picks another form, which it keeps
      // for the right; the centre and left keep theirs, and a move brings
      // back each section's own. It used to show its full form on the right.
      var settingsBeforeMove = pill.settings
      var writesBeforeMove = harness.entryWrites.length
      var formIn = function(section) {
        var layout = { left: [], center: [], right: [] }
        layout[section] = [{ id: "grvc.stonks" }]
        barApi.layoutConfig = layout
        var alone = harness.find(pill, "pillIcon").visible && !harness.find(pill, "pillSymbol").visible
        return pill.barStyle + (alone ? " alone" : "")
      }
      var middleClick = function() {
        mouseClick(pill, pill.width / 2, pill.height / 2, Qt.MiddleButton)
        harness.middleClicks++
      }
      var centreForm = formIn("center")
      var movedRight = formIn("right")
      // The icon form is the day's animal, as the header's: the bull on an
      // up day and the bear on a down one, each in its colour, and on a flat
      // day neither, a level line in the dim.
      var upSymbol = service.library.filter(function(s) {
        return !!service.quotes[s] && Figures.animalKind(Figures.rowModel(service.quotes[s], 0, service.changeMode)) === "bull"
      })[0] || ""
      service.feature(upSymbol)
      var onUpDay = upSymbol + " " + harness.iconDrawn()
      service.feature("DOWN")
      var onDownDay = "DOWN " + harness.iconDrawn()
      var quotesBeforeFlat = service.testFeed.quotes
      var flat = Object.assign({}, quotesBeforeFlat)
      flat.DOWN = Object.assign({}, quotesBeforeFlat.DOWN, { prevClose: quotesBeforeFlat.DOWN.price })
      service.testFeed.quotes = flat
      var onFlatDay = "DOWN " + harness.iconDrawn()
      service.testFeed.quotes = quotesBeforeFlat
      middleClick()
      middleClick()
      var pickedRight = pill.barStyle
      var moveWrites = harness.entryWrites.slice(writesBeforeMove)
      var wrote = moveWrites.length ? moveWrites[moveWrites.length - 1].settings : {}
      var backInCentre = formIn("center")
      var onLeft = formIn("left")
      var backOnRight = formIn("right")
      barApi.layoutConfig = ({})
      pill.settings = settingsBeforeMove
      harness.check("on the right the pill is its icon, the bull on an up day, the bear on a down one, and a level line on a flat one, until a middle-click there picks a form, kept for the right; the centre and left keep theirs",
        centreForm === "sparkline" && movedRight === "icon alone" && pickedRight === "arrow"
          && onUpDay === upSymbol + " bull in #9ece6a" && upSymbol !== "" && onDownDay === "DOWN bear in " + Commons.Color.urgent
          && onFlatDay === "DOWN level"
          && wrote.barStyleRight === "arrow" && wrote.barStyle === "sparkline"
          && backInCentre === "sparkline" && onLeft === "sparkline" && backOnRight === "arrow",
        [centreForm, movedRight, onUpDay, onDownDay, onFlatDay, pickedRight, JSON.stringify(wrote), backInCentre, onLeft, backOnRight].join(" | "))

      // Only a middle-click writes the bar entry: every look, range, and
      // list this flow changed is the data file's.
      service.createList("Held")
      service.switchList("")
      service.setRange("1D")
      wait(50)
      harness.check("looks, ranges, and lists never write the bar entry; only a middle-click does",
        harness.entryWrites.length === harness.middleClicks, harness.middleClicks + " clicks, " + JSON.stringify(harness.entryWrites))
      // Up and down are the theme's green and red, Tokyo Night's #9ece6a and
      // #f7768e, never its blue accent, and follow a theme switch:
      // omarchy-theme-set puts the new theme's files in place and then hands
      // the shell its palette and its shell.toml, and the plugin reads the
      // new file then. Each theme's green differs, so the read has landed
      // once the green has changed. Hackerman's green and red are both
      // greens and Solitude's two greys, so there up and down are Stonks'
      // own pair for a dark bar, and White's, two near-blacks, its pair for
      // a light one. A theme that differs from the last in its green alone
      // (Tokyo Night with Kanagawa's) is read too: found in review, its
      // green stayed the last one's.
      var change = harness.find(pill, "pillChange")
      var dayColours = function(theme) {
        service.feature("DOWN")
        var down = String(change.color)
        service.feature(upSymbol)
        return theme + " " + change.color + " " + down
      }
      var daysIn = function(theme, command) {
        var before = plugin.trendColors.green
        harness.themeCopied = false
        themeCopy.command = command || ["cp", "/usr/share/omarchy/themes/" + theme + "/colors.toml", harness.themeDir + "/colors.toml"]
        themeCopy.running = true
        tryVerify(function() { return harness.themeCopied }, 2000)
        var view = Qt.createQmlObject('import Quickshell.Io; FileView { blockLoading: true }', harness)
        view.path = harness.themeDir + "/colors.toml"
        Commons.Color.loadColors(view.text())
        Commons.Color.loadShell("")
        view.destroy()
        within(2000, function() { return plugin.trendColors.green !== before })
        return dayColours(theme)
      }
      var greenOnly = ["sh", "-c", "sed 's/^green = .*/green = \"#76946a\"/' /usr/share/omarchy/themes/tokyo-night/colors.toml > '"
        + harness.themeDir + "/colors.toml'"]
      var trendColours = [dayColours("tokyo-night"), daysIn("hackerman"), daysIn("solitude"), daysIn("white"), daysIn("kanagawa"),
        daysIn("tokyo-night"), daysIn("tokyo-night with kanagawa's green", greenOnly), daysIn("tokyo-night")]
      harness.check("up and down are the theme's green and red and follow a theme switch, Stonks' own pair for the bar's ground where the theme has none",
        trendColours.join(" | ") === "tokyo-night #9ece6a #f7768e | hackerman #3fb950 #f85149 | solitude #3fb950 #f85149"
          + " | white #116329 #a40e26 | kanagawa #76946a #c34043 | tokyo-night #9ece6a #f7768e"
          + " | tokyo-night with kanagawa's green #76946a #f7768e | tokyo-night #9ece6a #f7768e",
        trendColours.join(" | "))

      // The pill's animal turns with its own day: a new price that takes
      // TURN below its close leaves the bear, every column in the down
      // colour, and one back above it the bull, every column in the up
      // colour. A wheel step to another symbol shows that one's animal at
      // once, and back again. (popup-motion.sh judges the turn's frames.)
      var settingsBeforeTurn = pill.settings
      barApi.layoutConfig = { left: [], center: [], right: [{ id: "grvc.stonks" }] }
      service.addSymbol("TURN")
      tryVerify(function() { return !!service.quotes.TURN && service.arriving.length === 0 }, 10000)
      service.feature("TURN")
      var animal = harness.find(pill, "pillAnimal")
      var kindOf = function(symbol, mode) { return Figures.animalKind(Figures.rowModel(service.quotes[symbol], 0, mode || service.changeMode)) }
      var animalOf = function(symbol) {
        var kind = kindOf(symbol)
        return kind === "" ? "level" : kind + " in " + (kind === "bull" ? pill.upColor : pill.downColor)
      }
      var newPrice = function(down) {
        var proc = down ? turnDown : turnUp
        proc.running = true
        tryVerify(function() { return !proc.running }, 2000)
        var entries = Object.assign({}, service.testFeed.entries)
        entries.TURN = Object.assign({}, entries.TURN, { answeredAt: entries.TURN.answeredAt - 20 })
        service.testFeed.entries = entries
        service.refresh()
        tryVerify(function() { return kindOf("TURN") === (down ? "bear" : "bull") }, 10000)
        return harness.iconDrawn()
      }
      var turnStart = harness.iconDrawn()
      var turnedDown = newPrice(true)
      var turnedUp = newPrice(false)
      // Wheel steps until one lands on a symbol with the other animal, each
      // step's animal checked as it lands.
      var wheels = []
      for (var w = 0; w < 3; w++) {
        var before = harness.iconDrawn()
        mouseWheel(pill, pill.width / 2, pill.height / 2, 0, w === 0 ? -120 : 120)
        wheels.push(service.featuredSymbol + " " + "" + harness.iconDrawn()
          + (harness.iconDrawn() === animalOf(service.featuredSymbol) ? "" : " want " + animalOf(service.featuredSymbol)))
        if (harness.iconDrawn() !== before && service.featuredSymbol !== "TURN") break
      }
      var wheelsRight = wheels.every(function(line) { return !/turning| want /.test(line) })
        && harness.iconDrawn() !== animalOf("TURN")
      harness.check("a new price and a wheel step give the pill the current day's animal and its colour",
        turnStart === animalOf("TURN") && turnedDown === "bear in " + pill.downColor
          && turnedUp === "bull in " + pill.upColor && wheelsRight,
        [turnStart, turnedDown, turnedUp].concat(wheels).join(" | "))
      // The animal is the day against its close in every change mode, as
      // the header's is: "since open", reading TURN's day the other way,
      // neither changes nor turns it.
      service.feature("TURN")
      tryVerify(function() { return !!pill.featured && pill.featured.symbol === "TURN" }, 2000)
      var toneIn = function(mode) { return Figures.rowModel(service.quotes.TURN, 0, mode).tone }
      if (toneIn("open") === toneIn("pct")) newPrice(true)
      var modeFlip = toneIn("pct") + " to " + toneIn("open")
      var pctAnimal = harness.iconDrawn()
      service.persist({ changeMode: "open" })
      var modeAnimal = harness.iconDrawn()
      service.persist({ changeMode: "pct" })
      harness.check("a change of mode leaves the pill's animal reading its day against the close",
        toneIn("open") !== toneIn("pct") && modeAnimal === pctAnimal && pctAnimal === animalOf("TURN"),
        modeFlip + ": " + modeAnimal + ", " + pctAnimal + " in pct")
      barApi.layoutConfig = ({})
      pill.settings = settingsBeforeTurn
      service.feature(upSymbol)
      service.removeSymbol("TURN")

      service.removeSymbol("DOWN")

      // A removed symbol's cap and P/E stay only while its removal can be
      // undone. (What the history cache keeps is ahead.sh's tall window.)
      var withFigures = service.library.filter(function(s) { return !!service.fundamentals[s] && s !== service.featuredSymbol })
      var gone = withFigures[0] || ""
      var other = service.library.filter(function(s) { return s !== gone && s !== service.featuredSymbol })[0]
      service.removeSymbol(gone)
      wait(50)
      var keptForUndo = !!service.fundamentals[gone]
      service.removeSymbol(other)
      wait(50)
      harness.check("a removed symbol's cap and P/E stay while its removal can be undone, and go after",
        gone !== "" && keptForUndo && !service.fundamentals[gone],
        gone + ": " + keptForUndo + " then " + !!service.fundamentals[gone])

      harness.finish()
    }
  }

  HarnessExit { id: done }
}
