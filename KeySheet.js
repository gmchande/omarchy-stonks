.pragma library

// The keys a person uses every day, the same in every order and on both
// surfaces. The README has every key. Each line fits the panel's
// half column.
function sheet() {
  return {
    groups: [
      { title: "Rows", rows: [
        { key: "↑ ↓", does: "Move the selection" },
        { key: "⏎", does: "Show the row's chart" },
        { key: "a /", does: "Find or add a symbol" },
        { key: "Del ⌫", does: "Remove the selected row" },
        { key: "Ctrl+Z", does: "Undo a removal" }
      ]},
      { title: "Chart", rows: [
        { key: "← →", does: "Move along the chart" },
        { key: "[ ]", does: "Change the range" },
        { key: "s", does: "Switch smooth and retro" }
      ]},
      { title: "Lists", rows: [
        { key: "w", does: "Open the list menu" },
        { key: "o", does: "Change the order" }
      ]}
    ]
  }
}
