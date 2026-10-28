import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Cells.js" as Cells
import "Tones.js" as Tones
// The animal, the stock's name over the live status, the sounds, the
// camera, the look, and the help mark, with a rule under them, as a shell
// panel's hero has: an icon, a bold title, and its state in small capitals.
// Surfaces own the actions; this only draws and signals. The animal is the
// day's bull or bear in cells (`Cells.spriteFor`), the same in both looks,
// in one slot the status words start after, drawn or not, so neither the
// look nor a flat day moves them. While its market rests it sleeps: eyes
// shut and a dim "z" just past the slot, above the words. The height is the
// slot's in both looks, and the look is one small icon in both, so toggling
// moves nothing. Each icon on the right says on hover what a click does,
// in the shell's own tooltip, under the icon and inside the card, covering
// what is there while the pointer rests: a popup hangs from a top bar, at
// the screen's top, with no room above. The animal has none.
Item {
  id: root

  // The words, then the same said in less, each form shorter than the one
  // before (`StonksBody.headerForms`), up to three: where one doesn't fit,
  // the next shows.
  property var statusForms: []
  // The stock's name, over the status words. Its line stays while there is
  // none, so a name arriving moves nothing.
  property string title: ""
  // Whether the title's line and the rule show: the body gives them way
  // where large text on a short screen would leave fewer than three rows
  // beside the chart's least (`StonksBody.headerTitled`), and the header is
  // the words alone on one line, the name back on the hero's.
  property bool titled: true
  // The words say a range failed, and its button asks again, as r does.
  property bool offersRetry: false
  property bool retro: false
  // The sounds are on: the speaker shows its waves, or, off, a cross.
  property bool soundsOn: false
  // The animal, as the body decides it: `kind` "bull", "bear", or "" (a
  // flat day, or no direction yet), and `chart`, what it reads. A turn of
  // the same chart crossfades in smooth; any other change, and every one in
  // retro, is at once. `asleep`, its market resting, and `bell`, the clock
  // alone put it to sleep or woke it: then, on the same chart, the eyes
  // close or open over 320 ms; any other change of sleep is at once.
  // `scrubbed`: a scrub has it awake, so the sleep that follows its end is
  // no bell.
  property var animal: ({ kind: "", chart: "", asleep: false, bell: false, scrubbed: false })
  property bool scrubbing: false
  property bool live: false
  // The words say prices stopped (`StonksBody.troubleForms`): at full
  // strength, so they stand out with no colour, since red says down.
  property bool trouble: false
  // The surface is closing: the look icon's step and the animal's turn stop
  // where they are.
  property bool still: false
  // The key sheet shows, so a click on ? hides it.
  property bool helpShown: false
  // A screenshot was taken on this visit: the camera stays lit until the
  // surface closes.
  property bool cameraLit: false
  property color foreground: Commons.Color.foreground
  property color dim: Tones.dim(foreground, Commons.Color.background)
  property color upColor: Commons.Color.foreground
  property color downColor: Commons.Color.urgent
  property color ground: Commons.Color.background
  property string fontFamily: Style.font.family

  readonly property string kind: animal ? animal.kind : ""
  // The chart the animal last showed, by which a change is a turn.
  property string shownChart: ""
  // The sleep last shown, and whether a scrub had it awake.
  property bool shownAsleep: false
  property bool shownScrubbed: false
  // How far the eyes have closed, 0 to 1, evenly in time, and whether they
  // last moved open: a wake steps from shut, so the cells show the lids
  // half way at the middle of either move (`lids`: 0 open, 1 half, 2 shut).
  property real closing: 0
  property bool waking: false
  readonly property real moved: waking ? 1 - closing : closing
  readonly property int steps: moved >= 1 ? 2 : moved >= 0.5 ? 1 : 0
  readonly property int lids: waking ? 2 - steps : steps

  signal styleRequested(string style)
  signal soundsRequested()
  signal screenshotRequested()
  signal helpRequested()
  signal replayRequested()
  signal retryRequested()

  // At rest as a surface opens: the icon on the look, the animal on what
  // it reads.
  function settle() {
    lookIcon.settle()
    show(false)
  }

  // The layers to the animal: crossfading in smooth when it turns on the
  // chart it showed, from wherever a turn under way has them; else at
  // once. Its sleep as `sleep` decides.
  function show(fade) {
    var k = animal ? animal.kind : ""
    shownChart = animal ? animal.chart : ""
    turn.stop()
    turnBull.to = k === "bull" ? 1 : 0
    turnBear.to = k === "bear" ? 1 : 0
    if (fade && !retro) turn.start()
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

  // An icon's tip, 3 px under its target, centred on it but never past the
  // header's right edge. Declared in the target, inside its icon.
  component HeaderTip: PanelToolTip {
    readonly property Item icon: parent.parent
    y: parent.height + 3
    x: Math.min((parent.width - implicitWidth) / 2, icon.parent.width - icon.x - parent.x - implicitWidth)
  }

  // The title and the words, then the rule, a band's gap short of a group's
  // under them, so the group's gap the body leaves after the header makes
  // the gap below the rule the gap above it. The rest centre on the two
  // lines, not on the rule.
  readonly property int twoLines: Math.max(Style.space(28),
    titleText.implicitHeight + Style.space(2) + statusWords.implicitHeight)
  readonly property int ruleGap: Style.space(14)
  // The height with the title, whether or not it shows.
  readonly property int titledHeight: twoLines + ruleGap * 2 - Style.space(8) + 1
  readonly property int contentHeight: titled ? twoLines : Style.space(28)
  readonly property int centerOffset: Math.round((contentHeight - height) / 2)
  implicitHeight: titled ? titledHeight : Style.space(28)
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
    anchors.verticalCenterOffset: root.centerOffset

    // One layer each, so smooth's turn crossfades between them.
    PixelSprite {
      id: bull
      objectName: "bullCells"
      anchors.fill: parent
      visible: opacity > 0
      pixels: Cells.spriteFor(true, root.lids)
      color: root.upColor
    }
    PixelSprite {
      id: bear
      objectName: "bearCells"
      anchors.fill: parent
      visible: opacity > 0
      pixels: Cells.spriteFor(false, root.lids)
      color: root.downColor
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

  // Asleep, a small dim "z" in cells over the animal's back, just past its
  // slot, coming in as the eyes shut. It sits at the header's top, never
  // above it: the popup's body starts there and clips what draws past it.
  PixelSprite {
    objectName: "sleepCells"
    readonly property int cell: Math.floor(Math.min(slot.width / 20, slot.height / 14))
    visible: root.kind !== "" && root.lids === 2
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
  // range's retry follows them. They start twice as far from the sleeping
  // z as the bull is, so it reads as the animal's and not as a mark on the
  // first word, and stop as much sooner, so their room is the same. The
  // first form that fits that room shows: with its letters spaced, else
  // closed up. Without this, beside the speaker and the camera, Tokyo's
  // Constitution Memorial Day loses its name in the popup at the everyday
  // text size, and after hours at size 16 loses its time.
  readonly property real wordsRoom: Math.max(0, soundIcon.x - Style.space(8) - statusWords.x
    - (root.offersRetry ? retry.implicitWidth + Style.space(16) : 0))
  readonly property var measured: [form0, form1, form2].slice(0, statusForms.length)
  // The form on show (`form`) and whether its letters close up (`tight`);
  // where none fits, the last, closed up and cut.
  readonly property var fit: {
    for (var i = 0; i < measured.length; i++) {
      if (measured[i].spaced <= wordsRoom) return { form: i, tight: false }
      if (measured[i].tight <= wordsRoom) return { form: i, tight: true }
    }
    return { form: Math.max(0, measured.length - 1), tight: true }
  }
  // A form's width with its letters spaced and closed up, measured, never
  // shown.
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
  FormWidths { id: form0; words: String(root.statusForms[0] || "").toUpperCase(); family: root.fontFamily }
  FormWidths { id: form1; words: String(root.statusForms[1] || "").toUpperCase(); family: root.fontFamily }
  FormWidths { id: form2; words: String(root.statusForms[2] || "").toUpperCase(); family: root.fontFamily }
  Text {
    id: titleText
    objectName: "headerTitle"
    visible: root.titled
    anchors.left: slot.right
    anchors.leftMargin: Style.space(14)
    y: Math.round((root.contentHeight - implicitHeight - Style.space(2) - statusWords.implicitHeight) / 2)
    width: Math.min(implicitWidth, Math.max(0, soundIcon.x - Style.space(8) - x))
    textFormat: Text.PlainText
    text: root.title
    color: root.foreground
    font.family: root.fontFamily
    font.pixelSize: Style.font.title
    font.bold: true
    elide: Text.ElideRight
  }

  // The rule as the footer's, the shell's own separator.
  PanelSeparator {
    objectName: "headerRule"
    visible: root.titled
    y: root.contentHeight + root.ruleGap
    width: root.width
    foreground: root.foreground
    strength: 0.08
  }

  Text {
    id: statusWords
    objectName: "statusText"
    anchors.left: slot.right
    anchors.leftMargin: Style.space(14)
    width: Math.min(implicitWidth, root.wordsRoom)
    y: root.titled ? titleText.y + titleText.implicitHeight + Style.space(2) : Math.round((root.contentHeight - implicitHeight) / 2)
    textFormat: Text.PlainText
    text: root.measured.length ? root.measured[root.fit.form].words : ""
    color: root.scrubbing || root.live || root.trouble ? root.foreground : root.dim
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    font.bold: true
    font.letterSpacing: root.fit.tight ? 0 : 1
    elide: Text.ElideRight
  }

  ListAction {
    id: retry
    objectName: "retryRange"
    view: root
    visible: root.offersRetry
    anchors.left: statusWords.right
    anchors.leftMargin: Style.space(16)
    anchors.verticalCenter: statusWords.verticalCenter
    text: "RETRY"
    onActivated: root.retryRequested()
  }

  // Stonks' own speaker and camera, solid and the same in both looks
  // (`Cells.SOUND_ON` and the rest), and the look icon, on one grid whose
  // cell grows with the text (`Cells.iconCell`), so the header's four keep
  // their weight beside the words at every size; the ? is a word and grows
  // with them already.
  readonly property int cell: Cells.iconCell(Style.fontScale)

  // The sounds as they are, the speaker with its waves, or off with a
  // cross; a click turns them off or on, as m does. One width on or
  // off, so the toggle moves nothing. It hovers and presses as the look
  // icon does, and its target is the header's full height too.
  GridIcon {
    id: soundIcon
    objectName: "soundIcon"
    readonly property bool on: root.soundsOn
    anchors.right: camera.left
    anchors.rightMargin: Style.space(14)
    anchors.verticalCenter: parent.verticalCenter
    anchors.verticalCenterOffset: root.centerOffset
    cell: root.cell
    shape: on ? Cells.SOUND_ON : Cells.SOUND_OFF
    color: soundMouse.containsMouse ? root.foreground : root.dim

    Rectangle {
      objectName: "soundFill"
      z: -1
      anchors.centerIn: parent
      width: parent.width + Style.space(12)
      height: parent.height + Style.space(6)
      radius: root.retro ? 0 : Style.cornerRadius
      color: soundMouse.pressed ? Style.pressedFillFor(root.foreground, Commons.Color.accent) : "transparent"
    }

    MouseArea {
      id: soundMouse
      objectName: "soundToggle"
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.verticalCenter: parent.verticalCenter
      width: parent.width + Style.space(12)
      height: root.contentHeight
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: root.soundsRequested()

      HeaderTip {
        objectName: "soundTip"
        visible: soundMouse.containsMouse
        text: root.soundsOn ? "Turn sounds off" : "Turn sounds on"
        fontFamily: root.fontFamily
      }
    }
  }

  // The camera, which takes a screenshot of the chart on show, as Ctrl+C does:
  // solid, its lens a hole at rest; once it has taken one, lit in the full
  // ink with the shot's dot in its lens until the surface closes. It hovers
  // and presses as the look icon does, its target the header's full
  // height.
  GridIcon {
    id: camera
    objectName: "camera"
    readonly property bool lit: root.cameraLit
    anchors.right: lookIcon.left
    anchors.rightMargin: Style.space(14)
    anchors.verticalCenter: parent.verticalCenter
    anchors.verticalCenterOffset: root.centerOffset
    cell: root.cell
    shape: lit ? Cells.CAMERA_LIT : Cells.CAMERA
    color: lit || cameraMouse.containsMouse ? root.foreground : root.dim

    Rectangle {
      objectName: "cameraFill"
      z: -1
      anchors.centerIn: parent
      width: parent.width + Style.space(12)
      height: parent.height + Style.space(6)
      radius: root.retro ? 0 : Style.cornerRadius
      color: cameraMouse.pressed ? Style.pressedFillFor(root.foreground, Commons.Color.accent) : "transparent"
    }

    MouseArea {
      id: cameraMouse
      objectName: "cameraButton"
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.verticalCenter: parent.verticalCenter
      width: parent.width + Style.space(12)
      height: root.contentHeight
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: root.screenshotRequested()

      HeaderTip {
        objectName: "cameraTip"
        visible: cameraMouse.containsMouse
        text: "Take a screenshot"
        fontFamily: root.fontFamily
      }
    }
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
    anchors.verticalCenterOffset: root.centerOffset
    retro: root.retro
    still: root.still
    pixel: root.cell - 1
    color: lookMouse.containsMouse ? root.foreground : root.dim

    Rectangle {
      objectName: "lookFill"
      z: -1
      anchors.centerIn: parent
      width: parent.width + Style.space(12)
      height: parent.height + Style.space(6)
      radius: root.retro ? 0 : Style.cornerRadius
      color: lookMouse.pressed ? Style.pressedFillFor(root.foreground, Commons.Color.accent) : "transparent"
    }

    MouseArea {
      id: lookMouse
      objectName: "lookToggle"
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.verticalCenter: parent.verticalCenter
      width: parent.width + Style.space(12)
      height: root.contentHeight
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: root.styleRequested(root.retro ? "smooth" : "retro")

      HeaderTip {
        objectName: "lookTip"
        visible: lookMouse.containsMouse
        text: root.retro ? "Switch to smooth" : "Switch to retro"
        fontFamily: root.fontFamily
      }
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
    anchors.verticalCenterOffset: root.centerOffset
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
      color: helpMouse.pressed ? Style.pressedFillFor(root.foreground, Commons.Color.accent) : "transparent"
    }
    MouseArea {
      id: helpMouse
      objectName: "helpToggle"
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.verticalCenter: parent.verticalCenter
      width: Math.max(Style.space(24), parent.width + Style.space(12))
      height: root.contentHeight
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: root.helpRequested()

      HeaderTip {
        objectName: "helpTip"
        visible: helpMouse.containsMouse
        text: root.helpShown ? "Hide the keys" : "Show all keys"
        fontFamily: root.fontFamily
      }
    }
  }
}
