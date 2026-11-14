# Open a project wherever it lives in the cluster (server-mbp, mbp-36gb), from any Mac.
#   code <project>   VS Code on that Mac (Remote-SSH); its terminal runs there too
#   term <project>   a shell on that Mac, in the project's folder
# `code` with a path, a flag, or a name that is not a project acts as the plain `code` command.

# Where a project lives when it is not in /Projects yet. /Projects/<name> on either Mac wins.
typeset -gA _cluster_homes=(
  raweb             "mbp-36gb:/Users/wescopeland/Documents/GitHub/RAWeb"
  oh-my-pi          "mbp-36gb:/Users/wescopeland/Documents/GitHub/oh-my-pi"
  psn-api           "mbp-36gb:/Users/wescopeland/Documents/GitHub/psn-api"
  advisor-site      "server-mbp:/Users/server-mbp/code/advisor-site"
  agent-pipeline    "server-mbp:/Users/server-mbp/code/agent-pipeline"
  claims-department "server-mbp:/Users/server-mbp/Projects/claims-department"
)

function _cluster_here() { [[ $(scutil --get LocalHostName 2>/dev/null) == $1 ]]; }

# Prints "<mac> <path>" for a project name (any letter case), or fails.
function _cluster_project() {
  emulate -L zsh
  local name=${1:l} mac entry entries
  for mac in server-mbp mbp-36gb; do
    if _cluster_here "$mac"; then
      entries=$(command ls /Projects 2>/dev/null)
    else
      entries=$(ssh -o BatchMode=yes -o ConnectTimeout=3 "$mac" 'ls /Projects' 2>/dev/null)
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

function _cluster_project_names() {
  local -a names=(${(k)_cluster_homes})
  _describe -t projects 'cluster project' names
}
(( $+functions[compdef] )) && compdef '_alternative "projects:project:_cluster_project_names" "files:file:_files"' code
(( $+functions[compdef] )) && compdef _cluster_project_names term
