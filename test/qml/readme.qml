import QtQuick
import QtTest
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "plugin" as Stonks

// The README's pictures, through the real Service, popup (Panel.qml, its
// card in CardWindow.qml), window (App.qml), and pill (BarWidget.qml), on the
// demo watchlist at the saved moment readme.sh names. Each picture is
// grabbed into STONKS_README_RAW; readme.sh makes the README's from them.
// With STONKS_README_MARKETPLACE naming a symbol on the list, it grabs only
// the marketplace picture's two: that symbol's retro popup and its pill on
// the bar.
Harness {
  id: harness
  marker: "README DONE"

  readonly property string rawDir: Quickshell.env("STONKS_README_RAW")
  readonly property string marketplace: Quickshell.env("STONKS_README_MARKETPLACE") || ""
  readonly property var demo: ["AAPL", "JNJ", "SPY", "^GSPC", "BTC-USD", "SHEL.L", "7203.T"].concat(marketplace ? [marketplace] : [])
  readonly property var us: ["AAPL", "JNJ", "SPY"].concat(marketplace ? [marketplace] : [])
  readonly property string themeLink: Quickshell.env("HOME") + "/.local/state/omarchy/current/theme"
  property bool themeLinked: false

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
    foreground: Commons.Color.foreground
    fontFamily: Style.font.family
  }
  Stonks.Panel { id: panel; bar: api; settings: ({}) }
  Stonks.App { id: app; service: service; updates: updates; trendColors: colors }
  Process { id: themeSwitch; onExited: harness.themeLinked = true }

  // The pill on strips of bar: one as wide as the popup's card, for the
  // marketplace picture's bar; and each of its four forms.
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
        color: Qt.rgba(Commons.Color.bar.background.r, Commons.Color.bar.background.g, Commons.Color.bar.background.b, 1)

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
    foreground: Commons.Color.bar.text
    barForeground: Commons.Color.bar.text
    fontFamily: Style.font.family
    barSize: Style.bar.sizeHorizontal
  }

  Steps {
    name: "Readme"
    when: service.pluginsReady

    function quiet() {
      tryVerify(function() {
        return harness.demo.every(function(s) { return !!service.quotes[s] })
          && service.arriving.length === 0 && service.testFeed.firstRun.length + service.testFeed.refreshRun.length === 0
      }, 15000, "every demo listing answered")
      verify(colors.green !== "", "the theme's green is read")
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
      var rule = find(body, "breadthRule")
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
      var halo = find(body, "liveHalo")
      if (halo && halo.visible && (halo.scale !== 1 || halo.opacity !== 0.25)) return false
      var cap = find(body, "liveCap")
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
    }

    function test_pictures() {
      quiet()
      if (harness.marketplace) return marketplacePictures()
      verify(service.symbols.join(",") === harness.demo.join(",") && service.featuredSymbol === "AAPL"
        && service.listName === "" && service.range === "1D", "the demo watchlist, AAPL featured, on All and the day: " + service.symbols.join(","))

      panel.open()
      var body = panel.testBody
      tryVerify(function() { return body.surfaceOpen }, 3000)
      grab("forms", forms, body, robinhoodIn)

      // Scrubbed back an hour and a half, as ← steps do, a print at a time:
      // a capture taken mid-session lands in the same session.
      var back = service.now - 90 * 60
      body.nudgeScrub(-1)
      for (var step = 0; step < 500 && body.motion.scrubT > back; step++) body.nudgeScrub(-1)
      verify(body.motion.scrubT > 0 && body.motion.scrubT <= back, "the scrub reached an hour and a half back: " + body.motion.scrubT + " vs " + back)
      grab("scrub", panel.testCard.card, body, function() { return body.motion.scrubT !== 0 })
      body.endScrub()
      tryVerify(function() { return atRest(body) }, 3000, "the rows back on now")

      // The list's name eases into the open menu's fill.
      body.openListMenu()
      var control = find(body, "listControl")
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

      // Catppuccin Latte, as omarchy-theme-set switches it: the theme's
      // files in place, then its palette handed to the shell. Its green and
      // red are no real pair, so up and down are Stonks' own pair for a
      // light ground.
      var before = colors.green
      themeSwitch.command = ["ln", "-sfn", "/usr/share/omarchy/themes/catppuccin-latte", harness.themeLink]
      themeSwitch.running = true
      tryVerify(function() { return harness.themeLinked }, 2000, "Catppuccin Latte in place")
      var view = Qt.createQmlObject('import Quickshell.Io; FileView { blockLoading: true }', harness)
      view.path = harness.themeLink + "/colors.toml"
      Commons.Color.loadColors(view.text())
      Commons.Color.loadShell("")
      view.destroy()
      tryVerify(function() { return colors.green !== before }, 2000, "Catppuccin Latte read")
      panel.open()
      grab("light", panel.testCard.card, body, function() { return body.surfaceOpen })
      panel.close()
      harness.finish()
    }

    // The marketplace picture's: the symbol featured in retro, from a fresh
    // open, and its pill on the bar.
    function marketplacePictures() {
      var symbol = harness.marketplace
      verify(service.symbols.join(",") === harness.demo.join(","), "the demo watchlist and " + symbol + ": " + service.symbols.join(","))
      service.persist({ style: "retro" })
      service.feature(symbol)
      tryVerify(function() { return service.featuredSymbol === symbol }, 3000, symbol + " featured")
      panel.open()
      var body = panel.testBody
      grab("popup", panel.testCard.card, body, function() { return service.retro && body.surfaceOpen && service.featuredSymbol === symbol })
      grab("strip", heroStrip, body, robinhoodIn)
      panel.close()
      harness.finish()
    }
  }

}
