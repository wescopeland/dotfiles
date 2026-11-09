# Claims Department game. Development runs on server-mbp in ~/Projects/claims-department; the
# laptop keeps a mirror at $CLAIMS_DIR, which defaults to $GITHUB_DIR/claims-department.

# Claims Department: check the server's working copy, mirror it here, and play.
# Usage: cdplay              play alone
#        cdplay host         host a game on port 24690 for someone to join
#        cdplay join ADDR    join a host (a Tailscale name works, e.g. server-mbp)
cdplay() {
  local here="${CLAIMS_DIR:-$GITHUB_DIR/claims-department}"
  local remote="${CDPLAY_REMOTE:-server-mbp@server-mbp}"
  ssh "$remote" 'cd ~/Projects/claims-department && tools/claims check' || {
    echo "cdplay: the server's copy does not compile right now, so it was not played"
    return 1
  }
  mkdir -p "$here"
  rsync -a --delete --exclude .godot/ --exclude test-results/ \
    "${remote}:Projects/claims-department/" "$here/" || return 1
  godot --headless --path "$here/game" --import >/dev/null 2>&1
  case "$1" in
    host) godot --path "$here/game" -- --host ;;
    join) godot --path "$here/game" -- --join "${2:?cdplay: join needs an address}" ;;
    "")   godot --path "$here/game" ;;
    *)    echo "cdplay: use no argument, host, or join ADDR"; return 1 ;;
  esac
  # The host logs every paid claim; send it to the server for `tools/claims greed`.
  local log="$HOME/Library/Application Support/Godot/app_userdata/Claims Department/claims.jsonl"
  if [[ -f "$log" ]]; then
    ssh "$remote" "mkdir -p Projects/claims-department/test-results/playtests" &&
      rsync -a "$log" "${remote}:Projects/claims-department/test-results/playtests/claims.jsonl"
  fi
}
