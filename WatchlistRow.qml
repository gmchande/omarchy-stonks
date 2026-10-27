pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons
import qs.Commons as Commons
import "Cells.js" as Cells
import "Chart.js" as Chart
import "Figures.js" as Figures
import "Format.js" as Format
import "Tones.js" as Tones
// One watchlist row: symbol over name, the day line, price over change.
// The featured row sits in the shell's selected fill; the cursor, which the
// keys and the pointer both move, takes the shell's hover-cursor fill and a
// bar down the left edge, and on the featured row only the bar. A row held
// in a drag takes the pressed fill and a border. A cursor you put there,
// by pointer or key, shows a remove button.
Rectangle {
  id: row

  required property string symbol
  property var quote: null
  property var view: null
  property string status: "loading"
  property bool featuredRow: false
  property bool cursor: false
  // The cursor is yours here, not resting on the featured row: the remove
  // button shows.
  property bool removable: false
  property bool retro: false
  // True while the pointer carries this row; the panel positions it.
  property bool lifted: false
  // Whether the row's words, remove button, and pointer are built: the list
  // builds them only for rows near sight, so a long list costs little more
  // than a screenful does. Built, the row draws in the frame it is asked to.
  property bool built: true
  // Down to here in the row, the list menu lies over it: a line of words
  // that starts above this leaves out, the symbol with its remove button,
  // and the name, each on its own, so a row mostly below the menu keeps its
  // name, and a long name never shows past the menu's edge in pieces. 0
  // while the menu is shut.
  property real menuCovers: 0
  // While it moves, lifted or sliding, the row carries the card's own ground
  // under its fill, so the rows it passes never show through.
  property bool moving: false
  property color ground: "transparent"
  property real scrubX: -1
  // How much of the day line has been drawn, 0..1: a row joining the list
  // draws its line in from the left, as the hero's chart draws in (the list
  // runs it); at rest, and in every other change, the whole line.
  property real reveal: 1
  // The exchanges' calendars, for the breaks in the day line.
  property var calendars: null
  property color foreground: Commons.Color.foreground
  property color dim: Tones.dim(foreground, Commons.Color.background)
  property color dimmer: Tones.dimmer(foreground, Commons.Color.background)
  property color upColor: Commons.Color.foreground
  property color downColor: Commons.Color.urgent
  property string fontFamily: Style.font.family

  // Each click says where it was, in the scene, and whether Qt took it for
  // a double-click's second press, so the list decides whether it acts,
  // whichever row it lands on (Watchlist.clickRow).
  signal featureRequested(real x, real y, bool second)
  // A right-click: this row's menu, at the pointer.
  signal menuRequested(real x, real y, bool second)
  // The remove button's press, the list asked there whether its click counts
  // (Watchlist.clickCounts), a double-click's second press asking again;
  // and its release on the button, with no drag between, which acts on that
  // answer however long the press was held.
  signal removePressed(real x, real y, bool second)
  signal removeReleased(real x, real y)
  // Ctrl-click, Apple's Control-click: this row's lists.
  signal listsRequested(real x, real y, bool second)
  // Drag positions are in the parent's coordinates, since the row itself
  // moves under the pointer.
  signal dragStarted(real y)
  signal dragMoved(real y)
  signal dragEnded()
  signal dragCanceled()

  // The day line is the quote's own drawing: it changes when the quote does,
  // never with the clock, the change mode, or another symbol's quote. A day
  // with no print leaves the cell empty: the hero alone draws its baseline.
  readonly property var geometry: quote && quote.points.length ? Chart.chartGeometry(quote, calendars) : null

  readonly property color trend: !view || view.tone === "flat" ? dim : view.tone === "up" ? upColor : downColor
  // What the feed has done for this symbol, from Figures.freshness. A failed
  // or overdue refresh is said in words on the name line, so it reads
  // without hover and without color; an aged quote during trading, or one
  // kept from an earlier session, says when it is from. Where Yahoo sends
  // nothing for any listing (`sourceDown`), the surface says so once: the
  // row says only when its price is from, or, with none, nothing.
  property var freshness: null
  property bool sourceDown: false
  readonly property var shownFreshness: sourceDown ? Figures.quietFreshness(freshness) : freshness
  readonly property bool warns: Figures.freshnessWarns(shownFreshness)
  readonly property string freshnessNote: quote ? Figures.freshnessText(shownFreshness, quote, calendars) : ""
  // An aged quote is said plainly; only a failed or overdue refresh warns
  // (`! `). The hero says the same on its listing line.
  readonly property string detail: quote
    ? (freshnessNote !== "" ? (warns ? "! " : "") + capitalize(freshnessNote) : view.name)
    : sourceDown ? "" : (status === "failed" ? "! No data for this symbol" : warns ? "! No data" : "Loading…")

  // Sentence case, a day's name kept a name and a zone's its capitals:
  // "As of Fri 16:00", "As of Thu 16:39 BST".
  function capitalize(text) {
    var sentence = String(text.charAt(0) + text.slice(1).toLowerCase())
    return sentence.replace(/\b(mon|tue|wed|thu|fri|sat|sun)\b/, function(day) { return day.charAt(0).toUpperCase() + day.slice(1) })
      .replace(/(\d\d:\d\d) (\S+)/, function(all, clock, zone) { return clock + " " + zone.toUpperCase() })
  }

  // Two lines, the way Apple's Stocks sets a row: symbol over name on the
  // left, price over change on the right, the day line between them.
  readonly property int sparkWidth: Style.space(72)
  readonly property int priceWidth: Style.space(96)
  readonly property int gap: Style.space(10)
  readonly property int inset: Style.space(4)

  height: Style.space(40)
  radius: retro ? 0 : Style.cornerRadius
  // The fill the row's state asks for; the row eases to it, and the
  // retro stems are weighed against it over the ground, so a featured or
  // cursor row's two colours still read alike.
  readonly property color fill: lifted ? Style.pressedFillFor(foreground, Commons.Color.accent)
    : featuredRow ? Style.selectedFillFor(foreground, Commons.Color.accent)
    : cursor ? Style.hoverFillFor(foreground, Commons.Color.accent) : "transparent"
  color: fill
  border.width: lifted ? 1 : 0
  border.color: Style.normalBorderFor(foreground, Commons.Color.accent)

  // The shell's own speed (CursorSurface), so the fill keeps up with the
  // pointer.
  Behavior on color { ColorAnimation { duration: 60 } }

  // Under the fill, and there at once: the fill fades, the ground must not.
  Rectangle {
    objectName: "rowGround"
    z: -1
    anchors.fill: parent
    radius: row.radius
    visible: row.moving
    color: row.ground
  }

  // The day line, built whatever the row's distance from sight: a canvas
  // built as its row comes into sight would draw a frame or two after the
  // row's words. Only the shown look is built: `s` builds the other, which
  // draws before that frame.
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
      // The hero's rule at row size: up above the baseline, down below it.
      up: row.view ? row.view.dayUp : null
      upColor: row.upColor
      downColor: row.downColor
      lineColor: row.dim
      baselineColor: row.dimmer
      cursorX: row.scrubX
      reveal: row.reveal
    }
  }

  // The hero histogram at a finer pitch, so a row and the hero are one
  // drawing at two sizes.
  Component {
    id: cellsLine
    PixelChart {
      objectName: "rowCells"
      geometry: row.geometry
      // Unknown direction draws dim, the way the hero's chart does.
      up: row.view ? row.view.dayUp : null
      upColor: row.upColor
      downColor: row.downColor
      baselineColor: row.dimmer
      hairlineColor: row.foreground
      ground: Qt.tint(row.ground, row.fill)
      pixel: 2
      gap: 1
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
          width: row.width - x - row.priceWidth - row.gap * 2 - row.sparkWidth - row.gap
          textFormat: Text.PlainText
          text: row.detail
          color: row.warns ? row.foreground : row.dim
          font.family: row.fontFamily
          font.pixelSize: Style.font.bodySmall
          font.bold: row.warns
          elide: Text.ElideRight
        }

        // The shell's row action (PanelActionButton, as Bluetooth's Forget): dim
        // at rest, the foreground under the pointer, never the urgent colour,
        // which here means a falling price. It sits just after the symbol it
        // removes, on its line, so nothing on the row moves or narrows for it,
        // and it has no tip: the × says what it does, and a tip there would
        // cover the next row. The row's own pointer handles it, so a press
        // there and a move still lift the row, and a double-click is one
        // removal (Watchlist.clickRow); a left click that starts and ends on
        // it removes rather than features, and one that starts on it and ends
        // off it does nothing.
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

          // The shell's 22 px target; its fill 2 px inside it, so on a 40 px row
          // it keeps clear of the row's top edge.
          Rectangle {
            objectName: "rowRemoveFill"
            anchors.fill: parent
            anchors.margins: Style.space(2)
            radius: row.retro ? 0 : Style.cornerRadius
            color: removeButton.hovered && mouse.pressed && mouse.pressedOnRemove && !mouse.dragged ? Style.pressedFillFor(row.foreground, Commons.Color.accent)
              : removeButton.hovered ? Style.hoverFillFor(row.foreground, Commons.Color.accent) : "transparent"
            Behavior on color { ColorAnimation { duration: 60 } }
          }

          // Smooth: a plain ×, the weight of the symbol beside it.
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

          // Retro: an × in the rows' own 2 px cells, built only in that look.
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

        // Press and move a few pixels to lift the row; a plain click features it.
        // The list never steals the press, so the wheel is how it scrolls.
        MouseArea {
          id: mouse
          anchors.fill: parent
          hoverEnabled: true
          preventStealing: true
          acceptedButtons: Qt.LeftButton | Qt.RightButton
          cursorShape: row.lifted ? Qt.ClosedHandCursor : Qt.PointingHandCursor

          property real pressY: -1
          property bool dragged: false
          // The press began on the remove button: only a release on it with no
          // drag between removes, whatever Qt calls the press (a double-click's
          // second press acts at mouse-down).
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
          // A double-click is one click: its second would land on whatever took
          // the first one's place, a row sliding up or the rows back from search.
          // The list says whether it acts: only after the wheel or a key between.
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
