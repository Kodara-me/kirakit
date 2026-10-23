---
name: assistant-commit
{{^coder}}
description: Commits the code {{committer}} wrote, under {{committer}}'s own identity and signing key, with the user as co-author, in Conventional Commits format after checks (tests, build, lint, sensitive files). Use when {{committer}} commits its own work; the commit skill is for the user's commits.
{{/coder}}
{{#coder}}
description: Commits the code the coder or the assistant wrote, under the identity and signing key of the member who runs it, with the writer as author and the user as co-author, in Conventional Commits format after checks (tests, build, lint, sensitive files). Use when the coder or the assistant commits her own work, or the other member's work when its writer has no signing key; the commit skill is for the user's commits.
{{/coder}}
model: haiku
---

{{^coder}}
# Commit as {{committer}}
{{/coder}}
{{#coder}}
# Commit as the coder or the assistant
{{/coder}}

Answer in {{language}}.

{{^any_committer_key}}
{{^coder}}
No signing key is configured for {{committer}}, so it never commits as itself. Do not commit:
say so, and suggest the `commit` skill, or setting a key with the installer
(`--assistant-signing-key`).
{{/coder}}
{{#coder}}
No signing key is configured for the coder nor for the assistant, so neither commits through
this skill. Do not commit: leave the changes uncommitted, say so, and suggest the `commit`
skill under the user's identity, or setting a key with the installer (`--coder-signing-key`,
`--assistant-signing-key`).
{{/coder}}
{{/any_committer_key}}
{{#any_committer_key}}
{{^coder}}
This skill commits as {{committer_name}} <{{committer_email}}>, signed with
`{{committer_signing_key}}`. The repository and global git configuration stay the user's: the
identity and key are passed on the command line only.
{{/coder}}
{{#coder}}
## Who commits

This skill commits as the member who runs it, the coder or the assistant, and only when that
member has a signing key. The repository and global git configuration stay the user's: the
identity and key are passed on the command line only.

{{#committer_signing_key}}
- The coder commits as {{committer_name}} <{{committer_email}}>, signed with
  `{{committer_signing_key}}`.
{{/committer_signing_key}}
{{^committer_signing_key}}
- No signing key is configured for the coder, so the coder never commits. She leaves her
  changes uncommitted on the branch and hands the commit to the assistant, then pushes the
  branch and opens its pull request as usual.
{{/committer_signing_key}}
{{#assistant_signing_key}}
- The assistant commits as {{assistant_name}} <{{assistant_email}}>, signed with
  `{{assistant_signing_key}}`.
{{/assistant_signing_key}}
{{^assistant_signing_key}}
- No signing key is configured for the assistant, so the assistant never commits. It leaves
  its changes uncommitted on the branch and hands the commit to the coder, then pushes the
  branch and opens its pull request as usual.
{{/assistant_signing_key}}

What the member who runs it may commit:

- Her own work: the coder, the code she wrote for her task; the assistant, the code it wrote
  itself because the user explicitly asked it to (`rules/team.md`).
- The other member's work only when its writer has no signing key, for a task or a change of
  the team, on that work's branch, with the writer as the commit's author (step 6). The
  commit does not make the work hers: the writer still pushes the branch and opens its pull
  request.
- Never the user's own changes (they go through the `commit` skill), and never the other
  member's work when its writer has a key.
{{/coder}}

## 1. Check the key

{{^coder}}
- `{{committer_signing_key}}` and the private key next to it (the same path without `.pub`)
  must exist. If one is missing, do not commit: report it.
{{/coder}}
{{#coder}}
- The public key of the member who commits and the private key next to it (the same path
  without `.pub`) must exist:
{{#committer_signing_key}}
  - the coder: `{{committer_signing_key}}`;
{{/committer_signing_key}}
{{#assistant_signing_key}}
  - the assistant: `{{assistant_signing_key}}`.
{{/assistant_signing_key}}
- If one is missing, do not commit: report it. Never use the other member's key instead.
{{/coder}}

## 2. Review the changes

- `git status` and `git diff` (plus `git diff --staged` if files are already staged).
- `git log --oneline -10` to follow the repository's message style (language, scopes in use).
{{^coder}}
- Commit only changes {{committer}} wrote in this session. If other changes are mixed in,
  stage only {{committer}}'s, or ask the user.
{{/coder}}
{{#coder}}
- Commit only the changes this member may commit (see "Who commits"): her own, or the other
  member's when its writer has no key. Never the user's own changes. If other changes are
  mixed in, stage only those, or ask the user.
{{/coder}}
- If there is nothing to commit, say so and stop.

## 3. Pre-commit checks

Read the project's `CLAUDE.md` first: its rules take precedence (for example commands that are
forbidden or need approval before running). Run only quick checks.

- **Tests**: run the project's fast suite (for example `ctest`, `npm test`, `pytest -q`,
  `cargo test`, `go test ./...`). If no suite is found, say so.
- **Lint / format**: run the configured linter or formatter, without rewriting files without
  approval.
- **Diff hygiene**: no secrets (API keys, tokens, `.env`, passwords), no large or generated
  files, no leftover debug code or conflict markers; `git diff --check` for trailing
  whitespace.

If a check fails, do not commit anyway: report it.

## 4. Write the message

[Conventional Commits](https://www.conventionalcommits.org) format:

```
<type>(<optional scope>): <imperative description, lowercase, no period, ≤ 72 chars>

<optional body: the why, not the how, lines ≤ 72 chars>

<optional footer: BREAKING CHANGE: ..., Refs: #123>
{{#co_author}}

Co-Authored-By: <user name> <<user email>>
{{/co_author}}
```

{{#co_author}}
The last line credits the user: `Co-Authored-By:` followed by `git config user.name` and
`<git config user.email>`. If either is empty, ask the user for it.
{{/co_author}}
{{^co_author}}
No `Co-Authored-By` line.
{{/co_author}}
Follow the git rules (`rules/git.md`): no mention of Claude, Anthropic or a model.

## 5. Confirm with the user

Skip this step when the user already approved committing this work in the conversation (for
example by approving the task or a plan that includes it). Otherwise, use the
**AskUserQuestion** tool with a single question showing the result of the checks, the files
that will be committed and the full message, with the options "Commit" (recommended if
everything passes), "Edit the message" and "Cancel".

## 6. Commit

- Stage the relevant files explicitly (`git add <files>`); avoid a blind `git add -A`.
{{^coder}}
- Commit with exactly this command, the message passed through a heredoc:

  ```sh
  git -c user.name="{{committer_name}}" -c user.email="{{committer_email}}" -c user.signingkey="{{committer_signing_key}}" -c gpg.format=ssh -c commit.gpgsign=true commit -F - <<'MESSAGE'
  <message>
  MESSAGE
  ```

{{/coder}}
{{#coder}}
- Commit with exactly the command below for the member who commits and the work's writer,
  the message passed through a heredoc.
{{#committer_signing_key}}
- The coder, for her own work:

  ```sh
  git -c user.name="{{committer_name}}" -c user.email="{{committer_email}}" -c user.signingkey="{{committer_signing_key}}" -c gpg.format=ssh -c commit.gpgsign=true commit -F - <<'MESSAGE'
  <message>
  MESSAGE
  ```

{{^assistant_signing_key}}
{{#assistant_name}}
- The coder, for the assistant's work (the assistant has no key), with the assistant as
  author:

  ```sh
  git -c user.name="{{committer_name}}" -c user.email="{{committer_email}}" -c user.signingkey="{{committer_signing_key}}" -c gpg.format=ssh -c commit.gpgsign=true commit --author="{{assistant_name}} <{{assistant_email}}>" -F - <<'MESSAGE'
  <message>
  MESSAGE
  ```

{{/assistant_name}}
{{/assistant_signing_key}}
{{/committer_signing_key}}
{{#assistant_signing_key}}
- The assistant, for its own work:

  ```sh
  git -c user.name="{{assistant_name}}" -c user.email="{{assistant_email}}" -c user.signingkey="{{assistant_signing_key}}" -c gpg.format=ssh -c commit.gpgsign=true commit -F - <<'MESSAGE'
  <message>
  MESSAGE
  ```

{{^committer_signing_key}}
- The assistant, for the coder's work (the coder has no key), with the coder as author:

  ```sh
  git -c user.name="{{assistant_name}}" -c user.email="{{assistant_email}}" -c user.signingkey="{{assistant_signing_key}}" -c gpg.format=ssh -c commit.gpgsign=true commit --author="{{committer_name}} <{{committer_email}}>" -F - <<'MESSAGE'
  <message>
  MESSAGE
  ```

{{/committer_signing_key}}
{{/assistant_signing_key}}
- Commit only when the permission system allows it. If the commit is refused or signing
  fails, stop and report it: never fall back to another identity, an unsigned commit or the
  other member's key.
{{/coder}}
- Never use `--no-verify`, `--amend` or `--no-gpg-sign` without an explicit request. If a
  pre-commit hook fails, fix the issue and create a new commit.
{{^coder}}
- Check the result: `git log -1 --format='%an <%ae>'` must show
  {{committer_name}} <{{committer_email}}>, and `git cat-file commit HEAD` must hold a
  `gpgsig` header (`%G?` is not enough: it shows `N` for an SSH signature when no
  `gpg.ssh.allowedSignersFile` is configured). If the commit is not signed, stop and report
  it.
{{/coder}}
{{#coder}}
- Check the result: `git log -1 --format='%an <%ae> | %cn <%ce>'` must show the writer as
  author and the member who commits as committer, and `git cat-file commit HEAD` must hold a
  `gpgsig` header (`%G?` is not enough: it shows `N` for an SSH signature when no
  `gpg.ssh.allowedSignersFile` is configured). If the commit is not signed, stop and report
  it.
{{/coder}}
- Show `git log --oneline -1` and the final `git status`. Do not push.
{{/any_committer_key}}
