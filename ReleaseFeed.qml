import QtQuick
import "Fetch.js" as Fetch
import "Release.js" as Release
// The newest Stonks: the version in main's manifest on GitHub. An ask with
// no answer at all, as after a wake, goes again once Yahoo answers
// (`askAgain`): asked at the end of each of GitHub's short pauses, it would
// go about once a minute while the network is down.
Item {
  id: root

  property string version: ""
  property bool ready: false
  // `now` moves the feed to look; `clock.wallSecond()` is what it reads.
  property int now: 0
  property var clock: null
  property var clearance: null
  property var gate: null
  property int askedAt: 0
  property bool unanswered: false

  readonly property int interval: 24 * 60 * 60

  function pump() {
    if (!ready || fetchRun.out) return
    var now = clock.wallSecond()
    if (askedAt > 0 && now - askedAt < interval) return
    if (clearance && !clearance()) return
    if (gate && gate.take(1) === 0) return
    root.askedAt = now
    fetchRun.send([Release.MANIFEST_URL], Fetch.MANIFEST_CAP)
  }
  onNowChanged: pump()
  onReadyChanged: pump()

  function askAgain() {
    if (!unanswered) return
    root.askedAt = 0
    pump()
  }

  function receive(got) {
    root.unanswered = got.length > 0 && got.every(function(a) { return a.kind === "none" })
    var named = got.length && got[0].kind === "ok" ? Release.manifestVersion(got[0].body) : ""
    if (named === "") return
    root.version = named
  }

  FetchRun {
    id: fetchRun
    gate: root.gate
    onEnded: function(got) { root.receive(got) }
  }
}
