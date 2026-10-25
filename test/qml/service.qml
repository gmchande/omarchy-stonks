import QtQuick
import Quickshell
import Quickshell.Io
import "Settings.js" as Settings

// Drives the real Service through migration, persist, and external edits
// with the fake curl that test/qml/service.sh puts first on PATH, and a data
// file that can't be read, fixed, and gone; and the version watch through
// its manifest rewritten, updated, downgraded, and back. A scratch HOME
// holds the bar entry and the data file. Reads the file back with cat,
// never through the service's FileView. Prints one line per check and
// exits 0 when every check passed, 1 otherwise.
ShellRoot {
  id: harness

  property int failures: 0
  property int step: 0
  property int waited: 0
  property var afterCat: null
  property var afterWrite: null
  property var afterLs: null
  property bool reading: false
  // Asked for before their quotes, which the add fetches, and again once
  // they are in: an ETF and a cryptocurrency, which the service never sends
  // to Yahoo's fundamentals, and two Toronto listings, which it does, each
  // priced in CAD against earnings in USD.
  readonly property var asking: ["SPY", "BTC-USD", "SHOP.TO", "MAPLE.TO"]
  property int askingAt: 0
  property bool asked: false
  property int fundamentalsBefore: 0
  property var msftBefore: null
  // Data files that can't be read: half a JSON object, as a hand edit
  // leaves one, an empty file, and JSON that is not an object.
  readonly property var unreadable: [
    { label: "broken JSON", body: "{\n  \"symbols\": [\"AAPL\",\n" },
    { label: "an empty file", body: "" },
    { label: "JSON that is not an object", body: "[]\n" }
  ]
  property int unreadableAt: 0
  property var goodLibrary: []
  property string goodFeatured: ""
  property string goodBody: ""
  property var second: null
  // A save from elsewhere just after the migration's write has landed.
  property bool editedAfterMigration: false
  property bool lockedSaw: false
  property int versionAt: 0
  readonly property var versionCases: [
    { label: "the same version written again says nothing", body: JSON.stringify(harness.manifest) + "\n", how: "over", want: "" },
    { label: "a new version saved over the manifest is named", body: harness.manifestWith("9.9.9"), how: "rename", want: "9.9.9" },
    { label: "a downgrade, written anew as git checks it out, is named too", body: harness.manifestWith("0.0.1"), how: "recreate", want: "0.0.1" },
    { label: "a manifest with no version changes nothing", body: harness.manifestWith(undefined), how: "recreate", want: "0.0.1" },
    { label: "a half-written manifest changes nothing", body: "{\n  \"id\": \"grvc.st", how: "over", want: "0.0.1" },
    { label: "back to the running version, the notice goes", body: harness.manifestWith(harness.manifest.version), how: "recreate", want: "" }
  ]

  readonly property string dataPath: Quickshell.env("HOME") + "/.config/omarchy/grvc.stonks.json"
  readonly property string dataDir: Quickshell.env("HOME") + "/.config/omarchy"
  // The tree's copy of the manifest, which the version watch reads.
  readonly property string manifestPath: String(Qt.resolvedUrl("manifest.json")).replace(/^file:\/\//, "")
  readonly property var manifest: JSON.parse(manifestFile.text())
  FileView { id: manifestFile; path: harness.manifestPath; blockLoading: true }
  function manifestWith(version) {
    var next = JSON.parse(JSON.stringify(harness.manifest))
    if (version === undefined) delete next.version
    else next.version = version
    return JSON.stringify(next, null, 2) + "\n"
  }

  function check(name, ok, detail) {
    console.log((ok ? "PASS " : "FAIL ") + name + (detail !== undefined ? " — " + detail : ""))
    if (!ok) harness.failures++
  }

  // The fake curl counts its calls per name; a fresh view per read, since a
  // FileView that has loaded once returns its old text after reload().
  function calls(name) {
    var view = Qt.createQmlObject('import Quickshell.Io; FileView { blockLoading: true; printErrors: false }', harness)
    view.path = Quickshell.env("STONKS_FAKE_STATE") + "/" + name + ".calls"
    var n = Number(String(view.text()).trim() || "0")
    view.destroy()
    return n
  }

  function parseFile(text) {
    try {
      var parsed = JSON.parse(String(text || "").trim())
      if (!parsed || typeof parsed !== "object") return null
      return parsed
    } catch (e) {
      return null
    }
  }

  function complete(obj) {
    return !!(obj && obj.version === 1 && obj.symbols && obj.featured !== undefined
      && obj.order && obj.changeMode && obj.style && obj.refreshIntervalSec)
  }

  function sameSymbols(got, want) {
    if (!got || got.length !== want.length) return false
    for (var i = 0; i < want.length; i++) if (got[i] !== want[i]) return false
    return true
  }

  function snapshot() {
    return {
      version: 1,
      symbols: service.symbols.slice(),
      featured: service.featuredSymbol,
      order: service.order,
      changeMode: service.changeMode,
      style: service.retro ? "retro" : "smooth",
      refreshIntervalSec: service.refreshIntervalSec
    }
  }

  function bodyFrom(values) {
    var next = harness.snapshot()
    for (var key in values) next[key] = values[key]
    return JSON.stringify(next, null, 2) + "\n"
  }

  function finish() {
    console.log(harness.failures === 0 ? "ALL PASS" : harness.failures + " FAILED")
    exitTimer.exitCode = harness.failures === 0 ? 0 : 1
    exitTimer.start()
  }

  function go(next) {
    harness.step = next
    harness.waited = 0
    ticker.start()
  }

  Service { id: service }
  Updates { id: updates }
  // The service's reads of its data file: a read after a change is its
  // file watch reading that change back.
  property int loads: 0
  property int loadsAtBurst: 0
  Connections {
    target: service.testDataFile
    function onLoaded() { harness.loads++ }
  }
  // A shell started while the data file can't be read.
  Component { id: secondService; Service {} }
  // A Service whose data file the harness steps through (service.sh's
  // SteppedService.qml, on DataFileStandIn.qml).
  Component { id: steppedService; SteppedService {} }
  property var stepped: null
  // Ends the stepped Service's read in flight, one a tick, so a read it
  // starts once a handler has returned is ended too: true while there was
  // one to end.
  function settling() {
    var file = harness.stepped.testDataFile
    if (!file.reading || harness.waited >= 2000) return false
    file.endRead()
    return true
  }
  function withRange(owner, range) {
    return JSON.stringify(Object.assign({}, owner.dataSettings, { range: range }), null, 2) + "\n"
  }

  Component.onCompleted: service.fetchFundamentals("AAPL")

  // Yahoo's fundamentals out of reach, then MSFT asked for again.
  Process {
    id: endpointDown
    command: ["touch", Quickshell.env("STONKS_FAKE_STATE") + "/FUNDAMENTALS.down"]
    onExited: {
      service.fetchFundamentals("MSFT")
      harness.go(11)
    }
  }

  Process {
    id: catProc
    command: ["cat", harness.dataPath]
    stdout: StdioCollector {
      id: catOut
      waitForEnd: true
    }
    onExited: function(code) {
      harness.reading = false
      var text = code === 0 ? String(catOut.text) : null
      var obj = text !== null ? harness.parseFile(text) : null
      var fn = harness.afterCat
      harness.afterCat = null
      if (fn) fn(obj, text)
    }
  }

  Process {
    id: writeProc
    onExited: function() {
      var fn = harness.afterWrite
      harness.afterWrite = null
      if (fn) fn()
    }
  }

  Process {
    id: lsProc
    command: ["ls", "-A", harness.dataDir]
    stdout: StdioCollector {
      id: lsOut
      waitForEnd: true
    }
    onExited: function() {
      var fn = harness.afterLs
      harness.afterLs = null
      if (fn) fn(String(lsOut.text))
    }
  }

  // The data file's mode ("600"), and the end of service.sh's hold on chmod.
  property var afterMode: null
  Process {
    id: modeProc
    command: ["stat", "-c", "%a", harness.dataPath]
    stdout: StdioCollector { id: modeOut; waitForEnd: true }
    onExited: {
      var fn = harness.afterMode
      harness.afterMode = null
      if (fn) fn(String(modeOut.text).trim())
    }
  }
  Process {
    id: releaseChmod
    command: ["rm", "-f", Quickshell.env("STONKS_FAKE_STATE") + "/chmod.hold"]
  }

  function readThen(fn) {
    if (harness.reading) return
    harness.reading = true
    harness.afterCat = fn
    catProc.running = false
    catProc.running = true
  }

  // writeTo PATH BODY HOW FN: "over" writes the file in place, "rename"
  // writes a temporary file and moves it over, as an editor's atomic save
  // does, and "recreate" deletes it and writes it anew, as git's checkout
  // does; "remove" deletes it; "unreadable" writes it in place and takes
  // away its read permission, and "readable" gives it back.
  function writeTo(path, body, how, fn) {
    ticker.stop()
    harness.afterWrite = fn
    writeProc.running = false
    var script = how === "rename" ? "printf '%s' \"$1\" > \"$2.tmp\" && mv -f \"$2.tmp\" \"$2\""
      : how === "recreate" ? "rm -f \"$2\" && printf '%s' \"$1\" > \"$2\""
      : how === "remove" ? "rm -f \"$2\""
      : how === "unreadable" ? "printf '%s' \"$1\" > \"$2\" && chmod 0200 \"$2\""
      : how === "readable" ? "chmod 0600 \"$2\""
      : "printf '%s' \"$1\" > \"$2\""
    writeProc.command = ["bash", "-c", script, "--", body, path]
    writeProc.running = true
  }

  function writeThen(body, fn) {
    harness.writeTo(harness.dataPath, body, "over", fn)
  }

  function renameThen(body, fn) {
    harness.writeTo(harness.dataPath, body, "rename", fn)
  }

  // The USDCAD rate's last fetch made a day older.
  function ageRate() {
    var held = service.testFundamentalsFeed.rates.USDCAD
    service.testFundamentalsFeed.rates = { USDCAD: { value: held.value, checkedAt: held.checkedAt - 25 * 60 * 60 } }
  }

  // Runs SCRIPT in bash with the fake state's folder as $1, then FN.
  function stateThen(script, fn) {
    ticker.stop()
    harness.afterWrite = fn
    writeProc.running = false
    writeProc.command = ["bash", "-c", script, "--", Quickshell.env("STONKS_FAKE_STATE")]
    writeProc.running = true
  }

  Timer {
    id: ticker
    interval: 50
    repeat: true
    running: true
    onTriggered: {
      harness.waited += interval
      if (harness.step === 0) {
        if (!service.pluginsReady) {
          if (harness.waited >= 5000) {
            harness.check("service ready from bar", false, "timed out")
            harness.finish()
          }
          return
        }
        harness.go(1)
      } else if (harness.step === 1) {
        // The bar entry in test/fixtures/shell-bar-only.json carries settings
        // other than the defaults, and the pill's barStyle.
        harness.readThen(function(obj) {
          var ready = service.pluginsReady
            && harness.sameSymbols(service.symbols, ["AAPL"])
            && service.featuredSymbol === "AAPL"
          var fileOk = !!(obj && harness.sameSymbols(obj.symbols, ["AAPL"])
            && obj.featured === "AAPL" && obj.order === "pct" && obj.style === "retro"
            && obj.refreshIntervalSec === 120 && obj.barStyle === undefined)
          if (!fileOk && harness.waited < 2000) return
          harness.check("migrated from bar and wrote the file, leaving barStyle on the bar", ready && fileOk,
            JSON.stringify({ ready: ready, symbols: service.symbols, featured: service.featuredSymbol, file: obj }))
          // service.sh holds every chmod from the start, under umask 022, so
          // the mode read here is the one the file was first written with.
          harness.afterMode = function(mode) {
            harness.check("a data file new on this machine is its owner's alone from its first write", mode === "600", mode)
            releaseChmod.running = true
            // The migration's file is made as the read that found none ends:
            // the file's watch must still read a save from elsewhere after
            // it, with no change of Stonks' own in between.
            harness.writeThen(harness.bodyFrom({ style: "smooth" }), function() { harness.go(2) })
          }
          ticker.stop()
          modeProc.running = true
        })
      } else if (harness.step === 2) {
        if (!harness.editedAfterMigration) {
          if (service.retro && harness.waited < 2000) return
          harness.check("a save from elsewhere just after the migration's write lands", !service.retro)
          harness.editedAfterMigration = true
          service.persist({ style: "smooth" })
          service.persist({ order: "symbol" })
          harness.waited = 0
          return
        }
        harness.readThen(function(obj) {
          var ok = !!(obj && obj.style === "smooth" && obj.order === "symbol")
          if (!ok && harness.waited < 2000) return
          harness.check("two persists land together", ok, JSON.stringify(obj))
          service.persist({ changeMode: "abs" })
          harness.go(3)
        })
      } else if (harness.step === 3) {
        harness.readThen(function(obj) {
          var ok = harness.complete(obj) && obj.changeMode === "abs"
          if (!ok && harness.waited < 2000) return
          harness.check("one persist leaves a complete file", ok, JSON.stringify(obj))
          // An older build's order by the amount, reversed on All and not on
          // a named list: each reads as % change, its direction kept.
          harness.writeThen(harness.bodyFrom({ symbols: ["AAPL", "MSFT"], featured: "MSFT", order: "abs", reversed: true,
            lists: [{ name: "Yen", symbols: ["MSFT"], order: "abs" }] }), function() {
            harness.go(4)
          })
        })
      } else if (harness.step === 4) {
        var over = harness.sameSymbols(service.symbols, ["AAPL", "MSFT"])
          && service.featuredSymbol === "MSFT"
        if (!over && harness.waited < 2000) return
        harness.check("overwrite reaches the service", over,
          JSON.stringify({ symbols: service.symbols, featured: service.featuredSymbol }))
        var saved = service.dataSettings
        var yen = saved.lists[0] || {}
        harness.check("a list saved in $ CHANGE order reads as % change, its direction and its symbols kept",
          saved.order === "pct" && saved.reversed === true && saved.lists.length === 1
            && yen.name === "Yen" && yen.order === "pct" && yen.reversed === false && harness.sameSymbols(yen.symbols, ["MSFT"]),
          JSON.stringify({ order: saved.order, reversed: saved.reversed, lists: saved.lists }))
        harness.renameThen(harness.bodyFrom({ style: "retro" }), function() {
          harness.go(5)
        })
      } else if (harness.step === 5) {
        if (!service.retro && harness.waited < 2000) return
        harness.check("rename overwrite reaches the service", service.retro,
          service.retro ? "retro" : "smooth")
        service.persist({ featured: "AAPL" })
        harness.go(6)
      } else if (harness.step === 6) {
        harness.readThen(function(obj) {
          var kept = !!(obj && obj.featured === "AAPL"
            && harness.sameSymbols(obj.symbols, ["AAPL", "MSFT"])
            && obj.style === "retro")
          if (!kept && harness.waited < 2000) return
          harness.check("persist after edits keeps them", kept, JSON.stringify(obj))
          ticker.stop()
          harness.afterLs = function(text) {
            var names = String(text || "").split(/\s+/).filter(function(n) { return n !== "" })
            var extra = []
            for (var i = 0; i < names.length; i++) {
              var n = names[i]
              if (n === "shell.json" || n === "grvc.stonks.json") continue
              if (n.indexOf("grvc.stonks") === 0 || n.indexOf(".tmp") !== -1)
                extra.push(n)
            }
            harness.check("no leftover temp file", extra.length === 0, extra.join(" "))
            harness.go(7)
          }
          lsProc.running = false
          lsProc.running = true
        })
      } else if (harness.step === 7) {
        // Asked for before any quote said AAPL is an equity, its cap and EPS
        // still arrive where the surfaces read them, the cap with its close.
        var entry = service.fundamentals["AAPL"]
        var ready = !!(entry && entry.status === "ok" && entry.figures.cap && entry.figures.eps
          && entry.figures.cap.value === 4918530543600 && entry.figures.cap.close > 0 && entry.figures.eps.currency === "USD")
        if (!ready && harness.waited < 5000) return
        harness.check("a cap and P/E asked for before the quote arrive once it does", ready, JSON.stringify(entry))
        harness.fundamentalsBefore = harness.calls("FUNDAMENTALS")
        harness.go(8)
      } else if (harness.step === 8) {
        var symbol = harness.asking[harness.askingAt]
        if (!harness.asked) {
          service.fetchFundamentals(symbol)
          service.addSymbol(symbol)
          harness.asked = true
          return
        }
        if (!service.quotes[symbol]) {
          if (harness.waited < 5000) return
          harness.check("an added " + symbol + " gets its quote", false, "none in 5 s")
          harness.finish()
          return
        }
        service.fetchFundamentals(symbol)
        harness.asked = false
        harness.askingAt = harness.askingAt + 1
        if (harness.askingAt < harness.asking.length) {
          harness.go(8)
          return
        }
        service.fetchFundamentals("MSFT")
        harness.go(9)
      } else if (harness.step === 9) {
        var settled = ["SHOP.TO", "MAPLE.TO", "MSFT"].every(function(s) {
          return service.fundamentals[s] && service.fundamentals[s].status === "ok"
        }) && !service.testFundamentalsFeed.busy
        if (!settled && harness.waited < 5000) return
        var perSymbol = ["SPY", "BTC-USD", "SHOP.TO", "MAPLE.TO", "MSFT"].map(function(s) { return harness.calls(s + ".fundamentals") })
        var shop = service.fundamentals["SHOP.TO"]
        var maple = service.fundamentals["MAPLE.TO"]
        harness.check("only an equity asks for a cap and P/E, a Toronto listing too: not an ETF or a cryptocurrency",
          settled && perSymbol.join() === "0,0,1,1,1" && harness.calls("FUNDAMENTALS") - harness.fundamentalsBefore === 6
            && shop.figures.cap.currency === "CAD" && shop.figures.cap.close > 0,
          JSON.stringify({ perSymbol: perSymbol, shop: shop }))
        // Two listings in CAD with earnings in USD ask for USDCAD once, and
        // a listing in USD asks none.
        harness.check("a rate is asked once a day for its pair, not for each listing",
          settled && harness.calls("RATE") === 1 && harness.calls("USDCAD.rate") === 1
            && Object.keys(service.rates).join() === "USDCAD" && service.rates.USDCAD.value === 1.4004
            && shop.figures.eps.currency === "USD" && maple.figures.eps.currency === "USD",
          JSON.stringify({ rates: harness.calls("RATE"), held: service.rates }))
        // Asked again the same day, and refreshed: nothing goes. The quotes
        // were answered seconds ago, under the refresh's 10 s floor, so the
        // step gives the refresh a moment rather than waiting on a quote.
        harness.fundamentalsBefore = harness.calls("FUNDAMENTALS")
        service.fetchFundamentals("MSFT")
        service.fetchFundamentals("SHOP.TO")
        service.refresh()
        harness.go(10)
      } else if (harness.step === 10) {
        if (harness.waited < 1500) return
        harness.check("a cap and P/E are fetched once a day, and never by a refresh",
          harness.calls("FUNDAMENTALS") === harness.fundamentalsBefore && harness.calls("RATE") === 1,
          (harness.calls("FUNDAMENTALS") - harness.fundamentalsBefore) + " sent")
        // A day later, with the rate out of reach: SHOP.TO's series are a day
        // old, and so is the rate.
        var stale = Object.assign({}, service.testFundamentalsFeed.entries)
        stale["SHOP.TO"] = Object.assign({}, stale["SHOP.TO"], { checkedAt: stale["SHOP.TO"].checkedAt - 25 * 60 * 60 })
        service.testFundamentalsFeed.entries = stale
        harness.ageRate()
        harness.stateThen("touch \"$1/RATE.down\"", function() {
          service.fetchFundamentals("SHOP.TO")
          harness.go(44)
        })
      } else if (harness.step === 44) {
        var asked = harness.calls("RATE") === 2 && !service.testFundamentalsFeed.busy
        if (!asked && harness.waited < 5000) return
        var renewed = service.fundamentals["SHOP.TO"]
        harness.check("a failed rate leaves the new cap and no P/E, never one in the wrong currency",
          asked && renewed.status === "ok" && harness.calls("SHOP.TO.fundamentals") === 2 && renewed.figures.cap.close > 0
            && service.rates.USDCAD.value === null,
          JSON.stringify({ shop: renewed, held: service.rates }))
        // Both listings on the pair wanted again the same day, the rate still
        // out of reach.
        harness.fundamentalsBefore = harness.calls("FUNDAMENTALS")
        service.fetchFundamentals("MAPLE.TO")
        service.fetchFundamentals("SHOP.TO")
        harness.go(45)
      } else if (harness.step === 45) {
        if (harness.waited < 1500) return
        harness.check("a failed rate counts as its pair's fetch for the day: no listing asks it again",
          harness.calls("RATE") === 2 && harness.calls("FUNDAMENTALS") === harness.fundamentalsBefore,
          (harness.calls("RATE") - 2) + " rates, " + (harness.calls("FUNDAMENTALS") - harness.fundamentalsBefore) + " fundamentals sent")
        // The next day the rate answers, and MAPLE.TO's series are still
        // fresh: the rate is asked alone, by the first listing that wants it.
        harness.ageRate()
        harness.stateThen("rm -f \"$1/RATE.down\"", function() {
          service.fetchFundamentals("MAPLE.TO")
          harness.go(46)
        })
      } else if (harness.step === 46) {
        var back = service.rates.USDCAD.value === 1.4004 && !service.testFundamentalsFeed.busy
        if (!back && harness.waited < 5000) return
        harness.check("a day-old rate is asked again on its own, and serves every listing on its pair",
          back && harness.calls("RATE") === 3 && harness.calls("MAPLE.TO.fundamentals") === 1
            && harness.calls("FUNDAMENTALS") === harness.fundamentalsBefore,
          JSON.stringify({ rates: harness.calls("RATE"), held: service.rates, maple: harness.calls("MAPLE.TO.fundamentals") }))
        // A day later, with Yahoo's fundamentals out of reach.
        var aged = Object.assign({}, service.testFundamentalsFeed.entries)
        harness.msftBefore = aged.MSFT
        aged.MSFT = Object.assign({}, aged.MSFT, { checkedAt: aged.MSFT.checkedAt - 25 * 60 * 60 })
        service.testFundamentalsFeed.entries = aged
        ticker.stop()
        endpointDown.running = true
      } else if (harness.step === 11) {
        var msft = service.fundamentals["MSFT"]
        if (msft.status !== "failed" && harness.waited < 5000) return
        harness.check("a failed fetch keeps the last good cap and P/E",
          msft.status === "failed" && harness.calls("MSFT.fundamentals") === 2 && !!msft.figures && !!msft.figures.cap
            && JSON.stringify(msft.figures) === JSON.stringify(harness.msftBefore.figures),
          JSON.stringify(msft))
        harness.go(12)
      } else if (harness.step === 12) {
        // The data file goes bad by hand while the lists are in memory.
        var bad = harness.unreadable[harness.unreadableAt]
        if (harness.unreadableAt === 0) {
          harness.goodLibrary = service.library.slice()
          harness.goodFeatured = service.featuredSymbol
          harness.goodBody = harness.bodyFrom({})
        }
        harness.writeThen(bad.body, function() { harness.go(13) })
      } else if (harness.step === 13) {
        var label = harness.unreadable[harness.unreadableAt].label
        if (!service.settingsUnreadable && harness.waited < 2000) return
        harness.check("a data file of " + label + " keeps the lists in memory and says it can't be read",
          service.settingsUnreadable && harness.sameSymbols(service.library, harness.goodLibrary)
            && service.featuredSymbol === harness.goodFeatured,
          JSON.stringify({ unreadable: service.settingsUnreadable, library: service.library, featured: service.featuredSymbol }))
        // The pill's wheel: a change that saves, but not over this file.
        service.featureStep(1)
        harness.go(14)
      } else if (harness.step === 14) {
        if (harness.waited < 600) return
        harness.readThen(function(obj, text) {
          var bad = harness.unreadable[harness.unreadableAt]
          harness.check("a change while it is " + bad.label + " applies in memory and writes nothing over it",
            text === bad.body && service.featuredSymbol !== harness.goodFeatured,
            JSON.stringify({ file: text, featured: service.featuredSymbol }))
          harness.renameThen(harness.goodBody, function() { harness.go(15) })
        })
      } else if (harness.step === 15) {
        // Fixed by an editor's atomic save: the file's settings, not the
        // ones changed in memory meanwhile.
        var fixed = !service.settingsUnreadable && service.featuredSymbol === harness.goodFeatured
          && harness.sameSymbols(service.library, harness.goodLibrary)
        if (!fixed && harness.waited < 2000) return
        harness.check("fixed while running, by an atomic save, the file is read again", fixed,
          JSON.stringify({ unreadable: service.settingsUnreadable, library: service.library, featured: service.featuredSymbol }))
        service.featureStep(1)
        harness.go(16)
      } else if (harness.step === 16) {
        harness.readThen(function(obj) {
          var saved = !!obj && obj.featured === service.featuredSymbol && obj.featured !== harness.goodFeatured
          if (!saved && harness.waited < 2000) return
          harness.check("once it reads again, a change is saved", saved, JSON.stringify(obj))
          harness.unreadableAt++
          if (harness.unreadableAt < harness.unreadable.length) {
            harness.renameThen(harness.goodBody, function() { harness.go(12) })
          } else {
            harness.writeThen(harness.unreadable[0].body, function() { harness.go(17) })
          }
        })
      } else if (harness.step === 17) {
        if (!service.settingsUnreadable && harness.waited < 2000) return
        harness.second = secondService.createObject(harness)
        harness.go(18)
      } else if (harness.step === 18) {
        if (!harness.second.pluginsReady && harness.waited < 5000) return
        harness.check("a shell started on a file that can't be read shows the starter list and says so",
          harness.second.pluginsReady && harness.second.settingsUnreadable
            && harness.sameSymbols(harness.second.library, Settings.fileSettings(null).symbols),
          JSON.stringify({ ready: harness.second.pluginsReady, unreadable: harness.second.settingsUnreadable,
            library: harness.second.library }))
        harness.second.featureStep(1)
        harness.go(19)
      } else if (harness.step === 19) {
        if (harness.waited < 600) return
        harness.readThen(function(obj, text) {
          harness.check("and a change there writes nothing over the file", text === harness.unreadable[0].body, text)
          harness.second.destroy()
          harness.second = null
          // A good file whose permissions don't let it be read.
          harness.writeTo(harness.dataPath, harness.goodBody, "unreadable", function() {
            harness.second = secondService.createObject(harness)
            harness.go(20)
          })
        })
      } else if (harness.step === 20) {
        if (!harness.second.pluginsReady && harness.waited < 5000) return
        var locked = harness.second.pluginsReady && harness.second.settingsUnreadable
        harness.second.featureStep(1)
        harness.lockedSaw = locked
        harness.go(21)
      } else if (harness.step === 21) {
        if (harness.waited < 600) return
        harness.writeTo(harness.dataPath, "", "readable", function() {
          harness.readThen(function(obj, text) {
            harness.check("a file there that can't be read for its permissions is said so and never written over",
              harness.lockedSaw && text === harness.goodBody, harness.lockedSaw + "|" + text)
            harness.second.destroy()
            harness.second = null
            harness.writeTo(harness.dataPath, "", "remove", function() { harness.go(22) })
          })
        })
      } else if (harness.step === 22) {
        if (service.settingsUnreadable && harness.waited < 2000) return
        service.persist({ range: "1M" })
        harness.go(23)
      } else if (harness.step === 23) {
        harness.readThen(function(obj) {
          var created = !service.settingsUnreadable && !!obj && obj.range === "1M"
          if (!created && harness.waited < 2000) return
          harness.check("a missing file is created by the next change", created, JSON.stringify(obj))
          harness.check("the version watch reads the running version from the manifest as it starts",
            updates.runningVersion === harness.manifest.version && updates.newVersion === "",
            updates.runningVersion + "|" + updates.newVersion)
          // Three range changes in one go, the third back to the first:
          // each write is still in flight as the next starts, since the
          // service hears one finished only on a later turn of the event
          // loop. Quickshell's async write then compared the third against
          // the cancelled first and skipped it, leaving 3M in the file,
          // which the file watch read back over the 1W in hand.
          harness.loadsAtBurst = harness.loads
          service.setRange("1W")
          service.setRange("3M")
          service.setRange("1W")
          harness.go(24)
        })
      } else if (harness.step === 24) {
        harness.readThen(function(obj) {
          var readBack = harness.loads > harness.loadsAtBurst
          var kept = readBack && !!obj && obj.range === "1W" && service.range === "1W"
          if (!kept && harness.waited < 2000) return
          harness.check("a change back to a range still being written lands, and the file's read-back keeps it", kept,
            JSON.stringify({ readBack: readBack, file: obj && obj.range, range: service.range }))
          harness.go(40)
        })
      } else if (harness.step === 40) {
        // The file gone again, and the disk refusing the link that puts a
        // made file in place (bin/ln), every chmod held (bin/chmod).
        harness.stateThen("touch \"$1/ln.fail\" \"$1/chmod.hold\"", function() {
          harness.writeTo(harness.dataPath, "", "remove", function() { harness.go(41) })
        })
      } else if (harness.step === 41) {
        if (!service.dataMissing && harness.waited < 2000) return
        service.persist({ range: "5Y" })
        harness.go(42)
      } else if (harness.step === 42) {
        if (!service.saveFailed && harness.waited < 3000) return
        harness.readThen(function(obj, text) {
          harness.check("a first save that can't be made its owner's alone is said unsaved, and leaves no file another account could read",
            service.saveFailed && text === null && service.range === "5Y", service.saveFailed + "|" + text + "|" + service.range)
          // Two changes, the second while the first is being made.
          harness.stateThen("rm -f \"$1/ln.fail\" && touch \"$1/ln.hold\"", function() {
            service.persist({ range: "1Y" })
            service.persist({ range: "3M" })
            harness.stateThen("rm -f \"$1/ln.hold\"", function() { harness.go(43) })
          })
        })
      } else if (harness.step === 43) {
        harness.readThen(function(obj) {
          var landed = !!obj && obj.range === "3M" && !service.saveFailed && service.range === "3M"
          if (!landed && harness.waited < 3000) return
          harness.afterMode = function(mode) {
            harness.check("the next change makes it, its owner's alone from its first write, and a change made meanwhile lands in it",
              landed && mode === "600", JSON.stringify({ file: obj && obj.range, range: service.range, failed: service.saveFailed, mode: mode }))
            releaseChmod.running = true
            harness.go(25)
          }
          ticker.stop()
          modeProc.running = true
        })
      } else if (harness.step === 25) {
        // Each manifest as a surface's open checks it.
        var c = harness.versionCases[harness.versionAt]
        harness.writeTo(harness.manifestPath, c.body, c.how, function() {
          updates.check()
          harness.check(c.label, updates.newVersion === c.want, updates.newVersion)
          harness.versionAt++
          if (harness.versionAt < harness.versionCases.length) harness.go(25)
          else harness.go(26)
        })
      } else if (harness.step === 26) {
        // A save from elsewhere while the service reads its own write back,
        // its notice coming before that read ends, as a loaded machine can
        // order them. Quickshell ignores a reload asked for while a read is
        // in flight, so the read must follow once that one ends.
        harness.stepped = steppedService.createObject(harness)
        var file = harness.stepped.testDataFile
        file.endRead()
        harness.stepped.setRange("1D")
        file.fileChanged()
        file.saveElsewhere(harness.withRange(harness.stepped, "1Y"))
        harness.go(27)
      } else if (harness.step === 27) {
        if (harness.settling()) return
        harness.check("a save from elsewhere during a read of the file lands once that read ends",
          harness.stepped.range === "1Y", harness.stepped.range)
        // A write of the service's own drops a read in flight unheard; a
        // save from elsewhere during the next read still lands.
        var own = harness.stepped.testDataFile
        harness.stepped.setRange("1M")
        own.fileChanged()
        harness.stepped.setRange("3M")
        own.fileChanged()
        own.saveElsewhere(harness.withRange(harness.stepped, "1W"))
        harness.go(28)
      } else if (harness.step === 28) {
        if (harness.settling()) return
        harness.check("so does one after a write of the service's own cut a read short",
          harness.stepped.range === "1W", harness.stepped.range)
        // A save that lands, then one a full disk loses before the first is
        // read back: the file holds the first, which is no save from
        // elsewhere, so the second stays in memory, said unsaved, until a
        // save lands.
        var disk = harness.stepped.testDataFile
        harness.stepped.setRange("1M")
        disk.full = true
        harness.stepped.setRange("3M")
        harness.go(29)
      } else if (harness.step === 29) {
        if (harness.settling()) return
        harness.check("a save a full disk loses just after one that landed is said unsaved, and the change stays",
          harness.stepped.saveFailed && harness.stepped.range === "3M", harness.stepped.saveFailed + " " + harness.stepped.range)
        harness.stepped.testDataFile.full = false
        harness.stepped.saveAgain()
        harness.go(30)
      } else if (harness.step === 30) {
        if (harness.settling()) return
        var saved = harness.parseFile(harness.stepped.testDataFile.disk)
        harness.check("with room again, trying again saves it and the notice goes",
          !harness.stepped.saveFailed && !!saved && saved.range === "3M", harness.stepped.saveFailed + " " + JSON.stringify(saved && saved.range))
        harness.stepped.destroy()
        harness.stepped = null
        harness.finish()
      }
    }
  }

  HarnessExit { id: exitTimer }
}
