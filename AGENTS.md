# Countdown Manager: notes for future maintenance

This is a native macOS menu-bar app. Read `README.md` and `VERIFICATION.md` before changing behavior.

## Working agreement

The user is the product manager; the agent is the software engineer responsible for implementation.

- The user describes the desired outcome, priorities, and product constraints. Do not require the user to write code or translate goals into technical tasks.
- Own the technical work end to end: inspect the existing behavior, choose a proportionate design, implement it, add or update tests, update documentation, build, and verify the result.
- Make routine engineering decisions autonomously. Ask the user only when a product choice is genuinely ambiguous, an action needs new authority, or alternatives have materially different user-visible consequences.
- Preserve backward compatibility and existing countdown data unless the user explicitly approves a migration or reset.
- For bug reports, diagnose first and record evidence. Fix the cause rather than hiding the symptom.
- A change is not complete when it merely compiles. Run the relevant checks, exercise the affected UI when possible, and report what was actually verified.
- Do not publish, deploy, replace the installed app, or create releases unless the user's request includes that outcome.
- Keep communication in plain Russian unless the user asks otherwise. Lead with outcomes and product impact; keep implementation details available but compact.

For the longer workflow and definition of done, see `AI_WORKFLOW.md`.

## Preserve user data

- Production data is stored at `~/Library/Application Support/CountdownManager/countdowns.json`.
- Never delete, replace, or rewrite that file as part of a diagnostic check.
- Do not add countdown titles, notes, or emoji to diagnostics. They are user content.

## Diagnose a freeze before guessing

The app writes a rotating diagnostic journal to:

- `~/Library/Application Support/CountdownManager/Logs/countdown.log`
- `~/Library/Application Support/CountdownManager/Logs/countdown.previous.log`

Start with the last 200 lines. Look for the last UI breadcrumb, `ui.stall detected`, a missing matching `data.save success`, or a read/write failure. If the process is still stuck, capture a short `sample` of `CountdownManager` before terminating it. Unified macOS logs can then supply AppKit and system context around the same timestamp.

Keep diagnostic events short and structured. Any new action that can block the UI or mutate stored data should log its start and result.

## Mandatory pre-commit self-review

Every commit must pass a deliberate self-review before it is created.

- Inspect `git status` and the complete staged diff. Confirm that the commit contains only the intended change and no user data, secrets, build products, or unrelated edits.
- Review the staged code for correctness, edge cases, error handling, concurrency and persistence ordering, backward compatibility, privacy, accessibility, and the macOS 13+ deployment target where applicable.
- Run `git diff --cached --check` plus the relevant automated checks, build, and UI verification for the staged change.
- Fix every actionable finding, stage the correction, and repeat the review. Commit only when no actionable findings remain.
- Report what was reviewed and tested. Never describe a change as reviewed or verified when a relevant check was skipped; state any remaining verification gap explicitly.

## Tests, review, and push gate

- A completed behavior change must include or update unit tests for its logic and UI tests for its user-visible states and interactions where those can be automated reliably.
- Run the relevant unit and UI suites after implementation. Then perform the complete pre-commit self-review, fix its findings, and run the same suites again against the reviewed code.
- Do not commit or push while either test pass is failing. Do not weaken or delete a valid test merely to make the gate pass.
- A push is still an external publishing action and requires the user's request. When requested, push only reviewed commits whose post-review test pass is green.
- If platform tooling prevents a relevant UI interaction from being automated, add the closest deterministic UI smoke or state test, document the missing end-to-end check, and verify it manually when possible. Never label smoke coverage as full end-to-end coverage.
- Allow at most five complete fix-and-verify cycles for the same task. If the test/review gate is still not green after the fifth cycle, stop without committing or pushing and escalate to the product manager with the concrete blocker, evidence, and viable options.
- The product manager may explicitly authorize additional iterations. Stabilizing the test infrastructure to establish its first reliable green baseline may continue for as many iterations as needed, but must not weaken product behavior or remove valid assertions.

## Public release command

Treat the product manager's phrase “Собираем публичный релиз для пользователей” as explicit authorization to prepare and publish a GitHub Release. Unless a version is supplied, increment the patch version. Run the complete test/review gate, build and verify the app, package `Countdown Manager.app` as a ZIP archive, create the GitHub Release, attach the archive, and verify the published asset. This command does not authorize replacing the user's copy in `/Applications` unless that is requested separately.

## Verification

- Run `swift run CoreChecks` after core changes.
- Run `swift run UIChecks` after user-interface changes.
- Keep all production JSON reads and writes inside `CountdownRepository`; never move them back onto `Store`'s main actor.
- When adding an asynchronous mutation, update the in-memory snapshot before awaiting persistence and preserve revision ordering.
- Build the macOS executable after UI or diagnostics changes.
- On the current development machine the newest Command Line Tools compiler may not match the default SDK. A verified fallback is `SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk` with module caches and the scratch build placed under `/private/tmp`.
- Do not replace the copy in `/Applications` until the build and core checks pass.
- After deployment, launch the installed copy and verify that the UI responds and `countdown.log` contains `app.launch` and `data.load success`.
