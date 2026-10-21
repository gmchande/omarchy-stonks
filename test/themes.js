// Installed palettes are review evidence, not a distribution snapshot.
import {readdirSync,existsSync,readFileSync} from 'node:fs'
import {join} from 'node:path'
import {load} from './load.js'
const M=load('Tones.js'), dir='/usr/share/omarchy/themes'
for (const name of readdirSync(dir).sort()) {
  const file=join(dir,name,'colors.toml')
  if (!existsSync(file)) continue
  const toml=readFileSync(file,'utf8'), ground=M.hexColor(M.themeColor(toml,['background','color0']))
  const red=M.hexColor(M.themeColor(toml,['red','color1'])), pair=M.trend(M.themeColor(toml,['green','color2']),red,ground)
  const colour=c=>typeof c==='string'?M.hexColor(c):c
  const contrast=[pair.up,pair.down].map(c=>M.contrast(colour(c),ground))
  console.log(`${name}: ${pair.down===red?'theme':'fallback'}; contrast ${contrast.map(n=>n.toFixed(2)).join(' / ')}`)
  if (contrast.some(n=>n<(pair.down===red?3:4.5))) process.exitCode=1
}
