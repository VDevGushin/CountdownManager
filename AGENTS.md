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

## Verification

- Run `swift run CoreChecks` after core changes.
- Keep all production JSON reads and writes inside `CountdownRepository`; never move them back onto `Store`'s main actor.
- When adding an asynchronous mutation, update the in-memory snapshot before awaiting persistence and preserve revision ordering.
- Build the macOS executable after UI or diagnostics changes.
- On the current development machine the newest Command Line Tools compiler may not match the default SDK. A verified fallback is `SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk` with module caches and the scratch build placed under `/private/tmp`.
- Do not replace the copy in `/Applications` until the build and core checks pass.
- After deployment, launch the installed copy and verify that the UI responds and `countdown.log` contains `app.launch` and `data.load success`.
