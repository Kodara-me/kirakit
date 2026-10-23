---
name: assistant-commit
{{^coder}}
description: Commits the code {{committer}} wrote, under {{committer}}'s own identity and signing key, with the user as co-author, in Conventional Commits format after checks (tests, build, lint, sensitive files). Use when {{committer}} commits its own work; the commit skill is for the user's commits.
{{/coder}}
{{#coder}}
description: Commits the code the coder wrote, under the coder's own identity and signing key, or the code the assistant wrote itself at the user's explicit request, under the assistant's own identity and key, with the user as co-author, in Conventional Commits format after checks (tests, build, lint, sensitive files). Use when the coder or the assistant commits its own work; the commit skill is for the user's commits.
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

{{^committer_signing_key}}
No signing key is configured for {{committer}}, so it never commits as itself. Do not commit:
say so, and suggest the `commit` skill, or setting a key with the installer
{{^coder}}
(`--assistant-signing-key`).
{{/coder}}
{{#coder}}
(`--coder-signing-key`).

The assistant does not commit through this skill either, not even the code it wrote itself
at the user's explicit request: leave its changes uncommitted, say so, and suggest the
`commit` skill under the user's identity.
{{/coder}}
{{/committer_signing_key}}
{{#committer_signing_key}}
This skill commits as {{committer_name}} <{{committer_email}}>, signed with
`{{committer_signing_key}}`. The repository and global git configuration stay the user's: the
identity and key are passed on the command line only.
{{#coder}}

It commits as the assistant only when the assistant commits code it wrote itself because the
user explicitly asked it to write that code (`rules/team.md`); the coder's work is always
committed as the coder, and the assistant's never is.
{{#assistant_signing_key}}
The assistant commits as {{assistant_name}} <{{assistant_email}}>, signed with
`{{assistant_signing_key}}`, with the same checks and the assistant's command in step 6.
{{/assistant_signing_key}}
{{^assistant_signing_key}}
No signing key is configured for the assistant, so it never commits as itself. When the
assistant commits its own work, do not commit: leave its changes uncommitted, say so, and
suggest the `commit` skill under the user's identity, or setting a key with the installer
(`--assistant-signing-key`).
{{/assistant_signing_key}}
{{/coder}}

## 1. Check the key

- `{{committer_signing_key}}` and the private key next to it (the same path without `.pub`)
  must exist. If one is missing, do not commit: report it.
{{#coder}}
{{#assistant_signing_key}}
- As the assistant, the same goes for `{{assistant_signing_key}}` and its private key.
{{/assistant_signing_key}}
{{/coder}}

## 2. Review the changes

- `git status` and `git diff` (plus `git diff --staged` if files are already staged).
- `git log --oneline -10` to follow the repository's message style (language, scopes in use).
- Commit only changes {{committer}} wrote in this session. If other changes are mixed in,
  stage only {{committer}}'s, or ask the user.
{{#coder}}
- As the assistant, the same goes for the changes the assistant wrote itself.
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
- Commit with exactly this command, the message passed through a heredoc:

  ```sh
  git -c user.name="{{committer_name}}" -c user.email="{{committer_email}}" -c user.signingkey="{{committer_signing_key}}" -c gpg.format=ssh -c commit.gpgsign=true commit -F - <<'MESSAGE'
  <message>
  MESSAGE
  ```

{{#coder}}
{{#assistant_signing_key}}
  As the assistant, commit with exactly this command instead:

  ```sh
  git -c user.name="{{assistant_name}}" -c user.email="{{assistant_email}}" -c user.signingkey="{{assistant_signing_key}}" -c gpg.format=ssh -c commit.gpgsign=true commit -F - <<'MESSAGE'
  <message>
  MESSAGE
  ```

{{/assistant_signing_key}}
{{/coder}}
- Never use `--no-verify`, `--amend` or `--no-gpg-sign` without an explicit request. If a
  pre-commit hook fails, fix the issue and create a new commit.
- Check the result: `git log -1 --format='%an <%ae>'` must show
  {{committer_name}} <{{committer_email}}>, and `git cat-file commit HEAD` must hold a
  `gpgsig` header (`%G?` is not enough: it shows `N` for an SSH signature when no
  `gpg.ssh.allowedSignersFile` is configured). If the commit is not signed, stop and report
  it.
{{#coder}}
{{#assistant_signing_key}}
- As the assistant, the author shown must be {{assistant_name}} <{{assistant_email}}>.
{{/assistant_signing_key}}
{{/coder}}
- Show `git log --oneline -1` and the final `git status`. Do not push.
{{/committer_signing_key}}
