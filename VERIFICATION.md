# Countdown Manager — Verification Strategy

## Purpose

This document is the operational map of the project's current verification layers and commands.

Canonical test philosophy, cost policy, user-data safety and checkpoint communication live in `COUNTDOWN_MANAGER.md` sections 11, 12, 16 and 20.

## Current verification layers

| Layer | What it currently proves |
| --- | --- |
| CoreChecks | Domain model, validation, calendar rules, persistence contracts, JSON compatibility and deterministic core behaviour |
| UIChecks | Presentation/state behaviour without launching the real AppKit UI |
| Real UI Smoke | Real SwiftUI/AppKit popup behaviour, lifecycle, focus, geometry and regression paths that require actual UI infrastructure |
| XCUITest | External user interactions through macOS accessibility/UI automation, including real clicks, input, sheets and status-item behaviour |
| Manual verification | Visual quality or platform interactions that available automation cannot reliably exercise |

## Commands

### Fast gate

```sh
./verify.sh fast
```

Runs:

- CoreChecks
- UIChecks

### Real UI gate

```sh
./verify.sh ui
```

Builds an isolated ad-hoc signed application and runs the current Real UI Smoke suite.

The runner uses a temporary verification root under `/private/tmp` and an explicit UI-smoke environment marker.

### Combined gate

```sh
./verify.sh full
```

Runs the fast gate and Real UI gate.

`full` does not include XCUITest.

### XCUITest

```sh
./run-xcui-tests.sh
```

Runs the macOS XCUITest suite through `xcodebuild` with temporary DerivedData.

The XCUITest environment uses isolated test data/profile plumbing implemented by the test target; production countdown data must not be used as its fixture.

## Operational selection map

The final verification scope is chosen from the risk of the change under `COUNTDOWN_MANAGER.md`.

Typical starting points:

| Change / risk | Typical verification |
| --- | --- |
| Pure domain or persistence logic | relevant CoreChecks |
| Presentation/state behaviour | relevant CoreChecks / UIChecks |
| Popup, focus, responder, teardown or SwiftUI/AppKit lifecycle | relevant lower-level checks + Real UI Smoke |
| Real external click/input/sheet/status-item interaction | XCUITest when it adds evidence not available below |
| Visual judgement or automation boundary | targeted manual acceptance |

This table is operational guidance, not a second test policy.

## Current automation boundary

The current XCUITest baseline can exercise the app's accessible status item and normal application UI interactions.

A truly arbitrary click in another application/window remains manual-only unless available macOS UI automation exposes a reliable external surface for that scenario.

Do not build a production workaround only to make that automation gap disappear.

## Test isolation

Production-data rules are canonical in `COUNTDOWN_MANAGER.md`.

Operationally:

- Real UI Smoke must run only with its isolated temporary test home and marker;
- XCUITest must run with isolated fixture storage;
- production `~/Library/Application Support/CountdownManager/countdowns.json` must not be a mutation-test fixture;
- a verification run that cannot prove isolation must not mutate data.

## Environment notes

The current `verify.sh` can use the known Command Line Tools SDK fallback when it is present:

`/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk`

Build scratch space and module caches are placed under the temporary verification root.

The standalone XCUITest runner requires a working `xcodebuild` environment and the `CountdownManager.xcodeproj` test scheme.

## Failures and gaps

A failing or unavailable check is evidence about either the product, the test or the environment; classify it before changing production code or test assertions.

Test review categories and removal/merging rules are defined in `COUNTDOWN_MANAGER.md` and the `project-review` skill.

For checkpoint reporting, use the canonical format in `COUNTDOWN_MANAGER.md` section 20 and state exactly what was and was not verified.

## History

This file describes the current verification system.

Completed run logs, old assertion counts and one-off investigation detail belong in Git history or temporary investigation plans. Durable technical conclusions belong in `docs/decisions/`.
