pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons as Commons
// A header icon (the speaker, the camera, the unit) drawn from a `Cells`
// path in the look icon's pen, on its grid of cells each a pixel short of
// the next. Paths are drawn at a 3 px cell and scaled with it.
Item {
  id: root

  property color color: Commons.Color.foreground
  property int cell: 3
  property var shape: null

  readonly property int columns: shape ? shape.columns : 0
  readonly property int rows: shape ? shape.rows : 0

  implicitWidth: columns * cell - 1
  implicitHeight: rows * cell - 1
  width: implicitWidth
  height: implicitHeight

  onShapeChanged: pen.requestPaint()
  onColorChanged: pen.requestPaint()
  Canvas {
    id: pen
    anchors.fill: parent
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onPaint: {
      var ctx = getContext("2d")
      ctx.reset()
      if (!root.shape) return
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
