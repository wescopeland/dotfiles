# Resolve git worktrees by bare name, for `code` and `cd`.

# Repos whose worktrees the `code` and `cd` helpers can resolve by bare name.
# Only consulted when the helper runs outside a checkout. Each file in
# home/projects adds its own repo with WORKTREE_WORKSPACES+=(...).
typeset -ga WORKTREE_WORKSPACES=()

# The repos to scan for worktrees, nearest first. The current checkout leads so
# a name two repos share resolves to the one you are working in. The registry
# follows so names from other repos still work from anywhere.
function _worktree_search_roots() {
  emulate -L zsh
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 && print -- "$PWD"
  print -l -- "${WORKTREE_WORKSPACES[@]}"
}

# Open a git worktree in VS Code by name: `code agents-conversation-history`.
# Matching runs against branch names and worktree directory names, so the label
# the Claude Code statusline shows is enough. Anything the VS Code CLI already
# handles - flags, real paths, a bare `code` - passes straight through, so this
# only adds a fallback for a name that would otherwise be meaningless.
function _code_worktree_match() {
  emulate -L zsh
  local query="$1"

  # A hit in the repo you are standing in ends the search, so a name two repos
  # share resolves without complaint. Past that point every registered repo is
  # searched together, because registry order is arbitrary and quietly letting
  # it pick a winner would open the wrong project.
  local -a roots exact partial
  roots=($(_worktree_search_roots))
  local inside_repo=0
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 && inside_repo=1

  local root line wt_path branch name short
  local -i idx=0 before=0
  for root in "${roots[@]}"; do
    (( idx++ ))
    before=$(( ${#exact} + ${#partial} ))
    wt_path=""; branch=""
    while IFS= read -r line; do
      case "$line" in
        "worktree "*) wt_path="${line#worktree }"; branch="" ;;
        "branch "*) branch="${${line#branch }#refs/heads/}" ;;
        "")
          if [ -n "$wt_path" ]; then
            name="${wt_path:t}"
            short="${branch##*/}"
            if [ "$branch" = "$query" ] || [ "$short" = "$query" ] || [ "$name" = "$query" ]; then
              exact+=("$wt_path")
            elif [[ -n "$query" && ( "$branch" == *"$query"* || "$name" == *"$query"* ) ]]; then
              partial+=("$wt_path")
            fi
          fi
          wt_path=""; branch=""
          ;;
      esac
    done < <(git -C "$root" worktree list --porcelain 2>/dev/null)
    if (( inside_repo && idx == 1 && ${#exact} + ${#partial} > before )); then
      break
    fi
  done

  # The current checkout is usually registered as well, so the same worktree
  # can land in the list twice.
  exact=(${(u)exact}); partial=(${(u)partial})

  if (( ${#exact} )); then
    print -l -- "${exact[@]}"
  else
    print -l -- "${partial[@]}"
  fi
}

function code() {
  emulate -L zsh
  local vscode
  vscode="$(whence -p code)"

  if [ -z "$vscode" ]; then
    echo "code: the VS Code CLI is not on PATH" >&2
    return 1
  fi

  if [ $# -ne 1 ] || [ -e "$1" ] || [[ "$1" == -* ]]; then
    "$vscode" "$@"
    return
  fi

  local -a matches
  matches=(${(f)"$(_code_worktree_match "$1")"})
  matches=(${matches:#})

  if (( ${#matches} == 0 )); then
    "$vscode" "$@"
    return
  fi

  if (( ${#matches} > 1 )); then
    echo "code: '$1' matches several worktrees:" >&2
    print -l -- "${matches[@]/#/  }" >&2
    return 1
  fi

  "$vscode" "${matches[1]}"
}

# Fall back to worktree matching when a bare `cd <name>` finds no directory.
# autojump cannot do this, because it only knows directories already visited
# and a fresh worktree has never been one.
#
# The builtin is tried first and every one of its behaviors is preserved,
# including `cd -`, the two-argument form, and its own error text. Only an
# outright failure reaches the fallback, so nothing that worked before can
# start resolving somewhere else.
function cd() {
  emulate -L zsh
  builtin cd "$@" 2>/dev/null && return 0

  if [ $# -ne 1 ] || [[ "$1" == -* ]] || [[ "$1" == */* ]]; then
    builtin cd "$@"
    return
  fi

  local -a matches
  matches=(${(f)"$(_code_worktree_match "$1")"})
  matches=(${matches:#})

  if (( ${#matches} == 1 )); then
    builtin cd -- "${matches[1]}"
    return
  fi

  if (( ${#matches} > 1 )); then
    echo "cd: '$1' matches several worktrees:" >&2
    print -l -- "${matches[@]/#/  }" >&2
    return 1
  fi

  builtin cd "$@"
}

function _cd_worktrees() {
  emulate -L zsh
  local -a names
  local root
  for root in $(_worktree_search_roots); do
    names+=(${(f)"$(git -C "$root" worktree list --porcelain 2>/dev/null | awk '
      /^worktree /{ p = substr($0, 10); sub(/^.*\//, "", p); print p }
      /^branch refs\/heads\//{ sub(/^branch refs\/heads\//, ""); n = $0; sub(/^.*\//, "", n); print n }
    ')"})
  done
  names=(${names:#})
  names=(${(u)names})
  _alternative 'directories:directory:_path_files -/' "worktrees:worktree:(${names})"
}

function _code() {
  emulate -L zsh
  local -a names
  local root
  # Directory basenames as well as branch names, because the statusline label
  # people copy is the directory name.
  for root in $(_worktree_search_roots); do
    names+=(${(f)"$(git -C "$root" worktree list --porcelain 2>/dev/null | awk '
      /^worktree /{ p = substr($0, 10); sub(/^.*\//, "", p); print p }
      /^branch refs\/heads\//{ sub(/^branch refs\/heads\//, ""); n = $0; sub(/^.*\//, "", n); print n }
    ')"})
  done
  names=(${names:#})
  names=(${(u)names})
  _alternative "worktrees:worktree:(${names})" 'files:file:_files'
}

(( $+functions[compdef] )) && compdef _code code
(( $+functions[compdef] )) && compdef _cd_worktrees cd
