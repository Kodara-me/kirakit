# kirakit

Single source of truth for my development and AI tooling configuration, installable on any
machine with one command.

## Contents

| Path | Purpose |
| --- | --- |
| `personas/` | Claude Code output styles: `_core.md` holds the traits shared by every persona, each other file is an overlay (`kira-sassy.md`, …) |
| `claude/` | Content for `~/.claude/`: `CLAUDE.md`, `settings.json`, `agents/`, `commands/`, `skills/` |
| `github/` | Issue and PR templates, reusable workflows, Copilot instructions to copy into a repository |
| `scripts/` | Build and helper scripts |
| `get-kira.sh` | Installer for Linux and macOS (POSIX `sh`) |
| `get-kira.ps1` | Installer for Windows (PowerShell 5+) — planned |

## Install

From a clone (development machine, files are symlinked back to the clone):

```sh
git clone https://github.com/jstmichel/kirakit.git
cd kirakit
./get-kira.sh --dry-run   # preview
./get-kira.sh
```

Without a clone (files are copied):

```sh
curl -fsSL https://raw.githubusercontent.com/jstmichel/kirakit/main/get-kira.sh | sh -s -- --dry-run
```

### Options

| Option | Effect |
| --- | --- |
| `--dry-run` | Print what would change, change nothing |
| `--persona NAME` | Install only this persona (repeatable; default: all) |
| `--only COMPONENT` | `styles`, `claude` or `github` (only `styles` is implemented so far) |
| `--link` / `--copy` | Force symlink or copy mode (default: link from a clone, copy otherwise) |
| `--uninstall` | Remove installed files (planned) |

Environment variables:

- `CLAUDE_CONFIG_DIR` — Claude Code configuration directory (default: `~/.claude`)
- `KIRAKIT_REPO`, `KIRAKIT_REF` — repository and branch fetched when running without a clone

The installer is idempotent: files already up to date are left alone, and any other existing
file is moved to `$CLAUDE_CONFIG_DIR/.kirakit-backups/<timestamp>/` before being replaced.

Requirements: `git` and a POSIX shell with standard utilities (`awk`, `cmp`, `mktemp`).
Tested on Arch-based Linux, Fedora and macOS.

## Personas

Every output style is generated from `personas/_core.md` plus one overlay; nothing is
duplicated. An overlay starts with the output style front matter (`name`, `description`,
`keep-coding-instructions`), followed by the text that replaces the `{{overlay}}` line of the core.

Shared rule: the personality shows only in the conversation. Code, comments, commits, pull
requests and documents stay neutral and professional.

Build the styles into `dist/output-styles/`:

```sh
scripts/build-styles.sh            # all personas
scripts/build-styles.sh kira-sassy # one persona
```

## Development

- Shell scripts must pass `shellcheck` and stay POSIX (`sh`, BSD and GNU utilities).
- PowerShell scripts must pass `PSScriptAnalyzer`.
- CI runs the installer with `--dry-run` on Ubuntu, macOS and Windows.

## Roadmap

1. Repository skeleton, `kira-sassy` persona, style build, `get-kira.sh` for output styles
2. `kira-focus`, `kira-mentor`, `kira-review` personas
3. `get-kira.ps1`
4. Claude Code configuration (`claude/`), including the default output style
   ([#1](https://github.com/jstmichel/kirakit/issues/1)), and GitHub configuration (`github/`)
5. `--uninstall` and CI
