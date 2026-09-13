# Countdown Manager — Verification

## Purpose

Verification should answer one question: does the changed behaviour work without breaking relevant existing behaviour?

Use the cheapest reliable surface that exercises the actual failure mode. Do not run every suite by default, and do not build custom automation for interactions that the driver cannot reproduce faithfully.

Product behaviour is defined by `docs/PRODUCT.md`. Tests are evidence, not product truth.

## Verification surfaces

Countdown Manager has four useful verification surfaces:

- `CoreChecks` — domain, validation and persistence behaviour;
- `UIChecks` — deterministic presentation and application-state behaviour;
- `Real UI Smoke` — the real SwiftUI/AppKit runtime in an isolated environment;
- `XCUITest` — external keyboard/button interaction when XCU can deliver the interaction without changing the contract under test.

These are not an escalation ladder. Pick the smallest relevant set.

## Commands

### Fast

```sh
./verify.sh fast
```

Runs `CoreChecks` and `UIChecks`.

Use for domain, persistence, deterministic presentation and application-state changes.

### Real UI

```sh
./verify.sh ui
```

Builds a release application bundle in a temporary isolated environment and runs the current Real UI Smoke scenarios.

Use when the real SwiftUI/AppKit runtime matters: view construction, hosting/root identity, editor lifecycle, scroll/draft continuity, focus/responder behaviour that can be reproduced in-process, or main-thread stalls.

### Combined

```sh
./verify.sh full
```

Runs `fast` followed by `ui`.

Use only when both deterministic checks and the real runtime are relevant.

### XCUITest

```sh
./run-xcui-tests.sh
```

Runs the external macOS UI suite through Xcode in isolated test data.

Prefer targeted XCU tests while developing. Run the whole suite when the change has broad external-interaction risk or before a release checkpoint.

## What each surface proves

### CoreChecks

Use for behaviour that can be proven without the application UI, including validation, date calculations, expiry, ordering, JSON compatibility, repository behaviour and persistence revision handling.

CoreChecks do not prove SwiftUI rendering, AppKit lifecycle, focus, accessibility interaction or window behaviour.

### UIChecks

Use for deterministic presentation/state logic such as menu-bar formatting, editor validity, draft behaviour, grouping, disclosure state and persistence coordination.

UIChecks do not prove real AppKit event routing or system interaction.

### Real UI Smoke

Real UI Smoke launches the actual application runtime with isolated data. It is useful for regressions that need the real window/view hierarchy.

It can prove things such as retained panel/hosting/root identity, session continuity through supported in-process panel hide/show paths, editor/draft continuity, rendered control state and runtime responsiveness.

It does not prove that macOS delivered an external app-switch, Space change or status-item activation exactly as a user would perform it. Test-mode lifecycle suppression or direct internal actions must not be described as proof of production system behaviour.

Configuration and property assertions are supporting evidence only. For example, setting `moveToActiveSpace`, registering a Space callback, or calculating an anchored panel frame does not by itself prove the corresponding user-visible behaviour.

### XCUITest

Use XCUITest when the interaction itself is part of the contract and XCU can perform that interaction faithfully.

Current reliable examples include keyboard entry, normal application buttons and Command-W after the application is active.

Do not add Finder anchoring, coordinate-click workarounds, repeated timing loops or custom XCU driver machinery to simulate status-item activation, application switching or Spaces when the automation changes the lifecycle under test or cannot reliably deliver the action.

A flaky or lifecycle-altering driver is diagnostic noise, not a release gate.

## System-level macOS behaviour

Some shell behaviour is currently best accepted manually because the available automation cannot reproduce it without affecting the result.

When a change touches these contracts, manually verify only the relevant scenarios:

1. status-item click opens an arrowless panel directly below the status item from a fresh launch;
2. hiding and reopening preserves the same in-memory session when that is the product contract;
3. rapid repeated status-item clicks produce one immediate visibility toggle per distinct click;
4. switching to another application hides the panel;
5. switching Spaces hides the old panel without losing the current editor/draft, and returning does not show it again, including an immediate return during a rapid transition;
6. clicking the status item from another Space keeps the user on that Space and opens the panel below that Space's status item;
7. the panel has no arrow, title bar or traffic-light controls and cannot be dragged as a standalone window.

Do not require this checklist for unrelated changes.

Manual acceptance should be short and tied to the changed behaviour. If a future automation driver can faithfully reproduce one of these interactions, replace that manual step with the reliable automated check.

## Test isolation

Never mutate production Countdown Manager data during tests.

Real UI Smoke and XCUITest must use explicit isolated data/defaults/log locations. If safe isolation cannot be established, do not run a mutating verification path.

## Bundle provenance

Runtime evidence only applies to the bundle that was actually built and exercised.

`./verify.sh ui` builds from the current source tree before running smoke checks. `./run-xcui-tests.sh` builds through the current Xcode project using temporary DerivedData.

Do not treat an old `.app` as evidence for current source unless its provenance is known.

## Choosing verification

Use this rule of thumb:

- domain or persistence change → `./verify.sh fast`;
- deterministic UI/state change → `./verify.sh fast`;
- real SwiftUI/AppKit runtime change → `./verify.sh ui` or `./verify.sh full` when fast coverage is also relevant;
- external keyboard/button interaction → targeted XCUITest;
- app-switch, Spaces or status-item lifecycle → manual acceptance until a reliable external driver exists.

Add lower-level regression coverage when it protects a real failure mode. Do not duplicate the same assertion across every layer merely to make verification look stronger.

## Failures

A failing check can come from product code, stale tests, the test driver, platform behaviour or the environment.

Classify the failure before changing production code to satisfy it.

If a verification tool is unreliable, downgrade or remove that tool rather than making product code accommodate the test harness.

## Reporting

Report only material facts:

- what changed;
- which relevant checks ran and whether they passed;
- what behaviour remains unverified;
- any real blocker or remaining risk.

No fixed readiness template or mandatory escalation sequence is required.
