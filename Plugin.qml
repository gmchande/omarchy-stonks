import QtQuick

// The manifest's service entry: the data service, the theme's up and down,
// the plugin's version watch, the sounds, the window's host, and the IPC
// target, side by side, each on its own. The pills and the popup reach them
// through `serviceFor("grvc.stonks")`: the data as `service`, the colours as
// `trendColors`, the version watch as `updates`, the sounds as `sounds`, the
// window as `windowHost`, and the IPC target as `ipc`.
Item {
  id: root

  property var shell: null

  readonly property alias service: dataService
  readonly property alias updates: versionWatch
  readonly property alias trendColors: colors
  readonly property alias sounds: speaker
  readonly property alias windowHost: host
  readonly property alias ipc: target

  Service { id: dataService; screens: host }

  Updates { id: versionWatch; mainVersion: dataService.mainVersion; mainNamedAt: dataService.mainNamedAt }

  TrendColors { id: colors }

  Sounds { id: speaker; turnedOn: dataService.soundsOn; retro: dataService.retro }

  WindowHost {
    id: host
    shell: root.shell
    service: dataService
    updates: versionWatch
    sounds: speaker
    trendColors: colors
  }

  IpcTarget {
    id: target
    shell: root.shell
    service: dataService
    windowHost: host
  }
}
