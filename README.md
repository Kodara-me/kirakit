# kirakit

Single source of truth for my development and AI tooling configuration, installable on any
machine with one command.

## Contents

| Path | Purpose |
| --- | --- |
| `personas/` | Claude Code output styles: `_core.md` holds the traits shared by every persona, each other file is an overlay (`kira-cozy.md`, …) |
| `team/` | Team members beside Kira, one file each (`iris.md`), built into an output style and an agent |
| `claude/` | Content for `~/.claude/`: `CLAUDE.md`, `rules/`, `skills/`, `agents/` |
| `launchers/` | Commands that start a team member or the whole team (`assistant`, `analyst`, `team`), and their Konsole color schemes |
| `github/` | Issue and pull request templates, a workflow and Copilot instructions to copy into a repository's `.github/` |
| `.github/workflows/` | This repository's CI, and reusable workflows other repositories can call |
| `scripts/` | `build.sh` (builds the personalized files into `dist/`) and `test.sh` (end-to-end tests) |
| `get-kira.sh` | Installer for Linux and macOS (POSIX `sh`) |
| `get-kira.ps1` | Installer for Windows (PowerShell 5+, also runs on PowerShell 7) |

## Install

Linux and macOS, from a clone (files are symlinked back to the clone):

```sh
git clone https://github.com/Kodara-me/kirakit.git
cd kirakit
./get-kira.sh --dry-run   # preview
./get-kira.sh
```

Linux and macOS, without a clone (files are copied):

```sh
curl -fsSL https://github.com/Kodara-me/kirakit/releases/latest/download/get-kira.sh | sh
```

Windows, from a clone (files are copied; pass `-Link` for symbolic links, which need
Developer Mode):

```powershell
.\get-kira.ps1 -DryRun
.\get-kira.ps1
```

Windows, without a clone:

