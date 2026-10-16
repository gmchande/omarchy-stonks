import QtQuick
import Quickshell
import Quickshell.Io

// Drives HistoryFeed through caching, supersession, retry, and last-good.
// The feed has one chart wanted at a time, as the service asks for it.
ShellRoot {
  id: harness

  property int failures: 0
  property int step: 0
  property var onceHistory: null
  property int onceReceipt: 0
  // When the chart that superseded SLOW was asked for, and when it landed.
  property double latestAskedAt: 0
  property double latestLandedAt: 0
  property int failCalls: 0

  function check(name, ok, detail) {
    console.log((ok ? "PASS " : "FAIL ") + name + (detail !== undefined ? " — " + detail : ""))
    if (!ok) harness.failures++
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

  // The key the surfaces read, "SYMBOL|RANGE".
  function entry(symbol, range) {
    return feed.entries[symbol + "|" + range] || null
  }

  function waitFor(next) {
    harness.step = next
    ticker.start()
  }

  function finish() {
    console.log(harness.failures === 0 ? "ALL PASS" : harness.failures + " FAILED")
    exitTimer.exitCode = harness.failures === 0 ? 0 : 1
    exitTimer.start()
  }

  HistoryFeed { id: feed }

  Connections {
    target: feed
    function onEntriesChanged() {
      var latest = harness.entry("MSFT", "2Y")
      if (harness.latestAskedAt && !harness.latestLandedAt && latest && latest.status === "ok")
        harness.latestLandedAt = Date.now()
    }
  }

  Component.onCompleted: {
    feed.request("AAPL", "1Y")
    waitFor(0)
  }

  Timer {
    id: ticker
    interval: 50
    repeat: true
    onTriggered: {
      if (feed.busy) return
      ticker.stop()
      harness.advance()
    }
  }

  function advance() {
    if (step === 0) {
      check("a wanted chart is fetched", entry("AAPL", "1Y") && entry("AAPL", "1Y").status === "ok")
      feed.request("AAPL", "1Y")
      cachePause.start()
    } else if (step === 2) {
      check("superseded slow response dropped", entry("SLOW", "1Y") === null)
      check("a chart passed over before it launched never launches",
        calls("AAPL") === 1 && entry("AAPL", "1M") === null, String(calls("AAPL")))
      var latest = entry("MSFT", "2Y")
      check("latest symbol and range win", latest && latest.status === "ok" && latest.history.range === "2Y")
      check("slow request ran once", calls("SLOW") === 1, String(calls("SLOW")))
      check("latest request ran once", calls("MSFT") === 1, String(calls("MSFT")))
      // SLOW answers after a second. Waited out, it held the new chart back
      // until then; stopped, the new chart goes at once.
      check("a stale download is stopped, not waited out",
        latestLandedAt - latestAskedAt < 600, (latestLandedAt - latestAskedAt) + " ms")
      feed.request("ONCE", "1Y")
      waitFor(3)
    } else if (step === 3) {
      var once = entry("ONCE", "1Y")
      check("last-good fixture loaded", once && once.status === "ok")
      harness.onceHistory = once ? once.history : null
      harness.onceReceipt = once ? once.receivedAt : 0
      feed.request("ONCE", "1Y", true)
      waitFor(4)
    } else if (step === 4) {
      var failedRefresh = entry("ONCE", "1Y")
      check("failed refresh is visible", failedRefresh && failedRefresh.status === "failed")
      check("failed refresh keeps history", failedRefresh && failedRefresh.history === onceHistory)
      check("failed refresh keeps receipt", failedRefresh && failedRefresh.receivedAt === onceReceipt)
      check("one retry only", calls("ONCE") === 3, String(calls("ONCE")))
      feed.request("FAIL", "1Y")
      waitFor(5)
    } else if (step === 5) {
      check("initial failure tried twice", calls("FAIL") === 2, String(calls("FAIL")))
      // Refreshed, it fails at once, and the refresh is superseded in its
      // retry pause (failedSwitch).
      harness.failCalls = calls("FAIL")
      feed.request("FAIL", "1Y", true)
      harness.refreshingFail = true
    } else if (step === 6) {
      // Still failed and with no history invented: from the first fetch, and
      // restored when the refresh that replaced it is itself superseded.
      var restoredFailure = entry("FAIL", "1Y")
      var afterFailure = entry("AAPL", "2Y")
      check("superseding a failed refresh in its retry pause preserves failure",
        switchedInPause && restoredFailure && restoredFailure.status === "failed" && !restoredFailure.history,
        switchedInPause + "|" + JSON.stringify(restoredFailure))
      check("a superseded retry never runs", calls("FAIL") === failCalls + 1, String(calls("FAIL") - failCalls))
      check("request after failed refresh succeeds", afterFailure && afterFailure.status === "ok")
      // The day wants no history: going back to it in a retry pause ends
      // the retry too.
      harness.failCalls = calls("FAIL")
      feed.request("FAIL", "1Y", true)
      harness.clearingFail = true
    } else if (step === 7) {
      check("the day's clear drops the retry: nothing is left to run",
        clearedIdle && calls("FAIL") === failCalls + 1 && entry("FAIL", "1Y").status === "failed",
        clearedIdle + "|" + (calls("FAIL") - failCalls) + "|" + JSON.stringify(entry("FAIL", "1Y")))
      // history.sh checks that two identical answers log the dropped buckets once.
      feed.request("HISTSTRAY", "1W")
      waitFor(8)
    } else if (step === 8) {
      feed.request("HISTSTRAY", "1W", true)
      waitFor(9)
    } else if (step === 9) {
      finish()
    }
  }

  Timer {
    id: cachePause
    interval: 200
    onTriggered: {
      check("fresh cache returns without curl", !feed.busy && calls("AAPL") === 1, String(calls("AAPL")))
      feed.request("SLOW", "1Y")
      switchAway.start()
    }
  }

  // A range stepped past and the next, both while SLOW is out.
  Timer {
    id: switchAway
    interval: 100
    onTriggered: {
      feed.request("AAPL", "1M")
      harness.latestAskedAt = Date.now()
      feed.request("MSFT", "2Y")
      waitFor(2)
    }
  }

  // history.sh patches testRetrying into the copy: the retry pause is
  // running. The switch waits a moment into it, for the failed curl to end.
  property bool refreshingFail: false
  property bool switchedInPause: false
  property bool clearingFail: false
  property bool clearedIdle: false
  Connections {
    target: feed
    function onTestRetryingChanged() {
      if (!feed.testRetrying) return
      if (harness.refreshingFail) {
        harness.refreshingFail = false
        failedSwitch.start()
      } else if (harness.clearingFail) {
        harness.clearingFail = false
        failedClear.start()
      }
    }
  }

  Timer {
    id: failedSwitch
    interval: 50
    onTriggered: {
      harness.switchedInPause = feed.testRetrying
      feed.request("AAPL", "2Y")
      waitFor(6)
    }
  }

  Timer {
    id: failedClear
    interval: 50
    onTriggered: {
      feed.clear()
      harness.clearedIdle = !feed.busy
      // Past the retry pause, so a retry that still ran would be counted.
      retryPassed.start()
    }
  }

  Timer {
    id: retryPassed
    interval: 400
    onTriggered: waitFor(7)
  }

  HarnessExit { id: exitTimer }
}
