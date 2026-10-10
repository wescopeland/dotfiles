# remote <name>: open a Screen Sharing session to another Mac.

function remote() {
  emulate -L zsh

  if [ $# -ne 1 ]; then
    echo "Usage: remote <name>"
    echo "Example: remote server-mbp"
    return 1
  fi

  if ! command -v open >/dev/null 2>&1; then
    echo "remote: 'open' is required, so this only works on macOS"
    return 1
  fi

  # The name is a hostname, such as a Tailscale machine name. A user name
  # works too: `remote user@host`.
  open "vnc://$1"
}

# Tab completion: the other machines on the Tailscale network. The first line
# of `tailscale status` is this machine, so it is skipped. Without Tailscale
# there is nothing to offer, and `remote` still works with a typed name.
function _remote() {
  emulate -L zsh

  (( CURRENT == 2 )) || return 1
  command -v tailscale >/dev/null 2>&1 || return 1

  local -a machines
  machines=(${(f)"$(tailscale status 2>/dev/null \
    | awk 'NR > 1 && $1 ~ /^[0-9]/ { print $2 ":" ($0 ~ /offline/ ? "offline" : "online") }')"})
  (( ${#machines} )) || return 1

  _describe -t machines 'Tailscale machine' machines
}

(( $+functions[compdef] )) && compdef _remote remote
