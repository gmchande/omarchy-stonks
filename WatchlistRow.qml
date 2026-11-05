pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons
import qs.Commons as Commons
import "Cells.js" as Cells
import "Chart.js" as Chart
import "Figures.js" as Figures
import "Format.js" as Format
import "Tones.js" as Tones
// A row, set as Apple's Stocks sets one: symbol over name, price over
// change, the day line between.
Rectangle {
  id: row

  required property string symbol
  property var quote: null
  property var view: null
  property string status: "loading"
  property bool featuredRow: false
  property bool cursor: false
  property bool removable: false
  property bool retro: false
  property bool lifted: false
  // The list builds the words and the pointer only for rows near sight, so a
  // long list costs about what a screenful does.
  property bool built: true
  // How far down this row the open list menu reaches; 0 while it's shut.
  property real menuCovers: 0
  // Lifted or sliding, the row lays the card's ground under its fill, at
  // once, so the rows it passes never show through.
  property bool moving: false
  property color ground: "transparent"
  property real scrubX: -1
  property real reveal: 1
  property var calendars: null
  property color foreground: Commons.Color.foreground
  property color dim: Tones.dim(foreground, Commons.Color.background)
  property color dimmer: Tones.dimmer(foreground, Commons.Color.background)
  property color upColor: Commons.Color.foreground
  property color downColor: Commons.Color.urgent
  property string fontFamily: Style.font.family

  // In scene coordinates. `second` is Qt's double-click second press, which
  // the list may not act on (Watchlist.clickRow).
  signal featureRequested(real x, real y, bool second)
  signal menuRequested(real x, real y, bool second)
  // The release acts on the press's answer (Watchlist.clickCounts).
  signal removePressed(real x, real y, bool second)
  signal removeReleased(real x, real y)
  signal listsRequested(real x, real y, bool second)
  // In the parent's coordinates: the row itself moves under the pointer.
  signal dragStarted(real y)
  signal dragMoved(real y)
  signal dragEnded()
  signal dragCanceled()

  // The 1D chart's day (`Chart.lineDay`), null until Robinhood says which. It
  // changes with this quote or Robinhood's answer, never with the clock, the
  // change mode, or another symbol's quote.
  property var day: null
  readonly property var geometry: day && day.points.length ? Chart.chartGeometry(day, calendars) : null

  readonly property color trend: !view || view.tone === "flat" ? dim : view.tone === "up" ? upColor : downColor
  property var freshness: null
  property bool sourceDown: false
  readonly property var shownFreshness: sourceDown ? Figures.quietFreshness(freshness) : freshness
  readonly property bool warns: Figures.freshnessWarns(shownFreshness)
  readonly property string freshnessNote: quote ? Figures.freshnessText(shownFreshness, quote, calendars) : ""
  property string newestTime: ""
  readonly property string detail: quote
    ? (freshnessNote !== "" ? (warns ? "! " : "") + Format.sentenceCase(freshnessNote) : view.name)
    : sourceDown ? "" : (status === "failed" ? "! No data for this symbol" : warns ? "! No data" : "Loading…")
  readonly property string detailTime: quote && freshnessNote === "" && newestTime !== ""
    ? (detail !== "" ? " · " : "") + newestTime : ""

  readonly property int sparkWidth: Style.space(72)
  readonly property int priceWidth: Style.space(96)
  readonly property int gap: Style.space(10)
  readonly property int inset: Style.space(4)

  height: Style.space(40)
  radius: retro ? 0 : Style.cornerRadius
  readonly property color fill: lifted ? Style.pressedFillFor(foreground, Commons.Color.accent)
    : featuredRow ? Style.selectedFillFor(foreground, Commons.Color.accent)
    : cursor ? Style.hoverFillFor(foreground, Commons.Color.accent) : "transparent"
  color: fill
  border.width: lifted ? 1 : 0
  border.color: Style.normalBorderFor(foreground, Commons.Color.accent)

  // The shell's hover speed (CursorSurface).
  Behavior on color { ColorAnimation { duration: 60 } }

  Rectangle {
    objectName: "rowGround"
    z: -1
    anchors.fill: parent
    radius: row.radius
    visible: row.moving
    color: row.ground
  }

  // Built even out of sight: a canvas built as its row comes into sight draws
  // a frame or two after the row's words.
  Loader {
    x: row.width - row.gap - row.priceWidth - row.gap - row.sparkWidth
    width: row.sparkWidth
    height: Style.space(22)
    anchors.verticalCenter: parent.verticalCenter
    sourceComponent: row.retro ? cellsLine : smoothLine
  }

  Component {
    id: smoothLine
    Sparkline {
      objectName: "rowLine"
      geometry: row.geometry
      up: row.view ? row.view.dayUp : null
      upColor: row.upColor
      downColor: row.downColor
      lineColor: row.dim
      baselineColor: row.dimmer
      cursorX: row.scrubX
      reveal: row.reveal
    }
  }

  // The hero's retro chart at a finer pitch: one drawing at two sizes.
  Component {
    id: cellsLine
    PixelChart {
      objectName: "rowCells"
      geometry: row.geometry
      up: row.view ? row.view.dayUp : null
      upColor: row.upColor
      downColor: row.downColor
      baselineColor: row.dimmer
      hairlineColor: row.foreground
      ground: Qt.tint(row.ground, row.fill)
      pixel: 2
      gap: 1
      bells: false
      scrubX: row.scrubX
      reveal: row.reveal
    }
  }

  Loader {
    anchors.fill: parent
    active: row.built
    sourceComponent: Component {
      Item {
        objectName: "rowContent"
        CursorBar {
          visible: row.cursor
          retro: row.retro
          foreground: row.foreground
        }

        Text {
          id: symbolText
          objectName: "rowSymbol"
          visible: y >= row.menuCovers
          x: row.gap
          y: row.inset
          textFormat: Text.PlainText
          text: row.symbol
          color: row.foreground
          font.family: row.fontFamily
          font.pixelSize: Style.font.body
          font.bold: true
        }

        Text {
          id: detailText
          objectName: "rowDetail"
          visible: y >= row.menuCovers
          x: row.gap
          anchors.bottom: parent.bottom
          anchors.bottomMargin: row.inset
          // The name gives way to the newest price's time, so the time stays whole.
          width: Math.min(implicitWidth, row.width - x - row.priceWidth - row.gap * 2 - row.sparkWidth - row.gap - timeText.implicitWidth)
          textFormat: Text.PlainText
          text: row.detail
          color: row.warns ? row.foreground : row.dim
          font.family: row.fontFamily
          font.pixelSize: Style.font.bodySmall
          font.bold: row.warns
          elide: Text.ElideRight
        }
        Text {
          id: timeText
          objectName: "rowTime"
          visible: detailText.visible
          x: detailText.x + detailText.width
          anchors.baseline: detailText.baseline
          textFormat: Text.PlainText
          text: row.detailTime
          color: row.dim
          font.family: row.fontFamily
          font.pixelSize: Style.font.bodySmall
        }

        // The shell's row action (PanelActionButton): dim, the foreground
        // under the pointer, never the urgent colour, which here means a
        // falling price. Beside the symbol, so nothing on the row moves for
        // it; no tip, which would cover the next row.
        Item {
          id: removeButton
          objectName: "rowRemove"
          visible: row.removable && symbolText.visible
          width: Style.space(22)
          height: width
          x: symbolText.x + symbolText.width + Style.space(4)
          y: symbolText.y + (symbolText.height - height) / 2
          readonly property bool hovered: mouse.containsMouse && mouse.onRemove(mouse.mouseX, mouse.mouseY)
          readonly property color ink: hovered ? row.foreground : row.dim

          // The shell's 22 px target, its fill inset to clear the row's top.
          Rectangle {
            objectName: "rowRemoveFill"
            anchors.fill: parent
            anchors.margins: Style.space(2)
            radius: row.retro ? 0 : Style.cornerRadius
            color: removeButton.hovered && mouse.pressed && mouse.pressedOnRemove && !mouse.dragged ? Style.pressedFillFor(row.foreground, Commons.Color.accent)
              : removeButton.hovered ? Style.hoverFillFor(row.foreground, Commons.Color.accent) : "transparent"
            Behavior on color { ColorAnimation { duration: 60 } }
          }

          // Smooth: ×.
          Text {
            objectName: "rowRemoveGlyph"
            visible: !row.retro
            anchors.centerIn: parent
            textFormat: Text.PlainText
            text: "󰅖"
            color: removeButton.ink
            font.family: row.fontFamily
            font.pixelSize: Style.font.body
          }

          Loader {
            anchors.centerIn: parent
            active: row.retro
            sourceComponent: Component {
              PixelSprite {
                objectName: "rowRemoveCells"
                width: Cells.REMOVE_SPRITE[0].length * 2
                height: Cells.REMOVE_SPRITE.length * 2
                columns: Cells.REMOVE_SPRITE[0].length
                rows: Cells.REMOVE_SPRITE.length
                pixels: Cells.spritePixels(Cells.REMOVE_SPRITE)
                color: removeButton.ink
              }
            }
          }
        }

        Text {
          x: row.width - row.gap - row.priceWidth
          y: row.inset
          width: row.priceWidth
          horizontalAlignment: Text.AlignRight
          textFormat: Text.PlainText
          text: row.view ? row.view.priceText : ""
          color: row.foreground
          font.family: row.fontFamily
          font.pixelSize: Style.font.body
        }

        Text {
          x: row.width - row.gap - row.priceWidth
          width: row.priceWidth
          anchors.bottom: parent.bottom
          anchors.bottomMargin: row.inset
          horizontalAlignment: Text.AlignRight
          textFormat: Text.PlainText
          text: row.view ? Format.lookSigns(row.view.changeLine, row.retro) : ""
          color: row.trend
          font.family: row.fontFamily
          font.pixelSize: Style.font.body
          font.bold: true
        }

        // Keeps the press from the list: a drag lifts the row, and only the
        // wheel scrolls.
        MouseArea {
          id: mouse
          anchors.fill: parent
          hoverEnabled: true
          preventStealing: true
          acceptedButtons: Qt.LeftButton | Qt.RightButton
          cursorShape: row.lifted ? Qt.ClosedHandCursor : Qt.PointingHandCursor

          property real pressY: -1
          property bool dragged: false
          // Only a release on the button with no drag between removes: Qt
          // acts on a double-click's second press at mouse-down.
          property bool pressedOnRemove: false

          function onRemove(x, y) {
            return removeButton.visible && x >= removeButton.x && x < removeButton.x + removeButton.width
              && y >= removeButton.y && y < removeButton.y + removeButton.height
          }

          onPressed: function(event) {
            pressY = event.button === Qt.LeftButton ? event.y : -1
            dragged = false
            pressedOnRemove = event.button === Qt.LeftButton && !(event.modifiers & Qt.ControlModifier) && onRemove(event.x, event.y)
            if (pressedOnRemove) {
              var at = mapToItem(null, event.x, event.y)
              row.removePressed(at.x, at.y, false)
            }
          }
          onPositionChanged: function(event) {
            if (!pressed || pressY < 0) return
            if (!dragged) {
              if (Math.abs(event.y - pressY) < 6) return
              dragged = true
              row.dragStarted(row.mapToItem(row.parent, event.x, pressY).y)
            }
            row.dragMoved(row.mapToItem(row.parent, event.x, event.y).y)
          }
          onReleased: function(event) {
            if (dragged) row.dragEnded()
            else if (pressedOnRemove && onRemove(event.x, event.y)) {
              var at = mapToItem(null, event.x, event.y)
              row.removeReleased(at.x, at.y)
            }
          }
          onCanceled: {
            if (dragged) row.dragCanceled()
          }
          function act(event, second) {
            if (dragged) return
            var at = mapToItem(null, event.x, event.y)
            if (event.button === Qt.RightButton) row.menuRequested(at.x, at.y, second)
            else if (event.modifiers & Qt.ControlModifier) row.listsRequested(at.x, at.y, second)
            else if (pressedOnRemove) return
            else if (event.button === Qt.LeftButton) row.featureRequested(at.x, at.y, second)
          }
          onClicked: function(event) { act(event, false) }
          onDoubleClicked: function(event) {
            if (pressedOnRemove) {
              var at = mapToItem(null, event.x, event.y)
              row.removePressed(at.x, at.y, true)
            }
            else act(event, true)
          }
        }
      }
    }
  }
}
