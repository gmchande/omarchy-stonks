.import "Settings.js" as Settings

// What the key sheet shows. Knows nothing of how the keys are handled.

// The key sheet behind the header's ?: the everyday keys, grouped by what
// they touch, and the mouse in three lines. The README's table holds every key;
// the doubles and the shell's own keys are left to it, so the sheet stays
// short enough to read at a glance. J K and a row's drag show only where they
// act, on manual order.
function sheet(order) {
  var manual = Settings.normalizeOrder(order) === "manual"
  var rows = [
    { key: "↑ ↓", does: "Move the row cursor" },
    { key: "⏎", does: "Feature the cursor row" },
    { key: "1–9", does: "Feature that row" },
    { key: "a", does: "Add a symbol" },
    { key: "x", does: "Remove the cursor row" },
    { key: "u", does: "Undo a removal" }
  ]
  if (manual) rows.push({ key: "J K", does: "Reorder the cursor row" })
  return {
    groups: [
      { title: "Rows", rows: rows },
      { title: "Chart", rows: [
        { key: "← →", does: "Scrub one chart step" },
        { key: "[ ]", does: "Change the chart range" },
        { key: "p", does: "Replay the shown chart" }
      ]},
      { title: "Lists", rows: [
        { key: "w", does: "Open the list menu" },
        { key: "o", does: "Cycle the list order" },
        { key: ", .", does: "Step through the lists" }
      ]},
      { title: "Look", rows: [
        { key: "s", does: "Switch smooth and retro" },
        // The change mode is the day's: on a range the hero shows the period,
        // so c changes the rows and, on the day, the hero.
        { key: "c", does: "Cycle the day's change" },
        { key: "r", does: "Refresh quotes" }
      ]}
    ],
    mouse: { title: "Mouse", rows: [
      // Each fits one line of the popup at the shell's usual text size, so
      // the row's take two.
      { key: "pill", does: "Wheel steps · middle changes form · right opens the window" },
      { key: "row", does: "Click features it · right-click removes it" },
      { key: "", does: manual ? "Ctrl-click opens its lists · drag moves it" : "Ctrl-click opens its lists" },
      // The replay had a tooltip under the animal, which covered the line
      // naming the stock: the sheet says it instead.
      { key: "animal", does: "Click the bull or bear to replay the chart" }
    ]},
    note: "Every key is in the README"
  }
}
