import QtQuick
import "Fetch.js" as Fetch
import "Search.js" as Search
// Yahoo's lookup for the words in the search field: one request at a time,
// a quarter second after the typing stops. Words typed while a lookup is
// out wait behind it, and an answer counts only for the words still wanted.
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

  // A lookup is out for the words wanted.
  signal asked()
  // A lookup ended, whatever it was for.
  signal ended()
  // The answer for the words still wanted. A body of "" is no answer,
  // failed for `why`: "none" when nothing answered, "refused", "missing"
  // when Yahoo called the question wrong (as it does an emoji), or "other"
  // (`Search.failure`).
  signal answered(string query, string body, string why)

  function askSoon() { debounce.restart() }

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
    if (clearance && !clearance()) { requestedQuery = q; return }
    requestedQuery = ""
    activeQuery = q
    if (gate && gate.take(1) === 0) {
      land("", gate.pause === "refused" || gate.pause === "none" ? gate.pause : "other")
      return
    }
    fetchRun.send([Search.searchUrl(q)], Fetch.SEARCH_CAP)
    asked()
  }

  // Asked once more: a lookup of the same words still waiting on the typing
  // pause goes now, and one still out answers.
  function askAgain() {
    debounce.stop()
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

  function land(body, why) {
    ended()
    if (active && activeQuery !== "" && activeQuery === wanted) answered(activeQuery, body, why)
    if (requestedQuery !== "") {
      requestedQuery = ""
      ask()
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
      root.land(answer && answer.kind === "ok" ? answer.body : "", Search.failure(answer))
    }
  }
}
