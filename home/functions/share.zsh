# share <html-file>: serve a file and open an ngrok tunnel to it.

function share() {
  emulate -L zsh

  if [ $# -ne 1 ]; then
    echo "Usage: share <html-file>"
    return 1
  fi

  local file="${1:A}"
  if [ ! -f "$file" ]; then
    echo "share: file not found: $1"
    return 1
  fi

  if ! command -v python3 >/dev/null 2>&1; then
    echo "share: python3 is required to serve the file"
    return 1
  fi

  if ! command -v ngrok >/dev/null 2>&1; then
    echo "share: ngrok is required (install via 'brew install ngrok')"
    return 1
  fi

  local dir="${file:h}"
  local name="${file:t}"
  local encoded_name
  encoded_name="$(python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1]))' "$name")" || return 1

  local port
  port="$(python3 - <<'PY'
import socket

with socket.socket() as sock:
    sock.bind(("127.0.0.1", 0))
    print(sock.getsockname()[1])
PY
)" || return 1

  local http_log="/tmp/share-http-$port.log"
  local ngrok_log="/tmp/share-ngrok-$port.log"

  echo "Serving $file"
  echo "Local URL: http://127.0.0.1:$port/$encoded_name"
  echo "Starting ngrok tunnel. Press Ctrl-C to stop sharing."

  python3 -m http.server "$port" --bind 127.0.0.1 --directory "$dir" >"$http_log" 2>&1 &
  local server_pid=$!

  ngrok http "$port" --log=stdout >"$ngrok_log" 2>&1 &
  local ngrok_pid=$!

  local cleanup() {
    kill "$ngrok_pid" 2>/dev/null
    kill "$server_pid" 2>/dev/null
    wait "$ngrok_pid" 2>/dev/null
    wait "$server_pid" 2>/dev/null
  }

  trap cleanup INT TERM EXIT

  sleep 0.3
  if ! kill -0 "$server_pid" 2>/dev/null; then
    echo "share: local server failed to start. Log: $http_log"
    return 1
  fi

  local public_url=""
  local attempt
  for attempt in {1..40}; do
    if ! kill -0 "$ngrok_pid" 2>/dev/null; then
      echo "share: ngrok exited unexpectedly. Log: $ngrok_log"
      return 1
    fi
    public_url="$(curl -s "http://127.0.0.1:4040/api/tunnels" 2>/dev/null \
      | python3 -c 'import json, sys
try:
    data = json.load(sys.stdin)
    tunnels = data.get("tunnels", [])
    https = [t["public_url"] for t in tunnels if t.get("proto") == "https"]
    if https:
        print(https[0])
    elif tunnels:
        print(tunnels[0]["public_url"])
except Exception:
    pass' 2>/dev/null)"
    [ -n "$public_url" ] && break
    sleep 0.25
  done

  if [ -z "$public_url" ]; then
    echo "share: failed to obtain ngrok public URL. Log: $ngrok_log"
    return 1
  fi

  echo "File URL: ${public_url%/}/$encoded_name"

  wait "$ngrok_pid"
  local status=$?
  trap - INT TERM EXIT
  cleanup
  return "$status"
}
