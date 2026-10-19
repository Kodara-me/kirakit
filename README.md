# kirakit

Single source of truth for my development and AI tooling configuration, installable on any
machine with one command.

## Contents

| Path | Purpose |
| --- | --- |
| `personas/` | Claude Code output styles: `_core.md` holds the traits shared by every persona, each other file is an overlay (`kira-cozy.md`, …) |
| `claude/` | Content for `~/.claude/`: `CLAUDE.md`, `skills/`, `agents/` |
| `github/` | Issue and pull request templates, a workflow and Copilot instructions to copy into a repository's `.github/` |
| `.github/workflows/` | This repository's CI, and reusable workflows other repositories can call |
| `scripts/` | `build.sh` (builds the personalized files into `dist/`) and `test.sh` (end-to-end tests) |
| `get-kira.sh` | Installer for Linux and macOS (POSIX `sh`) |
| `get-kira.ps1` | Installer for Windows (PowerShell 5+, also runs on PowerShell 7) |

## Install

Linux and macOS, from a clone (files are symlinked back to the clone):

```sh
git clone https://github.com/jstmichel/kirakit.git
cd kirakit
./get-kira.sh --dry-run   # preview
./get-kira.sh
```

Linux and macOS, without a clone (files are copied):

```sh
curl -fsSL https://github.com/jstmichel/kirakit/releases/latest/download/get-kira.sh | sh
```

Windows, from a clone (files are copied; pass `-Link` for symbolic links, which need
Developer Mode):

```powershell
.\get-kira.ps1 -DryRun
.\get-kira.ps1
```

Windows, without a clone:

```powershell
& ([scriptblock]::Create((irm https://github.com/jstmichel/kirakit/releases/latest/download/get-kira.ps1)))
```

These URLs always serve the installer of the latest release, which installs that release.
For a fixed version, replace `latest/download` with `download/v0.2.2` (or any other tag). To
pass options through the pipe, use `sh -s -- --dry-run` or append `-DryRun` after the last
parenthesis.

### What gets installed

In `$CLAUDE_CONFIG_DIR` (default: `~/.claude`):

| Path | Component |
| --- | --- |
| `output-styles/kira-*.md` | `styles` |
| `CLAUDE.md`, `skills/*`, `agents/*` | `claude` |
| `outputStyle` in `settings.json` | `claude` — only this key is changed; the file is edited in place |
| `.kirakit-profile`, `.kirakit-manifest`, `.kirakit-originals` | Profile and the record used by `--uninstall` |
| `.kirakit-backups/<timestamp>/` | Files that were replaced or removed |

The `github` component is installed only on request (`--only github`), into a repository's
`.github/`: issue templates (bug report, and a feature request written as a specification),
a pull request template, Copilot instructions, and a workflow that checks pull request titles.

### Options

`get-kira.ps1` takes the same options in PowerShell form (`-DryRun`, `-Name`, `-CoAuthor`, …;
see `Get-Help .\get-kira.ps1 -Detailed`).

| Option | Effect |
| --- | --- |
| `--dry-run` | Print what would change, change nothing |
| `--name NAME` | How Kira calls you |
| `--gender GENDER` | `male`, `female`, `nonbinary` or `unspecified` (sets the pronouns Kira uses) |
| `--language LANGUAGE` | Answer language, or `auto` to follow the conversation |
| `--co-author "NAME <EMAIL>"` | Add this `Co-Authored-By` trailer to commits |
| `--no-co-author` | Add no `Co-Authored-By` trailer |
| `--default-style PERSONA` | Style selected in `settings.json` (default: `kira-cozy`) |
| `--reconfigure` | Ask all profile questions again |
| `--persona NAME` | Install only this persona (repeatable; default: all) |
| `--only COMPONENT` | `styles`, `claude` or `github`; default: `styles` and `claude` |
| `--target DIR` | Repository for `--only github` (default: the current one) |
| `--link` / `--copy` | Force symlink or copy mode |
| `--uninstall` | Remove what kirakit installed and restore the files it replaced |

Environment variables:

