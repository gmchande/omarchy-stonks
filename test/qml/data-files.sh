#!/usr/bin/env bash
# Each data file a release wrote (test/data-files/VERSION.json), loaded
# through the real Service: every list, its members, order, and direction,
# and the view the user left, back as they saved them. A later version must
# keep loading every one. They hold only our own settings and read no saved
# answer, so this runs on any clone.
#
#   data-files.sh                load every file and check what comes back
#   data-files.sh VERSION        load that release's file
#   data-files.sh write VERSION  have the real Service make that release's
#                                file afresh, through its own functions, only
#                                while that release is unreleased
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ $# -eq 0 ]; then
  for file in "$here"/../data-files/*.json; do
    version=${file##*/}
    echo "-- ${version%.json}"
    bash "${BASH_SOURCE[0]}" "${version%.json}" || exit 1
  done
  exit 0
fi
saved_answers=none
source "$here/lib.sh"
feed_tree data-files.qml Service.qml OwnerOnly.qml Gate.qml QuoteFeed.qml HistoryFeed.qml FundamentalsFeed.qml AllDayFeed.qml OvernightFeed.qml ReleaseFeed.qml Fetch.js Quote.js Format.js Market.js Overnight.js History.js Fundamentals.js Chart.js Settings.js Release.js calendars.json
data=$HOME/.config/omarchy/grvc.stonks.json
if [ "$1" = write ]; then
  export STONKS_DATA_VERSION=${2:?usage: data-files.sh write VERSION}
  file=$plugin/test/data-files/$STONKS_DATA_VERSION.json
  # Adding five symbols in a moment, each asked for as it is added, asks
  # Yahoo for more than its budget lets through.
  export STONKS_BUDGET_EXPECTED=1
  STONKS_DATA_FILE=write run_qs 30
  (finish "DATA FILE WRITTEN") || exit 1
  mkdir -p "${file%/*}" && cp "$data" "$file" && echo "wrote test/data-files/${file##*/}"
  exit
fi
export STONKS_DATA_VERSION=$1
cp "$plugin/test/data-files/$1.json" "$data"
run_qs 30
finish "DATA FILE LOADED"
