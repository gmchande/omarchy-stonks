.pragma library
.import "Settings.js" as Settings

// Each line fits the panel's half column, so some say less than the
// README's table.
function sheet(order, switchesPanels) {
  var manual = Settings.normalizeOrder(order) === "manual"
  var rows = [
    { key: "↑ ↓", does: "Move the selection" },
    { key: "⏎", does: "Show the row's chart" },
    { key: "Ctrl+⏎", does: "Choose the row's lists" },
    { key: "a /", does: "Find or add a symbol" },
    { key: "Del ⌫", does: "Remove the selected row" },
    { key: "Ctrl+Z", does: "Undo a removal" }
  ]
  if (manual) rows.push({ key: "⇧↑ ⇧↓", does: "Move the row" })
  var surface = []
  if (switchesPanels) surface.push({ key: "Tab", does: "Next panel" }, { key: "⇧Tab", does: "Previous panel" })
  surface.push({ key: "?", does: "All keys" }, { key: "Esc", does: "Close" })
  return {
    groups: [
      { title: "Rows", rows: rows },
      { title: "Chart", rows: [
        { key: "← →", does: "Move along the chart" },
        { key: "[ ]", does: "Change the range" },
        { key: "p", does: "Replay the chart" },
        { key: "Ctrl+C", does: "Take a screenshot" }
      ]},
      { title: "Lists", rows: [
        { key: "w", does: "Open the list menu" },
        { key: "o", does: "Change the order" },
        { key: "O", does: "Reverse the order" }
      ]},
      { title: "Look", rows: [
        // On a range the hero shows the period: c changes it only on the day.
        { key: "c", does: "%, amount or since open" },
        { key: "s", does: "Smooth or retro" },
        { key: "m", does: "Sound on or off" },
        { key: "r", does: "Refresh" },
        // Also the restart the footer offers after an update run elsewhere.
        { key: "U", does: "Update Stonks" }
      ]},
      { title: "Keys", rows: surface }
    ],
    mouse: { title: "Mouse", rows: [
      // Each fits a line of the panel at the shell's usual text size; two
      // actions that don't fit one take a line each, never wrapping a word.
      { key: "pill", does: "Scroll steps through your stocks · drag moves it" },
      { key: "", does: "Middle-click changes how the pill looks" },
      { key: "", does: "Right-click opens the window" },
      { key: "row", does: "Click shows its chart · right-click offers to remove it" },
      { key: "", does: manual ? "Ctrl-click opens its lists · drag moves it" : "Ctrl-click opens its lists" },
      // In manual order the arrow and the word are one control.
      { key: "order", does: manual ? "Click changes the order" : "Click changes the order · click its arrow reverses it" },
      // Here, not in a tooltip, which would cover the stock's name.
      { key: "animal", does: "Click the bull or bear to replay the chart" }
    ]}
  }
}
