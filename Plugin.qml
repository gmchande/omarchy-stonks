pragma ComponentBehavior: Bound

import QtQuick

// The manifest's service entry. The pills and the panel reach its parts
// through `serviceFor(id)`. Its id and name are the manifest's, which the
// shell hands it just after making it: from the id come the lists file, the
// cache folder, the IPC target and the update command, and from the name the
// window's title, so two copies never share one. Until the manifest is here,
// no part touches the lists file or the cache, or answers IPC.
Item {
  id: root

  property var shell: null
  property var manifest: null
  readonly property string pluginId: manifest && manifest.id ? String(manifest.id) : ""
  readonly property string name: manifest && manifest.name ? String(manifest.name) : ""

  readonly property alias service: dataService
  readonly property alias updates: versionWatch
  readonly property alias trendColors: colors
  readonly property alias sounds: speaker
  readonly property alias camera: shutter
  readonly property alias windowHost: host
  readonly property alias ipc: target

  Service {
    id: dataService
    pluginId: root.pluginId
    screens: host
    updatable: versionWatch.updatable
  }

  Updates { id: versionWatch; pluginId: root.pluginId; mainVersion: dataService.mainVersion }

  TrendColors { id: colors }

  Sounds {
    id: speaker
    turnedOn: dataService.soundsOn
    retro: dataService.retro
    files: dataService.files
  }

  Bell { service: dataService; sounds: speaker }

  Camera { id: shutter }

  WindowHost {
    id: host
    shell: root.shell
    pluginId: root.pluginId
    name: root.name
    service: dataService
    updates: versionWatch
    sounds: speaker
    camera: shutter
    trendColors: colors
  }

  IpcTarget {
    id: target
    shell: root.shell
    pluginId: root.pluginId
    service: dataService
    windowHost: host
  }
}
