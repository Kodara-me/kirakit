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

All personas are Kira: she introduces herself and signs as Kira. Only her character, and so
the way she answers, changes.

| Style | Character | Use it for |
| --- | --- | --- |
| Kira (cozy) — **default** | Gentle, calm and reassuring, low-pressure pace | Everyday work |
| Kira (sassy) | Warm, playful, lightly flirty and teasing | Relaxed sessions |
| Kira (focus) | Short, results-first, no small talk | Deep work, incidents, deadlines |
| Kira (mentor) | Patient teacher: explains why, checks understanding, gives exercises | Learning a stack or concept |
| Kira (review) | Candid reviewer: issues ranked by severity, no sugarcoating | Code, design and PR reviews |
| Kira (gremlin) | Devil's advocate hunting edge cases and failure modes | Testing, threat models, challenging a plan |
| Kira (hype) | Enthusiastic cheerleader focused on shipping | Releases, demos, motivation |

Every output style is generated from `personas/_core.md` plus one overlay; nothing is
duplicated. An overlay starts with the output style front matter (`name`, `description`,
`keep-coding-instructions`), followed by the character paragraph that replaces the
`{{overlay}}` marker of the core.

Shared rule: the personality shows only in the conversation. Code, comments, commits, pull
requests and documents stay neutral and professional.

Build the styles into `dist/output-styles/`:

```sh
scripts/build-styles.sh            # all personas
scripts/build-styles.sh kira-cozy  # one persona
```

## Development

- Shell scripts must pass `shellcheck` and stay POSIX (`sh`, BSD and GNU utilities).
- PowerShell scripts must pass `PSScriptAnalyzer`.
- CI runs the installer with `--dry-run` on Ubuntu, macOS and Windows.

## Roadmap

1. Repository skeleton, style build, `get-kira.sh` for output styles
2. Personas: cozy, sassy, focus, mentor, review, gremlin, hype
3. `get-kira.ps1`
4. Claude Code configuration (`claude/`), including the default output style, Kira (cozy)
   ([#1](https://github.com/jstmichel/kirakit/issues/1)), and GitHub configuration (`github/`)
5. `--uninstall` and CI
