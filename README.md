# dotfiles

![Terminal](images/terminal.jpg)

My zsh setup for macOS on Apple Silicon.

## Install

```bash
git clone https://github.com/wescopeland/dotfiles.git ~/.dotfiles
~/.dotfiles/bin/install
exec zsh
```

The install adds the Homebrew tools, links the zsh files into `~`, and creates `.env` from `.env.example`. Fill in `.env` with your own values.

Installation is idempotent, so it is safe to run multiple times. Use `--yes` to skip the prompt and `--no-brew` to skip Homebrew. Update with `~/.dotfiles/bin/update`.

## What you get

- [Starship](https://starship.rs) prompt, autosuggestions and autojump
- `ll` and `tree` through eza
- mise, pyenv and chruby for language versions
- `code <name>` and `cd <name>` that find git worktrees by name
- A pre-commit hook that blocks secrets, zsh syntax errors and shellcheck warnings
