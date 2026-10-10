# Interactive shells. Each section guards its own tools, so a machine that is
# missing one of them still starts cleanly.

# The repo root, resolved through the ~/.zshrc symlink.
export DOTFILES="${${(%):-%x}:A:h:h}"

# Non-login shells never read .zprofile, so set the fallback here.
: "${HOMEBREW_PREFIX:=/opt/homebrew}"

# Prompt
command -v starship >/dev/null && eval "$(starship init zsh)"

# Completion. Run compinit here, before any sourced script that would run it
# itself. The full security audit costs about 20ms, so it runs once a day,
# and the other shells trust the cached dump.
autoload -Uz compinit
() {
  if (( $# )); then
    compinit -C
  else
    compinit
  fi
} ${ZDOTDIR:-$HOME}/.zcompdump(N.mh-24)

# Shell plugins
# Source the plugin itself. The Homebrew profile.d wrapper loads it twice.
[ -f "$HOMEBREW_PREFIX/share/autojump/autojump.zsh" ] && . "$HOMEBREW_PREFIX/share/autojump/autojump.zsh"
[ -f "$HOMEBREW_PREFIX/opt/chruby/share/chruby/chruby.sh" ] && source "$HOMEBREW_PREFIX/opt/chruby/share/chruby/chruby.sh"
[ -f "$HOMEBREW_PREFIX/share/zsh-autosuggestions/zsh-autosuggestions.zsh" ] && source "$HOMEBREW_PREFIX/share/zsh-autosuggestions/zsh-autosuggestions.zsh"

# Version managers. mise is activated at the end of .exports.
export PHPENV_ROOT="$HOME/.phpenv"
if [ -d "${PHPENV_ROOT}" ]; then
  export PATH="${PHPENV_ROOT}/bin:${PHPENV_ROOT}/shims:${PATH}"
  source "${PHPENV_ROOT}/completions/phpenv.zsh"
  # This is the output of `phpenv init - --no-rehash`, written inline. The
  # command starts a bash process that costs about 60ms. Installs rehash the
  # shims already, so a rehash on each shell start is not necessary.
  phpenv() {
    local command="$1"
    [ "$#" -gt 0 ] && shift
    case "$command" in
      shell) eval "$(command phpenv "sh-$command" "$@")" ;;
      *) command phpenv "$command" "$@" ;;
    esac
  }
fi

# pyenv (lazy loaded)
export PYENV_ROOT="$HOME/.pyenv"
export PATH="$PYENV_ROOT/bin:$PATH"

_init_pyenv() {
  unalias python pip pyenv 2>/dev/null
  unfunction _init_pyenv 2>/dev/null
  eval "$(pyenv init --path)"
  eval "$(pyenv init -)"
}

unalias python pip pyenv 2>/dev/null
alias python='_init_pyenv && python'
alias pip='_init_pyenv && pip'
alias pyenv='_init_pyenv && pyenv'

# Build flags
export LDFLAGS="-L/opt/homebrew/opt/bzip2/lib"
export CPPFLAGS="-I/opt/homebrew/opt/bzip2/include"

# Secrets and per-machine settings: plain KEY=value lines, all exported.
if [ -f "$DOTFILES/.env" ]; then
  set -a
  source "$DOTFILES/.env"
  set +a
fi

# Shared files: general ones first, then functions, then project helpers.
for file in "$DOTFILES"/home/.{exports,aliases} \
            "$DOTFILES"/home/functions/*.zsh(N) \
            "$DOTFILES"/home/projects/*.zsh(N); do
  [ -r "$file" ] && [ -f "$file" ] && source "$file"
done
unset file

# Installers prepend the same directories again and again, so keep only the
# first copy of each entry. The unique flag only acts on array writes, not on
# `export PATH=...`, so the self-assignment does the actual work. Keep this
# block at the end of the file.
typeset -U path fpath
path=($path)
