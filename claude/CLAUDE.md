# Global instructions

## Git

Commits, attribution, identity and signing follow the git rules in `rules/git.md`, which
Claude Code loads on its own from the rules folder.

## Specifications

- A feature starts as an idea issue (`type:idea`, written by the `idea` skill), and becomes
  a specification in the same issue (Context, Requirements `R1…`, Design, Tasks, Open
  questions), with each task as a sub-issue. The `spec` skill writes it; a specification is
  never kept as a file in the repository.
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
  the attribution rules of `rules/git.md`.
