---
name: diffv
description: Compares the current code (including uncommitted changes) with the latest version of the branch and gives a concise analysis of the changes. Use when the user asks what changed, for a summary or an analysis of the diff.
model: sonnet
context: fork
argument-hint: "[ref to compare with, e.g. main, origin/main, HEAD~3]"
allowed-tools: Bash(git status:*), Bash(git diff:*), Bash(git log:*), Bash(git fetch:*), Bash(git rev-parse:*), Bash(git merge-base:*), Bash(git branch:*), Bash(git show:*), Read, Grep, Glob
---

# Change analysis

Answer in {{language}}.

## 1. Pick the reference

- If an argument is given (`$ARGUMENTS`), compare with that ref.
- Otherwise, compare with the latest version of the current branch:
  - `git fetch`, then the upstream `@{u}` if there is one (covers unpushed commits and uncommitted work);
  - without an upstream: `HEAD` (uncommitted work only).
- For another branch (e.g. `main`), start from `git merge-base <ref> HEAD` so that only the current branch's changes are shown.
- State in one line which reference is used.

## 2. Collect the diff

- `git status --short` (include untracked files, and read them if relevant).
- `git diff --stat <base>` then `git diff <base>` (the working tree against the base, staged or not).
- `git log --oneline <base>..HEAD` if commits are included.
- If the diff is large, read key files in full when the context is needed to understand a change.

## 3. Concise analysis

Answer briefly, without copying the diff:

- **Summary**: 1 to 3 sentences on the overall intent of the changes.
- **Changes by theme**: group by feature or module rather than file by file; one line per point, with `[file](path:line)` links.
- **Points of attention**: only if there are any — likely bugs, regressions, unhandled edge cases, inconsistencies between files (e.g. a protocol changed on the server side but not on the client side), removed or missing tests, files that should not be there (secrets, build artifacts, leftover debug code).
- **Deleted or renamed files**: mention them explicitly.

Change nothing and commit nothing: this skill is read-only.
