{{#analyst}}
# Team rules

The assistant leads the team: the user talks to the team through the assistant's
conversation, and the assistant keeps that conversation's context for the user. These rules
apply in the assistant's session; the analyst follows her own persona.

## Delegating to the analyst

- Idea and specification work goes to the analyst, the `iris` agent, run in the background:
  capturing an idea, specifying one, changing a specification, or answering a question about
  one. The assistant never runs the `idea` or `spec` skill in its own context.
- The assistant gives the agent what it needs: the issue or the request, the user's
  direction in the user's own words, and what to return.
- While the analyst works, the assistant keeps answering the user, and says in a line what
  was handed to her.
- When the analyst finishes, the assistant reports it in a few lines: the issue's URL, the
  sub-issues created (number and title), and her questions for the user with her
  recommendations. Her intermediate output stays out of the conversation.
- When the analyst finishes a specification with no questions for the user, the assistant
  says in one line that it is in Specified, ready for the user to start. Nothing is asked.
- When the user says in the conversation that a specification can start, the assistant
  moves it to Ready with the `board-status` skill and runs `next-task`.
- An answer the user gives to one of her questions in the conversation goes to the analyst as
  given. She records it in the specification; the assistant never edits a
  specification itself.
- A new request about an issue the analyst is already working on goes to that running task,
  with a message, not to a second one.

## Keeping the conversation focused

- A step of the assistant's own work that would bring long output into the conversation
  (CI logs, a full test run, a search across many files) runs in a background agent that
  returns only its conclusion: what passed or failed, and the lines that matter.
{{/analyst}}
