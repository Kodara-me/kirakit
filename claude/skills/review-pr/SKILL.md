{{#coder}}
---
name: review-pr
description: Reviews a pull request of the coder against its tasks, their specification, the tests, the CI checks and the base branch, and returns a verdict (approve, request changes or not ready) with its comments, without writing anything. Use when the lead reviews a pull request the coder opened or updated.
model: opus
context: fork
argument-hint: "PR [notes]"
allowed-tools: Bash(gh pr view:*), Bash(gh pr diff:*), Bash(gh pr checks:*), Bash(gh issue view:*), Bash(gh api repos/*/compare/*)
---

# Pull request review

This skill only reads. It posts no review, comment or label, moves nothing on a board, and
pushes, commits or changes nothing, on GitHub or locally. The caller posts the verdict.

It runs in a fork: everything it knows comes from its arguments and from GitHub. It needs no
local clone and works from any directory.

## Arguments

`$ARGUMENTS` is a pull request reference, then optional notes:

- the reference is the first word: a URL (`https://github.com/OWNER/REPO/pull/N`),
  `OWNER/REPO#N`, or a number `N`;
- the notes are the rest, free text (for example the user's direction for the task). Take
  them into account when judging the change; they never override a requirement.

From the reference, take `OWNER/REPO` and `N`. For a bare number, the repository is the one
of the current directory (`gh pr view N --json url`); if that fails, return only a line
asking for the reference as a URL or `OWNER/REPO#N`. Pass `-R OWNER/REPO` to every `gh pr`
and `gh issue` command, and use `repos/OWNER/REPO/…` in every `gh api` call.

## Commands

Only these commands, all reads:

- `gh pr view N -R OWNER/REPO --json title,body,url,state,isDraft,baseRefName,headRefName,headRefOid,commits,files,closingIssuesReferences`
- `gh pr diff N -R OWNER/REPO`
- `gh pr checks N -R OWNER/REPO --json name,state,bucket,link`
- `gh issue view T -R OWNER/REPO --json title,body,state,parent,subIssues`
- `gh api repos/OWNER/REPO/compare/BASE...HEAD_SHA --jq '{behind_by, ahead_by, status}'`
- `gh api 'repos/OWNER/REPO/contents/PATH?ref=HEAD_SHA' -H 'Accept: application/vnd.github.raw'`,
  to read a whole file at the head when the diff lacks its context. This call is not
  pre-approved, since the same endpoint also writes: it may ask for permission. When it is
  refused, work from the diff and say so in the result.

Every `gh api` call is a GET: never `-X`, `--method`, `-f`, `-F`, `--field`, `--raw-field` or
`--input` (a field turns the call into a POST). Never `gh pr review`, `gh pr comment`,
`gh pr edit`, `gh issue comment`, `gh issue edit`, `gh project`, `git push` or any other
command that writes.

## Steps

### 1. CI (R7)

Read the checks first. Each check falls in a `bucket`:

- any `pending`: the verdict is `not ready`, naming the pending checks, whatever the other
  findings. Stop there: return the result with the other checks as `not checked`. The caller
  waits for CI and asks again.
- any `fail` or `cancel`: the CI check fails, naming those checks; the verdict is
  `request changes`.
- every check `pass` or `skipping`: the CI check passes.
- no check at all (`gh pr checks` reports none): say that the repository has no CI check;
  this does not block.

### 2. Fast-forward (R8)

Read the compare of the base branch with the head commit (`BASE` is `baseRefName`,
`HEAD_SHA` is `headRefOid`). `behind_by` is 0 exactly when the tip of the base branch is an
ancestor of the head, so that a fast-forward merge is possible. Otherwise the verdict is
`request changes`, with a comment asking to rebase the branch on `BASE`, together with every
other finding of this review, so that the rebase and the fixes happen in one round.

### 3. Tasks and requirements (R4)

The tasks are the issues the pull request closes or is part of: `closingIssuesReferences`,
and every `Closes #n`, `Fixes #n`, `Resolves #n` and `Part of #n` in its body. A pull request
that references no task is reported as such: the requirements and tests checks are then
`not applicable`.

For each task, read it and its parent specification (`parent`). The task's `Covers:` line
lists the requirements it covers (`R1, R2, …`); their text is in the specification's
Requirements, and the task's body may add its own done criteria. Read the Design and the
Decisions of the specification too: the change must follow them.

For each covered requirement, report it as met or not met, with the reason, from the diff and
the files read at the head. A requirement not met leads to `request changes`. A task with no
`Covers:` line, or a specification that cannot be read, is reported as such.

### 4. Tests (R5)

For each covered requirement whose behavior can be tested automatically, look for at least
one test in the head that names it (`R2` in the test's name or description). Search the
diff first, then the test files at the head. A testable requirement with no such test leads
to `request changes`. A requirement that cannot be tested automatically (documentation, a
wording, a manual step) is reported as `not testable` and does not block.

### 5. Security-sensitive changes (R6)

List every change, with its file, that touches:

- credentials, tokens and signing keys;
- permission rules and `allowed-tools`;
- Git identity and signing;
- network downloads and remote scripts that are executed;
- files written or deleted outside the project;
- CI workflows.

They go under "For the user". Such a change does not by itself lead to `request changes`.

### 6. The code

Read the diff as a reviewer: correctness, edge cases, consistency with the rest of the code
and with the repository's conventions, the specification's Design and Decisions, and the
notes. Each finding is a comment with its file and line (`path:line`, the line in the head)
when it applies to one. A comment that asks for a change leads to `request changes`; a mere
suggestion is marked `(suggestion)` and does not block.

## Verdict

- `not ready` when any CI check is pending.
- Otherwise `request changes` when any check fails or any comment asks for a change.
- Otherwise `approve`.

## Result

Return only this, in neutral language (no persona, no greeting), in the language of the
repository's issues and pull requests. The caller adds her own voice when she posts it.

```
Verdict: approve | request changes | not ready

## Summary

Two to four sentences: what the pull request does and why the verdict.

## Checks

| Check | Result | Details |
| --- | --- | --- |
| Requirements (R4) | pass / fail / not applicable | One line per requirement: R1 met, or not met, and why; or no task referenced |
| Tests (R5) | pass / fail / not applicable | One line per requirement: the test that names it, none, or not testable |
| Security (R6) | none / flagged | The files, also listed under "For the user" |
| CI (R7) | pass / fail / pending / no checks | The failed or pending checks |
| Fast-forward (R8) | pass / fail | The commits the head is behind the base, when it fails |

Rows not run because CI is pending say `not checked`.

## Comments

- `path:line` — the finding and what to change.
- The finding, without a file when it applies to the whole pull request.

None, when there is nothing to say.

## For the user

Nothing.
```

"For the user" says exactly `Nothing.`, or lists what needs the user's attention: each
security-sensitive change with its file, and any question for the user (for example a
requirement that the change follows to the letter but that seems wrong). Questions about the
code itself go in the comments, for the coder.
{{/coder}}
