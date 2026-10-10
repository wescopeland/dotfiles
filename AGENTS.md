# AGENTS.md

Instructions for AI coding agents working in this repo.

This repo is a zsh setup for macOS on Apple Silicon. Cloning it and running `bin/install` gives a new machine the same shell. `README.md` explains the setup for people. This file explains the rules for agents.

## Layout and load order

`~/.zshenv`, `~/.zprofile` and `~/.zshrc` are symlinks into `home/`. Files load in this order:

1. `.env`, with every key exported.
2. `home/.exports`, then `home/.aliases`.
3. `home/functions/*.zsh`, one file per feature.
4. `home/projects/*.zsh`, one file per project.

The order matters. `home/functions/worktrees.zsh` creates `WORKTREE_WORKSPACES`, and each project file adds its repo to it.

## Rules

### Live shell

On the main machine the three symlinks point at this checkout. A broken edit breaks every new terminal. Before you finish any change to `home/`, run `zsh -n` on each file you touched.

### Secrets

- `.env` holds real secrets. Never print, quote or commit its values. To inspect it, print the keys only: `sed 's/=.*/=<hidden>/' .env`.
- A new setting goes in `.env.example` with no real value. Optional settings are commented out as `#KEY=value`. Follow the banner-and-section style already in that file.
- Never put a token, password or key in any other file.

### Portability

- Do not hardcode `/Users/<name>`. Use `$HOME`. Use `$GITHUB_DIR` for repo paths, or the project's own variable, such as `$RAWEB_DIR`.
- Guard every optional tool, for example with `command -v tool >/dev/null && ...` or `[ -f file ] && ...`. A machine without the tool must still start cleanly.
- A new tool the config calls goes in `config/Brewfile`.
- A new project goes in `home/projects/<name>.zsh`. Register its repo with `WORKTREE_WORKSPACES+=("$PROJECT_DIR")`. Add its path variable to `.env.example`.

### Testing a change

1. `zsh -n <file>` for each zsh file you changed. Use `bash -n` and `shellcheck` for files in `bin/`.
2. Start a shell in a clean environment, so your current shell does not hide a problem:
   ```bash
   env -i HOME="$HOME" USER="$USER" TERM=xterm-256color \
     PATH=/usr/bin:/bin:/usr/sbin:/sbin /bin/zsh -lic 'your check here'
   ```
3. To test the install script, point `HOME` at a temporary folder. Do not run it against the real home folder to test it.

### Commit guard

`.githooks/pre-commit` runs before every commit. It blocks a staged `.env`, secrets found by `gitleaks`, zsh syntax errors and `shellcheck` warnings. Never use `--no-verify`. Fix the cause instead. To test the hook, use a random fake secret in a throwaway clone. `gitleaks` ignores AWS's published example key on purpose.

### Docs

When you change the layout, the install steps or the hook, update `README.md` in the same commit.

### Names

Write the company name as `ApartmentAdvisor`, one word, with no space. This applies to comments, docs and variable names.

## Commit messages

Use commitizen-style commits. Commitizen follows the [Conventional Commits](https://www.conventionalcommits.org) format. The rules below come from the [commitizen guide](https://commitizen-tools.github.io/commitizen/tutorials/writing_commits/).

```
<type>: <description>

[optional footer]
```

**Leave out the scope.** Write `fix: ...`, not `fix(zsh): ...`.

### Types

| Type | Use it for |
|---|---|
| `feat` | A new feature |
| `fix` | A bug fix |
| `docs` | Documentation only |
| `style` | Formatting only, with no change in behavior |
| `refactor` | Restructuring with no change in behavior |
| `perf` | A speed improvement |
| `test` | Adding or changing tests |
| `build` | The build system or dependencies, such as the Brewfile |
| `ci` | CI configuration |
| `chore` | Anything else that does not change source or tests |

### Rules

1. **Keep the subject short.** Aim for about 50 characters. It must say what the commit does.
2. **Use the imperative mood.** Write as if finishing "If applied, this commit will...". Write `add`, not `added` or `adds`.
3. **Match the guide's examples.** Start the description in lowercase and end it without a period.
4. **Make one change per commit.** Do not mix unrelated changes. If several small commits are one change, squash them.
5. **Do not write a commit body.** The subject carries the whole message. If it cannot say what the commit does, the commit does too much, so split it.
6. **Think about the changelog.** Your subject may appear there, so it must make sense on its own. Use `build`, `chore` or `ci` for changes that should stay out of it.
7. **Mark breaking changes in the footer.** Add `BREAKING CHANGE: <what breaks and what to do>`. Do not use `!` in the subject, because this repo does not enable it.

### Examples

| Good | Poor |
|---|---|
| `fix: derive the Ruby gems path from the installed version` | `fix: stuff` |
| `feat: add a pre-commit guard for secrets` | `feat: pre-commit guard introduced` |
| `docs: describe the commit guard in the README` | `docs: changes` |
| `refactor: split projects into one file each` | `refactor: code cleanup` |
| `build: add gitleaks to the Brewfile` | `build: updated brewfile` |
