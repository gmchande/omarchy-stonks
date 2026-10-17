.import "Settings.js" as Settings

// What the key sheet shows. Knows nothing of how the keys are handled.

// The key sheet behind the header's ?: the everyday keys, grouped by what
// they touch, and the mouse in a few lines. The README's table holds every
// key, and its words are the sheet's: where its line is too long for the
// popup's half column, the sheet says it shorter in the same words. The
// doubles and the shell's own keys are left to the table, so the sheet stays
// short enough to read at a glance. J K, a row's drag, and the order's arrow
// show only where they act: J K and the drag on manual order, the arrow on a
// sorted one.
function sheet(order) {
  var manual = Settings.normalizeOrder(order) === "manual"
  var rows = [
    { key: "↑ ↓", does: "Move the selection" },
    { key: "⏎", does: "Show the row's chart" },
    { key: "1–9", does: "Show that row's chart" },
    { key: "a", does: "Search and add a symbol" },
    { key: "x", does: "Remove the selected row" },
    { key: "u", does: "Undo the last removal" }
  ]
  if (manual) rows.push({ key: "J K", does: "Move the row up or down" })
  return {
    groups: [
      { title: "Rows", rows: rows },
      { title: "Chart", rows: [
        { key: "← →", does: "Scrub one chart step" },
        { key: "[ ]", does: "Change the chart range" },
        { key: "p", does: "Replay the chart" }
      ]},
      { title: "Lists", rows: [
        { key: "w", does: "Open the list menu" },
        { key: "o", does: "Change the list's order" },
        { key: ", .", does: "Previous or next list" }
      ]},
      { title: "Look", rows: [
        { key: "s", does: "Switch smooth and retro" },
        // The change mode is the day's: on a range the hero shows the period,
        // so c changes the rows and, on the day, the hero.
        { key: "c", does: "Cycle the day's change" },
        { key: "r", does: "Refresh" }
      ]}
    ],
    mouse: { title: "Mouse", rows: [
      // Each fits one line of the popup at the shell's usual text size, so
      // the row's take two.
      { key: "pill", does: "Wheel steps · middle changes form · right opens the window" },
      { key: "row", does: "Click shows its chart · right-click removes it" },
      { key: "", does: manual ? "Ctrl-click opens its lists · drag moves it" : "Ctrl-click opens its lists" },
      // The sort word beside the list's name: in manual order the arrow and
      // the word are one control that steps.
      { key: "order", does: manual ? "Click changes the order" : "Click changes the order · click its arrow reverses it" },
      // The replay had a tooltip under the animal, which covered the line
      // naming the stock: the sheet says it instead.
      { key: "animal", does: "Click the bull or bear to replay the chart" }
    ]},
    note: "Every key is in the README"
  }
}
