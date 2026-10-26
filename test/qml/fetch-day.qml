import QtQuick
import QtTest
import Quickshell
import Quickshell.Io
import "plugin" as Stonks

// A whole day of glances through the real Service and App on a clock this
// harness sets, for fetch-day.sh to count: Wednesday 7 October 2026 and
// Saturday 10 October, New York time, midnight to midnight, in steps of
// 5 s. The list is a long one, 34 symbols: 32 US stocks, an ETF, and
// a Toronto listing. A weekday of glances is the policy's: 60 opens of 30 s
// (18 in pre-market, 24 in the regular session, 18 after hours), a 30-minute
// window at noon, and 5 opens after 20:00; a weekend, 20 opens. Each day's
// requests and curl calls are where its lines of the fake curl's logs start
// and end, printed as "DAY <name> <requests> <runs>".
ShellRoot {
  id: harness

  readonly property int wed7: 1791345600
  readonly property int sat10: 1791604800

  // How many lines a fake curl log has, read through a fresh view: a
  // FileView that has loaded once returns its old text after reload().
  function lines(name) {
    var view = Qt.createQmlObject('import Quickshell.Io; FileView { blockLoading: true; printErrors: false }', harness)
    view.path = Quickshell.env("STONKS_FAKE_STATE") + "/" + name
    var n = String(view.text() || "").split("\n").filter(function(l) { return l !== "" }).length
    view.destroy()
    return n
  }

  Stonks.Service { id: service }
  Stonks.App { id: app; service: service }

  TestCase {
    name: "FetchDay"
    when: service.pluginsReady

    function idle() {
      var feed = service.testFeed
      return feed.firstRun.length === 0 && feed.refreshRun.length === 0
    }

    // Opens of 30 s at each of `opens` (seconds after the day's midnight),
    // and a window of `window` seconds at `windowAt`.
    function day(name, midnight, opens, windowAt, windowFor) {
      service.now = midnight
      tryVerify(idle, 30000)
      var from = [harness.lines("requests.log"), harness.lines("runs.log")]
      var openUntil = 0
      for (var t = midnight; t < midnight + 86400; t += 5) {
        var since = t - midnight
        if (opens.indexOf(since) >= 0) {
          app.open("{}")
          openUntil = t + 30
        } else if (windowAt >= 0 && since === windowAt) {
          app.open("{}")
          openUntil = t + windowFor
        } else if (openUntil && t >= openUntil) {
          app.close()
          openUntil = 0
        }
        service.now = t
        if (!idle()) tryVerify(idle, 30000)
      }
      if (openUntil) app.close()
      console.log("DAY " + name + " " + from[0] + " " + harness.lines("requests.log") + " " + from[1] + " " + harness.lines("runs.log"))
    }

    // `count` opens spread evenly from `from` to `to`, hours after midnight.
    function spread(count, from, to) {
      var out = []
      for (var i = 0; i < count; i++) out.push(Math.round((from + (to - from) * (i + 0.5) / count) * 3600 / 5) * 5)
      return out
    }

    function test_days() {
      tryVerify(function() { return service.library.every(function(s) { return !!service.quotes[s] }) && idle() }, 30000)
      var weekday = spread(18, 4, 9.5).concat(spread(24, 9.5, 16), spread(18, 16, 20), spread(5, 20, 24))
      day("weekday", harness.wed7, weekday, 12 * 3600 + 15, 30 * 60)
      day("weekend", harness.sat10, spread(20, 8, 23), -1, 0)
      console.log("FETCH DAY DONE")
      done.start()
    }
  }

  HarnessExit { id: done }
}
