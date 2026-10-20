# ApartmentAdvisor. The repo is at $ADVISOR_WORKSPACE, which defaults to $GITHUB_DIR/advisor-site.

# Work
export ADVISOR_WORKSPACE="${ADVISOR_WORKSPACE:-$GITHUB_DIR/advisor-site}"
export ADVISOR_DB_CREDENTIALS_DIR="$ADVISOR_WORKSPACE/db-admin/dev/standard-dev-db-credentials"

WORKTREE_WORKSPACES+=("$ADVISOR_WORKSPACE")

function dev() {
  local repo="$ADVISOR_WORKSPACE"
  local advisor_node="$repo/advisor-node"

  if [ "$1" != "up" ]; then
    echo "Usage: dev up [--shared-only|--shared|--only-shared] [--tree=<slug>] [--app=<app>|--apps=<app1,app2>]"
    return 1
  fi
  shift

  local shared_only=0
  local tree=""
  local apps_csv=""

  while [ $# -gt 0 ]; do
    case "$1" in
      --shared-only|--shared|--only-shared)
        shared_only=1
        ;;
      --tree=*)
        tree="${1#*=}"
        ;;
      --app=*|--apps=*)
        apps_csv="${1#*=}"
        ;;
      *)
        echo "Unknown option: $1"
        echo "Usage: dev up [--shared-only|--shared|--only-shared] [--tree=<slug>] [--app=<app>|--apps=<app1,app2>]"
        return 1
        ;;
    esac
    shift
  done

  command -v mise >/dev/null 2>&1 && eval "$(mise activate --shims zsh)" >/dev/null 2>&1

  if [ "$shared_only" -eq 1 ]; then
    (cd "$advisor_node" && hivemind Procfile.shared)
    return $?
  fi

  # Resolve the worktree path when --tree is provided. Looks under
  # $repo/.worktrees/<slug>/advisor-node. Seeds gitignored Procfile* files
  # from the main checkout when they're missing so hivemind has something
  # to run - existing files in the worktree are kept (cp -n behavior).
  local worktree_advisor_node=""
  if [ -n "$tree" ]; then
    worktree_advisor_node="$repo/.worktrees/$tree/advisor-node"
    if [ ! -d "$worktree_advisor_node" ]; then
      echo "No worktree at $worktree_advisor_node"
      return 1
    fi

    local pf
    for pf in Procfile Procfile.backend Procfile.shared; do
      [ -f "$advisor_node/$pf" ] && cp -n "$advisor_node/$pf" "$worktree_advisor_node/$pf"
    done

    # .env.local is gitignored per-user secrets; tracked .env.development /
    # .env.production are already in the worktree from the original checkout.
    # Copy only the missing local-secrets files so auth and other per-user
    # config work inside the worktree.
    local app_dir rel_app
    for app_dir in "$advisor_node"/apps/*/; do
      rel_app="${app_dir#$advisor_node/}"
      [ -f "$app_dir.env.local" ] && [ -d "$worktree_advisor_node/$rel_app" ] \
        && cp -n "$app_dir.env.local" "$worktree_advisor_node/$rel_app.env.local"
    done
  fi

  # --tree alone runs the full Procfile in that worktree.
  if [ -n "$tree" ] && [ -z "$apps_csv" ]; then
    (cd "$worktree_advisor_node" && hivemind Procfile)
    return $?
  fi

  if [ -n "$tree" ] && [ -n "$apps_csv" ]; then
    local procfile
    procfile="$(mktemp)"
    trap 'rm -f "$procfile"' EXIT

    local old_ifs="$IFS"
    IFS=','

    local requested_apps
    requested_apps=(${=apps_csv})

    IFS="$old_ifs"

    local app
    for app in "${requested_apps[@]}"; do
      local resolved_app="$app"

      case "$app" in
        pm) resolved_app="property-manager" ;;
        lb) resolved_app="leasing-dashboard" ;;
        tp) resolved_app="tenant-portal" ;;
        hw) resolved_app="home-web" ;;
        at|admin) resolved_app="admin-tool" ;;
      esac

      case "$resolved_app" in
        home-web|leasing-dashboard|property-manager|tenant-portal|admin-tool)
          ;;
        *)
          echo "Unknown app: $app"
          rm -f "$procfile"
          return 1
          ;;
      esac

      echo "${resolved_app}: pnpm dev:${resolved_app}:local" >> "$procfile"
    done

    (cd "$worktree_advisor_node" && hivemind "$procfile")
    local status=$?
    rm -f "$procfile"
    trap - EXIT
    return $status
  fi

  if [ -z "$tree" ] && [ -z "$apps_csv" ]; then
    (cd "$advisor_node" && hivemind Procfile)
    return $?
  fi

  echo "Use --apps with --tree, or pass --tree alone for the full Procfile"
  return 1
}

function frontend() {
  if [ "$1" = "up" ]; then
    (cd "$ADVISOR_WORKSPACE/advisor-node" && hivemind Procfile.backend)
  else
    echo "Usage: frontend up"
  fi
}

function backend() {
  "$ADVISOR_WORKSPACE/scripts/backend-dev.sh" "$@"
}

# Stop stray watchexec/service JVMs left over from old `backend up` runs.
function killstray() {
  backend killstray "$@"
}

# Local viewer for the production and staging logs in Google Cloud.
# The viewer reads with your own gcloud credentials and changes nothing.
function logs() {
  local repo="${GCP_LOG_VIEWER_DIR:-$GITHUB_DIR/gcp-log-viewer}"

  case "${1:-up}" in
    up) ;;
    *)
      echo "Usage: logs [up]"
      return 1
      ;;
  esac

  if [ ! -x "$repo/bin/start" ]; then
    echo "No log viewer at $repo"
    return 1
  fi

  (cd "$repo" && ./bin/start)
}

# ASSIST app (leaseboard-mobile): run the dev build on this Mac's iOS simulator or Android emulator
# against a web preview on $ASPLAY_REMOTE. The remote runs Metro and builds the app (`mobile-preview`
# there), so this Mac needs no node or Xcode build: a JS change on the branch shows on a reload, and a
# new app build is copied only when the branch's native code changes. Builds are kept in $ASPLAY_DIR.
# The iOS simulator is one named asplay; the Android emulator is the AVD asplay, started when no
# Android device is connected.
# Usage: asplay [preview] [ios|android]   (default: develop ios), e.g. asplay pr-6888 android
asplay() {
  local id="${1:-develop}" platform="${2:-ios}"
  local remote="${ASPLAY_REMOTE-server-mbp@server-mbp}" root="${ASPLAY_DIR:-$HOME/.cache/asplay}"
  local app_id=com.apartmentadvisor.leaseboardMobile
  case "$platform" in
    ios|android) ;;
    *) echo "Usage: asplay [preview] [ios|android]"; return 1 ;;
  esac
  local info url art
  info=$(ssh "$remote" .local/bin/mobile-preview up "$id" --json) || return 1
  url=$(jq -r ".metro.$platform" <<< "$info")
  art=$(ssh "$remote" .local/bin/mobile-preview artifact "$id" "$platform") || {
    echo "asplay: no $platform build matches the native code of $id yet. On $remote run: mobile-preview build $id $platform"
    return 1
  }
  local build="${art:h:t}"
  local dir="$root/$build"
  mkdir -p "$root"
  if [ ! -e "$dir/${art:t}" ]; then
    rm -rf "$dir.partial" && mkdir -p "$dir.partial"
    /usr/bin/rsync -a "$remote:$art" "$dir.partial/" || { echo "asplay: could not copy the build from $remote"; return 1; }
    rm -rf "$dir" && mv "$dir.partial" "$dir"
  fi
  echo "asplay: $id on $platform, API $(jq -r .apiUrl <<< "$info"), build ${build#*-}"
  if [ "$platform" = ios ]; then
    local udid runtime
    udid=$(xcrun simctl list devices --json | jq -r '[.devices[][] | select(.name == "asplay" and .isAvailable)][0].udid // empty')
    if [ -z "$udid" ]; then
      runtime=$(xcrun simctl list runtimes --json | jq -r '[.runtimes[] | select(.platform == "iOS" and .isAvailable)] | last | .identifier // empty')
      [ -n "$runtime" ] || { echo "asplay: no iOS simulator runtime. Run: xcodebuild -downloadPlatform iOS"; return 1; }
      udid=$(xcrun simctl create asplay "${ASPLAY_IOS_DEVICE:-iPhone 17 Pro}" "$runtime") || return 1
    fi
    xcrun simctl bootstatus "$udid" -b > /dev/null || return 1
    open "$(xcode-select -p)/Applications/Simulator.app"
    if [ "$(cat "$root/installed-ios-$udid" 2> /dev/null)" != "$build" ]; then
      xcrun simctl install "$udid" "$dir/ASSISTDev.app" || return 1
      echo "$build" > "$root/installed-ios-$udid"
    fi
    # --initialUrl opens the bundle directly, with no "Open in ASSIST Dev?" prompt.
    xcrun simctl launch --terminate-running-process "$udid" "$app_id" --initialUrl "$url" > /dev/null
  else
    export ANDROID_HOME="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
    local serial
    serial=$(adb devices | awk 'NR > 1 && $2 == "device" { print $1; exit }')
    if [ -z "$serial" ]; then
      if ! "$ANDROID_HOME/emulator/emulator" -list-avds | grep -qx asplay; then
        # The SDK's own avdmanager: Homebrew's looks for system images in its own folder.
        echo no | "$ANDROID_HOME/cmdline-tools/latest/bin/avdmanager" create avd -n asplay \
          -k "system-images;android-36;google_apis;arm64-v8a" -d pixel_8 > /dev/null || return 1
      fi
      ("$ANDROID_HOME/emulator/emulator" -avd asplay -no-snapshot-save > "$root/emulator.log" 2>&1 &)
      local waited=0
      until [ "$(adb shell getprop sys.boot_completed 2> /dev/null | tr -d '\r')" = 1 ]; do
        if [ $waited -ge 240 ] || ! pgrep -qf "emulator.*-avd asplay"; then
          echo "asplay: the emulator did not start; see $root/emulator.log"
          return 1
        fi
        sleep 2
        waited=$((waited + 2))
      done
      serial=$(adb devices | awk 'NR > 1 && $2 == "device" { print $1; exit }')
    fi
    if [ "$(cat "$root/installed-android-$serial" 2> /dev/null)" != "$build" ]; then
      adb -s "$serial" install -r "$dir/app-debug.apk" > /dev/null || return 1
      echo "$build" > "$root/installed-android-$serial"
    fi
    adb -s "$serial" shell am force-stop "$app_id"
    adb -s "$serial" shell am start -a android.intent.action.VIEW \
      -d "'leaseboard-mobile://expo-development-client/?url=$(jq -rn --arg u "$url" '$u | @uri')'" > /dev/null
  fi
}
