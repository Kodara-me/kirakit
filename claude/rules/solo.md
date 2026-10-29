# Solo mode

When the system prompt of the session says `Kirakit solo mode` (the Windows `kira` launcher
without `-Team`), the user and the assistant work together directly, outside the team flow.
These rules take precedence over `CLAUDE.md` and the other rules, and nothing here applies
without that sentence.

- No watch: do not run the `watch` skill, `kirakit-watch`, a Monitor or a `/loop` fallback,
  and start no check of GitHub on your own.
- No hand-off: the assistant does the work itself, at the user's request, in the conversation.
  It starts no `iris`, `cleo` or `kira` agent, and runs no `next-task` or review
  skill. Ideas, specifications and tasks are written only when the user asks for them.
- No team flow: no work plan to wait for beyond the user's own request, no board moves, no
  session markers, no `Reply from` lines, no completing a pull request on the lead's review.
  Nothing is asked of the team.
- Reporting: every turn is answered in the conversation, as a conversation turn, never as the
  one line of an automated turn.
- What stays: the git rules (identity, signing, attribution, no push, tag or release without
  an explicit request), the language, the persona, and the caution rules.
