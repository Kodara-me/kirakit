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

{{^coder}}
{{#committer_signing_key}}
- Commits made by {{committer}} (the `assistant-commit` skill) end with exactly one line
  `Co-Authored-By: NAME <EMAIL>`, where NAME and EMAIL are the user's `git config user.name`
  and `git config user.email`.
{{/committer_signing_key}}
{{/coder}}
{{#coder}}
{{#any_committer_key}}
- Commits made by the coder or the assistant (the `assistant-commit` skill) end with exactly
  one line `Co-Authored-By: NAME <EMAIL>`, where NAME and EMAIL are the user's
  `git config user.name` and `git config user.email`.
{{/any_committer_key}}
{{/coder}}
{{/co_author}}
{{^co_author}}
- Commit messages have no `Co-Authored-By` line.
{{/co_author}}

## Who commits

{{#coder}}
- The team has a coder, Cleo: by default she writes the code, commits it with the
  `assistant-commit` skill under her own identity, and opens the pull requests. The assistant
  leads the team and writes code itself only when the user explicitly asks it to in the
  conversation (`rules/team.md`); that work is committed and its pull request opened under the
  rules below.
- The user commits with the `commit` skill, under the user's identity.
- Each member who has a signing key, the coder or the assistant, commits her own work with
  it. A writer without a key leaves her changes uncommitted on the branch and hands their
  commit to the member who has one, who commits them with `assistant-commit` as the
  committer, with the writer as the author; the writer then pushes the branch and opens its
  pull request, which stays hers. A member commits work she did not write only in that case:
  never the user's own changes, nor the other member's work when its writer has a key.
{{^coder_signing_key}}
{{#assistant_signing_key}}
- No signing key is configured for the coder, so she does not commit: the assistant commits
  her work (`--coder-signing-key`).
{{/assistant_signing_key}}
{{^assistant_signing_key}}
- No signing key is configured for the coder nor for the assistant, so neither commits: the
  member who wrote the code leaves her changes uncommitted, says so, and proposes the
  `commit` skill under the user's identity (`--coder-signing-key`, `--assistant-signing-key`).
{{/assistant_signing_key}}
{{/coder_signing_key}}
{{#coder_signing_key}}
{{^assistant_signing_key}}
- No signing key is configured for the assistant, so it does not commit: the coder commits
  the work it writes at the user's request (`--assistant-signing-key`).
{{/assistant_signing_key}}
{{/coder_signing_key}}
- Code the assistant writes at the user's explicit request follows the flow of a coder's
  task: the task assigned to the assistant and moved on the board by it, its own branch, the
  check against pull requests in review that touch the same files, and a pull request opened
  with the `pull-request` skill that closes the task (`Closes #<n>`), with the user as
  reviewer. The assistant never reviews or approves its own pull request: it is merged only
  when the user's own latest review approves its last commit, even with
  `--complete-approved-prs`. It pushes only to open or update that pull request.
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

{{^coder}}
  If `{{committer_signing_key}}` or the private key next to it is missing, stop and report it.
{{/coder}}
{{#coder}}
{{#assistant_signing_key}}
  If `{{committer_signing_key}}` or the private key next to it is missing, the coder hands the
  commit to the assistant, as a coder without a key does.
{{/assistant_signing_key}}
{{^assistant_signing_key}}
  If `{{committer_signing_key}}` or the private key next to it is missing, stop and report it.
{{/assistant_signing_key}}
{{/coder}}
{{/committer_signing_key}}
{{#coder}}
{{#assistant_signing_key}}
- A commit made by the assistant passes its own identity and key on the command line the
  same way:

  ```
  git -c user.name="{{assistant_name}}" -c user.email={{assistant_email}} \
      -c user.signingkey={{assistant_signing_key}} -c gpg.format=ssh -c commit.gpgsign=true \
      commit …
  ```

{{#committer_signing_key}}
  If `{{assistant_signing_key}}` or the private key next to it is missing, the assistant hands
  the commit to the coder, as an assistant without a key does.
{{/committer_signing_key}}
{{^committer_signing_key}}
  If `{{assistant_signing_key}}` or the private key next to it is missing, stop and report it.
{{/committer_signing_key}}
{{/assistant_signing_key}}
{{#any_committer_key}}
- A commit of the other member's work adds `--author="NAME <EMAIL>"` with the writer's
  identity, so that the writer is its author and the member who commits is its committer and
  signer. A commit refused by the permission system, or whose signing fails, stops there:
  never another identity, an unsigned commit or the other member's key.
{{/any_committer_key}}
{{/coder}}
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
  back to In progress when changes are requested. Use the `board-status` skill, with `--as`
  and the GitHub login of the member who makes the move when that member has one (below);
  without `--as`, it uses the user's account.
- The first task of a specification also moves the specification to In progress. A pull
  request is added to its tasks' boards in In review (`board-status` with
  `--add-to-boards-of`), and follows the same moves as its task. Done is left to the
  board's workflows and to merging.
- Comments on GitHub (on issues and pull requests, review comments and replies included) are
  written in the member's own voice, as in the conversation, and in the repository's
  language. The voice never replaces what a comment requires: the mentions and the closing
  short question when the rules below call for them, the links, and each question with its
  options and recommendation. Issue bodies, pull request descriptions and commit messages
  stay neutral.
- A comment mentions the user (`@<the user's login>`) only when it asks him to answer a
  question, make a decision, choose between options, or take an action that only he can take
  and that nothing else notifies him of, such as reviewing a pull request on which he is not
  requested as reviewer. A comment meant for the user addresses him by that mention, never
  by his name alone: a name without `@` notifies nobody.
- A request for the user's review is his notification: the comment or review posted with it
  does not mention him, unless it also asks him something under the rule above, and that
  question then goes in a comment of its own, as the rule below says.
- Every other comment is still posted, in the member's voice, without mentioning the user:
  progress, hand-offs, merge reports, a next step that needs no decision, an approval with
  nothing for him, a specification ready to start. The only exception is a notification
  that a rule requires by name.
- A comment ends with a short question, such as "Can I continue?" or "Do I have your
  approval?", only when it asks the user for an action under the rule above. Every other
  comment ends without one, a notification that mentions him included.
- What the user must answer, decide, choose or do goes in a comment of its own, short, that
  mentions him and holds only that: each question with its options and the member's
  recommendation, or the action asked, then the closing short question. It holds no status,
  restatement, settled item or exchange with another member. When the need comes with such
  content (a clarification restating the idea, a specification summary, a review, a
  hand-off), the member posts that content first, in a separate comment that does not mention
  him and keeps its usual level of detail, then the comment for the user, so that the comment
  mentioning him is the later of the two.
- When a comment needs another member of the team to act (changes to make to a pull
  request, a gap in a specification to answer, a specification to change), it mentions that
  member's account on GitHub when she has one. Such a mention is a notification only: the
  member's work is still started from the assistant's conversation.
{{#assistant_github}}

## The assistant's GitHub account

- The assistant has its own GitHub account, `{{assistant_github}}`. The user's account is the
  active one in `gh`, and the user's login comes from `gh config get user -h github.com`,
  which calls no API. The assistant must have Write on the repository first, as a
  collaborator or through a team of the user's organization.
- Every `gh` command the assistant runs, reads included (`gh issue view`, `gh pr view`,
  `gh pr checks`, `gh run view`, `gh project`, `gh api`), is prefixed with
  `GH_TOKEN=$(gh auth token --user {{assistant_github}})`, so that it uses its own account and
  quota: what it writes (issues, sub-issues, comments, pull requests, reviews and replies)
  and what it reads. None falls back to the user's account: when a command is refused with
  that token, the assistant reports it instead of running it as the user. The rule about
  asking before creating, editing or closing an issue still applies.
- Pull requests: `--assignee {{assistant_github}} --reviewer <the user's login>`, so the user
  is notified and reviews every one.
- Issues the assistant works on are assigned to `{{assistant_github}}`.
- Specifications are assigned to `{{assistant_github}}`, their owner, from their publication
  on. Their assignees are not changed afterwards: moving a specification on the board,
  changing it with the `spec` skill or closing it leaves them as they are.
{{^analyst_github}}
- Ideas are assigned to `{{assistant_github}}` too, until they become specifications.
{{/analyst_github}}
- Questions and decisions for the user are asked both in the conversation and in a comment
  of its own on the issue or pull request concerned, which mentions the user, holds only
  what he must decide and ends with a short question, as the rules on comments say. A next
  step that needs no decision is reported in a comment too, without mentioning him and
  without asking for permission.
- Project boards stay owned by the user or the user's organization. The assistant updates a
  board as `{{assistant_github}}`, which must be a Writer of it, directly or through a team:
  its board moves pass `--as {{assistant_github}}` to the `board-status` skill, which reads
  and writes the board with that account only and reports a move it refuses.
{{/assistant_github}}
{{#coder_github}}

## The coder's GitHub account

- The coder has her own GitHub account, `{{coder_github}}`, with Write on the repository, as
  a collaborator or through a team of the user's organization.
- Every `gh` command the coder runs, reads included (`gh issue view`, `gh pr view`,
  `gh pr checks`, `gh run view`, `gh project`, `gh api`), is prefixed with
  `GH_TOKEN=$(gh auth token --user {{coder_github}})`, so that it uses her own account and
  quota: her pull requests, comments, replies to review comments, and what she reads. None
  falls back to the user's account: when a command is refused with that token, the coder
  reports it instead of running it as the user. Her board moves pass her account to the
  `board-status` skill (`board-status NUMBER STATUS --as {{coder_github}}`).
{{#assistant_github}}
{{^complete_approved_prs}}
- Her pull requests: `--assignee {{coder_github}} --reviewer {{assistant_github}}`, so the
  assistant reviews each one first; the user is requested as reviewer after its approval.
{{/complete_approved_prs}}
{{#complete_approved_prs}}
- Her pull requests: `--assignee {{coder_github}} --reviewer {{assistant_github}}`, so the
  assistant reviews each one first; after its approval, the user is requested as reviewer
  only when the pull request does not meet the conditions for completing it without him
  (`rules/team.md`).
{{/complete_approved_prs}}
{{/assistant_github}}
{{^assistant_github}}
- Her pull requests: `--assignee {{coder_github}} --reviewer <the user's login>`.
{{/assistant_github}}
- The tasks she works on are assigned to `{{coder_github}}`.
- Her questions and decisions for the user follow the rules on comments: a comment of its
  own on the issue or pull request concerned, which mentions the user, holds only what he
  must decide and ends with a short question. A next step that needs no decision is posted
  without mentioning him.
{{/coder_github}}
{{#team_github}}

## Session marker and the user's replies

The user may answer from a team member's account after switching accounts, often from a
phone. The session marker tells the members' own comments from his.

- Every comment, review and review reply written as a team member's account ends with a
  session marker naming the member's role, alone on its last line, hidden once rendered:
{{#assistant_github}}
  - `<!-- kirakit:assistant -->` for the assistant, as `{{assistant_github}}`
{{/assistant_github}}
{{#analyst_github}}
  - `<!-- kirakit:analyst -->` for the analyst, as `{{analyst_github}}`
{{/analyst_github}}
{{#coder_github}}
  - `<!-- kirakit:coder -->` for the coder, as `{{coder_github}}`
{{/coder_github}}

  Issue and pull request bodies stay unmarked.
- A comment counts as the user's reply when its author is the user's account, or when its
  author is one of the accounts above, it carries no session marker, and it was posted after
  the latest comment carrying a session marker in the same thread. A comment from any other
  account never counts as the user's reply, with or without a marker.
- When a member acts on a reply posted from one of these accounts, the next comment the
  member writes in that thread starts with one line naming its writer and the account,
  without a mention:
  "Reply from <the user's login>, posted from the `<account>` account."
- A pull request review posted from one of these accounts is never the user's approval,
  with or without a marker: nobody merges on it. The member who merges asks the user, in a
  comment mentioning him and ending with a short question, to approve from his own account.
{{/team_github}}
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
- On GitHub, the analyst's work is done as her own account, `{{analyst_github}}`: every `gh`
  command of that work, reads included (`gh issue view`, `gh project`, `gh api`), is prefixed
  with `GH_TOKEN=$(gh auth token --user {{analyst_github}})`, for her ideas, specifications,
  sub-issues, their labels, clarification comments and what she reads. None falls back to
  the user's account: when a command is refused with that token, it is reported instead of
  run as the user. This applies to that work whoever does it, the assistant running the
  `idea` or `spec` skill included, and takes precedence over the assistant's own account.
  Her board moves pass `--as {{analyst_github}}` to the `board-status` skill.
- Her role on the repository is Triage where its owner offers it (an organization, as a
  collaborator or through a team), and Write otherwise (a personal account). With Triage,
  GitHub keeps her from pushing, and she cannot edit the body of an issue she did not write:
  the `spec` skill then opens the specification in a new issue.
{{#assistant_github}}
- Ideas are assigned to her account until they become specifications; a specification is
  then assigned to `{{assistant_github}}` instead.
{{/assistant_github}}
{{^assistant_github}}
- Ideas are assigned to her account, and stay so once they become specifications.
{{/assistant_github}}
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
  it does not decide alone: it asks the analyst in a comment on that issue, and waits for the
  answer.
{{#analyst_github}}
  The comment mentions the analyst's account, `@{{analyst_github}}`, not the user: she asks
  the user herself when the gap is a real trade-off.
{{/analyst_github}}
{{^analyst_github}}
  The comment names the analyst and does not mention the user: she asks the user herself
  when the gap is a real trade-off.
{{/analyst_github}}
  Handing work to the analyst follows `rules/team.md`. A change to the specification follows
  the `spec` skill.
{{#assistant_github}}
- The user's reply on an idea or a specification of the analyst, seen by the lead's watch,
  is handed as given to the `iris` agent, which records it; the analyst's account and
  its mentions are notifications only, and the work is started from the assistant's
  conversation.
{{/assistant_github}}
{{/analyst}}
{{#coder}}

## The coder

{{#analyst}}
- When the coder finds a gap or an ambiguity in a specification while working on a task, she
  does not decide alone: she asks the analyst in a comment on that issue, and stops that task
  until the answer.
{{#analyst_github}}
  The comment mentions the analyst's account, `@{{analyst_github}}`, not the user.
{{/analyst_github}}
{{^analyst_github}}
  The comment names the analyst and does not mention the user.
{{/analyst_github}}
{{#assistant_github}}
  The assistant hands her question to the analyst from its own conversation, with the report
  of her task, without waiting for the watch.
{{/assistant_github}}
{{/analyst}}
{{^analyst}}
- When the coder finds a gap or an ambiguity in a specification while working on a task, she
  does not decide alone: she asks the user in a comment on that issue, mentioning the user,
  and stops that task until the answer.
{{/analyst}}
{{/coder}}
