---
name: test
description: Builds and runs the project's unit tests, then shows the results in a clear table (summary per suite, failure details). Use when the user asks to run or check the tests.
model: haiku
argument-hint: "[optional filter: suite or test name]"
---

# Unit tests with a results table

Answer in {{language}}.

## 1. Respect the project

Read the project's `CLAUDE.md`: its rules take precedence. Run only the fast unit tests, never a long evaluation or a benchmark without an explicit request.

## 2. Detect and run

Build first if the project needs it, then run with the most detailed output available (one result per test, not only per executable):

- **CMake / CTest**: `cmake --build build`, then `ctest --test-dir build -N` to list the executables. For a **Qt Test** executable, run it directly with `-o -,txt` (one `PASS` / `FAIL!` / `SKIP` line per function and a `Totals` line); otherwise `ctest --test-dir build --output-on-failure`.
- **Node**: `npm test` (or `pnpm` / `yarn` depending on the lockfile).
- **Python**: `pytest -q -rA`.
- **Rust**: `cargo test`; **Go**: `go test ./... -v`; **Swift**: `swift test`.

If a filter is given (`$ARGUMENTS`), run only the matching tests (e.g. a Qt Test function as argument, `pytest -k`, `ctest -R`).
If the build fails, show the error (file:line and message) and stop.

## 3. Show the results

Start with a verdict line: `✅ All tests pass` or `❌ N failing test(s)`.

Then a summary table, one row per suite or executable:

| Suite | ✅ Passed | ❌ Failed | ⏭️ Skipped | ⏱️ Duration |
|---|---:|---:|---:|---:|
| DomainTest | 123 | 0 | 0 | 23 ms |
| **Total** | **123** | **0** | **0** | **23 ms** |

If there are failures, a second table, one test per row:

| ❌ Test | File | Reason |
|---|---|---|
| `DomainTest::giveItem` | [DomainTest.cpp:1688](tests/DomainTest.cpp:1688) | `QCOMPARE`: got `1`, expected `0` |

Rules:
- Do not list passing tests, unless there are 15 or fewer, or the user asks for them.
- Skipped tests: name them in one line with their reason, if there are any.
- Failure reason in one short sentence (actual and expected values if available), without copying the full trace.
- End with one line on what to do next, only on failure (e.g. which test to look at first).

Change nothing: this skill runs and reports, it does not fix.
