# Open a project wherever it lives in the cluster (server-mbp, mbp-36gb), from any Mac.
#   code <project>   VS Code on that Mac (Remote-SSH); its terminal runs there too
#   term <project>   a shell on that Mac, in the project's folder
# `code` with a path, a flag, or a name that is not a project acts as the plain `code` command.

# Where a project lives when it is not in /Projects yet. /Projects/<name> on either Mac wins.
typeset -gA _cluster_homes=(
  oh-my-pi          "mbp-36gb:/Users/wescopeland/Documents/GitHub/oh-my-pi"
  psn-api           "mbp-36gb:/Users/wescopeland/Documents/GitHub/psn-api"
  advisor-site      "server-mbp:/Users/server-mbp/code/advisor-site"
  agent-pipeline    "server-mbp:/Users/server-mbp/code/agent-pipeline"
  claims-department "server-mbp:/Users/server-mbp/Projects/claims-department"
)

function _cluster_here() { [[ $(scutil --get LocalHostName 2>/dev/null) == $1 ]]; }

# On the cluster Macs, web pages open on the Air (~/.cluster/bin/open, linked as
# ~/.local/bin/open). Tools that read BROWSER instead of calling open do the same.
if [[ -x $HOME/.local/bin/open && -d $HOME/.cluster ]] && { _cluster_here server-mbp || _cluster_here mbp-36gb; }; then
  export BROWSER=$HOME/.local/bin/open
fi

# A bare `omp` typed in a shell starts the agent where ~/.cluster/bin/cl-agent places
# it (the less busy Mac, or the Mac a stand-in project lives on), as Tern's ⇧⌘A does.
# With arguments (`omp --restore …`, which Tern types to bring agents back, `omp stats`,
# `omp session …`) it is plain omp on this Mac, since those name files on this Mac.
if [[ -x $HOME/.cluster/bin/cl-agent ]] && { _cluster_here server-mbp || _cluster_here mbp-36gb; }; then
  function omp() { if (( $# )); then command omp "$@"; else "$HOME/.cluster/bin/cl-agent"; fi; }
fi

# Prints "<mac> <path>" for a project name (any letter case), or fails. A /Projects
# folder holding .cluster-home is a stand-in for a project on the other Mac (it lets
# server-mbp's Tern open tabs there; ~/.cluster/docs/tern-multihost.md), so it is skipped.
function _cluster_project() {
  emulate -L zsh
  local name=${1:l} mac entry entries
  local list='for d in /Projects/*/; do [ -f "$d.cluster-home" ] || basename "$d"; done'
  for mac in server-mbp mbp-36gb; do
    if _cluster_here "$mac"; then
      entries=$(sh -c "$list" 2>/dev/null)
    else
      entries=$(ssh -o BatchMode=yes -o ConnectTimeout=3 "$mac" "$list" 2>/dev/null)
    fi
    for entry in ${(f)entries}; do
      [[ ${entry:l} == $name ]] && { print -r -- "$mac /Projects/$entry"; return 0; }
    done
  done
  [[ -n ${_cluster_homes[$name]} ]] || return 1
  print -r -- "${_cluster_homes[$name]%%:*} ${_cluster_homes[$name]#*:}"
}

function code() {
  emulate -L zsh
  local bin=${commands[code]:-"/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code"}
  if (( $# == 1 )) && [[ $1 != -* && ! -e $1 ]]; then
    local found
    if found=$(_cluster_project "$1"); then
      local mac=${found%% *} dir=${found#* }
      if _cluster_here "$mac"; then
        "$bin" "$dir"
      else
        echo "Opening $dir on $mac"
        "$bin" --remote "ssh-remote+$mac" "$dir"
      fi
      return
    fi
  fi
  "$bin" "$@"
}

function term() {
  emulate -L zsh
  (( $# == 1 )) || { echo "Usage: term <project>"; return 1; }
  local found
  found=$(_cluster_project "$1") || { echo "term: no project named '$1' on server-mbp or mbp-36gb"; return 1; }
  local mac=${found%% *} dir=${found#* }
  if _cluster_here "$mac"; then
    cd "$dir"
  else
    ssh -t "$mac" "cd ${(q)dir} && exec zsh -l"
  fi
}

# How to run each project's dev servers: one Tern tab per command, and the address that
# answers when they are up. Ports reach the Air through com.cluster.raweb-forward there.
typeset -gA _cluster_dev_tabs=(
  raweb "vendor/bin/sail up|pnpm dev"
)
typeset -gA _cluster_dev_urls=(
  raweb "http://localhost:64000"
)

# start <project>: start the project's dev servers on its Mac, in tabs of server-mbp's
# Tern (the one Tern host) named after each command ("sail up", "pnpm dev"), in the
# session that already holds the project (~/.cluster/bin/dev-tabs picks it). A project
# on mbp-36gb has a stand-in folder on server-mbp, and its tabs run there. Existing
# tabs are left alone, so running it again while they are up changes nothing.
function start() {
  emulate -L zsh
  (( $# == 1 )) || { echo "Usage: start <project>  (known: ${(kj:, :)_cluster_dev_tabs})"; return 1; }
  local name=${1:l}
  [[ -n ${_cluster_dev_tabs[$name]} ]] || { echo "start: no dev recipe for '$1' (known: ${(kj:, :)_cluster_dev_tabs})"; return 1; }
  local found
  found=$(_cluster_project "$name") || { echo "start: no project named '$1'"; return 1; }
  local mac=${found%% *} dir=${found#* } url=${_cluster_dev_urls[$name]}
  local -a args=("$mac" "$dir" "$url" "${(@s:|:)_cluster_dev_tabs[$name]}")

  echo "Starting ${dir:t} on $mac..."
  local result
  if _cluster_here server-mbp; then
    result=$(~/.cluster/bin/dev-tabs "${args[@]}")
  else
    result=$(ssh -o BatchMode=yes server-mbp "~/.cluster/bin/dev-tabs ${(j: :)${(q)args[@]}}")
  fi
  case $result in
    *'|started') echo "${dir:t} is up: $url (Tern session \"${result%|*}\")" ;;
    *'|still starting') echo "${dir:t} is still starting; check the tabs in Tern session \"${result%|*}\"" ;;
    *) echo "$result"; return 1 ;;
  esac
}

function _cluster_project_names() {
  local -a names=(${(k)_cluster_homes})
  _describe -t projects 'cluster project' names
}
(( $+functions[compdef] )) && compdef '_alternative "projects:project:_cluster_project_names" "files:file:_files"' code
(( $+functions[compdef] )) && compdef _cluster_project_names term
(( $+functions[compdef] )) && compdef "_values project ${(k)_cluster_dev_tabs}" start
