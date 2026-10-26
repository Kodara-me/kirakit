{{#assistant_github}}
---
name: watch
description: Starts the lead's background checks of GitHub, one `kirakit-watch` per team account, and dispatches what they report to the team's members. Use only in the lead's session, at its start (the `assistant` launcher runs it) or when the checks stopped.
model: haiku
---

# Watch

Answer in {{language}}.

The lead's session is the only one that watches GitHub (one watch for the whole team). Run this
skill only there: in the session of another member (the `analyst` launcher, a background agent),
do nothing and say so in one line. The members run as the lead's background agents; none of
them watches.

## 1. Start the checks

The `kirakit-watch ROLE` command prints one line per change, `KIND REPOSITORY#NUMBER URL`, and
nothing otherwise. Start one per team account of the profile, each with its role in front of
every line, so that a line tells which account reported it:

| Role | Account |
| --- | --- |
| `assistant` | `{{assistant_github}}` |
{{#analyst_github}}
| `analyst` | `{{analyst_github}}` |
{{/analyst_github}}
{{#coder_github}}
| `coder` | `{{coder_github}}` |
{{/coder_github}}

1. With the Monitor tool, one persistent monitor per row, described as `kirakit-watch ROLE`,
   running:

   ```
   kirakit-watch ROLE 2>&1 | awk '{ print "ROLE " $0; fflush() }'
   ```

   The model wakes up only when a line is printed. When a monitor answers that a check of
   that role is already running (a second continuous check exits at once with one line),
   leave it: do not start it again, and do not kill the other one, and name it in the line
   of step 3 as already running.
2. With `/loop 10m`, run the fallback for the same roles, which covers a monitor that
   stopped:

   ```
   kirakit-watch assistant --once | awk '{ print "assistant " $0 }'
{{#analyst_github}}
   kirakit-watch analyst --once | awk '{ print "analyst " $0 }'
{{/analyst_github}}
{{#coder_github}}
   kirakit-watch coder --once | awk '{ print "coder " $0 }'
{{/coder_github}}
   ```

   Its output is handled like the monitors' lines. It prints nothing and checks nothing for a
   role whose continuous check runs, and never runs more often than every 10 minutes.
3. This turn is automated: write one line that names the checks that run, a check reported
   as already running included (`rules/team.md`, "Reporting in the conversation"). Nothing
   else is written until a line arrives.

A line that arrives from the fallback and from a monitor, or from two accounts, is one change
(next section).

## 2. Handle a line

A line is `ROLE KIND REPOSITORY#NUMBER URL`, where KIND is `comment`, `review-comment`,
`review`, `approved`, `assigned` or `ready`.

**Once per change.** Keep, for this session, the URLs of the comments and reviews already
handled, and skip a `comment`, `review-comment` or `review` line whose URL is in it, whichever
account reported it: one change can reach the checks of several accounts. The other kinds
point at an issue or a pull request, not at one event: for `approved`, `assigned` and `ready`,
read the state on GitHub first (below) and act only if it still calls for it, so that a second
line for the same change finds nothing to do.

**Read before acting.** Every `gh` command of this skill, reads included, is prefixed with
`GH_TOKEN=$(gh auth token --user {{assistant_github}})`, so that it uses the lead's account and
quota. None falls back to the user's account: when a command is refused with that token,
report it instead of running it as the user. Read the
issue or the pull request with its comments (`gh issue view`, `gh pr view --json
comments,reviews,commits`) to see what the line is about. The watch has already applied the
rule of `rules/git.md` ("Session marker and the user's replies"): a comment it reports counts
as the user's, a reply posted from a team account included. When the next comment you write in
that thread acts on such a reply, it starts with the line that rule asks for.

Then dispatch by kind and role:

{{#analyst_github}}
- **`comment`, `review-comment`, `review` from `analyst`**: a comment of the user on an idea
  or a specification assigned to the analyst's account, or in a thread where she is mentioned
  (`@{{analyst_github}}`), goes to the `iris` agent, as given, as the user's answer. When an
  `iris` task is already running on that issue, send it a message instead of starting a second
  one. Nothing else goes to the analyst: a thread that is neither assigned to her nor
  mentions her is not hers. Start the agent with `model: opus` when the comment asks for a
  change to a specification's requirements, design, decisions or tasks, and with no `model`
  otherwise; in that case say in its prompt that she stops and hands the work back when it
  turns out to need such a change, and a new `iris` agent on Opus takes it (`rules/team.md`).
- **`assigned` from `analyst`**: an idea (label `type:idea`) newly assigned to the analyst's
  account goes to the `iris` agent to specify, started with `model: opus`; the result waits in
  Specified for the user. An assigned task or specification starts nothing: Ready is the only
  gate.
{{/analyst_github}}
- **`ready` from `assistant`**: read the issue first: if it is no longer Ready, stop.
  Otherwise run the `next-task` skill for that repository (`--as {{assistant_github}}`). The
  work plan for the task it gives is the turn's one line, the task's URL with the go asked
  of the user, unless a plan he gave already covers it (`CLAUDE.md`: the work plan comes
  before every task); wait for the go, then
{{#coder}}
  hand the task to the `cleo` agent, as `rules/team.md` describes for a coder's task
  (no `model`: her agent runs on Sonnet). While a coder task is running, start nothing more: `next-task` runs again
  when her task ends with a pull request.
{{/coder}}
{{^coder}}
  work on the task yourself, as the lead; while you work on a task, start nothing
  more.
{{/coder}}
  When `next-task` gives nothing, the turn's line says that nothing is workable, with the
  Ready item's URL.
{{#coder}}
- **`approved`, or a `review` of the user, on a pull request of the coder or of the lead**:
  merge only under the merge rule. Read `gh pr view N --json reviews,commits`: merge when the
  user's own latest review is an approval submitted after the last commit.
{{#complete_approved_prs}}
  The one other case is a pull request of the coder that the lead completes without the user
  under `rules/team.md`.
{{/complete_approved_prs}}
{{/coder}}
{{^coder}}
- **`approved`, or a `review` of the user, on a pull request of the lead**: merge only under
  the merge rule. Read `gh pr view N --json reviews,commits`: merge when the user's own latest
  review is an approval submitted after the last commit.
{{/coder}}
  Merge as the workspace rules describe (fast-forward only, branches deleted, board moves, a
  rebase by the writer when `main` moved). Never on `reviewDecision`, never on the lead's own
  approval, and never on a review posted from a team account. When the condition does not
  hold, merge nothing and write nothing. A pull request the lead wrote itself waits for the
  user's own approval.
{{#coder}}
  When the user requested changes on a pull request of the coder, count its reviews in the
  state `CHANGES_REQUESTED` first, as `rules/team.md` describes: the first goes back to the
  `cleo` agent, and from the second on, the lead continues the pull request herself in a
  takeover agent on Opus, with the pull request, the task and the review comments. A pull
  request the lead already took over goes to a new takeover agent, never to the coder.
{{/coder}}
  Once a pull request is merged, run `next-task`; the turn's line holds the merge status and
  the work plan of the task it gives, as for a `ready` line.
{{#coder_github}}
- **`comment` from `coder`**: a comment of the user that answers a question of the coder goes
  to the `cleo` agent: a message to her running task on that issue, or, when none runs, her
  next task. Tell her question from the lead's by who asked last in the thread.
{{/coder_github}}
- **A comment of the user that answers a question of the lead**: act on it yourself, as the
  answer says.
- **`assigned` from any other account**: start nothing.

## 3. What belongs to the user

Whatever a line leads to, these stay with the user and are never done from a line: merging a
pull request outside the merge rule above, tagging or releasing, and creating, editing or
closing an issue other than the analyst's own work. Ask in a comment on the issue or pull
request that mentions the user, holds only the question with its options and your
recommendation, and ends with a short question, then wait. A gap or an ambiguity in a
specification, found by a member while she works on a task, goes to the analyst from the
lead's conversation, not through the watch.

## 4. What the chat shows

One line per woken turn, under "Reporting in the conversation" in `rules/team.md`: it holds
the URL of each issue or pull request the turn concerned with its action or status
(handed to a member, merged, asked the user), and nothing else. A line that leads to
nothing, and a round with no line, write nothing, in the chat or on GitHub.
{{/assistant_github}}
