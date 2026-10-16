import QtQuick
import Quickshell
import Quickshell.Io

// Drives the real QuoteFeed through its scenarios with the fake curl that
// test/qml/run.sh puts first on PATH: runs of several symbols, the first
// answers' lane beside the refreshes', retries by what came back, and
// recovery. Quickshell only loads QML from inside its config folder, so
// run.sh assembles one from copies of the plugin's QuoteFeed.qml and the
// rule files it imports beside this file. No gate: the service's own flows
// (fetch.sh) drive the feed through one. Prints one line per check and
// exits 0 when every check passed, 1 otherwise.
ShellRoot {
  id: harness

  property int failures: 0
  property int step: 0
  property int now: 1791000000

  function check(name, ok, detail) {
    console.log((ok ? "PASS " : "FAIL ") + name + (detail !== undefined ? " — " + detail : ""))
    if (!ok) harness.failures++
  }

  function status(symbol) {
    var e = feed.entries[symbol]
    return e ? e.status : "none"
  }

  function receipt(symbol) {
    var e = feed.entries[symbol]
    return e ? e.receivedAt : 0
  }

  // A refresh of every member, as the service asks for what is due.
  function refresh() {
    harness.now += 60
    feed.ask(feed.symbols, harness.now)
  }

  QuoteFeed {
    id: feed
    now: harness.now
    watched: symbols
  }

  // Each step waits for the feed to go quiet, then checks and advances.
  Timer {
    id: ticker
    interval: 200
    running: true
    repeat: true
    onTriggered: {
      if (feed.busy) return
      ticker.stop()
      harness.advance()
    }
  }

  function advance() {
    harness.step++
    if (harness.step === 1) {
      // One symbol succeeds, one fails after its three tries, and the
      // failure inherits nothing from the success; both in one run.
      feed.symbols = ["AAPL", "FAIL"]
    } else if (harness.step === 2) {
      check("AAPL ok, with a quote and a receipt", status("AAPL") === "ok" && !!feed.quotes["AAPL"] && receipt("AAPL") === harness.now,
        status("AAPL") + "|" + receipt("AAPL"))
      check("FAIL failed after three tries, with no quote and no receipt",
        status("FAIL") === "failed" && !feed.quotes["FAIL"] && receipt("FAIL") === 0 && harness.calls("FAIL") === 3,
        status("FAIL") + "|" + harness.calls("FAIL"))
      check("the first answers went in one run, the retries in runs of their own",
        harness.runs()[0] === "chart:AAPL chart:FAIL" && harness.runs()[1] === "chart:FAIL", harness.runs().join(" / "))
      // Retry then recovery, and a symbol that fails after it once
      // succeeded keeps its quote and receipt.
      feed.symbols = ["AAPL", "FAIL", "FLAKY", "ONCE"]
    } else if (harness.step === 3) {
      check("FLAKY recovered after retries", status("FLAKY") === "ok", status("FLAKY"))
      check("ONCE ok on first answer", status("ONCE") === "ok", status("ONCE"))
      harness.onceReceipt = receipt("ONCE")
      harness.aaplQuote = feed.quotes["AAPL"]
      harness.runsBefore = harness.runs().length
      // A refresh of everything: ONCE now fails, AAPL succeeds again, FAIL
      // fails; the lead goes first.
      feed.lead = "ONCE"
      harness.refresh()
    } else if (harness.step === 4) {
      check("a refresh is one run, the lead first",
        harness.runs()[harness.runsBefore] === "chart:ONCE chart:AAPL chart:FAIL chart:FLAKY", harness.runs()[harness.runsBefore])
      check("ONCE failed on refresh, keeping its quote and receipt",
        status("ONCE") === "failed" && !!feed.quotes["ONCE"] && receipt("ONCE") === harness.onceReceipt,
        status("ONCE") + "|" + receipt("ONCE") + " vs " + harness.onceReceipt)
      check("the refresh leaves AAPL ok and FAIL failed without a quote",
        status("AAPL") === "ok" && status("FAIL") === "failed" && !feed.quotes["FAIL"])
      // The same answer again keeps the quote on screen, so no line repaints
      // for it, and still counts as received.
      check("an unchanged answer keeps the quote already shown, and its receipt moves",
        feed.quotes["AAPL"] === harness.aaplQuote && receipt("AAPL") === harness.now,
        receipt("AAPL") + " vs " + harness.now)
      feed.lead = ""
      // A symbol that leaves takes its quote, entry, and ask with it.
      feed.symbols = ["STRAY"]
    } else if (harness.step === 5) {
      check("a symbol that left took its quote and entry with it",
        !feed.quotes["AAPL"] && !feed.entries["AAPL"] && !feed.quotes["ONCE"] && !feed.entries["ONCE"])
      // run.sh checks that two identical answers log the dropped bucket once.
      harness.refresh()
    } else if (harness.step === 6) {
      // Coming back is a first fetch again: no receipt from the last visit.
      feed.symbols = ["STRAY", "AAPL"]
      check("a returning symbol starts with no quote or entry, and is asked for its first answer",
        !feed.quotes["AAPL"] && !feed.entries["AAPL"] && "AAPL" in feed.asked && feed.firstRun.indexOf("AAPL") >= 0,
        JSON.stringify(feed.entries["AAPL"]) + "|" + feed.firstRun)
    } else if (harness.step === 7) {
      // FAIL fails and pauses before its retry; removed in the pause, the
      // retry writes nothing back.
      feed.symbols = ["FAIL"]
    } else if (harness.step === 8) {
      check("a retry that fires after its symbol was removed writes nothing",
        !feed.entries["FAIL"] && !feed.quotes["FAIL"], JSON.stringify(feed.entries["FAIL"]))
      // BLIP answers once, then fails twice, then answers: a refresh after a
      // success still gets its full tries.
      feed.symbols = ["BLIP"]
    } else if (harness.step === 9) {
      check("BLIP ok after one request", status("BLIP") === "ok" && harness.calls("BLIP") === 1, String(harness.calls("BLIP")))
      harness.refresh()
    } else if (harness.step === 10) {
      check("a refresh after a success still retries: BLIP recovers on its third request",
        status("BLIP") === "ok" && harness.calls("BLIP") === 4, status("BLIP") + " after " + (harness.calls("BLIP") - 1) + " requests")
      harness.failCalls = harness.calls("FAIL")
      feed.symbols = ["FAIL"]
    } else if (harness.step === 11) {
      harness.failCalls = harness.calls("FAIL")
      harness.refresh()
    } else if (harness.step === 12) {
      check("a refresh after a final failure gets its full tries: three requests again",
        status("FAIL") === "failed" && harness.calls("FAIL") - harness.failCalls === 3,
        status("FAIL") + " after " + (harness.calls("FAIL") - harness.failCalls) + " requests")
      // A missing symbol fails at once; an answer over the cap is a bad
      // answer, tried three times.
      feed.symbols = ["GONE", "HUGE"]
    } else if (harness.step === 13) {
      check("a symbol the host does not know fails on its one request",
        status("GONE") === "failed" && harness.calls("GONE") === 1, status("GONE") + " after " + harness.calls("GONE"))
      check("an answer over the size cap is a bad answer: three tries, then failed",
        status("HUGE") === "failed" && !feed.quotes["HUGE"] && harness.calls("HUGE") === 3,
        status("HUGE") + " after " + harness.calls("HUGE"))
      feed.symbols = ["SLOW", "MSFT"]
    } else if (harness.step === 14) {
      // A symbol added while a refresh is out goes in the first answers'
      // lane at once: SLOW holds the refresh's run for a second.
      harness.refresh()
      check("the refresh is out when NVDA is added", feed.refreshRun.join() === "SLOW,MSFT", feed.refreshRun.join())
      feed.symbols = ["SLOW", "MSFT", "NVDA"]
    } else if (harness.step === 15) {
      check("a symbol added during a refresh lands before the refresh does", harness.nvdaBeforeRefresh, String(harness.nvdaBeforeRefresh))
      // The fake curl names each answer for the symbol asked for.
      check("every quote kept, through every step, is the symbol it is kept under",
        harness.misfiled.length === 0 && Object.keys(feed.quotes).every(function(key) { return feed.quotes[key].symbol === key }),
        harness.misfiled.join(", "))
      console.log(harness.failures === 0 ? "ALL PASS" : harness.failures + " FAILED")
      exitTimer.exitCode = harness.failures === 0 ? 0 : 1
      exitTimer.start()
      return
    }
    ticker.start()
  }

  property int onceReceipt: 0
  property var aaplQuote: null
  property int failCalls: 0
  property int runsBefore: 0
  property bool nvdaBeforeRefresh: false
  property var misfiled: []

  Connections {
    target: feed
    function onQuotesChanged() {
      for (var key in feed.quotes)
        if (feed.quotes[key] && feed.quotes[key].symbol !== key) harness.misfiled.push(key + " as " + feed.quotes[key].symbol)
      if (harness.step === 14 && feed.quotes["NVDA"] && feed.refreshRun.length > 0) harness.nvdaBeforeRefresh = true
    }
    // run.sh patches testRetrying into the copy: the retry pause is running.
    function onTestRetryingChanged() {
      if (harness.step === 7 && feed.testRetrying) feed.symbols = []
    }
  }

  // The fake curl counts its calls per name in STONKS_FAKE_STATE. A fresh
  // view per read: a FileView that has loaded once returns its old text
  // straight after reload().
  function read(name) {
    var view = Qt.createQmlObject('import Quickshell.Io; FileView { blockLoading: true; printErrors: false }', harness)
    view.path = Quickshell.env("STONKS_FAKE_STATE") + "/" + name
    var text = String(view.text())
    view.destroy()
    return text
  }

  function calls(name) {
    return Number(read(name + ".calls").trim() || "0")
  }

  // Each curl call, its URLs as kind:name.
  function runs() {
    return read("runs.log").split("\n").filter(function(line) { return line !== "" })
  }

  HarnessExit { id: exitTimer }
}
