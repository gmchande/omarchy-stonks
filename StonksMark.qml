pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons as Commons
import "Cells.js" as Cells
// Stonks' mark in cells (`Cells.markLevels`): each column's cap lit and its
// stem faint, down to the floor. It climbs, or falls on a down day, so the
// shape says the direction without its colour. The pill's icon form, and the
// look icon's retro cells, which step in column by column (`shown`). At icon
// size (`solid`) each column is one bar at full ink, cap and stem joined, so
// it still reads as a chart where faint cells would scatter into dots.
// A day that turns (`turnTo`) steps the mark to its new way left to right in
// the look icon's 200 ms, each column taking its new colour as it turns; a
// turn reversed mid-step turns back from where it is. At rest, and after
// `settle`, it is simply `falling` in `color`.
Item {
  id: root
  property bool falling: false
  property bool solid: false
  property color color: Commons.Color.foreground
  property int pixel: 2
  property int gap: 1
  readonly property int rows: 4
  readonly property var levels: Cells.markLevels(rows, falling)
  property int shown: levels.length

  // While a turn steps: the columns left of `turnedColumns` show the turn's
  // way in its colour, the rest the way it turned from in that one's.
  property real turn: 1
  readonly property bool turning: step.running
  readonly property int turnedColumns: Math.round(turn * levels.length)
  property bool turnFalling: false
  property color turnColor
  property bool fromFalling: false
  property color fromColor
  readonly property var turnLevels: Cells.markLevels(rows, turnFalling)
  readonly property var fromLevels: Cells.markLevels(rows, fromFalling)

  NumberAnimation { id: step; target: root; property: "turn"; duration: 200; easing.type: Easing.OutCubic }

  // The day now goes `nowFalling` in `nowColor`, after `wasFalling` in
  // `wasColor`. Only a change of shape turns: a colour alone, or a mark not
  // on show, changes at once. Mid-step, the turn heads for the new way:
  // back toward where it came from, or on, never queued.
  function turnTo(nowFalling, nowColor, wasFalling, wasColor) {
    var to
    if (!step.running) {
      if (nowFalling === wasFalling || !visible) return
      fromFalling = wasFalling
      fromColor = wasColor
      turnFalling = nowFalling
      turnColor = nowColor
      turn = 0
      to = 1
    } else if (nowFalling === fromFalling) {
      fromColor = nowColor
      to = 0
    } else {
      turnFalling = nowFalling
      turnColor = nowColor
      to = 1
    }
    if (step.running && step.to === to) return
    step.stop()
    step.to = to
    step.start()
  }

  // At once to `falling` in `color`: another symbol, or the mark hidden.
  function settle() {
    step.stop()
    turn = 1
  }
  onVisibleChanged: if (!visible) settle()

  implicitWidth: levels.length * (pixel + gap) - gap
  implicitHeight: rows * (pixel + gap) - gap

  Repeater {
    model: root.levels.length

    Item {
      id: column
      required property int index
      readonly property bool turned: index < root.turnedColumns
      readonly property int level: !root.turning ? root.levels[index]
        : turned ? root.turnLevels[index] : root.fromLevels[index]
      readonly property color ink: !root.turning ? root.color : turned ? root.turnColor : root.fromColor
      visible: index < root.shown
      x: index * (root.pixel + root.gap)
      width: root.pixel
      height: root.height

      Rectangle {
        y: column.level * (root.pixel + root.gap) + root.pixel + (root.solid ? 0 : root.gap)
        width: root.pixel
        height: Math.max(0, root.height - y)
        color: column.ink
        opacity: root.solid ? 1 : 0.35
      }
      Rectangle {
        objectName: "markCell"
        y: column.level * (root.pixel + root.gap)
        width: root.pixel
        height: root.pixel
        color: column.ink
      }
    }
  }
}
