---
name: spec
description: Writes a feature specification (context, requirements, design, tasks) in a GitHub issue, one phase at a time, and creates each task as a sub-issue. Use when the user asks to specify, spec out or plan a feature, to refine a feature request issue, or to move a specification file into an issue.
argument-hint: "[idea, issue number or URL, or path to a specification file]"
allowed-tools: Bash(gh issue view:*), Bash(gh issue list:*), Bash(gh label list:*), Bash(gh repo view:*), Bash(git log:*), Bash(git status:*), Read, Grep, Glob
---

# Feature specification

Answer in {{language}}. The specification itself is written in neutral English, unless the
repository already uses another language.

## Format

The parent issue holds the specification. Its body uses these sections, in this order, with
the same headings as the "Feature request" issue form:

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

## 1. Start from the input

Read `$ARGUMENTS`:

- **An issue** (`#12` or a URL): `gh issue view <n> --json number,title,body,labels,parent,subIssues`.
  Keep what is already written; the phases below fill or correct the missing parts.
- **A file** (a specification kept in the repository): read it and map its content onto
  the format. Once the issue exists, offer to delete the file in a separate commit.
- **An idea** or nothing: ask what the feature is for, in one or two questions at most.

Read the code that the feature touches before writing anything, so the design matches the
repository.

## 2. Write it one phase at a time

Show each phase in the conversation and wait for the user's approval before the next one.
Ask the questions that block a phase; record the others under Open questions.

1. **Context and requirements.**
2. **Design.**
3. **Tasks**: the list of sub-issues, with their titles, the requirements each one covers
   and their "Done when". Check that every requirement is covered.

## 3. Publish

Show what will be created or edited (parent issue, then each sub-issue) and ask for
confirmation before any `gh issue create` or `gh issue edit`. Then:

- Parent: `gh issue create --title "<title>" --body-file <file>`, or
  `gh issue edit <n> --body-file <file>` for an existing issue. Add `--label enhancement`
  only if `gh label list` shows it.
- Sub-issues, in the order they should be done: `gh issue create --parent <parent> --title
  "<title>" --body-file <file>`. An existing issue becomes a sub-issue with
  `gh issue edit <parent> --add-sub-issue <n>`.
- Write bodies to temporary files outside the repository, never into the working tree.

End with the parent's URL and the list of sub-issues (number and title).

## Changing a specification

When the user asks to change a published specification, edit the parent body and the
affected sub-issues the same way, with the same confirmation. A change to the requirements
updates the "Covers" line of every task concerned.
