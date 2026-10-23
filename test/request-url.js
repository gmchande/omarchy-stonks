// The fake's independent HTTP contract. Query order is immaterial; hosts,
// routes, symbols and vendor options are not. No product helpers are used.
export function requestUrl(raw) {
  const u = new URL(raw)
  if (u.protocol !== 'https:' || u.username || u.password || u.port || u.hash)
    throw new Error('expected an unadorned HTTPS address')
  const q = Object.fromEntries(u.searchParams)
  if ([...u.searchParams].length !== Object.keys(q).length) throw new Error('duplicate query parameter')
  const parameters = (values, variable = {}) => {
    if (Object.keys(q).sort().join() !== Object.keys({...values, ...variable}).sort().join()) throw new Error('unexpected parameters')
    for (const [k,v] of Object.entries(values)) if (q[k] !== v) throw new Error('wrong ' + k)
    for (const [k,valid] of Object.entries(variable)) if (!valid(q[k])) throw new Error('invalid ' + k)
    // The serving shell reads canonical parameter order, after validation.
    const order = ['q','symbols','range','interval','includePrePost','quotesCount','newsCount','events','includeAdjustedClose','span','bounds','type','period1','period2']
    u.search = new URLSearchParams(Object.fromEntries(order.filter(k => k in q).map(k => [k,q[k]]))).toString()
  }
  const symbol = s => !!s && !/[\s/?&#%]/u.test(s)
  const symbols = s => s.split(',').every(symbol)
  const epoch = s => /^\d+$/.test(s) && Number(s) > 0
  // A day's answer: one day, or two before a session opens.
  const days = s => s === '1d' || s === '2d'
  const chart = /^\/v8\/finance\/chart\/([^/]+)$/.exec(u.pathname)
  if (u.hostname === 'raw.githubusercontent.com') {
    if (u.pathname !== '/gmchande/omarchy-stonks/main/manifest.json' || u.search) throw new Error('wrong manifest')
  } else if (u.hostname === 'api.robinhood.com') {
    if (u.pathname === '/instruments/') parameters({}, {symbols})
    else if (u.pathname === '/marketdata/historicals/') parameters({interval:'5minute', bounds:'24_5'}, {symbols, span:s=>s === 'day' || s === 'hour'})
    else throw new Error('unknown Robinhood route')
  } else if (u.hostname === 'query2.finance.yahoo.com' && u.pathname === '/v1/finance/search') {
    parameters({newsCount:'0'}, {q:s=>s.trim().length > 0,quotesCount:epoch})
  } else if (u.hostname === 'query1.finance.yahoo.com') {
    if (chart && symbol(decodeURIComponent(chart[1]))) {
      if ('period1' in q) {
        parameters({interval:'1d'}, {period1:epoch,period2:epoch})
        if (+q.period2 <= +q.period1) throw new Error('reversed dates')
      } else if ('includeAdjustedClose' in q) {
        const intervals = {'5d':'15m','1mo':'1h','3mo':'1d','6mo':'1d',ytd:'1d','1y':'1d','2y':'1d','5y':'1wk','10y':'1wk',max:'1mo'}
        if (!(q.range in intervals)) throw new Error('unknown history range')
        parameters({range:q.range,interval:intervals[q.range],events:'div,splits',includeAdjustedClose:'true'})
      } else parameters({interval:'5m',includePrePost:'true'}, {range:days})
    } else if (u.pathname === '/v7/finance/spark') parameters({interval:'5m',includePrePost:'true'}, {symbols,range:days})
    else if (/^\/ws\/fundamentals-timeseries\/v1\/finance\/timeseries\/[^/]+$/.test(u.pathname)) {
      parameters({type:'trailingMarketCap,trailingPeRatio,trailingDilutedEPS'}, {period1:epoch,period2:epoch})
      if (+q.period2 <= +q.period1) throw new Error('reversed dates')
    } else throw new Error('unknown Yahoo route')
  } else throw new Error('unknown host')
  // Preserve the fake's symbol-list separators and symbol encoding.
  return u.toString().replace(/%2C/gi, ',')
}

if (import.meta.main) {
  for (const raw of process.argv.slice(2)) {
    try { console.log(requestUrl(raw)) }
    catch (e) {
      const {appendFileSync} = await import('node:fs')
      appendFileSync(process.env.STONKS_FAKE_STATE + '/unexpected.requests', raw + ': ' + e.message + '\n')
      process.exitCode = 2
    }
  }
}
