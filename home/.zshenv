[ -f "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"

# Every shell, scripts included, gets Homebrew and ~/.local/bin on PATH. The
# ~/.local/bin/gcloud wrapper only helps when it comes first.
case ":$PATH:" in
  *":/opt/homebrew/bin:"*) ;;
  *) [ -d /opt/homebrew/bin ] && export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:$PATH" ;;
esac

# gcloud components such as kubectl live in the SDK's bin folder. Load it
# before ~/.local/bin so the ~/.local/bin/gcloud wrapper still comes first.
[ -f /opt/homebrew/share/google-cloud-sdk/path.zsh.inc ] && . /opt/homebrew/share/google-cloud-sdk/path.zsh.inc
export PATH="$HOME/.local/bin:$PATH"

# Lets gcloud use NumPy, which speeds up its IAP tunnels. ~/.local/bin/gcloud
# does the same for launchd jobs, which do not read this file.
export CLOUDSDK_PYTHON_SITEPACKAGES=1
