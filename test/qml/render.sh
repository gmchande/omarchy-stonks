#!/usr/bin/env bash
# Renders StonksBody offscreen from fixtures. Quickshell only loads QML from
# inside its config folder, so a temporary one is assembled from copies.
# Usage: test/qml/render.sh [state or pattern ...]
#        test/qml/render.sh --part I/N
# With no state named, every state below. A name with *, ?, or [ is a
# pattern over them ('popup-lists-*'); any other name is rendered as given,
# such as a saved moment the list leaves out. --part I/N renders every Nth
# state from the Ith, so N runs side by side render every state once
# (test/review.sh).
if [ "${1:-}" = --anchors ]; then
  saved_answers=none
  source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
  plugin_tree popup-anchor.qml
  patch_copy plugin/Panel.qml 's/open: root.opened/open: false/'
  patch_copy plugin/Panel.qml '/readonly property int panelWidth:/a\  readonly property alias testCard: panel\n  readonly property alias testHeldAnchor: heldAnchor'
  # A fixed screen for the unmapped placement specimen; the installed
  # KeyboardPanel still computes its actual anchor, origin and clamping.
  rm "$root/Ui"
  cp -r /usr/share/omarchy/shell/Ui "$root/Ui"
  patch_copy Ui/KeyboardPanel.qml 's/readonly property real screenW: screen ? screen.width : 0/readonly property real screenW: 1000/; s/readonly property real screenH: screen ? screen.height : 0/readonly property real screenH: 900/'
  patch_copy Ui/KeyboardPanel.qml 's/readonly property var anchorWindow: /property var anchorWindow: /'
  patch_copy plugin/HeldAnchor.qml 's/readonly property var barWindow: /property var barWindow: /'
  export QT_QPA_PLATFORM=wayland
  run_qs 15
  sed -n 's/^.*qml: ANCHOR POSES //p' "$work/log" > "$2"
  [ -s "$2" ] || { echo "FAIL no anchor poses"; code=1; }
  finish "ANCHOR DONE"
fi
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
out="${STONKS_VISUAL_DIR:-$plugin/out/render}"
mkdir -p "$out"
plugin_tree render.qml
frame_tools
# The pill sheet's pills load no popup: the offscreen platform has no popup
# window to put one in, and no render shows one.
patch_copy plugin/BarWidget.qml '/id: panelLoader/,/source:/s/active: true/active: false/'

export QT_QPA_PLATFORM=offscreen
export STONKS_VISUAL_CALENDARS="$plugin/calendars.json"

