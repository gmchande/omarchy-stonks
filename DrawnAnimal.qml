import QtQuick
import qs.Commons
// The bull or the bear in smooth's own hand, drawn the way the hero chart
// draws: one 1.5 px round line in the day's colour and the wash inside it.
// The same subjects as retro's cells (`Cells.js`): two faces, front on, the
// bull's with its horns and the bear's with its round ears. Drawn on a 40
// by 28 grid, the retro sprite's box, and scaled to the item.
Item {
  id: root

  property bool bull: true
  property color color: Color.foreground
  // The wash's alpha, as the hero's (`Tones.washAlpha`), so the bear's red
  // weighs the same as the bull's green.
  property real wash: 0.16
  // How far the eyes have closed: 0 open, 1 shut to a flat slit of the
  // line's weight, as it sleeps.
  property real lids: 0

  implicitWidth: 40
  implicitHeight: 28

  onBullChanged: canvas.requestPaint()
  onColorChanged: canvas.requestPaint()
  onWashChanged: canvas.requestPaint()
  onLidsChanged: canvas.requestPaint()

  Canvas {
    id: canvas
    anchors.fill: parent
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onPaint: {
      var ctx = getContext("2d")
      ctx.clearRect(0, 0, width, height)
      var s = Math.min(width / 40, height / 28)
      if (s <= 0) return
      ctx.save()
      ctx.translate((width - 40 * s) / 2, (height - 28 * s) / 2)
      ctx.scale(s, s)
      ctx.lineJoin = "round"
      ctx.lineCap = "round"
      ctx.lineWidth = 1.5 / s
      ctx.strokeStyle = root.color
      ctx.fillStyle = Qt.rgba(root.color.r, root.color.g, root.color.b, root.wash)
      if (root.bull) bull(ctx)
      else bear(ctx)
      ctx.restore()
    }

    function dot(ctx, x, y, r) {
      ctx.beginPath()
      ctx.arc(x, y, r, 0, Math.PI * 2)
      ctx.fill()
    }

    // An eye, its lid down by `root.lids`: the dot squashed to a slit of
    // the line's weight, a little wider, as a shut eye is drawn.
    function eye(ctx, x, y, r) {
      var slit = ctx.lineWidth / 2 / r
      ctx.save()
      ctx.translate(x, y + r * 0.4 * root.lids)
      ctx.scale(1 + 0.6 * root.lids, 1 - (1 - slit) * root.lids)
      dot(ctx, 0, 0, r)
      ctx.restore()
    }

    // The bull's face, front on: a broad brow, horns sweeping out and up,
    // a long face narrowing to a soft muzzle and its two nostrils.
    function bull(ctx) {
      ctx.beginPath()
      ctx.moveTo(13.5, 8.5)
      ctx.quadraticCurveTo(20, 6.2, 26.5, 8.5)
      ctx.quadraticCurveTo(27.6, 13, 25.2, 17.2)
      ctx.quadraticCurveTo(27.2, 19.4, 26.2, 23)
      ctx.quadraticCurveTo(20, 27.4, 13.8, 23)
      ctx.quadraticCurveTo(12.8, 19.4, 14.8, 17.2)
      ctx.quadraticCurveTo(12.4, 13, 13.5, 8.5)
      ctx.closePath()
      ctx.fill()
      ctx.stroke()
      // The horns, from the brow's corners out and up.
      ctx.beginPath()
      ctx.moveTo(13.8, 10)
      ctx.quadraticCurveTo(5, 11.5, 3.5, 3)
      ctx.moveTo(26.2, 10)
      ctx.quadraticCurveTo(35, 11.5, 36.5, 3)
      ctx.stroke()
      // The ears, under the horns.
      ctx.beginPath()
      ctx.moveTo(13.6, 12.4)
      ctx.quadraticCurveTo(9.4, 13.8, 8.6, 12.6)
      ctx.moveTo(26.4, 12.4)
      ctx.quadraticCurveTo(30.6, 13.8, 31.4, 12.6)
      ctx.stroke()
      ctx.fillStyle = root.color
      eye(ctx, 17, 13.2, 1.15)
      eye(ctx, 23, 13.2, 1.15)
      dot(ctx, 17.6, 21.6, 0.95)
      dot(ctx, 22.4, 21.6, 0.95)
    }

    // The bear's face, front on, as tall as the bull's: a flat crown with a
    // round ear on each corner, the cheeks flaring wider than the ears and
    // drawing in to a broad jaw, and a nose with a short line under it. No
    // muzzle disc, which would make it a pig.
    function bear(ctx) {
      ctx.beginPath()
      ctx.arc(11.49, 7.71, 3.58, Math.PI * 145 / 180, Math.PI * 335 / 180, false)
      ctx.quadraticCurveTo(20, 5.47, 25.26, 6.2)
      ctx.arc(28.51, 7.71, 3.58, Math.PI * 205 / 180, Math.PI * 35 / 180, false)
      ctx.quadraticCurveTo(32.54, 12.86, 32.77, 17.34)
      ctx.quadraticCurveTo(31.87, 22.27, 26.27, 24.74)
      ctx.quadraticCurveTo(20, 27.65, 13.73, 24.74)
      ctx.quadraticCurveTo(8.13, 22.27, 7.23, 17.34)
      ctx.quadraticCurveTo(7.46, 12.86, 8.55, 9.77)
      ctx.closePath()
      ctx.fill()
      ctx.stroke()
      ctx.beginPath()
      ctx.moveTo(20, 19.81)
      ctx.lineTo(20, 21.82)
      ctx.stroke()
      ctx.fillStyle = root.color
      eye(ctx, 15.52, 13.76, 1.29)
      eye(ctx, 24.48, 13.76, 1.29)
      // The nose: a soft wedge, wider than tall, flat on top.
      ctx.beginPath()
      ctx.moveTo(17.98, 17.57)
      ctx.quadraticCurveTo(20, 17.01, 22.02, 17.57)
      ctx.quadraticCurveTo(22.24, 20.26, 20, 19.81)
      ctx.quadraticCurveTo(17.76, 20.26, 17.98, 17.57)
      ctx.closePath()
      ctx.fill()
    }
  }
}
