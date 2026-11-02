import QtQuick
import Quickshell.Io
import qs.Commons as Commons
import "Tones.js" as Tones
// Up and down for a surface's own ground (`Tones.trend`), as a light bar under
// a dark panel takes the other pair. The shell's Color keeps only five roles,
// so the green is read from the theme's colors.toml here.
Item {
  id: root

  // As colors.toml spells it, "" when the theme has none.
  property string green: ""

  function upOn(ground) { return Tones.trend(green, Commons.Color.urgent, ground).up }
  function downOn(ground) { return Tones.trend(green, Commons.Color.urgent, ground).down }

  // A theme switch puts the theme's files in place before it hands the shell
  // its palette and shell.toml (`Color.loadColors`, `Color.loadShell`), so
  // either is the cue to read the file again. The shell reassigns its values
  // on every theme applied, so a theme whose colours match the last one's is
  // read too.
  FileView {
    id: colors
    path: Commons.Color.currentThemePath + "/colors.toml"
    printErrors: false
    onLoaded: root.green = Tones.themeColor(text(), ["green", "color2"])
    onLoadFailed: root.green = ""
  }

  Connections {
    target: Commons.Color
    function onForegroundChanged() { colors.reload() }
    function onAccentChanged() { colors.reload() }
    function onUrgentChanged() { colors.reload() }
    function onShellValuesChanged() { colors.reload() }
  }
}
