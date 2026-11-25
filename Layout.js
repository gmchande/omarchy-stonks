.pragma library

// The body's heights, worked out from plain numbers, as Omarchy's
// `BorderGeometry.js` works out its border: the header, the chart, the rows
// and what opens over them, in the panel's card or the window. The body
// hands in what its pieces measure and places them by what comes back.
// Three steps, by what each reads of the body's height, since the panel's
// card and the window's least height are taken from them: `measure` reads
// none of it, `place` the window's alone, which its chart grows into, and
// `rows` the body's.

// Whole rows, at most `count`, in `space`.
function rowsHeight(count, space, rowPitch, rowGap) {
  var rows = Math.min(count, Math.floor((Math.max(0, space) + rowGap) / rowPitch))
  return rows > 0 ? rows * rowPitch - rowGap : 0
}

// `s`, in pixels unless named otherwise:
// - `screenRoom`: the height the screen leaves the panel's body, 0 in the
//   window.
// - `margins`, `groupGap`, `listMenuGap`: the gaps; `rowHeight`, `rowGap`:
//   a row's.
// - `chartHeight`: the chart's. `minChartHeight`: the window's least
//   chart, 0 in the panel.
// - `headerTitledHeight`, `headerBareHeight`: the header with its title and
//   without. `bandBesideChart`: the band under it, less its chart.
//   `footerBarHeight`, `hintRoom`: the footer's bar, and the room its hint
//   takes, 0 with no hint.
// - `named`: a named list, which keeps room for a row while empty;
//   `symbolCount`: its rows.
function measure(s) {
  var rowPitch = s.rowHeight + s.rowGap
  var threeRows = 3 * rowPitch - s.rowGap

  // The title gives way after the chart: where three rows won't fit beside
  // the least chart, the header is the status words alone. Each reads the
  // screen's room, never the card's, which fits the chart.
  var besideHeader = s.margins * 2 + s.bandBesideChart + s.footerBarHeight + s.groupGap * 3
  var leastScreenChart = Math.round(s.chartHeight / 5)
  var titled = s.screenRoom <= 0
    || besideHeader + s.headerTitledHeight + leastScreenChart + threeRows <= s.screenRoom
  var headerHeight = titled ? s.headerTitledHeight : s.headerBareHeight
  var screenChart = s.screenRoom <= 0 ? s.chartHeight
    : Math.max(leastScreenChart, Math.min(s.chartHeight, s.screenRoom - besideHeader - headerHeight - threeRows))
  // The hint gives way, after the chart, where it would leave fewer than
  // three rows.
  var hintShown = s.hintRoom > 0 && (s.screenRoom <= 0
    || besideHeader + headerHeight + screenChart + s.hintRoom + threeRows <= s.screenRoom)
  var footerHeight = (hintShown ? s.hintRoom : 0) + s.footerBarHeight

  var besideChart = s.margins * 2 + headerHeight + s.bandBesideChart + footerHeight + s.groupGap * 3
  var chartFitsSurface = s.minChartHeight > 0 && s.minChartHeight < s.chartHeight

  return {
    rowPitch: rowPitch,
    rowGap: s.rowGap,
    rowCount: s.named ? Math.max(1, s.symbolCount) : s.symbolCount,
    threeRows: threeRows,
    margins: s.margins,
    groupGap: s.groupGap,
    listMenuGap: s.listMenuGap,
    headerTitled: titled,
    headerHeight: headerHeight,
    hintShown: hintShown,
    footerHeight: footerHeight,
    bandBesideChart: s.bandBesideChart,
    besideChart: besideChart,
    chartHeight: s.chartHeight,
    minChartHeight: s.minChartHeight,
    chartFitsSurface: chartFitsSurface,
    screenChart: screenChart,
    // Counted from the rows, not the chart's give: at a larger text size
    // each rounds on its own (275 less 170 is not two 53 px rows).
    smallestHeight: chartFitsSurface ? besideChart + s.minChartHeight + threeRows
      : besideChart + s.chartHeight + s.rowHeight
  }
}

// `m` from `measure`, with the chart in a window whose body is
// `windowHeight` high, 0 in the panel, and what stands under it. The
// window's chart is sized from the window and the chrome beside it, never
// the list or itself, so a list switch moves nothing: it takes the spare
// height past whole rows, and gives way first as the window gets short, so
// three rows still show.
function place(m, windowHeight) {
  var room = windowHeight - m.besideChart - m.chartHeight
  var chart = !m.chartFitsSurface ? m.screenChart
    : room < m.threeRows ? m.chartHeight - Math.min(m.chartHeight - m.minChartHeight, m.threeRows - room)
    : m.chartHeight + room - rowsHeight(Infinity, room, m.rowPitch, m.rowGap)
  return Object.assign({}, m, {
    drawnChartHeight: chart,
    bandHeight: m.bandBesideChart + chart,
    chromeHeight: m.besideChart + chart,
    listMenuTop: m.margins + m.headerHeight + m.groupGap + m.bandBesideChart + chart + m.listMenuGap,
    // The panel's menu ends one gap above the footer, which stays in sight
    // under it; the window's may reach the margin.
    listMenuBelow: m.margins + (m.chartFitsSurface ? 0 : m.groupGap + m.footerHeight)
  })
}

// The rows' heights in a body `height` high, for `p` from `place`: the
// rows shown, those in sight, and the room the list menu has. The rows'
// sight is measured at `rowsRoom`, the most the panel's card gives the
// body, whatever the card has shrunk to for the key sheet or a view; 0 in
// the window.
function rows(p, height, rowsRoom) {
  var wholeRows = function(space) { return rowsHeight(p.rowCount, space - p.chromeHeight, p.rowPitch, p.rowGap) }
  var listHeight = wholeRows(height)
  return {
    listHeight: listHeight,
    sightHeight: rowsRoom > 0 ? wholeRows(rowsRoom) : listHeight,
    listMenuRoom: height - p.listMenuTop - p.listMenuBelow
  }
}

// The body's height under `maxHeight`, for `m` from `place` and what is
// open over the rows: `help`, `lists`, `search` or `menu`, each with the
// height of its content (`helpHeight`, `listsHeight`, `searchHeight`, and
// `menuHeight` and `menuLeast`, the least the menu shows).
function fittedHeight(m, open, maxHeight) {
  var whole = m.chromeHeight + rowsHeight(m.rowCount, maxHeight - m.chromeHeight, m.rowPitch, m.rowGap)
  // The sheet keeps the rows' height, so opening it moves nothing, and grows
  // the panel only past rows shorter than itself.
  if (open.help) return Math.max(whole, Math.min(maxHeight, m.margins * 2 + m.headerHeight + m.groupGap + open.helpHeight))
  var overBand = m.margins * 2 + m.headerHeight + m.bandHeight + m.groupGap * 2
  var menuEnd = m.listMenuTop + m.groupGap + m.footerHeight + m.margins
  var view = open.lists ? overBand + open.listsHeight
    : open.search ? overBand + open.searchHeight
    : open.menu ? menuEnd + open.menuHeight : 0
  var least = open.menu ? Math.min(maxHeight, menuEnd + open.menuLeast) : 0
  return Math.max(whole, least, Math.min(m.chromeHeight + rowsHeight(Infinity, maxHeight - m.chromeHeight, m.rowPitch, m.rowGap), view))
}
