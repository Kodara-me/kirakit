{{#start_verified_specs}}
---
name: review-spec
description: Verifies a specification of the analyst against its requirements, tasks, decisions and the code it names, and returns a verdict (verified, changes requested or needs the user) with its comments, without writing anything. Use when the lead verifies a specification the analyst finished with no question for the user.
model: opus
context: fork
argument-hint: "SPEC [notes]"
allowed-tools: Bash(gh issue view:*)
---

# Specification verification

This skill only reads. It posts no comment, edits no issue, adds no label, moves nothing on
a board, and pushes, commits or changes nothing, on GitHub or locally. The caller posts the
verdict.

It runs in a fork: everything it knows comes from its arguments and from GitHub. It needs no
local clone and works from any directory.

## Arguments

`$ARGUMENTS` is a specification reference, then optional notes:

- the reference is the first word: a URL (`https://github.com/OWNER/REPO/issues/N`),
  `OWNER/REPO#N`, or a number `N`;
- the notes are the rest, free text (for example the user's direction for the feature, or
  the comments of an earlier verification). Take them into account; they never override a
  requirement. Notes that hold the comments of an earlier verification make this a later
  round (see "Later rounds").

From the reference, take `OWNER/REPO` and `N`. For a bare number, the repository is the one
of the current directory (`gh issue view N --json url`); if that fails, return only a line
asking for the reference as a URL or `OWNER/REPO#N`. Pass `-R OWNER/REPO` to every
`gh issue` command, and use `repos/OWNER/REPO/…` in every `gh api` call.
{{#assistant_github}}

The verification is the lead's: every `gh` command of this skill, reads included, is
prefixed with `GH_TOKEN=$(gh auth token --user {{assistant_github}})`, so that it uses the
lead's account and quota. None falls back to the user's account: when a command is refused
with that token, report it instead of running it as the user.
{{/assistant_github}}

## Commands

Only these commands, all reads:

- `gh issue view N -R OWNER/REPO --json title,body,state,labels,comments,subIssues`
- `gh issue view T -R OWNER/REPO --json title,body,state,labels`, for each task `T`
- `gh api 'repos/OWNER/REPO/contents/PATH' -H 'Accept: application/vnd.github.raw'`, to read
  a file the specification names, on the default branch; `gh api repos/OWNER/REPO/contents/DIR
  --jq '.[].name'` lists a directory. This call is not pre-approved, since the same endpoint
  also writes: it may ask for permission. When it is refused, verify from the issues alone
  and say so in the result.

Every `gh api` call is a GET: never `-X`, `--method`, `-f`, `-F`, `--field`, `--raw-field` or
`--input` (a field turns the call into a POST). Never `gh issue comment`, `gh issue edit`,
`gh issue close`, `gh issue create`, `gh label`, `gh project`, `git push` or any other
command that writes.

## Security questions

A security question is an open choice about:

- credentials, tokens or signing keys;
- permission rules or `allowed-tools`;
- Git identity or signing;
- network downloads or remote scripts that are executed;
- files written or deleted outside the project;
- CI workflows;
- accounts and their access rights;
- data exposed outside the user's machine or to other people.

A change to such a file that follows from the user's decisions or the existing rules is not
an open choice. Only the user settles a security question: neither the analyst nor the lead
settles one, and a question either of them flags as a security question always goes to the
user.

## Blocking findings and suggestions

Each finding is either blocking or a suggestion. Only a finding of one of these classes is
blocking:

- a requirement that no task covers, or a task that lists a requirement that does not exist
  (step 2);
- a requirement that neither a test nor a reader can check (step 1);
- a contradiction between the requirements, the decisions, the user's answers or the code
  that would make a task impossible to complete as written or would lead to wrong behavior
  (steps 1, 4 and 5);
- a task that, merged alone, would make a check of the repository fail (step 3).

Every other finding is a suggestion, notably: a requirement that holds several behaviors
each of which is testable, or that states an implementation detail; a decision whose reason
is missing or thin; an incomplete list of files, lines or test checks in the Design (the
tasks' "Done when" requires the repository's checks to pass, and the splitting rule of the
`spec` skill, "once merged alone on `main`, every check of the repository passes", makes the
coder find the remaining places); a path or line reference that is wrong without changing
the behavior; tests or documentation split into a task of their own, or a split by platform,
installer, file or layer, that does not make a check fail; a task larger than the review-size
guideline; a fourth task without its reason in the Decisions.

A suggestion never changes the verdict, whatever their number.

## Steps

Read the specification with its comments and sub-issues, then each task. Each finding is a
comment that names the requirement (`R2`), the decision (`D3`) or the task (`#41`) it
applies to, and what to change, and that is classified as blocking or a suggestion.

1. **Requirements.** Each requirement is a single testable statement of observable
   behavior, not of implementation: one behavior, with a condition and a result that a test
   or a reader can check. An untestable wish blocks; a requirement that holds two behaviors
   that are each testable, or an implementation detail, is a suggestion.
2. **Coverage.** Every requirement that is not struck through is listed on the `Covers:`
   line of at least one task, and every requirement a task lists exists.
3. **Splitting.** The tasks follow the splitting rules of the `spec` skill: each task lands
   on its own, with every check of the repository passing once it is merged alone; changes
   that only pass the checks together stay in one task; tests and documentation stay in the
   task that changes the behavior, never split by platform, installer, file or layer; 1 to 3
   tasks, unless the Decisions record why, naming review size or a stage to try out for each
   extra task. Only a task that would make a check of the repository fail when merged alone
   blocks; the other breaches are suggestions.
4. **Decisions.** Every decision states its question, its choice and its reason.
5. **Code.** The specification is consistent with the code and files it names: the paths,
   functions, options and behaviors its Context and Design describe exist as described, or
   are named as new. Read those files at the default branch.
6. **Security.** No decision taken without the user settles a security question, and the
   specification leaves no security question open without asking the user. A decision is
   the user's when it says it is his answer (on the issue or in the conversation).

## Verdict

- `needs the user` when a decision taken without the user settles a security question, or
  when the specification leaves a security question open: name each one under "For the
  user", with its options and a recommendation. Report the other findings too.
- Otherwise `changes requested` when there is any blocking finding.
- Otherwise `verified`, with the suggestions, if any.

## Later rounds

When the notes hold the comments of an earlier verification:

- an "Earlier round" part of the result states, for each blocking finding of that round,
  whether it is resolved;
- a suggestion already given in that round is not repeated;
- a blocking finding about a part of the specification that did not change since that round
  is marked "not raised in the earlier round".

## Result

Return only this, in neutral language (no persona, no greeting), in the language of the
repository's issues. The caller adds her own voice when she posts it.

```
Verdict: verified | changes requested | needs the user

## Summary

Two to four sentences: what the specification covers and why the verdict.

## Checks

| Check | Result | Details |
| --- | --- | --- |
| Requirements | pass / suggestions / fail | The requirements that are not single testable statements, and which of them block |
| Coverage | pass / fail | The requirements no task covers, or the tasks that list unknown ones |
| Splitting | pass / suggestions / fail | The tasks that break a splitting rule, and which of them block |
| Decisions | pass / suggestions / fail | The decisions without a reason |
| Code | pass / suggestions / fail / not checked | The statements that do not match the code, or why files could not be read |
| Security | none / flagged | The security questions settled without the user or left open |

`fail` means at least one blocking finding in that row; `suggestions` means only
suggestions.

## Earlier round

Only on a later round: each blocking finding of the earlier round as resolved or not
resolved, with the reason. Omit the part on a first round.

## Blocking

- `R2` — the finding and what to change. A blocking finding on a part that did not change
  since the earlier round ends with "(not raised in the earlier round)".

None, when there is no blocking finding.

## Suggestions

These do not change the verdict.

- `R2` — the suggestion.

None, when there is nothing to suggest.

## For the user

Nothing.
```

"For the user" says exactly `Nothing.`, or lists each security question for the user, with
its options and a recommendation.
{{/start_verified_specs}}
