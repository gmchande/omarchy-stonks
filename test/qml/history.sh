#!/usr/bin/env bash
# The real HistoryFeed through caching, supersession, retry, and last-good,
# answered by the fake curl and the saved history fixtures.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
feed_tree history.qml HistoryFeed.qml Fetch.js History.js Market.js Quote.js Format.js
# The copy pauses 200 ms before a retry, not 2.5 s, and says when it is
# pausing, so a step can act inside the pause instead of on the clock.
patch_copy HistoryFeed.qml 's/interval: 2500/interval: 200/'
patch_copy HistoryFeed.qml '/readonly property bool busy:/a\  readonly property alias testRetrying: retryTimer.running'
run_qs 20
logs=$(rg -c 'stonks: HISTSTRAY 1W dropped stray buckets 2026-09-11T20:05:00.000Z, 2026-09-11T21:30:00.000Z, 2026-09-11T21:35:00.000Z' "$work/log" || true)
if [[ "$(fetched HISTSTRAY)" -eq 2 && "${logs:-0}" -eq 1 ]]; then
  echo "PASS two identical history responses log the dropped buckets once"
else
  echo "FAIL $(fetched HISTSTRAY) identical history responses produced ${logs:-0} dropped-bucket logs"
  code=1
fi
finish "ALL PASS"
