#!/usr/bin/env bash
# The real QuoteFeed through success, failure, retry, and recovery, answered
# by the fake curl. Needs the Wayland session, like the shell itself.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
feed_tree harness.qml QuoteFeed.qml Fetch.js Quote.js Format.js
# The copy pauses 200 ms before a retry, not 2.5 s, and says when it is
# pausing, so a step can act inside the pause instead of on the clock.
patch_copy QuoteFeed.qml 's/interval: 2500/interval: 200/'
patch_copy QuoteFeed.qml '/readonly property bool busy:/a\  readonly property alias testRetrying: retryTimer.running'
run_qs 30
logs=$(rg -c 'stonks: STRAY dropped stray buckets 2026-09-11T20:20:00.000Z' "$work/log" || true)
if [[ "$(fetched STRAY)" -eq 2 && "${logs:-0}" -eq 1 ]]; then
  echo "PASS two identical quote responses log the dropped bucket once"
else
  echo "FAIL $(fetched STRAY) identical quote responses produced ${logs:-0} dropped-bucket logs"
  code=1
fi
finish "ALL PASS"
