import QtQuick
import "Market.js" as Market
// The market's bell: as the clock passes the regular open or close of the
// stock you last looked at, once each a day, never late, while sounds and a
// screen are on. It is the one sound you didn't cause, so it says one true
// thing and cheers nothing: the market opened, or closed.
Item {
  id: root

  property var service: null
  property var sounds: null
  // Where Stonks started, then each step on. A clock set back isn't heard until
  // it passes this again, so no bell rings twice.
  property int heardAt: 0
  Component.onCompleted: if (service) heardAt = service.now
  // Asked as the bell is due, and again as Sounds' check ends up to 7 s
  // later: every screen may have gone off meanwhile.
  readonly property bool wanted: !!sounds && sounds.turnedOn && !service.screensOff

  Connections {
    target: root.service
    function onNowChanged() {
      var before = root.heardAt
      if (root.service.now <= before) return
      root.heardAt = root.service.now
      if (!root.wanted) return
      var quote = root.service.quotes[root.service.featuredSymbol]
      if (Market.bellBetween(quote, before, root.service.now, root.service.calendars) !== "")
        root.sounds.ring(function() { return root.wanted })
    }
  }
}
