---
name: idea
description: Captures an idea as a GitHub issue in the format of the "Idea" issue form (problem, desired outcome, context), without analysis or specification. Use when the user wants to note, capture or log an idea, a problem or an opportunity for later.
model: opus
argument-hint: "[the idea, in a few words]"
allowed-tools: Bash(gh issue list:*), Bash(gh label list:*), Bash(gh repo view:*)
---

# Capture an idea

Answer in {{language}}. The issue itself is written in neutral English, unless the
repository already uses another language. The comments posted on the issue
follow the member's own voice, in the repository's language.
{{#analyst_github}}

The analyst's work is done on GitHub as the analyst's own account, `{{analyst_github}}`,
whoever runs this skill: every `gh` command of this skill, reads included, is prefixed with
`GH_TOKEN=$(gh auth token --user {{analyst_github}})`, for example
`GH_TOKEN=$(gh auth token --user {{analyst_github}}) gh issue create …`. None falls back to
the user's account: when a command is refused with that token, report it instead of running
it as the user. Every comment this skill posts, its comment files included, ends with the
analyst's session marker, alone on its last line: `<!-- kirakit:analyst -->`
(`rules/git.md`). Issue bodies stay unmarked.
{{/analyst_github}}
{{^analyst_github}}
{{#assistant_github}}

This work is done on GitHub as the developer's own account, `{{assistant_github}}`: every
`gh` command of this skill, reads included, is prefixed with
`GH_TOKEN=$(gh auth token --user {{assistant_github}})`, for example
`GH_TOKEN=$(gh auth token --user {{assistant_github}}) gh issue create …`. None falls back
to the user's account: when a command is refused with that token, report it instead of
running it as the user. Every comment this skill posts, its comment files included, ends
with the assistant's session marker, alone on its last line: `<!-- kirakit:assistant -->`
(`rules/git.md`). Issue bodies stay unmarked.
{{/assistant_github}}
{{/analyst_github}}

An idea records intent only: the problem or opportunity and the outcome wanted. Do not read
the code, analyze, design or plan tasks: that is the `spec` skill's job, later.

## Format

Title: `[IDEA] ` followed by a short statement of the outcome (e.g. `[IDEA] Reuse a previous
search without rebuilding its filters`).

Body, with the headings of the "Idea" issue form, in this order. An optional section with
nothing to say holds `_No response_`, as the form does.

```markdown
### Problem or opportunity

What happens today and why it is worth considering.

### Desired outcome

What becomes possible or better, without prescribing the solution.

### Who is affected?

### Known context

### Open questions

### Why now?

### Additional context

### IDEA stage check

- [X] This issue describes the problem or opportunity and desired outcome without committing to a technical implementation.
```

- Keep implementation details out. If the user gave a technical approach, record it under
  Additional context as "Possible approach (not decided): …".
- Questions the user raised, or that the idea obviously leaves open, go under Open
  questions. Do not invent more.

## Steps

1. Take the idea from `$ARGUMENTS` and the conversation. Ask one question only if the
   problem or the desired outcome cannot be inferred.
2. Look for duplicates: `gh issue list --state all --search "<keywords>" --limit 5`. If a
   similar issue exists, show it and ask whether to go on.
3. Labels: `type:idea` and `status:needs-clarification`. Check them with `gh label list`, and
   create a missing one without asking (`gh label create`).
4. Create the issue without asking for confirmation: `gh issue create --title "<title>"
   --body-file <file> --label …`, with the body in a temporary file outside the repository.
{{#analyst_github}}
   Assign it to `{{analyst_github}}`, the owner of ideas until they become specifications:
   `--assignee {{analyst_github}}`.
{{/analyst_github}}
{{^analyst_github}}
{{#assistant_github}}
   Assign it to `{{assistant_github}}`, the owner of ideas: `--assignee {{assistant_github}}`.
{{/assistant_github}}
{{/analyst_github}}

End with the issue's URL and one line saying that `/spec #<n>` turns it into a
specification.
