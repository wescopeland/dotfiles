# Wardstone game. The repo is at $WARDSTONE_DIR, which defaults to $GITHUB_DIR/GameDev/wardstone.

# Wardstone: play a preset from the latest main, then send the F9 notes to
# $WSPLAY_REMOTE, where development runs. Set it empty to skip the upload.
# Usage: wsplay land_walk (no name opens the game's title screen).
wsplay() {
  local repo="${WARDSTONE_DIR:-$GITHUB_DIR/GameDev/wardstone}"
  local notes="Library/Application Support/Godot/app_userdata/Wardstone/reports/"
  git -C "$repo" pull -q --ff-only origin main || { echo "wsplay: the checkout has local changes, so it was not updated"; return 1; }
  godot --headless --path "$repo/game" --import >/dev/null 2>&1
  if [ -n "$1" ]; then
    godot --path "$repo/game" -- --playtest "$1"
  else
    godot --path "$repo/game"
  fi
  local remote="${WSPLAY_REMOTE-server-mbp@server-mbp}"
  [ -z "$remote" ] && return 0
  rsync -a "$HOME/$notes" "$remote:$notes" && echo "wsplay: notes sent to $remote"
}
