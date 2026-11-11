pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons
import qs.Commons as Commons
import "Cells.js" as Cells
import "Motion.js" as Motion
// The look a click switches to, as a button shows what pressing it does: the
// chart already shows the current look. Stonks' mark in cells (`StonksMark`)
// in smooth, the same shape as a curve in retro. As the look changes, the
// cells step in over the curve column by column, or give way to it, in 200 ms;
// a change mid-step turns back from where it is.
Item {
  id: root

  property bool retro: false
  property bool still: false
  property color color: Commons.Color.foreground

  // Left to right, 0 at the top.
  readonly property var points: Cells.markPoints()
  // A pixel short of the header's grid (`Header.cell`), so it grows with
  // the text.
  property int pixel: 2
  readonly property int gap: 1
  // 0 is the curve, 1 the cells.
  property real cells: 0
  readonly property int cellColumns: Math.round(cells * points.length)

  Component.onCompleted: settle()
  // While still, nothing moves: a change waits for the open's `settle`.
  onRetroChanged: {
    if (still) return
    step.stop()
    step.to = retro ? 0 : 1
    step.start()
  }
  onStillChanged: if (still && step.running) step.pause()
  NumberAnimation { id: step; target: root; property: "cells"; duration: Motion.duration(Style, 200); easing.type: Easing.Bezier; easing.bezierCurve: Motion.curve(Style) }

  function settle() {
    step.stop()
    cells = retro ? 0 : 1
  }

  implicitWidth: mark.implicitWidth
  implicitHeight: mark.implicitHeight

  onColorChanged: curve.requestPaint()

  Item {
    x: root.cellColumns * (root.pixel + root.gap)
    width: Math.max(0, root.width - x)
    height: root.height
    clip: true

    Canvas {
      id: curve
      x: -parent.x
      width: root.width
      height: root.height
      onWidthChanged: requestPaint()
      onHeightChanged: requestPaint()
      onPaint: {
        var ctx = getContext("2d")
        ctx.clearRect(0, 0, width, height)
        var pts = root.points
        var w = width
        var h = height
        var at = function(p) { return { x: 1 + p.x * (w - 2), y: 1 + p.y * (h - 2) } }
        ctx.strokeStyle = root.color
        // 1.5 px on the header's smallest grid, thickening with it.
        ctx.lineWidth = Math.max(1.5, (root.pixel + root.gap) / 2)
        ctx.lineCap = "round"
        ctx.lineJoin = "round"
        ctx.beginPath()
        var first = at(pts[0])
        ctx.moveTo(first.x, first.y)
        // Through the midpoints, each point a control: a curve, not a zigzag.
        for (var i = 1; i < pts.length - 1; i++) {
          var c = at(pts[i])
          var next = at(pts[i + 1])
          ctx.quadraticCurveTo(c.x, c.y, (c.x + next.x) / 2, (c.y + next.y) / 2)
        }
        var last = at(pts[pts.length - 1])
        ctx.lineTo(last.x, last.y)
        ctx.stroke()
      }
    }
  }

  StonksMark {
    id: mark
    pixel: root.pixel
    gap: root.gap
    color: root.color
    shown: root.cellColumns
  }
}
