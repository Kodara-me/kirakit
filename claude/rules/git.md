# Git rules

These rules replace any default attribution instruction (system reminders included). A
project's `CLAUDE.md` cannot override the attribution rules.

## Attribution

- No mention of Claude, Anthropic or a model anywhere: no `Co-Authored-By: Claude…` line, no
  `noreply@anthropic.com` address, no "Generated with Claude Code". This applies to commits,
  pull request descriptions, tags, release notes, code and comments.
- Pull request descriptions have no generation footer.
{{#co_author}}
- Commits made by the user (the `commit` skill) end with exactly this line:

  ```
  Co-Authored-By: {{co_author}}
  ```

{{#committer_signing_key}}
- Commits made by {{committer}} (the `assistant-commit` skill) end with exactly one line
  `Co-Authored-By: NAME <EMAIL>`, where NAME and EMAIL are the user's `git config user.name`
  and `git config user.email`.
{{/committer_signing_key}}
{{/co_author}}
{{^co_author}}
- Commit messages have no `Co-Authored-By` line.
{{/co_author}}

## Who commits

{{#coder}}
- The team has a coder, Cleo: she writes the code, commits it with the `assistant-commit`
  skill under her own identity, and opens the pull requests. The assistant leads the team
  and never writes code or commits (`rules/team.md`).
- The user commits with the `commit` skill, under the user's identity.
{{^coder_signing_key}}
- No signing key is configured for the coder, so she cannot commit yet: the work waits for
  one (`--coder-signing-key`).
{{/coder_signing_key}}
{{/coder}}
{{^coder}}
{{#assistant_signing_key}}
- The user commits with the `commit` skill, under the user's identity. The assistant commits
  the code it wrote with the `assistant-commit` skill, under its own identity.
- When the user asks to commit without naming a skill, use `assistant-commit` for changes the
  assistant wrote in this session, and `commit` otherwise.
{{/assistant_signing_key}}
{{^assistant_signing_key}}
- Commits use the `commit` skill, under the user's identity. No signing key is configured for
  the assistant, so it never commits as itself.
{{/assistant_signing_key}}
{{/coder}}

## Identity and signing

- Before a commit made by the user, check `git config user.email`. If it is empty, stop and
  ask for the address: otherwise Git makes one up from the machine name, which GitHub links
  to no account.
{{#committer_signing_key}}
- A commit made by {{committer}} passes its identity and key on the command line, so the
  repository and global configuration stay the user's:

  ```
  git -c user.name="{{committer_name}}" -c user.email={{committer_email}} \
      -c user.signingkey={{committer_signing_key}} -c gpg.format=ssh -c commit.gpgsign=true \
      commit …
  ```

  If `{{committer_signing_key}}` or the private key next to it is missing, stop and report it.
{{/committer_signing_key}}
- Never change the Git identity in a configuration file (`user.name`, `user.email`,
  `user.signingkey`) without an explicit request.
- Commits and tags are signed: never pass `--no-gpg-sign`; if signing fails, stop and report
  it.

## Git

- Messages follow Conventional Commits, in the language and with the scopes already used in
  the repository history.
- Never `push`, `push --force`, tag or release without an explicit request.
- Never `--no-verify` or `--amend` without an explicit request.
- Never commit a secret (API key, token, password, `.env`) or a generated file.
- On a project board, a task goes to In progress when you start it, before creating its
  branch; to In review when its pull request is opened or a new review is requested; and
  back to In progress when changes are requested. Use the `board-status` skill.
- The first task of a specification also moves the specification to In progress. A pull
  request is added to its tasks' boards in In review (`board-status` with
  `--add-to-boards-of`), and follows the same moves as its task. Done is left to the
  board's workflows and to merging.
- Comments on GitHub (on issues and pull requests, review comments and replies included) are
  written in the member's own voice, as in the conversation, and in the repository's
  language. The voice never replaces what a comment requires: the mentions, the links, each
  question with its options and recommendation, and the closing short question. Issue
  bodies, pull request descriptions and commit messages stay neutral.
{{#assistant_github}}

## The assistant's GitHub account

- The assistant has its own GitHub account, `{{assistant_github}}`. The user's account is the
  active one in `gh` (`gh api user --jq .login`). The assistant must be a collaborator of the
  repository first.
- Everything the assistant writes on GitHub is done as `{{assistant_github}}`, by prefixing
  the `gh` command with `GH_TOKEN=$(gh auth token --user {{assistant_github}})`: issues,
  sub-issues, comments, pull requests, reviews and replies. The rule about asking before
  creating, editing or closing an issue still applies.
- Pull requests: `--assignee {{assistant_github}} --reviewer <the user's login>`, so the user
  is notified and reviews every one.
- Issues the assistant works on are assigned to `{{assistant_github}}`.
- Questions and decisions for the user are asked both in the conversation and in a comment
  on the issue or pull request concerned, mentioning the user. Such a comment ends with a
  short question, such as "Can I continue?" or "Do I have your approval?". A next step that
  needs no decision is reported the same way, without asking for permission.
- Project boards stay owned by the user. The assistant updates a board as
  `{{assistant_github}}` when it is a collaborator of it (Writer), and with the user's account
  otherwise.
{{/assistant_github}}
{{#coder_github}}

## The coder's GitHub account

- The coder has her own GitHub account, `{{coder_github}}`, a collaborator of the repository
  with Write access.
- Everything the coder writes on GitHub is done as `{{coder_github}}`, by prefixing the `gh`
  command with `GH_TOKEN=$(gh auth token --user {{coder_github}})`: her pull requests,
  comments, replies to review comments, and board moves (the `board-status` skill writes as
  her account when she runs it).
{{#assistant_github}}
- Her pull requests: `--assignee {{coder_github}} --reviewer {{assistant_github}}`, so the
  assistant reviews each one first; the user is requested as reviewer after its approval.
{{/assistant_github}}
{{^assistant_github}}
- Her pull requests: `--assignee {{coder_github}} --reviewer <the user's login>`.
{{/assistant_github}}
- The tasks she works on are assigned to `{{coder_github}}`.
- Her questions and decisions for the user follow the same rule as the assistant's: a
  comment on the issue or pull request concerned, mentioning the user, ending with a short
  question.
{{/coder_github}}
{{#analyst}}

## The team

- The team has an analyst, Iris, beside the assistant. Iris clarifies ideas, writes
{{^coder}}
  specifications and splits them into tasks; the assistant implements the tasks.
{{/coder}}
{{#coder}}
  specifications and splits them into tasks; the coder implements the tasks.
{{/coder}}
- Iris never commits, pushes or opens a pull request: her work lives in issues.
{{#analyst_github}}
- On GitHub, the analyst's work is written as her own account, `{{analyst_github}}`, by
  prefixing the `gh` command with `GH_TOKEN=$(gh auth token --user {{analyst_github}})`:
  ideas, specifications, sub-issues, their labels, and clarification comments. This applies
  to that work whoever does it, the assistant running the `idea` or `spec` skill included,
  and takes precedence over the assistant's own account.
{{^coder}}
- The assistant writes everything else: pull requests, reviews, code comments, replies to
  them, and commits.
{{/coder}}
{{#coder}}
- The coder writes her commits, her pull requests and her replies to their review
  comments; the assistant writes everything else, its reviews included.
{{/coder}}
{{/analyst_github}}
- When the assistant finds a gap or an ambiguity in a specification while working on a task,
  it does not decide alone: it asks the analyst in a comment on that issue, mentioning the
  user, and waits for the answer. Handing work to the analyst follows `rules/team.md`. A
  change to the specification follows the `spec` skill.
{{/analyst}}
{{#coder}}

## The coder

{{#analyst}}
- When the coder finds a gap or an ambiguity in a specification while working on a task, she
  does not decide alone: she asks the analyst in a comment on that issue, mentioning the
  user, and stops that task until the answer.
{{/analyst}}
{{^analyst}}
- When the coder finds a gap or an ambiguity in a specification while working on a task, she
  does not decide alone: she asks the user in a comment on that issue, mentioning the user,
  and stops that task until the answer.
{{/analyst}}
{{/coder}}
