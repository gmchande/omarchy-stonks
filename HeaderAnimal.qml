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
  // chart crossfades in smooth, any other change is at once. `asleep` is its
  // market resting; `bell`, that the clock alone changed that, so the eyes
  // close or open over 320 ms;
  // `scrubbed`, that a scrub has it awake, so the sleep after it is no bell.
  property var animal: ({ kind: "", chart: "", asleep: false, bell: false, scrubbed: false })
  property Look look
  // While the panel or window shows (`seen`), the animal greets you at each
  // open and then fidgets ever more rarely (`Cells.fidgetMove`); asleep, its
  // eyes stay shut. Only its own cells change. A close holds its pose through
  // the fade; with the shell's animations off, or no animal, it sits still.
  property bool seen: false
  // Closing: the turn and the eyes stop where they are.
  property bool still: false

  signal replayRequested()

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
    show(false)
  }

  function show(fade) {
    var k = animal ? animal.kind : ""
    shownChart = animal ? animal.chart : ""
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
  }

  // While still, nothing moves: a change waits for the open's `settle`.
  onAnimalChanged: if (!still) show(animal.chart === shownChart)
  onStillChanged: if (still) {
    if (turn.running) turn.pause()
    if (shutting.running) shutting.pause()
  }

  NumberAnimation { id: shutting; target: root; property: "closing"; duration: Motion.duration(Style, 320) }

  width: Style.space(40)
  height: Style.space(28)

  // One layer each, so smooth's turn crossfades between them.
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
