import QtQuick
import "Fetch.js" as Fetch
import "Search.js" as Search
// Yahoo's lookup for the words in the search field: one request at a time,
// a quarter second after the typing stops. Words typed while a lookup is
// out wait behind it, and an answer counts only for the words still wanted.
// While search stays open, words Yahoo has answered are not asked again.
Item {
  id: root

  // Yahoo's gate (`Gate.qml`), held by the service; null without one.
  property var gate: null
  // Whether a lookup may go now. One held back waits for `pump`.
  property var clearance: null
  // The search is open, and the words in its field.
  property bool active: false
  property string wanted: ""

  // The words a lookup is out for, and the words waiting behind it.
  property string activeQuery: ""
  property string requestedQuery: ""
  readonly property bool out: fetchRun.out
  // The answers read since search opened, by their words: typed again, as
  // after a Backspace, they answer at once and nothing is asked.
  property var kept: new Map()
  onActiveChanged: if (!active) kept.clear()

  // A lookup is out for the words wanted.
  signal asked()
  // A lookup ended, whatever it was for.
  signal ended()
  // The answer for the words still wanted, as `Search.parseSearch` read it.
  // A null is no answer, failed for `why`: "none" when nothing answered,
  // "refused", "missing" when Yahoo called the question wrong (as it does an
  // emoji), or "other" (`Search.failure`).
  signal answered(string query, var found, string why)

  function askSoon() {
    if (kept.has(wanted)) {
      debounce.stop()
      ask()
    } else debounce.restart()
  }

  // A lookup already out for these same words answers them.
  function ask() {
    var q = wanted
    if (q.length < 1) return
    if (fetchRun.out) {
      if (activeQuery === q) return
      requestedQuery = q
      activeQuery = ""
      fetchRun.stop()
      return
    }
    if (kept.has(q)) {
      requestedQuery = ""
      activeQuery = q
      land(kept.get(q), "")
      return
    }
    if (clearance && !clearance()) { requestedQuery = q; return }
    requestedQuery = ""
    activeQuery = q
    if (gate && gate.take(1) === 0) {
      land(null, gate.pause === "refused" || gate.pause === "none" ? gate.pause : "other")
      return
    }
    fetchRun.send([Search.searchUrl(q)], Fetch.SEARCH_CAP)
    asked()
  }

  // Asked once more: a lookup of the same words still waiting on the typing
  // pause goes now, and one still out answers. An answer kept for them was
  // no use, so Yahoo is asked.
  function askAgain() {
    debounce.stop()
    kept.delete(wanted)
    if (fetchRun.out && activeQuery === wanted) {
      requestedQuery = ""
      asked()
    } else {
      if (gate) gate.hurry()
      ask()
    }
  }

  function pump() {
    if (active && requestedQuery !== "" && !fetchRun.out) ask()
  }

  // Nothing waits any more. A lookup still out ends unanswered.
  function forget() {
    debounce.stop()
    requestedQuery = ""
    activeQuery = ""
  }

  // And a lookup still out is stopped: its stream ends at once, empty.
  function drop() {
    forget()
    if (fetchRun.out) fetchRun.stop()
  }

  function land(found, why) {
    ended()
    if (activeQuery !== "" && found) kept.set(activeQuery, found)
    if (active && activeQuery !== "" && activeQuery === wanted) answered(activeQuery, found, why)
    if (requestedQuery !== "") {
      requestedQuery = ""
      // Words typed since wait out their own pause.
      if (!debounce.running) ask()
    }
  }

  Timer {
    id: debounce
    interval: 250
    onTriggered: root.ask()
  }

  FetchRun {
    id: fetchRun
    gate: root.gate
    onEnded: function(got) {
      // No answer at all, as from a curl stopped short, is nothing answered.
      var answer = got.length ? got[0] : null
      var found = null
      try { if (answer && answer.kind === "ok") found = Search.parseSearch(JSON.parse(answer.body)) } catch (e) {}
      root.land(found, Search.failure(answer))
    }
  }
}
