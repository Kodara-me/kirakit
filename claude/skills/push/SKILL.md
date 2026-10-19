---
name: push
description: Pushes the local commits of the current branch to its remote. Use when the user asks to push their commits.
model: haiku
disable-model-invocation: true
allowed-tools: Bash(git status:*), Bash(git fetch:*), Bash(git push:*), Bash(git branch:*), Bash(git rev-parse:*), Bash(git log:*), Bash(git rev-list:*), Bash(git remote:*)
---

# Push commits

Answer in {{language}}.

1. Identify the branch: `git rev-parse --abbrev-ref HEAD` and its upstream `git rev-parse --abbrev-ref --symbolic-full-name @{u}`.
2. `git fetch` then `git rev-list --left-right --count HEAD...@{u}`:
   - Nothing ahead: say so and stop.
   - Behind the remote: do not force; suggest the `pull` skill first.
3. List what will be pushed: `git log --oneline @{u}..HEAD`.
4. If `git status` shows uncommitted changes, mention them (they will not be pushed).
5. Push:
   - With an upstream: `git push`.
   - Without an upstream: `git push -u origin <branch>`.
6. Forbidden without an explicit request from the user: `--force` / `--force-with-lease`, pushing to a branch other than the current one, deleting a remote branch.
7. Summarize: branch, remote, number of commits pushed, and the PR URL suggested by the remote if there is one.
