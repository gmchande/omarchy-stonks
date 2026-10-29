import QtQuick
import Quickshell
import Quickshell.Io

// Drives the real QuoteFeed through its scenarios with the fake curl that
// quote-queue.sh puts first on PATH: runs of several symbols, the first
// answers' lane beside the refreshes', retries by what came back, and
// recovery. Every symbol on the chart endpoint, one answer each (`bulk`
// false, as the preview's feed asks), so each symbol's answer is its own:
// spark's batches are long-list.sh's. No gate: the service's own flows
// (fetch.sh) drive the feed through one.
Harness {
  id: harness
  marker: "QUOTE QUEUE DONE"

  property int step: 0
  property int now: 1791000000
  property int onceReceipt: 0
  property var aaplQuote: null
  property bool blipFirst: false
  property int failCalls: 0
  property int runsBefore: 0
  property string refreshOut: ""
  property bool nvdaBeforeRefresh: false
  property var misfiled: []

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

  // Each curl call, its URLs as kind:name.
  function runs() {
    return readFile(Quickshell.env("STONKS_FAKE_STATE") + "/runs.log").split("\n").filter(function(line) { return line !== "" })
  }

  QuoteFeed {
    id: feed
    now: harness.now
    watched: symbols
    bulk: false
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
      // Both in one run: the failure inherits nothing from the success.
      feed.symbols = ["AAPL", "FAIL"]
    } else if (harness.step === 2) {
      check("AAPL ok, with a quote and a receipt", status("AAPL") === "ok" && !!feed.quotes["AAPL"] && receipt("AAPL") === harness.now,
        status("AAPL") + "|" + receipt("AAPL"))
      check("FAIL failed after three tries, with no quote and no receipt",
        status("FAIL") === "failed" && !feed.quotes["FAIL"] && receipt("FAIL") === 0 && calls("FAIL") === 3,
        status("FAIL") + "|" + calls("FAIL"))
      check("the first answers went in one run, the retries in runs of their own",
        harness.runs()[0] === "chart:AAPL chart:FAIL" && harness.runs()[1] === "chart:FAIL", harness.runs().join(" / "))
      feed.symbols = ["AAPL", "FAIL", "FLAKY", "ONCE"]
    } else if (harness.step === 3) {
      check("FLAKY recovered after retries", status("FLAKY") === "ok", status("FLAKY"))
      harness.onceReceipt = status("ONCE") === "ok" ? receipt("ONCE") : 0
      harness.aaplQuote = feed.quotes["AAPL"]
      harness.runsBefore = harness.runs().length
      // ONCE now fails, AAPL answers the same again, FAIL fails.
      feed.lead = "ONCE"
      harness.refresh()
    } else if (harness.step === 4) {
      check("a refresh is one run, the lead first",
        harness.runs()[harness.runsBefore] === "chart:ONCE chart:AAPL chart:FAIL chart:FLAKY", harness.runs()[harness.runsBefore])
      check("ONCE failed on refresh, keeping its quote and receipt",
        harness.onceReceipt > 0 && status("ONCE") === "failed" && !!feed.quotes["ONCE"] && receipt("ONCE") === harness.onceReceipt
          && status("AAPL") === "ok" && status("FAIL") === "failed" && !feed.quotes["FAIL"],
        status("ONCE") + "|" + receipt("ONCE") + " vs " + harness.onceReceipt + ", AAPL " + status("AAPL") + ", FAIL " + status("FAIL"))
      // The very object: a copy equal in content would repaint every line.
      check("an unchanged answer keeps the quote already shown, and its receipt moves",
        feed.quotes["AAPL"] === harness.aaplQuote && receipt("AAPL") === harness.now,
        receipt("AAPL") + " vs " + harness.now)
      feed.lead = ""
      feed.symbols = ["MSFT"]
    } else if (harness.step === 5) {
      // AAPL left at the step before: coming back is a first fetch again.
      feed.symbols = ["MSFT", "AAPL"]
      check("a returning symbol starts with no quote or entry, and is asked for its first answer",
        !feed.quotes["AAPL"] && !feed.entries["AAPL"] && "AAPL" in feed.asked && feed.firstRun.indexOf("AAPL") >= 0,
        JSON.stringify(feed.entries["AAPL"]) + "|" + feed.firstRun)
    } else if (harness.step === 6) {
      // FAIL fails and pauses before its retry; removed in the pause, the
      // retry writes nothing back.
      feed.symbols = ["FAIL"]
    } else if (harness.step === 7) {
      check("a retry that fires after its symbol was removed writes nothing",
        !feed.entries["FAIL"] && !feed.quotes["FAIL"], JSON.stringify(feed.entries["FAIL"]))
      // BLIP answers once, then fails twice, then answers.
      feed.symbols = ["BLIP"]
    } else if (harness.step === 8) {
      harness.blipFirst = status("BLIP") === "ok" && calls("BLIP") === 1
      harness.refresh()
    } else if (harness.step === 9) {
      check("a refresh after a success still retries: BLIP recovers on its third request",
        harness.blipFirst && status("BLIP") === "ok" && calls("BLIP") === 4, status("BLIP") + " after " + calls("BLIP") + " requests in all")
      feed.symbols = ["FAIL"]
    } else if (harness.step === 10) {
      harness.failCalls = calls("FAIL")
      harness.refresh()
    } else if (harness.step === 11) {
      check("a refresh after a final failure gets its full tries: three requests again",
        status("FAIL") === "failed" && calls("FAIL") - harness.failCalls === 3,
        status("FAIL") + " after " + (calls("FAIL") - harness.failCalls) + " requests")
      // A missing symbol fails at once; an answer over the cap is a bad
      // answer, tried three times.
      feed.symbols = ["GONE", "HUGE"]
    } else if (harness.step === 12) {
      check("a symbol the host does not know fails on its one request",
        status("GONE") === "failed" && calls("GONE") === 1, status("GONE") + " after " + calls("GONE"))
      check("an answer over the size cap is a bad answer: three tries, then failed",
        status("HUGE") === "failed" && !feed.quotes["HUGE"] && calls("HUGE") === 3,
        status("HUGE") + " after " + calls("HUGE"))
      feed.symbols = ["SLOW", "MSFT"]
    } else if (harness.step === 13) {
      // SLOW holds the refresh's run for a second; NVDA goes in the first
      // answers' lane meanwhile.
      harness.refresh()
      harness.refreshOut = feed.refreshRun.join()
      feed.symbols = ["SLOW", "MSFT", "NVDA"]
    } else if (harness.step === 14) {
      check("a symbol added during a refresh lands before the refresh does",
        harness.refreshOut === "SLOW,MSFT" && harness.nvdaBeforeRefresh, harness.refreshOut + "|" + harness.nvdaBeforeRefresh)
      // The fake curl names each answer for the symbol asked for.
      check("every quote kept, through every step, is the symbol it is kept under",
        harness.misfiled.length === 0 && Object.keys(feed.quotes).every(function(key) { return feed.quotes[key].symbol === key }),
        harness.misfiled.join(", "))
      feed.symbols = ["MSFT", "NVDA"]
    } else if (harness.step === 15) {
      // A chart drawing itself in holds the feed: no answer is read, the
      // hero's MSFT included; each waits, still asked, for the motion to end.
      feed.lead = "MSFT"
      feed.holding = true
      harness.refresh()
      heldWatch.start()
      return
    } else if (harness.step === 16) {
      check("once the hold ends, what it held is read",
        ["MSFT", "NVDA"].every(function(s) { return receipt(s) === harness.now && !(s in feed.asked) }),
        receipt("MSFT") + ", " + receipt("NVDA") + " vs " + harness.now)
      feed.lead = ""
      feed.symbols = ["MSFT", "SLOW"]
    } else if (harness.step === 17) {
      // A reader's refresh of both: MSFT answers at once, SLOW a second
      // later. Asked for again meanwhile, MSFT is still waited on as the
      // first run ends.
      harness.now += 60
      feed.ask(["MSFT", "SLOW"], harness.now, true)
      reaskWatch.start()
      return
    } else if (harness.step === 18) {
      check("a symbol a reader asks for again while its last run is out stays waited on as that run ends",
        harness.reaskedWaited, JSON.stringify(feed.userAsked))
      finish()
      return
    }
    ticker.start()
  }

  // MSFT's answer is in and SLOW's still out: MSFT is asked for again.
  property bool reasked: false
  property bool reaskEnded: false
  property bool reaskedWaited: false
  Timer {
    id: reaskWatch
    interval: 20
    repeat: true
    onTriggered: {
      if (receipt("MSFT") !== harness.now || !("SLOW" in feed.asked)) return
      reaskWatch.stop()
      harness.reasked = true
      feed.ask(["MSFT"], harness.now, true)
      ticker.start()
    }
  }

  // The held run has ended and MSFT's answer is read: NVDA's is in hand,
  // unread.
  Timer {
    id: heldWatch
    interval: 20
    repeat: true
    onTriggered: {
      var run = feed.landing[0]
      if (!run || !run.ended) return
      heldWatch.stop()
      check("while a chart draws in, no answer is read, the hero's included; each waits, still asked",
        ["MSFT", "NVDA"].every(function(s) { return receipt(s) < harness.now && s in feed.asked }),
        receipt("MSFT") + ", " + receipt("NVDA") + " vs " + harness.now)
      feed.holding = false
      ticker.start()
    }
  }

  Connections {
    target: feed
    function onQuotesChanged() {
      for (var key in feed.quotes)
        if (feed.quotes[key] && feed.quotes[key].symbol !== key) harness.misfiled.push(key + " as " + feed.quotes[key].symbol)
      if (harness.step === 13 && feed.quotes["NVDA"] && feed.refreshRun.length > 0) harness.nvdaBeforeRefresh = true
    }
    // The first run of the reader's refresh ends: is MSFT's new ask still
    // waited on?
    function onRefreshRunChanged() {
      if (harness.step !== 17 || !harness.reasked || harness.reaskEnded || feed.refreshRun.length > 0) return
      harness.reaskEnded = true
      harness.reaskedWaited = "MSFT" in feed.userAsked
    }
    // quote-queue.sh patches testRetrying into the copy: the retry pause is running.
    function onTestRetryingChanged() {
      if (harness.step === 6 && feed.testRetrying) feed.symbols = []
    }
  }
}
