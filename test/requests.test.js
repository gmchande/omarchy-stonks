import {test, expect} from 'bun:test'
import {mkdtempSync, readFileSync, rmSync, mkdirSync, writeFileSync, chmodSync, existsSync} from 'node:fs'
import {tmpdir} from 'node:os'
import {join} from 'node:path'
// Invoke the actual fake executable: a helper that validates addresses but
// is never called by curl would leave the harnesses blind.
test('fake curl rejects a wrong host, route or vendor query and records it', () => {
  const dir = mkdtempSync(join(tmpdir(), 'stonks-url-'))
  try {
    const state = join(dir,'state'), fixtures = join(dir,'fixtures')
    mkdirSync(state); mkdirSync(fixtures)
    writeFileSync(join(fixtures,'aapl.json'), '{"chart":{"result":[{"meta":{"symbol":"AAPL"}}]}}')
    const call = (url, env = {}) => Bun.spawnSync(['bash',join(import.meta.dir,'qml/bin/curl'),url], {
      env:{...process.env,STONKS_FAKE_STATE:state,STONKS_FIXTURES:fixtures,...env}, stdout:'pipe',stderr:'pipe'
    })
    const correct = 'https://query1.finance.yahoo.com/v8/finance/chart/AAPL?range=1d&interval=5m&includePrePost=true'
    const got = call(correct)
    expect(got.exitCode).toBe(0)
    expect(JSON.parse(got.stdout.toString()).chart.result[0].meta.symbol).toBe('AAPL')
    expect(call(correct.replace('range=1d&interval=5m','interval=5m&range=1d')).stdout.toString()).toBe(got.stdout.toString())
    for (const bad of [correct.replace('query1.finance.yahoo.com','not-yahoo.invalid'), correct.replace('/v8/','/v9/'),
      correct.replace('range=1d','range=nonsense'),correct.replace('interval=5m','interval=1h'),correct.replace('includePrePost=true','includePrePost=false'),
      correct+'&range=1d',correct+'&unknown=true']) {
      expect(call(bad).exitCode, bad).not.toBe(0)
      expect(existsSync(join(state,'unexpected.requests'))).toBe(true)
      expect(readFileSync(join(state,'unexpected.requests'),'utf8')).toContain(bad)
    }
    rmSync(join(state,'unexpected.requests'))
    const bin=join(dir,'bin'); mkdirSync(bin)
    writeFileSync(join(bin,'bun'),'#!/usr/bin/env bash\nexit 2\n'); chmodSync(join(bin,'bun'),0o755)
    expect(call(correct,{PATH:bin+':'+process.env.PATH}).exitCode).not.toBe(0)
    expect(existsSync(join(state,'unexpected.requests'))).toBe(true)
    expect(readFileSync(join(state,'unexpected.requests'),'utf8')).toContain('validator failed: '+correct)
  } finally { rmSync(dir,{recursive:true,force:true}) }
})
