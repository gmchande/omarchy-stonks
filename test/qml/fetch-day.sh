#!/usr/bin/env bash
# The daily totals, by hand (neither test runner starts it: it takes minutes):
# a weekday and a weekend of glances through the real Service and App on a
# clock the harness sets (fetch-day.qml), with a long list's shape, 34
# symbols. Counts every request the fake curl answered and every curl call,
# and estimates the bytes both ways from the measured sizes: a new
# connection's TLS handshake, 8.25 KB; headers, 0.8 KB on it and 0.4 KB on
# each request after; a day's chart compressed, 2.9 KB (2.4 measured
# mid-morning on 8 October, 3.5 to 3.9 for a full day); Robinhood's prints,
# 6.0 KB a listing compressed, scaled to the list's 33 listings; a history,
# 15 KB; cap and P/E, 1.5 KB; instruments, 2 KB.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
plugin_tree fetch-day.qml
patch_copy plugin/Service.qml 's/function wallSecond() { return Math.floor(Date.now() \/ 1000) }/function wallSecond() { return root.now }/'
patch_copy plugin/Service.qml 's/property int now: Math.floor(Date.now() \/ 1000)/property int now: 1791345540/'
patch_copy plugin/Service.qml '/readonly property var entries: feed.entries/a\  readonly property alias testFeed: feed'
symbols='"NEST", "KILN", "BOLT"'
for n in $(seq -w 1 29); do symbols="$symbols, \"LONG$n\""; done
symbols="$symbols, \"SPY\", \"SHOP.TO\""
printf '{ "version": 1, "symbols": [%s], "featured": "NEST", "order": "manual", "refreshIntervalSec": 60 }\n' "$symbols" \
  > "$HOME/.config/omarchy/grvc.stonks.json"
echo fetch-2026-10-07 listings-2026-10-07-1455 > "$STONKS_FAKE_STATE/overnight.set"
export QT_QPA_PLATFORM=offscreen
run_qs 1800

# day NAME: that day's requests by kind, curl calls, and bytes.
day() {
  local line from to runs_from runs_to
  line=$(rg -o "DAY $1 [0-9]+ [0-9]+ [0-9]+ [0-9]+" "$work/log") || { echo "FAIL no totals for $1"; code=1; return; }
  read -r _ _ from to runs_from runs_to <<< "$line"
  sed -n "$((from + 1)),${to}p" "$STONKS_FAKE_STATE/requests.log" > "$work/$1.requests"
  sed -n "$((runs_from + 1)),${runs_to}p" "$STONKS_FAKE_STATE/runs.log" > "$work/$1.runs"
  awk -v name="$1" '
    FNR == NR { kinds[$1]++; total++; next }
    {
      bytes += 8250 + 400
      for (i = 1; i <= NF; i++) {
        split($i, part, ":")
        k = part[1]
        bytes += 400
        if (k == "chart") bytes += 2900
        else if (k == "overnight") bytes += 33 * 6000
        else if (k == "history") bytes += 15000
        else if (k == "fundamentals") bytes += 1500
        else if (k == "instruments") bytes += 2000
        else bytes += 1000
      }
      calls++
    }
    END {
      line = sprintf("PASS %s: %d requests in %d curl calls, about %.1f MB both ways —", name, total, calls, bytes / 1e6)
      for (k in kinds) line = line " " k " " kinds[k]
      print line
    }' "$work/$1.requests" "$work/$1.runs"
}
day weekday
day weekend
finish "FETCH DAY DONE"
