#!/usr/bin/env bash
# The real QuoteFeed through success, failure, retry, and recovery, answered
# by the fake curl. Needs the Wayland session, like the shell itself.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
feed_tree quote-queue.qml QuoteFeed.qml Asks.js Fetch.js Quote.js Format.js Market.js Overnight.js History.js Fundamentals.js
# The copy pauses 200 ms before a retry, not 2.5 s, and says when it is
# pausing, so a step can act inside the pause instead of on the clock.
patch_copy QuoteFeed.qml 's/interval: 2500/interval: 200/'
patch_copy QuoteFeed.qml '/readonly property bool busy:/a\  readonly property alias testRetrying: retryTimer.running'
run_qs 30
finish "QUOTE QUEUE DONE"
