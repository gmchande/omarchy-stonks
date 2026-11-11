pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Hyprland
import Quickshell.Wayland

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
  // The desktop's Hyprland, for the screens and the window host; its input,
  // which wakes the screens; and the service's clock (`Service.wallClock`).
  // A walk hands in its own of each.
  property var hyprland: Hyprland
  property var input: idle
  property var wallClock: null
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
    wallClock: root.wallClock
    screens: displays
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

  Screens { id: displays; hyprland: root.hyprland; input: root.input; watching: host.opened }
  // Watched only while every screen is off: the key that wakes one asks
  // Hyprland again (`Screens`).
  IdleMonitor {
    id: idle
    enabled: displays.screensOff
    timeout: 1
    respectInhibitors: false
  }

  WindowHost {
    id: host
    hyprland: root.hyprland
    screens: displays
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
