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

# How to run each project's dev servers: one Tern tab per command, and the address that
# answers when they are up. Ports reach the Air through com.cluster.raweb-forward there.
typeset -gA _cluster_dev_tabs=(
  raweb "vendor/bin/sail up|pnpm dev"
)
typeset -gA _cluster_dev_urls=(
  raweb "http://localhost:64000"
)

# start <project>: start the project's dev servers on its Mac, in a Tern session named
# "<folder> dev" that keeps running when this terminal closes. Running it again while
# they are up changes nothing.
function start() {
  emulate -L zsh
  (( $# == 1 )) || { echo "Usage: start <project>  (known: ${(kj:, :)_cluster_dev_tabs})"; return 1; }
  local name=${1:l}
  [[ -n ${_cluster_dev_tabs[$name]} ]] || { echo "start: no dev recipe for '$1' (known: ${(kj:, :)_cluster_dev_tabs})"; return 1; }
  local found
  found=$(_cluster_project "$name") || { echo "start: no project named '$1'"; return 1; }
  local mac=${found%% *} dir=${found#* }
  local session="${dir:t} dev" url=${_cluster_dev_urls[$name]}
  local -a tabs=(${(s:|:)_cluster_dev_tabs[$name]})

  # The whole check-and-start runs on the project's Mac in one go.
  local script="cd ${(q)dir} || exit 1
up() { curl -s -o /dev/null -m 3 ${(q)url}/; }
if up && tern ls --json | jq -e --arg s ${(q)session} '.sessions[] | select(.name == \$s)' >/dev/null; then
  echo 'already running'; exit 0
fi
tern kill session ${(q)session} >/dev/null 2>&1
tern new session ${(q)session} --keep-open --cwd ${(q)dir} -- zsh -lic ${(q):-"${tabs[1]}; exec zsh -l"} >/dev/null || exit 1"
  local tab
  for tab in ${tabs[2,-1]}; do
    script+="
tern new tab ${(q)session} --keep-open --cwd ${(q)dir} -- zsh -lic ${(q):-"$tab; exec zsh -l"} >/dev/null"
  done
  script+="
for i in \$(seq 1 90); do up && { echo started; exit 0; }; sleep 2; done
echo 'still starting; check the tabs'"

  echo "Starting ${dir:t} on $mac (Tern session \"$session\")..."
  local result
  if _cluster_here "$mac"; then
    result=$(zsh -lc "$script")
  else
    result=$(ssh -o BatchMode=yes "$mac" "zsh -lc ${(q)script}")
  fi
  case $result in
    *already*) echo "${dir:t} is already running: $url" ;;
    *started*) echo "${dir:t} is up: $url" ;;
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
