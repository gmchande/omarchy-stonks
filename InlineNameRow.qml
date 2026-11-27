pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons

// A list's name, typed in place: "New list…" (`prompt`) until it's taken,
// or over a list's row as it's renamed. Beside the field, its action and
// CANCEL; under it, why the name was refused (`problem`). The view it sits
// in (`host`) keeps whether a name is typed and why it was refused.
Item {
  id: row

  property OverRows host
  property Look look
  property bool editing: false
  property string problem: ""
  property string prompt: ""
  property bool isCursor: false
  property string placeholder: ""
  property string action: "MAKE"
  property int lineHeight: 0
  // Where the typed name, the prompt and the problem start; where the
  // field starts, and its gap to the actions; the actions' room on the right.
  property real textX: 0
  property real fieldX: 0
  property real fieldGap: Style.space(10)
  property real actionsRight: 0
  property string text: ""
  property bool fieldLoaded: false
  readonly property Field field: fieldLoader.item as Field
  onEditingChanged: if (editing) fieldLoaded = true
  onTextChanged: if (field && field.text !== text) field.text = text
  // The names the walks find them by.
  property string lineName: ""
  property string fieldName: ""
  property string actionName: ""
  property string cancelName: ""

  signal taken()
  signal submitted(string name)
  signal cancelled()

  height: lineHeight * (problem !== "" ? 2 : 1)

  // The field takes the keys a turn later, while the view is on and the name
  // still typed; a rename's name whole selected.
  function edit(selectAll) {
    Qt.callLater(function() {
      var input = row.field
      if (!row.host.active || !row.editing || !input) return
      input.forceActiveFocus()
      if (selectAll) input.selectAll()
    })
  }

  // The field gives the keys back to the view, while it's on. The field lets
  // go first, or the view's scope hands them straight back.
  function release() {
    if (field) field.focus = false
    if (row.host.active) row.host.forceActiveFocus()
  }

  // The line gives way whole to the field while a name is typed.
  MenuLine {
    objectName: row.lineName
    width: row.width
    height: row.lineHeight
    visible: row.prompt !== "" && !row.editing
    look: row.look
    isCursor: row.isCursor
    onTaken: row.taken()

    Text {
      x: row.textX
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: row.prompt
      color: row.look.dim
      font.family: row.look.fontFamily
      font.pixelSize: Style.font.bodySmall
    }
  }

  Loader {
    id: fieldLoader
    active: row.editing || row.fieldLoaded
    visible: row.editing
    x: row.fieldX
    width: actions.x - x - row.fieldGap
    height: row.lineHeight
    sourceComponent: Field {
      id: field
      objectName: row.fieldName
      visible: row.editing
      verticalPadding: 0
      leftPadding: row.textX - row.fieldX
      retro: row.look.retro
      foreground: row.look.foreground
      dim: row.look.dim
      font.family: row.look.fontFamily
      font.pixelSize: Style.font.bodySmall
      placeholderText: row.placeholder
      Component.onCompleted: text = row.text
      onTextChanged: if (row.text !== text) row.text = text
      // The field takes Enter itself, so it goes no further.
      onAccepted: row.submitted(field.text)
      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Escape) { row.cancelled(); event.accepted = true }
      }
    }
  }

  Row {
    id: actions
    visible: row.editing
    anchors.right: parent.right
    anchors.rightMargin: row.actionsRight
    height: row.lineHeight
    spacing: Style.space(14)

    ListAction {
      objectName: row.actionName
      look: row.look
      anchors.verticalCenter: parent.verticalCenter
      text: row.action
      enterTakes: true
      onActivated: row.submitted(row.text)
    }
    ListAction {
      objectName: row.cancelName
      look: row.look
      anchors.verticalCenter: parent.verticalCenter
      text: "CANCEL"
      onActivated: row.cancelled()
    }
  }

  Text {
    visible: row.problem !== ""
    x: row.textX
    y: row.lineHeight
    width: row.width - x
    height: row.lineHeight
    verticalAlignment: Text.AlignVCenter
    textFormat: Text.PlainText
    text: row.problem
    color: row.look.foreground
    font.family: row.look.fontFamily
    font.pixelSize: Style.font.caption
    elide: Text.ElideRight
  }
}
