#!/usr/bin/env bash
# The data file 1.0.0 wrote (test/data-files/1.0.0.json), loaded through the
# real Service: every list, its members, order, and direction, and the view
# the user left, back as they saved them. A later version must keep loading
# it. It holds only our own settings and reads no saved answer, so it runs on
# any clone.
#
#   data-files.sh          load the file and check what comes back
#   data-files.sh write    have the real Service make the file afresh, through
#                          its own functions, only while 1.0.0 is unreleased
saved_answers=none
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
feed_tree data-files.qml Service.qml Gate.qml QuoteFeed.qml HistoryFeed.qml FundamentalsFeed.qml AllDayFeed.qml OvernightFeed.qml Fetch.js Quote.js Format.js Market.js Overnight.js History.js Fundamentals.js Chart.js Settings.js calendars.json
file=$plugin/test/data-files/1.0.0.json
data=$HOME/.config/omarchy/grvc.stonks.json
if [ "${1:-}" = write ]; then
  # Adding five symbols in a moment, each asked for as it is added, asks
  # Yahoo for more than its budget lets through.
  export STONKS_BUDGET_EXPECTED=1
  STONKS_DATA_FILE=write run_qs 30
  (finish "DATA FILE WRITTEN") || exit 1
  mkdir -p "${file%/*}" && cp "$data" "$file" && echo "wrote test/data-files/${file##*/}"
  exit
fi
cp "$file" "$data"
run_qs 30
finish "DATA FILE LOADED"