# every_state: every state the kit renders, in order.
every_state() (
  states="window-help-smooth window-help-retro popup-help-smooth popup-help-retro popup-help-sorted-smooth popup-help-sorted-retro popup-holiday-retro popup-price4-solo-smooth popup-price4-solo-retro popup-price5-stack-smooth popup-price5-stack-retro popup-nest-1d-smooth popup-nest-1d-retro popup-history-failed popup-history-loading popup-history-1w-smooth popup-history-1w-retro popup-history-1m-smooth popup-history-1m-retro popup-history-1y-smooth popup-history-1y-retro popup-history-all-smooth popup-history-all-retro loading failed aged history-scrub history-empty-loading history-sparse sprite-candidates popup-search-smooth popup-search-retro popup-search-stale-smooth popup-search-none-smooth popup-search-failed-retro popup-search-preview-smooth popup-search-preview-retro popup-search-show-smooth popup-search-show-retro min-window-smooth min-window-retro min-window-search-smooth w22-popup-smooth-aapl-1d w22-popup-retro-aapl-1d w22-window-smooth-aapl-1d w22-window-retro-aapl-1d w22-popup-smooth-aapl-5y w22-popup-retro-aapl-5y w22-window-smooth-aapl-5y w22-window-retro-aapl-5y w22-popup-smooth-spy-1d w22-popup-retro-spy-1d w22-window-smooth-spy-1d w22-window-retro-spy-1d w22-popup-smooth-shop-1d w22-popup-retro-shop-1d w22-window-smooth-shop-1d w22-window-retro-shop-1d w22-popup-smooth-shop-1y w22-popup-retro-shop-1y w22-window-smooth-shop-1y w22-window-retro-shop-1y w22-popup-smooth-mz-1d w22-popup-retro-mz-1d w22-window-smooth-mz-1d w22-window-retro-mz-1d window-1416-smooth popup-room-one-open-smooth popup-room-growth-open-retro window-room-four-five-retro popup-room-five-long-smooth popup-room-five-long-retro popup-rowstates-smooth popup-rowstates-retro popup-note-smooth popup-hint-smooth popup-hint-retro popup-notice-file-smooth popup-notice-file-retro popup-notice-update-smooth popup-notice-update-retro popup-lists-menu-retro popup-lists-named-smooth popup-lists-empty-smooth popup-lists-empty-retro popup-lists-long-retro popup-lists-manage-smooth popup-lists-manage-retro popup-lists-symbol-smooth popup-lists-symbol-retro popup-lists-rename-smooth popup-lists-confirm-retro window-lists-manage-smooth window-lists-symbol-retro popup-rowlines-smooth popup-rowlines-retro popup-52w-smooth popup-52w-retro popup-breadth-even-smooth popup-breadth-even-retro popup-order-falls-smooth popup-order-rises-smooth popup-order-falls-retro popup-order-rises-retro window-order-falls-smooth window-order-rises-smooth window-order-falls-retro window-order-rises-retro popup-overnight-night-nest-smooth popup-overnight-night-nest-retro popup-overnight-night-silk-smooth popup-overnight-night-silk-retro popup-overnight-night-reed-retro popup-overnight-day-nest-smooth popup-overnight-day-nest-retro popup-overnight-sunday-nest-smooth popup-overnight-sunday-nest-retro popup-overnight-live-ez-smooth popup-overnight-live-ez-retro popup-overnight-live-toy-smooth popup-overnight-live-toy-retro popup-overnight-live-nest-1m-smooth popup-overnight-live-nest-1m-retro popup-overnight-live-nest-1m-scrub-smooth popup-overnight-live-nest-1m-scrub-retro popup-overnight-2026-10-07-1153-nest-smooth popup-overnight-2026-10-07-1153-nest-retro popup-overnight-2026-10-06-1800-nest-smooth popup-overnight-2026-10-06-2300-nest-retro popup-overnight-2026-10-07-0005-nest-smooth popup-overnight-2026-10-07-0005-nest-retro popup-overnight-2026-10-07-0100-nest-smooth popup-overnight-2026-10-07-0100-nest-scrub-smooth popup-overnight-2026-10-07-0100-nest-scrub-retro popup-overnight-2026-10-07-0600-nest-retro popup-overnight-2026-10-03-1200-nest-smooth popup-overnight-2026-10-04-2230-nest-retro popup-fill-up-smooth popup-fill-down-smooth popup-fill-cross-smooth popup-fill-up-retro popup-fill-down-retro popup-fill-cross-retro popup-fill-up-smooth-kanagawa popup-fill-down-smooth-kanagawa popup-fill-cross-smooth-kanagawa popup-fill-up-retro-kanagawa popup-fill-down-retro-kanagawa popup-fill-cross-retro-kanagawa pill-sheet fetch-saved-smooth fetch-saved-retro fetch-overdue-smooth fetch-overdue-retro"
  # A missing regular price: the last chart trade labelled with its time.
  states="$states popup-last-trade-smooth popup-last-trade-retro"
  # A save that didn't land, and a click on it that still didn't, in both
  # looks; and at text size 16, where the save's words say less rather than
  # be cut, and the file's notice.
  states="$states popup-notice-save-smooth popup-notice-save-retro popup-notice-save-again-smooth popup-notice-save-again-retro"
  states="$states popup-notice-save-smooth-large popup-notice-save-again-smooth-large popup-notice-file-smooth-large"
  # A change made while the file can't be read, in both looks and at 16.
  states="$states popup-notice-file-edited-smooth popup-notice-file-edited-retro popup-notice-file-edited-smooth-large"
  # A removal offered back beside the add, in both looks on both surfaces,
  # and at 16 beside a named list's longer add.
  states="$states popup-undo-smooth popup-undo-retro window-undo-retro popup-undo-retro-large popup-undo-named-smooth-large popup-undo-named-retro-large"
  # The header beside the speaker and the camera at 16, in both looks: after
  # hours, the pre-market, overnight, Tokyo closed for the night, a holiday
  # abroad, and a scrub, each whole or said in less with its time kept.
  for look in smooth retro; do
    for state in overnight-2026-10-06-1800-nest sweep-2026-10-07-0600-nest sweep-2026-10-07-0100-nest sweep-2026-10-07-0600-7203.t \
      holiday-tokyo holiday-london overnight-2026-10-07-0100-nest-scrub; do
      states="$states popup-$state-$look-large"
    done
  done
  # Every listing failed, said once in the header, in the popup in both
  # looks and at 16, where the words say less rather than be cut.
  states="$states popup-failed popup-failed-smooth popup-failed-large"
  # Hover and held presses formerly judged inside the behavior flows.
  # Each uses real pointer input on the displayed control in both looks.
  for look in smooth retro; do
    for pose in join crossing dragwheel scroll endremove notefade breadth look neutral; do
      states="$states popup-motion-$pose-$look"
    done
    states="$states min-window-lists-refused-menu-$look min-window-lists-refused-manage-$look"
    for section in left center right; do
      for moment in open held next; do
        states="$states popup-anchor-$section-$moment-$look"
      done
    done
    for control in range list orderword orderarrow unit manualorder look help footer done symbol search remove; do
      states="$states popup-controls-$control-hover-$look popup-controls-$control-press-$look"
    done
    states="$states popup-controls-deadmove-hover-$look popup-controls-livemove-hover-$look popup-controls-breadth-hover-$look"
  done
  # The listing sweep: every kind of listing on 1D at each of its moments, in
  # both looks.
  # The list menu over the cursor's row in both looks on both surfaces: its
  # edge shows nothing of the row under it.
  states="$states popup-lists-menu-smooth window-lists-menu-smooth window-lists-menu-retro"
  # The buttons that took over key hints: a new list's ⏎ MAKE, and a failed
  # range's R RETRY, in both looks.
  states="$states popup-lists-naming-smooth popup-lists-naming-retro popup-history-unavailable-smooth popup-history-unavailable-retro"
  # A scrub through where the 1Y high's date rests, and the low's: the whole
  # mark stands clear of the line, in both looks and at 16.
  states="$states popup-history-1y-crossed-smooth popup-history-1y-crossed-retro popup-history-1y-crossed-retro-large"
  states="$states popup-history-1y-crossedlow-smooth popup-history-1y-crossedlow-retro"
  # A refresh the reader asked for, out: the header says so, in both looks
  # on both surfaces.
  states="$states popup-refreshing-smooth popup-refreshing-retro window-of-refreshing-smooth window-of-refreshing-retro"
  # A chart held past its quarter second, dimmed under the label naming the
  # next, on a US stock, a non-US listing, and a cryptocurrency, in both
  # looks on both surfaces.
  for kind in aapl shel-l btc-usd; do
    for look in smooth retro; do
      states="$states popup-loading-$kind-$look window-of-loading-$kind-$look"
    done
  done
  # The power-user walk's odd days in both looks: CKX's one bar and CVR's
  # none said in words on both surfaces, JPM's stray pair dropped, and LUMN
  # in cents. And the list menu over 12 lists in the popup and 30 in the
  # smallest window: whole rows, New list and Manage lists in sight.
  for look in smooth retro; do
    for symbol in ckx cvr; do
      states="$states popup-power-$symbol-$look window-power-$symbol-$look"
    done
    states="$states popup-power-jpm-$look popup-power-lumn-$look popup-lists-menu12-$look min-window-of-lists-menu30-$look"
  done
  for moment in 2026-10-07-1455 2026-10-07-0100 2026-10-07-0600 2026-10-03-1200; do
    for symbol in nest kiln spy bolt gspc btc-usd shel.l 7203.t; do
      states="$states popup-sweep-$moment-$symbol-smooth popup-sweep-$moment-$symbol-retro"
    done
  done
  # The look sweep's new listings in session, 8 October 10:54: a coin under
  # a cent, Toronto, a six-figure price, and a long symbol. `render.sh
  # popup-sweep-<moment>-<symbol>-<look>` renders any listing sweep moment,
  # and `render.sh popup-sweep-<folder>-<symbol>-<look>` any saved moment
  # whose folder is named for its minute (watch-2026-10-24-2238).
  for symbol in shib-usd ry.to brk-a brk-b; do
    states="$states popup-sweep-2026-10-08-1054-$symbol-smooth popup-sweep-2026-10-08-1054-$symbol-retro"
  done
  # A thin stock's day, fewer prints than the chart's columns, and its 3M,
  # in both looks on both surfaces: retro lights every column the line joins.
  for look in smooth retro; do
    for range in 1d 3m; do
      states="$states popup-gaps-$range-$look window-gaps-$range-$look"
    done
  done
  # The header's animal: a cold start in smooth too, and the window on an up,
  # a down, and a flat day, and a cryptocurrency, in both looks; asleep at
  # 01:00 for KILN, whose night doesn't trade, and on Saturday for an index
  # (NEST awake at 01:00 and Tokyo's lunch are among the info lines' below).
  states="$states loading-smooth failed-smooth"
  for day in 2026-10-07-1455-kiln 2026-10-07-1455-nest 2026-10-07-0100-bolt 2026-10-07-1455-btc-usd \
    2026-10-07-0100-kiln 2026-10-03-1200-gspc; do
    states="$states window-sweep-$day-smooth window-sweep-$day-retro"
  done
  # The footer's notes in both looks and both surfaces: a refusal, and a
  # move refused in a sorted order.
  for look in smooth retro; do
    states="$states popup-note-sorted-$look window-note-sorted-$look"
  done
  # A row's menu: right-clicked in a list, its two lines, on both surfaces;
  # by Shift+X in All, its one line chosen; and after a removal, search's
  # one result putting it back. In both looks.
  for look in smooth retro; do
    states="$states popup-lists-rowmenu-$look window-lists-rowmenu-$look popup-lists-rowmenuall-$look popup-search-putback-$look"
  done
  states="$states popup-note-retro"
  # A newer Stonks offered at the footer's right end: beside All's add, a
  # named list's longer one, one too long to say whole, and an undo in its
  # place; in both looks, at 16, and in the window at its smallest.
  for look in smooth retro; do
    states="$states popup-update-offer-$look popup-update-offer-$look-size-16 popup-update-offer-named-$look"
    states="$states popup-update-offer-undo-$look window-update-offer-$look min-window-update-offer-$look"
  done
  states="$states popup-update-offer-named-retro-size-16 popup-update-offer-long-smooth popup-update-offer-undo-named-retro-size-16"
  # What search leaves out, said alone (vfiax) or under the results it shows
  # (eurusd), in both looks.
  for look in smooth retro; do
    states="$states popup-search-vfiax-$look popup-search-eurusd-$look"
  done
  # The views over the rows in the window at its smallest: the scrollbar
  # says more sits below.
  for look in smooth retro; do
    for view in lists-menu lists-manage lists-symbol search; do
      states="$states min-window-$view-$look"
    done
  done
  # A cursor of your own shows its row's remove button: on a plain row in
  # the window, and on the featured row's fill in the popup (popup-rowstates
  # has it on a plain row).
  for look in smooth retro; do
    states="$states window-rowstates-$look popup-rowstates-featured-$look"
  done
  # The info lines' hard cases, in both looks, in the popup and the window
  # (window-sweep-*, and window-of-<state> for the rest): every kind of
  # listing, a coin under a cent, a six-figure price, London before its
  # session and at its 52-week high, Tokyo at lunch, pre-market, after
  # hours, overnight, a Saturday, the ranges, and a 1Y range whose first day
  # passes Yahoo's 52 weeks. AAPL with every fact is w22-*-aapl-1d.
  for look in smooth retro; do
    for sweep in own-shel.l own-7203.t 2026-10-08-1054-shel.l; do
      states="$states popup-sweep-$sweep-$look"
    done
    for sweep in own-shel.l own-7203.t 2026-10-08-1054-shel.l 2026-10-07-1455-nest 2026-10-07-1455-kiln \
      2026-10-07-1455-spy 2026-10-07-1455-gspc 2026-10-07-1455-btc-usd 2026-10-07-1455-shel.l 2026-10-08-1054-brk-a \
      2026-10-08-1054-shib-usd 2026-10-07-0600-nest 2026-10-07-0100-nest 2026-10-03-1200-nest; do
      states="$states window-sweep-$sweep-$look"
    done
    for state in overnight-2026-10-06-1800-nest history-1y history-all 52w first-day-1d first-day-1y; do
      states="$states popup-$state-$look window-of-$state-$look"
    done
  done
  # The theme gallery: Omarchy's default, and four that take Stonks' pair:
  # Catppuccin Latte, whose green is under 3:1 on its ground, Hackerman's two
  # greens, Solitude's two greys, and White on a light ground. `render.sh
  # theme-<look>-<theme>` renders any other installed theme.
  for theme in tokyo-night catppuccin-latte hackerman solitude white; do
    states="$states theme-smooth-$theme theme-retro-$theme"
  done
  # Retro, the look a new install opens in, on the two light themes at 16.
  states="$states theme-retro-catppuccin-latte-large theme-retro-white-large"
  # The calendars' longest closures, in the popup and the smallest window.
  for place in popup min-window; do
    for market in tokyo london; do
      states="$states $place-holiday-$market-smooth $place-holiday-$market-retro"
    done
  done
  # The pill at a larger and a smaller text size, as `omarchy display text
  # size 16` and `10` set it: a side bar is then 37 and 23 pixels wide.
  states="$states pill-sheet-large pill-sheet-small"
  # The screenshot the camera takes, in both looks, of every kind of
  # listing: a thin stock, an ETF, an index, Bitcoin, London after its
  # close, Tokyo at lunch, a stock after hours, scrubbed, and a range at
  # rest and scrubbed. And the header's icons at text sizes 9, 16, and 20,
  # at rest, and with sounds off and the camera lit after a shot, in the
  # popup and the window at its widest and narrowest; and the smallest
  # window's longest closures at size 20, where the header is tightest.
  for look in smooth retro; do
    for state in gaps-1d sweep-2026-10-07-1455-spy sweep-2026-10-07-1455-gspc sweep-2026-10-07-1455-btc-usd \
      sweep-2026-10-07-1455-shel.l sweep-own-7203.t overnight-2026-10-06-1800-nest history-1y; do
      states="$states share-of-$state-$look"
    done
    states="$states share-scrub-of-sweep-2026-10-07-1455-nest-$look share-scrub-of-history-1y-$look"
    # After midnight, the change measured from the close before the chart's;
    # and an intraday bar of a range scrubbed, its time's zone named.
    states="$states share-of-sweep-2026-10-07-0100-nest-$look share-scrub-of-history-1w-$look"
    for size in 9 16 20; do
      for surface in popup-sweep window-sweep min-window-of-sweep; do
        states="$states $surface-2026-10-07-1455-spy-$look-size-$size quiet-lit-$surface-2026-10-07-1455-spy-$look-size-$size"
      done
    done
    states="$states min-window-holiday-tokyo-$look-size-20 min-window-holiday-london-$look-size-20"
  done
  echo $states
)
all=$(every_state)
if [ "${1:-}" = --part ]; then
  part=${2%/*} parts=${2#*/} i=0 states=""
  for state in $all; do
    (( i++ % parts == part - 1 )) && states="$states $state"
  done
