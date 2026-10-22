pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons as Commons
// One of the header's own icons, the speaker or the camera (`Cells`), on the
// look icon's grid: `cell` px a step, each cell a pixel short of the next.
// In retro, square cells, lit ("#") or faint ("+", at the mark's stems'
// 35%); in smooth, its path in the look icon's pen over the same box, drawn
// on cells 3 px apart and scaled with the cell, the pen with it: 1.5 px,
// then 2, then 2.5. It paints only when its shape, ink, look, or size does.
Item {
  id: root

  property bool retro: false
  property color color: Commons.Color.foreground
  property int cell: 3
  // The shape (`Cells.SOUND_ON` and the rest): its columns and rows, its
  // cells, and its path.
  property var shape: null

  readonly property int columns: shape ? shape.columns : 0
  readonly property int rows: shape ? shape.rows : 0
  readonly property var drawn: {
    var out = []
    var rowsOf = shape ? shape.cells : []
    for (var y = 0; y < rowsOf.length; y++) {
      for (var x = 0; x < rowsOf[y].length; x++) {
        var ch = rowsOf[y].charAt(x)
        if (ch === "#" || ch === "+") out.push({ x: x, y: y, faint: ch === "+" })
      }
    }
    return out
  }

  implicitWidth: columns * cell - 1
  implicitHeight: rows * cell - 1
  width: implicitWidth
  height: implicitHeight

  Repeater {
    model: root.retro ? root.drawn : []
    Rectangle {
      required property var modelData
      x: modelData.x * root.cell
      y: modelData.y * root.cell
      width: root.cell - 1
      height: root.cell - 1
      color: root.color
      opacity: modelData.faint ? 0.35 : 1
    }
  }

  onShapeChanged: pen.requestPaint()
  onColorChanged: pen.requestPaint()
  onRetroChanged: pen.requestPaint()
  Canvas {
    id: pen
    visible: !root.retro
    anchors.fill: parent
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onPaint: {
      var ctx = getContext("2d")
      ctx.reset()
      if (root.retro || !root.shape) return
      var s = root.cell / 3
      ctx.scale(s, s)
      ctx.lineWidth = 1.5
      ctx.lineCap = "round"
      ctx.lineJoin = "round"
      ctx.strokeStyle = root.color
      ctx.fillStyle = root.color
      ctx.beginPath()
      var ops = root.shape.path
      for (var i = 0; i < ops.length; i++) {
        var o = ops[i]
        switch (o[0]) {
        case "M": ctx.moveTo(o[1], o[2]); break
        case "L": ctx.lineTo(o[1], o[2]); break
        case "A":
          ctx.moveTo(o[1] + o[3] * Math.cos(o[4] * Math.PI / 180), o[2] + o[3] * Math.sin(o[4] * Math.PI / 180))
          ctx.arc(o[1], o[2], o[3], o[4] * Math.PI / 180, o[5] * Math.PI / 180, false)
          break
        case "Z": ctx.closePath(); break
        case "stroke": ctx.stroke(); ctx.beginPath(); break
        case "fill": ctx.fill(); ctx.beginPath(); break
        case "hollow": ctx.fillRule = Qt.OddEvenFill; ctx.fill(); ctx.fillRule = Qt.WindingFill; ctx.beginPath(); break
        case "dot": ctx.beginPath(); ctx.arc(o[1], o[2], o[3], 0, 2 * Math.PI, false); ctx.fill(); ctx.beginPath(); break
        }
      }
    }
  }
}
