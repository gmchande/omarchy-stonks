import QtQuick
import QtTest
import Quickshell
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "plugin" as Stonks
import "plugin/Figures.js" as Figures

// The panel's card edge in motion, judged on rendered frames (frames.js):
// the real Panel and Service with real Qt keys, the card in a plain window
// (CardWindow.qml) since the shell's layer-shell one does not load
// offscreen. Each change of what the card fits eases its edge there in the
// house 160 ms, the footer riding it whole and covering the rows it passes;
// an open from closed shows the fitted height from its first frame. Beside
// it, a real pill's animal turns column by column as its day crosses its
// close, and switches at once on a wheel step. HOME and curl are scratch
// fixtures.
Harness {
  id: harness
  marker: "POPUP MOTION DONE"

  property bool marked: false

  Stonks.Service { id: service; pluginId: "grvc.stonks" }
  // Hyprland's word on the screens (WindowHost), with the panel's own
  // screen on or off while the rest stay on.
  QtObject {
    id: fakeScreens
    property bool panelScreenOn: true
    readonly property bool screensOff: false
    signal screensAnswered()
    function askScreens() { return false }
    function screenOn(screen) { return panelScreenOn }
  }
  QtObject {
    id: shellApi
    function serviceFor(id) { return { service: service } }
  }
  PluginBarApi {
    id: api
    pluginId: "grvc.stonks"
    moduleName: "grvc.stonks"
    shell: shellApi
    foreground: Commons.Color.foreground
    fontFamily: Style.font.family
  }
  Stonks.Panel { id: panel; bar: api; settings: ({}) }
  FrameGrab { id: grab }
  // A real pill in its icon form, its own panel off (popup-motion.sh), on
  // a plain window in the bar's ground, for its animal's frames and the wheel.
  // Its shell hands it the plugin's up and down, as Plugin.qml does.
  Stonks.TrendColors { id: trendColors }
  QtObject {
    id: pillShell
    function serviceFor(id) { return { service: service, trendColors: trendColors } }
  }
  PluginBarApi {
    id: pillApi
    pluginId: "grvc.stonks"
    moduleName: "grvc.stonks"
    shell: pillShell
  }
  FloatingWindow {
    visible: true
    color: Qt.rgba(Commons.Color.bar.background.r, Commons.Color.bar.background.g, Commons.Color.bar.background.b, 1)
    implicitWidth: 120
    implicitHeight: 60
    Stonks.BarWidget {
      id: pill
      width: implicitWidth
      height: 32
      bar: pillApi
      moduleName: "grvc.stonks"
      settings: ({ id: "grvc.stonks", barStyle: "icon" })
    }
  }

  Steps {
    name: "PopupMotion"
    when: service.pluginsReady

    function quiet() {
      tryVerify(function() { return service.arriving.length === 0 && service.testFeed.firstRun.length + service.testFeed.refreshRun.length === 0 }, 8000)
    }

    function markOnce() {
      if (harness.marked) return
      harness.marked = true
      grab.markStart()
    }

    // The card's edge on screen: on 4.5 the shell eases it (drawnHeight);
    // on 4.0 the card takes the height Stonks eases.
    function edgeHeight() {
      return panel.testCard.card.height
    }

    function edgeAtRest() {
      return edgeHeight() === panel.fittedCardHeight
    }

    function rest() {
      tryVerify(edgeAtRest, 2000)
    }

    function moreFrames(count) {
      var from = grab.frames.length
      tryVerify(function() { return grab.frames.length >= from + count }, 2000)
    }

    // The card's frames from a few before `act` until four after its edge
    // rests, timed from the change of the height it fits (the mark), and
    // frames.js's verdict on them in `mode`.
    function frames(name, act, mode, args) {
      grab.source = panel.testCard.surface
      grab.begin(name)
      moreFrames(4)
      harness.marked = false
      panel.fittedCardHeightChanged.connect(markOnce)
      act()
      tryVerify(function() { return harness.marked && edgeAtRest() }, 2000)
      moreFrames(4)
      panel.fittedCardHeightChanged.disconnect(markOnce)
      return verdict(mode, args)
    }

    function verdict(mode, args) {
      grab.end()
      tryVerify(function() { return grab.waiting === 0 }, 5000)
      grab.judge(mode, null, args || [])
      tryVerify(function() { return grab.verdict !== null }, 10000)
      return grab.verdict
    }

    // A check on a film, its line naming the main thread's work and wait
    // over the frames judged (FrameGrab `work`), pass or fail.
    function filmed(label, ok, told, more) {
      check(label + " — " + grab.judgedWork, ok, told.own + (more || ""))
    }

    // The footer and the card's bottom inset: what rides the edge.
    function band() {
      return [String(find(panel.testBody, "footer").height + panel.testCard.card.contentBottomInset)]
    }

    // A key as a person presses it, once the panel has its keys: it takes
    // them as it opens and a turn after a view closes.
    function key(k, modifiers) {
      tryVerify(function() { return panel.testBodyKeys.activeFocus }, 2000)
      keyClick(k, modifiers === undefined ? Qt.NoModifier : modifiers)
    }

    // The pill's animal turning with its own day, judged on its own frames.
    function pillTurns() {
      service.persist({ featured: "AAPL" })
      var animal = find(pill, "pillAnimal")
      var kind = function() { return Figures.animalKind(pill.featured) }
      tryVerify(function() { return animal.visible && !!pill.featured && pill.featured.symbol === "AAPL" && kind() === "bull" }, 2000)
      var quotes = service.testFeed.quotes
      // AAPL below its close, and the symbols either side of it in the list
      // above theirs, so a wheel step either way lands on a bull.
      var turned = Object.assign({}, quotes)
      turned.AAPL = Object.assign({}, quotes.AAPL, { prevClose: quotes.AAPL.price + 10 })
      var shown = service.view.shown
      var at = shown.indexOf("AAPL")
      ;[shown[(at + 1) % shown.length], shown[(at - 1 + shown.length) % shown.length]].forEach(function(s) {
        turned[s] = Object.assign({}, quotes[s], { prevClose: quotes[s].price - 10 })
      })
      grab.source = animal
      grab.begin("animal-turn")
      moreFrames(4)
      grab.markStart()
      service.testFeed.quotes = turned
      within(2000, function() { return kind() === "bear" && !animal.turning })
      moreFrames(4)
      var turn = verdict("columns:200:" + animal.columns)
      filmed("a new price that turns the pill's day turns its bull into the bear left to right in 200 ms, each column taking its new cells and colour as it turns",
        turn.ok && kind() === "bear", turn)
      grab.source = animal
      grab.begin("animal-wheel")
      moreFrames(4)
      grab.markStart()
      mouseWheel(pill, pill.width / 2, pill.height / 2, 0, -120)
      within(2000, function() { return service.featuredSymbol !== "AAPL" && kind() === "bull" && !animal.turning })
      moreFrames(4)
      var wheel = verdict("turn:0")
      filmed("a wheel step to a symbol that is up switches the pill's animal at once",
        wheel.ok && service.featuredSymbol !== "AAPL" && kind() === "bull", wheel, " | " + service.featuredSymbol)
      service.testFeed.quotes = quotes
    }

    // An ease of the edge after `act`, judged on the frames.
    function eases(label, act) {
      var verdict = frames(label.replace(/[^a-z0-9]+/gi, "-"), act, "edge", band())
      filmed(label, verdict.ok, verdict)
    }

    function test_edge() {
      // All of six, a list of two, and an empty one.
      ["FLAT", "DOWN", "STRAY"].forEach(function(s) { service.addSymbol(s) })
      quiet()
      service.createList("Short")
      service.setMembership("AAPL", "Short", true)
      service.setMembership("MSFT", "Short", true)
      service.createList("Empty")
      service.switchList("")
      service.persist({ featured: "MSFT" })
      tryVerify(function() { return service.featuredSymbol === "MSFT" }, 2000)

      // The card's window exists once it shows: its frames are grabbed from
      // the same turn as the open, before its first frame.
      panel.open()
      grab.source = panel.testCard.surface
      grab.begin("open")
      // Half a second of frames in which the edge must not move.
      wait(500)
      var opened = verdict("edgeheld")
      filmed("an open from closed shows the fitted height from its first frame", opened.ok, opened)

      eases("a switch to a shorter list eases the edge up, the footer riding it", function() { service.switchList("Short") })
      eases("a switch to a longer list eases the edge down, the footer covering the rows it passes", function() { service.switchList("") })

      // As the key sheet closes and the card grows, the footer's line and
      // words must not draw through the rows.
      key("?")
      tryVerify(function() { return panel.testBody.showingHelp && edgeAtRest() }, 2000)
      eases("the key sheet closing eases the edge down, the footer covering the rows it passes", function() { key("?") })

      service.switchList("Short")
      rest()
      eases("a removal from a short list eases the edge up", function() { key(Qt.Key_Delete) })
      eases("an add that lands eases the edge down", function() { panel.testBody.acceptSymbol("SPY") })
      quiet()

      // The menu, a popover, passes over the footer as the card grows under
      // it: only the edge is judged.
      service.switchList("Empty")
      rest()
      var menu = frames("menu", function() { key("w") }, "edge", ["0"])
      filmed("the list menu on an empty list eases the edge down to room for it and the footer",
        menu.ok && service.listName === "Empty", menu)
      panel.testBody.closeListMenu()
      rest()

      // Search on the empty list: its field stands at the top, so nothing
      // rides the edge as it opens.
      var opening = frames("search-open", function() { key("a") }, "edge", ["0"])
      filmed("search opening eases the edge down to its room", opening.ok && panel.testBody.adding, opening)
      eases("search closing eases the edge back up, the footer riding it", function() { panel.testBody.cancelAdding() })

      service.switchList("")
      // The card closes as it was: the key sheet over a scrub stays for the
      // close, and the next open clears both.
      panel.testBody.showingHelp = true
      panel.testBody.motion.scrubT = 123
      panel.close()
      check("closing keeps the sheet and the scrub for the fade",
        panel.testBody.showingHelp && panel.testBody.scrubT === 123, panel.testBody.showingHelp + "|" + panel.testBody.scrubT)
      // Each later open from closed holds the thread at most 20 ms.
      var later = []
      for (var n = 0; n < 5; n++) {
        tryVerify(function() { return !panel.testCard.visible }, 2000)
        var laterAt = Date.now()
        panel.open()
        later.push(Date.now() - laterAt)
        waitForRendering(panel.testCard.surface)
        panel.close()
      }
      check("each later open of the panel holds the thread at most 20 ms", Math.max.apply(null, later) <= 20, later.join(", ") + " ms")
      pillTurns()
      viewsThroughClose()
      reopenMidFade()
      // Omarchy 4.0 has no switch to turn its animations off.
      if (Style.reduceMotion !== undefined) stillWithMotionOff()
      darkScreen()
      harness.finish()
    }

    // Reopened during its close's fade, the panel eases from the height still
    // on screen: the key sheet, closed by the open, gives way to the rows
    // from the sheet's height, never at once.
    function reopenMidFade() {
      panel.open()
      rest()
      key("?")
      tryVerify(function() { return panel.testBody.showingHelp && edgeAtRest() }, 2000)
      var sheet = edgeHeight()
      panel.close()
      var fading = panel.testCard.visible
      panel.open()
      var first = edgeHeight()
      var between = false
      tryVerify(function() {
        var h = edgeHeight()
        if (Math.abs(h - sheet) > 1 && Math.abs(h - panel.fittedCardHeight) > 1) between = true
        return h === panel.fittedCardHeight
      }, 2000)
      check("reopened during its close's fade, the panel eases from the height still on screen",
        fading && Math.abs(first - sheet) <= 1 && between && Math.abs(sheet - panel.fittedCardHeight) > 1,
        fading + " | " + sheet + " -> " + first + " -> " + edgeHeight() + (between ? ", eased" : ", at once"))
      panel.close()
    }

    // With the shell's animations off (`omarchy toggle animations`), the
    // panel opens with its chart whole and a list switch puts the edge in
    // place at once: from the change on, every frame shows the same chart,
    // and the edge where it rests. The words may change meanwhile, as the
    // clock turns a minute.
    function stillWithMotionOff() {
      // An ease begun before the switch runs to its end.
      tryVerify(function() { return edgeHeight() === panel.testCard.contentHeight }, 2000)
      Style.reduceMotion = true
      panel.open()
      // Whole from the open: no draw-in begins.
      var whole = panel.testBody.motion.reveal === 1 && !panel.testBody.motion.drawingIn
      grab.source = panel.testCard.surface
      grab.begin("still-open")
      moreFrames(15)
      // From the open's fourth frame: a hover's fade begun before the switch
      // can finish in the first three. The draw-in an open used to start
      // runs 320 ms.
      grab.end()
      tryVerify(function() { return grab.waiting === 0 }, 5000)
      var chart = find(panel.testBody, "heroChart")
      var at = chart.mapToItem(panel.testCard.surface, 0, 0)
      grab.judge("same:" + [Math.round(at.x), Math.round(at.y), Math.round(chart.width), Math.round(chart.height)].join(","), grab.frames.slice(3), [])
      tryVerify(function() { return grab.verdict !== null }, 10000)
      var opened = grab.verdict
      filmed("with animations off, the panel opens whole and still", opened.ok && whole, opened, whole ? "" : " | a draw-in began")
      // The animal doesn't fidget: past its greeting, its square holds.
      var slot = find(panel.testBody, "animal")
      var animal = slot.mapToItem(panel.testCard.surface, 0, 0)
      var shown = slot.parent.kind !== ""
      grab.begin("still-animal")
      grab.markStart()
      tryVerify(function() { return grab.frames.length > 0 && grab.frames[grab.frames.length - 1].at - grab.start >= 2600 }, 6000)
      var sat = verdict("same:" + [Math.round(animal.x), Math.round(animal.y), Math.round(slot.width), Math.round(slot.height)].join(","))
      filmed("with animations off, the animal sits still", sat.ok && shown, sat, shown ? "" : " | no animal shows")
      var before = panel.fittedCardHeight
      service.switchList("Short")
      waitForRendering(panel.testCard.surface)
      grab.begin("still-switch")
      moreFrames(12)
      var switched = verdict("edgeheld")
      var moved = panel.fittedCardHeight !== before && edgeAtRest()
      filmed("with animations off, a switch to a shorter list moves the edge at once",
        switched.ok && moved && service.listName === "Short", switched, moved ? "" : " | the switch moved no edge: " + before + " -> " + panel.fittedCardHeight)
      // A replay is the reader's own ask, as a press of play is: with
      // animations off it still plays its 2 s.
      service.switchList("")
      var motion = panel.testBody.motion
      tryVerify(function() { return !motion.loading }, 3000)
      var askedAt = Date.now()
      key("p")
      var began = within(500, function() { return motion.replayRunning })
      tryVerify(function() { return !motion.replayRunning }, 4000)
      var played = Date.now() - askedAt
      check("with animations off, p still replays the chart over its 2 s",
        began && played >= 1700 && played <= 2600, (began ? "played " : "never began, ") + played + " ms")
      panel.close()
      Style.reduceMotion = false
    }

    // The panel's own screen turned off, the others still on: the animal
    // stops fidgeting, and starts again when its screen comes back.
    function darkScreen() {
      service.screens = fakeScreens
      panel.open()
      var header = find(panel.testBody, "animal").parent
      var ran = within(2000, function() { return header.fidgeting })
      fakeScreens.panelScreenOn = false
      var stopped = !header.fidgeting
      fakeScreens.panelScreenOn = true
      var again = header.fidgeting
      panel.close()
      service.screens = null
      check("with the panel's own screen off and the others on, the animal stops fidgeting, and starts again when it comes back",
        ran && stopped && again, "ran " + ran + ", stopped " + stopped + ", again " + again)
    }

    function viewsThroughClose() {
      service.createList("Third")
      service.setMembership("AAPL", "Short", true)
      service.setMembership("AAPL", "Empty", true)
      service.setMembership("AAPL", "Third", true)
      panel.open()
      var body = panel.testBody
      var views = [
        [function() { body.openListMenu() }, function() { body.closeListMenu() }, "listMenu", "listChoice"],
        [function() { body.openSymbolLists("AAPL") }, function() { body.closeListViews() }, "symbolLists", "symbolListRow"],
        [function() { body.openManageLists() }, function() { body.closeListViews() }, "manageLists", "manageRow"]
      ].map(function(v) {
        v[0]()
        var view = null, rows = []
        tryVerify(function() { view = find(body, v[2]); rows = view ? findAll(view, v[3]) : []; return rows.length >= 3 && rows[2].height > 0 }, 2000, v[2] + " open")
        waitForRendering(body)
        var onTwo = rows[2].mapToItem(body, rows[2].width / 2, rows[2].height / 2)
        var onAll = rows[0].mapToItem(body, rows[0].width / 2, rows[0].height / 2)
        mouseMove(body, onTwo.x, onTwo.y - 6)
        mouseMove(body, onTwo.x, onTwo.y)
        within(1000, function() { return view.cursor === 2 })
        var before = view.cursor
        body.surfaceOpen = false
        mouseMove(body, onAll.x, onAll.y - 6)
        mouseMove(body, onAll.x, onAll.y)
        // Time for a cursor that wrongly follows the pointer to move.
        wait(50)
        var after = view.cursor
        body.surfaceOpen = true
        v[1]()
        tryVerify(function() { return !find(body, v[2]) || !find(body, v[2]).visible }, 2000, v[2] + " closed")
        return (before === 2 && after === 2) + " " + v[2] + " " + before + "->" + after
      })
      check("a list view showing through its surface's close moves no cursor as the pointer passes",
        views.every(function(c) { return c.indexOf("true ") === 0 }), views.join(" | "))
      panel.close()
    }
  }
}
