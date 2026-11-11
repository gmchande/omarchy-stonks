import QtQuick
import QtQuick.Controls as Controls
import qs.Commons

// A view's scrollbar, shown while the view scrolls, its thumb at least 24 px
// long, so a long view's thumb is there to see and grab.
Controls.ScrollBar {
  property bool scrolls: false
  policy: scrolls ? Controls.ScrollBar.AlwaysOn : Controls.ScrollBar.AlwaysOff
  visible: scrolls
  minimumSize: Math.min(1, Style.space(24) / Math.max(1, availableHeight))
}
