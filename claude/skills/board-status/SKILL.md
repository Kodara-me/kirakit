---
name: board-status
description: Sets the status of a task, a specification or a pull request on every project board it is on, and can first add a pull request to the boards of the task it closes. Use when the developer starts a task, opens a pull request, gets changes requested or asks for a new review.
argument-hint: "NUMBER STATUS [--add-to-boards-of ISSUE]"
allowed-tools: Bash(gh issue view:*), Bash(gh pr view:*), Bash(gh repo view:*), Bash(gh project list:*), Bash(gh project item-list:*), Bash(gh project field-list:*)
---

# Board status

Answer in {{language}}.

Arguments: `NUMBER STATUS`, where NUMBER is an issue (a task or a specification) or a pull
request of the current repository, and STATUS is the name of a `Status` option, such as
`In progress` or `In review`. With `--add-to-boards-of ISSUE`, NUMBER is a pull request that
is first added to the boards ISSUE is on.

Use only `gh project`, `gh issue view`, `gh pr view` and `gh repo view` commands, never
`gh api graphql`: a narrow permission rule must be enough.

{{#assistant_github}}
## Account

Reads use the user's account. Writes (`gh project item-add`, `gh project item-edit`) are
made as the developer's account, by prefixing them with
`GH_TOKEN=$(gh auth token --user {{assistant_github}})`. When a write fails because that
account cannot write to the board (it is not a Writer of it), make the same write again
with the user's account, without the prefix, and keep using the user's account for that
board.

{{/assistant_github}}
## Steps

1. Repository owner: `gh repo view --json owner --jq .owner.login`. Boards are looked up
   under this owner.
2. Boards to update:
   - With `--add-to-boards-of ISSUE`: `gh issue view ISSUE --json projectItems`.
   - Otherwise, for an issue: `gh issue view NUMBER --json projectItems`; for a pull
     request: `gh pr view NUMBER --json projectItems`. Try the issue first, then the pull
     request.

   Each entry gives the board's `title`. When there is no entry, stop without a word: an
   item on no board is left alone.
3. For each board:
   1. Number and ID: `gh project list --owner OWNER --format json --jq '.projects[] |
      select(.title == "TITLE") | "\(.number) \(.id)"'`.
   2. `Status` field and option: `gh project field-list BOARD --owner OWNER --format json
      --jq '.fields[] | select(.name == "Status")'`. When the board has no option named
      STATUS, say so in one line ("No *STATUS* column on the TITLE board: #NUMBER left
      as it is.") and go on with the next board.
   3. Item:
      - With `--add-to-boards-of`: `gh project item-add BOARD --owner OWNER --url
        PULL_REQUEST_URL --format json --jq .id` (the URL from `gh pr view NUMBER --json
        url`). Adding an item that is already on the board returns the same item.
      - Otherwise: `gh project item-list BOARD --owner OWNER --limit 1000 --format json
        --jq '.items[] | select(.content.number == NUMBER and .content.repository ==
        "OWNER/REPO") | .id'`.
   4. `gh project item-edit --id ITEM --project-id PROJECT_ID --field-id FIELD_ID
      --single-select-option-id OPTION_ID`.
4. Report in one line per board, for example "#65 → In progress on Kodara". When the item
   already had that status, the edit changes nothing: report it the same way.
