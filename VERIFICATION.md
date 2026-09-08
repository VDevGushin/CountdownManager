# Countdown Manager — Verification Strategy

## Purpose

Verification exists to provide justified confidence with the lowest reasonable complexity, runtime and maintenance cost.

Test count and coverage percentage are not goals.

Canonical test philosophy is defined in `COUNTDOWN_MANAGER.md`.

## Verification layers

| Layer | Purpose |
| --- | --- |
| CoreChecks | Domain model, validation, calendar rules, persistence contracts and deterministic core behaviour |
| UIChecks | Presentation/state behaviour without launching the real AppKit UI |
| Real UI Smoke | Real SwiftUI/AppKit popup, lifecycle, focus, geometry and regressions that require actual UI infrastructure |
| XCUITest | External user interactions that must be verified through macOS accessibility/UI automation |
| Manual verification | Visual quality or platform interactions that cannot be reliably automated |

## Commands

### Fast

```sh
./verify.sh fast
```

Runs:

- CoreChecks
- UIChecks

Use for changes whose contracts are reliably covered below the real UI layer.

### Real UI

```sh
./verify.sh ui
```

Builds an isolated signed application and runs the current Real UI Smoke suite.

Use when a change affects real SwiftUI/AppKit behaviour such as popup lifecycle, responder/focus behaviour or other platform-sensitive UI interactions.

### Combined

```sh
./verify.sh full
```

Runs the fast and Real UI gates.

`full` does not automatically include XCUITest.

### XCUITest

```sh
./run-xcui-tests.sh
```

Runs the external macOS XCUITest suite through `xcodebuild`.

Use when the risk requires verification of actual user-level clicks, input, sheets, status-item behaviour or accessibility-driven interaction.

Do not run XCUITest automatically for unrelated changes.

## Selecting verification

Protect a contract at the cheapest reliable level.

Prefer:

1. Core/unit/state verification;
2. UI state verification;
3. Real UI Smoke;
4. XCUITest;
5. manual verification.

Do not duplicate the same contract across layers automatically.

Multiple layers are justified only when they detect materially different classes of failure.

A regression should normally be protected at the lowest layer capable of reproducing the relevant failure.

Platform lifecycle regressions may legitimately require Real UI Smoke or XCUITest.

## User-data isolation

Automated verification must not mutate production user data.

Production data lives at:

`~/Library/Application Support/CountdownManager/countdowns.json`

UI and XCUITest environments must use isolated temporary profiles.

Never weaken isolation for convenience.

## Verification scope

Do not run the largest available suite simply because implementation occurred.

Choose checks from the risk introduced by the change.

Examples:

- pure domain change → CoreChecks and relevant focused checks;
- presentation/state change → CoreChecks/UIChecks as relevant;
- popup/focus/AppKit lifecycle → relevant lower-level checks plus Real UI Smoke;
- external macOS interaction → XCUITest when it provides additional confidence;
- visual judgement → targeted manual acceptance.

## Failures

A failed check is evidence.

Investigate whether it indicates:

- product regression;
- test defect;
- obsolete assertion;
- flaky infrastructure;
- unsupported environment.

Do not weaken a valid product contract merely to make a suite green.

Do not preserve an obsolete or redundant test merely because it already exists.

## Reporting

At checkpoint report:

STATUS: READY / NOT READY / NEEDS OWNER DECISION

Verified:

- what was actually checked.

Not verified:

- relevant checks intentionally or practically not performed.

Known risks:

- remaining uncertainty.

Do not claim a broader level of verification than was actually performed.

## History

This document describes the current verification strategy.

Historical verification runs and completed investigations belong in Git history or temporary investigation plans, not in this permanent policy document.
