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
    var wanted = source.testHistoryFeed.wanted
    return !!entry && entry.status === "ok" && !(wanted && wanted.key === key)
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

  // Which way the pill's mark goes, as drawn: its cells' caps from the left.
  function markWay(mark) {
    var caps = []
    var collect = function(item) {
      if (item.objectName === "markCell") caps.push(item)
      for (var i = 0; i < item.children.length; i++) collect(item.children[i])
    }
    collect(mark)
    caps.sort(function(a, b) { return a.parent.x - b.parent.x })
    if (caps.length < 2) return "no cells"
    var first = caps[0].y
    var last = caps[caps.length - 1].y
    return first > last ? "climbs" : first < last ? "falls" : "flat"
  }

  // The pill's mark as drawn: which way it goes, and each column's colour
  // from the left.
  function markDrawn(mark) {
    var caps = []
    var collect = function(item) {
      if (item.objectName === "markCell") caps.push(item)
      for (var i = 0; i < item.children.length; i++) collect(item.children[i])
    }
    collect(mark)
    caps.sort(function(a, b) { return a.parent.x - b.parent.x })
    return markWay(mark) + " in " + caps.map(function(c) { return String(c.color) }).join(" ")
  }

  // A window's info line: titled by its range, with the range's high once
  // its history is in; the day's otherwise.
  function infoLine(window) {
    return JSON.stringify(window.testBody.periodLine)
  }
  function showsRange(window, range) {
    var line = window.testBody.periodLine
    return window.testBody.chartRange === range && !!line && line.title === range.toUpperCase() && line.range.highText !== ""
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
    // `expected(retro)` and `tone`, and for the icon form the mark alone,
    // falling, in `tone`. Each middle-click hands the shell the entry's
    // other keys with the next style, and writes no data file. Returns what
    // was wrong.
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
          var mark = harness.find(pill, "pillMark")
          var symbolShown = harness.find(pill, "pillSymbol").visible
          var want = expected(service.retro)
          var where = pill.barStyle + " " + (service.retro ? "retro" : "smooth")
          if (pill.barStyle === "icon") {
            if (!mark.visible || arrow.visible || change.visible || symbolShown || !Qt.colorEqual(mark.color, tone)
                || harness.markWay(mark) !== "falls")
              wrong.push(where + ": mark " + mark.visible + " in " + mark.color + ", " + harness.markWay(mark) + ", arrow "
                + arrow.visible + ", symbol " + symbolShown + ", change " + change.visible + "; want the mark alone, falling, in " + tone)
          } else if (harness.pillText() !== want || !Qt.colorEqual(change.color, tone) || !symbolShown || !change.visible) {
            wrong.push(where + ": " + harness.pillText() + " in " + change.color + ", want " + want + " in " + tone)
          }
          // The text form alone says the price, the row's, between the
          // symbol and the change: "DOWN 95.00 −5.00%".
          var price = harness.find(pill, "pillPrice")
          var priceShown = price && price.visible ? price.text : ""
          var priceWant = pill.barStyle === "text"
            ? Figures.rowModel(service.quotes[service.featuredSymbol], 0, service.changeMode).priceText : ""
          var after = priceWant === "" || within(1000, function() { return price.x > harness.find(pill, "pillSymbol").x })
          if (priceShown !== priceWant || !after)
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
        tryVerify(function() { return harness.answered(key) && !body.chartLoading && body.motion.drawn === 1 }, 5000)
      }
      var hero = function() { return body.chartSymbol + " " + (body.featured ? body.featured.priceText : "") + " " + JSON.stringify(body.periodLine) }
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
        var lowest = 1
        var dimmedLater = false
        var watch = function() { if (!body.chartLoading) lowest = Math.min(lowest, body.motion.drawn) }
        var watchDim = function() { if (body.chartLoading && body.motion.dimmed === 1) dimmedLater = true }
        body.motion.drawnChanged.connect(watch)
        body.motion.dimmedChanged.connect(watchDim)
        change()
        var held = [hero() === shown, body.motion.drawn === 1, body.headerText === coming, body.motion.dimmed === 0].join(",")
        body.replay()
        var noReplay = !body.motion.replayRunning
        settle(key)
        body.motion.drawnChanged.disconnect(watch)
        body.motion.dimmedChanged.disconnect(watchDim)
        return held + "," + noReplay + "," + dimmedLater + "," + (lowest < 0.5 ? "draw" : "none") + " " + hero() + " " + body.headerText
      }
      var stepped = opensHeld("AAPL", function() { service.feature("SLOW"); app.open("{}") }, "SLOW|1W", "Loading SLOW 1W")
      var summoned = opensHeld("AAPL", function() { app.open(JSON.stringify({ symbol: "SLOW", range: "1M" })) }, "SLOW|1M", "Loading SLOW 1M")
      harness.check("an open while the chart is on its way shows the last one whole, names what is coming, dims it a quarter second on, then draws it in",
        /^true,true,true,true,true,true,draw /.test(stepped) && /^true,true,true,true,true,true,draw /.test(summoned), stepped + " | " + summoned)

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

      // A retry of a range whose first fetch failed keeps the day and says it
      // is unavailable until an answer lands: by r in the window, by the
      // header's RETRY, and by an open. NVDA's history always fails. Found
      // in the transition audit (ranges 7, lifecycle 4, ranges 4, data 4):
      // "Loading" and no AT CLOSE for the length of every retry, or an empty
      // chart on the popup's open. The RETRY was plain words, "· R to
      // retry", until the owner clicked one hint like it (14 October).
      // A first fetch that takes its time dims what is on show, and the
      // dim lifts as it fails; a retry dims nothing. Whatever an earlier
      // step left of NVDA's week goes first.
      var nvdaDimmed = false
      var nvdaHeld = false
      var watchNvda = function() { if (body.chartLoading && body.motion.dimmed === 1) nvdaDimmed = true }
      body.motion.dimmedChanged.connect(watchNvda)
      var withoutWeek = Object.assign({}, service.testHistoryFeed.entries)
      delete withoutWeek["NVDA|1W"]
      service.testHistoryFeed.entries = withoutWeek
      service.summon("NVDA", "1W")
      nvdaHeld = body.chartLoading
      tryVerify(function() { return body.headerText === "1W unavailable" && !service.testHistoryFeed.busy }, 10000)
      tryVerify(function() { return body.motion.dimmed === 0 }, 1000)
      body.motion.dimmedChanged.disconnect(watchNvda)
      var failedLifted = nvdaHeld + "," + nvdaDimmed + "," + (body.motion.dimmed === 0)
      var retryButton = harness.find(body, "retryRange")
      var offered = !!retryButton && retryButton.visible
      var retry = function(start) {
        var said = []
        var dimmed = 0
        var watch = function() {
          if (said.indexOf(body.headerText) < 0) said.push(body.headerText)
          dimmed = Math.max(dimmed, body.motion.dimmed)
        }
        var frames = Qt.createQmlObject('import QtQuick; FrameAnimation { running: true }', harness)
        frames.triggered.connect(watch)
        start()
        watch()
        var retried = within(3000, function() { return service.testHistoryFeed.busy })
        tryVerify(function() { return !service.testHistoryFeed.busy }, 10000)
        wait(50)
        frames.destroy()
        return [retried, said.join("/") === "1W unavailable", body.motion.drawn === 1, dimmed === 0].join(",") + " " + said.join("/")
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
      harness.check("a first fetch that fails dims what is on show while out, then lifts with the day and its unavailable header; a retry of it keeps them, undimmed, until an answer lands, by r, by RETRY, by an open, and by RETRY under search",
        failedLifted === "true,true,true" && offered && /^true,true,true,true /.test(byR) && /^true,true,true,true /.test(byClick) && /^true,true,true,true /.test(byOpen)
          && /^true,true,true,true /.test(inSearch) && searchWord === "true,RETRY",
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
      // A value strictly part way comes from a frame of the draw-in; a jump
      // from empty to whole draws none.
      var lowestReveal = 1
      var partReveal = false
      var watchReveal = function() {
        lowestReveal = Math.min(lowestReveal, body.motion.reveal)
        if (body.motion.reveal > 0 && body.motion.reveal < 1) partReveal = true
      }
      body.motion.revealChanged.connect(watchReveal)
      app.open("{}")
      app.testKeyCatcher.forceActiveFocus()
      within(2000, function() { return partReveal && body.motion.reveal === 1 })
      body.motion.revealChanged.disconnect(watchReveal)
      // The window moves as the popup does: it draws the chart in as it
      // opens, and as a row is featured.
      harness.check("the window draws the chart in as it opens",
        lowestReveal < 0.5 && partReveal && body.motion.reveal === 1, lowestReveal + "|" + partReveal + " -> " + body.motion.reveal)
      keyClick(Qt.Key_1)
      harness.check("a row featured in the window draws its chart in",
        service.featuredSymbol === "AAPL" && body.motion.reveal < 0.5, body.motion.reveal)
      wait(400)
      keyClick(Qt.Key_2)
      wait(400)

      // A hero change from anywhere gets the window's motion, once: the
      // pill's wheel, IPC's next and prev (Service.featureStep), a summon,
      // and a summon that also changes the range each draw the chart in.
      // Found in the code-quality review: with the window open, the wheel,
      // IPC, and a summon swapped the chart in one frame.
      var motions = []
      var watchDrawIn = function() { if (body.motion.reveal === 0) motions.push("draw " + service.featuredSymbol) }
      body.motion.revealChanged.connect(watchDrawIn)
      var heroBeforeWheel = service.featuredSymbol
      mouseWheel(pill, pill.width / 2, pill.height / 2, 0, -120)
      var wheeledTo = service.featuredSymbol
      wait(400)
      service.featureStep(-1)
      var steppedTo = service.featuredSymbol
      wait(400)
      app.open(JSON.stringify({ symbol: "NVDA" }))
      wait(400)
      var dayMotions = motions.join(",")
      motions = []
      app.open(JSON.stringify({ symbol: "AAPL", range: "1Y" }))
      tryVerify(function() { return body.motion.reveal === 1 && harness.answered("AAPL|1Y") }, 5000)
      var rangeMotions = motions.join(",")
      motions = []
      app.open(JSON.stringify({ symbol: "MSFT", range: "1D" }))
      wait(500)
      var backMotions = motions.join(",")
      body.motion.revealChanged.disconnect(watchDrawIn)
      harness.check("the pill's wheel, IPC's step, and a summon each draw the window's chart in once",
        wheeledTo !== heroBeforeWheel && steppedTo === heroBeforeWheel
          && dayMotions === ["draw " + wheeledTo, "draw " + steppedTo, "draw NVDA"].join(","),
        heroBeforeWheel + "->" + wheeledTo + "->" + steppedTo + "|" + dayMotions)
      harness.check("a summon that changes the range too draws the chart in once, either way",
        rangeMotions === "draw AAPL" && backMotions === "draw MSFT", rangeMotions + " / " + backMotions)
      service.setRange("1D")
      service.feature("MSFT")
      wait(350)
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

      // A refetch with the week in hand holds still: the header stays on the
      // market. It said "LOADING 1W" every fifteen minutes, when the service
      // refetched the pill's range, and on every r.
      // The fetch can land within the key press, so the header is read as the
      // refetch starts, from the service's own change.
      var header = body.headerText
      var whileLoading = null
      var watch = function() {
        var out = service.testHistoryFeed.wanted
        if (whileLoading === null && out && out.key === "MSFT|1W" && service.histories["MSFT|1W"].history)
          whileLoading = body.headerText
      }
      service.testHistoryFeed.wantedChanged.connect(watch)
      keyClick(Qt.Key_R)
      tryVerify(function() { return whileLoading !== null && harness.answered("MSFT|1W") }, 5000)
      service.testHistoryFeed.wantedChanged.disconnect(watch)
      harness.check("a refetch with the range in hand keeps the header",
        whileLoading === header && header.indexOf("Loading") !== 0 && body.headerText === header,
        header + " -> " + whileLoading + " -> " + body.headerText)

      // Replay unfolds: on a range too it is a scrub that drives itself, bar
      // by bar, with the chart drawing in behind it. It used to be a slow
      // draw-in with the header and the price left on today.
      var marketHeader = body.headerText
      var headline = body.featured.priceText
      keyClick(Qt.Key_P)
      wait(1000)
      harness.check("a replay on a range walks its bars: a date in the header, the price at that bar",
        body.motion.replayRunning && body.headerText !== marketHeader && body.featured.priceText !== headline
          && body.motion.drawn > 0 && body.motion.drawn < 1,
        body.headerText + "|" + body.featured.priceText + " vs " + headline + "|" + body.motion.drawn)
      tryVerify(function() { return !body.motion.replayRunning }, 3000)
      harness.check("the replay ends back on the market",
        body.headerText === marketHeader && body.featured.priceText === headline && body.motion.drawn === 1,
        body.headerText + "|" + body.featured.priceText)

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
        body.chartSymbol === "MSFT" && body.motion.drawn === 1
          && JSON.stringify(body.featuredGeometry) === JSON.stringify(History.historyGeometry(service.histories["MSFT|1W"].history)),
        body.chartSymbol + "|" + body.motion.drawn)
      harness.check("after it fails the window says the range is unavailable, with RETRY beside it",
        within(8000, function() { return header.text === "1W UNAVAILABLE" && harness.find(body, "retryRange").visible }), header.text)

      // Back to a symbol with history: the window draws its range once in.
      keyClick(Qt.Key_1)
      harness.check("a symbol change in the window brings that symbol's range",
        service.featuredSymbol === "AAPL"
          && within(5000, function() { return harness.showsRange(app, "1W") }),
        service.featuredSymbol + "|" + harness.infoLine(app))

      // A range's first fetch keeps the day's chart and info lines, as the
      // hero keeps the day's figures, until the range's response lands.
      // Found in motion pass 3: the chart went blank and the info line to
      // dashes for the length of the fetch, on every first visit to a range.
      tryVerify(function() { return body.motion.drawn === 1 }, 2000)
      var blanked = []
      var watchLoad = function() {
        var entry = service.histories["AAPL|1M"]
        if (service.range !== "1M" || (entry && entry.history)) return
        if (!body.featuredGeometry || body.motion.drawn < 1) blanked.push("chart")
        if (!body.periodLine || body.periodLine.range.highText === "") blanked.push("info")
      }
      body.featuredGeometryChanged.connect(watchLoad)
      body.periodLineChanged.connect(watchLoad)
      keyClick(Qt.Key_BracketRight)
      watchLoad()
      tryVerify(function() { return harness.answered("AAPL|1M") }, 5000)
      body.featuredGeometryChanged.disconnect(watchLoad)
      body.periodLineChanged.disconnect(watchLoad)
      tryVerify(function() { return body.motion.drawn === 1 }, 2000)
      harness.check("a range's first fetch keeps the day's chart and info lines until it lands",
        blanked.length === 0 && !!body.featuredGeometry && body.motion.drawn === 1, blanked.join(","))

      // A range whose cache has run out still has its chart: featured, it
      // draws in at once while the refetch is out. It opened blank until
      // the refetch landed, the first time after the laptop woke.
      keyClick(Qt.Key_2)
      tryVerify(function() { return harness.answered("MSFT|1M") && body.motion.drawn === 1 }, 5000)
      keyClick(Qt.Key_1)
      tryVerify(function() { return body.motion.drawn === 1 }, 2000)
      var aged = Object.assign({}, service.testHistoryFeed.entries)
      aged["MSFT|1M"] = Object.assign({}, aged["MSFT|1M"], { receivedAt: aged["MSFT|1M"].receivedAt - 16 * 60 })
      service.testHistoryFeed.entries = aged
      // The refetch's answer is held back until the check has read the
      // state it is out in: the fake curl could answer before the check.
      holdMsft.running = true
      tryVerify(function() { return !holdMsft.running }, 2000)
      // A frame part way in, while the refetch is still out, is the draw-in;
      // a reveal set back to 0 alone is not.
      var partWay = false
      var watchPart = function() {
        var reveal = body.motion.reveal
        if (reveal > 0 && reveal < 1 && !!service.testHistoryFeed.wanted) partWay = true
      }
      body.motion.revealChanged.connect(watchPart)
      keyClick(Qt.Key_2)
      var stale = service.histories["MSFT|1M"]
      var out = service.testHistoryFeed.wanted
      var loadingAtOnce = body.chartLoading
      tryVerify(function() { return partWay }, 2000)
      body.motion.revealChanged.disconnect(watchPart)
      harness.check("a range with expired history draws in at once while its refetch is out",
        partWay && !!out && out.key === "MSFT|1M" && !!stale.history && !loadingAtOnce,
        partWay + "|" + (out ? out.key : "none") + "|" + !!stale.history + "|" + loadingAtOnce + "|" + body.motion.reveal)
      releaseMsft.running = true
      tryVerify(function() { return harness.answered("MSFT|1M") && body.motion.drawn === 1 }, 5000)
      keyClick(Qt.Key_1)
      tryVerify(function() { return body.motion.drawn === 1 }, 2000)

      // r fetches every quote again, and the range on show, which the cache
      // would otherwise have kept: AAPL's quote and its history.
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
      // Each pill's dim is read as it happens, from its own change; a value
      // between the first pill's dimmest and whole comes from a frame of the
      // ease, and a dim undone at once draws none.
      var dimmedPills = []
      var dimmest = 1
      var eased = false
      var watchPill = function(which) {
        return function() {
          if (which.opacity < 1 && dimmedPills.indexOf(which) < 0) dimmedPills.push(which)
          if (which !== pill) return
          if (pill.opacity < 1 && pill.opacity > dimmest) eased = true
          dimmest = Math.min(dimmest, pill.opacity)
        }
      }
      var watchFirst = watchPill(pill)
      var watchOther = watchPill(otherPill)
      pill.opacityChanged.connect(watchFirst)
      otherPill.opacityChanged.connect(watchOther)
      harness.callIpc("refresh")
      tryVerify(function() { return !ipcCall.running }, 5000)
      tryVerify(function() { return !service.testFeed.busy && !service.testHistoryFeed.busy && pill.opacity === 1 }, 10000)
      pill.opacityChanged.disconnect(watchFirst)
      otherPill.opacityChanged.disconnect(watchOther)
      var bothDimmed = dimmedPills.length === 2
      histories = harness.calls("AAPL.history") - aaplHistory
      harness.check("IPC refresh acknowledges on every pill, eased back, and refreshes once",
        bothDimmed && eased && histories === 1 && harness.calls("AAPL") - aapl - histories === 1
          && harness.calls("MSFT") === msft + 1 && harness.calls("NVDA") === nvda + 1,
        bothDimmed + "|" + eased + "|" + histories + "|" + (harness.calls("AAPL") - aapl) + "|"
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
      var noteWant = function() { var w = service.testHistoryFeed.wanted; if (w) wantedSince.push(w.key) }
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
      var lowestReveal = 1
      var watchReveal = function() { lowestReveal = Math.min(lowestReveal, summoned.testBody.motion.reveal) }
      summoned.open(JSON.stringify({ symbol: "MSFT", range: "1Y" }))
      summoned.testBody.motion.revealChanged.connect(watchReveal)
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
        cold.chart === null && cold.periodLine === null && cold.yearLine === null
          && cold.featured === null && coldSymbol === "MSFT",
        coldSymbol + "|" + JSON.stringify(cold.periodLine) + "|" + JSON.stringify(cold.yearLine) + "|" + JSON.stringify(cold.featured))
      // A quarter second on, the label over the empty hero says Loading,
      // and the header doesn't: it's said once, where a reader looks.
      harness.check("a quarter second into a cold start the empty hero's label alone says Loading, naming what is coming",
        within(2000, function() { return coldLabel.visible && cold.motion.dimmed === 1 }) && coldLabel.text === "Loading MSFT 1Y…"
          && cold.chart === null && coldWords.text === "",
        coldLabel.visible + "|" + coldLabel.text + "|" + cold.motion.dimmed + "|" + coldWords.text)
      releaseMsft.running = true
      wait(50)
      harness.check("payload features its symbol",
        again.featuredSymbol === "MSFT" && summoned.featuredSymbol === "MSFT", again.featuredSymbol)
      harness.check("payload sets the shared range",
        again.range === "1Y" && summoned.range === "1Y", again.range + "|" + summoned.range)
      harness.check("the summoned window draws the range it asked for",
        within(5000, function() { return harness.showsRange(summoned, "1Y") }),
        harness.infoLine(summoned))
      wait(450)
      summoned.testBody.motion.revealChanged.disconnect(watchReveal)
      harness.check("a window summoned while its service starts draws its chart in",
        lowestReveal < 0.5 && summoned.testBody.motion.reveal === 1, lowestReveal)
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
      body.search.picked("NOPE")
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
      // icon's says the symbol and its change, which the mark can't show.
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
      harness.check("the pill waits quietly while the first fetch is out",
        service.featuredSymbol === "FAIL" && pillChange.text === "…", service.featuredSymbol + "|" + pillChange.text)
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
      // stacked form show the "!" too, the stacked one naming its symbol.
      // Found in the 1.0.0 review: they looked healthy, the stacked form
      // saying "ST …" as if still loading.
      var formsWarn = function() {
        var settingsWas = pill.settings
        var said = []
        ;[false, true].forEach(function(vertical) {
          barApi.vertical = vertical
          barApi.barSize = vertical ? Style.bar.sizeVertical : 0
          pill.settings = Object.assign({}, settingsWas, vertical ? { barStyleVertical: "icon" } : { barStyle: "icon" })
          var markWarning = harness.find(pill, "pillMarkWarning")
          said.push((vertical ? "side icon " : "icon ") + (!!markWarning && markWarning.visible && markWarning.text === "!"))
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
      harness.check("after a failed first fetch the icon form, on either bar, and the stacked form show the \"!\", the stacked one naming its symbol",
        failedForms === "icon true, side icon true, stacked FAIL/!", failedForms)
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
      tryVerify(function() { return harness.answered("SLOW|1W") && body.motion.drawn === 1 }, 5000)
      var sig = function() {
        return JSON.stringify([body.featuredGeometry, body.featured ? body.featured.priceText + " " + body.featured.changeLine : "",
          JSON.stringify(body.periodLine), body.chartSymbol])
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
        var drewIn = false
        var carried = false
        var watchDraw = function() {
          if (!changed || body.chartLoading) return
          if (body.motion.drawn < 0.5) drewIn = true
          if (body.motion.replayRunning || body.scrubT !== 0) carried = true
        }
        var label = harness.find(body, "loadingLabel")
        var changedAt = 0
        var dim = { early: 0, whole: false, label: "" }
        var watchDim = function() {
          if (Date.now() - changedAt < 200) dim.early = Math.max(dim.early, body.motion.dimmed)
          if (body.chartLoading && body.motion.dimmed === 1 && !dim.whole) {
            dim.whole = true
            dim.label = label.visible ? label.text : "hidden"
          }
        }
        // At the end of the turn, when the change is whole and a frame can draw it.
        var later = function() { Qt.callLater(record) }
        body.featuredGeometryChanged.connect(later)
        body.featuredChanged.connect(later)
        body.periodLineChanged.connect(later)
        body.motion.drawnChanged.connect(watchDraw)
        body.motion.dimmedChanged.connect(watchDim)
        changedAt = Date.now()
        change()
        changed = true
        Qt.callLater(record)
        if (during) during()
        tryVerify(function() { return harness.answered(key) && body.motion.drawn === 1 }, 5000)
        wait(20)
        record()
        body.featuredGeometryChanged.disconnect(later)
        body.featuredChanged.disconnect(later)
        body.periodLineChanged.disconnect(later)
        body.motion.drawnChanged.disconnect(watchDraw)
        body.motion.dimmedChanged.disconnect(watchDim)
        dim.after = body.motion.dimmed
        var b = sig()
        return { states: seen.map(function(s) { return s === a ? "A" : s === b ? "B" : "?" }).join(""),
          loading: loadingUnderA > 0 && quietUnderA === 0, drewIn: drewIn, carried: carried, dim: dim }
      }
      // A chart on its way past a quarter second dims what is on show under
      // a label naming it, and the dim is gone once the new one has drawn in.
      var dimmedFor = function(run, named) {
        return run.dim.early === 0 && run.dim.whole && run.dim.label === named + "…" && run.dim.after === 0
      }
      var toSixMonths = switchChart(function() { service.setRange("6M") }, "SLOW|6M")
      harness.check("1W to an uncached 6M keeps 1W under Loading until 6M lands, dimmed from a quarter second on under a label naming it, then draws 6M in",
        toSixMonths.states === "AB" && toSixMonths.loading && toSixMonths.drewIn && !toSixMonths.carried && dimmedFor(toSixMonths, "Loading SLOW 6M"),
        JSON.stringify(toSixMonths))
      var toCachedWeek = switchChart(function() { service.setRange("1W") }, "SLOW|1W")
      harness.check("6M to a cached 1W goes straight to 1W, dimming nothing", toCachedWeek.states === "AB" && !toCachedWeek.dim.whole && toCachedWeek.dim.early === 0,
        JSON.stringify(toCachedWeek))
      service.setRange("6M")
      tryVerify(function() { return harness.answered("SLOW|6M") && body.motion.drawn === 1 }, 5000)
      dropEntry("SLOW|1W")
      // A held chart takes no replay: 1W draws in clean.
      var toUncachedWeek = switchChart(function() { service.setRange("1W") }, "SLOW|1W", function() {
        wait(50)
        body.replay()
      })
      harness.check("6M to an uncached 1W keeps 6M under Loading, dimmed, until 1W lands, then draws 1W in, with no replay on the held chart",
        toUncachedWeek.states === "AB" && toUncachedWeek.loading && toUncachedWeek.drewIn && !toUncachedWeek.carried
          && !body.motion.replayRunning && body.scrubT === 0 && dimmedFor(toUncachedWeek, "Loading SLOW 1W"), JSON.stringify(toUncachedWeek))
      service.feature("AAPL")
      tryVerify(function() { return harness.answered("AAPL|1W") && body.motion.drawn === 1 }, 5000)
      dropEntry("SLOW|1W")
      var toSlowWeek = switchChart(function() { service.feature("SLOW") }, "SLOW|1W")
      harness.check("a symbol change on a range keeps the last symbol's chart and figures until the new one lands, dimmed under a label naming it, then draws it in",
        toSlowWeek.states === "AB" && toSlowWeek.loading && toSlowWeek.drewIn && !toSlowWeek.carried && dimmedFor(toSlowWeek, "Loading SLOW 1W"),
        JSON.stringify(toSlowWeek))
      // A chart that lands within a quarter second changes nothing but the
      // chart: AAPL's week, which the fake curl answers at once; one that
      // happens to take longer on a loaded machine dims, as any does.
      dropEntry("AAPL|1W")
      var quickFrom = Date.now()
      var quickAt = 0
      var quickDim = 0
      var watchQuick = function() { quickDim = Math.max(quickDim, body.motion.dimmed) }
      body.motion.dimmedChanged.connect(watchQuick)
      service.feature("AAPL")
      tryVerify(function() { if (!quickAt && !body.chartLoading) quickAt = Date.now() - quickFrom; return quickAt > 0 && body.motion.drawn === 1 }, 5000)
      body.motion.dimmedChanged.disconnect(watchQuick)
      harness.check("a chart that lands within a quarter second dims nothing, one later dims",
        quickAt < 234 ? quickDim === 0 : quickAt > 266 ? quickDim > 0 : true, "landed in " + quickAt + " ms, dimmed to " + quickDim)
      // Each change asked for waits its own quarter second: a second range
      // asked for while the first is still on its way, 150 ms on, dims
      // nothing until a quarter second after it. Found in the review of
      // this change: it dimmed 70 ms after the second, counted from the
      // first.
      service.feature("SLOW")
      tryVerify(function() { return !body.chartLoading && body.motion.drawn === 1 }, 5000)
      dropEntry("SLOW|1M")
      dropEntry("SLOW|3M")
      var dimFrom = 0
      var dimAt = 0
      var watchSecond = function() { if (!dimAt && body.motion.dimmed > 0) dimAt = Date.now() }
      body.motion.dimmedChanged.connect(watchSecond)
      service.setRange("1M")
      var firstFrom = Date.now()
      tryVerify(function() { return Date.now() - firstFrom >= 150 }, 1000)
      service.setRange("3M")
      dimFrom = Date.now()
      tryVerify(function() { return harness.answered("SLOW|3M") && body.motion.drawn === 1 }, 5000)
      body.motion.dimmedChanged.disconnect(watchSecond)
      harness.check("a second chart asked for while the first is on its way dims what is on show a quarter second after it, not after the first",
        dimAt > 0 && dimAt - dimFrom >= 234, "dimmed " + (dimAt ? dimAt - dimFrom : "never") + " ms after the second, "
          + (dimAt ? dimAt - firstFrom : "-") + " after the first")
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
      var settingsBefore = pill.settings
      // The stacked form's lines as drawn: text, ink width, size, colour.
      var stackLines = function() {
        return harness.find(pill, "pillStack").children.filter(function(c) { return c.objectName === "pillStackLine" })
      }
      for (var vlook = 0; vlook < 2; vlook++) {
        service.persist({ style: vlook === 0 ? "smooth" : "retro" })
        var stack = harness.find(pill, "pillStack")
        // The icon form, whatever the top bar's: the mark alone, falling, in
        // one slot.
        var verticalMark = harness.find(pill, "pillMark")
        if (!verticalMark.visible || stack.visible || !Qt.colorEqual(verticalMark.color, Commons.Color.urgent)
            || harness.markWay(verticalMark) !== "falls" || pill.implicitHeight !== Style.bar.iconSlot)
          verticalWrong.push((service.retro ? "retro" : "smooth") + " icon: mark " + verticalMark.visible + " in "
            + verticalMark.color + ", " + harness.markWay(verticalMark) + ", stack " + stack.visible + ", "
            + pill.implicitHeight + " px tall")
        // Stacked, as Omarchy's clock stacks a vertical bar's lines: DOWN
        // over its move, a percent over its %, or in money split at its
        // point, one line to an icon slot, each inside the bar at the bar's
        // size or 90% of it, never smaller. Its five-character change ran a
        // pixel past each side.
        pill.settings = Object.assign({}, settingsBefore, { barStyleVertical: "stacked" })
        ;["pct", "abs"].forEach(function(mode) {
          service.persist({ changeMode: mode })
          var day = Figures.rowModel(service.quotes.DOWN, 0, service.changeMode)
          var move = mode === "abs" ? Format.stackedMoney(day.abs, service.quotes.DOWN.priceDigits) : Format.stackedPct(day.pct)
          var want = ["DOWN"].concat(move.lines.map(function(t) { return Format.lookSigns(t, service.retro) }))
          var lines = stackLines()
          var drawn = lines.map(function(l) {
            return l.text + " " + Math.ceil(l.tightWidth) + "px at " + l.renderedFontSize
          })
          var wrong = lines.length !== want.length || pill.implicitHeight !== want.length * Style.bar.iconSlot
            || lines.some(function(l, i) {
              return l.text !== want[i] || l.tightWidth > Style.bar.sizeVertical
                || l.renderedFontSize !== Math.round(l.text.length > 3 ? Style.font.body * 0.9 : Style.font.body)
                || !Qt.colorEqual(l.color, i === 0 ? barApi.barForeground : Commons.Color.urgent)
            })
          if (wrong)
            verticalWrong.push((service.retro ? "retro " : "smooth ") + mode + ": " + drawn.join(" / ") + ", " + pill.implicitHeight
              + " px tall on a " + Style.bar.sizeVertical + " px bar, want " + want.join(" / "))
        })
        service.persist({ changeMode: "pct" })
        pill.settings = settingsBefore
      }
      // Each bar keeps its own form: a saved arrow stays the arrow on a
      // horizontal bar while a vertical one shows the mark, and a
      // middle-click there steps between the mark and the symbol over its
      // change without touching the arrow. The arrow, the line, and the text
      // used to share one setting with the vertical bar, so a middle-click
      // there lost the arrow.
      pill.settings = Object.assign({}, settingsBefore, { barStyle: "arrow" })
      var drawn = function() {
        return pill.barStyle + " " + (harness.find(pill, "pillMark").visible ? "mark" : harness.find(pill, "pillStack").visible ? "stacked"
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
      harness.check("a vertical bar shows the mark on 6M, falling, in both looks, and once picked the day stacked inside the bar in its colour, in % and in money",
        verticalWrong.length === 0, verticalWrong.join(" | "))
      harness.check("a horizontal bar's arrow and a vertical bar's form are kept apart, and on a vertical bar every middle-click changes what shows",
        walk.join(",") === "icon mark,arrow arrow,stacked stacked,icon mark,stacked stacked,arrow arrow", walk.join(","))

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
        var alone = harness.find(pill, "pillMark").visible && !harness.find(pill, "pillSymbol").visible
        return pill.barStyle + (alone ? " alone" : "")
      }
      var middleClick = function() {
        mouseClick(pill, pill.width / 2, pill.height / 2, Qt.MiddleButton)
        harness.middleClicks++
      }
      var centreForm = formIn("center")
      var movedRight = formIn("right")
      // The mark climbs on an up day and falls on a down one, in the day's
      // colour: the shape says the direction without the colour.
      var mark = harness.find(pill, "pillMark")
      var upSymbol = service.library.filter(function(s) {
        return !!service.quotes[s] && Figures.rowModel(service.quotes[s], 0, service.changeMode).tone === "up"
      })[0] || ""
      service.feature(upSymbol)
      var onUpDay = upSymbol + " " + harness.markWay(mark) + (Qt.colorEqual(mark.color, "#9ece6a") ? " up colour" : " " + mark.color)
      service.feature("DOWN")
      var onDownDay = "DOWN " + harness.markWay(mark) + (Qt.colorEqual(mark.color, Commons.Color.urgent) ? " down colour" : " " + mark.color)
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
      harness.check("on the right the pill is its mark, climbing on an up day and falling on a down one, until a middle-click there picks a form, kept for the right; the centre and left keep theirs",
        centreForm === "sparkline" && movedRight === "icon alone" && pickedRight === "arrow"
          && onUpDay === upSymbol + " climbs up colour" && upSymbol !== "" && onDownDay === "DOWN falls down colour"
          && wrote.barStyleRight === "arrow" && wrote.barStyle === "sparkline"
          && backInCentre === "sparkline" && onLeft === "sparkline" && backOnRight === "arrow",
        [centreForm, movedRight, onUpDay, onDownDay, pickedRight, JSON.stringify(wrote), backInCentre, onLeft, backOnRight].join(" | "))

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

      // The pill's mark turns with its own day: a new price that takes TURN
      // below its close leaves the mark falling, every column in the down
      // colour, and one back above it climbing, every column in the up
      // colour. A wheel step to another symbol shows that one's mark at
      // once, and back again. (popup-motion.sh judges the turn's frames.)
      var settingsBeforeTurn = pill.settings
      barApi.layoutConfig = { left: [], center: [], right: [{ id: "grvc.stonks" }] }
      service.addSymbol("TURN")
      tryVerify(function() { return !!service.quotes.TURN && service.arriving.length === 0 }, 10000)
      service.feature("TURN")
      var markOfIn = function(symbol, mode) {
        var tone = Figures.rowModel(service.quotes[symbol], 0, mode).tone
        return (tone === "down" ? "falls" : "climbs") + " in " + [0, 1, 2, 3, 4].map(function() { return String(pill.toneColor(tone)) }).join(" ")
      }
      var markOf = function(symbol) { return markOfIn(symbol, service.changeMode) }
      var newPrice = function(down) {
        var proc = down ? turnDown : turnUp
        proc.running = true
        tryVerify(function() { return !proc.running }, 2000)
        var entries = Object.assign({}, service.testFeed.entries)
        entries.TURN = Object.assign({}, entries.TURN, { answeredAt: entries.TURN.answeredAt - 20 })
        service.testFeed.entries = entries
        service.refresh()
        tryVerify(function() { return pill.featured.tone === (down ? "down" : "up") && !mark.turning }, 10000)
        return harness.markDrawn(mark)
      }
      var turnStart = harness.markDrawn(mark)
      var turnedDown = newPrice(true)
      var turnedUp = newPrice(false)
      // Wheel steps until one lands on a symbol whose mark has the other
      // shape, each step's mark checked as it lands.
      var wheels = []
      for (var w = 0; w < 3; w++) {
        var before = harness.markWay(mark)
        mouseWheel(pill, pill.width / 2, pill.height / 2, 0, w === 0 ? -120 : 120)
        wheels.push(service.featuredSymbol + " " + (mark.turning ? "turning " : "") + harness.markDrawn(mark)
          + (harness.markDrawn(mark) === markOf(service.featuredSymbol) ? "" : " want " + markOf(service.featuredSymbol)))
        if (harness.markWay(mark) !== before && service.featuredSymbol !== "TURN") break
      }
      var wheelsRight = wheels.every(function(line) { return !/turning| want /.test(line) })
        && / (falls|climbs) /.test(wheels[wheels.length - 1]) && harness.markWay(mark) !== markOf("TURN").split(" ")[0]
      harness.check("a new price that turns the pill's day ends its mark the new way in the new colour in every column, and a wheel step shows the next symbol's mark at once",
        turnStart === markOf("TURN") && turnedDown === "falls in " + [0, 1, 2, 3, 4].map(function() { return String(pill.downColor) }).join(" ")
          && turnedUp === "climbs in " + [0, 1, 2, 3, 4].map(function() { return String(pill.upColor) }).join(" ") && wheelsRight,
        [turnStart, turnedDown, turnedUp].concat(wheels).join(" | "))
      // A change of mode turns no mark: the turn says a new price crossed.
      // Found in review: "since open", reading TURN's day the other way,
      // stepped the mark as a crossing would.
      service.feature("TURN")
      tryVerify(function() { return !!pill.featured && pill.featured.symbol === "TURN" && !mark.turning }, 2000)
      var toneIn = function(mode) { return Figures.rowModel(service.quotes.TURN, 0, mode).tone }
      if (toneIn("open") === toneIn("pct")) newPrice(true)
      var modeFlip = toneIn("pct") + " to " + toneIn("open")
      service.persist({ changeMode: "open" })
      var modeTurned = mark.turning
      var modeMark = harness.markDrawn(mark)
      service.persist({ changeMode: "pct" })
      harness.check("a change of mode that reads the pill's day the other way switches its mark at once, with no turn",
        toneIn("open") !== toneIn("pct") && !modeTurned && !mark.turning && modeMark === markOfIn("TURN", "open"),
        modeFlip + ": " + (modeTurned ? "turning " : "") + modeMark + " want " + markOfIn("TURN", "open"))
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

      // With nothing open the clock moves by the minute, not the second
      // (once more as a run's answers land); open, it moves each second.
      var ticks = 0
      var tick = function() { ticks++ }
      service.nowChanged.connect(tick)
      wait(5500)
      var closedTicks = ticks
      ticks = 0
      app.open("{}")
      wait(3500)
      var openTicks = ticks
      app.close()
      service.nowChanged.disconnect(tick)
      harness.check("with nothing open the clock wakes by the minute, and with the window open each second",
        closedTicks <= 2 && openTicks >= 3, closedTicks + " in 5.5 s closed, " + openTicks + " in 3.5 s open")

      harness.finish()
    }
  }

  HarnessExit { id: done }
}
