.pragma library
.import "Settings.js" as Settings

// The key sheet behind the header's ?: every key, grouped by what it
// touches, then the mouse in a few lines. The README's table lists the same
// keys, in its words; where a line is too long for the panel's half column,
// the sheet says it shorter. A key shows only where it acts: ⇧↑ ⇧↓ and a
// row's drag on manual order, the order's arrow on a sorted one, and Tab in
// the panel, which steps to the next widget's panel. Knows nothing of how the
// keys are handled.
function sheet(order, switchesPanels) {
  var manual = Settings.normalizeOrder(order) === "manual"
  var rows = [
    { key: "↑ ↓", does: "Move the selection" },
    { key: "⏎", does: "Show the row's chart" },
    { key: "Ctrl+⏎", does: "Choose the row's lists" },
    { key: "a", does: "Add a symbol" },
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
        // The change mode is the day's: on a range the hero shows the period,
        // so c changes the rows and, on the day, the hero.
        { key: "c", does: "Show the change in %, price or since the open" },
        { key: "s", does: "Smooth or retro" },
        { key: "m", does: "Sound on or off" },
        { key: "r", does: "Refresh" },
        // What the footer offers: a newer Stonks's update, which restarts
        // the shell, or after an update run elsewhere, the restart.
        { key: "U", does: "Update Stonks" }
      ]},
      { title: "Keys", rows: surface }
    ],
    mouse: { title: "Mouse", rows: [
      // Each fits one line of the panel at the shell's usual text size, so
      // the pill's take three and the row's two; two actions that wouldn't
      // fit one line take one each, never wrapping a word alone.
      { key: "pill", does: "Scroll steps through your stocks · drag moves it" },
      { key: "", does: "Middle-click changes how the pill looks" },
      { key: "", does: "Right-click opens the window" },
      { key: "row", does: "Click shows its chart · right-click offers to remove it" },
      { key: "", does: manual ? "Ctrl-click opens its lists · drag moves it" : "Ctrl-click opens its lists" },
      // The sort word beside the list's name: in manual order the arrow and
      // the word are one control that steps.
      { key: "order", does: manual ? "Click changes the order" : "Click changes the order · click its arrow reverses it" },
      // Said here, not in a tooltip under the animal, which would cover the
      // line naming the stock.
      { key: "animal", does: "Click the bull or bear to replay the chart" }
    ]}
  }
}
