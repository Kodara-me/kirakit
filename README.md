# kirakit

Single source of truth for my development and AI tooling configuration, installable on any
machine with one command.

## Contents

| Path | Purpose |
| --- | --- |
| `personas/` | Claude Code output styles: `_core.md` holds the traits shared by every persona, each other file is an overlay (`kira-cozy.md`, …) |
| `team/` | Team members beside Kira, one file each (`iris.md`, `cleo.md`), built into an output style and an agent |
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
| `output-styles/iris.md`, with an analyst; `output-styles/cleo.md`, with a coder | `styles` |
| `CLAUDE.md`, `rules/git.md`, `skills/*`, `agents/*` (`rules/team.md` with an analyst or a coder, `agents/iris.md` with an analyst, `agents/cleo.md` and `agents/kira.md` with a coder) | `claude` |
| `outputStyle`, `attribution` and the members' rules in `permissions.allow` in `settings.json` | `claude` — only these are changed; the file is edited in place (see [Permission rules](#permission-rules)) |
| `.kirakit-profile`, `.kirakit-manifest`, `.kirakit-originals` | Profile and the record used by `--uninstall` |
| `.kirakit-permissions` | The permission rules kirakit added to `settings.json`, one per line |
| `.kirakit-backups/<timestamp>/` | Files that were replaced or removed |

