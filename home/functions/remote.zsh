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
