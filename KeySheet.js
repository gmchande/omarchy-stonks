.pragma library
.import "Settings.js" as Settings

// What the key sheet shows. Knows nothing of how the keys are handled.

// The key sheet behind the header's ?: every key, grouped by what it
// touches, then the mouse in a few lines. The README's table lists the same
// keys, in its words; where a line is too long for the popup's half column,
// the sheet says it shorter. A key shows only where it acts: ⇧↑ ⇧↓ and a
// row's drag on manual order, the order's arrow on a sorted one, and Tab in
// the popup, which steps to the bar's next panel.
function sheet(order, switchesPanels) {
  var manual = Settings.normalizeOrder(order) === "manual"
  var rows = [
    { key: "↑ ↓", does: "Move the selection" },
    { key: "⏎", does: "Show the row's chart" },
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
        { key: "← →", does: "Scrub one step" },
        { key: "[ ]", does: "Change the range" },
        { key: "p", does: "Replay the chart" },
        { key: "Ctrl+C", does: "Take a screenshot" }
      ]},
      { title: "Lists", rows: [
        { key: "l", does: "Open the list menu" },
        { key: "o", does: "Change the order" },
        { key: "O", does: "Reverse the order" }
      ]},
      { title: "Look", rows: [
        // The change mode is the day's: on a range the hero shows the period,
        // so c changes the rows and, on the day, the hero.
        { key: "c", does: "Cycle the day's change" },
        { key: "s", does: "Smooth or retro" },
        { key: "m", does: "Sound on or off" },
        { key: "r", does: "Refresh" },
        // What the footer offers: a newer Stonks's update, then the restart.
        { key: "U", does: "Update Stonks" }
      ]},
      { title: "Keys", rows: surface }
    ],
    mouse: { title: "Mouse", rows: [
      // Each fits one line of the popup at the shell's usual text size, so
      // the pill's and the row's take two.
      { key: "pill", does: "Scroll steps through your stocks · drag moves it" },
      { key: "", does: "Middle-click changes form · right-click opens the window" },
      { key: "row", does: "Click shows its chart · right-click offers to remove it" },
      { key: "", does: manual ? "Ctrl-click opens its lists · drag moves it" : "Ctrl-click opens its lists" },
      // The sort word beside the list's name: in manual order the arrow and
      // the word are one control that steps.
      { key: "order", does: manual ? "Click changes the order" : "Click changes the order · click its arrow reverses it" },
      // The replay had a tooltip under the animal, which covered the line
      // naming the stock: the sheet says it instead.
      { key: "animal", does: "Click the bull or bear to replay the chart" }
    ]}
  }
}
