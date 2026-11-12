.pragma library
// One host's gate, which every request to that host asks first: a budget, and
// a pause when the host stops answering or says no.
//
// Normal use never reaches the budget's edge. A run of quotes (`bulk`) leaves
// `reserve` for single requests, so a long list never starves a history, a
// search or a P/E. No answer at all pauses 2 s, doubling to 60, since nothing
// reached the server; a refusal (429, 503) pauses for Retry-After, else a
// minute, doubling with each refusal until the host answers again, and at
// most 30 minutes, so a hostile Retry-After can't silence Stonks for days.
// Each pause varies by ±20%, or by up to +20% for the host's own
// Retry-After, so installs don't all come back at once. After a pause one
// request goes alone, and only its answer reopens the host.
//
// A gate is { left, filledAt, pause, pausedUntil, silences, refusals,
// loneOut, warned, pauses }: the requests left in its budget and when that
// was last filled; why the host is paused ("" while it answers, "none" or
// "refused") and until when; how many times in a row no answer came, and
// how many refusals came since the host last answered, which set the next
// pause's length; whether the lone request after a pause is out; whether
// the budget has held a request back yet; and how many pauses have begun.
// Every rule here returns a new gate. `limits` is { capacity, perMinute,
// reserve }, and every time a second on the wall clock.

function openGate(capacity) {
  return { left: capacity, filledAt: 0, pause: "", pausedUntil: 0, silences: 0, refusals: 0, loneOut: false, warned: false, pauses: 0 }
}

function refilledGate(gate, limits, now) {
  var left = gate.filledAt > 0 ? Math.min(limits.capacity, gate.left + Math.max(0, now - gate.filledAt) * limits.perMinute / 60) : gate.left
  return Object.assign({}, gate, { left: left, filledAt: now })
}

// How many of `count` requests may go now: one alone once a pause has run
// out, and none while it lasts. `heldBack` is how many the budget kept back
// the first time it keeps any, for the gate to say so once.
function takenFromGate(gate, limits, count, bulk, now) {
  if (count <= 0) return { gate: gate, granted: 0, heldBack: 0 }
  var filled = refilledGate(gate, limits, now)
  if (filled.pause !== "") {
    if (filled.loneOut || now < filled.pausedUntil) return { gate: filled, granted: 0, heldBack: 0 }
    return { gate: Object.assign({}, filled, { loneOut: true, left: Math.max(0, filled.left - 1) }), granted: 1, heldBack: 0 }
  }
  var granted = Math.max(0, Math.min(count, Math.floor(filled.left - (bulk ? limits.reserve : 0))))
  var first = granted < count && !filled.warned
  return {
    gate: Object.assign({}, filled, { left: filled.left - granted, warned: filled.warned || first }),
    granted: granted,
    heldBack: first ? count - granted : 0
  }
}

// For a request that can wait, such as a chart fetched ahead of a click:
// only while half the budget is left, so quotes and the charts on show always
// find it.
function gateHasSpare(gate, limits) {
  return gate.pause === "" && gate.left >= limits.capacity / 2
}

// The gate once a run's answers are in. `kinds` are as `Fetch.answerKind`
// names them, and `sentUnder` is the gate's `pauses` when the run was sent:
// answers to a run sent before the latest pause can only refuse, and whatever
// was let through before a pause, the lone request included, no longer speaks
// for the host. `spread` is a number from 0 to 1, which varies the pause.
// `reopened` says the host answers again.
function gateAfterAnswers(gate, kinds, retryAfter, sentUnder, now, spread) {
  var current = sentUnder === gate.pauses
  var heard = current ? Object.assign({}, gate, { loneOut: false }) : gate
  if (kinds.indexOf("refused") >= 0) {
    // The rest of the run that began this pause adds no refusal.
    if (!current && heard.pause === "refused") return { gate: heard, reopened: false }
    var refusals = heard.refusals + 1
    var asked = Math.min(retryAfter > 0 ? retryAfter : 60 * Math.pow(2, refusals - 1), 30 * 60)
    // The host's own wait is never cut short.
    var varied = asked * (retryAfter > 0 ? 1 + 0.2 * spread : 0.8 + 0.4 * spread)
    return { gate: pausedGate(Object.assign({}, heard, { refusals: refusals, silences: 0 }), "refused", varied, now), reopened: false }
  }
  if (!current || kinds.length === 0) return { gate: heard, reopened: false }
  if (kinds.some(function(k) { return k !== "none" }))
    return { gate: Object.assign({}, heard, { pause: "", silences: 0, refusals: 0 }), reopened: heard.pause !== "" }
  var silences = heard.silences + 1
  var waited = Math.min(2 * Math.pow(2, silences - 1), 60) * (0.8 + 0.4 * spread)
  return { gate: pausedGate(Object.assign({}, heard, { silences: silences }), "none", waited, now), reopened: false }
}

function pausedGate(gate, kind, seconds, now) {
  return Object.assign({}, gate, {
    pause: kind,
    pauses: gate.pauses + 1,
    loneOut: false,
    pausedUntil: now + Math.max(1, Math.round(seconds))
  })
}

// By r or RETRY: the network may be back, so a pause for no answer ends now.
// A refusal's holds: the host asked for fewer requests.
function gateRetriedNow(gate, now) {
  return gate.pause === "none" && !gate.loneOut && gate.pausedUntil > now ? Object.assign({}, gate, { pausedUntil: now }) : gate
}
