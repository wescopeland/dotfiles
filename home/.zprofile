# Login shells only. Homebrew first, then the runtime shims.

# This is the output of `brew shellenv`, written inline. The command costs
# about 13ms on each login shell. Compare it again if Homebrew moves.
# These paths are the Apple Silicon ones.
export HOMEBREW_PREFIX="/opt/homebrew"
export HOMEBREW_CELLAR="/opt/homebrew/Cellar"
export HOMEBREW_REPOSITORY="/opt/homebrew"
fpath[1,0]="/opt/homebrew/share/zsh/site-functions"
export PATH="/opt/homebrew/bin:/opt/homebrew/sbin${PATH+:$PATH}"
[ -z "${MANPATH-}" ] || export MANPATH=":${MANPATH#:}"
export INFOPATH="/opt/homebrew/share/info:${INFOPATH:-}"

# OrbStack: command-line tools and integration
source ~/.orbstack/shell/init.zsh 2>/dev/null || :

# Resolve tool runtimes through mise shims before system binaries.
export PATH="$HOME/.local/share/mise/shims:$HOME/.local/bin:$PATH"
