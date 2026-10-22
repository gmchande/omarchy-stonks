import QtQuick
import QtTest
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "plugin" as Stonks

// The screenshot, through the real popup (Panel.qml, its card in
// CardWindow.qml) by keys and the real window (App.qml) by the pointer,
// with stand-ins first on PATH for wl-copy and omarchy-notification-send
// (bin/) that record what they were given: y and a click on the camera each
// save one picture, named for the symbol and the moment, in the folder the
// reader's user-dirs.dirs names for pictures, put that picture on the
// clipboard as a PNG, and send Omarchy's notification with that file, its
// thumbnail and a click to edit it; the picture is of the chart on show,
// its symbol, range, and scrub, never the list. Then, with Omasnap absent
// and present (camera.sh), the folder and editor each version of Omarchy
// uses, under each version's settings. HOME and curl are scratch.
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

  readonly property string fakeState: Quickshell.env("STONKS_FAKE_STATE")
  readonly property string shotsDir: Quickshell.env("HOME") + "/Shots"
  function readFile(path) {
    var view = Qt.createQmlObject('import Quickshell.Io; FileView { blockLoading: true; printErrors: false }', harness)
    view.path = path
    var text = String(view.text())
    view.destroy()
    return text
  }
  function readBytes(path) {
    if (path === "") return null
    var view = Qt.createQmlObject('import Quickshell.Io; FileView { blockLoading: true; printErrors: false }', harness)
    view.path = path
    var bytes = view.data()
    view.destroy()
    return bytes
  }
  function sameBytes(a, b) {
    if (!a || !b || a.byteLength === 0 || a.byteLength !== b.byteLength) return false
    var x = new Uint8Array(a), y = new Uint8Array(b)
    for (var i = 0; i < x.length; i++) if (x[i] !== y[i]) return false
    return true
  }
  function lines(name) {
    return readFile(fakeState + "/" + name).split("\n").filter(function(line) { return line !== "" })
  }
  // Each notification sent, its arguments in order.
  function notifications() {
    return lines("notifications.log").map(function(line) { return line.split("\t").slice(0, -1) })
  }
  // The picture's size as an image loads it: "2400x1350".
  function pictureSize(path) {
    if (path === "") return "no picture"
    var image = Qt.createQmlObject('import QtQuick; Image { asynchronous: false; cache: false }', harness)
    image.source = "file://" + path
    var size = image.status === Image.Ready ? image.implicitWidth + "x" + image.implicitHeight : "not loaded (" + image.status + ")"
    image.destroy()
    return size
  }
  // Every word drawn on `item` and under it.
  function texts(item, into) {
    into = into || []
    if (!item) return into
    if (typeof item.text === "string" && item.text !== "" && item.visible) into.push(item.text)
    for (var i = 0; i < item.children.length; i++) texts(item.children[i], into)
    return into
  }

  readonly property string cacheDir: Quickshell.env("XDG_CACHE_HOME") + "/grvc.stonks"
  property string listedDir: shotsDir
  Process {
    id: lister
    command: ["sh", "-c", "ls -1 \"$1\" 2> /dev/null", "sh", harness.listedDir]
    stdout: StdioCollector { id: listed }
  }
  Process { id: runner }

  Stonks.Service { id: service }
  Stonks.Updates { id: updates }
  Stonks.Camera { id: camera }
  QtObject {
    id: shellApi
    function serviceFor(id) { return { service: service, updates: updates, camera: camera } }
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
  Stonks.App { id: app; service: service; updates: updates; camera: camera }

  TestCase {
    name: "Camera"
    when: service.pluginsReady

    function quiet() {
      tryVerify(function() { return service.arriving.length === 0 && service.testFeed.firstRun.length + service.testFeed.refreshRun.length === 0 }, 8000)
    }

    // The files in `folder` (the pictures folder unless named), by name.
    function shots(folder) {
      harness.listedDir = folder || harness.shotsDir
      lister.running = true
      tryVerify(function() { return !lister.running }, 3000)
      return listed.text.split("\n").filter(function(name) { return name !== "" })
    }

    // Runs `script` in sh with `args`, and waits for it to end.
    function run(script, args) {
      runner.command = ["sh", "-c", script, "sh"].concat(args)
      runner.running = true
      tryVerify(function() { return !runner.running }, 3000)
    }

    // One shot, `act` taking it on `body`: what the camera laid out, the
    // pictures it left in `folder` (the pictures folder unless named), the
    // notification and the clipboard's call it made, and what the footer
    // said. A shot that never lands is reported by the checks, not stopped
    // at the wait.
    function shoot(body, act, folder) {
      var files = shots(folder).length
      var sent = notifications().length
      var copies = lines("wl-copy.calls").length
      var loader = harness.find(body, "shareLoader")
      var seen = null
      var take = function() {
        var card = loader.item
        seen = { symbol: card.symbol, range: card.range, retro: card.retro, scrubX: card.scrubX, scrubT: card.scrubT,
          when: card.words ? card.words.when : "", span: card.words ? card.words.span : "",
          currency: card.quote ? String(card.quote.currency || "") : "", texts: harness.texts(card) }
      }
      if (loader) loader.loaded.connect(take)
      act()
      for (var waited = 0; waited < 8000; waited += 50) {
        if (notifications().length > sent && body.note.indexOf("Copied a screenshot of ") === 0 && !camera.busy) break
        wait(50)
      }
      if (loader) loader.loaded.disconnect(take)
      var note = notifications()[sent] || []
      var file = note[3] || ""
      return {
        card: seen || {},
        added: shots(folder).length - files,
        cached: shots(harness.cacheDir).filter(function(name) { return /\.png$/.test(name) }),
        note: note,
        file: file,
        name: file.slice(file.lastIndexOf("/") + 1),
        folder: file.slice(0, file.lastIndexOf("/")),
        copied: lines("wl-copy.calls")[copies] || "",
        clipboard: harness.readBytes(harness.fakeState + "/wl-copy." + (copies + 1)),
        picture: harness.readBytes(file),
        size: harness.pictureSize(file),
        footer: body.note,
        loaded: loader ? String(loader.source) : ""
      }
    }

    // A shot that landed as Omarchy's own screenshots do: one picture,
    // named for `symbol`, in `folder` (the reader's pictures folder unless
    // named), and no copy of it in Stonks' cache; that picture on the
    // clipboard as a PNG; Omarchy's notification in Omarchy's own words, the
    // picture as its thumbnail and a click that opens `editor` (Tensaku
    // unless named) on it; the footer saying what it shows, `said` matching
    // what follows "Copied a screenshot of "; and the card gone. A second
    // shot in the same second keeps the first: its name ends "-2".
    function landed(shot, symbol, said, folder, editor) {
      var named = new RegExp("^stonks-" + symbol + "-\\d{4}-\\d\\d-\\d\\d_\\d\\d-\\d\\d-\\d\\d(-\\d+)?\\.png$")
      var expected = ["Screenshot saved to clipboard and file", "Edit with Super + Alt + , (or click this)",
        "--image", shot.file, "--exec", editor || "tensaku-edit", shot.file]
      var problems = []
      if (shot.added !== 1) problems.push(shot.added + " pictures saved")
      if (!named.test(shot.name) || shot.folder !== (folder || harness.shotsDir)) problems.push("saved as " + shot.file)
      if (shot.cached.length) problems.push("pictures in the cache: " + shot.cached.join(", "))
      if (JSON.stringify(shot.note) !== JSON.stringify(expected)) problems.push("notified " + JSON.stringify(shot.note))
      if (shot.copied !== "--type image/png" || !harness.sameBytes(shot.clipboard, shot.picture)) problems.push("copied " + shot.copied + " " + (shot.clipboard ? shot.clipboard.byteLength : 0) + " bytes")
      if (shot.size !== "2400x1350") problems.push("picture " + shot.size)
      if (!said.test(shot.footer.replace(/^Copied a screenshot of /, "")) || shot.footer.indexOf("Copied a screenshot of ") !== 0) problems.push("footer " + shot.footer)
      if (shot.loaded !== "") problems.push("card still loaded")
      return problems
    }

    // The card shows the chart on show and never the list: no other row's
    // symbol and no list's name. Its price's currency, USD for every shot
    // here, stands beside the price, and its foot says when: `span`, the
    // saved day's date of the price on show, or the range's length.
    function ofChart(shot, symbol, range, span, rows) {
      var problems = []
      if (!shot.card.texts) return ["no card laid out"]
      if (shot.card.symbol !== symbol || shot.card.range !== range) problems.push("card of " + shot.card.symbol + " " + shot.card.range)
      if (shot.card.texts.indexOf(symbol) < 0 || shot.card.span !== span || shot.card.texts.indexOf(span) < 0
        || shot.card.currency !== "USD" || shot.card.texts.indexOf("USD") < 0)
        problems.push("words " + shot.card.texts.join(" | "))
      var listed = shot.card.texts.filter(function(text) { return rows.indexOf(text) >= 0 && text !== symbol })
      if (listed.length) problems.push("shows the list's " + listed.join(", "))
      return problems
    }

    function test_camera() {
      quiet()
      // Every row's symbol and every list's name, the one on show too: none
      // is the chart's, so none may be on the picture.
      var rows = service.library.concat(service.lists.map(function(l) { return l.label }), ["All"])

      // The popup by keys, in smooth, on AAPL's day at rest.
      service.feature("AAPL")
      panel.open()
      var body = panel.testBody
      tryVerify(function() { return body && body.surfaceOpen && !body.chartLoading && body.featuredSymbol === "AAPL" }, 5000)
      panel.refocusKeys()
      wait(100)
      var still = shots().length
      var unlit = !body.cameraLit
      var rest = shoot(body, function() { keyClick(Qt.Key_Y) })
      var problems = landed(rest, "aapl", /^AAPL at .+$/).concat(ofChart(rest, "AAPL", "1D", "TUE 1 SEP 2026", rows))
      harness.check("y in the popup saves one picture of AAPL's day in the pictures folder, copies it as a PNG, and sends Omarchy's notification with it",
        problems.length === 0 && still === 0 && rest.card.scrubX === -1 && !rest.card.retro, problems.join("; "))
      harness.check("the camera lights after its first shot, and not before", unlit && body.cameraLit)

      // Scrubbed back two steps: the picture shows the scrub and says its
      // time, and the footer names it.
      keyClick(Qt.Key_H)
      keyClick(Qt.Key_H)
      tryVerify(function() { return body.scrubT !== 0 }, 2000)
      var scrubbed = shoot(body, function() { keyClick(Qt.Key_Y) })
      problems = landed(scrubbed, "aapl", /^AAPL at \d\d:\d\d$/).concat(ofChart(scrubbed, "AAPL", "1D", "TUE 1 SEP 2026", rows))
      harness.check("scrubbed, y takes the scrub: the picture shows it and says its time, its date only at the foot, and the footer says it too",
        problems.length === 0 && scrubbed.card.scrubT === body.scrubShown && scrubbed.card.scrubX >= 0 && /^AT \d\d:\d\d [A-Z]+$/.test(scrubbed.card.when)
          && scrubbed.name !== rest.name,
        problems.join("; ") + " | " + scrubbed.card.when + " | " + scrubbed.footer)

      // Lit through the close's fade, and out when the popup opens again.
      panel.close()
      var fading = body.cameraLit === true
      wait(300)
      panel.open()
      tryVerify(function() { return body.surfaceOpen }, 2000)
      harness.check("the camera stays lit until the popup closes, and is out when it opens again",
        fading && body.cameraLit === false, fading + "|" + body.cameraLit)
      panel.close()
      wait(300)

      // The window by the pointer, in retro, on AAPL's 1Y: a click on the
      // camera takes the range.
      service.persist({ style: "retro" })
      service.setRange("1Y")
      app.open("{}")
      var win = app.testBody
      tryVerify(function() { return win && win.surfaceOpen && !win.chartLoading && win.historyShown && win.retro }, 8000)
      wait(200)
      var button = harness.find(win, "cameraButton")
      var year = shoot(win, function() { if (button) mouseClick(button, button.width / 2, button.height / 2) })
      problems = landed(year, "aapl", /^AAPL 1Y at .+$/).concat(ofChart(year, "AAPL", "1Y", "1 YEAR", rows))
      harness.check("a click on the window's camera, in retro, takes AAPL's 1Y as it is shown",
        problems.length === 0 && year.card.retro && win.cameraLit, problems.join("; "))

      // The pointer on the chart scrubs it, and y takes that moment: the
      // way a mouse hand takes a scrubbed picture, since leaving the chart
      // for the camera ends the scrub.
      app.testKeyCatcher.forceActiveFocus()
      var chart = win.chartItem
      mouseMove(chart, chart.width * 0.4, chart.height / 2)
      tryVerify(function() { return win.scrubT !== 0 }, 2000)
      var hovered = shoot(win, function() { keyClick(Qt.Key_Y) })
      problems = landed(hovered, "aapl", /^AAPL 1Y on .+$/).concat(ofChart(hovered, "AAPL", "1Y", "1 YEAR", rows))
      harness.check("y with the pointer on the window's chart takes the bar the pointer reads",
        problems.length === 0 && hovered.card.scrubT === win.scrubShown && hovered.card.scrubX >= 0,
        problems.join("; ") + " | " + hovered.card.scrubT + " vs " + win.scrubShown)
      mouseMove(win, 1, 1)

      // Bitcoin, its file named for its symbol, its dash kept.
      service.setRange("1D")
      service.addSymbol("BTC-USD")
      quiet()
      service.feature("BTC-USD")
      tryVerify(function() { return win.featuredSymbol === "BTC-USD" && !win.chartLoading && !win.historyActive }, 8000)
      app.testKeyCatcher.forceActiveFocus()
      var coin = shoot(win, function() { keyClick(Qt.Key_Y) })
      problems = landed(coin, "btc-usd", /^BTC-USD at \d\d:\d\d(?: [A-Z]+)?$/).concat(ofChart(coin, "BTC-USD", "1D", "SAT 12 SEP 2026", rows))
      harness.check("y in the window takes Bitcoin's day", problems.length === 0, problems.join("; "))

      // Omarchy 4.5 hands its screenshots to Omasnap, which keeps them in a
      // folder of its own; 4.0 to Tensaku, in the pictures folder. Each shot
      // follows the Omarchy installed, which Omasnap's presence tells, and
      // that version's settings win, the other's counting for nothing.
      var home = Quickshell.env("HOME")
      var conf = home + "/.config/omasnap/omasnap.conf"
      var cases = [
        { label: "without Omasnap, OMARCHY_SCREENSHOT_DIR and OMARCHY_SCREENSHOT_EDITOR win, and Omasnap's settings count for nothing",
          omasnap: false, conf: true, folder: home + "/Legacy", editor: "my-editor",
          env: { OMARCHY_SCREENSHOT_DIR: home + "/Legacy", OMARCHY_SCREENSHOT_EDITOR: "my-editor", OMASNAP_SCREENSHOT_DIR: home + "/Snaps" } },
        { label: "with Omasnap, the picture lands in Screenshots in the pictures folder, and a click opens it in Omasnap",
          omasnap: true, conf: false, folder: harness.shotsDir + "/Screenshots", editor: "omasnap", env: {} },
        { label: "with Omasnap, the directory in omasnap.conf's [output] comes before that, its ~ expanded",
          omasnap: true, conf: true, folder: home + "/Captures", editor: "omasnap", env: {} },
        { label: "with Omasnap, OMARCHY_SCREENSHOT_DIR comes before omasnap.conf, as Omarchy hands it on, and OMARCHY_SCREENSHOT_EDITOR counts for nothing",
          omasnap: true, conf: true, folder: home + "/Legacy", editor: "omasnap",
          env: { OMARCHY_SCREENSHOT_DIR: home + "/Legacy", OMARCHY_SCREENSHOT_EDITOR: "my-editor" } },
        { label: "with Omasnap, OMASNAP_SCREENSHOT_DIR comes before OMARCHY_SCREENSHOT_DIR",
          omasnap: true, conf: true, folder: home + "/Snaps", editor: "omasnap",
          env: { OMARCHY_SCREENSHOT_DIR: home + "/Legacy", OMASNAP_SCREENSHOT_DIR: home + "/Snaps" } }
      ]
      for (var i = 0; i < cases.length; i++) {
        var step = cases[i]
        // Only [output]'s directory counts, its quotes and spaces as
        // Omasnap's settings reader drops them.
        if (step.conf) run("mkdir -p \"${1%/*}\" && printf '%s' \"$2\" > \"$1\"", [conf,
          "[colors]\ndirectory = /colors\n\n[output]\n# Where saved screenshots go.\ndirectory = \"~/Captures\" \n\n[later]\ndirectory = /later\n"])
        else run("rm -f \"$1\"", [conf])
        var env = step.env
        if (step.omasnap) env.PATH = Quickshell.env("STONKS_OMASNAP") + ":" + Quickshell.env("PATH")
        camera.testEnvironment = env
        app.testKeyCatcher.forceActiveFocus()
        var shot = shoot(win, function() { keyClick(Qt.Key_Y) }, step.folder)
        problems = landed(shot, "btc-usd", /^BTC-USD at \d\d:\d\d(?: [A-Z]+)?$/, step.folder, step.editor)
        harness.check(step.label, problems.length === 0, problems.join("; "))
      }
      app.close()

      console.log("CAMERA DONE")
      done.exitCode = harness.failures ? 1 : 0
      done.start()
    }
  }

  HarnessExit { id: done; interval: 100 }
}
