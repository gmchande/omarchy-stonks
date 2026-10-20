// The launcher icon, share/grvc.stonks.svg: Stonks' logo, the bull from
// Cells.js (`BULL_SPRITE`) trimmed to its lit rows and columns, one unit a
// cell, in Tokyo Night's green on its ground, on a 24-unit tile two cells
// in from each side and five down, so its heavier face sits below the
// middle. Whole units, so 24, 48, and 96 px land on whole pixels.
//   bun test/launcher-icon.js          rewrite share/grvc.stonks.svg
//   bun test/launcher-icon.js check    fail when the file is not the logo (test/all.sh)
import { readFileSync, writeFileSync } from "node:fs"
import { join } from "node:path"
import { load } from "./load.js"

const root = join(import.meta.dir, "..")
const { BULL_SPRITE } = load("Cells.js")
const target = join(root, "share/grvc.stonks.svg")

const tile = 24
const lit = BULL_SPRITE.filter(row => row.includes("#"))
const left = Math.min(...lit.map(row => row.indexOf("#")))
const right = Math.max(...lit.map(row => row.lastIndexOf("#")))
const bull = lit.map(row => row.slice(left, right + 1))

// Each run of lit cells in a row is one rect.
let rects = ""
bull.forEach((row, y) => {
  for (let x = 0; x < row.length;) {
    if (row[x] !== "#") { x++; continue }
    let end = x
    while (end < row.length && row[end] === "#") end++
    rects += `<rect x="${2 + x}" y="${5 + y}" width="${end - x}" height="1"/>`
    x = end
  }
})

const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="${tile}" height="${tile}" viewBox="0 0 ${tile} ${tile}" shape-rendering="crispEdges">`
  + `<title>Stonks</title><rect width="${tile}" height="${tile}" fill="#1a1b26"/><g fill="#9ece6a">${rects}</g></svg>\n`

if (process.argv[2] === "check") {
  if (readFileSync(target, "utf8") !== svg) {
    console.log("FAIL share/grvc.stonks.svg is not the logo: run bun test/launcher-icon.js")
    process.exit(1)
  }
  console.log("PASS share/grvc.stonks.svg is the logo")
} else {
  writeFileSync(target, svg)
}
