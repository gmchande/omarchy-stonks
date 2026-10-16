// The launcher icon, share/grvc.stonks.svg, drawn from Stonks' mark in
// Cells.js (`markLevels`), climbing, as StonksMark draws it at icon size
// (`solid`): each column one bar at full ink, from its cap to the floor, in
// one green that reads on light and dark launchers. Two-unit columns on a
// 16-unit square, so 16, 32, and 64 px land on whole pixels.
//   bun test/mark-svg.js          rewrite share/grvc.stonks.svg
//   bun test/mark-svg.js check    fail when the file is not the mark (test/all.sh)
import { readFileSync, writeFileSync } from "node:fs"
import { join } from "node:path"
import { load } from "./load.js"

const root = join(import.meta.dir, "..")
const { markLevels } = load("Cells.js")
const target = join(root, "share/grvc.stonks.svg")

const rows = 4
const pixel = 2
const gap = 1
const levels = markLevels(rows, false)
const height = rows * (pixel + gap) - gap
const left = (16 - (levels.length * (pixel + gap) - gap)) / 2
const top = Math.floor((16 - height) / 2)

const rects = levels.map((level, i) => {
  const x = left + i * (pixel + gap)
  const y = top + level * (pixel + gap)
  return `    <rect x="${x}" y="${y}" width="${pixel}" height="${top + height - y}"/>`
})

const svg = [
  `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16" shape-rendering="crispEdges">`,
  `  <g fill="#2f9e5a">`,
  ...rects,
  `  </g>`,
  `</svg>`,
  ""
].join("\n")

if (process.argv[2] === "check") {
  if (readFileSync(target, "utf8") !== svg) {
    console.log("FAIL share/grvc.stonks.svg is not the mark: run bun test/mark-svg.js")
    process.exit(1)
  }
  console.log("PASS share/grvc.stonks.svg is the mark")
} else {
  writeFileSync(target, svg)
}
