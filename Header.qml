pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Cells.js" as Cells
import "Motion.js" as Motion
// The header: the animal, the stock's name over its status, the speaker, the
// camera, the look and the ?, with a rule under them, as a shell panel's hero
// has. The words start after the animal's slot, drawn or not, so neither the
// look nor a flat day moves them. Each icon's tip hangs under it, inside the
// card: a panel hangs from a top bar, with no room above.
Item {
  id: root

  // The words, then up to two shorter forms of them (`StonksBody.headerForms`):
  // the first that fits shows.
  property var statusForms: []
  // Its line stays while there is none, so a name arriving moves nothing.
  property string title: ""
  // False where large text on a short screen would leave fewer than three rows
  // beside the chart (`StonksBody.headerTitled`): the words stand alone, and the
  // name goes on the hero's line.
  property bool titled: true
  // A range failed; the button asks again, as r does.
  property bool offersRetry: false
  property Look look
  property bool soundsOn: false
  // The animal's day and rest, and whether a surface shows it (`HeaderAnimal`).
  property var animal: ({ kind: "", chart: "", asleep: false, bell: false, scrubbed: false })
  property bool seen: false
  property bool scrubbing: false
  property bool live: false
  // In full ink, standing out without colour, since red says down.
  property bool trouble: false
  // Closing: the look icon's step and the animal's turn stop where they are.
  property bool still: false
  property bool helpShown: false
  // Lit from a screenshot until the surface closes.
  property bool cameraLit: false
  // Another stock's name and status change at once, where they stand; the
  // animal crosses on the switch's beat (`ChartMotion.crossing`), and a bell's
  // words wait for a stock switch (`ChartMotion.arrival`).
  property real arrival: 1
  property real crossing: 1

  signal styleRequested(string style)
  signal soundsRequested()
  signal screenshotRequested()
  signal helpRequested()
  signal replayRequested()
  signal retryRequested()
  // The market's bell rang (`HeaderAnimal.rang`).
  signal rang(bool woke)

  function settle() {
    lookIcon.settle()
    slot.settle()
    soundAnim.stop()
    soundStep = soundsOn ? 1 : 0
    lensAnim.stop()
    lensBloom = cameraLit ? 1 : 0
    if (wordSwap.running) endSwap()
  }

  // Speaker arcs emerge outward on unmute and cross to × on mute; camera
  // lens blooms when a screenshot lands.
  property real soundStep: soundsOn ? 1 : 0
  onSoundsOnChanged: {
    var target = soundsOn ? 1 : 0
    if (seen && !still && Motion.duration(Style, 160) > 0) {
      soundAnim.to = target
      soundAnim.restart()
    } else {
      soundAnim.stop()
      soundStep = target
    }
  }
  NumberAnimation { id: soundAnim; target: root; property: "soundStep"; duration: Motion.duration(Style, 160); easing.type: Easing.Linear }

  property real lensBloom: cameraLit ? 1 : 0
  onCameraLitChanged: {
    if (cameraLit && seen && !still && Motion.duration(Style, 160) > 0) {
      lensAnim.stop()
      lensBloom = 0
      lensAnim.start()
    } else {
      lensAnim.stop()
      lensBloom = cameraLit ? 1 : 0
    }
  }
  NumberAnimation { id: lensAnim; target: root; property: "lensBloom"; to: 1; duration: Motion.duration(Style, 160); easing.type: Easing.OutCubic }
  onLensBloomChanged: if (lensAnim.running && lensBloom > 0.985) {
    lensAnim.stop()
    lensBloom = 1
  }
  Connections {
    target: Style
    ignoreUnknownSignals: true
    function onReduceMotionChanged() {
      if (!Style.reduceMotion) return
      soundAnim.stop()
      root.soundStep = root.soundsOn ? 1 : 0
      lensAnim.stop()
      root.lensBloom = root.cameraLit ? 1 : 0
    }
  }

  Component.onCompleted: settle()

  // What makes an icon a button: its fill on hover, press or selection, a
  // target as tall as the header's two lines, and its tip 3 px under the
  // target, centred, but never past the header's right edge. Under the icon
  // it is put in.
  component HeaderPress: Item {
    id: press
    property string tip: ""
    property bool selected: false
    // The fill's height past the icon's, and the target's least width.
    property real fillPad: Style.space(6)
    property real leastWidth: 0
    readonly property alias containsMouse: area.containsMouse
    signal clicked()
    readonly property Item icon: parent
    z: -1
    anchors.fill: parent

    Rectangle {
      anchors.centerIn: parent
      width: parent.width + Style.space(12)
      height: parent.height + press.fillPad
      radius: root.look.retro ? 0 : Style.cornerRadius
      color: area.pressed ? Style.pressedFillFor(root.look.foreground, Commons.Color.accent)
        : press.selected ? Style.selectedFillFor(root.look.foreground, Commons.Color.accent)
        : area.containsMouse ? Style.hoverFillFor(root.look.foreground, Commons.Color.accent) : "transparent"
      Behavior on color { ColorAnimation { duration: Motion.duration(Style, 120) } }
    }

    MouseArea {
      id: area
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.verticalCenter: parent.verticalCenter
      width: Math.max(press.leastWidth, parent.width + Style.space(12))
      height: root.contentHeight
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: press.clicked()

      PanelToolTip {
        visible: area.containsMouse
        text: press.tip
        fontFamily: root.look.fontFamily
        y: parent.height + 3
        x: Math.min((parent.width - implicitWidth) / 2, press.icon.parent.width - press.icon.x - parent.x - implicitWidth)
      }
    }
  }

  // The rule sits a band's gap short of a group's under the two lines, so with
  // the group's gap the body leaves after the header, the gap below it matches
  // the one above. The icons centre on the two lines, not on the rule.
  readonly property int twoLines: Math.max(Style.space(28),
    titleText.implicitHeight + Style.space(2) + statusWords.implicitHeight)
  readonly property int ruleGap: Style.space(14)
  // The height with the title, whether or not it shows, and without it.
  readonly property int titledHeight: twoLines + ruleGap * 2 - Style.space(8) + 1
  readonly property int bareHeight: Style.space(28)
  readonly property int contentHeight: titled ? twoLines : bareHeight
  readonly property int centerOffset: Math.round((contentHeight - height) / 2)
  implicitHeight: titled ? titledHeight : bareHeight
  implicitWidth: parent ? parent.width : 0
  height: implicitHeight
  width: parent ? parent.width : implicitWidth


  HeaderAnimal {
    id: slot
    animal: root.animal
    look: root.look
    crossing: root.crossing
    seen: root.seen
    still: root.still
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
    anchors.verticalCenterOffset: root.centerOffset
    onReplayRequested: root.replayRequested()
    onRang: function(woke) { root.rang(woke) }
  }

  // At the header's top, never above: the panel's body starts there and clips
  // what draws past it. It comes and goes with the eyes: in smooth it fades
  // and drifts its 3 px down as they open, in retro it steps with the lids.
  PixelSprite {
    readonly property int cell: Math.floor(Math.min(slot.width / 20, slot.height / 14))
    readonly property real shut: slot.sleepZ
    visible: shut > 0
    opacity: shut
    columns: 3
    rows: 5
    width: cell * 3
    height: cell * 5
    x: slot.x + slot.width + Style.space(1)
    y: root.look.retro ? 0 : Math.round(Style.space(3) * (1 - shut))
    pixels: Cells.spritePixels(Cells.SLEEP_Z)
    color: root.look.dim
  }

  // Live shows as the chart's breathing dot and these words in full ink: a
  // mark before them would push them over at every range change and scrub.
  // They start twice as far from the z as the bull is, so it reads as the
  // animal's, and stop as much sooner. The first form that fits shows, letters
  // spaced, else closed up, so beside the icons Tokyo's "Constitution Memorial
  // Day" keeps its name at the everyday text size.
  readonly property real wordsRoom: Math.max(0, soundIcon.x - Style.space(8) - statusWords.x
    - (root.offersRetry ? retry.implicitWidth + Style.space(16) : 0))
  readonly property var measured: [form0, form1, form2].slice(0, statusForms.length)
  // Where none fits, the last, closed up and cut.
  readonly property var fit: {
    for (var i = 0; i < measured.length; i++) {
      if (measured[i].spaced <= wordsRoom) return { form: i, tight: false }
      if (measured[i].tight <= wordsRoom) return { form: i, tight: true }
    }
    return { form: Math.max(0, measured.length - 1), tight: true }
  }
  // Measured, never shown.
  component FormWidths: Item {
    property string words: ""
    property string family: ""
    readonly property real spaced: spacedWords.implicitWidth
    readonly property real tight: tightWords.implicitWidth
    visible: false
    Text {
      id: spacedWords
      textFormat: Text.PlainText
      text: parent.words
      font.family: parent.family
      font.pixelSize: Style.font.caption
      font.bold: true
      font.letterSpacing: 1
    }
    Text {
      id: tightWords
      textFormat: Text.PlainText
      text: parent.words
      font.family: parent.family
      font.pixelSize: Style.font.caption
      font.bold: true
    }
  }
  FormWidths { id: form0; words: String(root.statusForms[0] || "").toUpperCase(); family: root.look.fontFamily }
  FormWidths { id: form1; words: String(root.statusForms[1] || "").toUpperCase(); family: root.look.fontFamily }
  FormWidths { id: form2; words: String(root.statusForms[2] || "").toUpperCase(); family: root.look.fontFamily }
  Text {
    id: titleText
    visible: root.titled
    anchors.left: slot.right
    anchors.leftMargin: Style.space(14)
    y: Math.round((root.contentHeight - implicitHeight - Style.space(2) - statusWords.implicitHeight) / 2)
    width: Math.min(implicitWidth, Math.max(0, soundIcon.x - Style.space(8) - x))
    textFormat: Text.PlainText
    text: root.title
    color: root.look.foreground
    font.family: root.look.fontFamily
    font.pixelSize: Style.font.title
    font.bold: true
    elide: Text.ElideRight
  }

  // The rule as the footer's, the shell's own separator.
  PanelSeparator {
    visible: root.titled
    y: root.contentHeight + root.ruleGap
    width: root.width
    foreground: root.look.foreground
    strength: 0.08
  }

  // The words as they stand now, and as shown. At the bell, and as trouble
  // comes or goes, the old fade out and the new in where they stood, as
  // Omarchy's own status words swap (`phraseSwap`); any other change, as a
  // scrub's or the clock's, is at once.
  readonly property var wordsNow: ({ text: measured.length ? measured[fit.form].words : "", tight: fit.tight,
    bright: scrubbing || live || trouble })
  property var wordsShown: wordsNow
  property bool troubleShown: false
  property real wordsIn: 1
  onWordsNowChanged: Qt.callLater(takeWords)
  function takeWords() {
    var was = wordsShown
    var now = wordsNow
    var trouble = root.trouble
    var swap = seen && arrival >= 1 && was.text !== "" && now.text !== was.text
      && ((animal.bell && !animal.scrubbed) || trouble !== troubleShown)
    troubleShown = trouble
    if (swap) {
      wordSwap.restart()
      return
    }
    // Any other change shows at once, over a swap under way too, and
    // another stock's ends the swap, as its words arrive on their own beat.
    if (wordSwap.running && arrival < 1) endSwap()
    wordsShown = now
  }
  SequentialAnimation {
    id: wordSwap
    NumberAnimation { target: root; property: "wordsIn"; to: 0; duration: Motion.duration(Style, 120); easing.type: Easing.OutCubic }
    ScriptAction { script: root.wordsShown = root.wordsNow }
    NumberAnimation { target: root; property: "wordsIn"; to: 1; duration: Motion.duration(Style, 200); easing.type: Easing.OutCubic }
  }
  function endSwap() {
    wordSwap.stop()
    wordsShown = wordsNow
    wordsIn = 1
  }
  // Hidden while open, nothing moves; closing, the words hold through the
  // fade, and land at the next open (`settle`). Judged a turn later, once
  // a close has said so too.
  onSeenChanged: if (!seen) Qt.callLater(function() {
    if (root.seen || root.still) return
    if (wordSwap.running) root.endSwap()
    if (soundAnim.running) { soundAnim.stop(); root.soundStep = root.soundsOn ? 1 : 0 }
    if (lensAnim.running) { lensAnim.stop(); root.lensBloom = root.cameraLit ? 1 : 0 }
  })
  onStillChanged: if (still) {
    if (wordSwap.running) wordSwap.pause()
    if (soundAnim.running) soundAnim.pause()
    if (lensAnim.running) lensAnim.pause()
  }

  Text {
    id: statusWords
    anchors.left: slot.right
    opacity: root.wordsIn
    anchors.leftMargin: Style.space(14)
    width: Math.min(implicitWidth, root.wordsRoom)
    y: root.titled ? titleText.y + titleText.implicitHeight + Style.space(2) : Math.round((root.contentHeight - implicitHeight) / 2)
    textFormat: Text.PlainText
    text: root.wordsShown.text
    color: root.wordsShown.bright ? root.look.foreground : root.look.dim
    font.family: root.look.fontFamily
    font.pixelSize: Style.font.caption
    font.bold: true
    font.letterSpacing: root.wordsShown.tight ? 0 : 1
    elide: Text.ElideRight
  }

  ListAction {
    id: retry
    look: root.look
    visible: root.offersRetry
    opacity: root.wordsIn
    anchors.left: statusWords.right
    anchors.leftMargin: Style.space(16)
    anchors.verticalCenter: statusWords.verticalCenter
    text: "RETRY"
    onActivated: root.retryRequested()
  }

  // The speaker, the camera and the look icon share a grid whose cell grows
  // with the text (`Cells.iconCell`), so they keep their weight beside the
  // words at every size.
  readonly property int cell: Cells.iconCell(Style.fontScale)

  // One width on or off, so the toggle moves nothing. Each icon's target is the
  // height of the header's two lines.
  GridIcon {
    id: soundIcon
    readonly property bool on: root.soundsOn
    anchors.right: camera.left
    anchors.rightMargin: Style.space(14)
    anchors.verticalCenter: parent.verticalCenter
    anchors.verticalCenterOffset: root.centerOffset
    cell: root.cell
    shape: Cells.soundShape(root.soundStep)
    color: soundPress.containsMouse ? root.look.foreground : root.look.dim
    Behavior on color { ColorAnimation { duration: Motion.duration(Style, 120) } }

    HeaderPress {
      id: soundPress
      objectName: "soundToggle"
      tip: root.soundsOn ? "Turn sounds off" : "Turn sounds on"
      onClicked: root.soundsRequested()
    }
  }

  GridIcon {
    id: camera
    objectName: "camera"
    readonly property bool lit: root.cameraLit
    anchors.right: lookIcon.left
    anchors.rightMargin: Style.space(14)
    anchors.verticalCenter: parent.verticalCenter
    anchors.verticalCenterOffset: root.centerOffset
    cell: root.cell
    shape: Cells.cameraShape(root.lensBloom)
    color: lit || cameraPress.containsMouse ? root.look.foreground : root.look.dim
    Behavior on color { ColorAnimation { duration: Motion.duration(Style, 120) } }

    HeaderPress {
      id: cameraPress
      objectName: "cameraButton"
      tip: "Take a screenshot"
      onClicked: root.screenshotRequested()
    }
  }

  // The look a click switches to: the chart already shows the current one.
  LookIcon {
    id: lookIcon
    objectName: "lookIcon"
    anchors.right: helpMark.left
    anchors.rightMargin: Style.space(14)
    anchors.verticalCenter: parent.verticalCenter
    anchors.verticalCenterOffset: root.centerOffset
    retro: root.look.retro
    seen: root.seen
    still: root.still
    pixel: root.cell - 1
    color: lookPress.containsMouse ? root.look.foreground : root.look.dim
    Behavior on color { ColorAnimation { duration: Motion.duration(Style, 120) } }

    HeaderPress {
      id: lookPress
      objectName: "lookToggle"
      tip: root.look.retro ? "Switch to smooth" : "Switch to retro"
      onClicked: root.styleRequested(root.look.retro ? "smooth" : "retro")
    }
  }

  // Inset by its fill's margin, so the pressed fill ends on the header's
  // edge: the panel clips anything past it.
  Text {
    id: helpMark
    objectName: "helpMark"
    anchors.right: parent.right
    anchors.rightMargin: Style.space(6)
    anchors.verticalCenter: parent.verticalCenter
    anchors.verticalCenterOffset: root.centerOffset
    textFormat: Text.PlainText
    text: "?"
    color: root.helpShown || helpPress.containsMouse ? root.look.foreground : root.look.dim
    Behavior on color { ColorAnimation { duration: Motion.duration(Style, 120) } }
    font.family: root.look.fontFamily
    font.pixelSize: Style.font.caption
    font.bold: true
    HeaderPress {
      id: helpPress
      objectName: "helpToggle"
      selected: root.helpShown
      // A narrower fill, as the glyph is shorter than an icon, and a target
      // at least 24 wide.
      fillPad: Style.space(4)
      leastWidth: Style.space(24)
      tip: root.helpShown ? "Hide the keys" : "Show the keys"
      onClicked: root.helpRequested()
    }
  }
}
