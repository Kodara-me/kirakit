# Copilot instructions

## Style

- Write code, comments, commit messages and documentation in neutral, professional English,
  unless the repository already uses another language.
- Match the surrounding code: naming, idioms, comment density and formatting.
- Keep changes small and focused on the request; do not refactor unrelated code.

## Commits and pull requests

- Commit messages and pull request titles follow Conventional Commits:
  `type(scope): description`, imperative, lowercase, no final period, at most 72 characters.
- The commit body explains why, not how.

## Quality

- Add or update tests with every behavior change.
- Tests never touch real credentials, connected devices or production services: use
  in-memory storage, temporary directories and fake servers.
- Never commit secrets (API keys, tokens, passwords, `.env` files) or generated files.
