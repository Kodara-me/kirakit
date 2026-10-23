---
name: next-task
description: Finds the developer's next workable task from the project board, following the specifications the user moved to Ready, in order, and skipping tasks that are taken, blocked, waiting for an answer or overlapping a pull request in review. Use when the developer starts working and after each pull request she opens.
model: sonnet
context: fork
argument-hint: "[--as ACCOUNT]"
allowed-tools: Bash(gh repo view:*), Bash(gh project list:*), Bash(gh project item-list:*), Bash(gh issue view:*), Bash(gh issue list:*), Bash(gh pr list:*), Bash(gh pr view:*)
---

# Next task

Answer in {{language}}.

Only read commands: `gh project`, `gh issue` and `gh pr`. This skill changes nothing; the
developer starts the task it gives.

## Account

{{#assistant_github}}
The account is ACCOUNT when `--as ACCOUNT` is given, and the developer's account,
`{{assistant_github}}`, otherwise. Every `gh` command of this skill, reads included, is
prefixed with `GH_TOKEN=$(gh auth token --user ACCOUNT)`, so that it uses that account and
its quota. None falls back to the user's account: when a command is refused with that
token, report it in one line with GitHub's error instead of running it as the user.
{{/assistant_github}}
{{^assistant_github}}
With `--as ACCOUNT`, every `gh` command of this skill, reads included, is prefixed with
`GH_TOKEN=$(gh auth token --user ACCOUNT)`, so that it uses that account and its quota. None
falls back to the user's account: when a command is refused with that token, report it in
one line with GitHub's error instead of running it as the user. Without `--as`, the
commands use the user's account.
{{/assistant_github}}

## 1. Specifications that can be worked on

A task is workable only while its specification is in **Ready** or **In progress**.

- Board: the repository owner (`gh repo view --json owner,nameWithOwner`), its boards
  (`gh project list --owner OWNER --format json`), and for each board the items
  (`gh project item-list BOARD --owner OWNER --limit 1000 --format json`), which come in
  board order. Keep the items of this repository whose `status` is Ready or In progress and
  whose labels include `type:feature`, in that order.
- No board: the open issues with both `type:feature` and `status:ready`
  (`gh issue list --label type:feature --label status:ready --state open`), oldest first.

## 2. Their tasks, in order

For each specification, `gh issue view <n> --json subIssues` gives its sub-issues in order.
Take the open ones, and skip a task when:

- it is In progress or In review on the board (it is taken);
- it is blocked by an open issue (`gh issue view <task> --json blockedBy`);
- its last comment is a question from the developer, with no answer after it
  (`gh issue view <task> --json comments`);
{{#assistant_github}}
  the developer's comments are those of `{{assistant_github}}`;
{{/assistant_github}}
- it touches the same files as an open pull request in review: compare the files the task
  names in its body with the files of each open pull request (`gh pr list --state open
  --json number,files`). A shared test file, such as `scripts/test.sh`, does not count.

The first task that is not skipped is the next task.

## 3. Then issues with no specification

When no specification gives a task, take the board's Ready items of this repository that
are issues with no parent (`gh issue view <n> --json parent`), in board order, with the
same skips.

## 4. Answer

- A task: "Next task: #<n> <title> (specification #<parent>)."
- None: "Nothing workable.", then one line per task skipped with its reason, for example
  "#91: blocked by #93."
