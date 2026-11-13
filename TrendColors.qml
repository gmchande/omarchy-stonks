import QtQuick
import qs.Commons as Commons
import "Tones.js" as Tones
// Up and down for a surface's own ground (`Tones.trend`), as a light bar under
// a dark panel takes the other pair. The shell's Color keeps only five roles,
// so the green is read from the theme's colors.toml here (`FileRead`), at
// most 64 KiB: Omarchy's own are under 1 KB.
Item {
  id: root

  // As colors.toml spells it, "" when the theme has none.
  property string green: ""

  function upOn(ground) { return Tones.trend(green, Commons.Color.urgent, ground).up }
  function downOn(ground) { return Tones.trend(green, Commons.Color.urgent, ground).down }

  readonly property string path: Commons.Color.currentThemePath + "/colors.toml"
  function read() { colors.read(root.path, 65536) }
  FileRead {
    id: colors
    onDone: function(answer) { root.green = answer.text !== undefined ? Tones.themeColor(answer.text, ["green", "color2"]) : "" }
  }
  Component.onCompleted: root.read()
  onPathChanged: root.read()

  // A theme switch puts the theme's files in place before it hands the shell
  // its palette and shell.toml (`Color.loadColors`, `Color.loadShell`), so
  // either is the cue to read the file again. The shell reassigns its values
  // on every theme applied, so a theme whose colours match the last one's is
  // read too.
  Connections {
    target: Commons.Color
    function onForegroundChanged() { root.read() }
    function onAccentChanged() { root.read() }
    function onUrgentChanged() { root.read() }
    function onShellValuesChanged() { root.read() }
  }
}
