#!/usr/bin/env bash
# Makes a release's data file (test/data-files/VERSION.json) afresh, through
# the real Service's own functions, only while that release is unreleased.
# model.test.js reads every file there back, on any clone.
#
#   data-files.sh write VERSION
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ ${1:-} != write || -z ${2:-} ]]; then
  echo "usage: data-files.sh write VERSION" >&2
  exit 2
fi
if [[ $2 == 1.0.0 ]]; then
  echo "1.0.0 is immutable; model.test.js only reads it" >&2
  exit 2
fi
saved_answers=none
source "$here/lib.sh"
feed_tree data-files.qml Service.qml OwnerOnly.qml Gate.qml QuoteFeed.qml HistoryFeed.qml FundamentalsFeed.qml AllDayFeed.qml OvernightFeed.qml ReleaseFeed.qml Asks.js Fetch.js Quote.js Format.js Market.js Overnight.js History.js Fundamentals.js Figures.js Chart.js Settings.js Release.js calendars.json
data=$HOME/.config/omarchy/grvc.stonks.json
file=$plugin/test/data-files/$2.json
# Adding five symbols in a moment, each asked for as it is added, asks
# Yahoo for more than its budget lets through.
export STONKS_BUDGET_EXPECTED=1
run_qs 30
(finish "DATA FILE WRITTEN") || exit 1
mkdir -p "${file%/*}" && cp "$data" "$file" && echo "wrote test/data-files/${file##*/}"
