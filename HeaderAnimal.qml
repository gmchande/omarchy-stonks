import QtQuick
import qs.Commons
import "Cells.js" as Cells
import "Motion.js" as Motion

// The header's animal: the bull or the bear, turning as the day does, its
// eyes shut while its market rests, greeting you at each open and then
// fidgeting ever more rarely. A click replays the day.
Item {
  id: root
  objectName: "animal"

  // `kind` is "bull", "bear", "plain" (no move known yet: the bull in plain
  // ink) or "" (a flat day), and `chart` what it reads: a turn on the same
  // chart crossfades in smooth, any other change is at once, but another
  // stock (`stock`) crosses over on the switch's beat (`crossing`). `asleep`
  // is its market resting; `bell`, that the clock alone changed that, so the
  // eyes close or open over 320 ms;
  // `scrubbed`, that a scrub has it awake, so the sleep after it is no bell.
  property var animal: ({ kind: "", chart: "", stock: "", asleep: false, bell: false, scrubbed: false })
  // How far another stock's animal has come, 0 to 1 (`ChartMotion.arrival`):
  // smooth fades the cells that change, retro wipes them in a column at a
  // time from the left. Never a turn, which says the stock's own day turned,
  // nor the bell's eyes: it arrives as it is.
  property real crossing: 1
  property Look look
  // While the panel or window shows (`seen`), the animal greets you at each
  // open and then fidgets ever more rarely (`Cells.fidgetMove`); asleep, its
  // eyes stay shut. Only its own cells change. A close holds its pose through
  // the fade; with the shell's animations off, or no animal, it sits still.
  property bool seen: false
  // Closing: the turn and the eyes stop where they are.
  property bool still: false

  signal replayRequested()
  // The market's bell rang, the eyes closing or (`woke`) opening: what else
  // changes with the bell keeps to their beat (`Header`).
  signal rang(bool woke)

  readonly property string kind: animal ? animal.kind : ""
  // The chart the animal last showed: a change on it is a turn.
  property string shownChart: ""
  property bool shownAsleep: false
  property bool shownScrubbed: false
  // How far the eyes have closed, 0 to 1, evenly in time. A wake steps from
  // shut, so the lids are half way at the middle of either move (`lids`: 0
  // open, 1 half, 2 shut).
  property real closing: 0
  property bool waking: false
  readonly property real moved: waking ? 1 - closing : closing
  readonly property int steps: moved >= 1 ? 2 : moved >= 0.5 ? 1 : 0
  readonly property int lids: waking ? 2 - steps : steps

  // Moves begun since the open; the steps of the one playing or next, and
  // which is drawn, -1 being still.
  property int fidgetMoves: 0
  property var fidgetSteps: []
  property int fidgetStep: -1
  readonly property bool fidgeting: seen && kind !== "" && !Style.reduceMotion
  readonly property var fidget: fidgetStep >= 0 ? fidgetSteps[fidgetStep] : ({})
  // Plain values, so a step that changes neither draws nothing.
  readonly property bool pricked: !!fidget.pricked
  readonly property int drawnLids: fidget.blink ? 2 : lids
  function fidgetAnew() {
    fidgetMoves = 0
    fidgetNext()
  }
  // Still, until the next move.
  function fidgetNext() {
    var move = Cells.fidgetMove(fidgetMoves++)
    fidgetStep = -1
    fidgetSteps = move.steps
    fidgetClock.interval = move.wait
    if (fidgeting) fidgetClock.restart()
    else fidgetClock.stop()
  }
  // Each open starts with the greeting, running or not.
  onSeenChanged: if (seen) fidgetAnew()
  onFidgetingChanged: {
    if (seen) fidgetAnew()
    else fidgetClock.stop()
  }
  Timer {
    id: fidgetClock
    onTriggered: {
      if (root.fidgetStep + 1 < root.fidgetSteps.length) {
        root.fidgetStep++
        interval = root.fidgetSteps[root.fidgetStep].ms
        restart()
      } else root.fidgetNext()
    }
  }

  function settle() {
    crossLeaving = []
    crossComing = []
    crossStaying = []
    show(false)
    crossFromZ = hasZ
  }

  function show(fade) {
    var k = animal ? animal.kind : ""
    shownChart = animal ? animal.chart : ""
    shownKind = k
    shownStock = animal ? animal.stock : ""
    turn.stop()
    turnBull.to = k === "bull" || k === "plain" ? 1 : 0
    turnBear.to = k === "bear" ? 1 : 0
    if (fade && !look.retro) turn.start()
    else {
      bull.opacity = turnBull.to
      bear.opacity = turnBear.to
    }
    sleep(fade)
  }

  // Asleep after a scrub is let go is at once, never the bell's close; a move
  // under way runs on through a turn.
  function sleep(fade) {
    var asleep = !!(animal && animal.asleep)
    var afterScrub = shownScrubbed
    shownScrubbed = !!(animal && animal.scrubbed)
    if (fade && asleep === shownAsleep) return
    shownAsleep = asleep
    shutting.stop()
    // The bell owns the eyes: eyes Fidget's blink already shut fall asleep
    // at once, and a fidget under way stops and rests. A rest runs on: a
    // fidget's first blink comes 340 ms in, after the bell's 320 ms.
    var rung = fade && animal.bell && !afterScrub
    if (rung && !(asleep && fidget.blink)) {
      waking = !asleep
      shutting.from = asleep ? 0 : 1
      shutting.to = asleep ? 1 : 0
      shutting.start()
    } else closing = asleep ? 1 : 0
    if (rung && fidgetStep >= 0) fidgetNext()
    if (rung) rang(!asleep)
  }

  // While still, nothing moves: a change waits for the open's `settle`. The
  // surface works the animal out a piece at a time as a stock arrives, its
  // kind before its chart, so it is taken once those land together: a new
  // kind on the old chart would read as a turn.
  onAnimalChanged: if (!still) Qt.callLater(take)
  function take() {
    if (still) return
    var had = shownChart !== ""
    var before = drawn(shownKind)
    var wasZ = shownKind !== "" && shownAsleep
    var switched = had && !!animal && (animal.stock !== shownStock || animal.chart !== shownChart)
    show(!switched && !!animal && animal.chart === shownChart)
    if (switched) {
      crossFromZ = wasZ
      cross(before, drawn(kind))
    }
  }
  property string shownStock: ""
  property string shownKind: ""
  property bool crossFromZ: false
  readonly property bool hasZ: kind !== "" && shownAsleep
  // Sleep Z crosses in lockstep with the animal on a switch, stays steady when
  // both sides match, and follows the lids on a market bell.
  readonly property real sleepZ: crossing < 1
    ? (crossFromZ === hasZ ? (hasZ ? 1 : 0)
      : look.retro ? Math.round((hasZ ? crossing : 1 - crossing) * 2) / 2
      : (hasZ ? crossing : 1 - crossing))
    : (kind === "" ? 0 : (look.retro ? lids / 2 : closing))

  // The cells of `k` on show, in their ink.
  function drawn(k) {
    if (k === "") return { pixels: [], color: look.upColor }
    var up = k !== "bear"
    return { pixels: Cells.spriteFor(up, drawnLids, pricked), color: k === "plain" ? look.dim : up ? look.upColor : look.downColor }
  }

  // Smooth keeps the cells both share in one ink and fades the rest; retro
  // wipes the whole sprite.
  property var crossLeaving: []
  property var crossComing: []
  property var crossStaying: []
  property color leavingColor: look.upColor
  property color comingColor: look.upColor
  function cross(from, to) {
    var key = function(p) { return p.x + "," + p.y }
    var same = !look.retro && Qt.colorEqual(from.color, to.color)
    var had = {}
    from.pixels.forEach(function(p) { had[key(p)] = true })
    var has = {}
    to.pixels.forEach(function(p) { has[key(p)] = true })
    crossStaying = same ? to.pixels.filter(function(p) { return had[key(p)] }) : []
    crossLeaving = same ? from.pixels.filter(function(p) { return !has[key(p)] }) : from.pixels
    crossComing = same ? to.pixels.filter(function(p) { return !had[key(p)] }) : to.pixels
    leavingColor = from.color
    comingColor = to.color
  }
  readonly property bool crossShown: crossing < 1 && (crossLeaving.length > 0 || crossComing.length > 0)
  onStillChanged: if (still) {
    if (turn.running) turn.pause()
    if (shutting.running) shutting.pause()
  }

  NumberAnimation { id: shutting; target: root; property: "closing"; duration: Motion.duration(Style, 320) }

  width: Style.space(40)
  height: Style.space(28)

  // One layer each, so smooth's turn crossfades between them.
  Item {
    anchors.fill: parent
    visible: !root.crossShown
    PixelSprite {
      id: bull
      anchors.fill: parent
      visible: opacity > 0
      pixels: Cells.spriteFor(true, root.drawnLids, root.pricked)
      color: root.kind === "plain" ? root.look.dim : root.look.upColor
    }
    PixelSprite {
      id: bear
      anchors.fill: parent
      visible: opacity > 0
      pixels: Cells.spriteFor(false, root.drawnLids, root.pricked)
      color: root.look.downColor
    }
  }

  // Retro's wipe in whole columns of the sprite's 20.
  readonly property real crossEdge: root.look.retro ? Math.floor(root.crossing * 20) / 20 * width : width
  Item {
    visible: root.crossShown
    anchors.fill: parent
    PixelSprite {
      anchors.fill: parent
      pixels: root.crossStaying
      color: root.comingColor
    }
    Item {
      x: root.look.retro ? root.crossEdge : 0
      width: parent.width - x
      height: parent.height
      clip: true
      PixelSprite {
        x: -parent.x
        width: root.width
        height: root.height
        opacity: root.look.retro ? 1 : 1 - root.crossing
        pixels: root.crossLeaving
        color: root.leavingColor
      }
    }
    Item {
      width: root.crossEdge
      height: parent.height
      clip: true
      PixelSprite {
        width: root.width
        height: root.height
        opacity: root.look.retro ? 1 : root.crossing
        pixels: root.crossComing
        color: root.comingColor
      }
    }
  }

  ParallelAnimation {
    id: turn
    NumberAnimation { id: turnBull; target: bull; property: "opacity"; duration: Motion.duration(Style, 160); easing.type: Easing.Bezier; easing.bezierCurve: Motion.curve(Style) }
    NumberAnimation { id: turnBear; target: bear; property: "opacity"; duration: Motion.duration(Style, 160); easing.type: Easing.Bezier; easing.bezierCurve: Motion.curve(Style) }
  }

  // The plain bull has no move to replay.
  MouseArea {
    anchors.fill: parent
    enabled: root.kind === "bull" || root.kind === "bear"
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: root.replayRequested()
  }
}
