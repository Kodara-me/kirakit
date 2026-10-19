---
name: commit
description: Creates a Git commit in Conventional Commits format after checks (tests, build, lint, sensitive files), then asks for confirmation showing the test results and the proposed message. Use when the user asks to commit their changes.
model: haiku
---

# Commit with Conventional Commits

Answer in {{language}}.

## 1. Review the changes

- `git status` and `git diff` (plus `git diff --staged` if files are already staged).
- `git log --oneline -10` to follow the repository's message style (language, scopes in use).
- If there is nothing to commit, say so and stop.

## 2. Pre-commit checks

Read the project's `CLAUDE.md` first: its rules take precedence (for example commands that are forbidden or need approval before running, such as a long evaluation). Run only quick checks.

- **Tests**: detect and run the project's fast suite, for example:
  - CMake: `cmake --build build` then `ctest --test-dir build --output-on-failure`
  - Node: `npm test` / `pnpm test` (depending on `package.json`)
  - Python: `pytest -q`; Rust: `cargo test`; Go: `go test ./...`; Swift: `swift test`
  - If no suite is found, say so.
- **Lint / format**: run the configured linter or formatter if there is one (for example `npm run lint`, `clang-format --dry-run`, `ruff check`), without rewriting files without approval.
- **Diff hygiene**:
  - No secrets (API keys, tokens, `.env`, passwords) and no large or generated files (`build/`, binaries, `node_modules`).
  - No leftover debug code (`console.log`, temporary `printf`, `TODO` added by mistake) and no conflict markers (`<<<<<<<`).
  - `git diff --check` for trailing whitespace.
- If the changes mix several independent topics, suggest splitting them into several commits.
- **Identity**: check `git config user.email`. If it is empty, do not commit: report it and ask for the address (Git would make one up from the machine name, which GitHub links to no account).

If a check fails, do not commit anyway: report it in the confirmation.

## 3. Write the message

[Conventional Commits](https://www.conventionalcommits.org) format:

```
<type>(<optional scope>): <imperative description, lowercase, no period, ≤ 72 chars>

<optional body: the why, not the how, lines ≤ 72 chars>

<optional footer: BREAKING CHANGE: ..., Refs: #123>
{{co_author_trailer}}
```

Types: `feat`, `fix`, `refactor`, `perf`, `test`, `docs`, `style`, `build`, `ci`, `chore`, `revert`. Add `!` after the type for a breaking change.
Follow the language and scopes already used in the repository history.

{{attribution_rule}}

## 4. Confirm with the user

Use the **AskUserQuestion** tool with a single question showing:
- the result of the tests and other checks (✅ / ❌ with the number of passing tests, and the error on failure);
- the files that will be committed;
- the full commit message.

Options:
- "Commit" (recommended if everything passes)
- "Edit the message"
- "Cancel"

If the tests fail, highlight the failure and do not mark "Commit" as recommended.

## 5. Commit

- Stage the relevant files explicitly (`git add <files>`); avoid a blind `git add -A`.
- `git commit` with the message passed through a heredoc to keep the formatting.
- Never use `--no-verify` or `--amend` without an explicit request. If a pre-commit hook fails, fix the issue and create a new commit.
- Show `git log --oneline -1` and the final `git status`. Do not push (that is the `push` skill's job).
