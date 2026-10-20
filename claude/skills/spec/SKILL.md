---
name: spec
description: Turns an idea into a feature specification (context, requirements, design, tasks) in a GitHub issue, one phase at a time, and creates each task as a sub-issue. Starts from an idea issue, an existing specification to resume, a specification file, or a description. Use when the user asks to specify, spec out, clarify or plan a feature or an idea.
argument-hint: "[issue number or URL, path to a specification file, or a description]"
allowed-tools: Bash(gh issue view:*), Bash(gh issue list:*), Bash(gh label list:*), Bash(gh repo view:*), Bash(git log:*), Bash(git status:*), Read, Grep, Glob
---

# Feature specification

Answer in {{language}}. The specification itself is written in neutral English, unless the
repository already uses another language.

## Format

The specification lives in one issue, the parent. Its title states the feature, without a
prefix. Its body uses these sections, in this order, with the same headings as the
"Feature request" issue form. A section not written yet holds `_To be written._`.

```markdown
### Context

The problem to solve and why it matters now.

### Requirements

- **R1** — When …, the … shall …
- **R2** — …

### Design

How the requirements will be met, and the trade-offs considered.

### Tasks

Tracked as sub-issues.

### Open questions

- …
```

- **Requirements** are numbered `R1`, `R2`, … and never renumbered: a dropped requirement
  stays, struck through (`~~**R3** — …~~`), so references to it keep their meaning. Each one
  is a single testable statement of observable behavior, not of implementation.
- **Design** names the modules touched, the data and interfaces, and the alternatives
  rejected with the reason. It stays short; link files as `path:line` when useful.
- **Open questions** lists what is still undecided, or `None`.

Each task is a sub-issue of the parent:

- Title: imperative, specific, at most 72 characters (e.g. "Parse the retry delay from
  the config file").
- Body:

  ```markdown
  Part of #<parent>.

  Covers: R1, R3

  <What to change, in a few lines.>

  ### Done when

  - <Observable result, usually the test that proves it.>
  ```

- A task is small enough for one pull request, and lists the requirements it covers. Every
  requirement is covered by at least one task.

Labels: the parent has `type:feature`, plus `status:specified` once its tasks are
published; sub-issues have `type:task`.

## 1. Start from the input

Read `$ARGUMENTS`:

- **An issue** (`#12` or a URL): `gh issue view <n> --json number,title,body,labels,parent,subIssues`.
  - An **idea** (label `type:idea`, a `[IDEA] ` title, or the headings of the "Idea" form:
    Problem or opportunity, Desired outcome, …): start with step 2.
  - A **specification**: resume at the first phase whose section is missing, empty, or
    `_To be written._`. Show what is already there in two or three lines first.
- **A file** (a specification kept in the repository): read it and map its content onto
  the format, then resume like a specification. Once the issue exists, offer to delete the
  file in a separate commit.
- **A description** or nothing: ask what the feature is for, in one or two questions at
  most, then go to step 3.

Read the code that the feature touches before writing anything, so the specification
matches the repository.

## 2. Clarify an idea

Before writing any requirement:

- Restate the idea in two or three sentences: the problem, the outcome, who is affected.
- Say what already exists in the code and what is missing, with `path:line` links.
- Answer the idea's open questions that the code settles, and list the rest, with the new
  questions the analysis raised. Ask them all at once, most important first, and propose
  an answer for each one when there is a sensible default.

Wait for the answers, then go on to step 3. The idea's content feeds the specification:
problem and outcome go to Context, together with who is affected and why now; questions
still unanswered go to Open questions.

## 3. Write it one phase at a time

Show each phase in the conversation and wait for the user's approval before the next one.
Ask the questions that block a phase; record the others under Open questions.

1. **Context and requirements.**
2. **Design.**
3. **Tasks**: the list of sub-issues, with their titles, the requirements each one covers
   and their "Done when". Check that every requirement is covered.

## 4. Publish

Publish when the tasks are approved, or after any approved phase if the user asks; the
phases not written yet hold `_To be written._`. Show what will be created or edited, and ask
for confirmation before any `gh issue create` or `gh issue edit`. Then:

- Parent: `gh issue create --title "<title>" --body-file <file>`, or
  `gh issue edit <n> --title "<title>" --body-file <file>` for an existing issue. An idea
  becomes the specification in place: same issue, `[IDEA] ` removed from the title, body
  rewritten in the format above.
- Labels on the parent, with `gh issue edit --add-label / --remove-label`:
  - add `type:feature`, and remove `type:idea`;
  - once the tasks are published, add `status:specified` and remove
    `status:needs-clarification`.
- Sub-issues, in the order they should be done: `gh issue create --parent <parent> --title
  "<title>" --body-file <file> --label type:task`. An existing issue becomes a sub-issue
  with `gh issue edit <parent> --add-sub-issue <n>`.
- Before adding a label, check it with `gh label list`. If it is missing, offer to create
  it (`gh label create`); if the user declines, go on without it.
- Write bodies to temporary files outside the repository, never into the working tree.

End with the parent's URL, the list of sub-issues (number and title) if any, and the next
phase to write if the specification is not complete.

## Changing a specification

When the user asks to change a published specification, edit the parent body and the
affected sub-issues the same way, with the same confirmation. A change to the requirements
updates the "Covers" line of every task concerned.
