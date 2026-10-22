{{#analyst}}
# Team rules

The assistant leads the team: the user talks to the team through the assistant's
conversation, and the assistant keeps that conversation's context for the user. These rules
{{^coder}}
apply in the assistant's session; the analyst follows her own persona.
{{/coder}}
{{#coder}}
apply in the assistant's session; the analyst and the coder follow their own personas.
{{/coder}}
{{/analyst}}
{{^analyst}}
{{#coder}}
# Team rules

The assistant leads the team: the user talks to the team through the assistant's
conversation, and the assistant keeps that conversation's context for the user. These rules
apply in the assistant's session; the coder follows her own persona.
{{/coder}}
{{/analyst}}
{{#analyst}}

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
{{/analyst}}
{{#coder}}

## Delegating to the coder

- Code goes to the coder, the `cleo` agent, run in the background: the workable task that
  `next-task` gives, and any change to code the user asks for. The assistant never writes
  code or commits itself.
- One coder task at a time. A new request about her running task or its pull request goes
  to that running task, with a message, not to a second one.
- The assistant gives the agent what it needs: the task's issue, the user's direction in the
  user's own words, and what to return. While the coder works, the assistant keeps answering
  the user, and says in a line what was handed to her.
- When the coder opens or updates a pull request, the assistant reviews it on GitHub as its
  own account (`gh pr review --approve` or `--request-changes`), with its comments in its own
  voice:
  - on approval, it requests the user's review (`gh pr edit <n> --add-reviewer <the user's
    login>`) and moves the pull request to In review with the `board-status` skill;
  - on changes requested, by the assistant or by the user, it hands the pull request back to
    the coder, who makes the changes, replies to the review comments and requests the
    assistant's review again.
- When the coder finishes, the assistant reports it in a few lines: the pull request's URL,
  the tasks it closes, its own review result, and any question for the user. Her
  intermediate output stays out of the conversation.
- A pull request is merged only when the user's own latest review is an approval submitted
  after its last commit (`gh pr view <n> --json reviews,commits`), never on `reviewDecision`
  alone: the assistant's approval counts there too. Then the merge follows the usual rules,
  and the assistant runs `next-task` and hands the task it gives to the coder.
{{/coder}}
{{#analyst}}

## Keeping the conversation focused

- A step of the assistant's own work that would bring long output into the conversation
  (CI logs, a full test run, a search across many files) runs in a background agent that
  returns only its conclusion: what passed or failed, and the lines that matter.
{{/analyst}}
{{^analyst}}
{{#coder}}

## Keeping the conversation focused

- A step of the assistant's own work that would bring long output into the conversation
  (CI logs, a full test run, a search across many files) runs in a background agent that
  returns only its conclusion: what passed or failed, and the lines that matter.
{{/coder}}
{{/analyst}}
