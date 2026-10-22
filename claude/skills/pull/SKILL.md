---
name: pull
description: Fetches and pulls the current Git branch from its remote. Use when the user asks to update, sync or pull the current branch.
model: haiku
context: fork
allowed-tools: Bash(git status:*), Bash(git fetch:*), Bash(git pull:*), Bash(git branch:*), Bash(git rev-parse:*), Bash(git log:*), Bash(git rev-list:*)
---

# Pull the current branch

Answer in {{language}}.

1. Identify the branch and its upstream:
   - `git rev-parse --abbrev-ref HEAD`
   - `git rev-parse --abbrev-ref --symbolic-full-name @{u}` (if there is no upstream, say so and stop: do not set one up without asking).
2. `git fetch --prune` to get the state of the remote.
3. Show what is coming: `git log --oneline HEAD..@{u}` and the count `git rev-list --left-right --count HEAD...@{u}` (ahead / behind).
4. If there is nothing to fetch, say so and stop.
5. Check `git status --porcelain`:
   - If uncommitted local changes touch files changed upstream, warn the user before continuing.
   - Never run `git stash`, `reset` or `checkout` on files without explicit approval.
6. `git pull --rebase` if the branch has unpushed local commits, otherwise `git pull --ff-only`.
7. On conflict: list the conflicting files, resolve nothing automatically, and offer `git rebase --abort` or a guided resolution.
8. Summarize: number of commits fetched, files changed (`git diff --stat ORIG_HEAD..HEAD`), final state.
