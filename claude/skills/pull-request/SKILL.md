---
name: pull-request
description: Writes and opens the pull request of the current task, for the member who opens it, following the git rules for her account, assignee and reviewers, closes the tasks it completes and moves it on the board. Use when a member opens the pull request of her task.
model: sonnet
---

# Open a pull request

Answer in {{language}}.

This skill opens the pull request of the current branch for the member who opens it: the
coder when the team has one, otherwise the developer. It names no account itself: the
account that writes, the assignee, the reviewers and the board moves are the ones the git
rules (`rules/git.md`) give that member. When the rules give her a GitHub account, every
`gh` command of this skill, reads included, is prefixed with
`GH_TOKEN=$(gh auth token --user <login>)`, so that it uses her account and quota. None falls
back to the user's account: when a command is refused with that token, report it instead of
running it as the user. When the rules give her no GitHub account, she uses the user's
account (no `GH_TOKEN` prefix) and the board moves take no `--as`.

## 1. Check the branch

- Branch: `git rev-parse --abbrev-ref HEAD`; default branch:
  `gh repo view --json defaultBranchRef --jq .defaultBranchRef.name`. On the default branch,
  stop and say so: a pull request needs its own branch.
- Commits: `git log --oneline origin/<default>..HEAD`. With none, stop and say so.
- `git status --short`: uncommitted changes are not part of the pull request. Mention them;
  do not commit them here.
- An open pull request for the branch (`gh pr view --json url,state`): report its URL and
  stop. Updating it is a push, then a new review request, as the rules say.

## 2. The tasks

- The tasks come from the conversation (the task handed to the member and the user's
  direction), the branch name and the commits. Read each one with
  `gh issue view <n> --json title,body,parent`.
- The pull request closes each task it completes with one `Closes #<n>` line, and nothing
  else. A task it only partly covers is mentioned as `Part of #<n>`, never closed.

## 3. Push

- Pushing follows the git rules: push only when the user asked for the pull request,
  directly or through the task handed to the member that ends with one.
- `git push -u origin <branch>`. Never `--force` or `--force-with-lease` without an explicit
  request. When the remote branch has diverged, stop and report it.

## 4. Title and description

- Title: Conventional Commits, with the scopes the repository uses (its commits and
  `gh pr list --state merged --limit 5 --json title`), describing the change as a whole.
- Description, neutral and in the repository's language (English unless it uses another):
  - what the change does and why, from the task and the intent behind the commits;
  - the main changes, as a short list;
  - the tests run and their result;
  - one `Closes #<n>` line per task completed.
- No generation footer and no mention of Claude, Anthropic or a model, as the attribution
  rules say.
- Write the description to a temporary file and pass it with `--body-file`.

## 5. Open it

- `gh pr create --base <default> --head <branch> --title "<title>" --body-file <file>`,
  with the `--assignee` and `--reviewer` the git rules give the member who opens it, and
  prefixed with `GH_TOKEN=$(gh auth token --user <login>)` when the rules give her an
  account.

## 6. Board

- For each task it closes, add the pull request to the task's boards in In review, then move
  the task to In review: `board-status <pr> In review --add-to-boards-of <task>` and
  `board-status <task> In review`, each with `--as <login>` when the rules give the member
  an account.

## 7. Report

- The pull request's URL, the tasks it closes, the reviewers requested and the board moves,
  in a few lines.