elif [ $# -eq 0 ]; then
  states=$all
else
  states=""
  for name in "$@"; do
    if [[ $name != *[*?[]* ]]; then states="$states $name"; continue; fi
    matched=""
    for state in $all; do [[ $state == $name ]] && matched="$matched $state"; done
    [ -n "$matched" ] || { echo "FAIL no state matches $name"; exit 1; }
    states="$states$matched"
  done
fi
if [[ $states == *popup-anchor-* ]]; then
  export STONKS_ANCHOR_POSES="$work/anchors.json"
  bash "$0" --anchors "$STONKS_ANCHOR_POSES"
fi
# Every render is in an installed Omarchy theme: the one the state's name
# ends with, before any -large (popup-fill-up-smooth-kanagawa,
# theme-retro-white-large), else Tokyo
# Night, the theme a fresh Omarchy install sets. It goes where the shell
# reads the current theme, so the shell's Color and the plugin's
# TrendColors both read it as they do on the desktop. A state ending -large
# has the shell's text size at 16 rather than 12, one ending -small at 10,
# and one ending -size-N at N.
# STONKS_VISUAL_THEMES names a folder of other themes' folders, each with
# its colors.toml, such as community themes, rendered as installed ones are.
themes=$( (ls /usr/share/omarchy/themes; if [ -n "${STONKS_VISUAL_THEMES:-}" ]; then ls "$STONKS_VISUAL_THEMES"; fi) | awk '{ print length, $0 }' | sort -rn | cut -d' ' -f2-)
theme_dir="$HOME/.local/state/omarchy/current"
mkdir -p "$theme_dir"
for state in $states; do
  dest="$out/$state.png"
  shot="$work/$state.png"
  theme=tokyo-night
  for t in $themes; do [[ ${state%-large} == *-"$t" ]] && { theme=$t; break; }; done
  theme_path="/usr/share/omarchy/themes/$theme"
  [ -d "$theme_path" ] || theme_path="$STONKS_VISUAL_THEMES/$theme"
  ln -sfn "$theme_path" "$theme_dir/theme"
  if [[ $state == *-large ]]; then printf '[font]\nbase-size = 16\n' > "$HOME/.config/omarchy/shell.toml"
  elif [[ $state == *-small ]]; then printf '[font]\nbase-size = 10\n' > "$HOME/.config/omarchy/shell.toml"
  elif [[ $state =~ -size-([0-9]+)$ ]]; then printf '[font]\nbase-size = %s\n' "${BASH_REMATCH[1]}" > "$HOME/.config/omarchy/shell.toml"
  else rm -f "$HOME/.config/omarchy/shell.toml"; fi
  echo "render $state ($theme) -> $dest"
  # render.qml ignores whether the save worked and exits 0 anyway, so only a
  # picture this run wrote counts. It is judged in this run's own folder,
  # where no other run's picture can stand in for it, then moved to $out.
  rm -f "$dest"
  # A sweep of a saved moment's folder (render.qml): the answers it holds,
  # each by its file's name, since QML can't list a folder.
  saved=""
  if [[ $state =~ sweep-([a-z]+-[0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]{4})- ]]; then
    for answer in "$STONKS_FIXTURES/moments/${BASH_REMATCH[1]}"/*.json; do
      name=${answer##*/}
      [[ -e $answer && $name != robinhood-* ]] && saved="$saved ${name%.json}"
    done
  fi
  STONKS_VISUAL_SAVED="$saved" STONKS_VISUAL_STATE="$state" STONKS_VISUAL_OUT="$shot" quickshell_run 15 "$work/$state.log" -p "$root"
  code=$qs_code
  # A state whose QML threw still writes a picture; the log is what tells,
  # and so is a Qt warning from the plugin's files (lib.sh).
  warnings=$(stonks_warnings "$work/$state.log")
  if [[ $code -ne 0 || ! -s $shot || -n $warnings ]] || rg -q 'FAIL[ !]|TypeError|ReferenceError|\bError:' "$work/$state.log"; then
    echo "FAIL $state (exit $code)"
    rg 'FAIL[ !]|ERROR|error:|TypeError|ReferenceError|\bError:' "$work/$state.log" | head -30 || true
    [[ -n $warnings ]] && echo "Qt warnings from the plugin's files:" && head -30 <<< "$warnings"
    tail -20 "$work/$state.log"
    exit 1
  fi
  echo "OK $state ($(wc -c < "$shot") bytes)"
  mv "$shot" "$dest"
done