Outside it, on Linux and macOS (see [Launchers](#launchers)):

| Path | Component |
| --- | --- |
| `assistant`, `team`, `kirakit-session`, `kirakit-watch` in `~/.local/bin` (or `--bin-dir`; `$CLAUDE_CONFIG_DIR/bin` with a non-default configuration directory) | `launchers` |
| `analyst` in the same directory, with an analyst | `launchers` |
| `kirakit-analyst.json`, the `kirakit-analyst/` plugin and `kirakit-analyst.md` in the same directory, with an analyst: the settings, style, skills and prompt of the analyst's session (see [The analyst's session](#the-analysts-session)), not executable | `launchers` |
| `kirakit-assistant.colorscheme` in `$XDG_DATA_HOME/konsole` (default: `~/.local/share/konsole`; or `--color-scheme-dir`; `$CLAUDE_CONFIG_DIR/konsole` with a non-default configuration directory) | `launchers` |
| `kirakit-analyst.colorscheme` in the same directory, with an analyst | `launchers` |

The `github` component is installed only on request (`--only github`), into a repository's
`.github/`: issue templates (bug report, and a feature request written as a specification),
a pull request template, Copilot instructions, and a workflow that checks pull request titles.

### Options

`get-kira.ps1` takes the same options in PowerShell form (`-DryRun`, `-Name`, `-CoAuthor`,
`-Coder`, `-CoderSigningKey`, `-CoderGithub`, `-AllowReleases`, `-NoAllowReleases`,
`-CompleteApprovedPrs`, `-NoCompleteApprovedPrs`, `-StartVerifiedSpecs`,
`-NoStartVerifiedSpecs`, `-BinDir`, `-ColorSchemeDir`, …; see
`Get-Help .\get-kira.ps1 -Detailed`). `-BinDir DIR` and `-ColorSchemeDir DIR` are `--bin-dir`
and `--color-scheme-dir` for `get-kira.ps1`: absolute paths (a leading `~/` is expanded), saved
in the profile as `bin_dir` and `color_scheme_dir` only when passed (a saved value is kept), so
that both installers accept the same command line. `get-kira.ps1` installs no launchers or
color schemes and writes nothing in either directory.

| Option | Effect |
| --- | --- |
| `--dry-run` | Print what would change, change nothing |
| `--name NAME` | How Kira calls you |
| `--gender GENDER` | `male`, `female`, `nonbinary` or `unspecified` (sets the pronouns Kira uses) |
| `--language LANGUAGE` | Answer language, or `auto` to follow the conversation |
| `--assistant "NAME <EMAIL>"` | The assistant's git identity: its own commits, and its trailer in yours |
| `--assistant-signing-key PATH` | The assistant's public SSH signing key (empty: it never commits as itself; with a coder, the coder commits its work) |
| `--assistant-github LOGIN` | The assistant's own GitHub account (empty: none) |
| `--co-author "NAME <EMAIL>"` | Same as `--assistant`, with `Co-Authored-By` trailers |
| `--no-co-author` | Add no `Co-Authored-By` trailer |
| `--analyst` | Add Iris, an analyst for ideas and specifications, to the team |
| `--no-analyst` | No analyst: Kira writes ideas and specifications herself |
| `--analyst-github LOGIN` | The analyst's own GitHub account (implies `--analyst`; empty: none) |
| `--coder "NAME <EMAIL>"` | Add Cleo, a coder who implements the tasks, with her git identity (default: none) |
| `--coder-signing-key PATH` | The coder's public SSH signing key (empty: she does not commit, and the assistant commits her work) |
| `--coder-github LOGIN` | The coder's own GitHub account (empty: none) |
| `--allow-releases` | Let the assistant's GitHub account create releases and push tags without a prompt (saved in the profile) |
| `--no-allow-releases` | Releases and tags stay behind a prompt (default; saved in the profile) |
| `--complete-approved-prs` | With a coder, let the assistant merge the coder's pull requests it approved without your review (saved in the profile) |
| `--no-complete-approved-prs` | Every pull request waits for your review (default; saved in the profile) |
| `--start-verified-specs` | With an analyst and a coder, let the assistant verify the analyst's specifications and move the verified ones to Ready without you; you are asked only security questions (saved in the profile) |
| `--no-start-verified-specs` | Every specification waits in Specified for you (default; saved in the profile) |
| `--soft-rules` | Keep you out of the loop for what is not a security question: the team applies its own recommendations and reports them; turns on `--complete-approved-prs` with a coder and `--start-verified-specs` with an analyst and a coder (saved in the profile) |
| `--no-soft-rules` | Strict rules: the team asks you its questions (default; saved in the profile) |
| `--default-style PERSONA` | Style selected in `settings.json` (default: `kira-cozy`) |
| `--assistant-style PERSONA` | Style of the `assistant` launcher (default: the default style) |
| `--bin-dir DIR` | Where the launchers go, an absolute path (default: `~/.local/bin`, or `bin/` in a non-default configuration directory; saved in the profile) |
| `--color-scheme-dir DIR` | Where the Konsole color schemes go, an absolute path (default: `konsole/` in `XDG_DATA_HOME`, or `konsole/` in a non-default configuration directory; saved in the profile) |
| `--reconfigure` | Ask all profile questions again |
| `--persona NAME` | Install only this persona (repeatable; default: all) |
| `--only COMPONENT` | `styles`, `claude`, `launchers` or `github`; default: `styles`, `claude` and `launchers` |
| `--target DIR` | Repository for `--only github` (default: the current one) |
| `--link` / `--copy` | Force symlink or copy mode |
| `--uninstall` | Remove what kirakit installed and restore the files it replaced |

Environment variables:

- `CLAUDE_CONFIG_DIR` — Claude Code configuration directory (default: `~/.claude`)
- `XDG_DATA_HOME` — where the Konsole color schemes go without `--color-scheme-dir`, in
  `konsole/` (default: `~/.local/share`); ignored when `CLAUDE_CONFIG_DIR` is not `~/.claude`
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
  so there is no signing key to give for her;
- the coder, Cleo: her name and email (an empty email means no coder), then the path to her
  public SSH signing key and her GitHub login (both optional).

A profile saved by an earlier version, with a `co_author` value, is migrated: the co-author
becomes the assistant, with trailers. A profile saved before the analyst reads as no analyst,
and the question is not asked again: pass `--analyst` or `--analyst-github` to add her. A
profile saved before the coder reads as no coder in the same way: pass `--coder` to add her.
The coder's values are saved as `coder`, `coder_signing_key` and `coder_github`.
`--allow-releases` is not asked: it is saved as `allow_releases` (`yes` or `no`, default `no`)
and kept until `--no-allow-releases`. `--complete-approved-prs` is not asked either: it is
saved as `complete_approved_prs` (`yes` or `no`, default `no`) and kept until
`--no-complete-approved-prs`. It applies only with a coder, and a profile saved before it
reads as `no`. `--start-verified-specs` is not asked either: it is saved as
`start_verified_specs` (`yes` or `no`, default `no`) and kept until
`--no-start-verified-specs`. It applies only with both an analyst and a coder (otherwise the
installed files are those of an install without it), and a profile saved before it reads as
`no`. `--soft-rules` is not asked either: it is saved as `soft_rules` (`yes` or `no`, default
`no`) and kept until `--no-soft-rules`, and a profile saved before it reads as `no`. Giving
`--no-complete-approved-prs` or `--no-start-verified-specs` with the soft rules on is an
error, since they include both.

The answers are saved in `$CLAUDE_CONFIG_DIR/.kirakit-profile` and reused by later runs; only
questions that are not answered yet are asked. Options override the saved values, and
`--reconfigure` asks everything again. Without a terminal, unanswered values fall back to
defaults: no name, `unspecified`, `auto`, no assistant, no analyst, no coder; the optional assistant
values default to empty, and trailers to yes when there is an assistant. The launcher
locations (`bin_dir`, `color_scheme_dir`) are saved only when passed with `--bin-dir` or
`--color-scheme-dir`, never as their default; later runs use a saved one, `--uninstall`
included.

With a `CLAUDE_CONFIG_DIR` other than `~/.claude`, and no saved or passed location, the
launchers go in `$CLAUDE_CONFIG_DIR/bin` and the color schemes in `$CLAUDE_CONFIG_DIR/konsole`
(`XDG_DATA_HOME` is ignored), so that a run aimed at a scratch directory never touches your own
launchers; cleaning up and `--uninstall` skip, and log, any manifest path in `~/.local/bin` or
the default color scheme directory in that case. Every run that installs launchers logs both
directories. With `CLAUDE_CONFIG_DIR` unset, the defaults are `~/.local/bin` and
`${XDG_DATA_HOME:-~/.local/share}/konsole`.

### Who commits

The git rules (`rules/git.md`, which Claude Code loads on its own) follow the profile:

- **You commit** with the `commit` skill, under your git identity. With trailers on, the
  message ends with `Co-Authored-By:` and the assistant's name and email.
- **The assistant commits** the code it wrote with the `assistant-commit` skill, under its own
  name and email, signed with its own SSH key, and you are the co-author. Its identity and key
  are passed on the `git` command line: your git configuration is never changed. Without a
  signing key in the profile, the assistant never commits as itself (with a coder, Cleo
  commits its work instead).
- **With a GitHub account** for the assistant (`--assistant-github`), the rules also say how
  it works on GitHub: everything it writes uses its own token, its pull requests ask for your
  review, and its questions are asked both in the conversation and in a comment.
- **With an analyst,** a "The team" section adds that Iris never commits, and that a gap found
  in a specification while coding is asked to her in a comment rather than settled alone.
  With her own GitHub account (`--analyst-github`), her work (ideas, specifications,
  sub-issues, labels and clarification comments) is written as that account, whoever does
  it; the `idea` and `spec` skills use it too. Any login works, your own included.
- **With a coder,** Cleo writes the code by default, commits it with `assistant-commit` under
  her own identity and key, and opens the pull requests; the assistant leads, and writes code
  itself only when you explicitly ask it to in the conversation, for the task or change you
  name. It then commits that work under its own identity and key, opens its pull request as
  its own account with you as reviewer, and never reviews it itself: it waits for your own
  approval, even with `--complete-approved-prs`. Each of them commits her own work with her
  key; when one has no key, she leaves her changes uncommitted and the other commits them,
  with the writer as the commit's author, and the writer still pushes and opens the pull
  request. With neither key, nothing is committed and the `commit` skill is proposed. With
  her own GitHub account (`--coder-github`), her pull requests, comments, replies and board
  moves are written as that account, and her pull requests ask for the assistant's review.

  With `--complete-approved-prs` (off by default; it applies only with a coder), the
  assistant completes a pull request of the coder on its own approval, without requesting
  your review, when all of these hold: its CI checks all pass, or the repository has none
  and the assistant decides it can, giving its reason in its review; the review's "For the
  user" part says `Nothing.`; the assistant has no question, remark or disagreement for you;
  it closes at least one task; and you have neither requested changes on it nor asked to
  review it or its specification's pull requests. It then labels the pull request
  `review:lead-only`, merges it by the usual rules and mentions you nowhere on GitHub for
  it. When any condition fails, it falls back to the usual flow: it requests your review,
  moves the pull request to In review and says which condition failed. When such a pull
  request closes the last open task of a specification (or a task with no specification),
  the assistant posts a comment there that mentions you and lists every pull request of it
  merged without your review. The assistant's own pull requests always wait for your
  approval.

The installer also sets `"attribution": {"commit": "", "pr": ""}` in `settings.json`, so
Claude Code stops suggesting its own trailer and pull request footer. If `attribution` is
already set to something else, it is left unchanged, with a warning.

### Permission rules

In auto mode, Claude Code blocks a member's GitHub writes (issues, pull requests, comments,
pushes) as external writes, and the assistant cannot add permission rules itself. So for each
member with a GitHub account in the profile, the installer adds narrow rules to
`permissions.allow` in `settings.json`, one per sub-command. In the rules below, `P` stands
for `GH_TOKEN=$(gh auth token --user LOGIN) gh`, with that member's login:

| Member | Rules |
| --- | --- |
| Assistant (`--assistant-github`) | `Bash(P issue create:*)`, `issue edit`, `issue comment`, `issue close`; `Bash(P pr create:*)`, `pr comment`, `pr review`; `Bash(P label create:*)`; `Bash(git push -u origin TYPE/:*)` and `Bash(git push origin TYPE/:*)` for `feat`, `fix`, `docs`, `refactor`, `test`, `chore` and `ci`; `Bash(git push origin main)`; `Bash(git push origin --delete:*)`; `Bash(P project item-edit:*)` and `Bash(P project item-add:*)` |
| Assistant, with `--allow-releases` | Also `Bash(P release create:*)` and `Bash(git push origin v:*)` |
| Assistant, with a coder's account | Also `Bash(P pr edit:*)`, to request your review on the coder's approved pull requests, and to add itself as assignee and you as reviewer on a pull request it takes over |
| Analyst (`--analyst-github`) | `Bash(P issue create:*)`, `issue edit`, `issue comment`, `issue close`; `Bash(P label create:*)`; `Bash(P project item-edit:*)` and `Bash(P project item-list:*)` |
| Coder (`--coder-github`) | `Bash(P issue create:*)`, `issue edit`, `issue comment`; `Bash(P pr create:*)`, `pr comment`, `pr review`, `pr edit`; the assistant's work branch pushes; `Bash(git push origin --delete TYPE/:*)` for the same branch types; `Bash(P project item-edit:*)` and `Bash(P project item-add:*)`. Nothing that pushes or deletes `main`: the assistant merges |

A member without a GitHub account gets no rules. The `git push` rules are not tied to an
account: with a coder, `git push origin main` is still there when the assistant has an account,
since the assistant merges. An allowed rule only removes the prompt: the git rules still ask for an
explicit request before a release or a tag. `--dry-run` lists the rules that would be added or
removed.

**Ownership.** The installer records the rules it inserts in
`$CLAUDE_CONFIG_DIR/.kirakit-permissions`, as one set for all members.

- A rule that was already in `permissions.allow` before kirakit would add it stays yours: it is
  not added again, not recorded, and no later install, update or uninstall removes it.
- A rule you add by hand that is identical to one kirakit added belongs to kirakit: when the
  rule is no longer expected, one occurrence of it is removed.
- A rule shared by several members (the `git push` rules, or the same login for two members)
  stays as long as one of them expects it.

**Adding and dropping rules.** Any other rule you add to `permissions.allow` is yours and kept
as it is. kirakit's rules are dropped through the profile, not by deleting their lines: remove
the member's account (`--assistant-github ''`, `--analyst-github ''` or `--no-analyst`), change
it (the old login's rules are replaced), or pass `--no-allow-releases`. A kirakit rule deleted
by hand while still expected comes back on the next install. `--uninstall` removes the rules
kirakit recorded, and only those.

**Limits.** Without a JSON parser, the file is edited by text processing, only in shapes it
recognizes: a missing or empty file, no `permissions` key (one is added as the first setting),
or a single `"allow"` key whose array is empty or opens at the end of its line. Removing a
rule also needs it alone on its line in that array; the comma after it (or before it, for the
last rule) goes with it. In any other shape (several `"allow"` keys, an array on one line
holding rules, …), `settings.json` is left unchanged and a warning prints the rules to add or
remove by hand. A refused removal also blocks the additions of that run; on an update the
record is kept so that a later run retries, and on `--uninstall` it is deleted, since the
rules were handed to you.

### Give the assistant its own identity

The installer never creates or uploads keys: these steps are done once, by hand. The examples
use `kira` and `kira@example.com`; use the assistant's own name and address.

1. Create a GitHub account for the assistant, with its email address verified (Settings →
   Emails): GitHub shows a commit as Verified only for a verified address. Give it Write
   access to the repositories it works on: as a collaborator, or in an organization through a
   team that has it (see [Repositories in an organization](#repositories-in-an-organization-optional)).
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

3. Give her a role on the repositories she works on, from your account. On a repository
   owned by your personal account, make her a collaborator with Write (`push`): Read would
   keep her from labelling and assigning issues and linking sub-issues, and Triage is not
   offered there. Her token can then push, so her restriction to issues holds only in her
   sessions. In an organization, give her Triage instead, so that GitHub itself keeps her
   from pushing (see [Repositories in an organization](#repositories-in-an-organization-optional)).
   On a personal repository, invite her, then accept the invitations as her:

   ```sh
   gh api -X PUT repos/<owner>/<repo>/collaborators/iris -f permission=push
   t=$(gh auth token --user iris)
   for id in $(GH_TOKEN=$t gh api /user/repository_invitations --jq '.[].id'); do
       GH_TOKEN=$t gh api -X PATCH "/user/repository_invitations/$id"
   done
   ```

4. For a project board, add her as a Writer (the board's Settings → Manage access); a board
   owned by an organization can be shared with her team instead.
5. Run the installer with her login: `./get-kira.sh --analyst-github iris`. It also adds the
   allow rules her writes need in auto mode (see [Permission rules](#permission-rules)).

### Give the coder her own identity

Cleo commits, so she needs both a GitHub account and a signing key, set up like the
assistant's. Without her key, the assistant commits her work with its own key, with Cleo as
the commit's author; without the assistant's key, Cleo commits the code the assistant writes
at your request the same way. Give each of them a key so that each commits her own work. The examples use `cleo` and `cleo@example.com`.

1. Create a GitHub account for her, with its email address verified, and upload her avatar
   (Settings → Public profile).
2. Log it in to `gh`, with the `project` scope for the board, then switch back to your
   account so it stays the active one:

   ```sh
   gh auth login -h github.com --skip-ssh-key -s project
   gh auth switch -h github.com -u <your login>
   ```

3. Give her Write access to the repositories she works on: in an organization, add her to a
   team that has it (such as `developers`, see
   [Repositories in an organization](#repositories-in-an-organization-optional)); otherwise,
   make her a collaborator (`push`) and accept the invitations as her, as for the analyst. For a project board, add her as a
   Writer if the team does not give her access.
4. Create a signing key without a passphrase, and register it on her account as a signing
   key only (Settings → SSH and GPG keys → New SSH key → Key type: Signing Key), not as an
   authentication key: pushes go through your own access, and a key without a passphrase
   should not open her account.

   ```sh
   ssh-keygen -t ed25519 -N "" -C "cleo@example.com (git signing)" -f ~/.ssh/cleo_signing_ed25519
   ```

5. Run the installer with her identity. With her GitHub account, it also adds the allow rules
   her writes need in auto mode (see [Permission rules](#permission-rules)):

   ```sh
   ./get-kira.sh --coder "Cleo <cleo@example.com>" \
       --coder-signing-key ~/.ssh/cleo_signing_ed25519.pub --coder-github cleo
   ```

### Repositories in an organization (optional)

This setup is optional: with repositories owned by your personal account, the steps above are
all there is to do. The installer, the launchers and the analyst's session behave the same
whatever the owner of the repositories and the roles of the members.

On a repository owned by a personal account, a collaborator is Read, Write or Admin, so the
analyst gets Write and her restriction to issues holds only in her sessions. A repository
owned by an organization also offers the **Triage** role, which manages issues without push
access: the restriction then holds on GitHub's side too, even if her token is used outside a
session. Her session's own limits stay as a second layer.

With Triage, the analyst can open, comment on, label, assign and close issues, and link
sub-issues. She cannot push, commit through the API, or edit the body of an issue she did not
write: when she specifies an idea someone else wrote, the `spec` skill opens the
specification in a new issue that links to the idea, and closes the idea with a comment
pointing to it.

**Recommended setup: one team per role.** In the organization (Settings → Teams):

- a team `developers` with Write, for the assistant's and the coder's accounts;
- a team `analysts` with Triage, for the analyst's account;
- each repository the team works on added to both teams, including a repository created or
  moved into the organization later;
- the members' base permission (Settings → Member privileges) no higher than Read: with Write,
  every member, the analyst included, could push to every repository;
- the organization's project boards shared with both teams as Writers (the board's Settings →
  Manage access).

The alternative is a role per repository and per member, given as a collaborator
(`gh api -X PUT repos/<owner>/<repo>/collaborators/<login> -f permission=triage`, or `push`
for Write), with the boards shared with each member as a Writer. Teams need one step per
team for a new repository instead of one per member.

**Check the roles** of each member on a repository:

```sh
gh api repos/<owner>/<repo>/collaborators/<login>/permission --jq .role_name
```

It prints `triage` for the analyst and `write` for the assistant and the coder.

**Moving existing repositories** to the organization (the repository's Settings → Transfer
ownership) implies:

- the web and git URLs of the old owner redirect to the new ones, until a repository with the
  same name is created under the old owner: do not reuse the name;
- git remotes (`git remote set-url origin …`), install URLs and reusable workflow references
  (`uses: <owner>/<repo>/.github/workflows/…@<tag>`) are to be updated, the latter to a tag
  that exists under the new owner;
- project boards owned by your personal account do not move: recreate them under the
  organization and share them with the teams;
- the members' roles are to be checked after the move, with the command above.

### Updates, backups and uninstall

The installer is idempotent: files already up to date are left alone, and any other existing
file is moved to `$CLAUDE_CONFIG_DIR/.kirakit-backups/<timestamp>/` before being replaced.
From a clone, update with `git pull` then run the installer again.

`--uninstall` removes the links and moves copies to the backups, then restores the files that
were there before kirakit (for example your own `CLAUDE.md`). It removes the permission rules
kirakit recorded, and only those, then the record. It keeps the profile, the backups and the
`outputStyle` and `attribution` settings.

`--uninstall` also removes the launchers and color schemes, and restores the files they
replaced.

Requirements: `git`, and a POSIX shell with standard utilities (`awk`, `sed`, `cmp`, `diff`,
`mktemp`) or PowerShell 5+. The launchers need `bash`; `team` and the colors need Konsole.

`CLAUDE.md`, `rules/`, `skills/`, `agents/` and `output-styles/` in `$CLAUDE_CONFIG_DIR` are
built from the repository, so an edit made to them in place is not kept by the next install.
Make the change in the repository, then install again.

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

Shared rule: the personality shows in the conversation and in each member's comments on
GitHub (issues, pull requests, review comments and replies). Issue bodies, pull request
descriptions, commits, code, code comments and documents stay neutral and professional.

## The team

Beside Kira, the team can have an analyst: **Iris**, installed with `--analyst`. She
clarifies ideas, writes specifications and splits them into tasks; Kira implements them.
Having someone else write the specification gives it a real second look: a gap found while
coding goes back to Iris as a comment instead of being settled silently.

The team can also have a coder: **Cleo**, installed with `--coder`. She implements the tasks
and opens the pull requests, and Kira becomes the lead: she hands Cleo the work, reviews her
pull requests before you do, and merges once you approve. The team stays small on purpose.

Iris is calm, precise and curious. She asks "why" before "how", restates what she
understood, points out gaps and contradictions, settles the questions that have a good
answer and records them, and asks only about real trade-offs.

Cleo is modest and practical, and speaks like a clean terminal log: what she changed, what
she ran, what passed. She marks her status lines with a `>` instead of emoticons, and when
she is blocked she asks one precise question.

Each member's voice shows in the conversation and in her comments on GitHub (issues, pull
requests, review comments and replies). Issue bodies, pull request descriptions, commits,
code and documentation stay neutral, whoever writes them.

You are mentioned on GitHub only when you must answer or act. Every member, Kira, Iris and
Cleo alike, follows the same rule from `rules/git.md`, installed with every profile:

- **Mentioned** (`@` and your login): a question, a decision, options to choose from, or an
  action only you can take that nothing else notifies you of, such as reviewing a pull
  request you are not requested on. Such a comment ends with a short question ("Can I
  continue?").
- **In a comment of its own**: what you must decide is never buried in a long comment. The
  status, the settled items and the exchanges between members keep their usual level of
  detail in a first comment that does not mention you, then a second, short comment mentions
  you and holds only what you must decide: each question with its options and the member's
  recommendation, or the action asked. This is the same for a clarification from Iris, a
  specification summary with questions, a review from Kira whose "For the user" holds a
  question, and Cleo's questions.
- **Not mentioned**: a request for your review, whose notification is the request itself;
  progress, hand-offs, merge reports, approvals with nothing for you, a next step that needs
  no decision, a specification ready to start. These are still posted, neutral, without a
  closing question. The only exception is a notification a rule asks for by name.
- **Between members**: a comment that needs another member (changes for Cleo, a gap for
  Iris) mentions her account. It is a notification only: her work still starts from Kira's
  conversation. A gap found in a specification mentions Iris, not you; she asks you herself
  when it is a real trade-off.

### Answering from a team account

You can answer the team from whichever account your phone or browser is on. When a member
has a GitHub account, her session marks what it writes there, so that a reply you post from
a team account after switching still reads as yours:

- **Session marker.** Every comment, review and review reply a member writes as her account
  ends with a hidden HTML comment naming her role, `<!-- kirakit:assistant -->`,
  `<!-- kirakit:analyst -->` or `<!-- kirakit:coder -->`, invisible once rendered. Issue and
  pull request bodies stay unmarked.
- **Your replies.** A comment counts as your reply when it comes from your account, or from
  a team account without a marker and after the latest marked comment of the thread (older
  threads, written before the marker, are not misread). A comment from any other account
  never counts, with or without a marker, so an outside contributor cannot drive the team.
- **Attribution.** The member who acts on a reply posted from a team account starts her
  next comment in that thread with one line: "Reply from <your login>, posted from the
  `<account>` account."
- **Approvals from your account only.** A review posted from a team account is never your
  approval, marker or not: nothing is merged on it, and you are asked, with a mention, to
  approve from your own account.

The rule lives in `rules/git.md` ("Session marker and the user's replies"), and the `spec`
skill reads your answers on an issue with it. It is installed only when at least one member
has a GitHub account.

### Working through the lead

With an analyst or a coder, Kira leads the team: you talk to the team through one
conversation, Kira's, and she keeps its context for you. The rules are in `rules/team.md`,
installed only with an analyst or a coder.

- **Ideas and specifications go to Iris in the background.** When you ask Kira to capture
  an idea, specify one, change a specification or answer a question about one, she hands it
  to the `iris` agent and keeps talking with you meanwhile. She never runs the `idea` or
  `spec` skill in her own conversation.
- **One line per automated turn.** In a turn you did not start (a watch line, a background
  agent finishing, a check she started, the start of the watch), Kira writes exactly one
  line in the conversation: the full URL of each issue, pull request or comment concerned,
  with what you must do in a few words (answer, review, approve, give your go, look at) or a
  few-word status (merged, in review, working, waiting), and never a rewrite of what the
  ticket shows. Questions, "For the user" items and decisions are on GitHub, where you
  answer them. In a turn you started, she keeps the detail the answer needs. The rule is in
  `rules/team.md`, and only governs Kira's own output: the reports of her background agents
  keep their format.
- **Kira reports in one line** when Iris finishes: the issue's URL and,
  for a question, the URL of the comment that holds it. The sub-issues, the questions and
  Iris's intermediate work stay on GitHub and out of the conversation.
- **Answer in either place.** Iris also posts her questions on the issue, in a comment of
  its own that mentions you (see [when you are mentioned](#the-team)).
  Answer there, or in the conversation: Kira passes your answer to Iris as given, and Iris
  records it in the specification. Kira never edits a specification herself, and a new
  request about an issue Iris is already on goes to that same task.
- **You start a specification, then you give the plan of each task.** When Iris finishes a
  specification with no questions for you, Kira's line gives its URL and "move it to Ready".
  Move it to Ready on the board, or tell Kira it can start: its tasks become workable, and
  Kira states the work plan of each one (in one line with the task's URL when the turn is
  automated, in full when you ask) and waits for your go before starting it (see
  [Development](#development-from-a-ready-specification)). With `--start-verified-specs`,
  Kira verifies it and makes it workable herself (below).
- **Only the lead's session watches GitHub.** With the assistant's GitHub account in the
  profile, the `watch` skill (run by the `assistant` launcher at its start, and by the
  assistant's pane of `team`) starts one `kirakit-watch` check per team account of the
  profile, the assistant's, the analyst's and the coder's, with Claude Code's Monitor tool,
  so Kira wakes only when a line is printed, and `/loop 10m` running them with `--once` as
  the fallback. The `analyst` launcher, Iris's pane of `team` and a plain `claude` session
  start no watch; the analyst and the coder run as Kira's background agents. Kira acts on a
  change once, whichever account reported it, and writes one line in the chat per action,
  nothing when nothing changed:
  - your reply on an idea or a specification assigned to Iris, or in a thread where she is
    mentioned, goes to the `iris` agent as given (to the running task on that issue when
    there is one); an idea newly assigned to her goes to her to specify; an assignment of a
    task or a specification starts nothing;
  - **How a specification wakes Kira.** It enters Ready when you move it to Ready on its
    board (the Ready column), or, on a repository with no board, when it carries the
    `status:ready` label; the same goes for an issue with no specification. The watch
    reports it, Kira runs `next-task` in that repository and gives the work plan for the task
    it gives as one line (the task's URL and the go asked), waits for your go, then hands the
    task to Cleo, or works on it herself
    without a coder. While a coder task is running, no other starts, and `next-task` runs
    again when her task ends with a pull request;
  - **Merging.** A review on a pull request of Cleo or of Kira leads to a merge only when your
    own latest review approves its last commit (`gh pr view --json reviews,commits`), or when
    Kira completes Cleo's pull request without you under `--complete-approved-prs`. Kira's own
    approval and a review posted from a team account never count. Changes you request on
    Cleo's pull request go back to Cleo;
  - a comment of yours answering a question of Cleo goes to Cleo; a gap she finds in a
    specification comes back with her report and goes to Iris from Kira's conversation, not
    through the watch;
  - a merge outside that rule, a tag or a release, and creating, editing or closing an issue
    other than Iris's own work stay yours: Kira asks in a comment that mentions you.
- **Long outputs stay out of the conversation too.** CI logs, full test runs and broad
  searches run in a background agent that returns only its conclusion.
- On GitHub, Iris's work is still written as her account (see
  [Give the analyst a GitHub account](#give-the-analyst-a-github-account)).

#### Soft rules

With `--soft-rules` (off by default, saved in the profile as `soft_rules`), the team stops
asking you what it can decide itself. The installer turns on `--complete-approved-prs` when
the profile has a coder, and `--start-verified-specs` when it has both an analyst and a coder;
without them those stay as they are. With the soft rules off, the installed files are those of
an install without the option.

What the soft rules relax:

- **Questions that are not security questions.** Whoever has one, Kira, Iris or Cleo, applies
  her own recommendation instead of asking you, records the choice and its reason in a comment
  on the issue or pull request (in the specification, for Iris) that does not mention you, and
  Kira's line is "look at" with the URL of that comment. A clarifying question with no
  recommendation to apply is still asked.
- **The review of a pull request of the coder.** Kira completes an approved pull request
  without your review when its "For the user" items are neither questions nor security-sensitive
  changes, the other conditions of `--complete-approved-prs` holding; those items go in the
  review she posts, and her line is "look at" with that review's URL.
- **Issues.** Kira may create an issue for a bug or a follow-up idea found during the team's
  work, and add or remove labels on the team's issues, without asking; her line is "look at"
  with that issue's URL for each one.

What always reaches you: every security question (see below), every pull request with a
security-sensitive change, the escalation after two verifications requesting changes, Kira's
disagreement with a review verdict, closing and deleting issues, tags and releases, and your
approval of the pull requests Kira writes herself.

#### Verified specifications

With `--start-verified-specs` (off by default, saved in the profile as
`start_verified_specs`; it applies only with both an analyst and a coder), a specification
no longer waits for you when it holds nothing for you to decide:

- **Iris settles every question that is not a security question**, the logical option
  each time, hard-to-reverse choices (public interface, data format, file layout you depend
  on) and scope included, and records each one under Decisions with its reason. For scope
  beyond the idea, she takes the narrower option and records the extension under Open
  questions as a possible follow-up. Her summary comment lists the decisions taken without
  you, the hard-to-reverse ones first, does not mention you, and ends with "Sent to Kira for
  verification."
- **Security questions always go to you.** A security question is an open choice about
  credentials, tokens or signing keys; permission rules or `allowed-tools`; Git identity or
  signing; network downloads or remote scripts that are executed; files written or deleted
  outside the project; CI workflows; accounts and their access rights; or data exposed
  outside your machine or to other people. Iris asks you each one, with her
  recommendation, in a comment of its own that mentions you, and the specification waits
  in Specified for your answer. A question flagged by Iris or by Kira is never settled by the
  other. A change to such a file that follows from your decisions or the existing rules is
  not an open choice: the pull request review flags it for you.
- **Kira verifies the specification** in the background, in the `kira` agent, shown as
  Kira with a status such as "Verifying spec #42", following the read-only `review-spec`
  skill. It checks that each requirement is a single testable statement, that every
  requirement is covered by a task, that the tasks follow the splitting rules, that every
  decision states its reason, that the specification matches the code and files it names,
  and that no decision taken without you settles a security question. It returns one
  verdict, which Kira posts on the specification as her own account and reports in her one
  line, with the specification's URL:
  - `verified`: Kira moves the specification to Ready (or adds `status:ready` on a
    repository with no board) and development starts as if you had moved it;
  - `changes requested`: back to Iris, who changes the specification, then a new
    verification. After two verdicts in a row requesting changes there is no third
    verification (never more than two rounds before you): Iris makes one last pass on the
    remaining comments, and Kira asks you to review the specification yourself, listing the
    comments Iris addressed. The specification stays in Specified until you move it to Ready;
    a comment of yours on it goes to Iris and back to your review, not to a verification;
  - `needs the user`: a security question was settled without you or left open. Kira asks
    you in a comment of its own that mentions you; once Iris has recorded your answer, the
    specification is verified again.
- **You object on the issue, or on the board.** The decisions and the verdict are on the
  issue, without mentioning you. Comment on a specification in Ready or In progress to
  object: no new task of it starts while your comment has no answer from a member after
  it, and Kira hands it to Iris, who answers or changes the specification. This needs all
  three members' own GitHub accounts (`--assistant-github`, `--analyst-github` and
  `--coder-github`), so that their comments can be told from yours: without one of them, no
  specification is paused by a comment. Moving the
  specification out of Ready and In progress still stops it, and pull requests, tags and
  releases keep their own rules (`--complete-approved-prs` decides whether you review a
  pull request).

With a coder, code goes through Cleo the same way:

- **Kira hands her the work.** The task `next-task` gives, and any change to code you ask
  for, goes to the `cleo` agent in the background, one task at a time, and a new request
  about Cleo's running task goes to that task. Kira writes code herself only when you
  explicitly ask her to in your own message ("write #155 yourself"): only the task or change
  you name, in parallel with Cleo when she is busy, waiting when it touches the same files as
  Cleo's task or a pull request in review. A request that does not clearly ask Kira herself
  ("do #155") still goes to Cleo. The other case is the takeover, below.
- **Cleo opens the pull request, Kira reviews it first.** The review runs in the `kira` agent,
  in the background like the other members: it appears among the running agents as Kira,
  with a status such as "Reviewing PR #42", and Kira keeps answering you meanwhile. The agent
  runs on Opus whatever model Kira's session uses, and follows the `review-pr` skill, which
  it preloads: it reads the pull request, its tasks and their specification, the diff, the
  CI checks and whether the branch can be fast-forwarded, through `gh` only, and returns a
  verdict (`approve`, `request changes` or `not ready` while CI runs) with its comments and a
  "For the user" section, while the diff stays out of Kira's conversation. It has no tool to
  write files and writes nothing: Kira posts its verdict on GitHub as her own account, in her
  own voice, and never approves against it. Like the members' rules (see
  [Permission rules](#permission-rules)), the review needs auto mode: a background agent
  cannot ask for a permission, and in the default mode its `gh` reads are refused. Once she
  approves, she requests your review; what the review flagged for you
  (security-sensitive changes, questions) is in the review she posts, and a question for you
  is in a comment that mentions you; the first changes requested, by her or by you, go
  back to Cleo, who makes them, replies to the comments and asks Kira again.
- **Cleo always runs on Sonnet; Kira takes over on Opus.** There is no Opus for the coder:
  the `model:opus` label is retired, and asking Kira for Opus for a task changes nothing. From
  the second review requesting changes on a pull request, by Kira or by you, Kira continues
  it herself, in a background agent on Opus that works as her (her identity and key, her
  account, the coder's branch, plain commits without force). She adds herself as assignee and
  you as reviewer, runs no `kira` review on it and never completes it without you: it is
  merged only on your own approval of its last commit, and the changes you request on it go
  to Kira again, never to Cleo. Without Kira's signing key, a `cleo` agent commits her changes
  with Kira as author; with no key on either side nothing is committed and Kira proposes your
  `commit` skill. Every pull request is still reviewed on Opus, which is what keeps Sonnet's
  work in check, and a pull request gets at most two rounds before it reaches you.
- **Kira reports in one line:** the pull request's URL with the action or status that fits
  (review, merged, working, waiting). Her review result, the tasks it closes, the number of
  reviews requesting changes and any question for you stay on GitHub, in her review and in a
  comment that mentions you. Cleo's intermediate work stays out of the conversation.
- **Kira merges after your own approval.** Her approval also counts in GitHub's
  `reviewDecision`, so she merges only when your latest review approves the last commit,
  then picks the next task.
- A gap Cleo finds in a specification goes to Iris (to you, without an analyst) in a comment
  on the issue, and that task waits for the answer.

### Talking to a member from the conversation

Each member has a command named after her, `/iris` with an analyst and `/cleo` with a coder,
available in every session. Type it with your request, for example
`/iris is the second requirement of #120 testable?`, and the member handles it in her own
persona, under her own rules and on her agent's model, without leaving the conversation:

- **One exchange.** The command runs forked: the request goes to the member's agent (her
  persona, model and tools) inside the current session, she answers, and the conversation
  goes on with the lead. No other session starts, and neither the output style nor the
  settings change.
- **Her own words.** The lead shows her answer as she wrote it, under her name, with at most
  one line of its own after it. Answer one of her questions through the lead, as usual, or
  with the command again.
- **Yours only.** Only you run these commands: the lead never runs one itself, and keeps
  handing work to the members as background agents.
- **No request.** Typed alone, the command makes the member ask, in one line, what you want
  from her.

`/iris` and `/cleo` run on Sonnet (see [Models](#models)). The lead has no command.

### Talking to Iris directly

The lead setup changes nothing for a direct conversation with Iris, except that her session
is restricted (see [The analyst's session](#the-analysts-session)):

- **Talk to her** with the `analyst` command, or open the whole team side by side with
  `team` (see [Launchers](#launchers)). You can also switch the session's output style to
  `Iris` (`/config`), and back to a Kira style the same way.
- `claude --agent iris` is not the way to talk to her: an agent session keeps the global
  output style, so Kira's persona would sit in the same prompt.

### Team members

A member is written once, in `team/<name>.md`, and built into both `output-styles/<name>.md`
and `agents/<name>.md`, with the same body, and into her command, `skills/<name>/SKILL.md`.
The build fails when a member has the same name as a skill of `claude/skills/`. Its front matter holds `name` and `description`
for the output style, and `delegate`, the agent's description: when to hand work to this
member, and `model`, the agent's model, which every member declares: the build fails without
it. Iris's file sits in a `{{#analyst}}` block and Cleo's in a `{{#coder}}` block, so without
them nothing is built or installed. Iris's and Cleo's agents run on Sonnet (Iris on Opus for
specification work, started by the lead); their
output styles keep the session's model.

## Launchers

The `launchers` component installs one command per team member, and one for the whole team:

| Command | What it does |
| --- | --- |
| `assistant [ARGS…]` | Starts Claude Code as the assistant: a session named after it (Kira without a git identity), in its style. With the assistant's GitHub account, the session starts with `/watch`, the lead's watch of GitHub, except with `-p` or `--print` |
| `analyst [ARGS…]` | The same for Iris, with an analyst, in a restricted session that starts no watch (see [The analyst's session](#the-analysts-session)) |
| `team [DIR]` | Opens a new Konsole window with every member side by side (the assistant on the left), each running its command in `DIR` (default: the current directory); the watch starts in the assistant's pane only |

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

`kirakit-watch ROLE [--once]` is the background check of a team account (`assistant`,
`analyst`, or `coder`, also called `developer`); the lead's session runs one per team account
in the profile. It reads the account's notifications with `If-Modified-Since` (a `304` costs
nothing) at most every 2 minutes, or less often when GitHub's `X-Poll-Interval` asks, and
prints one line, `KIND REPOSITORY#NUMBER URL`, per change: a new assignment, and a reply of
yours in a thread the member takes part in (a comment of your login, or an unmarked comment of
a team account posted after the latest marked comment of the thread, see the session marker
above; never a comment of another account). For `assistant` and `coder`, it also reports an
approving review of a pull request that account wrote. For `assistant` only, it reports a
specification that enters Ready, or an issue with no specification that enters a Ready
column, once: the boards read are those of your account and of the owner of every repository
with an open issue assigned to the assistant's account (each published specification and task
is), an organization included; a specification on no board of its owner counts when labelled
`status:ready`. It never looks for tasks: the `next-task` skill chooses one. GitHub does not
notify an account of its own comments, so the check also reads the threads the member's account
commented in that changed since the last check (`gh search issues --commenter`). A lookup that
fails changes nothing and is tried again on the next check. It prints nothing otherwise and writes
nothing to GitHub. The member's account comes from the profile (`analyst_github`,
`coder_github`, `assistant_github`), your login from `gh config get user`. State is kept in
`${XDG_STATE_HOME:-~/.local/state}/kirakit/watch-ROLE`, so a restart reports nothing twice;
`--once` checks a single time and exits. One check per role runs at a time: a second
continuous check exits at once with one line on standard error and a non-zero status, and
`--once` while a check of the same role runs prints nothing, checks nothing and exits
successfully. A lock left by a check that was killed is taken over. It needs `jq`.

The installer warns when the bin directory is not on your `PATH`, and when another command
with a launcher's name comes first in it. A shell function or alias of the same name, such
as a hand-written `team` fish function, also wins over the launcher, and the installer
cannot see it: remove it once the launchers are installed.

The launchers are not supported on Windows: `get-kira.ps1` prints a notice and installs none,
so the analyst's restricted session and the watch are not available there either.

### The analyst's session

`analyst` starts Iris's session with her settings file, `kirakit-analyst.json`, beside the
launchers, as the only `--settings`, together with `--setting-sources=` and
`--permission-mode dontAsk`. Since no user settings load, it also passes her plugin,
`kirakit-analyst/` (her output style and the `idea`, `spec` and `board-status` skills), with
`--plugin-dir`, and her prompt file, `kirakit-analyst.md` (the built `CLAUDE.md` and
`rules/*.md`), with `--append-system-prompt-file`. All three are built from the profile and
installed beside the launchers. The plugin's skills have no `allowed-tools`, so the settings
file is the session's only source of permissions. When the settings file is missing, it starts
no session: it prints one line naming the file on standard error and exits with a non-zero
status. A plain `claude` session,
the assistant's and the lead's background agents (`iris` included) are not restricted this way.

**What the session can do.** Only what the `idea`, `spec` and `board-status` skills run:
those three skills (`Skill(kirakit-analyst:idea)`, `spec` and `board-status`); Claude Code's
bundled skills that would run without a rule (`dataviz`, `simplify`, `code-review`,
`workflow-authoring`, `run` and `plugin-authoring`) are denied by name;
`Read`, `Grep` and `Glob`; `gh issue view`, `list`, `status`, `create`, `edit`, `comment`,
`close` and `reopen`; `gh pr view` and `list`; `gh search`; `gh project list`, `view`,
`field-list`, `item-list`, `item-add` and `item-edit`; `gh label list` and `create`;
`gh repo view`; `gh config get user`; read-only `git log`, `show`, `diff` and `status`; and
`Write` and `Edit` under `~/.cache/kirakit/analyst/`, her temporary directory. With the
analyst's account, each `gh` rule carries the `GH_TOKEN=$(gh auth token --user LOGIN)` prefix,
and `gh auth token --user LOGIN` is allowed on its own. The skills write every body and comment
to a file in that directory and post it with `--body-file`, last on the command line.

**What it cannot do.** Anything else is refused without a prompt: writing, changing or
deleting a file outside her temporary directory, whatever the tool or command (`sed -i`, a
redirection, `git diff --output`, …); `git push`; `gh api`, so no commit or merge through the
API; `gh issue develop`, `delete` or `transfer`; creating, editing or deleting a board.

**Secret files.** The session cannot read `~/.ssh/`, `~/.gnupg/`, `~/.git-credentials`,
`~/.netrc`, `~/.config/gh/hosts.yml`, `~/.claude/.credentials.json` and
`~/.local/share/keyrings/`: `Read` deny rules for each path, and `Bash` deny rules for any
command naming one of them and for `git --no-index`, which close commands that read a file,
such as `gh issue comment --body-file ~/.ssh/id_ed25519`. A glob that hides the name, such as
`--body-file ~/.ss?/id_ed25519`, is refused too: no `?`, `[` or `*` may follow `--body-file` or
`-F`. `gh issue create --recover`, which also reads a file, is refused. `gh auth token` keeps
working: `gh` reads its own configuration itself.

**What `--setting-sources=` drops.** No user, project or local settings merge into the
session, so none of your own rules can widen it. It also drops, in that session only, your own
hooks, model, plugins and the other settings of `settings.json`, and kirakit's permission rules
(see [Permission rules](#permission-rules)). Your `~/.claude/CLAUDE.md`, `rules/`, skills and
output styles do not load either: the session gets kirakit's own from the plugin and the prompt
file, so your own edits to `~/.claude/CLAUDE.md` do not reach it, nor does a project's
`CLAUDE.md` (such as one in a parent directory). Her settings file turns automatic memory off
(`"autoMemoryEnabled": false`), so the memory index does not load either. She can still `Read`
them.

**Limits.**

- A command an allowed rule runs may keep files for itself: `git status` refreshes
  `.git/index`, and `gh` writes its own configuration and state under `~/.config/gh/` and
  `~/.local/state/gh/`.
- The analyst's token is the account's own: used outside the session, it can do whatever the
  account's role allows. A role that GitHub enforces needs a repository in an organization
  (see [Repositories in an organization](#repositories-in-an-organization-optional)).
- Arguments given to `analyst` are passed to Claude Code as they are: an option that widens
  permissions, such as `--dangerously-skip-permissions` or `--allowedTools`, widens the
  session.

**Unattended sessions.** A session that runs on its own, such as the lead's with its watch,
cannot wait on permission prompts: it needs the rules of [Permission rules](#permission-rules)
for each member's account. The analyst's session does not use them: its settings file holds
its own.

## Skills

`claude/skills/` holds Claude Code skills, one directory per skill with its `SKILL.md`:
`assistant-commit`, `board-status`, `commit`, `diffv`, `idea`, `next-task`, `pull`,
`pull-request`, `push`, `review-pr` (with a coder), `review-spec` (with
`--start-verified-specs`), `spec`, `test` and `watch` (with the assistant's GitHub account).
They answer in the profile's language; `commit` and `assistant-commit` follow the git rules in
`claude/rules/git.md` (see [Who commits](#who-commits)). Other skills already in
`$CLAUDE_CONFIG_DIR/skills/` are left untouched. Agents in `claude/agents/` are installed the
same way.

### Models

Each agent and skill declares the model it runs on, so that routine work costs less while
specifications and development keep the strongest model. A forked skill (`context: fork`)
runs in a sub-agent on its own model, sees only its arguments and the repository, and hands
its result back to the caller, who resumes on its own model. An inline skill runs in the
caller's conversation: its model applies when you type it as a slash command (`/commit`);
when a member invokes it herself, it runs on her model.

| Agent or skill | What it is for | Model | Runs |
| --- | --- | --- | --- |
| `iris` (agent) | Clarifies ideas, writes specifications and their tasks (Opus when the lead starts her for specification work) | sonnet | agent |
| `cleo` (agent) | Implements tasks and opens pull requests | sonnet | agent |
| `kira` (agent) | Reviews a pull request of the coder for the lead, in the background, and verifies a specification with `--start-verified-specs` | opus | agent |
| `next-task` | Finds the next workable task on the board | sonnet | forked |
| `board-status` | Moves a task, a specification or a pull request on its boards | haiku | forked |
| `test` | Runs the unit tests and shows a results table | haiku | forked |
| `pull` | Pulls the current branch | haiku | forked |
| `push` | Pushes the current branch | haiku | forked |
| `diffv` | Analyzes the changes against a branch | sonnet | forked |
| `commit` | Commits the user's changes | haiku | inline |
| `assistant-commit` | Commits the coder's or the assistant's own work | haiku | inline |
| `idea` | Captures an idea as an issue | sonnet | inline |
| `spec` | Turns an idea into a specification and its tasks | opus | inline |
| `pull-request` | Writes and opens the pull request of a task | sonnet | inline |
| `watch` | Starts the lead's background checks of GitHub and dispatches what they report (with the assistant's GitHub account) | haiku | inline |
| `review-pr` | Reviews a pull request of the coder and returns a verdict | opus | forked |
| `review-spec` | Verifies a specification of the analyst and returns a verdict (with `--start-verified-specs`) | opus | forked |
| `iris` (skill) | Lets you talk to Iris directly (`/iris`) | sonnet | forked |
| `cleo` (skill) | Lets you talk to Cleo directly (`/cleo`) | sonnet | forked |

The lead's and the analyst's own sessions (`assistant`, `analyst`) run on your model, from
your Claude Code settings: kirakit does not pin it. `board-status` takes the account that
writes as an argument (`--as LOGIN`), since a forked skill cannot tell who called it. The lead
gives its background agents a model suited to the step (`haiku` to read CI logs, run the
tests or search across many files), `opus` when it starts `iris` for specification work (an
idea to specify, a change to a specification) or its takeover agent, and none otherwise, so
that the agent's own model applies: Opus for `kira`, Sonnet for `cleo` and for `iris` on
routine work. A `cleo` agent never runs on Opus.

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
3. **Tasks** (`type:task`): each task is a sub-issue of the specification, created with
   `gh` (a version whose `gh issue create` has `--parent`), assigned to the assistant's
   account when there is one, and left in Backlog. The specification is published without
   confirmation and moved to Specified on its board, with a summary comment listing the
   tasks, the decisions made alone and the development order; with no questions for the
   user, it asks nothing. The user reverses a decision by replying on the issue, and starts
   the work by moving the specification to Ready; with `--start-verified-specs`, Kira moves
   it there once she has verified it (see [Verified specifications](#verified-specifications)).
   A specification has 1 to 3 tasks by
   default, each able to land on its own, with its tests and documentation; more are split
   off only for review size or a stage to try out, with the reason under Decisions.

The formats are defined in `claude/skills/idea/SKILL.md` and `claude/skills/spec/SKILL.md`;
`claude/CLAUDE.md` holds the rules for working from a specification.

### Assignees

Each issue and pull request shows its owner as its assignee, on GitHub and on the board:

- **Idea**: assigned to the analyst's account, or to the assistant's account when there is
  no analyst account, and to nobody without either. An idea written from the issue form is
  assigned when the `spec` skill starts from it.
- **Specification**: assigned to the assistant's account, the lead, from its publication
  on; the analyst's account is removed from it. Without an assistant account, it keeps the
  idea's assignees. Its assignees are not changed afterwards, whatever its status on the
  board, and other assignees (such as you, if you assign yourself) are kept.
- **Task**: assigned to the assistant's account when it is created, then to the member who
  works on it (the coder's account when she implements it).
- **Pull request**: assigned to the member who opens it, with the assistant's account as
  reviewer for the coder's pull requests, and yours for the others and after the
  assistant's approval.

The rules are in `claude/rules/git.md`; existing ideas and specifications are not assigned
after the fact.

### Project board

The workflow uses a board with these `Status` options, in this order:

| Status | What it holds |
| --- | --- |
| Backlog | Ideas, and the tasks of every specification |
| Specified | Specifications that are complete and wait for you, or, with `--start-verified-specs`, for Kira's verification |
| Ready | Specifications you want the team to work on |
| In progress | Specifications and tasks being worked on |
| In review | Tasks and pull requests waiting for your review |
| Done | Closed issues and merged pull requests |

GitHub's default board has no Specified option. Add it in the board's settings (⋯ →
Settings → Status → Add option), and drag it between Backlog and Ready. `gh` cannot add an
option, and replacing the option list through the API can clear existing statuses. Without
a Specified option, the analyst leaves the specification where it is and says so.

The developer moves her tasks, their specification and her pull requests with the
`board-status` skill. Done is left to the board's built-in workflows (item closed, pull
request merged).

### Development from a Ready specification

Moving a specification to Ready makes all its tasks workable. The developer runs
`next-task` when she starts working and after each pull request she opens: it finds the
task (specifications in board order, their tasks in sub-issue order, skipping a task that is
taken, blocked by an open issue, waiting for an answer, or touching the same files as a pull
request in review; a shared test file such as `scripts/test.sh` does not count). She then
states the work plan (the task, its specification, the tasks that follow it; in an automated
turn, one line with the task's URL and the go asked) and starts nothing until you answer. Your answer, or a plan you give yourself, is the go for what it
names: one task, the tasks of the day ("today X, Y and Z"), or "work the Ready ones". Within
that scope she goes on from task to task without asking, for the rest of the session or
until you change the plan; a task outside it waits for a new plan.

She stops for you only when:

- no work plan of yours covers the next task;
- she has a question, or solutions for you to choose from;
- a pull request waits for your review;
- she needs more information, asked on the issue;
- a safety stop applies: no stacked pull requests, tags and releases only on request, merge
  only after approval, asking before creating, editing or closing an issue;
- nothing is workable.

Moving a specification out of Ready and In progress stops it: no new task of it starts, and
a task already started goes on to its pull request. On a repository with no board, the
`status:ready` label on the specification takes the place of Ready.

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
| `{{analyst}}`, `{{analyst_github}}` | "yes" when the team has an analyst, and her GitHub login, or nothing |
| `{{coder}}` | The coder's git identity, "NAME <EMAIL>", or nothing |
| `{{coder_name}}`, `{{coder_email}}` | The coder's name and email, or nothing |
| `{{coder_signing_key}}`, `{{coder_github}}` | The coder's public SSH signing key and GitHub login, or nothing |
| `{{committer}}` | Who commits with `assistant-commit`: "the coder" with a coder, "the assistant" otherwise |
| `{{committer_name}}`, `{{committer_email}}`, `{{committer_signing_key}}` | That member's git identity and signing key: the coder's with a coder, the assistant's otherwise |
| `{{team_github}}` | "yes" when the assistant, the analyst or the coder has a GitHub account, or nothing |
| `{{team_rules}}` | "yes" when the lead's `rules/team.md` is installed (an analyst, a coder, the assistant's GitHub account or the soft rules), or nothing |
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
