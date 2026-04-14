<div align="center">

<img src="docs/logo.svg?v=2" alt="claude-project-profile" width="640">

<br>

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Shell: Bash](https://img.shields.io/badge/Shell-Bash-4EAA25?logo=gnubash&logoColor=white)](claude-project-profile)
[![Tests: bats](https://img.shields.io/badge/Tests-35_passing-brightgreen)](tests/)

Different tasks need different setups within the same project.<br>
Code review needs strict `CLAUDE.md` instructions. Daily dev needs full access.<br>
Prototyping needs a clean slate. Define each as a profile, switch with one command.

<br>

Companion to [**claude-profile**](https://github.com/yarikleto/claude-profile) (global profiles).<br>
Use both together: `claude-profile` for global `~/.claude/`, this tool for per-project `.claude/`.

</div>

---

```bash
$ claude-project-profile fork default          # save current project setup
$ claude-project-profile new code-review       # clean profile
$ claude-project-profile use code-review       # switch instantly

$ claude-project-profile list
  ○ default
  ● code-review (active)
```

## Install

### Homebrew (recommended)

```bash
brew tap yarikleto/claude-project-profile
brew install claude-project-profile
```

### One-liner

```bash
curl -fsSL https://raw.githubusercontent.com/yarikleto/claude-project-profile/main/remote-install.sh | bash
```

### From source

```bash
git clone https://github.com/yarikleto/claude-project-profile.git
cd claude-project-profile && bash install.sh
```

Open a new shell once to load tab completion: `exec zsh` or `exec bash`.

### Update

```bash
# Homebrew
brew upgrade claude-project-profile

# From source
cd claude-project-profile && git pull && bash install.sh
```

Your profiles and config are never touched — updates only replace the CLI binary and modules.

## Quick start

```bash
# 1. cd into your project
cd ~/projects/my-app

# 2. Save your current Claude Code project setup as a profile
claude-project-profile fork default

# 3. Create a clean profile for a different workflow
claude-project-profile new experiment

# 4. Switch between them
claude-project-profile use experiment     # clean slate
claude-project-profile use default        # back to your setup
```

That's it. Your original config is automatically backed up and can be restored at any time with `claude-project-profile deactivate`.

## What gets switched

Managed files are defined in `.claude-profiles/.include` — one entry per line, relative to project root.

Default:

```
.claude/
CLAUDE.md
```

Supports glob patterns — add anything you need:

```
.claude/
CLAUDE.md
AGENTS.md
docs/*.md
.claude/*.json
docs/**/*.md
```

| Pattern | Matches |
|---|---|
| `.claude/` | Entire directory |
| `CLAUDE.md` | Literal file |
| `.claude/*.json` | All JSON files in `.claude/` |
| `docs/**/*.md` | All Markdown files in `docs/` recursively |
| `?.txt` | Single-character `.txt` files |

Profiles are stored in `<project-root>/.claude-profiles/`, separate from `.claude/`.

> **Tip:** Add `.claude-profiles/` to your project's `.gitignore` — profiles contain local state and should not be committed.

## Commands

### Profile management

```
new <name>              Create a clean empty profile and activate it
fork <name>             Copy current state into a new profile
use <name>              Switch to a profile (auto-saves current)
list                    List all profiles, highlight active
current                 Print active profile name
show [name]             Show profile contents
edit [name]             Open profile directory in editor
delete <name> [-f]      Delete a profile
deactivate              Restore original state, turn off profiles
deactivate --keep       Detach from profiles, keep current config
```

### Version history

Every profile has built-in git history. Each save is a commit.

```
save [-m "message"]     Save current state with a commit message
history [name]          View change log with dates
diff [name] [ref]       Show unsaved changes or changes since a commit
restore [name] <ref>    Restore profile to a point in time
```

```bash
$ claude-project-profile save -m "Added strict review instructions"
$ claude-project-profile history
  17c7034 2025-03-15 14:30:00  Added strict review instructions
  a24a13b 2025-03-15 12:00:00  Profile created

$ claude-project-profile restore a24a13b
```

### Status line

Show the active project profile in Claude Code's status bar:

```bash
$ claude-project-profile statusline install
```

```
Opus 4.6 · project-profile: code-review
```

This writes to **project-level** `.claude/settings.json`, which overrides the global statusline from [claude-profile](https://github.com/yarikleto/claude-profile). When no project profile is active, the global statusline takes over automatically.

```
statusline install      Add profile to Claude Code status
statusline uninstall    Remove profile from Claude Code status
```

## How it differs from claude-profile

[**claude-profile**](https://github.com/yarikleto/claude-profile) switches **global** Claude Code configuration. This tool switches **project-level** configuration. They don't conflict and can be used together.

| | [claude-profile](https://github.com/yarikleto/claude-profile) | claude-project-profile |
|---|---|---|
| **Scope** | Global `~/.claude/` + `~/.claude.json` | Per-project `.claude/` + `CLAUDE.md` |
| **Storage** | `~/.local/share/claude-profile/` | `<project>/.claude-profiles/` |
| **Use case** | Different global personas | Different workflows within a project |
| **Isolation** | One active profile system-wide | Independent profiles per project |
| **Configurable** | Fixed set of managed files | `.include` with glob support |

## Safety

- **Original backup** — your pre-profiles project config is backed up on first use and **never modified** by any operation.
- **Auto-save on switch** — `use` saves the current profile before switching. No changes are lost.
- **Full isolation** — each profile is an independent copy. Changing one never affects another.
- **Clean exit** — `deactivate` restores your original state. `deactivate --keep` keeps your current config for migration.

## FAQ

<details>
<summary><strong>Does switching profiles affect running Claude Code sessions?</strong></summary>

Claude Code reads project config at startup. A running session won't pick up profile changes until you restart it.
</details>

<details>
<summary><strong>Should I commit .claude-profiles/ to git?</strong></summary>

No. Add `.claude-profiles/` to your `.gitignore`. Profiles contain local state (memory, conversation history) that shouldn't be shared.
</details>

<details>
<summary><strong>Can I use this alongside claude-profile?</strong></summary>

Yes. [claude-profile](https://github.com/yarikleto/claude-profile) manages global config (`~/.claude/`), while claude-project-profile manages project config (`.claude/` in project root). They operate on different files and don't conflict.
</details>

<details>
<summary><strong>Can I control which files are managed?</strong></summary>

Yes. Edit `.claude-profiles/.include` to add or remove files. Supports glob patterns like `*.json`, `docs/**/*.md`. By default it manages `.claude/` and `CLAUDE.md`.
</details>

<details>
<summary><strong>How do I uninstall?</strong></summary>

```bash
claude-project-profile deactivate   # restore original state in each project

# Homebrew
brew uninstall claude-project-profile

# From source
bash uninstall.sh                   # remove the CLI

rm -rf <project>/.claude-profiles   # remove profile data per project
```
</details>

## Contributing

PRs welcome. Development follows TDD — write the failing test first, then implement.

```bash
brew install bats-core    # install test runner
bats tests/               # run all tests
```

## License

[MIT](LICENSE)
