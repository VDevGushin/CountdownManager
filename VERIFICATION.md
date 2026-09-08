# Countdown Manager — Verification Strategy

## Purpose

This document is the operational map of the project's current verification layers and commands.

Canonical test philosophy, cost policy, user-data safety and checkpoint communication live in `COUNTDOWN_MANAGER.md` sections 11, 12, 16 and 20.

## Current verification layers

Verification level describes the evidence, not the test target or command name. A higher level is required only when a lower level cannot faithfully exercise the user contract.

| Level | What it proves | Current mechanisms |
| --- | --- | --- |
| A. Internal verification | Unit and regression behaviour through internal APIs, smoke controls, test hooks or programmatic lifecycle calls | CoreChecks, UIChecks and internal paths in Real UI Smoke |
| B. Platform integration verification | Behaviour of the real SwiftUI/AppKit runtime, including application activation, responder, window, popover and sheet lifecycle | Real UI Smoke and targeted integration experiments |
| C. Installed black-box acceptance | A current real application bundle responds correctly to real user interactions without replacing the action under test with a hook | XCUITest or another worker-operated external interaction driver |

Level C is not a universal UI-automation gate. CoreChecks/UIChecks remain sufficient for model, data and pure-logic changes when their correctness does not depend on external platform interaction.

## Installed black-box trigger

Installed black-box acceptance is required for a user-visible defect or feature whose correctness depends on AppKit event routing, outside click, activation/deactivation, key-window state, first responder/focus, `NSPopover`, `NSMenu`, sheet/window relationships, drag/drop, keyboard or mouse routing, system lifecycle behaviour, or any other case where an internal call is not equivalent to the user action.

Classify the contract by the interaction that can fail, not by the implementation method. For example:

- `outside click closes popup` must exercise a real outside click; calling `closePopover()` is internal regression evidence, not acceptance;
- `status item click opens popup` must exercise the status item; calling `showPopover()` alone is not black-box acceptance.

Internal hooks remain valid for focused regression tests, but cannot replace the external interaction that is the subject of the defect.

## Bundle provenance

Before installed black-box acceptance, the worker must record evidence that the tested `.app` was built from the current source state. Evidence must identify the source state, build/install step and exact bundle path used by acceptance; a stale or different bundle invalidates the result.

When the owner workflow or runbook uses `/Applications/Countdown Manager.app`, user-facing acceptance must run against a current installed copy there. Acceptance against only a temporary bundle under `/private/tmp` does not prove that installed workflow. Installing or replacing the `/Applications` copy still requires the explicit permission defined in `COUNTDOWN_MANAGER.md`; without that permission or another required environment capability, report the missing evidence as a blocker rather than treating temporary-bundle evidence as equivalent.

## Completion and READY contract

For a change that triggers installed black-box acceptance, the completion report must contain:

```text
IMPLEMENTATION: pass
INTERNAL REGRESSION: pass
INSTALLED BLACK-BOX ACCEPTANCE: pass
INDEPENDENT REVIEW: pass
READY: yes
```

Platform Integration (Level B) may be additional required evidence when the change risk calls for it, but it never satisfies or replaces Level C after the installed black-box trigger has fired.

`READY: yes` is allowed only when all four results are `pass`. Any required result that is `fail`, `unknown`, `not run` or `unavailable` means `READY: no`.

Product Owner manual testing is not part of the normal Definition of Done. The worker and independent reviewer must obtain the required evidence with the available harness/environment. If they cannot, finish with `READY: no` and `BLOCKED: <the exact evidence that could not be obtained>`. Owner acceptance may be additional, but the task must not conclude with “tests pass; now the owner must verify manually” as the route to readiness.

Independent review starts after implementation changes are complete, as required by the existing workflow. It is a distinct gate: the reviewer evaluates both implementation correctness and whether the evidence faithfully tests the real user contract. The concrete review procedure is in `.agents/skills/project-review/SKILL.md`.

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
| Popup, focus, responder, teardown or SwiftUI/AppKit lifecycle without an external-interaction contract | relevant lower-level checks + platform integration evidence |
| User-visible lifecycle or routing contract listed in the installed black-box trigger | relevant lower-level checks + installed black-box acceptance |
| Visual judgement that is not a lifecycle/interaction correctness gate | targeted observation; optional owner acceptance |

This table is operational guidance, not a second test policy.

## Current automation boundary

The current XCUITest baseline can exercise the app's accessible status item and normal application UI interactions.

A truly arbitrary click in another application/window may remain outside current automation unless available macOS UI automation exposes a reliable external surface for that scenario. When that click is required acceptance evidence, inability of the worker environment to perform it is a blocker; it is not a deferred owner QA gate.

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
