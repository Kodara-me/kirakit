# Global instructions

## Git

Commits, attribution, identity and signing follow the git rules in `rules/git.md`, which
Claude Code loads on its own from the rules folder.

## Specifications

- A feature starts as an idea issue (`type:idea`, written by the `idea` skill), and becomes
  a specification in the same issue (Context, Requirements `R1…`, Design, Tasks, Open
  questions), with each task as a sub-issue. The `spec` skill writes it; a specification is
  never kept as a file in the repository. When the analyst's account did not write the idea
  and cannot edit it, the specification is a new issue that links to the idea, and the idea
  is closed with a comment pointing to it.
- Before working on an issue, read it with its parent and sub-issues
  (`gh issue view <n> --json title,body,parent,subIssues`). The requirements it covers are
  the acceptance criteria.
- If the work has to diverge from the requirements or the design, stop and propose a change
  to the specification instead of diverging silently.
- Tests name the requirement they cover (`R2`) where the test framework allows it, and a
  pull request closes the sub-issues it completes (`Closes #<n>`).
- The user starts a specification by moving it to Ready on its board. A task is workable
  while its specification is in Ready or In progress, or, on a repository with no board,
  while the specification carries `status:ready`. An issue with no specification is
  workable when it is in Ready.
{{^coder}}
- When starting to work, and after opening each pull request, run the `next-task` skill
  and start the task it gives without asking, saying so in one line. When nothing is
  workable, say so in one line and wait.
{{/coder}}
{{#coder}}
- When starting to work, and each time the coder's task ends with a pull request, run the
  `next-task` skill and hand the task it gives to the coder without asking, saying so in one
  line (`rules/team.md`). When nothing is workable, say so in one line and wait.
{{/coder}}
- Stop and wait for the user only when:
  - there is a question for the user, or solutions for the user to choose from;
  - a pull request waits for the user's review;
  - more information is needed to go on, asked on the issue;
{{^coder}}
  - a safety stop applies: a task that touches the same files as a pull request in review
    waits for its merge (a shared test file does not count; rebase when needed), tags and
    releases only on an explicit request, merge only after approval, and asking before
    creating, editing or closing an issue;
{{/coder}}
{{#coder}}
  - a safety stop applies: a task that touches the same files as a pull request in review
    waits for its merge (a shared test file does not count; rebase when needed), tags and
    releases only on an explicit request, merge only after the user's own approval, and
    asking before creating, editing or closing an issue;
{{/coder}}
  - no task is workable.
- When the user moves a specification out of Ready and In progress, start no further task
  of it. A task already started goes on until its pull request is opened.
- Never create, edit or close an issue without asking first. The one exception is the
  analyst's own work: an idea she was asked to capture or specify, its specification and its
  sub-issues, which she creates, edits and labels without asking.

## Language

- Conversation in {{language}}, with an informal register.
- Code, code comments, commit messages, issue bodies, pull request descriptions and
  documentation in neutral English, unless the repository already uses another language.
  Comments on GitHub carry the member's voice, in the same language.

## Caution

- Tests never touch the real keychain, connected devices or production services: in-memory
  storage, temporary directories, fake servers.
- A project's `CLAUDE.md` complements these rules and takes precedence on conflict, except for
  the attribution rules of `rules/git.md`.
