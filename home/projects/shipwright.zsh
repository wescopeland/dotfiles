# Shipwright, our Ship of Harkinian fork. It is built on $SWPLAY_REMOTE, in Projects/Shipwright.

# Shipwright: copy the latest packaged build (`tools/sw dist` on $SWPLAY_REMOTE), play it, then send
# the F8 notes back to the remote's notes folder. A playtest name boots straight into a place and
# hands over the controller; a path to a .sws file plays that script instead. No name opens the
# title screen. When the remote cannot be reached, the last copy is played and the notes stay here.
# SWPLAY_REMOTE is an ssh host, or a folder that stands in for the remote's home (for a local test).
# Usage: swplay [field | field-dusk | path/to/script.sws]
swplay() {
  local remote="${SWPLAY_REMOTE-server-mbp@server-mbp}"
  local root="${SWPLAY_DIR:-$HOME/.cache/swplay}"
  # The game's own home, apart from any other Ship of Harkinian on this Mac, so no older .o2r there
  # is loaded in place of the copied ones. Its last folder name must be its folder in Application
  # Support, since libultraship makes that folder too.
  local home="${SHIP_HOME:-$HOME/Library/Application Support/swplay-shipwright}"
  local game="$root/dist" sep=":"
  [[ "$remote" == /* ]] && sep="/"

  mkdir -p "$game" "$home"
  if [ -n "$remote" ]; then
    # macOS's own rsync, whatever else is on PATH: the remote path quoting below is made for it.
    /usr/bin/rsync -a --delete --partial "$remote$sep""Projects/Shipwright/dist/" "$game/" \
      || echo "swplay: could not copy the build from $remote, so the last copy plays"
  fi
  if [ ! -x "$game/soh-macos" ]; then
    echo "swplay: no build in $game; run tools/sw dist on the remote first"
    return 1
  fi

  local need have
  need=$(sed -n 's/.*"min_macos": "\([0-9]*\).*/\1/p' "$game/manifest.json")
  have=$(sw_vers -productVersion | cut -d. -f1)
  if [ -n "$need" ] && [ "$have" -lt "$need" ]; then
    echo "swplay: this build needs macOS $need or later, and this Mac runs $(sw_vers -productVersion)"
    return 1
  fi
  sed -n 's/.*"commit": "\(.\{9\}\).*/swplay: build \1/p; s/.*"subject": "\(.*\)",/  \1/p' "$game/manifest.json"

  local script=""
  if [ -n "$1" ]; then
    script="$game/playtest/$1.sws"
    [[ "$1" == *.sws ]] && script="${1:A}"
    if [ ! -f "$script" ]; then
      echo "swplay: no playtest named $1 (have: $(ls "$game/playtest" | sed 's/\.sws$//' | tr '\n' ' '))"
      return 1
    fi
  fi

  rm -rf "$root/run"
  (cd "$game" && SHIP_HOME="$home" SW_SCRIPT="$script" SW_RESULTS="$root/run" ./soh-macos) >"$root/log.txt" 2>&1
  if [ -n "$script" ] && ! grep -q '"handover": true' "$root/run/result.json" 2>/dev/null; then
    echo "swplay: the playtest ended before it handed over the controller; see $root/log.txt"
  fi

  [ -z "$remote" ] || [ ! -d "$home/notes" ] && return 0
  local notes="Library/Application Support/com.shipofharkinian.soh/notes/"
  if [ "$sep" = "/" ]; then
    mkdir -p "$remote/$notes"
  else
    # macOS's rsync hands a remote path to the remote shell unquoted, so its spaces are escaped.
    notes="${notes// /\\ }"
  fi
  /usr/bin/rsync -a "$home/notes/" "$remote$sep$notes" && echo "swplay: notes sent to $remote"
}
