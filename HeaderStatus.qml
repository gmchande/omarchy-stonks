import QtQuick
import qs.Commons
import "Cells.js" as Cells
import "Tones.js" as Tones
// The animal, live status, the look, and the help mark. Surfaces own the
// actions; this only draws and signals. The animal is the day's bull or
// bear in both looks, retro's in cells and smooth's drawn, in one slot the
// status words start after, drawn or not, so neither the look nor a flat
// day moves them. While its market rests it sleeps: eyes shut and a dim
// "z" just past the slot, above the words. The height is the slot's in
// both looks, and the look is one small icon in both, so toggling moves
// nothing. None of the three has a tooltip: under the header one covered
// the line naming the stock, and what a click does is on the ? sheet with
// the keys.
Item {
  id: root

  property string statusText: ""
  // The words say a range failed, and its button asks again, as r does.
  property bool offersRetry: false
  property bool retro: false
  // The animal, as the body decides it: `kind` "bull", "bear", or "" (a
  // flat day, or no direction yet), and `chart`, what it reads. A turn of
  // the same chart crossfades in smooth; any other change is at once.
  // `asleep`, its market resting, and `bell`, the clock alone put it to
  // sleep or woke it: then, on the same chart, the eyes close or open over
  // 320 ms; any other change of sleep is at once. `scrubbed`: a scrub has it
  // awake, so the sleep that follows its end is no bell.
  property var animal: ({ kind: "", chart: "", asleep: false, bell: false, scrubbed: false })
  property bool scrubbing: false
  property bool live: false
  // The surface is closing: the look icon's step and the animal's turn stop
  // where they are.
  property bool still: false
  // The key sheet shows, so a click on ? hides it.
  property bool helpShown: false
  property color foreground: Color.foreground
  property color dim: Tones.dim(foreground, Color.background)
  property color upColor: Color.foreground
  property color downColor: Color.urgent
  property color ground: Color.background
  property string fontFamily: Style.font.family

  readonly property string kind: animal ? animal.kind : ""
  // The chart the animal last showed, by which a change is a turn.
  property string shownChart: ""
  // The sleep last shown, and whether a scrub had it awake.
  property bool shownAsleep: false
  property bool shownScrubbed: false
  // How far the eyes have closed, 0 to 1, evenly in time, and whether they
  // last moved open: a wake runs the close's own ease and steps from shut,
  // so smooth eases its lids out on both, and retro steps them, half way at
  // the middle.
  property real closing: 0
  property bool waking: false
  readonly property real moved: waking ? 1 - closing : closing
  readonly property real eased: 1 - Math.pow(1 - moved, 3)
  readonly property real lids: waking ? 1 - eased : eased
  readonly property int steps: moved >= 1 ? 2 : moved >= 0.5 ? 1 : 0
  readonly property int retroLids: waking ? 2 - steps : steps

  signal styleRequested(string style)
  signal helpRequested()
  signal replayRequested()
  signal retryRequested()

  // At rest as a surface opens: the icon on the look, the animal on what
  // it reads.
  function settle() {
    lookIcon.settle()
    show(false)
  }

  // Smooth's layers to the animal: crossfading when it turns on the chart
  // it showed, from wherever a turn under way has them; else at once. Its
  // sleep as `sleep` decides.
  function show(fade) {
    var k = animal ? animal.kind : ""
    shownChart = animal ? animal.chart : ""
    turn.stop()
    turnBull.to = k === "bull" ? 1 : 0
    turnBear.to = k === "bear" ? 1 : 0
    if (fade) turn.start()
    else {
      bull.opacity = turnBull.to
      bear.opacity = turnBear.to
    }
    sleep(fade)
  }

  // The eyes close or open over 320 ms at the bell, `fade` allowing, unless
  // a scrub let go is what puts it to sleep; a move under way runs on
  // through a turn. Any other change is at once.
  function sleep(fade) {
    var asleep = !!(animal && animal.asleep)
    var afterScrub = shownScrubbed
    shownScrubbed = !!(animal && animal.scrubbed)
    if (fade && asleep === shownAsleep) return
    shownAsleep = asleep
    shutting.stop()
    if (fade && animal.bell && !afterScrub) {
      waking = !asleep
      shutting.from = asleep ? 0 : 1
      shutting.to = asleep ? 1 : 0
      shutting.start()
    } else closing = asleep ? 1 : 0
  }

  Component.onCompleted: settle()
  // While still, nothing moves: a change waits for the open's `settle`.
  onAnimalChanged: if (!still) show(animal.chart === shownChart)
  onStillChanged: if (still) {
    if (turn.running) turn.pause()
    if (shutting.running) shutting.pause()
  }

  NumberAnimation { id: shutting; target: root; property: "closing"; duration: 320 }

  implicitHeight: Style.space(28)
  implicitWidth: parent ? parent.width : 0
  height: implicitHeight
  width: parent ? parent.width : implicitWidth

  Item {
    id: slot
    objectName: "animal"
    width: Style.space(40)
    height: Style.space(28)
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter

    PixelSprite {
      objectName: "sprite"
      anchors.fill: parent
      visible: root.retro && root.kind !== ""
      pixels: Cells.spriteFor(root.kind === "bull", root.retroLids)
      color: root.kind === "bull" ? root.upColor : root.downColor
    }

    // Smooth's pair, one layer each, so a turn crossfades between them.
    DrawnAnimal {
      id: bull
      objectName: "drawnBull"
      anchors.fill: parent
      visible: !root.retro && opacity > 0
      bull: true
      color: root.upColor
      lids: root.lids
      wash: Tones.washAlpha(root.upColor, root.upColor, root.ground, 0.16, 1)
    }
    DrawnAnimal {
      id: bear
      objectName: "drawnBear"
      anchors.fill: parent
      visible: !root.retro && opacity > 0
      bull: false
      color: root.downColor
      lids: root.lids
      wash: Tones.washAlpha(root.downColor, root.upColor, root.ground, 0.16, 1)
    }

    ParallelAnimation {
      id: turn
      NumberAnimation { id: turnBull; target: bull; property: "opacity"; duration: 160; easing.type: Easing.OutCubic }
      NumberAnimation { id: turnBear; target: bear; property: "opacity"; duration: 160; easing.type: Easing.OutCubic }
    }

    MouseArea {
      id: animalMouse
      objectName: "animalToggle"
      anchors.fill: parent
      enabled: root.kind !== ""
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: root.replayRequested()
    }
  }

  // Asleep, a small dim "z" over the animal's back, just past its slot:
  // text in smooth, cells in retro, coming in with the eyes' close. It sits
  // at the header's top, never above it: the popup's body starts there and
  // clips what draws past it.
  Text {
    objectName: "sleepZ"
    visible: !root.retro && root.kind !== "" && opacity > 0
    opacity: root.lids
    x: slot.x + slot.width + Style.space(1)
    y: 0
    textFormat: Text.PlainText
    text: "z"
    color: root.dim
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    font.bold: true
  }
  PixelSprite {
    objectName: "sleepCells"
    readonly property int cell: Math.floor(Math.min(slot.width / 20, slot.height / 14))
    visible: root.retro && root.kind !== "" && root.retroLids === 2
    columns: 3
    rows: 5
    width: cell * 3
    height: cell * 5
    x: slot.x + slot.width + Style.space(1)
    y: 0
    pixels: Cells.spritePixels(Cells.SLEEP_Z)
    color: root.dim
  }

  // Live is said by the chart's breathing dot and by these words in the
  // foreground; a mark in front of them would push them over each time it
  // came and went, with every range change and every scrub. A failed
  // range's retry follows them.
  Text {
    id: statusWords
    objectName: "statusText"
    anchors.left: slot.right
    anchors.leftMargin: Style.space(10)
    width: Math.max(0, Math.min(implicitWidth, lookIcon.x - Style.space(12) - x
      - (root.offersRetry ? retry.implicitWidth + Style.space(16) : 0)))
    anchors.verticalCenter: parent.verticalCenter
    textFormat: Text.PlainText
    text: root.statusText.toUpperCase()
    color: root.scrubbing || root.live ? root.foreground : root.dim
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    font.bold: true
    font.letterSpacing: 1
    elide: Text.ElideRight
  }

  ListAction {
    id: retry
    objectName: "retryRange"
    view: root
    visible: root.offersRetry
    anchors.left: statusWords.right
    anchors.leftMargin: Style.space(16)
    anchors.verticalCenter: parent.verticalCenter
    text: "RETRY"
    onActivated: root.retryRequested()
  }

  // The look a click switches to, as s does, about a word tall: the chart
  // already shows the current one. The target is the header's full height,
  // so a click above or below the icon still lands. Like the `?`, it hovers
  // in brighter ink, and takes the pressed fill while the button is down.
  LookIcon {
    id: lookIcon
    objectName: "lookIcon"
    anchors.right: helpMark.left
    anchors.rightMargin: Style.space(14)
    anchors.verticalCenter: parent.verticalCenter
    retro: root.retro
    still: root.still
    color: lookMouse.containsMouse ? root.foreground : root.dim

    Rectangle {
      objectName: "lookFill"
      z: -1
      anchors.centerIn: parent
      width: parent.width + Style.space(12)
      height: parent.height + Style.space(6)
      radius: root.retro ? 0 : Style.cornerRadius
      color: lookMouse.pressed ? Style.pressedFillFor(root.foreground, Color.accent) : "transparent"
    }

    MouseArea {
      id: lookMouse
      objectName: "lookToggle"
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.verticalCenter: parent.verticalCenter
      width: parent.width + Style.space(12)
      height: root.height
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: root.styleRequested(root.retro ? "smooth" : "retro")
    }
  }

  // Inset by its fill's margin, so the pressed fill ends on the header's
  // edge: the popup clips anything past it.
  Text {
    id: helpMark
    objectName: "helpMark"
    anchors.right: parent.right
    anchors.rightMargin: Style.space(6)
    anchors.verticalCenter: parent.verticalCenter
    textFormat: Text.PlainText
    text: "?"
    color: helpMouse.containsMouse ? root.foreground : root.dim
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    font.bold: true
    Behavior on color { ColorAnimation { duration: 160; easing.type: Easing.OutCubic } }
    Rectangle {
      objectName: "helpFill"
      z: -1
      anchors.centerIn: parent
      width: parent.implicitWidth + Style.space(12)
      height: parent.implicitHeight + Style.space(4)
      radius: root.retro ? 0 : Style.cornerRadius
      color: helpMouse.pressed ? Style.pressedFillFor(root.foreground, Color.accent) : "transparent"
    }
    MouseArea {
      id: helpMouse
      objectName: "helpToggle"
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.verticalCenter: parent.verticalCenter
      width: Math.max(Style.space(24), parent.width + Style.space(12))
      height: root.height
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: root.helpRequested()
    }
  }
}
