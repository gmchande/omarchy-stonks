import QtQuick
// One host's gate, which every request to that host asks first: a budget, and
// a pause when the host stops answering or says no.
//
// Normal use never reaches the budget's edge, and the first time it holds a
// request back it says so. A run of quotes (`bulk`) leaves `reserve` for single
// requests, so a long list never starves a history, a search or a P/E. No
// answer at all pauses 2 s, doubling to 60, since nothing reached the server;
// a refusal (429, 503) pauses for Retry-After, else a minute, doubling, and at
// most 30 minutes, so a hostile Retry-After can't silence Stonks for days. Each
// pause varies by ±20%, so installs don't all come back at once. After a pause
// one request goes alone, and only its answer reopens the host: an answer to a
// request let through before the latest pause (`ticket`) says nothing of it.
Item {
  id: root

  property string host: ""
  // The service: its wall clock (`wallSecond`), read at each call, never its
  // `now`, which trails the wall between ticks while nothing is open.
  property var clock: null
  property int capacity: 80
  property real perMinute: 40
  property int reserve: 10

  property real tokens: capacity
  property int filledAt: 0
  // Why the host is paused: "" while it answers, "none" or "refused".
  property string pause: ""
  property int pausedUntil: 0
  // Pauses of this kind in a row, which set the next one's length.
  property int strikes: 0
  // The lone request after a pause is out.
  property bool probing: false
  property bool warned: false
  // Moves on as each pause begins.
  property int ticket: 0

  readonly property bool paused: pause !== ""

  signal reopened()

  function now() {
    return clock ? clock.wallSecond() : 0
  }

  function refill() {
    if (filledAt > 0) root.tokens = Math.min(capacity, tokens + Math.max(0, now() - filledAt) * perMinute / 60)
    root.filledAt = now()
  }

  // One alone once a pause has run out; none while it lasts.
  function take(count, bulk) {
    if (count <= 0) return 0
    refill()
    if (paused) {
      if (probing || now() < pausedUntil) return 0
      root.probing = true
      root.tokens = Math.max(0, tokens - 1)
      return 1
    }
    var granted = Math.max(0, Math.min(count, Math.floor(tokens - (bulk ? reserve : 0))))
    if (granted < count && !warned) {
      root.warned = true
      console.warn("stonks: " + host + "'s budget held back " + (count - granted) + " requests")
    }
    root.tokens = tokens - granted
    return granted
  }

  // For a request that can wait, such as a chart fetched ahead of a click:
  // only while half the budget is left, so quotes and the charts on show always
  // find it. Takes nothing.
  function spare() {
    refill()
    return !paused && tokens >= capacity / 2
  }

  // `kinds` as `Fetch.answerKind` names them. Answers on an older ticket can
  // only refuse.
  function report(kinds, retryAfter, ticket) {
    var current = ticket === root.ticket
    if (current) root.probing = false
    if (kinds.indexOf("refused") >= 0) {
      // The rest of the run that began this pause adds no strike.
      if (!current && pause === "refused") return
      root.strikes = pause === "refused" ? strikes + 1 : 1
      begin("refused", Math.min(retryAfter > 0 ? retryAfter : 60 * Math.pow(2, strikes - 1), 30 * 60))
    } else if (!current) {
      return
    } else if (kinds.some(function(k) { return k !== "none" })) {
      var was = paused
      root.pause = ""
      root.strikes = 0
      if (was) root.reopened()
    } else if (kinds.length > 0) {
      root.strikes = pause === "none" ? strikes + 1 : 1
      begin("none", Math.min(2 * Math.pow(2, strikes - 1), 60))
    }
  }

  // By r or RETRY: the network may be back, so a pause for no answer ends now.
  // A refusal's holds: the host asked for fewer requests.
  function hurry() {
    if (pause === "none" && !probing && pausedUntil > now()) root.pausedUntil = now()
  }

  // Whatever was let through before it, a probe still out included, no longer
  // speaks for the host.
  function begin(kind, seconds) {
    root.pause = kind
    root.ticket = root.ticket + 1
    root.probing = false
    root.pausedUntil = now() + Math.max(1, Math.round(seconds * (0.8 + 0.4 * Math.random())))
  }
}
