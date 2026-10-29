import QtQuick
import Quickshell.Io
import qs.Commons as Commons
import "Tones.js" as Tones
// Up and down, from the current theme: its green and the shell's urgent, its
// red, or Stonks' own pair where the two are no pair (`Tones.trend`). Each
// surface asks for its own ground, as a light bar under a dark panel takes
// the other pair. The shell's Color keeps only five roles, so the green is
// read from the theme's colors.toml here.
Item {
  id: root

  // The green as colors.toml spells it, "" when the theme has none.
  property string green: ""

  function upOn(ground) { return Tones.trend(green, Commons.Color.urgent, ground).up }
  function downOn(ground) { return Tones.trend(green, Commons.Color.urgent, ground).down }

  // A theme switch puts the theme's files in place and then hands the shell
  // its palette and its shell.toml (`Color.loadColors`, `Color.loadShell`),
  // so either is when the file is read again. The shell reassigns its values
  // on every theme applied, so a theme whose foreground, accent, and red
  // match the last one's is read too.
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
