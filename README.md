# kirakit

Single source of truth for my development and AI tooling configuration, installable on any
machine with one command.

## Contents

| Path | Purpose |
| --- | --- |
| `personas/` | Claude Code output styles: `_core.md` holds the traits shared by every persona, each other file is an overlay (`kira-sassy.md`, …) |
| `claude/` | Content for `~/.claude/`: `CLAUDE.md`, `settings.json`, `agents/`, `commands/`, `skills/` |
| `github/` | Issue and PR templates, reusable workflows, Copilot instructions to copy into a repository |
| `scripts/` | `build.sh`, which builds the personalized styles and skills into `dist/` |
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
| `--name NAME` | How Kira calls you |
| `--gender GENDER` | `male`, `female`, `nonbinary` or `unspecified` (sets the pronouns Kira uses) |
| `--language LANGUAGE` | Answer language, or `auto` to follow the conversation |
| `--co-author "NAME <EMAIL>"` | Add this `Co-Authored-By` trailer to commits made with the `commit` skill |
| `--no-co-author` | Add no `Co-Authored-By` trailer |
| `--reconfigure` | Ask all profile questions again |
| `--persona NAME` | Install only this persona (repeatable; default: all) |
| `--only COMPONENT` | `styles` (output styles), `claude` (skills so far) or `github` (planned); default: all |
| `--link` / `--copy` | Force symlink or copy mode (default: link from a clone, copy otherwise) |
| `--uninstall` | Remove installed files (planned) |

Environment variables:

- `CLAUDE_CONFIG_DIR` — Claude Code configuration directory (default: `~/.claude`)
- `KIRAKIT_REPO`, `KIRAKIT_REF` — repository and branch fetched when running without a clone

### Profile

Output styles and skills are personalized. On the first run the installer asks, on the
terminal even when piped from curl:

- how Kira should call you, and your gender (for the pronouns she uses);
- the answer language: `auto` (default) follows the language of the conversation;
- whether commits get a `Co-Authored-By` trailer, and if so its name and email.

The answers are saved in `$CLAUDE_CONFIG_DIR/.kirakit-profile` and reused by later runs; only
questions that are not answered yet are asked. Options override the saved values, and
`--reconfigure` asks everything again. Without a terminal, unanswered values fall back to
defaults: no name, `unspecified`, `auto`, no co-author.

The installer is idempotent: files already up to date are left alone, and any other existing
file is moved to `$CLAUDE_CONFIG_DIR/.kirakit-backups/<timestamp>/` before being replaced.

Requirements: `git` and a POSIX shell with standard utilities (`awk`, `cmp`, `mktemp`).
Tested on Arch-based Linux, Fedora and macOS.

## Personas

All personas are Kira: she introduces herself as Kira and does not sign her messages. Only
her character, and so the way she answers, changes.

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

Personal details live only in the profile. The text uses placeholders, filled at build time:

| Placeholder | Value |
| --- | --- |
| `{{user}}` | Name and description, e.g. "Alex, a female staff software developer" |
| `{{they}}`, `{{them}}`, `{{their}}` | Pronouns; avoid verbs that agree with `{{they}}` |
| `{{language}}` | Answer language, e.g. "French" or "the language of the conversation" |
| `{{co_author_trailer}}`, `{{attribution_rule}}` | Commit attribution, used by the `commit` skill |

A line holding only a placeholder that expands to nothing is removed.

Shared rule: the personality shows only in the conversation. Code, comments, commits, pull
requests and documents stay neutral and professional.

Build the styles and skills into `dist/` (the installer does this for you):

```sh
scripts/build.sh                   # all personas, generic profile
scripts/build.sh kira-cozy         # one persona
scripts/build.sh --name Alex --gender female --language French --co-author "Kira <kira@example.com>"
```

## Skills

`claude/skills/` holds Claude Code skills, one directory per skill with its `SKILL.md`:
`commit`, `diffv`, `pull`, `push` and `test`. They are built like the styles, so they answer
in the profile's language and `commit` follows its co-author setting. The installer links or
copies each built directory to `$CLAUDE_CONFIG_DIR/skills/`; other skills already there are
left untouched.

## Development

- Shell scripts must pass `shellcheck` and stay POSIX (`sh`, BSD and GNU utilities).
- PowerShell scripts must pass `PSScriptAnalyzer`.
- CI runs the installer with `--dry-run` on Ubuntu, macOS and Windows.

## Roadmap

1. Repository skeleton, style build, `get-kira.sh` for output styles
2. Personas: cozy, sassy, focus, mentor, review, gremlin, hype; skills
3. `get-kira.ps1`
4. Claude Code configuration (`claude/`), including the default output style, Kira (cozy)
   ([#1](https://github.com/jstmichel/kirakit/issues/1)), and GitHub configuration (`github/`)
5. `--uninstall` and CI