- `CLAUDE_CONFIG_DIR` — Claude Code configuration directory (default: `~/.claude`)
- `KIRAKIT_REPO`, `KIRAKIT_REF` — repository and branch or tag fetched without a clone
  (default: the release the installer comes from, otherwise the latest `vX.Y.Z` tag; set
  `KIRAKIT_REF=main` for unreleased changes)

### Profile

Output styles, skills and `CLAUDE.md` are personalized. On the first run the installer asks,
on the terminal even when piped from curl:

- how Kira should call you, and your gender (for the pronouns she uses);
- the answer language: `auto` (default) follows the language of the conversation;
- whether commits get a `Co-Authored-By` trailer, and if so its name and email.

The answers are saved in `$CLAUDE_CONFIG_DIR/.kirakit-profile` and reused by later runs; only
questions that are not answered yet are asked. Options override the saved values, and
`--reconfigure` asks everything again. Without a terminal, unanswered values fall back to
defaults: no name, `unspecified`, `auto`, no co-author.

### Updates, backups and uninstall

The installer is idempotent: files already up to date are left alone, and any other existing
file is moved to `$CLAUDE_CONFIG_DIR/.kirakit-backups/<timestamp>/` before being replaced.
From a clone, update with `git pull` then run the installer again.

`--uninstall` removes the links and moves copies to the backups, then restores the files that
were there before kirakit (for example your own `CLAUDE.md`). It keeps the profile, the
backups and the `outputStyle` setting.

Requirements: `git`, and a POSIX shell with standard utilities (`awk`, `sed`, `cmp`, `diff`,
`mktemp`) or PowerShell 5+.

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

Shared rule: the personality shows only in the conversation. Code, comments, commits, pull
requests and documents stay neutral and professional.

## Skills

`claude/skills/` holds Claude Code skills, one directory per skill with its `SKILL.md`:
`commit`, `diffv`, `pull`, `push` and `test`. They answer in the profile's language, and
`commit` follows its co-author setting. Other skills already in `$CLAUDE_CONFIG_DIR/skills/`
are left untouched. Agents in `claude/agents/` are installed the same way.

## Placeholders

Personal details live only in the profile. Every Markdown file under `personas/` and
`claude/` can use these placeholders, filled at build time:

| Placeholder | Value |
| --- | --- |
| `{{user}}` | Name and description, e.g. "Alex, a female staff software developer" |
| `{{they}}`, `{{them}}`, `{{their}}` | Pronouns; avoid verbs that agree with `{{they}}` |
| `{{language}}` | Answer language, e.g. "French" or "the language of the conversation" |
| `{{co_author_trailer}}`, `{{attribution_rule}}` | Commit attribution in the `commit` skill |
| `{{co_author_rule}}` | Commit attribution rule in `CLAUDE.md` |

A line holding only a placeholder that expands to nothing is removed. Build the files into
`dist/` by hand with:

```sh
scripts/build.sh --name Alex --gender female --language French --co-author "Kira <kira@example.com>"
```

## Reusable workflows

Other repositories can call the workflows in `.github/workflows/`:

```yaml
jobs:
  conventional-commits:
    uses: jstmichel/kirakit/.github/workflows/conventional-pr-title.yml@v0.2.0
```

`conventional-pr-title.yml` fails when a pull request title does not follow Conventional
Commits (`types` input: allowed types, separated by `|`).

## Releases

Push a signed `vX.Y.Z` tag and publish a GitHub release for it: the `release.yml` workflow
attaches `get-kira.sh` and `get-kira.ps1`, stamped with the tag, which is what the
`latest/download` URLs serve.

## Development

- `scripts/test.sh [SHELL]` runs the end-to-end tests in a temporary directory, with `sh` by
  default (`scripts/test.sh dash`, `scripts/test.sh "bash --posix"`).
- Shell scripts must pass `shellcheck` and stay POSIX (`sh`, BSD and GNU utilities).
- `get-kira.ps1` must pass `PSScriptAnalyzer` with `PSScriptAnalyzerSettings.psd1`, stay ASCII
  and run on Windows PowerShell 5.1.
- `get-kira.ps1` reimplements `build.sh`: CI checks that both produce the same files.
- CI runs the tests on Ubuntu (`dash`, `bash --posix`) and macOS (`sh`, `zsh`), and the
  PowerShell installer on Windows (PowerShell 5.1 and 7).
