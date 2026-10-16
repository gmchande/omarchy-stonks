import QtQuick
import Quickshell.Io

// The plugin's one IPC target, `omarchy-shell grvc.stonks <function>`, with
// or without a pill on the bar. The popup's verbs go through the shell,
// which opens the popup on the focused screen's pill.
Item {
  id: root

  property var shell: null
  property var service: null
  property var windowHost: null

  // Every pill acknowledges a refresh asked for here.
  signal refreshed()

  // Every property and signal of the handler is offered over IPC, so what
  // it is wired to lives on the item around it.
  IpcHandler {
    id: handler
    target: "grvc.stonks"

    function refresh(): void {
      if (root.service) root.service.refresh()
      root.refreshed()
    }
    function next(): void { if (root.service) root.service.featureStep(1) }
    function prev(): void { if (root.service) root.service.featureStep(-1) }

    function open(): void { if (root.shell) root.shell.summon("grvc.stonks", "{}") }
    function close(): void { if (root.shell) root.shell.hide("grvc.stonks") }
    function show(): void { handler.open() }
    function hide(): void { handler.close() }
    function toggle(): void { if (root.shell) root.shell.toggle("grvc.stonks", "{}") }

    function toggleWindow(): void { if (root.windowHost) root.windowHost.toggle() }
    function openWindow(payloadJson: string): void { if (root.windowHost) root.windowHost.open(payloadJson) }
  }
}
