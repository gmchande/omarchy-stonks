import QtQuick
import QtTest
import Quickshell
import qs.Commons
import qs.Ui
import "plugin" as Stonks

// The README's pictures, through the real Service, popup (Panel.qml, its
// card in CardWindow.qml), window (App.qml), and pill (BarWidget.qml), on the
// demo watchlist at the saved moment readme.sh names. Each picture is
// grabbed into STONKS_README_RAW; readme.sh puts them together.
ShellRoot {
  id: harness

  property int failures: 0
  readonly property string rawDir: Quickshell.env("STONKS_README_RAW")
  readonly property var demo: ["AAPL", "PSIX", "SPY", "^GSPC", "BTC-USD", "SHEL.L", "7203.T"]
  readonly property var us: ["AAPL", "PSIX", "SPY"]

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
    return null
  }

  function finish() {
    console.log("README DONE")
    done.exitCode = failures ? 1 : 0
    done.start()
  }

  Stonks.Service { id: service }
  Stonks.Updates { id: updates }
  Stonks.TrendColors { id: colors }
  QtObject {
    id: shellApi
    function serviceFor(id) { return { service: service, trendColors: colors } }
  }
  PluginBarApi {
    id: api
    pluginId: "grvc.stonks"
    moduleName: "grvc.stonks"
    shell: shellApi
    foreground: Color.foreground
    fontFamily: Style.font.family
  }
  Stonks.Panel { id: panel; bar: api; settings: ({}) }
  Stonks.App { id: app; service: service; updates: updates; trendColors: colors }

  // The pill on strips of bar: one as wide as the popup's card, which
  // readme.sh widens into preview.png's bar; and each of its four forms.
  FloatingWindow {
    visible: true
    color: "transparent"
    implicitWidth: 560
    implicitHeight: 400

    Column {
      spacing: 24

      Rectangle {
        id: heroStrip
        width: panel.testCard.card.width
        height: Style.bar.sizeHorizontal
        color: Qt.rgba(Color.bar.background.r, Color.bar.background.g, Color.bar.background.b, 1)

        Stonks.BarWidget {
          anchors.centerIn: parent
          width: implicitWidth
          height: parent.height
          bar: barApi
          settings: ({ id: "grvc.stonks", barStyle: "sparkline" })
        }
      }

      Column {
        id: forms
        spacing: 8

        Repeater {
          model: ["sparkline", "arrow", "text", "icon"]

          Rectangle {
            required property string modelData
            width: 200
            height: Style.bar.sizeHorizontal
            color: heroStrip.color

            Stonks.BarWidget {
              anchors.centerIn: parent
              width: implicitWidth
              height: parent.height
              bar: barApi
              settings: ({ id: "grvc.stonks", barStyle: parent.modelData })
            }
          }
        }
      }
    }
  }
  PluginBarApi {
    id: barApi
    pluginId: "grvc.stonks"
    moduleName: "grvc.stonks"
    shell: shellApi
    foreground: Color.bar.text
    barForeground: Color.bar.text
    fontFamily: Style.font.family
    barSize: Style.bar.sizeHorizontal
  }

  TestCase {
    name: "Readme"
    when: service.pluginsReady

    function quiet() {
      tryVerify(function() {
        return harness.demo.every(function(s) { return !!service.quotes[s] })
          && service.arriving.length === 0 && service.testFeed.firstRun.length + service.testFeed.refreshRun.length === 0
      }, 15000, "every demo listing answered")
      harness.check("the theme's green is read", colors.green !== "", colors.green)
    }

    // Robinhood's word on the US listings, asked for once a surface opens:
    // whether each trades all day, and the prints of those that do.
    function robinhoodIn() {
      return harness.us.every(function(s) {
        var allDay = service.testAllDay.entries[s]
        var night = service.testOvernight.entries[s]
        return !!allDay && allDay.status === "ok" && (!allDay.allDay || (!!night && night.status === "ok"))
      })
    }

    // `body` at rest: its chart landed and drawn in whole, the rule beside
    // the list's name on its shares, which ease when a scrub moves the rows
    // and freeze where they are while a list view covers them, and the live
    // mark done marking a new price (liveStill).
    function atRest(body) {
      var rule = harness.find(body, "breadthRule")
      var share = function(n) { return rule.total ? n / rule.total : 0 }
      return !body.chartLoading && body.motion.reveal === 1
        && Math.abs(rule.upShare - share(rule.breadth.up)) < 1e-6
        && Math.abs(rule.downShare - share(rule.breadth.down)) < 1e-6
        && liveStill(body)
    }

    // The live mark at rest. Smooth's halo is at its resting size and
    // opacity only once its ripples stop; retro's cap is whole between
    // blinks too, so it rests once whole for longer than a blink's 700 ms.
    property var capWholeSince: 0
    function liveStill(body) {
      var halo = harness.find(body, "liveHalo")
      if (halo && halo.visible && (halo.scale !== 1 || halo.opacity !== 0.25)) return false
      var cap = harness.find(body, "liveCap")
      if (!cap || !cap.visible) return true
      if (cap.opacity !== 1) { capWholeSince = 0; return false }
      if (!capWholeSince) capWholeSince = Date.now()
      return Date.now() - capWholeSince > 900
    }

    // `item` as drawn now, into STONKS_README_RAW/<name>.png, once `body` is
    // at rest and `ready` holds. A new price's ripples take six seconds.
    function grab(name, item, body, ready) {
      capWholeSince = 0
      tryVerify(function() { return (!body || atRest(body)) && (!ready || ready()) }, 10000, name + " ready to grab")
      waitForRendering(item)
      var saved = false
      item.grabToImage(function(result) { saved = result.saveToFile(harness.rawDir + "/" + name + ".png") })
      tryVerify(function() { return saved }, 3000, "grab " + name)
      harness.check("grabbed " + name, saved)
    }

    function test_pictures() {
      quiet()
      harness.check("the demo watchlist, AAPL featured, on All and the day",
        service.symbols.join(",") === harness.demo.join(",") && service.featuredSymbol === "AAPL"
          && service.listName === "" && service.range === "1D", service.symbols.join(","))

      panel.open()
      var body = panel.testBody
      tryVerify(function() { return body.surfaceOpen }, 3000)
      grab("popup", panel.testCard.card, body, robinhoodIn)
      grab("strip", heroStrip)
      grab("forms", forms)
      // preview.png keeps the popup down to its list's header, fading out
      // over the space between the figures and that header: each end as a
      // share of the card's height, for readme.sh.
      var card = panel.testCard.card
      var info = harness.find(body, "infoBlock")
      var figuresEnd = info.mapToItem(card, 0, info.height).y
      var headerTop = harness.find(body, "listControl").mapToItem(card, 0, 0).y
      console.log("PREVIEW_FADE " + (figuresEnd / card.height).toFixed(4)
        + " " + (headerTop / card.height).toFixed(4))

      // Scrubbed back an hour and a half, as ← steps do, a print at a time:
      // a capture taken mid-session lands in the same session.
      var back = service.now - 90 * 60
      body.nudgeScrub(-1)
      for (var step = 0; step < 500 && body.motion.scrubT > back; step++) body.nudgeScrub(-1)
      harness.check("the scrub reached an hour and a half back", body.motion.scrubT > 0 && body.motion.scrubT <= back,
        body.motion.scrubT + " vs " + back)
      grab("scrub", panel.testCard.card, body, function() { return body.motion.scrubT !== 0 })
      body.endScrub()
      tryVerify(function() { return atRest(body) }, 3000, "the rows back on now")

      // The list's name takes the open menu's fill, easing in: grabbed once
      // that fill has held for five polls.
      body.openListMenu()
      var control = harness.find(body, "listControl")
      var lastFill = "", heldFor = 0
      grab("lists", panel.testCard.card, body, function() {
        var fill = String(control.color)
        heldFor = fill === lastFill ? heldFor + 1 : 0
        lastFill = fill
        return body.listMenuOpen && heldFor >= 5
      })
      body.closeListMenu()
      panel.close()
      tryVerify(function() { return !body.surfaceOpen }, 3000)

      // Retro from a fresh open, so the header's colour and the look
      // button's cells, which ease on a switch, ease while it is closed,
      // before the open's draw-in starts.
      service.persist({ style: "retro" })
      panel.open()
      grab("retro", panel.testCard.card, body, function() { return service.retro && body.surfaceOpen })
      panel.close()
      service.persist({ style: "smooth" })
      tryVerify(function() { return !body.surfaceOpen && !service.retro }, 3000)

      app.open("{}")
      grab("window", app.testKeyCatcher, app.testBody, function() { return app.testBody.surfaceOpen })
      app.close()
      harness.finish()
    }
  }

  HarnessExit { id: done; interval: 100 }
}
