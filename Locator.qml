import QtQuick
import Quickshell.Io

// Where a named control is, for the tophat's scripted journeys
// (test/tophat/journeys/): a journey then moves and clicks there through
// real input, never through a call into Stonks. Plugin.qml loads this only
// in the tophat's nested session, whose processes carry TOPHAT_RUN, so no
// owner's shell offers it. The pill's and the popup's surfaces start at the
// output's corner (the bar's top edge, the popup's full-screen overlay), so
// a rectangle here is one on the nested output too.
Item {
  id: root

  property var windowHost: null

  // Each pill hands itself over (BarWidget.qml): the service holds no pill.
  signal collect(var take)

  // The surfaces searched: each pill, its popup's body once built, and the
  // window's body while it is open.
  function surfaces() {
    var out = []
    root.collect(function(pill) {
      out.push({ surface: "pill", item: pill })
      if (pill.panel && pill.panel.body) out.push({ surface: "popup", item: pill.panel.body })
    })
    if (root.windowHost && root.windowHost.app.body) out.push({ surface: "window", item: root.windowHost.app.body })
    return out
  }

  // On screen: its window showing, it and every item around it visible and
  // not transparent, and its centre inside every item around it that clips.
  function shown(item, cx, cy) {
    if (!item.Window.window || !item.Window.window.visible) return false
    for (var node = item; node; node = node.parent) {
      if (!node.visible || node.opacity <= 0) return false
      if (node !== item && node.clip) {
        var at = node.mapFromItem(null, cx, cy)
        if (at.x < 0 || at.y < 0 || at.x > node.width || at.y > node.height) return false
      }
    }
    return true
  }

  // The words it draws, in order, its hidden parts left out.
  function words(item) {
    var out = []
    var walk = function(node) {
      if (!node.visible) return
      if (typeof node.text === "string" && node.text !== "") out.push(node.text)
      for (var i = 0; i < node.children.length; i++) walk(node.children[i])
    }
    walk(item)
    return out.join(" ")
  }

  // The symbol it belongs to: the nearest item around it that names one,
  // a row's or the chart's.
  function symbolOf(item) {
    for (var node = item; node; node = node.parent)
      if (typeof node.symbol === "string" && node.symbol !== "") return node.symbol
    return ""
  }

  function named(item, name, surface, out) {
    if (item.objectName === name) {
      var at = item.mapToItem(null, 0, 0)
      var cx = at.x + item.width / 2
      var cy = at.y + item.height / 2
      out.push({
        surface: surface,
        x: Math.round(at.x), y: Math.round(at.y),
        width: Math.round(item.width), height: Math.round(item.height),
        shown: root.shown(item, cx, cy),
        text: root.words(item),
        symbol: root.symbolOf(item)
      })
    }
    for (var i = 0; i < item.children.length; i++) named(item.children[i], name, surface, out)
  }

  IpcHandler {
    target: "grvc.stonks.tophat"

    // Every item named NAME, as a JSON list: its surface (pill, popup, or
    // window), its rectangle in that surface, whether it is on screen, the
    // words it draws, and its symbol.
    function where(name: string): string {
      var out = []
      root.surfaces().forEach(function(s) { root.named(s.item, name, s.surface, out) })
      return JSON.stringify(out)
    }
  }
}
