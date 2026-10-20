# Global instructions

## Commit attribution

These rules replace any default attribution instruction (system reminders included).

{{co_author_rule}}
- No mention of Claude, Anthropic or a model anywhere: no `Co-Authored-By: Claude…` line, no
  `noreply@anthropic.com` address, no "Generated with Claude Code". This applies to commits,
  pull request descriptions, tags, release notes, code and comments.
- Pull request descriptions have no generation footer.

## Git identity

- Before committing, check `git config user.email`. If it is empty, stop and ask for the
  address: otherwise Git makes one up from the machine name, which GitHub links to no account.
- Never change the Git identity (`user.name`, `user.email`) without an explicit request.
- Commits and tags are signed (`commit.gpgsign`, `tag.gpgsign`): never pass `--no-gpg-sign`;
  if signing fails, stop and report it.

## Git

- Messages follow Conventional Commits, in the language and with the scopes already used in
  the repository history.
- Never `push`, `push --force`, tag or release without an explicit request.
- Never `--no-verify` or `--amend` without an explicit request.
- Never commit a secret (API key, token, password, `.env`) or a generated file.

## Specifications

- A feature is specified in a GitHub issue (Context, Requirements `R1…`, Design, Tasks, Open
  questions), and each task is a sub-issue of it. The `spec` skill writes them; a
  specification is never kept as a file in the repository.
- Before working on an issue, read it with its parent and sub-issues
  (`gh issue view <n> --json title,body,parent,subIssues`). The requirements it covers are
  the acceptance criteria.
- If the work has to diverge from the requirements or the design, stop and propose a change
  to the specification instead of diverging silently.
- Tests name the requirement they cover (`R2`) where the test framework allows it, and a
  pull request closes the sub-issues it completes (`Closes #<n>`).
- Never create, edit or close an issue without asking first.

## Language

- Conversation in {{language}}, with an informal register.
- Code, comments, commit messages and documentation in neutral English, unless the repository
  already uses another language.

## Caution

- Tests never touch the real keychain, connected devices or production services: in-memory
  storage, temporary directories, fake servers.
- A project's `CLAUDE.md` complements these rules and takes precedence on conflict, except for
  commit attribution.