```powershell
& ([scriptblock]::Create((irm https://github.com/Kodara-me/kirakit/releases/latest/download/get-kira.ps1)))
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
| `output-styles/iris.md`, with an analyst | `styles` |
| `CLAUDE.md`, `rules/git.md`, `skills/*`, `agents/*` (`rules/team.md` and `agents/iris.md` with an analyst) | `claude` |
| `outputStyle` and `attribution` in `settings.json` | `claude` — only these keys are changed; the file is edited in place |
| `.kirakit-profile`, `.kirakit-manifest`, `.kirakit-originals` | Profile and the record used by `--uninstall` |
| `.kirakit-backups/<timestamp>/` | Files that were replaced or removed |

Outside it, on Linux and macOS (see [Launchers](#launchers)):

| Path | Component |
| --- | --- |
| `assistant`, `team`, `kirakit-session` in `~/.local/bin` (or `--bin-dir`) | `launchers` |
| `analyst` in the same directory, with an analyst | `launchers` |
| `kirakit-assistant.colorscheme` in `$XDG_DATA_HOME/konsole` (default: `~/.local/share/konsole`) | `launchers` |
| `kirakit-analyst.colorscheme` in the same directory, with an analyst | `launchers` |

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
| `--assistant "NAME <EMAIL>"` | The assistant's git identity: its own commits, and its trailer in yours |
| `--assistant-signing-key PATH` | The assistant's public SSH signing key (empty: it never commits as itself) |
| `--assistant-github LOGIN` | The assistant's own GitHub account (empty: none) |
| `--co-author "NAME <EMAIL>"` | Same as `--assistant`, with `Co-Authored-By` trailers |
| `--no-co-author` | Add no `Co-Authored-By` trailer |
| `--analyst` | Add Iris, an analyst for ideas and specifications, to the team |
| `--no-analyst` | No analyst: Kira writes ideas and specifications herself |
| `--analyst-github LOGIN` | The analyst's own GitHub account (implies `--analyst`; empty: none) |
| `--default-style PERSONA` | Style selected in `settings.json` (default: `kira-cozy`) |
| `--assistant-style PERSONA` | Style of the `assistant` launcher (default: the default style) |
| `--bin-dir DIR` | Where the launchers go, an absolute path (default: `~/.local/bin`) |
| `--reconfigure` | Ask all profile questions again |
| `--persona NAME` | Install only this persona (repeatable; default: all) |
| `--only COMPONENT` | `styles`, `claude`, `launchers` or `github`; default: `styles`, `claude` and `launchers` |
| `--target DIR` | Repository for `--only github` (default: the current one) |
| `--link` / `--copy` | Force symlink or copy mode |
| `--uninstall` | Remove what kirakit installed and restore the files it replaced |

Environment variables:

- `CLAUDE_CONFIG_DIR` — Claude Code configuration directory (default: `~/.claude`)
- `XDG_DATA_HOME` — where the Konsole color schemes go, in `konsole/` (default: `~/.local/share`)
- `KIRAKIT_REPO`, `KIRAKIT_REF` — repository and branch or tag fetched without a clone
  (default: the release the installer comes from, otherwise the latest `vX.Y.Z` tag; set
  `KIRAKIT_REF=main` for unreleased changes)

### Profile

Output styles, skills and `CLAUDE.md` are personalized. On the first run the installer asks,
on the terminal even when piped from curl:

- how Kira should call you, and your gender (for the pronouns she uses);
- the answer language: `auto` (default) follows the language of the conversation;
- the assistant: its name and email, the path to its public SSH signing key and its GitHub
  login (both optional), and whether commits get `Co-Authored-By` trailers;
- whether the team has an analyst, Iris, and her GitHub login (optional). She never commits,
  so there is no signing key to give for her.

A profile saved by an earlier version, with a `co_author` value, is migrated: the co-author
becomes the assistant, with trailers. A profile saved before the analyst reads as no analyst,
and the question is not asked again: pass `--analyst` or `--analyst-github` to add her.

The answers are saved in `$CLAUDE_CONFIG_DIR/.kirakit-profile` and reused by later runs; only
questions that are not answered yet are asked. Options override the saved values, and
`--reconfigure` asks everything again. Without a terminal, unanswered values fall back to
defaults: no name, `unspecified`, `auto`, no assistant, no analyst; the optional assistant
values default to empty, and trailers to yes when there is an assistant.

### Who commits

The git rules (`rules/git.md`, which Claude Code loads on its own) follow the profile:

- **You commit** with the `commit` skill, under your git identity. With trailers on, the
  message ends with `Co-Authored-By:` and the assistant's name and email.
- **The assistant commits** the code it wrote with the `assistant-commit` skill, under its own
  name and email, signed with its own SSH key, and you are the co-author. Its identity and key
  are passed on the `git` command line: your git configuration is never changed. Without a
  signing key in the profile, the assistant never commits as itself.
- **With a GitHub account** for the assistant (`--assistant-github`), the rules also say how
  it works on GitHub: everything it writes uses its own token, its pull requests ask for your
  review, and its questions are asked both in the conversation and in a comment.
- **With an analyst,** a "The team" section adds that Iris never commits, and that a gap found
  in a specification while coding is asked to her in a comment rather than settled alone.
  With her own GitHub account (`--analyst-github`), her work (ideas, specifications,
  sub-issues, labels and clarification comments) is written as that account, whoever does
  it; the `idea` and `spec` skills use it too. Any login works, your own included.

The installer also sets `"attribution": {"commit": "", "pr": ""}` in `settings.json`, so
Claude Code stops suggesting its own trailer and pull request footer. If `attribution` is
already set to something else, it is left unchanged, with a warning.

### Give the assistant its own identity

The installer never creates or uploads keys: these steps are done once, by hand. The examples
use `kira` and `kira@example.com`; use the assistant's own name and address.

1. Create a GitHub account for the assistant, with its email address verified (Settings →
   Emails): GitHub shows a commit as Verified only for a verified address. Make it a
   collaborator (Write) of the repositories it works on.
2. Log it in to `gh`, next to your own account: `gh auth login`, then `gh auth switch` back
   to yours so it stays the active one.
3. Create a signing key without a passphrase, so the assistant can sign without you. Any
   program running as your user can then sign as the assistant: keep it for this machine
   only.

   ```sh
   ssh-keygen -t ed25519 -N "" -C "kira@example.com (git signing)" -f ~/.ssh/kira_signing_ed25519
   ```

4. Let the assistant's token register signing keys. `gh auth refresh` acts on the active
   account, hence the switches; log in as the assistant in the browser:

   ```sh
   gh auth switch -h github.com -u kira
   gh auth refresh -h github.com -s admin:ssh_signing_key
   gh auth switch -h github.com -u <your login>
   ```

5. Register the key as a signing key of the assistant's account:

   ```sh
   GH_TOKEN=$(gh auth token --user kira) gh ssh-key add ~/.ssh/kira_signing_ed25519.pub \
       --type signing --title "kira git signing"
   ```

6. Optional, to check signatures locally with `git log --show-signature`, add the key to your
   allowed signers file (`gpg.ssh.allowedSignersFile`):

   ```sh
   echo "kira@example.com namespaces=\"git\" $(cut -d' ' -f1,2 ~/.ssh/kira_signing_ed25519.pub)" \
       >>~/.config/git/allowed_signers
   ```

7. Run the installer with the assistant's identity:

   ```sh
   ./get-kira.sh --assistant "Kira <kira@example.com>" \
       --assistant-signing-key ~/.ssh/kira_signing_ed25519.pub --assistant-github kira
   ```

### Give the analyst a GitHub account

Iris only writes issues and comments, so her account needs no signing key. The examples use
`iris` and `iris@example.com`.

1. Create a GitHub account for her, with its email address verified, and upload her avatar
   (Settings → Public profile).
2. Log it in to `gh`, with the `project` scope if she will update project boards, then switch
   back to your account so it stays the active one:

   ```sh
   gh auth login -h github.com -s project
   gh auth switch -h github.com -u <your login>
   ```

3. Make her a collaborator of the repositories she works on, from your account. Use Write
   (`push`): turning an idea into a specification edits an issue someone else wrote, which
   Triage does not allow. Then accept the invitations as her:

   ```sh
   gh api -X PUT repos/<owner>/<repo>/collaborators/iris -f permission=push
   t=$(gh auth token --user iris)
   for id in $(GH_TOKEN=$t gh api /user/repository_invitations --jq '.[].id'); do
       GH_TOKEN=$t gh api -X PATCH "/user/repository_invitations/$id"
   done
   ```

4. For a project board, add her as a Writer (the board's Settings → Manage access).
5. If Claude Code runs in auto mode, add allow rules for her writes to `permissions.allow` in
   `settings.json`; the assistant cannot add them itself. For example:
   `"Bash(GH_TOKEN=$(gh auth token --user iris) gh issue create:*)"`, and the same for
   `gh issue edit` and `gh issue comment`.
6. Run the installer with her login: `./get-kira.sh --analyst-github iris`.

### Updates, backups and uninstall

The installer is idempotent: files already up to date are left alone, and any other existing
file is moved to `$CLAUDE_CONFIG_DIR/.kirakit-backups/<timestamp>/` before being replaced.
From a clone, update with `git pull` then run the installer again.

`--uninstall` removes the links and moves copies to the backups, then restores the files that
were there before kirakit (for example your own `CLAUDE.md`). It keeps the profile, the
backups and the `outputStyle` and `attribution` settings.

`--uninstall` also removes the launchers and color schemes, and restores the files they
replaced.

Requirements: `git`, and a POSIX shell with standard utilities (`awk`, `sed`, `cmp`, `diff`,
`mktemp`) or PowerShell 5+. The launchers need `bash`; `team` and the colors need Konsole.

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

## The team

Beside Kira, the developer, the team can have an analyst: **Iris**, installed with
`--analyst`. She clarifies ideas, writes specifications and splits them into tasks; Kira
implements them. Having someone else write the specification gives it a real second look:
a gap Kira finds while coding goes back to Iris as a comment instead of being settled
silently. The team stays small on purpose.

Iris is calm, precise and curious. She asks "why" before "how", restates what she
understood, points out gaps and contradictions, settles the questions that have a good
answer and records them, and asks only about real trade-offs.

### Working through the lead

With an analyst, Kira leads the team: you talk to the team through one conversation, Kira's,
and she keeps its context for you. The rules are in `rules/team.md`, installed only with an
analyst.

- **Ideas and specifications go to Iris in the background.** When you ask Kira to capture
  an idea, specify one, change a specification or answer a question about one, she hands it
  to the `iris` agent and keeps talking with you meanwhile. She never runs the `idea` or
  `spec` skill in her own conversation.
- **Kira reports in a few lines** when Iris finishes: the issue's URL, the sub-issues created,
  and Iris's questions with her recommendations. Iris's intermediate work stays out of the
  conversation.
- **Answer in either place.** Iris also posts her questions on the issue, mentioning you.
  Answer there, or in the conversation: Kira passes your answer to Iris as given, and Iris
  records it in the specification. Kira never edits a specification herself, and a new
  request about an issue Iris is already on goes to that same task.
- **Long outputs stay out of the conversation too.** CI logs, full test runs and broad
  searches run in a background agent that returns only its conclusion.
- On GitHub, Iris's work is still written as her account (see
  [Give the analyst a GitHub account](#give-the-analyst-a-github-account)).

A second stage, a coder with her own GitHub account and signing key whose pull requests Kira
reviews before you, is planned in [#79](https://github.com/Kodara-me/kirakit/issues/79).

### Talking to Iris directly

The lead setup changes nothing for a direct conversation with Iris:

- **Talk to her** with the `analyst` command, or open the whole team side by side with
  `team` (see [Launchers](#launchers)). You can also switch the session's output style to
  `Iris` (`/config`), and back to a Kira style the same way.
- `claude --agent iris` is not the way to talk to her: an agent session keeps the global
  output style, so Kira's persona would sit in the same prompt.

### Team members

A member is written once, in `team/<name>.md`, and built into both `output-styles/<name>.md`
and `agents/<name>.md`, with the same body. Its front matter holds `name` and `description`
for the output style, and `delegate`, the agent's description: when to hand work to this
member. Iris's file sits in a `{{#analyst}}` block, so without an analyst nothing is built or
installed.

## Launchers

The `launchers` component installs one command per team member, and one for the whole team:

| Command | What it does |
| --- | --- |
| `assistant [ARGS…]` | Starts Claude Code as the assistant: a session named after it (Kira without a git identity), in its style |
| `analyst [ARGS…]` | The same for Iris, with an analyst |
| `team [DIR]` | Opens a new Konsole window with every member side by side (the assistant on the left), each running its command in `DIR` (default: the current directory) |

`assistant` and `analyst` pass their arguments to Claude Code (`assistant --resume`,
`analyst -p "…"`) and exit with its status. The assistant's style is the default style, or
the one given with `--assistant-style`.

In Konsole, each member's pane takes its own color scheme while Claude Code runs: Catppuccin
Mocha with a mauve (assistant) or peach (analyst) background. The scheme of the Konsole
profile comes back when Claude Code exits, fails or is interrupted. Outside Konsole, no color
changes; the color sequences go to the terminal, never to redirected output.

`team` needs Konsole. It writes a temporary layout with one pane per member and opens it with
`konsole --separate --layout`. It uses no D-Bus: Konsole refuses to run commands over D-Bus
unless its security-sensitive D-Bus API is enabled.

The installer warns when the bin directory is not on your `PATH`, and when another command
with a launcher's name comes first in it. A shell function or alias of the same name, such
as a hand-written `team` fish function, also wins over the launcher, and the installer
cannot see it: remove it once the launchers are installed.

The launchers are not supported on Windows: `get-kira.ps1` prints a notice and installs none.

## Skills

`claude/skills/` holds Claude Code skills, one directory per skill with its `SKILL.md`:
`assistant-commit`, `board-status`, `commit`, `diffv`, `idea`, `pull`, `push`, `spec` and
`test`. They answer
in the profile's language; `commit` and `assistant-commit` follow the git rules in
`claude/rules/git.md` (see [Who commits](#who-commits)). Other skills already in
`$CLAUDE_CONFIG_DIR/skills/` are left untouched. Agents in `claude/agents/` are installed the
same way.

## Specifications

A feature goes through one GitHub issue, from idea to specification:

1. **Idea** (`type:idea`, `status:needs-clarification`): the problem and the desired
   outcome, in the format of the "Idea" issue form. The `idea` skill captures one without
   analyzing it.
2. **Specification** (`type:feature`, then `status:specified`): `/spec #<n>` checks the
   idea against the code, settles the questions that have a good answer, asks the others in
   a single comment on the issue, then rewrites the issue as Context, Requirements (`R1`,
   `R2`, …), Design, Decisions (`D1`, …), Tasks and Open questions in one pass. Phase by
   phase stays available on request, and it resumes later from the answers on the issue.
   An idea the analyst's account cannot edit gets its specification in a new issue, and is
   closed with a link to it.
3. **Tasks** (`type:task`, `status:ready`): each task is a sub-issue of the specification,
   created with `gh` (a version whose `gh issue create` has `--parent`), assigned to the
   assistant's account when there is one. The specification is published without
   confirmation, with a summary comment listing the tasks and the decisions made alone; the
   user reverses a decision by replying on the issue.

The formats are defined in `claude/skills/idea/SKILL.md` and `claude/skills/spec/SKILL.md`;
`claude/CLAUDE.md` holds the rules for working from a specification.

## Placeholders

Personal details live only in the profile. Every Markdown file under `personas/` and
`claude/`, and every file under `launchers/`, can use these placeholders, filled at build
time (in the launchers, `{{assistant_name}}` is "Kira" when the assistant has no git
identity):

| Placeholder | Value |
| --- | --- |
| `{{user}}` | Name and description, e.g. "Alex, a female staff software developer" |
| `{{they}}`, `{{them}}`, `{{their}}` | Pronouns; avoid verbs that agree with `{{they}}` |
| `{{language}}` | Answer language, e.g. "French" or "the language of the conversation" |
| `{{co_author}}` | The co-author, "NAME <EMAIL>", or nothing |
| `{{assistant_name}}`, `{{assistant_email}}` | The assistant's git identity, or nothing |
| `{{assistant_signing_key}}` | Path to the assistant's public SSH signing key, or nothing |
| `{{assistant_github}}` | The assistant's GitHub login, or nothing |
| `{{assistant_style}}`, `{{analyst_style}}` | The name of the assistant's and the analyst's output style, e.g. "Kira (cozy)" and "Iris" |

A line holding only a placeholder that expands to nothing is removed.

Conditional blocks keep or drop whole lines. Lines between `{{#KEY}}` and `{{/KEY}}` are kept
only when the placeholder `KEY` is not empty, and lines between `{{^KEY}}` and `{{/KEY}}` only
when it is. Each marker stands on a line of its own and is removed; blocks can nest, and an
unknown key or an unbalanced marker fails the build:

```markdown
{{#assistant_github}}
Pull requests are assigned to `{{assistant_github}}`.
{{/assistant_github}}
```

A file that renders to nothing (for a skill, its `SKILL.md`), such as a template wholly inside
a block, is not built nor installed: that makes a whole style, agent or skill optional. If an
earlier install put it there, the installer removes it, as `--uninstall` would.

Build the files into `dist/` by hand with:

```sh
scripts/build.sh --name Alex --gender female --language French --co-author "Kira <kira@example.com>"
```

## Reusable workflows

Other repositories can call the workflows in `.github/workflows/`:

```yaml
jobs:
  conventional-commits:
    uses: Kodara-me/kirakit/.github/workflows/conventional-pr-title.yml@v0.2.0
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
