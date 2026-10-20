import QtQuick
import qs.Commons
import qs.Commons as Commons

// A caption-sized word that acts, in the list views and wherever a view
// needs a button: DONE, RENAME, SAVE, the moves. It says only what it does;
// the keys are on the key sheet. It hovers the way the order control does,
// and takes the pressed fill while the button is down. `view` is the view
// it sits in, for the look and the colours.
Text {
  id: root

  property var view: null
  // The button Enter takes, marked as the shell marks its default (its
  // Button's `selected`, ConfirmDialog's chosen button): the selected fill
  // at rest, the word in the selected colour.
  property bool enterTakes: false

  signal activated()

  textFormat: Text.PlainText
  color: enterTakes ? Style.selectedStateColor(view.foreground, Commons.Color.accent)
    : mouse.containsMouse ? view.foreground : view.dim
  font.family: view.fontFamily
  font.pixelSize: Style.font.caption
  font.bold: true
  font.letterSpacing: 1

  Rectangle {
    objectName: "actionFill"
    z: -1
    anchors.centerIn: parent
    width: parent.implicitWidth + Style.space(12)
    height: parent.implicitHeight + Style.space(4)
    radius: root.view.retro ? 0 : Style.cornerRadius
    color: mouse.pressed ? Style.pressedFillFor(root.view.foreground, Commons.Color.accent)
      : mouse.containsMouse ? Style.hoverFillFor(root.view.foreground, Commons.Color.accent)
      : root.enterTakes ? Style.selectedFillFor(root.view.foreground, Commons.Color.accent) : "transparent"
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    anchors.margins: -Style.space(6)
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: root.activated()
  }
}
