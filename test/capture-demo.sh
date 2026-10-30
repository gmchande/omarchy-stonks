#!/usr/bin/env bash
# Saves the endpoints' answers for the demo watchlist (test/demo.json)
# at this moment, into the saved answers' moments/demo-<YYYY-MM-DD-HHMM>,
# New York time, for the README's pictures: Yahoo's 1D chart for each
# listing, and its two days beside it in 2d/, since Stonks asks for two
# for a coin, and for a stock before its day's first print (render.qml
# reads whichever Stonks asks for); and for the US listings Robinhood's
# span=day prints and instruments. Commit the new folder in the saved
# answers' repository; test/qml/readme.sh renders from it once its `moment`
# names it. By hand: it calls the network.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
fixtures=$(test/fixtures-dir.sh)
moment=$(TZ=America/New_York date +%Y-%m-%d-%H%M)
final="$fixtures/moments/demo-$moment"
[ ! -e "$final" ] || { echo "$final exists" >&2; exit 1; }
# Saved into a scratch folder, and named a capture only once every answer
# is in: a failed fetch leaves nothing behind.
dir=$(mktemp -d "$fixtures/moments/.capture-XXXX")
trap 'rm -rf "$dir"' EXIT
ua="Mozilla/5.0 (Omarchy Stonks)"
listed=$(jq -r '.symbols[]' test/demo.json)
get() { curl -fsS --compressed --max-time 15 -A "$ua" "$1" || return; sleep 2; }
mkdir "$dir/2d"
for s in $listed; do
  file=$(tr 'A-Z' 'a-z' <<< "${s#^}")
  chart="https://query1.finance.yahoo.com/v8/finance/chart/$(jq -rn --arg s "$s" '$s|@uri')"
  get "$chart?range=1d&interval=5m&includePrePost=true" > "$dir/$file.json"
  get "$chart?range=2d&interval=5m&includePrePost=true" > "$dir/2d/$file.json"
done
# Robinhood's US symbols: the listings with no suffix, an index or a coin.
us=$(for s in $listed; do [[ $s == *.* || $s == ^* || $s == *-* ]] || echo "$s"; done | paste -sd,)
get "https://api.robinhood.com/marketdata/historicals/?symbols=$us&interval=5minute&span=day&bounds=24_5" \
  | jq -c '{ results: [.results[] | { symbol, historicals: [.historicals[] | { begins_at, close_price, volume, session, interpolated }] }] }' \
  > "$dir/robinhood-day.json"
get "https://api.robinhood.com/instruments/?symbols=$us" \
  | jq -c '{ next: null, results: [.results[] | { symbol, all_day_tradability }] }' > "$dir/robinhood-instruments.json"
cat > "$dir/.url" << EOF
# fetched, not derived: the endpoints' answers at $(TZ=America/New_York date -Iseconds) (New York)
# Yahoo: range=1d&interval=5m&includePrePost=true for each symbol, and range=2d in 2d/, fetched in turn two seconds apart
# Robinhood (symbols=$us&interval=5minute&span=day&bounds=24_5)
# Robinhood's bars keep begins_at, close_price, volume, session, and interpolated.
# Robinhood instruments (?symbols=$us), the same minute: symbol and all_day_tradability kept.
# The demo watchlist (test/demo.json), for the README's pictures.
# Saved by test/capture-demo.sh.
EOF
mv "$dir/.url" "$final.url"
mv "$dir" "$final"
echo "saved $final"
